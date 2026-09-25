// Compara build/perf/result.json com test/perf/baseline.json.
//
//   dart run tool/perf/compare.dart [--result R] [--baseline B]
//
// Sai com 1 em regressão, caso ausente ou arquivo ilegível. Com
// GITHUB_STEP_SUMMARY definido, acrescenta a tabela ao resumo do job.
import 'dart:io';

import 'lib/compare.dart';
import 'lib/perf_report.dart';

const _usage =
    'uso: dart run tool/perf/compare.dart [--result R] [--baseline B]';

void main(List<String> args) {
  var resultPath = 'build/perf/result.json';
  var baselinePath = 'test/perf/baseline.json';
  for (var i = 0; i < args.length; i++) {
    final hasValue = i + 1 < args.length;
    switch (args[i]) {
      case '--result' when hasValue:
        resultPath = args[++i];
      case '--baseline' when hasValue:
        baselinePath = args[++i];
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
    final baselineFile = File(baselinePath);
    final baseline = baselineFile.existsSync()
        ? PerfReport.parse(
            baselineFile.readAsStringSync(),
            source: baselinePath,
          )
        : null;
    final comparison = comparePerf(current: current, baseline: baseline);
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
