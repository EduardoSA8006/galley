import 'package:meta/meta.dart';

/// Tipos de token do CSS Syntax Level 3 (sem `EOF`, que não é emitido).
enum CssTokenType {
  /// Identificador.
  ident,

  /// Nome seguido de `(`.
  function,

  /// `@nome`.
  atKeyword,

  /// `#nome`.
  hash,

  /// Texto entre aspas.
  string,

  /// Texto entre aspas interrompido por quebra de linha.
  badString,

  /// `url(...)` sem aspas.
  url,

  /// `url(...)` sem aspas, malformado.
  badUrl,

  /// Qualquer outro caractere isolado.
  delim,

  /// Número sem unidade.
  number,

  /// Número seguido de `%`.
  percentage,

  /// Número seguido de unidade.
  dimension,

  /// Espaço em branco.
  whitespace,

  /// `<!--`.
  cdo,

  /// `-->`.
  cdc,

  /// `:`.
  colon,

  /// `;`.
  semicolon,

  /// `,`.
  comma,

  /// `[`.
  leftSquare,

  /// `]`.
  rightSquare,

  /// `(`.
  leftParen,

  /// `)`.
  rightParen,

  /// `{`.
  leftBrace,

  /// `}`.
  rightBrace,
}

/// Um token de CSS.
///
/// [start] e [end] (exclusivo) são deslocamentos em unidades UTF-16 no texto
/// **pré-processado** (ver [preprocessCss]).
@immutable
final class CssToken {
  /// Cria um token.
  const CssToken(
    this.type,
    this.start,
    this.end, {
    this.value = '',
    this.number = 0,
    this.isInteger = false,
    this.unit = '',
    this.isIdHash = false,
    this.hasSign = false,
  });

  /// Tipo do token.
  final CssTokenType type;

  /// Nome do ident, da função, do at-keyword e do hash; conteúdo da string e
  /// da url; caractere do delim. Vazio nos demais tipos.
  final String value;

  /// Valor numérico (number, percentage e dimension).
  final double number;

  /// Se o número foi escrito sem parte fracionária nem expoente.
  final bool isInteger;

  /// Unidade de uma dimension (caixa original preservada).
  final String unit;

  /// Se o número (number, percentage e dimension) foi escrito com sinal
  /// explícito (`+5`, `-2n`); a microssintaxe An+B distingue `+5` de `5`.
  final bool hasSign;

  /// Se um hash tem sintaxe de identificador (`#id` sim, `#1a` não).
  final bool isIdHash;

  /// Início no texto pré-processado.
  final int start;

  /// Fim (exclusivo) no texto pré-processado.
  final int end;

  @override
  String toString() => 'CssToken($type, "$value", $start-$end)';
}

/// Pré-processa o texto de uma folha (CSS Syntax §3.3): CR, CRLF e FF viram
/// LF; NUL e surrogates soltos viram U+FFFD.
///
/// Devolve a própria [input] quando nada muda.
String preprocessCss(String input) {
  final n = input.length;
  var i = 0;
  for (; i < n; i++) {
    final c = input.codeUnitAt(i);
    if (c == 0x0D || c == 0x0C || c == 0 || (c >= 0xD800 && c <= 0xDFFF)) {
      break;
    }
  }
  if (i == n) return input;
  final out = StringBuffer(input.substring(0, i));
  for (; i < n; i++) {
    final c = input.codeUnitAt(i);
    if (c == 0x0D) {
      if (i + 1 < n && input.codeUnitAt(i + 1) == 0x0A) i++;
      out.writeCharCode(0x0A);
    } else if (c == 0x0C) {
      out.writeCharCode(0x0A);
    } else if (c == 0) {
      out.writeCharCode(0xFFFD);
    } else if (c >= 0xD800 && c <= 0xDBFF) {
      if (i + 1 < n &&
          input.codeUnitAt(i + 1) >= 0xDC00 &&
          input.codeUnitAt(i + 1) <= 0xDFFF) {
        out.writeCharCode(c);
        out.writeCharCode(input.codeUnitAt(++i));
      } else {
        out.writeCharCode(0xFFFD);
      }
    } else if (c >= 0xDC00 && c <= 0xDFFF) {
      out.writeCharCode(0xFFFD);
    } else {
      out.writeCharCode(c);
    }
  }
  return out.toString();
}

/// Tokeniza [source] (CSS Syntax Level 3, §4). Pré-processa o texto, descarta
/// os comentários e não emite token de fim de arquivo. Os deslocamentos dos
/// tokens valem no texto devolvido por [preprocessCss].
List<CssToken> tokenizeCss(String source) =>
    _Tokenizer(preprocessCss(source)).run();

const _eof = -1;

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;
bool _isHex(int c) =>
    _isDigit(c) || (c >= 0x41 && c <= 0x46) || (c >= 0x61 && c <= 0x66);
bool _isNameStart(int c) =>
    (c >= 0x41 && c <= 0x5A) ||
    (c >= 0x61 && c <= 0x7A) ||
    c == 0x5F ||
    c >= 0x80;
