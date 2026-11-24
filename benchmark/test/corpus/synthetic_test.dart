import 'dart:io';

import 'package:galley/galley.dart';
import 'package:galley_benchmark/src/corpus/synthetic.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('galley_syn_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('constantes de tamanho', () {
    expect(kSynthetic50MiB, 52428800);
    expect(kSynthetic300MiB, 314572800);
  });

  test('5 MiB: tamanho ±5%, abre e o spine tem 200 itens', () async {
    const target = 5 * 1024 * 1024;
    final file = await writeSyntheticBook(
      '${tmp.path}/a.epub',
      targetBytes: target,
    );
    final size = file.lengthSync();
    expect(size, target);
    final book = await EpubBook.open(file.path);
    expect(book.spine.items, hasLength(200));
    expect(
      book.diagnostics.where((d) => d.severity == DiagnosticSeverity.error),
      isEmpty,
    );
    final first = book.spine.items.first;
    final text = await book.resourceText(first.item.path);
    expect(text, contains('<html'));
    await book.close();
  });

  test('é determinístico byte a byte', () async {
    final a = await writeSyntheticBook(
      '${tmp.path}/a.epub',
      targetBytes: 2 * 1024 * 1024,
      chapters: 20,
    );
    final b = await writeSyntheticBook(
      '${tmp.path}/b.epub',
      targetBytes: 2 * 1024 * 1024,
      chapters: 20,
    );
    expect(a.readAsBytesSync(), b.readAsBytesSync());
  });

  test('alvo pequeno demais lança ArgumentError', () {
    expect(
      () => writeSyntheticBook('${tmp.path}/c.epub', targetBytes: 1000),
      throwsArgumentError,
    );
  });

  test(
    'streaming: pico de RSS cresce menos de 64 MiB (livro de 100 MiB)',
    () async {
      final before = ProcessInfo.maxRss;
      final file = await writeSyntheticBook(
        '${tmp.path}/big.epub',
        targetBytes: 100 * 1024 * 1024,
      );
      final growth = ProcessInfo.maxRss - before;
      expect(file.lengthSync(), closeTo(100 * 1024 * 1024, 5 * 1024 * 1024));
      expect(growth, lessThan(64 * 1024 * 1024));
    },
  );
}
