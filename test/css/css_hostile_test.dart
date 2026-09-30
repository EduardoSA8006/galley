// Entradas hostis da cascata (spec do CSS §14.3): cada uma com teto de tempo
// folgado para o CI e a afirmação de corte certo. As do tokenizador, do
// parser, dos seletores e do loader estão nos testes de cada um.
import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/css/cascade.dart';
import 'package:galley/src/css/computed_style.dart';
import 'package:galley/src/css/loader.dart';
import 'package:galley/src/css/parser.dart';
import 'package:galley/src/diagnostics/diagnostic.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

const _section = 'OEBPS/Text/c.xhtml';

SectionSheets _sheets(String css) => SectionSheets([
  AppliedSheet(SheetRef.style(css), parseStyleSheet(css), 'a.css'),
]);

/// Documento vazio e o `body`, para montar a árvore por código (o
/// `html.parse` é quadrático com aninhamento profundo).
(Document, Element) _empty() {
  final document = html.parse('<html><head></head><body></body></html>');
  return (document, document.body!);
}

Element _el(String tag, [Map<String, String> attributes = const {}]) {
  final e = Element.tag(tag);
  e.attributes.addAll(attributes);
  return e;
}

/// Orçamento dos hostis que só precisam esgotá-lo: o padrão (2^22) fica só
/// no `div … div p`, o pior custo por passo (decisão 27 do plano).
const int _small = 1 << 20;

/// Cascata de [document] com [css], contando as cessões; mede só a cascata
/// (o parse da folha fica de fora).
(SectionStyles, DiagnosticSink, Duration, int) _run(
  Document document,
  String css, {
  int budget = cascadeBudget,
}) {
  final sheets = css.isEmpty ? SectionSheets.empty : _sheets(css);
  final sink = DiagnosticSink();
  final into = CascadeResult();
  var yields = 0;
  final sw = Stopwatch()..start();
  for (final _ in computeStyles(
    document,
    sheets,
    sectionPath: _section,
    sink: sink,
    into: into,
    budget: budget,
  )) {
    yields++;
  }
  sw.stop();
  return (into.styles, sink, sw.elapsed, yields);
}

int _count(Document document) {
  var n = 0;
  final stack = <Node>[document];
  while (stack.isNotEmpty) {
    final node = stack.removeLast();
    if (node is Element) n++;
    stack.addAll(node.nodes);
  }
  return n;
}

const _limit = Duration(seconds: 5);

