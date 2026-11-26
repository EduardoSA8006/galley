import 'dart:convert';
import 'dart:typed_data';

/// XHTML sintético determinístico, de pelo menos [targetBytes] bytes, com
/// parágrafos, tabelas, ruby, atributos `style`/`class`/`epub:type` e
/// entidades (apenas uso em testes de memória e desempenho).
///
/// [head] é inserido dentro do `<head>`, depois do `<title>` (ex.: um
/// `<link>` para a folha do teste).
Uint8List syntheticXhtml(int targetBytes, {String head = ''}) {
  final b = StringBuffer()
    ..write(
      '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE html>\n'
      '<html xmlns="http://www.w3.org/1999/xhtml" '
      'xmlns:epub="http://www.idpf.org/2007/ops" lang="pt-BR">'
      '<head><title>Sintético</title>$head</head><body>',
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
