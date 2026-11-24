import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../../../core/diagnostics/diagnostic.dart';
import '../../../core/diagnostics/diagnostic_codes.dart';
import '../../../core/diagnostics/diagnostic_sink.dart';
import '../../../core/errors/galley_exception.dart';
import '../data/fonts/font_deobfuscator.dart';
import '../data/parsers/container_xml_parser.dart';
import '../data/parsers/encryption_parser.dart';
import '../data/parsers/nav_parser.dart';
import '../data/parsers/ncx_parser.dart';
import '../data/parsers/opf_parser.dart';
import '../data/text/decode_text.dart';
import '../data/zip/byte_source.dart';
import '../data/zip/zip_archive.dart';
import '../data/zip/zip_entry.dart';
import '../data/zip/zip_limits.dart';
import 'models/epub_metadata.dart';
import 'models/manifest.dart';
import 'models/navigation.dart';
import 'models/opf_document.dart';
import 'models/rendition.dart';
import 'models/spine.dart';

const String _mimetype = 'application/epub+zip';
const String _containerPath = 'META-INF/container.xml';
const String _encryptionPath = 'META-INF/encryption.xml';

/// Arquivos cuja presença indica DRM (Adobe ADEPT e Readium LCP).
const List<String> _drmMarkers = [
  'META-INF/rights.xml',
  'META-INF/license.lcpl',
];

/// Livro EPUB aberto: metadados, manifest, spine, navegação e acesso aos
/// recursos.
///
/// Os recursos são lidos sob demanda do zip e não ficam em cache (memória
/// mínima). Feche com [close] ao terminar. Só [GalleyException] escapa desta
/// API; problemas recuperáveis viram [Diagnostic] em [diagnostics].
final class EpubBook {
  EpubBook._(
    this._archive,
    this._opf,
    this.packagePath,
    this.navigation,
    this._obfuscated,
    this._sink,
  );

  /// Abre o EPUB do arquivo em [path], lendo-o sob demanda.
  ///
  /// Arquivo inexistente ou ilegível lança [NotAnEpubException]. Os demais
  /// erros são os de [fromBytes]. Se a abertura falhar, o arquivo é fechado.
  static Future<EpubBook> open(
    String path, {
    DiagnosticSink? diagnostics,
    ZipLimits limits = const ZipLimits(),
  }) async {
    final ByteSource source;
    try {
      source = await FileByteSource.open(path);
    } on GalleyException {
      rethrow;
    } catch (e) {
      throw NotAnEpubException('Não foi possível abrir o arquivo "$path": $e');
    }
    return _openSource(source, diagnostics, limits);
  }

  /// Abre o EPUB contido em [bytes] (sem copiá-los: não os altere enquanto o
  /// livro estiver aberto).
  ///
  /// Lança [NotAnEpubException] se não for um zip,
  /// [DrmProtectedException] se houver DRM,
  /// [MissingPackageDocumentException] se não houver OPF legível,
  /// [ArchiveLimitExceededException] se um limite de [limits] for excedido e
  /// [CorruptArchiveException] para qualquer outra falha.
  static Future<EpubBook> fromBytes(
    Uint8List bytes, {
    DiagnosticSink? diagnostics,
    ZipLimits limits = const ZipLimits(),
  }) => _openSource(MemoryByteSource(bytes), diagnostics, limits);

  /// Abre o EPUB sobre uma [ByteSource] arbitrária (injeção em testes).
  @visibleForTesting
  static Future<EpubBook> fromSource(
    ByteSource source, {
    DiagnosticSink? diagnostics,
    ZipLimits limits = const ZipLimits(),
  }) => _openSource(source, diagnostics, limits);

  static Future<EpubBook> _openSource(
    ByteSource source,
    DiagnosticSink? diagnostics,
    ZipLimits limits,
  ) async {
    final sink = _BookSink(diagnostics);
    ZipArchive? archive;
    try {
      archive = await ZipArchive.open(source, limits: limits, sink: sink);
      return await _load(archive, sink);
    } catch (e) {
      try {
        await (archive?.close() ?? source.close());
      } catch (_) {
        // A falha original é a que interessa.
      }
      if (e is GalleyException) rethrow;
      throw CorruptArchiveException('Falha ao interpretar o EPUB: $e');
    }
  }

