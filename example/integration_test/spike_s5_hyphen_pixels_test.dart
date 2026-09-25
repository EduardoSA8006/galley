// Spike S5 (engine real) — o `ui.Paragraph` pinta o hífen quando quebra num
// U+00AD? Conta pixels escuros à direita da última letra da 1ª linha com uma
// fonte real do sistema. Também confere StrutStyle na engine real.
//
// Rodar: cd example && flutter test integration_test -d linux
// ignore_for_file: avoid_print — spike descartável, a saída é o resultado.
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const double _fs = 40;
const String _shy = '­';

ui.Paragraph _build(String text, String family, double width) {
  final b =
      ui.ParagraphBuilder(ui.ParagraphStyle(fontFamily: family, fontSize: _fs))
        ..pushStyle(
          ui.TextStyle(
            fontFamily: family,
            fontSize: _fs,
            color: const ui.Color(0xFF000000),
          ),
        )
        ..addText(text);
  return b.build()..layout(ui.ParagraphConstraints(width: width));
}

/// Pixels escuros na 1ª linha, à direita de [fromX].
Future<int> _darkPixelsRightOf(
  ui.Paragraph p,
  double fromX,
  double imgW,
) async {
  final line = p.computeLineMetrics().first;
  final rec = ui.PictureRecorder();
  ui.Canvas(rec)
    ..drawRect(
      ui.Rect.fromLTWH(0, 0, imgW, line.height),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    )
    ..drawParagraph(p, ui.Offset.zero);
  final img = await rec.endRecording().toImage(
    imgW.toInt(),
    line.height.ceil(),
  );
  final bytes = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  img.dispose();
  var dark = 0;
  final w = imgW.toInt();
  for (var y = 0; y < line.height.floor(); y++) {
    for (var x = fromX.ceil(); x < w; x++) {
      final i = (y * w + x) * 4;
      if (bytes.getUint8(i) < 128) dark++;
    }
  }
  return dark;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final family in const ['Noto Serif', 'Liberation Serif']) {
    testWidgets('S5.7 hífen pintado na quebra? ($family)', (tester) async {
      const first = 'Paralele';
      final alone = _build(first, family, 2000);
      final aloneW = alone.longestLine;
      final dashW = _build('$first-', family, 2000).longestLine;
      // Coluna que cabe "Paralele" mas não "Paralelep".
      final width = aloneW + 4;
      final withShy = _build('$first${_shy}pipedo', family, width);
      final withDash = _build('$first-pipedo', family, dashW + 4);

      final shyLine = withShy.computeLineMetrics().first;
      final imgW = dashW + 60;
      final darkAlone = await _darkPixelsRightOf(alone, aloneW, imgW);
      final darkShy = await _darkPixelsRightOf(withShy, aloneW, imgW);
      final darkDash = await _darkPixelsRightOf(withDash, aloneW, imgW);

      print(
        'S5.7 [$family] "$first"=${aloneW.toStringAsFixed(2)}px, '
        '"$first-"=${dashW.toStringAsFixed(2)}px, 1ª linha com SHY='
        '${shyLine.width.toStringAsFixed(2)}px, '
        'range da 1ª linha=${withShy.getLineBoundary(const ui.TextPosition(offset: 0))}',
      );
      print(
        'S5.7 [$family] pixels escuros à direita da última letra: '
        'sem SHY=$darkAlone, com SHY na quebra=$darkShy, com "-"=$darkDash',
      );

      expect(withShy.computeLineMetrics().length, 2);
      expect(
        darkDash,
        greaterThan(20),
        reason: 'o hífen literal deve aparecer',
      );
      // Registro do fato observado: se um dia o motor pintar o hífen, este
      // expect falha e a documentação muda.
      expect(
        darkShy,
        darkAlone,
        reason: 'nenhum hífen pintado na quebra por U+00AD',
      );
    });
  }

  testWidgets('S5.8 StrutStyle vs height na engine real', (tester) async {
    double h(ui.ParagraphStyle ps) {
      final b = ui.ParagraphBuilder(ps)
        ..pushStyle(ui.TextStyle(fontFamily: 'Noto Serif', fontSize: 20))
        ..addText('uma palavra outra');
      return (b.build()..layout(const ui.ParagraphConstraints(width: 1000)))
          .computeLineMetrics()
          .first
          .height;
    }

    final base = h(ui.ParagraphStyle(fontFamily: 'Noto Serif', fontSize: 20));
    final strut = h(
      ui.ParagraphStyle(
        fontFamily: 'Noto Serif',
        fontSize: 20,
        strutStyle: ui.StrutStyle(
          fontFamily: 'Noto Serif',
          fontSize: 20,
          height: 2.0,
          forceStrutHeight: true,
        ),
      ),
    );
    final viaHeight = h(
      ui.ParagraphStyle(fontFamily: 'Noto Serif', fontSize: 20, height: 2.0),
    );
    print(
      'S5.8 altura da linha: base=$base, StrutStyle(height 2.0, force)=$strut, '
      'ParagraphStyle.height 2.0=$viaHeight',
    );
    expect(viaHeight, closeTo(40, 0.5));
  });
}
