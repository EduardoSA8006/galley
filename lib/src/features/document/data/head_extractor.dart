import 'dart:typed_data';

import '../../../core/diagnostics/diagnostic.dart';
import '../../../core/diagnostics/diagnostic_codes.dart';
import '../../../core/diagnostics/diagnostic_sink.dart';
import '../../container/data/path/epub_path.dart';
import '../domain/document_head.dart';
import '../domain/document_tree.dart';
import '../domain/names.dart';
import 'event_adapter.dart';

final RegExp _whitespace = RegExp(r'\s+');

/// Extrai o `<head>` de [tree]: folhas de estilo (em ordem de documento),
/// título, `lang`, `dir` e viewport.
///
/// [documentPath] é o caminho do documento no zip, base dos `href`.
/// `<link>`/`<style>` dentro do `<body>` também são coletados, com
/// `document.headInBody`; hrefs externos ou que escapam do zip são
/// ignorados com `document.externalStyleSheet`. Como no [EventAdapter],
/// cada código entra no máximo [EventAdapter.reportLimit] vezes; o
/// excedente vira um resumo com o total.
///
/// Linear no tamanho da árvore: "dentro do `<body>`/`<head>`" sai de uma
/// única passada em ordem de documento ([_Containment]), sem subir até a
/// raiz por elemento.
DocumentHead extractHead(
  DocumentTree tree, {
  required String documentPath,
  required DiagnosticSink sink,
}) {
  const xhtml = Namespaces.xhtml;
  final htmls = tree.elementsNamed(xhtml, 'html');
  final html = htmls.isEmpty ? null : htmls.first;

  final sheetNodes = <int>[
    ...tree.elementsNamed(xhtml, 'link'),
    ...tree.elementsNamed(xhtml, 'style'),
  ]..sort();

  final limited = _LimitedSink(sink, documentPath);
  _Containment? containment;
  _Containment within() => containment ??= _Containment(tree);

  final sheets = <StyleSheetRef>[];
  for (final n in sheetNodes) {
    final isLink = tree.localNameOf(n) == 'link';
    if (isLink && !_isStyleSheetLink(tree, n)) continue;
    if (within().inBody(n)) {
      limited.report(
        DiagnosticSeverity.info,
        DiagnosticCodes.headInBody,
        '<${tree.localNameOf(n)}> dentro do <body>; coletado',
      );
    }
    final media = tree.attribute(n, Namespaces.none, 'media');
    if (!isLink) {
      sheets.add(InlineStyleSheet(css: _textContent(tree, n), media: media));
      continue;
    }
    final href = tree.attribute(n, Namespaces.none, 'href');
    if (href == null || href.trim().isEmpty) continue;
    final resolved = resolveHref(documentPath, href.trim());
    if (resolved == null) {
      limited.report(
        DiagnosticSeverity.info,
        DiagnosticCodes.externalStyleSheet,
        'folha de estilo externa ou fora do zip ignorada: $href',
      );
      continue;
    }
    sheets.add(
      LinkedStyleSheet(
        path: resolved.path,
        media: media,
        title: tree.attribute(n, Namespaces.none, 'title'),
      ),
    );
  }

  String? title;
  for (final t in tree.elementsNamed(xhtml, 'title')) {
    if (!within().inHead(t)) continue;
    title = _textContent(tree, t).trim().replaceAll(_whitespace, ' ');
    break;
  }

  String? viewport;
  for (final m in tree.elementsNamed(xhtml, 'meta')) {
    final name = tree.attribute(m, Namespaces.none, 'name');
    if (name != null && name.trim().toLowerCase() == 'viewport') {
      viewport = tree.attribute(m, Namespaces.none, 'content');
      break;
    }
  }

  limited.flush();
  return DocumentHead(
    styleSheets: List.unmodifiable(sheets),
    title: title,
    lang: html == null ? null : _lang(tree, html),
    dir: html == null ? null : tree.attribute(html, Namespaces.none, 'dir'),
    viewport: viewport,
  );
}

bool _isStyleSheetLink(DocumentTree tree, int link) {
  final rel = tree.attribute(link, Namespaces.none, 'rel');
  if (rel == null) return false;
  for (final token in rel.split(_whitespace)) {
    if (token.toLowerCase() == 'stylesheet') return true;
  }
  return false;
}

/// Idioma de [html]: `xml:lang` vence `lang` quando os dois existem (HTML,
/// "The lang and xml:lang attributes"); o valor é aparado, e vazio quer
/// dizer idioma desconhecido (`null`).
String? _lang(DocumentTree tree, int html) {
  final value =
      tree.attribute(html, Namespaces.xml, 'lang') ??
      tree.attribute(html, Namespaces.none, 'lang');
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Quais nós estão dentro de um `<body>` ou `<head>` XHTML, numa única
/// passada: os nós estão em ordem de documento, então o pai vem sempre
/// antes do filho e herda a marca dele.
final class _Containment {
  _Containment(DocumentTree tree) : _marks = Uint8List(tree.nodeCount) {
    final body = tree.names.lookup(Namespaces.xhtml, 'body');
    final head = tree.names.lookup(Namespaces.xhtml, 'head');
    if (body == null && head == null) return;
    for (var n = 1; n < _marks.length; n++) {
      final parent = tree.parentOf(n);
      var mark = _marks[parent];
      if (tree.kindOf(parent) == NodeKind.element) {
        final name = tree.nameOf(parent);
        if (name == body) mark |= _body;
        if (name == head) mark |= _head;
      }
      _marks[n] = mark;
    }
  }

  static const int _body = 1;
  static const int _head = 2;

  final Uint8List _marks;

  /// [n] tem um ancestral `<body>` XHTML?
  bool inBody(int n) => _marks[n] & _body != 0;

  /// [n] tem um ancestral `<head>` XHTML?
  bool inHead(int n) => _marks[n] & _head != 0;
}

/// Repassa a [sink] no máximo [EventAdapter.reportLimit] diagnósticos de
/// cada código; [flush] acrescenta o resumo do excedente.
final class _LimitedSink {
  _LimitedSink(this._sink, this._location);

  final DiagnosticSink _sink;
  final String _location;
  final Map<String, int> _counts = {};
  final Map<String, DiagnosticSeverity> _severities = {};

  void report(DiagnosticSeverity severity, String code, String message) {
    final count = (_counts[code] ?? 0) + 1;
    _counts[code] = count;
    if (count > EventAdapter.reportLimit) return;
    _severities[code] = severity;
    _sink.report(
      Diagnostic(
        severity: severity,
        code: code,
        message: message,
        location: _location,
      ),
    );
  }

  void flush() {
    for (final MapEntry(key: code, value: count) in _counts.entries) {
      if (count <= EventAdapter.reportLimit) continue;
      _sink.report(
        Diagnostic(
          severity: _severities[code]!,
          code: code,
          message:
              'mais ${count - EventAdapter.reportLimit} ocorrência(s) de '
              '$code omitida(s) (total $count)',
          location: _location,
        ),
      );
    }
  }
}

String _textContent(DocumentTree tree, int element) {
  final buffer = StringBuffer();
  for (final c in tree.childrenOf(element)) {
    if (tree.kindOf(c) == NodeKind.text) buffer.write(tree.textOf(c));
  }
  return buffer.toString();
}
