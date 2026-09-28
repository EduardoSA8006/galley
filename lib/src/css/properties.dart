/// Propriedades da tabela de §7.1 e as degradadas de §7.4 (spec do CSS §7):
/// expansão dos atalhos e tipagem dos valores.
///
/// Linear no tamanho do valor: uma passada junta os componentes de topo (um
/// bloco ou função conta como um componente, sem voltar ao conteúdo dele);
/// cada propriedade olha um número fixo de componentes (`margin` ≤ 4, `font`
/// ≤ 4 prefixos e o tamanho) e para no primeiro que sobra, fora a família
/// do `font` e as listas de palavras, uma passada cada. O nome é buscado num
/// mapa constante; conversão e limite são aritmética.
library;

import 'computed_style.dart';
import 'tokenizer.dart';

enum CssProperty {
  display(StyleClass.structure),
  whiteSpace(StyleClass.structure, inherited: true),
  direction(StyleClass.structure, inherited: true),
  verticalAlign(StyleClass.structure),
  listStyleType(StyleClass.structure, inherited: true),
  breakBefore(StyleClass.structure),
  breakAfter(StyleClass.structure),
  breakInside(StyleClass.structure),
  width(StyleClass.structure),
  height(StyleClass.structure),
  textAlign(StyleClass.relativeTypography, inherited: true),
  textDecoration(StyleClass.relativeTypography),
  fontStyle(StyleClass.relativeTypography, inherited: true),
  fontWeight(StyleClass.relativeTypography, inherited: true),
  fontVariant(StyleClass.relativeTypography, inherited: true),
  textTransform(StyleClass.relativeTypography, inherited: true),
  fontSize(StyleClass.relativeTypography),
  marginTop(StyleClass.relativeTypography),
  marginRight(StyleClass.relativeTypography),
  marginBottom(StyleClass.relativeTypography),
  marginLeft(StyleClass.relativeTypography),
  paddingTop(StyleClass.relativeTypography),
  paddingRight(StyleClass.relativeTypography),
  paddingBottom(StyleClass.relativeTypography),
  paddingLeft(StyleClass.relativeTypography),
  textIndent(StyleClass.relativeTypography, inherited: true),
  // Degradadas (§7.4): participam da cascata, não do ComputedStyle.
  float(StyleClass.structure, degraded: true),
  position(StyleClass.structure, degraded: true),
  columnCount(StyleClass.structure, degraded: true),
  columnWidth(StyleClass.structure, degraded: true),
  writingMode(StyleClass.structure, inherited: true, degraded: true);

  const CssProperty(
    this.styleClass, {
    this.inherited = false,
    this.degraded = false,
  });

  final StyleClass styleClass;

  /// Herda no CSS. `textDecoration` não herda: propaga (§10.5).
  final bool inherited;

  /// Entra na cascata só para emitir `unsupportedLayout` (§10.7).
  final bool degraded;
}

/// Uma declaração já expandida e tipada.
final class Declaration {
  const Declaration(this.property, this.value, {this.important = false});

  final CssProperty property;
  final CssValue value;
  final bool important;

  @override
  String toString() =>
      'Declaration(${property.name}: $value${important ? ' !important' : ''})';
}

sealed class CssValue {
  const CssValue();
}

enum CssWide { inherit, initial, unset }

/// `inherit`, `initial`, `unset`.
final class CssWideKeyword extends CssValue {
  const CssWideKeyword(this.keyword);

  final CssWide keyword;

  @override
  String toString() => keyword.name;
}

/// Palavra já mapeada para o enum da propriedade.
final class CssKeywordValue<E extends Enum> extends CssValue {
  const CssKeywordValue(this.value);

  final E value;

  @override
  String toString() => value.name;
}

/// `list-style-type` com nome desconhecido (resolvido no elemento, §7.1).
final class CssUnknownListStyle extends CssValue {
  const CssUnknownListStyle();

  @override
  String toString() => 'unknown-list-style';
}

/// `font-weight`: [absolute] 1–1000 (fracionário, como no CSS Fonts 4
/// §2.2), ou relativo ao pai ([bolder] ou `lighter`).
final class CssWeightValue extends CssValue {
  const CssWeightValue({this.absolute, this.bolder = false});

  final double? absolute;
  final bool bolder;

  @override
  String toString() {
    final a = absolute;
    if (a == null) return bolder ? 'bolder' : 'lighter';
    return a == a.truncateToDouble() ? '${a.toInt()}' : '$a';
  }
}

/// Margens, padding e `text-indent`: já convertidos e limitados.
final class CssEmValue extends CssValue {
  const CssEmValue(this.em);

  final double em;

  @override
  String toString() => '${em}em';
}

/// `width`/`height`; `null` = `auto`.
final class CssLengthValue extends CssValue {
  const CssLengthValue(this.length);

  final CssLength? length;

  @override
  String toString() => length?.toString() ?? 'auto';
}

/// `font-size` relativo.
final class CssFontSizeValue extends CssValue {
  const CssFontSizeValue(this.step);

  final CssFontSizeStep step;

  @override
  String toString() => step.name;
}

/// `text-decoration(-line)`: as linhas que o próprio elemento declara.
final class CssDecorationValue extends CssValue {
  const CssDecorationValue({this.underline = false, this.lineThrough = false});

  final bool underline, lineThrough;

  @override
  String toString() => 'decoration(u=$underline, s=$lineThrough)';
}

/// Propriedade degradada: se o valor degrada (`float: left`) e a palavra.
final class CssDegradedValue extends CssValue {
  const CssDegradedValue({required this.degrades, required this.keyword});

  final bool degrades;
  final String keyword;

  @override
  String toString() => '$keyword${degrades ? ' (degrada)' : ''}';
}

