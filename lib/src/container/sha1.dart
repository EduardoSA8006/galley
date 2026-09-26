/// SHA-1 próprio (FIPS 180-4), sem dependência (doc/11 §1). Vem do spike S6.
library;

import 'dart:typed_data';

/// Os 20 bytes do SHA-1 de [data], de uma vez (sem streaming).
Uint8List sha1(Uint8List data) {
  const mask = 0xFFFFFFFF;

  var h0 = 0x67452301;
  var h1 = 0xEFCDAB89;
  var h2 = 0x98BADCFE;
  var h3 = 0x10325476;
  var h4 = 0xC3D2E1F0;

  // Padding: 0x80, zeros até 56 mod 64, comprimento em bits big-endian.
  // O comprimento vai como dois u32 (setUint64 não existe no dart2js).
  final bitLength = data.length * 8;
  final paddedLength = ((data.length + 9 + 63) ~/ 64) * 64;
  final padded = Uint8List(paddedLength)..setRange(0, data.length, data);
  padded[data.length] = 0x80;
  final view = ByteData.sublistView(padded)
    ..setUint32(paddedLength - 8, bitLength ~/ 0x100000000, Endian.big)
    ..setUint32(paddedLength - 4, bitLength & mask, Endian.big);

  final w = Uint32List(80);

  int rotl(int x, int n) => ((x << n) | (x >>> (32 - n))) & mask;

  for (var chunk = 0; chunk < paddedLength; chunk += 64) {
    for (var i = 0; i < 16; i++) {
      w[i] = view.getUint32(chunk + i * 4, Endian.big);
    }
    for (var i = 16; i < 80; i++) {
      w[i] = rotl(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
    }

    var a = h0, b = h1, c = h2, d = h3, e = h4;
    for (var i = 0; i < 80; i++) {
      int f, k;
      if (i < 20) {
        f = (b & c) | ((~b & mask) & d);
        k = 0x5A827999;
      } else if (i < 40) {
        f = b ^ c ^ d;
        k = 0x6ED9EBA1;
      } else if (i < 60) {
        f = (b & c) | (b & d) | (c & d);
        k = 0x8F1BBCDC;
      } else {
        f = b ^ c ^ d;
        k = 0xCA62C1D6;
      }
      final temp = (rotl(a, 5) + f + e + k + w[i]) & mask;
      e = d;
      d = c;
      c = rotl(b, 30);
      b = a;
      a = temp;
    }

    h0 = (h0 + a) & mask;
    h1 = (h1 + b) & mask;
    h2 = (h2 + c) & mask;
    h3 = (h3 + d) & mask;
    h4 = (h4 + e) & mask;
  }

  final out = ByteData(20)
    ..setUint32(0, h0, Endian.big)
    ..setUint32(4, h1, Endian.big)
    ..setUint32(8, h2, Endian.big)
    ..setUint32(12, h3, Endian.big)
    ..setUint32(16, h4, Endian.big);
  return out.buffer.asUint8List();
}

/// SHA-1 em hexadecimal minúsculo.
String sha1Hex(Uint8List data) =>
    sha1(data).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
