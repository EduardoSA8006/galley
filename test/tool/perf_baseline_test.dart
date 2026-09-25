// Combinação de execuções do harness num baseline (spec §3.3).
// ignore_for_file: avoid_relative_lib_imports — tool/ não é pacote; importar por caminho é intencional.
import 'package:flutter_test/flutter_test.dart';

import '../../tool/perf/lib/baseline.dart';
import '../../tool/perf/lib/perf_report.dart';

PerfReport _run(
  Map<String, double> ratios, {
  String flutter = '3.47.0',
  String? cpu,
}) => PerfReport(
  flutter: flutter,
  dart: '3.13.0',
  os: 'linux',
  createdAt: DateTime.utc(2026, 9, 25),
  cpu: cpu,
  cases: {
    for (final MapEntry(:key, :value) in ratios.entries)
      key: PerfCaseResult(
        ratio: value,
        medianUs: value * 100,
        calibrationUs: 100,
        samples: [value],
      ),
  },
);

void main() {
  test('mediana por caso, sem amostras, com metadados', () {
    final base = combineBaseline(
      [
        _run({'a': 1, 'b': 10}),
        _run({'a': 3, 'b': 30}),
        _run({'a': 2, 'b': 20}),
      ],
      sourceCommit: 'abc123',
      runner: 'ubuntu-24.04',
      createdAt: DateTime.utc(2026, 9, 26),
    );
    expect(base.cases['a']!.ratio, 2);
    expect(base.cases['b']!.ratio, 20);
    expect(base.cases['b']!.medianUs, 2000);
    expect(base.cases['a']!.samples, isEmpty);
    expect(base.runs, 3);
    expect(base.sourceCommit, 'abc123');
    expect(base.runner, 'ubuntu-24.04');
    expect(base.createdAt, DateTime.utc(2026, 9, 26));
    expect(base.flutter, '3.47.0');
  });

  test('uma execução só vira baseline dela mesma', () {
    expect(
      combineBaseline([
        _run({'a': 1.5}),
      ]).cases['a']!.ratio,
      1.5,
    );
  });

  test('nenhuma execução lança', () {
    expect(() => combineBaseline(const []), throwsArgumentError);
  });

  test('Flutter diferente entre execuções lança', () {
    expect(
      () => combineBaseline([
        _run({'a': 1}),
        _run({'a': 1}, flutter: '3.47.5'),
      ]),
      throwsA(
        isA<ArgumentError>().having(
          (e) => '${e.message}',
          'message',
          contains('3.47.5'),
        ),
      ),
    );
  });

  test('casos diferentes entre execuções lança e nomeia o caso', () {
    expect(
      () => combineBaseline([
        _run({'a': 1}),
        _run({'a': 1, 'extra': 1}),
      ]),
      throwsA(
        isA<ArgumentError>().having(
          (e) => '${e.message}',
          'message',
          contains('extra'),
        ),
      ),
    );
  });

  test('CPU diferente entre execuções lança e nomeia as duas', () {
    expect(
      () => combineBaseline([
        _run({'a': 1}, cpu: 'Intel Core i5-11400H'),
        _run({'a': 1}, cpu: 'AMD EPYC 7763 64-Core Processor'),
      ]),
      throwsA(
        isA<ArgumentError>().having(
          (e) => '${e.message}',
          'message',
          allOf(
            contains('Intel Core i5-11400H'),
            contains('AMD EPYC 7763 64-Core Processor'),
          ),
        ),
      ),
    );
  });

  test('CPU igual propaga para o baseline', () {
    final base = combineBaseline([
      _run({'a': 1}, cpu: 'Intel Core i5-11400H'),
      _run({'a': 2}, cpu: 'Intel Core i5-11400H'),
    ]);
    expect(base.cpu, 'Intel Core i5-11400H');
  });

  group('baselineFileName', () {
    test('modelo simples com espaços', () {
      expect(
        baselineFileName('AMD EPYC 7763 64-Core Processor'),
        'amd-epyc-7763-64-core-processor.json',
      );
    });

    test('parênteses, arroba e ponto viram um único hífen', () {
      expect(
        baselineFileName('Intel(R) Xeon(R) Platinum 8370C CPU @ 2.80GHz'),
        'intel-r-xeon-r-platinum-8370c-cpu-2-80ghz.json',
      );
    });

    test('espaços duplos e pontuação nas pontas não deixam hífen sobrando', () {
      expect(
        baselineFileName('  --AMD  EPYC   9V45!!--  '),
        'amd-epyc-9v45.json',
      );
    });

    test('string vazia lança', () {
      expect(() => baselineFileName(''), throwsArgumentError);
    });

    test('"unknown" lança', () {
      expect(() => baselineFileName('unknown'), throwsArgumentError);
    });
  });

  test('defaultBaselinesDir aponta para test/perf/baselines', () {
    expect(defaultBaselinesDir, 'test/perf/baselines');
  });
}