/// Longhands de cada nome aceito; `inherit`/`initial`/`unset` num atalho
/// valem para todas.
const Map<String, List<CssProperty>> _longhands = {
  'display': [CssProperty.display],
  'white-space': [CssProperty.whiteSpace],
  'direction': [CssProperty.direction],
  'text-align': [CssProperty.textAlign],
  'vertical-align': [CssProperty.verticalAlign],
  'list-style-type': [CssProperty.listStyleType],
  'list-style': [CssProperty.listStyleType],
  'break-before': [CssProperty.breakBefore],
  'page-break-before': [CssProperty.breakBefore],
  'break-after': [CssProperty.breakAfter],
  'page-break-after': [CssProperty.breakAfter],
  'break-inside': [CssProperty.breakInside],
  'page-break-inside': [CssProperty.breakInside],
  'width': [CssProperty.width],
  'height': [CssProperty.height],
  'font-style': [CssProperty.fontStyle],
  'font-weight': [CssProperty.fontWeight],
  'font-variant': [CssProperty.fontVariant],
  'font-variant-caps': [CssProperty.fontVariant],
  'text-transform': [CssProperty.textTransform],
  'text-decoration-line': [CssProperty.textDecoration],
  'text-decoration': [CssProperty.textDecoration],
  'font-size': [CssProperty.fontSize],
  'font': [
    CssProperty.fontStyle,
    CssProperty.fontVariant,
    CssProperty.fontWeight,
    CssProperty.fontSize,
  ],
  'margin-top': [CssProperty.marginTop],
  'margin-right': [CssProperty.marginRight],
  'margin-bottom': [CssProperty.marginBottom],
  'margin-left': [CssProperty.marginLeft],
  'margin': [
    CssProperty.marginTop,
    CssProperty.marginRight,
    CssProperty.marginBottom,
    CssProperty.marginLeft,
  ],
  'padding-top': [CssProperty.paddingTop],
  'padding-right': [CssProperty.paddingRight],
  'padding-bottom': [CssProperty.paddingBottom],
  'padding-left': [CssProperty.paddingLeft],
  'padding': [
    CssProperty.paddingTop,
    CssProperty.paddingRight,
    CssProperty.paddingBottom,
    CssProperty.paddingLeft,
  ],
  'text-indent': [CssProperty.textIndent],
  'float': [CssProperty.float],
  'position': [CssProperty.position],
  'column-count': [CssProperty.columnCount],
  'column-width': [CssProperty.columnWidth],
  'columns': [CssProperty.columnCount, CssProperty.columnWidth],
  'writing-mode': [CssProperty.writingMode],
  '-epub-writing-mode': [CssProperty.writingMode],
  '-webkit-writing-mode': [CssProperty.writingMode],
};

/// Em por unidade (§7.2): base fixa 16px = 1em; `rem` como `em`; `ex` e
/// `ch` como 0,5em (CSS Values 4 §6.1.1, sem métrica de fonte).
const Map<String, double> _emPerUnit = {
  'em': 1,
  'rem': 1,
  'ex': 0.5,
  'ch': 0.5,
  'px': 1 / 16,
  'pt': 1 / 12,
  'pc': 1,
  'in': 6,
  'cm': 96 / 2.54 / 16,
  'mm': 96 / 25.4 / 16,
  'q': 96 / 101.6 / 16,
};

/// Unidades de comprimento válidas no CSS que o galley não converte: tornam
/// um tamanho de fonte absoluto (§7.1) mas não viram `em`.
const Set<String> _otherLengthUnits = {
  'vw', 'vh', 'vmin', 'vmax', 'vi', 'vb', 'lh', 'rlh', 'cap', 'ic', //
  'svw', 'svh', 'lvw', 'lvh', 'dvw', 'dvh',
};

/// Componentes de topo sem espaço: um bloco (`(`, `[`, `{` ou função) conta
/// como o token que o abre, e o conteúdo é saltado.
List<CssToken> _components(List<CssToken> tokens, int start, int end) {
  final out = <CssToken>[];
  var depth = 0;
  for (var i = start; i < end; i++) {
    final t = tokens[i];
    switch (t.type) {
      case CssTokenType.function ||
          CssTokenType.leftParen ||
          CssTokenType.leftBracket ||
          CssTokenType.leftBrace:
        if (depth == 0) out.add(t);
        depth++;
      case CssTokenType.rightParen ||
          CssTokenType.rightBracket ||
          CssTokenType.rightBrace:
        if (depth > 0) {
          depth--;
        } else {
          out.add(t);
        }
      case CssTokenType.whitespace:
        break;
      default:
        if (depth == 0) out.add(t);
    }
  }
  return out;
}

/// Expande e tipa uma declaração. Lista vazia: propriedade fora da tabela
/// ou valor fora do aceito (descarte em silêncio, §5.3). [name] em
/// minúsculas ASCII; [value] sem o `!important`.
List<Declaration> parseDeclaration(
  String name,
  List<CssToken> value, {
  required bool important,
}) {
  final longhands = _longhands[name];
  if (longhands == null) return const [];
  var start = 0, end = value.length;
  while (start < end && value[start].type == CssTokenType.whitespace) {
    start++;
  }
  while (end > start && value[end - 1].type == CssTokenType.whitespace) {
    end--;
  }
  if (start == end) return const [];
  for (var i = start; i < end; i++) {
    final t = value[i];
    if (t.type == CssTokenType.function && cssAsciiEquals(t.value, 'var')) {
      return const [];
    }
  }
  final c = _components(value, start, end);
  if (c.length == 1 && c.first.type == CssTokenType.ident) {
    final word = cssAsciiLower(c.first.value);
    // Sem origem do usuário no galley, voltar à folha padrão aproximaria mal.
    if (word == 'revert' || word == 'revert-layer') return const [];
    final wide = _wideWords[word];
    if (wide != null) {
      return [
        for (final p in longhands)
          Declaration(p, CssWideKeyword(wide), important: important),
      ];
    }
  }
  final parsed = _parse(name, c);
  if (parsed == null) return const [];
  return [for (final (p, v) in parsed) Declaration(p, v, important: important)];
}

const Map<String, CssWide> _wideWords = {
  'inherit': CssWide.inherit,
  'initial': CssWide.initial,
  'unset': CssWide.unset,
};

typedef _Parsed = List<(CssProperty, CssValue)>;

_Parsed? _one(CssProperty p, CssValue? v) => v == null ? null : [(p, v)];

/// Palavra única, em minúsculas; `null` se não é exatamente um `ident`.
String? _keyword(List<CssToken> c) =>
    c.length == 1 && c.first.type == CssTokenType.ident
    ? cssAsciiLower(c.first.value)
    : null;

