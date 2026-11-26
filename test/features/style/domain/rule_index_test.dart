import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/core/diagnostics/diagnostic_sink.dart';
import 'package:galley/src/features/document/data/parse_document.dart';
import 'package:galley/src/features/document/domain/document_tree.dart';
import 'package:galley/src/features/style/data/stylesheet_builder.dart';
import 'package:galley/src/features/style/domain/rule_index.dart';
import 'package:galley/src/features/style/domain/selector_matcher.dart';
import 'package:galley/src/features/style/domain/stylesheet.dart';

const _xhtml = 'http://www.w3.org/1999/xhtml';
const _svg = 'http://www.w3.org/2000/svg';

DocumentTree tree(String body) => parseDocumentBytes(
  Uint8List.fromList(
    utf8.encode(
      '<html xmlns="$_xhtml" xmlns:svg="$_svg"><body>$body</body></html>',
    ),
  ),
  path: 'a.xhtml',
).tree;

List<StyleRule> rules(String css) => buildStyleSheet(
  css,
  path: 'a.css',
  fontPrefix: '',
  sink: const NullDiagnosticSink(),
).rules;

RuleIndex index(String css) =>
    RuleIndex([for (final r in rules(css)) IndexedRule(r, userAgent: false)]);

int first(DocumentTree t, String name) {
  for (var n = 0; n < t.nodeCount; n++) {
    if (t.kindOf(n) == NodeKind.element && t.localNameOf(n) == name) return n;
  }
  throw StateError('sem $name');
}

/// Ordens (na folha) das regras candidatas de [element], ordenadas.
List<int> candidates(RuleIndex i, DocumentRuleIndex d, int element) {
  final out = <int>[];
  d.candidatesOf(element, out);
  return [for (final c in out) i.rules[c].rule.order]..sort();
}

void main() {
  group('baldes', () {
    const css =
        '#a{} .b{} p{} *{} [title]{} p#a.b{} span.b{} '
        '#nope{} .zzz{} article{}';
    // ordens: 0 #a, 1 .b, 2 p, 3 *, 4 [title], 5 p#a.b, 6 span.b,
    // 7 #nope, 8 .zzz, 9 article

    test('cada elemento recebe os baldes de id, classes, nome e universal', () {
      final t = tree('<p id="a" class="b">x</p><span>y</span><div/>');
      final i = index(css);
      final d = i.bind(t);
      expect(candidates(i, d, first(t, 'p')), [0, 1, 2, 3, 4, 5, 6]);
      expect(candidates(i, d, first(t, 'span')), [3, 4]);
      expect(candidates(i, d, first(t, 'div')), [3, 4]);
    });

    test('chave ausente no documento: regra descartada de cara', () {
      final t = tree('<p id="a" class="b">x</p>');
      final d = index(css).bind(t);
      expect(d.discardedRules, 3);
    });

    test('id vence classe e nome; classe vence nome', () {
      final i = index('p#a.b{} p.b{}');
      expect(i.rules.map((r) => r.bucket), [
        RuleBucket.id,
        RuleBucket.className,
      ]);
      expect(index('p{} *.x{} *{}').rules.map((r) => r.bucket), [
        RuleBucket.type,
        RuleBucket.className,
        RuleBucket.universal,
      ]);
    });

    test('nome XHTML sem caixa; outros namespaces exatos', () {
      final t = tree(
        '<p>x</p><svg:svg><svg:foreignObject/><svg:foreignobject/></svg:svg>',
      );
      final i = index('P{} foreignObject{} foreignobject{}');
      final d = i.bind(t);
      expect(candidates(i, d, first(t, 'p')), [0]);
      expect(candidates(i, d, first(t, 'foreignObject')), [1]);
      expect(candidates(i, d, first(t, 'foreignobject')), [2]);
    });

    test('elemento XHTML com nome em maiúsculas usa a chave sem caixa', () {
      final t = tree('<P>x</P>');
      final i = index('p{} P{}');
      final d = i.bind(t);
      expect(candidates(i, d, first(t, 'P')), [0, 1]);
    });

    test('cada candidata aparece uma vez', () {
      final t = tree('<p id="a" class="b c">x</p>');
      final i = index('.c{} *{} #a{} p{} .b{}');
      final d = i.bind(t);
      final out = <int>[];
      d.candidatesOf(first(t, 'p'), out);
      expect(out, hasLength(5));
    });
  });

  group('filtro de ancestrais', () {
    test('rejeita seletor cujo ancestral não está na pilha', () {
      final t = tree('<div class="w" id="d"><section><p>x</p></section></div>');
      final m = SelectorMatcher(t);
      final p = first(t, 'p');
      final chain = <int>[];
      for (var n = t.parentOf(p); n > 0; n = t.parentOf(n)) {
        chain.insert(0, n);
      }
      chain.forEach(m.pushAncestor);
      bool rejects(String css) =>
          m.rejectsByAncestors(rules(css).single.selector);
      expect(rejects('.w p{}'), isFalse);
      expect(rejects('#d p{}'), isFalse);
      expect(rejects('DIV > section p{}'), isFalse);
      expect(rejects('html body p{}'), isFalse);
      expect(rejects('p{}'), isFalse);
      expect(rejects('.k p{}'), isTrue);
      expect(rejects('#e p{}'), isTrue);
      expect(rejects('article p{}'), isTrue);
      // Irmão não entra no filtro.
      expect(rejects('.k + p{}'), isFalse);

      // Desempilhar o div tira .w, #d e div.
      for (final n in chain.reversed) {
        m.popAncestor(n);
      }
      expect(rejects('.w p{}'), isTrue);
      expect(rejects('html p{}'), isTrue);
    });

    test('contadores: o mesmo nome em vários ancestrais', () {
      final t = tree('<div><div><p>x</p></div></div>');
      final m = SelectorMatcher(t);
      final outer = first(t, 'div');
      final inner = t.firstChildOf(outer);
      m
        ..pushAncestor(outer)
        ..pushAncestor(inner)
        ..popAncestor(inner);
      expect(m.rejectsByAncestors(rules('div p{}').single.selector), isFalse);
      m.popAncestor(outer);
      expect(m.rejectsByAncestors(rules('div p{}').single.selector), isTrue);
    });

    test('fullMatchAttempts conta as chamadas de matches', () {
      final t = tree('<p>x</p>');
      final m = SelectorMatcher(t);
      expect(m.fullMatchAttempts, 0);
      m.matches(rules('p{}').single.selector, first(t, 'p'));
      expect(m.fullMatchAttempts, 1);
    });
  });
}
