/// Leitor de EPUB nativo em Dart/Flutter, sem WebView.
library;

export 'src/core/diagnostics/diagnostic.dart'
    show Diagnostic, DiagnosticSeverity;
export 'src/core/diagnostics/diagnostic_sink.dart'
    show CollectingDiagnosticSink, DiagnosticSink, NullDiagnosticSink;
export 'src/core/errors/galley_exception.dart';
