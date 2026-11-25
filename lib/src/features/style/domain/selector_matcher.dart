import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../../document/domain/document_tree.dart';
import '../../document/domain/names.dart';
import 'css_value.dart' show asciiLower;
import 'selector.dart';

/// Resultados do casamento de um composto (como no Servo): dizem até onde
/// voltar quando um composto à esquerda falha, evitando backtracking inútil.
const int _matched = 0;
const int _restartFromLaterSibling = 1;
const int _restartFromDescendant = 2;
const int _notMatchedGlobally = 3;

/// Casa [Selector]s contra os elementos de uma [DocumentTree].
///
/// O casamento é da direita para a esquerda e iterativo (pilha explícita,
/// sem recursão). Guarda caches por árvore (nomes em minúsculas, posições
/// entre irmãos), então use um casador por árvore.
///
/// Tem também um filtro de ancestrais (Bloom com contadores, como nos
/// navegadores): quem percorre a árvore em ordem de documento empilha cada
/// elemento com [pushAncestor] antes dos seus descendentes e o desempilha
/// com [popAncestor] depois; [rejectsByAncestors] descarta, sem percorrer
/// ancestrais, o seletor que exige um ancestral (id, classe ou nome) que
/// não está no filtro. Só vale enquanto o filtro contém exatamente os
/// ancestrais do elemento testado.
final class SelectorMatcher {
  /// Cria o casador; [documentLang] é o idioma usado por `:lang()` quando
  /// nenhum ancestral declara `xml:lang`/`lang`.
  SelectorMatcher(this.tree, {String? documentLang})
    : _documentLang = documentLang == null ? null : asciiLower(documentLang),
      _xmlLangId = tree.names.lookup(Namespaces.xml, 'lang'),
      _langId = tree.names.lookup(Namespaces.none, 'lang'),
      _hrefId = tree.names.lookup(Namespaces.none, 'href'),
      _lowerNames = List<String?>.filled(tree.names.length, null);

  /// A árvore.
  final DocumentTree tree;

  final String? _documentLang;
  final int? _xmlLangId;
  final int? _langId;
  final int? _hrefId;

  /// Nome local em minúsculas ASCII por id de nome (preenchido sob demanda).
  final List<String?> _lowerNames;

  /// Id de namespace por URI (resolvido sob demanda; −1 = ausente).
  final Map<String, int> _namespaceIds = {};

  // Posição (1-based) entre irmãos; 0 = ainda não calculada.
  Int32List? _childIndex;
  Int32List? _childIndexFromEnd;
  Int32List? _typeIndex;
  Int32List? _typeIndexFromEnd;

  // Pilha do casamento: elemento candidato de cada nível.
  Int32List _candidates = Int32List(16);

  /// Contadores do filtro de ancestrais: [_filterSize] posições, duas por
  /// hash (os 12 bits baixos e os 12 seguintes). `Int32List` para não
  /// saturar com milhares de ancestrais de mesmo nome.
  final Int32List _filter = Int32List(_filterSize);
  static const int _filterSize = 4096;
  static const int _filterMask = _filterSize - 1;

  /// Hash ([SelectorHashes.ofType]) por id de nome; 0 = ainda não calculado
  /// (um hash 0 real só custa recalcular).
  late final Int32List _nameHashes = Int32List(tree.names.length);

  /// Hash ([SelectorHashes.ofClass]) por id de token de classe.
  late final List<int?> _classHashes = List<int?>.filled(
    tree.tokens.length,
    null,
  );

  int _fullMatchAttempts = 0;

  /// Quantas vezes [matches] rodou (casamentos completos, depois dos
  /// filtros de quem chama).
  @visibleForTesting
  int get fullMatchAttempts => _fullMatchAttempts;

  /// Acrescenta o elemento [element] (nome, id e classes) ao filtro de
  /// ancestrais.
  void pushAncestor(int element) => _updateFilter(element, 1);

  /// Tira o elemento [element] do filtro de ancestrais (o inverso de
  /// [pushAncestor], para o mesmo elemento).
  void popAncestor(int element) => _updateFilter(element, -1);