CssKeywordValue<E>? _mapped<E extends Enum>(
  List<CssToken> c,
  Map<String, E> map,
) {
  final k = _keyword(c);
  if (k == null) return null;
  final v = map[k];
  return v == null ? null : CssKeywordValue<E>(v);
}

_Parsed? _parse(String name, List<CssToken> c) {
  switch (name) {
    case 'display':
      return _one(CssProperty.display, _mapped(c, _display));
    case 'white-space':
      return _one(CssProperty.whiteSpace, _mapped(c, _whiteSpace));
    case 'direction':
      return _one(CssProperty.direction, _mapped(c, _direction));
    case 'text-align':
      return _one(CssProperty.textAlign, _mapped(c, _textAlign));
    case 'vertical-align':
      return _one(CssProperty.verticalAlign, _verticalAlign(c));
    case 'list-style-type':
      return _one(CssProperty.listStyleType, _listStyleType(c));
    case 'list-style':
      return _one(CssProperty.listStyleType, _listStyle(c));
    case 'break-before' || 'break-after':
      return _one(
        name == 'break-before'
            ? CssProperty.breakBefore
            : CssProperty.breakAfter,
        _mapped(c, _breakBetween),
      );
    case 'page-break-before' || 'page-break-after':
      return _one(
        name == 'page-break-before'
            ? CssProperty.breakBefore
            : CssProperty.breakAfter,
        _mapped(c, _pageBreak),
      );
    case 'break-inside':
      return _one(CssProperty.breakInside, _mapped(c, _breakInside));
    case 'page-break-inside':
      return _one(CssProperty.breakInside, _mapped(c, _pageBreakInside));
    case 'width' || 'height':
      return _one(
        name == 'width' ? CssProperty.width : CssProperty.height,
        _size(c),
      );
    case 'font-style':
      return _one(CssProperty.fontStyle, _fontStyle(c));
    case 'font-weight':
      return _one(CssProperty.fontWeight, _fontWeight(c));
    case 'font-variant':
      return _one(CssProperty.fontVariant, _fontVariant(c));
    case 'font-variant-caps':
      return _one(CssProperty.fontVariant, _fontVariantCaps(c));
    case 'text-transform':
      return _one(CssProperty.textTransform, _mapped(c, _textTransform));
    case 'text-decoration-line':
      return _one(CssProperty.textDecoration, _decorationLine(c));
    case 'text-decoration':
      return _one(CssProperty.textDecoration, _decorationShorthand(c));
    case 'font-size':
      if (c.length != 1) return null;
      final size = _fontSize(c.first);
      if (size == null || size is! CssFontSizeValue) return null;
      return [(CssProperty.fontSize, size)];
    case 'font':
      return _font(c);
    case 'margin-top' || 'margin-right' || 'margin-bottom' || 'margin-left':
      return _one(_longhands[name]!.single, _margin(c));
    case 'padding-top' || 'padding-right' || 'padding-bottom' || 'padding-left':
      return _one(_longhands[name]!.single, _padding(c));
    case 'margin' || 'padding':
      return _box(_longhands[name]!, c, name == 'margin' ? _margin : _padding);
    case 'text-indent':
      return _one(CssProperty.textIndent, _textIndent(c));
    case 'float':
      return _one(CssProperty.float, _degraded(c, _float));
    case 'position':
      return _one(CssProperty.position, _degraded(c, _position));
    case 'column-count':
      if (c.length != 1) return null;
      return _one(CssProperty.columnCount, _columnCount(c.first));
    case 'column-width':
      if (c.length != 1) return null;
      return _one(CssProperty.columnWidth, _columnWidth(c.first));
    case 'columns':
      return _columns(c);
    case 'writing-mode' || '-epub-writing-mode' || '-webkit-writing-mode':
      return _one(CssProperty.writingMode, _degraded(c, _writingMode));
  }
  return null;
}

const Map<String, CssDisplay> _display = {
  'inline': CssDisplay.inline,
  'inline-block': CssDisplay.inline,
  'inline-flex': CssDisplay.inline,
  'inline-grid': CssDisplay.inline,
  'inline-table': CssDisplay.inline,
  'block': CssDisplay.block,
  'flex': CssDisplay.block,
  'grid': CssDisplay.block,
  'flow-root': CssDisplay.block,
  'table': CssDisplay.block,
  'table-row-group': CssDisplay.block,
  'table-header-group': CssDisplay.block,
  'table-footer-group': CssDisplay.block,
  'table-row': CssDisplay.block,
  'table-cell': CssDisplay.block,
  'table-column-group': CssDisplay.block,
  'table-column': CssDisplay.block,
  'table-caption': CssDisplay.block,
  'list-item': CssDisplay.listItem,
  'none': CssDisplay.none,
};

const Map<String, CssWhiteSpace> _whiteSpace = {
  'normal': CssWhiteSpace.normal,
  'pre': CssWhiteSpace.pre,
  'nowrap': CssWhiteSpace.nowrap,
  'pre-wrap': CssWhiteSpace.preWrap,
  'pre-line': CssWhiteSpace.preLine,
  'break-spaces': CssWhiteSpace.preWrap,
};

const Map<String, CssDirection> _direction = {
  'ltr': CssDirection.ltr,
  'rtl': CssDirection.rtl,
};

const Map<String, CssAlignKeyword> _textAlign = {
  'left': CssAlignKeyword.left,
  'right': CssAlignKeyword.right,
  'center': CssAlignKeyword.center,
  'justify': CssAlignKeyword.start,
  'start': CssAlignKeyword.start,
  'end': CssAlignKeyword.end,
};

const Map<String, CssVerticalAlign> _verticalAlignWords = {
  'baseline': CssVerticalAlign.baseline,
  'super': CssVerticalAlign.sup,
  'sub': CssVerticalAlign.sub,
  'top': CssVerticalAlign.baseline,
  'text-top': CssVerticalAlign.baseline,
  'middle': CssVerticalAlign.baseline,
  'bottom': CssVerticalAlign.baseline,
  'text-bottom': CssVerticalAlign.baseline,
};

