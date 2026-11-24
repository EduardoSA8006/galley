import 'dart:convert';
import 'dart:io';

import '../bmf.dart' as bmf;
import '../corpus/fetcher.dart';
import '../corpus/handmade.dart';
import '../corpus/manifest.dart';
import '../corpus/synthetic.dart';
import 'ab.dart' show abEnvironment;
import 'build.dart';
import 'local.dart' show OpenMeasurement, parseMeasureOpen;
import 'orchestration.dart';
import 'stats.dart';

/// Execuções (cada uma num processo) por célula para a mediana do tempo.
const int defaultCompareRuns = 5;

/// Tempo máximo de cada execução de um parser.
const Duration defaultCompareTimeout = Duration(minutes: 5);

/// Recurso lido no `read-one` do livro sintético de 50 MiB: o capítulo do
/// meio (`ch100` de 200).
const String syntheticMiddleChapter = 'OEBPS/text/ch100.xhtml';

/// Métricas medidas, na ordem das colunas do relatório.
const List<String> compareMetrics = ['open', 'read-all', 'read-one'];

/// Parser a comparar: um executável que aceita
/// `<args> --measure <métrica> [--resource <caminho>] <livro>` e imprime
/// `ns=`, `rss=` e `checksum=`.
final class CompareAdapter {
  /// Cria o adaptador [name], medido por [exe] com [prefixArgs] antes dos
  /// argumentos da medida (ex.: `--adapter galley` no `bench_runner`).
  const CompareAdapter(this.name, this.exe, {this.prefixArgs = const []});

  /// Nome do parser (`galley`, `epub_plus`, `epub_pro`, `epubx`).
  final String name;

  /// Executável (AOT) que mede o parser.
  final File exe;

  /// Argumentos fixos antes dos da medida.
  final List<String> prefixArgs;
}

/// Livro a medir.
final class CompareBook {
  /// Cria o livro de [key] (id no BMF e no relatório) em [file].
  ///
  /// Com [readOneResource], mede também o `read-one` desse recurso (caminho
  /// completo no arquivo).
  const CompareBook(this.key, this.file, {this.readOneResource});

  /// Chave do livro: `hm/<nome>`, `synthetic/50mib` ou `public/<id>`.
  final String key;

  /// Arquivo EPUB.
  final File file;

  /// Recurso do `read-one`, se este livro o mede.
  final String? readOneResource;
}

/// Resultado de uma métrica de um adaptador num livro.
final class CompareCell {
  /// Cria a célula.
  const CompareCell({
    required this.adapter,
    required this.book,
    required this.metric,
    this.wallNs,
    this.peakRss,
    this.checksum,
    this.failure,
  });

  /// Nome do adaptador.
  final String adapter;

  /// Chave do livro.
  final String book;

  /// `open`, `read-all` ou `read-one`.
  final String metric;

  /// Mediana do tempo, em ns.
  final double? wallNs;

  /// Maior pico de RSS (`VmHWM`) entre as execuções, em bytes.
  final double? peakRss;

  /// Checksum (estável entre as execuções): itens do spine no `open`, bytes
  /// no `read-all` e no `read-one`.
  final int? checksum;

  /// Motivo da falha, se falhou.
  final String? failure;

  /// Se a medição funcionou.
  bool get ok => failure == null && wallNs != null;
}

Future<OpenMeasurement> _runOnce(
  CompareAdapter adapter,
  CompareBook book,
  String metric,
  Directory workDir,
  Duration timeout,
) async {
  final what = '${adapter.name} $metric ${book.key}';
  final r = await runWithTimeout(
    adapter.exe.path,
    [
      ...adapter.prefixArgs,
      '--measure',
      metric,
      if (metric == 'read-one') ...['--resource', book.readOneResource!],
      book.file.path,
    ],
    environment: abEnvironment(),
    includeParentEnvironment: false,
    workingDirectory: workDir.path,
    timeout: timeout,
    what: what,
  );
  if (r.exitCode != 0) {
    final lines = (r.stderr as String).trim().split('\n');
    throw MeasurementFailure(
      'saiu com código ${r.exitCode}: ${lines.first}',
      exitCode: r.exitCode,
    );
  }
  try {
    return parseMeasureOpen(r.stdout as String);
  } on FormatException catch (e) {
    throw MeasurementFailure(e.message);
  }
}

