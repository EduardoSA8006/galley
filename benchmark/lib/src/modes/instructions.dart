import 'dart:convert';
import 'dart:io';

import '../bmf.dart' as bmf;
import 'build.dart';

/// Contador de instruções usado no modo `instructions`.
enum Counter {
  /// `valgrind --tool=cachegrind` (CI; não precisa de contadores de hardware).
  valgrind,

  /// `perf stat -e instructions:u` (local, em velocidade nativa).
  perf,
}

/// Iterações da execução curta: exclui a primeira iteração (inicializações
/// preguiçosas, caches estáticos) da diferença, porque ela roda nas duas.
const int defaultLowIterations = 1;

/// Iterações da execução longa: a diferença cobre 3 iterações em regime,
/// o que dilui oscilações pontuais (ex.: coleta de lixo) sem encarecer
/// demais o Valgrind no CI.
const int defaultHighIterations = 4;

/// Flags da VM aplicadas ao `bench_runner` via `DART_VM_OPTIONS` (separadas
/// por vírgula) durante a contagem, para a contagem ser determinística.
///
/// - GC sem marcação/varredura concorrentes e com uma tarefa por fase: com
///   os padrões, as threads auxiliares do GC fazem esperas que dependem do
///   tempo de relógio, e o mesmo binário variou ~3% sob o Valgrind.
/// - `--old_gen_growth_time_ratio=100`: o crescimento do heap velho também
///   depende da fração de tempo gasta em GC; com o padrão (3%), o número de
///   mark-sweeps mudava entre execuções (saltos de ~5% em
///   `container/deobfuscate-idpf`). Com 100, só o espaço decide.
/// - `--random_seed` fixo: os hash codes de identidade vêm de um gerador
///   aleatório da VM; sem semente, as colisões nos mapas mudam a cada
///   execução (~0,1% de variação).
///
/// Com isso, execuções repetidas variam ~0,001%, e o custo do GC continua
/// medido. `--marker_tasks=0` não serve: a VM aborta no primeiro mark-sweep
/// (`expected: num_tasks > 0`).
const String deterministicVmOptions =
    '--no_concurrent_mark,--no_concurrent_sweep,'
    '--marker_tasks=1,--scavenger_tasks=1,'
    '--old_gen_growth_time_ratio=100,--random_seed=42';

/// Limite do gate: regressão acima de 0,5% reprova.
const double defaultThreshold = 0.005;

/// O contador pedido não está disponível nesta máquina.
final class CounterUnavailable implements Exception {
  /// Cria o erro com uma [message] que diz como corrigir.
  const CounterUnavailable(this.message);

  /// Valgrind não encontrado no `PATH`.
  const CounterUnavailable.valgrindMissing()
    : message = 'instale valgrind (ex.: sudo apt-get install -y valgrind)';

  /// `perf` não encontrado no `PATH`.
  const CounterUnavailable.perfMissing()
    : message =
          'instale perf (ex.: sudo apt-get install -y linux-tools-generic) '
          'ou use --counter valgrind';

  /// `perf` bloqueado pelo `kernel.perf_event_paranoid` de valor [paranoid].
  CounterUnavailable.perfBlocked(Object paranoid)
    : message =
          'perf_event_paranoid=$paranoid; rode: sudo sysctl '
          'kernel.perf_event_paranoid=1 ou use --counter valgrind';

  /// Mensagem com a correção sugerida.
  final String message;

  @override
  String toString() => 'CounterUnavailable: $message';
}

/// Falha ao medir um benchmark (o `bench_runner` falhou ou a saída é
/// inesperada).
final class MeasurementFailure implements Exception {
  /// Cria a falha.
  const MeasurementFailure(this.message, {this.exitCode});

  /// Descrição da falha.
  final String message;

  /// Código de saída do `bench_runner`, se ele chegou a sair.
  final int? exitCode;

  @override
  String toString() => 'MeasurementFailure: $message';
}

final _iRefs = RegExp(r'I\s+refs:\s+([\d,]+)');
final _checksum = RegExp(r'^checksum=(-?\d+)\s*$', multiLine: true);

