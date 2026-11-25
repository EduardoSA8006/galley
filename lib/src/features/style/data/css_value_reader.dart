import 'dart:math' as math;

import '../../container/data/path/epub_path.dart';
import '../domain/css_value.dart';
import 'css_tokenizer.dart';

/// Nível máximo de aninhamento em `calc()` (o próprio `calc(` conta como 1).
const int kMaxCalcDepth = 32;

/// Menor e maior inteiro aceitos (`z-index`, contadores, `orphans`...).
const int kCssMinInt = -2147483648;

/// Maior inteiro aceito.
const int kCssMaxInt = 2147483647;

/// Valor componente de topo de um valor de declaração (CSS Syntax §5.4.7).
///
/// Um token simples ocupa `[head, head + 1)`; uma função ou um bloco
/// (`(`, `[`, `{`) ocupa `[head, end)`, com o conteúdo em
/// `[head + 1, innerEnd)` (sem o fechamento).
final class CssComponent {
  /// Cria o componente.
  const CssComponent(this.head, this.innerEnd, this.end);

  /// Índice do primeiro token.
  final int head;

  /// Fim (exclusivo) do conteúdo de uma função ou bloco.
  final int innerEnd;

  /// Fim (exclusivo) do componente.
  final int end;
}

/// Leitor dos valores primitivos de uma declaração: comprimentos (inclusive
/// `calc()`), números, cores, `url()` e textos.
///
/// Os métodos devolvem `null` quando o componente não é do tipo pedido ou é
/// inválido. Tudo é linear no tamanho do valor e sem recursão.
final class CssValueReader {
  /// Cria o leitor de [tokens] (aparados, sem `!important`); [sheetPath] é o
  /// caminho no zip da folha (base de `url()`).
  CssValueReader(this.tokens, this.sheetPath) : components = _split(tokens);

  /// Tokens do valor.
  final List<CssToken> tokens;

  /// Caminho da folha no zip.
  final String sheetPath;

  /// Componentes de topo, sem espaços; `null` se houver um fechamento
  /// (`)`, `]`, `}`) sem abertura.
  final List<CssComponent>? components;

  static List<CssComponent>? _split(List<CssToken> t) {
    final out = <CssComponent>[];
    var i = 0;
    while (i < t.length) {
      final type = t[i].type;
      if (type == CssTokenType.whitespace) {
        i++;
        continue;
      }
      if (_closes(type)) return null;
      if (!_opens(type)) {
        out.add(CssComponent(i, i + 1, i + 1));
        i++;
        continue;
      }
      var depth = 1;
      var j = i + 1;
      while (j < t.length) {
        final tt = t[j].type;
        if (_opens(tt)) {
          depth++;
        } else if (_closes(tt)) {
          depth--;
          if (depth == 0) break;
        }
        j++;
      }
      // Bloco sem fechamento (fim do valor): fecha implicitamente.
      final closed = j < t.length;
      out.add(CssComponent(i, j, closed ? j + 1 : j));
      i = closed ? j + 1 : j;
    }
    return out;
  }

  static bool _opens(CssTokenType t) =>
      t == CssTokenType.function ||
      t == CssTokenType.leftParen ||
      t == CssTokenType.leftSquare ||
      t == CssTokenType.leftBrace;

  static bool _closes(CssTokenType t) =>
      t == CssTokenType.rightParen ||
      t == CssTokenType.rightSquare ||
      t == CssTokenType.rightBrace;

  /// Primeiro token de [c].
  CssToken token(CssComponent c) => tokens[c.head];

  /// Id da palavra-chave de [c], se for um ident conhecido.
  int? keyword(CssComponent c) {
    final t = tokens[c.head];
    return t.type == CssTokenType.ident ? CssKeywords.idOf(t.value) : null;
  }

  /// Nome minúsculo do ident [c], ou `null`.
  String? identLower(CssComponent c) {
    final t = tokens[c.head];
    return t.type == CssTokenType.ident ? asciiLower(t.value) : null;
  }

