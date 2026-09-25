import 'dart:convert';
import 'dart:typed_data';

import 'hashes.dart';
import 'zip_writer.dart';

/// Um arquivo dentro do container.
class EpubResource {
  EpubResource({
    required this.path,
    required this.bytes,
    required this.mediaType,
    String? id,
    this.properties = const [],
    this.manifestHrefOverride,
    this.inManifest = true,
    this.inZip = true,
    this.compress = true,
    this.crcOverride,
  }) : id = id ?? _idFromPath(path);

  /// Caminho completo no ZIP (`OEBPS/Text/cap01.xhtml`).
  final String path;
  final List<int> bytes;
  final String mediaType;
  final String id;
  final List<String> properties;

  /// Substitui o href calculado no manifest (para hrefs errados de propósito).
  final String? manifestHrefOverride;
  final bool inManifest;
  final bool inZip;
  final bool compress;
  final int? crcOverride;

  static String _idFromPath(String path) =>
      path.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');

  EpubResource copyWithProperties(List<String> properties) => EpubResource(
    path: path,
    bytes: bytes,
    mediaType: mediaType,
    id: id,
    properties: properties,
    manifestHrefOverride: manifestHrefOverride,
    inManifest: inManifest,
    inZip: inZip,
    compress: compress,
    crcOverride: crcOverride,
  );
}

class SpineRef {
  const SpineRef(this.idref, {this.linear = true});
  final String idref;
  final bool linear;
}

class TocEntry {
  const TocEntry(this.title, this.href, {this.children = const []});
  final String title;

  /// Relativo ao diretório do OPF; `null` para agrupamento sem destino.
  final String? href;
  final List<TocEntry> children;
}

class PageMark {
  const PageMark(this.label, this.href);
  final String label;
  final String href;
}

/// Monta um EPUB 3 com os desvios que cada caso do corpus pede.
class EpubBuilder {
  EpubBuilder({
    required this.slug,
    this.title = 'Livro de teste',
    this.language = 'pt-BR',
    this.author = 'Corpus galley',
    this.opfDir = 'OEBPS',
  }) : identifier = 'urn:uuid:${_uuidFromSlug(slug)}';

  final String slug;
  final String title;
  final String language;
  final String author;
  final String opfDir;
  final String identifier;

  final List<EpubResource> resources = [];
  final List<SpineRef> spine = [];
  List<TocEntry> toc = [];

  /// Quando não nulo, o NCX usa esta lista em vez de [toc].
  List<TocEntry>? ncxToc;
  List<PageMark> navPageList = [];
  List<PageMark> ncxPageList = [];

  String? direction; // page-progression-direction
  String? coverId;
  bool epub2CoverMeta = false;
  bool includeNav = true;
  bool includeNcx = true;
  final Map<String, String> extraMeta = {};

  /// Substitui o OPF gerado por completo.
  String? opfOverride;

  /// Arquivos fora do manifest (META-INF/encryption.xml etc.).
  final Map<String, List<int>> extraFiles = {};

  bool mimetypeFirst = true;
  bool mimetypeCompressed = false;
  bool forceZip64 = false;

  String get opfPath => '$opfDir/content.opf';
  String get navPath => '$opfDir/nav.xhtml';
  String get ncxPath => '$opfDir/toc.ncx';

  /// Bytes da chave de ofuscação IDPF: SHA-1 do identificador sem whitespace.
  Uint8List get idpfKey =>
      sha1(utf8.encode(identifier.replaceAll(RegExp(r'\s'), '')));

  /// Bytes da chave Adobe: os 16 bytes do UUID.
  Uint8List get adobeKey {
    final h = identifier.substring('urn:uuid:'.length).replaceAll('-', '');
    return Uint8List.fromList(
      List.generate(
        16,
        (i) => int.parse(h.substring(i * 2, i * 2 + 2), radix: 16),
      ),
    );
  }

  /// Adiciona um XHTML (por padrão em `opfDir/Text/`) e devolve o recurso.
  EpubResource addChapter(
    String name,
    String xhtmlSource, {
    String? id,
    String? path,
    List<String> properties = const [],
    List<int>? bytes,
  }) {
    final r = EpubResource(
      path: path ?? '$opfDir/Text/$name',
      bytes: bytes ?? utf8.encode(xhtmlSource),
      mediaType: 'application/xhtml+xml',
      id: id,
      properties: properties,
    );
    resources.add(r);
    return r;
  }

