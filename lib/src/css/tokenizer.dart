/// Tokenizador do CSS Syntax Level 3 §4 (spec do CSS §4), recortado ao que o
/// parser usa.
///
/// Linear no tamanho do texto:
/// - um índice só avança; cada unidade de código é lida um número constante
///   de vezes (o escape olha no máximo 7 à frente e não volta);
/// - o valor de cada token é uma `substring` do trecho dele ou, a partir do
///   primeiro escape ou código trocado pelo pré-processamento, um
///   `StringBuffer`: a soma dos valores é ≤ o tamanho do texto;
/// - comentário, string e `url` sem fim consomem até o fim do texto uma vez;
/// - sem `RegExp`, sem `split`, sem busca para trás, sem lista de tokens.
library;

/// Literal numérico acima disto vira `NaN` (spec do CSS §4, regra 6).
const int maxNumericLiteralLength = 64;

enum CssTokenType {
  ident,
  function,
  atKeyword,
  hash,
  string,
  badString,
  url,
  badUrl,
  delim,
  number,
  percentage,
  dimension,
  whitespace,
  cdo,
  cdc,
  colon,
  semicolon,
  comma,
  leftBracket,
  rightBracket,
  leftParen,
  rightParen,
  leftBrace,
  rightBrace,
  eof,
}

/// Um token do CSS Syntax §4.
final class CssToken {
  const CssToken(
    this.type, {
    this.value = '',
    this.number = 0,
    this.isInteger = false,
    this.unit = '',
    this.isIdHash = false,
  });

  static const CssToken eof = CssToken(CssTokenType.eof);
  static const CssToken whitespace = CssToken(CssTokenType.whitespace);

  final CssTokenType type;

  /// `ident`, `function`, `atKeyword`, `hash`, `string`, `url`: o valor com os
  /// escapes resolvidos (sem `(`, `@`, `#` nem aspas). `delim`: o caractere.
  /// `number`, `percentage`, `dimension`: o literal numérico como escrito
  /// (sinal incluído, sem `%` nem unidade) — o An+B de `:nth-child` precisa
  /// saber se havia sinal.
  final String value;

  /// `number`, `percentage`, `dimension`; `NaN` se o literal passa de
  /// [maxNumericLiteralLength] caracteres. Também pode ser `±Infinity` com
  /// literal curto (`1e999`): quem consome trata valor não finito.
  final double number;

  /// Literal sem `.` nem expoente.
  final bool isInteger;

  /// `dimension`: a unidade em minúsculas ASCII; `''` nos outros.
  final String unit;

  /// `hash` cujo valor começa como identificador (serve de `#id`).
  final bool isIdHash;

  @override
  String toString() => switch (type) {
    CssTokenType.ident => 'ident($value)',
    CssTokenType.function => 'function($value)',
    CssTokenType.atKeyword => 'at($value)',
    CssTokenType.hash => isIdHash ? 'hash-id($value)' : 'hash($value)',
    CssTokenType.string => 'string($value)',
    CssTokenType.url => 'url($value)',
    CssTokenType.delim => 'delim($value)',
    CssTokenType.number => 'number($value${isInteger ? ' int' : ''})',
    CssTokenType.percentage => 'percentage($value)',
    CssTokenType.dimension => 'dimension($value $unit)',
    _ => type.name,
  };
}

/// [s] com `A`–`Z` trocados por `a`–`z` (só ASCII: o CSS compara sem caixa
/// ASCII, e `toLowerCase` do Dart muda também não ASCII, como `İ`).
String cssAsciiLower(String s) {
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c >= 0x41 && c <= 0x5A) {
      final b = StringBuffer(s.substring(0, i));
      for (var j = i; j < s.length; j++) {
        final d = s.codeUnitAt(j);
        b.writeCharCode(d >= 0x41 && d <= 0x5A ? d + 0x20 : d);
      }
      return b.toString();
    }
  }
  return s;
}

/// [s] igual a [lower] (já em minúsculas ASCII) sem diferença de caixa ASCII.
/// Custa no máximo `lower.length` passos.
bool cssAsciiEquals(String s, String lower) {
  if (s.length != lower.length) return false;
  for (var i = 0; i < s.length; i++) {
    var c = s.codeUnitAt(i);
    if (c >= 0x41 && c <= 0x5A) c += 0x20;
    if (c != lower.codeUnitAt(i)) return false;
  }
  return true;
}

bool _isWhitespace(int cp) => cp == 0x20 || cp == 0x09 || cp == 0x0A;

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

