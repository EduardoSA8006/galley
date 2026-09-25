/// Fim do arquivo (EOCD, EOCD64) e central directory (spec do contêiner
/// §5.1).
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../diagnostics/diagnostic.dart';
import '../../diagnostics/exceptions.dart';
import '../byte_source.dart';
import '../container.dart';
import 'binary.dart';
import 'cp437.dart';

const int _eocdSignature = 0x06054b50;
const int _locatorSignature = 0x07064b50;
const int _eocd64Signature = 0x06064b50;
const int _centralSignature = 0x02014b50;
const int _eocdSize = 22;
const int _locatorSize = 20;
const int _eocd64Size = 56;

/// Maior comentário do EOCD (65 535) + EOCD (22) + locator ZIP64 (20).
const int tailReadSize = 65535 + _eocdSize + _locatorSize;

/// Uma entrada do central directory.
final class ZipEntry {
  ZipEntry({
    required this.name,
    required this.rawName,
    required this.nameLength,
    required this.flags,
    required this.method,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.localHeaderOffset,
    required this.crc32,
    this.invalidReason,
  });

  /// Normalizado: `\` vira `/`, sem `/` nem `./` iniciais.
  final String name;

  /// Como decodificado do central directory, antes da normalização.
  final String rawName;

  /// Bytes do nome no central directory (orçamento da leitura do `fetch`).
  final int nameLength;

  final int flags;
  final int method;
  final int compressedSize;
  final int uncompressedSize;

  /// Já com o `delta` do prefixo.
  final int localHeaderOffset;

  final int crc32;

  /// Motivo de a entrada não ser legível (§5.1 item 7); `null` se válida.
  final String? invalidReason;

  bool get isDirectory => name.isEmpty || name.endsWith('/');
}

/// Resultado de uma busca no índice.
typedef ZipLookup = ({ZipEntry entry, bool exact});

/// Central directory lido e indexado.
final class CentralDirectory {
  CentralDirectory._({
    required this.entries,
    required this.length,
    required this.cdOffset,
    required this.cdSize,
    required this.delta,
    required this.zip64,
  });

  /// Todas as entradas, na ordem do central directory, inclusive diretórios
  /// e duplicatas.
  final List<ZipEntry> entries;

  /// Tamanho da fonte.
  final int length;

  /// Offset do central directory, já com [delta].
  final int cdOffset;
  final int cdSize;

  /// Bytes antes do ZIP (EPUB colado depois de outro arquivo).
  final int delta;

  final bool zip64;

  final Map<String, ZipEntry> _byName = {};
  final Map<String, ZipEntry> _byLowerName = {};
  final List<String> _paths = [];

  /// Arquivos (sem diretórios), primeira ocorrência de cada nome, na ordem do
  /// central directory.
  List<String> get paths => List.unmodifiable(_paths);

  /// Exato; senão, sem diferenciar maiúsculas (vence a primeira entrada).
  ZipLookup? lookup(String path) {
    final exact = _byName[path];
    if (exact != null) return (entry: exact, exact: true);
    final folded = _byLowerName[path.toLowerCase()];
    if (folded != null) return (entry: folded, exact: false);
    return null;
  }

  void _index(DiagnosticSink sink) {
    for (final e in entries) {
      if (e.isDirectory) continue;
      if (_byName.containsKey(e.name)) {
        sink.emit(
          EpubDiagnosticCode.zipDuplicateEntry,
          href: e.name,
          message: 'entrada repetida no central directory; vale a primeira',
          details: {'rawName': e.rawName},
        );
        continue;
      }
      _byName[e.name] = e;
      _byLowerName.putIfAbsent(e.name.toLowerCase(), () => e);
      _paths.add(e.name);
    }
  }
}

