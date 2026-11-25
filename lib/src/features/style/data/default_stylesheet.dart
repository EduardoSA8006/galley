import '../../../core/diagnostics/diagnostic_sink.dart';
import '../domain/stylesheet.dart';
import 'stylesheet_builder.dart';

/// Texto da folha padrão (origem do agente, spec §8.9).
///
/// Vazia por enquanto: a seção "Rendering" do HTML entra numa etapa
/// seguinte. Nada além de [defaultStyleSheet] deve depender do conteúdo.
const String kDefaultStyleSheetCss = '';

/// A folha padrão interpretada, lida uma vez por isolate (na primeira
/// consulta) e compartilhada por todos os livros.
StyleSheet get defaultStyleSheet => _defaultStyleSheet;

final StyleSheet _defaultStyleSheet = buildStyleSheet(
  kDefaultStyleSheetCss,
  path: '',
  fontPrefix: '',
  sink: const NullDiagnosticSink(),
);
