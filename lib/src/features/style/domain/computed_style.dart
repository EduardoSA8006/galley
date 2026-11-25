import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'css_value.dart';
import 'properties.dart';

/// Estilo calculado de um elemento (ou pseudo-elemento): o valor calculado
/// de cada uma das [kPropertyCount] propriedades (spec §8.5, §8.6).
///
/// Imutável e internado ([StyleInterner]): igualdade por valor e
/// [stableHash] igual entre isolates e entre execuções, para o cache de
/// medição do layout usar o valor do estilo e não o índice.
@immutable
final class ComputedStyle {
  /// Cria o estilo a partir de [values] (um valor por `PropertyId`).
  ComputedStyle(List<CssValue> values)
    : assert(values.length == kPropertyCount, 'um valor por propriedade'),
      _values = List.unmodifiable(values),
      stableHash = _hashValues(values);

  final List<CssValue> _values;

  /// Valor calculado da propriedade [property] (um id de `PropertyId`).
  CssValue operator [](int property) => _values[property];

  /// Os valores, por id de `PropertyId` (lista imutável).
  List<CssValue> get values => _values;

  /// FNV-1a de 32 bits sobre a codificação canônica dos valores
  /// ([StableHasher]); não depende de `Object.hash` nem de
  /// `String.hashCode`, que mudam entre isolates e execuções.
  final int stableHash;

  @override
  int get hashCode => stableHash;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ComputedStyle &&
        other.stableHash == stableHash &&
        listEquals(other._values, _values);
  }

  /// Bytes retidos pelo estilo em si (cabeçalho e referências; os valores
  /// costumam ser compartilhados).
  int get retainedBytes => 48 + _values.length * 8;

  @override
  String toString() => 'ComputedStyle(#$stableHash)';

  static int _hashValues(List<CssValue> values) {
    final h = StableHasher();
    for (final v in values) {
      h.addValue(v);
    }
    return h.value;
  }
}

/// Tabela de estilos distintos de um documento: estilos iguais por valor
/// viram o mesmo objeto (e o mesmo índice em [styles]).
final class StyleInterner {
  final Map<ComputedStyle, int> _indices = {};
  final List<ComputedStyle> _styles = [];

  /// Estilos distintos, na ordem em que apareceram.
  List<ComputedStyle> get styles => _styles;

  /// O estilo internado igual a [values].
  ComputedStyle intern(List<CssValue> values) => _styles[indexOf(values)];

  /// Índice em [styles] do estilo igual a [values] (criado se novo).
  int indexOf(List<CssValue> values) {
    final style = ComputedStyle(values);
    final known = _indices[style];
    if (known != null) return known;
    _styles.add(style);
    return _indices[style] = _styles.length - 1;
  }
}

/// Hash FNV-1a de 32 bits sobre uma codificação canônica de [CssValue]:
/// marca do tipo, inteiros em 64 bits, números como os bits IEEE de 64 bits
/// (com `-0.0` normalizado para `0.0`, coerente com `==`) e textos pelo
/// tamanho e pelas unidades de código UTF-16. Determinístico entre isolates,
/// plataformas e execuções.
final class StableHasher {
  static const int _offsetBasis = 0x811C9DC5;
  static const int _prime = 0x01000193;

  int _h = _offsetBasis;
  final ByteData _scratch = ByteData(8);

  /// O hash acumulado (32 bits, sem sinal).
  int get value => _h;

  /// Acrescenta um byte.
  void addByte(int b) {
    _h = ((_h ^ (b & 0xFF)) * _prime) & 0xFFFFFFFF;
  }

  /// Acrescenta um inteiro de 32 bits (os 32 bits baixos de [v]).
  void addInt32(int v) {
    addByte(v);
    addByte(v >> 8);
    addByte(v >> 16);
    addByte(v >> 24);
  }

  /// Acrescenta um inteiro de 64 bits.
  void addInt64(int v) {
    addInt32(v);
    addInt32(v >> 32);
  }

  /// Acrescenta um número pelos seus bits IEEE de 64 bits.
  void addDouble(double v) {
    _scratch.setFloat64(0, v == 0 ? 0.0 : v, Endian.little);
    for (var i = 0; i < 8; i++) {
      addByte(_scratch.getUint8(i));
    }
  }

  /// Acrescenta um texto: tamanho e unidades de código.
  void addString(String s) {
    addInt32(s.length);
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      addByte(c);
      addByte(c >> 8);
    }
  }

  /// Acrescenta um valor de CSS.
  void addValue(CssValue v) {
    switch (v) {
      case CssKeyword(:final id):
        addByte(1);
        addInt32(id);
      case CssLengthSpec():
        addByte(2);
        addDouble(v.px);
        addDouble(v.em);
        addDouble(v.ex);
        addDouble(v.rem);
        addDouble(v.percent);
        addDouble(v.vw);
        addDouble(v.vh);
      case CssLength():
        addByte(3);
        addDouble(v.px);
        addDouble(v.percent);
        addDouble(v.vw);
        addDouble(v.vh);
      case CssNumber(:final value):
        addByte(4);
        addDouble(value);
      case CssColor(:final argb):
        addByte(5);
        addInt64(argb);
      case CssFontFamilies(:final families):
        addByte(6);
        addInt32(families.length);
        for (final f in families) {
          addByte(f.generic ? 1 : 0);
          addString(f.name);
        }
      case CssString(:final value):
        addByte(7);
        addString(value);
      case CssUrl(:final path):
        addByte(8);
        addString(path);
      case CssContent(:final items):
        addByte(9);
        addInt32(items.length);
        for (final item in items) {
          _addContentItem(item);
        }
      case CssQuotes(:final pairs):
        addByte(10);
        addInt32(pairs.length);
        for (final (open, close) in pairs) {
          addString(open);
          addString(close);
        }
      case CssCounterChanges(:final changes):
        addByte(11);
        addInt32(changes.length);
        for (final (name, value) in changes) {
          addString(name);
          addInt64(value);
        }
      case CssList(:final items):
        addByte(12);
        addInt32(items.length);
        for (final item in items) {
          addValue(item);
        }
    }
  }

  void _addContentItem(ContentItem item) {
    switch (item) {
      case ContentText(:final text):
        addByte(1);
        addString(text);
      case ContentQuote(:final kind):
        addByte(2);
        addByte(kind.index);
      case ContentAttr(:final name):
        addByte(3);
        addString(name);
      case ContentCounter(:final name, :final style):
        addByte(4);
        addString(name);
        addInt32(style);
    }
  }
}
