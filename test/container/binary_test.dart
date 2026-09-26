// Primitivas do leitor de ZIP: little-endian, CRC-32 e CP437.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/container/zip/binary.dart';
import 'package:galley/src/container/zip/cp437.dart';
import 'package:galley/src/container/zip/crc32.dart';

void main() {
  group('binary', () {
    final b = Uint8List.fromList([
      0x34, 0x12, // u16 0x1234
      0x78, 0x56, 0x34, 0x12, // u32 0x12345678
      0xFF, 0xFF, 0xFF, 0xFF, // u32 0xFFFFFFFF
    ]);

    test('u16 e u32 little-endian', () {
      expect(readU16(b, 0), 0x1234);
      expect(readU32(b, 2), 0x12345678);
      expect(readU32(b, 6), 0xFFFFFFFF);
    });

    Uint8List u64(int lo, int hi) => Uint8List(8)
      ..buffer.asByteData().setUint32(0, lo, Endian.little)
      ..buffer.asByteData().setUint32(4, hi, Endian.little);

    test('u64 como dois u32', () {
      expect(readU64(u64(5, 0), 0), 5);
      expect(readU64(u64(0, 1), 0), 0x100000000);
      expect(readU64(u64(0xFFFFFFFF, 0x1FFFFF), 0), maxSafeInteger - 1);
      expect(readU64(u64(0, 0x200000), 0), maxSafeInteger);
    });

    test('u64 acima de 2^53 devolve null', () {
      expect(readU64(u64(1, 0x200000), 0), isNull);
      expect(readU64(u64(0xFFFFFFFF, 0xFFFFFFFF), 0), isNull);
    });
  });

  group('crc32', () {
    test('vetores conhecidos', () {
      expect(crc32(const []), 0);
      expect(crc32(ascii.encode('123456789')), 0xCBF43926);
      expect(
        crc32(ascii.encode('The quick brown fox jumps over the lazy dog')),
        0x414FA339,
      );
    });

    test('incremental em pedaços é igual ao de uma vez', () {
      final data = List<int>.generate(100000, (i) => (i * 31) & 0xFF);
      final c = Crc32();
      for (var i = 0; i < data.length; i += 7777) {
        c.add(data, i, i + 7777 > data.length ? data.length : i + 7777);
      }
      expect(c.value, crc32(data));
    });
  });

  group('cp437', () {
    test('ASCII passa direto; bytes altos pela tabela', () {
      expect(decodeCp437(ascii.encode('OEBPS/a.xhtml')), 'OEBPS/a.xhtml');
      expect(decodeCp437([0x80, 0x87, 0xA4, 0xE1, 0xFF]), 'Ççñß ');
    });
  });
}
