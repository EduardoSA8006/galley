/// Índice de regras pela parte mais à direita do seletor (spec do CSS
/// §10.3): um balde por `id`, pela primeira classe, pelo tipo, e o
/// universal.
///
/// Linear no número de seletores: cada seletor entra em um balde só, uma
/// vez; o construtor para em [maxRulesPerSection] entradas sem olhar o
/// resto.
library;

import 'parser.dart';
import 'properties.dart';
import 'selector.dart';
import 'ua_sheet.dart';

/// Seletores (entradas do índice) por seção (#14).
const int maxRulesPerSection = 20000;

enum CssOrigin { userAgent, author, styleAttribute }

final class RuleEntry {
  const RuleEntry(this.selector, this.declarations, this.seqBase, this.origin);

  final Selector selector;

  /// O bloco, partilhado pelos seletores da lista.
  final List<Declaration> declarations;

  /// Ordem da cascata: `seq` da primeira declaração do bloco; a i-ésima tem
  /// `seqBase + i`.
  final int seqBase;

  /// `userAgent` ou `author`.
  final CssOrigin origin;
}

final class RuleIndex {
  /// [rules] na ordem da cascata, com a origem e o `href` da folha. Uma
  /// regra sem declaração não entra (não muda nenhum estilo).
  RuleIndex(
    Iterable<(StyleRule, CssOrigin, String)> rules, {
    int maxEntries = maxRulesPerSection,
  }) {
    final byId = <String, List<RuleEntry>>{};
    final byClass = <String, List<RuleEntry>>{};
    final byTag = <String, List<RuleEntry>>{};
    final universal = <RuleEntry>[];
    var seq = 0;
    var length = 0;
    String? truncated;
    outer:
    for (final (rule, origin, href) in rules) {
      if (rule.declarations.isEmpty) continue;
      for (final selector in rule.selectors) {
        if (length == maxEntries) {
          truncated = href;
          break outer;
        }
        final entry = RuleEntry(selector, rule.declarations, seq, origin);
        final k = selector.rightmost;
        final id = k.id;
        final tag = k.tag;
        if (id != null) {
          (byId[id] ??= []).add(entry);
        } else if (k.classes.isNotEmpty) {
          (byClass[k.classes.first] ??= []).add(entry);
        } else if (tag != null) {
          (byTag[tag] ??= []).add(entry);
        } else {
          universal.add(entry);
        }
        length++;
      }
      seq += rule.declarations.length;
    }
    List<RuleEntry> freeze(List<RuleEntry> l) => List.unmodifiable(l);
    _byId = byId.map((k, v) => MapEntry(k, freeze(v)));
    _byClass = byClass.map((k, v) => MapEntry(k, freeze(v)));
    _byTag = byTag.map((k, v) => MapEntry(k, freeze(v)));
    this.universal = freeze(universal);
    this.length = length;
    truncatedAt = truncated;
  }

  late final Map<String, List<RuleEntry>> _byId;
  late final Map<String, List<RuleEntry>> _byClass;
  late final Map<String, List<RuleEntry>> _byTag;

  /// Atributo e pseudo-classe sozinhos, `*`.
  late final List<RuleEntry> universal;

  /// Entradas (seletores) no índice.
  late final int length;

  /// `href` da folha onde o teto cortou; `null` se tudo entrou.
  late final String? truncatedAt;

  List<RuleEntry> byId(String id) => _byId[id] ?? const [];

  List<RuleEntry> byClass(String className) => _byClass[className] ?? const [];

  List<RuleEntry> byTag(String lowerName) => _byTag[lowerName] ?? const [];
}

/// Índice da folha padrão, montado uma vez (preguiçoso).
final RuleIndex userAgentIndex = RuleIndex([
  for (final r in userAgentSheet.rules) (r, CssOrigin.userAgent, 'userAgent'),
]);
