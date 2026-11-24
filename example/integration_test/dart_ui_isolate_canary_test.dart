import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Mede um parágrafo misto (latino, CJK, RTL) com `dart:ui`.
Map<String, Object> measure() {
  final builder = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 16))
    ..addText('Galley ação — 漢字かな — עברית mixed bidi ' * 20);
  final paragraph = builder.build()
    ..layout(const ui.ParagraphConstraints(width: 300));
  return {
    'height': paragraph.height,
    'longestLine': paragraph.longestLine,
    'lines': paragraph.computeLineMetrics().length,
  };
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('dart:ui ainda NÃO funciona em isolate de fundo '
      '(canário flutter/flutter#30604)', (tester) async {
    Object? error;
    try {
      await Isolate.run(measure);
    } catch (e) {
      error = e;
    }
    expect(
      error,
      isNotNull,
      reason:
          'O Flutter passou a permitir dart:ui em isolates de fundo. '
          'Pendência do plano B: reescrever a etapa de layout para rodar '
          'em isolate (ver design geral §7 e flutter/flutter#30604).',
    );
    expect(error.toString(), contains('root isolate'));
  });
}
