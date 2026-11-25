import 'dart:typed_data';

import 'document_tree.dart';
import 'names.dart';

/// Monta uma [DocumentTree] de forma incremental, em ordem de documento.
///
/// Não faz reparo: quem chama (o montador) garante uma sequência bem
/// formada de [startElement]/[endElement]. Chamadas fora de ordem são erro
/// de programação e lançam `StateError`. Nenhuma operação é recursiva.
final class TreeBuilder {
  /// Cria um montador com o nó do documento já aberto.
  TreeBuilder() {
    _addNode(NodeKind.document.index, -1, 0, 0);
    _open.add(0);
    _lastChild.add(-1);
  }

  /// Nomes internados do documento em montagem.
  final NameTable names = NameTable();

  /// Tokens internados do documento em montagem.
  final TokenTable tokens = TokenTable();

  final _Uint8Array _flags = _Uint8Array();
  final _Int32Array _parents = _Int32Array();
  final _Int32Array _firstChildren = _Int32Array();
  final _Int32Array _nextSiblings = _Int32Array();
  final _Int32Array _previousSiblings = _Int32Array();
  final _Int32Array _data0 = _Int32Array();
  final _Int32Array _data1 = _Int32Array();
  final _Int32Array _attributeEnds = _Int32Array();
  final StringBuffer _text = StringBuffer();
  final _Int32Array _attributeNames = _Int32Array();
  final List<String> _attributeValues = [];

  /// Valores de atributo já vistos, para que repetições compartilhem a
  /// mesma `String`. Descartado no [build].
  final Map<String, String> _distinctValues = {};
  int _distinctValueChars = 0;

  /// Pilha dos nós abertos (o documento na base) e, em paralelo, o último
  /// filho de cada um (−1 se ainda não tem filhos).
  final _Int32Array _open = _Int32Array();
  final _Int32Array _lastChild = _Int32Array();

  bool _built = false;

  /// Quantidade de elementos abertos.
  int get depth => _open.length - 1;

  /// Id do nome do elemento aberto mais interno; −1 se nenhum estiver
  /// aberto.
  int get openElementName => depth == 0 ? -1 : _data0[_open.last];

  /// Abre um elemento com o nome [nameId] como último filho do elemento
  /// aberto. [virtual] marca um nó criado pela recuperação.
  void startElement(int nameId, {bool virtual = false}) {
    _checkNotBuilt();
    final flags =
        NodeKind.element.index | (virtual ? DocumentTree.virtualFlag : 0);
    final attributeStart = _attributeNames.length;
    final n = _appendChild(flags, nameId, attributeStart);
    _attributeEnds[n] = attributeStart;
    _open.add(n);
    _lastChild.add(-1);
  }

  /// Acrescenta o atributo [nameId] = [value] ao elemento aberto.
  ///
  /// Só é válido antes do primeiro filho do elemento.
  void attribute(int nameId, String value) {
    _checkNotBuilt();
    if (depth == 0 || _lastChild.last != -1) {
      throw StateError('atributo fora de um elemento recém-aberto');
    }
    var shared = _distinctValues[value];
    if (shared == null) {
      _distinctValues[value] = shared = value;
      _distinctValueChars += value.length;
    }
    _attributeNames.add(nameId);
    _attributeValues.add(shared);
    _attributeEnds[_open.last] = _attributeNames.length;
  }

  /// Acrescenta [data] como texto no elemento aberto, fundindo com o nó de
  /// texto imediatamente anterior, se houver. Texto vazio é ignorado.
  void text(String data) {
    _checkNotBuilt();
    if (data.isEmpty) return;
    final last = _lastChild.last;
    final start = _text.length;
    _text.write(data);
    if (last != -1 &&
        _flags[last] & DocumentTree.kindMask == NodeKind.text.index) {
      // O nó anterior termina no fim do buffer: nada foi escrito depois
      // dele, então basta estender a faixa.
      _data1[last] = _text.length;
      return;
    }
    _appendChild(NodeKind.text.index, start, _text.length);
  }

  /// Fecha o elemento aberto mais interno.
  void endElement() {
    _checkNotBuilt();
    if (depth == 0) throw StateError('nenhum elemento aberto');
    _open.removeLast();
    _lastChild.removeLast();
  }

