/// Contêiner sobre um `.epub` (ZIP) lido por faixas (spec do contêiner §5).
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:xml/xml.dart';

import '../../diagnostics/diagnostic.dart';
import '../../diagnostics/exceptions.dart';
import '../byte_source.dart';
import '../container.dart';
import '../encryption.dart';
import 'binary.dart';
import 'central_directory.dart';

const int _localSignature = 0x04034b50;

final class ZipContainer implements EpubContainer {
  ZipContainer._(this._source, this._sink, this.centralDirectory);

  final EpubByteSource _source;
  final DiagnosticSink _sink;

  /// Central directory lido na abertura (testes e orçamento de leitura).
  @visibleForTesting
  final CentralDirectory centralDirectory;

  final Map<String, FontObfuscation> _obfuscation = {};
  Future<void>? _closing;

  /// Lê o central directory, confere o DRM e o `mimetype` (nesta ordem: DRM
  /// é fatal e vem primeiro). Exceção da fonte vira [EpubContainerException]
  /// com `cause`. Se a abertura falha, a fonte é fechada.
  static Future<ZipContainer> open(
    EpubByteSource source, {
    required DiagnosticSink sink,
  }) async {
    try {
      final cd = await readCentralDirectory(source, sink: sink);
      final container = ZipContainer._(source, sink, cd);
      await container._checkEncryption();
      await container._checkMimetype();
      return container;
    } on Object {
      try {
        await source.close();
      } on Object {
        // A falha original é a que importa.
      }
      rethrow;
    }
  }

  @override
  Iterable<String> get paths => centralDirectory.paths;

  @override
  Future<bool> exists(String path) async {
    _checkOpen();
    return centralDirectory.lookup(path) != null;
  }

  @override
  Future<PendingResource?> fetch(String path) async {
    _checkOpen();
    final hit = centralDirectory.lookup(path);
    if (hit == null) return null;
    final e = hit.entry;
    if (!hit.exact) {
      _sink.emit(
        EpubDiagnosticCode.pathCaseMismatch,
        href: path,
        message: 'caminho achado só sem diferenciar maiúsculas: ${e.name}',
        details: {'actual': e.name},
      );
    }
    final invalid = e.invalidReason;
    if (invalid != null) throw EpubContainerException(invalid, href: path);
    if (e.method != 0 && e.method != 8) {
      throw EpubContainerException(
        'método de compressão ${e.method} não suportado',
        href: path,
      );
    }

    final length = centralDirectory.length;
    final offset = e.localHeaderOffset;
    final first = await readSource(
      _source,
      offset,
      math.min(30 + e.nameLength + e.compressedSize + 1024, length - offset),
      href: path,
    );
    if (first.length < 30 || readU32(first, 0) != _localSignature) {
      throw EpubContainerException('local header inválido', href: path);
    }
    final dataStart = 30 + readU16(first, 26) + readU16(first, 28);
    final Uint8List data;
    if (dataStart + e.compressedSize <= first.length) {
      data = Uint8List.sublistView(
        first,
        dataStart,
        dataStart + e.compressedSize,
      );
    } else {
      if (offset + dataStart + e.compressedSize > length) {
        throw EpubContainerException(
          'dados da entrada além do fim do arquivo',
          href: path,
        );
      }
      data = await readSource(
        _source,
        offset + dataStart,
        e.compressedSize,
        href: path,
      );
    }
    return PendingResource.zip(
      path: e.name,
      size: e.uncompressedSize,
      method: e.method,
      data: data,
      crc32: e.crc32,
      sink: _sink,
    );
  }

  @override
  FontObfuscation? obfuscationOf(String path) {
    final hit = centralDirectory.lookup(path);
    return _obfuscation[hit?.entry.name ?? path];
  }

  @override
  Future<void> close() => _closing ??= _source.close();

  /// §6, nesta ordem: licença LCP, `rights.xml`, `encryption.xml`.
  Future<void> _checkEncryption() async {
    if (centralDirectory.lookup('META-INF/license.lcpl') != null) {
      throw EpubEncryptedException(
        'livro protegido por Readium LCP (META-INF/license.lcpl): esquema lcp',
        scheme: 'lcp',
      );
    }
    if (centralDirectory.lookup('META-INF/rights.xml') != null) {
      final text = await _readText('META-INF/rights.xml');
      final scheme = text == null ? 'unknown:rights.xml' : rightsScheme(text);
      throw EpubEncryptedException(
        'livro com META-INF/rights.xml: esquema $scheme',
        scheme: scheme,
        href: 'META-INF/rights.xml',
      );
    }
    if (centralDirectory.lookup('META-INF/encryption.xml') == null) return;
    const invalid = 'unknown:encryption.xml-invalido';
    final text = await _readText('META-INF/encryption.xml');
    if (text == null) {
      throw EpubEncryptedException(
        'META-INF/encryption.xml ilegível: sem como provar que não há DRM '
        '(esquema $invalid)',
        scheme: invalid,
        href: 'META-INF/encryption.xml',
      );
    }
    final List<EncryptedItem> items;
    try {
      items = parseEncryptionXml(text);
    } on XmlException catch (e) {
      throw EpubEncryptedException(
        'META-INF/encryption.xml não é XML válido: sem como provar que não '
        'há DRM (esquema $invalid)',
        scheme: invalid,
        href: 'META-INF/encryption.xml',
        cause: e,
      );
    }
    _obfuscation.addAll(
      resolveEncryption(
        items,
        resolve: (uri) => centralDirectory.lookup(uri)?.entry.name ?? uri,
        sink: _sink,
        drmIsFatal: true,
      ),
    );
  }

  /// Texto UTF-8 de uma entrada; `null` se ausente ou ilegível.
  Future<String?> _readText(String path) async {
    try {
      final pending = await fetch(path);
      if (pending == null) return null;
      for (final _ in pending.decode()) {}
      return utf8.decode(pending.bytes, allowMalformed: true);
    } on EpubContainerException {
      return null;
    }
  }

  void _checkOpen() {
    if (_closing != null) throw StateError('ZipContainer fechado');
  }

  /// §5.2: primeira entrada (menor offset, e esse offset é o início do ZIP),
  /// stored, conteúdo exato. Nunca fatal.
  Future<void> _checkMimetype() async {
    final reason = await _mimetypeProblem();
    if (reason == null) return;
    _sink.emit(
      EpubDiagnosticCode.mimetypeIrregular,
      href: 'mimetype',
      message: switch (reason) {
        'missing' => 'entrada mimetype ausente',
        'notFirst' => 'mimetype não é a primeira entrada do ZIP',
        'compressed' => 'mimetype comprimido (deveria ser stored)',
        'content' => 'mimetype com conteúdo diferente de application/epub+zip',
        _ => 'mimetype ilegível',
      },
      details: {'reason': reason},
    );
  }

  Future<String?> _mimetypeProblem() async {
    final cd = centralDirectory;
    final hit = cd.lookup('mimetype');
    if (hit == null || !hit.exact) return 'missing';
    final entry = hit.entry;
    final first = cd.entries.reduce(
      (a, b) => b.localHeaderOffset < a.localHeaderOffset ? b : a,
    );
    if (!identical(first, entry) || entry.localHeaderOffset != cd.delta) {
      return 'notFirst';
    }
    if (entry.method != 0) return 'compressed';
    try {
      final pending = (await fetch('mimetype'))!;
      for (final _ in pending.decode()) {}
      final text = latin1.decode(pending.bytes);
      return text == 'application/epub+zip' ? null : 'content';
    } on EpubContainerException {
      return 'unreadable';
    }
  }
}
