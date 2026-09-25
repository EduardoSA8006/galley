// Regras do gate de desempenho (spec §3.2) e CLI do comparador.
// ignore_for_file: avoid_relative_lib_imports — tool/ não é pacote; importar por caminho é intencional.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/perf/lib/baseline.dart';
import '../../tool/perf/lib/compare.dart';
import '../../tool/perf/lib/perf_report.dart';

PerfReport _report(
  Map<String, double> ratios, {
  String flutter = '3.47.0',
  String? cpu,
}) => PerfReport(
  flutter: flutter,
  dart: '3.13.0',
  os: 'linux',
  cpu: cpu,
  createdAt: DateTime.utc(2026, 9, 25),
  cases: {
    for (final MapEntry(:key, :value) in ratios.entries)
      key: PerfCaseResult(ratio: value, medianUs: 1, calibrationUs: 1),
  },
);

CaseStatus _status(double base, double current) => comparePerf(
  current: _report({'c': current}),
  baseline: _report({'c': base}),
).cases.single.status;

void main() {
  group('comparePerf', () {
    test('igual passa', () {
      expect(_status(2, 2), CaseStatus.ok);
    });

    test('acima de 1,20× é regressão e falha', () {
      final cmp = comparePerf(
        current: _report({'c': 1.25}),
        baseline: _report({'c': 1}),
      );
      expect(cmp.cases.single.status, CaseStatus.regression);
      expect(cmp.failed, isTrue);
    });

    test('exatamente 1,20× passa (limite estrito)', () {
      expect(_status(1, 1.2), CaseStatus.ok);
    });

    test('abaixo de 0,80× é melhora e não falha', () {
      final cmp = comparePerf(
        current: _report({'c': 0.75}),
        baseline: _report({'c': 1}),
      );
      expect(cmp.cases.single.status, CaseStatus.improvement);
      expect(cmp.failed, isFalse);
    });

    test('caso novo avisa e não falha', () {
      final cmp = comparePerf(
        current: _report({'a': 1, 'novo': 1}),
        baseline: _report({'a': 1}),
      );
      expect(
        cmp.cases.firstWhere((c) => c.id == 'novo').status,
        CaseStatus.newCase,
      );
      expect(cmp.failed, isFalse);
    });

    test('caso ausente do resultado falha', () {
      final cmp = comparePerf(
        current: _report({'a': 1}),
        baseline: _report({'a': 1, 'sumiu': 1}),
      );
      expect(
        cmp.cases.firstWhere((c) => c.id == 'sumiu').status,
        CaseStatus.missing,
      );
      expect(cmp.failed, isTrue);
    });

    test('sem baseline tudo é novo e nada falha', () {
      final cmp = comparePerf(current: _report({'a': 1, 'b': 2}));
      expect(cmp.hasBaseline, isFalse);
      expect(cmp.cases.map((c) => c.status), everyElement(CaseStatus.newCase));
      expect(cmp.failed, isFalse);
      expect(cmp.toMarkdown(), contains('Sem baseline'));
    });

    test('Flutter diferente avisa em destaque', () {
      final cmp = comparePerf(
        current: _report({'a': 1}, flutter: '3.47.5'),
        baseline: _report({'a': 1}),
      );
      expect(cmp.flutterMismatch, isTrue);
      expect(cmp.failed, isFalse);
      final md = cmp.toMarkdown();
      expect(md, contains('Flutter diferente'));
      expect(md, contains('3.47.5'));
      expect(md, contains('3.47.0'));
    });

    test('tabela mostra variação com vírgula e casos em ordem', () {
      final md = comparePerf(
        current: _report({'b': 1.25, 'a': 1}),
        baseline: _report({'b': 1, 'a': 1}),
      ).toMarkdown();
      expect(md, contains('+25,0%'));
      expect(md.indexOf('`a`'), lessThan(md.indexOf('`b`')));
      expect(md, contains('Resultado: falhou'));
    });

    test('linha CPU presente sem baseline', () {
      final cmp = comparePerf(
        current: _report({'a': 1}, cpu: 'Intel Core i5-11400H'),
      );
      expect(cmp.currentCpu, 'Intel Core i5-11400H');
      expect(cmp.baselineCpu, isNull);
      expect(cmp.toMarkdown(), contains('CPU: Intel Core i5-11400H'));
    });

    test('linha CPU presente com baseline', () {
      final cmp = comparePerf(
        current: _report({'a': 1}, cpu: 'Intel Core i5-11400H'),
        baseline: _report({'a': 1}, cpu: 'Intel Core i5-11400H'),
      );
      final md = cmp.toMarkdown();
      expect(md, contains('CPU: Intel Core i5-11400H'));
      expect(md, contains('baseline: Intel Core i5-11400H'));
    });

    test('cpuMismatch verdadeiro e aviso quando CPU difere', () {
      final cmp = comparePerf(
        current: _report({'a': 1}, cpu: 'Intel Core i5-11400H'),
        baseline: _report({'a': 1}, cpu: 'AMD EPYC 7763 64-Core Processor'),
      );
      expect(cmp.cpuMismatch, isTrue);
      expect(cmp.failed, isFalse);
      final md = cmp.toMarkdown();
      expect(md, contains('AVISO: CPU diferente do baseline'));
      expect(md, contains('doc/14'));
    });

    test('cpuMismatch falso quando CPU igual', () {
      final cmp = comparePerf(
        current: _report({'a': 1}, cpu: 'Intel Core i5-11400H'),
        baseline: _report({'a': 1}, cpu: 'Intel Core i5-11400H'),
      );
      expect(cmp.cpuMismatch, isFalse);
      expect(
        cmp.toMarkdown(),
        isNot(contains('AVISO: CPU diferente do baseline')),
      );
    });

    test('baseline sem cpu conta como diferente', () {
      final cmp = comparePerf(
        current: _report({'a': 1}, cpu: 'Intel Core i5-11400H'),
        baseline: _report({'a': 1}),
      );
      expect(cmp.cpuMismatch, isTrue);
    });

    test('CPU diferente com regressão continua falhando', () {
      final cmp = comparePerf(
        current: _report({'c': 1.25}, cpu: 'Intel Core i5-11400H'),
        baseline: _report({'c': 1}, cpu: 'AMD EPYC 7763 64-Core Processor'),
      );
      expect(cmp.cpuMismatch, isTrue);
      expect(cmp.failed, isTrue);
    });

    test('sem baseline: markdown lista as CPUs existentes', () {
      final cmp = comparePerf(
        current: _report({'a': 1}, cpu: 'Intel Core i5-11400H'),
        availableCpus: const [
          'AMD EPYC 7763 64-Core Processor',
          'Intel(R) Xeon(R) 6973P-C',
        ],
      );
      final md = cmp.toMarkdown();
      expect(md, contains('Sem baseline para esta CPU'));
      expect(md, contains('`Intel Core i5-11400H`'));
      expect(
        md,
        contains(
          'Baselines existentes: AMD EPYC 7763 64-Core Processor, '
          'Intel(R) Xeon(R) 6973P-C',
        ),
      );
    });

    test('sem baseline e sem CPUs conhecidas: markdown diz "nenhum"', () {
      final md = comparePerf(current: _report({'a': 1})).toMarkdown();
      expect(md, contains('Sem baseline para esta CPU'));
      expect(md, contains('`desconhecida`'));
      expect(md, contains('Baselines existentes: nenhum'));
    });
  });

  group('CLI', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('perf_compare_'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<ProcessResult> run(List<String> args, {String? summary}) =>
        Process.run(
          'dart',
          ['run', 'tool/perf/compare.dart', ...args],
          environment: {'GITHUB_STEP_SUMMARY': summary ?? ''},
        );

    String write(String name, PerfReport report) {
      final f = File('${dir.path}/$name')..writeAsStringSync(report.encode());
      return f.path;
    }

    String writeIn(String subdir, String name, PerfReport report) {
      final d = Directory('${dir.path}/$subdir')..createSync(recursive: true);
      final f = File('${d.path}/$name')..writeAsStringSync(report.encode());
      return f.path;
    }

    test('resultado inexistente sai com 1 e nomeia o arquivo', () async {
      final missing = '${dir.path}/nao-existe.json';
      final r = await run(['--result', missing, '--baseline', missing]);
      expect(r.exitCode, 1);
      expect(r.stderr as String, contains('nao-existe.json'));
      expect(r.stderr as String, isNot(contains('#0')));
    });

    test('regressão sai com 1 e escreve o resumo do job', () async {
      final summary = '${dir.path}/summary.md';
      final r = await run([
        '--result',
        write('r.json', _report({'c': 2})),
        '--baseline',
        write('b.json', _report({'c': 1})),
      ], summary: summary);
      expect(r.exitCode, 1);
      expect(File(summary).readAsStringSync(), contains('regressão'));
    });

    test('sem regressão sai com 0', () async {
      final r = await run([
        '--result',
        write('r.json', _report({'c': 1.1})),
        '--baseline',
        write('b.json', _report({'c': 1})),
      ]);
      expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    });

    test('--baselines escolhe o arquivo da CPU atual (regressão sai 1)', () async {
      const cpu = 'AMD EPYC 7763 64-Core Processor';
      writeIn(
        'baselines',
        baselineFileName(cpu),
        _report({'c': 1}, cpu: cpu),
      );
      final r = await run([
        '--result',
        write('r.json', _report({'c': 2}, cpu: cpu)),
        '--baselines',
        '${dir.path}/baselines',
      ]);
      expect(r.exitCode, 1, reason: '${r.stdout}\n${r.stderr}');
      expect(r.stdout as String, contains('regressão'));
    });

    test(
      'CPU sem arquivo correspondente: sai 0 e lista as CPUs existentes',
      () async {
        const outra = 'Intel(R) Xeon(R) 6973P-C';
        writeIn(
          'baselines',
          baselineFileName(outra),
          _report({'c': 1}, cpu: outra),
        );
        const atual = 'AMD EPYC 9V45 96-Core Processor';
        final r = await run([
          '--result',
          write('r.json', _report({'c': 1}, cpu: atual)),
          '--baselines',
          '${dir.path}/baselines',
        ]);
        expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
        expect(r.stdout as String, contains('Sem baseline para esta CPU'));
        expect(r.stdout as String, contains(outra));
      },
    );

    test('diretório de baselines inexistente conta como vazio: sai 0', () async {
      const atual = 'AMD EPYC 9V45 96-Core Processor';
      final r = await run([
        '--result',
        write('r.json', _report({'c': 1}, cpu: atual)),
        '--baselines',
        '${dir.path}/nao-existe',
      ]);
      expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
      expect(r.stdout as String, contains('Sem baseline para esta CPU'));
    });

    test(
      '--baseline explícito continua funcionando mesmo com --baselines',
      () async {
        final r = await run([
          '--result',
          write('r.json', _report({'c': 2})),
          '--baseline',
          write('b.json', _report({'c': 1})),
          '--baselines',
          '${dir.path}/baselines',
        ]);
        expect(r.exitCode, 1, reason: '${r.stdout}\n${r.stderr}');
        expect(r.stdout as String, contains('regressão'));
      },
    );

    test(
      'arquivo malformado em --baselines falha com a mensagem de '
      'PerfFormatException',
      () async {
        const cpu = 'AMD EPYC 7763 64-Core Processor';
        writeIn(
          'baselines',
          baselineFileName(cpu),
          _report({'c': 1}, cpu: cpu),
        );
        File(
          '${dir.path}/baselines/garbage.json',
        ).writeAsStringSync('{ not valid json');
        final r = await run([
          '--result',
          write('r.json', _report({'c': 1}, cpu: cpu)),
          '--baselines',
          '${dir.path}/baselines',
        ]);
        expect(r.exitCode, 1, reason: '${r.stdout}\n${r.stderr}');
        expect(r.stderr as String, contains('garbage.json'));
      },
    );
  });
}
