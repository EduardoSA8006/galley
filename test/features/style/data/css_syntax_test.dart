import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/core/diagnostics/diagnostic_codes.dart';
import 'package:galley/src/core/diagnostics/diagnostic_sink.dart';
import 'package:galley/src/features/style/data/css_syntax.dart';
import 'package:galley/src/features/style/data/css_tokenizer.dart';

ParsedCss parse(String css, [CollectingDiagnosticSink? sink]) =>
    parseCss(css, location: 'a.css', sink: sink ?? CollectingDiagnosticSink());

int errors(CollectingDiagnosticSink s) =>
    s.diagnostics.where((d) => d.code == DiagnosticCodes.cssParseError).length;

List<String> names(List<RawDeclaration> d) => d.map((e) => e.name).toList();

void main() {
  group('regras e declarações', () {
    test('declarações vazias são ignoradas', () {
      final r = parse('p{color:red;;margin:0}').rules;
      expect(r, hasLength(1));
      expect(names((r.single as QualifiedRule).declarations), [
        'color',
        'margin',
      ]);
    });

    test('declaração sem dois-pontos é descartada até o ;', () {
      final sink = CollectingDiagnosticSink();
      final r = parse('p{color red; margin:0}', sink).rules;
      expect(names((r.single as QualifiedRule).declarations), ['margin']);
      expect(errors(sink), 1);
      expect(sink.diagnostics.single.location, 'a.css:1');
    });

    test('} solto vira o início do prelúdio da regra seguinte', () {
      final r = parse('p{color:red} } q{margin:0}').rules;
      expect(r, hasLength(2));
      expect(r[0], isA<QualifiedRule>());
      final second = r[1] as QualifiedRule;
      expect(second.prelude.first.type, CssTokenType.rightBrace);
      expect(names(second.declarations), ['margin']);
    });

    test('@media com regra interna e depois q', () {
      final r = parse('@media print { p{x:y} } q{color:red}').rules;
      expect(r, hasLength(2));
      final media = r[0] as AtRule;
      expect(media.name, 'media');
      expect(media.rules, hasLength(1));
      expect(media.declarations, isNull);
      expect((r[1] as QualifiedRule).prelude.single.value, 'q');
    });

    test('nome em minúsculas, !important em qualquer caixa', () {
      final d = (parse('P{COLOR:Red !IMPORTANT}').rules.single as QualifiedRule)
          .declarations
          .single;
      expect(d.name, 'color');
      expect(d.value.single.value, 'Red');
      expect(d.important, isTrue);
    });

    test('! important com espaço', () {
      final d =
          (parse('p{color:red ! important}').rules.single as QualifiedRule)
              .declarations
              .single;
      expect(d.important, isTrue);
      expect(d.value.single.value, 'red');
    });

    test('propriedade personalizada mantém a caixa', () {
      final d = (parse('p{--Foo:1}').rules.single as QualifiedRule)
          .declarations
          .single;
      expect(d.name, '--Foo');
    });

    test('bloco sem fechamento mantém as declarações', () {
      final sink = CollectingDiagnosticSink();
      final r = parse('p{a:b', sink).rules;
      expect(names((r.single as QualifiedRule).declarations), ['a']);
      expect(errors(sink), 1);
    });

    test('@import sem bloco e regra seguinte', () {
      final r = parse('@import "a.css";p{}').rules;
      expect(r, hasLength(2));
      final imp = r[0] as AtRule;
      expect(imp.name, 'import');
      expect(imp.rules, isNull);
      expect(imp.declarations, isNull);
      expect(r[1], isA<QualifiedRule>());
    });

    test('@font-face tem declarações; at-rule desconhecida é descartada', () {
      final r = parse('@font-face{font-family:x} @foo{a:b}').rules;
      expect(names((r[0] as AtRule).declarations!), ['font-family']);
      expect((r[1] as AtRule).declarations, isNull);
      expect((r[1] as AtRule).rules, isNull);
    });

    test('at-rule dentro de declarações é descartada', () {
      final r = parse('p{color:red; @media x {}; margin:0}').rules;
      expect(names((r.single as QualifiedRule).declarations), [
        'color',
        'margin',
      ]);
    });

    test('CDO e CDC ignorados no topo', () {
      expect(parse('<!-- p{color:red} -->').rules, hasLength(1));
    });

    test('valor com bloco e ; dentro de parênteses', () {
      final d =
          (parse('p{a:url(x;y) f(1;2); b:c}').rules.single as QualifiedRule)
              .declarations;
      expect(names(d), ['a', 'b']);
    });

    test('parseCssDeclarations', () {
      final d = parseCssDeclarations(
        'color: red; text-align:center',
        location: 'x.xhtml:3',
        sink: CollectingDiagnosticSink(),
      );
      expect(names(d), ['color', 'text-align']);
    });

    test('lineOf', () {
      final parsed = parse('p{\n a:b;\n c:d}');
      final d = (parsed.rules.single as QualifiedRule).declarations;
      expect(parsed.lineOf(d[0].offset), 2);
      expect(parsed.lineOf(d[1].offset), 3);
      final p3 = parse('a{}\n\np{x:y}');
      final d3 = (p3.rules[1] as QualifiedRule).declarations.single;
      expect(p3.lineOf(d3.offset), 3);
    });

    test('erro numa linha posterior usa essa linha', () {
      final sink = CollectingDiagnosticSink();
      parse('p{a:b}\n\nq{c d}', sink);
      expect(sink.diagnostics.single.location, 'a.css:3');
    });
  });

  test('CRLF: valueStart/valueEnd recortam source', () {
    final parsed = parse('p{\r\n  unicode-range: U+0-7F,\r\n U+80;\r\n}');
    final d = (parsed.rules.single as QualifiedRule).declarations.single;
    expect(parsed.source.contains('\r'), isFalse);
    expect(parsed.source.substring(d.valueStart, d.valueEnd), 'U+0-7F,\n U+80');
  });

  group('entradas patológicas', () {
    void stress(String name, String css) {
      test(name, () {
        final sink = CollectingDiagnosticSink();
        final sw = Stopwatch()..start();
        parse(css, sink);
        sw.stop();
        expect(sw.elapsedMilliseconds, lessThan(2000));
        expect(errors(sink), lessThanOrEqualTo(21));
      });
    }

    stress('parênteses', 'p{a:${'(' * 100000}');
    stress('chaves', '{' * 100000);
    stress('@media aninhadas', '@media all{' * 100000);
    stress('chaves em declaração', 'p{${'a:b{' * 50000}');

    test('aninhamento além de 32 níveis descarta o bloco', () {
      final sink = CollectingDiagnosticSink();
      final parsed = parse('${'@media all{' * 40}p{a:b}${'}' * 40}', sink);
      var depth = 0;
      var rule = parsed.rules.single as AtRule;
      while (rule.rules != null && rule.rules!.isNotEmpty) {
        depth++;
        final next = rule.rules!.single;
        if (next is! AtRule) break;
        rule = next;
      }
      expect(depth, 32);
      expect(errors(sink), greaterThan(0));
    });
  });
}
