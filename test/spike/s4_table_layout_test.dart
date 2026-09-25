// Spike S4 — layout de tabela (doc/04 §9, Emenda 12; doc/08 §2).
//
// Pergunta: o algoritmo de tabela de doc/04 §9 (min/max content por célula com
// `ui.Paragraph`, distribuição de colunas, colspan/rowspan, escala até 0.8×,
// rolagem horizontal como degradação declarada, linha como unidade de quebra,
// cabeçalho repetido) produz layouts corretos e a que custo?
//
// Roda em flutter_tester com a fonte FlutterTest (cada glifo tem avanço igual
// ao fontSize; altura de linha = fontSize). Os números impressos são copiados
// para spike/RESULTADO-S4.md.

import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'support/s4_table_layout.dart';

const _eps = 0.01;

CellModel c(String t, {int cs = 1, int rs = 1}) =>
    CellModel(t, colSpan: cs, rowSpan: rs);

CellModel th(String t, {int cs = 1, int rs = 1}) =>
    CellModel(t, colSpan: cs, rowSpan: rs, isHeader: true);

TableModel grid(List<List<CellModel>> rows) =>
    TableModel([for (final r in rows) RowModel(r)]);

double sumOf(Iterable<double> xs) => xs.fold(0.0, (a, b) => a + b);

ui.Paragraph _probe(String text) {
  final b =
      ui.ParagraphBuilder(
          ui.ParagraphStyle(fontSize: 10, fontFamily: 'FlutterTest'),
        )
        ..pushStyle(ui.TextStyle(fontSize: 10, fontFamily: 'FlutterTest'))
        ..addText(text);
  return b.build();
}

bool _breakable(String ch) => ch == ' ' || ch == '\n' || ch == '-';

/// Quantas quebras de linha caem no meio de uma palavra (quebra por
/// caractere). Zero significa que o min-content foi respeitado no layout final.
int charBreaks(TableLayout layout) {
  var count = 0;
  for (final cell in layout.cells) {
    final p = cell.paragraph!;
    final text = cell.cell.text;
    var off = 0;
    while (off < text.length) {
      final b = p.getLineBoundary(ui.TextPosition(offset: off));
      if (b.end <= off) {
        off++;
        continue;
      }
      if (b.end < text.length &&
          !_breakable(text[b.end - 1]) &&
          !_breakable(text[b.end])) {
        count++;
      }
      off = b.end;
    }
  }
  return count;
}

String words(Random rnd, int n) => List.generate(
  n,
  (_) => String.fromCharCodes(
    List.generate(1 + rnd.nextInt(12), (_) => 97 + rnd.nextInt(26)),
  ),
).join(' ');

