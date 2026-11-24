import 'dart:ui' as ui;

/// Resultado de [measureSliced].
final class SlicedResult {
  /// Cria o resultado.
  const SlicedResult({
    required this.measured,
    required this.batches,
    required this.maxBatch,
    required this.total,
  });

  /// Parágrafos medidos.
  final int measured;

  /// Número de lotes executados.
  final int batches;

  /// Duração do maior lote (sem contar a cessão ao event loop).
  final Duration maxBatch;

  /// Duração total (inclui as cessões).
  final Duration total;
}

/// Um parágrafo a medir.
final class ParagraphSpec {
  /// Cria a especificação.
  const ParagraphSpec(this.text, this.fontSize, this.width);

  /// Texto.
  final String text;

  /// Tamanho da fonte.
  final double fontSize;

  /// Largura de layout.
  final double width;
}

/// Mede [paragraphs] no isolate raiz em lotes: cada lote mede parágrafos até
/// gastar [budget] e então cede ao event loop.
Future<SlicedResult> measureSliced(
  List<ParagraphSpec> paragraphs, {
  required Duration budget,
}) async {
  final total = Stopwatch()..start();
  var batches = 0;
  var measured = 0;
  var maxBatch = Duration.zero;
  while (measured < paragraphs.length) {
    final batch = Stopwatch()..start();
    do {
      final spec = paragraphs[measured++];
      final paragraph =
          (ui.ParagraphBuilder(
              ui.ParagraphStyle(fontSize: spec.fontSize),
            )..addText(spec.text)).build()
            ..layout(ui.ParagraphConstraints(width: spec.width));
      paragraph.dispose();
    } while (measured < paragraphs.length && batch.elapsed < budget);
    batch.stop();
    batches++;
    if (batch.elapsed > maxBatch) maxBatch = batch.elapsed;
    await Future<void>.delayed(Duration.zero);
  }
  return SlicedResult(
    measured: measured,
    batches: batches,
    maxBatch: maxBatch,
    total: total.elapsed,
  );
}