  /// Nome minúsculo da função [c], ou `null`.
  String? functionLower(CssComponent c) {
    final t = tokens[c.head];
    return t.type == CssTokenType.function ? asciiLower(t.value) : null;
  }

  /// Se [c] é o delim [char].
  bool isDelim(CssComponent c, String char) {
    final t = tokens[c.head];
    return t.type == CssTokenType.delim && t.value == char;
  }

  /// Se [c] é uma vírgula.
  bool isComma(CssComponent c) => tokens[c.head].type == CssTokenType.comma;

  /// Texto de [c], se for uma string.
  String? string(CssComponent c) {
    final t = tokens[c.head];
    return t.type == CssTokenType.string ? t.value : null;
  }

  /// Tokens não-espaço do conteúdo da função ou bloco [c].
  List<CssToken> inner(CssComponent c) => [
    for (var i = c.head + 1; i < c.innerEnd; i++)
      if (tokens[i].type != CssTokenType.whitespace) tokens[i],
  ];

  /// Número sem unidade de [c] (limitado a ±[kCssMaxMagnitude]).
  double? number(CssComponent c) {
    final t = tokens[c.head];
    return t.type == CssTokenType.number ? clampMagnitude(t.number) : null;
  }

  /// Inteiro de [c] (número escrito sem fração nem expoente), limitado a
  /// [[kCssMinInt], [kCssMaxInt]].
  int? integer(CssComponent c) {
    final t = tokens[c.head];
    if (t.type != CssTokenType.number || !t.isInteger) return null;
    final v = t.number;
    if (v >= kCssMaxInt) return kCssMaxInt;
    if (v <= kCssMinInt) return kCssMinInt;
    return v.toInt();
  }

  /// Porcentagem de [c] (o número antes do `%`).
  double? percentage(CssComponent c) {
    final t = tokens[c.head];
    return t.type == CssTokenType.percentage ? clampMagnitude(t.number) : null;
  }

  /// Comprimento de [c]: dimensão, `0` sem unidade, porcentagem (se
  /// [percent]) ou `calc()`. Literais negativos são rejeitados se não
  /// [negative] (um `calc()` negativo fica para o uso limitar, como nos
  /// navegadores).
  CssLengthSpec? length(
    CssComponent c, {
    bool percent = true,
    bool negative = true,
  }) {
    final t = tokens[c.head];
    switch (t.type) {
      case CssTokenType.number:
        return t.number == 0 ? const CssLengthSpec() : null;
      case CssTokenType.percentage:
        if (!percent || (!negative && t.number < 0)) return null;
        return CssLengthSpec(percent: clampMagnitude(t.number));
      case CssTokenType.dimension:
        if (!negative && t.number < 0) return null;
        final lin = _Lin.dimension(t.number, t.unit);
        return lin?.toLength();
      case CssTokenType.function:
        final name = asciiLower(t.value);
        if (name != 'calc' && name != '-webkit-calc') return null;
        final lin = _calc(c);
        if (lin == null || lin.isNumber) return null;
        if (!percent && lin.c[_percent] != 0) return null;
        return lin.toLength();
      default:
        return null;
    }
  }