const Map<String, CssListStyleType> _listStyleTypes = {
  'disc': CssListStyleType.disc,
  'circle': CssListStyleType.circle,
  'square': CssListStyleType.square,
  'decimal': CssListStyleType.decimal,
  'lower-alpha': CssListStyleType.lowerAlpha,
  'lower-latin': CssListStyleType.lowerAlpha,
  'upper-alpha': CssListStyleType.upperAlpha,
  'upper-latin': CssListStyleType.upperAlpha,
  'lower-roman': CssListStyleType.lowerRoman,
  'upper-roman': CssListStyleType.upperRoman,
  'none': CssListStyleType.none,
};

const Map<String, CssBreak> _breakBetween = {
  'auto': CssBreak.auto,
  'avoid': CssBreak.avoid,
  'avoid-page': CssBreak.avoid,
  'page': CssBreak.page,
  'left': CssBreak.page,
  'right': CssBreak.page,
  'recto': CssBreak.page,
  'verso': CssBreak.page,
  'always': CssBreak.page,
  'column': CssBreak.auto,
  'avoid-column': CssBreak.auto,
  'region': CssBreak.auto,
  'avoid-region': CssBreak.auto,
};

const Map<String, CssBreak> _pageBreak = {
  'auto': CssBreak.auto,
  'always': CssBreak.page,
  'avoid': CssBreak.avoid,
  'left': CssBreak.page,
  'right': CssBreak.page,
};

const Map<String, CssBreak> _breakInside = {
  'auto': CssBreak.auto,
  'avoid': CssBreak.avoid,
  'avoid-page': CssBreak.avoid,
  'avoid-column': CssBreak.avoid,
  'avoid-region': CssBreak.avoid,
};

const Map<String, CssBreak> _pageBreakInside = {
  'auto': CssBreak.auto,
  'avoid': CssBreak.avoid,
};

const Map<String, CssTextTransform> _textTransform = {
  'none': CssTextTransform.none,
  'uppercase': CssTextTransform.uppercase,
  'lowercase': CssTextTransform.lowercase,
  'capitalize': CssTextTransform.capitalize,
};

bool _finite(double v) => !v.isNaN && !v.isInfinite;

/// Comprimento em em (§7.2). `%` vale ×0,3 (medida de 30em) com
/// [percentAsEm]; senão `null`. `0` sem unidade vale 0; outro número sem
/// unidade, unidade desconhecida, `NaN` e infinito dão `null`.
double? _toEm(CssToken t, {required bool percentAsEm}) {
  double? em;
  switch (t.type) {
    case CssTokenType.dimension:
      final factor = _emPerUnit[t.unit];
      if (factor != null) em = t.number * factor;
    case CssTokenType.percentage:
      if (percentAsEm) em = t.number * 0.3;
    case CssTokenType.number:
      if (t.number == 0) em = 0;
    default:
      break;
  }
  return em != null && _finite(em) ? em : null;
}

double _clamp(double v, double min, double max) =>
    v < min ? min : (v > max ? max : v);

bool _isLength(CssToken t) =>
    (t.type == CssTokenType.dimension &&
        (_emPerUnit.containsKey(t.unit) ||
            _otherLengthUnits.contains(t.unit)) &&
        _finite(t.number)) ||
    (t.type == CssTokenType.number && t.number == 0);

CssValue? _verticalAlign(List<CssToken> c) {
  if (c.length != 1) return null;
  final t = c.first;
  if (t.type == CssTokenType.ident) {
    final v = _verticalAlignWords[cssAsciiLower(t.value)];
    return v == null ? null : CssKeywordValue(v);
  }
  if (_isLength(t) ||
      (t.type == CssTokenType.percentage && _finite(t.number))) {
    return const CssKeywordValue(CssVerticalAlign.baseline);
  }
  return null;
}

CssValue? _listStyleType(List<CssToken> c) {
  if (c.length != 1) return null;
  final t = c.first;
  if (t.type == CssTokenType.string) return const CssUnknownListStyle();
  if (t.type != CssTokenType.ident) return null;
  final v = _listStyleTypes[cssAsciiLower(t.value)];
  return v == null ? const CssUnknownListStyle() : CssKeywordValue(v);
}

/// `list-style` (CSS Lists 3 §3.4): tipo, posição e imagem em qualquer
/// ordem; só o tipo entra. Um `none` vai para o que não foi dado (tipo ou
/// imagem); sem tipo nem `none`, o tipo reinicia em `disc`.
CssValue? _listStyle(List<CssToken> c) {
  if (c.isEmpty || c.length > 3) return null;
  CssValue? type;
  var position = false;
  var image = false;
  var nones = 0;
  for (final t in c) {
    if (t.type == CssTokenType.ident) {
      final v = cssAsciiLower(t.value);
      if (v == 'none') {
        nones++;
      } else if (v == 'inside' || v == 'outside') {
        if (position) {
          // O segundo `inside`/`outside` é um <counter-style-name> (CSS
          // Counter Styles 3 §3.1): tipo desconhecido.
          if (type != null) return null;
          type = const CssUnknownListStyle();
        }
        position = true;
      } else {
        if (type != null) return null;
        final known = _listStyleTypes[v];
        type = known == null
            ? const CssUnknownListStyle()
            : CssKeywordValue(known);
      }
    } else if (t.type == CssTokenType.string) {
      if (type != null) return null;
      type = const CssUnknownListStyle();
    } else if (t.type == CssTokenType.url || t.type == CssTokenType.function) {
      if (image) return null;
      image = true;
    } else {
      return null;
    }
  }
  final free = (type == null ? 1 : 0) + (image ? 0 : 1);
  if (nones > free) return null;
  if (type != null) return type;
  return nones > 0
      ? const CssKeywordValue(CssListStyleType.none)
      : const CssKeywordValue(CssListStyleType.disc);
}

/// `width`/`height`: comprimento ou `%` ≥ 0, limitados a [0, 100]; `auto`.
CssValue? _size(List<CssToken> c) {
  if (c.length != 1) return null;
  final t = c.first;
  if (t.type == CssTokenType.ident) {
    return cssAsciiLower(t.value) == 'auto' ? const CssLengthValue(null) : null;
  }
  if (t.type == CssTokenType.percentage) {
    if (!_finite(t.number) || t.number < 0) return null;
    return CssLengthValue(
      CssLength(_clamp(t.number, 0, 100), CssLengthUnit.percent),
    );
  }
  final em = _toEm(t, percentAsEm: false);
  if (em == null || em < 0) return null;
  return CssLengthValue(CssLength(_clamp(em, 0, 100), CssLengthUnit.em));
}

