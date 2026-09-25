// Combina um ou mais result.json num baseline candidato.
//
//   dart run tool/perf/update_baseline.dart [--out F | --out-dir D]
//       [--commit SHA] [--runner NOME] result1.json [result2.json ...]
//
// Sem --out nem --out-dir, escreve em build/perf/baselines/
// <baselineFileName(cpu)>. Atualizar test/perf/baselines/ é commit deliberado
// (doc/10 §4.2); o CI gera o candidato pelo workflow perf-baseline.
import 'dart:io';

import 'lib/baseline.dart';
import 'lib/perf_report.dart';

const _defaultOutDir = 'build/perf/baselines';

const _usage =
    'uso: dart run tool/perf/update_baseline.dart [--out F | --out-dir D] '
    '[--commit SHA] [--runner NOME] result1.json [result2.json ...]\n'
    '  --out e --out-dir são exclusivos; padrão: --out-dir $_defaultOutDir';

void main(List<String> args) {
  String? out;
  String? outDir;
  String? commit;
  String? runner;
  final inputs = <String>[];
  for (var i = 0; i < args.length; i++) {
    final hasValue = i + 1 < args.length;
    switch (args[i]) {
      case '--out' when hasValue:
        out = args[++i];
      case '--out-dir' when hasValue:
        outDir = args[++i];
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
  if (inputs.isEmpty || (out != null && outDir != null)) {
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
    final path =
        out ??
        '${outDir ?? _defaultOutDir}/${baselineFileName(baseline.cpu ?? '')}';
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(baseline.encode(includeSamples: false));
    stdout.writeln(
      'baseline com ${baseline.cases.length} casos de ${runs.length} '
      'execuções escrito em $path',
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
