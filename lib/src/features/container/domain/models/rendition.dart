import 'package:meta/meta.dart';

/// Layout da rendition.
enum RenditionLayout {
  /// Texto fluido.
  reflowable,

  /// Páginas de layout fixo.
  prePaginated,
}

/// Orientação da rendition.
enum RenditionOrientation {
  /// Sem preferência.
  auto,

  /// Retrato.
  portrait,

  /// Paisagem.
  landscape,
}

/// Comportamento de spreads (páginas duplas).
enum RenditionSpread {
  /// Sem preferência.
  auto,

  /// Nunca usar spread.
  none,

  /// Spread em paisagem.
  landscape,

  /// Spread em qualquer orientação.
  both,
}

/// Propriedades `rendition:*` do livro.
@immutable
final class EpubRendition {
  /// Cria a rendition; os padrões são reflowable/auto/auto.
  const EpubRendition({
    this.layout = RenditionLayout.reflowable,
    this.orientation = RenditionOrientation.auto,
    this.spread = RenditionSpread.auto,
  });

  /// Layout.
  final RenditionLayout layout;

  /// Orientação.
  final RenditionOrientation orientation;

  /// Spread.
  final RenditionSpread spread;
}
