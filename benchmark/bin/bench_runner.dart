import 'dart:io';

import 'package:args/args.dart';
import 'package:galley_benchmark/src/bench.dart';
import 'package:galley_benchmark/src/catalog.dart';
import 'package:galley_benchmark/src/runner.dart';

/// Executa um benchmark: `--bench <id> --iterations <n>`.
///
/// Imprime exatamente uma linha `checksum=<int>`. Com `--list`, imprime os
/// ids do catálogo, um por linha, e sai com 0. Id desconhecido ou argumentos
/// inválidos saem com código 64; exceção em `setUp`/`run` sai com 70 (ver
/// `runBench`).
Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addFlag('list', negatable: false, help: 'Lista os ids do catálogo.')
    ..addOption('bench', help: 'Id do benchmark.')
    ..addOption('iterations', defaultsTo: '1', help: 'Número de ciclos.');
  final ArgResults parsed;
  final int iterations;
  try {
    parsed = parser.parse(args);
    iterations = int.parse(parsed.option('iterations')!);
    if (iterations < 1) throw const FormatException('iterations < 1');
    if (!parsed.flag('list') && parsed.option('bench') == null) {
      throw const FormatException('--bench é obrigatório');
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
