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

  /// CRC-32 do conteúdo diverge do diretório central; bytes devolvidos
  /// mesmo assim (error).
  static const String zipCrcMismatch = 'zip.crcMismatch';

  /// `META-INF/container.xml` malformado; nenhum rootfile lido (error).
  static const String containerXmlInvalid = 'container.xmlInvalid';

  /// `container.xml` declara mais de um rootfile (múltiplas renditions);
  /// todos são devolvidos em ordem (info).
  static const String containerMultipleRenditions =
      'container.multipleRenditions';

  /// Atributo `version` do `<package>` ausente ou inválido; versão deduzida
  /// pela presença do item `nav` (warning).
  static const String opfVersionInvalid = 'opf.versionInvalid';

  /// Nenhum `dc:identifier` corresponde a `unique-identifier`; vale o
  /// primeiro identificador (warning).
  static const String opfUniqueIdentifierMissing =
      'opf.uniqueIdentifierMissing';

  /// OPF sem `dc:title` (warning).
  static const String opfTitleMissing = 'opf.titleMissing';

  /// Item do manifest sem `id`/`href`/`media-type` ou com `href` não
  /// resolvível; ignorado (warning).
  static const String opfManifestItemInvalid = 'opf.manifestItemInvalid';

  /// `id` duplicado no manifest; vale o primeiro item (warning).
  static const String opfDuplicateId = 'opf.duplicateId';

  /// `itemref` do spine com `idref` inexistente no manifest; ignorado
  /// (warning).
  static const String opfSpineRefMissing = 'opf.spineRefMissing';

  /// Valor desconhecido em `rendition:*`; vale o padrão (warning).
  static const String opfRenditionValueInvalid = 'opf.renditionValueInvalid';

  /// Spine sem nenhum item legível (error, não fatal).
  static const String opfSpineEmpty = 'opf.spineEmpty';
}