int _hexValue(int c) {
  if (c >= 0x30 && c <= 0x39) return c - 0x30;
  if (c >= 0x41 && c <= 0x46) return c - 0x41 + 10;
  if (c >= 0x61 && c <= 0x66) return c - 0x61 + 10;
  return -1;
}

/// Letra, `_` ou não ASCII (CSS Syntax 3 §4.2, "ident-start code point").
bool _isIdentStart(int cp) =>
    (cp >= 0x61 && cp <= 0x7A) ||
    (cp >= 0x41 && cp <= 0x5A) ||
    cp == 0x5F ||
    cp >= 0x80;

bool _isIdentCodePoint(int cp) =>
    _isIdentStart(cp) || _isDigit(cp) || cp == 0x2D;

/// CSS Syntax 3 §4.2, "non-printable code point".
bool _isNonPrintable(int cp) =>
    (cp >= 0 && cp <= 0x08) ||
    cp == 0x0B ||
    (cp >= 0x0E && cp <= 0x1F) ||
    cp == 0x7F;

/// Valor de um token: fatias do texto enquanto nada muda; um `StringBuffer`
/// a partir do primeiro escape ou código trocado.
final class _ValueBuilder {
  _ValueBuilder(this._s, this._start);

  final String _s;
  int _start;
  StringBuffer? _buffer;

  /// O texto de `[at, next)` sai do valor e, se [cp] ≥ 0, entra [cp].
  void replace(int at, int next, int cp) {
    final b = _buffer ??= StringBuffer();
    b.write(_s.substring(_start, at));
    if (cp >= 0) b.writeCharCode(cp);
    _start = next;
  }

  String finish(int end) {
    final b = _buffer;
    if (b == null) return _s.substring(_start, end);
    b.write(_s.substring(_start, end));
    return b.toString();
  }
}

/// Lê um texto do começo ao fim; depois do último token, [next] devolve
/// `eof` para sempre.
final class CssTokenizer {
  CssTokenizer(this._s) : _n = _s.length;

  final String _s;
  final int _n;
  int _i = 0;

  /// Largura, em unidades de código, do último código lido por [_cpAt].
  int _w = 0;

  /// Código em [at] depois do pré-processamento (CSS Syntax §3.3): CR, CRLF
  /// e FF viram LF; U+0000 e surrogate solto viram U+FFFD. `-1` no fim.
  int _cpAt(int at) {
    if (at >= _n) {
      _w = 0;
      return -1;
    }
    final c = _s.codeUnitAt(at);
    if (c == 0x0D) {
      _w = at + 1 < _n && _s.codeUnitAt(at + 1) == 0x0A ? 2 : 1;
      return 0x0A;
    }
    _w = 1;
    if (c == 0x0C) return 0x0A;
    if (c == 0) return 0xFFFD;
    if (c >= 0xD800 && c <= 0xDBFF && at + 1 < _n) {
      final d = _s.codeUnitAt(at + 1);
      if (d >= 0xDC00 && d <= 0xDFFF) {
        _w = 2;
        return 0x10000 + ((c - 0xD800) << 10) + (d - 0xDC00);
      }
    }
    if (c >= 0xD800 && c <= 0xDFFF) return 0xFFFD;
    return c;
  }

  /// O código [cp] lido em [at] é o próprio texto (nenhuma troca).
  bool _isRaw(int at, int cp) => cp > 0xFFFF || _s.codeUnitAt(at) == cp;

  /// CSS Syntax §4.3.8: `\` seguido de algo que não é LF (o fim conta).
  bool _validEscapeAt(int at) {
    if (_cpAt(at) != 0x5C) return false;
    return _cpAt(at + 1) != 0x0A;
  }

  /// CSS Syntax §4.3.9, "would start an ident sequence", a partir de [at].
  bool _wouldStartIdent(int at) {
    final a = _cpAt(at);
    final wa = _w;
    if (a == 0x2D) {
      final b = _cpAt(at + wa);
      if (_isIdentStart(b) || b == 0x2D) return true;
      return b == 0x5C && _validEscapeAt(at + wa);
    }
    if (_isIdentStart(a)) return true;
    return a == 0x5C && _validEscapeAt(at);
  }

  /// CSS Syntax §4.3.10, "starts with a number" (só ASCII: sem troca).
  bool _startsNumber(int at) {
    int unit(int k) => at + k < _n ? _s.codeUnitAt(at + k) : -1;
    final a = unit(0);
    if (a == 0x2B || a == 0x2D) {
      final b = unit(1);
      if (_isDigit(b)) return true;
      return b == 0x2E && _isDigit(unit(2));
    }
    if (a == 0x2E) return _isDigit(unit(1));
    return _isDigit(a);
  }

