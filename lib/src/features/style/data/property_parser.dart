import 'package:meta/meta.dart';

import '../domain/css_value.dart';
import '../domain/properties.dart';
import 'css_tokenizer.dart';
import 'css_value_reader.dart';

/// Resultado de [parseProperty].
@immutable
sealed class PropertyParseResult {
  const PropertyParseResult();
}

/// Declaração válida: os pares (id de [PropertyId], valor) das longhands, em
/// ordem. Abreviadas produzem todas as suas longhands (as omitidas com o
/// valor inicial).
final class ParsedLonghands extends PropertyParseResult {
  /// Cria o resultado.
  const ParsedLonghands(this.values);

  /// Pares (id da longhand, valor).
  final List<(int, CssValue)> values;

  @override
  String toString() => 'ParsedLonghands($values)';
}

/// Propriedade fora do escopo do motor (vira `css.unsupportedProperty`).
final class UnsupportedProperty extends PropertyParseResult {
  /// Cria o resultado.
  const UnsupportedProperty();
}

/// Propriedade conhecida e deliberadamente sem efeito num leitor (fala,
/// interação...): descartada sem diagnóstico.
final class IgnoredProperty extends PropertyParseResult {
  /// Cria o resultado.
  const IgnoredProperty();
}

/// Propriedade do escopo com valor inválido (vira `css.invalidValue`).
final class InvalidValue extends PropertyParseResult {
  /// Cria o resultado.
  const InvalidValue();
}

/// Interpreta a declaração `name: value`.
///
/// [name] é comparado sem diferença de caixa ASCII (exceto `--*`, sempre
/// [UnsupportedProperty]); [value] são os tokens aparados e sem
/// `!important` (o `value` de `RawDeclaration`); [sheetPath] é o caminho da folha
/// no zip, base de `url()`. Abreviadas viram longhands; aliases de prefixo
/// viram a propriedade padrão; `inherit`, `initial` e `unset` sozinhos valem
/// para todas as longhands da propriedade.
PropertyParseResult parseProperty(
  String name,
  List<CssToken> value, {
  required String sheetPath,
}) {
  if (name.startsWith('--')) return const UnsupportedProperty();
  var n = asciiLower(name);
  if (_ignored.contains(n)) return const IgnoredProperty();
  var tokens = value;
  final alias = _aliases[n];
  if (alias != null) {
    n = alias.target;
    final map = alias.values;
    if (map != null) {
      if (tokens.length != 1 || tokens.single.type != CssTokenType.ident) {
        return const InvalidValue();
      }
      final t = tokens.single;
      final v = asciiLower(t.value);
      if (!_cssWide.contains(v)) {
        final mapped = map[v];
        if (mapped == null) return const InvalidValue();
        tokens = [CssToken(CssTokenType.ident, t.start, t.end, value: mapped)];
      }
    }
  }
  final prop = _properties[n];
  if (prop == null) return const UnsupportedProperty();
  final r = CssValueReader(tokens, sheetPath);
  final comps = r.components;
  if (comps == null || comps.isEmpty) return const InvalidValue();
  if (comps.length == 1) {
    final ident = r.identLower(comps.single);
    if (ident != null && _cssWide.contains(ident)) {
      final v = CssKeyword(CssKeywords.idOf(ident)!);
      return ParsedLonghands([for (final id in prop.longhands) (id, v)]);
    }
  }
  // CSS-wide misturado a outros valores é inválido. (`var()`, `min()` etc.
  // não são aceitos por nenhum leitor e também dão InvalidValue.)
  for (final c in comps) {
    final ident = r.identLower(c);
    if (ident != null && _cssWide.contains(ident)) return const InvalidValue();
  }
  final out = prop.parse(r, comps);
  return out == null ? const InvalidValue() : ParsedLonghands(out);
}

const Set<String> _cssWide = {'inherit', 'initial', 'unset'};

const Set<String> _ignored = {
  'speak',
  'speak-as',
  'speak-punctuation',
  'speech-rate',
  'stress',
  'volume',
  'richness',
  'pause',
  'pause-before',
  'pause-after',
  '-webkit-tap-highlight-color',
  'pointer-events',
  'adobe-text-layout',
  'background-attachment',
};

/// Alias de prefixo (ou legado): propriedade padrão e, se houver, as
/// palavras-chave aceitas com a tradução de cada uma.
final class _Alias {
  const _Alias(this.target, [this.values]);

  final String target;
  final Map<String, String>? values;
}

const Map<String, String> _pageBreak = {
  'auto': 'auto',
  'always': 'page',
  'avoid': 'avoid',
  'left': 'left',
  'right': 'right',
};

const Map<String, _Alias> _aliases = {
  'page-break-before': _Alias('break-before', _pageBreak),
  'page-break-after': _Alias('break-after', _pageBreak),
  'page-break-inside': _Alias('break-inside', {
    'auto': 'auto',
    'avoid': 'avoid',
  }),
  '-webkit-hyphens': _Alias('hyphens'),
  '-epub-hyphens': _Alias('hyphens'),
  '-moz-hyphens': _Alias('hyphens'),
  '-ms-hyphens': _Alias('hyphens'),
  'adobe-hyphenate': _Alias('hyphens', {
    'none': 'none',
    'explicit': 'manual',
    'auto': 'auto',
  }),
  '-epub-writing-mode': _Alias('writing-mode'),
  '-webkit-writing-mode': _Alias('writing-mode'),
  '-epub-text-combine': _Alias('text-combine-upright', {
    'none': 'none',
    'horizontal': 'all',
  }),
  '-epub-text-emphasis-style': _Alias('text-emphasis-style'),
  '-epub-text-emphasis-color': _Alias('text-emphasis-color'),
  'word-wrap': _Alias('overflow-wrap'),
};

typedef _Comps = List<CssComponent>;
typedef _Out = List<(int, CssValue)>;

/// Leitor de um componente para um valor.
typedef _One = CssValue? Function(CssValueReader r, CssComponent c);

/// Propriedade do escopo: longhands que produz e o leitor do valor.
final class _Prop {
  const _Prop(this.longhands, this.parse);

  final List<int> longhands;
  final _Out? Function(CssValueReader r, _Comps cs) parse;
}

/// Longhand de um só componente.
_Prop _single(int id, _One f) => _Prop([id], (r, cs) {
  if (cs.length != 1) return null;
  final v = f(r, cs.single);
  return v == null ? null : [(id, v)];
});

