import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:galley_benchmark/src/corpus/fetcher.dart';
import 'package:galley_benchmark/src/corpus/manifest.dart';
import 'package:test/test.dart';

/// Tags que o manifesto real precisa cobrir.
const _allTags = <String>{
  'epub2',
  'epub3',
  'fixed-layout',
  'cjk',
  'rtl',
  'tables',
  'illustrated',
  'technical',
  'w3c-tests',
  'large',
};

/// Servidor HTTP local que responde por caminho e conta as requisições.
final class _FakeServer {
  _FakeServer._(this._server);

  final HttpServer _server;

  /// Caminho → corpo; caminhos ausentes respondem 404.
  final Map<String, List<int>> routes = {};

  /// Caminhos requisitados, na ordem.
  final List<String> requests = [];

  static Future<_FakeServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _FakeServer._(server);
    server.listen((request) async {
      fake.requests.add(request.uri.path);
      final body = fake.routes[request.uri.path];
      if (body == null) {
        request.response.statusCode = HttpStatus.notFound;
      } else {
        request.response.add(body);
      }
      await request.response.close();
    });
    return fake;
  }

  Uri uri(String path) =>
      Uri.parse('http://${_server.address.host}:${_server.port}$path');

  Future<void> close() => _server.close(force: true);
}

CorpusEntry _entry(
  Uint8List bytes, {
  required Uri url,
  Uri? mirrorUrl,
  String? sha,
}) => CorpusEntry(
  id: 'test-book',
  url: url,
  mirrorUrl: mirrorUrl,
  sha256: sha ?? sha256.convert(bytes).toString(),
  license: 'CC0-1.0',
  source: 'teste',
  tags: const {'epub3'},
  mirrorable: mirrorUrl != null,
);

void main() {
  final bytes = Uint8List.fromList(List.generate(4096, (i) => i * 7 % 256));
  late _FakeServer server;
  late Directory cacheDir;
  late CorpusFetcher fetcher;

  setUp(() async {
    server = await _FakeServer.start();
    cacheDir = await Directory.systemTemp.createTemp('galley-corpus-test-');
    fetcher = CorpusFetcher(cacheDir: cacheDir);
  });

  tearDown(() async {
    await server.close();
    await cacheDir.delete(recursive: true);
  });

  test('cache presente: nenhuma requisição', () async {
    final entry = _entry(
      bytes,
      url: server.uri('/orig.epub'),
      mirrorUrl: server.uri('/mirror.epub'),
    );
    final cached = File('${cacheDir.path}/${entry.sha256}.epub');
    await cached.writeAsBytes(bytes);

    final file = await fetcher.fetch(entry);

    expect(file.path, cached.path);
    expect(server.requests, isEmpty);
  });

  test('espelho OK: usa o espelho e grava no cache', () async {
    server.routes['/mirror.epub'] = bytes;
    server.routes['/orig.epub'] = bytes;
    final entry = _entry(
      bytes,
      url: server.uri('/orig.epub'),
      mirrorUrl: server.uri('/mirror.epub'),
    );

    final file = await fetcher.fetch(entry);

    expect(server.requests, ['/mirror.epub']);
    expect(file.path, '${cacheDir.path}/${entry.sha256}.epub');
    expect(await file.readAsBytes(), bytes);
  });

  test('espelho 404 e url OK: usa a url', () async {
    server.routes['/orig.epub'] = bytes;
    final entry = _entry(
      bytes,
      url: server.uri('/orig.epub'),
      mirrorUrl: server.uri('/mirror.epub'),
    );

    final file = await fetcher.fetch(entry);

    expect(server.requests, ['/mirror.epub', '/orig.epub']);
    expect(await file.readAsBytes(), bytes);
  });

  test('sha256 divergente: CorpusFetchException com id e causa', () async {
    server.routes['/orig.epub'] = bytes;
    final entry = _entry(bytes, url: server.uri('/orig.epub'), sha: '0' * 64);

    final error = await fetcher
        .fetch(entry)
        .then<Object?>((_) => null, onError: (Object e) => e);

    expect(error, isA<CorpusFetchException>());
    final exception = error! as CorpusFetchException;
    expect(exception.id, 'test-book');
    expect(exception.causes, hasLength(1));
    expect(exception.causes.single, contains('sha256 mismatch'));
    expect(
      File('${cacheDir.path}/${entry.sha256}.epub').existsSync(),
      isFalse,
      reason: 'arquivo inválido não pode ficar no cache',
    );
  });

  test('espelho e url falham: exceção com as duas causas', () async {
    final entry = _entry(
      bytes,
      url: server.uri('/orig.epub'),
      mirrorUrl: server.uri('/mirror.epub'),
    );

    final error = await fetcher
        .fetch(entry)
        .then<Object?>((_) => null, onError: (Object e) => e);

    expect(error, isA<CorpusFetchException>());
    final exception = error! as CorpusFetchException;
    expect(exception.id, 'test-book');
    expect(exception.causes, hasLength(2));
    expect(
      exception.causes[0],
      allOf(contains('mirror.epub'), contains('404')),
    );
    expect(exception.causes[1], allOf(contains('orig.epub'), contains('404')));
  });

  test('cache com sha256 divergente é descartado e baixado de novo', () async {
    server.routes['/orig.epub'] = bytes;
    final entry = _entry(bytes, url: server.uri('/orig.epub'));
    final cached = File('${cacheDir.path}/${entry.sha256}.epub');
    await cached.writeAsBytes([1, 2, 3]);

    final file = await fetcher.fetch(entry);

    expect(server.requests, ['/orig.epub']);
    expect(await file.readAsBytes(), bytes);
  });

  group('manifesto real', () {
    late List<CorpusEntry> entries;

    setUpAll(() {
      entries = loadManifest('../corpus/manifest.json');
    });

    test('carrega entre 15 e 25 livros com ids únicos', () {
      expect(entries.length, inInclusiveRange(15, 25));
      expect(entries.map((e) => e.id).toSet(), hasLength(entries.length));
    });

    test('cobre todas as tags', () {
      final covered = {for (final e in entries) ...e.tags};
      expect(covered, containsAll(_allTags));
      expect(_allTags, containsAll(covered), reason: 'tag desconhecida');
    });

    test('sha256 válido e espelho só nos itens espelháveis', () {
      final hex = RegExp(r'^[0-9a-f]{64}$');
      for (final e in entries) {
        expect(e.sha256, matches(hex), reason: e.id);
        expect(e.license, isNotEmpty, reason: e.id);
        expect(e.source, isNotEmpty, reason: e.id);
        if (e.mirrorable) {
          expect(
            e.mirrorUrl,
            Uri.parse(
              'https://github.com/EduardoSA8006/galley/releases/download/'
              'corpus-v1/${e.id}.epub',
            ),
            reason: e.id,
          );
        } else {
          expect(e.mirrorUrl, isNull, reason: e.id);
        }
      }
    });
  });

  test('loadManifest rejeita item sem campo obrigatório', () async {
    final dir = await Directory.systemTemp.createTemp('galley-manifest-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/m.json')
      ..writeAsStringSync('{"version": 1, "books": [{"id": "x"}]}');
    expect(() => loadManifest(file.path), throwsFormatException);
  });
}
