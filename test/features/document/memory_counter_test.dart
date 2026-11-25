import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/features/document/data/parse_document.dart';

/// Teto da razão `tree.retainedBytes / bytes do XHTML`.
///
/// Medido na primeira execução: 3,584 (512 KiB de XHTML sintético); o teto
/// é o medido × 1,25, arredondado para 4,48. O contador `retainedBytes` conta os arranjos
/// tipados da árvore, o texto e os valores de atributo a 2 bytes por caractere (UTF-16) e
/// exclui as tabelas de nomes e de tokens (definição documentada em
/// `DocumentTree.retainedBytes`).
const double _maxRetainedRatio = 4.48;

/// XHTML sintético determinístico, de pelo menos [targetBytes] bytes, com
/// parágrafos, tabelas, ruby, atributos `style`/`class`/`epub:type` e
/// entidades.
Uint8List _syntheticXhtml(int targetBytes) {
  final b = StringBuffer()
    ..write(
      '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE html>\n'
      '<html xmlns="http://www.w3.org/1999/xhtml" '
      'xmlns:epub="http://www.idpf.org/2007/ops" lang="pt-BR">'
      '<head><title>Sintético</title></head><body>',
    );
  var i = 0;
  while (b.length < targetBytes) {
    b.write(
      '<section epub:type="chapter" id="s$i" class="c${i % 7}">'
      '<h2>Capítulo $i</h2>'
      '<p class="texto" style="margin:0 ${i % 5}em">Um parágrafo com '
      '<em>ênfase</em>, <a href="#s${i + 1}">um link</a> &amp; texto '
      '&eacute;pico número $i.</p>'
      '<p><ruby>漢<rt>かん</rt></ruby>字 e mais texto corrido.</p>'
      '<table><tr><td>${i * 3}</td><td>${i * 7}</td></tr></table>'
      '</section>',
    );
    i++;
  }
  b.write('</body></html>');
  return Uint8List.fromList(utf8.encode(b.toString()));
}

void main() {
  test('a árvore retém no máximo K vezes os bytes do XHTML', () {
    final bytes = _syntheticXhtml(512 * 1024);
    final document = parseDocumentBytes(bytes, path: 'OEBPS/memoria.xhtml');
    expect(document.recovered, isFalse);
    final ratio = document.tree.retainedBytes / bytes.length;
    expect(ratio, lessThanOrEqualTo(_maxRetainedRatio));
  });
}
