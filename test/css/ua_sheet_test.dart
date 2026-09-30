// Folha padrão (spec do CSS §8.1): parseia sem issue e diz o que o HTML
// manda para cada elemento.
import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/css/parser.dart';
import 'package:galley/src/css/ua_sheet.dart';

/// Declarações das regras com um seletor de um composto só, de tipo [tag] e
/// sem atributo (`propriedade=valor`).
List<String> _declsFor(String tag) => [
  for (final r in userAgentSheet.rules)
    if (r.selectors.any(
      (s) =>
          s.compounds.length == 1 &&
          s.rightmost.tag == tag &&
          s.rightmost.attributes.isEmpty,
    ))
      for (final d in r.declarations) '${d.property.name}=${d.value}',
];

void main() {
  test('parseia sem nenhum CssIssue e sem seletor perdido', () {
    expect(userAgentSheet.issues, isEmpty);
    expect(userAgentSheet.imports, isEmpty);
    expect(userAgentSheet.rules, hasLength(31));
    expect(identical(userAgentSheet, userAgentSheet), isTrue);
  });

  test('h1–h6: bloco, negrito e as razões de §8.1', () {
    final steps = {
      'h1': 'larger',
      'h2': 'larger',
      'h3': 'larger',
      'h4': 'same',
      'h5': 'smaller',
      'h6': 'smaller',
    };
    for (final MapEntry(key: h, value: step) in steps.entries) {
      expect(_declsFor(h), [
        'display=block',
        'fontWeight=700',
        'fontSize=$step',
      ], reason: h);
    }
  });

  test('ênfase, negrito, sublinhado e riscado', () {
    for (final t in ['i', 'cite', 'em', 'var', 'dfn']) {
      expect(_declsFor(t), ['fontStyle=italic'], reason: t);
    }
    expect(_declsFor('address'), ['display=block', 'fontStyle=italic']);
    for (final t in ['b', 'strong']) {
      expect(_declsFor(t), ['fontWeight=bolder'], reason: t);
    }
    for (final t in ['u', 'ins']) {
      expect(_declsFor(t), ['textDecoration=decoration(u=true, s=false)']);
    }
    for (final t in ['s', 'strike', 'del']) {
      expect(_declsFor(t), ['textDecoration=decoration(u=false, s=true)']);
    }
  });

  test('escondidos, pre e nobr; rp e noscript ficam', () {
    for (final t in ['head', 'script', 'style', 'title', 'template', 'link']) {
      expect(_declsFor(t), ['display=none'], reason: t);
    }
    expect(_declsFor('pre'), ['display=block', 'whiteSpace=pre']);
    expect(_declsFor('nobr'), ['whiteSpace=nowrap']);
    expect(_declsFor('rp'), isEmpty);
    expect(_declsFor('noscript'), isEmpty);
  });

  test('sub e sup', () {
    expect(_declsFor('sup'), ['fontSize=smaller', 'verticalAlign=sup']);
    expect(_declsFor('sub'), ['fontSize=smaller', 'verticalAlign=sub']);
  });

  test('listas: tipos por aninhamento e ol[type] com caixa', () {
    expect(_declsFor('li'), ['display=listItem']);
    expect(_declsFor('ol'), [
      'display=block',
      'listStyleType=decimal',
      'paddingLeft=2.5em',
    ]);
    final typed = [
      for (final r in userAgentSheet.rules)
        for (final s in r.selectors)
          if (s.rightmost.attributes.isNotEmpty)
            '${s.rightmost.tag}[${s.rightmost.attributes.single.value}]='
                '${r.declarations.single.value}',
    ];
    expect(typed, [
      'ol[1]=decimal',
      'li[1]=decimal',
      'ol[a]=lowerAlpha',
      'li[a]=lowerAlpha',
      'ol[A]=upperAlpha',
      'li[A]=upperAlpha',
      'ol[i]=lowerRoman',
      'li[i]=lowerRoman',
      'ol[I]=upperRoman',
      'li[I]=upperRoman',
    ]);
    expect(_declsFor('dir'), [
      'display=block',
      'listStyleType=disc',
      'paddingLeft=2.5em',
    ]);
  });

  test('nenhum seletor tem combinador: a folha padrão não sobe ancestrais', () {
    for (final r in userAgentSheet.rules) {
      for (final sel in r.selectors) {
        expect(sel.compounds, hasLength(1));
      }
    }
  });

  test('blockquote e dd', () {
    expect(_declsFor('blockquote'), [
      'display=block',
      'marginTop=1.0em',
      'marginRight=2.5em',
      'marginBottom=1.0em',
      'marginLeft=2.5em',
    ]);
    expect(_declsFor('dd'), ['display=block', 'marginLeft=2.5em']);
  });

  test('é só texto: reparsear dá o mesmo número de regras', () {
    expect(parseStyleSheet(userAgentCss).rules, hasLength(31));
  });
}
