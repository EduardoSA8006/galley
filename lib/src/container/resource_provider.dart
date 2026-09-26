/// Recursos servidos pelo app, sem ZIP (doc/07 §4).
library;

import 'dart:typed_data';

/// O app entrega os bytes já claros (decifrados, se houver DRM). Caminhos
/// relativos à raiz do contêiner, normalizados pela Publicação.
abstract interface class EpubResourceProvider {
  Future<Uint8List> read(String href);
  Future<bool> exists(String href);
  Future<void> close();
}
