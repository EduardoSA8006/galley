/// NCX do EPUB2 com `package:xml` (spec da Publicação §7.3).
///
/// Linear no tamanho do NCX: um parse, e cada `navPoint`/`pageTarget` olha
/// só os próprios filhos diretos (o rótulo vem do texto direto de
/// `navLabel/text`, nunca de `innerText`); a recursão por nível para em
/// [maxNavDepth] e a contagem em [maxNavEntries], como no NAV.
library;

import 'package:xml/xml.dart';

import 'nav.dart';

/// O que o NCX fornece.
final class NcxDocument {
  NcxDocument({
    required List<NavEntry> toc,
    required List<NavEntry> pageList,
    required this.truncated,
  }) : toc = List.unmodifiable(toc),
       pageList = List.unmodifiable(pageList);

  final List<NavEntry> toc;
  final List<NavEntry> pageList;

  /// Algum limite de §7.2 foi atingido; a parte lida está nas listas.
  final bool truncated;
}

/// `navMap/navPoint` recursivo e `pageList/pageTarget`, por nome local.
/// `playOrder` é ignorado. [XmlException] com XML inválido.
NcxDocument parseNcx(String text) {
  final root = XmlDocument.parse(text).rootElement;
  final navMap = _child(root, 'navMap');
  final pageList = _child(root, 'pageList');
  final tocCount = _Count();
  final pageCount = _Count();
  return NcxDocument(
    toc: navMap == null ? const [] : _points(navMap, 'navPoint', 1, tocCount),
    pageList: pageList == null
        ? const []
        : _points(pageList, 'pageTarget', 1, pageCount),
    truncated: tocCount.truncated || pageCount.truncated,
  );
}

final class _Count {
  int count = 0;
  bool truncated = false;
}

List<NavEntry> _points(XmlElement parent, String local, int depth, _Count c) {
  final out = <NavEntry>[];
  for (final e in parent.childElements) {
    if (e.name.local != local) continue;
    // Só marca truncado se existe um navPoint/pageTarget além do limite (não
    // em toda chamada recursiva, mesmo sem filho algum) — como o NAV faz em
    // lib/src/publication/nav.dart:179.
    if (depth > maxNavDepth) {
      c.truncated = true;
      break;
    }
    if (c.count >= maxNavEntries) {
      c.truncated = true;
      break;
    }
    c.count++;
    final label = _child(e, 'navLabel');
    final text = label == null ? null : _child(label, 'text');
    out.add(
      NavEntry(
        title: text == null ? '' : _ownText(text),
        href: _child(e, 'content')?.getAttribute('src', namespaceUri: '*'),
        children: local == 'navPoint'
            ? _points(e, local, depth + 1, c)
            : const [],
      ),
    );
  }
  return out;
}

XmlElement? _child(XmlElement parent, String local) {
  for (final e in parent.childElements) {
    if (e.name.local == local) return e;
  }
  return null;
}

/// Whitespace do XML (U+00A0 não entra: é conteúdo).
final RegExp _whitespace = RegExp(r'[ \t\n\r]+');

String _ownText(XmlElement e) {
  final buffer = StringBuffer();
  for (final node in e.children) {
    if (node is XmlText) {
      buffer.write(node.value);
    } else if (node is XmlCDATA) {
      buffer.write(node.value);
    }
  }
  return buffer.toString().replaceAll(_whitespace, ' ').trim();
}