  /// Avalia o `calc()` [c] sem recursão (shunting-yard com pilhas).
  _Lin? _calc(CssComponent c) {
    final values = <_Lin>[];
    final ops = <int>[]; // _open, _add, _sub, _mul, _div
    var depth = 1;
    var expectOperand = true;
    final end = c.innerEnd;
    if (c.end == c.innerEnd) return null; // calc sem fechamento
    for (var i = c.head + 1; i < end; i++) {
      final t = tokens[i];
      if (t.type == CssTokenType.whitespace) continue;
      if (expectOperand) {
        switch (t.type) {
          case CssTokenType.number:
            values.add(_Lin.number(t.number));
          case CssTokenType.percentage:
            values.add(_Lin.percent(t.number));
          case CssTokenType.dimension:
            final lin = _Lin.dimension(t.number, t.unit);
            if (lin == null) return null;
            values.add(lin);
          case CssTokenType.leftParen:
          case CssTokenType.function:
            if (t.type == CssTokenType.function) {
              final name = asciiLower(t.value);
              if (name != 'calc' && name != '-webkit-calc') return null;
            }
            if (++depth > kMaxCalcDepth) return null;
            ops.add(_open);
            continue;
          default:
            return null;
        }
        expectOperand = false;
        continue;
      }
      if (t.type == CssTokenType.rightParen) {
        while (ops.isNotEmpty && ops.last != _open) {
          if (!_apply(values, ops.removeLast())) return null;
        }
        if (ops.isEmpty) return null;
        ops.removeLast();
        depth--;
        continue;
      }
      if (t.type != CssTokenType.delim) return null;
      final int op;
      switch (t.value) {
        case '+':
          op = _add;
        case '-':
          op = _sub;
        case '*':
          op = _mul;
        case '/':
          op = _div;
        default:
          return null;
      }
      if (op == _add || op == _sub) {
        // `+` e `-` exigem espaço dos dois lados.
        if (i + 1 >= end ||
            tokens[i - 1].type != CssTokenType.whitespace ||
            tokens[i + 1].type != CssTokenType.whitespace) {
          return null;
        }
      }
      while (ops.isNotEmpty &&
          ops.last != _open &&
          _precedence(ops.last) >= _precedence(op)) {
        if (!_apply(values, ops.removeLast())) return null;
      }
      ops.add(op);
      expectOperand = true;
    }
    if (expectOperand) return null;
    while (ops.isNotEmpty) {
      final op = ops.removeLast();
      if (op == _open) return null;
      if (!_apply(values, op)) return null;
    }
    return values.length == 1 ? values.single : null;
  }

  /// Cor de [c]: `CssColor` ou `CssKeyword(currentcolor)`.
  CssValue? color(CssComponent c) {
    final t = tokens[c.head];
    switch (t.type) {
      case CssTokenType.ident:
        final name = asciiLower(t.value);
        if (name == 'currentcolor') {
          return const CssKeyword(CssKeywords.currentcolor);
        }
        if (name == 'transparent') return const CssColor(0);
        final rgb = _namedColors[name];
        return rgb == null ? null : CssColor(0xFF000000 | rgb);
      case CssTokenType.hash:
        final argb = _hex(t.value);
        return argb == null ? null : CssColor(argb);
      case CssTokenType.function:
        if (c.end == c.innerEnd) return null;
        final name = asciiLower(t.value);
        final args = inner(c);
        final argb = switch (name) {
          'rgb' || 'rgba' => _rgb(args),
          'hsl' || 'hsla' => _hsl(args),
          _ => null,
        };
        return argb == null ? null : CssColor(argb);
      default:
        return null;
    }
  }

  /// Caminho no zip de `url(...)` em [c], resolvido relativo à folha; `null`
  /// se não for `url()`, se for externo (com esquema ou `//`), vazio ou se
  /// escapar da raiz do zip.
  String? url(CssComponent c) {
    final t = tokens[c.head];
    String href;
    if (t.type == CssTokenType.url) {
      href = t.value;
    } else if (t.type == CssTokenType.function &&
        asciiLower(t.value) == 'url') {
      final args = inner(c);
      if (args.length != 1 || args.single.type != CssTokenType.string) {
        return null;
      }
      href = args.single.value;
    } else {
      return null;
    }
    href = href.trim();
    if (href.isEmpty || href.startsWith('#') || href.startsWith('//')) {
      return null;
    }
    final resolved = resolveHref(sheetPath, href);
    if (resolved == null || resolved.path.isEmpty) return null;
    return resolved.path;
  }
}

