import 'dart:convert';
import 'dart:typed_data';

import 'package:galley_benchmark/src/corpus/epub_writer.dart';

/// EPUB 3 mínimo com um capítulo por item de [chapters] (XHTML cru, na
/// ordem do spine), para os testes de `docdiff`, `wide` e de estilo.
///
/// [styleSheets] (caminho no zip → texto CSS) entra no manifest como
/// `text/css`; os capítulos o ligam por `<link>`, se quiserem.
///
/// [spine] (índices de [chapters]) troca o spine padrão (cada capítulo uma
/// vez, em ordem), por exemplo para repetir um `itemref`.
Uint8List buildMiniEpub(
  List<String> chapters, {
  Map<String, String> styleSheets = const {},
  List<int>? spine,
}) {
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
    for (var i = 0; i < styleSheets.length; i++)
      OpfItem('css$i', styleSheets.keys.elementAt(i), 'text/css'),
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
          spineIds: [
            for (final i
                in spine ?? [for (var i = 0; i < chapters.length; i++) i])
              'c$i',
          ],
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
  styleSheets.forEach((path, css) => zip.addBytes(path, utf8.encode(css)));
  zip.finish();
  return out.takeBytes();
}
