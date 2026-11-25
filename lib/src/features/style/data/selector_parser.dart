import '../domain/css_value.dart' show asciiLower;
import '../domain/selector.dart';
import 'css_tokenizer.dart';

/// Lê a lista de seletores do prelúdio de uma regra (Selectors Level 3,
/// mais `:not` simples).
///
/// Devolve `null` se **qualquer** seletor da lista for inválido ou não
/// suportado: a regra inteira cai, como no CSS. [namespaces] resolve os
/// prefixos (`ns|tipo`, `[ns|attr]`); prefixo não declarado invalida.
List<Selector>? parseSelectorList(
  List<CssToken> prelude,
  NamespaceMap namespaces,
) {
  final parser = _SelectorParser(prelude, namespaces);
  final out = <Selector>[];
  var start = 0;
  var depth = 0;
  for (var i = 0; i <= prelude.length; i++) {
    if (i < prelude.length) {
      switch (prelude[i].type) {
        case CssTokenType.function ||
            CssTokenType.leftParen ||
            CssTokenType.leftSquare:
          depth++;
          continue;
        case CssTokenType.rightParen || CssTokenType.rightSquare:
          depth--;
          continue;
        case CssTokenType.comma when depth == 0:
          break;
        default:
          continue;
      }
    }
    final selector = parser.complex(start, i);
    if (selector == null) return null;
    out.add(selector);
    start = i + 1;
  }
  return out;
}

/// Sentinela de falha nas leituras internas.
final class _Invalid implements Exception {
  const _Invalid();
}

const _invalid = _Invalid();

/// Tetos de cada parte da especificidade empacotada.
const int _specMax = 1023;

final class _SelectorParser {
  _SelectorParser(this.t, this.ns);

  final List<CssToken> t;
  final NamespaceMap ns;

  // Estado do seletor em leitura.
  late int _end;
  int _a = 0;
  int _b = 0;
  int _c = 0;
  PseudoElement? _pseudo;

  /// Lê o seletor complexo em `t[from, to)`; `null` se inválido.
  Selector? complex(int from, int to) {
    _end = to;
    _a = _b = _c = 0;
    _pseudo = null;
    try {
      return _complex(from);
    } on _Invalid {
      return null;
    }
  }

  bool _isWs(int i) => i < _end && t[i].type == CssTokenType.whitespace;

  int _skipWs(int i) {
    while (_isWs(i)) {
      i++;
    }
    return i;
  }

  bool _isDelim(int i, String c) =>
      i < _end && t[i].type == CssTokenType.delim && t[i].value == c;

  Selector _complex(int from) {
    final compounds = <CompoundSelector>[];
    final combinators = <Combinator>[];
    var i = _skipWs(from);
    if (i >= _end) throw _invalid;
    while (true) {
      if (_pseudo != null) throw _invalid; // pseudo-elemento só no fim
      final (compound, next) = _compound(i);
      compounds.add(compound);
      i = next;
      final sawWs = _isWs(i);
      i = _skipWs(i);
      if (i >= _end) break;
      final Combinator combinator;
      if (_isDelim(i, '>')) {
        combinator = Combinator.child;
      } else if (_isDelim(i, '+')) {
        combinator = Combinator.nextSibling;
      } else if (_isDelim(i, '~')) {
        combinator = Combinator.laterSibling;
      } else if (sawWs) {
        combinator = Combinator.descendant;
        combinators.add(combinator);
        continue;
      } else {
        throw _invalid;
      }
      combinators.add(combinator);
      i = _skipWs(i + 1);
      if (i >= _end) throw _invalid;
    }
    return Selector(
      compounds: List.unmodifiable(compounds.reversed),
      combinators: List.unmodifiable(combinators.reversed),
      specificity:
          (_a > _specMax ? _specMax : _a) << 20 |
          (_b > _specMax ? _specMax : _b) << 10 |
          (_c > _specMax ? _specMax : _c),
      pseudoElement: _pseudo,
    );
  }

