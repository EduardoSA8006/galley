import 'dart:convert';
import 'dart:typed_data';

import 'package:galley_benchmark/src/corpus/epub_writer.dart';

/// EPUB 3 mínimo com um capítulo por item de [chapters] (XHTML cru, na
/// ordem do spine), para os testes de `docdiff` e `wide`.
Uint8List buildMiniEpub(List<String> chapters) {
  final out = BytesBuilder(copy: false);
  final zip = ZipWriter(out.add)
    ..addBytes('mimetype', utf8.encode('application/epub+zip'), deflate: false)
    ..addBytes('META-INF/container.xml', utf8.encode(containerXml('o.opf')));
  final items = [
    const OpfItem(
      'nav',
      'nav.xhtml',
      'application/xhtml+xml',
      properties: 'nav',
    ),
    for (var i = 0; i < chapters.length; i++)
      OpfItem('c$i', 'c$i.xhtml', 'application/xhtml+xml'),
  ];
  zip
    ..addBytes(
      'o.opf',
      utf8.encode(
        buildOpf(
          version: '3.0',
          title: 'Mini',
          identifier: 'urn:x:mini',
          language: 'pt-BR',
          items: items,
          spineIds: [for (var i = 0; i < chapters.length; i++) 'c$i'],
        ),
      ),
    )
    ..addBytes(
      'nav.xhtml',
      utf8.encode(
        buildNavXhtml(
          language: 'pt-BR',
          title: 'Mini',
          entries: [
            for (var i = 0; i < chapters.length; i++) ('c$i.xhtml', 'C$i'),
          ],
        ),
      ),
    );
  for (var i = 0; i < chapters.length; i++) {
    zip.addBytes('c$i.xhtml', utf8.encode(chapters[i]));
  }
  zip.finish();
  return out.takeBytes();
}