/// Lê a contagem `I refs` do stderr do cachegrind.
///
/// Lança [FormatException] se a linha não existir.
int parseCachegrindInstructions(String stderrText) {
  final m = _iRefs.firstMatch(stderrText);
  if (m == null) {
    throw const FormatException('linha "I refs" ausente na saída do Valgrind');
  }
  return int.parse(m[1]!.replaceAll(',', ''));
}

/// Lê a contagem de `perf stat -x, -e instructions:u`.
///
/// Procura a linha CSV cujo terceiro campo é o evento `instructions`; lança
/// [FormatException] se ela faltar ou se o perf não contou
/// (`<not supported>`, `<not counted>`).
int parsePerfInstructions(String stderrText) {
  for (final line in const LineSplitter().convert(stderrText)) {
    final fields = line.split(',');
    if (fields.length < 3 || !fields[2].startsWith('instructions')) continue;
    final value = int.tryParse(fields[0].trim());
    if (value == null) {
      throw FormatException('perf não contou instruções: ${fields[0]}');
    }
    return value;
  }
  throw const FormatException('linha de instructions ausente na saída do perf');
}

/// Uma execução do `bench_runner` sob o contador.
final class CountedRun {
  /// Cria o resultado.
  const CountedRun({required this.instructions, required this.checksum});

  /// Instruções do processo inteiro (partida, `setUp` e iterações).
  final int instructions;

  /// Checksum impresso pelo `bench_runner`.
  final int checksum;
}

String? _which(String name, Map<String, String> env) {
  for (final dir in (env['PATH'] ?? '').split(':')) {
    if (dir.isEmpty) continue;
    final f = File('$dir/$name');
    if (f.existsSync() && f.statSync().mode & 0x49 != 0) return f.path;
  }
  return null;
}

/// Caminho do executável de [counter], ou [CounterUnavailable] se faltar no
/// `PATH` de [environment] (padrão: o ambiente do processo).
String counterExecutable(Counter counter, {Map<String, String>? environment}) {
  final env = environment ?? Platform.environment;
  return switch (counter) {
    Counter.valgrind =>
      _which('valgrind', env) ??
          (throw const CounterUnavailable.valgrindMissing()),
    Counter.perf =>
      _which('perf', env) ?? (throw const CounterUnavailable.perfMissing()),
  };
}

String _paranoid() {
  try {
    return File('/proc/sys/kernel/perf_event_paranoid')
        .readAsStringSync()
        .trim();
  } on FileSystemException {
    return '?';
  }
}

/// Executa [benchId] por [iterations] ciclos sob [counter] e devolve as
/// instruções do processo inteiro e o checksum.
///
/// O processo herda o ambiente atual mais [environment] e
/// [deterministicVmOptions], e roda em [workingDirectory] (o `benchmark/`
/// do checkout, de onde o `bench_runner` acha o `corpus/`).
Future<CountedRun> runCounted(
  File exe,
  String benchId,
  int iterations,
  Counter counter, {
  Map<String, String>? environment,
  Directory? workingDirectory,
}) async {
  final tool = counterExecutable(counter, environment: environment);
  final runner = [exe.path, '--bench', benchId, '--iterations', '$iterations'];
  final args = switch (counter) {
    Counter.valgrind => [
      '--tool=cachegrind',
      '--cache-sim=no',
      '--cachegrind-out-file=/dev/null',
      ...runner,
    ],
    Counter.perf => ['stat', '-x,', '-e', 'instructions:u', '--', ...runner],
  };
  final r = await Process.run(
    tool,
    args,
    environment: {...?environment, 'DART_VM_OPTIONS': deterministicVmOptions},
    workingDirectory: workingDirectory?.path,
  );
  final out = r.stdout as String;
  final err = r.stderr as String;

  int? count;
  try {
    count = counter == Counter.valgrind
        ? parseCachegrindInstructions(err)
        : parsePerfInstructions(err);
  } on FormatException {
    if (counter == Counter.perf && _perfDenied(r.exitCode, err)) {
      throw CounterUnavailable.perfBlocked(_paranoid());
    }
  }
  if (r.exitCode != 0) {
    throw MeasurementFailure(
      '$benchId saiu com código ${r.exitCode}:\n$err'.trimRight(),
      exitCode: r.exitCode,
    );
  }
  if (count == null) {
    throw MeasurementFailure('$benchId: contagem ausente na saída:\n$err');
  }
  final m = _checksum.firstMatch(out);
  if (m == null) {
    throw MeasurementFailure('$benchId: checksum ausente na saída:\n$out');
  }
  return CountedRun(instructions: count, checksum: int.parse(m[1]!));
}

