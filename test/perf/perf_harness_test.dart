// Mecânica do harness de desempenho (spec §2): amostragem, normalização,
// versão do Flutter e escrita do resultado.
// ignore_for_file: avoid_relative_lib_imports — tool/ não é pacote; importar por caminho é intencional.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/perf/lib/perf_report.dart';
import 'support/perf_harness.dart';

void _busyWait(int micros) {
  final sw = Stopwatch()..start();
  while (sw.elapsedMicroseconds < micros) {}
}

void main() {
  group('PerfCase', () {
    test('exige exatamente um corpo', () {
      expect(() => PerfCase(id: 'x'), throwsArgumentError);
      expect(
        () => PerfCase(id: 'x', run: () {}, runAsync: () async {}),
        throwsArgumentError,
      );
      expect(PerfCase(id: 'x', run: () {}).id, 'x');
    });
  });

  group('measureCase', () {
    test('intercala calibração e caso, descarta o aquecimento', () async {
      var setUps = 0;
      var calibrations = 0;
      var bodies = 0;
      final result = await measureCase(
        PerfCase(
          id: 'conta',
          setUp: () async => setUps++,
          run: () => bodies++,
          innerIterations: 2,
        ),
        warmup: 3,
        samples: 5,
        calibration: () => calibrations++,
      );
      expect(setUps, 1);
      expect(calibrations, 8);
      expect(bodies, 16);
      expect(result.samples, hasLength(5));
    });

    test('corpo quase vazio ainda dá razão positiva', () async {
      final result = await measureCase(
        PerfCase(id: 'vazio', run: () {}),
        warmup: 1,
        samples: 5,
      );
      expect(result.ratio, greaterThan(0));
    });

    test('razão acompanha o custo relativo', () async {
      final result = await measureCase(
        PerfCase(id: 'dobro', run: () => _busyWait(2000)),
        warmup: 1,
        samples: 7,
        calibration: () => _busyWait(1000),
      );
      expect(result.ratio, inInclusiveRange(1.5, 2.5));
      expect(result.medianUs, inInclusiveRange(1800, 4000));
    });

    test('corpo assíncrono é aguardado', () async {
      final result = await measureCase(
        PerfCase(
          id: 'async',
          runAsync: () => Future<void>.delayed(const Duration(milliseconds: 2)),
        ),
        warmup: 0,
        samples: 3,
        calibration: () {},
      );
      expect(result.medianUs, greaterThanOrEqualTo(2000));
    });
  });

  test('calibração faz trabalho observável', () {
    final before = calibrationSink;
    calibrationWorkload();
    expect(calibrationSink, isNot(before));
  });

  group('detectFlutterVersion', () {
    test('FLUTTER_VERSION tem precedência', () async {
      final v = await detectFlutterVersion(
        environment: {'FLUTTER_VERSION': '3.47.0'},
        runProcess: (_, _) => throw StateError('não deveria rodar'),
      );
      expect(v, '3.47.0');
    });

    test('lê frameworkVersion mesmo com banner antes do JSON', () async {
      final v = await detectFlutterVersion(
        environment: const {},
        runProcess: (_, _) async => ProcessResult(
          0,
          0,
          'Downloading Dart SDK...\n{"frameworkVersion": "3.47.5"}\n',
          '',
        ),
      );
      expect(v, '3.47.5');
    });

    test('processo que falha vira unknown', () async {
      expect(
        await detectFlutterVersion(
          environment: const {},
          runProcess: (_, _) => throw const ProcessException('flutter', []),
        ),
        'unknown',
      );
      expect(
        await detectFlutterVersion(
          environment: const {},
          runProcess: (_, _) async => ProcessResult(0, 1, '', 'erro'),
        ),
        'unknown',
      );
    });
  });

  group('writeResultIfAny', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('perf_harness_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('mapa vazio não cria arquivo', () async {
      final path = '${dir.path}/perf/result.json';
      expect(await writeResultIfAny(const {}, path: path), isFalse);
      expect(File(path).existsSync(), isFalse);
    });

    test('escreve um result.json legível', () async {
      final path = '${dir.path}/perf/result.json';
      final wrote = await writeResultIfAny(
        const {
          'c': PerfCaseResult(
            ratio: 2,
            medianUs: 200,
            calibrationUs: 100,
            samples: [2],
          ),
        },
        path: path,
        environment: {'FLUTTER_VERSION': '3.47.0'},
      );
      expect(wrote, isTrue);
      final back = PerfReport.parse(
        File(path).readAsStringSync(),
        source: path,
      );
      expect(back.flutter, '3.47.0');
      expect(back.os, Platform.operatingSystem);
      expect(back.cases['c']!.samples, [2]);
    });

    test('grava cpu lido do arquivo temporário', () async {
      final path = '${dir.path}/perf/result.json';
      final cpuinfo = File('${dir.path}/cpuinfo')
        ..writeAsStringSync(
          'processor\t: 0\n'
          'model name\t: AMD EPYC 7763 64-Core Processor\n',
        );
      await writeResultIfAny(
        const {
          'c': PerfCaseResult(ratio: 2, medianUs: 200, calibrationUs: 100),
        },
        path: path,
        environment: {'FLUTTER_VERSION': '3.47.0'},
        cpuinfoPath: cpuinfo.path,
      );
      final back = PerfReport.parse(
        File(path).readAsStringSync(),
        source: path,
      );
      expect(back.cpu, 'AMD EPYC 7763 64-Core Processor');
    });
  });

  group('detectCpuModel', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('perf_cpuinfo_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('duas CPUs devolve o nome da primeira', () {
      final path = '${dir.path}/cpuinfo';
      File(path).writeAsStringSync(
        'processor\t: 0\n'
        'model name\t: AMD EPYC 7763 64-Core Processor\n'
        'cache size\t: 512 KB\n'
        'processor\t: 1\n'
        'model name\t: AMD EPYC 7763 64-Core Processor\n',
      );
      expect(
        detectCpuModel(cpuinfoPath: path),
        'AMD EPYC 7763 64-Core Processor',
      );
    });

    test('arquivo sem model name devolve unknown', () {
      final path = '${dir.path}/cpuinfo';
      File(path).writeAsStringSync('processor\t: 0\ncache size\t: 512 KB\n');
      expect(detectCpuModel(cpuinfoPath: path), 'unknown');
    });

    test('caminho inexistente devolve unknown', () {
      expect(detectCpuModel(cpuinfoPath: '${dir.path}/nao-existe'), 'unknown');
    });
  });
}
