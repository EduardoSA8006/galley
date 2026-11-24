import 'dart:async';
import 'dart:collection';

import 'diagnostic.dart';

/// Destino dos diagnósticos emitidos durante o processamento.
abstract interface class DiagnosticSink {
  /// Registra um [diagnostic].
  void report(Diagnostic diagnostic);
}

/// [DiagnosticSink] que acumula os diagnósticos e os emite em um stream.
final class CollectingDiagnosticSink implements DiagnosticSink {
  final List<Diagnostic> _diagnostics = [];
  late final List<Diagnostic> _view = UnmodifiableListView(_diagnostics);
  final StreamController<Diagnostic> _controller =
      StreamController<Diagnostic>.broadcast(sync: true);

  /// Diagnósticos acumulados (visão viva e não modificável, sempre a mesma
  /// instância; reflete os diagnósticos reportados depois da leitura).
  List<Diagnostic> get diagnostics => _view;

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