  /// Congela e devolve a árvore. O montador não pode mais ser usado: as
  /// tabelas [names] e [tokens] passam a recusar novos itens, e os buffers
  /// crescentes da montagem são soltos.
  ///
  /// Lança `StateError` se houver elemento aberto: fechá-los é
  /// responsabilidade do montador.
  DocumentTree build() {
    _checkNotBuilt();
    if (depth > 0) {
      throw StateError('build() com $depth elemento(s) aberto(s)');
    }
    _built = true;
    final indices = _buildIndices();
    final tree = DocumentTree.internal(
      flags: _flags.trimmed(),
      parents: _parents.trimmed(),
      firstChildren: _firstChildren.trimmed(),
      nextSiblings: _nextSiblings.trimmed(),
      previousSiblings: _previousSiblings.trimmed(),
      data0: _data0.trimmed(),
      data1: _data1.trimmed(),
      attributeEnds: _attributeEnds.trimmed(),
      text: _text.toString(),
      attributeNames: _attributeNames.trimmed(),
      attributeValues: List<String>.of(_attributeValues, growable: false),
      distinctValueCount: _distinctValues.length,
      distinctValueChars: _distinctValueChars,
      indices: indices,
      names: names..freeze(),
      tokens: tokens..freeze(),
    );
    for (final array in [
      _parents,
      _firstChildren,
      _nextSiblings,
      _previousSiblings,
      _data0,
      _data1,
      _attributeEnds,
      _attributeNames,
      _open,
      _lastChild,
    ]) {
      array.release();
    }
    _flags.release();
    _text.clear();
    _distinctValues.clear();
    _attributeValues.clear();
    return tree;
  }

  /// Monta os índices de consulta em O(n), antes de congelar [tokens]: um
  /// passe conta e outro preenche, sempre em ordem de documento.
  QueryIndices _buildIndices() {
    final count = _flags.length;
    final idName = names.lookup(Namespaces.none, 'id') ?? -1;
    final classAttr = names.lookup(Namespaces.none, 'class') ?? -1;
    final typeAttr = names.lookup(Namespaces.ops, 'type') ?? -1;

    final byId = <String, int>{};
    final classStarts = Int32List(count + 1);
    final typeStarts = Int32List(count + 1);
    final classValues = _Int32Array();
    final typeValues = _Int32Array();
    final nameCounts = Int32List(names.length + 1);
    final elements = _Int32Array();

    for (var n = 0; n < count; n++) {
      classStarts[n] = classValues.length;
      typeStarts[n] = typeValues.length;
      if (_flags[n] & DocumentTree.kindMask != NodeKind.element.index) {
        continue;
      }
      elements.add(n);
      nameCounts[_data0[n]]++;
      var seenId = false;
      var seenClass = false;
      var seenType = false;
      final end = _attributeEnds[n];
      for (var i = _data1[n]; i < end; i++) {
        final name = _attributeNames[i];
        if (name == idName && !seenId) {
          seenId = true;
          final value = _attributeValues[i];
          if (value.isNotEmpty) byId.putIfAbsent(value, () => n);
        } else if (name == classAttr && !seenClass) {
          seenClass = true;
          _tokenize(_attributeValues[i], classValues, classStarts[n]);
        } else if (name == typeAttr && !seenType) {
          seenType = true;
          _tokenize(_attributeValues[i], typeValues, typeStarts[n]);
        }
      }
    }
    classStarts[count] = classValues.length;
    typeStarts[count] = typeValues.length;
    final classTokens = classValues.trimmed();

    // Por nome: contagem, somas de prefixo e preenchimento (ordem estável).
    final nameStarts = _prefixSums(nameCounts);
    final nameFill = Int32List.fromList(nameStarts);
    final nameElements = Int32List(nameStarts[names.length]);
    for (var k = 0; k < elements.length; k++) {
      final e = elements[k];
      nameElements[nameFill[_data0[e]]++] = e;
    }

    // Por classe: o mesmo, sobre os tokens de classe de cada elemento.
    final classCounts = Int32List(tokens.length + 1);
    for (final token in classTokens) {
      classCounts[token]++;
    }
    final classElementStarts = _prefixSums(classCounts);
    final classFill = Int32List.fromList(classElementStarts);
    final classElements = Int32List(classElementStarts[tokens.length]);
    for (var k = 0; k < elements.length; k++) {
      final e = elements[k];
      for (var i = classStarts[e]; i < classStarts[e + 1]; i++) {
        classElements[classFill[classTokens[i]]++] = e;
      }
    }

    return QueryIndices(
      idName: idName,
      byId: byId,
      classStarts: classStarts,
      classTokens: classTokens,
      typeStarts: typeStarts,
      typeTokens: typeValues.trimmed(),
      classElementStarts: classElementStarts,
      classElements: classElements,
      nameElementStarts: nameStarts,
      nameElements: nameElements,
    );
  }

