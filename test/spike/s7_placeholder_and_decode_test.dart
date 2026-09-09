// Spike S7 — placeholder inline em `ui.Paragraph` e decode de imagem com
// tamanho-alvo. Números vão para spike/RESULTADO-S7.md.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show FontWeight;
import 'package:flutter/semantics.dart' show SemanticsConfiguration, SemanticsFlag;
import 'package:flutter_test/flutter_test.dart';

const double _fs = 10;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('S7.1 addPlaceholder(baseline) ocupa um U+FFFC e cresce a linha', () {
    ui.Paragraph build({double? phHeight}) {
      final b = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: _fs, fontFamily: 'FlutterTest'))
        ..pushStyle(ui.TextStyle(fontSize: _fs, fontFamily: 'FlutterTest'))
        ..addText('antes ');
      if (phHeight != null) {
        b.addPlaceholder(20, phHeight, ui.PlaceholderAlignment.baseline,
            baseline: ui.TextBaseline.alphabetic);
      }
      b.addText(' depois');
      return b.build()..layout(const ui.ParagraphConstraints(width: 1000));
    }

    final plain = build();
    final small = build(phHeight: 5);
    final tall = build(phHeight: 40);

    final phBoxes = tall.getBoxesForPlaceholders();
    // "antes " tem 6 code units; o placeholder ocupa o índice 6.
    final rangeBoxes = tall.getBoxesForRange(6, 7);
    final after = tall.getBoxesForRange(7, 8);
    print('S7.1 caixas de placeholder: ${phBoxes.length} → ${phBoxes.first}');
    print('S7.1 getBoxesForRange(6,7): ${rangeBoxes.first}');
    print('S7.1 caixa do caractere seguinte começa em x=${after.first.left} '
        '(placeholder termina em ${phBoxes.first.right})');
    print('S7.1 altura da linha: sem placeholder=${plain.height}, '
        'placeholder 5px=${small.height}, placeholder 40px=${tall.height}');

    expect(phBoxes.length, 1);
    expect(phBoxes.first.right - phBoxes.first.left, 20);
    expect(rangeBoxes.first.left, phBoxes.first.left);
    expect(rangeBoxes.first.right, phBoxes.first.right);
    // Ocupa exatamente um code unit: o texto seguinte começa onde ele termina.
    expect(after.first.left, phBoxes.first.right);
    expect(tall.height, greaterThan(plain.height));
    expect(small.height, plain.height);
  });

  test('S7.2 instantiateImageCodec com targetWidth', () async {
    // PNG 2000×2000 gerado no teste.
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    final paint = ui.Paint();
    for (var i = 0; i < 40; i++) {
      paint.color = ui.Color(0xFF000000 | (i * 6553) & 0xFFFFFF);
      canvas.drawRect(ui.Rect.fromLTWH(i * 50.0, 0, 50, 2000), paint);
    }
    final img = await rec.endRecording().toImage(2000, 2000);
    final png = (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    img.dispose();
    print('S7.2 PNG de teste: ${(png.length / 1024).toStringAsFixed(1)} KB');

    Future<(ui.Image, int)> decode(Uint8List bytes, {int? targetWidth}) async {
      final sw = Stopwatch()..start();
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: targetWidth);
      final frame = await codec.getNextFrame();
      sw.stop();
      codec.dispose();
      return (frame.image, sw.elapsedMicroseconds);
    }

    Future<(int w, int h, int medianUs)> run({int? targetWidth}) async {
      final times = <int>[];
      var w = 0, h = 0;
      for (var i = 0; i < 5; i++) {
        final (im, us) = await decode(png, targetWidth: targetWidth);
        w = im.width;
        h = im.height;
        im.dispose();
        times.add(us);
      }
      times.sort();
      return (w, h, times[2]);
    }

    final full = await run();
    final small = await run(targetWidth: 360);
    final fullMb = full.$1 * full.$2 * 4 / 1048576;
    final smallMb = small.$1 * small.$2 * 4 / 1048576;
    print('S7.2 sem alvo: ${full.$1}×${full.$2}, ${fullMb.toStringAsFixed(2)} MB, '
        'mediana ${(full.$3 / 1000).toStringAsFixed(1)} ms');
    print('S7.2 targetWidth 360: ${small.$1}×${small.$2}, ${smallMb.toStringAsFixed(2)} MB, '
        'mediana ${(small.$3 / 1000).toStringAsFixed(1)} ms');
    print('S7.2 razão de memória: ${(fullMb / smallMb).toStringAsFixed(1)}×, '
        'razão de tempo: ${(small.$3 / full.$3).toStringAsFixed(2)}×');
    expect(small.$1, 360);
    expect(full.$1, 2000);
  });

  test('S7.3 APIs existem e respondem', () {
    final b = ui.ParagraphBuilder(ui.ParagraphStyle(
      fontSize: _fs,
      fontFamily: 'FlutterTest',
      strutStyle: ui.StrutStyle(fontSize: _fs, height: 1.5, forceStrutHeight: true),
      locale: const ui.Locale('ja'),
    ))
      ..pushStyle(ui.TextStyle(
        fontSize: _fs,
        fontFamily: 'FlutterTest',
        locale: const ui.Locale('ja', 'JP'),
        fontWeight: FontWeight.bold,
      ))
      ..addText('uma palavra outra');
    final p = b.build()..layout(const ui.ParagraphConstraints(width: 1000));

    final glyph = p.getClosestGlyphInfoForOffset(const ui.Offset(25, 5));
    final word = p.getWordBoundary(const ui.TextPosition(offset: 6));
    final line = p.getLineBoundary(const ui.TextPosition(offset: 6));
    final strutHeight = p.computeLineMetrics().first.height;
    // StrutStyle(height: 1.5, forceStrutHeight: true) NÃO altera a altura em
    // flutter_tester (fica 10.0). ParagraphStyle.height e TextStyle.height
    // alteram (15.0). Registrado no RESULTADO; verificado também na engine real.
    final viaParagraphHeight = (ui.ParagraphBuilder(ui.ParagraphStyle(
            fontSize: _fs, fontFamily: 'FlutterTest', height: 1.5))
          ..pushStyle(ui.TextStyle(fontSize: _fs, fontFamily: 'FlutterTest'))
          ..addText('uma palavra outra'))
        .build()
      ..layout(const ui.ParagraphConstraints(width: 1000));
    final heightViaStyle = viaParagraphHeight.computeLineMetrics().first.height;
    print('S7.3 glyph em x=25: ${glyph?.graphemeClusterCodeUnitRange}; '
        'palavra em 6: $word; linha: $line; altura com StrutStyle 1.5: $strutHeight; '
        'altura com ParagraphStyle.height 1.5: $heightViaStyle');
    expect(glyph, isNotNull);
    expect(word, const ui.TextRange(start: 4, end: 11));
    expect(heightViaStyle, 15.0);
    p.dispose();
    viaParagraphHeight.dispose();

    // Semântica: nível de heading.
    final cfg = SemanticsConfiguration()..headingLevel = 2;
    expect(cfg.headingLevel, 2);
    expect(SemanticsFlag.isHeader, isNotNull);
  });
}
