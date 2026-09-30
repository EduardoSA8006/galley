// RuleIndex (spec do CSS §10.3): balde pela parte mais à direita, seq na
// ordem da cascata e o teto de 20 000 seletores.
import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/css/parser.dart';
import 'package:galley/src/css/rule_index.dart';
import 'package:galley/src/css/ua_sheet.dart';

RuleIndex _index(List<(String, String)> sheets, {int? max}) {
  final rules = [
    for (final (href, css) in sheets)
      for (final r in parseStyleSheet(css).rules) (r, CssOrigin.author, href),
  ];
  return max == null ? RuleIndex(rules) : RuleIndex(rules, maxEntries: max);
}

void main() {
  test('balde: id, senão a primeira classe, senão o tipo, senão universal', () {
    final i = _index([
      (
        'a.css',
        'div #x { display: block } p.a.b { display: block } '
            'P { display: block } [a=b] { display: block } * { display: block } '
            ':first-child { display: block } div > .c { display: block }',
      ),
    ]);
    expect(i.byId('x'), hasLength(1));
    expect(i.byClass('a'), hasLength(1));
    expect(i.byClass('b'), isEmpty);
    expect(i.byClass('c'), hasLength(1));
    expect(i.byTag('p'), hasLength(1), reason: 'p.a.b fica no balde da classe');
    expect(i.byTag('div'), isEmpty, reason: 'só a parte mais à direita conta');
    expect(i.universal, hasLength(3));
    expect(i.length, 7);
    expect(i.byId('nada'), isEmpty);
  });

  test('seq: contador global na ordem das folhas, regras e declarações', () {
    final i = _index([
      (
        'a.css',
        'p { display: block; font-style: italic } h1, h2 { display: none }',
      ),
      ('b.css', 'em { font-weight: bold }'),
    ]);
    expect(i.byTag('p').single.seqBase, 0);
    expect(i.byTag('h1').single.seqBase, 2);
    expect(i.byTag('h2').single.seqBase, 2, reason: 'o bloco é partilhado');
    expect(
      identical(
        i.byTag('h1').single.declarations,
        i.byTag('h2').single.declarations,
      ),
      isTrue,
    );
    expect(i.byTag('em').single.seqBase, 3);
    expect(i.byTag('em').single.origin, CssOrigin.author);
  });

  test('regra sem declaração não entra', () {
    final i = _index([
      ('a.css', 'p { } p { color: red } h1 { display: none }'),
    ]);
    expect(i.length, 1);
    expect(i.byTag('h1').single.seqBase, 0);
  });

  test('20 000 seletores entram; o 20 001º corta com truncatedAt', () {
    String rules(int n, String prefix) =>
        List.generate(n, (k) => '.$prefix$k { display: block }').join();
    final exact = _index([
      ('a.css', rules(19999, 'a')),
      ('b.css', rules(1, 'b')),
    ]);
    expect(exact.length, maxRulesPerSection);
    expect(exact.truncatedAt, isNull);
    final over = _index([
      ('a.css', rules(19999, 'a')),
      ('b.css', rules(2, 'b')),
    ]);
    expect(over.length, maxRulesPerSection);
    expect(over.truncatedAt, 'b.css');
    expect(over.byClass('b0'), hasLength(1));
    expect(over.byClass('b1'), isEmpty);
  });

  test('índice da folha padrão: montado uma vez, origem userAgent', () {
    expect(identical(userAgentIndex, userAgentIndex), isTrue);
    expect(userAgentIndex.truncatedAt, isNull);
    expect(userAgentIndex.byTag('nobr').single.origin, CssOrigin.userAgent);
    expect(userAgentIndex.byTag('li'), hasLength(6));
    expect(
      userAgentIndex.length,
      userAgentSheet.rules.fold<int>(0, (n, r) => n + r.selectors.length),
    );
  });

  test('listas não modificáveis', () {
    final i = _index([('a.css', 'p { display: block }')]);
    expect(() => i.byTag('p').clear(), throwsUnsupportedError);
    expect(() => i.universal.clear(), throwsUnsupportedError);
  });
}
