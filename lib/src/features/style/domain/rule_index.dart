import '../../document/domain/document_tree.dart';
import '../../document/domain/names.dart';
import 'css_value.dart' show asciiLower;
import 'stylesheet.dart';

/// Balde de uma regra no [RuleIndex]: a parte mais à direita do sujeito que
/// todo elemento casado precisa ter (spec §8.3).
enum RuleBucket {
  /// `#id` no sujeito.
  id,

  /// `.classe` no sujeito (sem id).
  className,

  /// Nome de tipo no sujeito (sem id nem classe).
  type,

  /// Nenhum dos anteriores: candidata para todo elemento.
  universal,
}

/// Uma regra no índice, com a origem e o balde.
final class IndexedRule {
  /// Cria a regra indexada; [userAgent] é a origem (folha padrão ou
  /// editora).
  IndexedRule(this.rule, {required this.userAgent}) : bucket = _bucketOf(rule);

  /// A regra.
  final StyleRule rule;

  /// Se vem da folha padrão (origem do agente).
  final bool userAgent;

  /// O balde.
  final RuleBucket bucket;

  static RuleBucket _bucketOf(StyleRule rule) {
    final s = rule.selector;
    if (s.rightmostId != null) return RuleBucket.id;
    if (s.rightmostClass != null) return RuleBucket.className;
    if (s.rightmostType != null) return RuleBucket.type;
    return RuleBucket.universal;
  }
}

/// Índice de regras por balde (id → classe → tipo → universal), sem
/// depender de documento: as chaves são as strings da folha.
///
/// A posição de cada regra em [rules] é a sua ordem na cascata (folha
/// padrão primeiro, depois as folhas da editora em ordem). Ligue a um
/// documento com [bind].
final class RuleIndex {
  /// Indexa [rules], na ordem da cascata. As condições (`@media`) já devem
  /// ter sido avaliadas por quem chama.
  RuleIndex(List<IndexedRule> rules) : rules = List.unmodifiable(rules) {
    for (var i = 0; i < this.rules.length; i++) {
      final r = this.rules[i];
      final s = r.rule.selector;
      switch (r.bucket) {
        case RuleBucket.id:
          (_byId[s.rightmostId!] ??= []).add(i);
        case RuleBucket.className:
          (_byClass[s.rightmostClass!] ??= []).add(i);
        case RuleBucket.type:
          // Ruling F4: a chave é o nome sem caixa; o nome exato fica na
          // regra para os elementos fora do XHTML.
          (_byType[asciiLower(s.rightmostType!)] ??= []).add(i);
        case RuleBucket.universal:
          _universal.add(i);
      }
    }
  }

  /// As regras, na ordem da cascata.
  final List<IndexedRule> rules;

  final Map<String, List<int>> _byId = {};
  final Map<String, List<int>> _byClass = {};
  final Map<String, List<int>> _byType = {};
  final List<int> _universal = [];

  /// Liga o índice à árvore [tree]: as chaves viram ids de token/nome da
  /// árvore, uma vez, e as regras com chave ausente no documento são
  /// descartadas.
  DocumentRuleIndex bind(DocumentTree tree) {
    var discarded = 0;
    final byId = <String, List<int>>{};
    for (final MapEntry(:key, :value) in _byId.entries) {
      if (tree.elementById(key) == null) {
        discarded += value.length;
      } else {
        byId[key] = value;
      }
    }
    final byClass = List<List<int>?>.filled(tree.tokens.length, null);
    for (final MapEntry(:key, :value) in _byClass.entries) {
      final token = tree.tokens.lookup(key);
      // Um token pode existir só em `epub:type`; aí não há elemento com a
      // classe e as candidatas nunca são pedidas.
      if (token == null || tree.elementsWithClass(key).isEmpty) {
        discarded += value.length;
      } else {
        byClass[token] = value;
      }
    }
    final names = tree.names;
    final byName = List<List<int>?>.filled(names.length, null);
    final used = <int>{};
    for (var nameId = 0; nameId < names.length; nameId++) {
      final local = names.localNameOf(nameId);
      final namespace = names.namespaceOf(nameId);
      if (tree.elementsNamed(namespace, local).isEmpty) continue;
      final bucket = _byType[asciiLower(local)];
      if (bucket == null) continue;
      List<int> hits;
      if (namespace == Namespaces.xhtml) {
        hits = bucket;
      } else {
        hits = [
          for (final i in bucket)
            if (rules[i].rule.selector.rightmostType == local) i,
        ];
        if (hits.isEmpty) continue;
      }
      byName[nameId] = hits;
      used.addAll(hits);
    }
    for (final bucket in _byType.values) {
      for (final i in bucket) {
        if (!used.contains(i)) discarded++;
      }
    }
    return DocumentRuleIndex._(
      tree,
      byId,
      byClass,
      byName,
      _universal,
      discarded,
    );
  }
}

/// [RuleIndex] ligado a uma árvore: candidatas por elemento.
final class DocumentRuleIndex {
  DocumentRuleIndex._(
    this._tree,
    this._byId,
    this._byClass,
    this._byName,
    this._universal,
    this.discardedRules,
  );

  final DocumentTree _tree;
  final Map<String, List<int>> _byId;
  final List<List<int>?> _byClass;
  final List<List<int>?> _byName;
  final List<int> _universal;

  /// Quantas regras foram descartadas por chave ausente no documento.
  final int discardedRules;

  /// Acrescenta a [out] as posições (em [RuleIndex.rules]) das regras
  /// candidatas do [element]: as do id, de cada classe, do nome e as
  /// universais. Sem repetição (cada regra está num só balde e as classes
  /// do elemento não se repetem), mas sem ordem garantida.
  void candidatesOf(int element, List<int> out) {
    final tree = _tree;
    if (_byId.isNotEmpty) {
      final id = tree.idOf(element);
      if (id != null) {
        final hits = _byId[id];
        if (hits != null) out.addAll(hits);
      }
    }
    for (final token in tree.classesOf(element)) {
      final hits = _byClass[token];
      if (hits != null) out.addAll(hits);
    }
    final named = _byName[tree.nameOf(element)];
    if (named != null) out.addAll(named);
    out.addAll(_universal);
  }
}
