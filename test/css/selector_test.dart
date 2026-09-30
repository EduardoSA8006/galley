// parseSelectorList: o subconjunto de §6.1, os três destinos de §6.3, a
// especificidade do Selectors 4 §17 e os hashes de ancestral de §10.4.
import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/css/selector.dart';
import 'package:galley/src/css/tokenizer.dart';

List<CssToken> _tokens(String text) {
  final t = CssTokenizer(text);
  return [for (var k = t.next(); k.type != CssTokenType.eof; k = t.next()) k];
}

SelectorListParse _parse(String text, {Set<String> ns = const {}}) =>
    parseSelectorList(_tokens(text), namespaces: ns);

/// O único seletor, que precisa estar no subconjunto.
Selector _one(String text, {Set<String> ns = const {}}) {
  final r = _parse(text, ns: ns);
  expect(r, isA<SelectorList>(), reason: text);
  final list = r as SelectorList;
  expect(list.unsupported, 0, reason: text);
  return list.selectors.single;
}

/// Destino de cada seletor de uma lista de um item só.
String _fate(String text, {Set<String> ns = const {}}) =>
    switch (_parse(text, ns: ns)) {
      SelectorInvalid() => 'invalid',
      SelectorList(:final selectors) when selectors.isNotEmpty => 'supported',
      SelectorList() => 'unsupported',
    };

(int, int, int) _spec(String text) {
  final s = _one(text).specificity;
  return (s >> 20, (s >> 10) & 1023, s & 1023);
}

