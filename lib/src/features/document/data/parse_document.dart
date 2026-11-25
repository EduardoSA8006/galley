import 'dart:typed_data';

import 'package:xml/xml.dart';

import '../../../core/diagnostics/diagnostic.dart';
import '../../../core/diagnostics/diagnostic_codes.dart';
import '../../../core/diagnostics/diagnostic_sink.dart';
import '../../container/data/text/decode_text.dart';
import '../domain/document_head.dart';
import '../domain/names.dart';
import '../domain/parsed_document.dart';
import '../domain/tree_builder.dart';
import 'event_adapter.dart';
import 'head_extractor.dart';

/// Lê os [bytes] de um documento XHTML/SVG e monta a árvore.
///
/// Função pura e segura para isolate: devolve a árvore e os diagnósticos
/// como dados e nunca lança (qualquer falha vira o documento
/// irrecuperável). [path] é o caminho do documento no EPUB, usado
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
  try {
    final text = decodeText(bytes);
    final adapter = EventAdapter(path: path);
    final tree = adapter.run(text);
    final head = extractHead(
      tree,
      documentPath: path,
      sink: _ListSink(adapter.diagnostics),
    );
    return ParsedDocument(
      tree: tree,
      head: head,
      diagnostics: adapter.diagnostics,
      recovered: false,
    );
  } on XmlException catch (e) {
    return _unparseable(path, e.message);
  } on Object catch (e) {
    // Contrato "nunca lança": um defeito inesperado também vira capítulo
    // vazio, em vez de exceção crua.
    return _unparseable(path, 'erro inesperado (${e.runtimeType})');
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

/// Sink que acrescenta numa lista existente.
final class _ListSink implements DiagnosticSink {
  _ListSink(this._list);

  final List<Diagnostic> _list;

  @override
  void report(Diagnostic diagnostic) => _list.add(diagnostic);
}