  /// `true` se algum dos [Selector.ancestorHashes] de [selector] está
  /// ausente do filtro: nenhum elemento cujos ancestrais sejam os do filtro
  /// pode casar. `false` não garante o casamento (falso positivo do Bloom).
  bool rejectsByAncestors(Selector selector) {
    final filter = _filter;
    for (final h in selector.ancestorHashes) {
      if (filter[h & _filterMask] == 0 ||
          filter[(h >> 12) & _filterMask] == 0) {
        return true;
      }
    }
    return false;
  }

  void _updateFilter(int element, int delta) {
    final filter = _filter;
    void add(int h) {
      filter[h & _filterMask] += delta;
      filter[(h >> 12) & _filterMask] += delta;
    }

    final nameId = tree.nameOf(element);
    var nameHash = _nameHashes[nameId];
    if (nameHash == 0) {
      nameHash = _nameHashes[nameId] = SelectorHashes.ofType(
        tree.names.localNameOf(nameId),
      ).toSigned(32);
    }
    add(nameHash);
    final id = tree.idOf(element);
    if (id != null) add(SelectorHashes.ofId(id));
    for (final token in tree.classesOf(element)) {
      add(
        _classHashes[token] ??= SelectorHashes.ofClass(
          tree.tokens.tokenOf(token),
        ),
      );
    }
  }

  /// Se [selector] casa o elemento [element] (o pseudo-elemento do seletor
  /// é ignorado aqui: casa o elemento que o origina).
  bool matches(Selector selector, int element) {
    _fullMatchAttempts++;
    final compounds = selector.compounds;
    final combinators = selector.combinators;
    final last = compounds.length - 1;
    if (_candidates.length < compounds.length) {
      _candidates = Int32List(compounds.length * 2);
    }
    final candidates = _candidates;
    var level = 0;
    var e = element;
    while (true) {
      // "Chamada" no nível [level] com o elemento [e].
      int result;
      if (!_matchesCompound(compounds[level], e)) {
        result = _restartFromLaterSibling;
      } else if (level == last) {
        result = _matched;
      } else {
        final next = _step(combinators[level], e);
        if (next < 0) {
          result = _notFound(combinators[level]);
        } else {
          candidates[level] = next;
          level++;
          e = next;
          continue;
        }
      }
      // "Retorno" do nível [level] com [result] para quem chamou.
      while (true) {
        if (level == 0) return result == _matched;
        final caller = level - 1;
        final combinator = combinators[caller];
        if (result == _matched ||
            result == _notMatchedGlobally ||
            combinator == Combinator.nextSibling) {
          level = caller;
          continue;
        }
        if (combinator == Combinator.child) {
          result = _restartFromDescendant;
          level = caller;
          continue;
        }
        if (combinator == Combinator.laterSibling &&
            result == _restartFromDescendant) {
          level = caller;
          continue;
        }
        // Tenta o próximo candidato do mesmo combinador.
        final next = _step(combinator, candidates[caller]);
        if (next < 0) {
          result = _notFound(combinator);
          level = caller;
          continue;
        }
        candidates[caller] = next;
        e = next;
        break;
      }
    }
  }

  static int _notFound(Combinator c) =>
      c == Combinator.descendant || c == Combinator.child
      ? _notMatchedGlobally
      : _restartFromDescendant;

  int _step(Combinator c, int e) => switch (c) {
    Combinator.descendant || Combinator.child => _parentElement(e),
    Combinator.nextSibling || Combinator.laterSibling => _previousElement(e),
  };

  bool _isElement(int n) => tree.kindOf(n) == NodeKind.element;

  int _parentElement(int e) {
    final p = tree.parentOf(e);
    return p >= 0 && _isElement(p) ? p : -1;
  }

  int _previousElement(int e) {
    var s = tree.previousSiblingOf(e);
    while (s >= 0 && !_isElement(s)) {
      s = tree.previousSiblingOf(s);
    }
    return s;
  }

