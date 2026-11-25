// ignore_for_file: implementation_imports

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:galley/src/features/container/data/zip/crc32.dart';

/// Hora DOS fixa (00:00:00) gravada em todas as entradas.
const int _dosTime = 0;

/// Data DOS fixa (1980-01-01) gravada em todas as entradas.
const int _dosDate = 0x21;

/// Nível fixo do zlib: a saída do deflate precisa ser reproduzível.
const int _zlibLevel = 6;

/// Limite do zip clássico (sem zip64).
const int _zip32Max = 0xFFFFFFFF;

class _Record {
  _Record(
    this.name,
    this.method,
    this.crc,
    this.compressed,
    this.size,
    this.offset,
  );

  final List<int> name;
  final int method;
  final int crc;
  final int compressed;
  final int size;
  final int offset;
}

/// Escritor de zip determinístico e em streaming.
///
/// Cada entrada é entregue ao [_out] assim que fica pronta; nada é guardado
/// além do diretório central. Timestamps (1980-01-01 00:00), nível de
/// compressão e ordem das entradas são fixos, então a mesma sequência de
/// chamadas gera sempre os mesmos bytes. Sem zip64: arquivos e entradas
/// precisam caber em 4 GiB.
final class ZipWriter {
  /// Cria um escritor que entrega os bytes a [out], na ordem.
  ZipWriter(this._out);

  final void Function(Uint8List bytes) _out;
  final List<_Record> _records = [];
  int _offset = 0;

  /// Total de bytes entregues até agora.
  int get offset => _offset;

  /// Tamanho do diretório central (com o EOCD) para entradas com os
  /// [names] dados, mais as já gravadas.
  int centralDirectorySize(Iterable<String> names) {
    var total = 22;
    for (final r in _records) {
      total += 46 + r.name.length;
    }
    for (final n in names) {
      total += 46 + utf8.encode(n).length;
    }
    return total;
  }

  /// Tamanho do cabeçalho local de uma entrada chamada [name].
  static int localHeaderSize(String name) => 30 + utf8.encode(name).length;

  /// Adiciona [data] inteira; com [deflate] falso a entrada é *stored*.
  void addBytes(String name, List<int> data, {bool deflate = true}) {
    final raw = data is Uint8List ? data : Uint8List.fromList(data);
    final body = deflate
        ? Uint8List.fromList(
            ZLibEncoder(raw: true, level: _zlibLevel).convert(raw),
          )
        : raw;
    _write(name, deflate ? 8 : 0, crc32(raw), body.length, raw.length, [body]);
  }

  /// Adiciona uma entrada *stored* de [size] bytes produzida por [chunks].
  ///
  /// [chunks] é chamada duas vezes (a primeira só para o CRC, que o
  /// cabeçalho local precisa conhecer) e deve devolver sempre os mesmos
  /// bytes, somando exatamente [size]. Os trechos podem reaproveitar o mesmo
  /// buffer; ele é consumido antes do próximo.
  void addStoredStream(
    String name,
    int size,
    Iterable<Uint8List> Function() chunks,
  ) {
    var crc = 0;
    var seen = 0;
    for (final c in chunks()) {
      crc = crc32(c, crc);
      seen += c.length;
    }
    if (seen != size) {
      throw StateError('Fluxo de "$name" tem $seen bytes; esperado $size.');
    }
    _write(name, 0, crc, size, size, chunks());
  }

  void _write(
    String name,
    int method,
    int crc,
    int compressed,
    int size,
    Iterable<Uint8List> body,
  ) {
    if (compressed > _zip32Max || size > _zip32Max || _offset > _zip32Max) {
      throw StateError('Entrada "$name" excede o limite do zip sem zip64.');
    }
    final nameBytes = utf8.encode(name);
    final record = _Record(nameBytes, method, crc, compressed, size, _offset);
    _records.add(record);
    final h = _Bytes()
      ..u32(0x04034b50)
      ..u16(20)
      ..u16(0x800)
      ..u16(method)
      ..u16(_dosTime)
      ..u16(_dosDate)
      ..u32(crc)
      ..u32(compressed)
      ..u32(size)
      ..u16(nameBytes.length)
      ..u16(0)
      ..raw(nameBytes);
    _emit(h.take());
    body.forEach(_emit);
  }

  void _emit(Uint8List bytes) {
    _out(bytes);
    _offset += bytes.length;
  }

  /// Grava o diretório central e o fim do arquivo. Não use o escritor depois.
  void finish() {
    final cdOffset = _offset;
    for (final r in _records) {
      final w = _Bytes()
        ..u32(0x02014b50)
        ..u16(20)
        ..u16(20)
        ..u16(0x800)
        ..u16(r.method)
        ..u16(_dosTime)
        ..u16(_dosDate)
        ..u32(r.crc)
        ..u32(r.compressed)
        ..u32(r.size)
        ..u16(r.name.length)
        ..u16(0)
        ..u16(0)
        ..u16(0)
        ..u16(0)
        ..u32(0)
        ..u32(r.offset)
        ..raw(r.name);
      _emit(w.take());
    }
    final cdSize = _offset - cdOffset;
    if (_records.length > 0xFFFF || _offset > _zip32Max) {
      throw StateError('Arquivo excede o limite do zip sem zip64.');
    }
    _emit(
      (_Bytes()
            ..u32(0x06054b50)
            ..u16(0)
            ..u16(0)
            ..u16(_records.length)
            ..u16(_records.length)
            ..u32(cdSize)
            ..u32(cdOffset)
            ..u16(0))
          .take(),
    );
  }
}

