import 'bench.dart';

/// Código de saída quando o benchmark lança uma exceção.
const int exitBenchFailure = 70;

/// Executa [bench] por [iterations] ciclos e devolve o código de saída.
///
/// Escreve `checksum=<int>` em [stdoutSink] em caso de sucesso. Qualquer
/// exceção de `setUp` ou `run` vira uma mensagem em [stderrSink] e o código
/// [exitBenchFailure]. O `tearDown` roda sempre (também após um `setUp`
/// parcial), e uma falha nele não esconde o erro original.
Future<int> runBench(
  Bench bench,
  int iterations, {
  required StringSink stdoutSink,
  required StringSink stderrSink,
}) async {
  var checksum = 0;
  var code = 0;
  try {
    await bench.setUp();
    for (var i = 0; i < iterations; i++) {
      checksum = await bench.run();
    }
  } on Object catch (e, st) {
    stderrSink.writeln('Falha no benchmark ${bench.id}: $e\n$st');
    code = exitBenchFailure;
  } finally {
    try {
      await bench.tearDown();
    } on Object catch (e) {
      if (code == 0) {
        stderrSink.writeln('Falha no tearDown de ${bench.id}: $e');
        code = exitBenchFailure;
      }
    }
  }
  if (code == 0) stdoutSink.writeln('checksum=$checksum');
  return code;
}
