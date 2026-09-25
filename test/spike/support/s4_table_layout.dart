// Spike S4 — layout de tabela (doc/04 §9, Emenda 12).
//
// Protótipo do layout automático simplificado sobre `ui.Paragraph` direto, sem
// widgets: medir min/max content por célula, derivar colMin/colMax, distribuir
// nos três regimes (cabe, proporcional, escala com piso 0.8× e rolagem
// horizontal), resolver alturas com rowSpan e paginar com a linha como unidade
// de quebra e cabeçalho repetido.
//
// O trabalho é um `sync*` que cede depois de cada célula, para que o mesmo
// código rode inteiro ([layoutTable]) ou fatiado no orçamento de 4 ms de
// doc/08 §2 ([TableLayoutJob.steps]).

import 'dart:math' as math;
import 'dart:ui' as ui;

// ---------------------------------------------------------------------------
// Modelo
// ---------------------------------------------------------------------------

class CellModel {
  const CellModel(
    this.text, {
    this.colSpan = 1,
    this.rowSpan = 1,
    this.isHeader = false,
  });

  final String text;
  final int colSpan;

  /// `0` segue o HTML: estende até a última linha da tabela.
  final int rowSpan;
  final bool isHeader;
}

class RowModel {
  const RowModel(this.cells);

  final List<CellModel> cells;

  bool get isHeader => cells.isNotEmpty && cells.every((c) => c.isHeader);
}

class TableModel {
  const TableModel(this.rows);

  final List<RowModel> rows;
}

// ---------------------------------------------------------------------------
// Opções
// ---------------------------------------------------------------------------

/// Como obter o min-content de uma célula.
enum MinContentProbe {
  /// Leitura literal de doc/04 §9 passo 1: `maxIntrinsicWidth` após
  /// `layout(0)` e `longestLine` após `layout(∞)`. Três layouts por célula.
  docLiteral,

  /// Um único `layout(∞)`: `minIntrinsicWidth` é a palavra mais longa e
  /// `longestLine` é o max-content. Dois layouts por célula.
  infinityOnly,
}

/// Como uma célula com `colSpan > 1` contribui para colMin/colMax.
enum SpanDistribution {
  /// doc/04 §9 passo 1: divide o valor da célula igualmente entre as colunas
  /// cobertas, e cada coluna fica com o máximo.
  equal,

  /// Estilo CSS: primeiro as células de span 1; depois cada célula com span
  /// (em ordem crescente de span) só reparte o que falta para caber.
  deficit,
}

/// Como aplicar o fator de escala `s < 1` (doc/04 §9 passo 3).
enum ScaleMode {
  /// Reconstrói cada parágrafo com `fontSize × s` e padding × s. Um build a
  /// mais por célula, e o avanço de glifo em tamanho fracionário não é
  /// exatamente linear.
  rebuildFont,

  /// Mantém o parágrafo medido em 1×, faz o layout final na largura / s e
  /// pinta com `canvas.scale(s)`. Nenhum build a mais; linear por construção.
  transform,
}

class TableStyle {
  const TableStyle({
    this.fontSize = 10,
    this.padding = 4,
    this.fontFamily = 'FlutterTest',
    this.minScale = 0.8,
    this.probe = MinContentProbe.infinityOnly,
    this.spans = SpanDistribution.equal,
    this.scaleMode = ScaleMode.rebuildFont,
    this.maxHeaderFraction = 0.5,
  });

  final double fontSize;

  /// Padding de cada lado da célula (horizontal e vertical).
  final double padding;
  final String fontFamily;
  final double minScale;
  final MinContentProbe probe;
  final SpanDistribution spans;
  final ScaleMode scaleMode;

  /// O cabeçalho só é repetido se ocupar no máximo esta fração da página.
  final double maxHeaderFraction;
}

// ---------------------------------------------------------------------------
// Saída
// ---------------------------------------------------------------------------

enum TableDiagnostic {
  tableOverflow,
  indivisibleBlock,
  truncatedColSpan,
  truncatedRowSpan,
  fragmentedRowSpan,
  headerNotRepeated,
}

