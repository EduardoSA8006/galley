import 'package:meta/meta.dart';

import '../../../core/diagnostics/diagnostic.dart';
import '../../../core/diagnostics/diagnostic_codes.dart';
import '../../../core/diagnostics/diagnostic_sink.dart';
import '../../../core/diagnostics/limited_diagnostic_sink.dart';
import '../../document/domain/names.dart';
import '../../document/domain/parsed_document.dart';
import '../domain/cascade.dart';
import '../domain/css_value.dart';
import '../domain/matched_document.dart';
import '../domain/rule_index.dart';
import '../domain/selector_matcher.dart';
import '../domain/style_environment.dart';
import '../domain/stylesheet.dart';
import 'book_style_context.dart';
import 'css_syntax.dart';
import 'css_tokenizer.dart';
import 'default_stylesheet.dart';
import 'property_parser.dart';

/// Quantos textos de `style=` distintos o último [matchDocument] leu.
@visibleForTesting
int styleAttributeParses = 0;

/// Casamentos completos (`SelectorMatcher.fullMatchAttempts`) do último
/// [matchDocument].
@visibleForTesting
int lastFullMatchAttempts = 0;

/// Casa as folhas do livro com o [document] no [environment] e monta a
/// cascata da editora (passos 1–3 da spec §8.1): o [MatchedDocument]
/// guardado, sobre o qual o SP4 calcula os estilos.
///
/// As folhas vêm de [context] (cache por livro) para o `<head>` do
/// documento; as condições `media` do `<link>`/`@import`, os `@media` das
/// regras e os do `@page` são avaliados aqui e registrados para
/// [MatchedDocument.isValidFor]. `style=` é lido uma vez por texto distinto,
/// relativo ao documento.
///
/// Os diagnósticos do documento (`<style>`, `style=`) vão para [sink]
/// limitados por código ([LimitedDiagnosticSink]), com o resumo no fim. A
/// folha padrão é [defaultStyleSheet], ou [userAgentSheet] nos testes.
MatchedDocument matchDocument(
  BookStyleContext context,
  ParsedDocument document,
  StyleEnvironment environment, {
  DiagnosticSink? sink,
  @visibleForTesting StyleSheet? userAgentSheet,
}) {
  final limited = LimitedDiagnosticSink(sink ?? const NullDiagnosticSink());
  final path = document.path;
  final tree = document.tree;
  final entries = context.sheetsFor(
    document.head,
    documentPath: path,
    sink: limited,
  );

  final media = MediaChecks(environment);
  final rules = <IndexedRule>[];
  final fontFaces = <FontFaceRule>[];
  final fontSheets = Set<StyleSheet>.identity();
  CssLengthSpec? top, right, bottom, left;
  var anyMargin = false;

  void addSheet(StyleSheet sheet, {required bool userAgent}) {
    for (final rule in sheet.rules) {
      if (media.all(rule.conditions)) {
        rules.add(IndexedRule(rule, userAgent: userAgent));
      }
    }
    for (final (margins, conditions) in sheet.pages) {
      if (!media.all(conditions)) continue;
      if (margins.top != null) top = margins.top;
      if (margins.right != null) right = margins.right;
      if (margins.bottom != null) bottom = margins.bottom;
      if (margins.left != null) left = margins.left;
      anyMargin = anyMargin || margins != const PageMargins();
    }
    if (fontSheets.add(sheet)) fontFaces.addAll(sheet.fontFaces);
  }

  addSheet(userAgentSheet ?? defaultStyleSheet, userAgent: true);
  for (final entry in entries) {
    if (media.all(entry.conditions)) addSheet(entry.sheet, userAgent: false);
  }

  final ruleIndex = RuleIndex(rules);
  final matcher = SelectorMatcher(tree, documentLang: document.head.lang);
  final styleName = tree.names.lookup(Namespaces.none, 'style');
  final inlineCache = <String, List<Declaration>>{};
  styleAttributeParses = 0;

  List<Declaration>? inlineStyle(int element) {
    if (styleName == null) return null;
    final text = tree.attributeById(element, styleName);
    if (text == null) return null;
    return inlineCache[text] ??= _parseStyleAttribute(text, path, limited);
  }

  final result = cascadeDocument(
    tree: tree,
    index: ruleIndex.bind(tree),
    rules: ruleIndex.rules,
    matcher: matcher,
    inlineStyle: inlineStyle,
    fontFaces: fontFaces,
    pageMargins: anyMargin
        ? PageMargins(top: top, right: right, bottom: bottom, left: left)
        : null,
    media: media,
  );
  // Só alimenta o contador de teste acima; não é usado no resultado.
  // ignore: invalid_use_of_visible_for_testing_member
  lastFullMatchAttempts = matcher.fullMatchAttempts;
  limited.flush();
  return result;
}

/// Lê o texto de um `style=` como lista de declarações (com `url()`
/// relativo ao documento em [path]).
List<Declaration> _parseStyleAttribute(
  String text,
  String path,
  DiagnosticSink sink,
) {
  styleAttributeParses++;
  final raw = parseCssDeclarations(text, location: path, sink: sink);
  final out = <Declaration>[];
  String? source;
  for (final d in raw) {
    switch (parseProperty(d.name, d.value, sheetPath: path)) {
      case ParsedLonghands(:final values):
        for (final (id, value) in values) {
          out.add(Declaration(id, value, important: d.important));
        }
      case UnsupportedProperty():
        sink.report(
          Diagnostic(
            severity: DiagnosticSeverity.info,
            code: DiagnosticCodes.cssUnsupportedProperty,
            message: 'propriedade não suportada em style=: ${d.name}',
            location: path,
          ),
        );
      case InvalidValue():
        source ??= preprocessCss(text);
        sink.report(
          Diagnostic(
            severity: DiagnosticSeverity.info,
            code: DiagnosticCodes.cssInvalidValue,
            message:
                'valor inválido em style= para ${d.name}: '
                '${source.substring(d.valueStart, d.valueEnd)}',
            location: path,
          ),
        );
      case IgnoredProperty():
        break;
    }
  }
  return List.unmodifiable(out);
}