/// Longhand de vários componentes.
_Prop _multi(int id, CssValue? Function(CssValueReader r, _Comps cs) f) =>
    _Prop([id], (r, cs) {
      final v = f(r, cs);
      return v == null ? null : [(id, v)];
    });

Set<int> _ids(List<String> names) => {
  for (final n in names) CssKeywords.idOf(n)!,
};

/// Leitor de palavra-chave de um conjunto.
_One _kw(List<String> names) {
  final set = _ids(names);
  return (r, c) {
    final id = r.keyword(c);
    return id != null && set.contains(id) ? CssKeyword(id) : null;
  };
}

/// Tenta os leitores em ordem.
_One _any(List<_One> fs) => (r, c) {
  for (final f in fs) {
    final v = f(r, c);
    if (v != null) return v;
  }
  return null;
};

_One _len({bool percent = true, bool negative = true}) =>
    (r, c) => r.length(c, percent: percent, negative: negative);

CssValue? _color(CssValueReader r, CssComponent c) => r.color(c);

CssValue? _url(CssValueReader r, CssComponent c) {
  final p = r.url(c);
  return p == null ? null : CssUrl(p);
}

CssValue? _string(CssValueReader r, CssComponent c) {
  final s = r.string(c);
  return s == null ? null : CssString(s);
}

/// Inteiro limitado (`z-index`).
CssValue? _integer(CssValueReader r, CssComponent c) {
  final v = r.integer(c);
  return v == null ? null : CssNumber(v.toDouble());
}

/// Inteiro ≥ 1 (`orphans`, `widows`).
CssValue? _positiveInteger(CssValueReader r, CssComponent c) {
  final v = r.integer(c);
  return v == null || v < 1 ? null : CssNumber(v.toDouble());
}

/// Lista de palavras-chave em grupos (`a || b || c`), em ordem canônica
/// (a dos grupos); cada grupo no máximo uma vez. `none`/`normal` sozinho
/// vira a palavra-chave.
CssValue? Function(CssValueReader, _Comps) _groups(
  List<List<String>> groups, {
  String? alone,
}) {
  final sets = [for (final g in groups) _ids(g)];
  final aloneId = alone == null ? null : CssKeywords.idOf(alone);
  return (r, cs) {
    if (cs.length == 1 && aloneId != null && r.keyword(cs.single) == aloneId) {
      return CssKeyword(aloneId);
    }
    final chosen = List<int?>.filled(sets.length, null);
    for (final c in cs) {
      final id = r.keyword(c);
      if (id == null) return null;
      final g = sets.indexWhere((s) => s.contains(id));
      if (g < 0 || chosen[g] != null) return null;
      chosen[g] = id;
    }
    return CssList([
      for (final id in chosen)
        if (id != null) CssKeyword(id),
    ]);
  };
}

/// 1 a 4 valores → topo, direita, base, esquerda.
_Prop _box(List<int> ids, _One f) => _Prop(ids, (r, cs) {
  if (cs.isEmpty || cs.length > 4) return null;
  final v = <CssValue>[];
  for (final c in cs) {
    final x = f(r, c);
    if (x == null) return null;
    v.add(x);
  }
  final top = v[0];
  final right = v.length > 1 ? v[1] : top;
  final bottom = v.length > 2 ? v[2] : top;
  final left = v.length > 3 ? v[3] : right;
  return [(ids[0], top), (ids[1], right), (ids[2], bottom), (ids[3], left)];
});

// --- Leitores por propriedade ------------------------------------------------

const List<String> _genericFamilies = [
  'serif',
  'sans-serif',
  'cursive',
  'fantasy',
  'monospace',
  'system-ui',
  'ui-serif',
  'ui-sans-serif',
  'ui-monospace',
  'ui-rounded',
  'math',
  'emoji',
  'fangsong',
];

CssValue? _fontFamily(CssValueReader r, _Comps cs) {
  final out = <FontFamilyName>[];
  final words = <String>[];
  var quoted = false;
  var hasIdent = false;
  bool flush() {
    if (quoted) {
      quoted = false;
      return true;
    }
    if (words.isEmpty) return false;
    if (words.length == 1) {
      final lower = asciiLower(words.single);
      if (lower == 'default' || _cssWide.contains(lower)) return false;
      if (_genericFamilies.contains(lower)) {
        out.add(FontFamilyName(lower, generic: true));
        words.clear();
        return true;
      }
    }
    out.add(FontFamilyName(words.join(' ')));
    words.clear();
    return true;
  }

  for (final c in cs) {
    if (r.isComma(c)) {
      if (!flush()) return null;
      hasIdent = false;
      continue;
    }
    final s = r.string(c);
    if (s != null) {
      if (quoted || hasIdent) return null;
      out.add(FontFamilyName(s));
      quoted = true;
      continue;
    }
    final t = r.token(c);
    if (t.type != CssTokenType.ident || quoted) return null;
    words.add(t.value);
    hasIdent = true;
  }
  if (!flush()) return null;
  return CssFontFamilies(out);
}

final _One _fontSize = _any([
  _len(negative: false),
  _kw([
    'xx-small',
    'x-small',
    'small',
    'medium',
    'large',
    'x-large',
    'xx-large',
    'xxx-large',
    'smaller',
    'larger',
  ]),
]);

final _One _fontStyle = _kw(['normal', 'italic', 'oblique']);

CssValue? _fontWeight(CssValueReader r, CssComponent c) {
  final n = r.number(c);
  if (n != null) return n >= 1 && n <= 1000 ? CssNumber(n) : null;
  switch (r.keyword(c)) {
    case CssKeywords.normal:
      return const CssNumber(400);
    case CssKeywords.bold:
      return const CssNumber(700);
    case CssKeywords.bolder:
      return const CssKeyword(CssKeywords.bolder);
    case CssKeywords.lighter:
      return const CssKeyword(CssKeywords.lighter);
  }
  return null;
}

final _One _fontVariant = _kw([
  'normal',
  'small-caps',
  'all-small-caps',
  'petite-caps',
  'all-petite-caps',
  'unicase',
  'titling-caps',
]);

CssValue? _lineHeight(CssValueReader r, CssComponent c) {
  final n = r.number(c);
  if (n != null) return n >= 0 ? CssNumber(n) : null;
  if (r.keyword(c) == CssKeywords.normal) {
    return const CssKeyword(CssKeywords.normal);
  }
  return r.length(c, negative: false);
}

const Set<String> _fontStretch = {
  'ultra-condensed',
  'extra-condensed',
  'condensed',
  'semi-condensed',
  'semi-expanded',
  'expanded',
  'extra-expanded',
  'ultra-expanded',
};

