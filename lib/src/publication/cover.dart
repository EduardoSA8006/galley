/// Capa pelo pacote (spec da Publicação §8.2; doc/06 §5.1, passos 1, 2 e 4).
/// Os passos que olham a seção (3 e 5 de doc/06) são do sub-projeto 6.
library;

import '../diagnostics/diagnostic.dart';
import '../diagnostics/exceptions.dart';
import 'model.dart';
import 'opf.dart';

/// Caminho da capa, na ordem: `properties` com `cover-image`; o item do
/// `<meta name="cover">`; um `image/*` cujo `id` ou caminho contém `cover`
/// (sem diferenciar maiúsculas, com `coverHeuristic`). Itens `missing` ou
/// `remote` são pulados. Uma passada pelo manifest por passo.
String? findCover(
  OpfDocument opf,
  Map<String, ManifestItem> manifest, {
  required DiagnosticSink sink,
}) {
  bool usable(ManifestItem item) => !item.missing && !item.remote;
  for (final item in manifest.values) {
    if (usable(item) && item.properties.contains('cover-image')) {
      return item.path;
    }
  }
  final byMeta = opf.coverId == null ? null : manifest[opf.coverId];
  if (byMeta != null && usable(byMeta)) return byMeta.path;
  for (final item in manifest.values) {
    if (!usable(item) || !item.mediaType.startsWith('image/')) continue;
    if (item.id.toLowerCase().contains('cover') ||
        item.path.toLowerCase().contains('cover')) {
      sink.emit(
        EpubDiagnosticCode.coverHeuristic,
        href: item.path,
        message: 'capa achada por heurística (id ou caminho com "cover")',
        details: {'id': item.id},
        onStrict: (m) => EpubPackageException(m, href: item.path),
      );
      return item.path;
    }
  }
  return null;
}
