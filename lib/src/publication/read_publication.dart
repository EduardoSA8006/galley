/// Orquestrador da Publicação (spec §9): lê `container.xml`, OPF, NAV e NCX
/// do contêiner, resolve caminhos e chama os parsers puros.
library;

import 'dart:typed_data';

import 'package:xml/xml.dart';

import '../container/container.dart';
import '../diagnostics/diagnostic.dart';
import '../diagnostics/exceptions.dart';
import 'container_xml.dart';
import 'cover.dart';
import 'href.dart';
import 'model.dart';
import 'nav.dart';
import 'ncx.dart';
import 'opf.dart';
import 'reconcile.dart';
import 'xml_text.dart';

/// Teto de `container.xml`, OPF, NAV e NCX: acima dele o recurso não é
/// drenado (OPF → fatal; NAV/NCX → `navIgnored`).
const int maxPackageDocumentSize = 4 * 1024 * 1024;

/// Máximo de passos na cadeia de `fallback` (spec §6.4).
const int maxFallbackSteps = 16;

const String ncxMediaType = 'application/x-dtbncx+xml';

/// Lê a publicação de [container]. Não fecha o contêiner (quem abriu fecha).
///
/// Fatais (spec §9.1): [EpubContainerException] para `container.xml`
/// ausente, ilegível ou sem `rootfile`; [EpubPackageException] para OPF
/// ausente, grande demais, inválido ou com spine vazio;
/// [EpubEncryptedException] para ofuscação declarada sobre conteúdo. A
/// exceção do [sink] em `strict` propaga como está.
Future<EpubPublication> readPublication(
  EpubContainer container, {
  required DiagnosticSink sink,
}) => _Reader(container, sink).read();

final class _Reader {
  _Reader(this.container, this.sink);

  final EpubContainer container;
  final DiagnosticSink sink;

  late final String opfPath;
  late final String opfDir;
  final Map<String, ManifestItem> manifest = {};

  /// `path` → item, exato e em minúsculas (o primeiro vence), para os alvos.
  final Map<String, ManifestItem> _byPath = {};
  final Map<String, ManifestItem> _byLowerPath = {};

  void _emit(
    EpubDiagnosticCode code, {
    required String message,
    String? href,
    Map<String, Object?> details = const {},
  }) => sink.emit(
    code,
    message: message,
    href: href,
    details: details,
    onStrict: (m) => EpubPackageException(m, href: href),
  );

