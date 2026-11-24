import 'dart:async';

import 'diagnostic.dart';

/// Destino dos diagnósticos emitidos durante o processamento.
abstract interface class DiagnosticSink {
  /// Registra um [diagnostic].
  void report(Diagnostic diagnostic);
}

/// [DiagnosticSink] que acumula os diagnósticos e os emite em um stream.
final class CollectingDiagnosticSink implements DiagnosticSink {
  final List<Diagnostic> _diagnostics = [];
  final StreamController<Diagnostic> _controller =
      StreamController<Diagnostic>.broadcast(sync: true);

  /// Diagnósticos acumulados até o momento (visão não modificável).
  List<Diagnostic> get diagnostics => List.unmodifiable(_diagnostics);

  /// Stream broadcast dos diagnósticos reportados após a assinatura.
  Stream<Diagnostic> get stream => _controller.stream;

  @override
  void report(Diagnostic diagnostic) {
    _diagnostics.add(diagnostic);
    _controller.add(diagnostic);
  }
}

/// [DiagnosticSink] que descarta tudo; valor padrão `const`.
final class NullDiagnosticSink implements DiagnosticSink {
  /// Cria o sink descartável.
  const NullDiagnosticSink();

  @override
  void report(Diagnostic diagnostic) {}
}
