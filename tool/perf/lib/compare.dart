/// Regras do gate de desempenho (doc/specs/2026-09-25-harness-ci-design.md
/// §3.2): compara a razão de cada caso com a do baseline.
library;

import 'perf_report.dart';

/// Acima disto, regressão: o build falha. O limite é estrito.
const double regressionThreshold = 1.20;

/// Abaixo disto, melhora: aviso para atualizar o baseline.
const double improvementThreshold = 0.80;

enum CaseStatus { ok, regression, improvement, newCase, missing }

final class CaseComparison {
  const CaseComparison({
    required this.id,
    required this.status,
    this.baselineRatio,
    this.currentRatio,
  });

  final String id;
  final CaseStatus status;
  final double? baselineRatio;
  final double? currentRatio;

  /// `currentRatio / baselineRatio`, quando os dois existem.
  double? get change => switch ((baselineRatio, currentRatio)) {
    (final b?, final c?) => c / b,
    _ => null,
  };
}

final class PerfComparison {
  const PerfComparison({
    required this.cases,
    required this.currentFlutter,
    this.baselineFlutter,
  });

  final List<CaseComparison> cases;
  final String currentFlutter;

  /// `null` quando não há baseline.
  final String? baselineFlutter;

  bool get hasBaseline => baselineFlutter != null;

  bool get flutterMismatch => hasBaseline && baselineFlutter != currentFlutter;

  bool get failed => cases.any(
    (c) => c.status == CaseStatus.regression || c.status == CaseStatus.missing,
  );

  String toMarkdown() {
    final out = StringBuffer('## Desempenho\n\n');
    if (!hasBaseline) {
      out.writeln(
        '> **Sem baseline** (`test/perf/baseline.json`): todos os casos são '
        'novos e nada falha. Gere o baseline pelo workflow `perf-baseline`.\n',
      );
    } else if (flutterMismatch) {
      out.writeln(
        '> **AVISO: Flutter diferente.** Resultado em $currentFlutter, '
        'baseline em $baselineFlutter. A comparação vale pouco até o baseline '
        'ser regenerado nesta versão.\n',
      );
    }
    out
      ..writeln('| Caso | Baseline | Atual | Variação | Estado |')
      ..writeln('|---|---:|---:|---:|---|');
    for (final c in cases) {
      out.writeln(
        '| `${c.id}` | ${_ratio(c.baselineRatio)} | ${_ratio(c.currentRatio)} '
        '| ${_change(c.change)} | ${_label(c.status)} |',
      );
    }
    out
      ..writeln()
      ..writeln(
        failed
            ? '**Resultado: falhou** (regressão acima de '
                  '${_percent(regressionThreshold)} ou caso ausente).'
            : '**Resultado: passou.**',
      );
    return out.toString();
  }
}

PerfComparison comparePerf({
  required PerfReport current,
  PerfReport? baseline,
}) {
  final ids = {...current.cases.keys, ...?baseline?.cases.keys}.toList()
    ..sort();
  return PerfComparison(
    currentFlutter: current.flutter,
    baselineFlutter: baseline?.flutter,
    cases: [
      for (final id in ids)
        _compareCase(id, baseline?.cases[id]?.ratio, current.cases[id]?.ratio),
    ],
  );
}

CaseComparison _compareCase(String id, double? base, double? current) {
  final status = switch ((base, current)) {
    (null, _) => CaseStatus.newCase,
    (_, null) => CaseStatus.missing,
    (final b?, final c?) when c / b > regressionThreshold =>
      CaseStatus.regression,
    (final b?, final c?) when c / b < improvementThreshold =>
      CaseStatus.improvement,
    _ => CaseStatus.ok,
  };
  return CaseComparison(
    id: id,
    status: status,
    baselineRatio: base,
    currentRatio: current,
  );
}

String _ratio(double? v) => v == null ? '—' : v.toStringAsFixed(3);

String _change(double? v) {
  if (v == null) return '—';
  final pct = (v - 1) * 100;
  final sign = pct >= 0 ? '+' : '';
  return '$sign${pct.toStringAsFixed(1).replaceAll('.', ',')}%';
}

String _percent(double threshold) => '${((threshold - 1) * 100).round()}%';

String _label(CaseStatus s) => switch (s) {
  CaseStatus.ok => 'ok',
  CaseStatus.regression => '**regressão**',
  CaseStatus.improvement => 'melhora (atualizar o baseline?)',
  CaseStatus.newCase => 'novo, sem baseline',
  CaseStatus.missing => '**ausente do resultado**',
};
