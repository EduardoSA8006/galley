import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/core/diagnostics/diagnostic_codes.dart';
import 'package:galley/src/core/diagnostics/diagnostic_sink.dart';
import 'package:galley/src/features/document/data/parse_document.dart';
import 'package:galley/src/features/document/domain/document_tree.dart';
import 'package:galley/src/features/style/data/book_style_context.dart';
import 'package:galley/src/features/style/data/default_stylesheet.dart';
import 'package:galley/src/features/style/data/style_document.dart';
import 'package:galley/src/features/style/data/stylesheet_builder.dart';
import 'package:galley/src/features/style/domain/css_value.dart';
import 'package:galley/src/features/style/domain/matched_document.dart';
import 'package:galley/src/features/style/domain/properties.dart';
import 'package:galley/src/features/style/domain/selector.dart';
import 'package:galley/src/features/style/domain/style_environment.dart';
import 'package:galley/src/features/style/domain/stylesheet.dart';

import '../../../support/style_fixture.dart' show checkedMatch;

const env = StyleEnvironment(pageWidth: 500, pageHeight: 800);

const red = CssColor(0xFFFF0000);
const blue = CssColor(0xFF0000FF);
const green = CssColor(0xFF008000);

StyleSheet sheet(String css) => buildStyleSheet(
  css,
  path: 'ua.css',
  fontPrefix: '',
  sink: const NullDiagnosticSink(),
);

/// Casa o documento com [body] (dentro de `<body>`), com as folhas [css]
/// (caminho relativo a `OEBPS/` → texto) ligadas por `<link>` na ordem do
/// mapa, mais o [head] extra.
MatchedDocument run(
  String body, {
  Map<String, String> css = const {},
  Map<String, String> files = const {},
  String head = '',
  String? ua,
  StyleEnvironment environment = env,
  DiagnosticSink? sink,
}) {
  final all = {
    for (final e in {...css, ...files}.entries)
      'OEBPS/${e.key}': Uint8List.fromList(utf8.encode(e.value)),
  };
  final links = [
    for (final name in css.keys) '<link rel="stylesheet" href="$name"/>',
  ].join();
  final xml =
      '<html xmlns="http://www.w3.org/1999/xhtml"><head>$links$head</head>'
      '<body>$body</body></html>';
  final document = parseDocumentBytes(
    Uint8List.fromList(utf8.encode(xml)),
    path: 'OEBPS/ch.xhtml',
  );
  final context = BookStyleContext(resolve: (p) => all[p], bookKey: 'livro');
  return checkedMatch(
    matchDocument(
      context,
      document,
      environment,
      sink: sink,
      userAgentSheet: ua == null ? null : sheet(ua),
    ),
  );
}

/// Elementos de nome [name], em ordem de documento.
List<int> named(DocumentTree tree, String name) => [
  for (var n = 0; n < tree.nodeCount; n++)
    if (tree.kindOf(n) == NodeKind.element && tree.localNameOf(n) == name) n,
];

CascadedValues valuesOf(MatchedDocument m, int element) =>
    m.sets[m.elementSets[element]];

CssValue? colorOf(MatchedDocument m, String name, {int index = 0}) =>
    valuesOf(m, named(m.tree, name)[index]).valueOf(PropertyId.color);

