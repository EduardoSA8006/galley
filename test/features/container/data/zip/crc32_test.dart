import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/features/container/data/zip/crc32.dart';

void main() {
  test('crc32 de vetores conhecidos', () {
    expect(crc32(utf8.encode('')), 0x00000000);
    expect(crc32(utf8.encode('123456789')), 0xCBF43926);
    expect(crc32(utf8.encode('56789'), crc32(utf8.encode('1234'))), 0xCBF43926);
  });
}
