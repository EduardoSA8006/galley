import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'build.dart';

/// Código de saída quando a preparação ou a medição falha (EX_SOFTWARE).
const int exitMeasurementFailure = 70;

/// Linha `checksum=<int>` impressa pelo `bench_runner`.
final RegExp checksumPattern = RegExp(
  r'^checksum=(-?\d+)\s*$',
  multiLine: true,
);

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

/// Roda [executable] e espera até [timeout]; ao estourar, mata o processo e
/// todos os descendentes e lança [MeasurementFailure] citando [what].
Future<ProcessResult> runWithTimeout(
  String executable,
  List<String> args, {
  required Map<String, String> environment,
  required String? workingDirectory,
  required Duration timeout,
  required String what,
  bool includeParentEnvironment = true,
}) async {
  final p = await Process.start(
    executable,
    args,
    environment: environment,
    includeParentEnvironment: includeParentEnvironment,
    workingDirectory: workingDirectory,
  );
  final out = p.stdout.transform(utf8.decoder).join();
  final err = p.stderr.transform(utf8.decoder).join();
  final int code;
  try {
    code = await p.exitCode.timeout(timeout);
  } on TimeoutException {
    await _killTree(p.pid);
    await p.exitCode;
    // Netos órfãos podem segurar os pipes; não esperamos pela saída.
    unawaited(out.then((_) {}, onError: (_) {}));
    unawaited(err.then((_) {}, onError: (_) {}));
    throw MeasurementFailure(
      '$what: tempo esgotado após ${timeout.inSeconds} s; processo morto',
    );
  }
  return ProcessResult(p.pid, code, await out, await err);
}

