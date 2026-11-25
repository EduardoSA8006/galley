import 'dart:convert';
import 'dart:typed_data';

/// Decodifica os bytes de uma folha CSS para texto (CSS Syntax Level 3, §3.2).
///
/// A ordem de decisão é: BOM (UTF-8, UTF-16LE, UTF-16BE), depois a regra
/// `@charset "<rótulo>";` (com os bytes exatos da especificação, só aspas
/// duplas, no início da folha), depois UTF-8. Rótulos `iso-8859-1`, `latin1`,
/// `us-ascii` e `windows-1252` decodificam como windows-1252; `utf-16*` e
/// rótulos desconhecidos caem em UTF-8 (a regra `@charset` de uma folha que já
/// foi lida como ASCII não pode ser UTF-16). Bytes inválidos viram U+FFFD.
String decodeCss(Uint8List bytes) {
  final n = bytes.length;
  if (n >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
    return _utf8(bytes, 3);
  }
  if (n >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _utf16(bytes, 2, littleEndian: true);
  }
  if (n >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _utf16(bytes, 2, littleEndian: false);
  }
  final label = _charsetLabel(bytes);
  if (label != null && _windows1252Labels.contains(label)) {
    return _windows1252(bytes);
  }
  return _utf8(bytes, 0);
}

const _windows1252Labels = {'iso-8859-1', 'latin1', 'us-ascii', 'windows-1252'};

// Bytes de `@charset "`.
const _charsetPrefix = [
  0x40, 0x63, 0x68, 0x61, 0x72, 0x73, 0x65, 0x74, 0x20, 0x22, //
];

/// Rótulo (minúsculo) da regra `@charset "...";` no começo, ou null.
String? _charsetLabel(Uint8List bytes) {
  const p = _charsetPrefix;
  if (bytes.length < p.length + 2) return null;
  for (var i = 0; i < p.length; i++) {
    if (bytes[i] != p[i]) return null;
  }
  // Limite generoso: rótulos reais têm menos de 40 bytes.
  final limit = bytes.length < p.length + 64 ? bytes.length : p.length + 64;
  for (var i = p.length; i < limit; i++) {
    final b = bytes[i];
    if (b == 0x22) {
      if (i + 1 < bytes.length && bytes[i + 1] == 0x3B) {
        final raw = bytes.sublist(p.length, i);
        for (final c in raw) {
          if (c >= 0x80) return null;
        }
        return String.fromCharCodes(raw).toLowerCase();
      }
      return null;
    }
    if (b == 0x0A || b == 0x0D) return null;
  }
  return null;
}

String _utf8(Uint8List bytes, int start) => utf8.decode(
  start == 0 ? bytes : Uint8List.sublistView(bytes, start),
  allowMalformed: true,
);

String _utf16(Uint8List bytes, int start, {required bool littleEndian}) {
  final units = <int>[];
  for (var i = start; i + 1 < bytes.length; i += 2) {
    units.add(
      littleEndian
          ? bytes[i] | (bytes[i + 1] << 8)
          : (bytes[i] << 8) | bytes[i + 1],
    );
  }
  final out = StringBuffer();
  for (var i = 0; i < units.length; i++) {
    final u = units[i];
    if (u >= 0xD800 && u <= 0xDBFF) {
      if (i + 1 < units.length &&
          units[i + 1] >= 0xDC00 &&
          units[i + 1] <= 0xDFFF) {
        out.writeCharCode(u);
        out.writeCharCode(units[++i]);
      } else {
        out.writeCharCode(0xFFFD);
      }
    } else if (u >= 0xDC00 && u <= 0xDFFF) {
      out.writeCharCode(0xFFFD);
    } else {
      out.writeCharCode(u);
    }
  }
  // Byte sobrando no fim: sequência truncada.
  if ((bytes.length - start).isOdd) out.writeCharCode(0xFFFD);
  return out.toString();
}

// windows-1252 nos bytes 0x80-0x9F (índice = byte - 0x80); os cinco
// indefinidos mapeiam para o controle C1 correspondente, como no HTML.
const _cp1252High = [
  0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, //
  0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F, //
  0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, //
  0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178, //
];

String _windows1252(Uint8List bytes) {
  final units = Uint16List(bytes.length);
  for (var i = 0; i < bytes.length; i++) {
    final b = bytes[i];
    units[i] = (b >= 0x80 && b <= 0x9F) ? _cp1252High[b - 0x80] : b;
  }
  return String.fromCharCodes(units);
}