  EpubResource addImage(
    String name,
    List<int> bytes, {
    String? id,
    String mediaType = 'image/png',
  }) {
    final r = EpubResource(
      path: '$opfDir/Images/$name',
      bytes: bytes,
      mediaType: mediaType,
      id: id,
    );
    resources.add(r);
    return r;
  }

  EpubResource addCss(String name, String css) {
    final r = EpubResource(
      path: '$opfDir/Styles/$name',
      bytes: utf8.encode(css),
      mediaType: 'text/css',
    );
    resources.add(r);
    return r;
  }

  /// href de um recurso relativo ao OPF, como aparece no manifest e no NAV.
  String hrefOf(EpubResource r) =>
      r.manifestHrefOverride ?? relativeHref(opfDir, r.path);

  /// Acrescenta ao spine e ao TOC de uma vez.
  void chapterInSpineAndToc(
    EpubResource r,
    String title, {
    bool linear = true,
  }) {
    spine.add(SpineRef(r.id, linear: linear));
    toc.add(TocEntry(title, hrefOf(r)));
  }

  Uint8List build() {
    final zip = ZipWriter(forceZip64: forceZip64);
    void mimetype() => zip.add(
      'mimetype',
      ascii.encode('application/epub+zip'),
      compress: mimetypeCompressed,
    );

    if (mimetypeFirst) mimetype();
    zip.add('META-INF/container.xml', utf8.encode(_containerXml()));
    for (final e in extraFiles.entries) {
      zip.add(e.key, e.value);
    }
    zip.add(opfPath, utf8.encode(opfOverride ?? _opf()));
    if (includeNav) zip.add(navPath, utf8.encode(_nav()));
    if (includeNcx) zip.add(ncxPath, utf8.encode(_ncx()));
    for (final r in resources) {
      if (r.inZip) {
        zip.add(
          r.path,
          r.bytes,
          compress: r.compress,
          crcOverride: r.crcOverride,
        );
      }
    }
    if (!mimetypeFirst) mimetype();
    return zip.build();
  }

  String _containerXml() =>
      '''
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="$opfPath" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
''';

  String _opf() {
    final items = StringBuffer();
    if (includeNav) {
      items.writeln(
        '    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>',
      );
    }
    if (includeNcx) {
      items.writeln(
        '    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>',
      );
    }
    for (final r in resources.where((r) => r.inManifest)) {
      final href = r.manifestHrefOverride ?? relativeHref(opfDir, r.path);
      final props = <String>[...r.properties];
      if (r.id == coverId && !props.contains('cover-image')) {
        props.add('cover-image');
      }
      final propAttr = props.isEmpty ? '' : ' properties="${props.join(' ')}"';
      items.writeln(
        '    <item id="${r.id}" href="${escapeAttr(href)}" media-type="${r.mediaType}"$propAttr/>',
      );
    }
    final refs = StringBuffer();
    for (final s in spine) {
      final linear = s.linear ? '' : ' linear="no"';
      refs.writeln('    <itemref idref="${s.idref}"$linear/>');
    }
    final meta = StringBuffer();
    if (epub2CoverMeta && coverId != null) {
      meta.writeln('    <meta name="cover" content="$coverId"/>');
    }
    for (final e in extraMeta.entries) {
      meta.writeln(
        '    <meta property="${e.key}">${escapeText(e.value)}</meta>',
      );
    }
    final dir = direction == null
        ? ''
        : ' page-progression-direction="$direction"';
    final ncxAttr = includeNcx ? ' toc="ncx"' : '';
    return '''
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id" xml:lang="$language">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="pub-id">$identifier</dc:identifier>
    <dc:title>${escapeText(title)}</dc:title>
    <dc:language>$language</dc:language>
    <dc:creator>${escapeText(author)}</dc:creator>
    <meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>
$meta  </metadata>
  <manifest>
$items  </manifest>
  <spine$ncxAttr$dir>
$refs  </spine>
</package>
''';
  }

