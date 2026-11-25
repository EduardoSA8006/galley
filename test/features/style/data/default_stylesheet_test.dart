import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/core/diagnostics/diagnostic_sink.dart';
import 'package:galley/src/features/style/data/default_stylesheet.dart';
import 'package:galley/src/features/style/data/stylesheet_builder.dart';
import 'package:galley/src/features/style/domain/computed_style.dart';
import 'package:galley/src/features/style/domain/css_value.dart';
import 'package:galley/src/features/style/domain/matched_document.dart';
import 'package:galley/src/features/style/domain/properties.dart';
import 'package:galley/src/features/style/domain/reader_preferences.dart';
import 'package:galley/src/features/style/domain/styled_document.dart';

import '../../../support/style_fixture.dart';

const _body =
    '<p>p</p><h1>1</h1><h2>2</h2><h3>3</h3><h4>4</h4><h5>5</h5><h6>6</h6>'
    '<blockquote>q</blockquote>'
    '<ul><li>a<ul><li>b<ul><li>c</li></ul></li></ul></li></ul>'
    '<ol><li>n</li></ol>'
    '<table><tr><th>h</th><td>d</td></tr></table>'
    '<ruby>漢<rt>kan</rt></ruby>'
    '<pre>x</pre><p>a<sub>2</sub> <a href="#x">l</a> <em>e</em> '
    '<strong>s</strong></p><center>c</center>';

// Globais finais são preguiçosas: lidas no primeiro uso.
final MatchedDocument _matched = matchCss(_body, defaultSheet: true);
final StyledDocument _styled = restyleChecked(_matched, ReaderPreferences.none);

ComputedStyle _style(String name, {int index = 0}) {
  final matched = matchCss(_body, defaultSheet: true);
  return styleOfElement(_styled, elementsNamed(matched.tree, name)[index]);
}

int _kw(ComputedStyle s, int property) => (s[property] as CssKeyword).id;

double _px(ComputedStyle s, int property) => (s[property] as CssLength).px;

double _weight(ComputedStyle s) =>
    (s[PropertyId.fontWeight] as CssNumber).value;

bool _hasLine(ComputedStyle s, int keyword) {
  final v = s[PropertyId.textDecorationLine];
  if (v is CssKeyword) return v.id == keyword;
  return v is CssList && v.items.contains(CssKeyword(keyword));
}

