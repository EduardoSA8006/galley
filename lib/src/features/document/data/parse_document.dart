import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:xml/xml.dart';

import '../../../core/diagnostics/diagnostic.dart';
import '../../../core/diagnostics/diagnostic_codes.dart';
import '../../../core/diagnostics/diagnostic_sink.dart';
import '../../container/data/text/decode_text.dart';
import '../../container/domain/epub_book.dart';
import '../domain/document_head.dart';
import '../domain/names.dart';
import '../domain/parsed_document.dart';
import '../domain/tree_builder.dart';
import 'event_adapter.dart';
import 'head_extractor.dart';
import 'recovery.dart';

/// Lê o documento em [path] do [book] e monta a árvore.
///
/// O media-type vem do manifest (sem item, `application/xhtml+xml`). Os
/// diagnósticos do documento também são repassados a [sink]. Um media-type
/// fora de `application/xhtml+xml`, `text/html` e `image/svg+xml` lança
/// [ArgumentError] (erro de programação do chamador); um [path] ausente do
/// livro propaga a `ResourceNotFoundException` de [EpubBook.resource].
/// Fora isso, ver [parseDocumentBytes] (nunca lança por conteúdo).
Future<ParsedDocument> parseDocument(
  EpubBook book,
  String path, {
  DiagnosticSink? sink,
}) async {
  final mediaType =
      book.manifestItemByPath(path)?.mediaType ?? 'application/xhtml+xml';
  if (!_supportedMediaTypes.contains(mediaType)) {
    throw ArgumentError.value(
      mediaType,
      'mediaType',
      'o documento "$path" não é XHTML, HTML nem SVG',
    );
  }
  final bytes = await book.resource(path);
  final document = parseDocumentBytes(bytes, path: path, mediaType: mediaType);
  if (sink != null) {
    document.diagnostics.forEach(sink.report);
  }
  return document;
}

const Set<String> _supportedMediaTypes = {
  'application/xhtml+xml',
  'text/html',
  'image/svg+xml',
};

/// Lê os [bytes] de um documento XHTML/HTML/SVG e monta a árvore.
///
/// Função pura e segura para isolate: devolve a árvore e os diagnósticos
/// como dados e nunca lança (qualquer falha vira o documento
/// irrecuperável). [path] é o caminho do documento no EPUB, usado
/// como local dos diagnósticos. [mediaType] é o do item do manifest.
///
/// O documento passa primeiro pelo caminho estrito. Se ele não é XML bem
/// formado, é lido de novo pelo modo tolerante ([TolerantRepairPolicy]),
/// com `document.recovered` (warning, na linha do erro original). Um
/// `text/html` vai direto para o modo tolerante, sem esse diagnóstico. Em
/// ambos os casos, [ParsedDocument.recovered] é `true`.
///
/// Um documento sem conteúdo (vazio, só espaços ou sem elemento nem texto)
/// vira uma árvore com `<html>` e `<body>` virtuais e vazios, com o
/// diagnóstico `document.unparseable`. Um defeito interno (exceção que
/// não é [XmlException]) também vira esse documento, com
/// [ParsedDocument.internalError] preenchido: sinal de bug do Galley.
ParsedDocument parseDocumentBytes(
  Uint8List bytes, {
  required String path,
  String mediaType = 'application/xhtml+xml',
}) {
  return guardParse(path, () {
    final text = decodeText(bytes);
    XmlException? failure;
    if (mediaType != 'text/html') {
      try {
        return _assemble(EventAdapter(path: path), text, path, null);
      } on XmlException catch (e) {
        failure = e;
      }
    }
    final adapter = EventAdapter(
      path: path,
      policy: TolerantRepairPolicy(html: mediaType == 'text/html'),
    );
    return _assemble(adapter, text, path, failure);
  });
}

/// O catch-all de [parseDocumentBytes]: roda [body] e transforma qualquer
/// exceção no documento irrecuperável de [path].
///
/// Uma [XmlException] é conteúdo ruim; qualquer outra coisa é defeito
/// interno e também preenche [ParsedDocument.internalError] com o tipo da
/// exceção. Separado só para os testes exercitarem esse caminho, que o
/// parse real não alcança sem um bug.
@visibleForTesting
ParsedDocument guardParse(String path, ParsedDocument Function() body) {
  try {
    return body();
  } on XmlException catch (e) {
    return _unparseable(path, e.message);
  } on Object catch (e) {
    // Contrato "nunca lança": um defeito inesperado também vira capítulo
    // vazio, em vez de exceção crua, marcado como erro interno.
    final type = '${e.runtimeType}';
    return _unparseable(path, 'erro inesperado ($type)', internalError: type);
  }
}

/// Monta a árvore de [text] com [adapter] e extrai o `<head>`. [failure],
/// se houver, é o erro do caminho estrito que levou ao modo tolerante.
ParsedDocument _assemble(
  EventAdapter adapter,
  String text,
  String path,
  XmlException? failure,
) {
  final tree = adapter.run(text);
  final diagnostics = <Diagnostic>[];
  if (failure != null) {
    final line = _lineOf(failure) ?? adapter.firstReportLine;
    diagnostics.add(
      Diagnostic(
        severity: DiagnosticSeverity.warning,
        code: DiagnosticCodes.recovered,
        message:
            'documento malformado (${failure.message}); '
            'lido pelo modo tolerante',
        location: line == null ? path : '$path:$line',
      ),
    );
  }
  diagnostics.addAll(adapter.diagnostics);
  final head = extractHead(
    tree,
    documentPath: path,
    sink: _ListSink(diagnostics),
  );
  return ParsedDocument(
    path: path,
    tree: tree,
    head: head,
    diagnostics: diagnostics,
    recovered: !adapter.policy.validating,
  );
}

/// Linha do erro do `package:xml`, se ele trouxer a posição.
int? _lineOf(XmlException e) => switch (e) {
  XmlFormatException(buffer: _?, position: _?, :final line) => line,
  _ => null,
};

/// Documento irrecuperável: `<html><body/></html>` virtuais.
ParsedDocument _unparseable(
  String path,
  String reason, {
  String? internalError,
}) {
  final builder = TreeBuilder();
  final names = builder.names;
  builder
    ..startElement(names.intern(Namespaces.xhtml, 'html'), virtual: true)
    ..startElement(names.intern(Namespaces.xhtml, 'body'), virtual: true)
    ..endElement()
    ..endElement();
  return ParsedDocument(
    path: path,
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
    internalError: internalError,
  );
}

/// Sink que acrescenta numa lista existente.
final class _ListSink implements DiagnosticSink {
  _ListSink(this._list);

  final List<Diagnostic> _list;

  @override
  void report(Diagnostic diagnostic) => _list.add(diagnostic);
}
