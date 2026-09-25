/// Combina execuções do harness num baseline
/// (doc/specs/2026-09-25-harness-ci-design.md §3.3).
library;

import 'perf_report.dart';
import 'stats.dart';

/// Mediana, caso a caso, de [runs]. Execuções de Flutter diferente ou com
/// conjuntos de casos diferentes não se combinam.
PerfReport combineBaseline(
  List<PerfReport> runs, {
  String? sourceCommit,
  String? runner,
  DateTime? createdAt,
}) {
  if (runs.isEmpty) {
    throw ArgumentError.value(runs, 'runs', 'nenhuma execução para combinar');
  }
  final first = runs.first;
  final ids = first.cases.keys.toSet();
  for (final r in runs.skip(1)) {
    if (r.flutter != first.flutter) {
      throw ArgumentError(
        'execuções com Flutter diferente: ${first.flutter} e ${r.flutter}',
      );
    }
    if (r.cpu != first.cpu) {
      throw ArgumentError(
        'execuções com CPU diferente: ${first.cpu} e ${r.cpu}',
      );
    }
    final other = r.cases.keys.toSet();
    final diff = ids.difference(other).union(other.difference(ids));
    if (diff.isNotEmpty) {
      throw ArgumentError(
        'execuções com casos diferentes: ${(diff.toList()..sort()).join(', ')}',
      );
    }
  }
  double med(String id, double Function(PerfCaseResult) field) =>
      median(runs.map((r) => field(r.cases[id]!)));
  return PerfReport(
    flutter: first.flutter,
    dart: first.dart,
    os: first.os,
    cpu: first.cpu,
    createdAt: (createdAt ?? DateTime.now()).toUtc(),
    sourceCommit: sourceCommit,
    runner: runner,
    runs: runs.length,
    cases: {
      for (final id in ids)
        id: PerfCaseResult(
          ratio: med(id, (c) => c.ratio),
          medianUs: med(id, (c) => c.medianUs),
          calibrationUs: med(id, (c) => c.calibrationUs),
        ),
    },
  );
}
