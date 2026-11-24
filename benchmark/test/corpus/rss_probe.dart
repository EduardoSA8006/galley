import 'dart:io';

import 'package:galley_benchmark/src/corpus/synthetic.dart';

/// Sonda de memória do teste de streaming do livro sintético.
///
/// Uso: `dart run test/corpus/rss_probe.dart <saída.epub> <bytes>`. Imprime
/// `before=<maxRss>` antes de gerar o livro e `after=<maxRss>` depois, num
/// processo próprio, para o pico não somar o de outras suítes de teste.
Future<void> main(List<String> args) async {
  stdout.writeln('before=${ProcessInfo.maxRss}');
  await writeSyntheticBook(args[0], targetBytes: int.parse(args[1]));
  stdout.writeln('after=${ProcessInfo.maxRss}');
}