/// Se a falha do perf é de permissão (e não do benchmark).
bool _perfDenied(int exitCode, String err) =>
    err.contains('perf_event_paranoid') ||
    err.contains('Permission denied') ||
    err.contains('Access to performance monitoring') ||
    err.contains('<not supported>') ||
    (exitCode == 0 && err.contains('<not counted>'));

/// Contagem de instruções de um benchmark numa versão, com os dados brutos.
final class InstructionCount {
  /// Cria a contagem.
  const InstructionCount({
    required this.lowIterations,
    required this.highIterations,
    required this.low,
    required this.high,
    required this.checksum,
  });

  /// Iterações da execução curta (n1).
  final int lowIterations;

  /// Iterações da execução longa (n2).
  final int highIterations;

  /// Instruções do processo com [lowIterations] iterações, I(n1).
  final int low;

  /// Instruções do processo com [highIterations] iterações, I(n2).
  final int high;

  /// Checksum do benchmark (igual nas duas execuções).
  final int checksum;

  /// Instruções por iteração: (I(n2) − I(n1)) / (n2 − n1).
  ///
  /// A diferença cancela a partida do processo e o `setUp`, que entram nas
  /// duas execuções.
  int get perIteration =>
      ((high - low) / (highIterations - lowIterations)).round();
}

/// Conta as instruções por iteração de [benchId] no executável [exe].
///
/// Roda o benchmark com [lowIterations] e [highIterations] iterações e
/// devolve a diferença por iteração (ver [InstructionCount.perIteration]).
/// Lança [CounterUnavailable] se o contador faltar ou estiver bloqueado e
/// [MeasurementFailure] se o benchmark falhar, se os checksums das duas
/// execuções divergirem ou se a contagem não crescer com as iterações.
/// [environment] e [workingDirectory] seguem [runCounted].
Future<InstructionCount> countInstructions(
  File exe,
  String benchId,
  Counter counter, {
  int lowIterations = defaultLowIterations,
  int highIterations = defaultHighIterations,
  Map<String, String>? environment,
  Directory? workingDirectory,
}) async {
  if (lowIterations < 1 || highIterations <= lowIterations) {
    throw ArgumentError(
      'iterações inválidas: n1=$lowIterations, n2=$highIterations',
    );
  }
  counterExecutable(counter, environment: environment);
  final a = await runCounted(
    exe,
    benchId,
    lowIterations,
    counter,
    environment: environment,
    workingDirectory: workingDirectory,
  );
  final b = await runCounted(
    exe,
    benchId,
    highIterations,
    counter,
    environment: environment,
    workingDirectory: workingDirectory,
  );
  if (a.checksum != b.checksum) {
    throw MeasurementFailure(
      '$benchId: checksum instável na mesma versão '
      '(${a.checksum} com n=$lowIterations, ${b.checksum} com '
      'n=$highIterations)',
    );
  }
  if (b.instructions <= a.instructions) {
    throw MeasurementFailure(
      '$benchId: I(n2)=${b.instructions} não é maior que '
      'I(n1)=${a.instructions}',
    );
  }
  return InstructionCount(
    lowIterations: lowIterations,
    highIterations: highIterations,
    low: a.instructions,
    high: b.instructions,
    checksum: b.checksum,
  );
}

