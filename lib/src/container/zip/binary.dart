/// Leitura little-endian para o ZIP. Só `getUint16`/`getUint32` e aritmética,
/// porque `ByteData.getUint64` não existe no dart2js.
library;

import 'dart:typed_data';

/// 2^53: acima disso um inteiro deixa de ser exato no dart2js.
const int maxSafeInteger = 9007199254740992;

int readU16(Uint8List bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8);

int readU32(Uint8List bytes, int offset) =>
    ByteData.sublistView(bytes, offset, offset + 4).getUint32(0, Endian.little);

/// u64 como dois u32. `null` quando o valor passa de 2^53 (fora de limite
/// para qualquer arquivo que o pacote aceita).
int? readU64(Uint8List bytes, int offset) {
  final lo = readU32(bytes, offset);
  final hi = readU32(bytes, offset + 4);
  if (hi > 0x200000 || (hi == 0x200000 && lo > 0)) return null;
  return hi * 0x100000000 + lo;
}