  /// Lê um composto a partir de [i]; devolve o composto e o índice seguinte.
  (CompoundSelector, int) _compound(int i) {
    final simples = <SimpleSelector>[];
    final typed = _typeOrUniversal(i);
    if (typed != null) {
      simples.add(typed.$1);
      i = typed.$2;
      if (typed.$1.localName != null) _c++;
    } else if (ns.defaultUri != null) {
      // Universal implícito no namespace padrão.
      simples.add(TypeSelector(null, NamespaceConstraint.uri(ns.defaultUri!)));
    }
    var any = typed != null;
    while (i < _end) {
      final token = t[i];
      if (token.type == CssTokenType.whitespace) break;
      if (_isDelim(i, '>') || _isDelim(i, '+') || _isDelim(i, '~')) break;
      if (_pseudo != null) throw _invalid;
      if (token.type == CssTokenType.colon &&
          i + 1 < _end &&
          t[i + 1].type == CssTokenType.colon) {
        _pseudo = _pseudoElement(i + 2);
        _c++;
        i += 3;
      } else if (token.type == CssTokenType.colon &&
          i + 1 < _end &&
          t[i + 1].type == CssTokenType.ident &&
          _legacyPseudoElement(asciiLower(t[i + 1].value)) != null) {
        // Sintaxe antiga (`p:before`).
        _pseudo = _pseudoElement(i + 1);
        _c++;
        i += 2;
      } else {
        final (simple, next) = _simple(i, inNot: false);
        simples.add(simple);
        i = next;
      }
      any = true;
    }
    if (!any) throw _invalid;
    return (CompoundSelector(List.unmodifiable(simples)), i);
  }

  PseudoElement _pseudoElement(int i) {
    if (i >= _end || t[i].type != CssTokenType.ident) throw _invalid;
    return _legacyPseudoElement(asciiLower(t[i].value)) ?? (throw _invalid);
  }

  static PseudoElement? _legacyPseudoElement(String name) => switch (name) {
    'before' => PseudoElement.before,
    'after' => PseudoElement.after,
    'first-letter' => PseudoElement.firstLetter,
    'first-line' => PseudoElement.firstLine,
    _ => null,
  };

  /// Resolve um prefixo declarado; prefixo desconhecido invalida.
  NamespaceConstraint _prefix(String prefix) {
    final uri = ns.prefixes[prefix];
    if (uri == null) throw _invalid;
    return NamespaceConstraint.uri(uri);
  }

  /// Tipo ou universal com prefixo opcional; `null` se não houver.
  (TypeSelector, int)? _typeOrUniversal(int i) {
    if (i >= _end) return null;
    final token = t[i];
    NamespaceConstraint? constraint;
    var nameAt = i;
    if (_isDelim(i, '|')) {
      constraint = NamespaceConstraint.none;
      nameAt = i + 1;
    } else if ((token.type == CssTokenType.ident || _isDelim(i, '*')) &&
        _isDelim(i + 1, '|')) {
      constraint = token.type == CssTokenType.ident
          ? _prefix(token.value)
          : NamespaceConstraint.any;
      nameAt = i + 2;
    }
    if (nameAt >= _end) {
      if (constraint != null) throw _invalid;
      return null;
    }
    final name = t[nameAt];
    final String? localName;
    if (name.type == CssTokenType.ident) {
      localName = name.value;
    } else if (_isDelim(nameAt, '*')) {
      localName = null;
    } else {
      if (constraint != null) throw _invalid;
      return null;
    }
    constraint ??= ns.defaultUri == null
        ? NamespaceConstraint.any
        : NamespaceConstraint.uri(ns.defaultUri!);
    return (TypeSelector(localName, constraint), nameAt + 1);
  }

  /// Seletor simples (exceto tipo e pseudo-elemento) em [i].
  (SimpleSelector, int) _simple(int i, {required bool inNot}) {
    final token = t[i];
    switch (token.type) {
      case CssTokenType.hash:
        if (!token.isIdHash) throw _invalid;
        _a++;
        return (IdSelector(token.value), i + 1);
      case CssTokenType.delim when token.value == '.':
        if (i + 1 >= _end || t[i + 1].type != CssTokenType.ident) {
          throw _invalid;
        }
        _b++;
        return (ClassSelector(t[i + 1].value), i + 2);
      case CssTokenType.leftSquare:
        _b++;
        return _attribute(i + 1);
      case CssTokenType.colon:
        return _pseudoClass(i + 1, inNot: inNot);
      default:
        throw _invalid;
    }
  }