CssValue? _fontStyle(List<CssToken> c) {
  if (c.isEmpty || c.first.type != CssTokenType.ident) return null;
  final v = cssAsciiLower(c.first.value);
  if (c.length == 1) {
    return switch (v) {
      'normal' => const CssKeywordValue(CssFontStyle.normal),
      'italic' || 'oblique' => const CssKeywordValue(CssFontStyle.italic),
      _ => null,
    };
  }
  if (c.length == 2 && v == 'oblique' && _isObliqueAngle(c[1])) {
    return const CssKeywordValue(CssFontStyle.italic);
  }
  return null;
}

/// Graus por unidade de ângulo (CSS Values 4 §7.1).
const Map<String, double> _degreesPerUnit = {
  'deg': 1,
  'grad': 0.9,
  'rad': 180 / 3.141592653589793,
  'turn': 360,
};

/// Ângulo de `oblique`, entre −90deg e 90deg (CSS Fonts 4 §2.3).
bool _isObliqueAngle(CssToken t) {
  if (t.type != CssTokenType.dimension) return false;
  final factor = _degreesPerUnit[t.unit];
  if (factor == null) return false;
  final degrees = t.number * factor;
  return degrees >= -90 && degrees <= 90;
}

CssWeightValue? _weightOf(CssToken t) {
  if (t.type == CssTokenType.number) {
    final n = t.number;
    if (!(n >= 1 && n <= 1000)) return null;
    return CssWeightValue(absolute: n);
  }
  if (t.type != CssTokenType.ident) return null;
  return switch (cssAsciiLower(t.value)) {
    'normal' => const CssWeightValue(absolute: 400),
    'bold' => const CssWeightValue(absolute: 700),
    'bolder' => const CssWeightValue(bolder: true),
    'lighter' => const CssWeightValue(),
    _ => null,
  };
}

CssValue? _fontWeight(List<CssToken> c) =>
    c.length == 1 ? _weightOf(c.first) : null;

/// Subgrupo de cada palavra de `font-variant` (CSS Fonts 4 §6.6, grupos
/// `||`: cada subgrupo no máximo uma vez).
const Map<String, String> _variantWords = {
  'small-caps': 'caps', 'all-small-caps': 'caps', 'petite-caps': 'caps', //
  'all-petite-caps': 'caps', 'unicase': 'caps', 'titling-caps': 'caps',
  'common-ligatures': 'common', 'no-common-ligatures': 'common',
  'discretionary-ligatures': 'discretionary',
  'no-discretionary-ligatures': 'discretionary',
  'historical-ligatures': 'historical', 'no-historical-ligatures': 'historical',
  'contextual': 'contextual', 'no-contextual': 'contextual',
  'lining-nums': 'figure', 'oldstyle-nums': 'figure',
  'proportional-nums': 'spacing', 'tabular-nums': 'spacing',
  'diagonal-fractions': 'fraction', 'stacked-fractions': 'fraction',
  'ordinal': 'ordinal', 'slashed-zero': 'slashed-zero',
  'jis78': 'form', 'jis83': 'form', 'jis90': 'form', 'jis04': 'form',
  'simplified': 'form', 'traditional': 'form',
  'full-width': 'width', 'proportional-width': 'width',
  'ruby': 'ruby',
  'historical-forms': 'historical-forms',
  'sub': 'position', 'super': 'position',
  'text': 'emoji', 'emoji': 'emoji', 'unicode': 'emoji',
};

/// Funções de `font-variant-alternates`, cada uma no máximo uma vez (o
/// conteúdo não é conferido).
const Set<String> _variantFunctions = {
  'stylistic', 'styleset', 'character-variant', 'swash', 'ornaments', //
  'annotation',
};

/// `font-variant` (CSS Fonts 4 §6.6): `normal`, `none` ou a combinação dos
/// subgrupos, sem repetir. Só o `small-caps` e o `all-small-caps` do grupo
/// de maiúsculas viram `smallCaps`.
CssValue? _fontVariant(List<CssToken> c) {
  var small = false;
  final seen = <String>{};
  for (final t in c) {
    final String key;
    if (t.type == CssTokenType.ident) {
      final v = cssAsciiLower(t.value);
      if (v == 'normal' || v == 'none') {
        if (c.length != 1) return null;
        return const CssKeywordValue(CssFontVariant.normal);
      }
      final g = _variantWords[v];
      if (g == null) return null;
      key = g;
      if (v == 'small-caps' || v == 'all-small-caps') small = true;
    } else if (t.type == CssTokenType.function) {
      final f = cssAsciiLower(t.value);
      if (!_variantFunctions.contains(f)) return null;
      key = f;
    } else {
      return null;
    }
    if (!seen.add(key)) return null;
  }
  return CssKeywordValue(
    small ? CssFontVariant.smallCaps : CssFontVariant.normal,
  );
}

const Set<String> _capsWords = {
  'normal', 'small-caps', 'all-small-caps', 'petite-caps', 'all-petite-caps', //
  'unicase', 'titling-caps',
};

/// `font-variant-caps` (CSS Fonts 4 §6.5): uma palavra da lista.
CssValue? _fontVariantCaps(List<CssToken> c) {
  final k = _keyword(c);
  if (k == null || !_capsWords.contains(k)) return null;
  return CssKeywordValue(
    k == 'small-caps' || k == 'all-small-caps'
        ? CssFontVariant.smallCaps
        : CssFontVariant.normal,
  );
}

const Set<String> _decorationLines = {
  'underline',
  'overline',
  'line-through',
  'blink',
};

/// `text-decoration-line` (CSS Text Decoration 3 §2.1): `none` ou uma ou
/// mais linhas sem repetição; `overline` e `blink` aceitos e ignorados.
CssValue? _decorationLine(List<CssToken> c) {
  if (_keyword(c) == 'none') return const CssDecorationValue();
  final seen = <String>{};
  for (final t in c) {
    if (t.type != CssTokenType.ident) return null;
    final v = cssAsciiLower(t.value);
    if (!_decorationLines.contains(v) || !seen.add(v)) return null;
  }
  return CssDecorationValue(
    underline: seen.contains('underline'),
    lineThrough: seen.contains('line-through'),
  );
}