/// Célula já posicionada na grade (após resolver spans e colisões).
class PlacedCell {
  PlacedCell({
    required this.index,
    required this.cell,
    required this.row,
    required this.col,
    required this.rowSpan,
    required this.colSpan,
  });

  /// Ordem de documento.
  final int index;
  final CellModel cell;
  final int row;
  final int col;
  final int rowSpan;
  final int colSpan;

  double minWidth = 0;
  double maxWidth = 0;
  double height = 0;
  int layouts = 0;
  int builds = 0;
  ui.Paragraph? paragraph;

  int get lastRow => row + rowSpan - 1;
}

class TablePage {
  TablePage();

  /// Linhas repetidas do cabeçalho no topo (vazio na primeira página).
  final List<int> headerRows = [];

  /// Linhas de conteúdo, em ordem, cada uma exatamente uma vez na tabela.
  final List<int> bodyRows = [];
  double height = 0;

  /// A página excede a altura porque a unidade não cabe numa página vazia.
  bool indivisible = false;

  /// Um grupo ligado por rowSpan foi quebrado entre linhas nesta página.
  bool fragmentedRowSpan = false;

  bool get isEmpty => bodyRows.isEmpty;

  @override
  String toString() =>
      'h=$headerRows b=${bodyRows.isEmpty ? '[]' : '${bodyRows.first}..${bodyRows.last}'}'
      ' ${height.toStringAsFixed(1)}${indivisible ? ' INDIV' : ''}';
}

class TableLayout {
  TableLayout({
    required this.cells,
    required this.columnCount,
    required this.colMin,
    required this.colMax,
    required this.colWidths,
    required this.rowHeights,
    required this.cellRects,
    required this.scale,
    required this.overflow,
    required this.diagnostics,
  });

  final List<PlacedCell> cells;
  final int columnCount;

  /// Em escala 1 (antes do fator de escala).
  final List<double> colMin;
  final List<double> colMax;

  /// Finais, já com escala.
  final List<double> colWidths;
  final List<double> rowHeights;

  /// Um por célula de [cells], na mesma ordem, cobrindo o span inteiro.
  final List<ui.Rect> cellRects;
  final double scale;
  final bool overflow;
  final Set<TableDiagnostic> diagnostics;
  List<TablePage> pages = const [];

  double get width => colWidths.fold(0.0, (a, b) => a + b);
  double get height => rowHeights.fold(0.0, (a, b) => a + b);
  double get sumColMin => colMin.fold(0.0, (a, b) => a + b);
  double get sumColMax => colMax.fold(0.0, (a, b) => a + b);

  int get layoutCalls => cells.fold(0, (a, c) => a + c.layouts);
  int get paragraphBuilds => cells.fold(0, (a, c) => a + c.builds);

  void dispose() {
    for (final c in cells) {
      c.paragraph?.dispose();
      c.paragraph = null;
    }
  }
}

// ---------------------------------------------------------------------------
// Grade
// ---------------------------------------------------------------------------

/// Posiciona as células como o modelo de tabela do HTML: cada célula vai para
/// o primeiro slot livre da linha, pulando slots ocupados por rowSpan de cima.
/// rowSpan além da última linha é truncado; colSpan que colide com um slot já
/// ocupado é truncado no slot livre anterior (o HTML chama isso de "table
/// model error" e deixa as células se sobreporem).
(List<PlacedCell>, int, Set<TableDiagnostic>) placeCells(TableModel table) {
  final rows = table.rows.length;
  final occupied = List.generate(rows, (_) => <int>{});
  final placed = <PlacedCell>[];
  final diags = <TableDiagnostic>{};
  var columns = 0;
  var index = 0;
  for (var r = 0; r < rows; r++) {
    var col = 0;
    for (final cell in table.rows[r].cells) {
      while (occupied[r].contains(col)) {
        col++;
      }
      final wantRows = cell.rowSpan <= 0 ? rows - r : cell.rowSpan;
      final rs = math.min(wantRows, rows - r);
      if (rs < wantRows) diags.add(TableDiagnostic.truncatedRowSpan);
      final wantCols = math.max(1, cell.colSpan);
      var cs = 0;
      while (cs < wantCols && !occupied[r].contains(col + cs)) {
        cs++;
      }
      if (cs < wantCols) diags.add(TableDiagnostic.truncatedColSpan);
      for (var rr = r; rr < r + rs; rr++) {
        for (var cc = col; cc < col + cs; cc++) {
          occupied[rr].add(cc);
        }
      }
      placed.add(
        PlacedCell(
          index: index++,
          cell: cell,
          row: r,
          col: col,
          rowSpan: rs,
          colSpan: cs,
        ),
      );
      col += cs;
      columns = math.max(columns, col);
    }
  }
  return (placed, columns, diags);
}

