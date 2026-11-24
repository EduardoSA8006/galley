import 'dart:io';

import 'package:galley/galley.dart';
import 'package:galley_benchmark/src/competitors/adapter.dart';
import 'package:galley_benchmark/src/competitors/epub_plus_adapter.dart';
import 'package:galley_benchmark/src/competitors/epub_pro_adapter.dart';
import 'package:galley_benchmark/src/competitors/galley_adapter.dart';
import 'package:galley_benchmark/src/corpus/handmade.dart';
import 'package:galley_benchmark/src/modes/build.dart';
import 'package:galley_benchmark/src/modes/compare.dart';
import 'package:galley_benchmark/src/modes/local.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late Map<String, File> books;
  late File epubxExe;

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('galley-compare-test-');
    final built = await buildHandmadeCorpus();
    books = {
      for (final id in ['hm/typography', 'hm/epub2-ncx'])
        id: File('${tmp.path}/${id.split('/').last}.epub')
          ..writeAsBytesSync(built[id]!),
    };
    // O epubx vive noutro pacote (image ^3): o teste o usa pelo executável.
    final root = await repoRoot();
    final satellite = '${root.path}/benchmark/competitors/epubx_runner';
    final get = await Process.run(Platform.resolvedExecutable, [
      'pub',
      'get',
    ], workingDirectory: satellite);
    expect(get.exitCode, 0, reason: '${get.stderr}');
    epubxExe = await compileEpubxRunner(
      satelliteDir: Directory(satellite),
      outPath: '${tmp.path}/epubx-runner',
    );
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

  Future<({int spine, int bytes})> viaEpubx(File book) async {
    Future<int> checksum(String kind) async {
      final r = await Process.run(epubxExe.path, [
        '--measure',
        kind,
        book.path,
      ]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      return parseMeasureOpen(r.stdout as String).checksum;
    }

    return (spine: await checksum('open'), bytes: await checksum('read-all'));
  }

  for (final id in ['hm/typography', 'hm/epub2-ncx']) {
    test('$id: os 4 adaptadores somam os mesmos bytes do spine', () async {
      final file = books[id]!;
      final results = {
        'galley': await inProcess(GalleyAdapter(), file),
        'epub_plus': await inProcess(EpubPlusAdapter(), file),
        'epub_pro': await inProcess(EpubProAdapter(), file),
        'epubx': await viaEpubx(file),
      };
      expect(results['galley']!.spine, greaterThan(0));
      expect(results['galley']!.bytes, greaterThan(0));
      // Se algum concorrente normalizar o conteúdo (ex.: quebras de linha ou
      // BOM), os bytes divergem: o teste então deve documentar a diferença e
      // manter a igualdade da contagem de itens do spine.
      for (final entry in results.entries) {
        expect(
          entry.value.spine,
          results['galley']!.spine,
          reason: '${entry.key}: itens do spine',
        );
        expect(
          entry.value.bytes,
          results['galley']!.bytes,
          reason: '${entry.key}: bytes do spine',
        );
      }
    });
  }

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
    final r = await Process.run(epubxExe.path, [
      '--measure',
      'read-one',
      '--resource',
      path,
      file.path,
    ]);
    expect(parseMeasureOpen(r.stdout as String).checksum, expected);
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
        expect(ok.map((c) => c.metric), ['open', 'read-all']);
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
