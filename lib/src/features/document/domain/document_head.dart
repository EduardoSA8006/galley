import 'package:meta/meta.dart';

/// Dados extraídos do `<head>` de um documento (folhas de estilo, título,
/// `lang`/`dir`, `<meta>`).
///
/// Por enquanto só existe o [empty]; os campos chegam com a extração do
/// `<head>`.
@immutable
final class DocumentHead {
  const DocumentHead._();

  /// Head sem nenhum dado.
  static const DocumentHead empty = DocumentHead._();
}