bool _isName(int c) => _isNameStart(c) || _isDigit(c) || c == 0x2D;
bool _isWs(int c) => c == 0x20 || c == 0x09 || c == 0x0A;
bool _isNonPrintable(int c) =>
    (c >= 0 && c <= 8) || c == 0x0B || (c >= 0x0E && c <= 0x1F) || c == 0x7F;

final class _Tokenizer {
  _Tokenizer(this.s) : n = s.length;

  final String s;
  final int n;
  int p = 0;
  final List<CssToken> out = [];

  int at(int i) => i < n ? s.codeUnitAt(i) : _eof;

  bool validEscape(int i) => at(i) == 0x5C && at(i + 1) != 0x0A;

  bool startsIdent(int i) {
    final a = at(i);
    if (a == 0x2D) {
      final b = at(i + 1);
      return _isNameStart(b) || b == 0x2D || validEscape(i + 1);
    }
    if (_isNameStart(a)) return true;
    return validEscape(i);
  }

  bool startsNumber(int i) {
    final a = at(i);
    if (a == 0x2B || a == 0x2D) {
      final b = at(i + 1);
      return _isDigit(b) || (b == 0x2E && _isDigit(at(i + 2)));
    }
    if (a == 0x2E) return _isDigit(at(i + 1));
    return _isDigit(a);
  }

  List<CssToken> run() {
    while (true) {
      _skipComments();
      if (p >= n) break;
      _next();
    }
    return out;
  }

  void _skipComments() {
    while (at(p) == 0x2F && at(p + 1) == 0x2A) {
      final close = s.indexOf('*/', p + 2);
      p = close < 0 ? n : close + 2;
    }
  }

  void _add(CssTokenType t, int start, {String value = ''}) =>
      out.add(CssToken(t, start, p, value: value));

  void _next() {
    final start = p;
    final c = s.codeUnitAt(p);
    if (_isWs(c)) {
      while (_isWs(at(p))) {
        p++;
      }
      _add(CssTokenType.whitespace, start);
      return;
    }
    switch (c) {
      case 0x22:
      case 0x27:
        _string(c, start);
      case 0x23:
        p++;
        if (_isName(at(p)) || validEscape(p)) {
          final id = startsIdent(p);
          final name = _name();
          out.add(
            CssToken(CssTokenType.hash, start, p, value: name, isIdHash: id),
          );
        } else {
          _delim(start);
        }
      case 0x28:
        p++;
        _add(CssTokenType.leftParen, start);
      case 0x29:
        p++;
        _add(CssTokenType.rightParen, start);
      case 0x2C:
        p++;
        _add(CssTokenType.comma, start);
      case 0x3A:
        p++;
        _add(CssTokenType.colon, start);
      case 0x3B:
        p++;
        _add(CssTokenType.semicolon, start);
      case 0x5B:
        p++;
        _add(CssTokenType.leftSquare, start);
      case 0x5D:
        p++;
        _add(CssTokenType.rightSquare, start);
      case 0x7B:
        p++;
        _add(CssTokenType.leftBrace, start);
      case 0x7D:
        p++;
        _add(CssTokenType.rightBrace, start);
      case 0x2B:
      case 0x2E:
        if (startsNumber(p)) {
          _numeric(start);
        } else {
          _delim(start);
        }
      case 0x2D:
        if (startsNumber(p)) {
          _numeric(start);
        } else if (at(p + 1) == 0x2D && at(p + 2) == 0x3E) {
          p += 3;
          _add(CssTokenType.cdc, start);
        } else if (startsIdent(p)) {
          _identLike(start);
        } else {
          _delim(start);
        }
      case 0x3C:
        if (at(p + 1) == 0x21 && at(p + 2) == 0x2D && at(p + 3) == 0x2D) {
          p += 4;
          _add(CssTokenType.cdo, start);
        } else {
          _delim(start);
        }
      case 0x40:
        p++;
        if (startsIdent(p)) {
          final name = _name();
          _add(CssTokenType.atKeyword, start, value: name);
        } else {
          p = start;
          _delim(start);
        }
      case 0x5C:
        if (validEscape(p)) {
          _identLike(start);
        } else {
          _delim(start);
        }
      default:
        if (_isDigit(c)) {
          _numeric(start);
        } else if (_isNameStart(c)) {
          _identLike(start);
        } else {
          _delim(start);
        }
    }
  }

  /// Consome um caractere como delim (um ponto de código completo).
  void _delim(int start) {
    p = start;
    final c = s.codeUnitAt(p);
    p += (c >= 0xD800 && c <= 0xDBFF && p + 1 < n) ? 2 : 1;
    _add(CssTokenType.delim, start, value: s.substring(start, p));
  }

