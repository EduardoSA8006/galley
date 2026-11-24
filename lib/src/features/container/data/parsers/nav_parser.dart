import 'package:xml/xml.dart';

import '../../../../core/diagnostics/diagnostic.dart';
import '../../../../core/diagnostics/diagnostic_codes.dart';
import '../../../../core/diagnostics/diagnostic_sink.dart';
import '../../domain/models/navigation.dart';
import '../path/epub_path.dart';

const String _opsNamespace = 'http://www.idpf.org/2007/ops';

/// Profundidade máxima de aninhamento aceita em navegação.
const int maxNavDepth = 64;

final RegExp _blank = RegExp(r'[ \t\r\n\f]+');

/// Colapsa espaços ASCII (preserva `&nbsp;`) e apara as pontas.
String collapseNavText(String s) => s.replaceAll(_blank, ' ').trim();

/// Converte um [href] em `(path, fragment)` ou `null` (externo/inválido).
ResolvedHref? resolveNavHref(String basePath, String? href) {
  if (href == null || href.trim().isEmpty) return null;
  return resolveHref(basePath, href.trim());
}

/// Lê o documento de navegação EPUB 3. `null` (+ `nav.invalid`) se não
/// parsear.
EpubNavigation? parseNavDocument(
  String xhtml, {
  required String navPath,
  required DiagnosticSink sink,
}) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(
      xhtml,
      entityMapping: XmlDefaultEntityMapping.html5(),
    );
  } on XmlException catch (e) {
    sink.report(
      Diagnostic(
        severity: DiagnosticSeverity.warning,
        code: DiagnosticCodes.navInvalid,
        message: 'Documento de navegação malformado: ${e.message}',
        location: navPath,
      ),
    );
    return null;
  }

  var tooDeepReported = false;
  void reportTooDeep() {
    if (tooDeepReported) return;
    tooDeepReported = true;
    sink.report(
      Diagnostic(
        severity: DiagnosticSeverity.warning,
        code: DiagnosticCodes.navTooDeep,
        message: 'Navegação aninhada além de $maxNavDepth níveis; truncada.',
        location: navPath,
      ),
    );
  }

  List<NavPoint> readList(XmlElement ol, int depth) {
    if (depth > maxNavDepth) {
      reportTooDeep();
      return const [];
    }
    final points = <NavPoint>[];
    for (final li in ol.childElements) {
      if (li.name.local != 'li') continue;
      final point = _readItem(li, navPath, depth, readList);
      if (point != null) points.add(point);
    }
    return points;
  }

  List<NavPoint> readNav(XmlElement? nav) {
    if (nav == null) return const [];
    for (final ol in nav.descendantElements) {
      if (ol.name.local == 'ol') return readList(ol, 1);
    }
    return const [];
  }

  XmlElement? toc, pageList, landmarks;
  for (final nav in doc.descendantElements) {
    if (nav.name.local != 'nav') continue;
    final types = _types(nav);
    final role = nav.getAttribute('role');
    if (toc == null && (types.contains('toc') || role == 'doc-toc')) {
      toc = nav;
    } else if (pageList == null &&
        (types.contains('page-list') || role == 'doc-pagelist')) {
      pageList = nav;
    } else if (landmarks == null && types.contains('landmarks')) {
      landmarks = nav;
    }
  }

  return EpubNavigation(
    toc: readNav(toc),
    pageList: readNav(pageList),
    landmarks: readNav(landmarks),
  );
}

NavPoint? _readItem(
  XmlElement li,
  String navPath,
  int depth,
  List<NavPoint> Function(XmlElement ol, int depth) readList,
) {
  XmlElement? label;
  final children = <NavPoint>[];
  for (final c in li.childElements) {
    final n = c.name.local;
    if (label == null && (n == 'a' || n == 'span')) {
      label = c;
    } else if (n == 'ol') {
      children.addAll(readList(c, depth + 1));
    }
  }

  var text = label == null ? '' : collapseNavText(label.innerText);
  if (text.isEmpty && label != null) {
    text = collapseNavText(label.getAttribute('title') ?? '');
  }

  String? path, fragment, type;
  if (label != null && label.name.local == 'a') {
    final resolved = resolveNavHref(navPath, label.getAttribute('href'));
    path = resolved?.path;
    fragment = resolved?.fragment;
    final types = _typeTokens(label);
    type = types.isEmpty ? null : types.first;
  }

  if (text.isEmpty && path == null && children.isEmpty) return null;
  return NavPoint(
    label: text,
    path: path,
    fragment: fragment,
    type: type,
    children: children,
  );
}

List<String> _typeTokens(XmlElement e) {
  for (final a in e.attributes) {
    if (a.name.local != 'type') continue;
    if (a.name.namespaceUri == _opsNamespace || a.name.prefix == 'epub') {
      return a.value.split(_blank).where((t) => t.isNotEmpty).toList();
    }
  }
  return const [];
}

Set<String> _types(XmlElement e) => _typeTokens(e).toSet();
