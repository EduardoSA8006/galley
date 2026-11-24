import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../bmf.dart' as bmf;
import 'orchestration.dart';
import 'stats.dart';

/// Rodadas intercaladas (base, head) por benchmark.
const int defaultRounds = 15;

/// Duração alvo de cada amostra (as iterações medidas de uma execução).
const Duration targetSampleTime = Duration(milliseconds: 200);

/// Máximo de iterações `k` por execução, para benchmarks minúsculos.
const int maxAbIterations = 100000;

/// Tempo máximo de cada execução do `bench_runner` no modo `ab`.
const Duration defaultAbTimeout = Duration(minutes: 5);

/// Iterações da execução de calibração (1 de aquecimento + 2 medidas).
const int _calibrationIterations = 3;

/// Resultado de uma execução `bench_runner --timing`.
typedef TimedRun = ({int ns, int checksum});

/// Lê `ns=` e `checksum=` da saída de `bench_runner --timing`.
///
/// Lança [FormatException] se alguma das linhas faltar.
TimedRun parseTimedRun(String out) {
  final ns = RegExp(r'^ns=(\d+)\s*$', multiLine: true).firstMatch(out);
  final sum = checksumPattern.firstMatch(out);
  if (ns == null || sum == null) {
    throw FormatException('saída sem ns= e checksum=:\n$out');
  }
  return (ns: int.parse(ns[1]!), checksum: int.parse(sum[1]!));
}

/// Iterações `k` para uma execução durar cerca de [target] medida.
///
/// A primeira iteração só aquece e não conta, então `k = 1 + medidas`, com
/// `medidas = target / perIterationNs`, com `k` entre 2 e [maxAbIterations].
int calibrateIterations(
  double perIterationNs, {
  Duration target = targetSampleTime,
}) {
  if (perIterationNs <= 0) return maxAbIterations;
  final measured = (target.inMicroseconds * 1000 / perIterationNs).round();
  return (1 + measured).clamp(2, maxAbIterations);
}

/// Amostras de tempo de um benchmark numa versão.
final class AbSamples {
  /// Cria o conjunto.
  const AbSamples({
    required this.iterations,
    required this.checksum,
    required this.nsPerIteration,
  });

  /// `k` usado em cada execução.
  final int iterations;

  /// Checksum devolvido pelo benchmark.
  final int checksum;

  /// Uma amostra por rodada: ns por iteração medida.
  final List<double> nsPerIteration;
}

/// Uma linha da comparação A/B.
final class AbRow {
  /// Cria a linha.
  const AbRow({
    required this.benchId,
    required this.base,
    required this.head,
    required this.ci,
    required this.verdict,
  });

  /// Id do benchmark.
  final String benchId;

  /// Mediana da base (ns por iteração), se medida.
  final double? base;

  /// Mediana do head (ns por iteração), se existir.
  final double? head;

  /// IC da razão head/base; `null` em `added` e `removed`.
  final RatioInterval? ci;

  /// Veredito.
  final AbVerdict verdict;
}

/// Resultado do modo `ab`.
final class AbResult {
  /// Cria o resultado.
  const AbResult({
    required this.rows,
    required this.checksumMismatches,
    required this.notes,
    required this.threshold,
  });

  /// Linhas ordenadas por id.
  final List<AbRow> rows;

  /// Ids com checksums diferentes entre base e head.
  final List<String> checksumMismatches;

  /// Observações para o relatório.
  final List<String> notes;

  /// Limite de regressão usado.
  final double threshold;

  /// 2 se algum checksum diverge, 1 se algum benchmark regrediu, 0 se não.
  int get exitCode {
    if (checksumMismatches.isNotEmpty) return 2;
    if (rows.any((r) => r.verdict == AbVerdict.regressed)) return 1;
    return 0;
  }