/// `font`: `[style || variant || weight || stretch]? size [/ line-height]?
/// family`. Fontes de sistema (`caption`, `menu`...) são inválidas.
_Out? _font(CssValueReader r, _Comps cs) {
  CssValue? style, variant, weight;
  var stretch = false;
  var i = 0;
  var count = 0;
  while (i < cs.length && count < 4) {
    final c = cs[i];
    final id = r.keyword(c);
    final ident = r.identLower(c);
    if (id == CssKeywords.normal) {
      // `normal` vale para qualquer das quatro.
    } else if (style == null &&
        (id == CssKeywords.italic || id == CssKeywords.oblique)) {
      style = CssKeyword(id!);
    } else if (variant == null && id == CssKeywords.smallCaps) {
      variant = const CssKeyword(CssKeywords.smallCaps);
    } else if (weight == null &&
        (id == CssKeywords.bold ||
            id == CssKeywords.bolder ||
            id == CssKeywords.lighter)) {
      weight = _fontWeight(r, c);
    } else if (!stretch && ident != null && _fontStretch.contains(ident)) {
      stretch = true;
    } else if (weight == null &&
        r.number(c) != null &&
        _fontWeight(r, c) != null) {
      weight = _fontWeight(r, c);
    } else {
      break;
    }
    i++;
    count++;
  }
  if (i >= cs.length) return null;
  final size = _fontSize(r, cs[i++]);
  if (size == null) return null;
  CssValue lineHeight = const CssKeyword(CssKeywords.normal);
  if (i < cs.length && r.isDelim(cs[i], '/')) {
    if (i + 1 >= cs.length) return null;
    final lh = _lineHeight(r, cs[i + 1]);
    if (lh == null) return null;
    lineHeight = lh;
    i += 2;
  }
  if (i >= cs.length) return null;
  final family = _fontFamily(r, cs.sublist(i));
  if (family == null) return null;
  return [
    (PropertyId.fontStyle, style ?? const CssKeyword(CssKeywords.normal)),
    (PropertyId.fontVariant, variant ?? const CssKeyword(CssKeywords.normal)),
    (PropertyId.fontWeight, weight ?? const CssNumber(400)),
    (PropertyId.fontSize, size),
    (PropertyId.lineHeight, lineHeight),
    (PropertyId.fontFamily, family),
    (PropertyId.fontVariantNumeric, const CssKeyword(CssKeywords.normal)),
  ];
}

final _decorationLine = _groups([
  ['underline'],
  ['overline'],
  ['line-through'],
  ['blink'],
], alone: 'none');

final _One _decorationStyle = _kw([
  'solid',
  'double',
  'dotted',
  'dashed',
  'wavy',
]);

/// `text-decoration`: `line || style || color` (as palavras da linha
/// juntas).
_Out? _textDecoration(CssValueReader r, _Comps cs) {
  CssValue? line, style, color;
  var i = 0;
  while (i < cs.length) {
    final c = cs[i];
    final id = r.keyword(c);
    final isLine =
        id == CssKeywords.none ||
        id == CssKeywords.underline ||
        id == CssKeywords.overline ||
        id == CssKeywords.lineThrough ||
        id == CssKeywords.blink;
    if (isLine) {
      if (line != null) return null;
      var j = i + 1;
      while (j < cs.length) {
        final k = r.keyword(cs[j]);
        if (k != CssKeywords.none &&
            k != CssKeywords.underline &&
            k != CssKeywords.overline &&
            k != CssKeywords.lineThrough &&
            k != CssKeywords.blink) {
          break;
        }
        j++;
      }
      line = _decorationLine(r, cs.sublist(i, j));
      if (line == null) return null;
      i = j;
      continue;
    }
    final s = _decorationStyle(r, c);
    if (s != null) {
      if (style != null) return null;
      style = s;
    } else {
      final col = r.color(c);
      if (col == null || color != null) return null;
      color = col;
    }
    i++;
  }
  return [
    (PropertyId.textDecorationLine, line ?? const CssKeyword(CssKeywords.none)),
    (
      PropertyId.textDecorationStyle,
      style ?? const CssKeyword(CssKeywords.solid),
    ),
    (
      PropertyId.textDecorationColor,
      color ?? const CssKeyword(CssKeywords.currentcolor),
    ),
  ];
}

CssValue? _writingMode(CssValueReader r, CssComponent c) {
  final s = r.identLower(c);
  final String? name = switch (s) {
    'horizontal-tb' ||
    'vertical-rl' ||
    'vertical-lr' ||
    'sideways-rl' ||
    'sideways-lr' => s,
    'lr' || 'lr-tb' || 'rl' || 'rl-tb' => 'horizontal-tb',
    'tb' || 'tb-rl' => 'vertical-rl',
    'tb-lr' => 'vertical-lr',
    _ => null,
  };
  return name == null ? null : CssKeyword(CssKeywords.idOf(name)!);
}

CssValue? _emphasisStyle(CssValueReader r, _Comps cs) {
  if (cs.length == 1) {
    final s = _string(r, cs.single);
    if (s != null) return s;
  }
  return _emphasisGroups(r, cs);
}

final _emphasisGroups = _groups([
  ['filled', 'open'],
  ['dot', 'circle', 'double-circle', 'triangle', 'sesame'],
], alone: 'none');

final _hangingPunctuation = _groups([
  ['first'],
  ['force-end', 'allow-end'],
  ['last'],
], alone: 'none');

final _fontVariantNumeric = _groups([
  ['lining-nums', 'oldstyle-nums'],
  ['proportional-nums', 'tabular-nums'],
  ['diagonal-fractions', 'stacked-fractions'],
  ['ordinal'],
  ['slashed-zero'],
], alone: 'normal');

// Caixa.

final _One _borderWidth = _any([
  (r, c) => switch (r.keyword(c)) {
    CssKeywords.thin => const CssLengthSpec(px: 1),
    CssKeywords.medium => const CssLengthSpec(px: 3),
    CssKeywords.thick => const CssLengthSpec(px: 5),
    _ => null,
  },
  _len(percent: false, negative: false),
]);

final _One _borderStyle = _kw([
  'none',
  'hidden',
  'dotted',
  'dashed',
  'solid',
  'double',
  'groove',
  'ridge',
  'inset',
  'outset',
]);

