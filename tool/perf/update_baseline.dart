// Combina um ou mais result.json num baseline candidato.
//
//   dart run tool/perf/update_baseline.dart [--out F] [--commit SHA]
//       [--runner NOME] result1.json [result2.json ...]
//
// Atualizar test/perf/baseline.json é commit deliberado (doc/10 §4.2); o CI
// gera o candidato pelo workflow perf-baseline.
import 'dart:io';

import 'lib/baseline.dart';
import 'lib/perf_report.dart';

const _usage =
    'uso: dart run tool/perf/update_baseline.dart [--out F] [--commit SHA] '
    '[--runner NOME] result1.json [result2.json ...]\n'
    '  --out padrão: build/perf/baseline.json';

void main(List<String> args) {
  var out = 'build/perf/baseline.json';
  String? commit;
  String? runner;
  final inputs = <String>[];
  for (var i = 0; i < args.length; i++) {
    final hasValue = i + 1 < args.length;
    switch (args[i]) {
      case '--out' when hasValue:
        out = args[++i];
      case '--commit' when hasValue:
        commit = args[++i];
      case '--runner' when hasValue:
        runner = args[++i];
      case final a when a.startsWith('--'):
        stderr.writeln(_usage);
        exitCode = 64;
        return;
      case final path:
        inputs.add(path);
    }
  }
  if (inputs.isEmpty) {
    stderr.writeln(_usage);
    exitCode = 64;
    return;
  }

  try {
    final runs = [
      for (final p in inputs)
        PerfReport.parse(File(p).readAsStringSync(), source: p),
    ];
    final baseline = combineBaseline(
      runs,
      sourceCommit: commit,
      runner: runner,
    );
    File(out)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(baseline.encode(includeSamples: false));
    stdout.writeln(
      'baseline com ${baseline.cases.length} casos de ${runs.length} '
      'execuções escrito em $out',
    );
  } on PerfFormatException catch (e) {
    stderr.writeln(e);
    exitCode = 1;
  } on ArgumentError catch (e) {
    stderr.writeln(e.message);
    exitCode = 1;
  } on FileSystemException catch (e) {
    stderr.writeln('Não consegui ler ${e.path}: ${e.message}');
    exitCode = 1;
  }
}