/// [v] limitado a ±[kCssMaxMagnitude], sem NaN e sem `-0.0`.
double clampMagnitude(double v) {
  if (v.isNaN || v == 0) return 0;
  if (v > kCssMaxMagnitude) return kCssMaxMagnitude;
  if (v < -kCssMaxMagnitude) return -kCssMaxMagnitude;
  return v;
}

const int _open = 0;
const int _add = 1;
const int _sub = 2;
const int _mul = 3;
const int _div = 4;

int _precedence(int op) => op == _mul || op == _div ? 2 : 1;

bool _apply(List<_Lin> values, int op) {
  if (values.length < 2) return false;
  final b = values.removeLast();
  final a = values.removeLast();
  final _Lin? r;
  switch (op) {
    case _add:
    case _sub:
      r = a.isNumber == b.isNumber ? a.plus(b, op == _sub ? -1 : 1) : null;
    case _mul:
      r = a.isNumber
          ? b.scaled(a.n)
          : b.isNumber
          ? a.scaled(b.n)
          : null;
    default:
      r = b.isNumber && b.n != 0 ? a.divided(b.n) : null;
  }
  if (r == null) return false;
  values.add(r);
  return true;
}

const int _px = 0;
const int _em = 1;
const int _ex = 2;
const int _rem = 3;
const int _percent = 4;
const int _vw = 5;
const int _vh = 6;

/// Termo linear de `calc()`: número puro ([isNumber]) ou combinação de
/// unidades.
final class _Lin {
  _Lin._(this.c, this.n, this.isNumber);

  factory _Lin.number(double v) =>
      _Lin._(List<double>.filled(7, 0), clampMagnitude(v), true);

  factory _Lin.percent(double v) => _Lin._(
    List<double>.filled(7, 0)..[_percent] = clampMagnitude(v),
    0,
    false,
  );

  /// Termo de uma dimensão; `null` para unidades fora do escopo.
  static _Lin? dimension(double v, String unit) {
    final int slot;
    var factor = 1.0;
    switch (asciiLower(unit)) {
      case 'px':
        slot = _px;
      case 'em':
        slot = _em;
      case 'ex':
      case 'ch':
        slot = _ex;
      case 'rem':
        slot = _rem;
      case 'vw':
        slot = _vw;
      case 'vh':
        slot = _vh;
      case 'pt':
        slot = _px;
        factor = 4 / 3;
      case 'pc':
        slot = _px;
        factor = 16;
      case 'in':
        slot = _px;
        factor = 96;
      case 'cm':
        slot = _px;
        factor = 96 / 2.54;
      case 'mm':
        slot = _px;
        factor = 96 / 25.4;
      case 'q':
        slot = _px;
        factor = 96 / 101.6;
      default:
        return null;
    }
    final c = List<double>.filled(7, 0);
    c[slot] = clampMagnitude(clampMagnitude(v) * factor);
    return _Lin._(c, 0, false);
  }

  /// Coeficientes (px, em, ex, rem, %, vw, vh).
  final List<double> c;

  /// Valor quando [isNumber].
  final double n;

  final bool isNumber;

  _Lin plus(_Lin o, int sign) => _Lin._(
    [for (var i = 0; i < 7; i++) clampMagnitude(c[i] + sign * o.c[i])],
    clampMagnitude(n + sign * o.n),
    isNumber,
  );

  _Lin scaled(double k) => _Lin._(
    [for (var i = 0; i < 7; i++) clampMagnitude(c[i] * k)],
    clampMagnitude(n * k),
    isNumber,
  );

  _Lin divided(double k) => _Lin._(
    [for (var i = 0; i < 7; i++) clampMagnitude(c[i] / k)],
    clampMagnitude(n / k),
    isNumber,
  );

  CssLengthSpec toLength() => CssLengthSpec(
    px: c[_px],
    em: c[_em],
    ex: c[_ex],
    rem: c[_rem],
    percent: c[_percent],
    vw: c[_vw],
    vh: c[_vh],
  );
}