void main() {
  test('a folha é lida sem diagnósticos e uma vez só', () {
    final sink = CollectingDiagnosticSink();
    buildStyleSheet(
      kDefaultStyleSheetCss,
      path: '',
      fontPrefix: '',
      sink: sink,
    );
    expect(sink.diagnostics, isEmpty);
    expect(defaultStyleSheet.rules, isNotEmpty);
    expect(identical(defaultStyleSheet, defaultStyleSheet), isTrue);
  });

  group('display', () {
    test('html, body, p → block; head → none; li → list-item', () {
      expect(_kw(_style('html'), PropertyId.display), CssKeywords.block);
      expect(_kw(_style('body'), PropertyId.display), CssKeywords.block);
      expect(_kw(_style('p'), PropertyId.display), CssKeywords.block);
      expect(_kw(_style('head'), PropertyId.display), CssKeywords.none);
      expect(_kw(_style('li'), PropertyId.display), CssKeywords.listItem);
    });

    test('table → table; td → table-cell; rt → ruby-text', () {
      expect(_kw(_style('table'), PropertyId.display), CssKeywords.table);
      expect(_kw(_style('td'), PropertyId.display), CssKeywords.tableCell);
      expect(_kw(_style('ruby'), PropertyId.display), CssKeywords.ruby);
      expect(_kw(_style('rt'), PropertyId.display), CssKeywords.rubyText);
    });

    test('rt com 50% (8 px); rb e rtc pelo CSS Ruby; rtc > rt sem reduzir', () {
      expect(_px(_style('rt'), PropertyId.fontSize), 8);
      const body = '<p><ruby><rb>漢</rb><rtc><rt>kan</rt></rtc></ruby></p>';
      final m = matchCss(body, defaultSheet: true);
      final s = restyleChecked(m, ReaderPreferences.none);
      ComputedStyle of(String name) =>
          styleOfElement(s, elementsNamed(m.tree, name).single);
      expect(_kw(of('rb'), PropertyId.display), CssKeywords.rubyBase);
      expect(_kw(of('rtc'), PropertyId.display), CssKeywords.rubyTextContainer);
      expect(_px(of('rtc'), PropertyId.fontSize), 8);
      expect(_px(of('rt'), PropertyId.fontSize), 8);
    });
  });

  group('caixa e títulos', () {
    test('body margin-top 8; p margin-top 16', () {
      expect(_px(_style('body'), PropertyId.marginTop), 8);
      expect(_px(_style('p'), PropertyId.marginTop), 16);
    });

    test('h1 32 px, margin-top 21,44, peso 700', () {
      final h1 = _style('h1');
      expect(_px(h1, PropertyId.fontSize), 32);
      expect(_px(h1, PropertyId.marginTop), closeTo(21.44, 1e-9));
      expect(_weight(h1), 700);
    });

    test('h2–h6 pelos fatores da especificação', () {
      expect(_px(_style('h2'), PropertyId.fontSize), 24);
      expect(_px(_style('h3'), PropertyId.fontSize), closeTo(18.72, 1e-9));
      expect(_px(_style('h4'), PropertyId.fontSize), 16);
      expect(_px(_style('h5'), PropertyId.fontSize), closeTo(13.28, 1e-9));
      expect(_px(_style('h6'), PropertyId.fontSize), closeTo(10.72, 1e-9));
      for (final h in ['h2', 'h3', 'h4', 'h5', 'h6']) {
        expect(_weight(_style(h)), 700, reason: h);
      }
    });

    test('blockquote margin-left 40', () {
      expect(_px(_style('blockquote'), PropertyId.marginLeft), 40);
    });
  });

  group('listas', () {
    test('ul padding-left 40 e disc; ul ul circle; ul ul ul square', () {
      final ul = _style('ul');
      expect(_px(ul, PropertyId.paddingLeft), 40);
      expect(_kw(ul, PropertyId.listStyleType), CssKeywords.disc);
      expect(
        _kw(_style('ul', index: 1), PropertyId.listStyleType),
        CssKeywords.circle,
      );
      expect(
        _kw(_style('ul', index: 2), PropertyId.listStyleType),
        CssKeywords.square,
      );
      // Lista aninhada sem margem vertical.
      expect(_px(_style('ul', index: 1), PropertyId.marginTop), 0);
    });

    test('ol decimal', () {
      expect(_kw(_style('ol'), PropertyId.listStyleType), CssKeywords.decimal);
    });
  });

  group('texto', () {
    test('pre → white-space: pre e [monospace(generic)]', () {
      final pre = _style('pre');
      expect(_kw(pre, PropertyId.whiteSpace), CssKeywords.pre);
      expect(
        pre[PropertyId.fontFamily],
        const CssFontFamilies([FontFamilyName('monospace', generic: true)]),
      );
    });

    test('sub → vertical-align: sub e 13,333 px', () {
      final sub = _style('sub');
      expect(_kw(sub, PropertyId.verticalAlign), CssKeywords.sub);
      expect(_px(sub, PropertyId.fontSize), closeTo(13.333, 1e-3));
    });

    test('a[href] → #0000EE e sublinhado', () {
      final a = _style('a');
      expect(a[PropertyId.color], const CssColor(0xFF0000EE));
      expect(_hasLine(a, CssKeywords.underline), isTrue);
    });

    test('th negrito e centralizado', () {
      final th = _style('th');
      expect(_weight(th), 700);
      expect(_kw(th, PropertyId.textAlign), CssKeywords.center);
    });

    test('em itálico; strong 700; center centralizado', () {
      expect(_kw(_style('em'), PropertyId.fontStyle), CssKeywords.italic);
      expect(_weight(_style('strong')), 700);
      expect(_kw(_style('center'), PropertyId.textAlign), CssKeywords.center);
    });

    test('a sem href não é :link', () {
      final s = styleCss('<p><a name="x">y</a></p>', defaultSheet: true);
      final m = matchCss('<p><a name="x">y</a></p>', defaultSheet: true);
      final a = styleOfElement(s, elementsNamed(m.tree, 'a').single);
      expect(_hasLine(a, CssKeywords.underline), isFalse);
    });
  });

  group('SVG e MathML', () {
    test('svg embutido e math em linha; title do SVG oculto', () {
      const body =
          '<p><svg xmlns="http://www.w3.org/2000/svg"><title>t</title>'
          '</svg><math xmlns="http://www.w3.org/1998/Math/MathML"><mi>x</mi>'
          '</math></p>';
      final s = styleCss(body, defaultSheet: true);
      final m = matchCss(body, defaultSheet: true);
      ComputedStyle of(String name) =>
          styleOfElement(s, elementsNamed(m.tree, name).single);
      expect(_kw(of('svg'), PropertyId.display), CssKeywords.inline);
      expect(_kw(of('math'), PropertyId.display), CssKeywords.inline);
      // O `title` do SVG some; o seletor de HTML não casa fora do XHTML.
      expect(_kw(of('title'), PropertyId.display), CssKeywords.none);
    });

    test('regras de HTML não casam elementos SVG de mesmo nome', () {
      const body =
          '<svg xmlns="http://www.w3.org/2000/svg"><a href="#x">l</a></svg>';
      final s = styleCss(body, defaultSheet: true);
      final m = matchCss(body, defaultSheet: true);
      final a = styleOfElement(s, elementsNamed(m.tree, 'a').single);
      expect(_hasLine(a, CssKeywords.underline), isFalse);
    });
  });
}
