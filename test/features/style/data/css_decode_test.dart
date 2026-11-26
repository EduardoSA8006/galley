import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/features/style/data/css_decode.dart';

Uint8List b(List<int> v) => Uint8List.fromList(v);

void main() {
  group('decodeCss', () {
    test('BOM UTF-8', () {
      expect(decodeCss(b([0xEF, 0xBB, 0xBF, ...'a{}'.codeUnits])), 'a{}');
    });

    test('BOM UTF-16LE', () {
      final bytes = [0xFF, 0xFE];
      for (final c in 'a{}'.codeUnits) {
        bytes
          ..add(c)
          ..add(0);
      }
      expect(decodeCss(b(bytes)), 'a{}');
    });

    test('BOM UTF-16BE', () {
      final bytes = [0xFE, 0xFF];
      for (final c in 'a{}'.codeUnits) {
        bytes
          ..add(0)
          ..add(c);
      }
      expect(decodeCss(b(bytes)), 'a{}');
    });

    test('@charset iso-8859-1 decodifica como windows-1252', () {
      final head = '@charset "iso-8859-1";'.codeUnits;
      expect(decodeCss(b([...head, 0xE9])), '@charset "iso-8859-1";é');
      expect(decodeCss(b([...head, 0x93])), '@charset "iso-8859-1";“');
    });

    test('@charset em caixa mista e rótulos de windows-1252', () {
      for (final l in ['Latin1', 'US-ASCII', 'windows-1252']) {
        final bytes = [...'@charset "$l";'.codeUnits, 0xE9];
        expect(decodeCss(b(bytes)).endsWith('é'), isTrue, reason: l);
      }
    });

    test('@charset UTF-8 e utf-16 caem em UTF-8', () {
      expect(
        decodeCss(b([...'@charset "UTF-8";'.codeUnits, 0xC3, 0xA9])),
        '@charset "UTF-8";é',
      );
      expect(
        decodeCss(b('@charset "utf-16";a{}'.codeUnits)),
        '@charset "utf-16";a{}',
      );
    });

    test('@charset com aspas simples é ignorado (UTF-8)', () {
      final bytes = [...'@charset \'latin1\';'.codeUnits, 0xC3, 0xA9];
      expect(decodeCss(b(bytes)), '@charset \'latin1\';é');
    });

    test('byte inválido vira U+FFFD', () {
      expect(decodeCss(b([0x61, 0xFF, 0x62])), 'a�b');
    });
  });
}