void main() {
  test(
    '20 000 regras x p sobre 100 000 <p>: Bloom rejeita e o orçamento corta',
    () {
      final (document, body) = _empty();
      for (var i = 0; i < 100000; i++) {
        body.append(_el('p'));
      }
      final css = List.generate(
        20000,
        (k) => 'x$k p { font-style: italic }',
      ).join();
      final (styles, sink, elapsed, _) = _run(document, css, budget: _small);
      expect(styles.budgetExhausted, isTrue);
      expect(sink.diagnostics.single.details['reason'], 'budget');
      expect(styles.length, 100003);
      expect(elapsed, lessThan(_limit));
    },
  );

  test('composto de 200 000 classes contra elemento com 200 000 classes', () {
    final classes = List.generate(200000, (k) => 'c$k').join(' ');
    final (document, body) = _empty();
    body.append(_el('p', {'class': classes}));
    final css =
        '${List.generate(200000, (k) => '.c$k').join()} { font-style: italic }';
    expect(parseStyleSheet(css).rules, isEmpty, reason: 'fora do subconjunto');
    final (styles, _, elapsed, _) = _run(document, css);
    expect(
      styles.styleOf(body.children.single)!.fontStyle,
      CssFontStyle.normal,
    );
    expect(elapsed, lessThan(_limit));
  });

  test('seletores de 1 MiB e 100 elementos com class e id de 1 MiB', () {
    final big = 'x' * (1024 * 1024);
    final (document, body) = _empty();
    for (var i = 0; i < 100; i++) {
      body.append(_el('p', {'class': big, 'id': big}));
    }
    final css =
        '.$big { display: none } #$big { display: none } '
        '[a="$big"] { display: none } '
        '${List.generate(20000, (k) => '.c$k { display: none }').join()}';
    final (styles, sink, elapsed, _) = _run(document, css);
    expect(styles.styleOf(body.children.first)!.display, CssDisplay.block);
    expect(styles.budgetExhausted, isFalse);
    expect(elapsed, lessThan(_limit));
  });

  test('20 000 regras .cN e 30 elementos com as 20 000 classes: budget', () {
    final classes = List.generate(20000, (k) => 'c$k').join(' ');
    final (document, body) = _empty();
    // Um elemento por <section>: só um Set de 20 000 classes vivo por vez.
    for (var i = 0; i < 30; i++) {
      body.append(_el('section')..append(_el('p', {'class': classes})));
    }
    // Uma consulta, um candidato, um seletor e uma declaração por classe:
    // 80 000 passos por elemento, 2^20 antes do 14º.
    final css = List.generate(
      20000,
      (k) => '.c$k { font-style: italic }',
    ).join();
    final (styles, _, elapsed, _) = _run(document, css, budget: _small);
    expect(styles.budgetExhausted, isTrue);
    expect(elapsed, lessThan(_limit));
  });

  test(
    '20 000 regras * { … } sobre 5 000 elementos: budget, folha padrão fica',
    () {
      final (document, body) = _empty();
      for (var i = 0; i < 5000; i++) {
        body.append(_el('p'));
      }
      final css = List.generate(20000, (_) => '* { margin-top: 1em }').join();
      final (styles, _, elapsed, _) = _run(document, css, budget: _small);
      expect(styles.budgetExhausted, isTrue);
      final last = styles.styleOf(body.children.last)!;
      expect((last.display, last.margin.top), (CssDisplay.block, 0.0));
      expect(elapsed, lessThan(_limit));
    },
  );

  test('20 000 regras div … div p (32 compostos) sobre 250 div aninhados', () {
    final (document, body) = _empty();
    var parent = body;
    for (var i = 0; i < 250; i++) {
      final div = _el('div');
      parent
        ..append(div)
        ..append(_el('p'));
      parent = div;
    }
    final css = List.generate(
      20000,
      (k) => '${'div ' * 31}p { text-indent: ${k % 8}em }',
    ).join();
    // O único hostil com o orçamento padrão: o casamento mais caro por passo.
    final (styles, _, elapsed, _) = _run(document, css);
    expect(styles.budgetExhausted, isTrue);
    expect(styles.length, _count(document));
    expect(elapsed, lessThan(_limit));
  });

  test('DOM de 10 000 níveis: dom-depth uma vez, todo elemento com estilo', () {
    final (document, body) = _empty();
    var parent = body;
    for (var i = 0; i < 10000; i++) {
      final div = _el('div');
      parent.append(div);
      parent = div;
    }
    final (styles, sink, elapsed, _) = _run(
      document,
      'div { font-style: italic }',
    );
    expect(styles.length, 10003);
    expect(sink.diagnostics.single.details['limit'], 'dom-depth');
    expect(styles.styleOf(parent)!.fontStyle, CssFontStyle.italic);
    expect(elapsed, lessThan(_limit));
  });

  test(
    '100 000 style="" iguais e 1 000 distintos de 8 KiB; um de 8 KiB + 1',
    () {
      final (document, body) = _empty();
      for (var i = 0; i < 100000; i++) {
        body.append(_el('p', {'style': 'font-style: italic'}));
      }
      for (var i = 0; i < 1000; i++) {
        final text = 'text-indent: ${i}em;'.padRight(maxStyleAttributeLength);
        body.append(_el('p', {'style': text}));
      }
      body.append(_el('p', {'style': ' ' * (maxStyleAttributeLength + 1)}));
      final (styles, sink, elapsed, _) = _run(document, '');
      expect(
        styles.styleOf(body.children.first)!.fontStyle,
        CssFontStyle.italic,
      );
      expect(sink.diagnostics.single.details['reason'], 'too-large');
      expect(elapsed, lessThan(_limit));
    },
  );

  test(
    'ids repetidos: 100 000 elementos com o mesmo id e 20 000 regras #x',
    () {
      final (document, body) = _empty();
      for (var i = 0; i < 100000; i++) {
        body.append(_el('p', {'id': 'x'}));
      }
      final css = List.generate(
        20000,
        (_) => '#x { font-style: italic }',
      ).join();
      final (styles, _, elapsed, _) = _run(document, css, budget: _small);
      // Os primeiros recebem a regra; esgotado o orçamento, os seguintes a
      // perdem, e o custo fica no teto.
      expect(
        styles.styleOf(body.children.first)!.fontStyle,
        CssFontStyle.italic,
      );
      expect(styles.budgetExhausted, isTrue);
      expect(
        styles.styleOf(body.children.last)!.fontStyle,
        CssFontStyle.normal,
      );
      expect(elapsed, lessThan(_limit));
    },
  );

  test('elemento com 100 000 classes iguais e 100 000 distintas', () {
    final (document, body) = _empty();
    body
      ..append(_el('p', {'class': List.filled(100000, 'a').join(' ')}))
      ..append(
        _el('p', {'class': List.generate(100000, (k) => 'k$k').join(' ')}),
      );
    final (styles, _, elapsed, _) = _run(document, '.a { font-style: italic }');
    expect(styles.styleOf(body.children.first)!.fontStyle, CssFontStyle.italic);
    expect(elapsed, lessThan(_limit));
  });

  test('bloco de 100 000 declarações casado por 1 000 elementos: budget', () {
    final (document, body) = _empty();
    for (var i = 0; i < 1000; i++) {
      body.append(_el('p'));
    }
    final css = 'p { ${'font-style: italic; ' * 100000} }';
    final (styles, _, elapsed, _) = _run(document, css, budget: _small);
    expect(styles.budgetExhausted, isTrue);
    expect(elapsed, lessThan(_limit));
  });

  test(
    '100 000 <ul> na profundidade 256: a folha padrão não sobe ancestrais',
    () {
      // html > body > ul > ol > menu > 250 div > 100 000 ul (profundidade 256):
      // com seletores descendentes (`ul ul`, `ol ul ul`), cada ul subiria os
      // 250 div; pelo nível de lista herdado, o custo por ul é constante.
      final (document, body) = _empty();
      Element parent = body;
      for (final tag in [
        'ul',
        'ol',
        'menu',
        for (var i = 0; i < 250; i++) 'div',
      ]) {
        final e = _el(tag);
        parent.append(e);
        parent = e;
      }
      for (var i = 0; i < 100000; i++) {
        parent.append(_el('ul'));
      }
      final (styles, _, elapsed, yields) = _run(document, '');
      expect(
        styles.styleOf(parent.children.last)!.listStyleType,
        CssListStyleType.square,
      );
      // Menos de 32 passos por ul: ~780 cessões; subindo os ancestrais seriam
      // dezenas de milhares.
      expect(yields, lessThan(100000 * 32 ~/ cascadeYieldSteps));
      expect(elapsed, lessThan(_limit));
    },
  );
}
