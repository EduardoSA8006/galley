// Spike S1 — `ui.Paragraph` em isolate de background, na engine real.
//
// Rodar: cd example && flutter test integration_test -d linux
// ignore_for_file: avoid_print — spike descartável, a saída é o resultado.
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

String _shape() {
  final b = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 14))
    ..addText('Texto shapeado em algum isolate.');
  final p = b.build()..layout(const ui.ParagraphConstraints(width: 200));
  final n = p.computeLineMetrics().length;
  p.dispose();
  return 'ok: $n linha(s)';
}

/// Devolve `ok: ...` ou `ERRO tipo: mensagem`.
String _tryShape() {
  try {
    return _shape();
  } catch (e) {
    return 'ERRO ${e.runtimeType}: $e';
  }
}

void _spawnEntry(SendPort port) => port.send(_tryShape());

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('S1.1 isolate raiz', (tester) async {
    final r = _tryShape();
    print('S1.1 isolate raiz: $r');
    expect(r, startsWith('ok'));
  });

  testWidgets('S1.2 Isolate.run', (tester) async {
    final r = await Isolate.run(_tryShape);
    print('S1.2 Isolate.run: $r');
    expect(
      r,
      startsWith('ERRO'),
      reason: 'presume-se negativo (doc/08 §2); se passar, a doc muda',
    );
  });

  testWidgets('S1.3 Isolate.spawn', (tester) async {
    final port = ReceivePort();
    final iso = await Isolate.spawn(_spawnEntry, port.sendPort);
    final r = await port.first as String;
    iso.kill();
    print('S1.3 Isolate.spawn: $r');
    expect(r, startsWith('ERRO'));
  });
}