  /// BMF `wall-time-ns`: valor = mediana do head; `lower`/`upper` = limites
  /// do IC da razão aplicados à mediana da base. Benchmarks removidos ficam
  /// de fora.
  Map<String, Object> toBmf() => bmf.toBmf({
    for (final r in rows)
      if (r.head != null)
        r.benchId: [
          bmf.Measure(
            slug: bmf.MeasureSlug.wallTimeNs,
            value: r.head!,
            // O percentil do bootstrap pode não envolver o ponto; os limites
            // são ajustados para valer lower ≤ value ≤ upper.
            lower: r.ci == null ? null : min(r.head!, r.base! * r.ci!.lower),
            upper: r.ci == null ? null : max(r.head!, r.base! * r.ci!.upper),
          ),
        ],
  });
}

/// Compara as amostras de [base] e [head], por id.
AbResult evaluateAb({
  required Map<String, AbSamples> base,
  required Map<String, AbSamples> head,
  List<String> notes = const [],
  double threshold = 0.05,
  int resamples = 10000,
}) {
  final ids = {...base.keys, ...head.keys}.toList()..sort();
  final rows = <AbRow>[];
  final mismatches = <String>[];
  for (final id in ids) {
    final b = base[id];
    final h = head[id];
    final bm = b == null || b.nsPerIteration.isEmpty
        ? null
        : median(b.nsPerIteration);
    if (h == null) {
      rows.add(
        AbRow(
          benchId: id,
          base: bm,
          head: null,
          ci: null,
          verdict: AbVerdict.removed,
        ),
      );
    } else if (b == null) {
      rows.add(
        AbRow(
          benchId: id,
          base: null,
          head: median(h.nsPerIteration),
          ci: null,
          verdict: AbVerdict.added,
        ),
      );
    } else {
      if (b.checksum != h.checksum) mismatches.add(id);
      final ci = bootstrapMedianRatio(
        b.nsPerIteration,
        h.nsPerIteration,
        resamples: resamples,
      );
      rows.add(
        AbRow(
          benchId: id,
          base: bm,
          head: median(h.nsPerIteration),
          ci: ci,
          verdict: decideAb(ci, threshold: threshold),
        ),
      );
    }
  }
  return AbResult(
    rows: rows,
    checksumMismatches: mismatches,
    notes: notes,
    threshold: threshold,
  );
}

String _pct(double ratio) {
  final v = (ratio - 1) * 100;
  final s = v.abs().toStringAsFixed(1).replaceAll('.', ',');
  return '${v < 0 ? '−' : '+'}$s%';
}

String _time(double? ns) {
  if (ns == null) return '—';
  if (ns >= 1e6) return '${(ns / 1e6).toStringAsFixed(3)} ms';
  if (ns >= 1e3) return '${(ns / 1e3).toStringAsFixed(3)} µs';
  return '${ns.toStringAsFixed(0)} ns';
}

/// Relatório Markdown do modo `ab`.
String renderAbReport(AbResult r, {required int rounds}) {
  final b = StringBuffer()
    ..writeln('# Comparação de tempo (A/B)')
    ..writeln()
    ..writeln(
      '$rounds rodadas intercaladas · mediana por iteração · '
      'IC 95% bootstrap da razão head/base · '
      'reprova se o IC fica inteiro acima de +${(r.threshold * 100).toStringAsFixed(0)}%',
    )
    ..writeln();
  for (final note in r.notes) {
    b.writeln('> $note');
  }
  if (r.notes.isNotEmpty) b.writeln();
  b
    ..writeln('| benchmark | base | head | variação | IC 95% | status |')
    ..writeln('|---|---:|---:|---:|---|---|');
  for (final row in r.rows) {
    final ci = row.ci;
    b.writeln(
      '| `${row.benchId}` | ${_time(row.base)} | ${_time(row.head)} | '
      '${ci == null ? '—' : _pct(ci.point)} | '
      '${ci == null ? '—' : '${_pct(ci.lower)} … ${_pct(ci.upper)}'} | '
      '${_verdictName(row.verdict)} |',
    );
  }
  if (r.checksumMismatches.isNotEmpty) {
    b
      ..writeln()
      ..writeln('## Checksums divergentes')
      ..writeln();
    for (final id in r.checksumMismatches) {
      b.writeln('- `$id`');
    }
  }
  return b.toString();
}

