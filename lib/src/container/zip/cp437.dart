/// Nomes de entrada sem o bit 11 que não são UTF-8 válido: CP437, a
/// codificação original do PKZIP.
library;

/// Os 128 bytes altos (0x80–0xFF) do CP437, em ordem. Os 128 baixos são
/// ASCII.
const String _high =
    'ÇüéâäàåçêëèïîìÄÅÉæÆôöòûùÿÖÜ¢£¥₧ƒ'
    'áíóúñÑªº¿⌐¬½¼¡«»░▒▓│┤╡╢╖╕╣║╗╝╜╛┐'
    '└┴┬├─┼╞╟╚╔╩╦╠═╬╧╨╤╥╙╘╒╓╫╪┘┌█▄▌▐▀'
    'αßΓπΣσµτΦΘΩδ∞φε∩≡±≥≤⌠⌡÷≈°∙·√ⁿ²■ ';

/// Decodifica [bytes] como CP437.
String decodeCp437(List<int> bytes) {
  final out = StringBuffer();
  for (final b in bytes) {
    out.writeCharCode(b < 0x80 ? b : _high.codeUnitAt(b - 0x80));
  }
  return out.toString();
}
