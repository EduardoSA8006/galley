import 'dart:io';

import 'package:galley_benchmark/src/competitors/css_adapter.dart';
import 'package:galley_benchmark/src/modes/compare.dart';
import 'package:galley_benchmark/src/suites/style_suites.dart';
import 'package:test/test.dart';

import 'support/mini_epub.dart';

const _small = '''
@charset "utf-8";
@font-face { font-family: "A"; src: url(a.otf); }
body { margin: 0; font-size: 100%; }
p.texto > em, h1 + p { color: #123; line-height: 1.4 !important; }
@media (min-width: 300px) { p { text-indent: 1em; } }
''';

const _chapter =
    '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE html>\n'
    '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>c</title>'
    '<link rel="stylesheet" href="s/a.css"/></head><body><p>x</p></body>'
    '</html>';

void main() {
  late Directory tmp;
  setUpAll(() => tmp = Directory.systemTemp.createTempSync('galley-css-test-'));
  tearDownAll(() => tmp.deleteSync(recursive: true));

  final parsers = <CssParser>[GalleyCssParser(), CsslibParser()];

  test('os nomes são galley-css e csslib', () {
    expect([for (final p in parsers) p.name], cssAdapterNames);
  });

  for (final parser in parsers) {
    group(parser.name, () {
      test('lê uma folha pequena com checksum > 0', () {
        expect(parser.parseAll([_small]), greaterThan(0));
      });

      test('lê as folhas text/css de um mini-EPUB com checksum > 0', () async {
        final file = File('${tmp.path}/${parser.name}.epub')
          ..writeAsBytesSync(
            buildMiniEpub(
              [_chapter, _chapter],
              styleSheets: {'s/a.css': _small, 's/b.css': 'p { margin: 0 }'},
            ),
          );
        final sheets = await loadStyleSheets(file.path);
        expect(sheets, hasLength(2));
        expect(sheets, contains(_small));
        expect(parser.parseAll(sheets), greaterThan(0));
      });

      test('runCssMeasure imprime ns, rss e checksum', () async {
        final file = File('${tmp.path}/${parser.name}.css')
          ..writeAsStringSync(buildLargeCss(32 * 1024));
        final out = StringBuffer();
        final code = await runCssMeasure(
          parser,
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
    });
  }

  test('runCssMeasure rejeita medida desconhecida e arquivo ausente', () async {
    final err = StringBuffer();
    expect(
      await runCssMeasure(
        GalleyCssParser(),
        'open',
        'x.css',
        out: StringBuffer(),
        err: err,
      ),
      64,
    );
    expect(
      await runCssMeasure(
        GalleyCssParser(),
        'parse',
        '/nao/existe.css',
        out: StringBuffer(),
        err: err,
      ),
      70,
    );
  });

  test('buildMiniEpub sem styleSheets continua igual ao uso antigo', () {
    expect(buildMiniEpub([_chapter]), buildMiniEpub([_chapter]));
  });

  test('a comparação de CSS gera os ids compare/<leitor>/parse/<livro>', () {
    final cells = [
      for (final a in cssAdapterNames)
        CompareCell(
          adapter: a,
          book: 'hm/publisher-css',
          metric: documentMetric,
          wallNs: a == 'csslib' ? 4e6 : 2e6,
          peakRss: 1048576,
          checksum: 5,
        ),
    ];
    expect(
      compareBmf(cells).keys,
      containsAll([
        'compare/galley-css/parse/hm/publisher-css',
        'compare/csslib/parse/hm/publisher-css',
      ]),
    );
    expect(
      renderCssCompareReport(cells, runs: 5),
      contains('| `hm/publisher-css` | 2.00 | 4.00 | 2.00 | 1.0 | 1.0 |'),
    );
  });
}
