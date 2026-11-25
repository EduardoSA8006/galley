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

  test('5 MiB: tamanho exato, abre e o spine tem 200 itens', () async {
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
    'streaming: pico de RSS não cresce com o tamanho do livro (20 × 100 MiB)',
    () async {
      // A sonda roda compilada AOT, num processo próprio: em JIT o pico
      // incluiria a compilação do gerador e o crescimento do heap, que
      // variam entre versões do Dart. O que define streaming é a memória não
      // acompanhar o tamanho do livro: sem streaming, 100 MiB custaria ~80
      // MiB a mais que 20 MiB.
      final exe = '${tmp.path}/rss_probe';
      final compiled = await Process.run(Platform.resolvedExecutable, [
        'compile',
        'exe',
        'test/corpus/rss_probe.dart',
        '-o',
        exe,
      ]);
      expect(compiled.exitCode, 0, reason: '${compiled.stderr}');

      Future<({int before, int after, int size})> probe(int mib) async {
        final out = '${tmp.path}/book-$mib.epub';
        final r = await Process.run(exe, [out, '${mib * 1024 * 1024}']);
        expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
        final values = {
          for (final m in RegExp(
            r'^(before|after)=(\d+)$',
            multiLine: true,
          ).allMatches(r.stdout as String))
            m[1]!: int.parse(m[2]!),
        };
        expect(values.keys, {'before', 'after'}, reason: '${r.stdout}');
        final size = File(out).lengthSync();
        File(out).deleteSync();
        return (before: values['before']!, after: values['after']!, size: size);
      }

      final small = await probe(20);
      final big = await probe(100);
      expect(big.size, 100 * 1024 * 1024);
      // Folga de 16 MiB para variação do coletor de lixo.
      expect(big.after - small.after, lessThan(16 * 1024 * 1024));
      expect(big.after - big.before, lessThan(64 * 1024 * 1024));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
