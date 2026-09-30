/// Casamento de seletor contra elemento (spec do CSS §10.4): da direita para
/// a esquerda, com os estados do `SelectorChecker` do Blink, e o filtro de
/// Bloom dos ancestrais.
///
/// Cada passo é O(1): o seletor tem no máximo 32 compostos de 32 seletores
/// simples, com identificadores de até 256 unidades (hash e minúsculas
/// calculados no parse); o elemento tem hash e minúsculas calculados uma vez
/// em [ElementInfo]; classes num `Set`. `failsCompletely` impede o
/// retrocesso do descendente, e [MatchSteps] conta cada seletor simples
/// testado.
library;

import 'dart:typed_data';

import 'package:html/dom.dart';

import 'selector.dart';
import 'tokenizer.dart';

const String htmlNamespace = 'http://www.w3.org/1999/xhtml';

/// Um elemento visto pela cascata, montado só quando ele é visitado
/// ([ChildCursor]; spec do CSS §10.2).
final class ElementInfo {
  ElementInfo._(
    this.element, {
    required this.parent,
    required this.previous,
    required this.index,
    required this.siblingCount,
    required this.depth,
  }) : localName = element.localName ?? '',
       isHtml = element.namespaceUri == htmlNamespace {
    lowerName = cssAsciiLower(localName);
    nameHash = bloomHash(bloomKindTag, lowerName);
    final attributes = element.attributes;
    final id = attributes['id'];
    this.id = id;
    idHash = id == null ? null : bloomHash(bloomKindId, cssAsciiLower(id));
    final classAttribute = attributes['class'];
    classes = classAttribute == null ? const {} : _classTokens(classAttribute);
    classHashes = [
      for (final c in classes) bloomHash(bloomKindClass, cssAsciiLower(c)),
    ];
    readUnits =
        localName.length + (id?.length ?? 0) + (classAttribute?.length ?? 0);
    final p = parent;
    listDepth = p == null ? 0 : p.listDepth + (p.isList ? 1 : 0);
  }

  final Element element;

  /// Como está no DOM (o `package:html` já baixa os nomes HTML).
  final String localName;
  late final String lowerName;
  final bool isHtml;
  late final String? id;

  /// Tokens de `class` por espaço ASCII, sem repetição (`class="a a"` é
  /// `{a}`).
  late final Set<String> classes;
  final ElementInfo? parent;

  /// Irmão-elemento anterior (texto e comentário não contam).
  final ElementInfo? previous;

  /// Posição (base 1) entre os irmãos-elemento, e quantos são.
  final int index;
  final int siblingCount;

  /// A raiz tem 1.
  final int depth;

  late final int nameHash;
  late final int? idHash;
  late final List<int> classHashes;

  /// Unidades de código de nome, `id` e `class` lidas ao montar (§10.6).
  late final int readUnits;

  /// Passos de montar este elemento (doc/08 §3): um, mais um a cada 64
  /// unidades lidas.
  int get buildSteps => 1 + readUnits ~/ 64;

  bool get isTemplate => isHtml && localName == 'template';

  /// `dir`, `menu`, `ol` ou `ul` do HTML: as listas do HTML §15.3.8.
  bool get isList =>
      isHtml &&
      (lowerName == 'ul' ||
          lowerName == 'ol' ||
          lowerName == 'menu' ||
          lowerName == 'dir');

  /// Quantos ancestrais são listas ([isList]), herdado do pai em O(1): o
  /// `circle`/`square` das listas aninhadas sai daqui, sem descendente.
  late final int listDepth;
}

/// Os filhos-elemento de um pai, montados um a um em [next] (nunca
/// `children` indexado, doc/03 §8): o [ElementInfo] de um irmão só é
/// montado quando ele é visitado, e [next] soma em [steps] o custo de
/// montá-lo ([ElementInfo.buildSteps]) antes de devolvê-lo, para a cessão
/// vir antes do trabalho seguinte.
///
/// O total de irmãos (`:last-child`) sai de uma passada que só testa o tipo
/// de cada nó, sem ler nome, classe nem atributo: O(nós do pai), uma vez
/// por pai.
final class ChildCursor {
  /// Os filhos-elemento de [parent].
  ChildCursor(ElementInfo this.parent, this.steps)
    : _nodes = parent.element.nodes,
      _depth = parent.depth + 1,
      _count = _elementCount(parent.element.nodes);

  /// Só a raiz do documento (profundidade 1, `:first-child` e
  /// `:last-child`, como no Selectors 4, que não exige pai).
  ChildCursor.root(Element root, this.steps)
    : parent = null,
      _nodes = [root],
      _depth = 1,
      _count = 1;

  final ElementInfo? parent;
  final MatchSteps steps;
  final List<Node> _nodes;
  final int _depth;
  final int _count;
  int _position = 0;
  int _index = 0;
  ElementInfo? _previous;

  /// Quantos filhos-elemento o pai tem.
  int get count => _count;

  /// O próximo filho-elemento, montado agora, ou `null` no fim.
  ElementInfo? next() {
    while (_position < _nodes.length) {
      final node = _nodes[_position++];
      if (node is! Element) continue;
      final info = ElementInfo._(
        node,
        parent: parent,
        previous: _previous,
        index: ++_index,
        siblingCount: _count,
        depth: _depth,
      );
      _previous = info;
      steps.add(info.buildSteps);
      return info;
    }
    return null;
  }