// ---------------------------------------------------------------------------
// Layout
// ---------------------------------------------------------------------------

class TableLayoutJob {
  TableLayoutJob(
    this.table, {
    required this.width,
    this.style = const TableStyle(),
  });

  final TableModel table;

  /// Largura disponível `W` (coluna de texto menos padding do bloco).
  final double width;
  final TableStyle style;

  TableLayout? _result;
  TableLayout get result => _result!;

  ui.Paragraph _build(String text, double fontSize) {
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(fontSize: fontSize, fontFamily: style.fontFamily),
          )
          ..pushStyle(
            ui.TextStyle(fontSize: fontSize, fontFamily: style.fontFamily),
          )
          ..addText(text);
    return builder.build();
  }

  void _layout(PlacedCell c, ui.Paragraph p, double w) {
    p.layout(ui.ParagraphConstraints(width: w));
    c.layouts++;
  }

  /// `longestLine` de parágrafo vazio é −FLT_MAX; `minIntrinsicWidth` de texto
  /// só com espaço é FLT_MIN. Ambos viram 0.
  static double _sane(double v) => v.isFinite && v > 1e-6 ? v : 0;

  /// Cede uma vez por célula medida e uma vez por célula com layout final.
  Iterable<void> steps() sync* {
    final (cells, columns, diags) = placeCells(table);
    final pad2 = 2 * style.padding;

    // 1. Medir.
    for (final c in cells) {
      final p = _build(c.cell.text, style.fontSize);
      c.builds++;
      double minC, maxC;
      switch (style.probe) {
        case MinContentProbe.docLiteral:
          _layout(c, p, 0);
          minC = _sane(p.maxIntrinsicWidth);
          _layout(c, p, double.infinity);
          maxC = _sane(p.longestLine);
        case MinContentProbe.infinityOnly:
          _layout(c, p, double.infinity);
          minC = _sane(p.minIntrinsicWidth);
          maxC = _sane(p.longestLine);
      }
      c.minWidth = minC + pad2;
      c.maxWidth = math.max(maxC, minC) + pad2;
      c.paragraph = p;
      yield null;
    }

    // 2. Colunas.
    final colMin = List<double>.filled(columns, 0);
    final colMax = List<double>.filled(columns, 0);
    for (final c in cells.where((c) => c.colSpan == 1)) {
      colMin[c.col] = math.max(colMin[c.col], c.minWidth);
      colMax[c.col] = math.max(colMax[c.col], c.maxWidth);
    }
    final spanned = cells.where((c) => c.colSpan > 1).toList()
      ..sort((a, b) => a.colSpan.compareTo(b.colSpan));
    for (final c in spanned) {
      final range = Iterable<int>.generate(c.colSpan, (i) => c.col + i);
      switch (style.spans) {
        case SpanDistribution.equal:
          for (final i in range) {
            colMin[i] = math.max(colMin[i], c.minWidth / c.colSpan);
            colMax[i] = math.max(colMax[i], c.maxWidth / c.colSpan);
          }
        case SpanDistribution.deficit:
          for (final (cols, v) in [
            (colMin, c.minWidth),
            (colMax, c.maxWidth),
          ]) {
            final have = range.fold(0.0, (a, i) => a + cols[i]);
            if (v > have) {
              for (final i in range) {
                cols[i] += (v - have) / c.colSpan;
              }
            }
          }
      }
    }
    for (var i = 0; i < columns; i++) {
      colMax[i] = math.max(colMax[i], colMin[i]);
    }

    // 3. Distribuir.
    final sumMin = colMin.fold(0.0, (a, b) => a + b);
    final sumMax = colMax.fold(0.0, (a, b) => a + b);
    var scale = 1.0;
    var overflow = false;
    final List<double> colWidths;
    if (sumMax <= width) {
      colWidths = List.of(colMax);
    } else if (sumMin <= width) {
      final slack = width - sumMin;
      final sumDiff = sumMax - sumMin;
      colWidths = [
        for (var i = 0; i < columns; i++)
          colMin[i] + slack * (colMax[i] - colMin[i]) / sumDiff,
      ];
    } else {
      scale = math.max(width / sumMin, style.minScale);
      overflow = sumMin * scale > width + 1e-9;
      if (overflow) diags.add(TableDiagnostic.tableOverflow);
      colWidths = [for (final m in colMin) m * scale];
    }
    final colX = List<double>.filled(columns + 1, 0);
    for (var i = 0; i < columns; i++) {
      colX[i + 1] = colX[i] + colWidths[i];
    }

    // 4. Layout final e linhas.
    final rows = table.rows.length;
    final rowHeights = List<double>.filled(rows, 0);
    final fontSize = style.fontSize * scale;
    final padding = style.padding * scale;
    final transform = style.scaleMode == ScaleMode.transform;
    for (final c in cells) {
      var p = c.paragraph!;
      final boxWidth = colX[c.col + c.colSpan] - colX[c.col];
      if (transform) {
        // Layout em 1× na largura desescalada; a pintura aplica scale(s).
        _layout(c, p, math.max(0, boxWidth / scale - 2 * style.padding));
        c.height = (p.height + 2 * style.padding) * scale;
      } else {
        if (scale != 1.0) {
          p.dispose();
          p = _build(c.cell.text, fontSize);
          c.builds++;
          c.paragraph = p;
        }
        _layout(c, p, math.max(0, boxWidth - 2 * padding));
        c.height = p.height + 2 * padding;
      }
      if (c.rowSpan == 1) {
        rowHeights[c.row] = math.max(rowHeights[c.row], c.height);
      }
      yield null;
    }
    final rowSpanned = cells.where((c) => c.rowSpan > 1).toList()
      ..sort((a, b) {
        final s = a.rowSpan.compareTo(b.rowSpan);
        return s != 0 ? s : a.row.compareTo(b.row);
      });
    for (final c in rowSpanned) {
      var covered = 0.0;
      for (var r = c.row; r <= c.lastRow; r++) {
        covered += rowHeights[r];
      }
      if (c.height > covered) rowHeights[c.lastRow] += c.height - covered;
    }
    final rowY = List<double>.filled(rows + 1, 0);
    for (var r = 0; r < rows; r++) {
      rowY[r + 1] = rowY[r] + rowHeights[r];
    }

    _result = TableLayout(
      cells: cells,
      columnCount: columns,
      colMin: colMin,
      colMax: colMax,
      colWidths: colWidths,
      rowHeights: rowHeights,
      cellRects: [
        for (final c in cells)
          ui.Rect.fromLTRB(
            colX[c.col],
            rowY[c.row],
            colX[c.col + c.colSpan],
            rowY[c.row + c.rowSpan],
          ),
      ],
      scale: scale,
      overflow: overflow,
      diagnostics: diags,
    );
  }
}

