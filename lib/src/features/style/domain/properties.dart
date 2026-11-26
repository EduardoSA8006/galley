import 'package:meta/meta.dart';

import 'css_value.dart';

/// Dados fixos de uma propriedade longhand.
@immutable
final class PropertyInfo {
  /// Cria os dados.
  const PropertyInfo(
    this.name, {
    required this.inherited,
    required this.initial,
  });

  /// Nome CSS (minúsculo).
  final String name;

  /// Se o valor é herdado por padrão.
  final bool inherited;

  /// Valor inicial (especificado).
  final CssValue initial;

  @override
  String toString() => 'PropertyInfo($name)';
}

/// Dados da propriedade [id] (um id de [PropertyId]).
PropertyInfo propertyInfo(int id) => _infos[id];

/// Ids das propriedades longhand do escopo (índices em [propertyInfo]).
abstract final class PropertyId {
  /// `font-family`.
  static const int fontFamily = 0;

  /// `font-size`.
  static const int fontSize = 1;

  /// `font-style`.
  static const int fontStyle = 2;

  /// `font-weight`.
  static const int fontWeight = 3;

  /// `font-variant`.
  static const int fontVariant = 4;

  /// `font-variant-numeric`.
  static const int fontVariantNumeric = 5;

  /// `line-height`.
  static const int lineHeight = 6;

  /// `text-align`.
  static const int textAlign = 7;

  /// `text-indent`.
  static const int textIndent = 8;

  /// `text-transform`.
  static const int textTransform = 9;

  /// `text-decoration-line`.
  static const int textDecorationLine = 10;

  /// `text-decoration-style`.
  static const int textDecorationStyle = 11;

  /// `text-decoration-color`.
  static const int textDecorationColor = 12;

  /// `letter-spacing`.
  static const int letterSpacing = 13;

  /// `word-spacing`.
  static const int wordSpacing = 14;

  /// `white-space`.
  static const int whiteSpace = 15;

  /// `hyphens`.
  static const int hyphens = 16;

  /// `vertical-align`.
  static const int verticalAlign = 17;

  /// `direction`.
  static const int direction = 18;

  /// `unicode-bidi`.
  static const int unicodeBidi = 19;

  /// `writing-mode`.
  static const int writingMode = 20;

  /// `text-combine-upright`.
  static const int textCombineUpright = 21;

  /// `hanging-punctuation`.
  static const int hangingPunctuation = 22;

  /// `overflow-wrap`.
  static const int overflowWrap = 23;

  /// `text-emphasis-style`.
  static const int textEmphasisStyle = 24;

  /// `text-emphasis-color`.
  static const int textEmphasisColor = 25;

  /// `text-wrap`.
  static const int textWrap = 26;

  /// `display`.
  static const int display = 27;

  /// `margin-top`.
  static const int marginTop = 28;

  /// `margin-right`.
  static const int marginRight = 29;

  /// `margin-bottom`.
  static const int marginBottom = 30;

  /// `margin-left`.
  static const int marginLeft = 31;

  /// `padding-top`.
  static const int paddingTop = 32;

  /// `padding-right`.
  static const int paddingRight = 33;

  /// `padding-bottom`.
  static const int paddingBottom = 34;

  /// `padding-left`.
  static const int paddingLeft = 35;

  /// `border-top-width`.
  static const int borderTopWidth = 36;

  /// `border-top-style`.
  static const int borderTopStyle = 37;

  /// `border-top-color`.
  static const int borderTopColor = 38;

  /// `border-right-width`.
  static const int borderRightWidth = 39;

  /// `border-right-style`.
  static const int borderRightStyle = 40;

  /// `border-right-color`.
  static const int borderRightColor = 41;

  /// `border-bottom-width`.
  static const int borderBottomWidth = 42;

  /// `border-bottom-style`.
  static const int borderBottomStyle = 43;

