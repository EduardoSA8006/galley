import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/features/style/domain/computed_style.dart';
import 'package:galley/src/features/style/domain/css_value.dart';
import 'package:galley/src/features/style/domain/properties.dart';
import 'package:galley/src/features/style/domain/reader_preferences.dart';
import 'package:galley/src/features/style/domain/style_environment.dart';
import 'package:galley/src/features/style/domain/stylesheet.dart';
import 'package:galley/src/features/style/domain/value_computer.dart';

import '../../../support/style_fixture.dart';

/// Estilo do elemento de nome [name] (o [index]-ésimo) no documento.
ComputedStyle styled(
  String body, {
  required String css,
  required String name,
  int index = 0,
}) {
  final m = matchCss(body, css: css);
  final s = restyleChecked(m, ReaderPreferences.none);
  return styleOfElement(s, elementsNamed(m.tree, name)[index]);
}

double fontSizeOf(ComputedStyle s) => (s[PropertyId.fontSize] as CssLength).px;

void main() {
  group('font-size', () {
    const css =
        'body{font-size:20px} .a{font-size:2em} .b{font-size:150%} '
        '.c{font-size:larger} .d{font-size:x-large} .e{font-size:12pt} '
        '.f{font-size:smaller} .g{font-size:2ex}';
    const body =
        '<p class="a"/><p class="b"/><p class="c"/><p class="d"/>'
        '<p class="e"/><p class="f"/><p class="g"/>';

    test('relativas ao pai, palavras-chave e absolutas', () {
      final m = matchCss(body, css: css);
      final s = restyleChecked(m, ReaderPreferences.none);
      final ps = elementsNamed(m.tree, 'p');
      double size(int i) => fontSizeOf(styleOfElement(s, ps[i]));
      expect(size(0), 40);
      expect(size(1), 30);
      expect(size(2), closeTo(24, 1e-9));
      expect(size(3), 24);
      expect(size(4), closeTo(16, 1e-9));
      expect(size(5), closeTo(20 / 1.2, 1e-9));
      expect(size(6), 20);
    });

    test('rem sobre a raiz', () {
      final s = styled(
        '<p class="f"/>',
        css: 'html{font-size:10px} body{font-size:20px} .f{font-size:1rem}',
        name: 'p',
      );
      expect(fontSizeOf(s), 10);
    });

    test('vw/vh sobre a página do casamento', () {
      final m = matchCss(
        '<p class="a"/><p class="b"/><p class="c"/>',
        css:
            '.a{font-size:5vw} .b{font-size:10vh} '
            '.c{font-size:calc(5vw + 1em)}',
        environment: const StyleEnvironment(pageWidth: 600, pageHeight: 800),
      );
      expect(m.pageWidth, 600);
      expect(m.pageHeight, 800);
      final s = restyleChecked(m, ReaderPreferences.none);
      final ps = elementsNamed(m.tree, 'p');
      expect(fontSizeOf(styleOfElement(s, ps[0])), 30);
      expect(fontSizeOf(styleOfElement(s, ps[1])), 80);
      expect(fontSizeOf(styleOfElement(s, ps[2])), 46);
    });

    test('rem nas demais propriedades da raiz é o tamanho da raiz', () {
      final s = styled(
        '',
        css: 'html{font-size:10px; padding-left:2rem}',
        name: 'html',
      );
      expect(fontSizeOf(s), 10);
      expect(s[PropertyId.paddingLeft], const CssLength(px: 20));
    });

    test('rem na raiz é sobre 16 px', () {
      final s = styled('', css: 'html{font-size:2rem}', name: 'html');
      expect(fontSizeOf(s), 32);
    });

    test('tabela das palavras-chave absolutas', () {
      const sizes = {
        'xx-small': 9.6,
        'x-small': 12.0,
        'small': 14.2222,
        'medium': 16.0,
        'large': 19.2,
        'x-large': 24.0,
        'xx-large': 32.0,
        'xxx-large': 48.0,
      };
      for (final e in sizes.entries) {
        final s = styled('<p/>', css: 'p{font-size:${e.key}}', name: 'p');
        expect(fontSizeOf(s), e.value, reason: e.key);
      }
    });

    test('sem font-size herda; initial dá 16', () {
      final m = matchCss(
        '<div><p/><span/></div>',
        css: 'div{font-size:30px} span{font-size:initial}',
      );
      final s = restyleChecked(m, ReaderPreferences.none);
      expect(fontSizeOf(styleOfElement(s, elementsNamed(m.tree, 'p')[0])), 30);
      expect(
        fontSizeOf(styleOfElement(s, elementsNamed(m.tree, 'span')[0])),
        16,
      );
    });
  });

  group('comprimentos', () {
    const css =
        'p{font-size:10px; margin-left:2em; width:50%; '
        'margin-right:calc(100% - 2em); height:10vh; text-indent:2ex; '
        'padding-left:1rem}';

    test('em, %, calc e vh', () {
      final s = styled('<p/>', css: css, name: 'p');
      expect(s[PropertyId.marginLeft], const CssLength(px: 20));
      expect(s[PropertyId.width], const CssLength(percent: 50));
      expect(s[PropertyId.marginRight], const CssLength(px: -20, percent: 100));
      expect(s[PropertyId.height], const CssLength(vh: 10));
      expect(s[PropertyId.textIndent], const CssLength(px: 10));
      expect(s[PropertyId.paddingLeft], const CssLength(px: 16));
    });

    test('calc negativo em propriedade não negativa vira 0', () {
      final s = styled(
        '<p/>',
        css:
            'p{font-size:10px; width:calc(10px - 2em); '
            'padding-top:calc(1px - 1em); margin-top:calc(1px - 1em)}',
        name: 'p',
      );
      expect(s[PropertyId.width], const CssLength());
      expect(s[PropertyId.paddingTop], const CssLength());
      expect(s[PropertyId.marginTop], const CssLength(px: -9));
    });

    test('listas de comprimentos (border-spacing) calculadas', () {
      final s = styled(
        '<table/>',
        css: 'table{font-size:10px; border-spacing:1em 2px}',
        name: 'table',
      );
      expect(
        s[PropertyId.borderSpacing],
        const CssList([CssLength(px: 10), CssLength(px: 2)]),
      );
    });
  });

  group('line-height', () {
    test('número fica fator, também no filho maior', () {
      final m = matchCss(
        '<div><span>x</span></div>',
        css: 'div{font-size:10px; line-height:1.5} span{font-size:20px}',
      );
      final s = restyleChecked(m, ReaderPreferences.none);
      final div = styleOfElement(s, elementsNamed(m.tree, 'div')[0]);
      final span = styleOfElement(s, elementsNamed(m.tree, 'span')[0]);
      expect(div[PropertyId.lineHeight], const CssNumber(1.5));
      expect(span[PropertyId.lineHeight], const CssNumber(1.5));
    });

    test('em vira px e é herdado como px', () {
      final m = matchCss(
        '<div><span>x</span></div>',
        css: 'div{font-size:10px; line-height:2em} span{font-size:20px}',
      );
      final s = restyleChecked(m, ReaderPreferences.none);
      final div = styleOfElement(s, elementsNamed(m.tree, 'div')[0]);
      final span = styleOfElement(s, elementsNamed(m.tree, 'span')[0]);
      expect(div[PropertyId.lineHeight], const CssLength(px: 20));
      expect(span[PropertyId.lineHeight], const CssLength(px: 20));
    });

    test('% é sobre a fonte; normal fica palavra-chave', () {
      final a = styled(
        '<p/>',
        css: 'p{font-size:10px; line-height:150%}',
        name: 'p',
      );
      expect(a[PropertyId.lineHeight], const CssLength(px: 15));
      final b = styled('<p/>', css: '', name: 'p');
      expect(b[PropertyId.lineHeight], const CssKeyword(CssKeywords.normal));
    });
  });

  group('font-weight', () {
    test('bolder sobre 400 → 700', () {
      final s = styled(
        '<div><span/></div>',
        css: 'div{font-weight:400} span{font-weight:bolder}',
        name: 'span',
      );
      expect(s[PropertyId.fontWeight], const CssNumber(700));
    });

    test('lighter sobre 700 → 400', () {
      final s = styled(
        '<div><span/></div>',
        css: 'div{font-weight:700} span{font-weight:lighter}',
        name: 'span',
      );
      expect(s[PropertyId.fontWeight], const CssNumber(400));
    });
  });

  group('inherit, initial e unset', () {
    test('border-top-width: inherit herda', () {
      final s = styled(
        '<div><span/></div>',
        css:
            'div{border-top:5px solid} '
            'span{border-top-style:solid; border-top-width:inherit}',
        name: 'span',
      );
      expect(s[PropertyId.borderTopWidth], const CssLength(px: 5));
    });

    test('color: initial → preto', () {
      final s = styled(
        '<p/>',
        css: 'body{color:red} p{color:initial}',
        name: 'p',
      );
      expect(s[PropertyId.color], const CssColor(0xFF000000));
    });

    test('unset herda numa herdada e dá o inicial numa não herdada', () {
      final s = styled(
        '<p/>',
        css:
            'body{color:red; margin-left:5px} '
            'p{color:unset; margin-left:unset}',
        name: 'p',
      );
      expect(s[PropertyId.color], const CssColor(0xFFFF0000));
      expect(s[PropertyId.marginLeft], const CssLength());
    });

    test('não declarada: herdada vem do pai, não herdada é a inicial', () {
      final s = styled(
        '<p/>',
        css: 'body{color:red; margin-left:5px}',
        name: 'p',
      );
      expect(s[PropertyId.color], const CssColor(0xFFFF0000));
      expect(s[PropertyId.marginLeft], const CssLength());
    });

    test('color: currentcolor herda; cores de borda mantêm currentcolor', () {
      final s = styled(
        '<p/>',
        css:
            'body{color:red} p{color:currentcolor; '
            'border-top-color:currentcolor}',
        name: 'p',
      );
      expect(s[PropertyId.color], const CssColor(0xFFFF0000));
      expect(
        s[PropertyId.borderTopColor],
        const CssKeyword(CssKeywords.currentcolor),
      );
      expect(
        s[PropertyId.textDecorationColor],
        const CssKeyword(CssKeywords.currentcolor),
      );
    });

    test('quotes inicial: “ ” ‘ ’', () {
      final s = styled('<p/>', css: '', name: 'p');
      expect(s[PropertyId.quotes], const CssQuotes([('“', '”'), ('‘', '’')]));
    });
  });

  group('borda e display', () {
    test('estilo solid sem largura → 3 px; largura com none → 0', () {
      final a = styled('<p/>', css: 'p{border-top-style:solid}', name: 'p');
      expect(a[PropertyId.borderTopWidth], const CssLength(px: 3));
      final b = styled(
        '<p/>',
        css: 'p{border-top-width:5px; border-top-style:none}',
        name: 'p',
      );
      expect(b[PropertyId.borderTopWidth], const CssLength());
      final c = styled('<p/>', css: 'p{border-left:5px hidden}', name: 'p');
      expect(c[PropertyId.borderLeftWidth], const CssLength());
    });

    test('float e position absolute blocam o display', () {
      final a = styled('<span/>', css: 'span{float:left}', name: 'span');
      expect(a[PropertyId.display], const CssKeyword(CssKeywords.block));
      final b = styled(
        '<span/>',
        css: 'span{position:absolute; float:left}',
        name: 'span',
      );
      expect(b[PropertyId.display], const CssKeyword(CssKeywords.block));
      expect(b[PropertyId.float], const CssKeyword(CssKeywords.none));
      final c = styled(
        '<span/>',
        css: 'span{display:inline-table; position:fixed}',
        name: 'span',
      );
      expect(c[PropertyId.display], const CssKeyword(CssKeywords.table));
    });

    test('a raiz é blocada', () {
      final s = styled('', css: '', name: 'html');
      expect(s[PropertyId.display], const CssKeyword(CssKeywords.block));
      final body = styled('', css: '', name: 'body');
      expect(body[PropertyId.display], const CssKeyword(CssKeywords.inline));
    });
  });

  group('Revisão 4: valores extremos', () {
    test('font-size: 1e30px → 10000', () {
      final s = styled('<p/>', css: 'p{font-size:1e30px}', name: 'p');
      expect(fontSizeOf(s), 10000);
    });

    test('40 div{font-size:1000%} aninhados → 10000, finito', () {
      final body = '${'<div>' * 40}x${'</div>' * 40}';
      final m = matchCss(body, css: 'div{font-size:1000%; margin-left:3em}');
      final s = restyleChecked(m, ReaderPreferences.none);
      final divs = elementsNamed(m.tree, 'div');
      final last = styleOfElement(s, divs.last);
      expect(fontSizeOf(last), 10000);
      final margin = last[PropertyId.marginLeft] as CssLength;
      expect(margin.px, 30000);
      for (final style in s.styles) {
        for (final v in style.values) {
          if (v is CssLength) {
            expect(v.px.isFinite, isTrue);
          }
        }
      }
    });

    test('font-size: 0 com line-height: 2em → 0 e 0, sem NaN', () {
      final s = styled(
        '<p/>',
        css: 'p{font-size:0; line-height:2em; margin-top:1ex}',
        name: 'p',
      );
      expect(fontSizeOf(s), 0);
      expect(s[PropertyId.lineHeight], const CssLength());
      expect(s[PropertyId.marginTop], const CssLength());
    });

    test('z-index enorme fica finito', () {
      final s = styled(
        '<p/>',
        css: 'p{position:relative; z-index:99999999999999999999}',
        name: 'p',
      );
      final z = s[PropertyId.zIndex];
      if (z is CssNumber) expect(z.value.isFinite, isTrue);
    });
  });

  group('F7: famílias do livro', () {
    FontFaceRule face(String family, String internal) => FontFaceRule(
      family: family,
      internalFamily: internal,
      sources: const [FontUrlSource('OEBPS/f.ttf', null)],
    );

    test('troca os nomes que casam sem caixa; genéricas ficam', () {
      final names = bookFamilyNames([face('Body Font', 'gfab-body font')]);
      const value = CssFontFamilies([
        FontFamilyName('BODY FONT'),
        FontFamilyName('Other'),
        FontFamilyName('serif', generic: true),
      ]);
      expect(
        translateBookFamilies(value, names),
        const CssFontFamilies([
          FontFamilyName('gfab-body font'),
          FontFamilyName('Other'),
          FontFamilyName('serif', generic: true),
        ]),
      );
    });

    test('sem @font-face, o mesmo objeto', () {
      const value = CssFontFamilies([FontFamilyName('X')]);
      expect(identical(translateBookFamilies(value, const {}), value), isTrue);
    });
  });
}
