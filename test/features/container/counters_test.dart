import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/features/container/data/zip/byte_source.dart';
import 'package:galley/src/features/container/domain/epub_book.dart';

import '../../support/counting_byte_source.dart';
import '../../support/epub_builder.dart';
import '../../support/synthetic_epub.dart';

// Limites congelados (ver a calibração no comentário de cada um).

/// Abrir o livro pequeno com um capítulo de 256 KiB incompressível (arquivo
/// de 263.434 bytes): medido em 66.656 bytes (11 leituras; o fim do zip e as
/// entradas de metadados, sem o capítulo); margem de ~25% (66.656 × 1,25 =
/// 83.320, arredondado para 84.000). Fica abaixo de um terço do arquivo, então
/// ler o livro inteiro ao abrir reprova.
const int _smallOpenLimit = 84000;

/// Abrir o sintético de 300 MiB: medido em 107.449 bytes (11 leituras); o
/// limite de 256 KiB (262.144 bytes) é fixado pelo spec, não derivado da
/// medição.
const int _heavyOpenLimit = 262144;

void main() {
  test('abrir um livro pequeno lê no máximo $_smallOpenLimit bytes, bem menos '
      'que o arquivo', () async {
    // Capítulo grande e incompressível: o arquivo fica muito maior que o
    // limite, então ler o livro inteiro ao abrir reprova este teste.
    final random = Random(42);
    final chapter = Uint8List.fromList(
      List.generate(256 * 1024, (_) => random.nextInt(256)),
    );
    final bytes = _smallBook(chapter: chapter);
    expect(bytes.length, greaterThan(3 * _smallOpenLimit));
    final source = CountingByteSource(MemoryByteSource(bytes));
    final book = await EpubBook.fromSource(source);
    try {
      expect(source.bytesRead, lessThanOrEqualTo(_smallOpenLimit));
    } finally {
      await book.close();
    }
  });

  test(
    'resource() lê só a entrada comprimida mais o cabeçalho local',
    () async {
      final body = utf8.encode('<p>${'texto ' * 500}</p>');
      final bytes = _smallBook(chapter: body);
      final source = CountingByteSource(MemoryByteSource(bytes));
      final book = await EpubBook.fromSource(source);
      final before = source.bytesRead;
      final data = await book.resource('OEBPS/ch1.xhtml');
      final delta = source.bytesRead - before;
      final compressed = ZLibEncoder(raw: true).convert(body).length;
      expect(data, body);
      expect(
        delta,
        lessThanOrEqualTo(compressed + 30 + 'OEBPS/ch1.xhtml'.length + 0 + 64),
      );
      await book.close();
    },
  );

  group('livro de 300 MiB', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('galley_heavy'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('abrir lê no máximo $_heavyOpenLimit bytes', () async {
      final f = File('${tmp.path}/big.epub');
      await writeSyntheticEpubTo(f, targetBytes: 300 * 1024 * 1024);
      final source = CountingByteSource(await FileByteSource.open(f.path));
      final book = await EpubBook.fromSource(source);
      // ignore: avoid_print
      print(
        'MEDIDO abrir 300MiB: ${source.bytesRead} bytes em ${source.reads} leituras',
      );
      expect(source.bytesRead, lessThanOrEqualTo(_heavyOpenLimit));
      await book.close();
    }, tags: ['heavy']);
  });
}

Uint8List _smallBook({List<int>? chapter}) => buildEpub({
  'OEBPS/content.opf': opf3(
    manifest:
        '<item id="n" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>'
        '<item id="c1" href="ch1.xhtml" media-type="application/xhtml+xml"/>',
    spine: '<itemref idref="c1"/>',
  ),
  'OEBPS/nav.xhtml': '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body><nav epub:type="toc"><ol><li><a href="ch1.xhtml">C1</a></li></ol></nav></body></html>',
  'OEBPS/ch1.xhtml': chapter ?? utf8.encode('<p>oi</p>'),
});
