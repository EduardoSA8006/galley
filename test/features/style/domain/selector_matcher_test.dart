import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/features/document/data/parse_document.dart';
import 'package:galley/src/features/document/domain/document_tree.dart';
import 'package:galley/src/features/style/data/css_tokenizer.dart';
import 'package:galley/src/features/style/data/selector_parser.dart';
import 'package:galley/src/features/style/domain/selector.dart';
import 'package:galley/src/features/style/domain/selector_matcher.dart';

const _doc =
    '<html xmlns="http://www.w3.org/1999/xhtml" '
    'xmlns:epub="http://www.idpf.org/2007/ops" '
    'xmlns:svg="http://www.w3.org/2000/svg" xml:lang="pt"><body>'
    '<div id="d" class="a b"><p class="x" title="hello world" lang="en-US">1'
    '</p><p>2</p><span/><p epub:type="footnote">3</p></div>'
    '<a href="#n">l</a><svg:svg><svg:rect/></svg:svg></body></html>';

const _svgNs = 'http://www.w3.org/2000/svg';
const _opsNs = 'http://www.idpf.org/2007/ops';

DocumentTree tree(String xml) => parseDocumentBytes(
  Uint8List.fromList(utf8.encode(xml)),
  path: 'a.xhtml',
).tree;

List<CssToken> prelude(String css) {
  final t = tokenizeCss(css);
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

/// Elementos não virtuais de [t] em ordem de documento.
List<int> elements(DocumentTree t) => [
  for (var n = 0; n < t.nodeCount; n++)
    if (t.kindOf(n) == NodeKind.element && !t.isVirtual(n)) n,
];

/// Rótulo: `p` + texto para os parágrafos (`p1`...), senão o nome local.
String label(DocumentTree t, int e) {
  final name = t.localNameOf(e);
  if (name.toLowerCase() != 'p') return name;
  final c = t.firstChildOf(e);
  return c >= 0 && t.kindOf(c) == NodeKind.text ? 'p${t.textOf(c)}' : name;
}

/// Rótulos dos elementos que casam [css]; `null` se o seletor for inválido.
List<String>? hits(
  String css, {
  String xml = _doc,
  NamespaceMap ns = NamespaceMap.empty,
  String? documentLang,
}) {
  final list = parseSelectorList(prelude(css), ns);
  if (list == null) return null;
  final t = tree(xml);
  final m = SelectorMatcher(t, documentLang: documentLang);
  return [
    for (final e in elements(t))
      if (list.any((s) => m.matches(s, e))) label(t, e),
  ];
}

void main() {
  group('tipo e caixa', () {
    test('tipo', () {
      expect(hits('p'), ['p1', 'p2', 'p3']);
      expect(hits('P'), ['p1', 'p2', 'p3']);
      expect(hits('p:FIRST-CHILD'), ['p1']);
      expect(hits('.X'), isEmpty);
      expect(hits('#D'), isEmpty);
    });

    test('<P> em XHTML casa p (Ruling F4)', () {
      const xml =
          '<html xmlns="http://www.w3.org/1999/xhtml"><body><P>1</P>'
          '</body></html>';
      expect(hits('p', xml: xml), ['p1']);
      expect(hits('P', xml: xml), ['p1']);
    });

    test('SVG casa com caixa (Ruling F4)', () {
      const xml =
          '<html xmlns="http://www.w3.org/1999/xhtml"><body>'
          '<svg xmlns="http://www.w3.org/2000/svg"><linearGradient/>'
          '<foreignObject/></svg></body></html>';
      expect(hits('linearGradient', xml: xml), ['linearGradient']);
      expect(hits('lineargradient', xml: xml), isEmpty);
      expect(hits('foreignObject', xml: xml), ['foreignObject']);
      expect(hits('LINEARGRADIENT', xml: xml), isEmpty);
    });

    test('atributo sem caixa no nome só em XHTML', () {
      expect(hits('[TITLE]'), ['p1']);
      const xml =
          '<html xmlns="http://www.w3.org/1999/xhtml"><body>'
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1"/>'
          '</body></html>';
      expect(hits('[viewBox]', xml: xml), ['svg']);
      expect(hits('[viewbox]', xml: xml), isEmpty);
    });
  });

  group('combinadores e estruturais', () {
    test('valores do brief', () {
      expect(hits('#d > p:first-child'), ['p1']);
      expect(hits('p + p'), ['p2']);
      expect(hits('p ~ p'), ['p2', 'p3']);
      expect(hits('p:nth-child(odd)'), ['p1']);
      expect(hits('#d > :nth-child(2n + 1)'), ['p1', 'span']);
      expect(hits('p:nth-of-type(3)'), ['p3']);
      expect(hits('p:last-of-type'), ['p3']);
      expect(hits('span:empty'), ['span']);
    });

    test('descendente e filho', () {
      expect(hits('body p'), ['p1', 'p2', 'p3']);
      expect(hits('body > p'), isEmpty);
      expect(hits('html div > p'), ['p1', 'p2', 'p3']);
      expect(hits('div p + span'), ['span']);
      expect(hits('div > p ~ p'), ['p2', 'p3']);
      expect(hits('.a.b p.x'), ['p1']);
      expect(hits('body > div ~ a'), ['a']);
    });

    test('volta ao descendente quando o filho falha', () {
      const xml =
          '<html xmlns="http://www.w3.org/1999/xhtml"><body>'
          '<div class="c"><div class="b"><div class="b"><p>1</p></div></div>'
          '</div><div class="b"><p>2</p></div></body></html>';
      expect(hits('.c > .b p', xml: xml), ['p1']);
      expect(hits('.c > .b > p', xml: xml), isEmpty);
      expect(hits('.c ~ .b p', xml: xml), ['p2']);
      expect(hits('.b + .b p', xml: xml), isEmpty);
      expect(hits('body > .b p', xml: xml), ['p2']);
      expect(hits('body > .c .b p', xml: xml), ['p1']);
    });

    test('outros estruturais', () {
      expect(hits('#d > :last-child'), ['p3']);
      expect(hits('body > :only-child'), isEmpty);
      expect(hits('svg|svg > :only-child', ns: _svg), ['rect']);
      expect(hits('#d > :nth-last-child(1)'), ['p3']);
      expect(hits('#d > :nth-last-child(-n+2)'), ['span', 'p3']);
      expect(hits('#d > :nth-child(n+3)'), ['span', 'p3']);
      expect(hits('#d > :nth-child(-n+3)'), ['p1', 'p2', 'span']);
      expect(hits('#d > :nth-child(+5)'), isEmpty);
      expect(hits('#d > :nth-child(even)'), ['p2', 'p3']);
      expect(hits('p:nth-last-of-type(3)'), ['p1']);
      expect(hits('p:first-of-type'), ['p1']);
      expect(hits('span:only-of-type'), ['span']);
      expect(hits('p:only-of-type'), isEmpty);
      expect(hits(':root'), ['html']);
    });

    test(':empty conta qualquer texto, mesmo espaço', () {
      const xml =
          '<html xmlns="http://www.w3.org/1999/xhtml"><body>'
          '<p> </p><p><b/></p><p/></body></html>';
      expect(hits('p:empty', xml: xml), ['p']);
    });
  });

  group('atributos', () {
    test('valores do brief', () {
      expect(hits('[title~=world]'), ['p1']);
      expect(hits('[title^=hel]'), ['p1']);
      expect(hits(r'[title$=LD i]'), ['p1']);
      expect(hits('[lang|=en]'), ['p1']);
    });

    test('operadores', () {
      expect(hits('[title]'), ['p1']);
      expect(hits('[title="hello world"]'), ['p1']);
      expect(hits('[title=hello]'), isEmpty);
      expect(hits('[title*="o w"]'), ['p1']);
      expect(hits(r'[title$=LD]'), isEmpty);
      expect(hits('[title^=""]'), isEmpty);
      expect(hits('[title~="hello world"]'), isEmpty);
      expect(hits('[lang|=EN i]'), ['p1']);
      expect(hits('[lang|=en-US]'), ['p1']);
      expect(hits('[class~=b]'), ['div']);
    });

    test('namespaces de atributo', () {
      final ns = NamespaceMap(prefixes: {'epub': _opsNs});
      expect(hits('[epub|type~=footnote]', ns: ns), ['p3']);
      expect(hits('[*|type]'), ['p3']);
      expect(hits('[type]'), isEmpty);
      expect(hits('[|title]'), ['p1']);
    });
  });

  group('pseudo-classes', () {
    test(':lang', () {
      expect(hits('p:lang(pt)'), ['p2', 'p3']);
      expect(hits('p:lang(en)'), ['p1']);
      expect(hits('p:lang(EN-us)'), ['p1']);
      expect(hits('p:lang(e)'), isEmpty);
      expect(hits(':lang(pt)')!.contains('p1'), isFalse);
    });

    test(':lang: xml:lang vence lang; documentLang é o último recurso', () {
      const xml =
          '<html xmlns="http://www.w3.org/1999/xhtml"><body>'
          '<p xml:lang="fr" lang="de">1</p><p>2</p><p lang="">3</p>'
          '</body></html>';
      expect(hits('p:lang(fr)', xml: xml), ['p1']);
      expect(hits('p:lang(de)', xml: xml), isEmpty);
      expect(hits('p:lang(ja)', xml: xml, documentLang: 'ja-JP'), ['p2']);
      expect(hits('p:lang(ja)', xml: xml), isEmpty);
    });

    test(':link, estados e :not', () {
      expect(hits('a:link'), ['a']);
      expect(hits(':link'), ['a']);
      expect(hits('a:hover'), isEmpty);
      expect(hits('a:visited'), isEmpty);
      expect(hits('a:active, a:focus'), isEmpty);
      expect(hits('p:not(.x)'), ['p2', 'p3']);
      expect(hits(':not(p.x)'), isNull);
      expect(hits('p:not([title])'), ['p2', 'p3']);
      expect(hits('p:not(:first-child)'), ['p2', 'p3']);
      expect(hits('a:not(:hover)'), ['a']);
      expect(hits('#d > :not(p)'), ['span']);
    });

    test('pseudo-elemento não altera o casamento do elemento', () {
      expect(hits('p::first-letter'), ['p1', 'p2', 'p3']);
    });
  });

  group('namespaces', () {
    test('valores do brief', () {
      expect(hits('svg|rect', ns: _svg), ['rect']);
      expect(hits('rect', ns: _svg), ['rect']);
      expect(
        hits(
          '[epub|type~=footnote]',
          ns: NamespaceMap(prefixes: {'epub': _opsNs}),
        ),
        ['p3'],
      );
      expect(hits('foo|p'), isNull);
    });

    test('padrão, *| e |', () {
      expect(hits('*|rect'), ['rect']);
      expect(hits('|rect'), isEmpty);
      expect(hits('svg|*', ns: _svg), ['svg', 'rect']);
      const def = NamespaceMap(defaultUri: _svgNs);
      expect(hits('rect', ns: def), ['rect']);
      expect(hits('p', ns: def), isEmpty);
      expect(hits('*', ns: def), ['svg', 'rect']);
      expect(hits('.x', ns: def), isEmpty);
    });

    test('elementos sem namespace casam |tipo', () {
      const xml =
          '<html xmlns="http://www.w3.org/1999/xhtml"><body>'
          '<x xmlns=""><p>1</p></x></body></html>';
      expect(hits('|p', xml: xml), ['p1']);
      expect(hits('p', xml: xml), ['p1']);
      expect(hits('P', xml: xml), isEmpty);
    });
  });

  test('casamento sem recursão: cadeia longa de ancestrais', () {
    final depth = 5000;
    final xml = StringBuffer('<html xmlns="http://www.w3.org/1999/xhtml">');
    for (var i = 0; i < depth; i++) {
      xml.write('<div>');
    }
    xml.write('<p>1</p>');
    for (var i = 0; i < depth; i++) {
      xml.write('</div>');
    }
    xml.write('</html>');
    final sel = 'span div p, ${List.filled(200, 'div').join(' ')} p';
    final list = parseSelectorList(prelude(sel), NamespaceMap.empty)!;
    final t = tree(xml.toString());
    final m = SelectorMatcher(t);
    final p = elements(t).last;
    expect(m.matches(list[0], p), isFalse);
    expect(m.matches(list[1], p), isTrue);
  });
}

const _svg = NamespaceMap(prefixes: {'svg': _svgNs});
