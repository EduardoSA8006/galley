/// Capa pelo pacote (spec da Publicação §8.2; doc/06 §5.1, passos 1, 2 e 4).
/// Os passos que olham a seção (3 e 5 de doc/06) são do sub-projeto 6.
library;

import '../diagnostics/diagnostic.dart';
import '../diagnostics/exceptions.dart';
import 'href.dart';
import 'model.dart';
import 'opf.dart';

/// Caminho da capa, na ordem: `properties` com `cover-image`; o item do
/// `<meta name="cover">` (por `id` e, sem casamento, pelo `content` resolvido
/// como `href` contra o diretório do OPF); um `image/*` cujo `id` ou caminho
/// contém `cover` (sem diferenciar maiúsculas, com `coverHeuristic`; entre
/// vários candidatos, prefere o de nome exatamente `cover`, senão o primeiro
/// na ordem do manifest). Os passos 1 e 2 só valem para item de `image/*`;
/// um item achado que não seja imagem (ou que seja `missing`/`remote`) não
/// é usado, e a busca segue para o próximo passo. Nenhum → `null`. No
/// máximo três passadas pelo manifest (uma por passo, mais a do `href` do
/// passo 2 quando o `content` não casa com nenhum `id`), então ainda
/// O(tamanho do manifest).
String? findCover(
  OpfDocument opf,
  Map<String, ManifestItem> manifest, {
  required DiagnosticSink sink,
}) {
  bool usable(ManifestItem item) => !item.missing && !item.remote;
  bool usableImage(ManifestItem item) =>
      usable(item) && item.mediaType.startsWith('image/');

  // Passo 1: properties="cover-image".
  for (final item in manifest.values) {
    if (usableImage(item) && item.properties.contains('cover-image')) {
      return item.path;
    }
  }

  // Passo 2: <meta name="cover">, por id e, sem casamento, por href.
  final coverId = opf.coverId;
  if (coverId != null) {
    final byId = manifest[coverId];
    if (byId != null) {
      if (usableImage(byId)) return byId.path;
    } else {
      final resolved = normalizeHref(dirnameOf(opf.opfPath), coverId);
      if (resolved != null) {
        for (final item in manifest.values) {
          if (item.path == resolved && usableImage(item)) return item.path;
        }
      }
    }
  }

  // Passo 3: id ou caminho com "cover"; desempate pelo nome exatamente
  // "cover", senão o primeiro na ordem do manifest.
  ManifestItem? first;
  ManifestItem? exact;
  for (final item in manifest.values) {
    if (!usableImage(item)) continue;
    if (!item.id.toLowerCase().contains('cover') &&
        !item.path.toLowerCase().contains('cover')) {
      continue;
    }
    first ??= item;
    if (exact == null &&
        basenameWithoutExtension(item.path).toLowerCase() == 'cover') {
      exact = item;
    }
  }
  final chosen = exact ?? first;
  if (chosen != null) {
    sink.emit(
      EpubDiagnosticCode.coverHeuristic,
      href: chosen.path,
      message: 'capa achada por heurística (id ou caminho com "cover")',
      details: {'id': chosen.id},
      onStrict: (m) => EpubPackageException(m, href: chosen.path),
    );
    return chosen.path;
  }
  return null;
}
