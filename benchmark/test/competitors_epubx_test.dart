@Tags(['slow'])
library;

import 'dart:io';

import 'package:galley/galley.dart';
import 'package:galley_benchmark/src/competitors/adapter.dart';
import 'package:galley_benchmark/src/competitors/epub_plus_adapter.dart';
import 'package:galley_benchmark/src/competitors/epub_pro_adapter.dart';
import 'package:galley_benchmark/src/competitors/galley_adapter.dart';
import 'package:galley_benchmark/src/corpus/handmade.dart';
import 'package:galley_benchmark/src/modes/build.dart';
import 'package:galley_benchmark/src/modes/local.dart';
import 'package:test/test.dart';

/// Os 4 adaptadores, com o epubx pelo executável do satélite (pacote próprio
/// por conflito de `image`): `pub get` e `dart compile exe` no `setUpAll`,
/// por isso `slow`.
void main() {
  late Directory tmp;
  late Map<String, File> books;
  late File epubxExe;

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('galley-epubx-test-');
    final built = await buildHandmadeCorpus();
    books = {
      for (final id in ['hm/typography', 'hm/epub2-ncx'])
        id: File('${tmp.path}/${id.split('/').last}.epub')
          ..writeAsBytesSync(built[id]!),
    };
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

  Future<int> epubx(String kind, File book, {String? resource}) async {
    final r = await Process.run(epubxExe.path, [
      '--measure',
      kind,
      if (resource != null) ...['--resource', resource],
      book.path,
    ]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    return parseMeasureOpen(r.stdout as String).checksum;
  }

  for (final id in ['hm/typography', 'hm/epub2-ncx']) {
    test('$id: os 4 adaptadores somam os mesmos bytes do spine', () async {
      final file = books[id]!;
      final galley = GalleyAdapter();
      await galley.open(file.path);
      final spine = galley.spineLength;
      final bytes = await galley.readAllSpine();
      await galley.close();
      expect(spine, greaterThan(0));
      expect(bytes, greaterThan(0));
      for (final adapter in <ParserAdapter>[
        EpubPlusAdapter(),
        EpubProAdapter(),
      ]) {
        await adapter.open(file.path);
        expect(adapter.spineLength, spine, reason: adapter.name);
        expect(await adapter.readAllSpine(), bytes, reason: adapter.name);
        await adapter.close();
      }
      expect(await epubx('open', file), spine);
      expect(await epubx('open-eager', file), spine);
      expect(await epubx('read-all', file), bytes);
    });
  }

  test('epubx lê um recurso pelo caminho completo no arquivo', () async {
    final file = books['hm/typography']!;
    final book = await EpubBook.open(file.path);
    final path = book.spine.items.first.item.path;
    final expected = (await book.resource(path)).length;
    await book.close();
    expect(await epubx('read-one', file, resource: path), expected);
  });
}
