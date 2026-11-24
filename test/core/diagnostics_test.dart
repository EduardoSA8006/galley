import 'package:flutter_test/flutter_test.dart';
import 'package:galley/galley.dart';

void main() {
  test('CollectingDiagnosticSink acumula e emite no stream', () async {
    final sink = CollectingDiagnosticSink();
    const d = Diagnostic(
      severity: DiagnosticSeverity.warning,
      code: 'x.y',
      message: 'm',
    );
    final next = sink.stream.first;
    sink.report(d);
    expect(sink.diagnostics, [d]);
    expect(await next, d);
    expect(() => (sink.diagnostics as List).add(d), throwsUnsupportedError);
  });

  test('Diagnostic tem igualdade por valor', () {
    const a = Diagnostic(
      severity: DiagnosticSeverity.info,
      code: 'a',
      message: 'b',
      location: 'c',
    );
    const b = Diagnostic(
      severity: DiagnosticSeverity.info,
      code: 'a',
      message: 'b',
      location: 'c',
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(
      a,
      isNot(
        const Diagnostic(
          severity: DiagnosticSeverity.info,
          code: 'a',
          message: 'b',
        ),
      ),
    );
  });

  test('NullDiagnosticSink descarta diagnósticos', () {
    const sink = NullDiagnosticSink();
    sink.report(
      const Diagnostic(
        severity: DiagnosticSeverity.error,
        code: 'x',
        message: 'm',
      ),
    );
  });
}