  static Future<EpubBook> _load(ZipArchive archive, _BookSink sink) async {
    await _checkMimetype(archive, sink);
    final obfuscated = await _checkEncryption(archive, sink);
    final opfEntry = await _locatePackage(archive, sink);
    final opf = parseOpf(
      decodeText(await archive.read(opfEntry)),
      opfPath: opfEntry.name,
      sink: sink,
    );
    final navigation = await _loadNavigation(archive, opf, sink);
    return EpubBook._(
      archive,
      opf,
      opfEntry.name,
      navigation,
      obfuscated,
      sink,
    );
  }

  final ZipArchive _archive;
  final OpfDocument _opf;
  final _BookSink _sink;

  /// Algoritmo de ofuscação por caminho do recurso (normalizado como os
  /// caminhos do manifest).
  final Map<String, String> _obfuscated;
  Map<String, ManifestItem>? _byPath;
  bool _closed = false;

  /// Caminho do documento de pacote (OPF) no zip.
  final String packagePath;

  /// Navegação (sumário, lista de páginas e marcos).
  final EpubNavigation navigation;

  /// Versão do EPUB.
  EpubVersion get version => _opf.version;

  /// Metadados da publicação.
  EpubMetadata get metadata => _opf.metadata;

  /// Itens do manifest por id.
  Map<String, ManifestItem> get manifest => _opf.manifest;

  /// Ordem de leitura. Itens cujo arquivo falta no zip continuam aqui; o
  /// erro só aparece ao acessar o recurso.
  EpubSpine get spine => _opf.spine;

  /// Propriedades de rendition.
  EpubRendition get rendition => _opf.rendition;

  /// Imagem de capa, se houver.
  ManifestItem? get cover => _opf.cover;

  /// Todos os diagnósticos da abertura e dos acessos a recursos posteriores
  /// (visão viva e não modificável).
  List<Diagnostic> get diagnostics => _sink.collector.diagnostics;

  /// Item do manifest cujo caminho é exatamente [path], ou `null`.
  ManifestItem? manifestItemByPath(String path) {
    final index = _byPath ??= () {
      final map = <String, ManifestItem>{};
      for (final item in manifest.values) {
        map.putIfAbsent(item.path, () => item);
      }
      return map;
    }();
    return index[path];
  }

  /// Bytes do recurso em [path] (caminho na raiz do zip, já decodificado).
  ///
  /// Se só existir com outra caixa, devolve-o e reporta
  /// `resource.caseMismatch`. Fontes ofuscadas (IDPF/Adobe) listadas em
  /// `encryption.xml` são devolvidas desofuscadas. Lança
  /// [ResourceNotFoundException] se não existir e [BookClosedException] após
  /// [close].
  Future<Uint8List> resource(String path) async {
    if (_closed) throw const BookClosedException();
    try {
      final entry =
          _findEntry(_archive, path, _sink) ??
          (throw ResourceNotFoundException(path));
      final bytes = await _archive.read(entry);
      final algorithm = _obfuscated[entry.name] ?? _obfuscated[path];
      return algorithm == null ? bytes : _deobfuscate(bytes, algorithm, path);
    } on GalleyException {
      // Fechado durante a leitura: não é corrupção.
      if (_closed) throw const BookClosedException();
      rethrow;
    } catch (e) {
      if (_closed) throw const BookClosedException();
      throw CorruptArchiveException('Falha ao ler "$path": $e');
    }
  }

  /// Texto do recurso em [path], decodificado (BOM/UTF-16/latin1/UTF-8).
  Future<String> resourceText(String path) async =>
      decodeText(await resource(path));

