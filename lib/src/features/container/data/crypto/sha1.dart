import 'dart:typed_data';

const int _mask = 0xFFFFFFFF;

int _rotl(int x, int n) => ((x << n) | (x >> (32 - n))) & _mask;

/// SHA-1 (FIPS 180-4) de [bytes]; devolve o digest de 20 bytes.
///
/// Implementação própria para evitar a dependência de `crypto`; usada apenas
/// na derivação da chave de ofuscação de fontes (não é uso criptográfico).
Uint8List sha1(List<int> bytes) {
  final length = bytes.length;
  final paddedLength = ((length + 8) ~/ 64 + 1) * 64;
  final padded = Uint8List(paddedLength);
  for (var i = 0; i < length; i++) {
    padded[i] = bytes[i] & 0xFF;
  }
  padded[length] = 0x80;
  final bitLength = length * 8;
  for (var i = 0; i < 8; i++) {
    padded[paddedLength - 1 - i] = (bitLength >> (8 * i)) & 0xFF;
  }

  var h0 = 0x67452301;
  var h1 = 0xEFCDAB89;
  var h2 = 0x98BADCFE;
  var h3 = 0x10325476;
  var h4 = 0xC3D2E1F0;
  final w = List<int>.filled(80, 0);

  for (var offset = 0; offset < paddedLength; offset += 64) {
    for (var t = 0; t < 16; t++) {
      final j = offset + t * 4;
      w[t] =
          (padded[j] << 24) |
          (padded[j + 1] << 16) |
          (padded[j + 2] << 8) |
          padded[j + 3];
    }
    for (var t = 16; t < 80; t++) {
      w[t] = _rotl(w[t - 3] ^ w[t - 8] ^ w[t - 14] ^ w[t - 16], 1);
    }
    var a = h0, b = h1, c = h2, d = h3, e = h4;
    for (var t = 0; t < 80; t++) {
      final int f;
      final int k;
      if (t < 20) {
        f = (b & c) | ((~b & _mask) & d);
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
      final temp = (_rotl(a, 5) + f + e + k + w[t]) & _mask;
      e = d;
      d = c;
      c = _rotl(b, 30);
      b = a;
      a = temp;
    }
    h0 = (h0 + a) & _mask;
    h1 = (h1 + b) & _mask;
    h2 = (h2 + c) & _mask;
    h3 = (h3 + d) & _mask;
    h4 = (h4 + e) & _mask;
  }

  final out = Uint8List(20);
  final data = ByteData.view(out.buffer);
  data.setUint32(0, h0);
  data.setUint32(4, h1);
  data.setUint32(8, h2);
  data.setUint32(12, h3);
  data.setUint32(16, h4);
  return out;
}
