// Gera `assets/sample.epub`, um EPUB pequeno de autoria própria (PT-BR).
//
// Uso (a partir de `example/`): `dart run tool/make_sample_epub.dart`
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const _chapters = <(String, String)>[
  (
    'Primeiro capítulo',
    'Era uma vez uma biblioteca que cabia dentro de um bolso. '
        'Cada página chegava ao leitor sem navegador nenhum no caminho.',
  ),
  (
    'Segundo capítulo',
    'A tipografia faz o texto respirar: margens, entrelinhas e quebras de '
        'linha decidem se a leitura flui ou tropeça.',
  ),
  (
    'Terceiro capítulo',
    'Fim da amostra. Este livro existe apenas para exercitar o Galley.',
  ),
];

void main() {
  final zip = _Zip()
    ..add('mimetype', utf8.encode('application/epub+zip'))
    ..add('META-INF/container.xml', utf8.encode(_container))
    ..add('OEBPS/content.opf', utf8.encode(_opf()))
    ..add('OEBPS/nav.xhtml', utf8.encode(_nav()));
  for (var i = 0; i < _chapters.length; i++) {
    zip.add('OEBPS/cap${i + 1}.xhtml', utf8.encode(_chapter(i)));
  }
  File('assets/sample.epub')
    ..createSync(recursive: true)
    ..writeAsBytesSync(zip.build());
  stdout.writeln('assets/sample.epub gerado.');
}

const _container =
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<container version="1.0" '
    'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
    '<rootfiles><rootfile full-path="OEBPS/content.opf" '
    'media-type="application/oebps-package+xml"/></rootfiles></container>';

String _opf() {
  final manifest = StringBuffer(
    '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" '
    'properties="nav"/>',
  );
  final spine = StringBuffer();
  for (var i = 1; i <= _chapters.length; i++) {
    manifest.write(
      '<item id="c$i" href="cap$i.xhtml" media-type="application/xhtml+xml"/>',
    );
    spine.write('<itemref idref="c$i"/>');
  }
  return '<?xml version="1.0" encoding="UTF-8"?>'
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
      'unique-identifier="bookid"><metadata '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="bookid">urn:uuid:6f1d2c3a-0000-4000-8000-00000000a001'
      '</dc:identifier><dc:title>Livro de Exemplo do Galley</dc:title>'
      '<dc:language>pt-BR</dc:language>'
      '<meta property="dcterms:modified">2026-11-24T00:00:00Z</meta>'
      '</metadata><manifest>$manifest</manifest>'
      '<spine>$spine</spine></package>';
}

String _nav() {
  final items = StringBuffer();
  for (var i = 0; i < _chapters.length; i++) {
    items.write('<li><a href="cap${i + 1}.xhtml">${_chapters[i].$1}</a></li>');
  }
  return _xhtml(
    'Sumário',
    '<nav xmlns:epub="http://www.idpf.org/2007/ops" epub:type="toc">'
        '<ol>$items</ol></nav>',
  );
}

String _chapter(int i) => _xhtml(
  _chapters[i].$1,
  '<h1>${_chapters[i].$1}</h1><p>${_chapters[i].$2}</p>',
);

String _xhtml(String title, String body) =>
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<html xmlns="http://www.w3.org/1999/xhtml" lang="pt-BR">'
    '<head><title>$title</title></head><body>$body</body></html>';

/// Zip mínimo, sem compressão (método 0), suficiente para o exemplo.
class _Zip {
  final _entries = <(String, Uint8List, int)>[];

  void add(String name, List<int> data) {
    final bytes = Uint8List.fromList(data);
    _entries.add((name, bytes, _crc32(bytes)));
  }

  Uint8List build() {
    final out = BytesBuilder();
    final central = BytesBuilder();
    for (final (name, data, crc) in _entries) {
      final nameBytes = utf8.encode(name);
      final offset = out.length;
      out
        ..add(_u32(0x04034b50))
        ..add(_u16(20))
        ..add(_u16(0x0800))
        ..add(_u16(0))
        ..add(_u16(0))
        ..add(_u16(0x21))
        ..add(_u32(crc))
        ..add(_u32(data.length))
        ..add(_u32(data.length))
        ..add(_u16(nameBytes.length))
        ..add(_u16(0))
        ..add(nameBytes)
        ..add(data);
      central
        ..add(_u32(0x02014b50))
        ..add(_u16(20))
        ..add(_u16(20))
        ..add(_u16(0x0800))
        ..add(_u16(0))
        ..add(_u16(0))
        ..add(_u16(0x21))
        ..add(_u32(crc))
        ..add(_u32(data.length))
        ..add(_u32(data.length))
        ..add(_u16(nameBytes.length))
        ..add(_u16(0))
        ..add(_u16(0))
        ..add(_u16(0))
        ..add(_u16(0))
        ..add(_u32(0))
        ..add(_u32(offset))
        ..add(nameBytes);
    }
    final cdOffset = out.length;
    final cd = central.takeBytes();
    out
      ..add(cd)
      ..add(_u32(0x06054b50))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u16(_entries.length))
      ..add(_u16(_entries.length))
      ..add(_u32(cd.length))
      ..add(_u32(cdOffset))
      ..add(_u16(0));
    return out.takeBytes();
  }
}

List<int> _u16(int v) => [v & 0xff, (v >> 8) & 0xff];
List<int> _u32(int v) => [
  v & 0xff,
  (v >> 8) & 0xff,
  (v >> 16) & 0xff,
  (v >> 24) & 0xff,
];

int _crc32(List<int> data) {
  var crc = 0xffffffff;
  for (final b in data) {
    crc ^= b;
    for (var k = 0; k < 8; k++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}
