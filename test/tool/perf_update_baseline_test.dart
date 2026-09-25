// CLI que combina execuções do harness num baseline candidato (spec §3.3).
// ignore_for_file: avoid_relative_lib_imports — tool/ não é pacote; importar por caminho é intencional.
import 'dart:io';

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
      ),
  },
);

void main() {
  group('CLI update_baseline', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('perf_update_bl_'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<ProcessResult> run(List<String> args) =>
        Process.run('dart', ['run', 'tool/perf/update_baseline.dart', ...args]);

    String write(String name, PerfReport report) {
      final f = File('${dir.path}/$name')..writeAsStringSync(report.encode());
      return f.path;
    }

    test(
      '--out-dir escreve em D/baselineFileName(cpu) e imprime o caminho',
      () async {
        const cpu = 'AMD EPYC 7763 64-Core Processor';
        final r = await run([
          '--out-dir',
          '${dir.path}/out',
          write('r1.json', _run({'c': 1}, cpu: cpu)),
          write('r2.json', _run({'c': 2}, cpu: cpu)),
        ]);
        expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
        final expectedPath = '${dir.path}/out/${baselineFileName(cpu)}';
        expect(r.stdout as String, contains(expectedPath));
        final baseline = PerfReport.parse(
          File(expectedPath).readAsStringSync(),
          source: expectedPath,
        );
        expect(baseline.cases['c']!.ratio, 1.5);
        expect(baseline.cpu, cpu);
      },
    );

    test('--out e --out-dir juntos: uso e sai 64', () async {
      final r = await run([
        '--out',
        '${dir.path}/b.json',
        '--out-dir',
        '${dir.path}/out',
        write('r1.json', _run({'c': 1})),
      ]);
      expect(r.exitCode, 64);
      expect(r.stderr as String, contains('uso'));
    });

    test('--out explícito continua escrevendo no arquivo indicado', () async {
      final out = '${dir.path}/b.json';
      final r = await run([
        '--out',
        out,
        write('r1.json', _run({'c': 1})),
      ]);
      expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
      expect(File(out).existsSync(), isTrue);
      expect(r.stdout as String, contains(out));
    });

    test('CPU desconhecida com --out-dir dá erro claro e sai 1', () async {
      final r = await run([
        '--out-dir',
        '${dir.path}/out',
        write('r1.json', _run({'c': 1})), // sem cpu
      ]);
      expect(r.exitCode, 1);
      expect(r.stderr as String, isNotEmpty);
      expect(Directory('${dir.path}/out').existsSync(), isFalse);
    });

    test(
      'sem --out e sem --out-dir usa build/perf/baselines por padrão',
      () async {
        const cpu = 'Bem Improvavel CPU De Teste 12345';
        final expectedPath = 'build/perf/baselines/${baselineFileName(cpu)}';
        addTearDown(() {
          final f = File(expectedPath);
          if (f.existsSync()) f.deleteSync();
        });
        final r = await run([
          write('r1.json', _run({'c': 1}, cpu: cpu)),
        ]);
        expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
        expect(r.stdout as String, contains(expectedPath));
        expect(File(expectedPath).existsSync(), isTrue);
      },
    );
  });
}