TableModel randomTable(Random rnd) {
  final cols = 1 + rnd.nextInt(8);
  final rows = 1 + rnd.nextInt(30);
  final header = rnd.nextBool();
  return TableModel([
    for (var r = 0; r < rows; r++)
      RowModel([
        for (var k = 0; k < cols; k++)
          CellModel(
            rnd.nextInt(20) == 0 ? '' : words(rnd, 1 + rnd.nextInt(40)),
            colSpan: rnd.nextInt(12) == 0 ? 2 + rnd.nextInt(3) : 1,
            rowSpan: rnd.nextInt(12) == 0
                ? (rnd.nextInt(6) == 0 ? 0 : 2 + rnd.nextInt(4))
                : 1,
            isHeader: header && r == 0,
          ),
      ]),
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('S4.0 o que layout(0) e layout(∞) devolvem', () {
    test('min-content: só minIntrinsicWidth após layout(∞) dá a palavra', () {
      // "defgh" é a palavra mais longa: 50 px. Max-content: 120 px.
      final p = _probe('abc defgh ij')
        ..layout(const ui.ParagraphConstraints(width: 0));
      final at0 = (p.minIntrinsicWidth, p.maxIntrinsicWidth, p.longestLine);
      final lines0 = p.computeLineMetrics().length;
      p.layout(const ui.ParagraphConstraints(width: double.infinity));
      final atInf = (p.minIntrinsicWidth, p.maxIntrinsicWidth, p.longestLine);
      print(
        'S4.0 layout(0): min=${at0.$1} max=${at0.$2} longest=${at0.$3} '
        'linhas=$lines0 width=${p.width}',
      );
      print(
        'S4.0 layout(∞): min=${atInf.$1} max=${atInf.$2} '
        'longest=${atInf.$3} width=${p.width}',
      );
      // layout(0): maxIntrinsic é o max-content (não a palavra), min/longest
      // são um glifo (quebra por caractere).
      expect(at0, (10.0, 120.0, 10.0));
      expect(lines0, 12 - 2, reason: '10 glifos visíveis, 1 por linha');
      // layout(∞) é aceito e dá as duas medidas de uma vez.
      expect(atInf, (50.0, 120.0, 120.0));
      expect(p.width, double.infinity);

      // Com quebra dura, maxIntrinsic após layout(0) soma as linhas duras.
      final q = _probe('x\ny long')
        ..layout(const ui.ParagraphConstraints(width: 0));
      final q0 = q.maxIntrinsicWidth;
      q.layout(const ui.ParagraphConstraints(width: double.infinity));
      print(
        'S4.0 "x\\ny long": maxIntrinsic após layout(0)=$q0, '
        'após layout(∞)=${q.maxIntrinsicWidth}, min=${q.minIntrinsicWidth}',
      );
      expect(q0, 80);
      expect(q.maxIntrinsicWidth, 60);
      expect(q.minIntrinsicWidth, 40);

      // minIntrinsicWidth depende da largura do último layout: com largura
      // menor que a palavra mais longa ele deixa de ser confiável.
      q.layout(const ui.ParagraphConstraints(width: 35));
      print('S4.0 "x\\ny long" após layout(35): min=${q.minIntrinsicWidth}');
      expect(q.minIntrinsicWidth, lessThan(40));
      p.dispose();
      q.dispose();
    });

    test('casos limite de medição', () {
      String fmt(double v) => v.abs() > 1e30 || (v != 0 && v.abs() < 1e-30)
          ? v.toStringAsExponential(3)
          : v.toString();
      for (final t in [
        '',
        ' ',
        'abc ',
        'Para­lele­pipedo',
        'https://exemplo.com/caminho/longo',
        '日本語のテキスト',
      ]) {
        final p = _probe(t)
          ..layout(const ui.ParagraphConstraints(width: double.infinity));
        print(
          'S4.0 [${t.replaceAll('­', '<SHY>')}] '
          'min=${fmt(p.minIntrinsicWidth)} max=${fmt(p.maxIntrinsicWidth)} '
          'longest=${fmt(p.longestLine)} h=${p.height}',
        );
        p.dispose();
      }
      final empty = _probe('')
        ..layout(const ui.ParagraphConstraints(width: double.infinity));
      expect(empty.longestLine, lessThan(-1e30), reason: '−FLT_MAX');
      expect(empty.height, 10, reason: 'parágrafo vazio tem uma linha');
      final shy = _probe('Para­lele­pipedo')
        ..layout(const ui.ParagraphConstraints(width: double.infinity));
      expect(shy.minIntrinsicWidth, 140, reason: 'SHY não entra no min');
      empty.dispose();
      shy.dispose();
    });
  });

  group('S4.1 distribuição (doc/04 §9 passo 3)', () {
    final simple = grid([
      [c('Nome'), c('Idade'), c('Cidade')],
      [c('Ana'), c('31'), c('Recife')],
      [c('Bruno'), c('7'), c('Belo Horizonte')],
    ]);

    test('1. 3×3 que cabe: colunas recebem colMax, sem escala', () {
      final l = layoutTable(simple, width: 400);
      print(
        'S4.1.1 colMin=${l.colMin} colMax=${l.colMax} '
        'widths=${l.colWidths}',
      );
      expect(l.colWidths, l.colMax);
      expect(l.colMax, [58, 58, 148]);
      expect(l.scale, 1);
      expect(l.overflow, isFalse);
      expect(l.width, lessThan(400), reason: 'sobra vai para a margem');
      expect(l.rowHeights, [18, 18, 18]);
      expect(charBreaks(l), 0);
      l.dispose();
    });

    test('2. ΣcolMin ≤ W < ΣcolMax: proporcional e ΣcolWidths == W', () {
      final t = grid([
        [c('Termo'), c('Definição'), c('Exemplo de uso')],
        [
          c('Idempotente'),
          c('Operação que aplicada duas vezes dá o mesmo resultado'),
          c('Chamar dispose duas vezes'),
        ],
        [c('Pura'), c('Sem efeito colateral'), c('Uma função soma')],
      ]);
      final probe = layoutTable(t, width: 1e6);
      final w = (probe.sumColMin + probe.sumColMax) / 2;
      probe.dispose();
      final l = layoutTable(t, width: w);
      print(
        'S4.1.2 ΣcolMin=${l.sumColMin} ΣcolMax=${l.sumColMax} W=$w '
        'widths=${l.colWidths.map((x) => x.toStringAsFixed(2)).toList()}',
      );
      expect(l.sumColMin, lessThanOrEqualTo(w));
      expect(l.sumColMax, greaterThan(w));
      expect(sumOf(l.colWidths), closeTo(w, _eps));
      final slack = w - l.sumColMin;
      final diff = l.sumColMax - l.sumColMin;
      for (var i = 0; i < l.columnCount; i++) {
        expect(l.colWidths[i], inInclusiveRange(l.colMin[i], l.colMax[i]));
        expect(
          l.colWidths[i],
          closeTo(
            l.colMin[i] + slack * (l.colMax[i] - l.colMin[i]) / diff,
            1e-9,
          ),
        );
      }
      expect(l.scale, 1);
      expect(charBreaks(l), 0);
      l.dispose();
    });

    test('3. ΣcolMin > W com pouca folga: escala em [0.8, 1) e cabe', () {
      final probe = layoutTable(simple, width: 1e6);
      final w = probe.sumColMin * 0.9;
      probe.dispose();
      final l = layoutTable(simple, width: w);
      print(
        'S4.1.3 ΣcolMin=${l.sumColMin} W=$w scale=${l.scale} '
        'Σwidths=${sumOf(l.colWidths)} rowHeights=${l.rowHeights}',
      );
      expect(l.scale, inInclusiveRange(0.8, 1.0));
      expect(l.scale, lessThan(1.0));
      expect(l.scale, closeTo(0.9, 1e-12));
      expect(l.overflow, isFalse);
      expect(sumOf(l.colWidths), closeTo(w, _eps));
      expect(l.diagnostics, isNot(contains(TableDiagnostic.tableOverflow)));
      expect(charBreaks(l), 0, reason: 'fonte escalada ainda cabe no min');

      // Escala por transformação: mesmo resultado, sem reconstruir parágrafos.
      final tr = layoutTable(
        simple,
        width: w,
        style: const TableStyle(scaleMode: ScaleMode.transform),
      );
      print(
        'S4.1.3 transform: rowHeights=${tr.rowHeights} '
        'builds=${tr.paragraphBuilds} (rebuildFont: ${l.paragraphBuilds})',
      );
      expect(tr.colWidths, l.colWidths);
      for (var r = 0; r < 3; r++) {
        expect(tr.rowHeights[r], closeTo(l.rowHeights[r], 1e-9));
      }
      expect(tr.paragraphBuilds, 9);
      expect(l.paragraphBuilds, 18);
      expect(charBreaks(tr), 0);
      tr.dispose();
      l.dispose();
    });

    test('4. ΣcolMin > W muito: scale 0.8, overflow, largura 0.8×ΣcolMin', () {
      final probe = layoutTable(simple, width: 1e6);
      final w = probe.sumColMin * 0.5;
      probe.dispose();
      final l = layoutTable(simple, width: w);
      print(
        'S4.1.4 ΣcolMin=${l.sumColMin} W=$w scale=${l.scale} '
        'largura=${l.width} overflow=${l.overflow}',
      );
      expect(l.scale, 0.8);
      expect(l.overflow, isTrue);
      expect(l.width, closeTo(0.8 * l.sumColMin, _eps));
      expect(l.width, greaterThan(w));
      expect(l.diagnostics, contains(TableDiagnostic.tableOverflow));
      expect(charBreaks(l), 0);
      l.dispose();
    });

    test('leitura literal de doc/04 §9: min == max, regime 2 some', () {
      final t = grid([
        [c('Operação que aplicada duas vezes dá o mesmo'), c('ok')],
      ]);
      final lit = layoutTable(
        t,
        width: 200,
        style: const TableStyle(probe: MinContentProbe.docLiteral),
      );
      final fix = layoutTable(t, width: 200);
      print(
        'S4.1.L literal: colMin=${lit.colMin} colMax=${lit.colMax} '
        'scale=${lit.scale} overflow=${lit.overflow}',
      );
      print(
        'S4.1.L corrigido: colMin=${fix.colMin} colMax=${fix.colMax} '
        'scale=${fix.scale} widths=${fix.colWidths}',
      );
      expect(lit.colMin, lit.colMax, reason: 'maxIntrinsic após layout(0)');
      expect(lit.overflow, isTrue);
      expect(fix.overflow, isFalse);
      expect(fix.scale, 1);
      expect(sumOf(fix.colWidths), closeTo(200, _eps));
      lit.dispose();
      fix.dispose();
    });
  });

  group('S4.2 spans', () {
    test('5. colspan=2 no cabeçalho cobre as duas colunas sem inflar', () {
      final t = grid([
        [th('Cabeçalho da tabela', cs: 2), th('X')],
        [c('uma frase bem comprida aqui'), c('b'), c('c')],
        [c('curta'), c('d'), c('e')],
      ]);
      for (final mode in SpanDistribution.values) {
        final l = layoutTable(t, width: 1000, style: TableStyle(spans: mode));
        final span = l.cells.first;
        final r = l.cellRects.first;
        final need = max(span.maxWidth, 278.0 + 18.0);
        print(
          'S4.2.5 ${mode.name}: colMin=${l.colMin} colMax=${l.colMax} '
          'rect=${r.left}..${r.right} Σ(0,1)=${l.colWidths[0] + l.colWidths[1]} '
          'necessário=$need inflação=${l.colWidths[0] + l.colWidths[1] - need}',
        );
        expect((span.col, span.colSpan), (0, 2));
        expect(r.left, 0);
        expect(r.width, closeTo(l.colWidths[0] + l.colWidths[1], 1e-9));
        if (mode == SpanDistribution.deficit) {
          expect(l.colMax[0], 278, reason: 'coluna A só com o corpo');
          expect(l.colMax[1], 18, reason: '"b" não é inflado pelo span');
          expect(l.colMax[0] + l.colMax[1], need);
        } else {
          // Achado: a divisão igual de doc/04 §9 dá a "b" metade do
          // cabeçalho mesmo quando a coluna A já cobre o span sozinha.
          expect(l.colMax[1], closeTo(span.maxWidth / 2, 1e-9));
          expect(l.colMax[0] + l.colMax[1], greaterThan(need));
        }
        l.dispose();
      }

      // Span mais largo que as colunas: o déficit é repartido, e a soma
      // fica exatamente na largura do span.
      final wide = grid([
        [th('Um cabeçalho muito mais largo que tudo', cs: 2)],
        [c('a'), c('bb')],
      ]);
      final l = layoutTable(
        wide,
        width: 1000,
        style: const TableStyle(spans: SpanDistribution.deficit),
      );
      print(
        'S4.2.5 span largo (deficit): colMax=${l.colMax} '
        'span=${l.cells.first.maxWidth}',
      );
      expect(l.colMax[0] + l.colMax[1], closeTo(l.cells.first.maxWidth, 1e-9));
      expect(l.cellRects.first.width, closeTo(l.width, 1e-9));
      l.dispose();
    });

    test('6. rowspan=2: cobre as duas linhas; célula alta estica a última', () {
      final t = grid([
        [c('l1\nl2\nl3\nl4\nl5', rs: 2), c('b1')],
        [c('b2')],
        [c('x'), c('y')],
      ]);
      final l = layoutTable(t, width: 400);
      final r = l.cellRects.first;
      print(
        'S4.2.6 rowHeights=${l.rowHeights} rect=${r.top}..${r.bottom} '
        'altura da célula=${l.cells.first.height}',
      );
      expect(l.cells[2].col, 1, reason: '"b2" pula o slot ocupado');
      expect(l.rowHeights, [18, 58 - 18, 18]);
      expect(r.top, 0);
      expect(r.height, l.rowHeights[0] + l.rowHeights[1]);
      expect(r.height, l.cells.first.height);

      // Célula com rowspan mais baixa que a soma: nada estica.
      final low = grid([
        [c('a', rs: 2), c('l1\nl2\nl3')],
        [c('l1\nl2')],
      ]);
      final l2 = layoutTable(low, width: 400);
      print('S4.2.6 rowspan baixo: rowHeights=${l2.rowHeights}');
      expect(l2.rowHeights, [38, 28]);
      expect(l2.cellRects.first.height, 66);
      l.dispose();
      l2.dispose();
    });
  });

  group('S4.3 casos limite da grade', () {
    test('célula vazia, uma coluna, spans que saem da grade', () {
      final empty = layoutTable(
        grid([
          [c(''), c('abc')],
        ]),
        width: 400,
      );
      print(
        'S4.3 vazia: min=${empty.cells.first.minWidth} '
        'max=${empty.cells.first.maxWidth} h=${empty.cells.first.height}',
      );
      expect(empty.colMax.first, 8, reason: 'só o padding');
      expect(empty.rowHeights, [18], reason: 'uma linha vazia + padding');

      final one = layoutTable(
        grid([
          for (var i = 0; i < 5; i++) [c(words(Random(i), 30))],
        ]),
        width: 200,
      );
      print('S4.3 uma coluna: widths=${one.colWidths} scale=${one.scale}');
      expect(one.columnCount, 1);
      expect(one.colWidths.single, 200);
      expect(charBreaks(one), 0);

      // rowSpan 5 numa tabela de 2 linhas; rowSpan 0 (até o fim); colSpan
      // que colide com um rowSpan de cima; linha mais curta que as outras.
      final out = layoutTable(
        grid([
          [c('a', rs: 5), c('b'), c('c', rs: 0)],
          [c('d', cs: 3)],
          [c('e')],
        ]),
        width: 400,
      );
      String pos(PlacedCell p) =>
          '${p.cell.text}@(${p.row},${p.col}) ${p.rowSpan}×${p.colSpan}';
      print(
        'S4.3 fora da grade: ${out.cells.map(pos).toList()} '
        'colunas=${out.columnCount} diag=${out.diagnostics}',
      );
      expect(out.cells[0].rowSpan, 3);
      expect(out.cells[2].rowSpan, 3);
      expect((out.cells[3].col, out.cells[3].colSpan), (1, 1));
      expect(out.cells[4].col, 1);
      expect(
        out.diagnostics,
        containsAll([
          TableDiagnostic.truncatedRowSpan,
          TableDiagnostic.truncatedColSpan,
        ]),
      );
      for (final l in [empty, one, out]) {
        l.dispose();
      }
    });

    test(
      '7. propriedade: 200 tabelas aleatórias, sem sobreposição e dentro',
      () {
        final rnd = Random(7);
        var cells = 0, overflows = 0, scaled = 0, proportional = 0, fits = 0;
        var colTruncs = 0, rowTruncs = 0, breaks = 0;
        for (var n = 0; n < 200; n++) {
          final table = randomTable(rnd);
          final w = 150.0 + rnd.nextInt(1351);
          final l = layoutTable(
            table,
            width: w,
            style: TableStyle(
              spans: SpanDistribution.values[n % 2],
              scaleMode: ScaleMode.values[(n ~/ 2) % 2],
            ),
          );
          final box = ui.Rect.fromLTWH(0, 0, l.width, l.height);
          cells += l.cells.length;
          if (l.overflow) {
            overflows++;
          } else if (l.scale < 1) {
            scaled++;
          } else if (l.sumColMax > w) {
            proportional++;
          } else {
            fits++;
          }
          if (l.diagnostics.contains(TableDiagnostic.truncatedColSpan)) {
            colTruncs++;
          }
          if (l.diagnostics.contains(TableDiagnostic.truncatedRowSpan)) {
            rowTruncs++;
          }
          breaks += charBreaks(l);
          for (var i = 0; i < l.cellRects.length; i++) {
            final a = l.cellRects[i];
            expect(a.left >= -1e-9 && a.top >= -1e-9, isTrue);
            expect(a.right, lessThanOrEqualTo(box.right + 1e-6));
            expect(a.bottom, lessThanOrEqualTo(box.bottom + 1e-6));
            // O retângulo cobre a altura do conteúdo da célula.
            expect(a.height, greaterThanOrEqualTo(l.cells[i].height - 1e-6));
            for (var j = i + 1; j < l.cellRects.length; j++) {
              final o = a.intersect(l.cellRects[j]);
              expect(
                o.width <= 1e-6 || o.height <= 1e-6,
                isTrue,
                reason: 'tabela $n: células $i e $j se sobrepõem',
              );
            }
          }
          if (!l.overflow) {
            expect(l.width, lessThanOrEqualTo(w + _eps), reason: 'tabela $n');
          }
          l.dispose();
        }
        print(
          'S4.3.7 200 tabelas, $cells células: cabe=$fits '
          'proporcional=$proportional escala=$scaled overflow=$overflows; '
          'colSpan truncado em $colTruncs, rowSpan truncado em $rowTruncs; '
          'quebras por caractere=$breaks',
        );
        expect(breaks, 0);
      },
    );
  });

  group('S4.4 paginação (doc/04 §9 passo 5)', () {
    test('8. 60 linhas com thead em H=600', () {
      final rnd = Random(3);
      final t = TableModel([
        RowModel([th('Ano'), th('Evento'), th('Observação')]),
        for (var r = 1; r < 60; r++)
          RowModel([
            c('${1900 + r}'),
            c(words(rnd, 1 + rnd.nextInt(12))),
            c(words(rnd, 1 + rnd.nextInt(20))),
          ]),
      ]);
      final l = layoutTable(t, width: 360, pageHeight: 600);
      final pages = l.pages;
      print(
        'S4.4.8 altura total=${l.height.toStringAsFixed(1)} '
        'páginas=${pages.length}: $pages',
      );
      expect(pages.length, greaterThan(2));
      expect(pages.first.headerRows, isEmpty);
      expect(pages.first.bodyRows.first, 0);
      for (final p in pages.skip(1)) {
        expect(p.headerRows, [0], reason: 'cabeçalho no topo');
      }
      final body = [for (final p in pages) ...p.bodyRows];
      expect(body, List.generate(60, (i) => i), reason: 'cada linha 1 vez');
      for (final p in pages) {
        final h = sumOf(
          [...p.headerRows, ...p.bodyRows].map((r) => l.rowHeights[r]),
        );
        expect(p.height, closeTo(h, 1e-9));
        if (!p.indivisible) expect(p.height, lessThanOrEqualTo(600));
      }
      // A fronteira é legal: a próxima linha não caberia na página.
      for (var i = 0; i + 1 < pages.length; i++) {
        final next = pages[i + 1].bodyRows.first;
        expect(pages[i].height + l.rowHeights[next], greaterThan(600));
      }
      l.dispose();
    });

    test('rowspan fica junto; grupo maior que H quebra; linha maior que H', () {
      final t = TableModel([
        RowModel([th('A'), th('B')]),
        for (var r = 1; r < 10; r++) RowModel([c('a$r'), c('b$r')]),
        // Linhas 10–12 ligadas por um rowspan de 3.
        RowModel([c('grupo', rs: 3), c('g1')]),
        RowModel([c('g2')]),
        RowModel([c('g3')]),
        // Linha 13 mais alta que a página (12 linhas duras = 128 px).
        RowModel([c(List.filled(12, 'x').join('\n')), c('alta')]),
        // Linhas 14–33: rowspan de 20 × 18 px = 360 > H.
        RowModel([c('longo', rs: 20), c('r0')]),
        for (var r = 1; r < 20; r++) RowModel([c('r$r')]),
      ]);
      final l = layoutTable(t, width: 400, pageHeight: 100);
      print('S4.4 grupos=${rowGroups(l)}');
      print('S4.4 páginas: ${l.pages}');
      print('S4.4 diag=${l.diagnostics}');
      final pageOf = <int, int>{};
      for (var i = 0; i < l.pages.length; i++) {
        for (final r in l.pages[i].bodyRows) {
          pageOf[r] = i;
        }
      }
      expect({pageOf[10], pageOf[11], pageOf[12]}.length, 1);
      final tall = l.pages[pageOf[13]!];
      expect(tall.bodyRows, [13]);
      expect(tall.indivisible, isTrue);
      expect(tall.headerRows, [0]);
      expect(l.pages.where((p) => p.fragmentedRowSpan).length, greaterThan(1));
      final body = [for (final p in l.pages) ...p.bodyRows];
      expect(body, List.generate(34, (i) => i));
      for (final p in l.pages.where((p) => !p.indivisible)) {
        expect(p.height, lessThanOrEqualTo(100));
      }
      expect(
        l.diagnostics,
        containsAll([
          TableDiagnostic.indivisibleBlock,
          TableDiagnostic.fragmentedRowSpan,
        ]),
      );
      l.dispose();
    });

    test('cabeçalho maior que metade da página não é repetido', () {
      final t = TableModel([
        RowModel([th(List.filled(4, 'h').join('\n'))]),
        for (var r = 0; r < 10; r++) RowModel([c('r$r')]),
      ]);
      final l = layoutTable(t, width: 200, pageHeight: 80);
      print('S4.4 cabeçalho de ${l.rowHeights.first} px em H=80: ${l.pages}');
      expect(l.pages.every((p) => p.headerRows.isEmpty), isTrue);
      expect(l.diagnostics, contains(TableDiagnostic.headerNotRepeated));
      l.dispose();
    });
  });

  group('S4.5 custo', () {
    // Textos novos a cada execução: o SkParagraph guarda o shaping de ~128
    // parágrafos (texto + estilo); repetir a mesma tabela pequena mede cache.
    TableModel costTable(int rows, int cols, int seed) {
      final rnd = Random(seed);
      return TableModel([
        RowModel([for (var k = 0; k < cols; k++) th('Coluna $k')]),
        for (var r = 1; r < rows; r++)
          RowModel([
            for (var k = 0; k < cols; k++) c(words(rnd, 1 + rnd.nextInt(15))),
          ]),
      ]);
    }

    test('9. 20×5 e 200×8: tempo (mediana de 5) e layouts por célula', () {
      const configs = [
        (MinContentProbe.docLiteral, ScaleMode.rebuildFont),
        (MinContentProbe.infinityOnly, ScaleMode.rebuildFont),
        (MinContentProbe.infinityOnly, ScaleMode.transform),
      ];
      for (final (rows, cols) in [(20, 5), (200, 8)]) {
        for (final (probe, scaleMode) in configs) {
          for (final w in [360.0, 20000.0]) {
            final style = TableStyle(probe: probe, scaleMode: scaleMode);
            // Aquecimento (JIT) com outra semente.
            layoutTable(
              costTable(rows, cols, 0),
              width: w,
              style: style,
            ).dispose();
            final times = <int>[];
            late TableLayout l;
            for (var i = 0; i < 5; i++) {
              final t = costTable(rows, cols, 1 + i);
              final sw = Stopwatch()..start();
              l = layoutTable(t, width: w, style: style);
              sw.stop();
              times.add(sw.elapsedMicroseconds);
              if (i < 4) l.dispose();
            }
            times.sort();
            final n = l.cells.length;
            final perCell = l.cells.map((x) => x.layouts).toSet();
            print(
              'S4.5.9 ${rows}x$cols ${probe.name}/${scaleMode.name} '
              'W=${w.toInt()}: mediana ${times[2]} µs '
              '(min ${times.first}, max ${times.last}), '
              '${(times[2] / n).toStringAsFixed(1)} µs/célula, '
              'layouts/célula=$perCell, builds=${l.paragraphBuilds} '
              'scale=${l.scale.toStringAsFixed(3)} overflow=${l.overflow}',
            );
            expect(perCell, {probe == MinContentProbe.docLiteral ? 3 : 2});
            final rebuilt = l.scale != 1 && scaleMode == ScaleMode.rebuildFont;
            expect(l.paragraphBuilds, rebuilt ? 2 * n : n);
            l.dispose();
          }
        }
      }
    });

    test('fatiado no orçamento de 4 ms (doc/08 §2)', () {
      for (final (rows, cols) in [(20, 5), (200, 8)]) {
        final t = costTable(rows, cols, 100);
        for (final w in [360.0, 20000.0]) {
          layoutTable(costTable(rows, cols, 0), width: w).dispose();
          final job = TableLayoutJob(t, width: w);
          final it = job.steps().iterator;
          const budget = 4000;
          final slices = <int>[];
          final stepTimes = <int>[];
          var steps = 0, maxStep = 0;
          var more = true;
          while (more) {
            final sw = Stopwatch()..start();
            while (sw.elapsedMicroseconds < budget) {
              final before = sw.elapsedMicroseconds;
              more = it.moveNext();
              final stepTime = sw.elapsedMicroseconds - before;
              stepTimes.add(stepTime);
              maxStep = max(maxStep, stepTime);
              if (!more) break;
              steps++;
            }
            slices.add(sw.elapsedMicroseconds);
          }
          final total = slices.fold(0, (a, b) => a + b);
          stepTimes.sort();
          final medianStep = stepTimes[stepTimes.length ~/ 2];
          print(
            'S4.5 fatiado ${rows}x$cols W=${w.toInt()}: ${slices.length} '
            'fatias, maior ${slices.reduce(max)} µs, passo mais longo '
            '$maxStep µs, passo mediano $medianStep µs, $steps passos, '
            'total $total µs',
          );
          expect(medianStep, lessThan(budget));
          job.result.dispose();
        }
      }
    });
  });
}
