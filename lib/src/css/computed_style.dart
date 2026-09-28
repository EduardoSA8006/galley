/// Estilo computado de um elemento (spec do CSS §3): só as propriedades da
/// tabela de §7.1, classificadas nas três classes de doc/02 §2. Interno.
library;

import 'package:meta/meta.dart';

enum CssDisplay { inline, block, listItem, none }

enum CssWhiteSpace { normal, pre, nowrap, preWrap, preLine }

enum CssDirection { ltr, rtl }

enum CssTextAlign { start, center, end }

/// A palavra computada, que é o que herda (no CSS Text, um filho `rtl` de um
/// pai com `left` continua `left`). `justify` vira `start` no parse.
enum CssAlignKeyword { start, end, left, right, center }

enum CssVerticalAlign { baseline, sup, sub }

enum CssListStyleType {
  disc,
  circle,
  square,
  decimal,
  lowerAlpha,
  upperAlpha,
  lowerRoman,
  upperRoman,
  none,
}

/// `breakInside` nunca é `page`.
enum CssBreak { auto, page, avoid }

enum CssFontStyle { normal, italic }

enum CssFontWeight { normal, bold }

enum CssFontVariant { normal, smallCaps }

enum CssTextTransform { none, uppercase, lowercase, capitalize }

/// Direção do tamanho em relação ao pai; o IR acumula (doc/03 §4,
/// `InlineAttr.sizeSmaller`/`sizeLarger`).
enum CssFontSizeStep { same, smaller, larger }

enum CssLengthUnit { em, percent }

/// As três classes de doc/02 §2. `globalAppearance` nunca chega ao
/// `ComputedStyle`: é a classe das propriedades ignoradas em silêncio.
enum StyleClass { structure, relativeTypography, globalAppearance }

/// Comprimento de `width`/`height`, em [0, 100] (spec do CSS §7.1).
@immutable
final class CssLength {
  const CssLength(this.value, this.unit);

  final double value;
  final CssLengthUnit unit;

  @override
  bool operator ==(Object other) =>
      other is CssLength && other.value == value && other.unit == unit;

  @override
  int get hashCode => Object.hash(value, unit);

  @override
  String toString() => '$value${unit == CssLengthUnit.em ? 'em' : '%'}';
}

/// Quatro lados, em em.
@immutable
final class EmEdges {
  const EmEdges(this.top, this.right, this.bottom, this.left);

  static const EmEdges zero = EmEdges(0, 0, 0, 0);

  final double top, right, bottom, left;

  @override
  bool operator ==(Object other) =>
      other is EmEdges &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom &&
      other.left == left;

  @override
  int get hashCode => Object.hash(top, right, bottom, left);

  @override
  String toString() => 'EmEdges($top, $right, $bottom, $left)';
}

@immutable
final class ComputedStyle {
  /// Os padrões são os valores iniciais de §7.1.
  const ComputedStyle({
    this.display = CssDisplay.inline,
    this.whiteSpace = CssWhiteSpace.normal,
    this.direction = CssDirection.ltr,
    this.verticalAlign = CssVerticalAlign.baseline,
    this.listStyleType = CssListStyleType.disc,
    this.breakBefore = CssBreak.auto,
    this.breakAfter = CssBreak.auto,
    this.breakInside = CssBreak.auto,
    this.width,
    this.height,
    this.alignKeyword = CssAlignKeyword.start,
    this.underline = false,
    this.lineThrough = false,
    this.fontStyle = CssFontStyle.normal,
    this.weight = 400.0,
    this.fontVariant = CssFontVariant.normal,
    this.textTransform = CssTextTransform.none,
    this.fontSizeStep = CssFontSizeStep.same,
    this.margin = EmEdges.zero,
    this.padding = EmEdges.zero,
    this.textIndent = 0,
  });

  /// Valores iniciais de todas as propriedades (§7.1).
  static const ComputedStyle initial = ComputedStyle();

