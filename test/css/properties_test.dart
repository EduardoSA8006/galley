// parseDeclaration: cada linha da tabela de §7.1, as conversões de §7.2, os
// atalhos e as degradadas de §7.4 (spec do CSS §7).
import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/css/computed_style.dart';
import 'package:galley/src/css/properties.dart';
import 'package:galley/src/css/tokenizer.dart';

List<CssToken> _tokens(String text) {
  final t = CssTokenizer(text);
  return [for (var k = t.next(); k.type != CssTokenType.eof; k = t.next()) k];
}

List<Declaration> _decl(String name, String value, {bool important = false}) =>
    parseDeclaration(name, _tokens(value), important: important);

/// `propriedade=valor` de cada declaração produzida.
List<String> _v(String name, String value) => [
  for (final d in _decl(name, value)) '${d.property.name}=${d.value}',
];

double _em(String name, String value) =>
    (_decl(name, value).single.value as CssEmValue).em;

void _table(String name, Map<String, List<String>> cases) {
  for (final MapEntry(key: value, value: expected) in cases.entries) {
    test('$name: $value', () => expect(_v(name, value), expected));
  }
}

void main() {
  group('display', () {
    _table('display', {
      'block': ['display=block'],
      'BLOCK': ['display=block'],
      'inline-block': ['display=inline'],
      'inline-table': ['display=inline'],
      'flex': ['display=block'],
      'grid': ['display=block'],
      'flow-root': ['display=block'],
      'table-cell': ['display=block'],
      'list-item': ['display=listItem'],
      'none': ['display=none'],
      'contents': [],
      'ruby': [],
      'block flow': [],
      'table-foo': [],
    });
  });

  group('white-space, direction, text-align, vertical-align', () {
    _table('white-space', {
      'pre-wrap': ['whiteSpace=preWrap'],
      'break-spaces': ['whiteSpace=preWrap'],
      'nowrap': ['whiteSpace=nowrap'],
      'collapse': [],
      'preserve nowrap': [],
    });
    _table('direction', {
      'rtl': ['direction=rtl'],
      'auto': [],
    });
    _table('text-align', {
      'left': ['textAlign=left'],
      'justify': ['textAlign=start'],
      'end': ['textAlign=end'],
      'Center': ['textAlign=center'],
      'match-parent': [],
      '-webkit-center': [],
    });
    _table('vertical-align', {
      'super': ['verticalAlign=sup'],
      'sub': ['verticalAlign=sub'],
      'middle': ['verticalAlign=baseline'],
      'text-top': ['verticalAlign=baseline'],
      '-0.2em': ['verticalAlign=baseline'],
      '10%': ['verticalAlign=baseline'],
      'up': [],
    });
  });

  group('listas', () {
    _table('list-style-type', {
      'square': ['listStyleType=square'],
      'lower-latin': ['listStyleType=lowerAlpha'],
      'upper-roman': ['listStyleType=upperRoman'],
      'none': ['listStyleType=none'],
      'lower-greek': ['listStyleType=unknown-list-style'],
      '"–"': ['listStyleType=unknown-list-style'],
      '3': [],
      'a b': [],
    });
    _table('list-style', {
      'square inside': ['listStyleType=square'],
      'url(x.png) outside circle': ['listStyleType=circle'],
      'none': ['listStyleType=none'],
      'inside': ['listStyleType=disc'],
      'url(x.png)': ['listStyleType=disc'],
      'none url(x.png)': ['listStyleType=none'],
      'square none': ['listStyleType=square'],
      'none none': ['listStyleType=none'],
      'square url(x.png) none': [],
      // O segundo inside/outside é um <counter-style-name> (CSS Counter Styles
      // 3 §3.1); o Chromium aceita.
      'inside outside': ['listStyleType=unknown-list-style'],
      'inside outside inside': [],
      'square inside outside': [],
      'square circle': [],
    });
  });

  group('quebras (page-break-* é a mesma propriedade)', () {
    _table('break-before', {
      'page': ['breakBefore=page'],
      'recto': ['breakBefore=page'],
      'avoid-page': ['breakBefore=avoid'],
      'column': ['breakBefore=auto'],
      'avoid-region': ['breakBefore=auto'],
    });
    _table('page-break-before', {
      'always': ['breakBefore=page'],
      'left': ['breakBefore=page'],
      'avoid': ['breakBefore=avoid'],
      'page': [],
    });
    _table('page-break-after', {
      'always': ['breakAfter=page'],
    });
    _table('break-inside', {
      'avoid-column': ['breakInside=avoid'],
      'auto': ['breakInside=auto'],
      'page': [],
    });
    _table('page-break-inside', {
      'avoid': ['breakInside=avoid'],
      'avoid-page': [],
    });
  });

  group('width e height', () {
    _table('width', {
      'auto': ['width=auto'],
      '50%': ['width=50.0%'],
      '250%': ['width=100.0%'],
      '32px': ['width=2.0em'],
      '0': ['width=0.0em'],
      '2000em': ['width=100.0em'],
      '-1em': [],
      '-10%': [],
      'min-content': [],
      'calc(1em)': [],
    });
  });

  group('fonte', () {
    _table('font-style', {
      'italic': ['fontStyle=italic'],
      'ITALIC': ['fontStyle=italic'],
      'oblique': ['fontStyle=italic'],
      'oblique 10deg': ['fontStyle=italic'],
      'oblique 90deg': ['fontStyle=italic'],
      'oblique -90deg': ['fontStyle=italic'],
      'oblique 91deg': [],
      'oblique -91deg': [],
      'oblique 90.0001deg': [],
      'oblique 0': [],
      'oblique 10px': [],
      'normal': ['fontStyle=normal'],
    });
    _table('font-weight', {
      'bold': ['fontWeight=700'],
      'Bold': ['fontWeight=700'],
      'normal': ['fontWeight=400'],
      'bolder': ['fontWeight=bolder'],
      'lighter': ['fontWeight=lighter'],
      '1': ['fontWeight=1'],
      '1000': ['fontWeight=1000'],
      '650': ['fontWeight=650'],
      '650.5': ['fontWeight=650.5'],
      '0': [],
      '1001': [],
      'heavy': [],
    });
    _table('font-variant', {
      'small-caps': ['fontVariant=smallCaps'],
      'all-small-caps': ['fontVariant=smallCaps'],
      'oldstyle-nums small-caps': ['fontVariant=smallCaps'],
      'oldstyle-nums': ['fontVariant=normal'],
      'normal': ['fontVariant=normal'],
      'none': ['fontVariant=normal'],
      'stylistic(x)': ['fontVariant=normal'],
      'small-caps swash(a) tabular-nums': ['fontVariant=smallCaps'],
      'sub': ['fontVariant=normal'],
      'emoji': ['fontVariant=normal'],
      'ordinal slashed-zero': ['fontVariant=normal'],
      'tabular-nums diagonal-fractions': ['fontVariant=normal'],
      'common-ligatures discretionary-ligatures': ['fontVariant=normal'],
      'full-width ruby': ['fontVariant=normal'],
      // Chromium 153: cada subgrupo no máximo uma vez (CSS Fonts 4 §6.6).
      'foo': [],
      'a a': [],
      'small-caps foo': [],
      'normal small-caps': [],
      'none small-caps': [],
      'small-caps petite-caps': [],
      'small-caps small-caps': [],
      'lining-nums oldstyle-nums': [],
      'tabular-nums proportional-nums': [],
      'common-ligatures no-common-ligatures': [],
      'contextual no-contextual': [],
      'jis78 jis83': [],
      'sub super': [],
      'swash(a) swash(b)': [],
      'unknown(x)': [],
      '"x"': [],
      '2': [],
    });
    _table('font-variant-caps', {
      'small-caps': ['fontVariant=smallCaps'],
      'all-small-caps': ['fontVariant=smallCaps'],
      'petite-caps': ['fontVariant=normal'],
      'titling-caps': ['fontVariant=normal'],
      'normal': ['fontVariant=normal'],
      'foo': [],
      'none': [],
      'small-caps all-small-caps': [],
      'oldstyle-nums': [],
    });
    _table('text-transform', {
      'uppercase': ['textTransform=uppercase'],
      'capitalize': ['textTransform=capitalize'],
      'full-width': [],
      'uppercase full-width': [],
    });
    _table('font-size', {
      '2em': ['fontSize=larger'],
      '1.5rem': ['fontSize=larger'],
      '1.05em': ['fontSize=same'],
      '1.06em': ['fontSize=larger'],
      '0.95em': ['fontSize=same'],
      '0.94em': ['fontSize=smaller'],
      '80%': ['fontSize=smaller'],
      '2ex': ['fontSize=same'],
      '1ch': ['fontSize=smaller'],
      'smaller': ['fontSize=smaller'],
      'larger': ['fontSize=larger'],
      '12px': [],
      '10pt': [],
      'medium': [],
      'x-large': [],
      '-1em': [],
      '0': [],
      'inherit': ['fontSize=inherit'],
    });
  });

  group('font (atalho)', () {
    _table('font', {
      'italic small-caps bold 1.2em/1.5 Georgia, serif': [
        'fontStyle=italic',
        'fontVariant=smallCaps',
        'fontWeight=700',
        'fontSize=larger',
      ],
      '1em serif': [
        'fontStyle=normal',
        'fontVariant=normal',
        'fontWeight=400',
        'fontSize=same',
      ],
      'bold 12px "Times New Roman"': [
        'fontStyle=normal',
        'fontVariant=normal',
        'fontWeight=700',
      ],
      '600 condensed 80% sans-serif': [
        'fontStyle=normal',
        'fontVariant=normal',
        'fontWeight=600',
        'fontSize=smaller',
      ],
      'oblique 91deg 1em x': [],
      'oblique 10deg 1em x': [
        'fontStyle=italic',
        'fontVariant=normal',
        'fontWeight=400',
        'fontSize=same',
      ],
      'normal normal normal normal 1em x': [
        'fontStyle=normal',
        'fontVariant=normal',
        'fontWeight=400',
        'fontSize=same',
      ],
      'normal normal normal normal normal 1em x': [],
      'caption': [],
      'italic 1em': [],
      'italic serif': [],
      'italic italic 1em x': [],
      // Um 0 (ou número fora de [1, 1000]) no prefixo não é peso: é o tamanho.
      '0 serif': ['fontStyle=normal', 'fontVariant=normal', 'fontWeight=400'],
      '0/0 a': ['fontStyle=normal', 'fontVariant=normal', 'fontWeight=400'],
      '1001 serif': [],
      // Família (CSS Fonts 4 §3.1): global e `default` só como primeiro ident.
      '1em inherit': [],
      '1em default': [],
      '1em a, inherit': [],
      '1em a, default': [],
      '1em default, a': [],
      '1em INHERIT': [],
      '1em "a" b': [],
      '1em a "b"': [],
      '1em "a" "b"': [],
      '1em a inherit': [
        'fontStyle=normal',
        'fontVariant=normal',
        'fontWeight=400',
        'fontSize=same',
      ],
      '1em inherit b': [
        'fontStyle=normal',
        'fontVariant=normal',
        'fontWeight=400',
        'fontSize=same',
      ],
      '1em default b': [
        'fontStyle=normal',
        'fontVariant=normal',
        'fontWeight=400',
        'fontSize=same',
      ],
      '1em a, inherit b': [
        'fontStyle=normal',
        'fontVariant=normal',
        'fontWeight=400',
        'fontSize=same',
      ],
      '1em a, default b': [
        'fontStyle=normal',
        'fontVariant=normal',
        'fontWeight=400',
        'fontSize=same',
      ],
      '1em unset b': [
        'fontStyle=normal',
        'fontVariant=normal',
        'fontWeight=400',
        'fontSize=same',
      ],
      '1em/-1 x': [],
      '1em/-1% x': [],
      '1em/1foo x': [],
      '1em/0 x': [
        'fontStyle=normal',
        'fontVariant=normal',
        'fontWeight=400',
        'fontSize=same',
      ],
      '1em/ x': [],
      '1em x,': [],
      '1em x, , y': [],
      'inherit': [
        'fontStyle=inherit',
        'fontVariant=inherit',
        'fontWeight=inherit',
        'fontSize=inherit',
      ],
    });
  });

  group('text-decoration', () {
    _table('text-decoration-line', {
      'underline': ['textDecoration=decoration(u=true, s=false)'],
      'underline line-through': ['textDecoration=decoration(u=true, s=true)'],
      'overline blink': ['textDecoration=decoration(u=false, s=false)'],
      'none': ['textDecoration=decoration(u=false, s=false)'],
      'underline underline': [],
      'none underline': [],
      'wavy': [],
      '"x"': [],
    });
    _table('text-decoration', {
      'underline': ['textDecoration=decoration(u=true, s=false)'],
      'line-through wavy red 2px': [
        'textDecoration=decoration(u=false, s=true)',
      ],
      'underline dotted #f00 from-font': [
        'textDecoration=decoration(u=true, s=false)',
      ],
      'rgb(1 2 3) underline': ['textDecoration=decoration(u=true, s=false)'],
      'solid blue': ['textDecoration=decoration(u=false, s=false)'],
      'none': ['textDecoration=decoration(u=false, s=false)'],
      'underline double transparent 0': [
        'textDecoration=decoration(u=true, s=false)',
      ],
      'AccentColor ButtonHighlight': [],
      'underline -1px': ['textDecoration=decoration(u=true, s=false)'],
      'underline 10% currentColor': [
        'textDecoration=decoration(u=true, s=false)',
      ],
      'underline min(1px, 2px) #abcd': [
        'textDecoration=decoration(u=true, s=false)',
      ],
      'foo': [],
      'red blue': [],
      'underline 2px 3px': [],
      'underline solid dotted': [],
      'underline from-font auto': [],
      'underline 5': [],
      'underline foo()': [],
      // As linhas são um componente só, contíguas (CSS Text Decoration 3
      // §2.4); o Chromium recusa a intercalada.
      'underline red overline': [],
      'underline 2px line-through': [],
      'underline overline red': ['textDecoration=decoration(u=true, s=false)'],
      'red underline overline': ['textDecoration=decoration(u=true, s=false)'],
      'underline #ggg': [],
      'none underline': [],
      '"x"': [],
    });
  });

  group('margem, padding e recuo (§7.2)', () {
    test('conversões de unidade', () {
      expect(_em('margin-top', '1em'), 1);
      expect(_em('margin-top', '2rem'), 2);
      expect(_em('margin-top', '2ex'), 1);
      expect(_em('margin-top', '2ch'), 1);
      expect(_em('margin-top', '16px'), 1);
      expect(_em('margin-top', '12pt'), 1);
      expect(_em('margin-top', '1pc'), 1);
      expect(_em('margin-top', '1in'), 6);
      expect(_em('margin-top', '1cm'), closeTo(2.3622, 1e-4));
      expect(_em('margin-top', '1mm'), closeTo(0.23622, 1e-5));
      expect(_em('margin-top', '1q'), closeTo(0.059055, 1e-6));
      expect(_em('margin-top', '10%'), closeTo(3, 1e-9));
      expect(_em('margin-top', '0'), 0);
    });

    _table('margin-left', {
      'auto': ['marginLeft=0.0em'],
      '-2em': ['marginLeft=0.0em'],
      '20em': ['marginLeft=8.0em'],
      '5': [],
      '1vw': [],
      'calc(1em + 2px)': [],
      '1e999em': [],
      '1foo': [],
    });
    _table('padding-left', {
      '2.5em': ['paddingLeft=2.5em'],
      '20em': ['paddingLeft=8.0em'],
      '-1em': [],
      'auto': [],
    });
    _table('text-indent', {
      '1em': ['textIndent=1.0em'],
      '-10em': ['textIndent=-4.0em'],
      '100px': ['textIndent=6.25em'],
      '1em hanging': [],
      'each-line': [],
    });

    test('valor não finito (1e999, literal de 100 dígitos) é recusado', () {
      for (final n in ['1e999', '-1e999', '1' * 100]) {
        expect(_decl('font-weight', n), isEmpty, reason: n);
        expect(_decl('width', '${n}px'), isEmpty, reason: n);
        expect(_decl('width', '$n%'), isEmpty, reason: n);
        expect(_decl('margin-top', '${n}em'), isEmpty, reason: n);
        expect(_decl('text-indent', '${n}px'), isEmpty, reason: n);
        expect(_decl('font-size', '${n}em'), isEmpty, reason: n);
        expect(_decl('column-count', n), isEmpty, reason: n);
        expect(_decl('column-width', '${n}px'), isEmpty, reason: n);
        expect(_decl('font-style', 'oblique ${n}deg'), isEmpty, reason: n);
        expect(_decl('font', '$n 1em x'), isEmpty, reason: n);
        expect(_decl('font', '1em/$n x'), isEmpty, reason: n);
        expect(_decl('vertical-align', '${n}px'), isEmpty, reason: n);
        expect(
          _decl('text-decoration', 'underline ${n}px'),
          isEmpty,
          reason: n,
        );
      }
    });

    test('literal numérico longo (NaN) descarta', () {
      expect(_decl('margin-top', '${'1' * 100}em'), isEmpty);
    });
  });

  group('atalhos de caixa', () {
    _table('margin', {
      '1em': [
        'marginTop=1.0em',
        'marginRight=1.0em',
        'marginBottom=1.0em',
        'marginLeft=1.0em',
      ],
      '1em 2em': [
        'marginTop=1.0em',
        'marginRight=2.0em',
        'marginBottom=1.0em',
        'marginLeft=2.0em',
      ],
      '1em 2em 3em': [
        'marginTop=1.0em',
        'marginRight=2.0em',
        'marginBottom=3.0em',
        'marginLeft=2.0em',
      ],
      '1em 2em 3em 4em': [
        'marginTop=1.0em',
        'marginRight=2.0em',
        'marginBottom=3.0em',
        'marginLeft=4.0em',
      ],
      '1em 2em 3em 4em 5em': [],
      '1em x': [],
    });
    _table('padding', {'0 auto': [], '1em -1em': []});
  });

  group('palavras globais', () {
    test('inherit, initial e unset em longhand e em atalho', () {
      expect(_v('display', 'inherit'), ['display=inherit']);
      expect(_v('margin', 'INITIAL'), [
        'marginTop=initial',
        'marginRight=initial',
        'marginBottom=initial',
        'marginLeft=initial',
      ]);
      expect(_v('list-style', 'unset'), ['listStyleType=unset']);
      expect(_v('columns', 'inherit'), [
        'columnCount=inherit',
        'columnWidth=inherit',
      ]);
    });

    test(
      'revert e revert-layer descartam; palavra global com mais algo também',
      () {
        expect(_decl('display', 'revert'), isEmpty);
        expect(_decl('display', 'revert-layer'), isEmpty);
        expect(_decl('display', 'inherit block'), isEmpty);
      },
    );

    test('var() em qualquer lugar descarta', () {
      expect(_decl('margin', '1em var(--x)'), isEmpty);
      expect(_decl('display', 'VAR(--d)'), isEmpty);
    });

    test('propriedade fora da tabela e customizada: vazio', () {
      expect(_decl('color', 'red'), isEmpty);
      expect(_decl('margin-inline-start', '1em'), isEmpty);
      expect(_decl('--x', '1em'), isEmpty);
    });

    test('!important vai para a declaração', () {
      expect(
        _decl('display', 'block', important: true).single.important,
        isTrue,
      );
    });
  });

  group('all (CSS Cascade 4 §3.2)', () {
    final allButDirection = [
      for (final p in CssProperty.values)
        if (p != CssProperty.direction) p,
    ];

    for (final (word, wide) in [
      ('initial', CssWide.initial),
      ('INHERIT', CssWide.inherit),
      ('unset', CssWide.unset),
    ]) {
      test('all: $word vale para todas as longhands, menos direction', () {
        final ds = _decl('all', word, important: true);
        expect(ds.map((d) => d.property), allButDirection);
        for (final d in ds) {
          expect((d.value as CssWideKeyword).keyword, wide);
          expect(d.important, isTrue);
        }
      });
    }

    test('revert, revert-layer e outro valor descartam', () {
      expect(_decl('all', 'revert'), isEmpty);
      expect(_decl('all', 'revert-layer'), isEmpty);
      expect(_decl('all', 'none'), isEmpty);
      expect(_decl('all', 'block'), isEmpty);
      expect(_decl('all', 'initial inherit'), isEmpty);
      expect(_decl('all', '0'), isEmpty);
    });
  });

  group('degradadas (§7.4)', () {
    _table('float', {
      'left': ['float=left (degrada)'],
      'inline-end': ['float=inline-end (degrada)'],
      'none': ['float=none'],
      'footnote': [],
    });
    _table('position', {
      'absolute': ['position=absolute (degrada)'],
      'sticky': ['position=sticky (degrada)'],
      'relative': ['position=relative'],
      'static': ['position=static'],
    });
    _table('column-count', {
      '2': ['columnCount=2 (degrada)'],
      '1': ['columnCount=1'],
      'auto': ['columnCount=auto'],
      '0': [],
      '2.5': [],
    });
    _table('column-width', {
      '10em': ['columnWidth=10em (degrada)'],
      'auto': ['columnWidth=auto'],
      '-1em': [],
    });
    _table('columns', {
      '3': ['columnCount=3 (degrada)', 'columnWidth=auto'],
      '12em': ['columnCount=auto', 'columnWidth=12em (degrada)'],
      '2 10em': ['columnCount=2 (degrada)', 'columnWidth=10em (degrada)'],
      'auto 1': ['columnCount=1', 'columnWidth=auto'],
      'auto': ['columnCount=auto', 'columnWidth=auto'],
      '2 3': [],
      'auto auto auto': [],
      // 0 não é contagem, mas é comprimento (CSS Multi-column 1 §3.3).
      '0': ['columnCount=auto', 'columnWidth=0 (degrada)'],
      '0 2': ['columnCount=2 (degrada)', 'columnWidth=0 (degrada)'],
      '2 0': ['columnCount=2 (degrada)', 'columnWidth=0 (degrada)'],
      '0 0': [],
      '-1': [],
    });
    _table('writing-mode', {
      'vertical-rl': ['writingMode=vertical-rl (degrada)'],
      'tb-rl': ['writingMode=tb-rl (degrada)'],
      'horizontal-tb': ['writingMode=horizontal-tb'],
      'lr-tb': ['writingMode=lr-tb'],
      'sideways': [],
    });
    _table('-epub-writing-mode', {
      'vertical-rl': ['writingMode=vertical-rl (degrada)'],
    });
    _table('-webkit-writing-mode', {
      'horizontal-tb': ['writingMode=horizontal-tb'],
    });
  });

  group('CssProperty', () {
    test('um slot por propriedade: 26 da tabela e 5 degradadas', () {
      expect(CssProperty.values, hasLength(31));
      expect(CssProperty.values.where((p) => p.degraded), hasLength(5));
    });

    test('classes e herança de §7.1', () {
      expect(CssProperty.display.styleClass, StyleClass.structure);
      expect(CssProperty.textAlign.styleClass, StyleClass.relativeTypography);
      expect(CssProperty.textDecoration.inherited, isFalse);
      expect(CssProperty.fontSize.inherited, isFalse);
      expect(CssProperty.textIndent.inherited, isTrue);
      expect(CssProperty.listStyleType.inherited, isTrue);
      expect(CssProperty.verticalAlign.inherited, isFalse);
    });
  });

  group('hostis: linear', () {
    test('valor com 200 000 componentes e 100 000 blocos', () {
      final sw = Stopwatch()..start();
      expect(_decl('font-variant', 'small-caps ' * 200000), isEmpty);
      expect(_decl('font-variant', 'stylistic(x) ' * 200000), isEmpty);
      expect(_decl('font-variant', 'small-caps oldstyle-nums'), hasLength(1));
      expect(_decl('margin', 'f(${'(' * 100000}${')' * 100000})'), isEmpty);
      expect(_decl('font', '1em ${'x, ' * 100000}y'), hasLength(4));
      sw.stop();
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
    });
  });
}
