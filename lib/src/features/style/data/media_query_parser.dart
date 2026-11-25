import 'dart:typed_data';

import '../domain/css_value.dart' show asciiLower;
import '../domain/style_environment.dart';
import 'css_blocks.dart';
import 'css_tokenizer.dart';

/// Lê a lista de media queries de [text] (atributo `media`).
MediaQueryList parseMediaQueryText(String text) =>
    parseMediaQueryList(tokenizeCss(preprocessCss(text)));

/// Lê a lista de media queries nos [tokens] (prelúdio de `@media`, resto
/// de `@import`), pelo Media Queries 4.
///
/// Sem diferença de caixa ASCII. Cada consulta malformada vira `not all`
/// (falsa) sem afetar as demais; recurso desconhecido ou valor inválido é
/// "desconhecido" (falso no fim). Parênteses além de [kMaxConditionDepth]
/// níveis tornam a consulta falsa. Linear no tamanho da entrada, com
/// recursão limitada a essa profundidade.
MediaQueryList parseMediaQueryList(List<CssToken> tokens) {
  final parser = _MediaParser(tokens);
  if (parser.skipWs(0, tokens.length) >= tokens.length) {
    return MediaQueryList.all;
  }
  final queries = <MediaQuery>[];
  var start = 0;
  var i = 0;
  while (true) {
    if (i >= tokens.length || tokens[i].type == CssTokenType.comma) {
      queries.add(parser.query(start, i));
      if (i >= tokens.length) break;
      start = ++i;
      continue;
    }
    final m = parser.match[i];
    i = m < 0 ? i + 1 : (m < tokens.length ? m + 1 : tokens.length);
  }
  return MediaQueryList(List.unmodifiable(queries));
}

/// Consulta malformada.
final class _Malformed implements Exception {
  const _Malformed();
}

/// Parênteses além do limite.
final class _TooDeep implements Exception {
  const _TooDeep();
}

const _malformed = _Malformed();

/// `em` e `rem` das consultas, em px.
const double _emPx = 16;

/// Palavras que não podem ser tipo de mídia.
const Set<String> _reservedTypes = {'not', 'and', 'or', 'only', 'layer'};

/// Tipos de mídia que casam; os demais (`print`, `amzn-kf8`...) não.
const Set<String> _matchingTypes = {'all', 'screen'};

/// Recursos de intervalo (aceitam `min-`/`max-` e a sintaxe de intervalo).
const Set<String> _rangeFeatures = {'width', 'height', 'aspect-ratio'};

final class _MediaParser {
  _MediaParser(this.t) : match = matchCssBlocks(t);

  final List<CssToken> t;
  final Int32List match;

  int skipWs(int i, int to) {
    while (i < to && t[i].type == CssTokenType.whitespace) {
      i++;
    }
    return i;
  }

  /// Fechamento do bloco aberto em [i] (ou [to], se não fechar antes).
  int _blockEnd(int i, int to) {
    final m = match[i];
    return m < to ? m : to;
  }

  /// Primeiro token depois do bloco aberto em [i], limitado a [to].
  int _after(int i, int to) {
    final m = match[i];
    return m < to ? m + 1 : to;
  }

  String? _ident(int i, int to) =>
      i < to && t[i].type == CssTokenType.ident ? asciiLower(t[i].value) : null;

  MediaQuery query(int from, int to) {
    try {
      return _query(from, to);
    } on _Malformed {
      return MediaQuery.never;
    } on _TooDeep {
      return MediaQuery.never;
    }
  }

