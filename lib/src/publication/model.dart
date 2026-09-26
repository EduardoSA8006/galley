/// Modelo da publicação (spec da Publicação §3). Interno nesta etapa, exceto
/// [EpubReadingDirection] e [EpubLayoutMode] (públicos, doc/11 §3.3).
library;

import 'metadata.dart';

/// `page-progression-direction` do spine.
enum EpubReadingDirection { ltr, rtl, auto }

/// `rendition:layout` global do OPF.
enum EpubLayoutMode { reflowable, prePaginated }

/// Como a IR trata um item do spine (spec §6.4).
enum SectionKind { xhtml, image, unsupported }

/// Um item do manifest, com o caminho já resolvido contra o contêiner.
final class ManifestItem {
  ManifestItem({
    required this.id,
    required this.path,
    required this.mediaType,
    Set<String> properties = const {},
    this.fallback,
    this.missing = false,
    this.remote = false,
  }) : properties = Set.unmodifiable(properties);

  final String id;

  /// Normalizado e resolvido; para `href` recusado ou remoto, o `href` cru.
  final String path;

  /// Em minúsculas, sem parâmetros (antes de `;`), sem espaços nas pontas.
  final String mediaType;
  final Set<String> properties;

  /// `id` de outro item.
  final String? fallback;

  /// Não existe no contêiner (ou `href` recusado).
  final bool missing;

  /// `href` `http:`/`https:` (recurso remoto do EPUB3).
  final bool remote;

  /// Tipo de seção pelo `media-type` (spec §6.4).
  SectionKind get kind => sectionKindOf(mediaType);

  @override
  String toString() =>
      'ManifestItem($id, $path, $mediaType'
      '${missing ? ', missing' : ''}${remote ? ', remote' : ''})';
}

/// `application/xhtml+xml`, `text/html` e `text/x-oeb1-document` (o XHTML
/// do OEB 1.x, cujo OPF a Publicação já lê) → [SectionKind.xhtml];
/// `image/*` → [SectionKind.image]; o resto → [SectionKind.unsupported].
SectionKind sectionKindOf(String mediaType) {
  if (mediaType == 'application/xhtml+xml' ||
      mediaType == 'text/html' ||
      mediaType == 'text/x-oeb1-document') {
    return SectionKind.xhtml;
  }
  if (mediaType.startsWith('image/')) return SectionKind.image;
  return SectionKind.unsupported;
}

/// Um item da ordem de leitura.
final class SpineItem {
  SpineItem({
    required this.idref,
    required this.item,
    required this.content,
    required this.linear,
  }) : kind = content.kind;

  final String idref;

  /// O item referenciado pelo `itemref`.
  final ManifestItem item;

  /// O item a renderizar: [item], ou o fim da cadeia de `fallback`.
  final ManifestItem content;

  /// `false` só com `linear="no"`.
  final bool linear;

  /// Tipo de [content].
  final SectionKind kind;
}

/// Alvo de uma entrada de navegação.
final class NavTarget {
  const NavTarget(this.path, [this.fragment]);

  /// Caminho de item do manifest (ou o resolvido, spec §5.4).
  final String path;

  /// Sem `#`, decodificado de `%xx`; `null` se ausente ou vazio.
  final String? fragment;

  @override
  bool operator ==(Object other) =>
      other is NavTarget && other.path == path && other.fragment == fragment;

  @override
  int get hashCode => Object.hash(path, fragment);

  @override
  String toString() => fragment == null ? path : '$path#$fragment';
}

/// Entrada de TOC, landmark ou `page-list`.
final class NavPoint {
  NavPoint({
    required this.title,
    this.target,
    List<NavPoint> children = const [],
    this.type,
    this.synthesized = false,
  }) : children = List.unmodifiable(children);

  final String title;

  /// `null` em entrada só de agrupamento ou com alvo externo.
  final NavTarget? target;
  final List<NavPoint> children;

  /// Landmark: `epub:type` (NAV) ou `reference@type` (guide).
  final String? type;

  /// Órfão inserido pela reconciliação (a UI pode escondê-lo).
  final bool synthesized;

  @override
  String toString() =>
      'NavPoint($title${target == null ? '' : ' → $target'}'
      '${synthesized ? ', synthesized' : ''})';
}

/// A publicação lida do pacote (spec §3). Não abre nenhuma seção.
final class EpubPublication {
  EpubPublication({
    required this.opfPath,
    required this.version,
    required this.metadata,
    required Map<String, ManifestItem> manifest,
    required List<SpineItem> spine,
    required List<NavPoint> toc,
    required List<NavPoint> landmarks,
    required List<NavPoint> pageList,
    required this.coverPath,
    required this.navPath,
    required this.ncxPath,
    required this.direction,
    required this.layout,
    required List<String> uniqueIdentifiers,
    required List<String> identifiers,
  }) : manifest = Map.unmodifiable(manifest),
       spine = List.unmodifiable(spine),
       toc = List.unmodifiable(toc),
       landmarks = List.unmodifiable(landmarks),
       pageList = List.unmodifiable(pageList),
       uniqueIdentifiers = List.unmodifiable(uniqueIdentifiers),
       identifiers = List.unmodifiable(identifiers);

  /// Caminho do OPF no contêiner.
  final String opfPath;

  /// Atributo `version` do `<package>`, cru (`''` se ausente).
  final String version;
  final EpubMetadata metadata;

  /// Por `id`, na ordem do OPF.
  final Map<String, ManifestItem> manifest;

  /// Ordem de leitura; nunca vazio; sem repetição de caminho.
  final List<SpineItem> spine;

  /// Reconciliado com o spine.
  final List<NavPoint> toc;
  final List<NavPoint> landmarks;
  final List<NavPoint> pageList;

  /// Caminho no contêiner, ou `null`.
  final String? coverPath;

  /// NAV efetivamente lido (entra na chave do livro, doc/08 §4.1).
  final String? navPath;

  /// NCX efetivamente lido.
  final String? ncxPath;
  final EpubReadingDirection direction;
  final EpubLayoutMode layout;

  /// Chave IDPF (doc/09 §4).
  final List<String> uniqueIdentifiers;

  /// Todos os `dc:identifier`, em ordem (chave Adobe).
  final List<String> identifiers;
}
