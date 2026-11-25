import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:galley_benchmark/src/corpus/fetcher.dart';
import 'package:galley_benchmark/src/corpus/manifest.dart';
import 'package:test/test.dart';

CorpusEntry _entry(Uri url, Uint8List bytes, {String? sha}) => CorpusEntry(
  id: 'robust',
  url: url,
  mirrorUrl: null,
  sha256: sha ?? sha256.convert(bytes).toString(),
  license: 'CC0-1.0',
  source: 'teste',
  tags: const {},
  mirrorable: false,
);

void main() {
  final bytes = Uint8List.fromList(List.generate(2048, (i) => i % 251));
  late HttpServer server;
  late Directory cacheDir;
  late List<DateTime> hits;
  late Future<void> Function(HttpRequest) handler;

  Uri uri(String path) =>
      Uri.parse('http://${server.address.host}:${server.port}$path');

  setUp(() async {
    hits = [];
    handler = (r) async {
      r.response.add(bytes);
      await r.response.close();
    };
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) {
      hits.add(DateTime.now());
      unawaited(handler(r));
    });
    cacheDir = await Directory.systemTemp.createTemp('galley-robust-');
  });

  tearDown(() async {
    await server.close(force: true);
    await cacheDir.delete(recursive: true);
  });

  test('servidor que não responde: falha dentro do prazo', () async {
    handler = (r) async {}; // nunca responde
    final fetcher = CorpusFetcher(
      cacheDir: cacheDir,
      requestTimeout: const Duration(milliseconds: 300),
    );
    addTearDown(fetcher.close);

    final sw = Stopwatch()..start();
    final error = await fetcher
        .fetch(_entry(uri('/x.epub'), bytes))
        .then<Object>((_) => 'sem erro', onError: (Object e) => e);

    expect(error, isA<CorpusFetchException>());
    expect((error as CorpusFetchException).causes.single, contains('tempo'));
    expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
  });

  test('corpo que trava no meio: falha dentro do prazo', () async {
    handler = (r) async {
      r.response.add(bytes.sublist(0, 100));
      await r.response.flush(); // e para
    };
    final fetcher = CorpusFetcher(
      cacheDir: cacheDir,
      requestTimeout: const Duration(milliseconds: 300),
    );
    addTearDown(fetcher.close);

    await expectLater(
      fetcher.fetch(_entry(uri('/x.epub'), bytes)),
      throwsA(isA<CorpusFetchException>()),
    );
    expect(cacheDir.listSync().where((f) => f.path.endsWith('.epub')), isEmpty);
  });

  test('close() é idempotente e encerra o cliente próprio', () async {
    final fetcher = CorpusFetcher(cacheDir: cacheDir);
    fetcher.close();
    fetcher.close();
    await expectLater(
      fetcher.fetch(_entry(uri('/x.epub'), bytes)),
      throwsA(isA<CorpusFetchException>()),
    );
  });

  test('pause: espera entre requisições de rede', () async {
    final fetcher = CorpusFetcher(
      cacheDir: cacheDir,
      pause: const Duration(milliseconds: 400),
    );
    addTearDown(fetcher.close);

    await fetcher.fetch(_entry(uri('/a.epub'), bytes));
    cacheDir.listSync().forEach((f) => f.deleteSync());
    await fetcher.fetch(_entry(uri('/b.epub'), bytes));

    expect(hits, hasLength(2));
    expect(
      hits[1].difference(hits[0]),
      greaterThanOrEqualTo(const Duration(milliseconds: 380)),
    );
  });

  test('Retry-After curto: espera e tenta de novo', () async {
    var n = 0;
    handler = (r) async {
      if (n++ == 0) {
        r.response.statusCode = HttpStatus.serviceUnavailable;
        r.response.headers.set('retry-after', '1');
      } else {
        r.response.add(bytes);
      }
      await r.response.close();
    };
    final fetcher = CorpusFetcher(cacheDir: cacheDir);
    addTearDown(fetcher.close);

    await fetcher.fetch(_entry(uri('/x.epub'), bytes));

    expect(hits, hasLength(2));
    expect(
      hits[1].difference(hits[0]),
      greaterThanOrEqualTo(const Duration(milliseconds: 900)),
    );
  });

  test('Retry-After longo: não espera e expõe retryAfter', () async {
    handler = (r) async {
      r.response.statusCode = HttpStatus.serviceUnavailable;
      r.response.headers.set('retry-after', '21600');
      await r.response.close();
    };
    final fetcher = CorpusFetcher(cacheDir: cacheDir);
    addTearDown(fetcher.close);

    final error = await fetcher
        .fetch(_entry(uri('/x.epub'), bytes))
        .then<Object>((_) => 'sem erro', onError: (Object e) => e);

    expect(hits, hasLength(1));
    expect(error, isA<CorpusFetchException>());
    expect(
      (error as CorpusFetchException).retryAfter,
      const Duration(hours: 6),
    );
  });

  test('sha256 divergente marca digestMismatch; 404 não', () async {
    final fetcher = CorpusFetcher(cacheDir: cacheDir);
    addTearDown(fetcher.close);

    final drift = await fetcher
        .fetch(_entry(uri('/x.epub'), bytes, sha: '0' * 64))
        .then<Object>((_) => 'sem erro', onError: (Object e) => e);
    handler = (r) async {
      r.response.statusCode = HttpStatus.notFound;
      await r.response.close();
    };
    final missing = await fetcher
        .fetch(_entry(uri('/y.epub'), bytes))
        .then<Object>((_) => 'sem erro', onError: (Object e) => e);

    expect((drift as CorpusFetchException).digestMismatch, isTrue);
    expect((missing as CorpusFetchException).digestMismatch, isFalse);
  });

  test('pin: baixa sem sha esperado e grava em <sha256>.epub', () async {
    final fetcher = CorpusFetcher(cacheDir: cacheDir);
    addTearDown(fetcher.close);

    final pinned = await fetcher.pin(uri('/x.epub'), id: 'x');

    expect(pinned.sha256, sha256.convert(bytes).toString());
    expect(pinned.file.path, '${cacheDir.path}/${pinned.sha256}.epub');
    expect(await pinned.file.readAsBytes(), bytes);
  });

  test('downloadTo: o timeout próprio substitui o do fetcher', () async {
    handler = (r) async {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      r.response.add(bytes);
      await r.response.close();
    };
    final fetcher = CorpusFetcher(
      cacheDir: cacheDir,
      requestTimeout: const Duration(milliseconds: 100),
    );
    addTearDown(fetcher.close);
    final target = File('${cacheDir.path}/catalog.csv');

    await expectLater(
      fetcher.downloadTo(uri('/c.csv'), target, id: 'c'),
      throwsA(isA<CorpusFetchException>()),
    );
    await fetcher.downloadTo(
      uri('/c.csv'),
      target,
      id: 'c',
      timeout: const Duration(seconds: 5),
    );
    expect(await target.readAsBytes(), bytes);
  });
}
