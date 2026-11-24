import 'package:meta/meta.dart';

import 'epub_metadata.dart';
import 'manifest.dart';
import 'rendition.dart';
import 'spine.dart';

/// Documento de pacote (OPF) interpretado.
@immutable
final class OpfDocument {
  /// Cria o documento.
  OpfDocument({
    required this.version,
    required this.metadata,
    required Map<String, ManifestItem> manifest,
    required this.spine,
    required this.rendition,
    this.cover,
    this.navItem,
    this.ncxItem,
  }) : manifest = Map.unmodifiable(manifest);

  /// Versão do EPUB.
  final EpubVersion version;

  /// Metadados.
  final EpubMetadata metadata;

  /// Itens do manifest por id.
  final Map<String, ManifestItem> manifest;

  /// Ordem de leitura.
  final EpubSpine spine;

  /// Propriedades de rendition.
  final EpubRendition rendition;

  /// Imagem de capa, se encontrada.
  final ManifestItem? cover;

  /// Documento de navegação EPUB 3 (property `nav`).
  final ManifestItem? navItem;

  /// Documento NCX (EPUB 2).
  final ManifestItem? ncxItem;
}