  void _skipWhitespace() {
    while (_isWhitespace(_cpAt(_i))) {
      _i += _w;
    }
  }

  /// CSS Syntax §4.3.7, "consume an escaped code point", com o `\` já
  /// consumido.
  int _consumeEscape() {
    final cp = _cpAt(_i);
    if (cp < 0) return 0xFFFD;
    if (_hexValue(cp) < 0) {
      _i += _w;
      return cp;
    }
    var value = 0;
    for (var count = 0; count < 6; count++) {
      final h = _hexValue(_cpAt(_i));
      if (h < 0) break;
      value = value * 16 + h;
      _i += 1;
    }
    if (_isWhitespace(_cpAt(_i))) _i += _w;
    if (value == 0 ||
        (value >= 0xD800 && value <= 0xDFFF) ||
        value > 0x10FFFF) {
      return 0xFFFD;
    }
    return value;
  }

  /// CSS Syntax §4.3.11, "consume an ident sequence".
  String _consumeIdentSequence() {
    final v = _ValueBuilder(_s, _i);
    while (true) {
      final at = _i;
      final cp = _cpAt(at);
      if (_isIdentCodePoint(cp)) {
        _i += _w;
        if (!_isRaw(at, cp)) v.replace(at, _i, cp);
      } else if (cp == 0x5C && _validEscapeAt(at)) {
        _i = at + 1;
        final e = _consumeEscape();
        v.replace(at, _i, e);
      } else {
        return v.finish(at);
      }
    }
  }

  /// CSS Syntax §4.3.5, "consume a string token", com a aspa já consumida.
  CssToken _consumeString(int quote) {
    final v = _ValueBuilder(_s, _i);
    while (true) {
      final at = _i;
      final cp = _cpAt(at);
      final w = _w;
      if (cp < 0) return CssToken(CssTokenType.string, value: v.finish(at));
      if (cp == quote) {
        _i += w;
        return CssToken(CssTokenType.string, value: v.finish(at));
      }
      if (cp == 0x0A) {
        // O LF não é consumido: é o próximo token.
        return CssToken(CssTokenType.badString, value: v.finish(at));
      }
      if (cp == 0x5C) {
        final next = _cpAt(at + 1);
        if (next < 0) {
          // `\` no fim do texto some.
          _i = at + 1;
          v.replace(at, _i, -1);
        } else if (next == 0x0A) {
          // `\` + LF é continuação: os dois somem.
          _i = at + 1 + _w;
          v.replace(at, _i, -1);
        } else {
          _i = at + 1;
          final e = _consumeEscape();
          v.replace(at, _i, e);
        }
        continue;
      }
      _i += w;
      if (!_isRaw(at, cp)) v.replace(at, _i, cp);
    }
  }

  /// CSS Syntax §4.3.14, "consume the remnants of a bad url".
  CssToken _consumeBadUrlRemnants() {
    while (true) {
      final at = _i;
      final cp = _cpAt(at);
      if (cp < 0) break;
      if (cp == 0x29) {
        _i += _w;
        break;
      }
      if (cp == 0x5C && _validEscapeAt(at)) {
        _i = at + 1;
        _consumeEscape();
      } else {
        _i += _w;
      }
    }
    return const CssToken(CssTokenType.badUrl);
  }

  /// CSS Syntax §4.3.6, "consume a url token", com `url(` já consumido.
  CssToken _consumeUrl() {
    _skipWhitespace();
    final v = _ValueBuilder(_s, _i);
    while (true) {
      final at = _i;
      final cp = _cpAt(at);
      final w = _w;
      if (cp < 0) return CssToken(CssTokenType.url, value: v.finish(at));
      if (cp == 0x29) {
        _i += w;
        return CssToken(CssTokenType.url, value: v.finish(at));
      }
      if (_isWhitespace(cp)) {
        final value = v.finish(at);
        _skipWhitespace();
        final c = _cpAt(_i);
        if (c < 0) return CssToken(CssTokenType.url, value: value);
        if (c == 0x29) {
          _i += _w;
          return CssToken(CssTokenType.url, value: value);
        }
        return _consumeBadUrlRemnants();
      }
      if (cp == 0x22 || cp == 0x27 || cp == 0x28 || _isNonPrintable(cp)) {
        return _consumeBadUrlRemnants();
      }
      if (cp == 0x5C) {
        if (!_validEscapeAt(at)) return _consumeBadUrlRemnants();
        _i = at + 1;
        final e = _consumeEscape();
        v.replace(at, _i, e);
        continue;
      }
      _i += w;
      if (!_isRaw(at, cp)) v.replace(at, _i, cp);
    }
  }