  // Classe 1 — estrutura: o usuário nunca sobrepõe (doc/02 §2).
  final CssDisplay display;
  final CssWhiteSpace whiteSpace;
  final CssDirection direction;
  final CssVerticalAlign verticalAlign;
  final CssListStyleType listStyleType;
  final CssBreak breakBefore, breakAfter, breakInside;

  /// `null` = `auto`.
  final CssLength? width, height;

  // Classe 2 — tipografia relativa.

  /// A palavra que herda; [textAlign] é ela resolvida.
  final CssAlignKeyword alignKeyword;

  /// Decorações em vigor: as do elemento mais as propagadas dos ancestrais
  /// (CSS Text Decoration 3 §2.1; spec do CSS §10.5).
  final bool underline, lineThrough;
  final CssFontStyle fontStyle;

  /// 1–1000, fracionário, o que herda (`bolder`/`lighter` do CSS Fonts 4
  /// §2.2 comparam o peso do pai sem arredondar: 349,5 + `bolder` = 400).
  final double weight;
  final CssFontVariant fontVariant;
  final CssTextTransform textTransform;

  /// Relativo ao pai; não herda.
  final CssFontSizeStep fontSizeStep;
  final EmEdges margin, padding;

  /// Em em, em [-4, 8].
  final double textIndent;

  /// [alignKeyword] resolvido pela [direction] deste elemento: `left` é
  /// `start` em `ltr` e `end` em `rtl`; `right`, o contrário.
  CssTextAlign get textAlign => switch (alignKeyword) {
    CssAlignKeyword.start => CssTextAlign.start,
    CssAlignKeyword.end => CssTextAlign.end,
    CssAlignKeyword.center => CssTextAlign.center,
    CssAlignKeyword.left =>
      direction == CssDirection.ltr ? CssTextAlign.start : CssTextAlign.end,
    CssAlignKeyword.right =>
      direction == CssDirection.ltr ? CssTextAlign.end : CssTextAlign.start,
  };

  /// `bold` se [weight] ≥ 600.
  CssFontWeight get fontWeight =>
      weight >= 600 ? CssFontWeight.bold : CssFontWeight.normal;

  @override
  bool operator ==(Object other) =>
      other is ComputedStyle &&
      other.display == display &&
      other.whiteSpace == whiteSpace &&
      other.direction == direction &&
      other.verticalAlign == verticalAlign &&
      other.listStyleType == listStyleType &&
      other.breakBefore == breakBefore &&
      other.breakAfter == breakAfter &&
      other.breakInside == breakInside &&
      other.width == width &&
      other.height == height &&
      other.alignKeyword == alignKeyword &&
      other.underline == underline &&
      other.lineThrough == lineThrough &&
      other.fontStyle == fontStyle &&
      other.weight == weight &&
      other.fontVariant == fontVariant &&
      other.textTransform == textTransform &&
      other.fontSizeStep == fontSizeStep &&
      other.margin == margin &&
      other.padding == padding &&
      other.textIndent == textIndent;

  @override
  int get hashCode => Object.hashAll([
    display,
    whiteSpace,
    direction,
    verticalAlign,
    listStyleType,
    breakBefore,
    breakAfter,
    breakInside,
    width,
    height,
    alignKeyword,
    underline,
    lineThrough,
    fontStyle,
    weight,
    fontVariant,
    textTransform,
    fontSizeStep,
    margin,
    padding,
    textIndent,
  ]);

  @override
  String toString() =>
      'ComputedStyle(${display.name}, ${whiteSpace.name}, ${direction.name}, '
      '${verticalAlign.name}, ${listStyleType.name}, ${breakBefore.name}/'
      '${breakAfter.name}/${breakInside.name}, $width x $height, '
      '${alignKeyword.name}, u=$underline s=$lineThrough, ${fontStyle.name}, '
      '$weight, ${fontVariant.name}, ${textTransform.name}, '
      '${fontSizeStep.name}, m=$margin, p=$padding, indent=$textIndent)';
}