String _verdictName(AbVerdict v) =>
    v == AbVerdict.inconclusiveOrOk ? 'inconclusive_or_ok' : v.name;

/// Ambiente do `bench_runner` no modo `ab`: o do processo atual sem
/// `DART_VM_OPTIONS`, para medir com o comportamento da VM de produção
/// (GC concorrente incluído). Base e head usam exatamente o mesmo.
Map<String, String> abEnvironment() => {
  for (final e in Platform.environment.entries)
    if (e.key != 'DART_VM_OPTIONS') e.key: e.value,
};

Future<TimedRun> _timed(
  File exe,
  String id,
  int iterations,
  Directory workDir,
  Duration timeout,
) async {
  final r = await runWithTimeout(
    exe.path,
    ['--bench', id, '--iterations', '$iterations', '--timing'],
    environment: abEnvironment(),
    includeParentEnvironment: false,
    workingDirectory: workDir.path,
    timeout: timeout,
    what: id,
  );
  if (r.exitCode != 0) {
    throw MeasurementFailure(
      '$id saiu com código ${r.exitCode}:\n${r.stderr}'.trimRight(),
      exitCode: r.exitCode,
    );
  }
  try {
    return parseTimedRun(r.stdout as String);
  } on FormatException catch (e) {
    throw MeasurementFailure('$id: ${e.message}');
  }
}

/// Confere que o checksum de [id] não muda entre rodadas do mesmo lado.
int _sameChecksum(String id, String side, int? previous, int current) {
  if (previous != null && previous != current) {
    throw MeasurementFailure(
      '$id: checksum instável na $side entre rodadas ($previous e $current)',
    );
  }
  return current;
}

/// Se o `bench_runner` de [exe] aceita `--timing`.
///
/// Só o código 64 com `--timing` no stderr (opção desconhecida de um runner
/// antigo) significa "não aceita". Qualquer outra falha (queda, corpus
/// ausente, sinal, tempo esgotado) lança [MeasurementFailure], para não
/// mascarar uma base quebrada como "tudo `added`". Usa [abEnvironment] e
/// [timeout], como as medições.
Future<bool> baseSupportsTiming(
  File exe,
  Directory workDir, {
  Duration timeout = defaultAbTimeout,
}) async {
  final r = await runWithTimeout(
    exe.path,
    ['--bench', 'harness/noop', '--iterations', '2', '--timing'],
    environment: abEnvironment(),
    includeParentEnvironment: false,
    workingDirectory: workDir.path,
    timeout: timeout,
    what: 'sonda de --timing',
  );
  if (r.exitCode == 0) return true;
  if (r.exitCode == 64 && (r.stderr as String).contains('--timing')) {
    return false;
  }
  throw MeasurementFailure(
    'sonda de --timing saiu com código ${r.exitCode}:\n${r.stderr}'.trimRight(),
    exitCode: r.exitCode,
  );
}

