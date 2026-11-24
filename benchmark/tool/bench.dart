import 'dart:io';

import 'package:args/args.dart';
import 'package:galley_benchmark/src/modes/instructions.dart';

/// Orquestrador dos benchmarks: `dart run tool/bench.dart <modo> [opções]`.
///
/// Modos:
/// - `instructions`: gate de instruções entre `--base` e `--head` (refs git),
///   com `--counter valgrind|perf`, `--out` (BMF), `--report` (Markdown) e
///   `--bench` (repetível, restringe os ids). Sai com 1 em regressão acima
///   de 0,5% e com 2 se os checksums da base e do head divergirem.
///
/// Argumentos inválidos saem com 64.
Future<void> main(List<String> args) async {
  final instructions = ArgParser()
    ..addOption('base', mandatory: true, help: 'Ref git da base.')
    ..addOption('head', mandatory: true, help: 'Ref git do head.')
    ..addOption(
      'counter',
      allowed: ['valgrind', 'perf'],
      defaultsTo: 'valgrind',
      help: 'Contador de instruções.',
    )
    ..addOption('out', help: 'Arquivo BMF (JSON) de saída.')
    ..addOption('report', help: 'Relatório em Markdown.')
    ..addMultiOption('bench', help: 'Restringe aos ids dados.')
    ..addOption(
      'low-iterations',
      defaultsTo: '$defaultLowIterations',
      help: 'Iterações da execução curta (n1).',
    )
    ..addOption(
      'high-iterations',
      defaultsTo: '$defaultHighIterations',
      help: 'Iterações da execução longa (n2 > n1).',
    );
  final parser = ArgParser()..addCommand('instructions', instructions);

  final int code;
  try {
    final parsed = parser.parse(args);
    final command = parsed.command;
    if (command == null) {
      throw const FormatException('informe o modo (instructions)');
    }
    final low = int.parse(command.option('low-iterations')!);
    final high = int.parse(command.option('high-iterations')!);
    if (low < 1 || high <= low) {
      throw const FormatException('exige 1 ≤ low-iterations < high-iterations');
    }
    code = await runInstructions(
      baseRef: command.option('base')!,
      headRef: command.option('head')!,
      counter: Counter.values.byName(command.option('counter')!),
      outPath: command.option('out'),
      reportPath: command.option('report'),
      only: command.multiOption('bench'),
      lowIterations: low,
      highIterations: high,
    );
  } on FormatException catch (e) {
    stderr.writeln(
      'Argumentos inválidos: ${e.message}\n'
      'Uso: dart run tool/bench.dart instructions [opções]\n'
      '${instructions.usage}',
    );
    await stderr.flush();
    exit(64);
  }
  await stdout.flush();
  await stderr.flush();
  exit(code);
}
