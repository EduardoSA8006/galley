// Fuzz curto e determinístico da Publicação (spec §1, critério de sucesso):
// mutações de container.xml, OPF, NAV e NCX de EPUBs do corpus; nenhuma
// exceção fora de EpubException pode escapar de readPublication.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/container/byte_source.dart';
import 'package:galley/src/container/provider_container.dart';
import 'package:galley/src/container/zip/zip_container.dart';
import 'package:galley/src/diagnostics/diagnostic.dart';
import 'package:galley/src/diagnostics/exceptions.dart';
import 'package:galley/src/publication/read_publication.dart';

import 'support/epub_fixtures.dart';

const _books = [
  'estrutura/nav-ncx-divergentes',
  'estrutura/opf-em-subpasta',
  'regressoes/href-url-encoded',
  'estrutura/page-list-tres-fontes',
];

/// Trechos que costumam quebrar parsers e resolução de caminho. As três
/// últimas são NAVs hostis já corrigidos em tarefas anteriores (referência
/// numérica fora de faixa, `<title/>` vazio no head e o disparador clássico
/// de `<math><style><i><title>` do HTML5).
const _tokens = [
  '<',
  '>',
  '"',
  "'",
  '&',
  '&#0;',
  '&#xD800;',
  '&#99999999;',
  '&nbsp;',
  '<![CDATA[',
  ']]>',
  '<!--',
  '\u0000',
  '﻿',
  '%',
  '%E9',
  '%2e%2e/',
  '%2F',
  '../../',
  r'\',
  '#',
  '?',
  'http:',
  'mailto:',
  '<ol><li>',
  '</li></ol>',
  '<nav epub:type="toc">',
  '<item id="x" href="" media-type=""/>',
  '<item id="c" href="a.pdf" media-type="application/pdf" fallback="c"/>',
  '<itemref idref="nope"/>',
  '<itemref idref="nav"/>',
  '<meta refines="#" property="role"/>',
  '<dc:date>+275760-09-14</dc:date>',
  '</manifest>',
  '</spine>',
  '</package>',
  '<package>',
  'full-path=""',
  '&#99999999999999999999;',
  '<title/>',
  '<math><style><i><title></style><!--',
];

Future<Map<String, Uint8List>> _entries(String book) async {
  final container = await ZipContainer.open(
    MemoryEpubByteSource(File('test/corpus/$book/book.epub').readAsBytesSync()),
    sink: DiagnosticSink(),
  );
  final out = <String, Uint8List>{};
  for (final path in container.paths) {
    if (path == 'mimetype') continue; // epubZip grava o seu
    final r = (await container.fetch(path))!;
    for (final _ in r.decode()) {}
    out[path] = r.bytes;
  }
  await container.close();
  return out;
}

Uint8List _mutate(Uint8List bytes, Random random) {
  final b = bytes.toList();
  final at = b.isEmpty ? 0 : random.nextInt(b.length);
  switch (random.nextInt(5)) {
    case 0:
      for (var k = 0; k < 1 + random.nextInt(4) && b.isNotEmpty; k++) {
        b[random.nextInt(b.length)] = random.nextInt(256);
      }
    case 1:
      b.removeRange(at, min(b.length, at + 1 + random.nextInt(40)));
    case 2:
      final end = min(b.length, at + 1 + random.nextInt(200));
      b.insertAll(at, b.sublist(at, end));
    case 3:
      b.insertAll(at, utf8.encode(_tokens[random.nextInt(_tokens.length)]));
    default:
      b.removeRange(at, b.length);
  }
  return Uint8List.fromList(b);
}

bool _isPackageDocument(String path) =>
    path == 'META-INF/container.xml' ||
    path.endsWith('.opf') ||
    path.endsWith('.ncx') ||
    path.endsWith('nav.xhtml');

void main() {
  test('400 mutações: nenhuma exceção fora de EpubException', () async {
    final random = Random(20260926);
    final escaped = <String>[];
    var taxonomy = 0;
    var iteration = 0;
    final stopwatch = Stopwatch()..start();
    for (final book in _books) {
      final original = await _entries(book);
      final targets = original.keys.where(_isPackageDocument).toList();
      for (var k = 0; k < 100; k++, iteration++) {
        final files = Map.of(original);
        for (var m = 0; m < 1 + random.nextInt(3); m++) {
          final target = targets[random.nextInt(targets.length)];
          files[target] = _mutate(files[target]!, random);
        }
        final sink = DiagnosticSink(strict: iteration % 3 == 0);
        try {
          final container = iteration.isEven
              ? await ZipContainer.open(
                  MemoryEpubByteSource(epubZip(files, compress: false)),
                  sink: sink,
                )
              : await ProviderContainer.open(MapProvider(files), sink: sink);
          try {
            await readPublication(container, sink: sink);
          } finally {
            await container.close();
          }
        } on EpubException {
          taxonomy++;
        } on Object catch (e, stack) {
          escaped.add(
            '$book #$k: ${e.runtimeType}: $e\n'
            '${stack.toString().split('\n').take(6).join('\n')}',
          );
        }
      }
    }
    stopwatch.stop();
    // ignore: avoid_print
    print(
      'fuzz: $iteration casos, $taxonomy EpubException, ${escaped.length} '
      'fora, ${stopwatch.elapsedMilliseconds} ms',
    );
    expect(escaped, isEmpty, reason: escaped.join('\n\n'));
    expect(iteration, 400);
  });
}
