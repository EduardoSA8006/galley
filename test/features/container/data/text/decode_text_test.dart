import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/features/container/data/text/decode_text.dart';

void main() {
  group('decodeText', () {
    test('remove BOM UTF-8', () {
      expect(
        decodeText(
          Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('ação')]),
        ),
        'ação',
      );
    });

    test('decodifica UTF-16 LE com BOM', () {
      expect(
        decodeText(Uint8List.fromList([0xFF, 0xFE, 0x61, 0x00, 0xE7, 0x00])),
        'aç',
      );
    });

    test('decodifica UTF-16 BE com BOM', () {
      expect(decodeText(Uint8List.fromList([0xFE, 0xFF, 0x00, 0x61])), 'a');
    });

    test('declaração ISO-8859-1 usa latin1', () {
      final bytes = Uint8List.fromList([
        ...ascii.encode('<?xml version="1.0" encoding="ISO-8859-1"?><a>'),
        0xE9,
      ]);
      expect(decodeText(bytes), endsWith('é'));
    });

    test('declaração windows-1252 usa latin1', () {
      final bytes = Uint8List.fromList([
        ...ascii.encode("<?xml version='1.0' encoding='windows-1252'?><a>"),
        0xE9,
      ]);
      expect(decodeText(bytes), endsWith('é'));
    });

    test('sem BOM e sem declaração usa UTF-8', () {
      expect(decodeText(Uint8List.fromList(utf8.encode('ação'))), 'ação');
    });

    test('UTF-8 malformado não lança', () {
      final result = decodeText(Uint8List.fromList([0x61, 0xFF, 0x62]));
      expect(result, startsWith('a'));
      expect(result, endsWith('b'));
    });

    test('UTF-16 truncado e vazio não lançam', () {
      expect(
        () => decodeText(Uint8List.fromList([0xFF, 0xFE, 0x61])),
        returnsNormally,
      );
      expect(decodeText(Uint8List(0)), '');
    });
  });
}
