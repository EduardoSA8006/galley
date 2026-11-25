import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/core/diagnostics/diagnostic_codes.dart';
import 'package:galley/src/features/document/data/parse_document.dart';
import 'package:galley/src/features/document/domain/document_head.dart';
import 'package:galley/src/features/document/domain/parsed_document.dart';

const _xhtml = 'http://www.w3.org/1999/xhtml';

ParsedDocument _parse(
  String head, {
  String body = '',
  String htmlAttrs = '',
  String path = 'OEBPS/text/c1.xhtml',
}) => parseDocumentBytes(
  Uint8List.fromList(
    utf8.encode(
      '<html xmlns="$_xhtml" $htmlAttrs><head>$head</head>'
      '<body>$body</body></html>',
    ),
  ),
  path: path,
);

List<String> _codes(ParsedDocument d) => [
  for (final x in d.diagnostics) x.code,
];

void main() {
  test('três folhas (link, style, link) em ordem', () {
    final head = _parse(
      '<link rel="stylesheet" href="a.css"/>'
      '<style>p { color: red; }</style>'
      '<link rel="stylesheet" href="b.css"/>',
    ).head;
    expect(head.styleSheets, hasLength(3));
    expect((head.styleSheets[0] as LinkedStyleSheet).path, 'OEBPS/text/a.css');
    expect((head.styleSheets[1] as InlineStyleSheet).css, 'p { color: red; }');
    expect((head.styleSheets[2] as LinkedStyleSheet).path, 'OEBPS/text/b.css');
  });

  test('href relativo com .. resolve a partir do documento', () {
    final head = _parse('<link rel="stylesheet" href="../css/a.css"/>').head;
    expect(
      (head.styleSheets.single as LinkedStyleSheet).path,
      'OEBPS/css/a.css',
    );
  });

  test('rel com vários tokens e caixa mista conta', () {
    final head = _parse(
      '<link rel="alternate StyleSheet" href="a.css" title="Alt" '
      'media="screen"/>'
      '<link rel="icon" href="i.png"/>',
    ).head;
    final s = head.styleSheets.single as LinkedStyleSheet;
    expect(s.title, 'Alt');
    expect(s.media, 'screen');
  });

  test('style preserva media', () {
    final head = _parse('<style media="print">a{}</style>').head;
    final s = head.styleSheets.single as InlineStyleSheet;
    expect(s.media, 'print');
    expect(s.css, 'a{}');
  });

  test('link no body é coletado com headInBody', () {
    final doc = _parse(
      '',
      body: '<link rel="stylesheet" href="x.css"/><p>t</p>',
    );
    expect(doc.head.styleSheets, hasLength(1));
    expect(_codes(doc), contains(DiagnosticCodes.headInBody));
  });

  test('link e style no head não geram headInBody', () {
    final doc = _parse(
      '<link rel="stylesheet" href="x.css"/><style>a{}</style>',
    );
    expect(_codes(doc), isNot(contains(DiagnosticCodes.headInBody)));
  });

  test('título, lang e dir', () {
    final head = _parse(
      '<title>  Capítulo\n  Um  </title>',
      htmlAttrs: 'lang="pt-BR" dir="rtl"',
    ).head;
    expect(head.title, 'Capítulo Um');
    expect(head.lang, 'pt-BR');
    expect(head.dir, 'rtl');
  });

  test('lang cai em xml:lang; lang tem preferência', () {
    expect(_parse('', htmlAttrs: 'xml:lang="en"').head.lang, 'en');
    expect(_parse('', htmlAttrs: 'lang="fr" xml:lang="en"').head.lang, 'fr');
    expect(_parse('').head.lang, isNull);
  });

  test('viewport', () {
    final head = _parse(
      '<meta name="viewport" content="width=600, height=800"/>',
    ).head;
    expect(head.viewport, 'width=600, height=800');
  });

  test('href externo é ignorado com diagnóstico', () {
    final doc = _parse('<link rel="stylesheet" href="http://x/y.css"/>');
    expect(doc.head.styleSheets, isEmpty);
    expect(_codes(doc), contains(DiagnosticCodes.externalStyleSheet));
  });

  test('href que escapa do zip é ignorado com diagnóstico', () {
    final doc = _parse('<link rel="stylesheet" href="../../../a.css"/>');
    expect(doc.head.styleSheets, isEmpty);
    expect(_codes(doc), contains(DiagnosticCodes.externalStyleSheet));
  });

  test('sem head útil: vazio', () {
    final head = _parse('').head;
    expect(head.styleSheets, isEmpty);
    expect(head.title, isNull);
    expect(head.viewport, isNull);
    expect(head.dir, isNull);
  });

  test('documento irrecuperável mantém DocumentHead.empty', () {
    final doc = parseDocumentBytes(
      Uint8List.fromList(utf8.encode('\u0000<<<')),
      path: 'a.xhtml',
    );
    expect(doc.head, same(DocumentHead.empty));
  });
}
