import 'package:meta/meta.dart';

/// Maior módulo de qualquer número guardado num [CssValue] (comprimentos,
/// coeficientes e números). Valores maiores, inclusive os que saem de
/// `calc()`, são limitados a ±[kCssMaxMagnitude]; nunca há NaN nem infinito.
const double kCssMaxMagnitude = 1e9;

/// Valor de uma propriedade, já interpretado na leitura da folha.
///
/// Todas as variantes têm igualdade por valor.
@immutable
sealed class CssValue {
  const CssValue();
}

/// Palavra-chave (id de [CssKeywords]).
final class CssKeyword extends CssValue {
  /// Cria o valor da palavra-chave [id].
  const CssKeyword(this.id);

  /// Id em [CssKeywords].
  final int id;

  @override
  bool operator ==(Object other) => other is CssKeyword && other.id == id;

  @override
  int get hashCode => Object.hash(CssKeyword, id);

  @override
  String toString() => 'CssKeyword(${CssKeywords.nameOf(id)})';
}

/// Comprimento **especificado**, na forma linear
/// `px + em·em + ex·ex + rem·rem + percent·% + vw·vw + vh·vh`.
///
/// As unidades absolutas viram px na leitura (1pt = 4/3 px, 1pc = 16 px,
/// 1in = 96 px, 1cm = 96/2,54 px, 1mm = 1cm/10, 1Q = 1cm/40); `ch` conta
/// como 0,5 em e vai para o coeficiente [ex]. `calc()` também produz esta
/// forma. Os coeficientes são finitos e limitados a ±[kCssMaxMagnitude].
final class CssLengthSpec extends CssValue {
  /// Cria um comprimento especificado.
  const CssLengthSpec({
    this.px = 0,
    this.em = 0,
    this.ex = 0,
    this.rem = 0,
    this.percent = 0,
    this.vw = 0,
    this.vh = 0,
  });

  /// Parte absoluta, em px lógicos.
  final double px;

  /// Coeficiente de `em` (tamanho da fonte do elemento).
  final double em;

  /// Coeficiente de `ex` (e de `ch`).
  final double ex;

  /// Coeficiente de `rem` (tamanho da fonte da raiz).
  final double rem;

  /// Coeficiente de `%` (base depende da propriedade).
  final double percent;

  /// Coeficiente de `vw`.
  final double vw;

  /// Coeficiente de `vh`.
  final double vh;

  @override
  bool operator ==(Object other) =>
      other is CssLengthSpec &&
      other.px == px &&
      other.em == em &&
      other.ex == ex &&
      other.rem == rem &&
      other.percent == percent &&
      other.vw == vw &&
      other.vh == vh;

  @override
  int get hashCode =>
      Object.hash(CssLengthSpec, px, em, ex, rem, percent, vw, vh);

  @override
  String toString() =>
      'CssLengthSpec(px: $px, em: $em, ex: $ex, rem: $rem, '
      'percent: $percent, vw: $vw, vh: $vh)';
}

/// Comprimento **calculado**: `px + percent·% + vw·vw + vh·vh`, com as
/// unidades relativas à fonte já resolvidas. `%`, `vw` e `vh` ficam
/// simbólicos até o layout.
final class CssLength extends CssValue {
  /// Cria um comprimento calculado.
  const CssLength({this.px = 0, this.percent = 0, this.vw = 0, this.vh = 0});

  /// Parte absoluta, em px lógicos.
  final double px;

  /// Coeficiente de `%`.
  final double percent;

  /// Coeficiente de `vw`.
  final double vw;

  /// Coeficiente de `vh`.
  final double vh;

  /// Se o comprimento não depende do layout (só px).
  bool get isAbsolute => percent == 0 && vw == 0 && vh == 0;

  @override
  bool operator ==(Object other) =>
      other is CssLength &&
      other.px == px &&
      other.percent == percent &&
      other.vw == vw &&
      other.vh == vh;

  @override
  int get hashCode => Object.hash(CssLength, px, percent, vw, vh);

