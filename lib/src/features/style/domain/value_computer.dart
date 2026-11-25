import 'dart:math' as math;

import 'computed_style.dart';
import 'css_value.dart';
import 'matched_document.dart';
import 'properties.dart';
import 'selector.dart';
import 'stylesheet.dart';

/// Tamanho de fonte inicial (`medium`), em px, base da raiz e de `rem` na
/// raiz.
const double kInitialFontSize = 16;

/// Maior tamanho de fonte calculado, em px (Revisão 4: `em`/`%` aninhados
/// não crescem sem limite).
const double kMaxFontSize = 10000;

/// Pares de aspas do valor inicial de `quotes` (`auto`).
const CssQuotes kDefaultQuotes = CssQuotes([('“', '”'), ('‘', '’')]);

/// Mapa "família em minúsculas → nome interno" das [fontFaces] do
/// documento, para [translateBookFamilies] (spec §8.8).
Map<String, String> bookFamilyNames(List<FontFaceRule> fontFaces) => {
  for (final f in fontFaces) f.family.toLowerCase(): f.internalFamily,
};

/// [value] com as famílias (não genéricas) que casam, sem diferença de
/// caixa, com uma `@font-face` do documento trocadas pelo nome interno do
/// livro ([internalByName], de [bookFamilyNames]); o mesmo objeto se nada
/// muda.
CssFontFamilies translateBookFamilies(
  CssFontFamilies value,
  Map<String, String> internalByName,
) {
  if (internalByName.isEmpty) return value;
  List<FontFamilyName>? out;
  final families = value.families;
  for (var i = 0; i < families.length; i++) {
    final f = families[i];
    final internal = f.generic ? null : internalByName[f.name.toLowerCase()];
    if (internal == null) continue;
    out ??= List.of(families);
    out[i] = FontFamilyName(internal);
  }
  return out == null ? value : CssFontFamilies(List.unmodifiable(out));
}

/// Calcula valores (especificado → calculado) com herança (spec §8.5).
///
/// Um por documento: guarda o tamanho de fonte da raiz (para `rem`) e o
/// mapa das famílias do livro.
final class ValueComputer {
  /// Cria o calculador; [internalFamilies] vem de [bookFamilyNames].
  ValueComputer({Map<String, String> internalFamilies = const {}})
    : _families = internalFamilies;

  final Map<String, String> _families;

  /// Tamanho de fonte calculado da raiz, base de `rem` (antes da raiz,
  /// [kInitialFontSize]). Quem percorre o documento atualiza depois de
  /// calcular a raiz.
  double rootFontSize = kInitialFontSize;

  /// Valores calculados de cada propriedade quando nada é declarado e não
  /// há herança.
  static final List<CssValue> initialValues = List.unmodifiable([
    for (var p = 0; p < kPropertyCount; p++)
      _computeInitial(p, propertyInfo(p).initial),
  ]);

  /// Valores calculados do elemento (ou do pseudo-elemento [pseudo]) com
  /// as declarações vencedoras [set], herdando de [parent] (`null` na
  /// raiz). [isRoot] liga as regras da raiz (`display` blocado).
  List<CssValue> compute(
    CascadedValues set, {
    required ComputedStyle? parent,
    bool isRoot = false,
    PseudoElement? pseudo,
  }) {
    final inherited = parent?.values ?? initialValues;
    final out = List<CssValue>.of(initialValues, growable: false);

    // `font-size` primeiro: as demais unidades dependem dele.
    final parentSize = parent == null
        ? kInitialFontSize
        : (inherited[PropertyId.fontSize] as CssLength).px;
    final fontSize = _fontSize(
      set.valueOf(PropertyId.fontSize),
      parentSize,
      isRoot ? kInitialFontSize : rootFontSize,
    );
    out[PropertyId.fontSize] = CssLength(px: fontSize);
    final rem = isRoot ? kInitialFontSize : rootFontSize;

    for (var p = 0; p < kPropertyCount; p++) {
      if (p == PropertyId.fontSize) continue;
      final info = propertyInfo(p);
      final specified = set.valueOf(p);
      CssValue value;
      if (specified == null) {
        value = info.inherited ? inherited[p] : initialValues[p];
      } else if (specified is CssKeyword && _isCssWide(specified.id)) {
        value = switch (specified.id) {
          CssKeywords.inherit => inherited[p],
          CssKeywords.initial => initialValues[p],
          _ => info.inherited ? inherited[p] : initialValues[p],
        };
      } else {
        value =
            _computeSpecified(p, specified, fontSize, rem, inherited) ??
            initialValues[p];
      }
      out[p] = value;
    }

    _fixUp(out, isRoot: isRoot, pseudo: pseudo);
    return out;
  }

