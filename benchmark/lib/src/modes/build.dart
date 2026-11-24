import 'dart:io';

/// Falha ao preparar ou compilar uma versão do repositório para medição.
final class BuildFailure implements Exception {
  /// Cria a falha com uma [message] legível.
  const BuildFailure(this.message);

  /// Descrição do que falhou, com a saída do comando quando houver.
  final String message;

  @override
  String toString() => 'BuildFailure: $message';
}

/// Caminho relativo do `bench_runner` dentro de um checkout do repositório.
const String benchRunnerPath = 'benchmark/bin/bench_runner.dart';

Future<ProcessResult> _run(
  String executable,
  List<String> args, {
  required String workingDirectory,
}) => Process.run(executable, args, workingDirectory: workingDirectory);

Never _fail(String what, ProcessResult r) => throw BuildFailure(
  '$what (código ${r.exitCode}):\n${r.stdout}\n${r.stderr}'.trimRight(),
);

/// Raiz do repositório git que contém [from] (por padrão, o diretório atual).
Future<Directory> repoRoot([Directory? from]) async {
  final dir = (from ?? Directory.current).path;
  final r = await _run('git', [
    'rev-parse',
    '--show-toplevel',
  ], workingDirectory: dir);
  if (r.exitCode != 0) _fail('$dir não está num repositório git', r);
  return Directory((r.stdout as String).trim());
}

/// Cria um `git worktree` destacado de [gitRef] dentro de [workDir].
///
/// [repo] é qualquer diretório do repositório (padrão: o diretório atual).
/// Se o checkout tiver `benchmark/pubspec.yaml`, roda `dart pub get` em
/// `benchmark/`. Em qualquer falha, o worktree parcial é removido antes de
/// lançar [BuildFailure]. Quem chama remove o checkout com [removeCheckout].
Future<Directory> prepareCheckout(
  String gitRef,
  Directory workDir, {
  Directory? repo,
}) async {
  final root = await repoRoot(repo);
  final rev = await _run('git', [
    'rev-parse',
    '--verify',
    '--quiet',
    '$gitRef^{commit}',
  ], workingDirectory: root.path);
  if (rev.exitCode != 0) _fail('ref git inválida: $gitRef', rev);
  final sha = (rev.stdout as String).trim();

  final checkout = await workDir.createTemp('checkout-');
  final add = await _run('git', [
    'worktree',
    'add',
    '--detach',
    checkout.path,
    sha,
  ], workingDirectory: root.path);
  if (add.exitCode != 0) {
    await removeCheckout(checkout, repo: root);
    _fail('git worktree add de $gitRef falhou', add);
  }

  try {
    final bench = Directory('${checkout.path}/benchmark');
    if (File('${bench.path}/pubspec.yaml').existsSync()) {
      final get = await _run(Platform.resolvedExecutable, [
        'pub',
        'get',
      ], workingDirectory: bench.path);
      if (get.exitCode != 0) _fail('dart pub get em $gitRef falhou', get);
    }
  } on Object {
    await removeCheckout(checkout, repo: root);
    rethrow;
  }
  return checkout;
}

/// Remove o worktree [checkout] criado por [prepareCheckout].
///
/// Nunca lança: usa `git worktree remove --force`, apaga o diretório se
/// sobrar e roda `git worktree prune` para limpar os metadados.
Future<void> removeCheckout(Directory checkout, {Directory? repo}) async {
  try {
    final root = (repo ?? await repoRoot()).path;
    await _run('git', [
      'worktree',
      'remove',
      '--force',
      checkout.path,
    ], workingDirectory: root);
    if (checkout.existsSync()) await checkout.delete(recursive: true);
    await _run('git', ['worktree', 'prune'], workingDirectory: root);
  } on Object catch (e) {
    stderr.writeln('Aviso: falha ao remover o checkout ${checkout.path}: $e');
  }
}

/// Se o [checkout] tem o `bench_runner` (refs antigas podem não ter).
bool hasBenchRunner(Directory checkout) =>
    File('${checkout.path}/$benchRunnerPath').existsSync();

/// Compila o `bench_runner` de [checkout] em AOT para [outPath].
///
/// Roda `dart compile exe` dentro de `benchmark/`, para usar a resolução de
/// pacotes do próprio checkout.
Future<File> compileRunner({
  required Directory checkout,
  required String outPath,
}) async {
  final r = await _run(Platform.resolvedExecutable, [
    'compile',
    'exe',
    'bin/bench_runner.dart',
    '-o',
    File(outPath).absolute.path,
  ], workingDirectory: '${checkout.path}/benchmark');
  if (r.exitCode != 0) _fail('dart compile exe em ${checkout.path} falhou', r);
  return File(outPath);
}
