// Fuzz curto e determinístico do CSS (spec do CSS §14.2): mutações de folhas,
// de <style> e de style="" de quatro livros do corpus; nenhuma exceção fora
// de EpubException pode escapar, e fora de strict todo elemento tem estilo.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/container/byte_source.dart';
import 'package:galley/src/container/container.dart';
import 'package:galley/src/container/provider_container.dart';
import 'package:galley/src/container/zip/zip_container.dart';
import 'package:galley/src/css/cascade.dart';
import 'package:galley/src/css/loader.dart';
import 'package:galley/src/diagnostics/diagnostic.dart';
import 'package:galley/src/diagnostics/exceptions.dart';
import 'package:galley/src/publication/xml_text.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../publication/support/epub_fixtures.dart';

const _books = [
  'reais/pride-and-prejudice-en',
  'conteudo/text-transform-uppercase',
  'conteudo/css-import-cadeia',
  'conteudo/css-media-misto',
];

/// Trechos que costumam quebrar tokenizador, parser, seletores e loader.
const _tokens = [
  '{', '}', '(', ')', '[', ']', '"', "'", r'\', '/*', '*/', 'url(', //
  '@import "a.css";', '@import url(../../../x.css);', '@media',
  '@charset "utf-16";', '!important', ';', ':', ',', '+', '>', '~', '*',
  '#', '.', 'a a a a', ':nth-child(99999999999999999999)', '1e999em',
  '99999999999999999999px', r'\0', r'\FFFFFF', r'\D800', '<!--', '-->',
  'var(--x)', ':foo', '::-moz-x', ':not(', ':nth-child(3.0)',
  '.a.a.a.a.a.a.a.a.a.a.a.a.a.a.a.a.a.a.a.a.a.a.a.a.a.a.a.a.a.a.a.a.a',
  '&gt;', '<![CDATA[', ']]>', '\u0000', '﻿',
];

/// Bytes crus: BOM, Latin-1 e UTF-8 inválido.
const _rawBytes = [
  [0xEF, 0xBB, 0xBF],
  [0xE7, 0xE3],
  [0xC3],
  [0xFF, 0xFE],
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

List<int> _piece(Random random) => random.nextInt(8) == 0
    ? _rawBytes[random.nextInt(_rawBytes.length)]
    : utf8.encode(_tokens[random.nextInt(_tokens.length)]);

/// Uma mutação de folha: inserir, trocar, repetir ou cortar.
Uint8List _mutateSheet(Uint8List bytes, Random random) {
  final b = bytes.toList();
  final at = b.isEmpty ? 0 : random.nextInt(b.length);
  switch (random.nextInt(4)) {
    case 0:
      b.insertAll(at, _piece(random));
    case 1:
      b.replaceRange(
        at,
        min(b.length, at + 1 + random.nextInt(8)),
        _piece(random),
      );
    case 2:
      final piece = _piece(random);
      final times = 1 + random.nextInt(50); // sorteado uma vez: 1–50 uniforme
      b.insertAll(at, [for (var k = 0; k < times; k++) ...piece]);
    default:
      b.removeRange(at, min(b.length, at + 1 + random.nextInt(40)));
  }
  return Uint8List.fromList(b);
}

/// Uma mutação de seção: trechos logo depois de um `<style …>` ou de um
/// `style="`; sem nenhum, um `style=""` novo no primeiro `<p`.
Uint8List _mutateSection(Uint8List bytes, Random random) {
  final text = latin1.decode(bytes); // posições por byte
  final spots = <int>[];
  for (final marker in ['<style', 'style="']) {
    for (
      var i = text.indexOf(marker);
      i >= 0;
      i = text.indexOf(marker, i + 1)
    ) {
      final end = marker == '<style'
          ? text.indexOf('>', i)
          : i + marker.length - 1;
      if (end >= 0) spots.add(end + 1);
    }
  }
  final b = bytes.toList();
  if (spots.isEmpty) {
    final p = text.indexOf('<p');
    if (p < 0) return bytes;
    b.insertAll(p + 2, utf8.encode(' style="'));
    b.insertAll(p + 10, [..._piece(random), 0x22]);
  } else {
    final at = spots[random.nextInt(spots.length)];
    final pieces = 1 + random.nextInt(4);
    for (var k = 0; k < pieces; k++) {
      b.insertAll(at, _piece(random));
    }
  }
  return Uint8List.fromList(b);
}

bool _isSection(String path) =>
    (path.endsWith('.xhtml') || path.endsWith('.html')) &&
    !path.endsWith('nav.xhtml');

int _elements(Document document) {
  var n = 0;
  final root = document.documentElement;
  if (root == null) return 0;
  final stack = <Element>[root];
  while (stack.isNotEmpty) {
    final e = stack.removeLast();
    n++;
    if (e.localName == 'template') continue;
    stack.addAll(e.nodes.whereType<Element>());
  }
  return n;
}

/// Carrega e casca todas as seções de [files]; devolve as falhas de "todo
/// elemento tem estilo".
Future<List<String>> _cascade(
  EpubContainer container,
  Map<String, Uint8List> files, {
  required DiagnosticSink sink,
  required DiagnosticSink containerSink,
}) async {
  final problems = <String>[];
  final cache = StyleSheetCache();
  for (final path in files.keys.where(_isSection)) {
    final r = await container.fetch(path);
    if (r == null) continue;
    for (final _ in r.decode()) {}
    final document = html.parse(
      decodeXml(r.bytes, path: path, sink: DiagnosticSink(), htmlMeta: true),
    );
    final sheets = await loadSectionSheets(
      container,
      document,
      sectionPath: path,
      cache: cache,
      sink: sink,
      containerSink: containerSink,
    );
    final styles = computeStylesSync(
      document,
      sheets,
      sectionPath: path,
      sink: sink,
    );
    if (styles.length != _elements(document)) {
      problems.add('$path: ${styles.length} estilos');
    }
  }
  return problems;
}

void main() {
  test('400 mutações: nenhuma exceção fora de EpubException', () async {
    final random = Random(20260926);
    final escaped = <String>[];
    final missing = <String>[];
    var taxonomy = 0;
    var iteration = 0;
    for (final book in _books) {
      final original = await _entries(book);
      final sheets = original.keys.where((p) => p.endsWith('.css')).toList();
      final sections = original.keys.where(_isSection).toList();
      for (var k = 0; k < 100; k++, iteration++) {
        final files = Map.of(original);
        final mutations = 1 + random.nextInt(3);
        for (var m = 0; m < mutations; m++) {
          if (sheets.isNotEmpty && random.nextBool()) {
            final target = sheets[random.nextInt(sheets.length)];
            files[target] = _mutateSheet(files[target]!, random);
          } else {
            final target = sections[random.nextInt(sections.length)];
            files[target] = _mutateSection(files[target]!, random);
          }
        }
        final strict = iteration % 3 == 0;
        final containerSink = DiagnosticSink(strict: strict);
        final sink = DiagnosticSink(strict: strict);
        try {
          final container = iteration.isEven
              ? await ZipContainer.open(
                  MemoryEpubByteSource(epubZip(files, compress: false)),
                  sink: containerSink,
                )
              : await ProviderContainer.open(
                  MapProvider(files),
                  sink: containerSink,
                );
          try {
            final problems = await _cascade(
              container,
              files,
              sink: sink,
              containerSink: containerSink,
            );
            if (!strict) {
              missing.addAll([for (final p in problems) '$book #$k $p']);
            }
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
    // ignore: avoid_print
    print(
      'fuzz: $iteration casos, $taxonomy EpubException, ${escaped.length} fora',
    );
    expect(escaped, isEmpty, reason: escaped.join('\n\n'));
    expect(missing, isEmpty, reason: missing.join('\n'));
    expect(iteration, 400);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
