// Implementação do harness de desempenho: amostragem, calibração e escrita
// do result.json (spec §2).
// ignore_for_file: avoid_relative_lib_imports — tool/ não é pacote; importar por caminho é intencional.
/// Harness de desempenho da Fase 0 (doc/specs/2026-09-25-harness-ci-design.md
/// §2). Mede cada caso intercalado com uma calibração fixa e registra a
/// mediana das razões, que é o que o gate compara.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../tool/perf/lib/perf_report.dart';
import '../../../tool/perf/lib/stats.dart';

const int warmupSamples = 3;
const int measuredSamples = 15;
const String defaultResultPath = 'build/perf/result.json';

/// Um caso medido. Exatamente um de [run] e [runAsync].
final class PerfCase {
  PerfCase({
    required this.id,
    this.run,
    this.runAsync,
    this.setUp,
    this.innerIterations = 1,
  }) {
    if ((run == null) == (runAsync == null)) {
      throw ArgumentError(
        'PerfCase "$id": informe exatamente um de run e runAsync',
      );
    }
  }

  /// Chave estável do baseline.
  final String id;
  final void Function()? run;
  final Future<void> Function()? runAsync;

  /// Preparação fora do tempo, uma vez antes das amostras.
  final Future<void> Function()? setUp;

  /// Repetições do corpo por amostra.
  final int innerIterations;
}

/// Repetições da carga de calibração; ajustado para ~5 ms no desktop de
/// desenvolvimento (spec §2.3).
const int _calibrationRounds = 4;

final Uint8List _calibrationBuffer = Uint8List.fromList(
  List<int>.generate(64 * 1024, (i) => (i * 31) & 0xff),
);

int _sink = 0;

/// Acumulador da calibração, para o trabalho não ser eliminado.
int get calibrationSink => _sink;

/// Carga fixa em Dart puro: FNV-1a 32 sobre 64 KB, `StringBuffer`, `Map` e
/// `sort`, repetidos [_calibrationRounds] vezes.
void calibrationWorkload() {
  var h = 0x811c9dc5;
  for (var round = 0; round < _calibrationRounds; round++) {
    for (final b in _calibrationBuffer) {
      h = ((h ^ b) * 0x01000193) & 0xffffffff;
    }
    final sb = StringBuffer();
    for (var i = 0; i < 2000; i++) {
      sb
        ..write('w')
        ..write(i)
        ..write(' ');
    }
    h ^= sb.length;
    final m = <String, int>{};
    for (var i = 0; i < 2000; i++) {
      m['k$i'] = i;
    }
    for (var i = 0; i < 2000; i++) {
      h ^= m['k${(i * 7) % 2000}']!;
    }
    final list = List<int>.generate(
      5000,
      (i) => (i * 2654435761 + round) & 0xffff,
    )..sort();
    h ^= list[2500];
  }
  _sink ^= h | 1;
}

double _micros(Stopwatch sw) => sw.elapsedTicks * 1e6 / sw.frequency;

/// Mede [c]: [warmup] amostras descartadas e [samples] medidas, cada uma
/// com a calibração e em seguida o caso.
Future<PerfCaseResult> measureCase(
  PerfCase c, {
  int warmup = warmupSamples,
  int samples = measuredSamples,
  void Function() calibration = calibrationWorkload,
}) async {
  await c.setUp?.call();
  final ratios = <double>[];
  final caseUs = <double>[];
  final calibrationUs = <double>[];
  final sw = Stopwatch();
  for (var i = 0; i < warmup + samples; i++) {
    sw
      ..reset()
      ..start();
    calibration();
    sw.stop();
    final cal = _micros(sw);

    sw
      ..reset()
      ..start();
    for (var k = 0; k < c.innerIterations; k++) {
      final run = c.run;
      if (run != null) {
        run();
      } else {
        await c.runAsync!();
      }
    }
    sw.stop();
    final t = _micros(sw);

    if (i < warmup) continue;
    // Piso de 1 tick nos dois lados: a razão nunca é 0 nem infinita.
    final tick = 1e6 / sw.frequency;
    ratios.add((t < tick ? tick : t) / (cal < tick ? tick : cal));
    caseUs.add(t);
    calibrationUs.add(cal);
  }
  return PerfCaseResult(
    ratio: median(ratios),
    medianUs: median(caseUs),
    calibrationUs: median(calibrationUs),
    samples: ratios,
  );
}

/// `FLUTTER_VERSION` quando definida; senão `frameworkVersion` de
/// `flutter --version --machine`; senão `"unknown"`.
Future<String> detectFlutterVersion({
  Map<String, String>? environment,
  Future<ProcessResult> Function(String, List<String>)? runProcess,
}) async {
  final fromEnv = (environment ?? Platform.environment)['FLUTTER_VERSION'];
  if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
  try {
    final r = await (runProcess ?? Process.run)('flutter', [
      '--version',
      '--machine',
    ]);
    if (r.exitCode != 0) return 'unknown';
    final out = r.stdout as String;
    final start = out.indexOf('{');
    if (start < 0) return 'unknown';
    final json = jsonDecode(out.substring(start));
    if (json is Map<String, Object?> && json['frameworkVersion'] is String) {
      return json['frameworkVersion']! as String;
    }
  } on Object {
    // Sem flutter no PATH ou saída inesperada: versão desconhecida.
  }
  return 'unknown';
}

/// Modelo da CPU a partir de `/proc/cpuinfo`: valor (depois do primeiro `:`,
/// com `trim()`) da primeira linha que começa com `model name`. Arquivo
/// inexistente, ilegível ou sem a linha devolve `'unknown'`.
String detectCpuModel({String cpuinfoPath = '/proc/cpuinfo'}) {
  try {
    final lines = File(cpuinfoPath).readAsLinesSync();
    for (final line in lines) {
      if (line.startsWith('model name')) {
        final i = line.indexOf(':');
        if (i < 0) continue;
        return line.substring(i + 1).trim();
      }
    }
  } on Object {
    // Arquivo inexistente ou ilegível: modelo desconhecido.
  }
  return 'unknown';
}

/// Escreve o `result.json` se houver ao menos um caso medido. A suíte normal
/// pula os casos `perf`, e um relatório vazio não pode sobrescrever o último.
Future<bool> writeResultIfAny(
  Map<String, PerfCaseResult> cases, {
  String path = defaultResultPath,
  Map<String, String>? environment,
  String? cpuinfoPath,
}) async {
  if (cases.isEmpty) return false;
  final report = PerfReport(
    flutter: await detectFlutterVersion(environment: environment),
    dart: Platform.version.split(' ').first,
    os: Platform.operatingSystem,
    createdAt: DateTime.now().toUtc(),
    cases: cases,
    cpu: cpuinfoPath == null
        ? detectCpuModel()
        : detectCpuModel(cpuinfoPath: cpuinfoPath),
  );
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(report.encode());
  return true;
}
