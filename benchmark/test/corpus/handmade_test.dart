import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:galley/galley.dart';
import 'package:galley_benchmark/src/corpus/handmade.dart';
import 'package:test/test.dart';

const _ids = <String>[
  'hm/typography',
  'hm/publisher-css',
  'hm/tables',
  'hm/notes',
  'hm/images',
  'hm/cjk',
  'hm/rtl-bidi',
  'hm/fonts-idpf',
  'hm/fonts-adobe',
  'hm/epub2-ncx',
  'hm/malformed-no-mimetype',
  'hm/malformed-case-mismatch',
];

/// Abre [bytes], lê todos os recursos do manifest e devolve o livro.
Future<EpubBook> _openAndTouch(Uint8List bytes) async {
  final book = await EpubBook.fromBytes(bytes);
  for (final item in book.manifest.values) {
    await book.resource(item.path);
  }
  return book;
}

void main() {
  late Map<String, Uint8List> corpus;

  setUpAll(() async {
    corpus = await buildHandmadeCorpus();
  });

  test('contém exatamente os 12 ids esperados', () {
    expect(corpus.keys.toSet(), _ids.toSet());
  });

  test('é determinístico: mesmos sha256 em duas execuções', () async {
    final again = await buildHandmadeCorpus();
    for (final id in _ids) {
      expect(
        sha256.convert(again[id]!),
        sha256.convert(corpus[id]!),
        reason: id,
      );
    }
  });

  for (final id in _ids.where((i) => !i.startsWith('hm/malformed'))) {
    test('$id abre sem diagnóstico de erro', () async {
      final book = await _openAndTouch(corpus[id]!);
      final errors = book.diagnostics
          .where((d) => d.severity == DiagnosticSeverity.error)
          .toList();
      expect(errors, isEmpty);
      expect(book.spine.items, isNotEmpty);
      await book.close();
    });
  }

  test('hm/malformed-no-mimetype emite container.mimetypeMissing', () async {
    final book = await _openAndTouch(corpus['hm/malformed-no-mimetype']!);
    expect(
      book.diagnostics.map((d) => d.code),
      contains(DiagnosticCodes.mimetypeMissing),
    );
    await book.close();
  });

  test('hm/malformed-case-mismatch emite resource.caseMismatch', () async {
    final book = await _openAndTouch(corpus['hm/malformed-case-mismatch']!);
    expect(
      book.diagnostics.map((d) => d.code),
      contains(DiagnosticCodes.resourceCaseMismatch),
    );
    await book.close();
  });

  test('fontes ofuscadas voltam desofuscadas (cabeçalho OTTO)', () async {
    for (final id in ['hm/fonts-idpf', 'hm/fonts-adobe']) {
      final book = await _openAndTouch(corpus[id]!);
      final font = book.manifest.values.firstWhere(
        (i) => i.path.endsWith('.otf'),
      );
      final bytes = await book.resource(font.path);
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'OTTO', reason: id);
      await book.close();
    }
  });

  test('epub2 tem versão 2 e sumário NCX', () async {
    final book = await _openAndTouch(corpus['hm/epub2-ncx']!);
    expect(book.version, EpubVersion.epub2);
    expect(book.navigation.toc, isNotEmpty);
    await book.close();
  });

  test('rtl-bidi tem progressão de página rtl', () async {
    final book = await _openAndTouch(corpus['hm/rtl-bidi']!);
    expect(book.spine.direction, PageProgressionDirection.rtl);
    await book.close();
  });
}