void main() {
  group('subconjunto (§6.1)', () {
    test('tipo: minúsculas em tag, como escrito em tagAsWritten', () {
      final k = _one('P').rightmost;
      expect(k.tag, 'p');
      expect(k.tagAsWritten, 'P');
      expect(_one('foreignObject').rightmost.tagAsWritten, 'foreignObject');
    });

    test('universal, classe e id', () {
      expect(_one('*').rightmost.tag, isNull);
      final k = _one('p.nota.Outra#x').rightmost;
      expect(k.classes, ['nota', 'Outra']);
      expect(k.id, 'x');
    });

    test('atributo com string, ident e prefixo', () {
      expect(_one('[a="v"]').rightmost.attributes.single.value, 'v');
      final a = _one('[Data-X=v]').rightmost.attributes.single;
      expect((a.name, a.nameAsWritten, a.value), ('data-x', 'Data-X', 'v'));
      expect(
        _one(
          '[epub|type="noteref"]',
          ns: {'epub'},
        ).rightmost.attributes.single.name,
        'epub:type',
      );
      expect(_one('[|a=v]').rightmost.attributes.single.name, 'a');
    });

    test('combinadores descendente, > e +, com e sem espaço', () {
      expect(_one('a b').combinators, [CssCombinator.descendant]);
      expect(_one('a>b').combinators, [CssCombinator.child]);
      expect(_one('a > b + c').combinators, [
        CssCombinator.child,
        CssCombinator.adjacent,
      ]);
      expect(_one('a  +  b').compounds.map((k) => k.tag), ['a', 'b']);
    });

    test(':first-child, :last-child e :nth-child inteiro', () {
      expect(_one(':first-child').rightmost.firstChild, isTrue);
      expect(_one('li:last-child').rightmost.lastChild, isTrue);
      expect(_one(':nth-child(3)').rightmost.nthChild, 3);
      expect(_one(':nth-child( +3 )').rightmost.nthChild, 3);
    });

    test(':nth-child fora da faixa guarda 0 (nunca casa)', () {
      expect(_one(':nth-child(0)').rightmost.nthChild, 0);
      expect(_one(':nth-child(-2)').rightmost.nthChild, 0);
      expect(_one(':nth-child(1073741824)').rightmost.nthChild, 1 << 30);
      expect(_one(':nth-child(1073741825)').rightmost.nthChild, 0);
      expect(_one(':nth-child(99999999999)').rightmost.nthChild, 0);
      // Expoente não é <integer> no An+B (CSS Syntax §6.2): inválido, sem
      // passar pelo double infinito de CssToken.number.
      expect(_fate(':nth-child(1e999)'), 'invalid');
      expect(_fate(':nth-child(n+1e999)'), 'invalid');
      // Literal de mais de 64 unidades vira NaN no tokenizador (§4, não
      // infinito): fora da faixa, :nth-child guarda 0 e nunca casa.
      expect(_one(':nth-child(${'9' * 400})').rightmost.nthChild, 0);
      expect(_one(':nth-child(-${'9' * 400})').rightmost.nthChild, 0);
      expect(_fate(':nth-child(n+${'9' * 400})'), 'unsupported');
    });

    test('pseudo-classe sem diferença de caixa', () {
      expect(_one(':FIRST-CHILD').rightmost.firstChild, isTrue);
      expect(_one(':Nth-Child(2)').rightmost.nthChild, 2);
    });
  });

  group('válido fora do subconjunto (§6.3)', () {
    for (final s in [
      'a ~ b',
      ':hover',
      'a:link',
      ':root',
      ':before',
      '::before',
      '::BEFORE',
      'q::after',
      ':not(.x)',
      ':is(a, b)',
      ':where(p)',
      ':has(> img)',
      ':lang(en)',
      ':dir(rtl)',
      ':not(p.x)',
      ':is()',
      ':where()',
      ':is(:foo)',
      'p::before::marker',
      '*|*',
      ':nth-child(odd)',
      ':nth-child(EVEN)',
      ':nth-child(2n+1)',
      ':nth-child(2n + 1)',
      ':nth-child(2n- 1)',
      ':nth-child(-n+3)',
      ':nth-child(+n)',
      ':nth-child(n)',
      ':nth-child(n-1)',
      ':nth-child(3 of p)',
      ':nth-child(n of p::before)',
      ':nth-last-child(1)',
      ':nth-of-type(2)',
      '[href]',
      '[a~=b]',
      '[a|=b]',
      '[a^=b]',
      r'[a$=b]',
      '[a*=b]',
      '[a=b i]',
      '[a=b S]',
      '[*|a=b]',
      '*|p',
      '|p',
      '::cue(b)',
    ]) {
      test(s, () => expect(_fate(s), 'unsupported'));
    }
  });

  group('inválido (§6.3): a regra inteira cai', () {
    for (final s in [
      ':foo',
      '::-moz-x',
      ':-webkit-any(a)',
      '::foo',
      ':nth-child(3.0)',
      ':nth-child(foo)',
      ':nth-child()',
      ':nth-child(+ 3)',
      ':nth-child(n of)',
      ':nth-of-type(2 of p)',
      ':first-child()',
      ':not',
      'a,,b',
      'a,',
      ',a',
      'a >',
      '> a',
      'a >> b',
      'a || b',
      'a||b',
      '#1a',
      '.',
      '.1a',
      '[a',
      '[a~b]',
      '[a="v" x]',
      '[a="v" ii]',
      '[1=a]',
      'p::before.x',
      'p::before:hover',
      'a:before:hover',
      'p::before:first-child',
      'p::before::after',
      'p::before span',
      'p::before > span',
      ':not()',
      ':has()',
      ':lang()',
      ':dir()',
      ':not(:foo)',
      ':not(p::before)',
      ':not(p:before)',
      ':nth-child(2n of 1+)',
      ':nth-child(n of :foo)',
      'ns|p',
      'ns|*',
      '[ns|a=b]',
      '[epub|type="x"]',
      '"x"',
      'a;',
      'a {',
      'p:not(',
    ]) {
      test(s, () => expect(_fate(s), 'invalid'));
    }
  });

  group('lista (§6.3)', () {
    test('um seletor fora cai sozinho; os outros ficam', () {
      final r = _parse('p.x, p:not(.y) , h1') as SelectorList;
      expect(r.selectors.map((s) => s.rightmost.tag), ['p', 'h1']);
      expect(r.unsupported, 1);
      expect(r.unsupportedSample, 'p:not(.y)');
    });

    test('todos fora: lista válida e vazia', () {
      final r = _parse('a:hover, b::after') as SelectorList;
      expect(r.selectors, isEmpty);
      expect(r.unsupported, 2);
    });

    test('inválidos do Chromium derrubam a lista toda', () {
      for (final s in [
        'p::before span, q',
        'ns|p, q',
        ':nth-child(2n of 1+), q',
        ':not(p::before), q',
      ]) {
        expect(_parse(s), isA<SelectorInvalid>(), reason: s);
      }
    });

    test('prefixo declarado por @namespace vale', () {
      expect(_fate('svg|rect', ns: {'svg'}), 'unsupported');
      expect(_fate('[epub|type="x"]', ns: {'epub'}), 'supported');
      expect(_fate('[epub|type="x"]', ns: {'svg'}), 'invalid');
    });

    test('um inválido derruba a lista com os válidos', () {
      final r = _parse('p, :foo, h1');
      expect(r, isA<SelectorInvalid>());
      expect((r as SelectorInvalid).sample, 'p, :foo, h1');
    });
  });

  group('limites (§6.3)', () {
    test('32 compostos no subconjunto; 33 fora', () {
      expect(_one(List.filled(32, 'a').join(' ')).compounds, hasLength(32));
      expect(_fate(List.filled(33, 'a').join(' ')), 'unsupported');
    });

    test(
      '33 compostos e depois :foo: inválido (a gramática vai até o fim)',
      () {
        expect(_fate('${List.filled(33, 'a').join(' ')} :foo'), 'invalid');
      },
    );

    test('32 seletores simples num composto; 33 fora', () {
      expect(_one('p${'.c' * 31}').rightmost.classes, hasLength(31));
      expect(_fate('p${'.c' * 32}'), 'unsupported');
      expect(_fate('.c' * 33), 'unsupported');
    });

    test('identificador e valor de atributo: 256 no subconjunto; 257 fora', () {
      for (final (ok, over) in [
        ('.${'a' * 256}', '.${'a' * 257}'),
        ('#${'a' * 256}', '#${'a' * 257}'),
        ('${'a' * 256} b', '${'a' * 257} b'),
        ('[${'a' * 256}=v]', '[${'a' * 257}=v]'),
        ('[a="${'v' * 256}"]', '[a="${'v' * 257}"]'),
      ]) {
        expect(_fate(ok), 'supported', reason: ok.substring(0, 3));
        expect(_fate(over), 'unsupported', reason: over.substring(0, 3));
      }
    });
  });

  group('repetição no mesmo composto', () {
    test(':nth-child diferentes nunca casam; iguais valem', () {
      expect(_one('li:nth-child(2):nth-child(3)').rightmost.nthChild, 0);
      expect(_one('li:nth-child(2):nth-child(2)').rightmost.nthChild, 2);
    });

    test('#a#b é válido, fica no subconjunto e nunca casa', () {
      final k = _one('#a#b').rightmost;
      expect(k.impossible, isTrue);
      expect(_one('#a#a').rightmost.impossible, isFalse);
    });

    test('a especificidade conta cada seletor simples', () {
      expect(_spec('li:first-child:first-child'), (0, 2, 1));
      expect(_spec('#a#a'), (2, 0, 0));
      expect(_spec('.x.x'), (0, 2, 0));
    });
  });

  group('especificidade (Selectors 4 §17)', () {
    test('exemplos do padrão', () {
      expect(_spec('*'), (0, 0, 0));
      expect(_spec('li'), (0, 0, 1));
      expect(_spec('ul li'), (0, 0, 2));
      expect(_spec('ul ol+li'), (0, 0, 3));
      expect(_spec('h1 + *[rel=up]'), (0, 1, 1));
      expect(_spec('ul ol li.red'), (0, 1, 3));
      expect(_spec('li.red.level'), (0, 2, 1));
      expect(_spec('#x34y'), (1, 0, 0));
      expect(_spec('p:first-child'), (0, 1, 1));
      expect(_spec('li:nth-child(2)'), (0, 1, 1));
    });

    test('cada componente satura em 1023', () {
      // 32 compostos de 32 classes: b seria 1024.
      final big = List.filled(32, '.a' * 32).join(' ');
      expect(_spec(big), (0, 1023, 0));
    });
  });

  group('hashes de ancestral (§10.4)', () {
    int tag(String s) => bloomHash(bloomKindTag, s);

    test('a > b + c: a é ancestral de c', () {
      expect(_one('a > b + c').ancestorHashes, [tag('a')]);
    });

    test('a + b c: só b é ancestral', () {
      expect(_one('a + b c').ancestorHashes, [tag('b')]);
    });

    test('id, classes e tipo em minúsculas; no máximo 4', () {
      expect(_one('A.X#Y.Z p').ancestorHashes, [
        bloomHash(bloomKindId, 'y'),
        bloomHash(bloomKindClass, 'x'),
        bloomHash(bloomKindClass, 'z'),
        tag('a'),
      ]);
      expect(_one('a b c d e f').ancestorHashes, [
        tag('e'),
        tag('d'),
        tag('c'),
        tag('b'),
      ]);
    });

    test('seletor sem ancestral obrigatório: vazio', () {
      expect(_one('p').ancestorHashes, isEmpty);
      expect(_one('h1 + p').ancestorHashes, isEmpty);
    });
  });

  group('hostis (§14.3): linear', () {
    test('a a … b com 200 000 compostos; e terminando em :foo', () {
      final sw = Stopwatch()..start();
      final chain = '${'a ' * 200000}b';
      expect(_fate(chain), 'unsupported');
      expect(_fate('$chain:foo'), 'invalid');
      sw.stop();
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('.a.b.c… com 200 000 classes', () {
      final sw = Stopwatch()..start();
      expect(_fate('.c' * 200000), 'unsupported');
      sw.stop();
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('classe, id e valor de atributo de 1 MiB', () {
      final big = 'x' * (1024 * 1024);
      final sw = Stopwatch()..start();
      expect(_fate('.$big'), 'unsupported');
      expect(_fate('#$big'), 'unsupported');
      expect(_fate('[a="$big"]'), 'unsupported');
      sw.stop();
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('lista de 100 000 seletores; :is( e :not( com 100 000 níveis', () {
      final sw = Stopwatch()..start();
      final list = _parse(List.filled(100000, 'p').join(',')) as SelectorList;
      expect(list.selectors, hasLength(100000));
      expect(_fate(':is(${'(' * 100000}${')' * 100000})'), 'unsupported');
      // :not( aninhado é validado por nível até 32: além disso, inválido.
      expect(_fate('${':not(' * 32}p${')' * 32}'), 'unsupported');
      expect(_fate('${':not(' * 33}p${')' * 33}'), 'invalid');
      // O `of` do :nth-child é outro nível da mesma conta.
      expect(
        _fate(':nth-child(1 of ${':not(' * 31}p${')' * 31})'),
        'unsupported',
      );
      expect(_fate(':nth-child(1 of ${':not(' * 32}p${')' * 32})'), 'invalid');
      expect(_fate('${':not(' * 100000}p${')' * 100000}'), 'invalid');
      sw.stop();
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
    });
  });
}
