import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/features/style/domain/css_value.dart';
import 'package:galley/src/features/style/domain/matched_document.dart';
import 'package:galley/src/features/style/domain/reader_preferences.dart';
import 'package:galley/src/features/style/domain/restyle.dart';
import 'package:galley/src/features/style/domain/text_run.dart';

import '../../../support/style_fixture.dart';

/// Casa [body] com a folha padrão real e o [css] da editora.
MatchedDocument _match(String body, {String css = ''}) =>
    matchCss(body, css: css, defaultSheet: true);

int _flagsOf(MatchedDocument m, String name, {int index = 0}) =>
    m.flags[elementsNamed(m.tree, name)[index]];

bool _has(int flags, int flag) => flags & flag != 0;

bool _isRoot(String body, String name, {String css = ''}) =>
    _has(_flagsOf(_match(body, css: css), name), ElementFlags.textRunRoot);

bool _anyRoot(MatchedDocument m) =>
    m.flags.any((f) => f & ElementFlags.textRunRoot != 0);

void main() {
  group('texto corrido (corpo de 16 px)', () {
    test('<p>texto</p>', () {
      final m = _match('<p>texto</p>');
      expect(m.bodyFontSize, 16);
      final p = _flagsOf(m, 'p');
      expect(_has(p, ElementFlags.textRunRoot), isTrue);
      expect(_has(p, ElementFlags.inTextRun), isTrue);
    });

    test('<p style="font-size:14px"> (−12,5%) ainda é', () {
      expect(_isRoot('<p style="font-size:14px">texto</p>', 'p'), isTrue);
    });

    test('<blockquote><p>x</p></blockquote>: o p é, o blockquote não', () {
      final m = _match('<blockquote><p>x</p></blockquote>');
      expect(_has(_flagsOf(m, 'p'), ElementFlags.textRunRoot), isTrue);
      final q = _flagsOf(m, 'blockquote');
      expect(_has(q, ElementFlags.textRunRoot), isFalse);
      expect(_has(q, ElementFlags.inTextRun), isFalse);
    });

    test('<div>texto <em>x</em></div>: div raiz, em dentro', () {
      final m = _match('<div>texto <em>x</em></div>');
      expect(_has(_flagsOf(m, 'div'), ElementFlags.textRunRoot), isTrue);
      final em = _flagsOf(m, 'em');
      expect(_has(em, ElementFlags.textRunRoot), isFalse);
      expect(_has(em, ElementFlags.inTextRun), isTrue);
    });

    test('<p><span>x</span></p> e <p><em><b>x</b></em></p>', () {
      expect(_isRoot('<p><span>x</span></p>', 'p'), isTrue);
      expect(_isRoot('<p><em><b>x</b></em></p>', 'p'), isTrue);
      final em = _flagsOf(_match('<p><em><b>x</b></em></p>'), 'em');
      expect(_has(em, ElementFlags.textRunRoot), isFalse);
      expect(_has(em, ElementFlags.inTextRun), isTrue);
    });

    test('<div><p>x</p></div> não marca o div', () {
      final m = _match('<div><p>x</p></div>');
      expect(_has(_flagsOf(m, 'div'), ElementFlags.textRunRoot), isFalse);
      expect(_has(_flagsOf(m, 'p'), ElementFlags.textRunRoot), isTrue);
    });

    test('<p><img/></p> sem texto não marca', () {
      expect(_isRoot('<p><img src="a.png"/></p>', 'p'), isFalse);
    });

    test('texto em inline-block não sobe para o bloco', () {
      expect(
        _isRoot(
          '<p><span>x</span></p>',
          'p',
          css: 'span{display:inline-block}',
        ),
        isFalse,
      );
    });

    test('texto de SVG embutido não sobe para o p', () {
      expect(
        _isRoot(
          '<p><svg xmlns="http://www.w3.org/2000/svg"><text>x</text></svg></p>',
          'p',
        ),
        isFalse,
      );
    });

    test('U+00A0 conta como texto', () {
      expect(_isRoot('<p> </p>', 'p'), isTrue);
    });

    test('<li>texto</li> é texto corrido e expõe list-item (F10)', () {
      final li = _flagsOf(_match('<ul><li>texto</li></ul>'), 'li');
      expect(_has(li, ElementFlags.textRunRoot), isTrue);
      expect(_has(li, ElementFlags.listItem), isTrue);
      final p = _flagsOf(_match('<p>texto</p>'), 'p');
      expect(_has(p, ElementFlags.listItem), isFalse);
    });

    test('display flow-root conta; inline não', () {
      expect(_isRoot('<p>x</p>', 'p', css: 'p{display:flow-root}'), isTrue);
      expect(_isRoot('<p>x</p>', 'p', css: 'p{display:inline}'), isFalse);
    });
  });

  group('não é texto corrido', () {
    test('<p> </p> (só espaço ASCII)', () {
      expect(_isRoot('<p> \t\n\r </p>', 'p'), isFalse);
    });

    test('<h2>t</h2>', () {
      expect(_isRoot('<h2>t</h2>', 'h2'), isFalse);
    });

    test('<p style="font-size:.8em"> (−20%, epígrafe)', () {
      expect(_isRoot('<p style="font-size:.8em">texto</p>', 'p'), isFalse);
    });

    test('<pre>x</pre>', () {
      expect(_isRoot('<pre>x</pre>', 'pre'), isFalse);
    });

    test('<td><p>x</p></td>', () {
      expect(
        _isRoot('<table><tr><td><p>x</p></td></tr></table>', 'p'),
        isFalse,
      );
    });

    test('<pre><div>x</div></pre> (ancestral pre)', () {
      expect(_isRoot('<pre><div>x</div></pre>', 'div'), isFalse);
    });

    test('<figcaption>', () {
      expect(
        _isRoot(
          '<figure><figcaption>legenda</figcaption></figure>',
          'figcaption',
        ),
        isFalse,
      );
    });

    test('td, th e caption, mesmo com display block', () {
      const css = 'td,th,caption{display:block}';
      const body =
          '<table><caption>c</caption><tr><th>h</th><td>d</td></tr></table>';
      final m = _match(body, css: css);
      for (final name in ['td', 'th', 'caption']) {
        expect(
          _has(_flagsOf(m, name), ElementFlags.textRunRoot),
          isFalse,
          reason: name,
        );
      }
    });
  });

  group('corpo, títulos, links e monoespaçada', () {
    test('body{font-size:120%} → bodyFontSize 19,2', () {
      final m = _match('<p>x</p>', css: 'body{font-size:120%}');
      expect(m.bodyFontSize, closeTo(19.2, 1e-9));
      expect(_has(_flagsOf(m, 'p'), ElementFlags.textRunRoot), isTrue);
    });

    test('heading em h1–h6 e descendentes', () {
      final m = _match('<h3>t <em>x</em></h3><p>y</p>');
      expect(_has(_flagsOf(m, 'h3'), ElementFlags.heading), isTrue);
      expect(_has(_flagsOf(m, 'em'), ElementFlags.heading), isTrue);
      expect(_has(_flagsOf(m, 'p'), ElementFlags.heading), isFalse);
    });

    test('<a href><em> → em com link; <a name> não', () {
      final m = _match('<p><a href="#x"><em>y</em></a><a name="x">z</a></p>');
      expect(_has(_flagsOf(m, 'em'), ElementFlags.link), isTrue);
      expect(_has(_flagsOf(m, 'a'), ElementFlags.link), isTrue);
      expect(_has(_flagsOf(m, 'a', index: 1), ElementFlags.link), isFalse);
      expect(_has(_flagsOf(m, 'p'), ElementFlags.link), isFalse);
    });

    test('"Courier New", serif e monospaced → monospace', () {
      final m = _match(
        '<p class="a">x</p><p class="b">y</p><p class="c">z</p>',
        css:
            '.a{font-family:"Courier New", serif} '
            '.b{font-family:monospaced} .c{font-family:Georgia}',
      );
      expect(_has(_flagsOf(m, 'p'), ElementFlags.monospace), isTrue);
      expect(_has(_flagsOf(m, 'p', index: 1), ElementFlags.monospace), isTrue);
      expect(_has(_flagsOf(m, 'p', index: 2), ElementFlags.monospace), isFalse);
    });

    test('pre e code da folha padrão são monospace', () {
      final m = _match('<pre>x</pre><p><code>y</code></p>');
      expect(_has(_flagsOf(m, 'pre'), ElementFlags.monospace), isTrue);
      expect(_has(_flagsOf(m, 'code'), ElementFlags.monospace), isTrue);
    });

    test('família do livro traduzida ainda reconhece monospace', () {
      final m = _match(
        '<p>x</p>',
        css:
            '@font-face{font-family:"Courier New";src:url(c.ttf)} '
            'p{font-family:"Courier New"}',
      );
      expect(_has(_flagsOf(m, 'p'), ElementFlags.monospace), isTrue);
    });

    test('publisherFamilies aponta a família calculada da editora', () {
      final m = _match(
        '<p>x</p><p class="g">y</p>',
        css: '.g{font-family:Georgia, serif}',
      );
      final ps = elementsNamed(m.tree, 'p');
      expect(
        m.familyTable[m.publisherFamilies[ps[0]]],
        const CssFontFamilies([FontFamilyName('serif', generic: true)]),
      );
      expect(
        m.familyTable[m.publisherFamilies[ps[1]]],
        const CssFontFamilies([
          FontFamilyName('Georgia'),
          FontFamilyName('serif', generic: true),
        ]),
      );
      // Famílias iguais compartilham o mesmo item da tabela.
      expect(m.familyTable.toSet().length, m.familyTable.length);
      // Nós que não são elemento: −1.
      expect(m.publisherFamilies[m.tree.documentNode], -1);
    });
  });

  group('Revisão 5: documentos sem <body> XHTML', () {
    test('item SVG do spine: não lança, corpo 16, nenhum texto corrido', () {
      final m = matchSource(
        '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">'
        '<text>legenda</text><title>t</title></svg>',
        mediaType: 'image/svg+xml',
        defaultSheet: true,
      );
      expect(m.bodyFontSize, 16);
      expect(_anyRoot(m), isFalse);
      restyle(m, ReaderPreferences.none);
    });

    test('SVG com font-size na raiz usa o tamanho da raiz', () {
      final m = matchSource(
        '<svg xmlns="http://www.w3.org/2000/svg" style="font-size:20px">'
        '<text>x</text></svg>',
        mediaType: 'image/svg+xml',
        defaultSheet: true,
      );
      expect(m.bodyFontSize, 20);
    });

    test('documento recuperado com body virtual classifica normalmente', () {
      final m = matchSource('<p>texto', defaultSheet: true);
      final body = elementsNamed(m.tree, 'body').single;
      expect(m.tree.isVirtual(body), isTrue);
      expect(m.bodyFontSize, 16);
      expect(_has(_flagsOf(m, 'p'), ElementFlags.textRunRoot), isTrue);
    });

    test('body{display:none} não lança', () {
      final m = _match('<p>x</p>', css: 'body{display:none}');
      expect(m.bodyFontSize, 16);
      restyle(m, ReaderPreferences.none);
    });
  });

  group('restyle', () {
    test('profundo: 10.000 div aninhados sem estouro', () {
      final m = _match('${'<div>' * 10000}x${'</div>' * 10000}');
      expect(m.flags.length, m.tree.nodeCount);
      restyle(m, ReaderPreferences.none);
    });
  });
}