  int _nextElement(int e) {
    var s = tree.nextSiblingOf(e);
    while (s >= 0 && !_isElement(s)) {
      s = tree.nextSiblingOf(s);
    }
    return s;
  }

  String _lowerName(int nameId) =>
      _lowerNames[nameId] ??= asciiLower(tree.names.localNameOf(nameId));

  /// Id do namespace exigido por [c]; −1 se nenhum nó pode tê-lo.
  int _namespaceId(String uri) {
    if (uri.isEmpty) return Namespaces.none;
    return _namespaceIds.putIfAbsent(
      uri,
      () => tree.names.namespaceIdOf(uri) ?? -1,
    );
  }

  bool _namespaceMatches(NamespaceConstraint c, int namespace) {
    final uri = c.uri;
    return uri == null || _namespaceId(uri) == namespace;
  }

  bool _matchesCompound(CompoundSelector compound, int e) {
    for (final s in compound.simples) {
      if (!_matchesSimple(s, e)) return false;
    }
    return true;
  }

  bool _matchesSimple(SimpleSelector s, int e) => switch (s) {
    TypeSelector() => _matchesType(s, e),
    IdSelector(:final id) => tree.idOf(e) == id,
    ClassSelector(:final name) => _hasClass(e, name),
    AttributeSelector() => _matchesAttribute(s, e),
    PseudoClassSelector() => _matchesPseudoClass(s, e),
    NotSelector(:final argument) => !_matchesSimple(argument, e),
  };

  bool _matchesType(TypeSelector s, int e) {
    final nameId = tree.nameOf(e);
    final namespace = tree.names.namespaceOf(nameId);
    if (!_namespaceMatches(s.namespace, namespace)) return false;
    final name = s.localName;
    if (name == null) return true;
    // Ruling F4: XHTML casa pelo nome em minúsculas; os demais, exato.
    if (namespace == Namespaces.xhtml) return _lowerName(nameId) == s.lowerName;
    return tree.names.localNameOf(nameId) == name;
  }

  bool _hasClass(int e, String name) {
    final token = tree.tokens.lookup(name);
    if (token == null) return false;
    for (final c in tree.classesOf(e)) {
      if (c == token) return true;
    }
    return false;
  }

  bool _matchesAttribute(AttributeSelector s, int e) {
    final html = tree.namespaceOf(e) == Namespaces.xhtml;
    final names = tree.names;
    for (final attribute in tree.attributesOf(e)) {
      final nameId = attribute.name;
      if (!_namespaceMatches(s.namespace, names.namespaceOf(nameId))) {
        continue;
      }
      final matchesName = html
          ? _lowerName(nameId) == s.lowerName
          : names.localNameOf(nameId) == s.localName;
      if (matchesName && _matchesValue(s, attribute.value)) return true;
    }
    return false;
  }

  static bool _matchesValue(AttributeSelector s, String actual) {
    var expected = s.value;
    if (s.operator == AttributeOperator.exists) return true;
    if (s.caseInsensitive) {
      actual = asciiLower(actual);
      expected = asciiLower(expected);
    }
    switch (s.operator) {
      case AttributeOperator.exists:
        return true;
      case AttributeOperator.equals:
        return actual == expected;
      case AttributeOperator.includes:
        if (expected.isEmpty || _hasWhitespace(expected)) return false;
        for (final word in actual.split(_whitespace)) {
          if (word == expected) return true;
        }
        return false;
      case AttributeOperator.dashMatch:
        return actual == expected ||
            (actual.length > expected.length &&
                actual.startsWith(expected) &&
                actual.codeUnitAt(expected.length) == 0x2D);
      case AttributeOperator.prefix:
        return expected.isNotEmpty && actual.startsWith(expected);
      case AttributeOperator.suffix:
        return expected.isNotEmpty && actual.endsWith(expected);
      case AttributeOperator.substring:
        return expected.isNotEmpty && actual.contains(expected);
    }
  }

  static final RegExp _whitespace = RegExp('[ \t\n\r\f]+');

  static bool _hasWhitespace(String s) => _whitespace.hasMatch(s);