  MediaQuery _query(int from, int to) {
    final i = skipWs(from, to);
    if (i >= to) throw _malformed;
    // Forma com tipo: `[not|only]? tipo [and condição]?`.
    var typeAt = -1;
    var negated = false;
    final first = _ident(i, to);
    if (first == 'not' || first == 'only') {
      final k = skipWs(i + 1, to);
      if (_ident(k, to) != null) {
        typeAt = k;
        negated = first == 'not';
      } else if (first == 'only') {
        throw _malformed;
      }
      // `not (...)` é a forma de condição.
    } else if (first != null) {
      typeAt = i;
    }
    if (typeAt >= 0) {
      final type = _ident(typeAt, to)!;
      if (_reservedTypes.contains(type)) throw _malformed;
      final typeMatches = _matchingTypes.contains(type);
      var k = skipWs(typeAt + 1, to);
      if (k >= to) {
        return MediaQuery(negated: negated, typeMatches: typeMatches);
      }
      if (_ident(k, to) != 'and') throw _malformed;
      k = skipWs(k + 1, to);
      final (condition, end) = _condition(k, to, allowOr: false, depth: 0);
      if (skipWs(end, to) < to) throw _malformed;
      return MediaQuery(
        negated: negated,
        typeMatches: typeMatches,
        condition: condition,
      );
    }
    final (condition, end) = _condition(i, to, allowOr: true, depth: 0);
    if (skipWs(end, to) < to) throw _malformed;
    return MediaQuery(condition: condition);
  }

  /// `<media-condition>` (ou sem `or`) a partir de [i]; devolve a condição e
  /// onde parou.
  (MediaCondition, int) _condition(
    int i,
    int to, {
    required bool allowOr,
    required int depth,
  }) {
    i = skipWs(i, to);
    if (_ident(i, to) == 'not') {
      final (c, end) = _inParens(skipWs(i + 1, to), to, depth);
      return (MediaNot(c), end);
    }
    final (first, firstEnd) = _inParens(i, to, depth);
    final operands = [first];
    String? kind;
    var end = firstEnd;
    while (true) {
      final j = skipWs(end, to);
      final word = _ident(j, to);
      if (word != 'and' && !(word == 'or' && allowOr)) break;
      if (kind != null && kind != word) throw _malformed;
      kind = word;
      final (c, e) = _inParens(skipWs(j + 1, to), to, depth);
      operands.add(c);
      end = e;
    }
    if (kind == null) return (first, end);
    return (
      kind == 'and'
          ? MediaAnd(List.unmodifiable(operands))
          : MediaOr(List.unmodifiable(operands)),
      end,
    );
  }

  /// `<media-in-parens>` em [i].
  (MediaCondition, int) _inParens(int i, int to, int depth) {
    if (i >= to) throw _malformed;
    final type = t[i].type;
    if (type == CssTokenType.function) {
      // `<general-enclosed>`.
      return (MediaConstant.unknown, _after(i, to));
    }
    if (type != CssTokenType.leftParen) throw _malformed;
    if (depth + 1 > kMaxConditionDepth) throw const _TooDeep();
    final close = _blockEnd(i, to);
    final next = _after(i, to);
    final from = skipWs(i + 1, close);
    final firstType = from < close ? t[from].type : null;
    if (firstType == CssTokenType.leftParen ||
        firstType == CssTokenType.function ||
        _ident(from, close) == 'not') {
      try {
        final (c, end) = _condition(
          from,
          close,
          allowOr: true,
          depth: depth + 1,
        );
        if (skipWs(end, close) == close) return (c, next);
      } on _Malformed {
        // Cai no `<general-enclosed>`.
      }
      return (MediaConstant.unknown, next);
    }
    return (_feature(from, close), next);
  }

  /// `<media-feature>` nos tokens `[from, to)`; desconhecido se não for.
  MediaCondition _feature(int from, int to) {
    final items = <CssToken>[];
    for (var i = from; i < to; i++) {
      final token = t[i];
      if (token.type == CssTokenType.whitespace) continue;
      if (items.length == 9) return MediaConstant.unknown;
      // Blocos não fazem parte de recurso algum.
      if (match[i] >= 0) return MediaConstant.unknown;
      items.add(token);
    }
    if (items.isEmpty) return MediaConstant.unknown;
    if (items.length == 1) {
      final name = _identOf(items.single);
      return name == null ? MediaConstant.unknown : _boolean(name);
    }
    final name = _identOf(items[0]);
    if (name != null && items[1].type == CssTokenType.colon) {
      return _plain(name, items.sublist(2));
    }
    return _range(items);
  }