  Future<EpubPublication> read() async {
    final rootfiles = parseContainerXml(await _readContainerXml());
    final (path, text) = await _readOpf(await _findOpf(rootfiles));
    opfPath = path;
    opfDir = dirnameOf(opfPath);
    final opf = parseOpf(text, opfPath: opfPath, sink: sink);

    for (final item in opf.items) {
      manifest[item.id] = await _resolveItem(item);
    }
    for (final item in manifest.values) {
      if (item.remote) continue;
      _byPath.putIfAbsent(item.path, () => item);
      _byLowerPath.putIfAbsent(item.path.toLowerCase(), () => item);
    }
    _checkFontObfuscation();

    final spine = _spine(opf);

    // NAV e NCX (spec §7).
    NavDocument? nav;
    String? navPath;
    final navItem = manifest.values
        .where((i) => i.properties.contains('nav'))
        .firstOrNull;
    if (navItem != null) {
      final text = await _readNavigation(navItem, isNav: true);
      if (text != null) {
        nav = parseNav(text);
        navPath = navItem.path;
        if (nav.toc.isEmpty) _navIgnored(navItem.path, 'no-toc');
        if (nav.truncated) _navIgnored(navItem.path, 'truncated');
      }
    }
    NcxDocument? ncx;
    String? ncxPath;
    if (nav == null || nav.toc.isEmpty || nav.pageList.isEmpty) {
      final ncxItem =
          manifest.values
              .where((i) => i.id == opf.spineToc && i.mediaType == ncxMediaType)
              .firstOrNull ??
          manifest.values.where((i) => i.mediaType == ncxMediaType).firstOrNull;
      if (ncxItem != null) {
        final text = await _readNavigation(ncxItem, isNav: false);
        if (text != null) {
          try {
            ncx = parseNcx(text);
            ncxPath = ncxItem.path;
            if (ncx.truncated) _navIgnored(ncxItem.path, 'truncated');
          } on XmlException catch (e) {
            _navIgnored(ncxItem.path, 'invalid', exception: e);
          }
        }
      }
    }

    // Precedência (spec §7.4) e alvos (§5.4).
    final List<NavPoint> toc;
    if (nav != null && nav.toc.isNotEmpty) {
      toc = _points(nav.toc, navPath!);
    } else if (ncx != null) {
      toc = _points(ncx.toc, ncxPath!);
    } else {
      toc = const [];
    }
    final List<NavPoint> pageList;
    if (nav != null && nav.pageList.isNotEmpty) {
      pageList = _points(nav.pageList, navPath!);
    } else if (ncx != null) {
      pageList = _points(ncx.pageList, ncxPath!);
    } else {
      pageList = const [];
    }
    final List<NavPoint> landmarks;
    if (nav != null && nav.landmarks.isNotEmpty) {
      landmarks = _points(nav.landmarks, navPath!);
    } else {
      landmarks = [
        for (final r in opf.guide)
          _point(
            NavEntry(title: r.title.trim(), href: r.href, type: r.type),
            opfPath,
          ),
      ];
    }

    return EpubPublication(
      opfPath: opfPath,
      version: opf.version,
      metadata: opf.metadata,
      manifest: manifest,
      spine: spine,
      toc: reconcileToc(toc, spine, sink: sink),
      landmarks: landmarks,
      pageList: pageList,
      coverPath: findCover(opf, manifest, sink: sink),
      navPath: navPath,
      ncxPath: ncxPath,
      direction: opf.direction,
      layout: opf.layout,
      uniqueIdentifiers: opf.uniqueIdentifiers,
      identifiers: opf.identifiers,
    );
  }

  // --- container.xml e OPF (spec §9.1) ---

  Future<String> _readContainerXml() async {
    final pending = await container.fetch(containerXmlPath);
    if (pending == null) {
      throw EpubContainerException(
        'container.xml ausente',
        href: containerXmlPath,
      );
    }
    if (pending.size > maxPackageDocumentSize) {
      throw EpubContainerException(
        'container.xml acima do teto de $maxPackageDocumentSize bytes',
        href: containerXmlPath,
      );
    }
    return decodeXml(_drain(pending), path: containerXmlPath, sink: sink);
  }

  /// O primeiro `full-path` que existe, com a tentativa dupla de §5.3.
  Future<String> _findOpf(List<String> rootfiles) async {
    for (final fullPath in rootfiles) {
      final normalized = normalizeHref('', fullPath);
      if (normalized == null) continue;
      for (final candidate in _candidates(normalized)) {
        if (await container.exists(candidate)) return candidate;
      }
    }
    throw EpubPackageException('OPF ausente', href: rootfiles.first);
  }

  /// Caminho real do OPF (o nome da entrada, que pode diferir em caixa do
  /// `full-path`) e o texto.
  Future<(String, String)> _readOpf(String located) async {
    final pending = await container.fetch(located);
    if (pending == null) {
      throw EpubPackageException('OPF ausente', href: located);
    }
    if (pending.size > maxPackageDocumentSize) {
      throw EpubPackageException(
        'OPF acima do teto de $maxPackageDocumentSize bytes',
        href: located,
      );
    }
    final bytes = _drain(pending);
    return (pending.path, decodeXml(bytes, path: pending.path, sink: sink));
  }

  static Uint8List _drain(PendingResource pending) {
    for (final _ in pending.decode()) {}
    return pending.bytes;
  }

  /// Forma decodificada (se houver e diferir) e depois a crua.
  static List<String> _candidates(String normalized) {
    final decoded = decodePath(normalized);
    return [if (decoded != null && decoded != normalized) decoded, normalized];
  }

  // --- Manifest (spec §5.3, §6.3) ---

