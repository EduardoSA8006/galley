import 'package:xml/xml.dart';

import '../../../../core/diagnostics/diagnostic.dart';
import '../../../../core/diagnostics/diagnostic_codes.dart';
import '../../../../core/diagnostics/diagnostic_sink.dart';
import '../../domain/models/navigation.dart';
import 'nav_parser.dart';

/// Lê um NCX (EPUB 2). `null` (+ `ncx.invalid`) se não parsear.
EpubNavigation? parseNcx(
  String xml, {
  required String ncxPath,
  required DiagnosticSink sink,
}) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(xml);
  } on XmlException catch (e) {
    sink.report(
      Diagnostic(
        severity: DiagnosticSeverity.warning,
        code: DiagnosticCodes.ncxInvalid,
        message: 'NCX malformado: ${e.message}',
        location: ncxPath,
      ),
    );
    return null;
  }

  var tooDeepReported = false;

  NavPoint? readPoint(XmlElement e, int depth) {
    final children = <NavPoint>[];
    if (depth >= maxNavDepth) {
      if (!tooDeepReported) {
        tooDeepReported = true;
        sink.report(
          Diagnostic(
            severity: DiagnosticSeverity.warning,
            code: DiagnosticCodes.navTooDeep,
            message:
                'Navegação aninhada além de $maxNavDepth níveis; truncada.',
            location: ncxPath,
          ),
        );
      }
    } else {
      children.addAll(_readLevel(e, 'navPoint', depth + 1, readPoint));
    }
    final label = _label(e);
    final resolved = resolveNavHref(
      ncxPath,
      _child(e, 'content')?.getAttribute('src'),
    );
    if (label.isEmpty && resolved == null && children.isEmpty) return null;
    return NavPoint(
      label: label,
      path: resolved?.path,
      fragment: resolved?.fragment,
      children: children,
    );
  }

  final root = doc.rootElement;
  final navMap = _child(root, 'navMap');
  final pageList = _child(root, 'pageList');
  return EpubNavigation(
    toc: navMap == null
        ? const []
        : _readLevel(navMap, 'navPoint', 1, readPoint),
    pageList: pageList == null
        ? const []
        : _readLevel(pageList, 'pageTarget', 1, readPoint),
  );
}

List<NavPoint> _readLevel(
  XmlElement parent,
  String name,
  int depth,
  NavPoint? Function(XmlElement e, int depth) read,
) {
  final entries = <(int?, NavPoint)>[];
  for (final e in parent.childElements) {
    if (e.name.local != name) continue;
    final p = read(e, depth);
    if (p == null) continue;
    entries.add((int.tryParse(e.getAttribute('playOrder') ?? ''), p));
  }
  if (entries.length > 1 && entries.every((e) => e.$1 != null)) {
    // sort estável: desempata pela ordem do documento.
    final indexed = [for (var i = 0; i < entries.length; i++) (i, entries[i])];
    indexed.sort((a, b) {
      final c = a.$2.$1!.compareTo(b.$2.$1!);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
    return [for (final i in indexed) i.$2.$2];
  }
  return [for (final e in entries) e.$2];
}

XmlElement? _child(XmlElement e, String local) {
  for (final c in e.childElements) {
    if (c.name.local == local) return c;
  }
  return null;
}

String _label(XmlElement e) {
  final navLabel = _child(e, 'navLabel');
  final text = navLabel == null ? null : _child(navLabel, 'text');
  return text == null ? '' : collapseNavText(text.innerText);
}