void main() {
  test('folha padrão lida uma vez', () {
    expect(kDefaultStyleSheetCss, isNotEmpty);
    expect(identical(defaultStyleSheet, defaultStyleSheet), isTrue);
  });

  group('ordem da cascata', () {
    test('agente normal < editora normal', () {
      final m = run(
        '<p>a</p>',
        ua: 'p{color:blue}',
        css: {'a.css': 'p{color:red}'},
      );
      expect(colorOf(m, 'p'), red);
    });

    test('agente !important > editora !important', () {
      final m = run(
        '<p>a</p>',
        ua: 'p{color:blue !important}',
        css: {'a.css': 'p{color:red !important}'},
      );
      expect(colorOf(m, 'p'), blue);
    });

    test('folha !important > style= normal', () {
      final m = run(
        '<p style="color:green">a</p>',
        css: {'a.css': 'p{color:red !important}'},
      );
      expect(colorOf(m, 'p'), red);
    });

    test('style= !important > folha !important', () {
      final m = run(
        '<p style="color:green !important">a</p>',
        css: {'a.css': 'p{color:red !important}'},
      );
      expect(colorOf(m, 'p'), green);
    });

    test('style= normal > folha normal de qualquer especificidade', () {
      final m = run(
        '<p id="x" style="color:green">a</p>',
        css: {'a.css': '#x{color:red}'},
      );
      expect(colorOf(m, 'p'), green);
    });

    test('especificidade: #x vence p mesmo antes', () {
      final m = run(
        '<p id="x">a</p>',
        css: {'a.css': '#x{color:red} p{color:blue}'},
      );
      expect(colorOf(m, 'p'), red);
    });

    test('mesma especificidade: a última regra vence', () {
      final m = run('<p>a</p>', css: {'a.css': 'p{color:red} p{color:blue}'});
      expect(colorOf(m, 'p'), blue);
    });

    test('a segunda folha vence a primeira', () {
      final m = run(
        '<p>a</p>',
        css: {'a.css': 'p{color:red}', 'b.css': 'p{color:blue}'},
      );
      expect(colorOf(m, 'p'), blue);
    });

    test('<style> depois do <link> vence', () {
      final m = run(
        '<p>a</p>',
        css: {'a.css': 'p{color:red}'},
        head: '<style>p{color:blue}</style>',
      );
      expect(colorOf(m, 'p'), blue);
    });

    test('regras de um @import perdem para as de quem importa', () {
      final m = run(
        '<p>a</p>',
        css: {'a.css': '@import "b.css"; p{color:red}'},
        files: {'b.css': 'p{color:blue}'},
      );
      expect(colorOf(m, 'p'), red);
    });

    test('folha com <link media="print"> não conta', () {
      final m = run(
        '<p>a</p>',
        head: '<link rel="stylesheet" href="a.css" media="print"/>',
        files: {'a.css': 'p{color:red}'},
      );
      expect(colorOf(m, 'p'), isNull);
      expect(
        valuesOf(m, named(m.tree, 'p').single).declares(PropertyId.color),
        isFalse,
      );
    });

    test('@import com media falsa não conta', () {
      final m = run(
        '<p>a</p>',
        css: {'a.css': '@import "b.css" print;'},
        files: {'b.css': 'p{color:red}'},
      );
      expect(colorOf(m, 'p'), isNull);
    });

    test('regra com :hover não casa', () {
      final m = run('<p>a</p>', css: {'a.css': 'p:hover{color:red}'});
      expect(colorOf(m, 'p'), isNull);
    });

    test('dentro da mesma regra, a última declaração vence', () {
      final m = run('<p>a</p>', css: {'a.css': 'p{color:red;color:blue}'});
      expect(colorOf(m, 'p'), blue);
    });

    test('nomes de tipo XHTML sem caixa', () {
      final m = run('<p>a</p>', css: {'a.css': 'P{color:red}'});
      expect(colorOf(m, 'p'), red);
    });
  });

  group('valores em cascata', () {
    test('properties ordenado e valueOf/declares', () {
      final m = run(
        '<p>a</p>',
        css: {'a.css': 'p{text-indent:1em;color:red;font-style:italic}'},
      );
      final v = valuesOf(m, named(m.tree, 'p').single);
      final props = v.properties.toList();
      expect(props, [...props]..sort());
      expect(
        props,
        containsAll([
          PropertyId.color,
          PropertyId.textIndent,
          PropertyId.fontStyle,
        ]),
      );
      expect(v.values, hasLength(props.length));
      expect(v.declares(PropertyId.color), isTrue);
      expect(v.declares(PropertyId.fontWeight), isFalse);
      expect(v.valueOf(PropertyId.fontWeight), isNull);
    });

    test('nós que não são elementos ficam com −1', () {
      final m = run('<p>a</p>');
      final t = m.tree;
      expect(m.elementSets, hasLength(t.nodeCount));
      for (var n = 0; n < t.nodeCount; n++) {
        if (t.kindOf(n) == NodeKind.element) {
          expect(m.elementSets[n], inInclusiveRange(0, m.sets.length - 1));
        } else {
          expect(m.elementSets[n], -1);
        }
      }
    });
  });

  group('internamento', () {
    test('1.000 <p class="t"> apontam para o mesmo conjunto', () {
      final m = run(
        List.filled(1000, '<p class="t">x</p>').join(),
        css: {'a.css': '.t{color:red}'},
      );
      final ps = named(m.tree, 'p');
      expect(ps, hasLength(1000));
      final first = m.elementSets[ps.first];
      for (final p in ps) {
        expect(m.elementSets[p], first);
      }
      expect(colorOf(m, 'p'), red);
      expect(m.sets.length, lessThanOrEqualTo(5));
    });

    test('o mesmo style= em 100 elementos é lido uma vez', () {
      final m = run(List.filled(100, '<p style="color:red">x</p>').join());
      expect(styleAttributeParses, 1);
      final ps = named(m.tree, 'p');
      expect({for (final p in ps) m.elementSets[p]}, hasLength(1));
      expect(colorOf(m, 'p', index: 99), red);
    });

    test('diagnósticos de style= limitados por documento', () {
      final sink = CollectingDiagnosticSink();
      run(
        [for (var i = 0; i < 30; i++) '<p style="zoom$i:1">x</p>'].join(),
        sink: sink,
      );
      final unsupported = sink.diagnostics
          .where((d) => d.code == DiagnosticCodes.cssUnsupportedProperty)
          .toList();
      // 20 repassados + o resumo do flush.
      expect(unsupported, hasLength(21));
      expect(unsupported.last.message, contains('total 30'));
      expect(unsupported.first.location, 'OEBPS/ch.xhtml');
    });
  });

  test(
    '<style> com mais de 20 erros: só o limite do livro, sem total falso',
    () {
      final sink = CollectingDiagnosticSink();
      final decls = [for (var i = 0; i < 30; i++) 'zoom$i:1'].join(';');
      run('<p>x</p>', head: '<style>p{$decls}</style>', sink: sink);
      final unsupported = sink.diagnostics
          .where((d) => d.code == DiagnosticCodes.cssUnsupportedProperty)
          .toList();
      // 20 repassados + o aviso único do limite do livro.
      expect(unsupported, hasLength(21));
      expect(unsupported.last.message, contains('limite de 20'));
      expect(unsupported.where((d) => d.message.contains('total')), isEmpty);
    },
  );

  test('style= continua limitado por documento junto com <style>', () {
    final sink = CollectingDiagnosticSink();
    run(
      [for (var i = 0; i < 30; i++) '<p style="zoomx$i:1">x</p>'].join(),
      head: '<style>p{zoomy:1}</style>',
      sink: sink,
    );
    final inline = sink.diagnostics
        .where(
          (d) =>
              d.code == DiagnosticCodes.cssUnsupportedProperty &&
              d.location == 'OEBPS/ch.xhtml',
        )
        .toList();
    // 20 de style= + o resumo do flush; o de <style> tem local com linha.
    expect(inline, hasLength(21));
    expect(inline.last.message, contains('total 30'));
  });

  group('filtro de ancestrais', () {
    test('2.000 <p> e 1.000 regras .kN p: poucas tentativas completas', () {
      final rules = StringBuffer();
      for (var i = 0; i < 1000; i++) {
        rules.write('.k$i p{color:red}');
      }
      rules.write('.w p{color:blue}');
      final m = run(
        '<div class="w">${List.filled(2000, '<p>x</p>').join()}</div>',
        css: {'a.css': '$rules'},
      );
      final ps = named(m.tree, 'p');
      expect(ps, hasLength(2000));
      for (final p in ps) {
        expect(valuesOf(m, p).valueOf(PropertyId.color), blue);
      }
      expect(lastFullMatchAttempts, lessThan(100000));
    });

    test('Revisão 3: 10.000 <div> aninhados, sem estouro e linear', () {
      const depth = 10000;
      final body = '${'<div>' * depth}<p>fundo</p>${'</div>' * depth}';
      final watch = Stopwatch()..start();
      final m = run(body, css: {'a.css': 'div div div p{color:red}'});
      watch.stop();
      expect(colorOf(m, 'p'), red);
      expect(named(m.tree, 'div'), hasLength(depth));
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('profundo sem casar: seletor que falha também é linear', () {
      const depth = 10000;
      final body = '${'<div>' * depth}<p>fundo</p>${'</div>' * depth}';
      final watch = Stopwatch()..start();
      final m = run(body, css: {'a.css': 'div div span p{color:red}'});
      watch.stop();
      expect(colorOf(m, 'p'), isNull);
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });
  });

  group('@media e isValidFor', () {
    test('max-width 600 casado em 500', () {
      final m = run(
        '<p>a</p>',
        css: {'a.css': '@media (max-width: 600px){p{color:red}}'},
      );
      expect(colorOf(m, 'p'), red);
      expect(
        m.isValidFor(const StyleEnvironment(pageWidth: 550, pageHeight: 800)),
        isTrue,
      );
      expect(
        m.isValidFor(const StyleEnvironment(pageWidth: 700, pageHeight: 800)),
        isFalse,
      );
      expect(
        m.isValidFor(
          const StyleEnvironment(
            pageWidth: 500,
            pageHeight: 800,
            colorScheme: ColorScheme.dark,
          ),
        ),
        isTrue,
      );
    });

    test('regra fora do @media em 700 não casa e a troca invalida', () {
      final m = run(
        '<p>a</p>',
        css: {'a.css': '@media (max-width: 600px){p{color:red}}'},
        environment: const StyleEnvironment(pageWidth: 700, pageHeight: 800),
      );
      expect(colorOf(m, 'p'), isNull);
      expect(m.isValidFor(env), isFalse);
    });

    test('media do <link> também é registrada', () {
      final m = run(
        '<p>a</p>',
        head:
            '<link rel="stylesheet" href="a.css" media="(min-width: 600px)"/>',
        files: {'a.css': 'p{color:red}'},
      );
      expect(colorOf(m, 'p'), isNull);
      expect(
        m.isValidFor(const StyleEnvironment(pageWidth: 700, pageHeight: 800)),
        isFalse,
      );
    });

    test('sem @media, sempre válido', () {
      final m = run('<p>a</p>', css: {'a.css': 'p{color:red}'});
      for (final e in const [
        StyleEnvironment(pageWidth: 1, pageHeight: 1),
        StyleEnvironment(pageWidth: 5000, pageHeight: 300),
        StyleEnvironment(
          pageWidth: 500,
          pageHeight: 800,
          colorScheme: ColorScheme.dark,
        ),
      ]) {
        expect(m.isValidFor(e), isTrue);
      }
    });
  });

  group('pseudo-elementos', () {
    test('p::before gera entrada para cada p, em ordem', () {
      final m = run(
        '<p>a</p><div>x</div><p>b</p>',
        css: {'a.css': 'p::before{content:"x"}'},
      );
      final ps = named(m.tree, 'p');
      expect(m.pseudoElements.toList(), ps);
      expect(m.pseudoKinds.toList(), [
        PseudoElement.before.index,
        PseudoElement.before.index,
      ]);
      expect(m.sets[m.pseudoSets[0]].declares(PropertyId.content), isTrue);
      // O elemento em si não recebe o `content` do pseudo.
      expect(valuesOf(m, ps.first).declares(PropertyId.content), isFalse);
    });

    test('::first-letter vazio também gera entrada; ordenado por tipo', () {
      final m = run(
        '<p>a</p>',
        css: {
          'a.css':
              'p::first-letter{} p::after{content:"y"} p::before{content:"x"}',
        },
      );
      final p = named(m.tree, 'p').single;
      expect(m.pseudoElements.toList(), [p, p, p]);
      expect(m.pseudoKinds.toList(), [
        PseudoElement.before.index,
        PseudoElement.after.index,
        PseudoElement.firstLetter.index,
      ]);
      expect(m.sets[m.pseudoSets[2]].properties, isEmpty);
    });

    test('sem regra de pseudo, nenhuma entrada', () {
      final m = run('<p>a</p>', css: {'a.css': 'p{color:red}'});
      expect(m.pseudoElements, isEmpty);
      expect(m.pseudoKinds, isEmpty);
      expect(m.pseudoSets, isEmpty);
    });
  });

  group('@page e @font-face', () {
    test('@page{margin:1em} → top em 1', () {
      final m = run('<p>a</p>', css: {'a.css': '@page{margin:1em}'});
      expect(m.pageMargins!.top!.em, 1);
    });

    test('por lado, o último @page com condição verdadeira', () {
      final m = run(
        '<p>a</p>',
        css: {
          'a.css':
              '@page{margin:1em} @page{margin-left:2px} '
              '@media print{@page{margin-top:9px}}',
        },
      );
      final pm = m.pageMargins!;
      expect(pm.top!.em, 1);
      expect(pm.left!.px, 2);
      expect(pm.right!.em, 1);
    });

    test('lado nunca declarado fica null', () {
      final m = run(
        '<p>a</p>',
        css: {'a.css': '@page{margin-top:1em} @page{margin-left:2px}'},
      );
      final pm = m.pageMargins!;
      expect(pm.top!.em, 1);
      expect(pm.left!.px, 2);
      expect(pm.right, isNull);
      expect(pm.bottom, isNull);
    });

    test('sem @page, null', () {
      expect(run('<p>a</p>').pageMargins, isNull);
    });

    test('@font-face das folhas do documento', () {
      final m = run(
        '<p>a</p>',
        css: {'a.css': '@font-face{font-family:Body;src:url(f.ttf)}'},
      );
      expect(m.fontFaces.single.family, 'Body');
    });
  });

  test('retainedBytes inclui a árvore e cresce com o conteúdo', () {
    final small = run('<p>a</p>');
    final big = run(
      List.filled(500, '<p class="t">x</p>').join(),
      css: {'a.css': '.t{color:red}'},
    );
    expect(small.retainedBytes, greaterThan(small.tree.retainedBytes));
    expect(big.retainedBytes, greaterThan(small.retainedBytes));
  });
}