  /// CSS Syntax §4.3.4, "consume an ident-like token".
  CssToken _consumeIdentLike() {
    final name = _consumeIdentSequence();
    if (_cpAt(_i) != 0x28) return CssToken(CssTokenType.ident, value: name);
    _i += 1;
    if (!cssAsciiEquals(name, 'url')) {
      return CssToken(CssTokenType.function, value: name);
    }
    // Enquanto os dois próximos são espaço, consome um.
    while (true) {
      final a = _cpAt(_i);
      final wa = _w;
      if (!_isWhitespace(a) || !_isWhitespace(_cpAt(_i + wa))) break;
      _i += wa;
    }
    final a = _cpAt(_i);
    final b = _isWhitespace(a) ? _cpAt(_i + _w) : -1;
    if (a == 0x22 || a == 0x27 || b == 0x22 || b == 0x27) {
      return CssToken(CssTokenType.function, value: name);
    }
    return _consumeUrl();
  }

  /// CSS Syntax §4.3.3 e §4.3.12, "consume a numeric token".
  CssToken _consumeNumeric() {
    final start = _i;
    var integer = true;
    int unit(int at) => at < _n ? _s.codeUnitAt(at) : -1;
    if (unit(_i) == 0x2B || unit(_i) == 0x2D) _i++;
    while (_isDigit(unit(_i))) {
      _i++;
    }
    if (unit(_i) == 0x2E && _isDigit(unit(_i + 1))) {
      integer = false;
      _i += 2;
      while (_isDigit(unit(_i))) {
        _i++;
      }
    }
    final e = unit(_i);
    if (e == 0x45 || e == 0x65) {
      final s = unit(_i + 1);
      final signed = s == 0x2B || s == 0x2D;
      if (_isDigit(signed ? unit(_i + 2) : s)) {
        integer = false;
        _i += signed ? 3 : 2;
        while (_isDigit(unit(_i))) {
          _i++;
        }
      }
    }
    final repr = _s.substring(start, _i);
    final number = repr.length > maxNumericLiteralLength
        ? double.nan
        : double.tryParse(repr) ?? double.nan;
    if (_wouldStartIdent(_i)) {
      return CssToken(
        CssTokenType.dimension,
        value: repr,
        number: number,
        isInteger: integer,
        unit: cssAsciiLower(_consumeIdentSequence()),
      );
    }
    if (unit(_i) == 0x25) {
      _i++;
      return CssToken(
        CssTokenType.percentage,
        value: repr,
        number: number,
        isInteger: integer,
      );
    }
    return CssToken(
      CssTokenType.number,
      value: repr,
      number: number,
      isInteger: integer,
    );
  }

  CssToken _single(CssTokenType type) {
    _i++;
    return CssToken(type);
  }

  CssToken _delim(int cp, int width) {
    _i += width;
    return CssToken(CssTokenType.delim, value: String.fromCharCode(cp));
  }

