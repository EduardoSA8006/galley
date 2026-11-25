import 'dart:typed_data';

import '../../../core/errors/galley_exception.dart';
import '../../document/domain/document_tree.dart';
import 'css_value.dart';
import 'matched_document.dart';
import 'properties.dart';
import 'rule_index.dart';
import 'selector.dart';
import 'selector_matcher.dart';
import 'style_environment.dart';
import 'stylesheet.dart';
import 'text_run.dart';
import 'value_computer.dart';

/// Declarações de `style=` do [element]; `null` se não houver.
typedef InlineStyleOf = List<Declaration>? Function(int element);

/// Casa as regras de [index] em todos os elementos de [tree] e monta a
/// cascata da editora (spec §8.3, §8.5, §8.6).
///
/// A árvore é percorrida em ordem de documento **sem recursão** (os nós já
/// estão em pré-ordem; uma pilha guarda os ancestrais abertos), mantendo o
/// filtro de ancestrais do [matcher]. Ordem da cascata, crescente: agente
/// normal < editora normal (folhas, depois `style=`) < editora `!important`
/// (folhas, depois `style=`) < agente `!important`; dentro do nível,
/// especificidade e depois a posição no índice.
///
/// [media] já traz as condições avaliadas por quem montou o [index]; os
/// conjuntos são internados pela identidade das declarações vencedoras.
MatchedDocument cascadeDocument({
  required String path,
  required String? documentLang,
  required StyleSheet userAgentSheet,
  required DocumentTree tree,
  required DocumentRuleIndex index,
  required List<IndexedRule> rules,
  required SelectorMatcher matcher,
  required InlineStyleOf inlineStyle,
  required List<FontFaceRule> fontFaces,
  required PageMargins? pageMargins,
  required MediaChecks media,
  String? internalError,
}) {
  final cascade = _Cascade(rules);
  final nodeCount = tree.nodeCount;
  final elementSets = Int32List(nodeCount)..fillRange(0, nodeCount, -1);
  final pseudoElements = <int>[];
  final pseudoKinds = <int>[];
  final pseudoSets = <int>[];
  final open = <int>[];
  final candidates = <int>[];
  final matched = <int>[];
  const pseudoCount = 4; // PseudoElement.values.length
  for (var n = 0; n < nodeCount; n++) {
    if (tree.kindOf(n) != NodeKind.element) continue;
    // Pré-ordem: os ancestrais de [n] são o prefixo da pilha que termina
    // no pai; os demais já foram fechados.
    final parent = tree.parentOf(n);
    while (open.isNotEmpty && open.last != parent) {
      matcher.popAncestor(open.removeLast());
    }

    candidates.clear();
    index.candidatesOf(n, candidates);
    matched.clear();
    var pseudoMask = 0;
    for (final c in candidates) {
      final selector = rules[c].rule.selector;
      if (matcher.rejectsByAncestors(selector)) continue;
      if (!matcher.matches(selector, n)) continue;
      matched.add(c);
      final pseudo = selector.pseudoElement;
      if (pseudo != null) pseudoMask |= 1 << pseudo.index;
    }
    if (matched.length > 1) matched.sort(cascade.compare);

    elementSets[n] = cascade.run(matched, null, inlineStyle(n));
    if (pseudoMask != 0) {
      for (var k = 0; k < pseudoCount; k++) {
        if (pseudoMask & (1 << k) == 0) continue;
        pseudoElements.add(n);
        pseudoKinds.add(k);
        pseudoSets.add(cascade.run(matched, PseudoElement.values[k], null));
      }
    }

    matcher.pushAncestor(n);
    open.add(n);
  }
  final sets = List<CascadedValues>.unmodifiable(cascade.sets);
  final environment = media.environment;
  final marks = classifyTextRuns(
    tree: tree,
    sets: sets,
    elementSets: elementSets,
    fontFaces: fontFaces,
    pageWidth: environment.pageWidth,
    pageHeight: environment.pageHeight,
  );
  var viewportFontSize = false;
  for (final set in sets) {
    final size = set.valueOf(PropertyId.fontSize);
    if (size is CssLengthSpec && (size.vw != 0 || size.vh != 0)) {
      viewportFontSize = true;
      break;
    }
  }
  return MatchedDocument(
    path: path,
    documentLang: documentLang,
    userAgentSheet: userAgentSheet,
    internalError: internalError,
    viewportFontSize: viewportFontSize,
    tree: tree,
    sets: sets,
    elementSets: elementSets,
    pseudoElements: Int32List.fromList(pseudoElements),
    pseudoKinds: Uint8List.fromList(pseudoKinds),
    pseudoSets: Int32List.fromList(pseudoSets),
    fontFaces: List.unmodifiable(fontFaces),
    pageMargins: pageMargins,
    pageWidth: environment.pageWidth,
    pageHeight: environment.pageHeight,
    flags: marks.flags,
    bodyFontSize: marks.bodyFontSize,
    publisherFamilies: marks.publisherFamilies,
    familyTable: marks.familyTable,
    mediaQueries: List.unmodifiable(media.queries),
    mediaResults: List.unmodifiable(media.results),
  );
}