  (SimpleSelector, int) _attribute(int i) {
    i = _skipWs(i);
    NamespaceConstraint constraint = NamespaceConstraint.none;
    if (_isDelim(i, '|')) {
      i++;
    } else if (_isDelim(i, '*') && _isDelim(i + 1, '|')) {
      constraint = NamespaceConstraint.any;
      i += 2;
    } else if (i < _end &&
        t[i].type == CssTokenType.ident &&
        _isDelim(i + 1, '|') &&
        i + 2 < _end &&
        t[i + 2].type == CssTokenType.ident) {
      constraint = _prefix(t[i].value);
      i += 2;
    }
    if (i >= _end || t[i].type != CssTokenType.ident) throw _invalid;
    final name = t[i].value;
    i = _skipWs(i + 1);
    if (i >= _end) throw _invalid;
    if (t[i].type == CssTokenType.rightSquare) {
      return (
        AttributeSelector(
          name,
          constraint,
          AttributeOperator.exists,
          '',
          caseInsensitive: false,
        ),
        i + 1,
      );
    }
    final AttributeOperator op;
    if (_isDelim(i, '=')) {
      op = AttributeOperator.equals;
      i++;
    } else {
      if (t[i].type != CssTokenType.delim || !_isDelim(i + 1, '=')) {
        throw _invalid;
      }
      op = switch (t[i].value) {
        '~' => AttributeOperator.includes,
        '|' => AttributeOperator.dashMatch,
        '^' => AttributeOperator.prefix,
        r'$' => AttributeOperator.suffix,
        '*' => AttributeOperator.substring,
        _ => throw _invalid,
      };
      i += 2;
    }
    i = _skipWs(i);
    if (i >= _end ||
        (t[i].type != CssTokenType.ident && t[i].type != CssTokenType.string)) {
      throw _invalid;
    }
    final value = t[i].value;
    i = _skipWs(i + 1);
    var insensitive = false;
    if (i < _end &&
        t[i].type == CssTokenType.ident &&
        asciiLower(t[i].value) == 'i') {
      insensitive = true;
      i = _skipWs(i + 1);
    }
    if (i >= _end || t[i].type != CssTokenType.rightSquare) throw _invalid;
    return (
      AttributeSelector(
        name,
        constraint,
        op,
        value,
        caseInsensitive: insensitive,
      ),
      i + 1,
    );
  }

  /// Pseudo-classe (o `:` já foi consumido; [i] aponta o nome).
  (SimpleSelector, int) _pseudoClass(int i, {required bool inNot}) {
    if (i >= _end) throw _invalid;
    final token = t[i];
    if (token.type == CssTokenType.ident) {
      final name = asciiLower(token.value);
      final simple = switch (name) {
        'root' => const PseudoClassSelector(PseudoClassKind.root),
        'first-child' => const PseudoClassSelector(
          PseudoClassKind.nthChild,
          b: 1,
        ),
        'last-child' => const PseudoClassSelector(
          PseudoClassKind.nthLastChild,
          b: 1,
        ),
        'only-child' => const PseudoClassSelector(PseudoClassKind.onlyChild),
        'first-of-type' => const PseudoClassSelector(
          PseudoClassKind.nthOfType,
          b: 1,
        ),
        'last-of-type' => const PseudoClassSelector(
          PseudoClassKind.nthLastOfType,
          b: 1,
        ),
        'only-of-type' => const PseudoClassSelector(PseudoClassKind.onlyOfType),
        'empty' => const PseudoClassSelector(PseudoClassKind.empty),
        'link' => const PseudoClassSelector(PseudoClassKind.link),
        'hover' ||
        'active' ||
        'focus' ||
        'visited' => const PseudoClassSelector(PseudoClassKind.never),
        _ => throw _invalid,
      };
      _b++;
      return (simple, i + 1);
    }
    if (token.type != CssTokenType.function) throw _invalid;
    final close = _closingParen(i + 1);
    final name = asciiLower(token.value);
    final argFrom = _skipWs(i + 1);
    var argTo = close;
    while (argTo > argFrom && t[argTo - 1].type == CssTokenType.whitespace) {
      argTo--;
    }
    switch (name) {
      case 'nth-child' ||
          'nth-last-child' ||
          'nth-of-type' ||
          'nth-last-of-type':
        final (a, b) = _anPlusB(argFrom, argTo);
        _b++;
        final kind = switch (name) {
          'nth-child' => PseudoClassKind.nthChild,
          'nth-last-child' => PseudoClassKind.nthLastChild,
          'nth-of-type' => PseudoClassKind.nthOfType,
          _ => PseudoClassKind.nthLastOfType,
        };
        return (PseudoClassSelector(kind, a: a, b: b), close + 1);
      case 'lang':
        if (argTo - argFrom != 1 || t[argFrom].type != CssTokenType.ident) {
          throw _invalid;
        }
        _b++;
        return (
          PseudoClassSelector(
            PseudoClassKind.lang,
            lang: asciiLower(t[argFrom].value),
          ),
          close + 1,
        );
      case 'not':
        if (inNot || argFrom >= argTo) throw _invalid;
        final savedEnd = _end;
        _end = argTo;
        final SimpleSelector argument;
        int next;
        final typed = _typeOrUniversal(argFrom);
        if (typed != null) {
          argument = typed.$1;
          next = typed.$2;
          if (typed.$1.localName != null) _c++;
        } else {
          final (simple, n) = _simple(argFrom, inNot: true);
          argument = simple;
          next = n;
        }
        if (next != argTo) throw _invalid;
        _end = savedEnd;
        return (NotSelector(argument), close + 1);
      default:
        throw _invalid;
    }
  }

