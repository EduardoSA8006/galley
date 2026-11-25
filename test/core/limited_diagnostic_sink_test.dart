import 'package:galley/src/core/diagnostics/diagnostic.dart';
import 'package:galley/src/core/diagnostics/diagnostic_sink.dart';
import 'package:galley/src/core/diagnostics/limited_diagnostic_sink.dart';
import 'package:flutter_test/flutter_test.dart';

Diagnostic _d(String code, int i, {DiagnosticSeverity? s}) => Diagnostic(
  severity: s ?? DiagnosticSeverity.warning,
  code: code,
  message: 'm$i',
  location: 'loc:$i',
);

void main() {
  test('25 relatos do mesmo código: 20 + 1 resumo', () {
    final target = CollectingDiagnosticSink();
    final sink = LimitedDiagnosticSink(target);
    for (var i = 0; i < 25; i++) {
      sink.report(_d('a.b', i, s: i == 0 ? DiagnosticSeverity.error : null));
    }
    expect(target.diagnostics, hasLength(20));
    sink.flush();
    expect(target.diagnostics, hasLength(21));
    final summary = target.diagnostics.last;
    expect(summary.message, contains('total 25'));
    expect(summary.message, contains('mais 5 ocorrência(s) de a.b'));
    expect(summary.severity, DiagnosticSeverity.error);
    expect(summary.location, 'loc:0');
  });

  test('códigos contados à parte e sem resumo abaixo do limite', () {
    final target = CollectingDiagnosticSink();
    final sink = LimitedDiagnosticSink(target);
    for (var i = 0; i < 22; i++) {
      sink.report(_d('x', i));
      sink.report(_d('y', i));
    }
    sink.report(_d('z', 0));
    sink.flush();
    expect(target.diagnostics, hasLength(20 + 20 + 1 + 2));
    expect(
      target.diagnostics.where((d) => d.message.contains('total 22')),
      hasLength(2),
    );
  });

  test('limite configurável', () {
    final target = CollectingDiagnosticSink();
    final sink = LimitedDiagnosticSink(target, limit: 2);
    for (var i = 0; i < 5; i++) {
      sink.report(_d('x', i));
    }
    sink.flush();
    expect(target.diagnostics, hasLength(3));
  });
}
