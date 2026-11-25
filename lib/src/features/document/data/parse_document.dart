import 'dart:typed_data';

import 'package:xml/xml.dart';

import '../../../core/diagnostics/diagnostic.dart';
import '../../../core/diagnostics/diagnostic_codes.dart';
import '../../container/data/text/decode_text.dart';
import '../domain/document_head.dart';
import '../domain/names.dart';
import '../domain/parsed_document.dart';
import '../domain/tree_builder.dart';
import 'event_adapter.dart';

/// Lê os [bytes] de um documento XHTML/SVG e monta a árvore.
///
/// Função pura e segura para isolate: devolve a árvore e os diagnósticos
/// como dados e nunca lança. [path] é o caminho do documento no EPUB, usado
/// como local dos diagnósticos. [mediaType] é o do item do manifest; por
/// enquanto todo documento passa pelo caminho estrito.
///
/// Um documento que não é XML bem formado vira uma árvore com `<html>` e
/// `<body>` virtuais e vazios, com o diagnóstico `document.unparseable`.
ParsedDocument parseDocumentBytes(
  Uint8List bytes, {
  required String path,
  String mediaType = 'application/xhtml+xml',
}) {
  final text = decodeText(bytes);
  try {
    final adapter = EventAdapter(path: path);
    final tree = adapter.run(text);
    return ParsedDocument(
      tree: tree,
      head: DocumentHead.empty,
      diagnostics: adapter.diagnostics,
      recovered: false,
    );
  } on XmlException catch (e) {
    return _unparseable(path, e.message);
  }
}

/// Documento irrecuperável: `<html><body/></html>` virtuais.
ParsedDocument _unparseable(String path, String reason) {
  final builder = TreeBuilder();
  final names = builder.names;
  builder
    ..startElement(names.intern(Namespaces.xhtml, 'html'), virtual: true)
    ..startElement(names.intern(Namespaces.xhtml, 'body'), virtual: true)
    ..endElement()
    ..endElement();
  return ParsedDocument(
    tree: builder.build(),
    head: DocumentHead.empty,
    diagnostics: [
      Diagnostic(
        severity: DiagnosticSeverity.error,
        code: DiagnosticCodes.unparseable,
        message: 'documento irrecuperável: $reason',
        location: path,
      ),
    ],
    recovered: true,
  );
}
