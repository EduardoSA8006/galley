import 'diagnostic.dart';
import 'diagnostic_sink.dart';

/// Quantas ocorrências de cada código passam adiante; as demais viram um
/// único resumo com o total.
const int kDiagnosticReportLimit = 20;

/// Repassa a um [DiagnosticSink] no máximo [limit] diagnósticos de cada
/// código; [flush] acrescenta o resumo do excedente, com a gravidade e o
/// `location` da primeira ocorrência do código.
final class LimitedDiagnosticSink implements DiagnosticSink {
  /// Cria o limitador sobre [target].
  LimitedDiagnosticSink(this._target, {this.limit = kDiagnosticReportLimit});

  final DiagnosticSink _target;

  /// Máximo de ocorrências repassadas por código.
  final int limit;
  final Map<String, int> _counts = {};
  final Map<String, Diagnostic> _firsts = {};

  @override
  void report(Diagnostic diagnostic) {
    final count = (_counts[diagnostic.code] ?? 0) + 1;
    _counts[diagnostic.code] = count;
    if (count == 1) _firsts[diagnostic.code] = diagnostic;
    if (count > limit) return;
    _target.report(diagnostic);
  }

  /// Emite o resumo de cada código que excedeu o limite e zera a contagem.
  void flush() {
    for (final MapEntry(key: code, value: count) in _counts.entries) {
      if (count <= limit) continue;
      final first = _firsts[code]!;
      _target.report(
        Diagnostic(
          severity: first.severity,
          code: code,
          message:
              'mais ${count - limit} ocorrência(s) de $code omitida(s) '
              '(total $count)',
          location: first.location,
        ),
      );
    }
    _counts.clear();
    _firsts.clear();
  }
}
