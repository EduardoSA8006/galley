// parseNav: toc, page-list, landmarks, títulos e limites (spec da
// Publicação §7.2).
import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/publication/nav.dart';

String _html(String body) =>
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<html xmlns="http://www.w3.org/1999/xhtml" '
    'xmlns:epub="http://www.idpf.org/2007/ops"><head><title>N</title></head>'
    '<body>$body</body></html>';

List<Object> _shape(List<NavEntry> entries) => [
  for (final e in entries)
    e.children.isEmpty
        ? '${e.title}|${e.href}'
        : ['${e.title}|${e.href}', _shape(e.children)],
];

int _depth(List<NavEntry> entries) {
  var max = 0;
  for (final e in entries) {
    final d = 1 + _depth(e.children);
    if (d > max) max = d;
  }
  return max;
}

int _count(List<NavEntry> entries) =>
    entries.fold(0, (n, e) => n + 1 + _count(e.children));

void main() {
  test('toc aninhado com ol e ul', () {
    final nav = parseNav(
      _html(
        '<nav epub:type="toc"><h1>Sumário</h1><ol>'
        '<li><a href="c1.xhtml">Um</a><ul>'
        '<li><a href="c1.xhtml#s1">Um.um</a></li>'
        '<li><a href="c1.xhtml#s2">Um.dois</a><ol>'
        '<li><a href="c1.xhtml#s2a">Fundo</a></li></ol></li></ul></li>'
        '<li><a href="c2.xhtml">Dois</a></li></ol></nav>',
      ),
    );
    expect(_shape(nav.toc), [
      [
        'Um|c1.xhtml',
        [
          'Um.um|c1.xhtml#s1',
          [
            'Um.dois|c1.xhtml#s2',
            ['Fundo|c1.xhtml#s2a'],
          ],
        ],
      ],
      'Dois|c2.xhtml',
    ]);
    expect(nav.truncated, isFalse);
  });

  test('a dentro de p e strong; whitespace colapsado', () {
    final nav = parseNav(
      _html(
        '<nav epub:type="toc"><ol><li><p><strong><a href="c1.xhtml">'
        '\n  Capítulo\n\t <em>primeiro</em>  </a></strong></p></li></ol></nav>',
      ),
    );
    expect(_shape(nav.toc), ['Capítulo primeiro|c1.xhtml']);
  });

  test('span de agrupamento e a sem href não têm alvo', () {
    final nav = parseNav(
      _html(
        '<nav epub:type="toc"><ol><li><span>Parte I</span><ol>'
        '<li><a href="c1.xhtml">Um</a></li></ol></li>'
        '<li><a>Sem alvo</a></li></ol></nav>',
      ),
    );
    expect(_shape(nav.toc), [
      [
        'Parte I|null',
        ['Um|c1.xhtml'],
      ],
      'Sem alvo|null',
    ]);
  });

  test('título vazio: alt do img, depois title, depois vazio', () {
    final nav = parseNav(
      _html(
        '<nav epub:type="toc"><ol>'
        '<li><a href="a.xhtml"><img src="x.png" alt=" Mapa "/></a></li>'
        '<li><a href="b.xhtml" title="Pelo título"><img src="y.png"/></a></li>'
        '<li><a href="c.xhtml"> </a></li></ol></nav>',
      ),
    );
    expect(nav.toc.map((e) => e.title), ['Mapa', 'Pelo título', '']);
  });

  test('a lista aninhada não entra no título nem na busca do rótulo', () {
    final nav = parseNav(
      _html(
        '<nav epub:type="toc"><ol><li><ol><li><a href="f.xhtml">Filho</a>'
        '</li></ol><a href="p.xhtml">Pai</a></li></ol></nav>',
      ),
    );
    expect(_shape(nav.toc), [
      [
        'Pai|p.xhtml',
        ['Filho|f.xhtml'],
      ],
    ]);
  });

  test('landmarks com type e page-list', () {
    final nav = parseNav(
      _html(
        '<nav epub:type="landmarks"><ol>'
        '<li><a epub:type="cover" href="capa.xhtml">Capa</a></li>'
        '<li><a epub:type="bodymatter" href="c1.xhtml">Início</a></li></ol>'
        '</nav><nav epub:type="page-list" hidden=""><ol>'
        '<li><a href="c1.xhtml#p1">1</a></li><li><a href="c1.xhtml#p2">2</a>'
        '</li></ol></nav>',
      ),
    );
    expect(nav.toc, isEmpty);
    expect(nav.landmarks.map((e) => (e.type, e.href)), [
      ('cover', 'capa.xhtml'),
      ('bodymatter', 'c1.xhtml'),
    ]);
    expect(nav.pageList.map((e) => e.title), ['1', '2']);
    expect(nav.pageList.first.type, isNull);
  });

  test('dois nav do mesmo tipo: vale o primeiro; token no epub:type', () {
    final nav = parseNav(
      _html(
        '<nav epub:type="x toc"><ol><li><a href="a.xhtml">A</a></li></ol></nav>'
        '<nav epub:type="toc"><ol><li><a href="b.xhtml">B</a></li></ol></nav>'
        '<nav epub:type="tocx"><ol><li><a href="c.xhtml">C</a></li></ol></nav>',
      ),
    );
    expect(_shape(nav.toc), ['A|a.xhtml']);
  });

  test('HTML malformado e sem declaração', () {
    final nav = parseNav(
      '<nav epub:type="toc"><ol><li><a href="a.xhtml">A &amp; B&nbsp;C'
      '<li><a href="b.xhtml">B',
    );
    expect(nav.toc.map((e) => e.title), ['A & B C', 'B']);
  });

  test('profundidade 64: o nível 65 é descartado e marca truncated', () {
    String nested(int levels) => levels == 0
        ? ''
        : '<ol><li><a href="n$levels.xhtml">N</a>${nested(levels - 1)}'
              '</li></ol>';
    final ok = parseNav(_html('<nav epub:type="toc">${nested(64)}</nav>'));
    expect(_depth(ok.toc), 64);
    expect(ok.truncated, isFalse);
    final deep = parseNav(_html('<nav epub:type="toc">${nested(65)}</nav>'));
    expect(_depth(deep.toc), 64);
    expect(deep.truncated, isTrue);
  });

  test('100 000 entradas por nav: o excedente é descartado', () {
    final items = '<li><a href="a.xhtml">x</a></li>' * (maxNavEntries + 5);
    final nav = parseNav(
      _html(
        '<nav epub:type="toc"><ol>$items</ol></nav>'
        '<nav epub:type="page-list"><ol><li><a href="p.xhtml">1</a></li>'
        '</ol></nav>',
      ),
    );
    expect(_count(nav.toc), maxNavEntries);
    expect(nav.pageList, hasLength(1), reason: 'o limite é por nav');
    expect(nav.truncated, isTrue);
  });

  test('aninhamento hostil: corte linear antes do parse, truncated', () {
    final body = '<ol><li><a href="x.xhtml">t</a>' * 20000;
    final sw = Stopwatch()..start();
    final nav = parseNav(_html('<nav epub:type="toc">$body</nav>'));
    sw.stop();
    expect(nav.truncated, isTrue);
    expect(_depth(nav.toc), maxNavDepth);
    expect(
      sw.elapsed,
      lessThan(const Duration(seconds: 3)),
      reason: 'sem o corte, 20 000 níveis levam minutos',
    );
  });

  group('htmlWorkCut', () {
    test('documento comum cabe inteiro', () {
      expect(
        htmlWorkCut(_html('<nav><ol><li><a href="a">A</a></li></ol></nav>')),
        isNull,
      );
    });

    test('comentário, doctype, void e /> não empilham', () {
      final text =
          '<!DOCTYPE html><!-- <div><div> --><br><img src="x"><div/>' * 1000;
      expect(htmlWorkCut(text, budget: 20000), isNull);
    });

    test('fechamento sem abertura não desempilha a pilha real', () {
      final text = '${'<div>' * 100}${'</p>' * 1000}';
      expect(htmlWorkCut(text, budget: 50000), isNotNull);
    });

    test('corta no < da tag que estoura o orçamento', () {
      final text = '<div>' * 10;
      // 1 + 2 + … + 10 = 55; com orçamento 45 a 10ª tag (9 + 1) estoura.
      expect(htmlWorkCut(text, budget: 45), 45);
    });
  });
}
