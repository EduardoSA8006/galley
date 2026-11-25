import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
// ignore_for_file: implementation_imports

import 'package:galley/src/features/document/data/parse_document.dart';
import 'package:galley/src/features/document/domain/parsed_document.dart';
import 'package:galley_benchmark/src/corpus/fetcher.dart';
import 'package:galley_benchmark/src/corpus/handmade.dart';
import 'package:galley_benchmark/src/corpus/manifest.dart';
import 'package:galley_benchmark/src/corpus/pg_wide.dart';
import 'package:galley_benchmark/src/modes/docdiff.dart'
    show DocumentBytesParser;
import 'package:galley_benchmark/src/modes/wide.dart';
import 'package:test/test.dart';

import '../support/mini_epub.dart';

String _sha(List<int> b) => sha256.convert(b).toString();

void main() {
  late HttpServer server;
  late Directory cacheDir;
  late Map<int, Uint8List> routes;
  late Uint8List good;

  Uri uri(int n) =>
      Uri.parse('http://${server.address.host}:${server.port}/$n.epub');

  PgWideEntry entry(int n, {String? sha}) => PgWideEntry(
    ebookNo: n,
    url: uri(n),
    sha256: sha ?? _sha(routes[n] ?? Uint8List(0)),
  );

  Future<WideReport> run(
    List<PgWideEntry> entries, {
    WideReader? reader,
    DocumentBytesParser? documentParser,
  }) async {
    final fetcher = CorpusFetcher(cacheDir: cacheDir);
    addTearDown(fetcher.close);
    return runWide(
      entries,
      cacheDir: cacheDir,
      fetcher: fetcher,
      reader: reader,
      documentParser: documentParser,
      log: StringBuffer(),
    );
  }

  setUpAll(() async {
    final books = await buildHandmadeCorpus();
    good = books.values.first;
  });

  setUp(() async {
    routes = {};
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      final n = int.tryParse(r.uri.pathSegments.last.split('.').first);
      final body = routes[n];
      if (body == null) {
        r.response.statusCode = HttpStatus.notFound;
      } else {
        r.response.add(body);
      }
      await r.response.close();
    });
    cacheDir = await Directory.systemTemp.createTemp('galley-wide-');
  });

  tearDown(() async {
    await server.close(force: true);
    await cacheDir.delete(recursive: true);
  });

  test('livro bom: ok, exit 0', () async {
    routes[1] = good;
    final report = await run([entry(1)]);

    expect(report.results.single.cls, WideClass.ok);
    expect(report.counts[WideClass.ok], 1);
    expect(report.exitCode, 0);
  });

  test('EPUB truncado: failed (GalleyException), exit 0', () async {
    routes[2] = Uint8List.sublistView(good, 0, good.length ~/ 2);
    final report = await run([entry(2)]);

    expect(report.results.single.cls, WideClass.failed);
    expect(report.results.single.detail, isNotEmpty);
    expect(report.exitCode, 0);
  });

  test('sha256 diferente na origem: drift, não reprova', () async {
    routes[3] = good;
    final report = await run([entry(3, sha: '0' * 64)]);

    expect(report.results.single.cls, WideClass.drift);
    expect(report.exitCode, 0);
  });

  test('404: unavailable, não reprova', () async {
    final report = await run([entry(4, sha: '1' * 64)]);

    expect(report.results.single.cls, WideClass.unavailable);
    expect(report.exitCode, 0);
  });

  test('StateError no leitor: crashed com stack, exit 1', () async {
    routes[5] = good;
    final report = await run([
      entry(5),
    ], reader: (file) async => throw StateError('bug do galley'));

    final r = report.results.single;
    expect(r.cls, WideClass.crashed);
    expect(r.detail, contains('StateError'));
    expect(r.detail, contains('bug do galley'));
    expect(report.exitCode, 1);
  });

  test('parser de documento que lança StateError: crashed, exit 1', () async {
    routes[8] = good;
    final report = await run(
      [entry(8)],
      documentParser: (bytes, {required path, mediaType = ''}) =>
          throw StateError('bug no montador'),
    );

    final r = report.results.single;
    expect(r.cls, WideClass.crashed);
    expect(r.detail, contains('bug no montador'));
    expect(report.exitCode, 1);
  });

  test('documento com internalError: crashed com o tipo e o caminho', () async {
    routes[11] = good;
    final report = await run(
      [entry(11)],
      documentParser: (bytes, {required path, mediaType = ''}) {
        final real = parseDocumentBytes(bytes, path: path);
        return ParsedDocument(
          tree: real.tree,
          head: real.head,
          diagnostics: real.diagnostics,
          recovered: true,
          internalError: 'RangeError',
        );
      },
    );

    final r = report.results.single;
    expect(r.cls, WideClass.crashed);
    expect(r.detail, contains('RangeError'));
    expect(r.detail, contains('.xhtml'));
    expect(report.exitCode, 1);
  });

  test('livro bom: parseia todos os documentos do spine', () async {
    routes[9] = good;
    final report = await run([entry(9)]);

    final r = report.results.single;
    expect(r.cls, WideClass.ok);
    expect(r.documents, greaterThan(0));
    expect(r.tolerantDocuments, 0);
    expect(report.summary(), contains('documentos do spine'));
  });

  test('documento no modo tolerante: contado, não reprova', () async {
    routes[10] = buildMiniEpub([
      '<html xmlns="http://www.w3.org/1999/xhtml"><body><p>ok</p></body></html>',
      '<html xmlns="http://www.w3.org/1999/xhtml"><body><p>aberto</div></body></html>',
    ]);
    final report = await run([entry(10)]);

    final r = report.results.single;
    expect(r.cls, WideClass.ok);
    expect(r.tolerantDocuments, greaterThan(0));
    expect(report.tolerantDocuments, r.tolerantDocuments);
    expect(report.exitCode, 0);
    final bmf = report.toBmf();
    expect((bmf['wide/documents-tolerant']! as Map)['count'], {
      'value': r.tolerantDocuments.toDouble(),
    });
  });

  test('diagnóstico error: diagnostics-error, não reprova', () async {
    routes[6] = good;
    final report = await run([
      entry(6),
    ], reader: (file) async => const WideRead(hasError: true));

    expect(report.results.single.cls, WideClass.diagnosticsError);
    expect(report.exitCode, 0);
  });

  test('mistura: contagens por classe e BMF com todas as classes', () async {
    routes[1] = good;
    routes[2] = Uint8List.sublistView(good, 0, 100);
    routes[3] = good;
    final report = await run([
      entry(1),
      entry(2),
      entry(3, sha: '0' * 64),
      entry(4, sha: '1' * 64),
    ]);

    expect(report.counts[WideClass.ok], 1);
    expect(report.counts[WideClass.failed], 1);
    expect(report.counts[WideClass.drift], 1);
    expect(report.counts[WideClass.unavailable], 1);
    final bmf = report.toBmf();
    expect(
      bmf.keys,
      containsAll([
        'wide/ok',
        'wide/diagnostics-error',
        'wide/failed',
        'wide/crashed',
        'wide/drift',
        'wide/unavailable',
      ]),
    );
    expect((bmf['wide/ok']! as Map)['count'], {'value': 1.0});
    expect((bmf['wide/crashed']! as Map)['count'], {'value': 0.0});
    expect(report.summary(), contains('2')); // ebook do failed
  });

  test('runWideMode grava o BMF e devolve o exit code', () async {
    routes[7] = good;
    final manifest = File('${cacheDir.path}/pg-wide.json')
      ..writeAsStringSync(
        jsonEncode({
          'version': 1,
          'books': [
            {'ebookNo': 7, 'url': '${uri(7)}', 'sha256': _sha(good)},
          ],
        }),
      );
    final out = File('${cacheDir.path}/wide.json');

    final code = await runWideMode(
      manifestPath: manifest.path,
      cacheDir: cacheDir,
      outPath: out.path,
      log: StringBuffer(),
    );

    expect(code, 0);
    final bmf = jsonDecode(out.readAsStringSync()) as Map<String, Object?>;
    expect((bmf['wide/ok']! as Map)['count'], {'value': 1.0});
  });

  test('loadPgWide valida a estrutura', () {
    final f = File('${cacheDir.path}/bad.json')..writeAsStringSync('{}');
    expect(() => loadPgWide(f.path), throwsFormatException);
    f.writeAsStringSync(
      jsonEncode({
        'version': 1,
        'books': [
          {'ebookNo': 84, 'url': 'https://x/84.epub', 'sha256': 'AB' * 32},
        ],
      }),
    );
    final entries = loadPgWide(f.path);
    expect(entries.single.ebookNo, 84);
    expect(entries.single.sha256, 'ab' * 32);
  });

  test(
    'Retry-After longo: para de pedir; cache continua, resto unavailable',
    () async {
      routes[1] = good;
      routes[2] = good;
      // 1 entra no cache; 3 devolve 503 com Retry-After longo; 4 e 5 não podem
      // chegar ao servidor.
      final fetcher = CorpusFetcher(cacheDir: cacheDir);
      addTearDown(fetcher.close);
      await fetcher.fetch(
        CorpusEntry(
          id: 'x',
          url: uri(1),
          mirrorUrl: null,
          sha256: _sha(good),
          license: '',
          source: '',
          tags: const {},
          mirrorable: false,
        ),
      );
      var hits = 0;
      await server.close(force: true);
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((r) async {
        hits++;
        r.response.statusCode = HttpStatus.serviceUnavailable;
        r.response.headers.set('retry-after', '21600');
        await r.response.close();
      });
      final entries = [
        PgWideEntry(ebookNo: 3, url: uri(3), sha256: '3' * 64),
        PgWideEntry(ebookNo: 4, url: uri(4), sha256: '4' * 64),
        PgWideEntry(ebookNo: 1, url: uri(1), sha256: _sha(good)),
        PgWideEntry(ebookNo: 5, url: uri(5), sha256: '5' * 64),
      ];

      final report = await runWide(
        entries,
        cacheDir: cacheDir,
        fetcher: fetcher,
        log: StringBuffer(),
      );

      expect(hits, 1);
      expect(report.results.map((r) => r.cls), [
        WideClass.unavailable,
        WideClass.unavailable,
        WideClass.ok,
        WideClass.unavailable,
      ]);
      expect(report.exitCode, 0);
    },
  );
}
