import 'dart:convert';
import 'dart:typed_data';

final RegExp _latin1Declaration = RegExp(
  r'''^<\?xml[^>]*encoding\s*=\s*["'](iso-8859-1|latin1|windows-1252)["']''',
  caseSensitive: false,
);

/// Decodifica [bytes] de um documento de texto/XML sem lançar exceções.
///
/// Reconhece BOM UTF-8 (removido) e UTF-16 LE/BE. Sem BOM, se começa com
/// `<?xml` e declara ISO-8859-1, latin1 ou windows-1252, decodifica como
/// latin1; caso contrário, UTF-8 tolerante a bytes malformados.
String decodeText(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true);
  }
  if (bytes.length >= 2) {
    if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return _decodeUtf16(bytes, 2, littleEndian: true);
    }
    if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return _decodeUtf16(bytes, 2, littleEndian: false);
    }
  }
  if (bytes.length >= 5 &&
      bytes[0] == 0x3C &&
      bytes[1] == 0x3F &&
      bytes[2] == 0x78) {
    final end = bytes.length < 200 ? bytes.length : 200;
    final head = latin1.decode(bytes.sublist(0, end));
    if (_latin1Declaration.hasMatch(head)) return latin1.decode(bytes);
  }
  return utf8.decode(bytes, allowMalformed: true);
}

/// Junta os pares de bytes a partir de [start] em unidades UTF-16 (um byte
/// ímpar no fim é ignorado).
///
/// As unidades vão para um [Uint16List] do tamanho exato, não para uma lista
/// que cresce: em documentos grandes, a lista crescente realocava um array de
/// 8 bytes por unidade várias vezes, e essas alocações grandes disparavam
/// mark-sweeps do heap velho, cujo custo cresce com o tamanho do programa.
String _decodeUtf16(Uint8List bytes, int start, {required bool littleEndian}) {
  final units = Uint16List((bytes.length - start) >> 1);
  final hi = littleEndian ? 1 : 0;
  final lo = 1 - hi;
  for (var u = 0, i = start; u < units.length; u++, i += 2) {
    units[u] = (bytes[i + hi] << 8) | bytes[i + lo];
  }
  return String.fromCharCodes(units);
}
