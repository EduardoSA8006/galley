import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/core/diagnostics/diagnostic_codes.dart';
import 'package:galley/src/core/diagnostics/diagnostic_sink.dart';
import 'package:galley/src/features/container/data/parsers/nav_parser.dart';
import 'package:galley/src/features/container/domain/models/navigation.dart';

const _head =
    '<?xml version="1.0" encoding="utf-8"?>'
    '<html xmlns="http://www.w3.org/1999/xhtml" '
    'xmlns:epub="http://www.idpf.org/2007/ops"><body>';
const _tail = '</body></html>';

EpubNavigation? _parse(String body, CollectingDiagnosticSink sink) =>
    parseNavDocument(
      '$_head$body$_tail',
      navPath: 'OEBPS/nav/nav.xhtml',
      sink: sink,
    );

void main() {
  test('toc aninhado em 3 níveis com href resolvido', () {
    final sink = CollectingDiagnosticSink();
    final nav = _parse(
      '<nav epub:type="toc"><ol>'
      '<li><a href="../Text/c%201.xhtml#x">Um</a><ol>'
      '<li><a href="../Text/c2.xhtml">Dois</a><ol>'
      '<li><a href="../Text/c3.xhtml">Três</a></li></ol></li></ol></li>'
      '<li><a href="../Text/c4.xhtml">Quatro</a></li>'
      '</ol></nav>',
      sink,
    )!;
    expect(nav.toc, hasLength(2));
    expect(nav.toc[0].label, 'Um');
    expect(nav.toc[0].path, 'OEBPS/Text/c 1.xhtml');
    expect(nav.toc[0].fragment, 'x');
    expect(nav.toc[0].children[0].children[0].label, 'Três');
    expect(nav.toc[0].children[0].children[0].path, 'OEBPS/Text/c3.xhtml');
    expect(nav.pageList, isEmpty);
    expect(sink.diagnostics, isEmpty);
  });

  test('&nbsp; e espaços colapsados no rótulo', () {
    final nav = _parse(
      '<nav epub:type="toc"><ol><li><a href="a.xhtml">  Capítulo&nbsp;1 \n'
      '  fim </a></li></ol></nav>',
      CollectingDiagnosticSink(),
    )!;
    expect(nav.toc.single.label, 'Capítulo 1 fim');
  });

  test('span sem link mantém filhos e path nulo', () {
    final nav = _parse(
      '<nav epub:type="toc"><ol><li><span>Parte I</span><ol>'
      '<li><a href="a.xhtml">A</a></li></ol></li></ol></nav>',
      CollectingDiagnosticSink(),
    )!;
    expect(nav.toc.single.label, 'Parte I');
    expect(nav.toc.single.path, isNull);
    expect(nav.toc.single.children.single.path, 'OEBPS/nav/a.xhtml');
  });

  test('href externo gera path nulo; rótulo vazio usa title', () {
    final nav = _parse(
      '<nav epub:type="toc"><ol>'
      '<li><a href="http://x.org/a">Ext</a></li>'
      '<li><a href="a.xhtml" title="Do título"></a></li>'
      '<li><a href="b.xhtml"></a></li>'
      '<li><span></span></li>'
      '</ol></nav>',
      CollectingDiagnosticSink(),
    )!;
    expect(nav.toc, hasLength(3));
    expect(nav.toc[0].path, isNull);
    expect(nav.toc[1].label, 'Do título');
    expect(nav.toc[2].label, '');
  });

  test('page-list e landmarks com type', () {
    final nav = _parse(
      '<nav epub:type="page-list"><ol>'
      '<li><a href="a.xhtml#p1">1</a></li></ol></nav>'
      '<nav epub:type="landmarks"><ol>'
      '<li><a epub:type="bodymatter x" href="a.xhtml">Início</a></li>'
      '</ol></nav>',
      CollectingDiagnosticSink(),
    )!;
    expect(nav.pageList.single.fragment, 'p1');
    expect(nav.landmarks.single.type, 'bodymatter');
    expect(nav.landmarks.single.label, 'Início');
  });

  test('aceita epub:type com vários tokens, role e sem namespace', () {
    final nav = parseNavDocument(
      '<html><body>'
      '<nav epub:type="foo toc"><ol><li><a href="a.xhtml">A</a></li></ol></nav>'
      '<nav role="doc-pagelist"><ol><li><a href="a.xhtml">1</a></li></ol></nav>'
      '</body></html>',
      navPath: 'nav.xhtml',
      sink: CollectingDiagnosticSink(),
    )!;
    expect(nav.toc.single.label, 'A');
    expect(nav.pageList, hasLength(1));
  });

  test('nav inválido devolve null e nav.invalid', () {
    final sink = CollectingDiagnosticSink();
    expect(
      parseNavDocument('<html><body>', navPath: 'n.xhtml', sink: sink),
      isNull,
    );
    expect(sink.diagnostics.single.code, DiagnosticCodes.navInvalid);
  });

  test('aninhamento patológico não estoura a pilha', () {
    final sink = CollectingDiagnosticSink();
    final open = '<li><a href="a.xhtml">x</a><ol>' * 200;
    final close = '</ol></li>' * 200;
    final nav = _parse('<nav epub:type="toc"><ol>$open$close</ol></nav>', sink);
    expect(nav, isNotNull);
    expect(
      sink.diagnostics.map((d) => d.code),
      contains(DiagnosticCodes.navTooDeep),
    );
  });

  test('EpubNavigation.empty', () {
    expect(EpubNavigation.empty.toc, isEmpty);
    expect(EpubNavigation.empty.pageList, isEmpty);
    expect(EpubNavigation.empty.landmarks, isEmpty);
  });
}