class _Bytes {
  final BytesBuilder _b = BytesBuilder(copy: false);

  void u16(int v) => _b.add([v & 0xFF, (v >> 8) & 0xFF]);

  void u32(int v) =>
      _b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);

  void raw(List<int> v) => _b.add(v);

  Uint8List take() => _b.takeBytes();
}

/// Escreve os bytes do zip em um [RandomAccessFile] de forma síncrona (a
/// memória fica limitada ao trecho corrente).
void Function(Uint8List) fileSink(RandomAccessFile file) =>
    (bytes) => file.writeFromSync(bytes);

/// Escapa [s] para uso em texto e atributos XML.
String xmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// `META-INF/container.xml` apontando para [opfPath].
String containerXml(String opfPath) =>
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<container version="1.0" '
    'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">\n'
    '  <rootfiles>\n'
    '    <rootfile full-path="${xmlEscape(opfPath)}" '
    'media-type="application/oebps-package+xml"/>\n'
    '  </rootfiles>\n'
    '</container>\n';

/// Item do manifest para [buildOpf].
final class OpfItem {
  /// Cria um item com [id], [href] relativo ao OPF e [mediaType].
  const OpfItem(this.id, this.href, this.mediaType, {this.properties});

  /// Identificador do item.
  final String id;

  /// Caminho relativo ao OPF.
  final String href;

  /// Tipo de mídia.
  final String mediaType;

  /// Valor do atributo `properties`, se houver.
  final String? properties;
}

/// Gera um OPF. [spineIds] lista os `idref` na ordem de leitura; [ncxId], se
/// dado, vira o atributo `toc` do spine (EPUB 2). Com [version] `3.0` inclui
/// `dcterms:modified` fixo.
String buildOpf({
  required String version,
  required String title,
  required String identifier,
  required String language,
  required List<OpfItem> items,
  required List<String> spineIds,
  bool rtl = false,
  String? ncxId,
  String extraMetadata = '',
}) {
  final b = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln(
      '<package xmlns="http://www.idpf.org/2007/opf" '
      'xmlns:dc="http://purl.org/dc/elements/1.1/" version="$version" '
      'unique-identifier="bookid">',
    )
    ..writeln('  <metadata>')
    ..writeln('    <dc:title>${xmlEscape(title)}</dc:title>')
    ..writeln(
      '    <dc:identifier id="bookid">${xmlEscape(identifier)}</dc:identifier>',
    )
    ..writeln('    <dc:language>$language</dc:language>');
  if (version.startsWith('3')) {
    b.writeln(
      '    <meta property="dcterms:modified">2024-01-01T00:00:00Z</meta>',
    );
  }
  if (extraMetadata.isNotEmpty) b.writeln(extraMetadata);
  b
    ..writeln('  </metadata>')
    ..writeln('  <manifest>');
  for (final i in items) {
    final props = i.properties == null ? '' : ' properties="${i.properties}"';
    b.writeln(
      '    <item id="${i.id}" href="${xmlEscape(i.href)}" '
      'media-type="${i.mediaType}"$props/>',
    );
  }
  b.writeln('  </manifest>');
  final attrs = [
    if (ncxId != null) 'toc="$ncxId"',
    if (rtl) 'page-progression-direction="rtl"',
  ].join(' ');
  b.writeln('  <spine${attrs.isEmpty ? '' : ' $attrs'}>');
  for (final id in spineIds) {
    b.writeln('    <itemref idref="$id"/>');
  }
  b
    ..writeln('  </spine>')
    ..writeln('</package>');
  return b.toString();
}

/// Documento de navegação EPUB 3 com um item por par `(href, título)`.
String buildNavXhtml({
  required String language,
  required String title,
  required List<(String href, String title)> entries,
}) {
  final b = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<!DOCTYPE html>')
    ..writeln(
      '<html xmlns="http://www.w3.org/1999/xhtml" '
      'xmlns:epub="http://www.idpf.org/2007/ops" lang="$language" '
      'xml:lang="$language">',
    )
    ..writeln('<head><meta charset="utf-8"/>')
    ..writeln('<title>${xmlEscape(title)}</title></head>')
    ..writeln('<body>')
    ..writeln('<nav epub:type="toc" id="toc"><ol>');
  for (final (href, t) in entries) {
    b.writeln('<li><a href="${xmlEscape(href)}">${xmlEscape(t)}</a></li>');
  }
  b
    ..writeln('</ol></nav>')
    ..writeln('</body>')
    ..writeln('</html>');
  return b.toString();
}

/// NCX (EPUB 2) com um `navPoint` por par `(href, título)`.
String buildNcx({
  required String identifier,
  required String title,
  required List<(String href, String title)> entries,
}) {
  final b = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln(
      '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">',
    )
    ..writeln('<head><meta name="dtb:uid" content="${xmlEscape(identifier)}"/>')
    ..writeln('</head>')
    ..writeln('<docTitle><text>${xmlEscape(title)}</text></docTitle>')
    ..writeln('<navMap>');
  var n = 1;
  for (final (href, t) in entries) {
    b
      ..writeln('<navPoint id="np$n" playOrder="$n">')
      ..writeln('<navLabel><text>${xmlEscape(t)}</text></navLabel>')
      ..writeln('<content src="${xmlEscape(href)}"/>')
      ..writeln('</navPoint>');
    n++;
  }
  b
    ..writeln('</navMap>')
    ..writeln('</ncx>');
  return b.toString();
}
