import 'dart:async';

import 'package:galley_benchmark/src/bench.dart';
import 'package:galley_benchmark/src/catalog.dart';
import 'package:galley_benchmark/src/runner.dart';
import 'package:test/test.dart';

final _kebabId = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*(/[a-z0-9]+(-[a-z0-9]+)*)+$');

const _micro = <String>[
  'container/crc32-1mib',
  'container/zip-central-dir-2000',
  'container/inflate-1mib',
  'container/opf-parse-large',
  'container/nav-parse-large',
  'container/ncx-parse-large',
  'container/deobfuscate-idpf',
  'container/decode-text-utf16',
];

const _books = <String>[
  'typography',
  'publisher-css',
  'tables',
  'notes',
  'images',
  'cjk',
  'rtl-bidi',
  'fonts-idpf',
  'fonts-adobe',
  'epub2-ncx',
];

final class _Throwing implements Bench {
  _Throwing({this.inSetUp = false});

  final bool inSetUp;
  bool tornDown = false;

  @override
  String get id => 'test/throwing';

  @override
  Future<void> setUp() async {
    if (inSetUp) throw StateError('falha no setUp');
  }

  @override
  FutureOr<int> run() => throw StateError('falha no run');

  @override
  Future<void> tearDown() async => tornDown = true;
}

void main() {
  final all = Catalog.all();

  test('ids únicos e em kebab-case', () {
    final ids = [for (final b in all) b.id];
    expect(ids.toSet().length, ids.length);
    for (final id in ids) {
      expect(_kebabId.hasMatch(id), isTrue, reason: id);
    }
  });

  test('o catálogo contém todos os ids esperados', () {
    final ids = {for (final b in all) b.id};
    expect(ids, containsAll(_micro));
    for (final b in _books) {
      expect(ids, contains('container/open-$b'));
      expect(ids, contains('container/open-read-spine-$b'));
    }
    expect(ids.any((i) => i.contains('malformed')), isFalse);
  });

  for (final bench in all.where((b) => b.id != 'harness/noop')) {
    test(
      '${bench.id}: 2 execuções dão o mesmo checksum diferente de 0',
      () async {
        await bench.setUp();
        try {
          final first = await bench.run();
          final second = await bench.run();
          expect(second, first);
          expect(first, isNot(0));
        } finally {
          await bench.tearDown();
        }
      },
      timeout: const Timeout(Duration(minutes: 1)),
    );
  }

  group('runBench', () {
    test(
      'exceção em run sai com 70, escreve no stderr e faz tearDown',
      () async {
        final bench = _Throwing();
        final err = StringBuffer();
        final code = await runBench(
          bench,
          2,
          stdoutSink: StringBuffer(),
          stderrSink: err,
        );
        expect(code, 70);
        expect(err.toString(), contains('falha no run'));
        expect(bench.tornDown, isTrue);
      },
    );

    test('exceção em setUp também sai com 70 e faz tearDown', () async {
      final bench = _Throwing(inSetUp: true);
      final err = StringBuffer();
      final code = await runBench(
        bench,
        1,
        stdoutSink: StringBuffer(),
        stderrSink: err,
      );
      expect(code, 70);
      expect(err.toString(), contains('falha no setUp'));
      expect(bench.tornDown, isTrue);
    });

    test('sucesso imprime checksum e sai com 0', () async {
      final out = StringBuffer();
      final code = await runBench(
        const NoopBench(),
        3,
        stdoutSink: out,
        stderrSink: StringBuffer(),
      );
      expect(code, 0);
      expect(out.toString().trim(), 'checksum=0');
    });
  });
}
