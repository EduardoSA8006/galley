// ignore_for_file: implementation_imports

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:galley/src/features/container/data/fonts/font_deobfuscator.dart';
import 'package:galley/src/features/container/data/zip/crc32.dart';

import 'epub_writer.dart';

/// Especificação de um livro escrito à mão (o conteúdo vive em
/// `corpus/handmade/<id>/`; aqui ficam só os metadados e as variações).
final class _Spec {
  const _Spec(
    this.title,
    this.language, {
    this.rtl = false,
    this.epub2 = false,
    this.noMimetype = false,
    this.lowercaseXhtml = false,
    this.obfuscation,
    this.identifier = 'urn:uuid:6c1f0a52-3d4e-4b8a-9f27-0a1b2c3d4e5f',
    this.extraFiles = const {},
  });

  final String title;
  final String language;
  final bool rtl;
  final bool epub2;
  final bool noMimetype;

  /// Grava os capítulos no zip com o nome em minúsculas (o manifest mantém a
  /// caixa original): provoca `resource.caseMismatch`.
  final bool lowercaseXhtml;

  /// Algoritmo de ofuscação aplicado à fonte embutida, se houver.
  final String? obfuscation;
  final String identifier;

  /// Arquivos gerados em código (caminho relativo ao livro → bytes).
  final Map<String, Uint8List> extraFiles;
}

/// Identificador do livro com fonte IDPF (qualquer texto serve de chave).
const String _idpfIdentifier = 'galley-hm-fonts-idpf-0001';

final Map<String, _Spec> _specs = {
  'typography': const _Spec('Tipografia', 'pt-BR'),
  'publisher-css': const _Spec('Publisher CSS', 'en'),
  'tables': const _Spec('Tables', 'en'),
  'notes': const _Spec('Notas', 'pt-BR'),
  'images': _Spec('Imagens', 'pt-BR', extraFiles: {'pixel.png': _checkerPng()}),
  'cjk': const _Spec('日本語の本', 'ja'),
  'rtl-bidi': const _Spec('كتاب ودفتر', 'ar', rtl: true),
  'fonts-idpf': _Spec(
    'Fonts IDPF',
    'en',
    obfuscation: idpfObfuscation,
    identifier: _idpfIdentifier,
    extraFiles: {'fonts/demo.otf': _fakeFont()},
  ),
  'fonts-adobe': _Spec(
    'Fonts Adobe',
    'en',
    obfuscation: adobeObfuscation,
    extraFiles: {'fonts/demo.otf': _fakeFont()},
  ),
  'epub2-ncx': const _Spec('EPUB 2', 'pt-BR', epub2: true),
  'malformed-no-mimetype': const _Spec('Sem mimetype', 'en', noMimetype: true),
  'malformed-case-mismatch': const _Spec(
    'Caixa divergente',
    'en',
    lowercaseXhtml: true,
  ),
};

/// Gera todos os livros do corpus escrito à mão: id (`hm/...`) → bytes do
/// EPUB.
///
/// A saída é determinística: mesmos arquivos de origem, mesmos bytes
/// (timestamps do zip fixos em 1980-01-01, ordem e compressão fixas).
/// [corpusRoot] é o diretório `corpus/handmade`; por omissão é localizado a
/// partir deste pacote.
Future<Map<String, Uint8List>> buildHandmadeCorpus({String? corpusRoot}) async {
  final root = Directory(corpusRoot ?? await _defaultCorpusRoot());
  if (!root.existsSync()) {
    throw StateError('Diretório do corpus não encontrado: ${root.path}');
  }
  final out = <String, Uint8List>{};
  for (final entry in _specs.entries) {
    out['hm/${entry.key}'] = _buildBook(
      Directory('${root.path}/${entry.key}'),
      entry.value,
    );
  }
  return out;
}

/// Localiza `corpus/handmade` na raiz do repositório a partir do pacote.
Future<String> _defaultCorpusRoot() async {
  final here = await Isolate.resolvePackageUri(
    Uri.parse('package:galley_benchmark/src/corpus/handmade.dart'),
  );
  if (here != null && here.scheme == 'file') {
    // benchmark/lib/src/corpus/handmade.dart -> raiz do repositório.
    final dir = Directory.fromUri(here.resolve('../../../../corpus/handmade'));
    if (dir.existsSync()) return dir.path;
  }
  var dir = Directory.current.absolute;
  while (true) {
    final candidate = Directory('${dir.path}/corpus/handmade');
    if (candidate.existsSync()) return candidate.path;
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError(
        'corpus/handmade não encontrado a partir de '
        '${Directory.current.path}',
      );
    }
    dir = parent;
  }
}

