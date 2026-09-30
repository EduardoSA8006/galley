// parseStyleSheet, parseStyleAttribute e mediaMatches (spec do CSS §5): o
// algoritmo do CSS Syntax Level 3 atual, os casos fechados de §5.3, a
// posição do @import do CSS Cascade 4 §2.2 e o Media Queries 4 §3.
import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/css/parser.dart';
import 'package:galley/src/css/tokenizer.dart';

/// Declarações de todas as regras, `propriedade=valor`, na ordem.
List<String> _decls(StyleSheet s) => [
  for (final r in s.rules)
    for (final d in r.declarations)
      '${d.property.name}=${d.value}${d.important ? '!' : ''}',
];

/// `código/motivo×descartados` de cada `CssIssue`.
List<String> _issues(StyleSheet s) => [
  for (final i in s.issues)
    '${i.code.name}${i.reason == null ? '' : '/${i.reason}'}×${i.discarded}',
];

List<String> _tags(StyleSheet s) => [
  for (final r in s.rules)
    r.selectors.map((x) => x.rightmost.tag ?? '*').join(','),
];

List<CssToken> _tokens(String text) {
  final t = CssTokenizer(text);
  return [for (var k = t.next(); k.type != CssTokenType.eof; k = t.next()) k];
}

void main() {
  group('regras', () {
    test(
      'seletores e declarações na ordem; no topo, espaço, cdo e cdc somem',
      () {
        const css =
            '<!-- p, h1 { font-style: italic; font-weight: bold } --> em{}';
        final s = parseStyleSheet(css);
        expect(_tags(s), ['p,h1', 'em']);
        expect(_decls(s), ['fontStyle=italic', 'fontWeight=700']);
        expect(s.issues, isEmpty);
        expect(s.sourceLength, css.length);
      },
    );

    test('lista parcial: o seletor fora cai, a regra fica', () {
      final s = parseStyleSheet('p.x, p:not(.y), q::before { display: none }');
      expect(_tags(s), ['p']);
      expect(_issues(s), ['cssRuleIgnored/unsupported-selector×2']);
      expect(s.issues.single.details['sample'], 'p:not(.y)');
    });

    test('só seletores fora: a regra some', () {
      final s = parseStyleSheet(
        'a:hover { display: none } p { display: block }',
      );
      expect(_tags(s), ['p']);
      expect(_issues(s), ['cssRuleIgnored/unsupported-selector×1']);
    });

    test('um seletor inválido derruba a regra inteira (parse-error)', () {
      final s = parseStyleSheet(
        'p, :foo { display: none } h1 { display: block }',
      );
      expect(_tags(s), ['h1']);
      expect(_issues(s), ['cssRuleIgnored/parse-error×1']);
      expect(s.issues.single.details['sample'], 'p, :foo');
    });

    test('prelúdio que chega ao fim sem { é descartado', () {
      final s = parseStyleSheet('p { display: block } h1');
      expect(_tags(s), ['p']);
      expect(_issues(s), ['cssRuleIgnored/parse-error×1']);
    });

    test('bloco sem fim vale até o fim do texto', () {
      expect(_decls(parseStyleSheet('p { font-style: italic')), [
        'fontStyle=italic',
      ]);
    });
  });

  group('casos fechados de §5.3 (consume a block\'s contents)', () {
    test('p { .x { … } font-style: italic; color: blue }', () {
      final s = parseStyleSheet(
        'p { .x { font-weight: bold } font-style: italic; color: blue }',
      );
      expect(_decls(s), ['fontStyle=italic']);
      expect(_issues(s), ['cssRuleIgnored/nested-rule×1']);
    });

    test('p { a:hover { … } font-style: italic }', () {
      final s = parseStyleSheet(
        'p { a:hover { font-weight: bold } font-style: italic }',
      );
      expect(_decls(s), ['fontStyle=italic']);
      expect(_issues(s), ['cssRuleIgnored/nested-rule×1']);
    });

    test('a{};p{…}: no topo o ; é prelúdio', () {
      final s = parseStyleSheet('a{};p{font-style: italic}');
      expect(_tags(s), ['a']);
      expect(s.rules.single.declarations, isEmpty);
      expect(_issues(s), ['cssRuleIgnored/parse-error×1']);
    });

    test('p { @media screen { … } font-style: italic }', () {
      final s = parseStyleSheet(
        'p { @media screen { font-weight: bold } font-style: italic }',
      );
      expect(_decls(s), ['fontStyle=italic']);
      expect(_issues(s), ['cssRuleIgnored/nested-rule×1']);
    });

    test('@media screen { @import "x.css"; p { … } }', () {
      final s = parseStyleSheet(
        '@media screen { @import "x.css"; p { font-style: italic } }',
      );
      expect(s.imports, isEmpty);
      expect(_decls(s), ['fontStyle=italic']);
      expect(_issues(s), ['stylesheetIgnored/late-import×1']);
      expect(s.issues.single.details['import'], 'x.css');
    });

    test('p { font-style: italic; @foo; font-weight: bold }', () {
      final s = parseStyleSheet(
        'p { font-style: italic; @foo; font-weight: bold }',
      );
      expect(_decls(s), ['fontStyle=italic', 'fontWeight=700']);
      expect(s.issues, isEmpty);
    });

    test('@import dentro de bloco de estilo: late-import', () {
      final s = parseStyleSheet('p { @import url(x.css); font-style: italic }');
      expect(_decls(s), ['fontStyle=italic']);
      expect(_issues(s), ['stylesheetIgnored/late-import×1']);
    });

    test('lixo até o ; vira parse-error e o resto do bloco segue', () {
      final s = parseStyleSheet(
        'p { 12px; font-style italic; font-weight: bold }',
      );
      expect(_decls(s), ['fontWeight=700']);
      expect(_issues(s), ['cssRuleIgnored/parse-error×2']);
    });

    test('{} no começo do valor: valor inteiro (inclusive com !important)', () {
      final s = parseStyleSheet(
        'p { a: {x}; b: {y} !important; font-style: italic }',
      );
      expect(_decls(s), ['fontStyle=italic']);
      expect(s.issues, isEmpty);
    });

    test(
      '{} no começo seguido de outro token: regra aninhada e o token volta',
      () {
        final s = parseStyleSheet(
          'p { a: {x} font-style: italic; font-weight: bold }',
        );
        // `a: {x}` é regra aninhada; `font-style: italic` é relido como item.
        expect(_decls(s), ['fontStyle=italic', 'fontWeight=700']);
        expect(_issues(s), ['cssRuleIgnored/nested-rule×1']);
      },
    );

    test(
      '{} seguido de ! solto: nested-rule e parse-error, sem perder o ;',
      () {
        final s = parseStyleSheet('p { a: {} !; font-style: italic }');
        expect(_decls(s), ['fontStyle=italic']);
        expect(_issues(s), [
          'cssRuleIgnored/nested-rule×1',
          'cssRuleIgnored/parse-error×1',
        ]);
      },
    );

    test('propriedade customizada vai até o ; e some em silêncio', () {
      final s = parseStyleSheet('p { --x: { a: b } c; font-style: italic }');
      expect(_decls(s), ['fontStyle=italic']);
      expect(s.issues, isEmpty);
    });

    test('badString e badUrl invalidam a declaração (parse-error)', () {
      final s = parseStyleSheet(
        'p { list-style: "a\n; font-style: italic; b: url(a b); '
        'font-weight: bold }',
      );
      expect(_decls(s), ['fontStyle=italic', 'fontWeight=700']);
      expect(_issues(s), ['cssRuleIgnored/parse-error×2']);
    });
  });

  group('valores e !important', () {
    test('{ e ( no meio do valor são consumidos inteiros', () {
      final s = parseStyleSheet(
        'p { font-family: f(a;b); font-style: italic }',
      );
      expect(_decls(s), ['fontStyle=italic']);
    });

    test('!important com espaço, comentário e caixa', () {
      final s = parseStyleSheet(
        'p { display: block ! /* x */ IMPORTANT; font-style: italic!important }',
      );
      expect(_decls(s), ['display=block!', 'fontStyle=italic!']);
    });

    test('! no meio do valor invalida em silêncio', () {
      expect(_decls(parseStyleSheet('p { display: ! block }')), isEmpty);
    });
  });

  group('at-rules (§5.1)', () {
    test('nomes sem diferença de caixa', () {
      final s = parseStyleSheet(
        '@IMPORT "a.css"; @MEDIA SCREEN { p { display: block } }',
      );
      expect(s.imports.map((i) => i.href), ['a.css']);
      expect(_tags(s), ['p']);
    });

    test('@media que casa entra como se estivesse fora; aninhado filtra', () {
      final s = parseStyleSheet(
        '@media screen { p { display: block } @media print { h1 { display: '
        'none } } @media all { h2 { display: none } } } em { display: block }',
      );
      expect(_tags(s), ['p', 'h2', 'em']);
      expect(_issues(s), ['stylesheetMediaIgnored×1']);
      expect(s.issues.single.details['media'], 'print');
    });

    test('@media que não casa: agregado por folha', () {
      final s = parseStyleSheet(
        '@media print { p { display: none } } '
        '@media (prefers-color-scheme: dark) { p { display: none } }',
      );
      expect(s.rules, isEmpty);
      expect(_issues(s), ['stylesheetMediaIgnored×2']);
    });

    test('at-rules descartadas em silêncio', () {
      final s = parseStyleSheet(
        '@charset "utf-8"; @namespace epub "x"; @font-face { src: url(a) } '
        '@page { margin: 1em } @supports (display: flex) { p { display: flex } } '
        '@-webkit-keyframes k { from { x: y } } @layer a { p { x: y } } '
        '@foo bar { } @bar; p { display: block }',
      );
      expect(_tags(s), ['p']);
      expect(s.issues, isEmpty);
    });
  });

  group('@import (§5.2, CSS Cascade 4 §2.2)', () {
    List<String> imports(String css) => [
      for (final i in parseStyleSheet(css).imports) i.href,
    ];

    test('string, url sem aspas e url com aspas', () {
      expect(
        imports('@import "a.css"; @import url(b.css); @import url("c.css");'),
        ['a.css', 'b.css', 'c.css'],
      );
    });

    test('depois de @charset vale; depois de regra não (late-import)', () {
      expect(imports('@charset "utf-8"; @import "a.css";'), ['a.css']);
      final s = parseStyleSheet('p { } @import "a.css";');
      expect(s.imports, isEmpty);
      expect(_issues(s), ['stylesheetIgnored/late-import×1']);
    });

    test('depois de regra parse-error vale (a regra não é válida)', () {
      expect(imports(':foo { } @import "a.css";'), ['a.css']);
    });

    test('depois de regra só com seletores fora do subconjunto não vale', () {
      expect(imports('a:hover { } @import "a.css";'), isEmpty);
    });

    test('depois de @namespace não vale; depois de @layer sem bloco vale', () {
      expect(imports('@namespace x "y"; @import "a.css";'), isEmpty);
      expect(imports('@layer a, b; @import "a.css";'), ['a.css']);
      expect(imports('@layer a { } @import "a.css";'), isEmpty);
      expect(imports('@foo; @import "a.css";'), ['a.css']);
    });

    test('@layer sem bloco entre dois @import invalida o seguinte', () {
      expect(imports('@layer x; @import "a.css"; @import "b.css";'), [
        'a.css',
        'b.css',
      ]);
      expect(imports('@import "a.css"; @layer x; @import "b.css";'), ['a.css']);
    });

    test('at-rule conhecida mas inválida não tira o @import de posição', () {
      for (final at in ['@font-face;', '@page;', '@supports foo { }']) {
        expect(imports('$at @import "a.css";'), ['a.css'], reason: at);
      }
      expect(imports('@supports (a: b) { } @import "a.css";'), isEmpty);
    });

    test(
      'at-rules que o Chromium não conhece não tiram o @import de posição',
      () {
        for (final at in [
          '@-moz-document url-prefix() { p { } }',
          '@document url(x) { p { } }',
          '@viewport { width: device-width }',
          '@-ms-viewport { width: device-width }',
          '@-moz-keyframes k { from { } }',
        ]) {
          expect(imports('$at @import "a.css";'), ['a.css'], reason: at);
        }
        for (final at in [
          '@-webkit-keyframes k { from { } }',
          '@keyframes k { from { } }',
          '@font-face { font-family: a }',
        ]) {
          expect(imports('$at @import "a.css";'), isEmpty, reason: at);
        }
      },
    );

    test(
      'media que casa vale; que não casa vai para stylesheetMediaIgnored',
      () {
        expect(imports('@import "a.css" screen;'), ['a.css']);
        final s = parseStyleSheet('@import url(x.css) print; @import "b.css";');
        expect(s.imports.map((i) => i.href), ['b.css']);
        expect(_issues(s), ['stylesheetMediaIgnored×1']);
        expect(s.issues.single.details, {'media': 'print', 'import': 'x.css'});
      },
    );

    test('layer, layer() e supports(): unsupported-import', () {
      final s = parseStyleSheet(
        '@import "a.css" layer; @import "b.css" layer(x); '
        '@import "c.css" supports(display: grid); @import "d.css";',
      );
      expect(s.imports.map((i) => i.href), ['d.css']);
      expect(_issues(s), ['stylesheetIgnored/unsupported-import×3']);
    });

    test('prelúdio sem string nem url: parse-error', () {
      final s = parseStyleSheet('@import a.css; @import url("a" x);');
      expect(s.imports, isEmpty);
      expect(_issues(s), ['cssRuleIgnored/parse-error×2']);
    });
  });

  group('@namespace (CSS Namespaces 3)', () {
    test(
      'prefixo declarado vale nos seletores; não declarado derruba a regra',
      () {
        final ok = parseStyleSheet(
          '@namespace epub "http://www.idpf.org/2007/ops"; '
          '[epub|type="noteref"] { display: block }',
        );
        expect(ok.rules, hasLength(1));
        expect(ok.issues, isEmpty);
        final none = parseStyleSheet(
          '[epub|type="noteref"], p { display: block }',
        );
        expect(none.rules, isEmpty);
        expect(_issues(none), ['cssRuleIgnored/parse-error×1']);
      },
    );

    test('regra inválida antes não fecha os @namespace (como no Chromium)', () {
      final s = parseStyleSheet(
        'p!{} @namespace epub "x"; [epub|type="n"] { display: block }',
      );
      expect(s.rules, hasLength(1));
      expect(
        s.rules.single.selectors.single.rightmost.attributes.single.name,
        'epub:type',
      );
    });

    test('@namespace com lixo é inválido e não registra o prefixo', () {
      final s = parseStyleSheet(
        '@namespace epub "x" junk; [epub|type="n"] { display: block }',
      );
      expect(s.rules, isEmpty);
      expect(_issues(s), ['cssRuleIgnored/parse-error×1']);
      expect(
        parseStyleSheet('@namespace epub "x" junk; @import "a.css";').imports,
        hasLength(1),
      );
    });

    test('@namespace fora de posição não declara nada', () {
      final late = parseStyleSheet(
        'p { } @namespace epub "x"; [epub|type="n"] { display: block }',
      );
      expect(_tags(late), ['p']);
      expect(_issues(late), ['cssRuleIgnored/parse-error×1']);
      final url = parseStyleSheet(
        '@charset "utf-8"; @import "a.css"; @namespace e url(x); '
        '[e|t="n"] { display: block }',
      );
      expect(url.rules, hasLength(1));
      expect(url.imports, hasLength(1));
    });
  });

  group('aninhamento (§5.4)', () {
    test('32 blocos abertos valem; o 33º entra em salto com limit', () {
      String nested(int blocks) =>
          'p { a: ${'f(' * (blocks - 1)}${')' * (blocks - 1)}; '
          'font-style: italic }';
      final ok = parseStyleSheet(nested(32));
      expect(_decls(ok), ['fontStyle=italic']);
      expect(ok.issues, isEmpty);
      final over = parseStyleSheet(nested(33));
      expect(_decls(over), ['fontStyle=italic']);
      expect(_issues(over), ['stylesheetIgnored/limit×1']);
      expect(over.issues.single.details, {'limit': 'nesting'});
    });

    test('declaração que falha com mais de 32 níveis não engole a folha', () {
      final deep = '(' * 40 + ')' * 40;
      for (final decl in [
        'a: b {$deep} x',
        'a: {$deep} x',
        'a: f($deep) {x}',
        'a: {$deep} !; x',
      ]) {
        final s = parseStyleSheet(
          'p { $decl font-style: italic } h1 { display: block }',
        );
        expect(_tags(s), ['p', 'h1'], reason: decl);
        expect(_decls(s), contains('display=block'), reason: decl);
        expect(
          s.issues.where((i) => i.reason == 'limit').single.discarded,
          1,
          reason: decl,
        );
      }
      final s = parseStyleSheet(
        'p { a: b {$deep} font-style: italic } h1 { display: block }',
      );
      expect(_decls(s), ['fontStyle=italic', 'display=block']);
    });

    test('prelúdio e bloco acima do limite: um limit só', () {
      final deep = '(' * 40 + ')' * 40;
      final s = parseStyleSheet('p $deep { a: $deep } h1 { display: block }');
      expect(_tags(s), ['h1']);
      expect(_issues(s), ['stylesheetIgnored/limit×1']);
    });

    test('@media aninhado 32 vezes vale; 33 salta', () {
      String media(int n) =>
          '${'@media all { ' * (n - 1)}p { display: block }${' }' * (n - 1)}';
      expect(_tags(parseStyleSheet(media(32))), ['p']);
      final over = parseStyleSheet(media(33));
      expect(over.rules, isEmpty);
      expect(_issues(over), ['stylesheetIgnored/limit×1']);
    });

    test(') solto dentro de { é só um token', () {
      final s = parseStyleSheet('p { a: ) ; font-style: italic }');
      expect(_decls(s), ['fontStyle=italic']);
    });
  });

  group('agregação (§12.1)', () {
    test('um CssIssue por (código, motivo), com o primeiro como amostra', () {
      final s = parseStyleSheet(
        ':foo { } :bar { } p { .x { } } a:hover { } b:hover { }',
      );
      expect(_issues(s), [
        'cssRuleIgnored/parse-error×2',
        'cssRuleIgnored/nested-rule×1',
        'cssRuleIgnored/unsupported-selector×2',
      ]);
      expect(s.issues.first.details['sample'], ':foo');
    });

    test('amostra truncada em 64', () {
      final s = parseStyleSheet('${'a' * 100}:foo { }');
      expect(
        (s.issues.single.details['sample']! as String).length,
        maxSampleLength,
      );
    });
  });

  group('parseStyleAttribute', () {
    test('declarações, sem seletor; erros de sintaxe somados', () {
      final (d, errors) = parseStyleAttribute(
        'font-style: italic; 12px; a{b}; display: none; color: red',
      );
      expect([for (final x in d) x.property.name], ['fontStyle', 'display']);
      expect(errors, 2);
    });

    test('} termina a lista', () {
      final (d, _) = parseStyleAttribute('display: none } font-style: italic');
      expect(d.single.property.name, 'display');
    });

    test('vazio e só espaço', () {
      expect(parseStyleAttribute('').$1, isEmpty);
      expect(parseStyleAttribute('   ;; ').$2, 0);
    });
  });

  group('mediaMatches (Media Queries 4)', () {
    for (final (media, expected) in [
      ('', true),
      ('   ', true),
      ('all', true),
      ('screen', true),
      ('SCREEN', true),
      ('only screen', true),
      ('only all', true),
      ('screen, print', true),
      ('print', false),
      ('speech', false),
      ('not print', true),
      ('not screen', false),
      ('not all', false),
      ('not amzn-kf8', true),
      ('not only', false),
      ('amzn-kf8', false),
      ('screen and (max-width: 600px)', false),
      ('(prefers-color-scheme: dark)', false),
      ('(a, b), screen', true),
      ('screen and (a, b)', false),
      ('screen, , print', true),
      ('print, ,', false),
      ('only', false),
      ('screen print', false),
      ('screen;', false),
      ('f(screen)', false),
      ('"screen"', false),
    ]) {
      test('"$media" → $expected', () {
        expect(mediaMatches(_tokens(media)), expected);
        expect(mediaAttributeMatches(media), expected);
      });
    }

    test('media ausente casa', () {
      expect(mediaAttributeMatches(null), isTrue);
    });
  });

  group('hostis (§14.3): linear', () {
    void linear(String name, void Function() body) {
      test(name, () {
        final sw = Stopwatch()..start();
        body();
        sw.stop();
        expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
      });
    }

    linear('p { a:b{} … } com 100 000 itens sem ;', () {
      final s = parseStyleSheet('p { ${'a:b{} ' * 100000}font-style: italic }');
      expect(_decls(s), ['fontStyle=italic']);
      expect(_issues(s), ['cssRuleIgnored/nested-rule×100000']);
    });

    linear('o mesmo num style="" de 8 KiB', () {
      final (d, errors) = parseStyleAttribute('a:b{}' * (8 * 1024 ~/ 5));
      expect(d, isEmpty);
      expect(errors, 8 * 1024 ~/ 5);
    });

    linear('{, ( e [ repetidos 500 000 vezes', () {
      for (final c in ['{', '(', '[']) {
        final s = parseStyleSheet('p ${c * 500000}');
        expect(_decls(s), isEmpty);
        expect(_issues(s), contains('stylesheetIgnored/limit×1'));
      }
      final s = parseStyleSheet('p { a: ${'(' * 500000} }');
      expect(_issues(s), ['stylesheetIgnored/limit×1']);
    });

    linear('folha com a a … b de 200 000 compostos; e terminando em :foo', () {
      final chain = '${'a ' * 200000}b';
      expect(_issues(parseStyleSheet('$chain { display: block }')), [
        'cssRuleIgnored/unsupported-selector×1',
      ]);
      expect(_issues(parseStyleSheet('$chain:foo { display: block }')), [
        'cssRuleIgnored/parse-error×1',
      ]);
    });

    linear('um milhão de regras inválidas: um CssIssue', () {
      final s = parseStyleSheet(':foo{}' * 1000000);
      expect(_issues(s), ['cssRuleIgnored/parse-error×1000000']);
    });

    linear('250 000 @import depois de regra: um CssIssue', () {
      final s = parseStyleSheet('p{}${'@import "a.css";' * 250000}');
      expect(_issues(s), ['stylesheetIgnored/late-import×250000']);
    });

    linear('mil blocos de 1 000 declarações lixo', () {
      final s = parseStyleSheet('p { ${'x y; ' * 1000} }' * 1000);
      expect(_issues(s), ['cssRuleIgnored/parse-error×1000000']);
    });
  });
}
