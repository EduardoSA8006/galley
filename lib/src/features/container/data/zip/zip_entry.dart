/// Entrada do diretório central de um zip.
final class ZipEntry {
  /// Cria uma entrada.
  const ZipEntry({
    required this.name,
    required this.method,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.crc32,
    required this.localHeaderOffset,
    required this.isEncrypted,
  });

  /// Caminho normalizado (separador `/`).
  final String name;

  /// Método de compressão (0 = armazenado, 8 = deflate).
  final int method;

  /// Tamanho comprimido, em bytes.
  final int compressedSize;

  /// Tamanho descomprimido, em bytes.
  final int uncompressedSize;

  /// CRC-32 dos dados descomprimidos.
  final int crc32;

  /// Posição do cabeçalho local na fonte.
  final int localHeaderOffset;

  /// Se a entrada está cifrada (flag bit 0).
  final bool isEncrypted;

  /// Se a entrada é um diretório (nome terminado em `/`).
  bool get isDirectory => name.endsWith('/');

  @override
  String toString() => 'ZipEntry($name)';
}