/// `width || style || color` de uma borda; omitidos com o valor inicial.
(CssValue, CssValue, CssValue)? _borderSide(CssValueReader r, _Comps cs) {
  if (cs.isEmpty || cs.length > 3) return null;
  CssValue? width, style, color;
  for (final c in cs) {
    final w = _borderWidth(r, c);
    if (w != null) {
      if (width != null) return null;
      width = w;
      continue;
    }
    final s = _borderStyle(r, c);
    if (s != null) {
      if (style != null) return null;
      style = s;
      continue;
    }
    final col = r.color(c);
    if (col == null || color != null) return null;
    color = col;
  }
  return (
    width ?? const CssLengthSpec(px: 3),
    style ?? const CssKeyword(CssKeywords.none),
    color ?? const CssKeyword(CssKeywords.currentcolor),
  );
}

const List<List<int>> _borderIds = [
  [
    PropertyId.borderTopWidth,
    PropertyId.borderTopStyle,
    PropertyId.borderTopColor,
  ],
  [
    PropertyId.borderRightWidth,
    PropertyId.borderRightStyle,
    PropertyId.borderRightColor,
  ],
  [
    PropertyId.borderBottomWidth,
    PropertyId.borderBottomStyle,
    PropertyId.borderBottomColor,
  ],
  [
    PropertyId.borderLeftWidth,
    PropertyId.borderLeftStyle,
    PropertyId.borderLeftColor,
  ],
];

_Prop _borderSideProp(List<int> ids) => _Prop(ids, (r, cs) {
  final v = _borderSide(r, cs);
  if (v == null) return null;
  return [(ids[0], v.$1), (ids[1], v.$2), (ids[2], v.$3)];
});

final _Prop _border = _Prop([for (final s in _borderIds) ...s], (r, cs) {
  final v = _borderSide(r, cs);
  if (v == null) return null;
  return [
    for (final s in _borderIds) ...[(s[0], v.$1), (s[1], v.$2), (s[2], v.$3)],
  ];
});

const List<int> _radiusIds = [
  PropertyId.borderTopLeftRadius,
  PropertyId.borderTopRightRadius,
  PropertyId.borderBottomRightRadius,
  PropertyId.borderBottomLeftRadius,
];

final _One _radius = _len(negative: false);

/// `border-radius`: 1 a 4 raios horizontais; a parte após `/` (raios
/// verticais) é validada e ignorada.
_Out? _borderRadius(CssValueReader r, _Comps cs) {
  var slash = cs.indexWhere((c) => r.isDelim(c, '/'));
  if (slash < 0) slash = cs.length;
  final h = cs.sublist(0, slash);
  if (h.isEmpty || h.length > 4) return null;
  if (slash < cs.length) {
    final v = cs.sublist(slash + 1);
    if (v.isEmpty || v.length > 4) return null;
    if (v.any((c) => _radius(r, c) == null)) return null;
  }
  final x = <CssValue>[];
  for (final c in h) {
    final l = _radius(r, c);
    if (l == null) return null;
    x.add(l);
  }
  final tl = x[0];
  final tr = x.length > 1 ? x[1] : tl;
  final br = x.length > 2 ? x[2] : tl;
  final bl = x.length > 3 ? x[3] : tr;
  return [
    (_radiusIds[0], tl),
    (_radiusIds[1], tr),
    (_radiusIds[2], br),
    (_radiusIds[3], bl),
  ];
}

/// Longhand de canto: 1 ou 2 raios; guarda o horizontal.
_Prop _cornerRadius(int id) => _multi(id, (r, cs) {
  if (cs.isEmpty || cs.length > 2) return null;
  if (cs.length == 2 && _radius(r, cs[1]) == null) return null;
  return _radius(r, cs[0]);
});

final _One _size = _any([
  _len(negative: false),
  _kw(['auto', 'min-content', 'max-content', 'fit-content']),
]);

final _One _maxSize = _any([
  _len(negative: false),
  _kw(['none', 'min-content', 'max-content', 'fit-content']),
]);

final _One _inset = _any([
  _len(),
  _kw(['auto']),
]);

// Fundo.

const Set<String> _repeatSingle = {
  'repeat',
  'repeat-x',
  'repeat-y',
  'no-repeat',
  'space',
  'round',
};

const Set<String> _repeatPair = {'repeat', 'no-repeat', 'space', 'round'};

CssValue? _backgroundRepeat(CssValueReader r, _Comps cs) {
  if (cs.length == 1) {
    final s = r.identLower(cs.single);
    return s != null && _repeatSingle.contains(s)
        ? CssKeyword(CssKeywords.idOf(s)!)
        : null;
  }
  if (cs.length != 2) return null;
  final a = r.identLower(cs[0]);
  final b = r.identLower(cs[1]);
  if (a == null || b == null) return null;
  if (!_repeatPair.contains(a) || !_repeatPair.contains(b)) return null;
  return CssList([
    CssKeyword(CssKeywords.idOf(a)!),
    CssKeyword(CssKeywords.idOf(b)!),
  ]);
}

const CssLengthSpec _p0 = CssLengthSpec();
const CssLengthSpec _p50 = CssLengthSpec(percent: 50);
const CssLengthSpec _p100 = CssLengthSpec(percent: 100);

bool _isPositionKeyword(int? id) =>
    id == CssKeywords.left ||
    id == CssKeywords.right ||
    id == CssKeywords.top ||
    id == CssKeywords.bottom ||
    id == CssKeywords.center;

/// Eixo de uma palavra de posição: 0 = x, 1 = y, -1 = qualquer (`center`).
int _axis(int id) => switch (id) {
  CssKeywords.left || CssKeywords.right => 0,
  CssKeywords.top || CssKeywords.bottom => 1,
  _ => -1,
};

CssLengthSpec _keywordOffset(int id) => switch (id) {
  CssKeywords.right || CssKeywords.bottom => _p100,
  CssKeywords.center => _p50,
  _ => _p0,
};

