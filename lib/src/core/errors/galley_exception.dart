/// Erro irrecuperável ao abrir ou usar um EPUB.
///
/// É o único tipo de exceção que escapa da API pública do Galley; problemas
/// recuperáveis são reportados como `Diagnostic`.
sealed class GalleyException implements Exception {
  const GalleyException();

  /// Descrição legível do erro.
  String get message;

  @override
  String toString() => '$runtimeType: $message';
}

/// O arquivo não é um EPUB (por exemplo, `mimetype` ausente ou incorreto).
final class NotAnEpubException extends GalleyException {
  /// Cria a exceção com a [message] informada.
  const NotAnEpubException(this.message);

  @override
  final String message;
}

/// O arquivo ZIP está corrompido ou malformado.
final class CorruptArchiveException extends GalleyException {
  /// Cria a exceção com a [message] informada.
  const CorruptArchiveException(this.message);

  @override
  final String message;
}

/// O arquivo excede um limite de segurança (tamanho, entradas ou razão).
final class ArchiveLimitExceededException extends GalleyException {
  /// Cria a exceção com a [message] informada.
  const ArchiveLimitExceededException(this.message);

  @override
  final String message;
}

/// O documento de pacote (OPF) não foi encontrado ou não pôde ser lido.
final class MissingPackageDocumentException extends GalleyException {
  /// Cria a exceção com a [message] informada.
  const MissingPackageDocumentException(this.message);

  @override
  final String message;
}

/// O EPUB usa DRM/criptografia que o Galley não suporta.
final class DrmProtectedException extends GalleyException {
  /// Cria a exceção com os [algorithms] de criptografia encontrados.
  DrmProtectedException(List<String> algorithms)
    : algorithms = List.unmodifiable(algorithms);

  /// Identificadores (URIs) dos algoritmos de criptografia encontrados.
  final List<String> algorithms;

  @override
  String get message =>
      'EPUB protegido por DRM; algoritmos não suportados: '
      '${algorithms.join(', ')}';
}

/// Um recurso solicitado não existe no EPUB.
final class ResourceNotFoundException extends GalleyException {
  /// Cria a exceção para o [path] não encontrado.
  const ResourceNotFoundException(this.path);

  /// Caminho do recurso inexistente.
  final String path;

  @override
  String get message => 'Recurso não encontrado: $path';
}

/// O livro já foi fechado e não pode mais ser usado.
final class BookClosedException extends GalleyException {
  /// Cria a exceção.
  const BookClosedException();

  @override
  String get message => 'O livro já foi fechado.';
}
