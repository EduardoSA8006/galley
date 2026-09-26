/// CRC-32 (IEEE 802.3), o do ZIP, por tabela e incremental.
library;

import 'dart:typed_data';

final Uint32List _table = () {
  final table = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
    }
    table[n] = c;
  }
  return table;
}();

/// Acumulador: [add] em pedaços, [value] a qualquer momento.
final class Crc32 {
  int _c = 0xFFFFFFFF;

  void add(List<int> data, [int start = 0, int? end]) {
    final stop = RangeError.checkValidRange(start, end, data.length);
    var c = _c;
    for (var i = start; i < stop; i++) {
      c = _table[(c ^ data[i]) & 0xFF] ^ (c >>> 8);
    }
    _c = c;
  }

  int get value => (_c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// CRC-32 de [data] de uma vez.
int crc32(List<int> data) => (Crc32()..add(data)).value;