int? _hexDigit(int ch) {
  if (ch >= 0x30 && ch <= 0x39) return ch - 0x30;
  if (ch >= 0x41 && ch <= 0x46) return ch - 0x41 + 10;
  if (ch >= 0x61 && ch <= 0x66) return ch - 0x61 + 10;
  return null;
}

/// `#rgb`, `#rgba`, `#rrggbb` e `#rrggbbaa` → ARGB.
int? _hex(String s) {
  final d = <int>[];
  for (var i = 0; i < s.length; i++) {
    final v = _hexDigit(s.codeUnitAt(i));
    if (v == null) return null;
    d.add(v);
  }
  int r, g, b, a = 255;
  switch (d.length) {
    case 3:
    case 4:
      r = d[0] * 17;
      g = d[1] * 17;
      b = d[2] * 17;
      if (d.length == 4) a = d[3] * 17;
    case 6:
    case 8:
      r = d[0] * 16 + d[1];
      g = d[2] * 16 + d[3];
      b = d[4] * 16 + d[5];
      if (d.length == 8) a = d[6] * 16 + d[7];
    default:
      return null;
  }
  return _argb(a, r, g, b);
}

int _argb(int a, int r, int g, int b) => (a << 24) | (r << 16) | (g << 8) | b;

int _channel(double v) => v.isNaN ? 0 : v.clamp(0, 255).round();

/// Separa os argumentos de `rgb()`/`hsl()`: três valores e um alfa opcional,
/// na sintaxe com vírgulas ou na com espaços (`/ alfa`). Devolve também se
/// era a sintaxe com vírgulas.
(List<CssToken>, CssToken?, bool)? _colorArgs(List<CssToken> args) {
  final legacy = args.any((t) => t.type == CssTokenType.comma);
  final values = <CssToken>[];
  CssToken? alpha;
  if (legacy) {
    // v , v , v [, a]
    if (args.length != 5 && args.length != 7) return null;
    for (var i = 0; i < args.length; i++) {
      final isSep = i.isOdd;
      if (isSep != (args[i].type == CssTokenType.comma)) return null;
      if (!isSep) values.add(args[i]);
    }
    if (values.length == 4) alpha = values.removeLast();
  } else {
    // v v v [/ a]
    if (args.length != 3 && args.length != 5) return null;
    values.addAll(args.take(3));
    if (args.length == 5) {
      if (args[3].type != CssTokenType.delim || args[3].value != '/') {
        return null;
      }
      alpha = args[4];
    }
  }
  return (values, alpha, legacy);
}

/// Alfa (número de 0 a 1 ou porcentagem) em 0–255; `null` se inválido.
int? _alpha(CssToken? t) {
  if (t == null) return 255;
  final double v;
  if (t.type == CssTokenType.number) {
    v = t.number;
  } else if (t.type == CssTokenType.percentage) {
    v = t.number / 100;
  } else {
    return null;
  }
  return (v.clamp(0.0, 1.0) * 255).round();
}

int? _rgb(List<CssToken> args) {
  final parsed = _colorArgs(args);
  if (parsed == null) return null;
  final (values, alphaToken, legacy) = parsed;
  final ch = <int>[];
  final firstType = values.first.type;
  for (final t in values) {
    if (legacy && t.type != firstType) return null;
    if (t.type == CssTokenType.number) {
      ch.add(_channel(t.number));
    } else if (t.type == CssTokenType.percentage) {
      ch.add(_channel(t.number * 255 / 100));
    } else {
      return null;
    }
  }
  final a = _alpha(alphaToken);
  if (a == null) return null;
  return _argb(a, ch[0], ch[1], ch[2]);
}

