import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/features/container/data/zip/crc32.dart';

void main() {
  test('crc32 de vetores conhecidos', () {
    expect(crc32(utf8.encode('')), 0x00000000);
    expect(crc32(utf8.encode('123456789')), 0xCBF43926);
    expect(crc32(utf8.encode('56789'), crc32(utf8.encode('1234'))), 0xCBF43926);
  });

  test('Uint8List, vista e List<int> genérica dão o mesmo CRC', () {
    final bytes = Uint8List.fromList([for (var i = 0; i < 1000; i++) i * 7]);
    final expected = _bitwiseCrc32(bytes);
    expect(crc32(bytes), expected);
    expect(crc32(List<int>.of(bytes)), expected);
    expect(crc32([for (final b in bytes) b]), expected);
    final padded = Uint8List(bytes.length + 8)..setRange(3, 1003, bytes);
    expect(crc32(Uint8List.sublistView(padded, 3, 1003)), expected);
  });

  test('incremental igual nos dois caminhos', () {
    final a = utf8.encode('1234');
    final b = utf8.encode('56789');
    expect(crc32(List<int>.of(b), crc32(List<int>.of(a))), 0xCBF43926);
    expect(crc32(b, crc32(List<int>.of(a))), 0xCBF43926);
    expect(crc32(List<int>.of(b), crc32(a)), 0xCBF43926);
  });
}

/// Referência bit a bit, sem tabela.
int _bitwiseCrc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c ^= b & 0xFF;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
  }
  return c ^ 0xFFFFFFFF;
}
