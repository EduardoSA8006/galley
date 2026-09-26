/// Metadados da publicação (doc/06 §5; spec da Publicação §3 e §6.2).
library;

/// Metadados do OPF. Pública desde já (nome de doc/11 §3.3); o
/// `EpubDocument` do sub-projeto 6 a expõe como `doc.metadata`.
final class EpubMetadata {
  EpubMetadata({
    this.title,
    this.subtitle,
    List<String> authors = const [],
    List<String> contributors = const [],
    this.language,
    this.publisher,
    this.identifier,
    this.description,
    this.published,
    this.modified,
    List<String> subjects = const [],
    this.rights,
    this.series,
    this.seriesIndex,
    Map<String, List<String>> raw = const {},
  }) : authors = List.unmodifiable(authors),
       contributors = List.unmodifiable(contributors),
       subjects = List.unmodifiable(subjects),
       raw = Map.unmodifiable({
         for (final MapEntry(:key, :value) in raw.entries)
           key: List<String>.unmodifiable(value),
       });

  final String? title;
  final String? subtitle;
  final List<String> authors;
  final List<String> contributors;
  final String? language;
  final String? publisher;

  /// O primeiro dos identificadores únicos (a chave IDPF, doc/09 §4).
  final String? identifier;
  final String? description;
  final DateTime? published;
  final DateTime? modified;
  final List<String> subjects;
  final String? rights;

  /// `belongs-to-collection` de série, ou `calibre:series`.
  final String? series;
  final double? seriesIndex;

  /// O que não virou campo: chave = nome local do `dc:*` (em minúsculas), ou
  /// o `property`/`name` do `meta`; valores em ordem de documento.
  final Map<String, List<String>> raw;
}
