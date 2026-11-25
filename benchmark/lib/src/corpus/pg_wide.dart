import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'fetcher.dart';

/// Espelho oficial do Project Gutenberg (o `www.gutenberg.org` bloqueia
/// acesso automatizado).
const String pgMirror = 'https://gutenberg.pglaf.org';

/// Catálogo completo (CSV) publicado para robôs, no espelho.
final Uri pgCatalogUrl = Uri.parse('$pgMirror/cache/epub/feeds/pg_catalog.csv');

/// Pausa mínima entre requisições ao espelho.
const Duration pgPause = Duration(seconds: 2);

/// Um livro do corpus amplo do Project Gutenberg, fixado por `sha256`.
final class PgWideEntry {
  /// Cria a entrada; normalmente vem de [loadPgWide].
  const PgWideEntry({
    required this.ebookNo,
    required this.url,
    required this.sha256,
  });

  /// Número do ebook no Project Gutenberg.
  final int ebookNo;

  /// URL do EPUB (`pgN.epub`, "epub (no images)") no espelho oficial.
  final Uri url;

  /// `sha256` do arquivo, em hexadecimal minúsculo.
  final String sha256;
}

/// URL do EPUB sem imagens do ebook [n] no [mirror].
Uri pgEpubUrl(int n, {String mirror = pgMirror}) =>
    Uri.parse('$mirror/cache/epub/$n/pg$n.epub');

/// Lê `pg-wide.json` (`{"version":1,"books":[{ebookNo,url,sha256}]}`).
///
/// Lança [FormatException] se a estrutura ou algum campo for inválido.
List<PgWideEntry> loadPgWide(String path) {
  final Object? root = jsonDecode(File(path).readAsStringSync());
  if (root is! Map<String, Object?> || root['books'] is! List<Object?>) {
    throw FormatException('pg-wide sem a lista "books": $path');
  }
  return [
    for (final item in root['books']! as List<Object?>)
      switch (item) {
        {
          'ebookNo': final int no,
          'url': final String url,
          'sha256': final String sha,
        } =>
          PgWideEntry(
            ebookNo: no,
            url: Uri.parse(url),
            sha256: sha.toLowerCase(),
          ),
        _ => throw FormatException('item de pg-wide inválido: $item'),
      },
  ];
}

/// Interpreta [text] como CSV (RFC 4180): campos entre aspas podem ter
/// vírgulas, quebras de linha e aspas duplicadas (`""`).
List<List<String>> parseCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  var pending = false; // há conteúdo na linha corrente
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        field.write(c);
      }
    } else if (c == '"') {
      quoted = true;
      pending = true;
    } else if (c == ',') {
      row.add(field.toString());
      field.clear();
      pending = true;
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      if (pending || field.isNotEmpty) {
        row.add(field.toString());
        rows.add(row);
      }
      row = <String>[];
      field.clear();
      pending = false;
    } else {
      field.write(c);
      pending = true;
    }
  }
  if (pending || field.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  return rows;
}

/// Números dos ebooks do tipo `Text` do catálogo CSV [csv] (colunas `Text#`
/// e `Type`), ordenados e sem repetição.
List<int> catalogTextBooks(String csv) {
  final rows = parseCsv(csv);
  if (rows.isEmpty) return const [];
  final header = rows.first;
  final noCol = header.indexOf('Text#');
  final typeCol = header.indexOf('Type');
  if (noCol < 0 || typeCol < 0) {
    throw const FormatException('catálogo sem as colunas Text# e Type');
  }
  return {
    for (final r in rows.skip(1))
      if (r.length > max(noCol, typeCol) &&
          r[typeCol] == 'Text' &&
          int.tryParse(r[noCol]) != null)
        int.parse(r[noCol]),
  }.toList()..sort();
}

/// Ordem embaralhada de [candidates] com `Random(seed)`: mesma semente e
/// mesmo conjunto dão sempre a mesma ordem, qualquer que seja a de entrada.
List<int> shuffledBookNumbers(List<int> candidates, {required int seed}) =>
    ([...candidates]..sort()).toList()..shuffle(Random(seed));

