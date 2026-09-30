// Casamento de seletores (spec do CSS §10.4): combinadores do Selectors 4
// §16, irmãos-elemento, caixa, namespace, os passos contados e o filtro de
// Bloom.
import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/css/matcher.dart';
import 'package:galley/src/css/selector.dart';
import 'package:galley/src/css/tokenizer.dart';
import 'package:html/parser.dart' as html;

Selector _selector(String text) {
  final t = CssTokenizer(text);
  final tokens = [
    for (var k = t.next(); k.type != CssTokenType.eof; k = t.next()) k,
  ];
  return (parseSelectorList(
    tokens,
    namespaces: const {'epub'},
  ) as SelectorList).selectors.single;
}

/// ElementInfo de cada elemento com `id`, montados como a cascata monta.
Map<String, ElementInfo> _infos(String body) {
  final document = html.parse(
    '<html xmlns="http://www.w3.org/1999/xhtml"><body>$body</body></html>',
  );
  final out = <String, ElementInfo>{};
  final stack = [ElementInfo.root(document.documentElement!)];
  while (stack.isNotEmpty) {
    final e = stack.removeLast();
    final id = e.id;
    if (id != null) out[id] = e;
    stack.addAll(e.children());
  }
  return out;
}

bool _matches(String selector, Map<String, ElementInfo> infos, String id) =>
    matchSelector(_selector(selector), infos[id]!, MatchSteps(1 << 30));