/// Posição de fundo (1 a 4 valores) como `CssList([x, y])`, com as
/// palavras-chave em porcentagem e os deslocamentos de `right`/`bottom`
/// como `100% - deslocamento`.
CssValue? _position(CssValueReader r, _Comps cs) {
  if (cs.isEmpty || cs.length > 4) return null;
  final kws = [for (final c in cs) r.keyword(c)];
  final lens = [
    for (final c in cs) _isPositionKeyword(r.keyword(c)) ? null : r.length(c),
  ];
  for (var i = 0; i < cs.length; i++) {
    if (!_isPositionKeyword(kws[i]) && lens[i] == null) return null;
  }
  CssLengthSpec? x, y;
  if (cs.length == 1) {
    final k = kws[0];
    if (lens[0] != null) return CssList([lens[0]!, _p50]);
    if (_axis(k!) == 1) return CssList([_p50, _keywordOffset(k)]);
    return CssList([_keywordOffset(k), _p50]);
  }
  if (cs.length == 2) {
    final a = kws[0], b = kws[1];
    if (lens[0] == null && lens[1] == null) {
      final ax = _axis(a!), bx = _axis(b!);
      if (ax == bx && ax != -1) return null;
      // Ordem trocada (`top left`).
      if (ax == 1 || bx == 0) {
        return CssList([_keywordOffset(b), _keywordOffset(a)]);
      }
      return CssList([_keywordOffset(a), _keywordOffset(b)]);
    }
    x = lens[0] ?? (_axis(a!) == 1 ? null : _keywordOffset(a));
    y = lens[1] ?? (_axis(b!) == 0 ? null : _keywordOffset(b));
    if (x == null || y == null) return null;
    return CssList([x, y]);
  }
  // 3 ou 4 valores: pares palavra-chave [+ deslocamento].
  if (lens[0] != null) return null;
  final groups = <(int, CssLengthSpec?)>[];
  var i = 0;
  while (i < cs.length) {
    final k = kws[i];
    if (lens[i] != null || k == null) return null;
    CssLengthSpec? off;
    if (i + 1 < cs.length && lens[i + 1] != null) {
      if (k == CssKeywords.center) return null;
      off = lens[i + 1];
      i += 2;
    } else {
      i++;
    }
    groups.add((k, off));
  }
  if (groups.length != 2) return null;
  var (k0, o0) = groups[0];
  var (k1, o1) = groups[1];
  final a0 = _axis(k0), a1 = _axis(k1);
  if (a0 == a1 && a0 != -1) return null;
  if (a0 == 1 || a1 == 0) {
    (k0, o0, k1, o1) = (k1, o1, k0, o0);
  }
  CssLengthSpec place(int k, CssLengthSpec? off) {
    if (off == null) return _keywordOffset(k);
    if (k == CssKeywords.right || k == CssKeywords.bottom) {
      return CssLengthSpec(
        px: clampMagnitude(-off.px),
        em: clampMagnitude(-off.em),
        ex: clampMagnitude(-off.ex),
        rem: clampMagnitude(-off.rem),
        percent: clampMagnitude(100 - off.percent),
        vw: clampMagnitude(-off.vw),
        vh: clampMagnitude(-off.vh),
      );
    }
    return off;
  }

  return CssList([place(k0, o0), place(k1, o1)]);
}

final _One _sizeAxis = _any([
  _len(negative: false),
  _kw(['auto']),
]);

CssValue? _backgroundSize(CssValueReader r, _Comps cs) {
  if (cs.length == 1) {
    final id = r.keyword(cs.single);
    if (id == CssKeywords.cover || id == CssKeywords.contain) {
      return CssKeyword(id!);
    }
    if (id == CssKeywords.auto) return const CssKeyword(CssKeywords.auto);
  }
  if (cs.isEmpty || cs.length > 2) return null;
  final w = _sizeAxis(r, cs[0]);
  final h = cs.length == 2
      ? _sizeAxis(r, cs[1])
      : const CssKeyword(CssKeywords.auto);
  if (w == null || h == null) return null;
  return CssList([w, h]);
}

final _One _image = _any([
  _kw(['none']),
  _url,
]);

const Set<String> _attachment = {'scroll', 'fixed', 'local'};
const Set<String> _boxes = {'border-box', 'padding-box', 'content-box'};

/// `background` de uma camada: cor, imagem, repetição, posição [/ tamanho];
/// `attachment`, `origin` e `clip` aceitos e ignorados.
_Out? _background(CssValueReader r, _Comps cs) {
  CssValue? color, image, repeat, position, size;
  var attachment = false;
  var boxes = 0;
  var i = 0;
  while (i < cs.length) {
    final c = cs[i];
    final ident = r.identLower(c);
    if (ident != null && _repeatSingle.contains(ident)) {
      if (repeat != null) return null;
      var j = i + 1;
      if (j < cs.length) {
        final next = r.identLower(cs[j]);
        if (next != null && _repeatSingle.contains(next)) j++;
      }
      repeat = _backgroundRepeat(r, cs.sublist(i, j));
      if (repeat == null) return null;
      i = j;
      continue;
    }
    if (ident != null && _attachment.contains(ident)) {
      if (attachment) return null;
      attachment = true;
      i++;
      continue;
    }
    if (ident != null && _boxes.contains(ident)) {
      if (++boxes > 2) return null;
      i++;
      continue;
    }
    if (_isPositionKeyword(r.keyword(c)) || r.length(c) != null) {
      if (position != null) return null;
      var j = i;
      while (j < cs.length &&
          (_isPositionKeyword(r.keyword(cs[j])) || r.length(cs[j]) != null)) {
        j++;
      }
      position = _position(r, cs.sublist(i, j));
      if (position == null) return null;
      i = j;
      if (i < cs.length && r.isDelim(cs[i], '/')) {
        var k = i + 1;
        while (k < cs.length &&
            k < i + 3 &&
            (_sizeAxis(r, cs[k]) != null ||
                r.keyword(cs[k]) == CssKeywords.cover ||
                r.keyword(cs[k]) == CssKeywords.contain)) {
          k++;
        }
        size = _backgroundSize(r, cs.sublist(i + 1, k));
        if (size == null) return null;
        i = k;
      }
      continue;
    }
    final img = _image(r, c);
    if (img != null) {
      if (image != null) return null;
      image = img;
      i++;
      continue;
    }
    final col = r.color(c);
    if (col == null || color != null) return null;
    color = col;
    i++;
  }
  return [
    (PropertyId.backgroundColor, color ?? const CssColor(0)),
    (PropertyId.backgroundImage, image ?? const CssKeyword(CssKeywords.none)),
    (
      PropertyId.backgroundRepeat,
      repeat ?? const CssKeyword(CssKeywords.repeat),
    ),
    (
      PropertyId.backgroundPosition,
      position ?? const CssList([CssLengthSpec(), CssLengthSpec()]),
    ),
    (PropertyId.backgroundSize, size ?? const CssKeyword(CssKeywords.auto)),
  ];
}

CssValue? _opacity(CssValueReader r, CssComponent c) {
  final pct = r.percentage(c);
  final v = r.number(c) ?? (pct == null ? null : pct / 100);
  return v == null ? null : CssNumber(v.clamp(0.0, 1.0));
}

