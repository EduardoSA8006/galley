import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/features/container/data/crypto/sha1.dart';

String hex(Uint8List b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

void main() {
  test('vetores FIPS 180-4', () {
    expect(
      hex(sha1(utf8.encode('abc'))),
      'a9993e364706816aba3e25717850c26c9cd0d89d',
    );
    expect(
      hex(sha1(utf8.encode(''))),
      'da39a3ee5e6b4b0d3255bfef95601890afd80709',
    );
    expect(
      hex(
        sha1(
          utf8.encode(
            'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq',
          ),
        ),
      ),
      '84983e441c3bd26ebaae4aa1f95129e5e54670f1',
    );
    expect(
      hex(sha1(List.filled(1000000, 0x61))),
      '34aa973cd4c4daa4f61eeb2bdbad27316534016f',
    );
  });

  test('fronteiras de padding (55, 56, 64 bytes)', () {
    expect(
      hex(sha1(List.filled(55, 0x61))),
      'c1c8bbdc22796e28c0e15163d20899b65621d65a',
    );
    expect(
      hex(sha1(List.filled(56, 0x61))),
      'c2db330f6083854c99d4b5bfb6e8f29f201be699',
    );
    expect(
      hex(sha1(List.filled(64, 0x61))),
      '0098ba824b5c16427bd7a1122a5a442a25ec644d',
    );
  });
}