/// `text-decoration` (CSS Text Decoration 3 §2.4): linha, estilo, cor e
/// espessura em qualquer ordem, cada uma no máximo uma vez; só a linha
/// entra. Uma palavra que não é linha, `none`, estilo, espessura nem cor
/// invalida a declaração (`text-decoration: foo`, `red blue`), como no
/// navegador; sem linha, vale `none` (o atalho reinicia).
CssValue? _decorationShorthand(List<CssToken> c) {
  final seen = <String>{};
  var none = false, style = false, color = false, thickness = false;
  var lastLine = false;
  for (final t in c) {
    final String kind;
    switch (t.type) {
      case CssTokenType.ident:
        final v = cssAsciiLower(t.value);
        if (v == 'none') {
          kind = 'none';
        } else if (_decorationLines.contains(v)) {
          // As linhas formam um componente só: contíguas (§2.4).
          if (!seen.add(v) || (seen.length > 1 && !lastLine)) return null;
          lastLine = true;
          continue;
        } else if (_decorationStyles.contains(v)) {
          kind = 'style';
        } else if (v == 'auto' || v == 'from-font') {
          kind = 'thickness';
        } else if (_isColorWord(v)) {
          kind = 'color';
        } else {
          return null;
        }
      case CssTokenType.hash:
        if (!_isHexColor(t.value)) return null;
        kind = 'color';
      case CssTokenType.function:
        final f = cssAsciiLower(t.value);
        if (_colorFunctions.contains(f)) {
          kind = 'color';
        } else if (_mathFunctions.contains(f)) {
          kind = 'thickness';
        } else {
          return null;
        }
      case CssTokenType.dimension || CssTokenType.number:
        if (!_isLength(t)) return null;
        kind = 'thickness';
      case CssTokenType.percentage:
        if (!_finite(t.number)) return null;
        kind = 'thickness';
      default:
        return null;
    }
    lastLine = false;
    switch (kind) {
      case 'none':
        if (none) return null;
        none = true;
      case 'style':
        if (style) return null;
        style = true;
      case 'thickness':
        if (thickness) return null;
        thickness = true;
      default:
        if (color) return null;
        color = true;
    }
  }
  if (none && seen.isNotEmpty) return null;
  return CssDecorationValue(
    underline: seen.contains('underline'),
    lineThrough: seen.contains('line-through'),
  );
}

const Set<String> _decorationStyles = {
  'solid',
  'double',
  'dotted',
  'dashed',
  'wavy',
};

/// Funções de cor do CSS Color 4 e 5.
const Set<String> _colorFunctions = {
  'rgb', 'rgba', 'hsl', 'hsla', 'hwb', 'lab', 'lch', 'oklab', 'oklch', //
  'color', 'color-mix', 'light-dark',
};

const Set<String> _mathFunctions = {'calc', 'min', 'max', 'clamp'};

bool _isHexColor(String v) {
  if (v.length != 3 && v.length != 4 && v.length != 6 && v.length != 8) {
    return false;
  }
  for (var i = 0; i < v.length; i++) {
    final c = v.codeUnitAt(i) | 0x20;
    if (!((c >= 0x30 && c <= 0x39) || (c >= 0x61 && c <= 0x66))) return false;
  }
  return true;
}

bool _isColorWord(String lower) =>
    lower == 'transparent' ||
    lower == 'currentcolor' ||
    _namedColors.contains(lower) ||
    _systemColors.contains(lower);

/// As 148 cores com nome do CSS Color 4 §6.1.
const Set<String> _namedColors = {
  'aliceblue', 'antiquewhite', 'aqua', 'aquamarine', 'azure', 'beige', //
  'bisque', 'black', 'blanchedalmond', 'blue', 'blueviolet', 'brown',
  'burlywood', 'cadetblue', 'chartreuse', 'chocolate', 'coral',
  'cornflowerblue', 'cornsilk', 'crimson', 'cyan', 'darkblue', 'darkcyan',
  'darkgoldenrod', 'darkgray', 'darkgreen', 'darkgrey', 'darkkhaki',
  'darkmagenta', 'darkolivegreen', 'darkorange', 'darkorchid', 'darkred',
  'darksalmon', 'darkseagreen', 'darkslateblue', 'darkslategray',
  'darkslategrey', 'darkturquoise', 'darkviolet', 'deeppink', 'deepskyblue',
  'dimgray', 'dimgrey', 'dodgerblue', 'firebrick', 'floralwhite',
  'forestgreen', 'fuchsia', 'gainsboro', 'ghostwhite', 'gold', 'goldenrod',
  'gray', 'green', 'greenyellow', 'grey', 'honeydew', 'hotpink', 'indianred',
  'indigo', 'ivory', 'khaki', 'lavender', 'lavenderblush', 'lawngreen',
  'lemonchiffon', 'lightblue', 'lightcoral', 'lightcyan',
  'lightgoldenrodyellow', 'lightgray', 'lightgreen', 'lightgrey', 'lightpink',
  'lightsalmon', 'lightseagreen', 'lightskyblue', 'lightslategray',
  'lightslategrey', 'lightsteelblue', 'lightyellow', 'lime', 'limegreen',
  'linen', 'magenta', 'maroon', 'mediumaquamarine', 'mediumblue',
  'mediumorchid', 'mediumpurple', 'mediumseagreen', 'mediumslateblue',
  'mediumspringgreen', 'mediumturquoise', 'mediumvioletred', 'midnightblue',
  'mintcream', 'mistyrose', 'moccasin', 'navajowhite', 'navy', 'oldlace',
  'olive', 'olivedrab', 'orange', 'orangered', 'orchid', 'palegoldenrod',
  'palegreen', 'paleturquoise', 'palevioletred', 'papayawhip', 'peachpuff',
  'peru', 'pink', 'plum', 'powderblue', 'purple', 'rebeccapurple', 'red',
  'rosybrown', 'royalblue', 'saddlebrown', 'salmon', 'sandybrown', 'seagreen',
  'seashell', 'sienna', 'silver', 'skyblue', 'slateblue', 'slategray',
  'slategrey', 'snow', 'springgreen', 'steelblue', 'tan', 'teal', 'thistle',
  'tomato', 'turquoise', 'violet', 'wheat', 'white', 'whitesmoke', 'yellow',
  'yellowgreen',
};