  static String? _identOf(CssToken token) =>
      token.type == CssTokenType.ident ? asciiLower(token.value) : null;

  MediaCondition _boolean(String name) => switch (name) {
    'width' => const MediaSizeTest(height: false, comparison: null),
    'height' => const MediaSizeTest(height: true, comparison: null),
    'aspect-ratio' => const MediaAspectRatioTest(comparison: null),
    'orientation' => const MediaOrientationTest(null),
    'prefers-color-scheme' => const MediaColorSchemeTest(null),
    _ => MediaConstant.unknown,
  };

  MediaCondition _plain(String name, List<CssToken> value) {
    var feature = name;
    var comparison = MediaComparison.equal;
    if (name.startsWith('min-') || name.startsWith('max-')) {
      feature = name.substring(4);
      if (!_rangeFeatures.contains(feature)) return MediaConstant.unknown;
      comparison = name.startsWith('min-')
          ? MediaComparison.greaterOrEqual
          : MediaComparison.lessOrEqual;
    }
    switch (feature) {
      case 'width' || 'height' || 'aspect-ratio':
        return _rangeTest(feature, comparison, value) ?? MediaConstant.unknown;
      case 'orientation':
        if (value.length != 1) return MediaConstant.unknown;
        return switch (_identOf(value.single)) {
          'portrait' => const MediaOrientationTest(true),
          'landscape' => const MediaOrientationTest(false),
          _ => MediaConstant.unknown,
        };
      case 'prefers-color-scheme':
        if (value.length != 1) return MediaConstant.unknown;
        return switch (_identOf(value.single)) {
          'light' => const MediaColorSchemeTest(ColorScheme.light),
          'dark' => const MediaColorSchemeTest(ColorScheme.dark),
          _ => MediaConstant.unknown,
        };
    }
    return MediaConstant.unknown;
  }

  /// Teste de `feature <comparison> value`, ou `null` se o valor for
  /// inválido para o recurso.
  MediaCondition? _rangeTest(
    String feature,
    MediaComparison comparison,
    List<CssToken> value,
  ) {
    if (feature == 'aspect-ratio') {
      final ratio = _ratio(value);
      if (ratio == null) return null;
      return MediaAspectRatioTest(
        comparison: comparison,
        numerator: ratio.$1,
        denominator: ratio.$2,
      );
    }
    if (value.length != 1) return null;
    final px = _length(value.single);
    if (px == null) return null;
    return MediaSizeTest(
      height: feature == 'height',
      comparison: comparison,
      px: px,
    );
  }