/// Normalização de nome de §5.1 item 5.
///
/// Avança um índice em vez de cortar `substring` a cada iteração: na VM
/// `substring` copia, e um nome hostil só de `/` ou `./` repetidos ficaria
/// quadrático (um EPUB com poucas entradas de dezenas de KiB assim travaria a
/// abertura por segundos).
String normalizeEntryName(String raw) {
  final name = raw.replaceAll(r'\', '/');
  var i = 0;
  while (true) {
    if (name.startsWith('/', i)) {
      i += 1;
    } else if (name.startsWith('./', i)) {
      i += 2;
    } else {
      break;
    }
  }
  return name.substring(i);
}

/// Lê o fim do arquivo e o central directory. Exceções da fonte viram
/// [EpubContainerException] com `cause`.
Future<CentralDirectory> readCentralDirectory(
  EpubByteSource source, {
  required DiagnosticSink sink,
}) async {
  final length = await _guard(() => source.length);
  final tailLength = math.min(length, tailReadSize);
  final tailStart = length - tailLength;
  final tail = await _read(source, tailStart, tailLength);

  final at = _findEocd(tail);
  if (at == null) {
    throw EpubContainerException(
      'fim do central directory (EOCD) não encontrado',
    );
  }
  final eocdPos = tailStart + at;
  var disk = readU16(tail, at + 4);
  var cdDisk = readU16(tail, at + 6);
  int? cdSize = readU32(tail, at + 12);
  int? cdOffset = readU32(tail, at + 16);
  var cdEnd = eocdPos;
  var zip64 = false;

  if (at >= _locatorSize &&
      readU32(tail, at - _locatorSize) == _locatorSignature) {
    final loc = at - _locatorSize;
    final totalDisks = readU32(tail, loc + 16);
    if (readU32(tail, loc + 4) != 0 || totalDisks > 1) {
      throw EpubContainerException('ZIP em vários discos não é suportado');
    }
    final declared = readU64(tail, loc + 8);
    final eocd64 = await _findEocd64(
      source,
      tail,
      tailStart,
      declared,
      eocdPos,
    );
    if (eocd64 == null) {
      throw EpubContainerException('registro EOCD64 não encontrado');
    }
    zip64 = true;
    cdEnd = eocd64.pos;
    disk = readU32(eocd64.bytes, 16);
    cdDisk = readU32(eocd64.bytes, 20);
    cdSize = readU64(eocd64.bytes, 40);
    cdOffset = readU64(eocd64.bytes, 48);
  }

  if (disk != 0 || cdDisk != 0) {
    throw EpubContainerException('ZIP em vários discos não é suportado');
  }
  if (cdSize == null || cdOffset == null || cdSize > cdEnd) {
    throw EpubContainerException('central directory não cabe no arquivo');
  }
  final delta = cdEnd - cdSize - cdOffset;
  if (delta < 0) {
    throw EpubContainerException(
      'central directory não cabe no arquivo (offset além do fim)',
    );
  }
  if (delta > 0) {
    sink.emit(
      EpubDiagnosticCode.mimetypeIrregular,
      message: '$delta bytes antes do ZIP',
      details: {'reason': 'prefix', 'delta': delta},
    );
  }

  final cd = await _read(source, cdOffset + delta, cdSize);
  final entries = _parseEntries(cd, delta: delta, length: length);
  return CentralDirectory._(
    entries: entries,
    length: length,
    cdOffset: cdOffset + delta,
    cdSize: cdSize,
    delta: delta,
    zip64: zip64,
  ).._index(sink);
}

/// Posição do EOCD em [tail], de trás para frente; o candidato só vale se o
/// comentário termina exatamente no fim do bloco.
int? _findEocd(Uint8List tail) {
  for (var pos = tail.length - _eocdSize; pos >= 0; pos--) {
    if (tail[pos] == 0x50 &&
        tail[pos + 1] == 0x4b &&
        readU32(tail, pos) == _eocdSignature &&
        pos + _eocdSize + readU16(tail, pos + 20) == tail.length) {
      return pos;
    }
  }
  return null;
}

/// O EOCD64 no offset declarado pelo locator; se não estiver lá (prefixo),
/// logo antes do locator.
Future<({int pos, Uint8List bytes})?> _findEocd64(
  EpubByteSource source,
  Uint8List tail,
  int tailStart,
  int? declared,
  int eocdPos,
) async {
  final candidates = [?declared, eocdPos - _locatorSize - _eocd64Size];
  for (final pos in candidates) {
    if (pos < 0 || pos + _eocd64Size > eocdPos - _locatorSize) continue;
    final bytes = pos >= tailStart
        ? Uint8List.sublistView(
            tail,
            pos - tailStart,
            pos - tailStart + _eocd64Size,
          )
        : await _read(source, pos, _eocd64Size);
    if (readU32(bytes, 0) == _eocd64Signature) return (pos: pos, bytes: bytes);
  }
  return null;
}

List<ZipEntry> _parseEntries(
  Uint8List cd, {
  required int delta,
  required int length,
}) {
  final entries = <ZipEntry>[];
  var p = 0;
  while (p < cd.length) {
    if (p + 46 > cd.length) {
      throw EpubContainerException('central directory truncado');
    }
    if (readU32(cd, p) != _centralSignature) {
      throw EpubContainerException(
        'assinatura de entrada do central directory errada no byte $p',
      );
    }
    final flags = readU16(cd, p + 8);
    final method = readU16(cd, p + 10);
    final crc = readU32(cd, p + 16);
    int? compressed = readU32(cd, p + 20);
    int? uncompressed = readU32(cd, p + 24);
    final nameLength = readU16(cd, p + 28);
    final extraLength = readU16(cd, p + 30);
    final commentLength = readU16(cd, p + 32);
    int? offset = readU32(cd, p + 42);
    final nameStart = p + 46;
    final extraStart = nameStart + nameLength;
    final end = extraStart + extraLength + commentLength;
    if (end > cd.length) {
      throw EpubContainerException('central directory truncado');
    }
    final nameBytes = Uint8List.sublistView(cd, nameStart, extraStart);
    final rawName = _decodeName(nameBytes, utf8Flag: flags & 0x0800 != 0);
    final name = normalizeEntryName(rawName);
    if (flags & 0x0001 != 0) {
      throw EpubEncryptedException(
        'entrada com a criptografia do próprio ZIP: $name',
        scheme: 'zip-encryption',
        href: name,
      );
    }

    // Campos 0xFFFFFFFF vêm do extra 0x0001, na ordem da especificação.
    var q = extraStart;
    final extraEnd = extraStart + extraLength;
    while (q + 4 <= extraEnd) {
      final id = readU16(cd, q);
      final size = readU16(cd, q + 2);
      final dataEnd = q + 4 + size;
      if (dataEnd > extraEnd) break;
      if (id == 0x0001) {
        var f = q + 4;
        int? next() {
          if (f + 8 > dataEnd) return null;
          final v = readU64(cd, f);
          f += 8;
          return v;
        }

        if (uncompressed == 0xFFFFFFFF) uncompressed = next();
        if (compressed == 0xFFFFFFFF) compressed = next();
        if (offset == 0xFFFFFFFF) offset = next();
        break;
      }
      q = dataEnd;
    }

    String? invalid;
    if (compressed == null || uncompressed == null || offset == null) {
      invalid = 'tamanho ou offset acima de 2^53';
    } else if (offset + delta >= length) {
      invalid = 'local header além do fim do arquivo';
    } else if (offset + delta + 30 + compressed > length) {
      invalid = 'dados da entrada além do fim do arquivo';
    } else if (uncompressed > maxEntrySize) {
      invalid = 'tamanho descomprimido acima de $maxEntrySize bytes';
    }

    entries.add(
      ZipEntry(
        name: name,
        rawName: rawName,
        nameLength: nameLength,
        flags: flags,
        method: method,
        compressedSize: compressed ?? 0,
        uncompressedSize: uncompressed ?? 0,
        localHeaderOffset: (offset ?? 0) + delta,
        crc32: crc,
        invalidReason: invalid,
      ),
    );
    p = end;
  }
  return entries;
}

/// Bit 11: UTF-8 tolerante. Sem ele: UTF-8 se válido, senão CP437.
String _decodeName(Uint8List bytes, {required bool utf8Flag}) {
  if (utf8Flag) return utf8.decode(bytes, allowMalformed: true);
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return decodeCp437(bytes);
  }
}

/// `readRange` com as exceções da fonte (`FileSystemException`,
/// `RangeError`, `StateError`) embrulhadas em [EpubContainerException].
Future<Uint8List> readSource(
  EpubByteSource source,
  int offset,
  int length, {
  String? href,
}) => _guard(() => source.readRange(offset, length), href: href);

Future<Uint8List> _read(EpubByteSource source, int offset, int length) =>
    readSource(source, offset, length);

Future<T> _guard<T>(Future<T> Function() op, {String? href}) async {
  try {
    return await op();
  } on EpubException {
    rethrow;
  } on Object catch (e) {
    throw EpubContainerException(
      'falha ao ler a fonte: $e',
      href: href,
      cause: e,
    );
  }
}
