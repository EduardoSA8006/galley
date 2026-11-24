import 'package:meta/meta.dart';

/// Versão do formato EPUB declarada (ou deduzida) pelo pacote.
enum EpubVersion {
  /// EPUB 2.x (NCX).
  epub2,

  /// EPUB 3.x (nav document).
  epub3,
}

/// Criador ou colaborador de uma publicação.
@immutable
final class EpubContributor {
  /// Cria um contribuidor.
  const EpubContributor({required this.name, this.fileAs, this.role});

  /// Nome de exibição.
  final String name;

  /// Forma de ordenação (ex.: "Sobrenome, Nome").
  final String? fileAs;

  /// Código de papel MARC (ex.: `aut`, `trl`).
  final String? role;

  @override
  String toString() => 'EpubContributor($name, fileAs: $fileAs, role: $role)';
}

/// Identificador (`dc:identifier`) da publicação.
@immutable
final class EpubIdentifier {
  /// Cria um identificador.
  const EpubIdentifier({required this.value, this.scheme, this.id});

  /// Valor do identificador.
  final String value;

  /// Esquema (ex.: `ISBN`), quando declarado.
  final String? scheme;

  /// Atributo `id` do elemento, usado por `unique-identifier`.
  final String? id;

  @override
  String toString() => 'EpubIdentifier($value, scheme: $scheme, id: $id)';
}

/// Metadados da publicação, extraídos do `<metadata>` do OPF.
@immutable
final class EpubMetadata {
  /// Cria os metadados; as coleções são copiadas como não modificáveis.
  EpubMetadata({
    required List<String> titles,
    required List<EpubContributor> creators,
    required List<EpubContributor> contributors,
    required List<String> languages,
    required List<EpubIdentifier> identifiers,
    required this.uniqueIdentifier,
    this.publisher,
    this.description,
    required List<String> subjects,
    this.date,
    this.modified,
    this.rights,
    required Map<String, String> otherMeta,
  }) : titles = List.unmodifiable(titles),
       creators = List.unmodifiable(creators),
       contributors = List.unmodifiable(contributors),
       languages = List.unmodifiable(languages),
       identifiers = List.unmodifiable(identifiers),
       subjects = List.unmodifiable(subjects),
       otherMeta = Map.unmodifiable(otherMeta);

  /// Títulos; o título principal (`main`) vem primeiro.
  final List<String> titles;

  /// Título principal, ou `null` quando não há nenhum.
  String? get title => titles.firstOrNull;

  /// Criadores (`dc:creator`).
  final List<EpubContributor> creators;

  /// Colaboradores (`dc:contributor`).
  final List<EpubContributor> contributors;

  /// Idiomas (`dc:language`).
  final List<String> languages;

  /// Identificadores (`dc:identifier`).
  final List<EpubIdentifier> identifiers;

  /// Valor do identificador apontado por `unique-identifier`.
  final String? uniqueIdentifier;

  /// Editora.
  final String? publisher;

  /// Descrição.
  final String? description;

  /// Assuntos (`dc:subject`).
  final List<String> subjects;

  /// Data de publicação (`dc:date`), como escrita no OPF.
  final String? date;

  /// Data de modificação (`dcterms:modified`), EPUB 3.
  final String? modified;

  /// Direitos (`dc:rights`).
  final String? rights;

  /// Demais `<meta>` (por `property` ou `name`); em chave repetida vale a
  /// primeira.
  final Map<String, String> otherMeta;
}