  /// Fecha o livro e o arquivo subjacente. Chamadas repetidas são
  /// inofensivas.
  ///
  /// O livro fica fechado mesmo se a liberação do arquivo falhar; nesse caso
  /// lança [CorruptArchiveException].
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _archive.close();
    } on GalleyException {
      rethrow;
    } catch (e) {
      throw CorruptArchiveException('Falha ao fechar o arquivo: $e');
    }
  }

  Uint8List _deobfuscate(Uint8List bytes, String algorithm, String path) {
    final ids = <String>[
      ?metadata.uniqueIdentifier,
      if (algorithm == adobeObfuscation)
        for (final id in metadata.identifiers)
          if (id.value != metadata.uniqueIdentifier) id.value,
    ];
    if (algorithm == idpfObfuscation && ids.isNotEmpty) {
      return deobfuscateIdpf(bytes, ids.first);
    }
    for (final id in ids) {
      try {
        return deobfuscateAdobe(bytes, id);
      } on FormatException {
        // Tenta o próximo identificador.
      }
    }
    _sink.report(
      Diagnostic(
        severity: DiagnosticSeverity.error,
        code: DiagnosticCodes.fontDeobfuscationFailed,
        message: ids.isEmpty
            ? 'Fonte ofuscada, mas o livro não tem identificador único.'
            : 'Nenhum identificador é um UUID válido para a ofuscação '
                  'Adobe.',
        location: path,
      ),
    );
    return bytes;
  }
}

/// Repassa ao coletor interno e ao sink do chamador, se houver.
final class _BookSink implements DiagnosticSink {
  _BookSink(this._external);

  final DiagnosticSink? _external;
  final CollectingDiagnosticSink collector = CollectingDiagnosticSink();

  @override
  void report(Diagnostic diagnostic) {
    collector.report(diagnostic);
    _external?.report(diagnostic);
  }
}

/// Entrada com nome [path]; se só existir com outra caixa, reporta
/// `resource.caseMismatch` e a devolve.
ZipEntry? _findEntry(ZipArchive archive, String path, DiagnosticSink sink) {
  final exact = archive.entry(path);
  if (exact != null) return exact;
  final loose = archive.entryIgnoringCase(path);
  if (loose != null) {
    sink.report(
      Diagnostic(
        severity: DiagnosticSeverity.warning,
        code: DiagnosticCodes.resourceCaseMismatch,
        message: 'Recurso encontrado com caixa diferente: "${loose.name}".',
        location: path,
      ),
    );
  }
  return loose;
}

Future<void> _checkMimetype(ZipArchive archive, DiagnosticSink sink) async {
  final entry = archive.entry('mimetype');
  if (entry == null) {
    sink.report(
      const Diagnostic(
        severity: DiagnosticSeverity.warning,
        code: DiagnosticCodes.mimetypeMissing,
        message: 'Arquivo mimetype ausente.',
        location: 'mimetype',
      ),
    );
    return;
  }
  if (!identical(archive.entries.first, entry)) {
    sink.report(
      const Diagnostic(
        severity: DiagnosticSeverity.info,
        code: DiagnosticCodes.mimetypeNotFirst,
        message: 'mimetype não é a primeira entrada do zip.',
        location: 'mimetype',
      ),
    );
  }
  final String content;
  try {
    content = latin1.decode(await archive.read(entry)).trim();
  } on DrmProtectedException {
    rethrow;
  } on GalleyException catch (e) {
    sink.report(
      Diagnostic(
        severity: DiagnosticSeverity.warning,
        code: DiagnosticCodes.mimetypeInvalid,
        message: 'Não foi possível ler o mimetype: $e',
        location: 'mimetype',
      ),
    );
    return;
  }
  if (content != _mimetype) {
    sink.report(
      Diagnostic(
        severity: DiagnosticSeverity.warning,
        code: DiagnosticCodes.mimetypeInvalid,
        message: 'mimetype contém "$content", esperado "$_mimetype".',
        location: 'mimetype',
      ),
    );
  }
}

