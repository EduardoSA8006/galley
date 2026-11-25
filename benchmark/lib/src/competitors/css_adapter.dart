// ignore_for_file: implementation_imports

import 'dart:io';

import 'package:csslib/parser.dart' as csslib;
import 'package:csslib/visitor.dart' as csslib_tree;
import 'package:galley/galley.dart';
import 'package:galley/src/features/style/data/css_decode.dart';
import 'package:galley/src/features/style/data/stylesheet_builder.dart';
import 'package:galley/src/features/style/domain/stylesheet.dart';

import '../peak_rss.dart';
import 'measure.dart' show exitMeasureFailure, exitMeasureUsage;

/// Leitor de folhas CSS para a comparação informativa (`compare`).
///
/// Mede só a leitura (texto da folha → estrutura de regras): o texto já
/// está na memória.
abstract interface class CssParser {
  /// Nome do parser (`galley-css` ou `csslib`).
  String get name;

  /// Lê todas as [sheets] e mantém os resultados vivos até o fim (o pico de
  /// memória precisa contá-los). Devolve o total de regras, que é o
  /// checksum (os dois contam as regras de topo, incluindo at-rules).
  int parseAll(List<String> sheets);
}

/// `buildStyleSheet` do Galley (tokenização, seletores e propriedades já
/// interpretados). Checksum: total de regras da folha.
final class GalleyCssParser implements CssParser {
  @override
  String get name => 'galley-css';

  @override
  int parseAll(List<String> sheets) {
    final parsed = <StyleSheet>[
      for (var i = 0; i < sheets.length; i++)
        buildStyleSheet(
          sheets[i],
          path: 'OEBPS/sheet$i.css',
          fontPrefix: 'gf0-',
          sink: const NullDiagnosticSink(),
        ),
    ];
    var rules = 0;
    for (final sheet in parsed) {
      rules += sheet.rules.length;
    }
    return rules;
  }
}

/// `parse` de `package:csslib` (árvore de sintaxe completa). Checksum:
/// total de `topLevels`.
final class CsslibParser implements CssParser {
  @override
  String get name => 'csslib';

  @override
  int parseAll(List<String> sheets) {
    final parsed = <csslib_tree.StyleSheet>[
      for (final css in sheets) csslib.parse(css),
    ];
    var topLevels = 0;
    for (final sheet in parsed) {
      topLevels += sheet.topLevels.length;
    }
    return topLevels;
  }
}

/// Carrega as folhas de [path]: num `.epub`, todos os recursos `text/css`
/// do manifest (na ordem do manifest, cada caminho uma vez, decodificados
/// por `decodeCss`); em qualquer outro arquivo, o próprio arquivo (também
/// por `decodeCss`).
Future<List<String>> loadStyleSheets(String path) async {
  if (!path.endsWith('.epub')) {
    return [decodeCss(File(path).readAsBytesSync())];
  }
  final book = await EpubBook.fromBytes(File(path).readAsBytesSync());
  try {
    final seen = <String>{};
    return [
      for (final item in book.manifest.values)
        if (item.mediaType == 'text/css' && seen.add(item.path))
          decodeCss(await book.resource(item.path)),
    ];
  } finally {
    await book.close();
  }
}

/// Mede a leitura das folhas de [path] com [parser] e escreve `ns=`, `rss=`
/// e `checksum=` em [out], no mesmo formato do `runDocumentMeasure`.
///
/// O tempo cobre só a leitura das folhas (a do arquivo e a decodificação
/// ficam de fora); `rss` é o pico (`VmHWM`) lido no fim. Devolve 0 ou
/// [exitMeasureFailure].
Future<int> runCssMeasure(
  CssParser parser,
  String kind,
  String path, {
  required StringSink out,
  required StringSink err,
}) async {
  if (kind != 'parse') {
    err.writeln('Medida desconhecida: $kind (use parse)');
    return exitMeasureUsage;
  }
  try {
    final sheets = await loadStyleSheets(path);
    final clock = Stopwatch()..start();
    final checksum = parser.parseAll(sheets);
    clock.stop();
    final ns = (clock.elapsedTicks * 1e9 / clock.frequency).round();
    out
      ..writeln('ns=$ns')
      ..writeln('rss=${peakRssBytes()}')
      ..writeln('checksum=$checksum');
    return 0;
  } on Object catch (e, st) {
    err.writeln('Falha em ${parser.name} (parse): $e\n$st');
    return exitMeasureFailure;
  }
}