/// Mata [pid] e os descendentes (via `pgrep -P`), dos netos para cima.
Future<void> _killTree(int pid) async {
  final children = <int>[];
  try {
    final r = await Process.run('pgrep', ['-P', '$pid']);
    children.addAll(
      const LineSplitter().convert(r.stdout as String).map(int.parse),
    );
  } on Object {
    // Sem pgrep: mata só o processo direto.
  }
  // Para os filhos antes de descer, para não renascerem netos.
  Process.killPid(pid, ProcessSignal.sigstop);
  for (final child in children) {
    await _killTree(child);
  }
  Process.killPid(pid, ProcessSignal.sigkill);
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

/// Base e head prontos para medir: checkouts, `bench_runner` compilados e
/// ids selecionados.
final class Versions {
  /// Cria o conjunto.
  const Versions({
    required this.headDir,
    required this.baseDir,
    required this.headExe,
    required this.baseExe,
    required this.headIds,
    required this.baseIds,
    required this.notes,
  });

  /// Checkout do head.
  final Directory headDir;

  /// Checkout da base.
  final Directory baseDir;

  /// `bench_runner` do head.
  final File headExe;

  /// `bench_runner` da base, ou `null` se a base não tem `benchmark/`.
  final File? baseExe;

  /// Ids medidos no head.
  final List<String> headIds;

  /// Ids da base; `null` se a base tem `bench_runner` sem `--list`; vazia se
  /// não tem `bench_runner`.
  final List<String>? baseIds;

  /// Observações para o relatório.
  final List<String> notes;

  /// Diretório de trabalho do head (o `bench_runner` acha o corpus daqui).
  Directory get headWorkDir => Directory('${headDir.path}/benchmark');

  /// Diretório de trabalho da base.
  Directory get baseWorkDir => Directory('${baseDir.path}/benchmark');

  /// Se o benchmark [id] deve ser medido na base (`baseIds == null` significa
  /// "tente": o código 64 do runner indica que não existe lá).
  bool baseMayHave(String id) =>
      baseExe != null && (baseIds == null || baseIds!.contains(id));

  /// Ids da união base ∪ head, ordenados.
  List<String> get allIds => {...headIds, ...?baseIds}.toList()..sort();
}

/// Diretório temporário e checkouts de uma execução de modo, com a limpeza.
///
/// Use [runSession], que cria a sessão, converte as falhas em código de saída
/// e limpa tudo no fim.
final class Session {
  Session._(this.workDir, this.log);

  /// Diretório temporário da execução.
  final Directory workDir;

  /// Destino das mensagens de progresso.
  final StringSink log;

  final List<Directory> _checkouts = [];
  Directory? _repo;

  /// Cria o checkout de [ref] em [workDir].
  Future<Directory> checkout(String ref) async {
    log.writeln('Preparando $ref…');
    final dir = await prepareCheckout(
      ref,
      workDir,
      repo: _repo ??= await repoRoot(),
    );
    _checkouts.add(dir);
    return dir;
  }

  /// Prepara [baseRef] e [headRef]: checkouts, compilação AOT dos
  /// `bench_runner` e seleção dos ids.
  ///
  /// Ids `harness/*` ficam fora; [only], se não vazio, restringe aos ids
  /// dados (que precisam existir no head). Base sem `benchmark/` não é erro:
  /// vira uma nota e todos os ids do head entram como `added`. Lança
  /// [BuildFailure] se o head não tem `bench_runner` ou `--list`.
  Future<Versions> prepare({
    required String baseRef,
    required String headRef,
    List<String> only = const [],
  }) async {
    final headDir = await checkout(headRef);
    if (!hasBenchRunner(headDir)) {
      throw BuildFailure('o head ($headRef) não tem $benchRunnerPath');
    }
    final baseDir = await checkout(baseRef);
    final notes = <String>[];

    log.writeln('Compilando o bench_runner do head…');
    final headExe = await compileRunner(
      checkout: headDir,
      outPath: '${workDir.path}/head-runner',
    );
    File? baseExe;
    if (hasBenchRunner(baseDir)) {
      log.writeln('Compilando o bench_runner da base…');
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
    final baseIds = baseExe == null
        ? const <String>[]
        : (await listBenches(baseExe))?.where(selected).toList();
    return Versions(
      headDir: headDir,
      baseDir: baseDir,
      headExe: headExe,
      baseExe: baseExe,
      headIds: headIds,
      baseIds: baseIds,
      notes: notes,
    );
  }

  Future<void> _dispose() async {
    for (final dir in _checkouts) {
      await removeCheckout(dir, repo: _repo);
    }
    try {
      await workDir.delete(recursive: true);
    } on FileSystemException {
      // Diretório temporário: o sistema limpa depois.
    }
  }
}

/// Executa [body] numa [Session] nova (diretório temporário com prefixo
/// [prefix]) e devolve o código de saída.
///
/// Falhas de preparação, medição, processo, arquivo e argumento viram uma
/// mensagem em [log] (sem stack trace) e [exitMeasurementFailure]. Os
/// checkouts e o diretório temporário são removidos sempre.
Future<int> runSession(
  String prefix,
  Future<int> Function(Session session) body, {
  StringSink? log,
}) async {
  final logSink = log ?? stderr;
  final session = Session._(
    await Directory.systemTemp.createTemp(prefix),
    logSink,
  );
  try {
    return await body(session);
  } on BuildFailure catch (e) {
    logSink.writeln('Falha na preparação: ${e.message}');
    return exitMeasurementFailure;
  } on MeasurementFailure catch (e) {
    logSink.writeln('Falha na medição: ${e.message}');
    return exitMeasurementFailure;
  } on ProcessException catch (e) {
    logSink.writeln(
      'Falha ao executar ${e.executable}: ${e.message} '
      '(está instalado e no PATH?)',
    );
    return exitMeasurementFailure;
  } on FileSystemException catch (e) {
    logSink.writeln(
      'Falha de arquivo: ${e.message}${e.path == null ? '' : ' (${e.path})'}'
      '${e.osError == null ? '' : ': ${e.osError!.message}'}',
    );
    return exitMeasurementFailure;
  } on ArgumentError catch (e) {
    // Parâmetros inválidos (ex.: iterações) viram mensagem, sem stack trace.
    logSink.writeln('Argumento inválido: ${e.message}');
    return exitMeasurementFailure;
  } finally {
    await session._dispose();
  }
}
