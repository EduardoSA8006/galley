// Cascata (spec do CSS §10): herança e palavras globais do CSS Cascade 4
// §7, camadas de origem e importância (§6.1), especificidade, `left`
// herdado como palavra (CSS Text 3 §7.1), `bolder`/`lighter` (CSS Fonts 4
// §2.2), propagação de `text-decoration` (CSS Text Decoration 3 §2.1),
// dicas `hidden`/`dir`, profundidade, orçamento, cessão e internação.
import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/css/cascade.dart';
import 'package:galley/src/css/computed_style.dart';
import 'package:galley/src/css/loader.dart';
import 'package:galley/src/css/parser.dart';
import 'package:galley/src/css/properties.dart';
import 'package:galley/src/css/rule_index.dart';
import 'package:galley/src/diagnostics/diagnostic.dart';
import 'package:galley/src/diagnostics/exceptions.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

const _section = 'OEBPS/Text/c.xhtml';

SectionSheets _sheets(List<String> css) => SectionSheets([
  for (var i = 0; i < css.length; i++)
    AppliedSheet(SheetRef.style(css[i]), parseStyleSheet(css[i]), 's$i.css'),
]);

final class _Run {
  _Run(
    String css,
    String body, {
    bool strict = false,
    int budget = cascadeBudget,
    this.recordOrigins = true,
    List<String>? sheets,
  }) : document = html.parse(
         '<html xmlns="http://www.w3.org/1999/xhtml"><head></head>'
         '<body>$body</body></html>',
       ),
       sink = DiagnosticSink(strict: strict) {
    styles = computeStylesSync(
      document,
      _sheets(sheets ?? [if (css.isNotEmpty) css]),
      sectionPath: _section,
      sink: sink,
      recordOrigins: recordOrigins,
      budget: budget,
    );
  }

  final Document document;
  final DiagnosticSink sink;
  final bool recordOrigins;
  late final SectionStyles styles;

  Element element(String id) => document.getElementById(id)!;

  ComputedStyle operator [](String id) => styles.styleOf(element(id))!;

  /// Estilo do primeiro elemento [tag] (para quando um `id` mudaria a conta
  /// de passos).
  ComputedStyle first(String tag) =>
      styles.styleOf(document.getElementsByTagName(tag).first)!;

  CssOrigin? origin(String id, CssProperty p) =>
      styles.originOf(element(id), p);

  List<String> get codes => [for (final d in sink.diagnostics) d.code.name];

  EpubDiagnostic only(EpubDiagnosticCode code) =>
      sink.diagnostics.singleWhere((d) => identical(d.code, code));
}