int? _hsl(List<CssToken> args) {
  final parsed = _colorArgs(args);
  if (parsed == null) return null;
  final (values, alphaToken, legacy) = parsed;
  final hueToken = values[0];
  double hue;
  if (hueToken.type == CssTokenType.number) {
    hue = hueToken.number;
  } else if (hueToken.type == CssTokenType.dimension) {
    final v = hueToken.number;
    switch (asciiLower(hueToken.unit)) {
      case 'deg':
        hue = v;
      case 'rad':
        hue = v * 180 / math.pi;
      case 'grad':
        hue = v * 0.9;
      case 'turn':
        hue = v * 360;
      default:
        return null;
    }
  } else {
    return null;
  }
  final sl = <double>[];
  for (final t in values.skip(1)) {
    if (t.type == CssTokenType.percentage ||
        (!legacy && t.type == CssTokenType.number)) {
      sl.add(t.number.clamp(0.0, 100.0) / 100);
    } else {
      return null;
    }
  }
  if (!hue.isFinite) return null;
  hue = hue % 360;
  if (hue < 0) hue += 360;
  final s = sl[0];
  final l = sl[1];
  double f(int n) {
    final k = (n + hue / 30) % 12;
    final a = s * math.min(l, 1 - l);
    return l - a * math.max(-1, math.min(math.min(k - 3, 9 - k), 1));
  }

  final a = _alpha(alphaToken);
  if (a == null) return null;
  return _argb(
    a,
    _channel(f(0) * 255),
    _channel(f(8) * 255),
    _channel(f(4) * 255),
  );
}

