/// Exceções do pacote (doc/09 §2). As desta etapa: contêiner, pacote, DRM e
/// seção.
library;

import 'package:meta/meta.dart';

/// Raiz da taxonomia. `abstract base`, não `sealed`: uma exceção nova não
/// quebra `switch` de consumidores (doc/11 §3.3).
abstract base class EpubException implements Exception {
  EpubException(this.message, {this.href, this.cause});

  final String message;

  /// Caminho da entrada envolvida, quando há uma.
  final String? href;

  /// Exceção embrulhada (FormatException, XmlException, FileSystemException).
  final Object? cause;

  /// Nome do tipo em `toString`. Literal, e não `runtimeType`, porque o
  /// dart2js minifica nomes de tipo em release.
  @protected
  String get typeName;

  @override
  String toString() =>
      href == null ? '$typeName: $message' : '$typeName($href): $message';
}

/// ZIP ilegível. Fatal em `ZipContainer.open`; depois dele, é falha de uma
/// entrada (spec do contêiner §4.1).
final class EpubContainerException extends EpubException {
  EpubContainerException(super.message, {super.href, super.cause});

  @override
  String get typeName => 'EpubContainerException';
}

/// DRM que o pacote não decifra. Fatal em `open` (doc/09 §4).
final class EpubEncryptedException extends EpubException {
  EpubEncryptedException(
    super.message, {
    required this.scheme,
    super.href,
    super.cause,
  });

  /// `lcp`, `adobe-adept`, `zip-encryption` ou `unknown:<detalhe>`.
  final String scheme;

  @override
  String get typeName => 'EpubEncryptedException';
}

/// Pacote inválido: OPF ausente, ilegível como XML, sem `manifest` ou
/// `spine`, spine vazio (spec da Publicação §9.1). Também é o tipo que um
/// warning da Publicação lança em `strict`.
final class EpubPackageException extends EpubException {
  EpubPackageException(super.message, {super.href, super.cause});

  @override
  String get typeName => 'EpubPackageException';
}

/// Falha de parse de uma seção (doc/09 §2). Nunca chega ao app fora de
/// `strict`: vira seção degradada e diagnóstico. Em `strict`, é também o tipo
/// que um warning do CSS lança (spec do CSS §12.3). Interna até o
/// sub-projeto 6.
final class EpubSectionParseException extends EpubException {
  EpubSectionParseException(super.message, {super.href, super.cause});

  @override
  String get typeName => 'EpubSectionParseException';
}
