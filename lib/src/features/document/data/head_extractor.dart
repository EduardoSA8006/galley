import '../../../core/diagnostics/diagnostic.dart';
import '../../../core/diagnostics/diagnostic_codes.dart';
import '../../../core/diagnostics/diagnostic_sink.dart';
import '../../container/data/path/epub_path.dart';
import '../domain/document_head.dart';
import '../domain/document_tree.dart';
import '../domain/names.dart';

final RegExp _whitespace = RegExp(r'\s+');

/// Extrai o `<head>` de [tree]: folhas de estilo (em ordem de documento),
/// título, `lang`, `dir` e viewport.
///
/// [documentPath] é o caminho do documento no zip, base dos `href`.
/// `<link>`/`<style>` dentro do `<body>` também são coletados, com
/// `document.headInBody`; hrefs externos ou que escapam do zip são
/// ignorados com `document.externalStyleSheet`.
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

  final sheets = <StyleSheetRef>[];
  for (final n in sheetNodes) {
    final isLink = tree.localNameOf(n) == 'link';
    if (isLink && !_isStyleSheetLink(tree, n)) continue;
    if (_hasAncestor(tree, n, 'body')) {
      sink.report(
        Diagnostic(
          severity: DiagnosticSeverity.info,
          code: DiagnosticCodes.headInBody,
          message: '<${tree.localNameOf(n)}> dentro do <body>; coletado',
          location: documentPath,
        ),
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
      sink.report(
        Diagnostic(
          severity: DiagnosticSeverity.info,
          code: DiagnosticCodes.externalStyleSheet,
          message: 'folha de estilo externa ou fora do zip ignorada: $href',
          location: documentPath,
        ),
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
    if (!_hasAncestor(tree, t, 'head')) continue;
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

  return DocumentHead(
    styleSheets: List.unmodifiable(sheets),
    title: title,
    lang: html == null
        ? null
        : tree.attribute(html, Namespaces.none, 'lang') ??
              tree.attribute(html, Namespaces.xml, 'lang'),
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

/// Há um ancestral XHTML de nome [localName]?
bool _hasAncestor(DocumentTree tree, int element, String localName) {
  var n = tree.parentOf(element);
  while (n > tree.documentNode) {
    if (tree.kindOf(n) == NodeKind.element &&
        tree.namespaceOf(n) == Namespaces.xhtml &&
        tree.localNameOf(n) == localName) {
      return true;
    }
    n = tree.parentOf(n);
  }
  return false;
}

String _textContent(DocumentTree tree, int element) {
  final buffer = StringBuffer();
  for (final c in tree.childrenOf(element)) {
    if (tree.kindOf(c) == NodeKind.text) buffer.write(tree.textOf(c));
  }
  return buffer.toString();
}
