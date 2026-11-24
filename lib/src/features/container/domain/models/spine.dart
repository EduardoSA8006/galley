import 'package:meta/meta.dart';

import 'manifest.dart';

/// Direção de progressão de páginas declarada no spine.
enum PageProgressionDirection {
  /// Esquerda para a direita.
  ltr,

  /// Direita para a esquerda.
  rtl,

  /// Não declarada.
  unspecified,
}

/// Item da ordem de leitura.
@immutable
final class SpineItem {
  /// Cria um item do spine.
  SpineItem({
    required this.item,
    this.linear = true,
    Set<String> properties = const {},
  }) : properties = Set.unmodifiable(properties);

  /// Item do manifest referenciado.
  final ManifestItem item;

  /// `false` quando `linear="no"`.
  final bool linear;

  /// Propriedades do `itemref` (ex.: `page-spread-left`).
  final Set<String> properties;
}

/// Ordem de leitura do livro.
@immutable
final class EpubSpine {
  /// Cria o spine.
  EpubSpine({
    required List<SpineItem> items,
    this.direction = PageProgressionDirection.unspecified,
  }) : items = List.unmodifiable(items);

  /// Itens em ordem de leitura.
  final List<SpineItem> items;

  /// Direção de progressão de páginas.
  final PageProgressionDirection direction;
}