  /// Soma de prefixos de [counts] (com um item a mais que o necessário nas
  /// chaves): `result[k]` é o início do grupo `k`; o último, o total.
  static Int32List _prefixSums(Int32List counts) {
    final keys = counts.length - 1;
    final starts = Int32List(keys + 1);
    for (var k = 0; k < keys; k++) {
      starts[k + 1] = starts[k] + counts[k];
    }
    return starts;
  }

  /// Separa [value] em tokens por espaço em branco ASCII, interna cada um e
  /// acrescenta a [out] os que ainda não aparecem a partir de [from].
  void _tokenize(String value, _Int32Array out, int from) {
    final length = value.length;
    var i = 0;
    while (i < length) {
      while (i < length && _isSpace(value.codeUnitAt(i))) {
        i++;
      }
      final start = i;
      while (i < length && !_isSpace(value.codeUnitAt(i))) {
        i++;
      }
      if (i == start) break;
      final token = tokens.intern(value.substring(start, i));
      var seen = false;
      for (var k = from; k < out.length; k++) {
        if (out[k] == token) {
          seen = true;
          break;
        }
      }
      if (!seen) out.add(token);
    }
  }

  static bool _isSpace(int c) =>
      c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x0C;

  /// Cria um nó como último filho do elemento aberto e devolve o índice.
  int _appendChild(int flags, int data0, int data1) {
    final parent = _open.last;
    final previous = _lastChild.last;
    final n = _addNode(flags, parent, data0, data1);
    if (previous == -1) {
      _firstChildren[parent] = n;
    } else {
      _nextSiblings[previous] = n;
      _previousSiblings[n] = previous;
    }
    _lastChild[_lastChild.length - 1] = n;
    return n;
  }

  int _addNode(int flags, int parent, int data0, int data1) {
    final n = _flags.length;
    _flags.add(flags);
    _parents.add(parent);
    _firstChildren.add(-1);
    _nextSiblings.add(-1);
    _previousSiblings.add(-1);
    _data0.add(data0);
    _data1.add(data1);
    _attributeEnds.add(data1);
    return n;
  }

  void _checkNotBuilt() {
    if (_built) throw StateError('TreeBuilder já usado em build()');
  }
}

/// `Int32List` que dobra de capacidade ao crescer.
final class _Int32Array {
  Int32List _data = Int32List(64);
  int length = 0;

  int operator [](int i) => _data[i];

  void operator []=(int i, int value) => _data[i] = value;

  int get last => _data[length - 1];

  void add(int value) {
    if (length == _data.length) {
      _data = Int32List(length * 2)..setRange(0, length, _data);
    }
    _data[length++] = value;
  }

  void removeLast() => length--;

  /// Solta o armazenamento.
  void release() {
    _data = Int32List(0);
    length = 0;
  }

  /// Cópia com exatamente [length] elementos.
  Int32List trimmed() =>
      Int32List.fromList(Int32List.sublistView(_data, 0, length));
}

/// `Uint8List` que dobra de capacidade ao crescer.
final class _Uint8Array {
  Uint8List _data = Uint8List(64);
  int length = 0;

  int operator [](int i) => _data[i];

  void add(int value) {
    if (length == _data.length) {
      _data = Uint8List(length * 2)..setRange(0, length, _data);
    }
    _data[length++] = value;
  }

  /// Solta o armazenamento.
  void release() {
    _data = Uint8List(0);
    length = 0;
  }

  /// Cópia com exatamente [length] elementos.
  Uint8List trimmed() =>
      Uint8List.fromList(Uint8List.sublistView(_data, 0, length));
}
