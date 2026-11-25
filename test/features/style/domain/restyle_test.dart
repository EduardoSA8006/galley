import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/features/document/domain/document_tree.dart';
import 'package:galley/src/features/style/domain/computed_style.dart';
import 'package:galley/src/features/style/domain/css_value.dart';
import 'package:galley/src/features/style/domain/properties.dart';
import 'package:galley/src/features/style/domain/reader_preferences.dart';
import 'package:galley/src/features/style/domain/restyle.dart';
import 'package:galley/src/features/style/domain/selector.dart';
import 'package:galley/src/features/style/domain/value_computer.dart';

import '../../../support/style_fixture.dart';

const _css =
    'body{font-size:20px} p{margin:1em 0; line-height:1.5} '
    'em{font-style:italic} .x{color:#123456}';

String _body(int n) => [
  for (var i = 0; i < n; i++)
    '<p>texto <em>a</em> <span class="x">b</span></p>',
].join();

List<int> _hashes(int n) => restyle(
  matchCss(_body(n), css: _css),
  ReaderPreferences.none,
).styles.map((s) => s.stableHash).toList();

const _extremeCss =
    'p{font-size:1e30px; line-height:2em; z-index:2147483647; '
    'margin-left:1e30px} '
    'div{font-size:1000%} span{font-size:0; line-height:2em}';

String _extremeBody() =>
    '<p>a</p>${'<div>' * 40}<span>x</span>${'</div>' * 40}';

List<int> _extremeHashes() => restyle(
  matchCss(_extremeBody(), css: _extremeCss),
  ReaderPreferences.none,
).styles.map((s) => s.stableHash).toList();

