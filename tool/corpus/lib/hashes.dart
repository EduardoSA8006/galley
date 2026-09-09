import 'dart:typed_data';

/// CRC-32 (IEEE 802.3), o mesmo do ZIP e do PNG.
int crc32(List<int> data, [int seed = 0]) {
  var c = seed ^ 0xFFFFFFFF;
  for (final b in data) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >>> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

final Uint32List _crcTable = _buildCrcTable();

Uint32List _buildCrcTable() {
  final table = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
    }
    table[n] = c;
  }
  return table;
}

/// SHA-1 (RFC 3174). Devolve 20 bytes.
Uint8List sha1(List<int> message) {
  var h0 = 0x67452301;
  var h1 = 0xEFCDAB89;
  var h2 = 0x98BADCFE;
  var h3 = 0x10325476;
  var h4 = 0xC3D2E1F0;

  final padded = BytesBuilder(copy: false)
    ..add(message)
    ..addByte(0x80);
  while (padded.length % 64 != 56) {
    padded.addByte(0);
  }
  final length = ByteData(8)..setUint64(0, message.length * 8);
  padded.add(length.buffer.asUint8List());
  final bytes = padded.toBytes();

  final w = Uint32List(80);
  for (var offset = 0; offset < bytes.length; offset += 64) {
    final block = ByteData.sublistView(bytes, offset, offset + 64);
    for (var t = 0; t < 16; t++) {
      w[t] = block.getUint32(t * 4);
    }
    for (var t = 16; t < 80; t++) {
      w[t] = _rotl(w[t - 3] ^ w[t - 8] ^ w[t - 14] ^ w[t - 16], 1);
    }
    var a = h0, b = h1, c = h2, d = h3, e = h4;
    for (var t = 0; t < 80; t++) {
      int f, k;
      if (t < 20) {
        f = (b & c) | ((~b & 0xFFFFFFFF) & d);
        k = 0x5A827999;
      } else if (t < 40) {
        f = b ^ c ^ d;
        k = 0x6ED9EBA1;
      } else if (t < 60) {
        f = (b & c) | (b & d) | (c & d);
        k = 0x8F1BBCDC;
      } else {
        f = b ^ c ^ d;
        k = 0xCA62C1D6;
      }
      final temp = (_rotl(a, 5) + f + e + k + w[t]) & 0xFFFFFFFF;
      e = d;
      d = c;
      c = _rotl(b, 30);
      b = a;
      a = temp;
    }
    h0 = (h0 + a) & 0xFFFFFFFF;
    h1 = (h1 + b) & 0xFFFFFFFF;
    h2 = (h2 + c) & 0xFFFFFFFF;
    h3 = (h3 + d) & 0xFFFFFFFF;
    h4 = (h4 + e) & 0xFFFFFFFF;
  }

  final out = ByteData(20)
    ..setUint32(0, h0)
    ..setUint32(4, h1)
    ..setUint32(8, h2)
    ..setUint32(12, h3)
    ..setUint32(16, h4);
  return out.buffer.asUint8List();
}

int _rotl(int x, int n) => ((x << n) | (x >>> (32 - n))) & 0xFFFFFFFF;

String hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
