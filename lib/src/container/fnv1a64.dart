/// FNV-1a de 64 bits (spec do CSS §9.7; doc/08 §4.1, P8), sem dependência.
library;

/// Incremental e exato na VM e no JS: o estado são quatro palavras de 16
/// bits (o `int` do web não tem 64 bits), e cada produto parcial cabe
/// folgado nos 53 bits do `double`.
final class Fnv1a64 {
  // offset basis 0xcbf29ce484222325, da palavra baixa para a alta.
  int _h0 = 0x2325, _h1 = 0x8422, _h2 = 0x9ce4, _h3 = 0xcbf2;

  /// Acrescenta `bytes[start, end)`.
  void add(List<int> bytes, [int start = 0, int? end]) {
    final stop = RangeError.checkValidRange(start, end, bytes.length);
    var h0 = _h0, h1 = _h1, h2 = _h2, h3 = _h3;
    for (var i = start; i < stop; i++) {
      h0 ^= bytes[i] & 0xFF;
      // h × 0x100000001b3 = h × 0x1b3 + (h << 40), módulo 2^64.
      final t0 = h0 * 0x1b3;
      final t1 = h1 * 0x1b3 + (t0 >> 16);
      final t2 = h2 * 0x1b3 + (t1 >> 16) + ((h0 << 8) & 0xFFFF);
      final t3 = h3 * 0x1b3 + (t2 >> 16) + ((h1 << 8) | (h0 >> 8));
      h0 = t0 & 0xFFFF;
      h1 = t1 & 0xFFFF;
      h2 = t2 & 0xFFFF;
      h3 = t3 & 0xFFFF;
    }
    _h0 = h0;
    _h1 = h1;
    _h2 = h2;
    _h3 = h3;
  }

  /// 16 dígitos hexadecimais minúsculos.
  String get hex => [
    _h3,
    _h2,
    _h1,
    _h0,
  ].map((w) => w.toRadixString(16).padLeft(4, '0')).join();
}
