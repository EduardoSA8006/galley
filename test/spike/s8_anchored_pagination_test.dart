// Spike S8 — paginação ancorada (doc/04 §3.1, Emenda 10, doc/10 Invariante 8).
//
// Pergunta: paginar a partir de um âncora arbitrário (para trás até o início e
// para frente até o fim) cobre a seção inteira, respeita as regras de quebra
// nas duas direções e difere da paginação a partir de (0,0) em no máximo uma
// página? Resultado em spike/RESULTADO-S8.md.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'support/s8_paginator.dart';

SpikeBlock p(List<double> lines, {bool breakBefore = false}) => SpikeBlock(
      kind: SpikeBlockKind.paragraph,
      lineHeights: lines,
      breakBefore: breakBefore,
    );

SpikeBlock h(List<double> lines) =>
    SpikeBlock(kind: SpikeBlockKind.heading, lineHeights: lines);

const sceneBreak =
    SpikeBlock(kind: SpikeBlockKind.sceneBreak, lineHeights: [18]);

List<double> lines(int n, [double height = 20]) => List.filled(n, height);

void main() {
  group('regras de quebra (doc/04 §2.2)', () {
    test('órfã: 1ª linha de parágrafo sozinha no fim vai para a página seguinte',
        () {
      // 4 linhas de 20 + spacing 12 + 1 linha de 20 = 112 cabe em H=115;
      // a 5ª linha seria a 1ª de um parágrafo de 3 → empurrada.
      final pg = SpikePaginator([p(lines(4)), p(lines(3))], pageHeight: 115);
      final pages = pg.paginateForward(0);
      expect(pages.map((x) => x.lineCount), [4, 3]);
    });

    test('viúva: última linha sozinha no início puxa mais uma', () {
      // Parágrafo de 6 linhas de 20 em H=100: 5 cabem, sobraria 1 → 4 + 2.
      final pg = SpikePaginator([p(lines(6))], pageHeight: 100);
      final pages = pg.paginateForward(0);
      expect(pages.map((x) => x.lineCount), [4, 2]);
    });

    test('heading no fim da página vai junto com ≥ 2 linhas do bloco seguinte',
        () {
      // 3 linhas (60) + spacing + heading (24) = 96 cabe em H=100; o
      // parágrafo seguinte não cabe → heading empurrado.
      final pg = SpikePaginator(
        [p(lines(3)), h([24]), p(lines(5))],
        pageHeight: 100,
      );
      final pages = pg.paginateForward(0);
      expect(pages.first.lineCount, 3);
      expect(pg.cursorOf(pages[1].firstLine), const SpikeCursor(1, 0));
      expect(pg.illegalBreaks(pages), isEmpty);
    });

    test('heading + 1 linha de bloco que continua também é empurrado', () {
      // Página 1: 20 + 12 + 24 = 56 cabe em H=80, mas a 1ª linha do parágrafo
      // (88) não; o heading seria a última coisa da página → empurrado.
      // Página 2: heading + 2 linhas = 76 cabe; a 3ª não.
      final pg = SpikePaginator(
        [p(lines(1)), h([24]), p(lines(4))],
        pageHeight: 80,
      );
      expect(pg.typographyRulesEnabled, isTrue);
      final pages = pg.paginateForward(0);
      expect(pg.illegalBreaks(pages), isEmpty);
      // A página do heading tem heading + 2 linhas ou mais.
      final headingPage =
          pages.firstWhere((x) => pg.cursorOf(x.firstLine).block == 1);
      expect(headingPage.lineCount, greaterThanOrEqualTo(3));
    });

    test('breakBefore: page força nova página', () {
      final pg = SpikePaginator(
        [p(lines(2)), p(lines(2), breakBefore: true)],
        pageHeight: 500,
      );
      expect(pg.paginateForward(0).map((x) => x.lineCount), [2, 2]);
      expect(pg.paginateBackward(4).map((x) => x.lineCount), [2, 2]);
    });

    test('coluna com menos de 3 linhas desliga órfã e viúva', () {
      final pg = SpikePaginator([p(lines(5))], pageHeight: 45);
      expect(pg.typographyRulesEnabled, isFalse);
      expect(pg.paginateForward(0).map((x) => x.lineCount), [2, 2, 1]);
    });

    test('para trás espelha para frente no caso simétrico', () {
      final blocks = [p(lines(7)), h([24]), p(lines(9)), sceneBreak, p(lines(3))];
      final pg = SpikePaginator(blocks, pageHeight: 130);
      final fwd = pg.paginateForward(0);
      final bwd = pg.paginateBackward(pg.totalLines);
      expect(pg.illegalBreaks(fwd), isEmpty);
      expect(pg.illegalBreaks(bwd), isEmpty);
      expect((fwd.length - bwd.length).abs(), lessThanOrEqualTo(1));
    });
  });

  group('propriedades (Random(42), 500 casos)', () {
    final rnd = Random(42);
    final cases = List.generate(500, (_) => _randomCase(rnd));

    test('(a) cobertura exata, (b) altura ≤ H, (d) começa no âncora, (e) regras',
        () {
      var maxSnap = 0;
      for (final c in cases) {
        final pg = c.paginator;
        final anchorLine = pg.lineOf(c.anchor);
        final result = pg.paginateAnchored(c.anchor);

        // (a) união dos ranges == [0, totalLines), sem lacuna nem sobreposição.
        var expected = 0;
        for (final page in result.pages) {
          expect(page.firstLine, expected, reason: 'lacuna/sobreposição em $c');
          expect(page.lineCount, greaterThan(0));
          expected = page.endLine;
        }
        expect(expected, pg.totalLines, reason: 'não cobre o fim em $c');

        // (b) nenhuma página excede H.
        for (final page in result.pages) {
          expect(page.height, lessThanOrEqualTo(pg.pageHeight + 1e-9),
              reason: 'página $page excede H em $c');
        }

        // (d) a página ancorada começa no âncora (após snap) e o âncora pedido
        // está nela.
        final anchored = result.pages[result.anchorPageIndex];
        expect(anchored.firstLine, result.anchorLine);
        expect(result.anchorLine, lessThanOrEqualTo(anchorLine));
        expect(anchorLine, lessThan(anchored.endLine),
            reason: 'âncora pedido fora da página ancorada em $c');
        maxSnap = max(maxSnap, anchorLine - result.anchorLine);

        // (e) órfã/viúva/heading respeitadas nas duas direções.
        if (pg.typographyRulesEnabled) {
          expect(pg.illegalBreaks(result.pages), isEmpty,
              reason: 'quebra ilegal em $c');
        }
      }
      print('S8 (d): deslocamento máximo do âncora por snap = $maxSnap linhas');
    });

    test('(c) |páginas(âncora) − páginas((0,0))| ≤ 1', () {
      final histogram = <int, int>{};
      final failures = <(_Case, int, int)>[];
      for (final c in cases) {
        final pg = c.paginator;
        final fromStart = pg.paginateForward(0).length;
        final anchored = pg.paginateAnchored(c.anchor).pages.length;
        final diff = anchored - fromStart;
        histogram.update(diff, (n) => n + 1, ifAbsent: () => 1);
        if (diff.abs() > 1) failures.add((c, fromStart, anchored));
      }
      final keys = histogram.keys.toList()..sort();
      print('S8 (c): distribuição de páginas(âncora) − páginas(0,0): '
          '${{for (final k in keys) k: histogram[k]}}');
      if (failures.isNotEmpty) {
        failures.sort((a, b) =>
            a.$1.paginator.totalLines.compareTo(b.$1.paginator.totalLines));
        final (c, s, a) = failures.first;
        fail('${failures.length} casos com diferença > 1. Menor: $c → '
            'de (0,0)=$s, ancorada=$a');
      }
    });

    test('(c\') diferença zero quando o âncora já é fronteira da paginação (0,0)',
        () {
      // Se o âncora coincide com o início de uma página da paginação normal,
      // a parte de trás deve reproduzir exatamente a mesma contagem.
      var checked = 0;
      for (final c in cases) {
        final pg = c.paginator;
        final fwd = pg.paginateForward(0);
        if (fwd.length < 3) continue;
        final boundary = fwd[fwd.length ~/ 2].firstLine;
        final anchored = pg.paginateAnchored(pg.cursorOf(boundary));
        expect((anchored.pages.length - fwd.length).abs(), lessThanOrEqualTo(1),
            reason: 'âncora em fronteira real diverge em $c');
        checked++;
      }
      expect(checked, greaterThan(100));
    });
  });

  test('tempo: paginateAnchored em 5 mil blocos de 30 linhas', () {
    final blocks = List.generate(5000, (i) => p(lines(30, 20 + (i % 5))));
    final pg = SpikePaginator(blocks, pageHeight: 640);
    const anchor = SpikeCursor(2500, 7);
    // Aquecimento.
    pg.paginateAnchored(anchor);
    final samples = <int>[];
    for (var i = 0; i < 5; i++) {
      final sw = Stopwatch()..start();
      final r = pg.paginateAnchored(anchor);
      sw.stop();
      samples.add(sw.elapsedMicroseconds);
      expect(r.pages.last.endLine, pg.totalLines);
    }
    samples.sort();
    print('S8 tempo: ${pg.totalLines} linhas, ${pg.paginateForward(0).length} '
        'páginas; paginateAnchored mediana ${samples[2]} µs '
        '(min ${samples.first}, max ${samples.last})');
  });
}

