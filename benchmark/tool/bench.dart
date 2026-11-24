import 'dart:io';

import 'package:args/args.dart';
import 'package:galley_benchmark/src/modes/ab.dart';
import 'package:galley_benchmark/src/modes/instructions.dart';

/// Orquestrador dos benchmarks: `dart run tool/bench.dart <modo> [opções]`.
///
/// Modos:
/// - `instructions`: gate de instruções entre `--base` e `--head` (refs git),
///   com `--counter valgrind|perf`, `--out` (BMF), `--report` (Markdown) e
///   `--bench` (repetível, restringe os ids). Sai com 1 em regressão acima
///   de 0,5% e com 2 se os checksums da base e do head divergirem.
/// - `ab`: comparação de tempo de parede entre `--base` e `--head`, em
///   `--rounds` rodadas intercaladas (padrão 15) e IC 95% bootstrap da razão
///   das medianas. Aceita `--out`, `--report` e `--bench`. Sai com 1 se o IC
///   de algum benchmark fica inteiro acima de +5%, com 2 se os checksums
///   divergem e com 70 em falha.
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
    )
    ..addOption(
      'timeout-minutes',
      defaultsTo: '${defaultRunTimeout.inMinutes}',
      help: 'Tempo máximo de cada execução do bench_runner sob o contador.',
    );
  final ab = ArgParser()
    ..addOption('base', mandatory: true, help: 'Ref git da base.')
    ..addOption('head', mandatory: true, help: 'Ref git do head.')
    ..addOption(
      'rounds',
      defaultsTo: '$defaultRounds',
      help: 'Rodadas intercaladas por benchmark (≥ 3).',
    )
    ..addOption('out', help: 'Arquivo BMF (JSON) de saída.')
    ..addOption('report', help: 'Relatório em Markdown.')
    ..addMultiOption('bench', help: 'Restringe aos ids dados.')
    ..addOption(
      'timeout-minutes',
      defaultsTo: '${defaultAbTimeout.inMinutes}',
      help: 'Tempo máximo de cada execução do bench_runner.',
    );
  final parser = ArgParser()
    ..addCommand('instructions', instructions)
    ..addCommand('ab', ab);

  final int code;
  try {
    final parsed = parser.parse(args);
    final command = parsed.command;
    if (command == null) {
      throw const FormatException('informe o modo (instructions ou ab)');
    }
    if (command.name == 'ab') {
      final rounds = int.parse(command.option('rounds')!);
      final minutes = int.parse(command.option('timeout-minutes')!);
      if (rounds < 3) throw const FormatException('rounds < 3');
      if (minutes < 1) throw const FormatException('timeout-minutes < 1');
      code = await runAb(
        baseRef: command.option('base')!,
        headRef: command.option('head')!,
        rounds: rounds,
        outPath: command.option('out'),
        reportPath: command.option('report'),
        only: command.multiOption('bench'),
        timeout: Duration(minutes: minutes),
      );
    } else {
      final low = int.parse(command.option('low-iterations')!);
      final high = int.parse(command.option('high-iterations')!);
      final minutes = int.parse(command.option('timeout-minutes')!);
      if (minutes < 1) throw const FormatException('timeout-minutes < 1');
      if (low < 1 || high <= low) {
        throw const FormatException(
          'exige 1 ≤ low-iterations < high-iterations',
        );
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
        timeout: Duration(minutes: minutes),
      );
    }
  } on FormatException catch (e) {
    stderr.writeln(
      'Argumentos inválidos: ${e.message}\n'
      'Uso: dart run tool/bench.dart <instructions|ab> [opções]\n'
      'instructions:\n${instructions.usage}\nab:\n${ab.usage}',
    );
    await stderr.flush();
    exit(64);
  }
  await stdout.flush();
  await stderr.flush();
  exit(code);
}
