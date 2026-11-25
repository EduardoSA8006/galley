import 'dart:io';

import 'package:galley_benchmark/src/catalog.dart';
import 'package:galley_benchmark/src/competitors/document_adapter.dart';
import 'package:galley_benchmark/src/corpus/handmade.dart';
import 'package:galley_benchmark/src/modes/compare.dart';
import 'package:galley_benchmark/src/suites/document_suites.dart';
import 'package:test/test.dart';

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

void main() {
  final ids = <String>[
    'document/build-large-1mib',
    'document/build-dense-256kib',
    'document/query-id-class',
    'document/build-tolerant',
    'document/transfer-large',
    for (final b in _books) 'document/parse-spine-hm-$b',
  ];

  test('os ids de documento existem no catálogo e são únicos', () {
    final all = [for (final b in Catalog.all()) b.id];
    expect(all.toSet().length, all.length);
    expect(all, containsAll(ids));
    expect(
      all.any((i) => i.startsWith('document/parse-spine-hm-malformed')),
      isFalse,
    );
  });

  for (final id in ids) {
    test('$id: 2 execuções dão o mesmo checksum diferente de 0', () async {
      final bench = Catalog.byId(id);
      await bench.setUp();
      try {
        final first = await bench.run();
        final second = await bench.run();
        expect(second, first);
        expect(first, isNot(0));
      } finally {
        await bench.tearDown();
      }
    }, timeout: const Timeout(Duration(minutes: 1)));
  }

  test('o XHTML de 1 MiB é determinístico e tem o tamanho pedido', () {
    final a = buildLargeXhtml(kLargeXhtmlBytes);
    final b = buildLargeXhtml(kLargeXhtmlBytes);
    expect(a.length, greaterThanOrEqualTo(kLargeXhtmlBytes));
    expect(a, b);
  });

  test('o XHTML denso é determinístico e tem mais elementos por byte', () {
    final dense = buildDenseXhtml(kDenseXhtmlBytes);
    expect(buildDenseXhtml(kDenseXhtmlBytes), dense);
    expect(dense.length, greaterThanOrEqualTo(kDenseXhtmlBytes));
    final large = buildLargeXhtml(kDenseXhtmlBytes);
    final parser = GalleyDocumentParser();
    expect(
      parser.parseAll([dense]) / dense.length,
      greaterThan(2 * parser.parseAll([large]) / large.length),
    );
  });

  group('adaptadores de documento', () {
    test('galley-document e xml-dom contam os mesmos elementos', () async {
      final corpus = await buildHandmadeCorpus();
      final dir = Directory.systemTemp.createTempSync('galley-doc-test-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/tables.epub')
        ..writeAsBytesSync(corpus['hm/tables']!);
      final galley = await loadDocuments(file.path);
      expect(galley, isNotEmpty);
      final ours = GalleyDocumentParser().parseAll(galley);
      final theirs = XmlDomParser().parseAll(galley);
      expect(ours, greaterThan(0));
      expect(theirs, ours);
    });

    test('runDocumentMeasure imprime ns, rss e checksum', () async {
      final dir = Directory.systemTemp.createTempSync('galley-doc-test-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/a.xhtml')
        ..writeAsBytesSync(buildLargeXhtml(64 * 1024));
      final out = StringBuffer();
      final code = await runDocumentMeasure(
        XmlDomParser(),
        'parse',
        file.path,
        out: out,
        err: StringBuffer(),
      );
      expect(code, 0);
      expect(
        out.toString(),
        allOf(contains('ns='), contains('rss='), contains('checksum=')),
      );
    });

    test(
      'a comparação de documentos gera os ids compare/<parser>/parse/<doc>',
      () {
        final cells = [
          for (final a in documentAdapterNames)
            CompareCell(
              adapter: a,
              book: 'hm/tables',
              metric: documentMetric,
              wallNs: 2e6,
              peakRss: 1048576,
              checksum: 5,
            ),
        ];
        expect(
          compareBmf(cells).keys,
          containsAll([
            'compare/galley-document/parse/hm/tables',
            'compare/xml-dom/parse/hm/tables',
          ]),
        );
        expect(
          renderDocumentCompareReport(cells, runs: 5),
          contains('| `hm/tables` | 2.00 | 2.00 | 1.00 |'),
        );
      },
    );
  });
}
