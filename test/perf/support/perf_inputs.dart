// ignore_for_file: avoid_relative_lib_imports — tool/ não é pacote; importar por caminho é intencional.
/// Entradas determinísticas dos casos de desempenho, a partir dos geradores
/// do corpus (tool/corpus).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../tool/corpus/lib/text.dart';

/// Documento XHTML com cerca de [chars] caracteres de `<p>` de prosa.
String xhtmlOfLength(int chars, {int seed = 9}) {
  final prose = Prose(seed: seed);
  final body = StringBuffer();
  while (body.length < chars) {
    body
      ..write('<p>')
      ..write(prose.paragraph())
      ..write('</p>\n');
  }
  return '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<html xmlns="http://www.w3.org/1999/xhtml" lang="pt-BR">'
      '<head><title>perf</title></head><body>\n$body</body></html>\n';
}

/// [count] parágrafos de exatamente [words] palavras cada.
List<String> paragraphsOfWords(int count, int words, {int seed = 11}) {
  final prose = Prose(seed: seed);
  return List.generate(count, (_) {
    final out = <String>[];
    while (out.length < words) {
      out.addAll(prose.sentence().split(' '));
    }
    return out.take(words).join(' ');
  });
}

/// [length] bytes UTF-8 de prosa.
Uint8List proseBytes(int length, {int seed = 13}) {
  final prose = Prose(seed: seed);
  final out = BytesBuilder(copy: false);
  while (out.length < length) {
    out.add(utf8.encode('${prose.paragraph()}\n'));
  }
  return Uint8List.sublistView(out.takeBytes(), 0, length);
}

/// Deflate cru, como numa entrada de ZIP.
Uint8List deflateRaw(Uint8List data) =>
    Uint8List.fromList(ZLibEncoder(raw: true).convert(data));
