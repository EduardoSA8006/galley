import 'dart:convert';
import 'dart:io';

/// Um livro externo do corpus público, fixado por `sha256`.
final class CorpusEntry {
  /// Cria a entrada; normalmente vem de [loadManifest].
  const CorpusEntry({
    required this.id,
    required this.url,
    required this.mirrorUrl,
    required this.sha256,
    required this.license,
    required this.source,
    required this.tags,
    required this.mirrorable,
  });

  /// Identificador estável (também é o nome do asset no espelho).
  final String id;

  /// URL original de download.
  final Uri url;

  /// URL no espelho (release `corpus-v1`); só existe se [mirrorable].
  final Uri? mirrorUrl;

  /// `sha256` do arquivo, em hexadecimal minúsculo.
  final String sha256;

  /// Licença (identificador SPDX ou descrição curta).
  final String license;

  /// Procedência (acervo de origem).
  final String source;

  /// Tags de cobertura (`epub2`, `epub3`, `fixed-layout`, `cjk`, `rtl`,
  /// `tables`, `illustrated`, `technical`, `w3c-tests`, `large`).
  final Set<String> tags;

  /// Se a licença permite redistribuir o arquivo no espelho do projeto.
  final bool mirrorable;
}

/// Lê o manifesto JSON em [path] e devolve as entradas na ordem do arquivo.
///
/// Lança [FormatException] se a estrutura ou algum campo for inválido.
List<CorpusEntry> loadManifest(String path) {
  final Object? root = jsonDecode(File(path).readAsStringSync());
  if (root is! Map<String, Object?> || root['books'] is! List<Object?>) {
    throw FormatException('manifesto sem a lista "books": $path');
  }
  return [
    for (final item in root['books']! as List<Object?>) _parseEntry(item),
  ];
}

CorpusEntry _parseEntry(Object? item) {
  if (item is! Map<String, Object?>) {
    throw FormatException('item do manifesto não é um objeto: $item');
  }
  T field<T>(String name) {
    final value = item[name];
    if (value is! T) {
      throw FormatException('campo "$name" ausente ou inválido em $item');
    }
    return value;
  }

  final mirrorable = field<bool>('mirrorable');
  final mirror = item['mirrorUrl'];
  if (mirror != null && mirror is! String) {
    throw FormatException('campo "mirrorUrl" inválido em $item');
  }
  final tags = field<List<Object?>>('tags');
  return CorpusEntry(
    id: field<String>('id'),
    url: Uri.parse(field<String>('url')),
    mirrorUrl: mirror == null ? null : Uri.parse(mirror as String),
    sha256: field<String>('sha256').toLowerCase(),
    license: field<String>('license'),
    source: field<String>('source'),
    tags: {
      for (final tag in tags)
        if (tag is String)
          tag
        else
          throw FormatException('tag inválida em $item'),
    },
    mirrorable: mirrorable,
  );
}