/// Cores de sistema do CSS Color 4 §6.2, inclusive as obsoletas de §6.2.1
/// (o navegador ainda as aceita), em minúsculas.
const Set<String> _systemColors = {
  'accentcolor', 'accentcolortext', 'activetext', 'buttonborder', //
  'buttonface', 'buttontext', 'canvas', 'canvastext', 'field', 'fieldtext',
  'graytext', 'highlight', 'highlighttext', 'linktext', 'mark', 'marktext',
  'selecteditem', 'selecteditemtext', 'visitedtext', 'activeborder',
  'activecaption', 'appworkspace', 'background', 'buttonhighlight',
  'buttonshadow', 'captiontext', 'inactiveborder', 'inactivecaption',
  'inactivecaptiontext', 'infobackground', 'infotext', 'menu', 'menutext',
  'scrollbar', 'threeddarkshadow', 'threedface', 'threedhighlight',
  'threedlightshadow', 'threedshadow', 'window', 'windowframe', 'windowtext',
};

const Set<String> _absoluteSizeWords = {
  'xx-small', 'x-small', 'small', 'medium', 'large', 'x-large', 'xx-large', //
  'xxx-large',
};

/// Tamanho de fonte. [CssFontSizeValue] se relativo; `absolute` (`12px`,
/// `medium`) é um tamanho válido que o galley descarta; `null` se não é
/// tamanho. A razão r sobre o pai: r < 0,95 → `smaller`, r > 1,05 →
/// `larger`, senão `same` (§7.1).
Object? _fontSize(CssToken t) {
  double? ratio;
  switch (t.type) {
    case CssTokenType.dimension:
      if (!_finite(t.number) || t.number < 0) return null;
      switch (t.unit) {
        case 'em' || 'rem':
          ratio = t.number;
        case 'ex' || 'ch':
          ratio = t.number * 0.5;
        default:
          return _isLength(t) ? _absolute : null;
      }
    case CssTokenType.percentage:
      if (!_finite(t.number) || t.number < 0) return null;
      ratio = t.number / 100;
    case CssTokenType.number:
      return t.number == 0 ? _absolute : null;
    case CssTokenType.ident:
      final v = cssAsciiLower(t.value);
      return switch (v) {
        'smaller' => const CssFontSizeValue(CssFontSizeStep.smaller),
        'larger' => const CssFontSizeValue(CssFontSizeStep.larger),
        _ => _absoluteSizeWords.contains(v) ? _absolute : null,
      };
    default:
      return null;
  }
  final step = ratio < 0.95
      ? CssFontSizeStep.smaller
      : (ratio > 1.05 ? CssFontSizeStep.larger : CssFontSizeStep.same);
  return CssFontSizeValue(step);
}

/// Marcador de tamanho absoluto em [_fontSize].
const Object _absolute = Object();

const Set<String> _systemFonts = {
  'caption', 'icon', 'menu', 'message-box', 'small-caption', 'status-bar', //
};

const Set<String> _reservedFamily = {
  'inherit', 'initial', 'unset', 'revert', 'revert-layer', 'default', //
};

const Set<String> _stretchWords = {
  'ultra-condensed', 'extra-condensed', 'condensed', 'semi-condensed', //
  'semi-expanded', 'expanded', 'extra-expanded', 'ultra-expanded',
};

/// `font` (CSS Fonts 4 §2.8): `[estilo ‖ variante ‖ peso ‖ largura]?
/// tamanho [/ entrelinha]? família`. Reinicia estilo, variante e peso; o
/// tamanho absoluto não gera `fontSize`.
_Parsed? _font(List<CssToken> c) {
  final only = _keyword(c);
  if (only != null && _systemFonts.contains(only)) return null;
  CssFontStyle? style;
  CssFontVariant? variant;
  CssWeightValue? weight;
  var stretch = false;
  var i = 0;
  for (var prefix = 0; prefix < 4 && i < c.length; prefix++) {
    final t = c[i];
    if (t.type == CssTokenType.number) {
      if (weight != null) break;
      final w = _weightOf(t);
      // Fora de [1, 1000] não é peso: cai para o tamanho (`0 serif`).
      if (w == null) break;
      weight = w;
      i++;
      continue;
    }
    if (t.type != CssTokenType.ident) break;
    final v = cssAsciiLower(t.value);
    if (v == 'normal') {
      i++;
    } else if ((v == 'italic' || v == 'oblique') && style == null) {
      style = CssFontStyle.italic;
      i++;
      if (v == 'oblique' && i < c.length && _isObliqueAngle(c[i])) i++;
    } else if (v == 'small-caps' && variant == null) {
      variant = CssFontVariant.smallCaps;
      i++;
    } else if ((v == 'bold' || v == 'bolder' || v == 'lighter') &&
        weight == null) {
      weight = _weightOf(t);
      i++;
    } else if (_stretchWords.contains(v) && !stretch) {
      stretch = true;
      i++;
    } else {
      break;
    }
  }
  if (i >= c.length) return null;
  final size = _fontSize(c[i]);
  if (size == null) return null;
  i++;
  if (i < c.length && c[i].type == CssTokenType.delim && c[i].value == '/') {
    i++;
    if (i >= c.length) return null;
    final h = c[i];
    final ok = switch (h.type) {
      CssTokenType.number ||
      CssTokenType.percentage => _finite(h.number) && h.number >= 0,
      CssTokenType.dimension => _isLength(h) && h.number >= 0,
      CssTokenType.ident => cssAsciiLower(h.value) == 'normal',
      _ => false,
    };
    if (!ok) return null;
    i++;
  }
  // Família: nomes separados por vírgula; um nome é uma string ou uma
  // sequência de idents (CSS Fonts 4 §3.1). A palavra global ou `default` só
  // é inválida como primeiro ident do nome (como no Chromium).
  if (i >= c.length) return null;
  var expectName = true;
  var idents = 0, strings = 0;
  for (; i < c.length; i++) {
    final t = c[i];
    if (t.type == CssTokenType.comma) {
      if (expectName) return null;
      expectName = true;
      idents = 0;
      strings = 0;
    } else if (t.type == CssTokenType.ident) {
      if (strings > 0) return null;
      if (idents == 0 && _reservedFamily.contains(cssAsciiLower(t.value))) {
        return null;
      }
      idents++;
      expectName = false;
    } else if (t.type == CssTokenType.string) {
      if (idents > 0 || strings > 0) return null;
      strings++;
      expectName = false;
    } else {
      return null;
    }
  }
  if (expectName) return null;
  return [
    (CssProperty.fontStyle, CssKeywordValue(style ?? CssFontStyle.normal)),
    (
      CssProperty.fontVariant,
      CssKeywordValue(variant ?? CssFontVariant.normal),
    ),
    (CssProperty.fontWeight, weight ?? const CssWeightValue(absolute: 400)),
    if (size is CssFontSizeValue) (CssProperty.fontSize, size),
  ];
}

