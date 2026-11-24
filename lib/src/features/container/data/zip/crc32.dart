import 'dart:typed_data';

final Uint32List _table = _buildTable();

Uint32List _buildTable() {
  final table = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    table[n] = c;
  }
  return table;
}

/// Calcula o CRC-32 (polinômio `0xEDB88320`) de [bytes].
///
/// O parâmetro [crc] permite o cálculo incremental: passe o resultado anterior
/// para continuar a soma sobre o próximo trecho. O resultado é sem sinal, de
/// 32 bits.
int crc32(List<int> bytes, [int crc = 0]) {
  var c = crc ^ 0xFFFFFFFF;
  for (var i = 0; i < bytes.length; i++) {
    c = _table[(c ^ bytes[i]) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
