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

  /// Documento de navegação (`nav.xhtml`) malformado; navegação ignorada
  /// (warning).
  static const String navInvalid = 'nav.invalid';

  /// NCX malformado; navegação ignorada (warning).
  static const String ncxInvalid = 'ncx.invalid';

  /// Navegação aninhada além do limite de profundidade; ramo truncado
  /// (warning).
  static const String navTooDeep = 'nav.tooDeep';

  /// `encryption.xml` malformado ou entrada sem `Algorithm`/`URI`; entrada
  /// ignorada (warning).
  static const String encryptionInvalid = 'encryption.invalid';

  /// Arquivo `mimetype` ausente no zip (warning).
  static const String mimetypeMissing = 'container.mimetypeMissing';

  /// Conteúdo de `mimetype` (aparado) diferente de `application/epub+zip`
  /// (warning).
  static const String mimetypeInvalid = 'container.mimetypeInvalid';

  /// `mimetype` não é a primeira entrada do zip (info).
  static const String mimetypeNotFirst = 'container.mimetypeNotFirst';

  /// `META-INF/container.xml` ausente, sem rootfile ou apontando para um
  /// arquivo inexistente; usado o primeiro `.opf` do zip (warning).
  static const String containerMissing = 'container.containerMissing';

  /// Recurso encontrado só ignorando a caixa do caminho (warning).
  static const String resourceCaseMismatch = 'resource.caseMismatch';

  /// Fonte ofuscada que não pôde ser desofuscada; bytes crus devolvidos
  /// (error).
  static const String fontDeobfuscationFailed = 'font.deobfuscationFailed';

  /// Documento de navegação EPUB 3 ausente ou inválido; sumário lido do NCX
  /// (info).
  static const String navFallbackToNcx = 'nav.fallbackToNcx';

  /// Nenhuma navegação utilizável; navegação vazia (warning).
  static const String navMissing = 'nav.missing';

  /// Comentários, instruções de processamento e doctype descartados do
  /// documento; a mensagem traz a contagem de cada tipo (info).
  static const String droppedNodes = 'document.droppedNodes';

  /// Prefixo de namespace usado sem declaração; `epub:` cai no namespace
  /// OPS, os demais num namespace "desconhecido" (info).
  static const String undeclaredPrefix = 'document.undeclaredPrefix';

  /// Raiz sem declaração `xmlns` padrão: os elementos sem prefixo são
  /// lidos no namespace XHTML (ou SVG, numa raiz `svg`), como se ele
  /// estivesse declarado (info).
  static const String impliedNamespace = 'document.impliedNamespace';

  /// Declaração de namespace ilegal (`xmlns:p=""` ou `xmlns:="…"`),
  /// ignorada (info).
  static const String invalidNamespaceDeclaration =
      'document.invalidNamespaceDeclaration';

  /// Documento malformado lido pelo modo tolerante (warning).
  static const String recovered = 'document.recovered';

  /// Fechamento sem abertura correspondente, descartado (warning).
  static const String strayEndTag = 'document.strayEndTag';

  /// Elemento sem fechamento, fechado implicitamente (warning).
  static const String unclosedElement = 'document.unclosedElement';

  /// Caractere que não inicia marcação válida (por exemplo um `<` solto no
  /// texto), mantido como texto pelo modo tolerante (warning).
  static const String markupAsText = 'document.markupAsText';

  /// Atributo repetido no mesmo elemento; vale o primeiro (info).
  static const String duplicateAttribute = 'document.duplicateAttribute';

  /// Documento irrecuperável; vira um `<body>` vazio (error).
  static const String unparseable = 'document.unparseable';

  /// `<link>` ou `<style>` fora do `<head>`, coletado mesmo assim (info).
  static const String headInBody = 'document.headInBody';

  /// `<link rel="stylesheet">` com href externo ou que escapa do zip;
  /// ignorado (info).
  static const String externalStyleSheet = 'document.externalStyleSheet';

  /// Ponto de recuperação de erro na sintaxe CSS (declaração inválida, bloco
  /// sem fechamento, aninhamento excessivo); o trecho é descartado (warning).
  static const String cssParseError = 'css.parseError';

  /// Seletor fora do suportado (pseudo desconhecido, `:has`, `:is`,
  /// `:nth-child(… of S)`...) ou malformado; a regra inteira é descartada
  /// (info).
  static const String cssUnsupportedSelector = 'css.unsupportedSelector';

  /// Propriedade fora do escopo do motor; declaração ignorada (info).
  static const String cssUnsupportedProperty = 'css.unsupportedProperty';

  /// Valor inválido para uma propriedade do escopo; declaração ignorada
  /// (info).
  static const String cssInvalidValue = 'css.invalidValue';

  /// At-rule não suportada (`@keyframes`, `@layer`, `@page :first`...);
  /// ignorada (info).
  static const String cssUnsupportedAtRule = 'css.unsupportedAtRule';

  /// `@font-face` sem família ou sem fonte utilizável; regra descartada
  /// (warning).
  static const String cssFontFaceInvalid = 'css.fontFaceInvalid';
}