  String _nav() {
    String ol(List<TocEntry> entries) {
      if (entries.isEmpty) return '';
      final b = StringBuffer('<ol>');
      for (final e in entries) {
        b.write('<li>');
        b.write(
          e.href == null
              ? '<span>${escapeText(e.title)}</span>'
              : '<a href="${escapeAttr(e.href!)}">${escapeText(e.title)}</a>',
        );
        b.write(ol(e.children));
        b.write('</li>');
      }
      b.write('</ol>');
      return b.toString();
    }

    final pageList = navPageList.isEmpty
        ? ''
        : '<nav epub:type="page-list" hidden=""><h2>Páginas</h2><ol>${navPageList.map((p) => '<li><a href="${escapeAttr(p.href)}">${escapeText(p.label)}</a></li>').join()}</ol></nav>';
    final first = spine.isEmpty ? null : _hrefOfId(spine.first.idref);
    final landmarks = first == null
        ? ''
        : '<nav epub:type="landmarks" hidden=""><h2>Marcos</h2><ol><li><a epub:type="bodymatter" href="${escapeAttr(first)}">Início</a></li></ol></nav>';
    return '''
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="$language" xml:lang="$language">
<head><title>Sumário</title></head>
<body>
<nav epub:type="toc" id="toc"><h1>Sumário</h1>${ol(toc)}</nav>
$pageList
$landmarks
</body>
</html>
''';
  }

  String _ncx() {
    var play = 0;
    String navPoints(List<TocEntry> entries) {
      final b = StringBuffer();
      for (final e in entries) {
        play++;
        b.write(
          '<navPoint id="np$play" playOrder="$play"><navLabel><text>${escapeText(e.title)}</text></navLabel>',
        );
        b.write(
          '<content src="${escapeAttr(e.href ?? _hrefOfId(spine.first.idref)!)}"/>',
        );
        b.write(navPoints(e.children));
        b.write('</navPoint>');
      }
      return b.toString();
    }

    final map = navPoints(ncxToc ?? toc);
    final pages = ncxPageList.isEmpty
        ? ''
        : '<pageList>${ncxPageList.indexed.map((e) => '<pageTarget id="pt${e.$1}" type="normal" value="${e.$1 + 1}" playOrder="${++play}"><navLabel><text>${escapeText(e.$2.label)}</text></navLabel><content src="${escapeAttr(e.$2.href)}"/></pageTarget>').join()}</pageList>';
    return '''
<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head>
    <meta name="dtb:uid" content="$identifier"/>
    <meta name="dtb:depth" content="1"/>
    <meta name="dtb:totalPageCount" content="0"/>
    <meta name="dtb:maxPageNumber" content="0"/>
  </head>
  <docTitle><text>${escapeText(title)}</text></docTitle>
  <navMap>$map</navMap>
  $pages
</ncx>
''';
  }

  String? _hrefOfId(String id) {
    for (final r in resources) {
      if (r.id == id) {
        return r.manifestHrefOverride ?? relativeHref(opfDir, r.path);
      }
    }
    return null;
  }

  static String _uuidFromSlug(String slug) {
    final h = hex(sha1(utf8.encode('galley-corpus:$slug')));
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-4${h.substring(13, 16)}-a${h.substring(17, 20)}-${h.substring(20, 32)}';
  }
}

/// Caminho de [toPath] relativo ao diretório [fromDir], com `..` quando preciso.
String relativeHref(String fromDir, String toPath) {
  final from = fromDir.split('/').where((s) => s.isNotEmpty).toList();
  final to = toPath.split('/');
  var common = 0;
  while (common < from.length &&
      common < to.length - 1 &&
      from[common] == to[common]) {
    common++;
  }
  final ups = List.filled(from.length - common, '..');
  return [...ups, ...to.sublist(common)].join('/');
}

String escapeText(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

String escapeAttr(String s) => escapeText(s).replaceAll('"', '&quot;');

/// Documento XHTML completo. [body] é o conteúdo interno de `<body>`.
String xhtml({
  required String title,
  required String body,
  String lang = 'pt-BR',
  String? dir,
  String? css,
  List<String> cssHrefs = const [],
  String? head,
  String? xmlEncoding = 'UTF-8',
  bool xmlDeclaration = true,
  String? bodyAttrs,
}) {
  final decl = xmlDeclaration
      ? '<?xml version="1.0" encoding="$xmlEncoding"?>\n'
      : '';
  final links = cssHrefs
      .map(
        (h) =>
            '<link rel="stylesheet" type="text/css" href="${escapeAttr(h)}"/>',
      )
      .join('\n');
  final style = css == null ? '' : '<style type="text/css">\n$css\n</style>';
  final dirAttr = dir == null ? '' : ' dir="$dir"';
  return '''
$decl<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="$lang" xml:lang="$lang"$dirAttr>
<head>
<title>${escapeText(title)}</title>
$links
$style
${head ?? ''}
</head>
<body${bodyAttrs == null ? '' : ' $bodyAttrs'}>
$body
</body>
</html>
''';
}