/// Margem: comprimento, `%` ou `auto` (→ 0), limitada a [0, 8]em; negativa
/// vira 0.
CssValue? _margin(List<CssToken> c) {
  if (c.length != 1) return null;
  final t = c.first;
  if (t.type == CssTokenType.ident) {
    return cssAsciiLower(t.value) == 'auto' ? const CssEmValue(0) : null;
  }
  final em = _toEm(t, percentAsEm: true);
  return em == null ? null : CssEmValue(_clamp(em, 0, 8));
}

/// Padding: comprimento ou `%` ≥ 0, limitado a [0, 8]em; negativo é
/// inválido no CSS e descarta.
CssValue? _padding(List<CssToken> c) {
  if (c.length != 1) return null;
  final em = _toEm(c.first, percentAsEm: true);
  if (em == null || em < 0) return null;
  return CssEmValue(_clamp(em, 0, 8));
}

/// Atalho de caixa: 1 a 4 valores (topo, direita, base, esquerda); um
/// componente inválido descarta o atalho.
_Parsed? _box(
  List<CssProperty> sides,
  List<CssToken> c,
  CssValue? Function(List<CssToken>) side,
) {
  if (c.isEmpty || c.length > 4) return null;
  final values = <CssValue>[];
  for (final t in c) {
    final v = side([t]);
    if (v == null) return null;
    values.add(v);
  }
  final top = values[0];
  final right = values.length > 1 ? values[1] : top;
  final bottom = values.length > 2 ? values[2] : top;
  final left = values.length > 3 ? values[3] : right;
  return [
    (sides[0], top),
    (sides[1], right),
    (sides[2], bottom),
    (sides[3], left),
  ];
}

/// `text-indent`: um comprimento ou `%`, limitado a [-4, 8]em; `hanging` e
/// `each-line` descartam.
CssValue? _textIndent(List<CssToken> c) {
  if (c.length != 1) return null;
  final em = _toEm(c.first, percentAsEm: true);
  return em == null ? null : CssEmValue(_clamp(em, -4, 8));
}

CssValue? _degraded(List<CssToken> c, Map<String, bool> map) {
  final k = _keyword(c);
  if (k == null) return null;
  final degrades = map[k];
  return degrades == null
      ? null
      : CssDegradedValue(degrades: degrades, keyword: k);
}

const Map<String, bool> _float = {
  'left': true,
  'right': true,
  'inline-start': true,
  'inline-end': true,
  'none': false,
};

const Map<String, bool> _position = {
  'absolute': true,
  'fixed': true,
  'sticky': true,
  'static': false,
  'relative': false,
};

const Map<String, bool> _writingMode = {
  'vertical-rl': true,
  'vertical-lr': true,
  'sideways-rl': true,
  'sideways-lr': true,
  'tb': true,
  'tb-rl': true,
  'horizontal-tb': false,
  'lr': false,
  'lr-tb': false,
  'rl': false,
  'rl-tb': false,
};

const CssDegradedValue _columnAuto = CssDegradedValue(
  degrades: false,
  keyword: 'auto',
);

/// `column-count`: `auto` ou inteiro ≥ 1; degrada acima de 1.
CssDegradedValue? _columnCount(CssToken t) {
  if (t.type == CssTokenType.ident) {
    return cssAsciiLower(t.value) == 'auto' ? _columnAuto : null;
  }
  if (t.type != CssTokenType.number || !t.isInteger || !(t.number >= 1)) {
    return null;
  }
  return CssDegradedValue(degrades: t.number > 1, keyword: t.value);
}

/// `column-width`: `auto` ou comprimento ≥ 0; o comprimento degrada.
CssDegradedValue? _columnWidth(CssToken t) {
  if (t.type == CssTokenType.ident) {
    return cssAsciiLower(t.value) == 'auto' ? _columnAuto : null;
  }
  if (!_isLength(t) || t.number < 0) return null;
  return CssDegradedValue(degrades: true, keyword: '${t.value}${t.unit}');
}

/// `columns` (CSS Multi-column 1 §3.3): contagem e largura em qualquer
/// ordem, `auto` no que faltar.
_Parsed? _columns(List<CssToken> c) {
  if (c.isEmpty || c.length > 2) return null;
  CssDegradedValue? count;
  CssDegradedValue? width;
  var autos = 0;
  for (final t in c) {
    if (t.type == CssTokenType.ident && cssAsciiLower(t.value) == 'auto') {
      autos++;
      continue;
    }
    // `0` não é contagem (≥ 1), mas é comprimento: vira a largura.
    if (t.type == CssTokenType.number && count == null && t.number != 0) {
      count = _columnCount(t);
      if (count == null) return null;
    } else {
      if (width != null) return null;
      width = _columnWidth(t);
      if (width == null) return null;
    }
  }
  if (autos + (count == null ? 0 : 1) + (width == null ? 0 : 1) != c.length) {
    return null;
  }
  return [
    (CssProperty.columnCount, count ?? _columnAuto),
    (CssProperty.columnWidth, width ?? _columnAuto),
  ];
}
