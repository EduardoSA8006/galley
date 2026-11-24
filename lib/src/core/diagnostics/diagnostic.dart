import 'package:meta/meta.dart';

/// Gravidade de um [Diagnostic].
enum DiagnosticSeverity {
  /// Informação sem impacto na leitura.
  info,

  /// Problema recuperável; o conteúdo segue utilizável.
  warning,

  /// Problema que degrada ou impede parte do conteúdo.
  error,
}

/// Problema recuperável encontrado ao processar um EPUB.
@immutable
final class Diagnostic {
  /// Cria um diagnóstico.
  const Diagnostic({
    required this.severity,
    required this.code,
    required this.message,
    this.location,
  });

  /// Gravidade do problema.
  final DiagnosticSeverity severity;

  /// Código estável (ver `DiagnosticCodes`).
  final String code;

  /// Descrição legível.
  final String message;

  /// Onde ocorreu (caminho no EPUB, opcionalmente com detalhe).
  final String? location;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Diagnostic &&
          other.severity == severity &&
          other.code == code &&
          other.message == message &&
          other.location == location;

  @override
  int get hashCode => Object.hash(severity, code, message, location);

  @override
  String toString() =>
      'Diagnostic(${severity.name}, $code, $message'
      '${location == null ? '' : ', $location'})';
}