/// Executa o modo `ab`: mede [baseRef] e [headRef] em [rounds] rodadas
/// intercaladas e decide o gate.
///
/// Para cada benchmark, `k` é calibrado no head para ~200 ms por amostra
/// (a mesma `k` nos dois lados) e cada rodada roda a base e depois o head.
/// Cada amostra é o tempo de relógio das iterações 2 a `k`, medido dentro do
/// `bench_runner` (`--timing`): partida do processo, `setUp` e a iteração de
/// aquecimento ficam fora, então não há `noop` a descontar. Escreve o BMF
/// `wall-time-ns` em [outPath] e o relatório em [reportPath]. Devolve 0
/// (aprovado), 1 (regressão), 2 (checksums divergentes) ou 70 (falha).
Future<int> runAb({
  required String baseRef,
  required String headRef,
  int rounds = defaultRounds,
  String? outPath,
  String? reportPath,
  List<String> only = const [],
  Duration timeout = defaultAbTimeout,
  StringSink? log,
}) {
  final logSink = log ?? stderr;
  return runSession('galley-ab-', log: logSink, (session) async {
    if (rounds < 3) {
      throw ArgumentError.value(rounds, 'rounds', 'exige ≥ 3 rodadas');
    }
    final v = await session.prepare(
      baseRef: baseRef,
      headRef: headRef,
      only: only,
    );
    final notes = [...v.notes];
    var baseExe = v.baseExe;
    if (baseExe != null &&
        !await baseSupportsTiming(baseExe, v.baseWorkDir, timeout: timeout)) {
      notes.add(
        'O bench_runner da base ($baseRef) não aceita `--timing`: todos os '
        'benchmarks do head entram como `added`.',
      );
      baseExe = null;
    }

    final base = <String, AbSamples>{};
    final head = <String, AbSamples>{};
    for (final id in v.headIds) {
      logSink.writeln('ab  $id');
      final probe = await _timed(
        v.headExe,
        id,
        _calibrationIterations,
        v.headWorkDir,
        timeout,
      );
      final k = calibrateIterations(probe.ns / (_calibrationIterations - 1));
      // Quem aceita --timing também tem --list (Task 5), logo baseIds existe.
      final onBase = baseExe != null && (v.baseIds?.contains(id) ?? false);
      final baseSamples = <double>[];
      final headSamples = <double>[];
      int? baseSum;
      int? headSum;
      // Aquecimento da base (simétrico à calibração do head), descartado.
      if (onBase) await _timed(baseExe, id, k, v.baseWorkDir, timeout);
      Future<void> sampleBase() async {
        final r = await _timed(baseExe!, id, k, v.baseWorkDir, timeout);
        baseSum = _sameChecksum(id, 'base', baseSum, r.checksum);
        baseSamples.add(r.ns / (k - 1));
      }

      Future<void> sampleHead() async {
        final r = await _timed(v.headExe, id, k, v.headWorkDir, timeout);
        headSum = _sameChecksum(id, 'head', headSum, r.checksum);
        headSamples.add(r.ns / (k - 1));
      }

      // ABBA: a ordem alterna a cada rodada para cancelar efeitos de posição.
      for (var i = 0; i < rounds; i++) {
        if (i.isEven) {
          if (onBase) await sampleBase();
          await sampleHead();
        } else {
          await sampleHead();
          if (onBase) await sampleBase();
        }
      }
      head[id] = AbSamples(
        iterations: k,
        checksum: headSum!,
        nsPerIteration: headSamples,
      );
      if (baseSamples.isNotEmpty) {
        base[id] = AbSamples(
          iterations: k,
          checksum: baseSum!,
          nsPerIteration: baseSamples,
        );
      }
    }
    // Só na base: aparecem como `removed`, sem medição.
    for (final id in v.baseIds ?? const <String>[]) {
      if (!v.headIds.contains(id)) {
        base[id] = const AbSamples(
          iterations: 0,
          checksum: 0,
          nsPerIteration: [],
        );
      }
    }

    final result = evaluateAb(base: base, head: head, notes: notes);
    final report = renderAbReport(result, rounds: rounds);
    if (outPath != null) {
      await File(outPath).writeAsString(
        const JsonEncoder.withIndent('  ').convert(result.toBmf()),
      );
    }
    if (reportPath != null) await File(reportPath).writeAsString(report);
    stdout.write(report);
    if (result.checksumMismatches.isNotEmpty) {
      logSink.writeln(
        'Checksums divergentes entre base e head: '
        '${result.checksumMismatches.join(', ')}',
      );
    }
    return result.exitCode;
  });
}