void main() {
  group('internamento', () {
    test('1.000 p iguais → o mesmo estilo, poucos distintos', () {
      final m = matchCss('<p>a</p>' * 1000, css: 'p{margin-top:1em}');
      final s = restyle(m, ReaderPreferences.none);
      final ps = elementsNamed(m.tree, 'p');
      expect(ps, hasLength(1000));
      final first = s.elementStyles[ps.first];
      for (final p in ps) {
        expect(s.elementStyles[p], first);
      }
      expect(s.distinctStyleCount, lessThanOrEqualTo(6));
    });

    test('nós que não são elemento ficam com −1', () {
      final m = matchCss('<p>texto</p>');
      final s = restyle(m, ReaderPreferences.none);
      for (var n = 0; n < m.tree.nodeCount; n++) {
        final element = m.tree.kindOf(n) == NodeKind.element;
        expect(s.elementStyles[n] >= 0, element, reason: 'nó $n');
      }
    });

    test('StyleInterner devolve o mesmo objeto para valores iguais', () {
      final interner = StyleInterner();
      final a = interner.intern(List.of(ValueComputer.initialValues));
      final b = interner.intern(List.of(ValueComputer.initialValues));
      expect(identical(a, b), isTrue);
      expect(interner.styles, hasLength(1));
    });

    test('igualdade por valor e hashCode = stableHash', () {
      final a = ComputedStyle(ValueComputer.initialValues);
      final b = ComputedStyle(List.of(ValueComputer.initialValues));
      expect(a, b);
      expect(a.hashCode, a.stableHash);
      final values = List.of(ValueComputer.initialValues);
      values[PropertyId.color] = const CssColor(0xFFFF0000);
      expect(ComputedStyle(values) == a, isFalse);
    });

    test('-0.0 e 0.0: iguais e com o mesmo hash', () {
      final a = List.of(ValueComputer.initialValues);
      final b = List.of(ValueComputer.initialValues);
      a[PropertyId.marginTop] = const CssLength(px: -0.0);
      b[PropertyId.marginTop] = const CssLength();
      expect(ComputedStyle(a), ComputedStyle(b));
      expect(ComputedStyle(a).stableHash, ComputedStyle(b).stableHash);
    });
  });

  group('hash estável', () {
    test('duas chamadas: estilos iguais por valor e mesmo hash', () {
      final m = matchCss(_body(20), css: _css);
      final a = restyle(m, ReaderPreferences.none);
      final b = restyle(m, ReaderPreferences.none);
      expect(a.styles, b.styles);
      expect(
        a.styles.map((s) => s.stableHash).toList(),
        b.styles.map((s) => s.stableHash).toList(),
      );
      expect(a.elementStyles, b.elementStyles);
    });

    test('igual dentro e fora de um Isolate.run', () async {
      final m = matchCss(_body(20), css: _css);
      final local = restyle(
        m,
        ReaderPreferences.none,
      ).styles.map((s) => s.stableHash).toList();
      final remote = await Isolate.run(
        () => restyle(
          m,
          ReaderPreferences.none,
        ).styles.map((s) => s.stableHash).toList(),
      );
      expect(remote, local);
      expect(await Isolate.run(() => _hashes(20)), local);
    });

    test('Revisão 4: valores extremos, mesmo hash dentro e fora', () async {
      final local = _extremeHashes();
      expect(await Isolate.run(_extremeHashes), local);
      final m = matchCss(_extremeBody(), css: _extremeCss);
      final s = restyle(m, ReaderPreferences.none);
      final p = styleOfElement(s, elementsNamed(m.tree, 'p').single);
      expect(p[PropertyId.fontSize], const CssLength(px: 10000));
      expect(p[PropertyId.lineHeight], const CssLength(px: 20000));
      final span = styleOfElement(s, elementsNamed(m.tree, 'span').single);
      expect(span[PropertyId.fontSize], const CssLength());
      expect(span[PropertyId.lineHeight], const CssLength());
      final div = styleOfElement(s, elementsNamed(m.tree, 'div').last);
      expect(div[PropertyId.fontSize], const CssLength(px: 10000));
    });

    test('valor fixo entre execuções (estilo inicial)', () {
      // Calculado uma vez e congelado: muda só se a codificação canônica
      // ou os valores iniciais mudarem.
      expect(ComputedStyle(ValueComputer.initialValues).stableHash, _golden);
    });
  });

  group('pseudo-elementos', () {
    test('::before com strings e attr()', () {
      final m = matchCss(
        '<p id="x">a</p><p>b</p>',
        css: 'p::before{content:"[" attr(id) "]"}',
      );
      final s = restyle(m, ReaderPreferences.none);
      final ps = elementsNamed(m.tree, 'p');
      expect(s.generatedTextOf(ps[0], PseudoElement.before), '[x]');
      expect(s.generatedTextOf(ps[1], PseudoElement.before), '[]');
      expect(s.pseudoStyleOf(ps[0], PseudoElement.after), isNull);
      expect(s.generatedTextOf(ps[0], PseudoElement.after), isNull);
    });

    test('aspas pela profundidade em ordem de documento', () {
      final m = matchCss(
        '<q>a<q>b</q></q>',
        css: 'q::before{content:open-quote} q::after{content:close-quote}',
      );
      final s = restyle(m, ReaderPreferences.none);
      final qs = elementsNamed(m.tree, 'q');
      expect(s.generatedTextOf(qs[0], PseudoElement.before), '“');
      expect(s.generatedTextOf(qs[1], PseudoElement.before), '‘');
      expect(s.generatedTextOf(qs[1], PseudoElement.after), '’');
      expect(s.generatedTextOf(qs[0], PseudoElement.after), '”');
    });

    test('contadores ficam vazios', () {
      final m = matchCss('<p>a</p>', css: 'p::before{content:counter(c) ". "}');
      final s = restyle(m, ReaderPreferences.none);
      final p = elementsNamed(m.tree, 'p').single;
      expect(s.generatedTextOf(p, PseudoElement.before), '. ');
    });

    test('content: none e normal → sem pseudo-elemento', () {
      final m = matchCss(
        '<p>a</p>',
        css: 'p::before{content:none; color:red} p::after{color:red}',
      );
      final s = restyle(m, ReaderPreferences.none);
      final p = elementsNamed(m.tree, 'p').single;
      expect(s.pseudoStyleOf(p, PseudoElement.before), isNull);
      expect(s.pseudoStyleOf(p, PseudoElement.after), isNull);
    });

    test('::before herda do elemento', () {
      final m = matchCss(
        '<p>a</p>',
        css:
            'p{color:red; font-size:10px} '
            'p::before{content:"x"; margin-left:2em}',
      );
      final s = restyle(m, ReaderPreferences.none);
      final p = elementsNamed(m.tree, 'p').single;
      final before = s.styles[s.pseudoStyleOf(p, PseudoElement.before)!];
      expect(before[PropertyId.color], const CssColor(0xFFFF0000));
      expect(before[PropertyId.marginLeft], const CssLength(px: 20));
    });

    test('::first-letter com 2em sobre 16 → 32', () {
      final m = matchCss('<p>abc</p>', css: 'p::first-letter{font-size:2em}');
      final s = restyle(m, ReaderPreferences.none);
      final p = elementsNamed(m.tree, 'p').single;
      final index = s.pseudoStyleOf(p, PseudoElement.firstLetter);
      expect(index, isNotNull);
      expect(s.styles[index!][PropertyId.fontSize], const CssLength(px: 32));
      expect(s.generatedTextOf(p, PseudoElement.firstLetter), isNull);
    });
  });

  group('documento', () {
    test('@page{margin:1em} → lados especificados (F8)', () {
      final s = styleCss('<p/>', css: '@page{margin:1em}');
      expect(s.pageMargins, isNotNull);
      expect(s.pageMargins!.top, const CssLengthSpec(em: 1));
      expect(s.pageMargins!.left, const CssLengthSpec(em: 1));
      expect(styleCss('<p/>').pageMargins, isNull);
    });

    test('sem tema, pageBackground é nulo', () {
      expect(
        styleCss('<p/>', css: 'body{background-color:red}').pageBackground,
        isNull,
      );
    });

    test('Revisão 3: 10.000 div aninhados sem estouro e linear', () {
      const depth = 10000;
      final body = '${'<div>' * depth}x${'</div>' * depth}';
      final m = matchCss(body, css: 'div{margin-left:1em}');
      final sw = Stopwatch()..start();
      final s = restyle(m, ReaderPreferences.none);
      sw.stop();
      final divs = elementsNamed(m.tree, 'div');
      expect(divs, hasLength(depth));
      expect(s.elementStyles[divs.last], s.elementStyles[divs.first]);
      expect(s.distinctStyleCount, lessThanOrEqualTo(4));
      // Linear: a medida folgada pega só um comportamento quadrático.
      expect(sw.elapsedMilliseconds, lessThan(5000));
    });

    test('retainedBytes > 0 e cresce com o documento', () {
      final small = styleCss(_body(5), css: _css);
      final big = styleCss(_body(500), css: _css);
      expect(small.retainedBytes, greaterThan(0));
      expect(big.retainedBytes, greaterThan(small.retainedBytes));
    });
  });
}

const int _golden = 2798588880;