Future<CompareCell> _cell(
  CompareAdapter adapter,
  CompareBook book,
  String metric, {
  required int runs,
  required Duration timeout,
  required Directory workDir,
}) async {
  try {
    final samples = [
      for (var i = 0; i < runs; i++)
        await _runOnce(adapter, book, metric, workDir, timeout),
    ];
    final checksum = samples.first.checksum;
    if (samples.any((s) => s.checksum != checksum)) {
      throw const MeasurementFailure('checksum instável entre execuções');
    }
    return CompareCell(
      adapter: adapter.name,
      book: book.key,
      metric: metric,
      wallNs: median([for (final s in samples) s.ns.toDouble()]),
      peakRss: samples
          .map((s) => s.rss)
          .reduce((a, b) => a > b ? a : b)
          .toDouble(),
      checksum: checksum,
    );
  } on MeasurementFailure catch (e) {
    return CompareCell(
      adapter: adapter.name,
      book: book.key,
      metric: metric,
      failure: e.message,
    );
  }
}

/// Mede cada [adapters] × [books] × métricas, cada execução num processo
/// próprio com a VM de produção, e devolve as células.
///
/// `open` e `read-all` valem para todo livro; `read-one`, só para o que
/// define [CompareBook.readOneResource]. Uma falha vira uma célula com
/// [CompareCell.failure] e não aborta nada; se o `open` de um adaptador
/// falha num livro, as demais métricas dele nesse livro herdam a falha sem
/// rodar. Progresso em [log].
Future<List<CompareCell>> compareBooks({
  required List<CompareAdapter> adapters,
  required List<CompareBook> books,
  required int runs,
  required Duration timeout,
  required Directory workDir,
  required StringSink log,
}) async {
  final cells = <CompareCell>[];
  for (final book in books) {
    for (final adapter in adapters) {
      log.writeln('medindo ${adapter.name} em ${book.key}');
      String? openFailure;
      for (final metric in compareMetrics) {
        if (metric == 'read-one' && book.readOneResource == null) continue;
        final cell = openFailure != null
            ? CompareCell(
                adapter: adapter.name,
                book: book.key,
                metric: metric,
                failure: openFailure,
              )
            : await _cell(
                adapter,
                book,
                metric,
                runs: runs,
                timeout: timeout,
                workDir: workDir,
              );
        if (metric == 'open' && !cell.ok) openFailure = cell.failure;
        if (!cell.ok) {
          log.writeln(
            'Falha: ${adapter.name} $metric ${book.key}: ${cell.failure}',
          );
        }
        cells.add(cell);
      }
    }
  }
  return cells;
}

String _ms(double ns) => (ns / 1e6).toStringAsFixed(2);

String _mib(double bytes) => (bytes / 1048576).toStringAsFixed(1);

/// BMF das células com sucesso: `compare/<adaptador>/<métrica>/<livro>` com
/// `wall-time-ns` e `peak-rss-bytes`.
Map<String, Object> compareBmf(List<CompareCell> cells) => bmf.toBmf({
  for (final c in cells.where((c) => c.ok))
    'compare/${c.adapter}/${c.metric}/${c.book}': [
      bmf.Measure(slug: bmf.MeasureSlug.wallTimeNs, value: c.wallNs!),
      bmf.Measure(slug: bmf.MeasureSlug.peakRssBytes, value: c.peakRss!),
    ],
});

