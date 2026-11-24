/// Códigos estáveis de `Diagnostic`.
///
/// Este arquivo é a fonte única dos códigos; cada task acrescenta os seus.
abstract final class DiagnosticCodes {
  /// Nome de entrada do zip fora de UTF-8, lido como CP437 (info).
  static const String zipNameNotUtf8 = 'zip.nameNotUtf8';

  /// Entrada do zip com caminho absoluto ou `..`, ignorada (warning).
  static const String zipUnsafePath = 'zip.unsafePath';

  /// Entrada duplicada no zip; vale a primeira (warning).
  static const String zipDuplicateEntry = 'zip.duplicateEntry';
}