/// Os [count] primeiros de [shuffledBookNumbers].
List<int> pickBookNumbers(
  List<int> candidates, {
  required int count,
  required int seed,
}) => shuffledBookNumbers(candidates, seed: seed).take(count).toList();

/// Escolhe [count] livros do catálogo com `Random(seed)`, baixa cada EPUB
/// (`pgN.epub`) em sequência e grava [outPath] (`pg-wide.json`).
///
/// Ebooks sem esse arquivo (404) são pulados e o próximo da ordem
/// embaralhada entra. Respeita a política de robôs: User-Agent genérico,
/// [pause] entre requisições e `Retry-After` (um pedido longo aborta a
/// execução). O progresso fica em `<cacheDir>/pg-wide-progress.jsonl`, então
/// uma execução interrompida continua de onde parou. Os arquivos ficam em
/// [cacheDir] como `<sha256>.epub`. Só roda manualmente.
Future<List<PgWideEntry>> refreshPgWide({
  required int count,
  required int seed,
  required Directory cacheDir,
  required String outPath,
  CorpusFetcher? fetcher,
  Duration pause = pgPause,
  Uri? catalogUrl,
  String mirror = pgMirror,
  StringSink? log,
}) async {
  final out = log ?? stderr;
  final f =
      fetcher ??
      CorpusFetcher(
        cacheDir: cacheDir,
        pause: pause,
        requestTimeout: const Duration(minutes: 3),
      );
  try {
    final catalog = File('${cacheDir.path}/pg_catalog.csv');
    if (!catalog.existsSync()) {
      out.writeln('Baixando o catálogo…');
      await f.downloadTo(
        catalogUrl ?? pgCatalogUrl,
        catalog,
        id: 'pg_catalog.csv',
        timeout: const Duration(minutes: 40), // ~21 MB; o espelho é lento
      );
    }
    final order = shuffledBookNumbers(
      catalogTextBooks(await catalog.readAsString()),
      seed: seed,
    );

    final progress = File('${cacheDir.path}/pg-wide-progress.jsonl');
    final done = <int, String?>{}; // ebookNo → sha (null = sem EPUB)
    if (progress.existsSync()) {
      for (final line in const LineSplitter().convert(
        await progress.readAsString(),
      )) {
        final m = jsonDecode(line) as Map<String, Object?>;
        done[m['ebookNo']! as int] = m['sha256'] as String?;
      }
    }

    final entries = <PgWideEntry>[];
    for (final no in order) {
      if (entries.length >= count) break;
      final url = pgEpubUrl(no, mirror: mirror);
      if (!done.containsKey(no)) {
        try {
          final pinned = await f.pin(url, id: 'pg$no');
          done[no] = pinned.sha256;
        } on CorpusFetchException catch (e) {
          if (e.retryAfter != null) {
            throw StateError(
              'o servidor pediu Retry-After de ${e.retryAfter!.inSeconds} s; '
              'tente de novo depois ($e)',
            );
          }
          if (e.causes.any((c) => !c.contains('HTTP 404'))) {
            // Falha transitória: não registra, para não perder o livro.
            out.writeln('pg$no: $e (pulado nesta execução)');
            continue;
          }
          done[no] = null;
        }
        await progress.writeAsString(
          '${jsonEncode({'ebookNo': no, 'sha256': done[no]})}\n',
          mode: FileMode.append,
        );
      }
      final sha = done[no];
      if (sha == null) continue;
      entries.add(PgWideEntry(ebookNo: no, url: url, sha256: sha));
      if (entries.length % 10 == 0) {
        out.writeln('${entries.length}/$count livros');
      }
    }
    entries.sort((a, b) => a.ebookNo.compareTo(b.ebookNo));
    await File(outPath).writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({
        'version': 1,
        'seed': seed,
        'file': 'pgN.epub (EPUB sem imagens)',
        'books': [
          for (final e in entries) {'ebookNo': e.ebookNo, 'url': '${e.url}', 'sha256': e.sha256},
        ],
      })}\n',
    );
    return entries;
  } finally {
    if (fetcher == null) f.close();
  }
}