  /// `border-bottom-color`.
  static const int borderBottomColor = 44;

  /// `border-left-width`.
  static const int borderLeftWidth = 45;

  /// `border-left-style`.
  static const int borderLeftStyle = 46;

  /// `border-left-color`.
  static const int borderLeftColor = 47;

  /// `border-top-left-radius`.
  static const int borderTopLeftRadius = 48;

  /// `border-top-right-radius`.
  static const int borderTopRightRadius = 49;

  /// `border-bottom-right-radius`.
  static const int borderBottomRightRadius = 50;

  /// `border-bottom-left-radius`.
  static const int borderBottomLeftRadius = 51;

  /// `width`.
  static const int width = 52;

  /// `height`.
  static const int height = 53;

  /// `min-width`.
  static const int minWidth = 54;

  /// `min-height`.
  static const int minHeight = 55;

  /// `max-width`.
  static const int maxWidth = 56;

  /// `max-height`.
  static const int maxHeight = 57;

  /// `box-sizing`.
  static const int boxSizing = 58;

  /// `object-fit`.
  static const int objectFit = 59;

  /// `float`.
  static const int float = 60;

  /// `clear`.
  static const int clear = 61;

  /// `position`.
  static const int position = 62;

  /// `top`.
  static const int top = 63;

  /// `right`.
  static const int right = 64;

  /// `bottom`.
  static const int bottom = 65;

  /// `left`.
  static const int left = 66;

  /// `z-index`.
  static const int zIndex = 67;

  /// `overflow`.
  static const int overflow = 68;

  /// `flex-direction`.
  static const int flexDirection = 69;

  /// `justify-content`.
  static const int justifyContent = 70;

  /// `align-items`.
  static const int alignItems = 71;

  /// `color`.
  static const int color = 72;

  /// `background-color`.
  static const int backgroundColor = 73;

  /// `background-image`.
  static const int backgroundImage = 74;

  /// `background-repeat`.
  static const int backgroundRepeat = 75;

  /// `background-position`.
  static const int backgroundPosition = 76;

  /// `background-size`.
  static const int backgroundSize = 77;

  /// `opacity`.
  static const int opacity = 78;

  /// `list-style-type`.
  static const int listStyleType = 79;

  /// `list-style-position`.
  static const int listStylePosition = 80;

  /// `list-style-image`.
  static const int listStyleImage = 81;

  /// `border-collapse`.
  static const int borderCollapse = 82;

  /// `border-spacing`.
  static const int borderSpacing = 83;

  /// `caption-side`.
  static const int captionSide = 84;

  /// `table-layout`.
  static const int tableLayout = 85;

  /// `empty-cells`.
  static const int emptyCells = 86;

  /// `break-before`.
  static const int breakBefore = 87;

  /// `break-after`.
  static const int breakAfter = 88;

  /// `break-inside`.
  static const int breakInside = 89;

  /// `orphans`.
  static const int orphans = 90;

  /// `widows`.
  static const int widows = 91;

  /// `content`.
  static const int content = 92;

  /// `quotes`.
  static const int quotes = 93;

  /// `counter-increment`.
  static const int counterIncrement = 94;

  /// `counter-reset`.
  static const int counterReset = 95;

  /// `visibility`.
  static const int visibility = 96;
}

/// Quantidade de propriedades longhand (ids de 0 a `kPropertyCount - 1`).
const int kPropertyCount = 97;