  @override
  String toString() =>
      'CssLength(px: $px, percent: $percent, vw: $vw, vh: $vh)';
}

/// Número sem unidade (fator de `line-height`, `z-index`, peso da fonte...).
final class CssNumber extends CssValue {
  /// Cria um número.
  const CssNumber(this.value);

  /// O número.
  final double value;

  @override
  bool operator ==(Object other) => other is CssNumber && other.value == value;

  @override
  int get hashCode => Object.hash(CssNumber, value);

  @override
  String toString() => 'CssNumber($value)';
}

/// Cor em ARGB de 32 bits (`0xAARRGGBB`).
final class CssColor extends CssValue {
  /// Cria uma cor.
  const CssColor(this.argb);

  /// A cor, `0xAARRGGBB`.
  final int argb;

  @override
  bool operator ==(Object other) => other is CssColor && other.argb == argb;

  @override
  int get hashCode => Object.hash(CssColor, argb);

  @override
  String toString() =>
      'CssColor(0x${argb.toRadixString(16).padLeft(8, '0').toUpperCase()})';
}

/// Nome de uma família de fontes.
@immutable
final class FontFamilyName {
  /// Cria o nome; [generic] para as famílias genéricas (`serif`,
  /// `monospace`...), escritas sem aspas.
  const FontFamilyName(this.name, {this.generic = false});

  /// Nome como escrito (genéricas em minúsculas).
  final String name;

  /// Se é uma família genérica.
  final bool generic;

  @override
  bool operator ==(Object other) =>
      other is FontFamilyName && other.name == name && other.generic == generic;

  @override
  int get hashCode => Object.hash(name, generic);

  @override
  String toString() => generic ? '$name(generic)' : '"$name"';
}

/// Lista de famílias de fontes, em ordem de preferência.
final class CssFontFamilies extends CssValue {
  /// Cria a lista.
  const CssFontFamilies(this.families);

  /// As famílias.
  final List<FontFamilyName> families;

  @override
  bool operator ==(Object other) =>
      other is CssFontFamilies && listEquals(other.families, families);

  @override
  int get hashCode => Object.hash(CssFontFamilies, Object.hashAll(families));

  @override
  String toString() => 'CssFontFamilies($families)';
}

/// Texto entre aspas (ex.: forma de `text-emphasis-style`, marcador de
/// `list-style-type`).
final class CssString extends CssValue {
  /// Cria o texto.
  const CssString(this.value);

  /// O texto.
  final String value;

  @override
  bool operator ==(Object other) => other is CssString && other.value == value;

  @override
  int get hashCode => Object.hash(CssString, value);

  @override
  String toString() => 'CssString("$value")';
}

/// Referência a um recurso do livro, já resolvida para o caminho no zip.
final class CssUrl extends CssValue {
  /// Cria a referência.
  const CssUrl(this.path);

  /// Caminho do recurso no zip.
  final String path;

  @override
  bool operator ==(Object other) => other is CssUrl && other.path == path;

  @override
  int get hashCode => Object.hash(CssUrl, path);

  @override
  String toString() => 'CssUrl($path)';
}

/// Tipo de aspa em `content`.
enum QuoteKind {
  /// `open-quote`.
  open,

  /// `close-quote`.
  close,

  /// `no-open-quote`.
  noOpen,

  /// `no-close-quote`.
  noClose,
}

/// Item de `content`.
@immutable
sealed class ContentItem {
  const ContentItem();
}

/// Texto literal.
final class ContentText extends ContentItem {
  /// Cria o item.
  const ContentText(this.text);

  /// O texto.
  final String text;

  @override
  bool operator ==(Object other) => other is ContentText && other.text == text;

  @override
  int get hashCode => Object.hash(ContentText, text);

  @override
  String toString() => 'ContentText("$text")';
}

/// Aspa (`open-quote`, `close-quote`...).
final class ContentQuote extends ContentItem {
  /// Cria o item.
  const ContentQuote(this.kind);

  /// O tipo de aspa.
  final QuoteKind kind;

  @override
  bool operator ==(Object other) => other is ContentQuote && other.kind == kind;

