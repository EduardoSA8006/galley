/// Dados de teste do contêiner. A Tarefa 5 amplia este arquivo com o
/// `ZipWriter` do corpus e os ajustes de bytes.
library;

import 'dart:convert';
import 'dart:typed_data';

/// [n] bytes de texto repetitivo (comprime bem).
Uint8List prose(int n, {int seed = 1}) {
  final words = ['livro', 'página', 'capítulo', 'nota', 'verso', 'texto'];
  final out = BytesBuilder(copy: false);
  var i = seed;
  while (out.length < n) {
    out.add(utf8.encode('${words[i % words.length]}$i '));
    i = (i * 7 + 3) % 10007;
  }
  return Uint8List.sublistView(out.takeBytes(), 0, n);
}

/// [n] bytes pseudoaleatórios (não comprimem).
Uint8List noise(int n, {int seed = 7}) {
  var x = seed;
  return Uint8List.fromList(
    List<int>.generate(n, (_) {
      x = (x * 1103515245 + 12345) & 0x7FFFFFFF;
      return x >> 16 & 0xFF;
    }),
  );
}
