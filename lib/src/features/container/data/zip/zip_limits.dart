/// Limites de segurança aplicados na leitura de um zip.
final class ZipLimits {
  /// Cria os limites; os padrões protegem contra zip bombs.
  const ZipLimits({
    this.maxEntries = 100000,
    this.maxEntrySize = 512 * 1024 * 1024,
    this.maxCompressionRatio = 1000,
    this.ratioCheckThreshold = 1024 * 1024,
  });

  /// Número máximo de entradas no diretório central.
  final int maxEntries;

  /// Tamanho máximo descomprimido de uma entrada, em bytes.
  final int maxEntrySize;

  /// Razão máxima entre tamanho descomprimido e comprimido.
  final int maxCompressionRatio;

  /// Tamanho descomprimido (em bytes) a partir do qual a razão é verificada.
  final int ratioCheckThreshold;
}
