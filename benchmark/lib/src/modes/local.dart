import 'dart:convert';
import 'dart:io';

import '../bencher.dart';
import '../bmf.dart' as bmf;
import '../corpus/fetcher.dart';
import '../corpus/manifest.dart';
import '../corpus/private_corpus.dart';
import '../corpus/synthetic.dart';
import 'ab.dart' show abEnvironment;
import 'build.dart';
import 'instructions.dart';
import 'orchestration.dart';
import 'stats.dart';

/// Execuções (cada uma num processo) por livro para a mediana do tempo.
const int defaultLocalRuns = 9;

/// Testbed do Bencher para as medições da máquina do mantenedor.
const String localTestbed = 'local-dev';

/// Tempo máximo de cada execução do `bench_runner --measure-open`.
const Duration defaultLocalTimeout = Duration(minutes: 10);

final RegExp _nsPattern = RegExp(r'^ns=(\d+)\s*$', multiLine: true);
final RegExp _rssPattern = RegExp(r'^rss=(\d+)\s*$', multiLine: true);

/// Saída de `bench_runner --measure-open`.
typedef OpenMeasurement = ({int ns, int rss, int checksum});

/// Lê `ns=`, `rss=` e `checksum=` da saída de `--measure-open`.
///
/// Lança [FormatException] se alguma linha faltar.
OpenMeasurement parseMeasureOpen(String stdoutText) {
  final ns = _nsPattern.firstMatch(stdoutText);
  final rss = _rssPattern.firstMatch(stdoutText);
  final sum = checksumPattern.firstMatch(stdoutText);
  if (ns == null || rss == null || sum == null) {
    throw const FormatException('saída sem ns=, rss= ou checksum=');
  }
  return (
    ns: int.parse(ns[1]!),
    rss: int.parse(rss[1]!),
    checksum: int.parse(sum[1]!),
  );
}

/// Resultado de um livro: tempo absoluto, pico de memória e instruções.
final class LocalResult {
  /// Cria o resultado de [key] (a chave no BMF e no relatório).
  const LocalResult({
    required this.key,
    this.wallNs,
    this.peakRss,
    this.instructions,
    this.failure,
  });

  /// Chave no BMF: `synthetic/50mib`, `public/<id>` ou `private/<id anônimo>`.
  final String key;

  /// Mediana do tempo de abertura + leitura do spine, em ns.
  final double? wallNs;

  /// Maior pico de RSS (`VmHWM`) entre as execuções, em bytes.
  final double? peakRss;

  /// Instruções (`instructions:u`) de uma execução sob `perf`.
  final int? instructions;

  /// Motivo da falha (já sem nomes nem caminhos privados), se falhou.
  final String? failure;

  /// Se a medição de tempo e memória funcionou.
  bool get ok => failure == null && wallNs != null;
}

class _Book {
  _Book(this.key, this.file, {this.scrub = _identity});

  final String key;
  final File file;
  final String Function(String) scrub;
}

String _identity(String s) => s;

/// Função que troca nome, caminho e diretório de [files] (e de [root]) por
/// `<privado>` em qualquer texto.
String Function(String) privateScrubber(List<File> files, {String? root}) {
  final needles = <String>{
    ?root,
    for (final f in files) ...[
      f.path,
      f.parent.path,
      f.uri.pathSegments.last,
      Uri.decodeComponent(f.uri.pathSegments.last),
      Uri.encodeFull(f.path),
      Uri.encodeComponent(f.uri.pathSegments.last),
      if (f.uri.pathSegments.last.contains('.'))
        Uri.decodeComponent(f.uri.pathSegments.last)
            .replaceFirst(RegExp(r'\.[^.]*$'), ''),
    ],
  }.where((n) => n.isNotEmpty).toList()..sort((a, b) => b.length - a.length);
  return (text) {
    var out = text;
    for (final n in needles) {
      out = out.replaceAll(n, '<privado>');
    }
    return out;
  };
}

Future<OpenMeasurement> _openOnce(
  File exe,
  _Book book,
  Directory workDir,
  Duration timeout,
) async {
  final r = await runWithTimeout(
    exe.path,
    ['--measure-open', book.file.path],
    environment: abEnvironment(),
    includeParentEnvironment: false,
    workingDirectory: workDir.path,
    timeout: timeout,
    what: book.key,
  );
  if (r.exitCode != 0) {
    throw MeasurementFailure(
      book
          .scrub('${book.key} saiu com código ${r.exitCode}:\n${r.stderr}')
          .trimRight(),
      exitCode: r.exitCode,
    );
  }
  try {
    return parseMeasureOpen(r.stdout as String);
  } on FormatException catch (e) {
    throw MeasurementFailure('${book.key}: ${e.message}');
  }
}