  @override
  int get hashCode => Object.hash(ContentQuote, kind);

  @override
  String toString() => 'ContentQuote($kind)';
}

/// Valor de um atributo do elemento (`attr(nome)`).
final class ContentAttr extends ContentItem {
  /// Cria o item.
  const ContentAttr(this.name);

  /// Nome do atributo.
  final String name;

  @override
  bool operator ==(Object other) => other is ContentAttr && other.name == name;

  @override
  int get hashCode => Object.hash(ContentAttr, name);

  @override
  String toString() => 'ContentAttr($name)';
}

/// Valor de um contador (`counter(nome, estilo)`).
final class ContentCounter extends ContentItem {
  /// Cria o item; [style] é o id em [CssKeywords] de um estilo de
  /// `list-style-type` (padrão `decimal`).
  const ContentCounter(this.name, this.style);

  /// Nome do contador.
  final String name;

  /// Estilo de numeração (id em [CssKeywords]).
  final int style;

  @override
  bool operator ==(Object other) =>
      other is ContentCounter && other.name == name && other.style == style;

  @override
  int get hashCode => Object.hash(ContentCounter, name, style);

  @override
  String toString() => 'ContentCounter($name, ${CssKeywords.nameOf(style)})';
}

/// Valor de `content` feito de itens.
final class CssContent extends CssValue {
  /// Cria o valor.
  const CssContent(this.items);

  /// Os itens, em ordem.
  final List<ContentItem> items;

  @override
  bool operator ==(Object other) =>
      other is CssContent && listEquals(other.items, items);

  @override
  int get hashCode => Object.hash(CssContent, Object.hashAll(items));

  @override
  String toString() => 'CssContent($items)';
}

/// Pares de aspas de `quotes` (abertura, fechamento), por nível.
final class CssQuotes extends CssValue {
  /// Cria o valor.
  const CssQuotes(this.pairs);

  /// Os pares, do nível mais externo ao mais interno.
  final List<(String, String)> pairs;

  @override
  bool operator ==(Object other) =>
      other is CssQuotes && listEquals(other.pairs, pairs);

  @override
  int get hashCode => Object.hash(CssQuotes, Object.hashAll(pairs));

  @override
  String toString() => 'CssQuotes($pairs)';
}

/// Mudanças de contadores (`counter-increment`, `counter-reset`): nome e
/// valor.
final class CssCounterChanges extends CssValue {
  /// Cria o valor.
  const CssCounterChanges(this.changes);

  /// Os pares (nome, valor), em ordem.
  final List<(String, int)> changes;

  @override
  bool operator ==(Object other) =>
      other is CssCounterChanges && listEquals(other.changes, changes);

  @override
  int get hashCode => Object.hash(CssCounterChanges, Object.hashAll(changes));

  @override
  String toString() => 'CssCounterChanges($changes)';
}

/// Lista de valores (ex.: `text-decoration-line: underline overline`,
/// posição x/y de `background-position`).
final class CssList extends CssValue {
  /// Cria a lista.
  const CssList(this.items);

  /// Os valores, em ordem.
  final List<CssValue> items;

  @override
  bool operator ==(Object other) =>
      other is CssList && listEquals(other.items, items);

  @override
  int get hashCode => Object.hash(CssList, Object.hashAll(items));

  @override
  String toString() => 'CssList($items)';
}

/// Igualdade elemento a elemento de duas listas.
bool listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// [s] com as letras ASCII em minúsculas (as demais ficam como estão).
String asciiLower(String s) {
  var i = 0;
  for (; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c >= 0x41 && c <= 0x5A) break;
  }
  if (i == s.length) return s;
  final out = StringBuffer(s.substring(0, i));
  for (; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    out.writeCharCode(c >= 0x41 && c <= 0x5A ? c + 32 : c);
  }
  return out.toString();
}

/// Palavras-chave de CSS conhecidas pelo motor, como ids inteiros.
///
/// A busca ([idOf]) não diferencia caixa ASCII: `RED`, `Red` e `red` dão o
/// mesmo id. Os ids valem só dentro do processo (não são persistidos).
abstract final class CssKeywords {
  /// `inherit`.
  static const int inherit = 0;