/// Recusa DRM e devolve o algoritmo de ofuscação por caminho das fontes.
///
/// [DrmProtectedException.algorithms] traz os algoritmos não suportados de
/// `encryption.xml` seguidos dos arquivos-marcadores de DRM encontrados
/// (`META-INF/rights.xml`, `META-INF/license.lcpl`).
Future<Map<String, String>> _checkEncryption(
  ZipArchive archive,
  DiagnosticSink sink,
) async {
  final entry = archive.entry(_encryptionPath);
  final resources = entry == null
      ? const <EncryptedResource>[]
      : parseEncryptionXml(decodeText(await archive.read(entry)), sink);
  final unsupported = <String>{
    for (final r in resources)
      if (r.algorithm != idpfObfuscation && r.algorithm != adobeObfuscation)
        r.algorithm,
  };
  final markers = _drmMarkers.where((m) => archive.entry(m) != null);
  if (unsupported.isNotEmpty || markers.isNotEmpty) {
    throw DrmProtectedException([...unsupported, ...markers]);
  }
  return {for (final r in resources) r.path: r.algorithm};
}

/// Entrada do OPF: primeiro rootfile do `container.xml`, ou o primeiro
/// `.opf` do zip (com `container.containerMissing`).
Future<ZipEntry> _locatePackage(ZipArchive archive, DiagnosticSink sink) async {
  final container = archive.entry(_containerPath);
  String reason;
  if (container == null) {
    reason = 'META-INF/container.xml ausente';
  } else {
    final rootfiles = parseContainerXml(
      decodeText(await archive.read(container)),
      sink,
    );
    if (rootfiles.isEmpty) {
      reason = 'container.xml sem rootfile';
    } else {
      final found = _findEntry(archive, rootfiles.first, sink);
      if (found != null) return found;
      reason = 'rootfile "${rootfiles.first}" inexistente';
    }
  }
  final fallback = archive.entries
      .where((e) => e.name.toLowerCase().endsWith('.opf'))
      .firstOrNull;
  if (fallback == null) {
    throw MissingPackageDocumentException(
      'Nenhum documento de pacote (.opf) encontrado ($reason).',
    );
  }
  sink.report(
    Diagnostic(
      severity: DiagnosticSeverity.warning,
      code: DiagnosticCodes.containerMissing,
      message: '$reason; usando "${fallback.name}".',
      location: _containerPath,
    ),
  );
  return fallback;
}

Future<EpubNavigation> _loadNavigation(
  ZipArchive archive,
  OpfDocument opf,
  DiagnosticSink sink,
) async {
  Future<String?> text(ManifestItem item) async {
    final entry = _findEntry(archive, item.path, sink);
    return entry == null ? null : decodeText(await archive.read(entry));
  }

  final navItem = opf.navItem;
  if (navItem != null) {
    final xhtml = await text(navItem);
    final nav = xhtml == null
        ? null
        : parseNavDocument(xhtml, navPath: navItem.path, sink: sink);
    if (nav != null) return nav;
  }

  final ncxItem = opf.ncxItem;
  final ncxXml = ncxItem == null ? null : await text(ncxItem);
  final ncx = ncxXml == null
      ? null
      : parseNcx(ncxXml, ncxPath: ncxItem!.path, sink: sink);
  if (ncx != null) {
    // No EPUB 2 o NCX é a navegação normal; só no EPUB 3 é um fallback.
    if (navItem != null || opf.version == EpubVersion.epub3) {
      sink.report(
        Diagnostic(
          severity: DiagnosticSeverity.info,
          code: DiagnosticCodes.navFallbackToNcx,
          message: navItem == null
              ? 'EPUB 3 sem documento de navegação; usando o NCX.'
              : 'Documento de navegação ausente ou inválido; usando o NCX.',
          location: ncxItem!.path,
        ),
      );
    }
    return ncx;
  }

  sink.report(
    const Diagnostic(
      severity: DiagnosticSeverity.warning,
      code: DiagnosticCodes.navMissing,
      message: 'Nenhuma navegação utilizável (nav.xhtml ou NCX).',
    ),
  );
  return EpubNavigation.empty;
}