TableLayout layoutTable(
  TableModel table, {
  required double width,
  TableStyle style = const TableStyle(),
  double? pageHeight,
}) {
  final job = TableLayoutJob(table, width: width, style: style);
  for (final _ in job.steps()) {}
  final layout = job.result;
  if (pageHeight != null) {
    layout.pages = paginate(
      layout,
      pageHeight,
      maxHeaderFraction: style.maxHeaderFraction,
    );
  }
  return layout;
}

// ---------------------------------------------------------------------------
// Paginação
// ---------------------------------------------------------------------------

/// Intervalos [início, fim) de linhas ligadas por rowSpan (fechamento
/// transitivo). Cada intervalo é indivisível enquanto couber numa página.
List<(int, int)> rowGroups(TableLayout layout) {
  final rows = layout.rowHeights.length;
  final reach = List<int>.generate(rows, (r) => r + 1);
  for (final c in layout.cells) {
    reach[c.row] = math.max(reach[c.row], c.row + c.rowSpan);
  }
  final groups = <(int, int)>[];
  var r = 0;
  while (r < rows) {
    var end = reach[r];
    var k = r + 1;
    while (k < end) {
      end = math.max(end, reach[k]);
      k++;
    }
    groups.add((r, end));
    r = end;
  }
  return groups;
}

