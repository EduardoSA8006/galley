// Casos de desempenho da Fase 0: só primitivas das quais o motor vai
// depender (spec §2.4). Rodar com:
//
//   flutter test --tags perf --run-skipped test/perf
//
// e comparar com `dart run tool/perf/compare.dart`.
// ignore_for_file: avoid_relative_lib_imports — tool/ não é pacote; importar por caminho é intencional.
@Tags(['perf'])
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

import '../../tool/corpus/lib/png.dart';
import '../../tool/perf/lib/perf_report.dart';
import 'support/perf_harness.dart';
import 'support/perf_inputs.dart';

int _sink = 0;

List<PerfCase> _phase0Cases() {
  late String xhtml;
  late List<String> paragraphs;
  late Uint8List deflated;
  late Uint8List pngBytes;
  return [
    PerfCase(
      id: 'html.parse.500kb',
      setUp: () async => xhtml = xhtmlOfLength(500 * 1024),
      run: () => _sink += html.parse(xhtml).body!.nodes.length,
    ),
    PerfCase(
      id: 'paragraph.shape.1000',
      setUp: () async => paragraphs = paragraphsOfWords(1000, 40),
      run: () {
        for (final text in paragraphs) {
          final builder =
              ui.ParagraphBuilder(
                  ui.ParagraphStyle(fontFamily: 'FlutterTest', fontSize: 16),
                )
                ..pushStyle(
                  ui.TextStyle(fontFamily: 'FlutterTest', fontSize: 16),
                )
                ..addText(text);
          final p = builder.build()
            ..layout(const ui.ParagraphConstraints(width: 320));
          _sink += p.height.toInt();
          p.dispose();
        }
      },
    ),
    PerfCase(
      id: 'zlib.inflate.1mb',
      setUp: () async => deflated = deflateRaw(proseBytes(1024 * 1024)),
      run: () => _sink += ZLibDecoder(raw: true).convert(deflated).length,
      innerIterations: 6, // ≈ 5 ms por amostra, como a calibração
    ),
    PerfCase(
      id: 'image.decode.target',
      setUp: () async => pngBytes = png(1200, 1600, seed: 5),
      runAsync: () async {
        final codec = await ui.instantiateImageCodec(
          pngBytes,
          targetWidth: 300,
        );
        final frame = await codec.getNextFrame();
        _sink += frame.image.width;
        frame.image.dispose();
        codec.dispose();
      },
    ),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final results = <String, PerfCaseResult>{};

  for (final c in _phase0Cases()) {
    test(c.id, () async {
      final r = await measureCase(c);
      results[c.id] = r;
      print(
        '[perf] ${c.id}: razão ${r.ratio.toStringAsFixed(3)}, '
        'caso ${r.medianUs.round()} µs, calibração ${r.calibrationUs.round()} µs',
      );
    }, timeout: const Timeout(Duration(minutes: 5)));
  }

  tearDownAll(() async {
    if (await writeResultIfAny(results)) {
      print(
        '[perf] $defaultResultPath escrito (${results.length} casos, sink $_sink)',
      );
    }
  });
}