// Listas.

final _One _listStyleType = _any([
  _kw([
    'none',
    'disc',
    'circle',
    'square',
    'decimal',
    'decimal-leading-zero',
    'lower-roman',
    'upper-roman',
    'lower-greek',
    'lower-alpha',
    'lower-latin',
    'upper-alpha',
    'upper-latin',
    'armenian',
    'georgian',
    'lower-armenian',
    'upper-armenian',
    'hebrew',
    'cjk-ideographic',
    'cjk-decimal',
    'hiragana',
    'katakana',
    'hiragana-iroha',
    'katakana-iroha',
    'disclosure-open',
    'disclosure-closed',
  ]),
  _string,
]);

final _One _listStylePosition = _kw(['inside', 'outside']);

/// `list-style`: `type || position || image`; `none` preenche o tipo e/ou a
/// imagem que faltarem.
_Out? _listStyle(CssValueReader r, _Comps cs) {
  if (cs.length > 3) return null;
  CssValue? type, position, image;
  var nones = 0;
  for (final c in cs) {
    if (r.keyword(c) == CssKeywords.none) {
      nones++;
      continue;
    }
    final p = _listStylePosition(r, c);
    if (p != null) {
      if (position != null) return null;
      position = p;
      continue;
    }
    final u = _url(r, c);
    if (u != null) {
      if (image != null) return null;
      image = u;
      continue;
    }
    final t = _listStyleType(r, c);
    if (t == null || type != null) return null;
    type = t;
  }
  const none = CssKeyword(CssKeywords.none);
  if (nones > 0 && type == null) {
    type = none;
    nones--;
  }
  if (nones > 0 && image == null) {
    image = none;
    nones--;
  }
  if (nones > 0) return null;
  return [
    (PropertyId.listStyleType, type ?? const CssKeyword(CssKeywords.disc)),
    (
      PropertyId.listStylePosition,
      position ?? const CssKeyword(CssKeywords.outside),
    ),
    (PropertyId.listStyleImage, image ?? none),
  ];
}

CssValue? _borderSpacing(CssValueReader r, _Comps cs) {
  if (cs.isEmpty || cs.length > 2) return null;
  final h = r.length(cs[0], percent: false, negative: false);
  final v = cs.length == 2
      ? r.length(cs[1], percent: false, negative: false)
      : h;
  if (h == null || v == null) return null;
  return CssList([h, v]);
}

// Conteúdo.

const Set<int> _counterStyles = {
  CssKeywords.none,
  CssKeywords.disc,
  CssKeywords.circle,
  CssKeywords.square,
  CssKeywords.decimal,
  CssKeywords.decimalLeadingZero,
  CssKeywords.lowerRoman,
  CssKeywords.upperRoman,
  CssKeywords.lowerGreek,
  CssKeywords.lowerAlpha,
  CssKeywords.lowerLatin,
  CssKeywords.upperAlpha,
  CssKeywords.upperLatin,
  CssKeywords.armenian,
  CssKeywords.georgian,
  CssKeywords.lowerArmenian,
  CssKeywords.upperArmenian,
  CssKeywords.hebrew,
  CssKeywords.cjkIdeographic,
  CssKeywords.cjkDecimal,
  CssKeywords.hiragana,
  CssKeywords.katakana,
  CssKeywords.hiraganaIroha,
  CssKeywords.katakanaIroha,
  CssKeywords.disclosureOpen,
  CssKeywords.disclosureClosed,
};

CssValue? _content(CssValueReader r, _Comps cs) {
  if (cs.length == 1) {
    final id = r.keyword(cs.single);
    if (id == CssKeywords.normal || id == CssKeywords.none) {
      return CssKeyword(id!);
    }
  }
  final items = <ContentItem>[];
  for (final c in cs) {
    final s = r.string(c);
    if (s != null) {
      items.add(ContentText(s));
      continue;
    }
    final quote = switch (r.keyword(c)) {
      CssKeywords.openQuote => QuoteKind.open,
      CssKeywords.closeQuote => QuoteKind.close,
      CssKeywords.noOpenQuote => QuoteKind.noOpen,
      CssKeywords.noCloseQuote => QuoteKind.noClose,
      _ => null,
    };
    if (quote != null) {
      items.add(ContentQuote(quote));
      continue;
    }
    final fn = r.functionLower(c);
    if (fn == null || c.end == c.innerEnd) return null;
    final args = r.inner(c);
    if (fn == 'attr') {
      if (args.length != 1 || args.single.type != CssTokenType.ident) {
        return null;
      }
      items.add(ContentAttr(args.single.value));
    } else if (fn == 'counter') {
      if (args.isEmpty || args.first.type != CssTokenType.ident) return null;
      var style = CssKeywords.decimal;
      if (args.length == 3) {
        if (args[1].type != CssTokenType.comma ||
            args[2].type != CssTokenType.ident) {
          return null;
        }
        final id = CssKeywords.idOf(args[2].value);
        if (id == null || !_counterStyles.contains(id)) return null;
        style = id;
      } else if (args.length != 1) {
        return null;
      }
      items.add(ContentCounter(args.first.value, style));
    } else {
      return null;
    }
  }
  return CssContent(items);
}

CssValue? _quotes(CssValueReader r, _Comps cs) {
  if (cs.length == 1) {
    final id = r.keyword(cs.single);
    if (id == CssKeywords.none || id == CssKeywords.auto) {
      return CssKeyword(id!);
    }
  }
  if (cs.isEmpty || cs.length.isOdd) return null;
  final pairs = <(String, String)>[];
  for (var i = 0; i < cs.length; i += 2) {
    final a = r.string(cs[i]);
    final b = r.string(cs[i + 1]);
    if (a == null || b == null) return null;
    pairs.add((a, b));
  }
  return CssQuotes(pairs);
}

/// `counter-increment`/`counter-reset`: `none | [nome inteiro?]+`.
CssValue? Function(CssValueReader, _Comps) _counters(int defaultValue) =>
    (r, cs) {
      if (cs.length == 1 && r.keyword(cs.single) == CssKeywords.none) {
        return const CssKeyword(CssKeywords.none);
      }
      final out = <(String, int)>[];
      var i = 0;
      while (i < cs.length) {
        final t = r.token(cs[i]);
        if (t.type != CssTokenType.ident) return null;
        final lower = asciiLower(t.value);
        if (lower == 'none' || lower == 'default') return null;
        var v = defaultValue;
        if (i + 1 < cs.length &&
            r.token(cs[i + 1]).type != CssTokenType.ident) {
          final n = r.integer(cs[i + 1]);
          if (n == null) return null;
          v = n;
          i++;
        }
        out.add((t.value, v));
        i++;
      }
      return CssCounterChanges(out);
    };

