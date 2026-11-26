import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/features/style/data/css_tokenizer.dart';
import 'package:galley/src/features/style/data/property_parser.dart';
import 'package:galley/src/features/style/domain/css_value.dart';
import 'package:galley/src/features/style/domain/properties.dart';

/// Tokens do valor como o parser de declarações entrega (aparado).
List<CssToken> tokens(String v) {
  final t = tokenizeCss(v);
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

PropertyParseResult parse(
  String name,
  String value, {
  String sheet = 'OEBPS/css/s.css',
}) => parseProperty(name, tokens(value), sheetPath: sheet);

/// Longhands como mapa nome → valor (falha se não for ParsedLonghands).
Map<String, CssValue> longhands(String name, String value) {
  final r = parse(name, value);
  expect(r, isA<ParsedLonghands>(), reason: '$name: $value');
  return {
    for (final (id, v) in (r as ParsedLonghands).values)
      propertyInfo(id).name: v,
  };
}

/// Valor da única longhand produzida.
CssValue single(String name, String value) {
  final m = longhands(name, value);
  expect(m, hasLength(1), reason: '$name: $value');
  return m.values.single;
}

CssKeyword kw(String name) => CssKeyword(CssKeywords.idOf(name)!);

void invalid(String name, String value) =>
    expect(parse(name, value), isA<InvalidValue>(), reason: '$name: $value');

void main() {
  group('caixa alta (Review Focus 2)', () {
    test('cores, unidades e nomes sem diferença de caixa', () {
      expect(single('color', 'RED'), const CssColor(0xFFFF0000));
      expect(single('COLOR', 'Red'), const CssColor(0xFFFF0000));
      expect(single('color', '#ABC'), const CssColor(0xFFAABBCC));
      expect(single('margin-top', '1EM'), const CssLengthSpec(em: 1));
      expect(single('display', 'BLOCK'), kw('block'));
      expect(
        single('width', 'CALC(100% - 2EM)'),
        const CssLengthSpec(percent: 100, em: -2),
      );
      expect(single('color', 'RGB(255, 0, 0)'), const CssColor(0xFFFF0000));
      expect(single('margin-top', 'INHERIT'), kw('inherit'));
      expect(CssKeywords.idOf('List-Item'), CssKeywords.listItem);
    });
  });

  group('cores', () {
    test('rgb e rgba nas duas sintaxes', () {
      expect(single('color', 'rgb(255 0 0 / 50%)'), const CssColor(0x80FF0000));
      expect(single('color', 'rgba(0,0,0,.5)'), const CssColor(0x80000000));
      expect(single('color', 'rgb(100%, 0%, 0%)'), const CssColor(0xFFFF0000));
      expect(single('color', 'rgb(300, -5, 0)'), const CssColor(0xFFFF0000));
      invalid('color', 'rgb(255, 0%, 0)');
      invalid('color', 'rgb(255, 0)');
    });

    test('hex de 3, 4, 6 e 8 dígitos', () {
      expect(single('color', '#abcd'), const CssColor(0xDDAABBCC));
      expect(single('color', '#102030'), const CssColor(0xFF102030));
      expect(single('color', '#10203040'), const CssColor(0x40102030));
      invalid('color', '#12345');
      invalid('color', '#ggg');
    });

    test('hsl e hsla', () {
      expect(single('color', 'hsl(0, 100%, 50%)'), const CssColor(0xFFFF0000));
      expect(
        single('color', 'hsl(120deg 100% 25%)'),
        const CssColor(0xFF008000),
      );
      expect(
        single('color', 'hsla(240, 100%, 50%, 0.5)'),
        const CssColor(0x800000FF),
      );
    });

    test('nomes, transparent e currentcolor', () {
      expect(single('color', 'black'), const CssColor(0xFF000000));
      expect(single('color', 'rebeccapurple'), const CssColor(0xFF663399));
      expect(
        single('color', 'lightgoldenrodyellow'),
        const CssColor(0xFFFAFAD2),
      );
      expect(single('background-color', 'transparent'), const CssColor(0));
      expect(single('color', 'currentColor'), kw('currentcolor'));
      invalid('color', '12px');
      invalid('color', 'nada');
    });
  });

  group('comprimentos', () {
    test('margin com dois valores', () {
      final m = longhands('margin', '1em 2px');
      expect(m['margin-top'], const CssLengthSpec(em: 1));
      expect(m['margin-bottom'], const CssLengthSpec(em: 1));
      expect(m['margin-left'], const CssLengthSpec(px: 2));
      expect(m['margin-right'], const CssLengthSpec(px: 2));
    });

    test('margin com 1, 3 e 4 valores e auto', () {
      final a = longhands('margin', '0 auto');
      expect(a['margin-top'], const CssLengthSpec());
      expect(a['margin-left'], kw('auto'));
      final b = longhands('margin', '1px 2px 3px');
      expect(b['margin-bottom'], const CssLengthSpec(px: 3));
      expect(b['margin-left'], const CssLengthSpec(px: 2));
      final c = longhands('padding', '1px 2px 3px 4px');
      expect(c['padding-left'], const CssLengthSpec(px: 4));
      invalid('margin', '1px 2px 3px 4px 5px');
    });

    test('unidades absolutas viram px', () {
      expect(single('font-size', '12pt'), const CssLengthSpec(px: 16));
      expect(single('margin-top', '1pc'), const CssLengthSpec(px: 16));
      expect(single('margin-top', '1in'), const CssLengthSpec(px: 96));
      expect(single('margin-top', '2.54cm'), const CssLengthSpec(px: 96));
      expect(single('margin-top', '25.4mm'), const CssLengthSpec(px: 96));
      expect(single('margin-top', '101.6Q'), const CssLengthSpec(px: 96));
      expect(single('margin-top', '2ch'), const CssLengthSpec(ex: 2));
      expect(single('margin-top', '1rem'), const CssLengthSpec(rem: 1));
      expect(single('max-height', '50vh'), const CssLengthSpec(vh: 50));
      invalid('margin-top', '1vmin');
      invalid('margin-top', '1deg');
    });

    test('0 sem unidade é comprimento; outros números não', () {
      expect(single('margin-top', '0'), const CssLengthSpec());
      invalid('margin-top', '5');
      invalid('width', '100');
    });

    test('negativos inválidos onde a especificação proíbe', () {
      invalid('padding', '-1px');
      invalid('padding-left', '-1em');
      invalid('font-size', '-2em');
      invalid('line-height', '-1');
      invalid('line-height', '-1em');
      invalid('width', '-10%');
      invalid('max-height', '-1px');
      invalid('border-width', '-1px');
      expect(single('margin-left', '-1em'), const CssLengthSpec(em: -1));
      expect(single('text-indent', '-2em'), const CssLengthSpec(em: -2));
    });

    test('line-height', () {
      expect(single('line-height', '150%'), const CssLengthSpec(percent: 150));
      expect(single('line-height', '1.5'), const CssNumber(1.5));
      expect(single('line-height', '0'), const CssNumber(0));
      expect(single('line-height', 'normal'), kw('normal'));
      expect(single('line-height', '1.2em'), const CssLengthSpec(em: 1.2));
    });

    test('valores extremos ficam finitos e limitados (Review Focus 4)', () {
      final v = single('width', '1e30px') as CssLengthSpec;
      expect(v.px, kCssMaxMagnitude);
      final w = single('margin-top', '-1e30em') as CssLengthSpec;
      expect(w.em, -kCssMaxMagnitude);
      expect(single('z-index', '99999999999'), const CssNumber(2147483647));
      expect(single('z-index', '-99999999999'), const CssNumber(-2147483648));
      final c =
          single('width', 'calc(1e300px * 1e300 * 1e300)') as CssLengthSpec;
      expect(c.px.isFinite, isTrue);
      expect(c.px, kCssMaxMagnitude);
      final d = single('width', 'calc(1px / 1e-320)') as CssLengthSpec;
      expect(d.px, kCssMaxMagnitude);
    });
  });

  group('calc()', () {
    test('forma linear', () {
      expect(
        single('width', 'calc(100% - 2em)'),
        const CssLengthSpec(percent: 100, em: -2),
      );
      expect(single('width', 'calc(2em * 3)'), const CssLengthSpec(em: 6));
      expect(
        single('width', 'calc(3 * (1px + 1em) / 2)'),
        const CssLengthSpec(px: 1.5, em: 1.5),
      );
      expect(
        single('margin-top', 'calc(1px + 2px * 3)'),
        const CssLengthSpec(px: 7),
      );
      expect(single('margin-top', 'calc((1px))'), const CssLengthSpec(px: 1));
      expect(
        single('margin-top', 'calc(1px + calc(2pt * 3))'),
        const CssLengthSpec(px: 9),
      );
    });

    test('inválidos', () {
      invalid('width', 'calc(1px * 1px)');
      invalid('width', 'calc(1px / 0)');
      invalid('width', 'calc(1px / 1px)');
      invalid('width', 'calc(1px + 2)');
      invalid('width', 'calc(1px +2px)');
      invalid('width', 'calc(1px -2px)');
      invalid('width', 'calc(1px+ 2px)');
      invalid('width', 'calc()');
      invalid('width', 'calc(1px +)');
      invalid('width', 'calc(2)');
      invalid('width', 'calc(1px + var(--x))');
      invalid('width', 'min(1px, 2px)');
      invalid('width', 'max(1px, 2px)');
      invalid('width', 'clamp(1px, 2px, 3px)');
      invalid('width', 'var(--x)');
      invalid('color', 'var(--c)');
    });

    test('aninhamento até 32 níveis; além disso inválido', () {
      String nested(int depth) =>
          'calc(${'(' * (depth - 1)}1px${')' * (depth - 1)})';
      expect(single('width', nested(32)), const CssLengthSpec(px: 1));
      invalid('width', nested(33));
      invalid('width', nested(5000));
    });
  });

  group('aliases', () {
    test('hifenização', () {
      for (final n in [
        '-webkit-hyphens',
        '-epub-hyphens',
        '-moz-hyphens',
        '-ms-hyphens',
      ]) {
        expect(longhands(n, 'auto'), {'hyphens': kw('auto')});
      }
      expect(longhands('adobe-hyphenate', 'none'), {'hyphens': kw('none')});
      expect(longhands('adobe-hyphenate', 'explicit'), {
        'hyphens': kw('manual'),
      });
    });

    test('quebras de página', () {
      expect(longhands('page-break-after', 'always'), {
        'break-after': kw('page'),
      });
      expect(longhands('page-break-before', 'avoid'), {
        'break-before': kw('avoid'),
      });
      expect(longhands('page-break-before', 'right'), {
        'break-before': kw('right'),
      });
      expect(longhands('page-break-inside', 'avoid'), {
        'break-inside': kw('avoid'),
      });
      invalid('page-break-inside', 'always');
      expect(longhands('page-break-after', 'inherit'), {
        'break-after': kw('inherit'),
      });
    });

    test('escrita, combinação, ênfase e word-wrap', () {
      expect(longhands('-epub-text-combine', 'horizontal'), {
        'text-combine-upright': kw('all'),
      });
      expect(longhands('-epub-writing-mode', 'vertical-rl'), {
        'writing-mode': kw('vertical-rl'),
      });
      expect(longhands('-webkit-writing-mode', 'horizontal-tb'), {
        'writing-mode': kw('horizontal-tb'),
      });
      expect(longhands('-epub-text-emphasis-style', 'sesame'), {
        'text-emphasis-style': CssList([kw('sesame')]),
      });
      expect(longhands('-epub-text-emphasis-color', 'red'), {
        'text-emphasis-color': const CssColor(0xFFFF0000),
      });
      expect(longhands('word-wrap', 'break-word'), {
        'overflow-wrap': kw('break-word'),
      });
    });
  });

  group('abreviadas', () {
    test('font completa', () {
      final m = longhands('font', 'italic bold 12px/1.5 Georgia, serif');
      expect(m['font-style'], kw('italic'));
      expect(m['font-weight'], const CssNumber(700));
      expect(m['font-size'], const CssLengthSpec(px: 12));
      expect(m['line-height'], const CssNumber(1.5));
      expect(
        m['font-family'],
        const CssFontFamilies([
          FontFamilyName('Georgia'),
          FontFamilyName('serif', generic: true),
        ]),
      );
      expect(m['font-variant'], kw('normal'));
      expect(m['font-variant-numeric'], kw('normal'));
    });

    test('font mínima reinicia as demais', () {
      final m = longhands('font', '1em serif');
      expect(m['font-style'], kw('normal'));
      expect(m['font-weight'], const CssNumber(400));
      expect(m['line-height'], kw('normal'));
      expect(m['font-size'], const CssLengthSpec(em: 1));
      final n = longhands('font', 'small-caps 700 large/120% "Body Text"');
      expect(n['font-variant'], kw('small-caps'));
      expect(n['font-weight'], const CssNumber(700));
      expect(n['font-size'], kw('large'));
      expect(n['line-height'], const CssLengthSpec(percent: 120));
    });

    test('font inválida e fontes de sistema', () {
      invalid('font', 'caption');
      invalid('font', 'menu');
      invalid('font', 'bold serif');
      invalid('font', '12px');
      invalid('font', 'italic italic 12px serif');
    });

    test('border expande em 12 longhands', () {
      final m = longhands('border', '1px solid black');
      expect(m, hasLength(12));
      for (final side in ['top', 'right', 'bottom', 'left']) {
        expect(m['border-$side-width'], const CssLengthSpec(px: 1));
        expect(m['border-$side-style'], kw('solid'));
        expect(m['border-$side-color'], const CssColor(0xFF000000));
      }
      final n = longhands('border', 'none');
      expect(n['border-top-width'], const CssLengthSpec(px: 3));
      expect(n['border-top-style'], kw('none'));
      expect(n['border-top-color'], kw('currentcolor'));
      invalid('border', '1px 2px solid');
    });

    test('border de um lado, larguras nomeadas e listas por lado', () {
      final m = longhands('border-bottom', 'thin dotted gray');
      expect(m, hasLength(3));
      expect(m['border-bottom-width'], const CssLengthSpec(px: 1));
      expect(m['border-bottom-style'], kw('dotted'));
      expect(m['border-bottom-color'], const CssColor(0xFF808080));
      expect(single('border-top-width', 'thick'), const CssLengthSpec(px: 5));
      expect(single('border-top-width', 'medium'), const CssLengthSpec(px: 3));
      final w = longhands('border-width', '1px 2px');
      expect(w['border-top-width'], const CssLengthSpec(px: 1));
      expect(w['border-left-width'], const CssLengthSpec(px: 2));
      final s = longhands('border-style', 'solid dashed dotted double');
      expect(s['border-left-style'], kw('double'));
      final c = longhands('border-color', 'red');
      expect(c, hasLength(4));
    });

    test('border-radius ignora a parte após /', () {
      final m = longhands('border-radius', '1px 2px / 5px');
      expect(m['border-top-left-radius'], const CssLengthSpec(px: 1));
      expect(m['border-top-right-radius'], const CssLengthSpec(px: 2));
      expect(m['border-bottom-right-radius'], const CssLengthSpec(px: 1));
      expect(m['border-bottom-left-radius'], const CssLengthSpec(px: 2));
      invalid('border-radius', '-1px');
    });

    test('text-decoration', () {
      expect(longhands('text-decoration', 'underline overline'), {
        'text-decoration-line': CssList([kw('underline'), kw('overline')]),
        'text-decoration-style': kw('solid'),
        'text-decoration-color': kw('currentcolor'),
      });
      final m = longhands('text-decoration', 'line-through dashed red');
      expect(m['text-decoration-line'], CssList([kw('line-through')]));
      expect(m['text-decoration-style'], kw('dashed'));
      expect(m['text-decoration-color'], const CssColor(0xFFFF0000));
      expect(
        longhands('text-decoration', 'none')['text-decoration-line'],
        kw('none'),
      );
      invalid('text-decoration', 'underline underline');
    });

    test('CSS-wide sozinho vale para todas as longhands', () {
      final m = longhands('margin', 'inherit');
      expect(m, hasLength(4));
      expect(m.values.every((v) => v == kw('inherit')), isTrue);
      expect(longhands('border', 'initial'), hasLength(12));
      expect(longhands('font', 'unset'), hasLength(7));
      invalid('margin', 'inherit 1px');
    });

    test('background', () {
      final m = longhands(
        'background',
        '#fff url(../img/a.png) no-repeat right 10px top / cover fixed',
      );
      expect(m['background-color'], const CssColor(0xFFFFFFFF));
      expect(m['background-image'], const CssUrl('OEBPS/img/a.png'));
      expect(m['background-repeat'], kw('no-repeat'));
      expect(
        m['background-position'],
        const CssList([CssLengthSpec(percent: 100, px: -10), CssLengthSpec()]),
      );
      expect(m['background-size'], kw('cover'));
      final n = longhands('background', 'white');
      expect(n['background-image'], kw('none'));
      expect(n['background-color'], const CssColor(0xFFFFFFFF));
      invalid('background', 'red, blue');
    });

    test('background-position e background-size', () {
      expect(
        single('background-position', 'center'),
        const CssList([CssLengthSpec(percent: 50), CssLengthSpec(percent: 50)]),
      );
      expect(
        single('background-position', 'top left'),
        const CssList([CssLengthSpec(), CssLengthSpec()]),
      );
      expect(
        single('background-position', '10px bottom'),
        const CssList([CssLengthSpec(px: 10), CssLengthSpec(percent: 100)]),
      );
      invalid('background-position', 'left right');
      expect(
        single('background-size', '50%'),
        CssList([const CssLengthSpec(percent: 50), kw('auto')]),
      );
      expect(single('background-size', 'contain'), kw('contain'));
    });

    test('list-style', () {
      final m = longhands('list-style', 'none');
      expect(m['list-style-type'], kw('none'));
      expect(m['list-style-image'], kw('none'));
      expect(m['list-style-position'], kw('outside'));
      final n = longhands('list-style', 'square inside');
      expect(n['list-style-type'], kw('square'));
      expect(n['list-style-position'], kw('inside'));
      invalid('list-style', 'none none none');
    });
  });

  group('propriedades e valores diversos', () {
    test('ignoradas e não suportadas', () {
      expect(parse('speak', 'none'), isA<IgnoredProperty>());
      expect(parse('background-attachment', 'fixed'), isA<IgnoredProperty>());
      expect(parse('filter', 'invert(1)'), isA<UnsupportedProperty>());
      expect(parse('--x', '1'), isA<UnsupportedProperty>());
      expect(parse('box-shadow', 'none'), isA<UnsupportedProperty>());
      expect(parse('all', 'initial'), isA<UnsupportedProperty>());
      expect(parse('transform', 'none'), isA<UnsupportedProperty>());
      expect(parse('transition-duration', '1s'), isA<UnsupportedProperty>());
    });

    test('content', () {
      expect(
        single('content', '"«" attr(title) open-quote'),
        const CssContent([
          ContentText('«'),
          ContentAttr('title'),
          ContentQuote(QuoteKind.open),
        ]),
      );
      expect(
        single('content', 'counter(n, upper-roman) no-close-quote'),
        const CssContent([
          ContentCounter('n', CssKeywords.upperRoman),
          ContentQuote(QuoteKind.noClose),
        ]),
      );
      expect(
        single('content', 'counter(n)'),
        const CssContent([ContentCounter('n', CssKeywords.decimal)]),
      );
      expect(single('content', 'none'), kw('none'));
      invalid('content', 'counters(n, ".")');
      invalid('content', 'banana');
    });

    test('quotes e contadores', () {
      expect(
        single('quotes', '"«" "»" "‹" "›"'),
        const CssQuotes([('«', '»'), ('‹', '›')]),
      );
      invalid('quotes', '"«"');
      expect(
        single('counter-reset', 'a b 3'),
        const CssCounterChanges([('a', 0), ('b', 3)]),
      );
      expect(
        single('counter-increment', 'a -2 b'),
        const CssCounterChanges([('a', -2), ('b', 1)]),
      );
      invalid('counter-reset', 'a 1.5');
      invalid('counter-reset', 'none a');
    });

    test('font-family', () {
      expect(
        single('font-family', '"Body Text", monospaced'),
        const CssFontFamilies([
          FontFamilyName('Body Text'),
          FontFamilyName('monospaced'),
        ]),
      );
      expect(
        single('font-family', 'Times  New Roman, SERIF'),
        const CssFontFamilies([
          FontFamilyName('Times New Roman'),
          FontFamilyName('serif', generic: true),
        ]),
      );
      expect(
        single('font-family', '"serif"'),
        const CssFontFamilies([FontFamilyName('serif')]),
      );
      invalid('font-family', 'a,');
      invalid('font-family', 'a, inherit');
      invalid('font-family', '12px');
    });

    test('font-weight', () {
      expect(single('font-weight', 'bold'), const CssNumber(700));
      expect(single('font-weight', 'normal'), const CssNumber(400));
      expect(single('font-weight', '1000'), const CssNumber(1000));
      expect(single('font-weight', 'bolder'), kw('bolder'));
      invalid('font-weight', '0');
      invalid('font-weight', '1001');
    });

    test('números sem unidade só onde permitido', () {
      expect(single('opacity', '0.5'), const CssNumber(0.5));
      expect(single('opacity', '50%'), const CssNumber(0.5));
      expect(single('opacity', '7'), const CssNumber(1));
      expect(single('orphans', '3'), const CssNumber(3));
      invalid('orphans', '0');
      invalid('widows', '1.5');
      invalid('z-index', '1.5');
      expect(single('z-index', 'auto'), kw('auto'));
    });

    test('url resolvido no zip; externo ou fora do zip inválido', () {
      expect(
        single('background-image', 'url(../img/a.png)'),
        const CssUrl('OEBPS/img/a.png'),
      );
      expect(
        single('background-image', 'url("../img/b c.png")'),
        const CssUrl('OEBPS/img/b c.png'),
      );
      expect(
        single('list-style-image', 'URL(i.png)'),
        const CssUrl('OEBPS/css/i.png'),
      );
      invalid('background-image', 'url(http://x.com/a.png)');
      invalid('background-image', 'url(data:image/png;base64,AAAA)');
      invalid('background-image', 'url(../../../a.png)');
      invalid('background-image', 'linear-gradient(red, blue)');
    });

    test('palavras-chave por propriedade', () {
      expect(single('text-align', 'justify'), kw('justify'));
      invalid('text-align', 'axis');
      expect(single('writing-mode', 'tb-rl'), kw('vertical-rl'));
      expect(single('writing-mode', 'rl-tb'), kw('horizontal-tb'));
      expect(single('vertical-align', 'super'), kw('super'));
      expect(single('vertical-align', '-0.2em'), const CssLengthSpec(em: -0.2));
      expect(single('text-wrap', 'balance'), kw('balance'));
      expect(
        single('hanging-punctuation', 'last first'),
        CssList([kw('first'), kw('last')]),
      );
      expect(
        single('font-variant-numeric', 'tabular-nums oldstyle-nums'),
        CssList([kw('oldstyle-nums'), kw('tabular-nums')]),
      );
      expect(single('text-emphasis-style', '"x"'), const CssString('x'));
      expect(
        single('text-emphasis-style', 'open circle'),
        CssList([kw('open'), kw('circle')]),
      );
      expect(
        single('border-spacing', '2px'),
        const CssList([CssLengthSpec(px: 2), CssLengthSpec(px: 2)]),
      );
      expect(single('break-after', 'page'), kw('page'));
      expect(single('max-width', 'none'), kw('none'));
      expect(single('width', 'auto'), kw('auto'));
      expect(single('list-style-type', 'lower-alpha'), kw('lower-alpha'));
      invalid('display', 'inline flow');
      invalid('float', 'center');
    });

    test('valor vazio e lixo são inválidos', () {
      invalid('color', '');
      invalid('margin-top', '1px 2px');
      invalid('display', 'block !');
    });
  });

  group('tabela', () {
    test('ids, nomes e valores iniciais', () {
      expect(kPropertyCount, 97);
      final names = <String>{};
      for (var id = 0; id < kPropertyCount; id++) {
        names.add(propertyInfo(id).name);
      }
      expect(names, hasLength(kPropertyCount));
      expect(propertyInfo(PropertyId.color).inherited, isTrue);
      expect(propertyInfo(PropertyId.marginTop).inherited, isFalse);
      expect(propertyInfo(PropertyId.fontSize).initial, kw('medium'));
      expect(
        propertyInfo(PropertyId.borderTopWidth).initial,
        const CssLengthSpec(px: 3),
      );
    });

    test('cada longhand aceita o próprio valor inicial nomeado', () {
      for (var id = 0; id < kPropertyCount; id++) {
        final name = propertyInfo(id).name;
        expect(parse(name, 'initial'), isA<ParsedLonghands>(), reason: name);
      }
    });

    test('palavras-chave: id e nome ida e volta', () {
      for (var id = 0; id < CssKeywords.count; id++) {
        expect(CssKeywords.idOf(CssKeywords.nameOf(id)), id);
      }
      expect(CssKeywords.nameOf(CssKeywords.listItem), 'list-item');
      expect(CssKeywords.idOf('nada'), isNull);
    });

    test('todo nome do escopo, dos aliases e das ignoradas é reconhecido', () {
      const scope = [
        'font-family', 'font-size', 'font-style', 'font-weight',
        'font-variant', 'font-variant-numeric', 'font',
        'text-align', 'text-indent', 'text-transform', 'text-decoration',
        'text-decoration-line', 'text-decoration-style',
        'text-decoration-color', 'letter-spacing', 'word-spacing',
        'white-space', 'hyphens', 'line-height', 'vertical-align',
        'direction', 'unicode-bidi', 'writing-mode', 'text-combine-upright',
        'hanging-punctuation', 'overflow-wrap', 'text-emphasis-style',
        'text-emphasis-color', 'text-wrap',
        'display', 'margin', 'margin-top', 'margin-right', 'margin-bottom',
        'margin-left', 'padding', 'padding-top', 'padding-right',
        'padding-bottom', 'padding-left', 'border', 'border-top',
        'border-right', 'border-bottom', 'border-left', 'border-width',
        'border-style', 'border-color', 'border-top-width',
        'border-top-style', 'border-top-color', 'border-right-width',
        'border-right-style', 'border-right-color', 'border-bottom-width',
        'border-bottom-style', 'border-bottom-color', 'border-left-width',
        'border-left-style', 'border-left-color', 'border-radius',
        'border-top-left-radius', 'border-top-right-radius',
        'border-bottom-right-radius', 'border-bottom-left-radius',
        'width', 'height', 'min-width', 'min-height', 'max-width',
        'max-height', 'box-sizing', 'object-fit',
        'float', 'clear', 'position', 'top', 'right', 'bottom', 'left',
        'z-index', 'overflow', 'flex-direction', 'justify-content',
        'align-items',
        'color', 'background-color', 'background-image',
        'background-repeat', 'background-position', 'background-size',
        'background', 'opacity',
        'list-style', 'list-style-type', 'list-style-position',
        'list-style-image', 'border-collapse', 'border-spacing',
        'caption-side', 'table-layout', 'empty-cells',
        'break-before', 'break-after', 'break-inside', 'orphans', 'widows',
        'content', 'quotes', 'counter-increment', 'counter-reset',
        'visibility',
        // aliases
        'page-break-before', 'page-break-after', 'page-break-inside',
        '-webkit-hyphens', '-epub-hyphens', '-moz-hyphens', '-ms-hyphens',
        'adobe-hyphenate', '-epub-writing-mode', '-webkit-writing-mode',
        '-epub-text-combine', '-epub-text-emphasis-style',
        '-epub-text-emphasis-color', 'word-wrap',
      ];
      for (final n in scope) {
        expect(parse(n, 'inherit'), isA<ParsedLonghands>(), reason: n);
      }
      const ignored = [
        'speak',
        'speak-as',
        'speak-punctuation',
        'speech-rate',
        'stress',
        'volume',
        'richness',
        'pause',
        'pause-before',
        'pause-after',
        '-webkit-tap-highlight-color',
        'pointer-events',
        'adobe-text-layout',
        'background-attachment',
      ];
      for (final n in ignored) {
        expect(parse(n, 'x'), isA<IgnoredProperty>(), reason: n);
      }
    });
  });

  group('robustez', () {
    test('nenhuma propriedade lança com valores estranhos', () {
      const odd = [
        '',
        '(',
        ')',
        '[',
        '{',
        'calc(',
        'calc(1px',
        'calc(1px +',
        'rgb(',
        'rgb(1,2',
        'hsl(1 2 3 / )',
        'url(',
        'url("',
        'url()',
        '#',
        '#f',
        '/',
        '/ /',
        ',',
        ',,',
        'a,',
        '"x',
        '1px/',
        'right 10px 5px 3px',
        'left 10px top 5px center',
        'center 10px top',
        'counter(',
        'attr()',
        'counter(a,)',
        'counter(a, b, c)',
        '! important',
        '-',
        '+',
        'e',
        '1e999px',
        '-1e999',
        '99999999999999999999',
        'inherit inherit',
        'none none',
        'auto auto auto auto auto',
        '0 0 0 0 0',
        'top / 1px',
        'calc(1px) / 2px',
        'url(a) url(b)',
        'red blue',
        'italic',
        '12px /',
        '12px / 1.5',
        'bold 12px/ serif',
        'normal normal normal normal 1px a',
        'oblique 10deg 12px serif',
        '\\',
        'u+0-7f',
        '1px ) 2px',
      ];
      for (var id = 0; id < kPropertyCount; id++) {
        final name = propertyInfo(id).name;
        for (final v in odd) {
          expect(
            () => parseProperty(name, tokens(v), sheetPath: 'a/b.css'),
            returnsNormally,
            reason: '$name: $v',
          );
        }
      }
      for (final name in [
        'font',
        'margin',
        'padding',
        'border',
        'border-top',
        'border-width',
        'border-radius',
        'background',
        'list-style',
        'text-decoration',
      ]) {
        for (final v in odd) {
          expect(
            () => parseProperty(name, tokens(v), sheetPath: 'a/b.css'),
            returnsNormally,
            reason: '$name: $v',
          );
        }
      }
    });

    test('calc profundo e longo é rápido e não estoura a pilha', () {
      final deep = 'calc(${'(' * 200000}1px${')' * 200000})';
      final long = 'calc(${List.filled(100000, '1px').join(' + ')})';
      final sw = Stopwatch()..start();
      invalid('width', deep);
      expect(single('width', long), const CssLengthSpec(px: 100000));
      expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
    });
  });
}