  /// Consome um escape (o `\` já foi verificado como válido e está em [p]).
  void _escape(StringBuffer b) {
    p++; // a barra
    final c = at(p);
    if (c == _eof) {
      b.writeCharCode(0xFFFD);
      return;
    }
    if (_isHex(c)) {
      var v = 0;
      var count = 0;
      while (count < 6 && _isHex(at(p))) {
        v = v * 16 + int.parse(s[p], radix: 16);
        p++;
        count++;
      }
      if (_isWs(at(p))) p++;
      if (v == 0 || (v >= 0xD800 && v <= 0xDFFF) || v > 0x10FFFF) {
        b.writeCharCode(0xFFFD);
      } else {
        b.writeCharCode(v);
      }
      return;
    }
    b.writeCharCode(c);
    p++;
  }

  String _name() {
    final b = StringBuffer();
    while (true) {
      final c = at(p);
      if (_isName(c)) {
        b.writeCharCode(c);
        p++;
      } else if (validEscape(p)) {
        _escape(b);
      } else {
        return b.toString();
      }
    }
  }

  void _identLike(int start) {
    final name = _name();
    if (at(p) == 0x28) {
      p++;
      if (name.length == 3 && name.toLowerCase() == 'url') {
        while (_isWs(at(p)) && _isWs(at(p + 1))) {
          p++;
        }
        final a = at(p);
        final quoted =
            a == 0x22 ||
            a == 0x27 ||
            (_isWs(a) && (at(p + 1) == 0x22 || at(p + 1) == 0x27));
        if (!quoted) {
          _url(start);
          return;
        }
      }
      _add(CssTokenType.function, start, value: name);
      return;
    }
    _add(CssTokenType.ident, start, value: name);
  }

  void _url(int start) {
    while (_isWs(at(p))) {
      p++;
    }
    final b = StringBuffer();
    while (true) {
      final c = at(p);
      if (c == 0x29) {
        p++;
        break;
      }
      if (c == _eof) break;
      if (_isWs(c)) {
        while (_isWs(at(p))) {
          p++;
        }
        if (at(p) == 0x29) {
          p++;
          break;
        }
        if (at(p) == _eof) break;
        _badUrlRemnants();
        _add(CssTokenType.badUrl, start);
        return;
      }
      if (c == 0x22 || c == 0x27 || c == 0x28 || _isNonPrintable(c)) {
        _badUrlRemnants();
        _add(CssTokenType.badUrl, start);
        return;
      }
      if (c == 0x5C) {
        if (validEscape(p)) {
          _escape(b);
        } else {
          _badUrlRemnants();
          _add(CssTokenType.badUrl, start);
          return;
        }
        continue;
      }
      b.writeCharCode(c);
      p++;
    }
    _add(CssTokenType.url, start, value: b.toString());
  }

  void _badUrlRemnants() {
    final sink = StringBuffer();
    while (true) {
      final c = at(p);
      if (c == 0x29) {
        p++;
        return;
      }
      if (c == _eof) return;
      if (validEscape(p)) {
        _escape(sink);
        sink.clear();
      } else {
        p++;
      }
    }
  }

  void _string(int quote, int start) {
    p++;
    final b = StringBuffer();
    while (true) {
      final c = at(p);
      if (c == quote) {
        p++;
        break;
      }
      if (c == _eof) break;
      if (c == 0x0A) {
        _add(CssTokenType.badString, start);
        return;
      }
      if (c == 0x5C) {
        final next = at(p + 1);
        if (next == _eof) {
          p++;
        } else if (next == 0x0A) {
          p += 2;
        } else {
          _escape(b);
        }
        continue;
      }
      b.writeCharCode(c);
      p++;
    }
    _add(CssTokenType.string, start, value: b.toString());
  }

  void _numeric(int start) {
    final numStart = p;
    var isInt = true;
    final signed = at(p) == 0x2B || at(p) == 0x2D;
    if (signed) p++;
    while (_isDigit(at(p))) {
      p++;
    }
    if (at(p) == 0x2E && _isDigit(at(p + 1))) {
      isInt = false;
      p++;
      while (_isDigit(at(p))) {
        p++;
      }
    }
    if (at(p) == 0x45 || at(p) == 0x65) {
      final a = at(p + 1);
      if (_isDigit(a) || ((a == 0x2B || a == 0x2D) && _isDigit(at(p + 2)))) {
        isInt = false;
        p += 2;
        while (_isDigit(at(p))) {
          p++;
        }
      }
    }
    var v = double.parse(s.substring(numStart, p));
    if (v.isInfinite) v = v.isNegative ? -double.maxFinite : double.maxFinite;
    if (startsIdent(p)) {
      final unit = _name();
      out.add(
        CssToken(
          CssTokenType.dimension,
          start,
          p,
          number: v,
          isInteger: isInt,
          unit: unit,
          hasSign: signed,
        ),
      );
    } else if (at(p) == 0x25) {
      p++;
      out.add(
        CssToken(
          CssTokenType.percentage,
          start,
          p,
          number: v,
          isInteger: isInt,
          hasSign: signed,
        ),
      );
    } else {
      out.add(
        CssToken(
          CssTokenType.number,
          start,
          p,
          number: v,
          isInteger: isInt,
          hasSign: signed,
        ),
      );
    }
  }
}
