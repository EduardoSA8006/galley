// Spike S6 — desofuscação de fontes embutidas (doc/09 §4, doc/13 S6).
//
// Perguntas: o SHA-1 próprio está correto e é rápido o bastante para a chave
// do cache (doc/08 §4.1)? A desofuscação IDPF e Adobe devolve bytes idênticos
// e a fonte resultante carrega no motor de texto? Resultado em
// spike/RESULTADO-S6.md.

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/s6_font_obfuscation.dart';
import 'support/sha1.dart';

Uint8List _ascii(String s) => Uint8List.fromList(ascii.encode(s));

/// Uma fonte TTF do sistema, preferindo uma variante regular; null se não há.
File? _systemFont() {
  const candidates = [
    '/usr/share/fonts/noto/NotoSerif-Regular.ttf',
    '/usr/share/fonts/noto/NotoSans-Regular.ttf',
    '/usr/share/fonts/TTF/DejaVuSans.ttf',
    '/usr/share/fonts/dejavu/DejaVuSans.ttf',
    '/usr/share/fonts/liberation/LiberationSerif-Regular.ttf',
    '/usr/share/fonts/TTF/LiberationSerif-Regular.ttf',
  ];
  for (final c in candidates) {
    final f = File(c);
    if (f.existsSync()) return f;
  }
  for (final dir in ['/usr/share/fonts/noto', '/usr/share/fonts/TTF']) {
    final d = Directory(dir);
    if (!d.existsSync()) continue;
    for (final e in d.listSync()) {
      if (e is File && e.path.endsWith('.ttf')) return e;
    }
  }
  return null;
}

void main() {
  group('SHA-1 próprio', () {
    test('vetores conhecidos', () {
      expect(
        sha1Hex(_ascii('abc')),
        'a9993e364706816aba3e25717850c26c9cd0d89d',
      );
      expect(sha1Hex(Uint8List(0)), 'da39a3ee5e6b4b0d3255bfef95601890afd80709');
      expect(
        sha1Hex(_ascii('The quick brown fox jumps over the lazy dog')),
        '2fd4e1c67a2d28fced849ee1bb76e7391b93eb12',
      );
      // Fronteiras do padding: 55, 56 e 64 bytes.
      expect(
        sha1Hex(_ascii('a' * 55)),
        'c1c8bbdc22796e28c0e15163d20899b65621d65a',
      );
      expect(
        sha1Hex(_ascii('a' * 56)),
        'c2db330f6083854c99d4b5bfb6e8f29f201be699',
      );
      expect(
        sha1Hex(_ascii('a' * 64)),
        '0098ba824b5c16427bd7a1122a5a442a25ec644d',
      );
    });

    test('tempo sobre 100 KB e 1 MB (mediana de 5)', () {
      final rnd = Random(7);
      for (final size in [100 * 1024, 1024 * 1024]) {
        final data = Uint8List.fromList(
          List.generate(size, (_) => rnd.nextInt(256)),
        );
        sha1(data); // aquecimento
        final samples = <int>[];
        for (var i = 0; i < 5; i++) {
          final sw = Stopwatch()..start();
          sha1(data);
          sw.stop();
          samples.add(sw.elapsedMicroseconds);
        }
        samples.sort();
        print(
          'S6 SHA-1 ${size ~/ 1024} KB: mediana ${samples[2]} µs '
          '(min ${samples.first}, max ${samples.last})',
        );
      }
    });
  });

  group('ofuscação de fonte', () {
    const identifier = 'urn:uuid:b7e2f1a0-4c3d-4e5f-8a9b-0c1d2e3f4a5b';

    test('chave IDPF ignora whitespace e usa SHA-1', () {
      final k1 = idpfKey(['urn:uuid:abc', 'def']);
      final k2 = idpfKey(['urn:uuid:abc \n', '\tdef ']);
      expect(k1, k2);
      expect(k1, sha1(_ascii('urn:uuid:abcdef')));
      expect(k1.length, 20);
    });

    test('chave Adobe são os 16 bytes do UUID', () {
      final k = adobeKey(identifier);
      expect(k.length, 16);
      expect(k.first, 0xb7);
      expect(k.last, 0x5b);
      expect(() => adobeKey('urn:uuid:curto'), throwsArgumentError);
    });

    test('ida e volta IDPF e Adobe sobre uma fonte real do sistema', () {
      final file = _systemFont();
      final Uint8List font;
      if (file != null) {
        font = file.readAsBytesSync();
        print('S6 fonte: ${file.path} (${font.length} bytes)');
      } else {
        font = Uint8List.fromList(
          List.generate(4096, (i) => Random(1).nextInt(256)),
        );
        print('S6 fonte: nenhuma TTF do sistema; usando 4 KB aleatórios');
      }

      final ids = [identifier];
      final idpf = idpfObfuscate(font, ids);
      expect(idpf.length, font.length);
      expect(idpf.sublist(0, 1040), isNot(font.sublist(0, 1040)));
      expect(
        idpf.sublist(1040),
        font.sublist(1040),
        reason: 'IDPF só toca os primeiros 1040 bytes',
      );
      expect(idpfDeobfuscate(idpf, ids), font);

      final adobe = adobeObfuscate(font, identifier);
      expect(adobe.sublist(0, 1024), isNot(font.sublist(0, 1024)));
      expect(
        adobe.sublist(1024),
        font.sublist(1024),
        reason: 'Adobe só toca os primeiros 1024 bytes',
      );
      expect(adobeDeobfuscate(adobe, identifier), font);

      // Chave errada não devolve a fonte.
      expect(idpfDeobfuscate(idpf, ['urn:uuid:outro']), isNot(font));
    });

    testWidgets('fonte desofuscada carrega no motor e faz layout', (
      tester,
    ) async {
      final file = _systemFont();
      if (file == null) {
        markTestSkipped('sem fonte TTF do sistema');
        return;
      }
      final font = file.readAsBytesSync();
      final restored = idpfDeobfuscate(idpfObfuscate(font, [identifier]), [
        identifier,
      ]);

      final loader = FontLoader('SpikeS6')
        ..addFont(Future.value(ByteData.sublistView(restored)));
      await loader.load();

      final builder =
          ui.ParagraphBuilder(
              ui.ParagraphStyle(fontFamily: 'SpikeS6', fontSize: 16),
            )
            ..pushStyle(ui.TextStyle(fontFamily: 'SpikeS6', fontSize: 16))
            ..addText('Fonte desofuscada em layout.');
      final paragraph = builder.build()
        ..layout(const ui.ParagraphConstraints(width: 300));
      final metrics = paragraph.computeLineMetrics();
      expect(metrics, isNotEmpty);
      expect(paragraph.longestLine, greaterThan(0));
      print(
        'S6 layout com fonte carregada: ${metrics.length} linha(s), '
        'largura ${paragraph.longestLine.toStringAsFixed(1)} px',
      );
      paragraph.dispose();
    });
  });
}