/// Relatório em Markdown: uma tabela livro × adaptador por métrica
/// (`open` e `read-all` em ms, RSS de pico do `read-all` em MiB, `read-one`
/// em ms), as divergências de bytes entre adaptadores e as falhas.
///
/// [elapsed] é o tempo total do modo; [notes] vira citações no topo.
String renderCompareReport(
  List<CompareCell> cells, {
  required List<String> adapterNames,
  required int runs,
  required Duration elapsed,
  List<String> notes = const [],
}) {
  final books = <String>[];
  for (final c in cells) {
    if (!books.contains(c.book)) books.add(c.book);
  }
  CompareCell? find(String book, String adapter, String metric) {
    for (final c in cells) {
      if (c.book == book && c.adapter == adapter && c.metric == metric) {
        return c;
      }
    }
    return null;
  }

  final b = StringBuffer()
    ..writeln('# Comparação com outros parsers')
    ..writeln()
    ..writeln(
      'Cada medida roda num processo próprio, com a VM de produção; tempo = '
      'mediana de $runs execuções, RSS = maior pico (`VmHWM`). `open` mede '
      'só a abertura; `read-all` e `read-one` medem do arquivo até os bytes '
      '(abertura inclusa). Os concorrentes usam `EpubReader.readBook`, que lê '
      'o livro inteiro; o Galley abre o contêiner e lê os recursos sob '
      'demanda. Tempo total desta execução: ${elapsed.inSeconds} s.',
    )
    ..writeln();
  for (final n in notes) {
    b.writeln('> $n');
  }
  if (notes.isNotEmpty) b.writeln();

  void table(
    String title,
    String metric,
    String Function(CompareCell) value, {
    bool Function(String book)? only,
  }) {
    final rows = books.where((k) => only?.call(k) ?? true).where((k) {
      return adapterNames.any((a) => find(k, a, metric) != null);
    }).toList();
    if (rows.isEmpty) return;
    b
      ..writeln('## $title')
      ..writeln()
      ..writeln('| livro | ${adapterNames.join(' | ')} |')
      ..writeln('|---|${'---:|' * adapterNames.length}');
    for (final k in rows) {
      final row = [
        for (final a in adapterNames)
          switch (find(k, a, metric)) {
            null => '—',
            final c when c.ok => value(c),
            _ => 'falhou',
          },
      ];
      b.writeln('| `$k` | ${row.join(' | ')} |');
    }
    b.writeln();
  }

  table('Abrir (ms)', 'open', (c) => _ms(c.wallNs!));
  table('Ler o spine inteiro (ms)', 'read-all', (c) => _ms(c.wallNs!));
  table('RSS de pico do `read-all` (MiB)', 'read-all', (c) => _mib(c.peakRss!));
  table('Ler um recurso, capítulo do meio (ms)', 'read-one', (c) {
    return _ms(c.wallNs!);
  });
  table('RSS de pico do `read-one` (MiB)', 'read-one', (c) => _mib(c.peakRss!));

  final divergent = [
    for (final k in books)
      if ({
            for (final c in cells)
              if (c.book == k && c.metric == 'read-all' && c.ok) c.checksum,
          }.length >
          1)
        k,
  ];
  if (divergent.isNotEmpty) {
    b
      ..writeln('## Divergência de bytes do spine')
      ..writeln()
      ..writeln(
        'Os adaptadores somaram bytes diferentes (um parser normaliza o '
        'texto); soma por adaptador:',
      )
      ..writeln();
    for (final k in divergent) {
      final sums = [
        for (final c in cells)
          if (c.book == k && c.metric == 'read-all' && c.ok)
            '${c.adapter}=${c.checksum}',
      ];
      b.writeln('- `$k`: ${sums.join(', ')}');
    }
    b.writeln();
  }

  final failed = cells.where((c) => !c.ok).toList();
  if (failed.isNotEmpty) {
    b
      ..writeln('## Falhas')
      ..writeln();
    for (final c in failed) {
      b.writeln('- `${c.adapter}` `${c.metric}` `${c.book}`: ${c.failure}');
    }
  }
  return b.toString();
}

