import 'dart:io';

import 'package:galley_benchmark/src/corpus/synthetic.dart';
import 'package:galley_benchmark/src/peak_rss.dart';

/// Sonda de memória do teste de streaming do livro sintético.
///
/// Uso: `dart run test/corpus/rss_probe.dart <saída.epub> <bytes>`. Imprime
/// `before=<VmHWM>` antes de gerar o livro e `after=<VmHWM>` depois, num
/// processo próprio, para o pico não somar o de outras suítes de teste.
///
/// Antes de medir, gera um livro pequeno (aquecimento): o processo roda em
/// JIT, e sem isso o crescimento incluiria a memória da compilação do
/// gerador e o crescimento inicial do heap, que variam entre versões do
/// Dart (no Dart 3.14 passavam do limite) e não têm relação com o streaming.
Future<void> main(List<String> args) async {
  final warmUp = '${args[0]}.aquecimento';
  await writeSyntheticBook(warmUp, targetBytes: 2 * 1024 * 1024);
  File(warmUp).deleteSync();
  stdout.writeln('before=${peakRssBytes()}');
  await writeSyntheticBook(args[0], targetBytes: int.parse(args[1]));
  stdout.writeln('after=${peakRssBytes()}');
}