/// Ids do catálogo de [exe] (`bench_runner --list`), ou `null` se esse
/// `bench_runner` não tiver `--list` (versões antigas).
Future<List<String>?> listBenches(File exe) async {
  final r = await Process.run(exe.path, ['--list']);
  if (r.exitCode != 0) return null;
  return const LineSplitter()
      .convert(r.stdout as String)
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
}

/// Situação de um benchmark no gate.
enum GateStatus {
  /// Dentro do limite.
  ok,

  /// Caiu mais que o limite.
  improved,

  /// Subiu mais que o limite: reprova.
  regressed,

  /// Só existe no head (não reprova).
  added,

  /// Só existe na base (não reprova).
  removed,
}

/// Uma linha da comparação base × head.
final class GateRow {
  /// Cria a linha.
  const GateRow({
    required this.benchId,
    required this.base,
    required this.head,
    required this.ratio,
    required this.status,
  });

  /// Id do benchmark.
  final String benchId;

  /// Instruções por iteração na base, se existir.
  final double? base;

  /// Instruções por iteração no head, se existir.
  final double? head;

  /// head / base, quando os dois existem e a base é positiva.
  final double? ratio;

  /// Resultado do gate.
  final GateStatus status;
}

/// Compara as instruções por benchmark da [base] e do [head].
///
/// Reprova (`regressed`) quando head/base > 1 + [threshold]; marca
/// `improved` quando head/base < 1 − [threshold]. As linhas saem ordenadas
/// por id.
List<GateRow> compareInstructions(
  Map<String, int> base,
  Map<String, int> head, {
  double threshold = defaultThreshold,
}) {
  final ids = {...base.keys, ...head.keys}.toList()..sort();
  return [for (final id in ids) _row(id, base[id], head[id], threshold)];
}

GateRow _row(String id, int? base, int? head, double threshold) {
  if (base == null) {
    return GateRow(
      benchId: id,
      base: null,
      head: head!.toDouble(),
      ratio: null,
      status: GateStatus.added,
    );
  }
  if (head == null) {
    return GateRow(
      benchId: id,
      base: base.toDouble(),
      head: null,
      ratio: null,
      status: GateStatus.removed,
    );
  }
  final ratio = base > 0 ? head / base : null;
  final GateStatus status;
  if (ratio == null) {
    status = head > base ? GateStatus.regressed : GateStatus.ok;
  } else if (ratio > 1 + threshold) {
    status = GateStatus.regressed;
  } else if (ratio < 1 - threshold) {
    status = GateStatus.improved;
  } else {
    status = GateStatus.ok;
  }
  return GateRow(
    benchId: id,
    base: base.toDouble(),
    head: head.toDouble(),
    ratio: ratio,
    status: status,
  );
}

/// Resultado do gate de instruções.
final class GateResult {
  /// Cria o resultado.
  const GateResult({
    required this.rows,
    required this.base,
    required this.head,
    required this.checksumMismatches,
    required this.notes,
    required this.threshold,
  });

  /// Comparação por benchmark, ordenada por id.
  final List<GateRow> rows;

  /// Contagens da base, por id.
  final Map<String, InstructionCount> base;

  /// Contagens do head, por id.
  final Map<String, InstructionCount> head;

  /// Ids presentes nas duas versões cujos checksums divergem.
  final List<String> checksumMismatches;

  /// Observações para o relatório (ex.: base sem `benchmark/`).
  final List<String> notes;

  /// Limite usado na comparação.
  final double threshold;

  /// 2 se algum checksum diverge, 1 se algum benchmark regrediu, 0 se não.
  int get exitCode {
    if (checksumMismatches.isNotEmpty) return 2;
    if (rows.any((r) => r.status == GateStatus.regressed)) return 1;
    return 0;
  }

  /// BMF com as instruções por iteração do head.
  Map<String, Object> toBmf() => bmf.toBmf({
    for (final e in head.entries)
      e.key: [
        bmf.Measure(
          slug: bmf.MeasureSlug.instructions,
          value: e.value.perIteration.toDouble(),
        ),
      ],
  });
}

