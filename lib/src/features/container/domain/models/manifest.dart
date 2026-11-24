import 'package:meta/meta.dart';

/// Item do manifest do OPF.
@immutable
final class ManifestItem {
  /// Cria um item do manifest.
  ManifestItem({
    required this.id,
    required this.path,
    required this.mediaType,
    Set<String> properties = const {},
    this.fallbackId,
  }) : properties = Set.unmodifiable(properties);

  /// Identificador único no manifest.
  final String id;

  /// Caminho do recurso no zip, já resolvido.
  final String path;

  /// Tipo de mídia declarado.
  final String mediaType;

  /// Propriedades (`properties`), como `nav`, `cover-image`, `scripted`.
  final Set<String> properties;

  /// Id do item de fallback, se houver.
  final String? fallbackId;
}