  static int _elementCount(List<Node> nodes) {
    var n = 0;
    for (final node in nodes) {
      if (node is Element) n++;
    }
    return n;
  }
}

Set<String> _classTokens(String value) {
  final out = <String>{};
  var start = -1;
  for (var i = 0; i <= value.length; i++) {
    final c = i < value.length ? value.codeUnitAt(i) : 0x20;
    final space = c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0C || c == 0x0D;
    if (space) {
      if (start >= 0) out.add(value.substring(start, i));
      start = -1;
    } else if (start < 0) {
      start = i;
    }
  }
  return out;
}

/// Filtro de Bloom contador dos ancestrais (§10.4): duas posições de 12 bits
/// por hash; contador que chega a 255 fica preso (só gera falso positivo).
final class AncestorFilter {
  final Uint8List _counts = Uint8List(4096);

  void push(ElementInfo e) {
    _add(e.nameHash);
    final id = e.idHash;
    if (id != null) _add(id);
    for (final h in e.classHashes) {
      _add(h);
    }
  }

  void pop(ElementInfo e) {
    _remove(e.nameHash);
    final id = e.idHash;
    if (id != null) _remove(id);
    for (final h in e.classHashes) {
      _remove(h);
    }
  }

  /// `false` só se nenhum ancestral tem o identificador de [hash].
  bool mayContain(int hash) =>
      _counts[hash & 0xFFF] != 0 && _counts[(hash >> 12) & 0xFFF] != 0;

  void _add(int hash) {
    _inc(hash & 0xFFF);
    _inc((hash >> 12) & 0xFFF);
  }

  void _remove(int hash) {
    _dec(hash & 0xFFF);
    _dec((hash >> 12) & 0xFFF);
  }

  void _inc(int i) {
    final c = _counts[i];
    if (c < 255) _counts[i] = c + 1;
  }

  void _dec(int i) {
    final c = _counts[i];
    if (c != 0 && c < 255) _counts[i] = c - 1;
  }
}

/// Os dois contadores de §10.6: [total] (cessão) conta todo o trabalho;
/// [book] (orçamento) só o das regras do livro, enquanto [bookMode].
final class MatchSteps {
  MatchSteps(this.budget);

  final int budget;
  int total = 0;
  int book = 0;
  bool bookMode = false;

  bool get exhausted => book > budget;

  /// O casamento em curso é do livro e o orçamento acabou: para.
  bool get stopped => bookMode && book > budget;

  void add(int n) {
    total += n;
    if (bookMode) book += n;
  }
}

enum _Result { matches, failsLocally, failsAllSiblings, failsCompletely }

/// [selector] casa [e]? O chamador já conferiu os hashes de ancestral.
bool matchSelector(Selector selector, ElementInfo e, MatchSteps steps) =>
    _match(selector, selector.compounds.length - 1, e, steps) ==
    _Result.matches;

_Result _match(Selector s, int i, ElementInfo e, MatchSteps steps) {
  if (steps.stopped) return _Result.failsCompletely;
  if (!_compoundMatches(s.compounds[i], e, steps)) return _Result.failsLocally;
  if (i == 0) return _Result.matches;
  switch (s.combinators[i - 1]) {
    case CssCombinator.adjacent:
      final previous = e.previous;
      if (previous == null) return _Result.failsAllSiblings;
      return _match(s, i - 1, previous, steps);
    case CssCombinator.child:
      final parent = e.parent;
      if (parent == null) return _Result.failsCompletely;
      return _match(s, i - 1, parent, steps);
    case CssCombinator.descendant:
      for (var p = e.parent; p != null; p = p.parent) {
        final r = _match(s, i - 1, p, steps);
        if (r == _Result.matches || r == _Result.failsCompletely) return r;
      }
      return _Result.failsCompletely;
  }
}

/// Ordem: `id`, tipo, classes, atributos, pseudo-classes; cada seletor
/// simples testado custa um passo (um composto universal custa um).
bool _compoundMatches(CompoundSelector k, ElementInfo e, MatchSteps steps) {
  final tested = _testCompound(k, e);
  if (tested < 0) {
    steps.add(-tested);
    return false;
  }
  steps.add(tested == 0 ? 1 : tested);
  return true;
}

/// Quantos seletores simples de [k] foram testados: positivo se todos
/// casaram; negativo (o número com sinal trocado) se o último falhou.
int _testCompound(CompoundSelector k, ElementInfo e) {
  if (k.impossible) return -1;
  var tested = 0;
  final id = k.id;
  if (id != null) {
    tested++;
    if (e.id != id) return -tested;
  }
  final tag = k.tag;
  if (tag != null) {
    tested++;
    if (e.localName != (e.isHtml ? tag : k.tagAsWritten)) return -tested;
  }
  for (final c in k.classes) {
    tested++;
    if (!e.classes.contains(c)) return -tested;
  }
  for (final a in k.attributes) {
    tested++;
    final value = e.element.attributes[e.isHtml ? a.name : a.nameAsWritten];
    if (value != a.value) return -tested;
  }
  if (k.firstChild) {
    tested++;
    if (e.index != 1) return -tested;
  }
  if (k.lastChild) {
    tested++;
    if (e.index != e.siblingCount) return -tested;
  }
  final nth = k.nthChild;
  if (nth != null) {
    tested++;
    if (nth == 0 || e.index != nth) return -tested;
  }
  return tested;
}