/// Monta o [GateResult] a partir das contagens de [base] e [head].
GateResult evaluateGate({
  required Map<String, InstructionCount> base,
  required Map<String, InstructionCount> head,
  List<String> notes = const [],
  double threshold = defaultThreshold,
}) {
  final mismatches = [
    for (final id in head.keys)
      if (base[id] != null && base[id]!.checksum != head[id]!.checksum) id,
  ]..sort();
  return GateResult(
    rows: compareInstructions(
      {for (final e in base.entries) e.key: e.value.perIteration},
      {for (final e in head.entries) e.key: e.value.perIteration},
      threshold: threshold,
    ),
    base: base,
    head: head,
    checksumMismatches: mismatches,
    notes: notes,
    threshold: threshold,
  );
}

String _int(double? v) => v == null ? '—' : v.round().toString();

String _percent(double v, {bool sign = true}) {
  final s = (v * 100).abs().toStringAsFixed(3).replaceAll('.', ',');
  if (!sign) return '$s%';
  return '${v < 0 ? '−' : '+'}$s%';
}

/// Relatório em Markdown do gate (tabela, checksums divergentes e contagens
/// brutas para depuração).
String renderReport(GateResult r, {Counter? counter}) {
  final b = StringBuffer()
    ..writeln('# Gate de instruções')
    ..writeln();
  final any = [...r.head.values, ...r.base.values].firstOrNull;
  b.writeln(
    [
      if (counter != null) 'Contador: `${counter.name}`',
      'limite: +${_percent(r.threshold, sign: false)}',
      if (any != null)
        'instruções por iteração = (I(n2) − I(n1)) / (n2 − n1), '
            'n1=${any.lowIterations}, n2=${any.highIterations}',
    ].join(' · '),
  );
  b.writeln();
  for (final note in r.notes) {
    b.writeln('> $note');
  }
  if (r.notes.isNotEmpty) b.writeln();
  b
    ..writeln('| benchmark | base | head | variação | status |')
    ..writeln('|---|---:|---:|---:|---|');
  for (final row in r.rows) {
    final ratio = row.ratio;
    b.writeln(
      '| `${row.benchId}` | ${_int(row.base)} | ${_int(row.head)} | '
      '${ratio == null ? '—' : _percent(ratio - 1)} | ${row.status.name} |',
    );
  }
  if (r.checksumMismatches.isNotEmpty) {
    b
      ..writeln()
      ..writeln('## Checksums divergentes')
      ..writeln();
    for (final id in r.checksumMismatches) {
      b.writeln(
        '- `$id`: base ${r.base[id]!.checksum}, head ${r.head[id]!.checksum}',
      );
    }
  }
  b
    ..writeln()
    ..writeln('## Contagens brutas')
    ..writeln()
    ..writeln('| benchmark | versão | I(n1) | I(n2) | checksum |')
    ..writeln('|---|---|---:|---:|---:|');
  for (final row in r.rows) {
    for (final (label, c) in [
      ('base', r.base[row.benchId]),
      ('head', r.head[row.benchId]),
    ]) {
      if (c == null) continue;
      b.writeln(
        '| `${row.benchId}` | $label | ${c.low} | ${c.high} | ${c.checksum} |',
      );
    }
  }
  return b.toString();
}

/// Código de saída quando o contador não está disponível (EX_UNAVAILABLE).
const int exitCounterUnavailable = 69;

/// Código de saída quando a preparação ou a medição falha (EX_SOFTWARE).
const int exitInstructionsFailure = 70;

