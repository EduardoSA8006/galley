import 'dart:convert';
import 'dart:io';

// ignore_for_file: implementation_imports

import 'package:galley/galley.dart';
import 'package:galley/src/features/document/data/parse_document.dart';

import '../bmf.dart' as bmf;
import '../corpus/fetcher.dart';
import '../corpus/manifest.dart';
import '../corpus/pg_wide.dart';
import 'docdiff.dart' show DocumentBytesParser, documentMediaTypes;

/// Classe de resultado de um livro do corpus amplo.
enum WideClass {
  /// Abriu, leu todos os recursos, parseou os documentos do spine e não
  /// houve diagnóstico `error` no livro.
  ok('ok'),

  /// Abriu e leu tudo, mas com algum diagnóstico `error`.
  diagnosticsError('diagnostics-error'),

  /// O Galley lançou uma `GalleyException` (EPUB rejeitado de forma
  /// controlada).
  failed('failed'),

  /// O Galley lançou outra coisa (na abertura, na leitura ou no parse de um
  /// documento): **bug do Galley**; reprova o noturno.
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
  const WideResult(
    this.entry,
    this.cls, [
    this.detail = '',
    this.documents = 0,
    this.tolerantDocuments = 0,
  ]);

  /// O livro.
  final PgWideEntry entry;

  /// A classe.
  final WideClass cls;

  /// Detalhe: exceção (e o início da stack, no `crashed`) ou causa.
  final String detail;

  /// Documentos do spine parseados.
  final int documents;

  /// Desses, quantos caíram no modo tolerante (não reprova).
  final int tolerantDocuments;
}

/// O que o [WideReader] leu de um livro.
final class WideRead {
  /// Cria o resultado da leitura.
  const WideRead({
    required this.hasError,
    this.documents = 0,
    this.tolerantDocuments = 0,
  });

  /// Se o livro teve diagnóstico `error`.
  final bool hasError;

  /// Documentos do spine parseados.
  final int documents;

  /// Desses, quantos caíram no modo tolerante.
  final int tolerantDocuments;
}

/// Abre [file], lê todos os recursos do manifest e parseia os documentos do
/// spine. Pode lançar qualquer coisa; [runWide] classifica.
typedef WideReader = Future<WideRead> Function(File file);

/// Leitor padrão: `EpubBook.open`, leitura de todos os recursos do manifest
/// (cada um uma vez) e [parse] (por padrão `parseDocumentBytes`) dos bytes
/// já lidos de cada documento do spine (itens que não são documento ficam
/// de fora).
///
/// Um documento com `internalError` (exceção inesperada capturada pelo
/// leitor: bug do Galley) lança [WideInternalError], que [runWide] classifica
/// como `crashed`.
Future<WideRead> readWholeBook(
  File file, {
  DocumentBytesParser parse = parseDocumentBytes,
}) async {
  final book = await EpubBook.open(file.path);
  try {
    final spineDocuments = {
      for (final s in book.spine.items)
        if (documentMediaTypes.contains(s.item.mediaType)) s.item.path,
    };
    var documents = 0;
    var tolerant = 0;
    for (final item in book.manifest.values) {
      final bytes = await book.resource(item.path);
      if (!spineDocuments.contains(item.path)) continue;
      final parsed = parse(bytes, path: item.path, mediaType: item.mediaType);
      final internal = parsed.internalError;
      if (internal != null) throw WideInternalError(item.path, internal);
      documents++;
      if (parsed.recovered) tolerant++;
    }
    return WideRead(
      hasError: book.diagnostics.any(
        (d) => d.severity == DiagnosticSeverity.error,
      ),
      documents: documents,
      tolerantDocuments: tolerant,
    );
  } finally {
    await book.close();
  }
}

/// Um documento do spine voltou com `ParsedDocument.internalError`: o
/// leitor do Galley capturou uma exceção inesperada (bug).
final class WideInternalError implements Exception {
  /// Cria o erro do documento [path] com a exceção do tipo [type].
  const WideInternalError(this.path, this.type);

  /// Caminho do documento no EPUB.
  final String path;

  /// Tipo da exceção capturada.
  final String type;