void main() {
  group('herança (§7.1)', () {
    test('herdadas copiadas; não herdadas no inicial', () {
      final r = _Run(
        '#d { white-space: pre; direction: rtl; list-style-type: square; '
            'text-align: center; font-style: italic; font-weight: bold; '
            'font-variant: small-caps; text-transform: uppercase; '
            'text-indent: 2em; vertical-align: super; break-before: page; '
            'break-after: page; break-inside: avoid; width: 10em; height: 5em; '
            'font-size: 2em; margin: 1em; padding: 1em }',
        '<div id="d"><span id="s">x</span></div>',
      );
      final s = r['s'];
      expect(
        (s.whiteSpace, s.direction, s.listStyleType, s.alignKeyword),
        (
          CssWhiteSpace.pre,
          CssDirection.rtl,
          CssListStyleType.square,
          CssAlignKeyword.center,
        ),
      );
      expect(
        (s.fontStyle, s.weight, s.fontVariant, s.textTransform, s.textIndent),
        (
          CssFontStyle.italic,
          700,
          CssFontVariant.smallCaps,
          CssTextTransform.uppercase,
          2.0,
        ),
      );
      expect(
        (
          s.display,
          s.verticalAlign,
          s.breakBefore,
          s.breakAfter,
          s.breakInside,
        ),
        (
          CssDisplay.inline,
          CssVerticalAlign.baseline,
          CssBreak.auto,
          CssBreak.auto,
          CssBreak.auto,
        ),
      );
      expect(
        (s.width, s.height, s.fontSizeStep),
        (null, null, CssFontSizeStep.same),
      );
      expect((s.margin, s.padding), (EmEdges.zero, EmEdges.zero));
      expect(r['d'].fontSizeStep, CssFontSizeStep.larger);
      expect(r['d'].margin, const EmEdges(1, 1, 1, 1));
    });

    test('inherit, initial e unset', () {
      final r = _Run(
        '#d { display: list-item; font-style: italic; margin-top: 2em; '
            'margin-bottom: 2em; '
            'text-indent: 3em; width: 50% } '
            '#p { display: inherit; font-style: initial; margin-top: inherit; '
            'margin-bottom: unset; text-indent: unset; width: inherit }',
        '<div id="d"><p id="p">x</p></div>',
      );
      final p = r['p'];
      expect(p.display, CssDisplay.listItem);
      expect(p.fontStyle, CssFontStyle.normal);
      expect(p.margin.top, 2);
      expect(p.margin.bottom, 0);
      expect(p.textIndent, 3);
      expect(p.width, const CssLength(50, CssLengthUnit.percent));
    });

    test('font-size: inherit, initial e unset dão same', () {
      final r = _Run(
        '#h { font-size: inherit } #i { font-size: initial }',
        '<h1><span id="h">a</span></h1><h2 id="i">b</h2>',
      );
      expect(r['h'].fontSizeStep, CssFontSizeStep.same);
      expect(r['i'].fontSizeStep, CssFontSizeStep.same);
    });
  });

  group('camadas e ordem (CSS Cascade 4 §6)', () {
    test('!important do livro vence style="" normal', () {
      final r = _Run(
        '#x { font-style: normal !important }',
        '<p id="x" style="font-style: italic">t</p>',
      );
      expect(r['x'].fontStyle, CssFontStyle.normal);
    });

    test(
      'style="" vence #id; style="" !important vence !important de folha',
      () {
        final r = _Run(
          '#x { display: none } #y { display: none !important }',
          '<p id="x" style="display: inline">t</p>'
              '<p id="y" style="display: inline !important">t</p>',
        );
        expect(r['x'].display, CssDisplay.inline);
        expect(r['y'].display, CssDisplay.inline);
      },
    );

    test('ordem entre regras e última declaração do bloco', () {
      final r = _Run(
        'p { font-style: italic } p { font-style: normal } '
            'em { font-weight: bold; font-weight: normal }',
        '<p id="p">t</p><em id="e">t</em>',
      );
      expect(r['p'].fontStyle, CssFontStyle.normal);
      expect(r['e'].weight, 400);
    });

    test('ordem entre folhas', () {
      final r = _Run(
        '',
        '<p id="p">t</p>',
        sheets: ['p { font-style: italic }', 'p { font-style: normal }'],
      );
      expect(r['p'].fontStyle, CssFontStyle.normal);
    });

    test(
      'especificidade vence a ordem; o livro normal vence a folha padrão',
      () {
        final r = _Run(
          '#x { font-style: italic } p { font-style: normal } '
              'h1 { font-weight: normal }',
          '<p id="x">t</p><h1 id="h">t</h1>',
        );
        expect(r['x'].fontStyle, CssFontStyle.italic);
        expect(r['h'].weight, 400);
      },
    );

    test(
      'bloco casado por dois seletores da lista: vale a maior especificidade',
      () {
        final r = _Run(
          'p, #x { display: none } .y { display: block }',
          '<p id="x" class="y">t</p>',
        );
        expect(r['x'].display, CssDisplay.none);
      },
    );
  });

  group('valores relativos', () {
    test(
      'text-align: left herdado por filho rtl alinha à direita do fluxo',
      () {
        final r = _Run(
          '#d { text-align: left } #s { text-align: start }',
          '<div id="d"><p id="r" dir="rtl">a</p><p id="l">b</p>'
              '<p id="s" dir="rtl">c</p></div>',
        );
        expect(r['r'].alignKeyword, CssAlignKeyword.left);
        expect(r['r'].textAlign, CssTextAlign.end);
        expect(r['l'].textAlign, CssTextAlign.start);
        expect(r['s'].textAlign, CssTextAlign.start);
      },
    );

    test('bolder e lighter sobre 900 e 300 (CSS Fonts 4 §2.2)', () {
      final r = _Run(
        '.w9 { font-weight: 900 } .w3 { font-weight: 300 } '
            '.b { font-weight: bolder } .l { font-weight: lighter }',
        '<div class="w9"><span id="b9" class="b">a</span>'
            '<span id="l9" class="l">b</span></div>'
            '<div class="w3"><span id="b3" class="b">c</span>'
            '<span id="l3" class="l">d</span></div>'
            '<h1><b id="hb">e</b></h1>',
      );
      expect(r['b9'].weight, 900);
      expect(r['l9'].weight, 700);
      expect(r['b3'].weight, 400);
      expect(r['b3'].fontWeight, CssFontWeight.normal);
      expect(r['l3'].weight, 100);
      expect(r['hb'].weight, 900);
    });

    test('bolder e lighter: a tabela inteira, como no Chromium', () {
      // Peso do pai → (bolder, lighter), medido no Chromium 153.
      final table = <double, (int, int)>{
        99.0: (400, 99),
        100.0: (400, 100),
        349.0: (400, 100),
        349.5: (400, 100),
        350.0: (700, 100),
        549.0: (700, 100),
        550.0: (900, 400),
        749.0: (900, 400),
        750.0: (900, 700),
        899.0: (900, 700),
        900.0: (900, 700),
        1000.0: (1000, 700),
      };
      final weights = table.keys.toList();
      final body = [
        for (var k = 0; k < weights.length; k++)
          '<div style="font-weight: ${weights[k]}"><b id="b$k" '
              'style="font-weight: bolder">a</b><i id="l$k" '
              'style="font-weight: lighter">b</i></div>',
      ].join();
      final r = _Run('', body);
      for (var k = 0; k < weights.length; k++) {
        final (bolder, lighter) = table[weights[k]]!;
        expect(r['b$k'].weight, bolder, reason: 'bolder sobre ${weights[k]}');
        expect(r['l$k'].weight, lighter, reason: 'lighter sobre ${weights[k]}');
      }
    });

    test('display: unset e font-weight: initial não herdam', () {
      final r = _Run(
        '#d { display: list-item; font-weight: bold } '
            '#u { display: unset } #w { font-weight: initial }',
        '<div id="d"><p id="u">a</p><p id="w">b</p></div>',
      );
      expect(r['u'].display, CssDisplay.inline);
      expect(r['w'].weight, 400);
    });

    test('listas aninhadas do HTML §15.3.8, como no Chromium', () {
      final r = _Run(
        '',
        '<ol id="ol"><menu id="m1"><li>x</li><menu id="m2"><li>y</li>'
            '<ul id="ul"><li id="li">z</li></ul></menu></menu></ol>'
            '<dir id="d1"><dir id="d2"><dir id="d3"><li>w</li></dir></dir></dir>',
      );
      expect(
        [
          for (final id in ['ol', 'm1', 'm2', 'ul', 'd1', 'd2', 'd3'])
            r[id].listStyleType,
        ],
        [
          CssListStyleType.decimal,
          CssListStyleType.circle,
          CssListStyleType.square,
          CssListStyleType.square,
          CssListStyleType.disc,
          CssListStyleType.circle,
          CssListStyleType.square,
        ],
      );
      expect(r['li'].listStyleType, CssListStyleType.square, reason: 'herda');
      final book = _Run(
        'ul ul { list-style-type: none }',
        '<ul><ul id="u">x</ul></ul>',
      );
      expect(
        book['u'].listStyleType,
        CssListStyleType.none,
        reason: 'o livro vence',
      );
    });

    test('tipo de lista desconhecido resolve no elemento (#8)', () {
      final r = _Run(
        '.g { list-style-type: lower-greek }',
        '<ul class="g" id="ul"><li id="a">a</li></ul>'
            '<ol class="g" id="ol"><li id="b">b</li></ol>'
            '<ol><li class="g" id="c">c</li></ol>'
            '<ul><li class="g" id="d">d</li></ul>',
      );
      expect(r['ul'].listStyleType, CssListStyleType.disc);
      expect(r['a'].listStyleType, CssListStyleType.disc);
      expect(r['ol'].listStyleType, CssListStyleType.decimal);
      expect(r['b'].listStyleType, CssListStyleType.decimal);
      expect(r['c'].listStyleType, CssListStyleType.decimal);
      expect(r['d'].listStyleType, CssListStyleType.disc);
    });

    test('fontSizeStep é relativo ao pai, por nível', () {
      final r = _Run(
        '.big { font-size: 150% }',
        '<h1 id="h"><span id="s">a</span><small id="m">b</small></h1>'
            '<p class="big" id="p">c</p>',
      );
      expect(r['h'].fontSizeStep, CssFontSizeStep.larger);
      expect(r['s'].fontSizeStep, CssFontSizeStep.same);
      expect(r['m'].fontSizeStep, CssFontSizeStep.smaller);
      expect(r['p'].fontSizeStep, CssFontSizeStep.larger);
    });
  });

  group('text-decoration propaga, não herda (#24)', () {
    test('u dentro de s fica com as duas linhas', () {
      final r = _Run('', '<s><u id="a">x</u></s>');
      expect((r['a'].underline, r['a'].lineThrough), (true, true));
    });

    test(
      'none num filho de u não tira o sublinhado; inherit não soma nada',
      () {
        final r = _Run(
          '',
          '<u><span id="n" style="text-decoration: none">a</span>'
              '<span id="i" style="text-decoration: inherit">b</span></u>'
              '<p id="p" style="text-decoration: underline line-through">c</p>',
        );
        expect((r['n'].underline, r['n'].lineThrough), (true, false));
        expect((r['i'].underline, r['i'].lineThrough), (true, false));
        expect((r['p'].underline, r['p'].lineThrough), (true, true));
      },
    );
  });

  group('dicas de apresentação (§8.2)', () {
    test('hidden esconde, exceto until-found; o livro vence', () {
      final r = _Run(
        '.show { display: block }',
        '<p id="h" hidden="">a</p><p id="u" hidden="until-found">b</p>'
            '<p id="U" hidden="UNTIL-FOUND">c</p>'
            '<p id="s" class="show" hidden="hidden">d</p>',
      );
      expect(r['h'].display, CssDisplay.none);
      expect(r.origin('h', CssProperty.display), CssOrigin.userAgent);
      expect(r['u'].display, CssDisplay.block);
      expect(r['U'].display, CssDisplay.block);
      expect(r['s'].display, CssDisplay.block);
    });

    test('dir rtl/ltr sem caixa e sem espaço; auto fica com o IR', () {
      final r = _Run(
        '',
        '<div dir="rtl"><p id="a">a</p><p id="b" dir="LTR">b</p></div>'
            '<p id="c" dir=" rtl">c</p><p id="d" dir="auto">d</p>',
      );
      expect(r['a'].direction, CssDirection.rtl);
      expect(r['b'].direction, CssDirection.ltr);
      expect(r['c'].direction, CssDirection.ltr);
      expect(r['d'].direction, CssDirection.ltr);
    });
  });

  group('seletores de ponta a ponta', () {
    test('+, >, descendente, :nth-child e :last-child com texto no meio', () {
      final r = _Run(
        'h2 + p { text-indent: 0 } p { text-indent: 1em } '
            'div > p { font-style: italic } section p { font-weight: bold } '
            'li:nth-child(2) { display: none } li:last-child { font-style: italic }',
        '<h2>t</h2> texto <p id="a">a</p><p id="b">b</p>'
            '<div><section><p id="c">c</p></section></div>'
            '<ul> x <li id="l1">1</li><li id="l2">2</li><li id="l3">3</li> y </ul>',
      );
      expect(r['a'].textIndent, 0);
      expect(r['b'].textIndent, 1);
      expect(r['c'].fontStyle, CssFontStyle.normal);
      expect(r['c'].weight, 700);
      expect(r['l2'].display, CssDisplay.none);
      expect(r['l3'].fontStyle, CssFontStyle.italic);
      expect(r['l1'].fontStyle, CssFontStyle.normal);
    });

    test('classe e id com maiúsculas passam pelo filtro de Bloom', () {
      final r = _Run(
        '.Foo p { font-style: italic } #Main span { font-weight: bold } '
            '.foo p { text-transform: uppercase }',
        '<div class="Foo" id="Main"><p id="p"><span id="s">x</span></p></div>',
      );
      expect(r['p'].fontStyle, CssFontStyle.italic);
      expect(r['s'].weight, 700);
      expect(r['p'].textTransform, CssTextTransform.none);
    });
  });

  group('unsupportedLayout (§10.7)', () {
    test('só o vencedor degrada: float desfeito por float: none não emite', () {
      final r = _Run(
        '.a { float: left } .a { float: none } .z { float: left }',
        '<p class="a">t</p>',
      );
      expect(r.codes, isEmpty);
    });

    test('uma vez por (seção, propriedade); o sink funde por href', () {
      final one = _Run(
        '.b { float: right }',
        '<p class="b">t</p><p class="b">u</p>',
      );
      final d = one.only(EpubDiagnosticCode.unsupportedLayout);
      expect((d.href, d.severity), (_section, EpubSeverity.warning));
      expect(d.details, {'property': 'float', 'value': 'right', 'count': 1});
      final three = _Run(
        '.b { float: right } .c { position: absolute } .d { columns: 2 } '
            '.e { writing-mode: horizontal-tb }',
        '<p class="b">t</p><p class="c">u</p><p class="d">v</p><p class="e">w</p>',
      );
      final all = three.only(EpubDiagnosticCode.unsupportedLayout);
      expect(all.details['count'], 3);
      expect(all.details['property'], 'columns');
    });

    test('strict: lança EpubSectionParseException com o código', () {
      expect(
        () => _Run('p { float: left }', '<p>t</p>', strict: true),
        throwsA(
          isA<EpubSectionParseException>()
              .having(
                (e) => e.message,
                'message',
                startsWith('unsupportedLayout: '),
              )
              .having((e) => e.href, 'href', _section),
        ),
      );
    });
  });

  group('profundidade e template', () {
    test('256 níveis casam; 257 recebe o herdado puro, dom-depth uma vez', () {
      final document = html.parse('<html><body></body></html>');
      var parent = document.body!; // profundidade 2
      final byDepth = <int, Element>{};
      for (var depth = 3; depth <= 260; depth++) {
        final div = Element.tag('div');
        parent.append(div);
        byDepth[depth] = div;
        parent = div;
      }
      final sink = DiagnosticSink();
      final styles = computeStylesSync(
        document,
        _sheets(['div { font-style: italic; margin-top: 1em }']),
        sectionPath: _section,
        sink: sink,
      );
      final at256 = styles.styleOf(byDepth[256]!)!;
      expect(
        (at256.display, at256.fontStyle, at256.margin.top),
        (CssDisplay.block, CssFontStyle.italic, 1.0),
      );
      final at257 = styles.styleOf(byDepth[257]!)!;
      expect(
        (at257.display, at257.fontStyle, at257.margin.top),
        (CssDisplay.inline, CssFontStyle.italic, 0.0),
      );
      expect(styles.styleOf(byDepth[260]!), same(at257));
      final d = sink.diagnostics.single;
      expect(
        (d.code, d.href, d.details['limit']),
        (EpubDiagnosticCode.stylesheetIgnored, _section, 'dom-depth'),
      );
      expect(styles.length, 3 + 258); // html, head, body e as divs
    });

    test('a decoração propaga abaixo da profundidade 256', () {
      final document = html.parse('<html><body></body></html>');
      var parent = document.body!;
      for (var depth = 3; depth <= 260; depth++) {
        final e = Element.tag(depth == 250 ? 'u' : 'span');
        parent.append(e);
        parent = e;
      }
      final styles = computeStylesSync(
        document,
        SectionSheets.empty,
        sectionPath: _section,
        sink: DiagnosticSink(),
      );
      expect(styles.styleOf(parent)!.underline, isTrue);
    });

    test('subárvore de <template> fica fora do mapa', () {
      final r = _Run(
        'p { font-style: italic }',
        '<template id="t"><p id="in">x</p></template>',
      );
      expect(r['t'].display, CssDisplay.none);
      final inner = r.document.getElementsByTagName('p').single;
      expect(r.styles.styleOf(inner), isNull);
      expect(r.styles.length, 4); // html, head, body, template
    });
  });

  group('orçamento (§10.6)', () {
    // html, head, body e p: tipo e universal em cada um (8 passos); no p,
    // o candidato, o seletor de tipo e a declaração (3).
    test(
      'borda exata: 11 passos cabem em 11; em 10 o p é refeito sem o livro',
      () {
        final ok = _Run('p { font-style: italic }', '<p>t</p>', budget: 11);
        expect(ok.first('p').fontStyle, CssFontStyle.italic);
        expect(ok.styles.budgetExhausted, isFalse);
        final over = _Run('p { font-style: italic }', '<p>t</p>', budget: 10);
        expect(over.first('p').fontStyle, CssFontStyle.normal);
        expect(
          over.first('p').display,
          CssDisplay.block,
          reason: 'a folha padrão continua',
        );
        expect(over.styles.budgetExhausted, isTrue);
        final d = over.only(EpubDiagnosticCode.stylesheetIgnored);
        expect((d.href, d.details['reason']), (_section, 'budget'));
      },
    );

    test('candidato rejeitado pelo Bloom conta um passo', () {
      // 8 consultas e 1 candidato (x p, sem x na árvore).
      expect(
        _Run(
          'x p { font-style: italic }',
          '<p>t</p>',
          budget: 9,
        ).styles.budgetExhausted,
        isFalse,
      );
      expect(
        _Run(
          'x p { font-style: italic }',
          '<p>t</p>',
          budget: 8,
        ).styles.budgetExhausted,
        isTrue,
      );
    });

    test('esgotado: folha padrão, dicas e style="" continuam no resto', () {
      final r = _Run(
        'p { font-style: italic }',
        '${'<p>t</p>' * 10}<p id="z" hidden="" style="font-weight: bold">z</p>',
        budget: 20,
      );
      expect(r.styles.budgetExhausted, isTrue);
      expect(r['z'].fontStyle, CssFontStyle.normal);
      expect(r['z'].display, CssDisplay.none);
      expect(r['z'].weight, 700);
      expect(r.codes, ['stylesheetIgnored']);
    });
  });

  group('cessão (§10.6)', () {
    test('um yield a cada 4 096 passos, com o orçamento separado', () {
      final document = html.parse(
        '<html><body>${'<p>t</p>' * 10000}</body></html>',
      );
      final into = CascadeResult();
      expect(() => into.styles, throwsStateError);
      var yields = 0;
      for (final _ in computeStyles(
        document,
        SectionSheets.empty,
        sectionPath: _section,
        sink: DiagnosticSink(),
        into: into,
        budget: 0,
      )) {
        yields++;
      }
      // Cada p custa ao menos a visita e duas consultas à folha padrão.
      expect(yields, greaterThanOrEqualTo(10000 * 3 ~/ cascadeYieldSteps));
      expect(into.styles.budgetExhausted, isFalse);
      expect(into.styles.length, 10003);
    });
  });

  group('cessão depois de um salto', () {
    test('um salto grande de passos dá uma cessão, não uma rajada', () {
      final document = html.parse('<html><body></body></html>');
      // A montagem do primeiro p soma ~16 000 passos de uma vez.
      document.body!.append(
        Element.tag('p')..attributes['class'] = 'a'.padRight(1 << 20),
      );
      for (var i = 0; i < 10000; i++) {
        document.body!.append(Element.tag('p'));
      }
      final marks = <int>[];
      for (final _ in computeStyles(
        document,
        SectionSheets.empty,
        sectionPath: _section,
        sink: DiagnosticSink(),
        into: CascadeResult(),
        onYield: marks.add,
      )) {}
      marks.removeLast(); // a marca do fim, que não é cessão
      expect(marks.length, greaterThan(10));
      for (var i = 1; i < marks.length; i++) {
        expect(
          marks[i] - marks[i - 1],
          greaterThanOrEqualTo(cascadeYieldSteps),
          reason: 'cessões ${i - 1} e $i',
        );
      }
    });
  });

  group('cessão do parse de style=""', () {
    test(
      'um texto novo conta o tamanho: 2 000 de 8 KiB cedem ~2 000 vezes',
      () {
        final document = html.parse('<html><body></body></html>');
        for (var i = 0; i < 2000; i++) {
          document.body!.append(
            Element.tag('p')
              ..attributes['style'] = 'text-indent: ${i}em;'.padRight(
                maxStyleAttributeLength,
              ),
          );
        }
        var yields = 0;
        for (final _ in computeStyles(
          document,
          SectionSheets.empty,
          sectionPath: _section,
          sink: DiagnosticSink(),
          into: CascadeResult(),
        )) {
          yields++;
        }
        expect(
          yields,
          greaterThanOrEqualTo(2000 * (maxStyleAttributeLength ~/ 2) ~/ 4096),
        );
      },
    );
  });

  group('internação e originOf', () {
    test('dois elementos com o mesmo estilo recebem a mesma instância', () {
      final r = _Run('', '<p id="a">a</p><p id="b">b</p><em id="c">c</em>');
      expect(r['a'], same(r['b']));
      expect(r['a'], isNot(same(r['c'])));
    });

    test('originOf: livro, style="", folha padrão e herança', () {
      final r = _Run(
        'p { font-style: italic }',
        '<p id="p" style="font-weight: bold">t</p>',
      );
      expect(r.origin('p', CssProperty.fontStyle), CssOrigin.author);
      expect(r.origin('p', CssProperty.fontWeight), CssOrigin.styleAttribute);
      expect(r.origin('p', CssProperty.display), CssOrigin.userAgent);
      expect(r.origin('p', CssProperty.whiteSpace), isNull);
    });

    test('sem recordOrigins, originOf lança StateError', () {
      final r = _Run('', '<p id="p">t</p>', recordOrigins: false);
      expect(() => r.origin('p', CssProperty.display), throwsStateError);
    });

    test('elemento de fora do documento: styleOf é null', () {
      final r = _Run('', '<p>t</p>');
      expect(r.styles.styleOf(Element.tag('p')), isNull);
    });
  });

  group('diagnósticos da cascata', () {
    test('20 001 seletores: limit rules com a folha onde cortou', () {
      final r = _Run(
        '',
        '<p>t</p>',
        sheets: [
          List.generate(19999, (k) => '.a$k { display: block }').join(),
          '.b0, .b1 { display: block }',
        ],
      );
      final d = r.only(EpubDiagnosticCode.stylesheetIgnored);
      expect((d.href, d.details['limit']), ('s1.css', 'rules'));
    });

    test('style="": 8 KiB vale, + 1 é too-large uma vez; erros somados', () {
      final ok = 'font-style: italic;${' ' * (maxStyleAttributeLength - 19)}';
      expect(ok.length, maxStyleAttributeLength);
      final r = _Run(
        '',
        '<p id="a" style="$ok">a</p><p id="b" style="$ok ">b</p>'
            '<p style="$ok  ">c</p><p style="12px; display: none">d</p>'
            '<p style="12px; display: none">e</p>',
      );
      expect(r['a'].fontStyle, CssFontStyle.italic);
      expect(r['b'].fontStyle, CssFontStyle.normal);
      expect(r.codes, ['stylesheetIgnored', 'cssRuleIgnored']);
      final large = r.only(EpubDiagnosticCode.stylesheetIgnored);
      expect(large.details['count'], 1);
      expect(large.details['source'], 'style-attribute');
      final errors = r.only(EpubDiagnosticCode.cssRuleIgnored);
      expect((errors.href, errors.details['discarded']), (_section, 2));
    });
  });
}
