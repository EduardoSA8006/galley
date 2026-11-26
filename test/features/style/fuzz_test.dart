import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/core/diagnostics/diagnostic_sink.dart';
import 'package:galley/src/features/document/data/parse_document.dart';
import 'package:galley/src/features/style/data/book_style_context.dart';
import 'package:galley/src/features/style/data/style_document.dart';
import 'package:galley/src/features/style/data/stylesheet_builder.dart';
import 'package:galley/src/features/style/domain/reader_preferences.dart';
import 'package:galley/src/features/style/domain/style_environment.dart';

import '../../support/publisher_css.dart';
import '../../support/synthetic_xhtml.dart';

const _env = StyleEnvironment(pageWidth: 500, pageHeight: 800);
const _limit = Duration(seconds: 2);

String _mutate(Random random) {
  var s = kPublisherCss;
  final steps = 1 + random.nextInt(4);
  for (var i = 0; i < steps; i++) {
    if (s.isEmpty) break;
    switch (random.nextInt(7)) {
      case 0: // truncar
        s = s.substring(0, random.nextInt(s.length));
      case 1: // trocar bytes
        final units = s.codeUnits.toList();
        for (var k = 0; k < 1 + random.nextInt(6); k++) {
          units[random.nextInt(units.length)] = random.nextInt(128);
        }
        s = String.fromCharCodes(units);
      case 2: // apagar ';'
        s = _deleteSome(s, ';', random);
      case 3: // apagar '{'
        s = _deleteSome(s, '{', random);
      case 4: // apagar '}'
        s = _deleteSome(s, '}', random);
      case 5: // duplicar um trecho
        final a = random.nextInt(s.length);
        final b = min(s.length, a + 1 + random.nextInt(200));
        s = s.replaceRange(b, b, s.substring(a, b));
      case 6: // inserir lixo
        const junk = ['@media(', r'\', '"', '/*', "'", 'url(', '{', '}'];
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
  test('2.000 variações da folha: nunca lança, < 2 s, sem erro interno', () {
    final random = Random(42);
    final failures = <String>[];
    // Documento fixo, pequeno, que liga a folha do fuzz.
    final document = parseDocumentBytes(
      syntheticXhtml(
        4 * 1024,
        head: '<link rel="stylesheet" href="estilo.css"/>',
      ),
      path: 'OEBPS/texto/cap.xhtml',
    );
    for (var i = 0; i < 2000; i++) {
      final css = _mutate(random);
      var watch = Stopwatch()..start();
      try {
        buildStyleSheet(
          css,
          path: 'OEBPS/texto/estilo.css',
          fontPrefix: 'gf00000000-',
          sink: const NullDiagnosticSink(),
        );
        watch.stop();
        if (watch.elapsed >= _limit) {
          failures.add(
            '#$i leitura lenta (${watch.elapsed}): ${jsonEncode(css)}',
          );
        }
        final bytes = Uint8List.fromList(utf8.encode(css));
        final context = BookStyleContext(
          resolve: (p) => p == 'OEBPS/texto/estilo.css' ? bytes : null,
          bookKey: 'fuzz',
        );
        watch = Stopwatch()..start();
        final styled = styleDocument(
          context,
          document,
          _env,
          ReaderPreferences.none,
        );
        watch.stop();
        if (styled.internalError != null) {
          failures.add(
            '#$i erro interno ${styled.internalError}: '
            '${jsonEncode(css)}',
          );
        }
        if (watch.elapsed >= _limit) {
          failures.add(
            '#$i estilo lento (${watch.elapsed}): ${jsonEncode(css)}',
          );
        }
      } on Object catch (e) {
        failures.add('#$i lançou $e: ${jsonEncode(css)}');
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
  });

  test('folha de 1 MiB com regras repetidas: lida em < 2 s', () {
    final b = StringBuffer();
    var i = 0;
    while (b.length < 1024 * 1024) {
      b.write(
        '.c$i p.texto > em, section#s$i a[href^="#"]::after '
        '{ margin: 0 ${i % 5}em; color: #${(i * 4099 % 0xFFFFFF).toRadixString(16).padLeft(6, '0')}; '
        'font: italic bold 1.${i % 9}em/1.4 "Livro Serif", serif; }\n',
      );
      i++;
    }
    final css = b.toString();
    final watch = Stopwatch()..start();
    final sheet = buildStyleSheet(
      css,
      path: 'OEBPS/grande.css',
      fontPrefix: 'gf00000000-',
      sink: const NullDiagnosticSink(),
    );
    watch.stop();
    expect(sheet.rules, isNotEmpty);
    expect(watch.elapsed, lessThan(_limit));
  });
}