  /// `initial`.
  static const int initial = 1;

  /// `unset`.
  static const int unset = 2;

  /// `none`.
  static const int none = 3;

  /// `auto`.
  static const int auto = 4;

  /// `normal`.
  static const int normal = 5;

  /// `inline`.
  static const int inline = 6;

  /// `block`.
  static const int block = 7;

  /// `list-item`.
  static const int listItem = 8;

  /// `inline-block`.
  static const int inlineBlock = 9;

  /// `table`.
  static const int table = 10;

  /// `inline-table`.
  static const int inlineTable = 11;

  /// `table-row-group`.
  static const int tableRowGroup = 12;

  /// `table-header-group`.
  static const int tableHeaderGroup = 13;

  /// `table-footer-group`.
  static const int tableFooterGroup = 14;

  /// `table-row`.
  static const int tableRow = 15;

  /// `table-column-group`.
  static const int tableColumnGroup = 16;

  /// `table-column`.
  static const int tableColumn = 17;

  /// `table-cell`.
  static const int tableCell = 18;

  /// `table-caption`.
  static const int tableCaption = 19;

  /// `flex`.
  static const int flex = 20;

  /// `inline-flex`.
  static const int inlineFlex = 21;

  /// `grid`.
  static const int grid = 22;

  /// `inline-grid`.
  static const int inlineGrid = 23;

  /// `flow-root`.
  static const int flowRoot = 24;

  /// `contents`.
  static const int contents = 25;

  /// `ruby`.
  static const int ruby = 26;

  /// `ruby-base`.
  static const int rubyBase = 27;

  /// `ruby-text`.
  static const int rubyText = 28;

  /// `ruby-base-container`.
  static const int rubyBaseContainer = 29;

  /// `ruby-text-container`.
  static const int rubyTextContainer = 30;

  /// `run-in`.
  static const int runIn = 31;

  /// `start`.
  static const int start = 32;

  /// `end`.
  static const int end = 33;

  /// `left`.
  static const int left = 34;

  /// `right`.
  static const int right = 35;

  /// `center`.
  static const int center = 36;

  /// `justify`.
  static const int justify = 37;

  /// `match-parent`.
  static const int matchParent = 38;

  /// `italic`.
  static const int italic = 39;

  /// `oblique`.
  static const int oblique = 40;

  /// `bold`.
  static const int bold = 41;

  /// `bolder`.
  static const int bolder = 42;

  /// `lighter`.
  static const int lighter = 43;

  /// `xx-small`.
  static const int xxSmall = 44;

  /// `x-small`.
  static const int xSmall = 45;

  /// `small`.
  static const int small = 46;

  /// `medium`.
  static const int medium = 47;

  /// `large`.
  static const int large = 48;

  /// `x-large`.
  static const int xLarge = 49;

  /// `xx-large`.
  static const int xxLarge = 50;

  /// `xxx-large`.
  static const int xxxLarge = 51;

  /// `smaller`.
  static const int smaller = 52;

  /// `larger`.
  static const int larger = 53;

  /// `small-caps`.
  static const int smallCaps = 54;

  /// `all-small-caps`.
  static const int allSmallCaps = 55;

  /// `petite-caps`.
  static const int petiteCaps = 56;

  /// `all-petite-caps`.
  static const int allPetiteCaps = 57;

  /// `unicase`.
  static const int unicase = 58;

  /// `titling-caps`.
  static const int titlingCaps = 59;

  /// `lining-nums`.
  static const int liningNums = 60;

  /// `oldstyle-nums`.
  static const int oldstyleNums = 61;

  /// `proportional-nums`.
  static const int proportionalNums = 62;

  /// `tabular-nums`.
  static const int tabularNums = 63;

  /// `diagonal-fractions`.
  static const int diagonalFractions = 64;

  /// `stacked-fractions`.
  static const int stackedFractions = 65;

  /// `ordinal`.
  static const int ordinal = 66;

  /// `slashed-zero`.
  static const int slashedZero = 67;