/// Cores nomeadas do CSS Color 4 (RGB), sem `transparent` e `currentcolor`.
const Map<String, int> _namedColors = {
  'aliceblue': 0xF0F8FF,
  'antiquewhite': 0xFAEBD7,
  'aqua': 0x00FFFF,
  'aquamarine': 0x7FFFD4,
  'azure': 0xF0FFFF,
  'beige': 0xF5F5DC,
  'bisque': 0xFFE4C4,
  'black': 0x000000,
  'blanchedalmond': 0xFFEBCD,
  'blue': 0x0000FF,
  'blueviolet': 0x8A2BE2,
  'brown': 0xA52A2A,
  'burlywood': 0xDEB887,
  'cadetblue': 0x5F9EA0,
  'chartreuse': 0x7FFF00,
  'chocolate': 0xD2691E,
  'coral': 0xFF7F50,
  'cornflowerblue': 0x6495ED,
  'cornsilk': 0xFFF8DC,
  'crimson': 0xDC143C,
  'cyan': 0x00FFFF,
  'darkblue': 0x00008B,
  'darkcyan': 0x008B8B,
  'darkgoldenrod': 0xB8860B,
  'darkgray': 0xA9A9A9,
  'darkgreen': 0x006400,
  'darkgrey': 0xA9A9A9,
  'darkkhaki': 0xBDB76B,
  'darkmagenta': 0x8B008B,
  'darkolivegreen': 0x556B2F,
  'darkorange': 0xFF8C00,
  'darkorchid': 0x9932CC,
  'darkred': 0x8B0000,
  'darksalmon': 0xE9967A,
  'darkseagreen': 0x8FBC8F,
  'darkslateblue': 0x483D8B,
  'darkslategray': 0x2F4F4F,
  'darkslategrey': 0x2F4F4F,
  'darkturquoise': 0x00CED1,
  'darkviolet': 0x9400D3,
  'deeppink': 0xFF1493,
  'deepskyblue': 0x00BFFF,
  'dimgray': 0x696969,
  'dimgrey': 0x696969,
  'dodgerblue': 0x1E90FF,
  'firebrick': 0xB22222,
  'floralwhite': 0xFFFAF0,
  'forestgreen': 0x228B22,
  'fuchsia': 0xFF00FF,
  'gainsboro': 0xDCDCDC,
  'ghostwhite': 0xF8F8FF,
  'gold': 0xFFD700,
  'goldenrod': 0xDAA520,
  'gray': 0x808080,
  'green': 0x008000,
  'greenyellow': 0xADFF2F,
  'grey': 0x808080,
  'honeydew': 0xF0FFF0,
  'hotpink': 0xFF69B4,
  'indianred': 0xCD5C5C,
  'indigo': 0x4B0082,
  'ivory': 0xFFFFF0,
  'khaki': 0xF0E68C,
  'lavender': 0xE6E6FA,
  'lavenderblush': 0xFFF0F5,
  'lawngreen': 0x7CFC00,
  'lemonchiffon': 0xFFFACD,
  'lightblue': 0xADD8E6,
  'lightcoral': 0xF08080,
  'lightcyan': 0xE0FFFF,
  'lightgoldenrodyellow': 0xFAFAD2,
  'lightgray': 0xD3D3D3,
  'lightgreen': 0x90EE90,
  'lightgrey': 0xD3D3D3,
  'lightpink': 0xFFB6C1,
  'lightsalmon': 0xFFA07A,
  'lightseagreen': 0x20B2AA,
  'lightskyblue': 0x87CEFA,
  'lightslategray': 0x778899,
  'lightslategrey': 0x778899,
  'lightsteelblue': 0xB0C4DE,
  'lightyellow': 0xFFFFE0,
  'lime': 0x00FF00,
  'limegreen': 0x32CD32,
  'linen': 0xFAF0E6,
  'magenta': 0xFF00FF,
  'maroon': 0x800000,
  'mediumaquamarine': 0x66CDAA,
  'mediumblue': 0x0000CD,
  'mediumorchid': 0xBA55D3,
  'mediumpurple': 0x9370DB,
  'mediumseagreen': 0x3CB371,
  'mediumslateblue': 0x7B68EE,
  'mediumspringgreen': 0x00FA9A,
  'mediumturquoise': 0x48D1CC,
  'mediumvioletred': 0xC71585,
  'midnightblue': 0x191970,
  'mintcream': 0xF5FFFA,
  'mistyrose': 0xFFE4E1,
  'moccasin': 0xFFE4B5,
  'navajowhite': 0xFFDEAD,
  'navy': 0x000080,
  'oldlace': 0xFDF5E6,
  'olive': 0x808000,
  'olivedrab': 0x6B8E23,
  'orange': 0xFFA500,
  'orangered': 0xFF4500,
  'orchid': 0xDA70D6,
  'palegoldenrod': 0xEEE8AA,
  'palegreen': 0x98FB98,
  'paleturquoise': 0xAFEEEE,
  'palevioletred': 0xDB7093,
  'papayawhip': 0xFFEFD5,
  'peachpuff': 0xFFDAB9,
  'peru': 0xCD853F,
  'pink': 0xFFC0CB,
  'plum': 0xDDA0DD,
  'powderblue': 0xB0E0E6,
  'purple': 0x800080,
  'rebeccapurple': 0x663399,
  'red': 0xFF0000,
  'rosybrown': 0xBC8F8F,
  'royalblue': 0x4169E1,
  'saddlebrown': 0x8B4513,
  'salmon': 0xFA8072,
  'sandybrown': 0xF4A460,
  'seagreen': 0x2E8B57,
  'seashell': 0xFFF5EE,
  'sienna': 0xA0522D,
  'silver': 0xC0C0C0,
  'skyblue': 0x87CEEB,
  'slateblue': 0x6A5ACD,
  'slategray': 0x708090,
  'slategrey': 0x708090,
  'snow': 0xFFFAFA,
  'springgreen': 0x00FF7F,
  'steelblue': 0x4682B4,
  'tan': 0xD2B48C,
  'teal': 0x008080,
  'thistle': 0xD8BFD8,
  'tomato': 0xFF6347,
  'turquoise': 0x40E0D0,
  'violet': 0xEE82EE,
  'wheat': 0xF5DEB3,
  'white': 0xFFFFFF,
  'whitesmoke': 0xF5F5F5,
  'yellow': 0xFFFF00,
  'yellowgreen': 0x9ACD32,
};