Uint8List _buildBook(Directory dir, _Spec spec) {
  if (!dir.existsSync()) {
    throw StateError('Livro sem diretório de origem: ${dir.path}');
  }
  // Caminho relativo (com "/") -> bytes, ordenado.
  final files = <String, Uint8List>{};
  for (final f in dir.listSync(recursive: true).whereType<File>()) {
    final rel = f.path
        .substring(dir.path.length + 1)
        .replaceAll(Platform.pathSeparator, '/');
    files[rel] = f.readAsBytesSync();
  }
  files.addAll(spec.extraFiles);
  final names = files.keys.toList()..sort();

  final items = <OpfItem>[];
  final spine = <String>[];
  final nav = <(String, String)>[];
  for (var i = 0; i < names.length; i++) {
    final rel = names[i];
    final type = _mediaType(rel);
    final id = 'item$i';
    items.add(OpfItem(id, rel, type));
    if (type == 'application/xhtml+xml') {
      spine.add(id);
      nav.add((rel, _titleOf(utf8.decode(files[rel]!), rel)));
    }
  }

  final bookTitle = spec.title;
  final String opf;
  final String navPath;
  final String navDoc;
  if (spec.epub2) {
    navPath = 'toc.ncx';
    navDoc = buildNcx(
      identifier: spec.identifier,
      title: bookTitle,
      entries: nav,
    );
    items.add(const OpfItem('ncx', 'toc.ncx', 'application/x-dtbncx+xml'));
    opf = buildOpf(
      version: '2.0',
      title: bookTitle,
      identifier: spec.identifier,
      language: spec.language,
      items: items,
      spineIds: spine,
      ncxId: 'ncx',
    );
  } else {
    navPath = 'nav.xhtml';
    navDoc = buildNavXhtml(
      language: spec.language,
      title: bookTitle,
      entries: nav,
    );
    items.add(
      const OpfItem(
        'nav',
        'nav.xhtml',
        'application/xhtml+xml',
        properties: 'nav',
      ),
    );
    opf = buildOpf(
      version: '3.0',
      title: bookTitle,
      identifier: spec.identifier,
      language: spec.language,
      items: items,
      spineIds: spine,
      rtl: spec.rtl,
    );
  }

  final bytes = BytesBuilder(copy: false);
  final zip = ZipWriter(bytes.add);
  if (!spec.noMimetype) {
    zip.addBytes(
      'mimetype',
      ascii.encode('application/epub+zip'),
      deflate: false,
    );
  }
  zip.addBytes(
    'META-INF/container.xml',
    utf8.encode(containerXml('OEBPS/content.opf')),
  );
  if (spec.obfuscation != null) {
    zip.addBytes(
      'META-INF/encryption.xml',
      utf8.encode(_encryptionXml(spec.obfuscation!, 'OEBPS/fonts/demo.otf')),
    );
  }
  zip.addBytes('OEBPS/content.opf', utf8.encode(opf));
  zip.addBytes('OEBPS/$navPath', utf8.encode(navDoc));
  for (final rel in names) {
    var data = files[rel]!;
    var zipName = 'OEBPS/$rel';
    if (spec.lowercaseXhtml && rel.endsWith('.xhtml')) {
      zipName = zipName.toLowerCase();
    }
    if (rel == 'fonts/demo.otf' && spec.obfuscation == idpfObfuscation) {
      data = deobfuscateIdpf(data, spec.identifier);
    } else if (rel == 'fonts/demo.otf' &&
        spec.obfuscation == adobeObfuscation) {
      data = deobfuscateAdobe(data, spec.identifier);
    }
    zip.addBytes(zipName, data);
  }
  zip.finish();
  return bytes.takeBytes();
}

String _encryptionXml(String algorithm, String uri) =>
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container" '
    'xmlns:enc="http://www.w3.org/2001/04/xmlenc#">\n'
    '  <enc:EncryptedData>\n'
    '    <enc:EncryptionMethod Algorithm="$algorithm"/>\n'
    '    <enc:CipherData><enc:CipherReference URI="$uri"/></enc:CipherData>\n'
    '  </enc:EncryptedData>\n'
    '</encryption>\n';

String _mediaType(String path) {
  final ext = path.substring(path.lastIndexOf('.') + 1).toLowerCase();
  return switch (ext) {
    'xhtml' => 'application/xhtml+xml',
    'css' => 'text/css',
    'svg' => 'image/svg+xml',
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'otf' => 'font/otf',
    'ttf' => 'font/ttf',
    _ => throw StateError('Tipo de mídia desconhecido: $path'),
  };
}

final RegExp _titleRe = RegExp(r'<title>([^<]*)</title>');

/// Título (`<title>`) de um capítulo XHTML, para o sumário.
String _titleOf(String xhtml, String fallback) =>
    _titleRe.firstMatch(xhtml)?.group(1) ?? fallback;

/// Bytes de aparência de OpenType (`OTTO` + tabelas fictícias), com conteúdo
/// pseudoaleatório fixo. Nada o renderiza; só precisa sobreviver à
/// ofuscação e desofuscação.
Uint8List _fakeFont() {
  final data = Uint8List(4096);
  var s = 0x9E3779B9;
  for (var i = 0; i < data.length; i++) {
    s ^= (s << 13) & 0xFFFFFFFF;
    s ^= s >> 17;
    s ^= (s << 5) & 0xFFFFFFFF;
    data[i] = s & 0xFF;
  }
  data.setRange(0, 4, ascii.encode('OTTO'));
  return data;
}

/// PNG RGB 16x16 com um quadriculado, gerado em código (determinístico).
Uint8List _checkerPng() {
  const size = 16;
  final raw = BytesBuilder();
  for (var y = 0; y < size; y++) {
    raw.addByte(0); // filtro nenhum
    for (var x = 0; x < size; x++) {
      final on = ((x ~/ 4) + (y ~/ 4)).isEven;
      raw.add(on ? const [0x2A, 0x6F, 0x97] : const [0xF4, 0xE3, 0xC1]);
    }
  }
  final out = BytesBuilder()
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, List<int> data) {
    final t = ascii.encode(type);
    out
      ..add(_be32(data.length))
      ..add(t)
      ..add(data)
      ..add(_be32(crc32(data, crc32(t))));
  }

  chunk('IHDR', [..._be32(size), ..._be32(size), 8, 2, 0, 0, 0]);
  chunk('IDAT', ZLibEncoder(level: 6).convert(raw.takeBytes()));
  chunk('IEND', const []);
  return out.takeBytes();
}

List<int> _be32(int v) => [
  (v >> 24) & 0xFF,
  (v >> 16) & 0xFF,
  (v >> 8) & 0xFF,
  v & 0xFF,
];
