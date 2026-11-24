import 'dart:io';

import 'package:galley/galley.dart';
import 'package:galley_benchmark/src/competitors/adapter.dart';
import 'package:galley_benchmark/src/competitors/epub_plus_adapter.dart';
import 'package:galley_benchmark/src/competitors/epub_pro_adapter.dart';
import 'package:galley_benchmark/src/competitors/galley_adapter.dart';
import 'package:galley_benchmark/src/corpus/handmade.dart';
import 'package:galley_benchmark/src/modes/compare.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late Map<String, File> books;

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('galley-compare-test-');
    final built = await buildHandmadeCorpus();
    books = {
      for (final id in ['hm/typography', 'hm/epub2-ncx'])
        id: File('${tmp.path}/${id.split('/').last}.epub')
          ..writeAsBytesSync(built[id]!),
    };
  });

  tearDownAll(() => tmp.deleteSync(recursive: true));

  Future<({int spine, int bytes})> inProcess(
    ParserAdapter adapter,
    File book,
  ) async {
    await adapter.open(book.path);
    try {
      return (spine: adapter.spineLength, bytes: await adapter.readAllSpine());
    } finally {
      await adapter.close();
    }
  }

  for (final id in ['hm/typography', 'hm/epub2-ncx']) {
    test('$id: galley, epub_plus e epub_pro somam os mesmos bytes', () async {
      final file = books[id]!;
      final galley = await inProcess(GalleyAdapter(), file);
      expect(galley.spine, greaterThan(0));
      expect(galley.bytes, greaterThan(0));
      for (final adapter in <ParserAdapter>[
        EpubPlusAdapter(),
        EpubProAdapter(),
      ]) {
        final r = await inProcess(adapter, file);
        expect(r.spine, galley.spine, reason: '${adapter.name}: spine');
        expect(r.bytes, galley.bytes, reason: '${adapter.name}: bytes');
      }
    });
  }

  test(
    'openEager: concorrentes abrem o livro inteiro, Galley não tem',
    () async {
      final file = books['hm/typography']!;
      for (final adapter in <ParserAdapter>[
        EpubPlusAdapter(),
        EpubProAdapter(),
      ]) {
        await adapter.openEager(file.path);
        expect(adapter.spineLength, greaterThan(0), reason: adapter.name);
        await adapter.close();
      }
      expect(
        GalleyAdapter().openEager(file.path),
        throwsA(isA<UnsupportedError>()),
      );
    },
  );

  test('readOne acha o recurso pelo caminho completo no arquivo', () async {
    final file = books['hm/typography']!;
    final path = await _firstSpinePath(file);
    final galley = GalleyAdapter();
    await galley.open(file.path);
    final expected = await galley.readOne(path);
    await galley.close();
    for (final adapter in <ParserAdapter>[
      EpubPlusAdapter(),
      EpubProAdapter(),
    ]) {
      await adapter.open(file.path);
      expect(await adapter.readOne(path), expected, reason: adapter.name);
      await expectLater(adapter.readOne('nao/existe.xhtml'), throwsStateError);
      await adapter.close();
    }
  });

  group('compareBooks', () {
    late File good;
    late File bad;

    setUpAll(() {
      File script(String name, String body) {
        final f = File('${tmp.path}/$name.sh')
          ..writeAsStringSync('#!/bin/sh\n$body\n');
        Process.runSync('chmod', ['+x', f.path]);
        return f;
      }

      good = script(
        'good',
        'echo ns=2000000; echo rss=1048576; echo checksum=7',
      );
      bad = script('bad', 'echo "Falha: boom" >&2; exit 70');
    });

    test(
      'adaptador que lança vira a célula falhou sem abortar o modo',
      () async {
        final cells = await compareBooks(
          adapters: [
            CompareAdapter('galley', good),
            CompareAdapter('epub_pro', bad),
          ],
          books: [CompareBook('hm/typography', books['hm/typography']!)],
          runs: 3,
          timeout: const Duration(seconds: 30),
          workDir: tmp,
          log: StringBuffer(),
        );
        final ok = cells.where((c) => c.adapter == 'galley').toList();
        expect(ok.map((c) => c.metric), ['open', 'open-eager', 'read-all']);
        expect(ok.every((c) => c.ok), isTrue);
        expect(ok.first.wallNs, 2000000);
        expect(ok.last.peakRss, 1048576);
        final failed = cells.where((c) => c.adapter == 'epub_pro');
        expect(failed.every((c) => !c.ok), isTrue);
        expect(failed.first.failure, contains('boom'));

        final report = renderCompareReport(
          cells,
          adapterNames: ['galley', 'epub_pro'],
          runs: 3,
          elapsed: const Duration(seconds: 5),
        );
        expect(report, contains('falhou'));
        expect(report, contains('2.00'));
        final bmf = compareBmf(cells);
        expect(bmf.keys, contains('compare/galley/open/hm/typography'));
        expect(
          bmf.keys,
          isNot(contains('compare/epub_pro/open/hm/typography')),
        );
      },
    );

    test(
      'ordem gira a cada rodada, há aquecimento e eager só onde existe',
      () async {
        final log = File('${tmp.path}/order.log');
        final logger = File('${tmp.path}/logger.sh')
          ..writeAsStringSync(
            '#!/bin/sh\necho "\$1 \$3" >> ${log.path}\n'
            'echo ns=1; echo rss=2; echo checksum=3\n',
          );
        Process.runSync('chmod', ['+x', logger.path]);
        final cells = await compareBooks(
          adapters: [
            CompareAdapter('a', logger, prefixArgs: ['a']),
            CompareAdapter(
              'b',
              logger,
              prefixArgs: ['b'],
              supportsEager: false,
            ),
          ],
          books: [CompareBook('hm/typography', books['hm/typography']!)],
          runs: 3,
          timeout: const Duration(seconds: 30),
          workDir: tmp,
          log: StringBuffer(),
        );
        final lines = log.readAsLinesSync();
        // Aquecimento (a, b) e depois as 3 rodadas do `open` girando.
        expect(lines.take(8).toList(), [
          'a open',
          'b open',
          'a open',
          'b open',
          'b open',
          'a open',
          'a open',
          'b open',
        ]);
        expect(
          cells.where((c) => c.metric == 'open-eager').map((c) => c.adapter),
          ['a'],
        );
      },
    );

    test('falha no open: read-all herda a falha sem rodar', () async {
      final cells = await compareBooks(
        adapters: [CompareAdapter('x', bad)],
        books: [CompareBook('hm/typography', books['hm/typography']!)],
        runs: 1,
        timeout: const Duration(seconds: 30),
        workDir: tmp,
        log: StringBuffer(),
      );
      final readAll = cells.singleWhere((c) => c.metric == 'read-all');
      expect(readAll.inherited, isTrue);
      expect(cells.singleWhere((c) => c.metric == 'open').inherited, isFalse);
      final report = renderCompareReport(
        cells,
        adapterNames: ['x'],
        runs: 1,
        elapsed: Duration.zero,
      );
      expect(RegExp('`read-all` `hm/typography`').hasMatch(report), isFalse);
    });

    test('read-one só no livro que define o recurso', () async {
      final cells = await compareBooks(
        adapters: [CompareAdapter('galley', good)],
        books: [
          CompareBook(
            'synthetic/50mib',
            books['hm/typography']!,
            readOneResource: 'OEBPS/text/ch100.xhtml',
          ),
          CompareBook('hm/epub2-ncx', books['hm/epub2-ncx']!),
        ],
        runs: 1,
        timeout: const Duration(seconds: 30),
        workDir: tmp,
        log: StringBuffer(),
      );
      expect(cells.where((c) => c.metric == 'read-one').map((c) => c.book), [
        'synthetic/50mib',
      ]);
    });
  });
}

/// Caminho completo, no arquivo, do primeiro documento do spine.
Future<String> _firstSpinePath(File file) async {
  final book = await EpubBook.open(file.path);
  try {
    return book.spine.items.first.item.path;
  } finally {
    await book.close();
  }
}