  /// `capitalize`.
  static const int capitalize = 68;

  /// `uppercase`.
  static const int uppercase = 69;

  /// `lowercase`.
  static const int lowercase = 70;

  /// `full-width`.
  static const int fullWidth = 71;

  /// `full-size-kana`.
  static const int fullSizeKana = 72;

  /// `underline`.
  static const int underline = 73;

  /// `overline`.
  static const int overline = 74;

  /// `line-through`.
  static const int lineThrough = 75;

  /// `blink`.
  static const int blink = 76;

  /// `solid`.
  static const int solid = 77;

  /// `double`.
  static const int doubleKeyword = 78;

  /// `dotted`.
  static const int dotted = 79;

  /// `dashed`.
  static const int dashed = 80;

  /// `wavy`.
  static const int wavy = 81;

  /// `pre`.
  static const int pre = 82;

  /// `nowrap`.
  static const int nowrap = 83;

  /// `pre-wrap`.
  static const int preWrap = 84;

  /// `pre-line`.
  static const int preLine = 85;

  /// `break-spaces`.
  static const int breakSpaces = 86;

  /// `manual`.
  static const int manual = 87;

  /// `baseline`.
  static const int baseline = 88;

  /// `sub`.
  static const int sub = 89;

  /// `super`.
  static const int superKeyword = 90;

  /// `text-top`.
  static const int textTop = 91;

  /// `text-bottom`.
  static const int textBottom = 92;

  /// `middle`.
  static const int middle = 93;

  /// `top`.
  static const int top = 94;

  /// `bottom`.
  static const int bottom = 95;

  /// `ltr`.
  static const int ltr = 96;

  /// `rtl`.
  static const int rtl = 97;

  /// `embed`.
  static const int embed = 98;

  /// `isolate`.
  static const int isolate = 99;

  /// `bidi-override`.
  static const int bidiOverride = 100;

  /// `isolate-override`.
  static const int isolateOverride = 101;

  /// `plaintext`.
  static const int plaintext = 102;

  /// `horizontal-tb`.
  static const int horizontalTb = 103;

  /// `vertical-rl`.
  static const int verticalRl = 104;

  /// `vertical-lr`.
  static const int verticalLr = 105;

  /// `sideways-rl`.
  static const int sidewaysRl = 106;

  /// `sideways-lr`.
  static const int sidewaysLr = 107;

  /// `all`.
  static const int all = 108;

  /// `first`.
  static const int first = 109;

  /// `force-end`.
  static const int forceEnd = 110;

  /// `allow-end`.
  static const int allowEnd = 111;

  /// `last`.
  static const int last = 112;

  /// `break-word`.
  static const int breakWord = 113;

  /// `anywhere`.
  static const int anywhere = 114;

  /// `filled`.
  static const int filled = 115;

  /// `open`.
  static const int open = 116;

  /// `dot`.
  static const int dot = 117;

  /// `circle`.
  static const int circle = 118;

  /// `double-circle`.
  static const int doubleCircle = 119;

  /// `triangle`.
  static const int triangle = 120;

  /// `sesame`.
  static const int sesame = 121;

  /// `wrap`.
  static const int wrap = 122;

  /// `balance`.
  static const int balance = 123;

  /// `stable`.
  static const int stable = 124;

  /// `pretty`.
  static const int pretty = 125;

  /// `hidden`.
  static const int hidden = 126;

  /// `groove`.
  static const int groove = 127;

  /// `ridge`.
  static const int ridge = 128;

  /// `inset`.
  static const int inset = 129;

  /// `outset`.
  static const int outset = 130;

  /// `thin`.
  static const int thin = 131;

  /// `thick`.
  static const int thick = 132;

  /// `min-content`.
  static const int minContent = 133;

  /// `max-content`.
  static const int maxContent = 134;

  /// `fit-content`.
  static const int fitContent = 135;

  /// `content-box`.
  static const int contentBox = 136;

  /// `border-box`.
  static const int borderBox = 137;

  /// `padding-box`.
  static const int paddingBox = 138;