  bool _matchesPseudoClass(PseudoClassSelector s, int e) {
    switch (s.kind) {
      case PseudoClassKind.root:
        return tree.parentOf(e) == tree.documentNode;
      case PseudoClassKind.nthChild:
        return _nth(s.a, s.b, _index(e, fromEnd: false, ofType: false));
      case PseudoClassKind.nthLastChild:
        return _nth(s.a, s.b, _index(e, fromEnd: true, ofType: false));
      case PseudoClassKind.nthOfType:
        return _nth(s.a, s.b, _index(e, fromEnd: false, ofType: true));
      case PseudoClassKind.nthLastOfType:
        return _nth(s.a, s.b, _index(e, fromEnd: true, ofType: true));
      case PseudoClassKind.onlyChild:
        return _previousElement(e) < 0 && _nextElement(e) < 0;
      case PseudoClassKind.onlyOfType:
        return _index(e, fromEnd: false, ofType: true) == 1 &&
            _index(e, fromEnd: true, ofType: true) == 1;
      case PseudoClassKind.empty:
        // Só elementos e texto entram na árvore; qualquer texto é conteúdo.
        return tree.firstChildOf(e) < 0;
      case PseudoClassKind.lang:
        return _matchesLang(s.lang!, e);
      case PseudoClassKind.link:
        final nameId = tree.nameOf(e);
        if (tree.names.namespaceOf(nameId) != Namespaces.xhtml) return false;
        final name = _lowerName(nameId);
        if (name != 'a' && name != 'area') return false;
        final href = _hrefId;
        return href != null && tree.attributeById(e, href) != null;
      case PseudoClassKind.never:
        return false;
    }
  }

  static bool _nth(int a, int b, int index) {
    if (a == 0) return index == b;
    final d = index - b;
    return d % a == 0 && d ~/ a >= 0;
  }

  /// Posição (1-based) de [e] entre os irmãos elementos (do mesmo nome, se
  /// [ofType]), contando do início ou do fim. Preenche o cache de todos os
  /// irmãos percorridos, então o custo total por lista de irmãos é linear.
  int _index(int e, {required bool fromEnd, required bool ofType}) {
    final Int32List cache;
    if (ofType) {
      cache = fromEnd
          ? (_typeIndexFromEnd ??= Int32List(tree.nodeCount))
          : (_typeIndex ??= Int32List(tree.nodeCount));
    } else {
      cache = fromEnd
          ? (_childIndexFromEnd ??= Int32List(tree.nodeCount))
          : (_childIndex ??= Int32List(tree.nodeCount));
    }
    final known = cache[e];
    if (known != 0) return known;
    final name = ofType ? tree.nameOf(e) : -1;
    // Irmãos sem posição conhecida, de [e] até o início (ou o fim).
    final pending = <int>[e];
    var base = 0;
    var s = fromEnd ? _nextElement(e) : _previousElement(e);
    while (s >= 0) {
      if (!ofType || tree.nameOf(s) == name) {
        final c = cache[s];
        if (c != 0) {
          base = c;
          break;
        }
        pending.add(s);
      }
      s = fromEnd ? _nextElement(s) : _previousElement(s);
    }
    final n = pending.length;
    for (var k = 0; k < n; k++) {
      cache[pending[k]] = base + n - k;
    }
    return cache[e];
  }

  bool _matchesLang(String range, int e) {
    String? lang;
    for (var n = e; n >= 0 && _isElement(n); n = tree.parentOf(n)) {
      final xmlLang = _xmlLangId;
      final htmlLang = _langId;
      lang =
          (xmlLang == null ? null : tree.attributeById(n, xmlLang)) ??
          (htmlLang == null ? null : tree.attributeById(n, htmlLang));
      if (lang != null) break;
    }
    lang = lang == null ? _documentLang : asciiLower(lang);
    if (lang == null || lang.isEmpty) return false;
    return lang == range ||
        (lang.length > range.length &&
            lang.startsWith(range) &&
            lang.codeUnitAt(range.length) == 0x2D);
  }
}
