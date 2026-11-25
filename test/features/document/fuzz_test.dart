import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/features/document/data/parse_document.dart';
import 'package:galley/src/features/document/domain/names.dart';

const _xhtml = 'http://www.w3.org/1999/xhtml';

/// Piso de documentos XHTML/SVG (de 1333) que chegam ao modo tolerante.
const _minRecovered = 1000;

const _seed =
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<!DOCTYPE html>\n'
    '<html xmlns="$_xhtml" lang="pt"><head><title>T</title>'
    '<link rel="stylesheet" href="a.css"/><style>p{a:b}</style></head>'
    '<body><h1 id="t">Título</h1><p class="x y">Olá &amp; <em>mundo</em> '
    '&eacute;<br/>fim</p><!-- c --><ul><li>a</li><li>b</li></ul>'
    '<table><tr><td>1</td><td>2</td></tr></table>'
    '<svg xmlns="http://www.w3.org/2000/svg"><rect width="1"/></svg>'
    '<![CDATA[dados]]></body></html>';

String _mutate(Random random) {
  var s = _seed;
  final steps = 1 + random.nextInt(4);
  for (var i = 0; i < steps; i++) {
    if (s.isEmpty) break;
    switch (random.nextInt(6)) {
      case 0: // truncar
        s = s.substring(0, random.nextInt(s.length));
      case 1: // trocar bytes
        final units = s.codeUnits.toList();
        for (var k = 0; k < 1 + random.nextInt(6); k++) {
          units[random.nextInt(units.length)] = random.nextInt(128);
        }
        s = String.fromCharCodes(units);
      case 2: // apagar '<'
        s = _deleteSome(s, '<', random);
      case 3: // apagar '>'
        s = _deleteSome(s, '>', random);
      case 4: // duplicar uma tag
        final tags = RegExp('<[^<>]*>').allMatches(s).toList();
        if (tags.isNotEmpty) {
          final m = tags[random.nextInt(tags.length)];
          s = s.replaceRange(m.end, m.end, m.group(0)!);
        }
      case 5: // inserir lixo
        const junk = ['<', '&', '<!--', '<![CDATA[', '</', '<?', '&#x', '"'];
        final at = random.nextInt(s.length);
        s = s.replaceRange(at, at, junk[random.nextInt(junk.length)]);
    }
  }
  return s;
}

String _deleteSome(String s, String char, Random random) {
  final hits = <int>[
    for (var i = 0; i < s.length; i++)
      if (s[i] == char) i,
  ];
  if (hits.isEmpty) return s;
  final drop = <int>{
    for (var k = 0; k < 1 + random.nextInt(3); k++)
      hits[random.nextInt(hits.length)],
  };
  return [
    for (var i = 0; i < s.length; i++)
      if (!drop.contains(i)) s[i],
  ].join();
}

void main() {
  test('2.000 variações: nunca lança, < 2 s, raiz html ou svg', () {
    final random = Random(42);
    final failures = <String>[];
    // XHTML/SVG que caíram no modo tolerante (text/html vai sempre).
    var recovered = 0;
    for (var i = 0; i < 2000; i++) {
      final source = _mutate(random);
      final mediaType = const [
        'application/xhtml+xml',
        'text/html',
        'image/svg+xml',
      ][i % 3];
      final watch = Stopwatch()..start();
      try {
        final doc = parseDocumentBytes(
          Uint8List.fromList(utf8.encode(source)),
          path: 'OEBPS/f.xhtml',
          mediaType: mediaType,
        );
        watch.stop();
        if (doc.recovered && mediaType != 'text/html') recovered++;
        final t = doc.tree;
        final root = t.firstChildOf(t.documentNode);
        final name = t.localNameOf(root);
        if (name != 'html' && name != 'svg') {
          failures.add('#$i raiz inesperada <$name>: ${jsonEncode(source)}');
        } else if (name == 'svg' && t.namespaceOf(root) != Namespaces.svg) {
          failures.add('#$i svg fora do namespace SVG: ${jsonEncode(source)}');
        } else if (t.nextSiblingOf(root) != -1) {
          failures.add('#$i mais de uma raiz: ${jsonEncode(source)}');
        }
      } on Object catch (e) {
        watch.stop();
        failures.add('#$i lançou $e: ${jsonEncode(source)}');
      }
      if (watch.elapsed >= const Duration(seconds: 2)) {
        failures.add('#$i lento (${watch.elapsed}): ${jsonEncode(source)}');
      }
    }
    if (failures.isNotEmpty) {
      // ignore: avoid_print
      print(
        '${failures.length} falhas; primeiras:\n'
        '${failures.take(5).join('\n')}',
      );
    }
    expect(failures, isEmpty);
    // Piso: sem ele, uma mudança no seed ou no mutador poderia deixar o
    // fuzz sem exercitar o modo tolerante, sem ninguém perceber.
    // Medido com o seed 42: 1294 de 1333.
    expect(
      recovered,
      greaterThanOrEqualTo(_minRecovered),
      reason: 'XHTML/SVG pelo modo tolerante: $recovered de 1333',
    );
  });
}
