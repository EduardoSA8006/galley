import 'dart:convert';
import 'dart:typed_data';

import 'package:galley/src/features/document/data/parse_document.dart';
import 'package:galley/src/features/document/domain/document_tree.dart';
import 'package:galley/src/features/style/data/book_style_context.dart';
import 'package:galley/src/features/style/data/style_document.dart';
import 'package:galley/src/features/style/domain/computed_style.dart';
import 'package:galley/src/features/style/domain/matched_document.dart';
import 'package:galley/src/features/style/domain/reader_preferences.dart';
import 'package:galley/src/features/style/domain/restyle.dart';
import 'package:galley/src/features/style/domain/style_environment.dart';
import 'package:galley/src/features/style/domain/styled_document.dart';
import 'package:galley/src/features/style/domain/stylesheet.dart';

/// Ambiente padrão dos testes de estilo.
const StyleEnvironment testEnvironment = StyleEnvironment(
  pageWidth: 500,
  pageHeight: 800,
);

/// Casa o documento com [body] dentro de `<body>` e a folha [css] num
/// `<style>`, no [environment]; **sem** folha padrão (`StyleSheet.empty`),
/// a menos que [defaultSheet] peça a real.
MatchedDocument matchCss(
  String body, {
  String css = '',
  StyleEnvironment environment = testEnvironment,
  bool defaultSheet = false,
}) => matchSource(
  '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
  '<style>$css</style></head><body>$body</body></html>',
  environment: environment,
  defaultSheet: defaultSheet,
);

/// Casa o documento [source] inteiro (com o [mediaType] dado); **sem**
/// folha padrão, a menos que [defaultSheet] peça a real.
MatchedDocument matchSource(
  String source, {
  String mediaType = 'application/xhtml+xml',
  StyleEnvironment environment = testEnvironment,
  bool defaultSheet = false,
}) {
  final document = parseDocumentBytes(
    Uint8List.fromList(utf8.encode(source)),
    path: 'OEBPS/ch.xhtml',
    mediaType: mediaType,
  );
  final context = BookStyleContext(resolve: (_) => null, bookKey: 'livro');
  return matchDocument(
    context,
    document,
    environment,
    userAgentSheet: defaultSheet ? null : StyleSheet.empty,
  );
}

/// [matchCss] seguido de `restyle` sem preferências.
StyledDocument styleCss(
  String body, {
  String css = '',
  bool defaultSheet = false,
}) => restyle(
  matchCss(body, css: css, defaultSheet: defaultSheet),
  ReaderPreferences.none,
);

/// Elementos de nome [name], em ordem de documento.
List<int> elementsNamed(DocumentTree tree, String name) => [
  for (var n = 0; n < tree.nodeCount; n++)
    if (tree.kindOf(n) == NodeKind.element && tree.localNameOf(n) == name) n,
];

/// Estilo calculado do [element].
ComputedStyle styleOfElement(StyledDocument s, int element) =>
    s.styles[s.elementStyles[element]];