  Future<ManifestItem> _resolveItem(OpfItem raw) async {
    ManifestItem make(
      String path, {
      bool missing = false,
      bool remote = false,
    }) => ManifestItem(
      id: raw.id,
      path: path,
      mediaType: _mediaType(raw.mediaType),
      properties: raw.properties,
      fallback: raw.fallback,
      missing: missing,
      remote: remote,
    );

    final href = raw.href;
    if (isRemoteHref(href)) return make(href, remote: true);
    final normalized = normalizeHref(opfDir, href);
    if (normalized == null) {
      _emit(
        EpubDiagnosticCode.resourceMissing,
        message: 'href recusado no item "${raw.id}": $href',
        details: {'id': raw.id, 'raw': href},
      );
      return make(href, missing: true);
    }
    final candidates = _candidates(normalized);
    final preferred = candidates.first;
    final isOpf = candidates.contains(opfPath);
    if (isOpf || _pointsToDirectory(href)) {
      _emit(
        EpubDiagnosticCode.resourceMissing,
        href: preferred,
        message: isOpf
            ? 'item "${raw.id}" aponta para o próprio OPF'
            : 'item "${raw.id}" aponta para um diretório',
        details: {'id': raw.id, 'reason': isOpf ? 'opf' : 'directory'},
      );
      return make(preferred, missing: true);
    }
    try {
      for (final candidate in candidates) {
        if (await container.exists(candidate)) return make(candidate);
      }
    } on EpubContainerException catch (e) {
      _emit(
        EpubDiagnosticCode.resourceUnreadable,
        href: preferred,
        message: 'exists falhou para o item "${raw.id}"',
        details: {'reason': 'exists', 'exception': '$e'},
      );
      return make(preferred, missing: true);
    }
    _emit(
      EpubDiagnosticCode.resourceMissing,
      href: preferred,
      message: 'item "${raw.id}" sem arquivo no contêiner',
      details: {'id': raw.id},
    );
    return make(preferred, missing: true);
  }