  /// `name op valor`, `valor op name` ou `valor op name op valor`.
  MediaCondition _range(List<CssToken> items) {
    // Separa em operandos e operadores.
    final operands = <List<CssToken>>[[]];
    final ops = <MediaComparison>[];
    for (var i = 0; i < items.length; i++) {
      final token = items[i];
      final op = _operator(items, i);
      if (op != null) {
        if (operands.last.isEmpty) return MediaConstant.unknown;
        ops.add(op.$1);
        operands.add([]);
        i += op.$2 - 1;
      } else {
        operands.last.add(token);
      }
    }
    if (operands.last.isEmpty || ops.isEmpty || ops.length > 2) {
      return MediaConstant.unknown;
    }
    if (ops.length == 1) {
      final left = operands[0];
      final right = operands[1];
      final leftName = left.length == 1 ? _identOf(left.single) : null;
      final rightName = right.length == 1 ? _identOf(right.single) : null;
      if (leftName != null && _rangeFeatures.contains(leftName)) {
        return _rangeTest(leftName, ops[0], right) ?? MediaConstant.unknown;
      }
      if (rightName != null && _rangeFeatures.contains(rightName)) {
        return _rangeTest(rightName, _flip(ops[0]), left) ??
            MediaConstant.unknown;
      }
      return MediaConstant.unknown;
    }
    final middle = operands[1];
    final name = middle.length == 1 ? _identOf(middle.single) : null;
    if (name == null || !_rangeFeatures.contains(name)) {
      return MediaConstant.unknown;
    }
    final lessFamily = {MediaComparison.less, MediaComparison.lessOrEqual};
    final greaterFamily = {
      MediaComparison.greater,
      MediaComparison.greaterOrEqual,
    };
    final sameDirection =
        (lessFamily.contains(ops[0]) && lessFamily.contains(ops[1])) ||
        (greaterFamily.contains(ops[0]) && greaterFamily.contains(ops[1]));
    if (!sameDirection) return MediaConstant.unknown;
    final low = _rangeTest(name, _flip(ops[0]), operands[0]);
    final high = _rangeTest(name, ops[1], operands[2]);
    if (low == null || high == null) return MediaConstant.unknown;
    return MediaAnd(List.unmodifiable([low, high]));
  }

  /// Operador em `items[i]` e quantos tokens ocupa (`<=` são dois delims
  /// colados).
  static (MediaComparison, int)? _operator(List<CssToken> items, int i) {
    final token = items[i];
    if (token.type != CssTokenType.delim) return null;
    final hasEq =
        i + 1 < items.length &&
        items[i + 1].type == CssTokenType.delim &&
        items[i + 1].value == '=' &&
        items[i + 1].start == token.end;
    return switch (token.value) {
      '<' =>
        hasEq ? (MediaComparison.lessOrEqual, 2) : (MediaComparison.less, 1),
      '>' =>
        hasEq
            ? (MediaComparison.greaterOrEqual, 2)
            : (MediaComparison.greater, 1),
      '=' => (MediaComparison.equal, 1),
      _ => null,
    };
  }

  /// `valor op recurso` ⇔ `recurso flip(op) valor`.
  static MediaComparison _flip(MediaComparison c) => switch (c) {
    MediaComparison.less => MediaComparison.greater,
    MediaComparison.lessOrEqual => MediaComparison.greaterOrEqual,
    MediaComparison.equal => MediaComparison.equal,
    MediaComparison.greaterOrEqual => MediaComparison.lessOrEqual,
    MediaComparison.greater => MediaComparison.less,
  };

  /// Comprimento em px (`0` sem unidade aceito; `em`/`rem` = 16 px).
  static double? _length(CssToken token) {
    if (token.type == CssTokenType.number) {
      return token.number == 0 ? 0 : null;
    }
    if (token.type != CssTokenType.dimension) return null;
    final factor = switch (asciiLower(token.unit)) {
      'px' => 1.0,
      'em' || 'rem' => _emPx,
      'in' => 96.0,
      'cm' => 96 / 2.54,
      'mm' => 96 / 25.4,
      'q' => 96 / 101.6,
      'pt' => 96 / 72,
      'pc' => 16.0,
      _ => null,
    };
    return factor == null ? null : token.number * factor;
  }

  /// `<ratio>`: `n` ou `n / d`, ambos positivos.
  static (double, double)? _ratio(List<CssToken> value) {
    double? positive(CssToken token) =>
        token.type == CssTokenType.number && token.number > 0
        ? token.number
        : null;
    if (value.length == 1) {
      final n = positive(value.single);
      return n == null ? null : (n, 1);
    }
    if (value.length != 3 ||
        value[1].type != CssTokenType.delim ||
        value[1].value != '/') {
      return null;
    }
    final n = positive(value[0]);
    final d = positive(value[2]);
    return n == null || d == null ? null : (n, d);
  }
}