  /// Valor calculado de [specified] (já sem `inherit`/`initial`/`unset`);
  /// `null` se o resultado não for finito (vale o inicial).
  CssValue? _computeSpecified(
    int p,
    CssValue specified,
    double fontSize,
    double rem,
    List<CssValue> inherited,
  ) => switch (specified) {
    CssLengthSpec() => _length(
      specified,
      fontSize,
      rem,
      nonNegative: _nonNegative.contains(p),
      percentOfFont: p == PropertyId.lineHeight,
    ),
    CssList(:final items) => _list(items, fontSize, rem, p),
    CssKeyword(:final id) => _keyword(p, id, inherited),
    CssFontFamilies() => translateBookFamilies(specified, _families),
    CssNumber(:final value) => value.isFinite ? specified : null,
    _ => specified,
  };

  CssValue? _list(List<CssValue> items, double fontSize, double rem, int p) {
    final out = <CssValue>[];
    for (final item in items) {
      final v = item is CssLengthSpec
          ? _length(
              item,
              fontSize,
              rem,
              nonNegative: _nonNegative.contains(p),
              percentOfFont: false,
            )
          : item;
      if (v == null) return null;
      out.add(v);
    }
    return CssList(List.unmodifiable(out));
  }

  CssValue _keyword(int p, int id, List<CssValue> inherited) {
    switch (p) {
      case PropertyId.color when id == CssKeywords.currentcolor:
        // `color: currentcolor` é a cor herdada.
        return inherited[PropertyId.color];
      case PropertyId.fontWeight
          when id == CssKeywords.bolder || id == CssKeywords.lighter:
        final parent = (inherited[PropertyId.fontWeight] as CssNumber).value;
        return CssNumber(
          id == CssKeywords.bolder ? _bolder(parent) : _lighter(parent),
        );
      case PropertyId.quotes when id == CssKeywords.auto:
        return kDefaultQuotes;
    }
    return CssKeyword(id);
  }

  /// Regras que dependem de mais de uma propriedade.
  static void _fixUp(
    List<CssValue> out, {
    required bool isRoot,
    PseudoElement? pseudo,
  }) {
    // Largura da borda é 0 com estilo `none`/`hidden`.
    for (final (width, style) in _borderSides) {
      final s = out[style];
      if (s is CssKeyword &&
          (s.id == CssKeywords.none || s.id == CssKeywords.hidden)) {
        out[width] = const CssLength();
      }
    }
    // `position` absoluto/fixo anula `float`; os dois e a raiz blocam o
    // `display` (CSS 2.1 §9.7, CSS Display 3 §2.7).
    final position = (out[PropertyId.position] as CssKeyword).id;
    final positioned =
        position == CssKeywords.absolute || position == CssKeywords.fixed;
    if (positioned) out[PropertyId.float] = const CssKeyword(CssKeywords.none);
    final floated =
        (out[PropertyId.float] as CssKeyword).id != CssKeywords.none;
    if (positioned || floated || isRoot) {
      final display = (out[PropertyId.display] as CssKeyword).id;
      final blocked = blockify(display, isRoot: isRoot);
      if (blocked != display) out[PropertyId.display] = CssKeyword(blocked);
    }
    // `content: normal` calcula para `none` em `::before`/`::after`.
    if (pseudo == PseudoElement.before || pseudo == PseudoElement.after) {
      final c = out[PropertyId.content];
      if (c is CssKeyword && c.id == CssKeywords.normal) {
        out[PropertyId.content] = const CssKeyword(CssKeywords.none);
      }
    }
  }

  static CssValue _computeInitial(int p, CssValue initial) {
    if (p == PropertyId.fontSize) return const CssLength(px: kInitialFontSize);
    if (p == PropertyId.quotes) return kDefaultQuotes;
    return switch (initial) {
      CssLengthSpec() => _length(
        initial,
        kInitialFontSize,
        kInitialFontSize,
        nonNegative: false,
        percentOfFont: false,
      )!,
      CssList(:final items) => CssList(
        List.unmodifiable([
          for (final i in items)
            i is CssLengthSpec
                ? _length(
                    i,
                    kInitialFontSize,
                    kInitialFontSize,
                    nonNegative: false,
                    percentOfFont: false,
                  )!
                : i,
        ]),
      ),
      _ => initial,
    };
  }
}

bool _isCssWide(int id) =>
    id == CssKeywords.inherit ||
    id == CssKeywords.initial ||
    id == CssKeywords.unset;

/// `display` blocado de [display] (CSS Display 3 §2.7): internos de tabela
/// e de ruby, `inline`, `run-in` e `inline-block` viram `block`; as formas
/// `inline-*` viram as de bloco. Na raiz, `contents` também vira `block`.
int blockify(int display, {bool isRoot = false}) => switch (display) {
  CssKeywords.inlineTable => CssKeywords.table,
  CssKeywords.inlineFlex => CssKeywords.flex,
  CssKeywords.inlineGrid => CssKeywords.grid,
  CssKeywords.inline ||
  CssKeywords.inlineBlock ||
  CssKeywords.runIn ||
  CssKeywords.tableRowGroup ||
  CssKeywords.tableHeaderGroup ||
  CssKeywords.tableFooterGroup ||
  CssKeywords.tableRow ||
  CssKeywords.tableColumnGroup ||
  CssKeywords.tableColumn ||
  CssKeywords.tableCell ||
  CssKeywords.tableCaption ||
  CssKeywords.ruby ||
  CssKeywords.rubyBase ||
  CssKeywords.rubyText ||
  CssKeywords.rubyBaseContainer ||
  CssKeywords.rubyTextContainer => CssKeywords.block,
  CssKeywords.contents when isRoot => CssKeywords.block,
  _ => display,
};