/// Casamento de reserva só com a folha padrão [userAgentSheet] (sem folhas
/// do livro, `style=`, `@font-face` nem `@page`), marcado com
/// [internalError]: o que sobra quando o casamento ou o `restyle` têm um
/// defeito interno.
///
/// Se até essa cascata lançar, devolve um casamento em que todo elemento
/// tem o conjunto vazio (valores iniciais e herança). Só [GalleyException]
/// escapa.
MatchedDocument userAgentMatch({
  required String path,
  required String? documentLang,
  required StyleSheet userAgentSheet,
  required DocumentTree tree,
  required StyleEnvironment environment,
  required String internalError,
}) {
  try {
    final media = MediaChecks(environment);
    final rules = [
      for (final rule in userAgentSheet.rules)
        if (media.all(rule.conditions)) IndexedRule(rule, userAgent: true),
    ];
    final index = RuleIndex(rules);
    return cascadeDocument(
      path: path,
      documentLang: documentLang,
      userAgentSheet: userAgentSheet,
      tree: tree,
      index: index.bind(tree),
      rules: index.rules,
      matcher: SelectorMatcher(tree, documentLang: documentLang),
      inlineStyle: (_) => null,
      fontFaces: const [],
      pageMargins: null,
      media: media,
      internalError: internalError,
    );
  } on GalleyException {
    rethrow;
  } on Object {
    return _emptyMatch(
      path: path,
      documentLang: documentLang,
      userAgentSheet: userAgentSheet,
      tree: tree,
      environment: environment,
      internalError: internalError,
    );
  }
}

/// Casamento em que todo elemento tem [CascadedValues.empty]; não depende
/// de folha, seletor nem classificação de texto corrido.
MatchedDocument _emptyMatch({
  required String path,
  required String? documentLang,
  required StyleSheet userAgentSheet,
  required DocumentTree tree,
  required StyleEnvironment environment,
  required String internalError,
}) {
  final nodeCount = tree.nodeCount;
  final elementSets = Int32List(nodeCount);
  final families = Int32List(nodeCount)..fillRange(0, nodeCount, -1);
  for (var n = 0; n < nodeCount; n++) {
    if (tree.kindOf(n) != NodeKind.element) elementSets[n] = -1;
  }
  return MatchedDocument(
    path: path,
    documentLang: documentLang,
    userAgentSheet: userAgentSheet,
    internalError: internalError,
    viewportFontSize: false,
    tree: tree,
    sets: List.unmodifiable([CascadedValues.empty]),
    elementSets: elementSets,
    pseudoElements: Int32List(0),
    pseudoKinds: Uint8List(0),
    pseudoSets: Int32List(0),
    fontFaces: const [],
    pageMargins: null,
    pageWidth: environment.pageWidth,
    pageHeight: environment.pageHeight,
    flags: Uint8List(nodeCount),
    bodyFontSize: kInitialFontSize,
    publisherFamilies: families,
    familyTable: const [],
    mediaQueries: const [],
    mediaResults: const [],
  );
}

