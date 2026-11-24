import 'package:xml/xml.dart';

import '../../../../core/diagnostics/diagnostic.dart';
import '../../../../core/diagnostics/diagnostic_codes.dart';
import '../../../../core/diagnostics/diagnostic_sink.dart';
import '../../domain/models/epub_metadata.dart';
import 'opf_xml.dart';

String _normalize(String text) => text.trim().replaceAll(RegExp(r'\s+'), ' ');

String? _textOrNull(XmlElement e) {
  final t = _normalize(e.innerText);
  return t.isEmpty ? null : t;
}

/// Determina a versão do EPUB a partir do elemento `<package>`.
///
/// `version` iniciando em `3` → [EpubVersion.epub3]; em `2` →
/// [EpubVersion.epub2]. Ausente ou inválida: epub3 se o manifest tiver item
/// com `properties` contendo `nav`, senão epub2, com `opf.versionInvalid`.
EpubVersion parseEpubVersion(XmlElement package, DiagnosticSink sink) {
  final version = package.getAttribute('version')?.trim() ?? '';
  if (version.startsWith('3')) return EpubVersion.epub3;
  if (version.startsWith('2')) return EpubVersion.epub2;

  final hasNav = package.descendantElements.any(
    (e) =>
        isOpfElement(e, 'item') &&
        (e.getAttribute('properties') ?? '')
            .split(RegExp(r'\s+'))
            .contains('nav'),
  );
  sink.report(
    Diagnostic(
      severity: DiagnosticSeverity.warning,
      code: DiagnosticCodes.opfVersionInvalid,
      message:
          'Atributo version ausente ou inválido ("$version"); '
          'assumindo ${hasNav ? 'EPUB 3 (item nav presente)' : 'EPUB 2'}.',
    ),
  );
  return hasNav ? EpubVersion.epub3 : EpubVersion.epub2;
}

/// Lê o `<metadata>` do OPF.
///
/// Elementos Dublin Core são reconhecidos pelo namespace, com qualquer
/// prefixo. Refinamentos EPUB 3 (`refines`) cujo alvo não exista são
/// ignorados. A leitura é leniente quanto à [version]: tanto os refinamentos
/// EPUB 3 quanto os atributos `opf:*` e `<meta name content>` do EPUB 2 são
/// aceitos em qualquer versão.
EpubMetadata parseOpfMetadata(
  XmlElement metadata, {
  required EpubVersion version,
  required String? uniqueIdentifierId,
  required DiagnosticSink sink,
}) {
  final children = metadata.childElements.toList();

  // Refinamentos: id -> propriedade -> valor (o primeiro vence).
  final refinements = <String, Map<String, String>>{};
  final otherMeta = <String, String>{};
  String? modified;
  for (final meta in children.where((e) => isOpfElement(e, 'meta'))) {
    final property = meta.getAttribute('property')?.trim();
    final refines = meta.getAttribute('refines')?.trim();
    final value = _textOrNull(meta);
    if (property != null && property.isNotEmpty) {
      if (value == null) continue;
      if (refines != null && refines.isNotEmpty) {
        final id = refines.startsWith('#') ? refines.substring(1) : refines;
        refinements
            .putIfAbsent(id, () => {})
            .putIfAbsent(property, () => value);
      } else if (property == 'dcterms:modified') {
        modified ??= value;
      } else {
        otherMeta.putIfAbsent(property, () => value);
      }
      continue;
    }
    final name = meta.getAttribute('name')?.trim();
    final content = meta.getAttribute('content');
    if (name != null && name.isNotEmpty && content != null) {
      otherMeta.putIfAbsent(name, () => content);
    }
  }

  String? refined(XmlElement e, String property) {
    final id = e.getAttribute('id');
    return id == null ? null : refinements[id]?[property];
  }

  EpubContributor? contributor(XmlElement e) {
    final name = _textOrNull(e);
    if (name == null) return null;
    return EpubContributor(
      name: name,
      fileAs: refined(e, 'file-as') ?? opfAttribute(e, 'file-as'),
      role: refined(e, 'role') ?? opfAttribute(e, 'role'),
    );
  }

  final titleElements = children.where((e) => isDcElement(e, 'title')).toList();
  final titleEntries = <({String text, bool main, int? seq, int index})>[];
  for (var i = 0; i < titleElements.length; i++) {
    final e = titleElements[i];
    final text = _textOrNull(e);
    if (text == null) continue;
    titleEntries.add((
      text: text,
      main: refined(e, 'title-type') == 'main',
      seq: int.tryParse(refined(e, 'display-seq') ?? ''),
      index: i,
    ));
  }
  titleEntries.sort((a, b) {
    if (a.main != b.main) return a.main ? -1 : 1;
    if (a.seq != b.seq) {
      if (a.seq == null) return 1;
      if (b.seq == null) return -1;
      return a.seq!.compareTo(b.seq!);
    }
    return a.index.compareTo(b.index);
  });
  final titles = [for (final t in titleEntries) t.text];

  if (titles.isEmpty) {
    sink.report(
      const Diagnostic(
        severity: DiagnosticSeverity.warning,
        code: DiagnosticCodes.opfTitleMissing,
        message: 'O OPF não declara nenhum dc:title.',
      ),
    );
  }

  final identifiers = <EpubIdentifier>[];
  String? uniqueIdentifier;
  for (final e in children.where((e) => isDcElement(e, 'identifier'))) {
    final value = _textOrNull(e);
    if (value == null) continue;
    final id = e.getAttribute('id');
    identifiers.add(
      EpubIdentifier(
        value: value,
        id: id,
        scheme: opfAttribute(e, 'scheme') ?? refined(e, 'identifier-type'),
      ),
    );
    if (uniqueIdentifier == null && id != null && id == uniqueIdentifierId) {
      uniqueIdentifier = value;
    }
  }
  if (uniqueIdentifier == null) {
    uniqueIdentifier = identifiers.firstOrNull?.value;
    sink.report(
      Diagnostic(
        severity: DiagnosticSeverity.warning,
        code: DiagnosticCodes.opfUniqueIdentifierMissing,
        message:
            'Nenhum dc:identifier com id "$uniqueIdentifierId"; '
            'usando o primeiro identificador.',
      ),
    );
  }

  List<String> texts(String local) => [
    for (final e in children.where((e) => isDcElement(e, local)))
      ?_textOrNull(e),
  ];

  return EpubMetadata(
    titles: titles,
    creators: [
      for (final e in children.where((e) => isDcElement(e, 'creator')))
        ?contributor(e),
    ],
    contributors: [
      for (final e in children.where((e) => isDcElement(e, 'contributor')))
        ?contributor(e),
    ],
    languages: texts('language'),
    identifiers: identifiers,
    uniqueIdentifier: uniqueIdentifier,
    publisher: texts('publisher').firstOrNull,
    description: texts('description').firstOrNull,
    subjects: texts('subject'),
    date: texts('date').firstOrNull,
    modified: modified,
    rights: texts('rights').firstOrNull,
    otherMeta: otherMeta,
  );
}
