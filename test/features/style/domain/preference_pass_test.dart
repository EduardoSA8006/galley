import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/features/document/domain/document_tree.dart';
import 'package:galley/src/features/document/domain/names.dart';
import 'package:galley/src/features/style/domain/computed_style.dart';
import 'package:galley/src/features/style/domain/css_value.dart';
import 'package:galley/src/features/style/domain/matched_document.dart';
import 'package:galley/src/features/style/domain/properties.dart';
import 'package:galley/src/features/style/domain/reader_preferences.dart';
import 'package:galley/src/features/style/domain/styled_document.dart';
import 'package:galley/src/features/style/domain/text_run.dart';

import '../../../support/style_fixture.dart';

const _css = '''
body{font-size:16px;line-height:1.5;font-family:Georgia,serif}
h1{font-size:2em;text-align:center}
p{margin:0 0 1em;text-indent:1.5em;text-align:justify}
p.r{text-align:right}  p.ep{font-size:.8em}  pre{font-family:monospace}
div.box{background-color:white;border:1px solid black}
p.imp{line-height:1.2 !important}
''';

const _body =
    '<h1>Título <span class="t">s</span></h1>'
    '<p class="a">Texto <em>ênfase</em> '
    '<span class="lh" style="line-height:1.2">a</span> '
    '<span class="px" style="font-size:12px">b</span></p>'
    '<p class="r">direita</p>'
    '<p class="ep">epígrafe</p>'
    '<pre>código</pre>'
    '<div class="box"><p class="nb">na caixa</p></div>'
    '<p class="imp">importante</p>'
    '<p class="ln"><a href="#x"><em class="le">l</em></a></p>'
    '<blockquote><p class="q">citação</p></blockquote>'
    '<ul><li>item</li></ul>';

MatchedDocument _match({String body = _body, String css = _css}) =>
    matchCss(body, css: css, defaultSheet: true);

/// O elemento [name] (com a classe [cls], se dada).
int _el(DocumentTree tree, String name, {String? cls}) {
  for (final n in elementsNamed(tree, name)) {
    if (cls == null || tree.attribute(n, Namespaces.none, 'class') == cls) {
      return n;
    }
  }
  throw StateError('sem $name.$cls');
}

final class _Doc {
  _Doc(this.matched, ReaderPreferences prefs)
    : styled = restyleChecked(matched, prefs);

  final MatchedDocument matched;
  final StyledDocument styled;

  ComputedStyle of(String name, {String? cls}) =>
      styleOfElement(styled, _el(matched.tree, name, cls: cls));

  double px(String name, int property, {String? cls}) =>
      (of(name, cls: cls)[property] as CssLength).px;

  double fontSize(String name, {String? cls}) =>
      px(name, PropertyId.fontSize, cls: cls);

  double lineHeight(String name, {String? cls}) =>
      (of(name, cls: cls)[PropertyId.lineHeight] as CssNumber).value;

  CssValue value(String name, int property, {String? cls}) =>
      of(name, cls: cls)[property];
}

_Doc _doc(ReaderPreferences prefs, {String body = _body, String css = _css}) =>
    _Doc(_match(body: body, css: css), prefs);

const _adjust = PreferencePolicy.adjust;
const _force = PreferencePolicy.force;
const _publisher = PreferencePolicy.publisher;

CssFontFamilies _families(List<FontFamilyName> names) => CssFontFamilies(names);

const _theme = ReaderTheme(
  background: 0xFF000000,
  text: 0xFFEEEEEE,
  link: 0xFF88AAFF,
);

ReaderPreferences _all(PreferencePolicy policy) => ReaderPreferences(
  fontFamily: Preference('Literata', policy: policy),
  fontSize: Preference(1.5, policy: policy),
  lineHeight: Preference(2, policy: policy),
  paragraphSpacing: Preference(0.5, policy: policy),
  textIndent: Preference(2, policy: policy),
  textAlign: Preference(ReaderTextAlign.start, policy: policy),
  hyphenation: Preference(true, policy: policy),
  wordSpacing: Preference(0.25, policy: policy),
  letterSpacing: Preference(0.1, policy: policy),
  theme: Preference(_theme, policy: policy),
);

void _expectSame(StyledDocument a, StyledDocument b) {
  expect(a.styles, b.styles);
  expect(a.elementStyles, b.elementStyles);
  expect(a.pageBackground, b.pageBackground);
}

