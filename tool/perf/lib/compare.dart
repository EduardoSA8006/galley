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
    this.currentCpu,
    this.baselineCpu,
    this.availableCpus = const [],
  });

  final List<CaseComparison> cases;
  final String currentFlutter;

  /// `null` quando não há baseline.
  final String? baselineFlutter;

  /// Modelo da CPU do resultado atual; `null` quando desconhecida.
  final String? currentCpu;

  /// Modelo da CPU do baseline; `null` quando não há baseline ou é
  /// desconhecida.
  final String? baselineCpu;

  /// Modelos de CPU com baseline existente no diretório consultado; usado só
  /// quando `!hasBaseline`, para apontar o que já existe.
  final List<String> availableCpus;

  bool get hasBaseline => baselineFlutter != null;

  bool get flutterMismatch => hasBaseline && baselineFlutter != currentFlutter;

  /// Baseline sem `cpu` conta como diferente.
  bool get cpuMismatch => hasBaseline && baselineCpu != currentCpu;

  bool get failed => cases.any(
    (c) => c.status == CaseStatus.regression || c.status == CaseStatus.missing,
  );

  String toMarkdown() {
    final out = StringBuffer('## Desempenho\n\n');
    out.write('CPU: ${currentCpu ?? "desconhecida"}');
    if (hasBaseline) {
      out.write(' · baseline: ${baselineCpu ?? "desconhecida"}');
    }
    out.writeln('\n');
    if (!hasBaseline) {
      final cpusList = availableCpus.isEmpty
          ? 'nenhum'
          : availableCpus.join(', ');
      out.writeln(
        '> **Sem baseline para esta CPU** (`${currentCpu ?? "desconhecida"}`)'
        ': todos os casos são novos e nada falha.\n'
        '> Baselines existentes: $cpusList. Gere o desta CPU pelo workflow '
        '`perf-baseline`.\n',
      );
    } else if (flutterMismatch) {
      out.writeln(
        '> **AVISO: Flutter diferente.** Resultado em $currentFlutter, '
        'baseline em $baselineFlutter. A comparação vale pouco até o baseline '
        'ser regenerado nesta versão.\n',
      );
    }
    if (cpuMismatch) {
      out.writeln(
        '> **AVISO: CPU diferente do baseline.** Entre VMs do runner a razão '
        'já variou até 23% (zlib); uma regressão aqui pode ser a máquina, não '
        'o código (doc/14).\n',
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
  List<String> availableCpus = const [],
}) {
  final ids = {...current.cases.keys, ...?baseline?.cases.keys}.toList()
    ..sort();
  return PerfComparison(
    currentFlutter: current.flutter,
    baselineFlutter: baseline?.flutter,
    currentCpu: current.cpu,
    baselineCpu: baseline?.cpu,
    availableCpus: availableCpus,
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