  /// Índice do `)` que fecha a função cujo conteúdo começa em [i].
  int _closingParen(int i) {
    var depth = 1;
    for (; i < _end; i++) {
      switch (t[i].type) {
        case CssTokenType.function || CssTokenType.leftParen:
          depth++;
        case CssTokenType.rightParen:
          if (--depth == 0) return i;
        default:
      }
    }
    throw _invalid;
  }

  /// Microssintaxe An+B (CSS Syntax §6) em `t[from, to)`, sem espaço nas
  /// pontas.
  (int, int) _anPlusB(int from, int to) {
    if (from >= to) throw _invalid;
    var i = from;
    final first = t[i];
    int a;
    // Resto do ident/unidade depois do `n` (ex.: '', '-', '-3').
    String rest;
    switch (first.type) {
      case CssTokenType.number:
        if (!first.isInteger || to - from != 1) throw _invalid;
        return (0, _int(first.number));
      case CssTokenType.dimension:
        if (!first.isInteger) throw _invalid;
        final unit = asciiLower(first.unit);
        if (!unit.startsWith('n')) throw _invalid;
        a = _int(first.number);
        rest = unit.substring(1);
        i++;
      case CssTokenType.ident:
        final v = asciiLower(first.value);
        if (to - from == 1 && v == 'odd') return (2, 1);
        if (to - from == 1 && v == 'even') return (2, 0);
        if (v.startsWith('-n')) {
          a = -1;
          rest = v.substring(2);
        } else if (v.startsWith('n')) {
          a = 1;
          rest = v.substring(1);
        } else {
          throw _invalid;
        }
        i++;
      case CssTokenType.delim when first.value == '+':
        // `+n...`: o `+` precisa estar colado ao ident.
        if (i + 1 >= to ||
            t[i + 1].type != CssTokenType.ident ||
            t[i + 1].start != first.end) {
          throw _invalid;
        }
        final v = asciiLower(t[i + 1].value);
        if (!v.startsWith('n')) throw _invalid;
        a = 1;
        rest = v.substring(1);
        i += 2;
      default:
        throw _invalid;
    }
    if (rest.isEmpty) {
      // `an`, seguido opcionalmente de `±b`.
      i = _skipWs(i);
      if (i >= to) return (a, 0);
      final token = t[i];
      if (token.type == CssTokenType.number) {
        if (!token.isInteger || !token.hasSign || i + 1 != to) throw _invalid;
        return (a, _int(token.number));
      }
      if (token.type != CssTokenType.delim ||
          (token.value != '+' && token.value != '-')) {
        throw _invalid;
      }
      final sign = token.value == '-' ? -1 : 1;
      i = _skipWs(i + 1);
      return (a, sign * _signless(i, to));
    }
    if (rest == '-') {
      // `an-` seguido de inteiro sem sinal.
      return (a, -_signless(_skipWs(i), to));
    }
    // `an-<dígitos>`.
    if (rest.length < 2 || rest.codeUnitAt(0) != 0x2D || i != to) {
      throw _invalid;
    }
    var b = 0;
    for (var k = 1; k < rest.length; k++) {
      final c = rest.codeUnitAt(k);
      if (c < 0x30 || c > 0x39) throw _invalid;
      if (b < _intCap) b = b * 10 + (c - 0x30);
    }
    return (a, -(b > _intCap ? _intCap : b));
  }

  /// Inteiro sem sinal em [i], que precisa ser o último token antes de [to].
  int _signless(int i, int to) {
    if (i >= to || i + 1 != to) throw _invalid;
    final token = t[i];
    if (token.type != CssTokenType.number ||
        !token.isInteger ||
        token.hasSign) {
      throw _invalid;
    }
    return _int(token.number);
  }

  static const int _intCap = 1 << 30;

  static int _int(double v) {
    if (v > _intCap) return _intCap;
    if (v < -_intCap) return -_intCap;
    return v.toInt();
  }
}