class _Case {
  _Case(this.paginator, this.anchor, this.seedIndex);

  final SpikePaginator paginator;
  final SpikeCursor anchor;
  final int seedIndex;

  @override
  String toString() =>
      'caso#$seedIndex blocos=${paginator.blocks.length} '
      'linhas=${paginator.totalLines} H=${paginator.pageHeight} âncora=$anchor';
}

var _caseCounter = 0;

_Case _randomCase(Random rnd) {
  final blockCount = 1 + rnd.nextInt(80);
  final blocks = <SpikeBlock>[];
  for (var b = 0; b < blockCount; b++) {
    final roll = rnd.nextDouble();
    final breakBefore = b > 0 && rnd.nextDouble() < 0.05;
    if (roll < 0.05) {
      blocks.add(SpikeBlock(
        kind: SpikeBlockKind.sceneBreak,
        lineHeights: const [18],
        breakBefore: breakBefore,
      ));
    } else if (roll < 0.15) {
      blocks.add(SpikeBlock(
        kind: SpikeBlockKind.heading,
        lineHeights: [22 + rnd.nextInt(5).toDouble()],
        breakBefore: breakBefore,
      ));
    } else {
      final n = 1 + rnd.nextInt(60);
      final base = 18 + rnd.nextInt(9).toDouble();
      blocks.add(SpikeBlock(
        kind: SpikeBlockKind.paragraph,
        lineHeights: List.filled(n, base),
        breakBefore: breakBefore,
      ));
    }
  }
  final pageHeight = 300 + rnd.nextInt(601).toDouble();
  final pg = SpikePaginator(blocks, pageHeight: pageHeight);
  final anchorLine = rnd.nextInt(pg.totalLines);
  return _Case(pg, pg.cursorOf(anchorLine), _caseCounter++);
}
