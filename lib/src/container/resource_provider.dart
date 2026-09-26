/// Recursos servidos pelo app, sem ZIP (doc/07 §4).
library;

import 'dart:typed_data';

/// O app entrega os bytes já claros (decifrados, se houver DRM). Caminhos
/// relativos à raiz do contêiner, normalizados pela Publicação.
///
/// Os caminhos recebidos por [read] e [exists] são **literais**: já
/// normalizados (`normalizeHref`/`decodePath`), sem `\`, sem `..` e sem `%xx`
/// como separador de verdade. O provider **nunca** deve decodificar `%xx`
/// nem resolvê-los com `Uri.parse`/`toFilePath` — um `%2e%2e` literal no
/// caminho é o nome de um arquivo, não um `..` a interpretar de novo.
abstract interface class EpubResourceProvider {
  Future<Uint8List> read(String href);
  Future<bool> exists(String href);
  Future<void> close();
}
