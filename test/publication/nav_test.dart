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

/// [unit] repetido até [bytes].
String _fill(String unit, [int bytes = 1 << 20]) =>
    unit * (bytes ~/ unit.length);

/// [unit] com o índice da repetição, até [bytes].
String _seq(String Function(int) unit, [int bytes = 1 << 20]) {
  final out = StringBuffer();
  for (var i = 0; out.length < bytes; i++) {
    out.write(unit(i));
  }
  return out.toString();
}

/// Um NAV com uma entrada seguido de [tail]: o sumário tem de sair inteiro.
String _navThen(String tail) => _html(
  '<nav epub:type="toc"><ol><li><a href="a.xhtml">A</a></li></ol></nav>$tail',
);

/// Parse de [text] com corte, rápido, sem perder o NAV que vem antes.
void _expectCutFast(String text) {
  expect(htmlWorkCut(text), isNotNull);
  final sw = Stopwatch()..start();
  final nav = parseNav(text);
  sw.stop();
  expect(nav.truncated, isTrue);
  expect(_shape(nav.toc), ['A|a.xhtml']);
  expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
}

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

  test('li sem fechamento num ol só: um li fecha o anterior, sem corte', () {
    final items = '<li><a href="x.xhtml">t</a>' * 20000;
    final nav = parseNav(_html('<nav epub:type="toc"><ol>$items</ol></nav>'));
    expect(nav.toc, hasLength(20000));
    expect(nav.truncated, isFalse);
  });

  group('formas hostis de 1 MiB: o corte segue o parser HTML5', () {
    // Cada uma deixava o html.parse quadrático porque o corte não via o que
    // o parser vê (200 KB levavam de 5 s a mais de 60 s).
    final forms = <String, String>{
      '<!--> fecha o comentário': '<!-->${_fill('<div>')}',
      '<!---> fecha o comentário': '<!--->${_fill('<div>')}',
      '--!> fecha o comentário': '<!-- x --!>${_fill('<div>')}-->',
      '</li> ignorado com ol no meio': _fill('<li><ol></li>'),
      '</span> ignorado com div (special) no meio': _fill('<span><div></span>'),
      'adoption agency deixa o div aberto (b)': _fill('<b><div></b>'),
      'adoption agency deixa o div aberto (a)': _fill('<a><div></a>'),
      'reconstrução da formatação ativa (div)': _seq(
        (i) => '<div><b x="$i"></div>',
      ),
      'reconstrução da formatação ativa (p)': _seq((i) => '<p><b x="$i"></p>'),
    };
    for (final MapEntry(key: name, value: body) in forms.entries) {
      test(name, () => _expectCutFast(_navThen(body)));
    }
  });

  group('formas hostis de 256 KiB fora do modelo antigo', () {
    const k256 = 1 << 18;
    final forms = <String, String>{
      '> e </div> dentro de valor entre aspas': _fill(
        '<div title="></div>">',
        k256,
      ),
      'comentário com > antes do fim': _fill('<div><!-- > </div> -->', k256),
      '</ e <? são comentários falsos até o >': _fill(
        '<div></ </div><? </div>',
        k256,
      ),
      'nome do fechamento vai até whitespace, / ou >': _fill(
        '<div></div">',
        k256,
      ),
      'fechamento de nome qualquer para em li e dd': _fill(
        '<span><li></span><span><dd></span>',
        k256,
      ),
      'iframe ignorado dentro de select':
          '<select><iframe></select>${_fill('<div>', k256)}</iframe>',
      'script com <!--<script> não fecha no primeiro </script>': _fill(
        '<div><script><!--<script></script></div></script>',
        k256,
      ),
      'foster parenting procura a tabela entre os irmãos':
          '<table>${_fill('x<i></i>', k256)}',
      'input sem type=hidden também vai por foster parenting':
          '<table>${_fill('<input>', k256)}',
      'textarea em SVG: região ambígua cobra o pior token':
          '<svg>${_fill('</h1><textarea>', k256)}',
      'texto com formatação ativa fora do topo':
          '<b>${'<div>' * 3000}<span>${_fill('x&amp;', k256)}',
      'option em SVG é estrangeiro e não fecha option':
          '<svg>${_fill('<option><</script>', k256)}',
      '</h1> testa o escopo de cada cabeçalho':
          '<b>${'<div>' * 200}<span>${_fill('--!></h1>', k256)}',
      'nome de tag longo (concatenado caractere a caractere)':
          '<${'a' * k256}>',
      'DOCTYPE longo': '<!DOCTYPE html PUBLIC "${'a' * k256}">',
    };
    for (final MapEntry(key: name, value: body) in forms.entries) {
      test(name, () => _expectCutFast(_navThen(body)));
    }
  });

  group('htmlWorkCut', () {
    test('documento comum cabe inteiro', () {
      expect(
        htmlWorkCut(_html('<nav><ol><li><a href="a">A</a></li></ol></nav>')),
        isNull,
      );
    });

    test('comentário, doctype e void não empilham', () {
      final text = '<!DOCTYPE html><!-- <div><div> --><br><img src="x">' * 1000;
      expect(htmlWorkCut(text, budget: 20000), isNull);
    });

    test('/> não fecha elemento não vazio (o HTML5 ignora a barra)', () {
      expect(htmlWorkCut('<div/>' * 1000, budget: 20000), isNotNull);
    });

    test('> e </div> em valor entre aspas não terminam a tag', () {
      expect(
        htmlWorkCut('<div title="></div>">' * 1000, budget: 20000),
        isNotNull,
      );
      expect(
        htmlWorkCut('<div title="a>b"></div>' * 1000, budget: 20000),
        isNull,
      );
    });

    test('isindex conta os seis nós que o parser cria', () {
      expect(htmlWorkCut('<isindex>' * 1000, budget: 100000), isNotNull);
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
