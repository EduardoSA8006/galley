/// Metade alta (0x80-0xFF) da página de código CP437.
const String _high =
    'ÇüéâäàåçêëèïîìÄÅ'
    'ÉæÆôöòûùÿÖÜ¢£¥₧ƒ'
    'áíóúñÑªº¿⌐¬½¼¡«»'
    '░▒▓│┤╡╢╖╕╣║╗╝╜╛┐'
    '└┴┬├─┼╞╟╚╔╩╦╠═╬╧'
    '╨╤╥╙╘╒╓╫╪┘┌█▄▌▐▀'
    'αßΓπΣσµτΦΘΩδ∞φε∩'
    '≡±≥≤⌠⌡÷≈°∙·√ⁿ²■\u00A0';

/// Decodifica [bytes] em CP437, a codificação histórica de nomes de zip.
String decodeCp437(List<int> bytes) {
  final out = StringBuffer();
  for (final b in bytes) {
    out.writeCharCode(b < 0x80 ? b : _high.codeUnitAt(b - 0x80));
  }
  return out.toString();
}
