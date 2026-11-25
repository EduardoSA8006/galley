import '../../../core/diagnostics/diagnostic.dart';
import 'document_head.dart';
import 'document_tree.dart';

/// Resultado da leitura de um documento: a árvore, o `<head>` extraído e
/// os diagnósticos, só com dados (pode ser enviado entre isolates).
final class ParsedDocument {
  /// Cria o resultado; [diagnostics] é copiada para uma lista não
  /// modificável.
  ParsedDocument({
    required this.tree,
    required this.head,
    required List<Diagnostic> diagnostics,
    required this.recovered,
    this.internalError,
  }) : diagnostics = List.unmodifiable(diagnostics);

  /// A árvore do documento.
  final DocumentTree tree;

  /// Os dados do `<head>`.
  final DocumentHead head;

  /// Os diagnósticos da leitura, em ordem de emissão (não modificável).
  final List<Diagnostic> diagnostics;

  /// `true` se o documento não pôde ser lido como XML bem formado e a
  /// árvore veio da recuperação (inclusive o documento irrecuperável).
  final bool recovered;

  /// Tipo da exceção inesperada que o leitor capturou (ex.: `StateError`),
  /// ou `null` no caso normal.
  ///
  /// Só é preenchido pelo catch-all de `parseDocumentBytes`, que transforma
  /// um defeito interno em documento irrecuperável para cumprir o contrato
  /// "nunca lança". Não-nulo é **sinal de bug do Galley**, não de um
  /// documento ruim: o benchmark (`wide`, `docdiff`) reprova com ele.
  final String? internalError;
}