const List<PropertyInfo> _infos = [
  PropertyInfo(
    'font-family',
    inherited: true,
    initial: CssFontFamilies([FontFamilyName('serif', generic: true)]),
  ),
  PropertyInfo(
    'font-size',
    inherited: true,
    initial: CssKeyword(CssKeywords.medium),
  ),
  PropertyInfo(
    'font-style',
    inherited: true,
    initial: CssKeyword(CssKeywords.normal),
  ),
  PropertyInfo('font-weight', inherited: true, initial: CssNumber(400)),
  PropertyInfo(
    'font-variant',
    inherited: true,
    initial: CssKeyword(CssKeywords.normal),
  ),
  PropertyInfo(
    'font-variant-numeric',
    inherited: true,
    initial: CssKeyword(CssKeywords.normal),
  ),
  PropertyInfo(
    'line-height',
    inherited: true,
    initial: CssKeyword(CssKeywords.normal),
  ),
  PropertyInfo(
    'text-align',
    inherited: true,
    initial: CssKeyword(CssKeywords.start),
  ),
  PropertyInfo('text-indent', inherited: true, initial: CssLengthSpec()),
  PropertyInfo(
    'text-transform',
    inherited: true,
    initial: CssKeyword(CssKeywords.none),
  ),
  PropertyInfo(
    'text-decoration-line',
    inherited: false,
    initial: CssKeyword(CssKeywords.none),
  ),
  PropertyInfo(
    'text-decoration-style',
    inherited: false,
    initial: CssKeyword(CssKeywords.solid),
  ),
  PropertyInfo(
    'text-decoration-color',
    inherited: false,
    initial: CssKeyword(CssKeywords.currentcolor),
  ),
  PropertyInfo(
    'letter-spacing',
    inherited: true,
    initial: CssKeyword(CssKeywords.normal),
  ),
  PropertyInfo(
    'word-spacing',
    inherited: true,
    initial: CssKeyword(CssKeywords.normal),
  ),
  PropertyInfo(
    'white-space',
    inherited: true,
    initial: CssKeyword(CssKeywords.normal),
  ),
  PropertyInfo(
    'hyphens',
    inherited: true,
    initial: CssKeyword(CssKeywords.manual),
  ),
  PropertyInfo(
    'vertical-align',
    inherited: false,
    initial: CssKeyword(CssKeywords.baseline),
  ),
  PropertyInfo(
    'direction',
    inherited: true,
    initial: CssKeyword(CssKeywords.ltr),
  ),
  PropertyInfo(
    'unicode-bidi',
    inherited: false,
    initial: CssKeyword(CssKeywords.normal),
  ),
  PropertyInfo(
    'writing-mode',
    inherited: true,
    initial: CssKeyword(CssKeywords.horizontalTb),
  ),
  PropertyInfo(
    'text-combine-upright',
    inherited: true,
    initial: CssKeyword(CssKeywords.none),
  ),
  PropertyInfo(
    'hanging-punctuation',
    inherited: true,
    initial: CssKeyword(CssKeywords.none),
  ),
  PropertyInfo(
    'overflow-wrap',
    inherited: true,
    initial: CssKeyword(CssKeywords.normal),
  ),
  PropertyInfo(
    'text-emphasis-style',
    inherited: true,
    initial: CssKeyword(CssKeywords.none),
  ),
  PropertyInfo(
    'text-emphasis-color',
    inherited: true,
    initial: CssKeyword(CssKeywords.currentcolor),
  ),
  PropertyInfo(
    'text-wrap',
    inherited: true,
    initial: CssKeyword(CssKeywords.wrap),
  ),
  PropertyInfo(
    'display',
    inherited: false,
    initial: CssKeyword(CssKeywords.inline),
  ),
  PropertyInfo('margin-top', inherited: false, initial: CssLengthSpec()),
  PropertyInfo('margin-right', inherited: false, initial: CssLengthSpec()),
  PropertyInfo('margin-bottom', inherited: false, initial: CssLengthSpec()),
  PropertyInfo('margin-left', inherited: false, initial: CssLengthSpec()),
  PropertyInfo('padding-top', inherited: false, initial: CssLengthSpec()),
  PropertyInfo('padding-right', inherited: false, initial: CssLengthSpec()),
  PropertyInfo('padding-bottom', inherited: false, initial: CssLengthSpec()),
  PropertyInfo('padding-left', inherited: false, initial: CssLengthSpec()),
  PropertyInfo(
    'border-top-width',
    inherited: false,
    initial: CssLengthSpec(px: 3),
  ),
  PropertyInfo(
    'border-top-style',
    inherited: false,
    initial: CssKeyword(CssKeywords.none),
  ),
  PropertyInfo(
    'border-top-color',
    inherited: false,
    initial: CssKeyword(CssKeywords.currentcolor),
  ),
  PropertyInfo(
    'border-right-width',
    inherited: false,
    initial: CssLengthSpec(px: 3),
  ),
  PropertyInfo(
    'border-right-style',
    inherited: false,
    initial: CssKeyword(CssKeywords.none),
  ),
  PropertyInfo(
    'border-right-color',
    inherited: false,
    initial: CssKeyword(CssKeywords.currentcolor),
  ),
  PropertyInfo(
    'border-bottom-width',
    inherited: false,
    initial: CssLengthSpec(px: 3),
  ),
  PropertyInfo(
    'border-bottom-style',
    inherited: false,
    initial: CssKeyword(CssKeywords.none),
  ),
  PropertyInfo(
    'border-bottom-color',
    inherited: false,
    initial: CssKeyword(CssKeywords.currentcolor),
  ),
  PropertyInfo(
    'border-left-width',
    inherited: false,
    initial: CssLengthSpec(px: 3),
  ),
  PropertyInfo(
    'border-left-style',
    inherited: false,
    initial: CssKeyword(CssKeywords.none),
  ),
  PropertyInfo(
    'border-left-color',
    inherited: false,
    initial: CssKeyword(CssKeywords.currentcolor),
  ),
  PropertyInfo(
    'border-top-left-radius',
    inherited: false,
    initial: CssLengthSpec(),
  ),
  PropertyInfo(
    'border-top-right-radius',
    inherited: false,
    initial: CssLengthSpec(),
  ),
  PropertyInfo(
    'border-bottom-right-radius',
    inherited: false,
    initial: CssLengthSpec(),
  ),
  PropertyInfo(
    'border-bottom-left-radius',
    inherited: false,
    initial: CssLengthSpec(),
  ),
  PropertyInfo(
    'width',
    inherited: false,
    initial: CssKeyword(CssKeywords.auto),
  ),
  PropertyInfo(
    'height',
    inherited: false,
    initial: CssKeyword(CssKeywords.auto),
  ),
  PropertyInfo(
    'min-width',
    inherited: false,
    initial: CssKeyword(CssKeywords.auto),
  ),
  PropertyInfo(
    'min-height',
    inherited: false,
    initial: CssKeyword(CssKeywords.auto),
  ),
  PropertyInfo(
    'max-width',
    inherited: false,
    initial: CssKeyword(CssKeywords.none),
  ),
  PropertyInfo(
    'max-height',
    inherited: false,
    initial: CssKeyword(CssKeywords.none),
  ),
  PropertyInfo(
    'box-sizing',
    inherited: false,
    initial: CssKeyword(CssKeywords.contentBox),
  ),
  PropertyInfo(
    'object-fit',
    inherited: false,
    initial: CssKeyword(CssKeywords.fill),
  ),
  PropertyInfo(
    'float',
    inherited: false,
    initial: CssKeyword(CssKeywords.none),
  ),
  PropertyInfo(
    'clear',
    inherited: false,
    initial: CssKeyword(CssKeywords.none),
  ),
  PropertyInfo(
    'position',
    inherited: false,
    initial: CssKeyword(CssKeywords.staticKeyword),
  ),
  PropertyInfo('top', inherited: false, initial: CssKeyword(CssKeywords.auto)),
  PropertyInfo(
    'right',
    inherited: false,
    initial: CssKeyword(CssKeywords.auto),
  ),
  PropertyInfo(
    'bottom',
    inherited: false,
    initial: CssKeyword(CssKeywords.auto),
  ),
  PropertyInfo('left', inherited: false, initial: CssKeyword(CssKeywords.auto)),
  PropertyInfo(
    'z-index',
    inherited: false,
    initial: CssKeyword(CssKeywords.auto),
  ),
  PropertyInfo(
    'overflow',
    inherited: false,
    initial: CssKeyword(CssKeywords.visible),
  ),
  PropertyInfo(
    'flex-direction',
    inherited: false,
    initial: CssKeyword(CssKeywords.row),
  ),
  PropertyInfo(
    'justify-content',
    inherited: false,
    initial: CssKeyword(CssKeywords.normal),
  ),
  PropertyInfo(
    'align-items',
    inherited: false,
    initial: CssKeyword(CssKeywords.normal),
  ),
  PropertyInfo('color', inherited: true, initial: CssColor(0xFF000000)),
  PropertyInfo(
    'background-color',
    inherited: false,
    initial: CssColor(0x00000000),
  ),
  PropertyInfo(
    'background-image',
    inherited: false,
    initial: CssKeyword(CssKeywords.none),
  ),
  PropertyInfo(
    'background-repeat',
    inherited: false,
    initial: CssKeyword(CssKeywords.repeat),
  ),
  PropertyInfo(
    'background-position',
    inherited: false,
    initial: CssList([CssLengthSpec(), CssLengthSpec()]),
  ),
  PropertyInfo(
    'background-size',
    inherited: false,
    initial: CssKeyword(CssKeywords.auto),
  ),
  PropertyInfo('opacity', inherited: false, initial: CssNumber(1)),
  PropertyInfo(
    'list-style-type',
    inherited: true,
    initial: CssKeyword(CssKeywords.disc),
  ),
  PropertyInfo(
    'list-style-position',
    inherited: true,
    initial: CssKeyword(CssKeywords.outside),
  ),
  PropertyInfo(
    'list-style-image',
    inherited: true,
    initial: CssKeyword(CssKeywords.none),
  ),
  PropertyInfo(
    'border-collapse',
    inherited: true,
    initial: CssKeyword(CssKeywords.separate),
  ),
  PropertyInfo(
    'border-spacing',
    inherited: true,
    initial: CssList([CssLengthSpec(), CssLengthSpec()]),
  ),
  PropertyInfo(
    'caption-side',
    inherited: true,
    initial: CssKeyword(CssKeywords.top),
  ),
  PropertyInfo(
    'table-layout',
    inherited: false,
    initial: CssKeyword(CssKeywords.auto),
  ),
  PropertyInfo(
    'empty-cells',
    inherited: true,
    initial: CssKeyword(CssKeywords.show),
  ),
  PropertyInfo(
    'break-before',
    inherited: false,
    initial: CssKeyword(CssKeywords.auto),
  ),
  PropertyInfo(
    'break-after',
    inherited: false,
    initial: CssKeyword(CssKeywords.auto),
  ),
  PropertyInfo(
    'break-inside',
    inherited: false,
    initial: CssKeyword(CssKeywords.auto),
  ),
  PropertyInfo('orphans', inherited: true, initial: CssNumber(2)),
  PropertyInfo('widows', inherited: true, initial: CssNumber(2)),
  PropertyInfo(
    'content',
    inherited: false,
    initial: CssKeyword(CssKeywords.normal),
  ),
  PropertyInfo(
    'quotes',
    inherited: true,
    initial: CssKeyword(CssKeywords.auto),
  ),
  PropertyInfo(
    'counter-increment',
    inherited: false,
    initial: CssKeyword(CssKeywords.none),
  ),
  PropertyInfo(
    'counter-reset',
    inherited: false,
    initial: CssKeyword(CssKeywords.none),
  ),
  PropertyInfo(
    'visibility',
    inherited: true,
    initial: CssKeyword(CssKeywords.visible),
  ),
];