  /// `fill`.
  static const int fill = 139;

  /// `contain`.
  static const int contain = 140;

  /// `cover`.
  static const int cover = 141;

  /// `scale-down`.
  static const int scaleDown = 142;

  /// `inline-start`.
  static const int inlineStart = 143;

  /// `inline-end`.
  static const int inlineEnd = 144;

  /// `both`.
  static const int both = 145;

  /// `static`.
  static const int staticKeyword = 146;

  /// `relative`.
  static const int relative = 147;

  /// `absolute`.
  static const int absolute = 148;

  /// `fixed`.
  static const int fixed = 149;

  /// `sticky`.
  static const int sticky = 150;

  /// `visible`.
  static const int visible = 151;

  /// `clip`.
  static const int clip = 152;

  /// `scroll`.
  static const int scroll = 153;

  /// `row`.
  static const int row = 154;

  /// `row-reverse`.
  static const int rowReverse = 155;

  /// `column`.
  static const int column = 156;

  /// `column-reverse`.
  static const int columnReverse = 157;

  /// `flex-start`.
  static const int flexStart = 158;

  /// `flex-end`.
  static const int flexEnd = 159;

  /// `space-between`.
  static const int spaceBetween = 160;

  /// `space-around`.
  static const int spaceAround = 161;

  /// `space-evenly`.
  static const int spaceEvenly = 162;

  /// `stretch`.
  static const int stretch = 163;

  /// `self-start`.
  static const int selfStart = 164;

  /// `self-end`.
  static const int selfEnd = 165;

  /// `repeat`.
  static const int repeat = 166;

  /// `repeat-x`.
  static const int repeatX = 167;

  /// `repeat-y`.
  static const int repeatY = 168;

  /// `no-repeat`.
  static const int noRepeat = 169;

  /// `space`.
  static const int space = 170;

  /// `round`.
  static const int round = 171;

  /// `local`.
  static const int local = 172;

  /// `disc`.
  static const int disc = 173;

  /// `square`.
  static const int square = 174;

  /// `decimal`.
  static const int decimal = 175;

  /// `decimal-leading-zero`.
  static const int decimalLeadingZero = 176;

  /// `lower-roman`.
  static const int lowerRoman = 177;

  /// `upper-roman`.
  static const int upperRoman = 178;

  /// `lower-greek`.
  static const int lowerGreek = 179;

  /// `lower-alpha`.
  static const int lowerAlpha = 180;

  /// `lower-latin`.
  static const int lowerLatin = 181;

  /// `upper-alpha`.
  static const int upperAlpha = 182;

  /// `upper-latin`.
  static const int upperLatin = 183;

  /// `armenian`.
  static const int armenian = 184;

  /// `georgian`.
  static const int georgian = 185;

  /// `lower-armenian`.
  static const int lowerArmenian = 186;

  /// `upper-armenian`.
  static const int upperArmenian = 187;

  /// `hebrew`.
  static const int hebrew = 188;

  /// `cjk-ideographic`.
  static const int cjkIdeographic = 189;

  /// `cjk-decimal`.
  static const int cjkDecimal = 190;

  /// `hiragana`.
  static const int hiragana = 191;

  /// `katakana`.
  static const int katakana = 192;

  /// `hiragana-iroha`.
  static const int hiraganaIroha = 193;

  /// `katakana-iroha`.
  static const int katakanaIroha = 194;

  /// `disclosure-open`.
  static const int disclosureOpen = 195;

  /// `disclosure-closed`.
  static const int disclosureClosed = 196;

  /// `inside`.
  static const int inside = 197;

  /// `outside`.
  static const int outside = 198;

  /// `collapse`.
  static const int collapse = 199;

  /// `separate`.
  static const int separate = 200;

  /// `show`.
  static const int show = 201;

  /// `hide`.
  static const int hide = 202;

  /// `avoid`.
  static const int avoid = 203;

  /// `always`.
  static const int always = 204;

  /// `avoid-page`.
  static const int avoidPage = 205;

  /// `page`.
  static const int page = 206;