/// Executa o modo `instructions`: mede [baseRef] e [headRef] no mesmo
/// processo e decide o gate.
///
/// Cada ref vira um `git worktree` temporário com o `bench_runner` compilado
/// em AOT; os benchmarks rodam intercalados (base, head) por benchmark. Os
/// ids `harness/*` ficam fora. [only], se não vazio, restringe aos ids
/// dados. Escreve o BMF em [outPath] e o relatório em [reportPath] (quando
/// dados) e devolve o código de saída: 0 aprovado, 1 regressão, 2 checksums
/// divergentes, [exitCounterUnavailable] ou [exitInstructionsFailure].
Future<int> runInstructions({
  required String baseRef,
  required String headRef,
  required Counter counter,
  String? outPath,
  String? reportPath,
  List<String> only = const [],
  int lowIterations = defaultLowIterations,
  int highIterations = defaultHighIterations,
  StringSink? log,
}) async {
  final logSink = log ?? stderr;
  final workDir = await Directory.systemTemp.createTemp('galley-instr-');
  final checkouts = <Directory>[];
  try {
    counterExecutable(counter);
    final root = await repoRoot();

    Future<Directory> checkout(String ref) async {
      logSink.writeln('Preparando $ref…');
      final dir = await prepareCheckout(ref, workDir, repo: root);
      checkouts.add(dir);
      return dir;
    }

    final headDir = await checkout(headRef);
    if (!hasBenchRunner(headDir)) {
      throw BuildFailure('o head ($headRef) não tem $benchRunnerPath');
    }
    final baseDir = await checkout(baseRef);
    final notes = <String>[];

    logSink.writeln('Compilando o bench_runner do head…');
    final headExe = await compileRunner(
      checkout: headDir,
      outPath: '${workDir.path}/head-runner',
    );
    File? baseExe;
    if (hasBenchRunner(baseDir)) {
      logSink.writeln('Compilando o bench_runner da base…');
      baseExe = await compileRunner(
        checkout: baseDir,
        outPath: '${workDir.path}/base-runner',
      );
    } else {
      notes.add(
        'A base ($baseRef) não tem `benchmark/`: todos os benchmarks do head '
        'entram como `added`.',
      );
    }

    bool selected(String id) =>
        !id.startsWith('harness/') && (only.isEmpty || only.contains(id));
    final headIds = (await listBenches(headExe))?.where(selected).toList();
    if (headIds == null) {
      throw const BuildFailure('o bench_runner do head não aceitou --list');
    }
    final unknown = only.where((id) => !headIds.contains(id)).toList();
    if (unknown.isNotEmpty) {
      throw BuildFailure('benchmarks desconhecidos no head: $unknown');
    }
    // `null`: a base tem bench_runner, mas sem --list (versão antiga); cada
    // id do head é tentado e o código 64 significa "não existe na base".
    final baseIds = baseExe == null
        ? const <String>[]
        : (await listBenches(baseExe))?.where(selected).toList();

    final ids = {...headIds, ...?baseIds}.toList()..sort();
    final base = <String, InstructionCount>{};
    final head = <String, InstructionCount>{};
    for (final id in ids) {
      if (baseExe != null && (baseIds == null || baseIds.contains(id))) {
        logSink.writeln('base  $id');
        try {
          base[id] = await countInstructions(
            baseExe,
            id,
            counter,
            workingDirectory: Directory('${baseDir.path}/benchmark'),
            lowIterations: lowIterations,
            highIterations: highIterations,
          );
        } on MeasurementFailure catch (e) {
          if (baseIds != null || e.exitCode != 64) rethrow;
        }
      }
      if (headIds.contains(id)) {
        logSink.writeln('head  $id');
        head[id] = await countInstructions(
          headExe,
          id,
          counter,
          workingDirectory: Directory('${headDir.path}/benchmark'),
          lowIterations: lowIterations,
          highIterations: highIterations,
        );
      }
    }

    final result = evaluateGate(base: base, head: head, notes: notes);
    final report = renderReport(result, counter: counter);
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
  } on CounterUnavailable catch (e) {
    logSink.writeln('Contador indisponível: ${e.message}');
    return exitCounterUnavailable;
  } on BuildFailure catch (e) {
    logSink.writeln('Falha na preparação: ${e.message}');
    return exitInstructionsFailure;
  } on MeasurementFailure catch (e) {
    logSink.writeln('Falha na medição: ${e.message}');
    return exitInstructionsFailure;
  } finally {
    for (final dir in checkouts) {
      await removeCheckout(dir);
    }
    try {
      await workDir.delete(recursive: true);
    } on FileSystemException {
      // Diretório temporário: o sistema limpa depois.
    }
  }
}
