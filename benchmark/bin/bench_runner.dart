import 'dart:io';

import 'package:args/args.dart';
import 'package:galley_benchmark/src/bench.dart';
import 'package:galley_benchmark/src/catalog.dart';
import 'package:galley_benchmark/src/runner.dart';

/// Executa um benchmark: `--bench <id> --iterations <n>`.
///
/// Imprime exatamente uma linha `checksum=<int>`. Id desconhecido ou
/// argumentos inválidos saem com código 64; exceção em `setUp`/`run` sai com
/// 70 (ver `runBench`).
Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('bench', mandatory: true, help: 'Id do benchmark.')
    ..addOption('iterations', defaultsTo: '1', help: 'Número de ciclos.');
  final ArgResults parsed;
  final int iterations;
  try {
    parsed = parser.parse(args);
    iterations = int.parse(parsed.option('iterations')!);
    if (iterations < 1) throw const FormatException('iterations < 1');
  } on FormatException catch (e) {
    stderr.writeln('Argumentos inválidos: ${e.message}\n${parser.usage}');
    exit(64);
  }
  final id = parsed.option('bench')!;
  final Bench bench;
  try {
    bench = Catalog.byId(id);
  } on ArgumentError {
    stderr.writeln('Benchmark desconhecido: $id');
    exit(64);
  }
  final code = await runBench(
    bench,
    iterations,
    stdoutSink: stdout,
    stderrSink: stderr,
  );
  await stdout.flush();
  exit(code);
}
