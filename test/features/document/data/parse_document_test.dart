import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/core/diagnostics/diagnostic_codes.dart';
import 'package:galley/src/core/diagnostics/diagnostic_sink.dart';
import 'package:galley/src/core/errors/galley_exception.dart';
import 'package:galley/src/features/container/domain/epub_book.dart';
import 'package:galley/src/features/document/data/parse_document.dart';
import 'package:galley/src/features/document/domain/names.dart';

import '../../../support/document_dump.dart';
import '../../../support/epub_builder.dart';

const _xhtml = 'http://www.w3.org/1999/xhtml';
const _svg = 'http://www.w3.org/2000/svg';

Future<EpubBook> _book() => EpubBook.fromBytes(
  buildEpub({
    'OEBPS/content.opf': opf3(
      manifest:
          '<item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>'
          '<item id="c2" href="c2.html" media-type="text/html"/>'
          '<item id="c3" href="c3.svg" media-type="image/svg+xml"/>'
          '<item id="c4" href="c4.svg" media-type="image/svg+xml"/>'
          '<item id="c5" href="c5.css" media-type="text/css"/>',
      spine: '<itemref idref="c1"/><itemref idref="c2"/><itemref idref="c3"/>',
    ),
    'OEBPS/c1.xhtml':
        '<html xmlns="$_xhtml"><head><title>Um</title></head>'
        '<body><p>Oi</p></body></html>',
    'OEBPS/c2.html': '<p>Solto<br>texto',
    'OEBPS/c3.svg': '<svg xmlns="$_svg"><rect width="1"/></svg>',
    'OEBPS/c4.svg': '<svg><rect width="1"></svg',
    'OEBPS/c5.css': 'p{}',
    'OEBPS/solto.xhtml':
        '<html xmlns="$_xhtml"><body>sem manifest</body></html>',
  }),
);

void main() {
  group('parseDocument', () {
    test('XHTML: modo estrito, head e diagnósticos no sink', () async {
      final book = await _book();
      final sink = CollectingDiagnosticSink();
      final doc = await parseDocument(book, 'OEBPS/c1.xhtml', sink: sink);
      expect(doc.recovered, isFalse);
      expect(doc.head.title, 'Um');
      final t = doc.tree;
      final root = t.firstChildOf(t.documentNode);
      expect(t.localNameOf(root), 'html');
      expect(sink.diagnostics, doc.diagnostics);
    });

    test('text/html: tolerante, raiz html virtual', () async {
      final book = await _book();
      final sink = CollectingDiagnosticSink();
      final doc = await parseDocument(book, 'OEBPS/c2.html', sink: sink);
      expect(doc.recovered, isTrue);
      final t = doc.tree;
      final root = t.firstChildOf(t.documentNode);
      expect(t.localNameOf(root), 'html');
      expect(t.isVirtual(root), isTrue);
      expect(sink.diagnostics, isNotEmpty);
      expect(sink.diagnostics, doc.diagnostics);
    });

    test('SVG: raiz svg no namespace SVG, sem html/body', () async {
      final book = await _book();
      final doc = await parseDocument(book, 'OEBPS/c3.svg');
      final t = doc.tree;
      final root = t.firstChildOf(t.documentNode);
      expect(t.localNameOf(root), 'svg');
      expect(t.namespaceOf(root), Namespaces.svg);
      expect(t.isVirtual(root), isFalse);
      expect(t.nextSiblingOf(root), -1);
      expect(doc.recovered, isFalse);
      expect(doc.head.styleSheets, isEmpty);
      expect(doc.head.title, isNull);
    });

    test('SVG malformado: tolerante, sem envolver em html/body', () async {
      final book = await _book();
      final doc = await parseDocument(book, 'OEBPS/c4.svg');
      final t = doc.tree;
      final root = t.firstChildOf(t.documentNode);
      expect(t.localNameOf(root), 'svg');
      expect(t.namespaceOf(root), Namespaces.svg);
      expect(t.isVirtual(root), isFalse);
      expect(doc.recovered, isTrue);
      expect(
        doc.diagnostics.map((d) => d.code),
        contains(DiagnosticCodes.recovered),
      );
    });

    test('sem item no manifest usa XHTML', () async {
      final book = await _book();
      final doc = await parseDocument(book, 'OEBPS/solto.xhtml');
      final t = doc.tree;
      final root = t.firstChildOf(t.documentNode);
      expect(t.localNameOf(root), 'html');
      expect(t.namespaceOf(root), Namespaces.xhtml);
    });

    test('media-type fora de XHTML/HTML/SVG lança ArgumentError', () async {
      final book = await _book();
      await expectLater(
        parseDocument(book, 'OEBPS/c5.css'),
        throwsArgumentError,
      );
    });

    test('recurso inexistente propaga ResourceNotFoundException', () async {
      final book = await _book();
      await expectLater(
        parseDocument(book, 'OEBPS/nada.xhtml'),
        throwsA(isA<ResourceNotFoundException>()),
      );
    });
  });

  group('isolate', () {
    final cases = <String, (String, String)>{
      'xhtml': (
        '<html xmlns="$_xhtml" lang="pt"><head><title>T</title></head>'
            '<body><p class="a b" id="x">Oi &amp; <b>você</b></p>'
            '<![CDATA[cd]]></body></html>',
        'application/xhtml+xml',
      ),
      'malformado': (
        '<p>um<p>dois <b>três &nbsp; <img src=a>',
        'application/xhtml+xml',
      ),
      'html': ('<DIV CLASS=x>a<br>b</DIV>', 'text/html'),
      'svg': ('<svg xmlns="$_svg"><g id="a"/></svg>', 'image/svg+xml'),
    };
    cases.forEach((name, c) {
      test('árvore transferida é igual à local: $name', () async {
        final bytes = Uint8List.fromList(utf8.encode(c.$1));
        final mediaType = c.$2;
        final local = parseDocumentBytes(
          bytes,
          path: 'a/b.xhtml',
          mediaType: mediaType,
        );
        final remote = await Isolate.run(
          () => parseDocumentBytes(
            bytes,
            path: 'a/b.xhtml',
            mediaType: mediaType,
          ),
        );
        expect(dumpTree(remote.tree), dumpTree(local.tree));
        expect(remote.recovered, local.recovered);
        expect(remote.head.title, local.head.title);
        expect(
          remote.diagnostics.map((d) => '${d.code}@${d.location}').toList(),
          local.diagnostics.map((d) => '${d.code}@${d.location}').toList(),
        );
      });
    });
  });
}