// --- Tabela ------------------------------------------------------------------

const List<int> _marginIds = [
  PropertyId.marginTop,
  PropertyId.marginRight,
  PropertyId.marginBottom,
  PropertyId.marginLeft,
];

const List<int> _paddingIds = [
  PropertyId.paddingTop,
  PropertyId.paddingRight,
  PropertyId.paddingBottom,
  PropertyId.paddingLeft,
];

final _One _margin = _any([
  _len(),
  _kw(['auto']),
]);
final _One _padding = _len(negative: false);

final Map<String, _Prop> _properties = {
  // Fonte.
  'font-family': _multi(PropertyId.fontFamily, _fontFamily),
  'font-size': _single(PropertyId.fontSize, _fontSize),
  'font-style': _single(PropertyId.fontStyle, _fontStyle),
  'font-weight': _single(PropertyId.fontWeight, _fontWeight),
  'font-variant': _single(PropertyId.fontVariant, _fontVariant),
  'font-variant-numeric': _multi(
    PropertyId.fontVariantNumeric,
    _fontVariantNumeric,
  ),
  'font': _Prop([
    PropertyId.fontStyle,
    PropertyId.fontVariant,
    PropertyId.fontWeight,
    PropertyId.fontSize,
    PropertyId.lineHeight,
    PropertyId.fontFamily,
    PropertyId.fontVariantNumeric,
  ], _font),
  // Texto.
  'line-height': _single(PropertyId.lineHeight, _lineHeight),
  'text-align': _single(
    PropertyId.textAlign,
    _kw(['start', 'end', 'left', 'right', 'center', 'justify', 'match-parent']),
  ),
  'text-indent': _single(PropertyId.textIndent, _len()),
  'text-transform': _single(
    PropertyId.textTransform,
    _kw([
      'none',
      'capitalize',
      'uppercase',
      'lowercase',
      'full-width',
      'full-size-kana',
    ]),
  ),
  'text-decoration': _Prop([
    PropertyId.textDecorationLine,
    PropertyId.textDecorationStyle,
    PropertyId.textDecorationColor,
  ], _textDecoration),
  'text-decoration-line': _multi(
    PropertyId.textDecorationLine,
    _decorationLine,
  ),
  'text-decoration-style': _single(
    PropertyId.textDecorationStyle,
    _decorationStyle,
  ),
  'text-decoration-color': _single(PropertyId.textDecorationColor, _color),
  'letter-spacing': _single(
    PropertyId.letterSpacing,
    _any([
      _kw(['normal']),
      _len(),
    ]),
  ),
  'word-spacing': _single(
    PropertyId.wordSpacing,
    _any([
      _kw(['normal']),
      _len(),
    ]),
  ),
  'white-space': _single(
    PropertyId.whiteSpace,
    _kw(['normal', 'pre', 'nowrap', 'pre-wrap', 'pre-line', 'break-spaces']),
  ),
  'hyphens': _single(PropertyId.hyphens, _kw(['none', 'manual', 'auto'])),
  'vertical-align': _single(
    PropertyId.verticalAlign,
    _any([
      _kw([
        'baseline',
        'sub',
        'super',
        'text-top',
        'text-bottom',
        'middle',
        'top',
        'bottom',
      ]),
      _len(),
    ]),
  ),
  'direction': _single(PropertyId.direction, _kw(['ltr', 'rtl'])),
  'unicode-bidi': _single(
    PropertyId.unicodeBidi,
    _kw([
      'normal',
      'embed',
      'isolate',
      'bidi-override',
      'isolate-override',
      'plaintext',
    ]),
  ),
  'writing-mode': _single(PropertyId.writingMode, _writingMode),
  'text-combine-upright': _single(
    PropertyId.textCombineUpright,
    _kw(['none', 'all']),
  ),
  'hanging-punctuation': _multi(
    PropertyId.hangingPunctuation,
    _hangingPunctuation,
  ),
  'overflow-wrap': _single(
    PropertyId.overflowWrap,
    _kw(['normal', 'break-word', 'anywhere']),
  ),
  'text-emphasis-style': _multi(PropertyId.textEmphasisStyle, _emphasisStyle),
  'text-emphasis-color': _single(PropertyId.textEmphasisColor, _color),
  'text-wrap': _single(
    PropertyId.textWrap,
    _kw(['wrap', 'nowrap', 'balance', 'stable', 'pretty']),
  ),
  // Caixa.
  'display': _single(
    PropertyId.display,
    _kw([
      'none',
      'inline',
      'block',
      'list-item',
      'inline-block',
      'table',
      'inline-table',
      'table-row-group',
      'table-header-group',
      'table-footer-group',
      'table-row',
      'table-column-group',
      'table-column',
      'table-cell',
      'table-caption',
      'flex',
      'inline-flex',
      'grid',
      'inline-grid',
      'flow-root',
      'contents',
      'ruby',
      'ruby-base',
      'ruby-text',
      'ruby-base-container',
      'ruby-text-container',
      'run-in',
    ]),
  ),
  'margin': _box(_marginIds, _margin),
  'margin-top': _single(PropertyId.marginTop, _margin),
  'margin-right': _single(PropertyId.marginRight, _margin),
  'margin-bottom': _single(PropertyId.marginBottom, _margin),
  'margin-left': _single(PropertyId.marginLeft, _margin),
  'padding': _box(_paddingIds, _padding),
  'padding-top': _single(PropertyId.paddingTop, _padding),
  'padding-right': _single(PropertyId.paddingRight, _padding),
  'padding-bottom': _single(PropertyId.paddingBottom, _padding),
  'padding-left': _single(PropertyId.paddingLeft, _padding),
  'border': _border,
  'border-top': _borderSideProp(_borderIds[0]),
  'border-right': _borderSideProp(_borderIds[1]),
  'border-bottom': _borderSideProp(_borderIds[2]),
  'border-left': _borderSideProp(_borderIds[3]),
  'border-width': _box([for (final s in _borderIds) s[0]], _borderWidth),
  'border-style': _box([for (final s in _borderIds) s[1]], _borderStyle),
  'border-color': _box([for (final s in _borderIds) s[2]], _color),
  'border-top-width': _single(PropertyId.borderTopWidth, _borderWidth),
  'border-top-style': _single(PropertyId.borderTopStyle, _borderStyle),
  'border-top-color': _single(PropertyId.borderTopColor, _color),
  'border-right-width': _single(PropertyId.borderRightWidth, _borderWidth),
  'border-right-style': _single(PropertyId.borderRightStyle, _borderStyle),
  'border-right-color': _single(PropertyId.borderRightColor, _color),
  'border-bottom-width': _single(PropertyId.borderBottomWidth, _borderWidth),
  'border-bottom-style': _single(PropertyId.borderBottomStyle, _borderStyle),
  'border-bottom-color': _single(PropertyId.borderBottomColor, _color),
  'border-left-width': _single(PropertyId.borderLeftWidth, _borderWidth),
  'border-left-style': _single(PropertyId.borderLeftStyle, _borderStyle),
  'border-left-color': _single(PropertyId.borderLeftColor, _color),
  'border-radius': _Prop(_radiusIds, _borderRadius),
  'border-top-left-radius': _cornerRadius(PropertyId.borderTopLeftRadius),
  'border-top-right-radius': _cornerRadius(PropertyId.borderTopRightRadius),
  'border-bottom-right-radius': _cornerRadius(
    PropertyId.borderBottomRightRadius,
  ),
  'border-bottom-left-radius': _cornerRadius(PropertyId.borderBottomLeftRadius),
  'width': _single(PropertyId.width, _size),
  'height': _single(PropertyId.height, _size),
  'min-width': _single(PropertyId.minWidth, _size),
  'min-height': _single(PropertyId.minHeight, _size),
  'max-width': _single(PropertyId.maxWidth, _maxSize),
  'max-height': _single(PropertyId.maxHeight, _maxSize),
  'box-sizing': _single(
    PropertyId.boxSizing,
    _kw(['content-box', 'border-box']),
  ),
  'object-fit': _single(
    PropertyId.objectFit,
    _kw(['fill', 'contain', 'cover', 'none', 'scale-down']),
  ),
  // Fluxo.
  'float': _single(
    PropertyId.float,
    _kw(['none', 'left', 'right', 'inline-start', 'inline-end']),
  ),
  'clear': _single(
    PropertyId.clear,
    _kw(['none', 'left', 'right', 'both', 'inline-start', 'inline-end']),
  ),
  'position': _single(
    PropertyId.position,
    _kw(['static', 'relative', 'absolute', 'fixed', 'sticky']),
  ),
  'top': _single(PropertyId.top, _inset),
  'right': _single(PropertyId.right, _inset),
  'bottom': _single(PropertyId.bottom, _inset),
  'left': _single(PropertyId.left, _inset),
  'z-index': _single(
    PropertyId.zIndex,
    _any([
      _kw(['auto']),
      _integer,
    ]),
  ),
  'overflow': _single(
    PropertyId.overflow,
    _kw(['visible', 'hidden', 'clip', 'scroll', 'auto']),
  ),
  'flex-direction': _single(
    PropertyId.flexDirection,
    _kw(['row', 'row-reverse', 'column', 'column-reverse']),
  ),
  'justify-content': _single(
    PropertyId.justifyContent,
    _kw([
      'normal',
      'flex-start',
      'flex-end',
      'start',
      'end',
      'center',
      'left',
      'right',
      'space-between',
      'space-around',
      'space-evenly',
      'stretch',
    ]),
  ),
  'align-items': _single(
    PropertyId.alignItems,
    _kw([
      'normal',
      'stretch',
      'flex-start',
      'flex-end',
      'start',
      'end',
      'center',
      'baseline',
      'self-start',
      'self-end',
    ]),
  ),
  // Cor e fundo.
  'color': _single(PropertyId.color, _color),
  'background-color': _single(PropertyId.backgroundColor, _color),
  'background-image': _single(PropertyId.backgroundImage, _image),
  'background-repeat': _multi(PropertyId.backgroundRepeat, _backgroundRepeat),
  'background-position': _multi(PropertyId.backgroundPosition, _position),
  'background-size': _multi(PropertyId.backgroundSize, _backgroundSize),
  'background': _Prop([
    PropertyId.backgroundColor,
    PropertyId.backgroundImage,
    PropertyId.backgroundRepeat,
    PropertyId.backgroundPosition,
    PropertyId.backgroundSize,
  ], _background),
  'opacity': _single(PropertyId.opacity, _opacity),
  // Listas.
  'list-style': _Prop([
    PropertyId.listStyleType,
    PropertyId.listStylePosition,
    PropertyId.listStyleImage,
  ], _listStyle),
  'list-style-type': _single(PropertyId.listStyleType, _listStyleType),
  'list-style-position': _single(
    PropertyId.listStylePosition,
    _listStylePosition,
  ),
  'list-style-image': _single(PropertyId.listStyleImage, _image),
  // Tabela.
  'border-collapse': _single(
    PropertyId.borderCollapse,
    _kw(['collapse', 'separate']),
  ),
  'border-spacing': _multi(PropertyId.borderSpacing, _borderSpacing),
  'caption-side': _single(PropertyId.captionSide, _kw(['top', 'bottom'])),
  'table-layout': _single(PropertyId.tableLayout, _kw(['auto', 'fixed'])),
  'empty-cells': _single(PropertyId.emptyCells, _kw(['show', 'hide'])),
  // Fragmentação.
  'break-before': _single(PropertyId.breakBefore, _breakOuter),
  'break-after': _single(PropertyId.breakAfter, _breakOuter),
  'break-inside': _single(
    PropertyId.breakInside,
    _kw(['auto', 'avoid', 'avoid-page', 'avoid-column', 'avoid-region']),
  ),
  'orphans': _single(PropertyId.orphans, _positiveInteger),
  'widows': _single(PropertyId.widows, _positiveInteger),
  // Conteúdo.
  'content': _multi(PropertyId.content, _content),
  'quotes': _multi(PropertyId.quotes, _quotes),
  'counter-increment': _multi(PropertyId.counterIncrement, _counters(1)),
  'counter-reset': _multi(PropertyId.counterReset, _counters(0)),
  'visibility': _single(
    PropertyId.visibility,
    _kw(['visible', 'hidden', 'collapse']),
  ),
};

final _One _breakOuter = _kw([
  'auto',
  'avoid',
  'always',
  'all',
  'avoid-page',
  'page',
  'left',
  'right',
  'recto',
  'verso',
  'avoid-column',
  'column',
  'avoid-region',
  'region',
]);