  /// O caminho do `href` (sem `?query` e `#fragmento`) termina em `/` ou `\`.
  static bool _pointsToDirectory(String href) {
    var path = href.trim();
    final hash = path.indexOf('#');
    if (hash >= 0) path = path.substring(0, hash);
    final query = path.indexOf('?');
    if (query >= 0) path = path.substring(0, query);
    return path.endsWith('/') || path.endsWith(r'\');
  }

  static String _mediaType(String raw) {
    final semicolon = raw.indexOf(';');
    return (semicolon < 0 ? raw : raw.substring(0, semicolon))
        .trim()
        .toLowerCase();
  }

  /// Spec §8.1: ofuscação declarada sobre um item que não é fonte é DRM
  /// disfarçado pela extensão.
  void _checkFontObfuscation() {
    for (final item in manifest.values) {
      if (item.missing || item.remote) continue;
      if (container.obfuscationOf(item.path) == null) continue;
      if (isFontMediaType(item.mediaType)) continue;
      throw EpubEncryptedException(
        'ofuscação de fonte declarada sobre ${item.path} '
        '(${item.mediaType}), que não é fonte',
        scheme: 'unknown:obfuscation-on-content',
        href: item.path,
      );
    }
  }

  // --- Spine (spec §6.3, §6.4) ---

  List<SpineItem> _spine(OpfDocument opf) {
    final spine = <SpineItem>[];
    final paths = <String>{};
    for (final ref in opf.itemrefs) {
      final item = manifest[ref.idref]!;
      if (!paths.add(item.path)) {
        _emit(
          EpubDiagnosticCode.spineItemDuplicate,
          href: opfPath,
          message: 'itemref "${ref.idref}" repete o caminho ${item.path}',
          details: {'idref': ref.idref},
        );
        continue;
      }
      spine.add(
        SpineItem(
          idref: ref.idref,
          item: item,
          content: _content(item),
          linear: ref.linear,
        ),
      );
    }
    if (spine.isEmpty) {
      throw EpubPackageException('spine vazio', href: opfPath);
    }
    return spine;
  }

  static bool _renderable(ManifestItem item) =>
      !item.missing && item.kind != SectionKind.unsupported;

  ManifestItem _content(ManifestItem item) {
    if (_renderable(item)) return item;
    final visited = <String>{item.id};
    var current = item;
    for (var step = 0; step < maxFallbackSteps; step++) {
      final next = current.fallback == null ? null : manifest[current.fallback];
      if (next == null || !visited.add(next.id)) break;
      if (_renderable(next)) return next;
      current = next;
    }
    if (item.kind == SectionKind.unsupported) {
      _emit(
        EpubDiagnosticCode.unsupportedMediaType,
        href: item.path,
        message: 'item do spine "${item.id}" com media-type ${item.mediaType}',
        details: {'mediaType': item.mediaType},
      );
    }
    return item;
  }

  // --- NAV e NCX (spec §7.5) ---

  void _navIgnored(String path, String reason, {Object? exception}) => _emit(
    EpubDiagnosticCode.navIgnored,
    href: path,
    message: 'navegação ignorada ($reason)',
    details: {'reason': reason, 'exception': ?exception?.toString()},
  );

  /// Texto do NAV ou do NCX, ou `null` com `navIgnored`. Só falha do próprio
  /// `fetch`/`decode()` vira `unreadable`; a exceção do [sink] em `strict`
  /// propaga.
  Future<String?> _readNavigation(
    ManifestItem item, {
    required bool isNav,
  }) async {
    if (item.missing || item.remote) {
      _navIgnored(item.path, 'missing');
      return null;
    }
    final Uint8List bytes;
    try {
      final pending = await container.fetch(item.path);
      if (pending == null) {
        _navIgnored(item.path, 'missing');
        return null;
      }
      if (pending.size > maxPackageDocumentSize) {
        _navIgnored(item.path, 'too-large');
        return null;
      }
      bytes = _drain(pending);
    } on EpubException catch (e) {
      if (_raisedBySink(e)) rethrow;
      _emit(
        EpubDiagnosticCode.resourceUnreadable,
        href: item.path,
        message: '${isNav ? 'NAV' : 'NCX'} ilegível',
        details: {'reason': 'unreadable', 'exception': '$e'},
      );
      _navIgnored(item.path, 'unreadable', exception: e);
      return null;
    }
    return decodeXml(bytes, path: item.path, sink: sink, htmlMeta: isNav);
  }

  /// A exceção veio do [sink] em `strict` (a mensagem é a de um warning
  /// registrado), e não do `fetch`/`decode()`.
  bool _raisedBySink(EpubException e) =>
      sink.strict &&
      sink.diagnostics.any(
        (d) =>
            d.severity == EpubSeverity.warning &&
            e.message == '${d.code.name}: ${d.message}',
      );

  // --- Alvos (spec §5.4) ---

  List<NavPoint> _points(List<NavEntry> entries, String documentPath) => [
    for (final e in entries) _point(e, documentPath),
  ];

  NavPoint _point(NavEntry entry, String documentPath) {
    final target = _target(entry.href, documentPath);
    return NavPoint(
      title: entry.title.isNotEmpty || target == null
          ? entry.title
          : basenameWithoutExtension(target.path),
      target: target,
      type: entry.type,
      children: _points(entry.children, documentPath),
    );
  }

  NavTarget? _target(String? href, String documentPath) {
    if (href == null) return null;
    final raw = href.trim();
    if (hasScheme(raw)) return null;
    final (_, fragment) = splitFragment(raw);
    if (raw.startsWith('#')) return NavTarget(documentPath, fragment);
    final normalized = normalizeHref(dirnameOf(documentPath), raw);
    if (normalized == null) return null;
    final decoded = decodePath(normalized);
    final item =
        (decoded == null ? null : _byPath[decoded]) ??
        _byPath[normalized] ??
        (decoded == null ? null : _byLowerPath[decoded.toLowerCase()]) ??
        _byLowerPath[normalized.toLowerCase()];
    return NavTarget(item?.path ?? decoded ?? normalized, fragment);
  }
}

/// `font/*`, `application/font-*`, `application/x-font-*`,
/// `application/vnd.ms-opentype` e `application/octet-stream` (genérico:
/// não declara conteúdo, e produtores antigos o usam para fontes).
bool isFontMediaType(String mediaType) =>
    mediaType.startsWith('font/') ||
    mediaType.startsWith('application/font-') ||
    mediaType.startsWith('application/x-font-') ||
    mediaType == 'application/vnd.ms-opentype' ||
    mediaType == 'application/octet-stream';
