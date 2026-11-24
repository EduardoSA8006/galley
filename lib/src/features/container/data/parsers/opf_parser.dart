import 'package:xml/xml.dart';

import '../../../../core/diagnostics/diagnostic.dart';
import '../../../../core/diagnostics/diagnostic_codes.dart';
import '../../../../core/diagnostics/diagnostic_sink.dart';
import '../../../../core/errors/galley_exception.dart';
import '../../domain/models/manifest.dart';
import '../../domain/models/opf_document.dart';
import '../../domain/models/rendition.dart';
import '../../domain/models/spine.dart';
import '../path/epub_path.dart';
import 'opf_metadata_parser.dart';
import 'opf_xml.dart';

/// Interpreta o OPF em [xml], localizado em [opfPath] dentro do zip.
///
/// XML inválido ou raiz diferente de `package` lança
/// [MissingPackageDocumentException]. Todo o resto é recuperável e vira
/// [Diagnostic] em [sink].
OpfDocument parseOpf(
  String xml, {
  required String opfPath,
  required DiagnosticSink sink,
}) {
  final XmlElement package;
  try {
    package = XmlDocument.parse(xml).rootElement;
  } on XmlException catch (e) {
    throw MissingPackageDocumentException('OPF não é um XML válido: $e');
  }
  if (!isOpfElement(package, 'package')) {
    throw MissingPackageDocumentException(
      'A raiz do OPF é <${package.name.local}>, esperado <package>.',
    );
  }

  final version = parseEpubVersion(package, sink);
  final metadataElement = package.childElements
      .where((e) => isOpfElement(e, 'metadata'))
      .firstOrNull;
  final metadata = parseOpfMetadata(
    metadataElement ?? XmlElement(XmlName('metadata')),
    version: version,
    uniqueIdentifierId: package.getAttribute('unique-identifier'),
    sink: sink,
  );

  void warn(String code, String message) => sink.report(
    Diagnostic(
      severity: DiagnosticSeverity.warning,
      code: code,
      message: message,
      location: opfPath,
    ),
  );

  // Manifest.
  final manifest = <String, ManifestItem>{};
  final manifestElement = package.childElements
      .where((e) => isOpfElement(e, 'manifest'))
      .firstOrNull;
  for (final e in manifestElement?.childElements ?? const <XmlElement>[]) {
    if (!isOpfElement(e, 'item')) continue;
    final id = e.getAttribute('id')?.trim();
    final href = e.getAttribute('href');
    final mediaType = e.getAttribute('media-type')?.trim();
    if (id == null ||
        id.isEmpty ||
        href == null ||
        href.trim().isEmpty ||
        mediaType == null ||
        mediaType.isEmpty) {
      warn(
        DiagnosticCodes.opfManifestItemInvalid,
        'Item do manifest sem id, href ou media-type; ignorado.',
      );
      continue;
    }
    final resolved = resolveHref(opfPath, href.trim());
    if (resolved == null) {
      warn(
        DiagnosticCodes.opfManifestItemInvalid,
        'href "$href" do item "$id" não pode ser resolvido; ignorado.',
      );
      continue;
    }
    if (manifest.containsKey(id)) {
      warn(
        DiagnosticCodes.opfDuplicateId,
        'Id "$id" duplicado no manifest; vale o primeiro.',
      );
      continue;
    }
    manifest[id] = ManifestItem(
      id: id,
      path: resolved.path,
      mediaType: mediaType,
      properties: splitProperties(e.getAttribute('properties')),
      fallbackId: e.getAttribute('fallback')?.trim(),
    );
  }

  // Spine.
  final spineElement = package.childElements
      .where((e) => isOpfElement(e, 'spine'))
      .firstOrNull;
  final spineItems = <SpineItem>[];
  for (final e in spineElement?.childElements ?? const <XmlElement>[]) {
    if (!isOpfElement(e, 'itemref')) continue;
    final idref = e.getAttribute('idref')?.trim();
    final item = idref == null ? null : manifest[idref];
    if (item == null) {
      warn(
        DiagnosticCodes.opfSpineRefMissing,
        'itemref com idref "$idref" inexistente no manifest; ignorado.',
      );
      continue;
    }
    spineItems.add(
      SpineItem(
        item: item,
        linear: e.getAttribute('linear')?.trim().toLowerCase() != 'no',
        properties: splitProperties(e.getAttribute('properties')),
      ),
    );
  }
  if (spineItems.isEmpty) {
    sink.report(
      Diagnostic(
        severity: DiagnosticSeverity.error,
        code: DiagnosticCodes.opfSpineEmpty,
        message: 'O spine não contém nenhum item legível.',
        location: opfPath,
      ),
    );
  }
  final direction = switch (spineElement
      ?.getAttribute('page-progression-direction')
      ?.trim()) {
    'ltr' => PageProgressionDirection.ltr,
    'rtl' => PageProgressionDirection.rtl,
    _ => PageProgressionDirection.unspecified,
  };

  // Nav e NCX.
  final items = manifest.values;
  final navItem = items.where((i) => i.properties.contains('nav')).firstOrNull;
  final tocId = spineElement?.getAttribute('toc')?.trim();
  final ncxItem =
      (tocId == null ? null : manifest[tocId]) ??
      items.where((i) => i.mediaType == 'application/x-dtbncx+xml').firstOrNull;

  // Capa.
  ManifestItem? cover = items
      .where((i) => i.properties.contains('cover-image'))
      .firstOrNull;
  final metaCover = metadata.otherMeta['cover'];
  if (cover == null && metaCover != null) cover = manifest[metaCover];
  if (cover == null) {
    final guide = package.childElements
        .where((e) => isOpfElement(e, 'guide'))
        .firstOrNull;
    for (final ref in guide?.childElements ?? const <XmlElement>[]) {
      if (!isOpfElement(ref, 'reference') ||
          ref.getAttribute('type')?.trim() != 'cover') {
        continue;
      }
      final href = ref.getAttribute('href');
      final resolved = href == null ? null : resolveHref(opfPath, href.trim());
      if (resolved == null) continue;
      final target = items
          .where(
            (i) => i.path == resolved.path && i.mediaType.startsWith('image/'),
          )
          .firstOrNull;
      if (target != null) {
        cover = target;
        break;
      }
    }
  }

  return OpfDocument(
    version: version,
    metadata: metadata,
    manifest: manifest,
    spine: EpubSpine(items: spineItems, direction: direction),
    rendition: _parseRendition(metadata.otherMeta, warn),
    cover: cover,
    navItem: navItem,
    ncxItem: ncxItem,
  );
}

EpubRendition _parseRendition(
  Map<String, String> meta,
  void Function(String code, String message) warn,
) {
  T pick<T>(String key, T fallback, Map<String, T> values) {
    final raw = meta[key]?.trim();
    if (raw == null) return fallback;
    final v = values[raw];
    if (v == null) {
      warn(
        DiagnosticCodes.opfRenditionValueInvalid,
        'Valor "$raw" inválido para $key; usando o padrão.',
      );
      return fallback;
    }
    return v;
  }

  return EpubRendition(
    layout: pick('rendition:layout', RenditionLayout.reflowable, {
      'reflowable': RenditionLayout.reflowable,
      'pre-paginated': RenditionLayout.prePaginated,
    }),
    orientation: pick('rendition:orientation', RenditionOrientation.auto, {
      'auto': RenditionOrientation.auto,
      'portrait': RenditionOrientation.portrait,
      'landscape': RenditionOrientation.landscape,
    }),
    spread: pick('rendition:spread', RenditionSpread.auto, {
      'auto': RenditionSpread.auto,
      'none': RenditionSpread.none,
      'landscape': RenditionSpread.landscape,
      'both': RenditionSpread.both,
      'portrait': RenditionSpread.both,
    }),
  );
}
