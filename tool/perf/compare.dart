// Compara build/perf/result.json com o baseline da CPU atual, em
// test/perf/baselines/.
//
//   dart run tool/perf/compare.dart [--result R] [--baseline B] [--baselines DIR]
//
// Sem --baseline explícito, escolhe DIR/<baselineFileName(cpu atual)> quando
// existir; senão compara sem baseline (todos os casos viram "novo"). Sai com
// 1 em regressão, caso ausente ou arquivo ilegível. Com GITHUB_STEP_SUMMARY
// definido, acrescenta a tabela ao resumo do job.
import 'dart:io';

import 'lib/baseline.dart';
import 'lib/compare.dart';
import 'lib/perf_report.dart';

const _usage =
    'uso: dart run tool/perf/compare.dart [--result R] [--baseline B] '
    '[--baselines DIR]';

void main(List<String> args) {
  var resultPath = 'build/perf/result.json';
  String? baselinePath;
  var baselinesDir = defaultBaselinesDir;
  for (var i = 0; i < args.length; i++) {
    final hasValue = i + 1 < args.length;
    switch (args[i]) {
      case '--result' when hasValue:
        resultPath = args[++i];
      case '--baseline' when hasValue:
        baselinePath = args[++i];
      case '--baselines' when hasValue:
        baselinesDir = args[++i];
      default:
        stderr.writeln(_usage);
        exitCode = 64;
        return;
    }
  }

  try {
    final current = PerfReport.parse(
      File(resultPath).readAsStringSync(),
      source: resultPath,
    );

    PerfReport? baseline;
    var availableCpus = const <String>[];
    if (baselinePath != null) {
      final baselineFile = File(baselinePath);
      baseline = baselineFile.existsSync()
          ? PerfReport.parse(
              baselineFile.readAsStringSync(),
              source: baselinePath,
            )
          : null;
    } else {
      final (selected, cpus) = _selectBaseline(baselinesDir, current.cpu);
      baseline = selected;
      availableCpus = cpus;
    }

    final comparison = comparePerf(
      current: current,
      baseline: baseline,
      availableCpus: availableCpus,
    );
    final markdown = comparison.toMarkdown();
    stdout.write(markdown);
    final summary = Platform.environment['GITHUB_STEP_SUMMARY'];
    if (summary != null && summary.isNotEmpty) {
      File(summary).writeAsStringSync('$markdown\n', mode: FileMode.append);
    }
    exitCode = comparison.failed ? 1 : 0;
  } on PerfFormatException catch (e) {
    stderr.writeln(e);
    exitCode = 1;
  } on FileSystemException catch (e) {
    stderr.writeln('Não consegui ler ${e.path}: ${e.message}');
    exitCode = 1;
  }
}

/// Lê todo `*.json` de [baselinesDir] (inexistente conta como vazio) e
/// devolve o baseline da CPU atual (quando o arquivo existir e tiver o mesmo
/// `cpu`) junto com os modelos de CPU encontrados. Colisão de nome (arquivo
/// existe, mas com `cpu` diferente) conta como sem baseline.
(PerfReport?, List<String>) _selectBaseline(
  String baselinesDir,
  String? currentCpu,
) {
  final dir = Directory(baselinesDir);
  final byCpu = <String, PerfReport>{};
  if (dir.existsSync()) {
    for (final entity in dir.listSync()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final report = PerfReport.parse(
        entity.readAsStringSync(),
        source: entity.path,
      );
      final cpu = report.cpu;
      if (cpu != null) byCpu[cpu] = report;
    }
  }
  final availableCpus = byCpu.keys.toList()..sort();
  if (currentCpu == null || currentCpu == 'unknown') {
    return (null, availableCpus);
  }
  final path = '$baselinesDir/${baselineFileName(currentCpu)}';
  final file = File(path);
  if (!file.existsSync()) return (null, availableCpus);
  final candidate = PerfReport.parse(file.readAsStringSync(), source: path);
  return (candidate.cpu == currentCpu ? candidate : null, availableCpus);
}
