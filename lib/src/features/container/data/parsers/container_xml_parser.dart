import 'package:xml/xml.dart';

import '../../../../core/diagnostics/diagnostic.dart';
import '../../../../core/diagnostics/diagnostic_codes.dart';
import '../../../../core/diagnostics/diagnostic_sink.dart';

const String _opfMediaType = 'application/oebps-package+xml';

/// Lê `META-INF/container.xml` e devolve o `full-path` de cada `rootfile` com
/// media-type de pacote OPF, na ordem do documento.
///
/// XML inválido gera `container.xmlInvalid` e lista vazia; mais de um rootfile
/// gera `container.multipleRenditions` (info).
List<String> parseContainerXml(String xml, DiagnosticSink sink) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(xml);
  } on XmlException catch (e) {
    sink.report(
      Diagnostic(
        severity: DiagnosticSeverity.error,
        code: DiagnosticCodes.containerXmlInvalid,
        message: 'container.xml malformado: ${e.message}',
        location: 'META-INF/container.xml',
      ),
    );
    return const [];
  }
  final paths = <String>[
    for (final e in doc.findAllElements('rootfile'))
      if (e.getAttribute('media-type') == _opfMediaType &&
          (e.getAttribute('full-path') ?? '').isNotEmpty)
        e.getAttribute('full-path')!,
  ];
  if (paths.length > 1) {
    sink.report(
      Diagnostic(
        severity: DiagnosticSeverity.info,
        code: DiagnosticCodes.containerMultipleRenditions,
        message: 'O container declara ${paths.length} rootfiles.',
        location: 'META-INF/container.xml',
      ),
    );
  }
  return paths;
}
