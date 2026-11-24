import 'dart:io';

import 'package:args/args.dart';
import 'package:galley_benchmark/src/bench.dart';
import 'package:galley_benchmark/src/catalog.dart';
import 'package:galley_benchmark/src/runner.dart';

/// Executa um benchmark: `--bench <id> --iterations <n>`.
///
/// Com `--measure-open <caminho>`, abre o EPUB, lê o spine e imprime `ns=`,
/// `rss=` (`VmHWM`, ver `peakRssBytes`) e `checksum=` (ver `measureOpen`).
///
/// Imprime a linha `checksum=<int>`; com `--timing`, imprime antes a linha
/// `ns=<int>` (tempo de relógio das iterações 2 a n, sem `setUp`). Com `--list`, imprime os
/// ids do catálogo, um por linha, e sai com 0. Id desconhecido ou argumentos
/// inválidos saem com código 64; exceção em `setUp`/`run` sai com 70 (ver
/// `runBench`).
Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addFlag('list', negatable: false, help: 'Lista os ids do catálogo.')
    ..addOption('bench', help: 'Id do benchmark.')
    ..addOption(
      'measure-open',
      help:
          'Abre o EPUB do caminho, lê o spine e imprime ns=, rss= e checksum=.',
    )
    ..addFlag(
      'timing',
      negatable: false,
      help: 'Imprime ns=<tempo das iterações 2..n> (exige --iterations ≥ 2).',
    )
    ..addOption('iterations', defaultsTo: '1', help: 'Número de ciclos.');
  final ArgResults parsed;
  final int iterations;
  try {
    parsed = parser.parse(args);
    iterations = int.parse(parsed.option('iterations')!);
    if (iterations < 1) throw const FormatException('iterations < 1');
    if (parsed.flag('timing') && iterations < 2) {
      throw const FormatException('--timing exige --iterations ≥ 2');
    }
    if (!parsed.flag('list') &&
        parsed.option('bench') == null &&
        parsed.option('measure-open') == null) {
      throw const FormatException('--bench ou --measure-open é obrigatório');
    }
  } on FormatException catch (e) {
    stderr.writeln('Argumentos inválidos: ${e.message}\n${parser.usage}');
    await _exit(64);
  }
  if (parsed.flag('list')) {
    for (final bench in Catalog.all()) {
      stdout.writeln(bench.id);
    }
    await _exit(0);
  }
  final openPath = parsed.option('measure-open');
  if (openPath != null) {
    await _exit(
      await measureOpen(openPath, stdoutSink: stdout, stderrSink: stderr),
    );
  }
  final id = parsed.option('bench')!;
  final Bench bench;
  try {
    bench = Catalog.byId(id);
  } on ArgumentError {
    stderr.writeln('Benchmark desconhecido: $id');
    await _exit(64);
  }
  final code = await runBench(
    bench,
    iterations,
    stdoutSink: stdout,
    stderrSink: stderr,
    timing: parsed.flag('timing'),
  );
  await _exit(code);
}

/// Esvazia stdout e stderr antes de sair, para não perder mensagens quando a
/// saída vai para um pipe.
Future<Never> _exit(int code) async {
  await stdout.flush();
  await stderr.flush();
  exit(code);
}
