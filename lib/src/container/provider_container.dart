/// Contêiner sobre um [EpubResourceProvider] do app (spec do contêiner
/// §6.2). O provider é a autoridade: sem busca sem diferenciar
/// maiúsculas, sem CRC, sem `mimetype` e sem DRM fatal (ele já decifrou,
/// doc/09 §4).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import '../diagnostics/diagnostic.dart';
import '../diagnostics/exceptions.dart';
import 'container.dart';
import 'encryption.dart';
import 'resource_provider.dart';

const String _encryptionPath = 'META-INF/encryption.xml';

final class ProviderContainer implements EpubContainer {
  ProviderContainer._(this._provider);

  final EpubResourceProvider _provider;
  final Map<String, FontObfuscation> _obfuscation = {};
  Future<void>? _closing;

  /// Lê só as entradas de ofuscação de fonte de `encryption.xml`, se houver.
  /// XML inválido ou ilegível emite `encryptionIgnored` e segue. Se a
  /// abertura falha (só possível em `strict`, com `fontObfuscationUnknown`),
  /// o provider é fechado antes de relançar, como o `ZipContainer` faz com a
  /// fonte.
  static Future<ProviderContainer> open(
    EpubResourceProvider provider, {
    required DiagnosticSink sink,
  }) async {
    final container = ProviderContainer._(provider);
    try {
      final Uint8List bytes;
      try {
        if (!await provider.exists(_encryptionPath)) return container;
        bytes = await provider.read(_encryptionPath);
      } on Object catch (e) {
        sink.emit(
          EpubDiagnosticCode.encryptionIgnored,
          href: _encryptionPath,
          message: 'encryption.xml ilegível pelo provider; ofuscação ignorada',
          details: {'reason': 'unreadable', 'exception': '$e'},
        );
        return container;
      }
      if (bytes.length > maxMetadataSize) {
        sink.emit(
          EpubDiagnosticCode.encryptionIgnored,
          href: _encryptionPath,
          message:
              'encryption.xml acima do teto de $maxMetadataSize bytes; '
              'ofuscação ignorada',
          details: {'reason': 'too-large'},
        );
        return container;
      }
      final text = utf8.decode(bytes, allowMalformed: true);
      try {
        container._obfuscation.addAll(
          resolveEncryption(
            parseEncryptionXml(text),
            resolve: (uri) => uri,
            sink: sink,
            drmIsFatal: false,
          ),
        );
      } on XmlException catch (e) {
        sink.emit(
          EpubDiagnosticCode.encryptionIgnored,
          href: _encryptionPath,
          message: 'encryption.xml não é XML válido; ofuscação ignorada',
          details: {'reason': 'invalid-xml', 'exception': '$e'},
        );
      }
      return container;
    } on Object {
      try {
        await provider.close();
      } on Object {
        // A falha original é a que importa.
      }
      rethrow;
    }
  }

  /// O provider não lista seus recursos.
  @override
  Iterable<String> get paths => const [];

  @override
  Future<bool> exists(String path) async {
    _checkOpen();
    try {
      return await _provider.exists(path);
    } on Object catch (e) {
      throw EpubContainerException('provider falhou: $e', href: path, cause: e);
    }
  }

  @override
  Future<PendingResource?> fetch(String path) async {
    _checkOpen();
    try {
      if (!await _provider.exists(path)) return null;
      final bytes = await _provider.read(path);
      if (bytes.length > maxEntrySize) {
        throw EpubContainerException(
          'recurso acima de $maxEntrySize bytes',
          href: path,
        );
      }
      return PendingResource.ready(path: path, bytes: bytes);
    } on EpubException {
      rethrow;
    } on Object catch (e) {
      throw EpubContainerException('provider falhou: $e', href: path, cause: e);
    }
  }

  @override
  FontObfuscation? obfuscationOf(String path) => _obfuscation[path];

  @override
  Future<void> close() => _closing ??= _provider.close();

  void _checkOpen() {
    if (_closing != null) throw StateError('ProviderContainer fechado');
  }
}