  /// CSS Syntax §4.3.1, "consume a token" (comentários antes, §4.3.2).
  CssToken next() {
    while (_i + 1 < _n &&
        _s.codeUnitAt(_i) == 0x2F &&
        _s.codeUnitAt(_i + 1) == 0x2A) {
      final end = _s.indexOf('*/', _i + 2);
      _i = end < 0 ? _n : end + 2;
    }
    final at = _i;
    final cp = _cpAt(at);
    final w = _w;
    if (cp < 0) return CssToken.eof;
    if (_isWhitespace(cp)) {
      _skipWhitespace();
      return CssToken.whitespace;
    }
    switch (cp) {
      case 0x22 || 0x27:
        _i += 1;
        return _consumeString(cp);
      case 0x23:
        final a = _cpAt(at + 1);
        if (_isIdentCodePoint(a) || _validEscapeAt(at + 1)) {
          _i = at + 1;
          final isId = _wouldStartIdent(_i);
          return CssToken(
            CssTokenType.hash,
            value: _consumeIdentSequence(),
            isIdHash: isId,
          );
        }
        return _delim(cp, w);
      case 0x28:
        return _single(CssTokenType.leftParen);
      case 0x29:
        return _single(CssTokenType.rightParen);
      case 0x2B || 0x2E:
        if (_startsNumber(at)) return _consumeNumeric();
        return _delim(cp, w);
      case 0x2C:
        return _single(CssTokenType.comma);
      case 0x2D:
        if (_startsNumber(at)) return _consumeNumeric();
        if (_s.startsWith('->', at + 1)) {
          _i += 3;
          return const CssToken(CssTokenType.cdc);
        }
        if (_wouldStartIdent(at)) return _consumeIdentLike();
        return _delim(cp, w);
      case 0x3A:
        return _single(CssTokenType.colon);
      case 0x3B:
        return _single(CssTokenType.semicolon);
      case 0x3C:
        if (_s.startsWith('!--', at + 1)) {
          _i += 4;
          return const CssToken(CssTokenType.cdo);
        }
        return _delim(cp, w);
      case 0x40:
        if (_wouldStartIdent(at + 1)) {
          _i = at + 1;
          return CssToken(
            CssTokenType.atKeyword,
            value: _consumeIdentSequence(),
          );
        }
        return _delim(cp, w);
      case 0x5B:
        return _single(CssTokenType.leftBracket);
      case 0x5C:
        if (_validEscapeAt(at)) return _consumeIdentLike();
        return _delim(cp, w);
      case 0x5D:
        return _single(CssTokenType.rightBracket);
      case 0x7B:
        return _single(CssTokenType.leftBrace);
      case 0x7D:
        return _single(CssTokenType.rightBrace);
    }
    if (_isDigit(cp)) return _consumeNumeric();
    if (_isIdentStart(cp)) return _consumeIdentLike();
    return _delim(cp, w);
  }
}

/// Tamanho das amostras em `details` (spec do CSS §11).
const int maxSampleLength = 64;

/// Texto aproximado dos tokens `[start, end)` de [tokens], para amostra de
/// diagnóstico: no máximo [maxSampleLength] unidades de código, sem cortar
/// um par de surrogates e sem espaço nas pontas. Custa O([maxSampleLength])
/// mais o número de tokens percorridos, qualquer que seja o tamanho deles.
String cssSample(List<CssToken> tokens, [int start = 0, int? end]) {
  final stop = end ?? tokens.length;
  final b = StringBuffer();
  void write(String s) {
    final room = maxSampleLength + 1 - b.length;
    if (room <= 0) return;
    b.write(s.length <= room ? s : s.substring(0, room));
  }

  for (var i = start; i < stop && b.length <= maxSampleLength; i++) {
    final t = tokens[i];
    switch (t.type) {
      case CssTokenType.ident || CssTokenType.delim || CssTokenType.number:
        write(t.value);
      case CssTokenType.function:
        write(t.value);
        write('(');
      case CssTokenType.atKeyword:
        write('@');
        write(t.value);
      case CssTokenType.hash:
        write('#');
        write(t.value);
      case CssTokenType.string:
        write('"');
        write(t.value);
        write('"');
      case CssTokenType.badString:
        write('"');
      case CssTokenType.url:
        write('url(');
        write(t.value);
        write(')');
      case CssTokenType.badUrl:
        write('url()');
      case CssTokenType.percentage:
        write(t.value);
        write('%');
      case CssTokenType.dimension:
        write(t.value);
        write(t.unit);
      case CssTokenType.whitespace:
        write(' ');
      case CssTokenType.cdo:
        write('<!--');
      case CssTokenType.cdc:
        write('-->');
      case CssTokenType.colon:
        write(':');
      case CssTokenType.semicolon:
        write(';');
      case CssTokenType.comma:
        write(',');
      case CssTokenType.leftBracket:
        write('[');
      case CssTokenType.rightBracket:
        write(']');
      case CssTokenType.leftParen:
        write('(');
      case CssTokenType.rightParen:
        write(')');
      case CssTokenType.leftBrace:
        write('{');
      case CssTokenType.rightBrace:
        write('}');
      case CssTokenType.eof:
        break;
    }
  }
  return truncateSample(b.toString().trim());
}

/// [s] cortado em [maxSampleLength] unidades de código sem separar um par de
/// surrogates.
String truncateSample(String s) {
  var end = s.length < maxSampleLength ? s.length : maxSampleLength;
  // Os tokens não têm surrogate solto (o pré-processamento os troca por
  // U+FFFD): um surrogate alto no fim só pode vir do corte de `write`.
  if (end > 0) {
    final last = s.codeUnitAt(end - 1);
    if (last >= 0xD800 && last <= 0xDBFF) end--;
  }
  return end == s.length ? s : s.substring(0, end);
}