  /// `recto`.
  static const int recto = 207;

  /// `verso`.
  static const int verso = 208;

  /// `avoid-column`.
  static const int avoidColumn = 209;

  /// `avoid-region`.
  static const int avoidRegion = 210;

  /// `region`.
  static const int region = 211;

  /// `open-quote`.
  static const int openQuote = 212;

  /// `close-quote`.
  static const int closeQuote = 213;

  /// `no-open-quote`.
  static const int noOpenQuote = 214;

  /// `no-close-quote`.
  static const int noCloseQuote = 215;

  /// `currentcolor`.
  static const int currentcolor = 216;

  /// `transparent`.
  static const int transparent = 217;

  /// Quantidade de palavras-chave.
  static const int count = 218;

  static const List<String> _names = [
    'inherit',
    'initial',
    'unset',
    'none',
    'auto',
    'normal',
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
    'start',
    'end',
    'left',
    'right',
    'center',
    'justify',
    'match-parent',
    'italic',
    'oblique',
    'bold',
    'bolder',
    'lighter',
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
    'small-caps',
    'all-small-caps',
    'petite-caps',
    'all-petite-caps',
    'unicase',
    'titling-caps',
    'lining-nums',
    'oldstyle-nums',
    'proportional-nums',
    'tabular-nums',
    'diagonal-fractions',
    'stacked-fractions',
    'ordinal',
    'slashed-zero',
    'capitalize',
    'uppercase',
    'lowercase',
    'full-width',
    'full-size-kana',
    'underline',
    'overline',
    'line-through',
    'blink',
    'solid',
    'double',
    'dotted',
    'dashed',
    'wavy',
    'pre',
    'nowrap',
    'pre-wrap',
    'pre-line',
    'break-spaces',
    'manual',
    'baseline',
    'sub',
    'super',
    'text-top',
    'text-bottom',
    'middle',
    'top',
    'bottom',
    'ltr',
    'rtl',
    'embed',
    'isolate',
    'bidi-override',
    'isolate-override',
    'plaintext',
    'horizontal-tb',
    'vertical-rl',
    'vertical-lr',
    'sideways-rl',
    'sideways-lr',
    'all',
    'first',
    'force-end',
    'allow-end',
    'last',
    'break-word',
    'anywhere',
    'filled',
    'open',
    'dot',
    'circle',
    'double-circle',
    'triangle',
    'sesame',
    'wrap',
    'balance',
    'stable',
    'pretty',
    'hidden',
    'groove',
    'ridge',
    'inset',
    'outset',
    'thin',
    'thick',
    'min-content',
    'max-content',
    'fit-content',
    'content-box',
    'border-box',
    'padding-box',
    'fill',
    'contain',
    'cover',
    'scale-down',
    'inline-start',
    'inline-end',
    'both',
    'static',
    'relative',
    'absolute',
    'fixed',
    'sticky',
    'visible',
    'clip',
    'scroll',
    'row',
    'row-reverse',
    'column',
    'column-reverse',
    'flex-start',
    'flex-end',
    'space-between',
    'space-around',
    'space-evenly',
    'stretch',
    'self-start',
    'self-end',
    'repeat',
    'repeat-x',
    'repeat-y',
    'no-repeat',
    'space',
    'round',
    'local',
    'disc',
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
    'inside',
    'outside',
    'collapse',
    'separate',
    'show',
    'hide',
    'avoid',
    'always',
    'avoid-page',
    'page',
    'recto',
    'verso',
    'avoid-column',
    'avoid-region',
    'region',
    'open-quote',
    'close-quote',
    'no-open-quote',
    'no-close-quote',
    'currentcolor',
    'transparent',
  ];

  static final Map<String, int> _ids = {
    for (var i = 0; i < _names.length; i++) _names[i]: i,
  };

  /// Id de [name] (sem diferença de caixa ASCII), ou `null` se a palavra
  /// não for conhecida.
  static int? idOf(String name) => _ids[asciiLower(name)];

  /// Nome (minúsculo) da palavra-chave [id].
  static String nameOf(int id) => _names[id];
}