void main() {
  group('sem preferências', () {
    test('none e todas com "editora" dão o mesmo resultado', () {
      final m = _match();
      final none = restyleChecked(m, ReaderPreferences.none);
      _expectSame(restyleChecked(m, _all(_publisher)), none);
      expect(none.pageBackground, isNull);
      final p = styleOfElement(none, _el(m.tree, 'p', cls: 'a'));
      expect((p[PropertyId.lineHeight] as CssNumber).value, 1.5);
      expect(p[PropertyId.textAlign], const CssKeyword(CssKeywords.justify));
    });
  });

  group('família', () {
    const literata = CssFontFamilies([FontFamilyName('Literata')]);
    final georgia = _families(const [
      FontFamilyName('Georgia'),
      FontFamilyName('serif', generic: true),
    ]);

    test('ajustar: texto e títulos; monoespaçada e itálico intactos', () {
      final d = _doc(
        const ReaderPreferences(fontFamily: Preference('Literata')),
      );
      expect(d.value('p', PropertyId.fontFamily, cls: 'a'), literata);
      expect(d.value('h1', PropertyId.fontFamily), literata);
      final pre = d.value('pre', PropertyId.fontFamily) as CssFontFamilies;
      expect(pre.families.single.name, 'monospace');
      expect(d.value('em', PropertyId.fontFamily), literata);
      expect(
        d.value('em', PropertyId.fontStyle),
        const CssKeyword(CssKeywords.italic),
      );
    });

    test('ajustar com preserveHeadingFonts: o título fica com a editora', () {
      final d = _doc(
        const ReaderPreferences(
          fontFamily: Preference('Literata'),
          preserveHeadingFonts: true,
        ),
      );
      expect(d.value('h1', PropertyId.fontFamily), georgia);
      expect(d.value('span', PropertyId.fontFamily, cls: 't'), georgia);
      expect(d.value('p', PropertyId.fontFamily, cls: 'a'), literata);
    });

    test('forçar: inclusive a monoespaçada', () {
      final d = _doc(
        const ReaderPreferences(
          fontFamily: Preference('Literata', policy: _force),
        ),
      );
      expect(d.value('pre', PropertyId.fontFamily), literata);
    });

    test('genericFamilies troca o genérico pelo nome do app', () {
      final d = _doc(
        const ReaderPreferences(genericFamilies: {'serif': 'Literata'}),
      );
      expect(
        d.value('body', PropertyId.fontFamily),
        _families(const [
          FontFamilyName('Georgia'),
          FontFamilyName('Literata'),
        ]),
      );
    });
  });

  group('tamanho (Revisão 1: sem dupla aplicação)', () {
    test('ajustar 1,5', () {
      final d = _doc(const ReaderPreferences(fontSize: Preference(1.5)));
      expect(d.fontSize('body'), 24);
      expect(d.fontSize('h1'), 48);
      expect(d.fontSize('span', cls: 'px'), 18);
      expect(d.fontSize('em'), 24);
      expect(d.fontSize('p', cls: 'a'), 24);
      // `em` acompanham o tamanho ajustado.
      expect(d.px('p', PropertyId.marginBottom, cls: 'a'), 24);
    });

    test('forçar 20 → fator 1,25', () {
      final d = _doc(
        const ReaderPreferences(fontSize: Preference(20, policy: _force)),
      );
      expect(d.fontSize('p', cls: 'a'), 20);
      expect(d.fontSize('h1'), 40);
    });

    test('line-height absoluto acompanha o fator', () {
      final d = _doc(
        const ReaderPreferences(fontSize: Preference(1.5)),
        body: '<p>x</p>',
        css: 'p{line-height:20px}',
      );
      expect(d.px('p', PropertyId.lineHeight), 30);
    });
  });

  group('entrelinha (Revisão 1)', () {
    test('ajustar 2,0', () {
      final d = _doc(const ReaderPreferences(lineHeight: Preference(2)));
      expect(d.lineHeight('p', cls: 'a'), 3.0);
      expect(d.lineHeight('span', cls: 'lh'), closeTo(2.4, 1e-9));
      expect(d.lineHeight('em'), 3.0);
      expect(d.lineHeight('span', cls: 'px'), 3.0);
      expect(d.lineHeight('h1'), 2.25);
      expect(d.lineHeight('span', cls: 't'), 2.25);
      expect(d.lineHeight('p', cls: 'ep'), 1.5);
      expect(d.lineHeight('p', cls: 'imp'), closeTo(2.4, 1e-9));
      expect(d.lineHeight('body'), 1.5);
    });

    test('ajustar: texto corrido aninhado não multiplica duas vezes', () {
      final d = _doc(
        const ReaderPreferences(lineHeight: Preference(2)),
        body: '<div>texto<p>dentro <em>x</em></p></div>',
        css: 'body{line-height:1.5}',
      );
      expect(d.lineHeight('div'), 3.0);
      expect(d.lineHeight('p'), 3.0);
      expect(d.lineHeight('em'), 3.0);
    });

    test('ajustar: normal e px', () {
      final d = _doc(
        const ReaderPreferences(lineHeight: Preference(2)),
        body: '<p class="n">x</p><p class="x">y</p>',
        css: 'p.x{line-height:20px}',
      );
      expect(d.lineHeight('p', cls: 'n'), closeTo(2.4, 1e-9));
      expect(d.px('p', PropertyId.lineHeight, cls: 'x'), 40);
    });

    test('forçar 1,8 em todos', () {
      final d = _doc(
        const ReaderPreferences(lineHeight: Preference(1.8, policy: _force)),
      );
      for (final (name, cls) in [
        ('body', null),
        ('h1', null),
        ('p', 'a'),
        ('span', 'lh'),
        ('em', null),
        ('p', 'ep'),
        ('p', 'imp'),
        ('pre', null),
      ]) {
        expect(d.lineHeight(name, cls: cls), 1.8, reason: '$name.$cls');
      }
    });
  });

  group('parágrafos', () {
    test('ajustar 0,5: só texto corrido, pulando li (F10)', () {
      final none = _doc(ReaderPreferences.none);
      final d = _doc(const ReaderPreferences(paragraphSpacing: Preference(.5)));
      expect(d.px('p', PropertyId.marginTop, cls: 'a'), 0);
      expect(d.px('p', PropertyId.marginBottom, cls: 'a'), 8);
      for (final name in ['h1', 'blockquote', 'li']) {
        for (final p in [PropertyId.marginTop, PropertyId.marginBottom]) {
          expect(d.value(name, p), none.value(name, p), reason: name);
        }
      }
    });

    test('ajustar: o li continua recebendo os demais ajustes (F10)', () {
      final d = _doc(
        const ReaderPreferences(
          paragraphSpacing: Preference(.5),
          textIndent: Preference(2),
          lineHeight: Preference(2),
        ),
      );
      expect(d.px('li', PropertyId.textIndent), 32);
      expect(d.lineHeight('li'), 3.0);
    });

    test('forçar: em todos os blocos', () {
      final d = _doc(
        const ReaderPreferences(
          paragraphSpacing: Preference(.5, policy: _force),
        ),
      );
      expect(d.px('h1', PropertyId.marginTop), 0);
      expect(d.px('h1', PropertyId.marginBottom), 16);
      expect(d.px('li', PropertyId.marginBottom), 8);
    });

    test('forçar: margens de html e body ficam as da editora', () {
      const css = '$_css html{margin:3px 0 5px} body{margin:20px 10px 30px}';
      for (final prefs in const [
        ReaderPreferences(paragraphSpacing: Preference(.5, policy: _force)),
        // Com o tema, `isBody` já era calculado.
        ReaderPreferences(
          paragraphSpacing: Preference(.5, policy: _force),
          theme: Preference(_theme),
        ),
      ]) {
        final d = _doc(prefs, css: css);
        expect(d.px('html', PropertyId.marginTop), 3);
        expect(d.px('html', PropertyId.marginBottom), 5);
        expect(d.px('body', PropertyId.marginTop), 20);
        expect(d.px('body', PropertyId.marginBottom), 30);
        // Os blocos de dentro continuam forçados.
        expect(d.px('p', PropertyId.marginTop, cls: 'a'), 0);
        expect(d.px('p', PropertyId.marginBottom, cls: 'a'), 8);
      }
    });
  });

  group('recuo', () {
    test('ajustar 2: texto corrido', () {
      final d = _doc(const ReaderPreferences(textIndent: Preference(2)));
      expect(d.px('p', PropertyId.textIndent, cls: 'a'), 32);
      expect(d.px('h1', PropertyId.textIndent), 0);
    });

    test('forçar: todo bloco', () {
      final d = _doc(
        const ReaderPreferences(textIndent: Preference(2, policy: _force)),
      );
      expect(d.px('h1', PropertyId.textIndent), 64);
    });
  });

  group('alinhamento', () {
    const start = CssKeyword(CssKeywords.start);

    test('ajustar start: justificado troca; centro e direita ficam', () {
      final d = _doc(
        const ReaderPreferences(textAlign: Preference(ReaderTextAlign.start)),
      );
      expect(d.value('p', PropertyId.textAlign, cls: 'a'), start);
      expect(
        d.value('h1', PropertyId.textAlign),
        const CssKeyword(CssKeywords.center),
      );
      expect(
        d.value('p', PropertyId.textAlign, cls: 'r'),
        const CssKeyword(CssKeywords.right),
      );
    });

    test('ajustar: poema centralizado ou alinhado ao fim fica (F11)', () {
      final d = _doc(
        const ReaderPreferences(textAlign: Preference(ReaderTextAlign.justify)),
        body:
            '<p class="poema">verso</p><p class="fim">assinatura</p>'
            '<p class="ini">texto</p><p class="esq">texto</p>',
        css:
            'p.poema{text-align:center} p.fim{text-align:end} '
            'p.ini{text-align:start} p.esq{text-align:left}',
      );
      expect(
        d.value('p', PropertyId.textAlign, cls: 'poema'),
        const CssKeyword(CssKeywords.center),
      );
      expect(
        d.value('p', PropertyId.textAlign, cls: 'fim'),
        const CssKeyword(CssKeywords.end),
      );
      const justify = CssKeyword(CssKeywords.justify);
      expect(d.value('p', PropertyId.textAlign, cls: 'ini'), justify);
      expect(d.value('p', PropertyId.textAlign, cls: 'esq'), justify);
    });

    test('ajustar em RTL: direita é o início, esquerda é o fim', () {
      final d = _doc(
        const ReaderPreferences(textAlign: Preference(ReaderTextAlign.start)),
        body: '<p class="d">x</p><p class="e">y</p>',
        css: 'p{direction:rtl} p.d{text-align:right} p.e{text-align:left}',
      );
      expect(d.value('p', PropertyId.textAlign, cls: 'd'), start);
      expect(
        d.value('p', PropertyId.textAlign, cls: 'e'),
        const CssKeyword(CssKeywords.left),
      );
    });

    test('forçar: em tudo', () {
      final d = _doc(
        const ReaderPreferences(
          textAlign: Preference(ReaderTextAlign.start, policy: _force),
        ),
      );
      expect(d.value('h1', PropertyId.textAlign), start);
      expect(d.value('p', PropertyId.textAlign, cls: 'r'), start);
    });
  });

  group('hifenização', () {
    const auto = CssKeyword(CssKeywords.auto);
    const manual = CssKeyword(CssKeywords.manual);

    test('ajustar: texto corrido', () {
      final d = _doc(const ReaderPreferences(hyphenation: Preference(true)));
      expect(d.value('p', PropertyId.hyphens, cls: 'a'), auto);
      expect(d.value('h1', PropertyId.hyphens), manual);
    });

    test('forçar: em tudo', () {
      final d = _doc(
        const ReaderPreferences(hyphenation: Preference(true, policy: _force)),
      );
      expect(d.value('h1', PropertyId.hyphens), auto);
    });
  });

  group('espaçamento de letras e palavras (Revisão 1)', () {
    test('letras ajustar 0,1: 1,6 px herdado sem dobrar', () {
      final d = _doc(const ReaderPreferences(letterSpacing: Preference(.1)));
      expect(d.px('p', PropertyId.letterSpacing, cls: 'a'), closeTo(1.6, 1e-9));
      expect(d.px('em', PropertyId.letterSpacing), closeTo(1.6, 1e-9));
      expect(
        d.value('h1', PropertyId.letterSpacing),
        const CssKeyword(CssKeywords.normal),
      );
    });

    test('letras ajustar soma ao valor da editora', () {
      final d = _doc(
        const ReaderPreferences(letterSpacing: Preference(.1)),
        body: '<p>x <em>y</em></p>',
        css: 'p{letter-spacing:1px}',
      );
      expect(d.px('p', PropertyId.letterSpacing), closeTo(2.6, 1e-9));
      expect(d.px('em', PropertyId.letterSpacing), closeTo(2.6, 1e-9));
    });

    test('letras forçar: 1,6 px em todo elemento de 16 px', () {
      final d = _doc(
        const ReaderPreferences(letterSpacing: Preference(.1, policy: _force)),
      );
      for (final (name, cls) in [
        ('body', null),
        ('p', 'a'),
        ('em', null),
        ('p', 'r'),
        ('li', null),
      ]) {
        expect(
          d.px(name, PropertyId.letterSpacing, cls: cls),
          closeTo(1.6, 1e-9),
          reason: '$name.$cls',
        );
      }
      expect(d.px('h1', PropertyId.letterSpacing), closeTo(3.2, 1e-9));
    });

    test('palavras ajustar 0,25: 4 px herdado sem dobrar (F11)', () {
      final d = _doc(const ReaderPreferences(wordSpacing: Preference(.25)));
      expect(d.px('p', PropertyId.wordSpacing, cls: 'a'), 4);
      expect(d.px('em', PropertyId.wordSpacing), 4);
      expect(
        d.value('h1', PropertyId.wordSpacing),
        const CssKeyword(CssKeywords.normal),
      );
    });

    test('palavras forçar: em tudo', () {
      final d = _doc(
        const ReaderPreferences(wordSpacing: Preference(.25, policy: _force)),
      );
      expect(d.px('h1', PropertyId.wordSpacing), 8);
      expect(d.px('p', PropertyId.wordSpacing, cls: 'ep'), closeTo(3.2, 1e-9));
    });
  });

  group('tema', () {
    const text = CssColor(0xFFEEEEEE);
    const link = CssColor(0xFF88AAFF);
    const currentcolor = CssKeyword(CssKeywords.currentcolor);

    for (final policy in [_adjust, _force]) {
      test('$policy: cores de texto, link, fundos e bordas', () {
        final d = _doc(
          ReaderPreferences(theme: Preference(_theme, policy: policy)),
        );
        expect(d.value('p', PropertyId.color, cls: 'a'), text);
        expect(d.value('h1', PropertyId.color), text);
        expect(d.value('a', PropertyId.color), link);
        expect(d.value('em', PropertyId.color, cls: 'le'), link);
        expect(
          d.value('div', PropertyId.backgroundColor, cls: 'box'),
          const CssColor(0),
        );
        for (final p in [
          PropertyId.borderTopColor,
          PropertyId.borderRightColor,
          PropertyId.borderBottomColor,
          PropertyId.borderLeftColor,
          PropertyId.textDecorationColor,
          PropertyId.textEmphasisColor,
        ]) {
          expect(d.value('div', p, cls: 'box'), currentcolor);
        }
        // A borda continua existindo.
        expect(d.px('div', PropertyId.borderTopWidth, cls: 'box'), 1);
        expect(
          d.value('body', PropertyId.backgroundColor),
          const CssColor(0xFF000000),
        );
        expect(
          d.value('html', PropertyId.backgroundColor),
          const CssColor(0xFF000000),
        );
        expect(d.styled.pageBackground, 0xFF000000);
      });
    }

    test('imagem intacta (F11): só a cor do texto muda', () {
      const body = '<p>x <img src="a.png" alt="" class="i"/></p>';
      const css = 'img.i{width:50%;opacity:.5;border:2px solid red}';
      final none = _doc(ReaderPreferences.none, body: body, css: css);
      final d = _doc(
        const ReaderPreferences(theme: Preference(_theme)),
        body: body,
        css: css,
      );
      final a = none.of('img');
      final b = d.of('img');
      const changed = {
        PropertyId.color,
        PropertyId.borderTopColor,
        PropertyId.borderRightColor,
        PropertyId.borderBottomColor,
        PropertyId.borderLeftColor,
      };
      for (var p = 0; p < kPropertyCount; p++) {
        if (changed.contains(p)) continue;
        expect(b[p], a[p], reason: propertyInfo(p).name);
      }
    });
  });

  group('Ruling T10 I1: blocos internos de um bloco com texto direto', () {
    const body =
        '<div class="run">texto direto <em>e</em>'
        '<p class="ep">epígrafe <em>x</em></p>'
        '<table><tr><td>célula</td></tr></table>'
        '<pre>código</pre>'
        '<h1>Título</h1>'
        '<p class="n">normal <em>y</em></p></div>';
    const css =
        'body{font-size:16px;line-height:1.2} p.ep{font-size:.8em} '
        'p{margin:0}';
    const prefs = ReaderPreferences(
      lineHeight: Preference(2),
      textAlign: Preference(ReaderTextAlign.justify),
      hyphenation: Preference(true),
      letterSpacing: Preference(.1),
      wordSpacing: Preference(.25),
      textIndent: Preference(2),
    );
    const tracked = [
      PropertyId.lineHeight,
      PropertyId.textAlign,
      PropertyId.hyphens,
      PropertyId.wordSpacing,
      PropertyId.letterSpacing,
      PropertyId.textIndent,
    ];

    test('marcas: só os descendentes em linha herdam o texto corrido', () {
      final m = _match(body: body, css: css);
      int flagsOf(String name, {String? cls}) =>
          m.flags[_el(m.tree, name, cls: cls)];
      expect(flagsOf('div') & ElementFlags.textRunRoot, isNonZero);
      expect(flagsOf('em') & ElementFlags.inTextRun, isNonZero);
      for (final (name, cls) in [
        ('p', 'ep'),
        ('table', null),
        ('td', null),
        ('pre', null),
        ('h1', null),
      ]) {
        expect(
          flagsOf(name, cls: cls) & ElementFlags.inTextRun,
          0,
          reason: '$name.$cls',
        );
      }
      expect(flagsOf('p', cls: 'n') & ElementFlags.textRunRoot, isNonZero);
    });

    test('epígrafe, tabela, célula e pre ficam com a editora', () {
      final none = _doc(ReaderPreferences.none, body: body, css: css);
      final d = _doc(prefs, body: body, css: css);
      for (final (name, cls) in [
        ('p', 'ep'),
        ('table', null),
        ('td', null),
        ('pre', null),
      ]) {
        for (final p in tracked) {
          expect(
            d.value(name, p, cls: cls),
            none.value(name, p, cls: cls),
            reason: '$name.$cls ${propertyInfo(p).name}',
          );
        }
      }
      // O em dentro da epígrafe herda da editora também.
      expect(d.lineHeight('p', cls: 'ep'), 1.2);
    });

    test('o título recebe só o fator de título sobre o valor da editora', () {
      final none = _doc(ReaderPreferences.none, body: body, css: css);
      final d = _doc(prefs, body: body, css: css);
      expect(d.lineHeight('h1'), closeTo(1.8, 1e-9));
      for (final p in tracked) {
        if (p == PropertyId.lineHeight) continue;
        expect(d.value('h1', p), none.value('h1', p), reason: '$p');
      }
    });

    test('o caso normal continua: bloco e parágrafo aninhado sem dobrar', () {
      final d = _doc(prefs, body: body, css: css);
      expect(d.lineHeight('div'), closeTo(2.4, 1e-9));
      expect(d.lineHeight('p', cls: 'n'), closeTo(2.4, 1e-9));
      expect(d.px('div', PropertyId.textIndent), 32);
      expect(d.px('p', PropertyId.textIndent, cls: 'n'), 32);
      expect(
        d.value('p', PropertyId.textAlign, cls: 'n'),
        const CssKeyword(CssKeywords.justify),
      );
      expect(
        d.value('div', PropertyId.hyphens),
        const CssKeyword(CssKeywords.auto),
      );
      expect(d.px('em', PropertyId.letterSpacing), closeTo(1.6, 1e-9));
    });

    test('forçar continua valendo nos blocos internos', () {
      final d = _doc(
        const ReaderPreferences(lineHeight: Preference(1.8, policy: _force)),
        body: body,
        css: css,
      );
      expect(d.lineHeight('pre'), 1.8);
      expect(d.lineHeight('p', cls: 'ep'), 1.8);
    });
  });

  group('Revisão 5: documentos sem body XHTML', () {
    for (final policy in [_adjust, _force]) {
      test('SVG do spine com todas ($policy)', () {
        final m = matchSource(
          '<svg xmlns="http://www.w3.org/2000/svg" style="font-size:20px">'
          '<text>x</text></svg>',
          mediaType: 'image/svg+xml',
          defaultSheet: true,
        );
        final s = restyleChecked(m, _all(policy));
        expect(s.pageBackground, 0xFF000000);
        final svg = styleOfElement(s, elementsNamed(m.tree, 'svg').single);
        // Referência = a raiz (20 px): forçar 1,5 px → fator 0,075.
        final size = (svg[PropertyId.fontSize] as CssLength).px;
        expect(size, policy == _force ? closeTo(1.5, 1e-9) : 30);
      });

      test('body{display:none} com todas ($policy)', () {
        final m = _match(
          body: '<p>x <em>y</em></p>',
          css: 'body{display:none}',
        );
        expect(() => restyleChecked(m, _all(policy)), returnsNormally);
      });
    }
  });
}
