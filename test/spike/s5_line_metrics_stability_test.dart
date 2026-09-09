// Spike S5.6 — cor não altera métricas de linha (sustenta doc/02 §5.2:
// trocar tema repinta, não repagina).
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('computeLineMetrics idêntico para cores diferentes', () {
    final sb = StringBuffer();
    for (var i = 0; i < 120; i++) {
      sb.write('palavra$i ');
    }
    final text = sb.toString();

    List<ui.LineMetrics> layout(ui.Color color, ui.Color bg, ui.Color deco) {
      final b = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 12, fontFamily: 'FlutterTest'))
        ..pushStyle(ui.TextStyle(
          fontSize: 12,
          fontFamily: 'FlutterTest',
          color: color,
          background: ui.Paint()..color = bg,
          decoration: ui.TextDecoration.underline,
          decorationColor: deco,
        ))
        ..addText(text);
      final p = b.build()..layout(const ui.ParagraphConstraints(width: 200));
      return p.computeLineMetrics();
    }

    final a = layout(const ui.Color(0xFF000000), const ui.Color(0xFFFFFFFF), const ui.Color(0xFF000000));
    final b = layout(const ui.Color(0xFFEEEEEE), const ui.Color(0xFF202020), const ui.Color(0xFFFF0000));
    print('S5.6 linhas: ${a.length}');
    expect(a.length, b.length);
    for (var i = 0; i < a.length; i++) {
      expect(a[i].width, b[i].width);
      expect(a[i].height, b[i].height);
      expect(a[i].baseline, b[i].baseline);
      expect(a[i].ascent, b[i].ascent);
      expect(a[i].descent, b[i].descent);
      expect(a[i].left, b[i].left);
      expect(a[i].hardBreak, b[i].hardBreak);
      expect(a[i].unscaledAscent, b[i].unscaledAscent);
    }
  });
}