Future<LocalResult> _measure(
  File exe,
  _Book book, {
  required Directory workDir,
  required int runs,
  required Duration timeout,
  required List<String> notes,
  required bool Function() perfAvailable,
  required void Function() markPerfUnavailable,
}) async {
  try {
    final samples = <OpenMeasurement>[
      for (var i = 0; i < runs; i++)
        await _openOnce(exe, book, workDir, timeout),
    ];
    final checksum = samples.first.checksum;
    if (samples.any((s) => s.checksum != checksum)) {
      throw MeasurementFailure(
        '${book.key}: checksum instável entre execuções',
      );
    }
    int? instructions;
    if (perfAvailable()) {
      try {
        final counted = await runCounted(
          exe,
          book.key,
          1,
          Counter.perf,
          workingDirectory: workDir,
          timeout: timeout,
          runnerArgs: ['--measure-open', book.file.path],
        );
        if (counted.checksum != checksum) {
          throw MeasurementFailure(
            '${book.key}: checksum sob perf difere do medido',
          );
        }
        instructions = counted.instructions;
      } on CounterUnavailable catch (e) {
        markPerfUnavailable();
        notes.add('Instruções não medidas: ${e.message}');
      } on MeasurementFailure catch (e) {
        throw MeasurementFailure(book.scrub(e.message), exitCode: e.exitCode);
      }
    }
    return LocalResult(
      key: book.key,
      wallNs: median([for (final s in samples) s.ns.toDouble()]),
      peakRss: samples
          .map((s) => s.rss)
          .reduce((a, b) => a > b ? a : b)
          .toDouble(),
      instructions: instructions,
    );
  } on MeasurementFailure catch (e) {
    return LocalResult(key: book.key, failure: book.scrub(e.message));
  }
}

String _mib(double bytes) => (bytes / 1048576).toStringAsFixed(1);

String _ms(double ns) => (ns / 1e6).toStringAsFixed(2);

String _row(LocalResult r) => r.ok
    ? '| `${r.key}` | ${_ms(r.wallNs!)} | ${_mib(r.peakRss!)} | '
          '${r.instructions ?? '—'} |'
    : '| `${r.key}` | falhou | — | — |';

/// Agregado dos livros privados medidos com sucesso (`private/aggregate`):
/// mediana e p95 do tempo de abertura e maior RSS. `null` se não houver.
LocalResult? privateAggregate(List<LocalResult> results) {
  final ok = results.where((r) => r.ok).toList();
  if (ok.isEmpty) return null;
  return LocalResult(
    key: 'private/aggregate',
    wallNs: median([for (final r in ok) r.wallNs!]),
    peakRss: ok.map((r) => r.peakRss!).reduce((a, b) => a > b ? a : b),
  );
}

/// BMF dos resultados. O agregado privado leva o p95 em `upper_value`.
Map<String, Object> localBmf(List<LocalResult> results) {
  final byBench = <String, List<bmf.Measure>>{};
  for (final r in results.where((r) => r.ok)) {
    byBench[r.key] = [
      bmf.Measure(slug: bmf.MeasureSlug.wallTimeNs, value: r.wallNs!),
      bmf.Measure(slug: bmf.MeasureSlug.peakRssBytes, value: r.peakRss!),
      if (r.instructions != null)
        bmf.Measure(
          slug: bmf.MeasureSlug.instructions,
          value: r.instructions!.toDouble(),
        ),
    ];
  }
  final priv = results
      .where((r) => r.key.startsWith('private/') && r.ok)
      .toList();
  final agg = privateAggregate(priv);
  if (agg != null) {
    byBench[agg.key] = [
      bmf.Measure(
        slug: bmf.MeasureSlug.wallTimeNs,
        value: agg.wallNs!,
        upper: percentile([for (final r in priv) r.wallNs!], 0.95),
      ),
      bmf.Measure(slug: bmf.MeasureSlug.peakRssBytes, value: agg.peakRss!),
    ];
  }
  return bmf.toBmf(byBench);
}

/// Relatório em Markdown. Livros privados só aparecem pelo id anônimo.
String renderLocalReport(
  List<LocalResult> results, {
  required int runs,
  List<String> notes = const [],
}) {
  final b = StringBuffer()
    ..writeln('# Benchmark local')
    ..writeln()
    ..writeln(
      'Abertura + leitura do spine (`EpubBook.open`), mediana de $runs '
      'execuções em processos separados com a VM de produção; RSS = maior '
      'pico; instruções = uma execução sob `perf` (`instructions:u`, VM '
      'determinística, processo inteiro).',
    )
    ..writeln();
  for (final n in notes) {
    b.writeln('> $n');
  }
  if (notes.isNotEmpty) b.writeln();
  void table(String title, List<LocalResult> rows) {
    b
      ..writeln('## $title')
      ..writeln()
      ..writeln('| livro | abertura (ms) | RSS pico (MiB) | instruções |')
      ..writeln('|---|---:|---:|---:|');
    for (final r in rows) {
      b.writeln(_row(r));
    }
    b.writeln();
  }

  final open = results.where((r) => !r.key.startsWith('private/')).toList();
  table('Sintéticos e corpus público', open);
  final priv = results.where((r) => r.key.startsWith('private/')).toList();
  if (priv.isNotEmpty) {
    final agg = privateAggregate(priv);
    final ok = priv.where((r) => r.ok).toList();
    table('Corpus privado (${priv.length} livros, só ids anônimos)', priv);
    if (agg != null) {
      b
        ..writeln(
          '**Agregado:** abertura mediana ${_ms(agg.wallNs!)} ms, '
          'p95 ${_ms(percentile([for (final r in ok) r.wallNs!], 0.95))} ms, '
          'RSS máximo ${_mib(agg.peakRss!)} MiB.',
        )
        ..writeln();
    }
  }
  final failed = results.where((r) => !r.ok).toList();
  if (failed.isNotEmpty) {
    b
      ..writeln('## Falhas')
      ..writeln();
    for (final r in failed) {
      b.writeln('- `${r.key}`: ${r.failure?.split('\n').first}');
    }
  }
  return b.toString();
}