/// Executa o modo `compare`: Galley contra `epubx`, `epub_plus` e `epub_pro`
/// nos livros do corpus escrito à mão, no sintético de 50 MiB e no corpus
/// público (cache em `.corpus-cache/`).
///
/// Compila o `bench_runner` do checkout (Galley, `epub_plus`, `epub_pro`) e o
/// executável do `epubx` (pacote satélite `competitors/epubx_runner`, por
/// conflito de dependências). Escreve o BMF em [outPath] e o relatório em
/// [reportPath]; [echoReport] também imprime o relatório. Não reprova antes
/// da 1.0: falhas de parser viram `falhou` na tabela e o código é 0; só falha
/// de preparação (compilação, corpus ausente) devolve
/// [exitMeasurementFailure].
Future<int> runCompare({
  String? outPath,
  String? reportPath,
  int runs = defaultCompareRuns,
  Duration timeout = defaultCompareTimeout,
  bool includePublic = true,
  StringSink? log,
  bool echoReport = true,
}) {
  final logSink = log ?? stderr;
  return runSession('galley-compare-', log: logSink, (session) async {
    if (runs < 1) throw ArgumentError('runs deve ser ≥ 1');
    final clock = Stopwatch()..start();
    final root = await repoRoot();
    final workDir = Directory('${root.path}/benchmark');
    final notes = <String>[];

    logSink.writeln('Compilando o bench_runner do checkout atual…');
    final runner = await compileRunner(
      checkout: root,
      outPath: '${session.workDir.path}/runner',
    );
    logSink.writeln('Compilando o runner do epubx…');
    final satellite = Directory('${workDir.path}/competitors/epubx_runner');
    final get = await Process.run(Platform.resolvedExecutable, [
      'pub',
      'get',
    ], workingDirectory: satellite.path);
    if (get.exitCode != 0) {
      throw BuildFailure('dart pub get em ${satellite.path} falhou');
    }
    final epubx = await compileEpubxRunner(
      satelliteDir: satellite,
      outPath: '${session.workDir.path}/epubx-runner',
    );
    final adapters = [
      for (final name in ['galley', 'epub_plus', 'epub_pro'])
        CompareAdapter(name, runner, prefixArgs: ['--adapter', name]),
      CompareAdapter('epubx', epubx),
    ];

    final books = <CompareBook>[];
    final handmade = await buildHandmadeCorpus();
    for (final entry in handmade.entries) {
      final file = File(
        '${session.workDir.path}/${entry.key.replaceAll('/', '-')}.epub',
      )..writeAsBytesSync(entry.value);
      books.add(CompareBook(entry.key, file));
    }
    books.add(
      CompareBook(
        'synthetic/50mib',
        await writeSyntheticBook(
          '${session.workDir.path}/synthetic-50mib.epub',
          targetBytes: kSynthetic50MiB,
        ),
        readOneResource: syntheticMiddleChapter,
      ),
    );
    if (includePublic) {
      final fetcher = CorpusFetcher(
        cacheDir: Directory('${root.path}/.corpus-cache'),
      );
      for (final entry in loadManifest('${root.path}/corpus/manifest.json')) {
        try {
          books.add(
            CompareBook('public/${entry.id}', await fetcher.fetch(entry)),
          );
        } on CorpusFetchException catch (e) {
          logSink.writeln('Sem ${entry.id}: $e');
          notes.add('`public/${entry.id}` não baixou e ficou fora.');
        }
      }
    }

    final cells = await compareBooks(
      adapters: adapters,
      books: books,
      runs: runs,
      timeout: timeout,
      workDir: workDir,
      log: logSink,
    );
    clock.stop();
    final report = renderCompareReport(
      cells,
      adapterNames: [for (final a in adapters) a.name],
      runs: runs,
      elapsed: clock.elapsed,
      notes: notes,
    );
    if (outPath != null) {
      await File(outPath).writeAsString(
        const JsonEncoder.withIndent('  ').convert(compareBmf(cells)),
      );
    }
    if (reportPath != null) await File(reportPath).writeAsString(report);
    if (echoReport) stdout.write(report);
    return 0;
  });
}
