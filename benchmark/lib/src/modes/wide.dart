import 'dart:convert';
import 'dart:io';

import 'package:galley/galley.dart';

import '../bmf.dart' as bmf;
import '../corpus/fetcher.dart';
import '../corpus/manifest.dart';
import '../corpus/pg_wide.dart';

/// Classe de resultado de um livro do corpus amplo.
enum WideClass {
  /// Abriu, leu todos os recursos e não houve diagnóstico `error`.
  ok('ok'),

  /// Abriu e leu tudo, mas com algum diagnóstico `error`.
  diagnosticsError('diagnostics-error'),

  /// O Galley lançou uma `GalleyException` (EPUB rejeitado de forma
  /// controlada).
  failed('failed'),

  /// O Galley lançou outra coisa: **bug do Galley**; reprova o noturno.
  crashed('crashed'),

  /// O `sha256` mudou na origem (o PG regera os EPUBs); não reprova.
  drift('drift'),

  /// Não foi possível baixar (404, rede, prazo); não reprova.
  unavailable('unavailable');

  const WideClass(this.slug);

  /// Nome estável (chave no BMF: `wide/<slug>`).
  final String slug;
}

/// Resultado de um livro.
final class WideResult {
  /// Cria o resultado.
  const WideResult(this.entry, this.cls, [this.detail = '']);

  /// O livro.
  final PgWideEntry entry;

  /// A classe.
  final WideClass cls;

  /// Detalhe: exceção (e o início da stack, no `crashed`) ou causa.
  final String detail;
}

/// Abre [file], lê todos os recursos do manifest e devolve se houve
/// diagnóstico `error`. Pode lançar qualquer coisa; [runWide] classifica.
typedef WideReader = Future<bool> Function(File file);

/// Leitor padrão: `EpubBook.open` e leitura de todos os recursos do manifest.
Future<bool> readWholeBook(File file) async {
  final book = await EpubBook.open(file.path);
  try {
    for (final item in book.manifest.values) {
      await book.resource(item.path);
    }
    return book.diagnostics.any((d) => d.severity == DiagnosticSeverity.error);
  } finally {
    await book.close();
  }
}

/// Resultados de uma execução do modo `wide`.
final class WideReport {
  /// Cria o relatório.
  const WideReport(this.results);

  /// Um resultado por livro, na ordem do manifesto.
  final List<WideResult> results;

  /// Contagem por classe (todas as classes presentes, mesmo com zero).
  Map<WideClass, int> get counts => {
    for (final c in WideClass.values)
      c: results.where((r) => r.cls == c).length,
  };

  /// 1 só se houve `crashed`; as demais classes não reprovam.
  int get exitCode => counts[WideClass.crashed]! > 0 ? 1 : 0;

  /// BMF com `wide/<classe>` → `count`.
  Map<String, Object> toBmf() => bmf.toBmf({
    for (final e in counts.entries)
      'wide/${e.key.slug}': [
        bmf.Measure(slug: bmf.MeasureSlug.count, value: e.value.toDouble()),
      ],
  });

  /// Resumo em texto: contagem por classe e os livros de cada classe que
  /// merece atenção (os números são públicos do Project Gutenberg).
  String summary() {
    final b = StringBuffer('Corpus amplo do Project Gutenberg: ');
    b.writeln('${results.length} livros');
    for (final e in counts.entries) {
      b.writeln('  ${e.key.slug}: ${e.value}');
    }
    for (final cls in [
      WideClass.crashed,
      WideClass.failed,
      WideClass.diagnosticsError,
      WideClass.drift,
      WideClass.unavailable,
    ]) {
      final of = results.where((r) => r.cls == cls).toList();
      if (of.isEmpty) continue;
      b.writeln('${cls.slug}:');
      for (final r in of) {
        final detail = cls == WideClass.crashed
            ? '\n${r.detail.split('\n').map((l) => '      $l').join('\n')}'
            : r.detail.isEmpty
            ? ''
            : ' — ${r.detail.split('\n').first}';
        b.writeln('  #${r.entry.ebookNo}$detail');
      }
    }
    return b.toString();
  }
}

/// Abre cada livro de [entries] (baixando para [cacheDir] se preciso) e o
/// classifica; nunca lança por causa de um livro.
///
/// [fetcher] e [reader] são injetáveis (padrões: [CorpusFetcher] com pausa de
/// [pgPause] e [readWholeBook]). Progresso em [log] (padrão: stderr).
Future<WideReport> runWide(
  List<PgWideEntry> entries, {
  required Directory cacheDir,
  CorpusFetcher? fetcher,
  WideReader? reader,
  StringSink? log,
}) async {
  final out = log ?? stderr;
  final f = fetcher ?? CorpusFetcher(cacheDir: cacheDir, pause: pgPause);
  final read = reader ?? readWholeBook;
  final results = <WideResult>[];
  try {
    for (final (i, e) in entries.indexed) {
      final r = await _classify(e, f, read);
      results.add(r);
      if (r.cls != WideClass.ok) {
        out.writeln(
          '[${i + 1}/${entries.length}] #${e.ebookNo}: ${r.cls.slug}',
        );
      } else if ((i + 1) % 25 == 0) {
        out.writeln('[${i + 1}/${entries.length}]');
      }
    }
  } finally {
    if (fetcher == null) f.close();
  }
  return WideReport(results);
}

Future<WideResult> _classify(
  PgWideEntry e,
  CorpusFetcher fetcher,
  WideReader read,
) async {
  final File file;
  try {
    file = await fetcher.fetch(
      CorpusEntry(
        id: 'pg${e.ebookNo}',
        url: e.url,
        mirrorUrl: null,
        sha256: e.sha256,
        license: 'public-domain',
        source: 'Project Gutenberg',
        tags: const {},
        mirrorable: false,
      ),
    );
  } on CorpusFetchException catch (x) {
    return WideResult(
      e,
      x.digestMismatch ? WideClass.drift : WideClass.unavailable,
      x.causes.join('; '),
    );
  } on Object catch (x) {
    return WideResult(e, WideClass.unavailable, '$x');
  }
  try {
    final hasError = await read(file);
    return WideResult(e, hasError ? WideClass.diagnosticsError : WideClass.ok);
  } on GalleyException catch (x) {
    return WideResult(e, WideClass.failed, '${x.runtimeType}: $x');
  } on Object catch (x, stack) {
    final head = stack.toString().split('\n').take(8).join('\n');
    return WideResult(e, WideClass.crashed, '${x.runtimeType}: $x\n$head');
  }
}

/// Executa o modo `wide`: lê [manifestPath] (`corpus/pg-wide.json`), roda
/// [runWide], imprime o resumo em [log] e grava o BMF em [outPath] e o
/// relatório em [reportPath] (se dados).
///
/// Devolve 1 **só** se houver `crashed`; senão 0.
Future<int> runWideMode({
  required String manifestPath,
  required Directory cacheDir,
  String? outPath,
  String? reportPath,
  StringSink? log,
}) async {
  final sink = log ?? stderr;
  final report = await runWide(
    loadPgWide(manifestPath),
    cacheDir: cacheDir,
    log: sink,
  );
  final summary = report.summary();
  sink.write(summary);
  if (outPath != null) {
    await File(outPath).writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(report.toBmf())}\n',
    );
  }
  if (reportPath != null) {
    await File(reportPath).writeAsString('```\n$summary```\n');
  }
  return report.exitCode;
}