/// Executa o modo `local`: mede o checkout ATUAL (sem base/head) na máquina
/// do mantenedor.
///
/// Compila o `bench_runner` do checkout (ou usa [runnerExe]) e mede, cada
/// livro em processos próprios, tempo absoluto (mediana de [runs]), pico de
/// RSS e instruções nativas com `perf`. Cobre livros sintéticos de
/// [syntheticSizes] bytes (gerados num diretório temporário, apagado no
/// fim), o corpus público ([includePublic], com cache em `.corpus-cache/`) e
/// o privado de `GALLEY_PRIVATE_CORPUS` em [environment], que só aparece
/// anonimizado. Escreve o BMF em [outPath] e o relatório em [reportPath];
/// [echoReport] também imprime o relatório. Com [upload], e sem falhas,
/// chama [bencherRun] (stub até a Task 10). Devolve 0, ou
/// [exitMeasurementFailure] se algum livro falhou (os arquivos saem assim
/// mesmo).
Future<int> runLocal({
  String? outPath,
  String? reportPath,
  bool upload = false,
  int runs = defaultLocalRuns,
  Duration timeout = defaultLocalTimeout,
  List<int> syntheticSizes = const [kSynthetic50MiB, kSynthetic300MiB],
  bool includePublic = true,
  File? runnerExe,
  Map<String, String>? environment,
  StringSink? log,
  bool echoReport = true,
}) {
  final logSink = log ?? stderr;
  return runSession('galley-local-', log: logSink, (session) async {
    if (runs < 1) throw ArgumentError('runs deve ser ≥ 1');
    final root = await repoRoot();
    final workDir = Directory('${root.path}/benchmark');
    final notes = <String>[];
    final exe =
        runnerExe ??
        await () async {
          logSink.writeln('Compilando o bench_runner do checkout atual…');
          return compileRunner(
            checkout: root,
            outPath: '${session.workDir.path}/runner',
          );
        }();

    final privateFiles = await listPrivateCorpus(
      environment: environment,
      onWarning: notes.add,
    );
    final privateRoot =
        (environment ?? Platform.environment)[privateCorpusVariable];
    final scrub = privateScrubber(privateFiles, root: privateRoot);

    var perf = true;
    final results = <LocalResult>[];
    Future<void> measure(_Book book) async {
      logSink.writeln('medindo ${book.key}');
      final r = await _measure(
        exe,
        book,
        workDir: workDir,
        runs: runs,
        timeout: timeout,
        notes: notes,
        perfAvailable: () => perf,
        markPerfUnavailable: () => perf = false,
      );
      if (!r.ok) logSink.writeln('Falha em ${book.key}: ${r.failure}');
      results.add(r);
    }

    for (final size in syntheticSizes) {
      final key = 'synthetic/${size ~/ 1048576}mib';
      final file = await writeSyntheticBook(
        '${session.workDir.path}/synthetic-$size.epub',
        targetBytes: size,
      );
      try {
        await measure(_Book(key, file));
      } finally {
        await file.delete();
      }
    }

    if (includePublic) {
      final fetcher = CorpusFetcher(
        cacheDir: Directory('${root.path}/.corpus-cache'),
      );
      for (final entry in loadManifest('${root.path}/corpus/manifest.json')) {
        final File file;
        try {
          file = await fetcher.fetch(entry);
        } on CorpusFetchException catch (e) {
          logSink.writeln('Sem ${entry.id}: $e');
          results.add(
            LocalResult(key: 'public/${entry.id}', failure: 'download falhou'),
          );
          continue;
        }
        await measure(_Book('public/${entry.id}', file));
      }
    }

    for (final file in privateFiles) {
      await measure(_Book('private/${anonymousId(file)}', file, scrub: scrub));
    }

    final report = renderLocalReport(results, runs: runs, notes: notes);
    if (outPath != null) {
      await File(outPath).writeAsString(
        const JsonEncoder.withIndent('  ').convert(localBmf(results)),
      );
    }
    if (reportPath != null) await File(reportPath).writeAsString(report);
    if (echoReport) stdout.write(report);

    final failed = results.any((r) => !r.ok);
    if (upload && !failed && outPath != null) {
      return bencherRun(bmfPath: outPath, testbed: localTestbed, log: logSink);
    }
    if (upload && outPath == null) {
      logSink.writeln('--upload exige --out');
      return exitMeasurementFailure;
    }
    return failed ? exitMeasurementFailure : 0;
  });
}
