// ignore_for_file: implementation_imports

import 'dart:io';

import 'package:galley/src/core/diagnostics/diagnostic_sink.dart';
import 'package:galley/src/features/style/data/stylesheet_builder.dart';
import 'package:galley_benchmark/src/catalog.dart';
import 'package:galley_benchmark/src/modes/instructions.dart';
import 'package:galley_benchmark/src/modes/build.dart';
import 'package:galley_benchmark/src/suites/document_suites.dart';
import 'package:galley_benchmark/src/suites/style_suites.dart';
import 'package:test/test.dart';

/// Formato dos ids do catálogo (o mesmo que o `bench-pr-upload` valida).
final _idFormat = RegExp(r'^[a-z0-9][a-z0-9/._-]{0,127}$');

/// Meta da spec: o `restyle` custa no máximo 1/5 do estilo completo.
const double kMinFullOverRestyle = 5.0;

void main() {
  final ids = <String>[
    'style/parse-sheet-256kib',
    'style/full-large-1mib',
    'style/restyle-large-1mib',
    'style/match-descendant-heavy',
    for (final b in kHandmadeSpineBooks) 'style/spine-hm-$b',
  ];

  test('os ids de estilo existem no catálogo, são únicos e bem formados', () {
    final all = [for (final b in Catalog.all()) b.id];
    expect(all.toSet().length, all.length);
    expect(all, containsAll(ids));
    for (final id in ids) {
      expect(_idFormat.hasMatch(id), isTrue, reason: id);
    }
    expect(all.any((i) => i.startsWith('style/spine-hm-malformed')), isFalse);
  });

  test('kHandmadeSpineBooks são os livros hm/* bem formados', () {
    expect(kHandmadeSpineBooks, hasLength(10));
    expect(kHandmadeSpineBooks, contains('publisher-css'));
    expect(kHandmadeSpineBooks.any((b) => b.startsWith('malformed')), isFalse);
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

  group('geradores de CSS', () {
    test('a folha de editora tem ~40 KiB e é determinística', () {
      final css = buildPublisherCss();
      expect(buildPublisherCss(), css);
      expect(css.length, inInclusiveRange(40 * 1024, 44 * 1024));
      for (final needle in [
        '@font-face',
        '@media',
        '@page',
        ' > ',
        ' + ',
        '#s',
        'line-height: 1.5 !important',
        'text-align: left !important',
        'width: 90% !important',
      ]) {
        expect(css, contains(needle), reason: needle);
      }
    });

    test('a folha grande tem o tamanho pedido e é determinística', () {
      final css = buildLargeCss(kLargeCssBytes);
      expect(css.length, greaterThanOrEqualTo(kLargeCssBytes));
      expect(buildLargeCss(kLargeCssBytes), css);
    });

    test('a folha de editora é lida sem diagnósticos de erro', () {
      final sink = CollectingDiagnosticSink();
      final sheet = buildStyleSheet(
        buildPublisherCss(),
        path: 'OEBPS/estilo.css',
        fontPrefix: 'gf0-',
        sink: sink,
      );
      expect(sheet.rules.length, greaterThan(200));
      expect(sheet.fontFaces, hasLength(3));
      expect(sink.diagnostics, isEmpty);
    });

    test('a folha descendente tem as regras pedidas, todas distintas', () {
      final css = buildDescendantCss(kDescendantRules);
      final lines = css.trim().split('\n');
      expect(lines, hasLength(kDescendantRules));
      expect(
        lines.map((l) => l.split(' {').first).toSet().length,
        kDescendantRules,
      );
    });
  });

  // Registro permanente da meta da spec (§ desempenho): o `restyle` precisa
  // ser pelo menos 5× mais barato que o estilo completo (casamento +
  // um `restyle`) do mesmo capítulo, contra um `restyle`. Conta instruções (determinístico, não
  // tempo de parede); `slow` porque compila o `bench_runner` e roda o
  // contador (perf ou Valgrind) 4 vezes.
  test(
    'restyle-large-1mib custa no máximo 1/5 de full-large-1mib (instruções)',
    tags: ['slow'],
    () async {
      final work = Directory.systemTemp.createTempSync('galley-style-ratio-');
      addTearDown(() => work.deleteSync(recursive: true));
      final exe = await compileRunner(
        checkout: Directory('..'),
        outPath: '${work.path}/runner',
      );
      final counter = Platform.environment['GALLEY_COUNTER'] == 'valgrind'
          ? Counter.valgrind
          : Counter.perf;
      Future<int> count(String id) async => (await countInstructions(
        exe,
        id,
        counter,
        workingDirectory: Directory('.'),
      )).perIteration;
      final int full;
      final int restyle;
      try {
        full = await count('style/full-large-1mib');
        restyle = await count('style/restyle-large-1mib');
      } on CounterUnavailable catch (e) {
        markTestSkipped('contador indisponível: $e');
        return;
      }
      final ratio = full / restyle;
      expect(
        ratio,
        greaterThanOrEqualTo(kMinFullOverRestyle),
        reason: 'full=$full restyle=$restyle razão=$ratio (meta ≥ 5)',
      );
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
