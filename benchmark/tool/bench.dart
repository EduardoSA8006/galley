import 'dart:io';

import 'package:args/args.dart';
import 'package:galley_benchmark/src/modes/ab.dart';
import 'package:galley_benchmark/src/modes/compare.dart';
import 'package:galley_benchmark/src/modes/instructions.dart';
import 'package:galley_benchmark/src/modes/local.dart';

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
/// - `local`: mede o checkout atual na máquina do mantenedor (tempo absoluto,
///   RSS de pico e instruções nativas com `perf`) em livros sintéticos de 50 e
///   300 MiB, no corpus público e no privado (`GALLEY_PRIVATE_CORPUS`,
///   anonimizado). Aceita `--out`, `--report` e `--upload` (stub até a
///   Task 10). Sai com 70 se algum livro falha.
/// - `compare`: Galley contra `epubx`, `epub_plus` e `epub_pro` (abrir, ler o
///   spine inteiro, ler um recurso do livro de 50 MiB e RSS de pico) nos
///   livros escritos à mão, no sintético de 50 MiB e no corpus público.
///   Aceita `--out`, `--report` e `--runs` (padrão 5). Não reprova antes da
///   1.0: falha de parser vira `falhou` na tabela; sai com 70 só se a
///   preparação falha.
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
  final local = ArgParser()
    ..addOption('out', help: 'Arquivo BMF (JSON) de saída.')
    ..addOption('report', help: 'Relatório em Markdown.')
    ..addFlag(
      'upload',
      negatable: false,
      help: 'Envia o BMF ao Bencher (testbed local-dev).',
    );
  final compare = ArgParser()
    ..addOption('out', help: 'Arquivo BMF (JSON) de saída.')
    ..addOption('report', help: 'Relatório em Markdown.')
    ..addOption(
      'runs',
      defaultsTo: '$defaultCompareRuns',
      help: 'Execuções (processos) por célula para a mediana do tempo.',
    );
  final parser = ArgParser()
    ..addCommand('compare', compare)
    ..addCommand('local', local)
    ..addCommand('instructions', instructions)
    ..addCommand('ab', ab);

  final int code;
  try {
    final parsed = parser.parse(args);
    final command = parsed.command;
    if (command == null) {
      throw const FormatException(
        'informe o modo (instructions, ab, local ou compare)',
      );
    }
    if (command.name == 'compare') {
      final runs = int.parse(command.option('runs')!);
      if (runs < 1) throw const FormatException('runs < 1');
      code = await runCompare(
        outPath: command.option('out'),
        reportPath: command.option('report'),
        runs: runs,
      );
    } else if (command.name == 'local') {
      code = await runLocal(
        outPath: command.option('out'),
        reportPath: command.option('report'),
        upload: command.flag('upload'),
      );
    } else if (command.name == 'ab') {
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
    await _invalidArgs(e.message, instructions, ab, local, compare);
  } on ArgumentError catch (e) {
    // Opção obrigatória ausente ou valor fora da lista permitida.
    await _invalidArgs('${e.message}', instructions, ab, local, compare);
  }
  await stdout.flush();
  await stderr.flush();
  exit(code);
}

/// Escreve o erro de argumentos e o uso no stderr e sai com 64.
Future<Never> _invalidArgs(
  String message,
  ArgParser a,
  ArgParser b,
  ArgParser c,
  ArgParser d,
) async {
  stderr.writeln(
    'Argumentos inválidos: $message\n'
    'Uso: dart run tool/bench.dart <instructions|ab|local|compare> [opções]\n'
    'instructions:\n${a.usage}\nab:\n${b.usage}\nlocal:\n${c.usage}\ncompare:\n${d.usage}',
  );
  await stderr.flush();
  exit(64);
}
