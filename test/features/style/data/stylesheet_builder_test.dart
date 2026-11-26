import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/core/diagnostics/diagnostic.dart';
import 'package:galley/src/core/diagnostics/diagnostic_codes.dart';
import 'package:galley/src/core/diagnostics/diagnostic_sink.dart';
import 'package:galley/src/features/style/data/stylesheet_builder.dart';
import 'package:galley/src/features/style/domain/css_value.dart';
import 'package:galley/src/features/style/domain/properties.dart';
import 'package:galley/src/features/style/domain/style_environment.dart';
import 'package:galley/src/features/style/domain/stylesheet.dart';

const env = StyleEnvironment(pageWidth: 600, pageHeight: 800);
const path = 'OEBPS/css/s.css';

late CollectingDiagnosticSink sink;

StyleSheet build(String css, {String fontPrefix = 'gf1-'}) =>
    buildStyleSheet(css, path: path, fontPrefix: fontPrefix, sink: sink);

List<Diagnostic> withCode(String code) =>
    sink.diagnostics.where((d) => d.code == code).toList();

void main() {
  setUp(() => sink = CollectingDiagnosticSink());

  group('@media', () {
    test('regra condicionada e regra livre', () {
      final s = build('@media print { p {color:red} } p{margin:0}');
      expect(s.rules, hasLength(2));
      expect(s.rules[0].conditions, hasLength(1));
      expect(s.rules[0].conditions.single.evaluate(env), isFalse);
      expect(s.rules[1].conditions, isEmpty);
    });

    test('caixa alta no nome e no tipo (revisão 2)', () {
      final s = build('@MEDIA SCREEN { p{} }');
      expect(s.rules, hasLength(1));
      expect(s.rules.single.conditions.single.evaluate(env), isTrue);
      expect(sink.diagnostics, isEmpty);
    });

    test('@media aninhados acumulam condições', () {
      final s = build('@media screen { @media (max-width: 1px) { p{} } }');
      expect(s.rules.single.conditions, hasLength(2));
      expect(s.rules.single.conditions[1].evaluate(env), isFalse);
    });

    test('100.000 "(" no prelúdio não estoura a pilha', () {
      final css = '@media ${'(' * 100000}width${')' * 100000} { p{} } q{}';
      final s = build(css);
      expect(s.rules, hasLength(2));
      expect(s.rules.first.conditions.single.evaluate(env), isFalse);
    });
  });

  group('@supports', () {
    test('suportada, não suportada e not', () {
      expect(build('@supports (display:flex) { p{} }').rules, hasLength(1));
      expect(build('@supports (filter: invert(1)) { p{} }').rules, isEmpty);
      expect(build('@supports not (filter: x) { p{} }').rules, hasLength(1));
    });

    test('and, or, parênteses e caixa alta', () {
      expect(
        build('@supports (display:flex) and (color:red) { p{} }').rules,
        hasLength(1),
      );
      expect(
        build('@supports (display:flex) and (filter:x) { p{} }').rules,
        isEmpty,
      );
      expect(
        build('@supports (filter:x) or ((color:red)) { p{} }').rules,
        hasLength(1),
      );
      expect(
        build('@SUPPORTS NOT ((filter:x) OR (foo:y)) { p{} }').rules,
        hasLength(1),
      );
      expect(
        build('@supports (display:flex) and (color:red) or (x:y) { p{} }')
            .rules,
        isEmpty,
      );
    });

    test('selector()', () {
      expect(build('@supports selector(p > a) { p{} }').rules, hasLength(1));
      expect(build('@supports selector(:has(a)) { p{} }').rules, isEmpty);
    });

    test('condição desconhecida ou malformada é falsa', () {
      expect(build('@supports foo(1) { p{} }').rules, isEmpty);
      expect(build('@supports display:flex { p{} }').rules, isEmpty);
      expect(build('@supports { p{} }').rules, isEmpty);
    });

    test('100.000 "(" é falso, sem estouro de pilha', () {
      final css =
          '@supports ${'(' * 100000}display:flex${')' * 100000} { p{} } q{}';
      final sw = Stopwatch()..start();
      final s = build(css);
      expect(s.rules, hasLength(1));
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
      final ok = build('@supports ${'(' * 32}display:flex${')' * 32} { p{} }');
      expect(ok.rules, hasLength(1));
      final deep = build(
        '@supports ${'(' * 33}display:flex${')' * 33} { p{} }',
      );
      expect(deep.rules, isEmpty);
    });

    test('@media dentro de @supports verdadeiro', () {
      final s = build('@supports (color:red) { @media print { p{} } }');
      expect(s.rules.single.conditions.single.evaluate(env), isFalse);
    });
  });

  group('@namespace e @import', () {
    test('@namespace declara o prefixo', () {
      final s = build(
        '@namespace svg url(http://www.w3.org/2000/svg); svg|rect{}',
      );
      expect(s.rules, hasLength(1));
      expect(sink.diagnostics, isEmpty);
    });

    test('@namespace depois de uma regra é css.parseError', () {
      final s = build('p{} @namespace x url(y);');
      expect(s.rules, hasLength(1));
      expect(withCode(DiagnosticCodes.cssParseError), hasLength(1));
    });

    test('@import resolvido pela folha, com media', () {
      final s = build(
        '@charset "utf-8"; @import "a.css"; '
        '@import url(../b.css) print; @import url(http://x/c.css); p{}',
      );
      expect(s.imports.map((i) => i.path), ['OEBPS/css/a.css', 'OEBPS/b.css']);
      expect(s.imports[0].media, isNull);
      expect(s.imports[1].media!.evaluate(env), isFalse);
      expect(withCode(DiagnosticCodes.cssParseError), isEmpty);
    });

    test('@import depois de uma regra é css.parseError', () {
      final s = build('p{} @import "a.css";');
      expect(s.imports, isEmpty);
      expect(withCode(DiagnosticCodes.cssParseError), hasLength(1));
    });

    test('@import dentro de @media é css.parseError', () {
      final s = build('@media screen { @import "a.css"; p{} }');
      expect(s.imports, isEmpty);
      expect(s.rules, hasLength(1));
      expect(withCode(DiagnosticCodes.cssParseError), hasLength(1));
    });

    test('@namespace padrão restringe seletores de tipo', () {
      final s = build(
        '@charset "utf-8";\n@namespace url(http://www.w3.org/1999/xhtml);\n'
        '@namespace s "http://www.w3.org/2000/svg";\np{} s|svg{}',
      );
      expect(s.rules, hasLength(2));
      expect(sink.diagnostics, isEmpty);
    });

    test('@import com layer/supports é descartado com diagnóstico', () {
      final s = build(
        '@import url(a.css) layer(base); @import "b.css" layer; '
        '@import "c.css" SUPPORTS(display: flex) screen; @import "d.css";',
      );
      expect(s.imports.map((i) => i.path), ['OEBPS/css/d.css']);
      final d = withCode(DiagnosticCodes.cssUnsupportedAtRule);
      expect(d, hasLength(3));
      expect(d.first.severity, DiagnosticSeverity.info);
    });

    test('@IMPORT em caixa alta', () {
      expect(build('@IMPORT "a.css";').imports, hasLength(1));
    });
  });

  group('@page', () {
    test('margens', () {
      final s = build('@page { margin: 1em 2em; size: a4 }');
      expect(s.pages, hasLength(1));
      final (m, conds) = s.pages.single;
      expect(m.top, const CssLengthSpec(em: 1));
      expect(m.right, const CssLengthSpec(em: 2));
      expect(m.bottom, const CssLengthSpec(em: 1));
      expect(m.left, const CssLengthSpec(em: 2));
      expect(conds, isEmpty);
      expect(sink.diagnostics, isEmpty);
    });

    test('lados avulsos e condição de @media', () {
      final s = build('@media screen { @PAGE { margin-top: 5px } }');
      final (m, conds) = s.pages.single;
      expect(m.top, const CssLengthSpec(px: 5));
      expect(m.left, isNull);
      expect(conds, hasLength(1));
    });

    test('com seletor é ignorada', () {
      final s = build('@page :first {margin:0}');
      expect(s.pages, isEmpty);
      final d = withCode(DiagnosticCodes.cssUnsupportedAtRule).single;
      expect(d.severity, DiagnosticSeverity.info);
    });
  });

  group('@font-face', () {
    test('completa', () {
      final s = build(
        '@font-face { font-family: "Body"; '
        'src: url(../fonts/b.otf) format("opentype"), local(Georgia); '
        'font-weight: bold; unicode-range: U+0000-00FF, U+4?? }',
      );
      final f = s.fontFaces.single;
      expect(f.family, 'Body');
      expect(f.internalFamily, 'gf1-body');
      expect(f.sources, const [
        FontUrlSource('OEBPS/fonts/b.otf', 'opentype'),
        FontLocalSource('Georgia'),
      ]);
      expect((f.weightMin, f.weightMax), (700, 700));
      expect(f.style, CssKeywords.normal);
      expect(f.stretch, isNull);
      expect(f.unicodeRanges, [(0, 0xFF), (0x400, 0x4FF)]);
      expect(sink.diagnostics, isEmpty);
    });

    test('padrões, intervalo de peso, estilo e largura', () {
      final s = build(
        '@FONT-FACE { font-family: My Font; src: url("a.woff2"); '
        'font-weight: 900 100; font-style: italic; font-stretch: condensed }',
      );
      final f = s.fontFaces.single;
      expect(f.family, 'My Font');
      expect(f.internalFamily, 'gf1-my font');
      expect(f.sources, const [FontUrlSource('OEBPS/css/a.woff2', null)]);
      expect((f.weightMin, f.weightMax), (100, 900));
      expect(f.style, CssKeywords.italic);
      expect(f.stretch, 'condensed');
      expect(f.unicodeRanges, [(0, 0x10FFFF)]);
    });

    test('unicode-range com caixa e faixa simples', () {
      final s = build(
        '@font-face { font-family: X; src: local(Y); '
        'unicode-range: u+41, U+3000-303f }',
      );
      expect(s.fontFaces.single.unicodeRanges, [
        (0x41, 0x41),
        (0x3000, 0x303F),
      ]);
    });

    test('sem família ou sem fonte usável é css.fontFaceInvalid', () {
      build('@font-face { src: url(a.otf) }');
      build('@font-face { font-family: X; src: url(http://x/a.otf) }');
      final ds = withCode(DiagnosticCodes.cssFontFaceInvalid);
      expect(ds, hasLength(2));
      expect(ds.first.severity, DiagnosticSeverity.warning);
    });

    test('unicode-range recortado do texto pré-processado (CRLF)', () {
      final s = build(
        'p{}\r\n\r\n\r\n@font-face { font-family: X; src: local(Y);\r\n'
        '  unicode-range: U+0041-005A /* maiúsculas */, U+0061-007A }',
      );
      expect(s.fontFaces.single.unicodeRanges, [(0x41, 0x5A), (0x61, 0x7A)]);
    });

    test('nome interno centralizado', () {
      expect(internalFontFamily('a1b2-', 'Body Text'), 'a1b2-body text');
    });
  });

  test('@keyframes é css.unsupportedAtRule', () {
    final s = build('@keyframes k { from {} } @-webkit-keyframes j {}');
    expect(s.rules, isEmpty);
    expect(withCode(DiagnosticCodes.cssUnsupportedAtRule), hasLength(2));
  });

  group('regras', () {
    test('declarações interpretadas e diagnósticos', () {
      final s = build('p{speak:none; filter:x; color:12px; color:red}');
      final d = s.rules.single.declarations;
      expect(d, hasLength(1));
      expect(d.single.property, PropertyId.color);
      expect(d.single.value, const CssColor(0xFFFF0000));
      expect(d.single.important, isFalse);
      expect(withCode(DiagnosticCodes.cssUnsupportedProperty), hasLength(1));
      expect(withCode(DiagnosticCodes.cssInvalidValue), hasLength(1));
      expect(sink.diagnostics.map((e) => e.severity).toSet(), {
        DiagnosticSeverity.info,
      });
    });

    test('abreviada vira longhands, com !important', () {
      final d = build('p{margin:0 !important}').rules.single.declarations;
      expect(d, hasLength(4));
      expect(d.every((e) => e.important), isTrue);
    });

    test('seletor não suportado derruba a regra', () {
      final s = build('p, q:desconhecida {color:red}');
      expect(s.rules, isEmpty);
      final d = withCode(DiagnosticCodes.cssUnsupportedSelector).single;
      expect(d.severity, DiagnosticSeverity.info);
    });

    test('uma regra por seletor, declarações compartilhadas', () {
      final s = build('p, q {color:red}');
      expect(s.rules, hasLength(2));
      expect(
        identical(s.rules[0].declarations, s.rules[1].declarations),
        isTrue,
      );
    });

    test('order cresce na ordem do texto', () {
      final s = build('a{} @media screen { b{} } c, d{} e{}');
      final orders = s.rules.map((r) => r.order).toList();
      expect(orders, hasLength(5));
      for (var i = 1; i < orders.length; i++) {
        expect(orders[i], greaterThan(orders[i - 1]));
      }
    });

    test('location com a linha', () {
      build('p{}\n\nq{}\nr{filter:x}');
      expect(
        withCode(DiagnosticCodes.cssUnsupportedProperty).single.location,
        'OEBPS/css/s.css:4',
      );
    });
  });

  test('StyleSheet.empty', () {
    expect(StyleSheet.empty.rules, isEmpty);
    expect(StyleSheet.empty.fontFaces, isEmpty);
    expect(StyleSheet.empty.pages, isEmpty);
    expect(StyleSheet.empty.imports, isEmpty);
  });
}
