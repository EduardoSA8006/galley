import 'dart:io';

import 'package:args/args.dart';
import 'package:galley_benchmark/src/corpus/pg_wide.dart';
import 'package:galley_benchmark/src/modes/ab.dart';
import 'package:galley_benchmark/src/modes/compare.dart';
import 'package:galley_benchmark/src/modes/instructions.dart';
import 'package:galley_benchmark/src/modes/build.dart' show repoRoot;
import 'package:galley_benchmark/src/modes/local.dart';
import 'package:galley_benchmark/src/modes/size.dart';
import 'package:galley_benchmark/src/modes/wide.dart';

/// Orquestrador dos benchmarks: `dart run tool/bench.dart <modo> [opções]`.
///
/// Modos:
/// - `instructions`: gate de instruções entre `--base` e `--head` (refs git),
///   com `--counter valgrind|perf`, `--out` (BMF), `--report` (Markdown) e
///   `--bench` (repetível, restringe os ids) e `--threshold` (fração; padrão
///   0.005). Sai com 1 em regressão acima do limite (0,5% no PR; o noturno
///   usa `--base bench-baseline --threshold 0.10`) e com 2 se os checksums da base e do head divergirem.
/// - `ab`: comparação de tempo de parede entre `--base` e `--head`, em
///   `--rounds` rodadas intercaladas (padrão 15) e IC 95% bootstrap da razão
///   das medianas. Aceita `--out`, `--report` e `--bench`. Sai com 1 se o IC
///   de algum benchmark fica inteiro acima de +5%, com 2 se os checksums
///   divergem e com 70 em falha.
/// - `local`: mede o checkout atual na máquina do mantenedor (tempo absoluto,
///   RSS de pico e instruções nativas com `perf`) em livros sintéticos de 50 e
///   300 MiB, no corpus público e no privado (`GALLEY_PRIVATE_CORPUS`,
///   anonimizado). Aceita `--out`, `--report` e `--upload` (envia ao
///   Bencher; sem `BENCHER_API_TOKEN` pula com aviso). Sai com 70 se algum
///   livro falha.
/// - `compare`: Galley contra `epubx`, `epub_plus` e `epub_pro` (abrir, ler o
///   spine inteiro, ler um recurso do livro de 50 MiB e RSS de pico) nos
///   livros escritos à mão, no sintético de 50 MiB e no corpus público.
///   Aceita `--out`, `--report` e `--runs` (padrão 5). Não reprova antes da
///   1.0: falha de parser vira `falhou` na tabela; sai com 70 só se a
///   preparação falha.
///
/// - `size`: compila os apps de `benchmark/size/` (release, split por ABI,
///   arm64) com e sem o Galley e mede a diferença de bytes do APK. Aceita
///   `--out` (BMF). Sai com 1 se passar de 2 MiB e com 70 se a compilação
///   falha.
///
/// - `wide`: robustez no corpus amplo do Project Gutenberg
///   (`corpus/pg-wide.json`, 300 livros; cache em `.corpus-cache/pg-wide/`):
///   abre cada livro e lê todos os recursos do manifest, classificando em
///   `ok`, `diagnostics-error`, `failed`, `crashed`, `drift` e `unavailable`.
///   Aceita `--out` (BMF com `wide/<classe>`) e `--report`. Sai com 1
///   **só** se houver `crashed` (bug do Galley) e com 70 em falha de
///   preparação.
/// - `wide-refresh`: escolhe `--count` (300) livros do catálogo do PG com
///   `Random(--seed)` (2026), baixa e grava `corpus/pg-wide.json`. Só
///   manualmente; faz 1 requisição a cada 2 s ao espelho oficial.
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
      'threshold',
      defaultsTo: '$defaultThreshold',
      help:
          'Regressão que reprova, em fração (0,005 = 0,5%; o noturno usa '
          '0.10 contra a tag bench-baseline).',
    )
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
  final size = ArgParser()
    ..addOption('out', help: 'Arquivo BMF (JSON) de saída.');
  final wide = ArgParser()
    ..addOption('out', help: 'Arquivo BMF (JSON) de saída.')
    ..addOption('report', help: 'Relatório em texto (Markdown).');
  final wideRefresh = ArgParser()
    ..addOption('count', defaultsTo: '300', help: 'Livros a escolher.')
    ..addOption('seed', defaultsTo: '2026', help: 'Semente do sorteio.');
  final parser = ArgParser()
    ..addCommand('wide', wide)
    ..addCommand('wide-refresh', wideRefresh)
    ..addCommand('size', size)
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
        'informe o modo (instructions, ab, local, compare, size, wide ou wide-refresh)',
      );
    }
    if (command.name == 'wide') {
      final root = await repoRoot();
      code = await runWideMode(
        manifestPath: '${root.path}/corpus/pg-wide.json',
        cacheDir: Directory('${root.path}/.corpus-cache/pg-wide'),
        outPath: command.option('out'),
        reportPath: command.option('report'),
      );
    } else if (command.name == 'wide-refresh') {
      final count = int.parse(command.option('count')!);
      final seed = int.parse(command.option('seed')!);
      if (count < 1) throw const FormatException('count < 1');
      final root = await repoRoot();
      var refreshCode = 0;
      try {
        final entries = await refreshPgWide(
          count: count,
          seed: seed,
          cacheDir: Directory('${root.path}/.corpus-cache/pg-wide'),
          outPath: '${root.path}/corpus/pg-wide.json',
        );
        stderr.writeln('corpus/pg-wide.json: ${entries.length} livros');
      } on Object catch (e) {
        stderr.writeln('Falha no wide-refresh: $e');
        refreshCode = 70;
      }
      code = refreshCode;
    } else if (command.name == 'size') {
      code = await runSize(outPath: command.option('out'));
    } else if (command.name == 'compare') {
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
        threshold: parseThreshold(command.option('threshold')!),
        lowIterations: low,
        highIterations: high,
        timeout: Duration(minutes: minutes),
      );
    }
  } on FormatException catch (e) {
    await _invalidArgs(e.message, instructions, ab, local, compare, size, wide);
  } on ArgumentError catch (e) {
    // Opção obrigatória ausente ou valor fora da lista permitida.
    await _invalidArgs(
      '${e.message}',
      instructions,
      ab,
      local,
      compare,
      size,
      wide,
    );
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
  ArgParser e,
  ArgParser f,
) async {
  stderr.writeln(
    'Argumentos inválidos: $message\n'
    'Uso: dart run tool/bench.dart <instructions|ab|local|compare|size|wide|wide-refresh> [opções]\n'
    'instructions:\n${a.usage}\nab:\n${b.usage}\nlocal:\n${c.usage}\ncompare:\n${d.usage}\nsize:\n${e.usage}\nwide:\n${f.usage}',
  );
  await stderr.flush();
  exit(64);
}
