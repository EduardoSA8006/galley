import 'package:meta/meta.dart';
import 'package:xml/xml.dart';

import '../../../../core/diagnostics/diagnostic.dart';
import '../../../../core/diagnostics/diagnostic_codes.dart';
import '../../../../core/diagnostics/diagnostic_sink.dart';
import '../path/epub_path.dart';

const String _location = 'META-INF/encryption.xml';

/// Recurso do container cifrado ou ofuscado, conforme `encryption.xml`.
@immutable
final class EncryptedResource {
  /// Cria um recurso cifrado.
  const EncryptedResource({required this.path, required this.algorithm});

  /// Caminho do recurso na raiz do container (decodificado).
  final String path;

  /// URI do algoritmo de cifra/ofuscação.
  final String algorithm;

  @override
  bool operator ==(Object other) =>
      other is EncryptedResource &&
      other.path == path &&
      other.algorithm == algorithm;

  @override
  int get hashCode => Object.hash(path, algorithm);

  @override
  String toString() => 'EncryptedResource($path, $algorithm)';
}

/// Lê `META-INF/encryption.xml` e devolve os recursos cifrados na ordem do
/// documento.
///
/// Os elementos são casados pelo nome local, ignorando namespace. XML
/// inválido gera `encryption.invalid` e lista vazia; entradas sem `Algorithm`
/// ou `URI` são ignoradas com o mesmo diagnóstico (warning).
List<EncryptedResource> parseEncryptionXml(String xml, DiagnosticSink sink) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(xml);
  } on XmlException catch (e) {
    _report(sink, 'encryption.xml malformado: ${e.message}');
    return const [];
  }
  final result = <EncryptedResource>[];
  for (final data in doc.descendantElements.where(
    (e) => e.name.local == 'EncryptedData',
  )) {
    final algorithm = _first(
      data,
      'EncryptionMethod',
    )?.getAttribute('Algorithm');
    final uri = _first(data, 'CipherReference')?.getAttribute('URI');
    if (algorithm == null || algorithm.isEmpty || uri == null || uri.isEmpty) {
      _report(sink, 'EncryptedData sem Algorithm ou URI; ignorado.');
      continue;
    }
    final resolved = resolveHref(_location, '/$uri');
    if (resolved == null || resolved.path.isEmpty) {
      _report(sink, 'URI de CipherReference inválida: $uri');
      continue;
    }
    result.add(EncryptedResource(path: resolved.path, algorithm: algorithm));
  }
  return List.unmodifiable(result);
}

XmlElement? _first(XmlElement parent, String local) {
  for (final e in parent.descendantElements) {
    if (e.name.local == local) return e;
  }
  return null;
}

void _report(DiagnosticSink sink, String message) => sink.report(
  Diagnostic(
    severity: DiagnosticSeverity.warning,
    code: DiagnosticCodes.encryptionInvalid,
    message: message,
    location: _location,
  ),
);
