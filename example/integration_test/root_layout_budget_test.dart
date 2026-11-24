import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'sliced_measure.dart';

List<ParagraphSpec> _paragraphs() {
  const samples = [
    'O rato roeu a roupa do rei de Roma, e a rainha, com raiva, rasgou o resto. ',
    '吾輩は猫である。名前はまだ無い。どこで生れたかとんと見当がつかぬ。',
    'בראשית ברא אלהים את השמים ואת הארץ והארץ היתה תהו ובהו. ',
    'Galley ação — 漢字かな — עברית mixed bidi ',
  ];
  return [
    for (var i = 0; i < 400; i++)
      ParagraphSpec(
        samples[i % samples.length] * (3 + i % 7),
        12.0 + (i % 13),
        200.0 + (i * 37) % 201,
      ),
  ];
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('layout fatiado respeita o orçamento por lote', (tester) async {
    // Aquecimento (fontes, caches do motor): fora da medição.
    await measureSliced(
      _paragraphs().take(20).toList(),
      budget: const Duration(milliseconds: 4),
    );
    final r = await measureSliced(
      _paragraphs(),
      budget: const Duration(milliseconds: 4),
    );
    expect(r.measured, 400);
    // Invariante real: um lote nunca estoura o orçamento por mais de um
    // parágrafo (o limite se calibra pela máquina, sem depender de 8 ms fixos).
    expect(
      r.maxBatch,
      lessThanOrEqualTo(
        const Duration(milliseconds: 4) +
            r.maxParagraph +
            const Duration(milliseconds: 1),
      ),
    );
    final perParagraph = r.total.inMicroseconds / r.measured;
    // ignore: avoid_print
    print(
      'LAYOUT FATIADO: ${r.measured} parágrafos em ${r.batches} lotes, '
      'total ${r.total.inMilliseconds} ms, '
      'média ${perParagraph.toStringAsFixed(1)} us/parágrafo, '
      'maior lote ${r.maxBatch.inMicroseconds} us, '
      'maior parágrafo ${r.maxParagraph.inMicroseconds} us',
    );
  });
}