void main() {
  group('combinadores (Selectors 4 §16)', () {
    final infos = _infos(
      '<div id="d"><p id="p1">a</p> texto <!-- c --> <p id="p2">b</p>'
      '<section id="s"><p id="p3">c</p></section></div><h1 id="h"></h1>',
    );

    test(
      '+ olha o irmão-elemento anterior (texto e comentário não contam)',
      () {
        expect(_matches('p + p', infos, 'p2'), isTrue);
        expect(_matches('p + p', infos, 'p1'), isFalse);
        expect(_matches('h1 + p', infos, 'p2'), isFalse);
        expect(_matches('div + h1', infos, 'h'), isTrue);
      },
    );

    test('> só o pai; descendente qualquer ancestral', () {
      expect(_matches('div > p', infos, 'p1'), isTrue);
      expect(_matches('div > p', infos, 'p3'), isFalse);
      expect(_matches('div p', infos, 'p3'), isTrue);
      expect(_matches('body div section p', infos, 'p3'), isTrue);
      expect(_matches('section div p', infos, 'p3'), isFalse);
    });

    test('mistura: a > b + c e a + b c', () {
      expect(_matches('div > p + p', infos, 'p2'), isTrue);
      expect(_matches('div > p + section > p', infos, 'p3'), isTrue);
      expect(_matches('p + section p', infos, 'p3'), isTrue);
      expect(_matches('p + div p', infos, 'p3'), isFalse);
    });

    test('estados aninhados: o descendente segue depois de + e > falharem', () {
      final nested = _infos(
        '<h1></h1><div><div><p id="q">t</p></div></div>'
        '<section><div><div><p id="r">t</p></div></div></section>',
      );
      // `+` sem irmão no div de dentro é failsAllSiblings, não
      // failsCompletely: o descendente tenta o div de fora, cujo irmão
      // anterior é o h1 (Selectors 4 §16; SelectorChecker do Blink).
      expect(_matches('h1 + div p', nested, 'q'), isTrue);
      // `>` com o pai errado (div > div) é failsLocally: o descendente tenta
      // o div de fora, filho do body.
      expect(_matches('body > div p', nested, 'q'), isTrue);
      expect(_matches('body > div p', nested, 'r'), isFalse);
    });
  });

  group('pseudo-classes estruturais', () {
    final infos = _infos(
      '<ul> texto <li id="a"></li><li id="b"></li>'
      '<!-- c --><li id="c"></li> fim </ul>',
    );

    test(':first-child, :last-child e :nth-child contam só elementos', () {
      expect(_matches('li:first-child', infos, 'a'), isTrue);
      expect(_matches('li:first-child', infos, 'b'), isFalse);
      expect(_matches('li:last-child', infos, 'c'), isTrue);
      expect(_matches(':nth-child(2)', infos, 'b'), isTrue);
      expect(_matches(':nth-child(3)', infos, 'c'), isTrue);
      expect(_matches(':nth-child(0)', infos, 'a'), isFalse);
    });

    test('a raiz é :first-child (Selectors 4 não exige pai)', () {
      final root = ElementInfo.root(
        html.parse('<html><body></body></html>').documentElement!,
      );
      expect(
        matchSelector(_selector('html:first-child'), root, MatchSteps(9)),
        isTrue,
      );
    });
  });

  group('caixa e namespace (§6.1)', () {
    final infos = _infos(
      '<p id="p" class="Nota x" epub:type="noteref" data-x="Um">t</p>'
      '<svg id="svg" xmlns="http://www.w3.org/2000/svg">'
      '<foreignObject id="fo" viewBox="0 0 1 1"/></svg>',
    );

    test('classe e id com diferença de caixa', () {
      expect(_matches('.Nota', infos, 'p'), isTrue);
      expect(_matches('.nota', infos, 'p'), isFalse);
      expect(_matches('#p', infos, 'p'), isTrue);
      expect(_matches('#P', infos, 'p'), isFalse);
    });

    test('tipo sem caixa no HTML; exato fora dele', () {
      expect(_matches('P', infos, 'p'), isTrue);
      expect(_matches('foreignObject', infos, 'fo'), isTrue);
      expect(_matches('foreignobject', infos, 'fo'), isFalse);
    });

    test('atributo: nome sem caixa no HTML, exato fora; valor exato', () {
      expect(_matches('[epub|type="noteref"]', infos, 'p'), isTrue);
      expect(_matches('[DATA-X="Um"]', infos, 'p'), isTrue);
      expect(_matches('[data-x="um"]', infos, 'p'), isFalse);
      expect(_matches('[viewBox="0 0 1 1"]', infos, 'fo'), isTrue);
      expect(_matches('[viewbox="0 0 1 1"]', infos, 'fo'), isFalse);
    });

    test('#a#b e :nth-child repetido diferente nunca casam', () {
      final e = _infos('<p id="a">t</p>')['a']!;
      final steps = MatchSteps(1 << 30);
      expect(matchSelector(_selector('#a#b'), e, steps), isFalse);
      expect(matchSelector(_selector('#a#a'), e, steps), isTrue);
      expect(
        matchSelector(_selector(':nth-child(1):nth-child(2)'), e, steps),
        isFalse,
      );
    });

    test('class="a a" vira {a}', () {
      final e = _infos('<p id="p" class=" a\ta  b ">t</p>')['p']!;
      expect(e.classes, {'a', 'b'});
      expect(e.classHashes, hasLength(2));
    });
  });

  group('passos (§10.6)', () {
    final infos = _infos('<div id="d"><p id="p" class="a b">t</p></div>');

    int steps(String selector, String id) {
      final s = MatchSteps(1 << 30);
      matchSelector(_selector(selector), infos[id]!, s);
      return s.total;
    }

    test('um passo por seletor simples testado; universal custa um', () {
      expect(steps('p.a.b', 'p'), 3);
      expect(steps('p.z.b', 'p'), 2, reason: 'para na primeira falha');
      expect(steps('*', 'p'), 1);
      expect(steps('div p', 'p'), 2);
    });

    test('> sem pai na raiz é failsCompletely: o descendente não segue', () {
      // p (1); body contra o div (1); body (1), html (1), a raiz sem pai
      // para tudo. Com failsLocally, o descendente ainda testaria body
      // contra o html (5).
      expect(steps('x > html > body p', 'p'), 4);
    });

    test('bookMode soma no orçamento; exhausted passa de budget', () {
      final s = MatchSteps(2)..bookMode = true;
      matchSelector(_selector('p.a.b'), infos['p']!, s);
      expect((s.total, s.book, s.exhausted), (3, 3, true));
      final off = MatchSteps(2);
      matchSelector(_selector('p.a.b'), infos['p']!, off);
      expect((off.book, off.exhausted), (0, false));
    });

    test('esgotado, o casamento do livro para; o da folha padrão segue', () {
      final s = MatchSteps(0)
        ..bookMode = true
        ..book = 1;
      expect(matchSelector(_selector('p'), infos['p']!, s), isFalse);
      expect(s.total, 0);
      s.bookMode = false;
      expect(s.exhausted, isTrue);
      expect(matchSelector(_selector('p'), infos['p']!, s), isTrue);
    });
  });

  group('AncestorFilter', () {
    test('push e pop; identificadores em minúsculas', () {
      final e = _infos('<p id="Main" class="Foo">t</p>')['Main']!;
      final f = AncestorFilter()..push(e);
      expect(f.mayContain(bloomHash(bloomKindClass, 'foo')), isTrue);
      expect(f.mayContain(bloomHash(bloomKindId, 'main')), isTrue);
      expect(f.mayContain(bloomHash(bloomKindTag, 'p')), isTrue);
      f.pop(e);
      expect(f.mayContain(bloomHash(bloomKindClass, 'foo')), isFalse);
    });

    test('contador que chega a 255 fica preso (só falso positivo)', () {
      final e = _infos('<p id="p">t</p>')['p']!;
      final f = AncestorFilter();
      for (var i = 0; i < 300; i++) {
        f.push(e);
      }
      for (var i = 0; i < 300; i++) {
        f.pop(e);
      }
      expect(f.mayContain(e.nameHash), isTrue);
      // Uma posição fora das presas continua exata: liga no push, desliga no
      // pop.
      final stuck = {
        for (final h in [e.nameHash, e.idHash!]) ...[
          h & 0xFFF,
          (h >> 12) & 0xFFF,
        ],
      };
      final free = [for (var k = 0; k < 64; k++) 'solta$k']
          .map((c) => _infos('<p id="q" class="$c">t</p>')['q']!)
          .firstWhere((q) {
            final h = q.classHashes.single;
            return !stuck.contains(h & 0xFFF) &&
                !stuck.contains((h >> 12) & 0xFFF);
          });
      final hash = free.classHashes.single;
      expect(f.mayContain(hash), isFalse);
      f.push(free);
      expect(f.mayContain(hash), isTrue);
      f.pop(free);
      expect(f.mayContain(hash), isFalse);
      expect(f.mayContain(e.nameHash), isTrue, reason: 'continua presa');
    });
  });

  group('hostis: linear', () {
    test('span div … div p (32 compostos) sobre 250 div aninhados', () {
      final infos = _infos('${'<div>' * 250}<p id="p">t</p>${'</div>' * 250}');
      final chain = _selector('${'div ' * 31}p');
      // A falha na ponta esquerda: com retrocesso, cada um dos 30 `div`
      // tentaria todos os ancestrais restantes (combinatório).
      final miss = _selector('span ${'div ' * 30}p');
      final sw = Stopwatch()..start();
      final s = MatchSteps(1 << 30);
      for (var i = 0; i < 1000; i++) {
        expect(matchSelector(chain, infos['p']!, s), isTrue);
        expect(matchSelector(miss, infos['p']!, s), isFalse);
      }
      sw.stop();
      // failsCompletely: sem retrocesso, cada teste custa O(compostos + profundidade).
      expect(s.total, lessThan(1000 * 2 * (32 + 260)));
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
    });
  });
}
