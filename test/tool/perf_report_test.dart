// Modelo do JSON do harness de desempenho (spec §2.5 e §3.3).
import 'package:flutter_test/flutter_test.dart';

import '../../tool/perf/lib/perf_report.dart';
import '../../tool/perf/lib/stats.dart';

PerfReport _report() => PerfReport(
  flutter: '3.47.0',
  dart: '3.13.0',
  os: 'linux',
  createdAt: DateTime.utc(2026, 9, 25, 12),
  cases: const {
    'z.last': PerfCaseResult(
      ratio: 2.5,
      medianUs: 1000,
      calibrationUs: 400,
      samples: [2.4, 2.5, 2.6],
    ),
    'a.first': PerfCaseResult(ratio: 1.5, medianUs: 600, calibrationUs: 400),
  },
);

void main() {
  group('median', () {
    test('ímpar devolve o central', () {
      expect(median([3, 1, 2]), 2);
    });
    test('par devolve a média dos centrais', () {
      expect(median([4, 1, 3, 2]), 2.5);
    });
    test('vazio lança', () {
      expect(() => median(const []), throwsArgumentError);
    });
  });

  group('PerfReport', () {
    test('ida e volta preserva os campos', () {
      final back = PerfReport.parse(_report().encode(), source: 'mem');
      expect(back.flutter, '3.47.0');
      expect(back.dart, '3.13.0');
      expect(back.os, 'linux');
      expect(back.createdAt, DateTime.utc(2026, 9, 25, 12));
      expect(back.cases['z.last']!.ratio, 2.5);
      expect(back.cases['z.last']!.samples, [2.4, 2.5, 2.6]);
      expect(back.cases['a.first']!.calibrationUs, 400);
    });

    test('encode ordena os casos por id', () {
      final text = _report().encode();
      expect(text.indexOf('a.first'), lessThan(text.indexOf('z.last')));
    });

    test('encode sem amostras omite samples e mantém o resto', () {
      final text = _report().encode(includeSamples: false);
      expect(text, isNot(contains('samples')));
      expect(
        PerfReport.parse(text, source: 'mem').cases['z.last']!.samples,
        isEmpty,
      );
    });

    test('campos do baseline fazem ida e volta', () {
      final base = PerfReport(
        flutter: '3.47.0',
        dart: '3.13.0',
        os: 'linux',
        createdAt: DateTime.utc(2026, 9, 25),
        cases: const {},
        sourceCommit: 'abc123',
        runner: 'ubuntu-24.04',
        runs: 3,
      );
      final back = PerfReport.parse(base.encode(), source: 'mem');
      expect(back.sourceCommit, 'abc123');
      expect(back.runner, 'ubuntu-24.04');
      expect(back.runs, 3);
    });

    test('números inteiros no JSON são aceitos', () {
      const text =
          '{"schema":1,"flutter":"x","dart":"y","os":"linux",'
          '"createdAt":"2026-09-25T00:00:00.000Z",'
          '"cases":{"c":{"ratio":2,"medianUs":36120,"calibrationUs":4874}}}';
      expect(PerfReport.parse(text, source: 'mem').cases['c']!.medianUs, 36120);
    });

    test('JSON inválido nomeia a origem', () {
      expect(
        () => PerfReport.parse('{', source: 'build/perf/result.json'),
        throwsA(
          isA<PerfFormatException>().having(
            (e) => e.toString(),
            'toString',
            contains('build/perf/result.json'),
          ),
        ),
      );
    });

    test('schema desconhecido é recusado', () {
      final text = _report().encode().replaceFirst(
        '"schema": 1',
        '"schema": 2',
      );
      expect(
        () => PerfReport.parse(text, source: 'mem'),
        throwsA(
          isA<PerfFormatException>().having(
            (e) => e.message,
            'message',
            contains('schema desconhecido'),
          ),
        ),
      );
    });

    test('ratio não positivo nomeia o campo', () {
      const text =
          '{"schema":1,"flutter":"x","dart":"y","os":"linux",'
          '"createdAt":"2026-09-25T00:00:00.000Z",'
          '"cases":{"c":{"ratio":0,"medianUs":1,"calibrationUs":1}}}';
      expect(
        () => PerfReport.parse(text, source: 'mem'),
        throwsA(
          isA<PerfFormatException>().having(
            (e) => e.message,
            'message',
            contains('cases.c.ratio'),
          ),
        ),
      );
    });

    test('campo obrigatório ausente nomeia o campo', () {
      const text =
          '{"schema":1,"dart":"y","os":"linux",'
          '"createdAt":"2026-09-25T00:00:00.000Z","cases":{}}';
      expect(
        () => PerfReport.parse(text, source: 'mem'),
        throwsA(
          isA<PerfFormatException>().having(
            (e) => e.message,
            'message',
            contains("'flutter'"),
          ),
        ),
      );
    });
  });
}
