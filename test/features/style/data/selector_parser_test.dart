import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/features/style/data/css_tokenizer.dart';
import 'package:galley/src/features/style/data/selector_parser.dart';
import 'package:galley/src/features/style/domain/selector.dart';

/// Tokens de [css] sem espaço nas pontas, como o prelúdio de uma regra.
List<CssToken> prelude(String css) {
  final t = tokenizeCss(css);
  var a = 0;
  var b = t.length;
  while (a < b && t[a].type == CssTokenType.whitespace) {
    a++;
  }
  while (b > a && t[b - 1].type == CssTokenType.whitespace) {
    b--;
  }
  return t.sublist(a, b);
}

List<Selector>? parse(String css, [NamespaceMap ns = NamespaceMap.empty]) =>
    parseSelectorList(prelude(css), ns);

Selector one(String css) {
  final l = parse(css);
  expect(l, isNotNull, reason: css);
  expect(l, hasLength(1), reason: css);
  return l!.single;
}

int spec(int a, int b, int c) => a << 20 | b << 10 | c;

void main() {
  group('especificidade', () {
    test('valores do brief', () {
      expect(one('#a .b c').specificity, spec(1, 1, 1));
      expect(one('p::before').specificity, spec(0, 0, 2));
      expect(one(':not(#x)').specificity, spec(1, 0, 0));
      expect(one('*').specificity, 0);
    });

    test('atributo e pseudo-classe contam como classe', () {
      expect(one('a[href]:hover').specificity, spec(0, 2, 1));
      expect(one('ul li:nth-child(2n+1)').specificity, spec(0, 1, 2));
      expect(one('*|rect').specificity, spec(0, 0, 1));
    });
  });

  group('pseudo-elementos', () {
    test('sintaxe antiga com um dois-pontos', () {
      expect(one('p:before').pseudoElement, PseudoElement.before);
      expect(one('p:after').pseudoElement, PseudoElement.after);
      expect(one('p:first-letter').pseudoElement, PseudoElement.firstLetter);
      expect(one('p::first-line').pseudoElement, PseudoElement.firstLine);
      expect(one('p').pseudoElement, isNull);
    });

    test('só no fim', () {
      expect(parse('p::before span'), isNull);
      expect(parse('p::before.x'), isNull);
      expect(parse('p::before::after'), isNull);
      expect(parse(':not(::before)'), isNull);
      expect(parse('p::desconhecido'), isNull);
    });
  });

  group('validade', () {
    test('inválidos derrubam a lista inteira', () {
      expect(parse('p:nth-child(2 of .x)'), isNull);
      expect(parse(':has(p)'), isNull);
      expect(parse(':is(p)'), isNull);
      expect(parse('p, q:desconhecida'), isNull);
      expect(parse(':not(p.x)'), isNull);
      expect(parse(':not(:not(p))'), isNull);
      expect(parse('foo|p'), isNull);
      expect(parse('[foo|a]'), isNull);
      expect(parse('#1a'), isNull);
      expect(parse('> p'), isNull);
      expect(parse('p >'), isNull);
      expect(parse('p > > q'), isNull);
      expect(parse('p,'), isNull);
      expect(parse(',p'), isNull);
      expect(parse('p q('), isNull);
      expect(parse('[a=]'), isNull);
      expect(parse('[a b]'), isNull);
      expect(parse('[a=b x]'), isNull);
      expect(parse('p.'), isNull);
      expect(parse('p || q'), isNull);
    });

    test('válidos', () {
      expect(parse('p, q'), hasLength(2));
      expect(parse('P'), hasLength(1));
      expect(parse('p:FIRST-CHILD'), hasLength(1));
      expect(parse('A:Hover, a:visited, a:active, a:focus'), hasLength(4));
      expect(parse('a > b + c ~ d e'), hasLength(1));
      expect(parse('a>b+c~d'), hasLength(1));
      expect(parse('[ lang |= "en" ]'), hasLength(1));
      expect(parse('[title=a i]'), hasLength(1));
      expect(parse('*|p, |p, *|*'), hasLength(3));
      expect(parse(':NOT(.x)'), hasLength(1));
      expect(parse(':lang(pt-BR)'), hasLength(1));
    });

    test('prefixo declarado', () {
      const ns = NamespaceMap(prefixes: {'svg': 'http://www.w3.org/2000/svg'});
      expect(parse('svg|rect, svg|*, [svg|x]', ns), hasLength(3));
    });
  });

  group('An+B', () {
    final ok = <String>[
      'odd',
      'EVEN',
      '3',
      '+5',
      '-2',
      'n',
      '+n',
      '-n',
      'N',
      '2n',
      '2n+1',
      '2n + 1',
      '2n- 1',
      '2n -1',
      '2n-1',
      '-n+3',
      '-n-3',
      'n-3',
      '+n-3',
      '+n - 3',
      '-n- 3',
      ' 2n + 1 ',
    ];
    for (final s in ok) {
      test('aceita "$s"', () {
        expect(parse(':nth-child($s)'), isNotNull, reason: s);
      });
    }
    final bad = <String>[
      '2n 3',
      '+ 5',
      '+ n',
      '- n',
      '2n + -1',
      '2n++1',
      '1.5',
      '1.5n',
      'n- -3',
      '',
      'odd 1',
      'foo',
      '2 of p',
    ];
    for (final s in bad) {
      test('rejeita "$s"', () {
        expect(parse(':nth-child($s)'), isNull, reason: s);
      });
    }
  });

  group('chaves do índice', () {
    test('parte mais à direita', () {
      final s = one('div.a #x > p.b.c#y');
      expect(s.rightmostId, 'y');
      expect(s.rightmostClass, 'b');
      expect(s.rightmostType, 'p');
      expect(one('.x').rightmostType, isNull);
      expect(one(':not(.x)').rightmostClass, isNull);
    });

    test('hashes de ancestrais só à esquerda de descendente/filho', () {
      final s = one('div.a #x > span + p');
      expect(s.ancestorHashes.toSet(), {
        SelectorHashes.ofType('div'),
        SelectorHashes.ofClass('a'),
        SelectorHashes.ofId('x'),
      });
      expect(one('p').ancestorHashes, isEmpty);
      expect(one('a ~ p').ancestorHashes, isEmpty);
    });

    test('hash de nome sem caixa ASCII', () {
      expect(SelectorHashes.ofType('P'), SelectorHashes.ofType('p'));
      expect(
        SelectorHashes.ofType('linearGradient'),
        SelectorHashes.ofType('lineargradient'),
      );
      expect(SelectorHashes.ofClass('A'), isNot(SelectorHashes.ofClass('a')));
    });
  });
}
