// Spike S5 — soft hyphen (U+00AD) e justificação em `ui.Paragraph`.
//
// Roda em flutter_tester com a fonte FlutterTest (cada glifo tem avanço igual
// ao fontSize; ascent 0.75em, descent 0.25em). Os números impressos são
// copiados para spike/RESULTADO-S5.md.
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

const double _fs = 10;
const String _shy = '­';

ui.Paragraph _build(
  String text, {
  required double width,
  ui.TextAlign align = ui.TextAlign.start,
  ui.TextStyle? style,
}) {
  final builder =
      ui.ParagraphBuilder(
          ui.ParagraphStyle(
            fontSize: _fs,
            textAlign: align,
            fontFamily: 'FlutterTest',
          ),
        )
        ..pushStyle(
          style ?? ui.TextStyle(fontSize: _fs, fontFamily: 'FlutterTest'),
        )
        ..addText(text);
  final p = builder.build()..layout(ui.ParagraphConstraints(width: width));
  return p;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('S5.1 quebra no soft hyphen', () {
    test('largura que só cabe a primeira metade quebra no U+00AD', () {
      const first = 'Paralele';
      const second = 'pipedo';
      // 8 glifos × 10 px = 80. Coluna de 85: cabe "Paralele", não cabe "Paralelep".
      const width = 85.0;

      final withShy = _build('$first$_shy$second', width: width);
      final linesShy = withShy.computeLineMetrics();
      final firstAlone = _build(first, width: 1000);
      final firstWithDash = _build('$first-', width: 1000);

      print('S5.1 linhas com SHY: ${linesShy.length}');
      print('S5.1 largura 1ª linha com SHY: ${linesShy.first.width}');
      print('S5.1 largura de "$first" sozinho: ${firstAlone.longestLine}');
      print('S5.1 largura de "$first-": ${firstWithDash.longestLine}');
      // Range de texto da 1ª linha: até onde vai?
      final boundary = withShy.getLineBoundary(
        const ui.TextPosition(offset: 0),
      );
      print(
        'S5.1 range da 1ª linha: [${boundary.start}, ${boundary.end}) '
        '(SHY está no índice ${first.length})',
      );

      expect(linesShy.length, 2, reason: 'deve quebrar em duas linhas');
      // A quebra é exatamente no soft hyphen: a 1ª linha termina depois dele.
      expect(boundary.end, first.length + 1);
      // Sem quebra em qualquer caractere: a segunda linha começa em "pipedo".
      final second2 = withShy.getLineBoundary(
        const ui.TextPosition(offset: first.length + 1),
      );
      expect(second2.start, first.length + 1);

      // Sem o SHY, a mesma palavra em 85 px quebra em qualquer caractere.
      final noShy = _build('$first$second', width: width);
      final b2 = noShy.getLineBoundary(const ui.TextPosition(offset: 0));
      print(
        'S5.1 sem SHY, 1ª linha termina em ${b2.end} (quebra por caractere)',
      );
      expect(b2.end, isNot(first.length + 1));
    });

    test('a largura da 1ª linha revela se o hífen é pintado', () {
      const first = 'Paralele';
      final withShy = _build('$first${_shy}pipedo', width: 85);
      final line = withShy.computeLineMetrics().first;
      final alone = _build(first, width: 1000).longestLine;
      final dash = _build('$first-', width: 1000).longestLine;
      // Caixa do próprio U+00AD na posição de quebra.
      final shyBoxes = withShy.getBoxesForRange(first.length, first.length + 1);
      final shyWidth = shyBoxes.isEmpty
          ? 0.0
          : shyBoxes.first.right - shyBoxes.first.left;
      print(
        'S5.2 largura 1ª linha=${line.width} | "$first"=$alone | "$first-"=$dash '
        '| caixa do SHY na quebra=$shyWidth',
      );
      // Registro do fato (a asserção documenta o comportamento observado; se um
      // dia o motor passar a pintar o hífen, este teste falha e a doc muda).
      expect(
        line.width,
        alone,
        reason: 'largura igual à metade sozinha: nenhum hífen ocupa espaço',
      );
      expect(shyWidth, 0.0);
    });
  });

  test('S5.3 em largura larga o U+00AD tem largura zero', () {
    const text = 'Paralele${_shy}pipedo';
    final p = _build(text, width: 1000);
    final boxes = p.getBoxesForRange(8, 9);
    final w = boxes.isEmpty ? 0.0 : boxes.first.right - boxes.first.left;
    final noShy = _build('Paralelepipedo', width: 1000);
    print(
      'S5.3 caixa do SHY sem quebra: ${boxes.length} caixa(s), largura=$w; '
      'longestLine com SHY=${p.longestLine}, sem SHY=${noShy.longestLine}',
    );
    expect(w, 0.0);
    expect(p.longestLine, noShy.longestLine);
    expect(p.computeLineMetrics().length, 1);
  });

  test('S5.4 justify: última linha não é justificada', () {
    const text =
        'aa bb cc dd ee ff gg hh ii jj kk ll mm nn oo pp qq rr ss tt uu vv x';
    const width = 125.0; // ~12 glifos por linha
    final p = _build(text, width: width, align: ui.TextAlign.justify);
    final lines = p.computeLineMetrics();
    for (final l in lines) {
      print(
        'S5.4 linha ${l.lineNumber}: width=${l.width} hardBreak=${l.hardBreak}',
      );
    }
    expect(lines.length, greaterThan(2));
    for (final l in lines.take(lines.length - 1)) {
      expect(
        l.width,
        closeTo(width, 0.01),
        reason: 'linhas internas ocupam a coluna',
      );
    }
    expect(
      lines.last.width,
      lessThan(width),
      reason: 'última linha não justificada',
    );
    // Inventário: o que ParagraphStyle e TextStyle oferecem para espaçamento.
    // ParagraphStyle: textAlign, textDirection, maxLines, fontFamily, fontSize,
    //   height, textHeightBehavior, fontWeight, fontStyle, strutStyle, ellipsis,
    //   locale. Nenhum campo de espaçamento máximo entre palavras.
    // TextStyle: letterSpacing e wordSpacing FIXOS (double), sem máximo,
    //   sem callback por linha. Confirmado por compilação abaixo.
    final ts = ui.TextStyle(letterSpacing: 1, wordSpacing: 2);
    expect(ts, isNotNull);
  });

  test('S5.5 custo de shaping com e sem U+00AD', () {
    const base = 'Paralelepipedo constitucionalissimamente anticonstitucional ';
    final sb = StringBuffer();
    while (sb.length < 2000) {
      sb.write(base);
    }
    final plain = sb.toString().substring(0, 2000);
    // Um SHY a cada 6 letras (só dentro de palavras).
    final hy = StringBuffer();
    var run = 0;
    for (final ch in plain.split('')) {
      if (ch == ' ') {
        run = 0;
      } else {
        run++;
        if (run % 6 == 0) hy.write(_shy);
      }
      hy.write(ch);
    }
    final hyphenated = hy.toString();
    final shyCount = hyphenated.length - plain.length;

    double bench(String text) {
      for (var i = 0; i < 20; i++) {
        _build(text, width: 360).dispose();
      }
      final sw = Stopwatch()..start();
      for (var i = 0; i < 200; i++) {
        _build(text, width: 360).dispose();
      }
      sw.stop();
      return sw.elapsedMicroseconds / 200;
    }

    // Intercalado, 3 rodadas, para reduzir ruído.
    final a = <double>[], b = <double>[];
    for (var r = 0; r < 3; r++) {
      a.add(bench(plain));
      b.add(bench(hyphenated));
    }
    a.sort();
    b.sort();
    print(
      'S5.5 2000 chars @360px, 200 layouts, mediana de 3: '
      'sem SHY=${a[1].toStringAsFixed(0)} µs, com $shyCount SHY='
      '${b[1].toStringAsFixed(0)} µs, razão=${(b[1] / a[1]).toStringAsFixed(2)}',
    );
    expect(b[1] / a[1], lessThan(1.5));
  });
}