/// Propriedades que não aceitam valor negativo: um `calc()` absoluto que dê
/// negativo é limitado a 0 (com termos simbólicos, o layout limita).
const Set<int> _nonNegative = {
  PropertyId.lineHeight,
  PropertyId.paddingTop,
  PropertyId.paddingRight,
  PropertyId.paddingBottom,
  PropertyId.paddingLeft,
  PropertyId.borderTopWidth,
  PropertyId.borderRightWidth,
  PropertyId.borderBottomWidth,
  PropertyId.borderLeftWidth,
  PropertyId.borderTopLeftRadius,
  PropertyId.borderTopRightRadius,
  PropertyId.borderBottomRightRadius,
  PropertyId.borderBottomLeftRadius,
  PropertyId.width,
  PropertyId.height,
  PropertyId.minWidth,
  PropertyId.minHeight,
  PropertyId.maxWidth,
  PropertyId.maxHeight,
  PropertyId.backgroundSize,
  PropertyId.borderSpacing,
};

/// (largura, estilo) de cada lado da borda.
const List<(int, int)> _borderSides = [
  (PropertyId.borderTopWidth, PropertyId.borderTopStyle),
  (PropertyId.borderRightWidth, PropertyId.borderRightStyle),
  (PropertyId.borderBottomWidth, PropertyId.borderBottomStyle),
  (PropertyId.borderLeftWidth, PropertyId.borderLeftStyle),
];

/// Tamanhos das palavras-chave absolutas pelo CSS Fonts 4 sobre 16 px.
double? _absoluteSize(int id) => switch (id) {
  CssKeywords.xxSmall => 9.6,
  CssKeywords.xSmall => 12,
  CssKeywords.small => 14.2222,
  CssKeywords.medium => 16,
  CssKeywords.large => 19.2,
  CssKeywords.xLarge => 24,
  CssKeywords.xxLarge => 32,
  CssKeywords.xxxLarge => 48,
  _ => null,
};

/// `font-size` calculado em px, limitado a [0, [kMaxFontSize]].
///
/// `em`, `ex` (0,5 em) e `%` são sobre o tamanho do pai; `rem`, sobre o da
/// raiz. Termos `vw`/`vh` não têm base no estilo (não há página aqui) e são
/// ignorados.
double _fontSize(CssValue? specified, double parent, double root) {
  double size;
  switch (specified) {
    case null:
      size = parent;
    case CssKeyword(:final id):
      size = switch (id) {
        CssKeywords.initial => kInitialFontSize,
        CssKeywords.larger => parent * 1.2,
        CssKeywords.smaller => parent / 1.2,
        _ => _absoluteSize(id) ?? parent, // inherit, unset
      };
    case CssLengthSpec():
      size =
          specified.px +
          specified.em * parent +
          specified.ex * 0.5 * parent +
          specified.rem * root +
          specified.percent / 100 * parent;
    default:
      size = parent;
  }
  if (!size.isFinite) return kInitialFontSize;
  return size.clamp(0, kMaxFontSize).toDouble();
}

/// Comprimento calculado: `em`, `ex` e `rem` viram px; `%` (exceto em
/// [percentOfFont], que é sobre a fonte), `vw` e `vh` ficam simbólicos.
/// Coeficientes limitados a ±[kCssMaxMagnitude]; `null` se não finito.
CssLength? _length(
  CssLengthSpec s,
  double fontSize,
  double rem, {
  required bool nonNegative,
  required bool percentOfFont,
}) {
  var px = s.px + s.em * fontSize + s.ex * 0.5 * fontSize + s.rem * rem;
  var percent = s.percent;
  if (percentOfFont) {
    px += percent / 100 * fontSize;
    percent = 0;
  }
  if (!px.isFinite || !percent.isFinite || !s.vw.isFinite || !s.vh.isFinite) {
    return null;
  }
  px = _clamp(px);
  if (nonNegative && px < 0 && percent == 0 && s.vw == 0 && s.vh == 0) {
    px = 0;
  }
  return CssLength(
    px: px == 0 ? 0 : px,
    percent: _clamp(percent),
    vw: _clamp(s.vw),
    vh: _clamp(s.vh),
  );
}

double _clamp(double v) =>
    math.max(-kCssMaxMagnitude, math.min(kCssMaxMagnitude, v));

/// `bolder` pelo CSS Fonts 4 (tabela de pesos relativos).
double _bolder(double w) {
  if (w < 350) return 400;
  if (w < 550) return 700;
  if (w < 900) return 900;
  return w;
}

/// `lighter` pelo CSS Fonts 4 (tabela de pesos relativos).
double _lighter(double w) {
  if (w < 100) return w;
  if (w < 550) return 100;
  if (w < 750) return 400;
  return 700;
}
