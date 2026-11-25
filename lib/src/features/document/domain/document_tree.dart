import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'names.dart';

/// Tipo de um nó da [DocumentTree].
enum NodeKind {
  /// O nó raiz, sempre o nó 0.
  document,

  /// Um elemento.
  element,

  /// Uma sequência contígua de texto (inclusive CDATA).
  text,
}

/// Árvore compacta de um documento XHTML/SVG, imutável depois de montada.
///
/// Os nós são índices `int` numa arena de arranjos tipados, em ordem de
/// documento (pré-ordem); o nó 0 é o [documentNode]. Ausência de nó é −1.
/// O texto de todos os nós de texto fica numa única `String`, e cada nó de
/// texto guarda a sua faixa nela.
///
/// Só contém arranjos tipados e strings, então pode ser enviada entre
/// isolates. Monte com `TreeBuilder`. Todas as operações são iterativas.
final class DocumentTree {
  /// Cria a árvore a partir dos arranjos já aparados pelo `TreeBuilder`.
  ///
  /// [data0] guarda o id do nome (elemento) ou o início do texto (texto);
  /// [data1], o início dos atributos (elemento) ou o fim do texto (texto);
  /// [attributeEnds], o fim dos atributos (elemento). [attributeValues]
  /// já vem com valores repetidos compartilhando a mesma `String`;
  /// [distinctValueChars] e [distinctValueCount] descrevem esses valores
  /// distintos para o [retainedBytes].
  @internal
  DocumentTree.internal({
    required this._flags,
    required this._parents,
    required this._firstChildren,
    required this._nextSiblings,
    required this._previousSiblings,
    required this._data0,
    required this._data1,
    required this._attributeEnds,
    required this._text,
    required this._attributeNames,
    required this._attributeValues,
    required this._distinctValueCount,
    required this._distinctValueChars,
    required this.names,
    required this.tokens,
  });

  /// Bits 0–1 de `_flags`: o índice do [NodeKind].
  static const int kindMask = 0x3;

  /// Bit 2 de `_flags`: nó criado pela recuperação (fora do CFI).
  static const int virtualFlag = 0x4;

  final Uint8List _flags;
  final Int32List _parents;
  final Int32List _firstChildren;
  final Int32List _nextSiblings;
  final Int32List _previousSiblings;
  final Int32List _data0;
  final Int32List _data1;
  final Int32List _attributeEnds;
  final String _text;
  final Int32List _attributeNames;
  final List<String> _attributeValues;
  final int _distinctValueCount;
  final int _distinctValueChars;

  /// Nomes internados (elementos e atributos) deste documento.
  final NameTable names;

  /// Tokens internados (`class`, `epub:type`) deste documento.
  final TokenTable tokens;

  // ---------------------------------------------------------------- estrutura

  /// O nó raiz; sempre 0.
  int get documentNode => 0;

  /// Quantidade de nós, contando o [documentNode].
  int get nodeCount => _flags.length;

  /// Tipo do nó [n].
  NodeKind kindOf(int n) => NodeKind.values[_flags[n] & kindMask];

  /// Pai do nó [n]; −1 para o [documentNode].
  int parentOf(int n) => _parents[n];

  /// Primeiro filho do nó [n]; −1 se não houver.
  int firstChildOf(int n) => _firstChildren[n];

  /// Próximo irmão do nó [n]; −1 se não houver.
  int nextSiblingOf(int n) => _nextSiblings[n];

  /// Irmão anterior do nó [n]; −1 se não houver.
  int previousSiblingOf(int n) => _previousSiblings[n];

  /// Filhos do nó [n], em ordem de documento.
  Iterable<int> childrenOf(int n) sync* {
    for (var c = _firstChildren[n]; c != -1; c = _nextSiblings[c]) {
      yield c;
    }
  }

  /// `true` se o nó [n] foi criado pela recuperação (por exemplo, um
  /// `<body>` sintético) e fica fora da contagem do CFI.
  bool isVirtual(int n) => _flags[n] & virtualFlag != 0;

  // ---------------------------------------------------------------- elementos

  /// Id do nome internado do [element] (ver [names]).
  int nameOf(int element) {
    _checkKind(element, NodeKind.element);
    return _data0[element];
  }

  /// Nome local do [element].
  String localNameOf(int element) => names.localNameOf(nameOf(element));

  /// Id do namespace do [element] (ver `Namespaces`).
  int namespaceOf(int element) => names.namespaceOf(nameOf(element));

  // -------------------------------------------------------------------- texto

  /// Texto do nó [textNode], como no original depois da decodificação de
  /// entidades.
  String textOf(int textNode) {
    _checkKind(textNode, NodeKind.text);
    return _text.substring(_data0[textNode], _data1[textNode]);
  }

  // ---------------------------------------------------------------- atributos

  /// Quantidade de atributos do [element].
  int attributeCountOf(int element) {
    _checkKind(element, NodeKind.element);
    return _attributeEnds[element] - _data1[element];
  }

  /// Valor do atributo ([namespace], [localName]) do [element], ou `null`.
  ///
  /// Com atributos duplicados, vale o primeiro.
  String? attribute(int element, int namespace, String localName) {
    _checkKind(element, NodeKind.element);
    final name = names.lookup(namespace, localName);
    if (name == null) return null;
    final end = _attributeEnds[element];
    for (var i = _data1[element]; i < end; i++) {
      if (_attributeNames[i] == name) return _attributeValues[i];
    }
    return null;
  }

  /// Atributos do [element], na ordem do original.
  Iterable<({int name, String value})> attributesOf(int element) sync* {
    _checkKind(element, NodeKind.element);
    final end = _attributeEnds[element];
    for (var i = _data1[element]; i < end; i++) {
      yield (name: _attributeNames[i], value: _attributeValues[i]);
    }
  }

  // ------------------------------------------------------------------ memória

  /// Bytes retidos pela árvore: os arranjos tipados, o texto em UTF-16 e os
  /// valores de atributo (8 bytes por referência mais, por valor distinto,
  /// 16 bytes de cabeçalho e o conteúdo em UTF-16).
  int get retainedBytes =>
      _flags.lengthInBytes +
      _parents.lengthInBytes +
      _firstChildren.lengthInBytes +
      _nextSiblings.lengthInBytes +
      _previousSiblings.lengthInBytes +
      _data0.lengthInBytes +
      _data1.lengthInBytes +
      _attributeEnds.lengthInBytes +
      _text.length * 2 +
      _attributeNames.lengthInBytes +
      _attributeValues.length * 8 +
      _distinctValueCount * 16 +
      _distinctValueChars * 2;

  void _checkKind(int n, NodeKind kind) {
    if (_flags[n] & kindMask != kind.index) {
      throw ArgumentError.value(n, 'n', 'não é um nó do tipo ${kind.name}');
    }
  }
}