/// A linha é a unidade de quebra; grupos ligados por rowSpan ficam na mesma
/// página. A primeira linha com todas as células `isHeader` (com seu grupo) é
/// repetida no topo de cada página seguinte. Unidade que não cabe numa página
/// vazia: grupo é quebrado entre linhas ([TablePage.fragmentedRowSpan]); linha
/// sozinha vira página própria ([TablePage.indivisible]).
List<TablePage> paginate(
  TableLayout layout,
  double pageHeight, {
  double maxHeaderFraction = 0.5,
}) {
  final h = layout.rowHeights;
  final groups = rowGroups(layout);
  double sum(int a, int b) {
    var s = 0.0;
    for (var r = a; r < b; r++) {
      s += h[r];
    }
    return s;
  }

  // Grupo do cabeçalho.
  final headerRowIndex = layout.cells.isEmpty
      ? -1
      : Iterable<int>.generate(h.length).firstWhere((r) {
          final rowCells = layout.cells.where((c) => c.row == r);
          return rowCells.isNotEmpty && rowCells.every((c) => c.cell.isHeader);
        }, orElse: () => -1);
  (int, int)? header;
  if (headerRowIndex >= 0) {
    header = groups.firstWhere(
      (g) => g.$1 <= headerRowIndex && headerRowIndex < g.$2,
    );
    if (sum(header.$1, header.$2) > pageHeight * maxHeaderFraction) {
      layout.diagnostics.add(TableDiagnostic.headerNotRepeated);
      header = null;
    }
  }
  final headerHeight = header == null ? 0.0 : sum(header.$1, header.$2);
  var headerPlaced = false;

  final pages = <TablePage>[];
  var page = TablePage();

  void newPage() {
    pages.add(page);
    page = TablePage();
    if (header != null && headerPlaced) {
      page.headerRows.addAll([for (var r = header.$1; r < header.$2; r++) r]);
      page.height = headerHeight;
    }
  }

  void place(int a, int b, {required bool fragment}) {
    final gh = sum(a, b);
    if (!page.isEmpty && page.height + gh > pageHeight) newPage();
    if (page.height + gh > pageHeight && b - a > 1) {
      // Não cabe nem numa página vazia: quebra entre as linhas do grupo.
      layout.diagnostics.add(TableDiagnostic.fragmentedRowSpan);
      for (var r = a; r < b; r++) {
        place(r, r + 1, fragment: true);
      }
      return;
    }
    if (page.height + gh > pageHeight) {
      page.indivisible = true;
      layout.diagnostics.add(TableDiagnostic.indivisibleBlock);
    }
    if (fragment) page.fragmentedRowSpan = true;
    page.bodyRows.addAll([for (var r = a; r < b; r++) r]);
    page.height += gh;
    if (header != null && a == header.$1) headerPlaced = true;
  }

  for (final (a, b) in groups) {
    place(a, b, fragment: false);
  }
  if (!page.isEmpty || pages.isEmpty) pages.add(page);
  return pages;
}