  @override
  String toString() => 'erro interno do Galley ($type) no documento $path';
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

  /// Documentos do spine parseados, somando todos os livros.
  int get documents => results.fold(0, (s, r) => s + r.documents);

  /// Documentos que caíram no modo tolerante, somando todos os livros.
  int get tolerantDocuments =>
      results.fold(0, (s, r) => s + r.tolerantDocuments);

  /// 1 só se houve `crashed`; as demais classes não reprovam.
  int get exitCode => counts[WideClass.crashed]! > 0 ? 1 : 0;

  /// BMF com `wide/<classe>`, `wide/documents` e `wide/documents-tolerant`
  /// → `count`.
  Map<String, Object> toBmf() => bmf.toBmf({
    for (final e in counts.entries)
      'wide/${e.key.slug}': [
        bmf.Measure(slug: bmf.MeasureSlug.count, value: e.value.toDouble()),
      ],
    'wide/documents': [
      bmf.Measure(slug: bmf.MeasureSlug.count, value: documents.toDouble()),
    ],
    'wide/documents-tolerant': [
      bmf.Measure(
        slug: bmf.MeasureSlug.count,
        value: tolerantDocuments.toDouble(),
      ),
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
    b.writeln(
      'documentos do spine: $documents '
      '(modo tolerante: $tolerantDocuments)',
    );
    final tolerantBooks = [
      for (final r in results)
        if (r.tolerantDocuments > 0)
          '#${r.entry.ebookNo} (${r.tolerantDocuments})',
    ];
    if (tolerantBooks.isNotEmpty) {
      b.writeln(
        '  livros com documento tolerante: ${tolerantBooks.join(', ')}',
      );
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
/// [pgPause] e [readWholeBook]); [documentParser] troca o parse de
/// documentos do leitor padrão. Progresso em [log] (padrão: stderr).
Future<WideReport> runWide(
  List<PgWideEntry> entries, {
  required Directory cacheDir,
  CorpusFetcher? fetcher,
  WideReader? reader,
  DocumentBytesParser? documentParser,
  StringSink? log,
}) async {
  final out = log ?? stderr;
  final f = fetcher ?? CorpusFetcher(cacheDir: cacheDir, pause: pgPause);
  final read =
      reader ??
      (File file) =>
          readWholeBook(file, parse: documentParser ?? parseDocumentBytes);
  final results = <WideResult>[];
  try {
    var suspended = false; // o servidor pediu Retry-After: sem mais rede
    for (final (i, e) in entries.indexed) {
      final WideResult r;
      if (suspended &&
          !File('${cacheDir.path}/${e.sha256}.epub').existsSync()) {
        r = WideResult(
          e,
          WideClass.unavailable,
          'requisições suspensas após Retry-After do servidor',
        );
      } else {
        final c = await _classify(e, f, read);
        r = c.result;
        if (c.retryAfter != null && !suspended) {
          suspended = true;
          out.writeln(
            'O servidor pediu Retry-After de ${c.retryAfter!.inSeconds} s: '
            'sem novas requisições; livros fora do cache viram unavailable.',
          );
        }
      }
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

Future<({WideResult result, Duration? retryAfter})> _classify(
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
    return (
      result: WideResult(
        e,
        x.digestMismatch ? WideClass.drift : WideClass.unavailable,
        x.causes.join('; '),
      ),
      retryAfter: x.retryAfter,
    );
  } on Object catch (x) {
    return (
      result: WideResult(e, WideClass.unavailable, '$x'),
      retryAfter: null,
    );
  }
  try {
    final r = await read(file);
    return (
      result: WideResult(
        e,
        r.hasError ? WideClass.diagnosticsError : WideClass.ok,
        '',
        r.documents,
        r.tolerantDocuments,
      ),
      retryAfter: null,
    );
  } on GalleyException catch (x) {
    return (
      result: WideResult(e, WideClass.failed, '${x.runtimeType}: $x'),
      retryAfter: null,
    );
  } on Object catch (x, stack) {
    final head = stack.toString().split('\n').take(8).join('\n');
    return (
      result: WideResult(e, WideClass.crashed, '${x.runtimeType}: $x\n$head'),
      retryAfter: null,
    );
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
