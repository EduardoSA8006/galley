import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/core/diagnostics/diagnostic_codes.dart';
import 'package:galley/src/features/document/data/parse_document.dart';
import 'package:galley/src/features/document/domain/document_head.dart';
import 'package:galley/src/features/document/domain/names.dart';
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

  test('xml:lang vence lang; valor aparado; vazio é desconhecido', () {
    expect(_parse('', htmlAttrs: 'xml:lang="en"').head.lang, 'en');
    expect(_parse('', htmlAttrs: 'lang="fr"').head.lang, 'fr');
    expect(_parse('', htmlAttrs: 'lang="fr" xml:lang="en"').head.lang, 'en');
    expect(_parse('', htmlAttrs: 'lang=" pt "').head.lang, 'pt');
    expect(_parse('', htmlAttrs: 'lang="" xml:lang="en"').head.lang, 'en');
    expect(_parse('', htmlAttrs: 'lang="fr" xml:lang=" "').head.lang, isNull);
    expect(_parse('').head.lang, isNull);
  });

  test('ordem de documento entre head e body; style no body', () {
    final doc = _parse(
      '<link rel="stylesheet" href="a.css"/>',
      body:
          '<style>b{}</style><div><link rel="stylesheet" href="c.css"/></div>',
    );
    final sheets = doc.head.styleSheets;
    expect(sheets, hasLength(3));
    expect((sheets[0] as LinkedStyleSheet).path, 'OEBPS/text/a.css');
    expect((sheets[1] as InlineStyleSheet).css, 'b{}');
    expect((sheets[2] as LinkedStyleSheet).path, 'OEBPS/text/c.css');
    expect(
      _codes(doc).where((c) => c == DiagnosticCodes.headInBody),
      hasLength(2),
    );
  });

  test('título: o primeiro do head; title no body não conta', () {
    final head = _parse(
      '<title>Um</title><title>Dois</title>',
      body: '<title>Corpo</title>',
    ).head;
    expect(head.title, 'Um');
    final onlyBody = _parse('', body: '<title>Corpo</title>').head;
    expect(onlyBody.title, isNull);
  });

  group('sem xmlns (namespace implícito)', () {
    const head =
        '<title>T</title><link rel="stylesheet" href="a.css"/>'
        '<style>p{}</style>';
    String source({bool xmlns = false, bool broken = false}) =>
        '<html${xmlns ? ' xmlns="$_xhtml"' : ''} lang="pt">'
        '<head>$head</head><body><p>a${broken ? '' : '</p>'}</body></html>';
    ParsedDocument parse(String s) =>
        parseDocumentBytes(Uint8List.fromList(utf8.encode(s)), path: 'c.xhtml');

    void expectSameHead(DocumentHead a, DocumentHead b) {
      expect(a.title, b.title);
      expect(a.lang, b.lang);
      expect(a.styleSheets, hasLength(b.styleSheets.length));
      for (var i = 0; i < a.styleSheets.length; i++) {
        expect(a.styleSheets[i].runtimeType, b.styleSheets[i].runtimeType);
      }
    }

    test('mesmo head que o documento com xmlns', () {
      final implied = parse(source());
      final declared = parse(source(xmlns: true));
      expect(implied.recovered, isFalse);
      expect(implied.head.title, 'T');
      expect(implied.head.lang, 'pt');
      expect(implied.head.styleSheets, hasLength(2));
      expectSameHead(implied.head, declared.head);
      expect(_codes(implied), contains(DiagnosticCodes.impliedNamespace));
      expect(
        _codes(declared),
        isNot(contains(DiagnosticCodes.impliedNamespace)),
      );
    });

    test('estrito e tolerante concordam', () {
      final strict = parse(source());
      final tolerant = parse(source(broken: true));
      expect(strict.recovered, isFalse);
      expect(tolerant.recovered, isTrue);
      expectSameHead(strict.head, tolerant.head);
      expect(_codes(tolerant), contains(DiagnosticCodes.impliedNamespace));
      for (final doc in [strict, tolerant]) {
        final root = doc.tree.firstChildOf(doc.tree.documentNode);
        expect(doc.tree.namespaceOf(root), Namespaces.xhtml);
      }
    });

    test('text/html não gera impliedNamespace', () {
      final doc = parseDocumentBytes(
        Uint8List.fromList(utf8.encode(source())),
        path: 'c.html',
        mediaType: 'text/html',
      );
      expect(doc.head.title, 'T');
      expect(_codes(doc), isNot(contains(DiagnosticCodes.impliedNamespace)));
    });
  });

  test('80k <div> aninhados + 80k <style/> no body: tempo linear', () {
    // Antes da passada única, cada <style> subia até a raiz: O(n²)
    // (742 KiB levavam 15 s). ~1,5 MiB aqui.
    final body = '${'<div>' * 80000}${'<style/>' * 80000}${'</div>' * 80000}';
    final watch = Stopwatch()..start();
    final doc = _parse('', body: body);
    watch.stop();
    expect(watch.elapsed, lessThan(const Duration(seconds: 10)));
    expect(doc.recovered, isFalse);
    expect(doc.head.styleSheets, hasLength(80000));
    // Limite por código: 20 ocorrências + 1 resumo com o total.
    final inBody = doc.diagnostics
        .where((d) => d.code == DiagnosticCodes.headInBody)
        .toList();
    expect(inBody, hasLength(21));
    expect(inBody.last.message, contains('80000'));
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
      Uint8List.fromList(utf8.encode('<!-- sem conteúdo -->')),
      path: 'a.xhtml',
    );
    expect(doc.head, same(DocumentHead.empty));
  });
}