/// Estado da cascata de um documento: vencedor por propriedade e a tabela
/// de internamento.
final class _Cascade {
  _Cascade(this._rules);

  final List<IndexedRule> _rules;

  /// Vencedor atual por propriedade (reposto a `null` depois de cada
  /// elemento).
  final List<Declaration?> _slots = List<Declaration?>.filled(
    kPropertyCount,
    null,
  );
  final List<int> _touched = [];

  final Map<_WinnerKey, int> _interned = {};
  final List<CascadedValues> sets = [];

  /// Ordem crescente de prioridade: agente antes da editora; depois
  /// especificidade; depois a posição.
  int compare(int a, int b) {
    final ra = _rules[a];
    final rb = _rules[b];
    if (ra.userAgent != rb.userAgent) return ra.userAgent ? -1 : 1;
    final sa = ra.rule.selector.specificity;
    final sb = rb.rule.selector.specificity;
    if (sa != sb) return sa < sb ? -1 : 1;
    return a - b;
  }

  void _apply(Declaration d) {
    final p = d.property;
    if (_slots[p] == null) _touched.add(p);
    _slots[p] = d;
  }

  void _pass(
    List<int> sorted,
    PseudoElement? pseudo, {
    required bool userAgent,
    required bool important,
  }) {
    for (final i in sorted) {
      final r = _rules[i];
      if (r.userAgent != userAgent || r.rule.selector.pseudoElement != pseudo) {
        continue;
      }
      for (final d in r.rule.declarations) {
        if (d.important == important) _apply(d);
      }
    }
  }

  void _inline(List<Declaration>? inline, {required bool important}) {
    if (inline == null) return;
    for (final d in inline) {
      if (d.important == important) _apply(d);
    }
  }

  /// Cascata das regras [sorted] (já em ordem crescente de prioridade) que
  /// têm o pseudo-elemento [pseudo], mais [inline]; devolve o índice do
  /// conjunto internado.
  int run(List<int> sorted, PseudoElement? pseudo, List<Declaration>? inline) {
    _pass(sorted, pseudo, userAgent: true, important: false);
    _pass(sorted, pseudo, userAgent: false, important: false);
    _inline(inline, important: false);
    _pass(sorted, pseudo, userAgent: false, important: true);
    _inline(inline, important: true);
    _pass(sorted, pseudo, userAgent: true, important: true);

    final touched = _touched..sort();
    final winners = List<Declaration>.generate(
      touched.length,
      (i) => _slots[touched[i]]!,
      growable: false,
    );
    for (final p in touched) {
      _slots[p] = null;
    }
    touched.clear();

    final key = _WinnerKey(winners);
    final known = _interned[key];
    if (known != null) return known;
    final properties = Int32List(winners.length);
    for (var i = 0; i < winners.length; i++) {
      properties[i] = winners[i].property;
    }
    final set = winners.isEmpty
        ? CascadedValues.empty
        : CascadedValues(
            properties,
            List.unmodifiable([for (final d in winners) d.value]),
          );
    sets.add(set);
    return _interned[key] = sets.length - 1;
  }
}

/// Chave de internamento: a lista das declarações vencedoras, comparadas
/// por identidade.
final class _WinnerKey {
  _WinnerKey(this.declarations) : hashCode = _hash(declarations);

  final List<Declaration> declarations;

  @override
  final int hashCode;

  static int _hash(List<Declaration> list) {
    var h = list.length;
    for (final d in list) {
      h = (h * 31 + identityHashCode(d)) & 0x3FFFFFFF;
    }
    return h;
  }

  @override
  bool operator ==(Object other) {
    if (other is! _WinnerKey) return false;
    final a = declarations;
    final b = other.declarations;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }
}
