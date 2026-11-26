import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:galley/src/core/diagnostics/diagnostic.dart';
import 'package:galley/src/core/diagnostics/diagnostic_codes.dart';
import 'package:galley/src/core/diagnostics/diagnostic_sink.dart';
import 'package:galley/src/core/errors/galley_exception.dart';
import 'package:galley/src/features/container/data/zip/byte_source.dart';
import 'package:galley/src/features/container/data/zip/cp437.dart';
import 'package:galley/src/features/container/data/zip/crc32.dart';
import 'package:galley/src/features/container/data/zip/zip_entry.dart';
import 'package:galley/src/features/container/data/zip/zip_limits.dart';

const int _eocdSig = 0x06054b50;
const int _locator64Sig = 0x07064b50;
const int _eocd64Sig = 0x06064b50;
const int _cdSig = 0x02014b50;
const int _localSig = 0x04034b50;
const int _localHeaderSize = 30;
const int _eocdMin = 22;
const int _maxComment = 65535;

/// Leitor preguiçoso de zip: lê só o diretório central na abertura.
final class ZipArchive {
  ZipArchive._(this._source, this.limits, this._sink, _Directory directory)
    : entries = List.unmodifiable(directory.entries),
      _byName = directory.byName;

  /// Abre o zip em [source], lendo o diretório central.
  ///
  /// Lança [NotAnEpubException] se não houver EOCD,
  /// [CorruptArchiveException] se a estrutura for inconsistente e
  /// [ArchiveLimitExceededException] se houver mais entradas que
  /// [ZipLimits.maxEntries].
  static Future<ZipArchive> open(
    ByteSource source, {
    ZipLimits limits = const ZipLimits(),
    DiagnosticSink sink = const NullDiagnosticSink(),
  }) async {
    final directory = await _readDirectory(source, limits, sink);
    return ZipArchive._(source, limits, sink, directory);
  }

  final ByteSource _source;
  final DiagnosticSink _sink;
  bool _closed = false;

  /// Limites de segurança aplicados a esta leitura.
  final ZipLimits limits;

  /// Entradas na ordem do diretório central (já sem as inseguras/duplicadas).
  final List<ZipEntry> entries;

  final Map<String, ZipEntry> _byName;
  Map<String, ZipEntry>? _byLowerName;

  /// Entrada com nome exatamente igual a [name], ou `null`.
  ZipEntry? entry(String name) => _byName[name];

  /// Entrada cujo nome coincide com [name] sem diferenciar caixa, ou `null`.
  ///
  /// Se houver mais de uma, vale a primeira do diretório central.
  ZipEntry? entryIgnoringCase(String name) {
    final index = _byLowerName ??= {
      for (final e in entries.reversed) e.name.toLowerCase(): e,
    };
    return index[name.toLowerCase()];
  }

  /// Lê e descomprime o conteúdo de [entry].
  ///
  /// Lança [BookClosedException] após [close], [DrmProtectedException] para
  /// entradas cifradas, [ArchiveLimitExceededException] se os limites de
  /// tamanho ou de razão de compressão forem excedidos e
  /// [CorruptArchiveException] para qualquer inconsistência ou falha de E/S.
  /// CRC divergente não lança: reporta `zip.crcMismatch` e devolve os bytes.
  Future<Uint8List> read(ZipEntry entry) async {
    if (_closed) throw const BookClosedException();
    if (entry.isEncrypted) {
      throw DrmProtectedException(['zip-encryption']);
    }
    if (entry.method != 0 && entry.method != 8) {
      throw _corrupt(
        'método de compressão ${entry.method} não suportado em '
        '"${entry.name}"',
      );
    }
    _checkLimits(entry);

    final Uint8List result;
    try {
      final compressed = await _readCompressed(entry);
      result = entry.method == 0
          ? _storedBytes(entry, compressed)
          : _inflate(entry, compressed);
    } on GalleyException {
      rethrow;
    } on Object catch (e) {
      throw _corrupt('falha ao ler "${entry.name}" ($e)');
    }

    if (crc32(result) != entry.crc32) {
      _sink.report(
        Diagnostic(
          severity: DiagnosticSeverity.error,
          code: DiagnosticCodes.zipCrcMismatch,
          message: 'CRC-32 da entrada diverge do diretório central.',
          location: entry.name,
        ),
      );
    }
    return result;
  }

  void _checkLimits(ZipEntry entry) {
    if (entry.method == 0 && entry.compressedSize != entry.uncompressedSize) {
      throw _corrupt('tamanhos de "${entry.name}" divergem no método stored');
    }
    if (entry.compressedSize > limits.maxEntrySize) {
      throw ArchiveLimitExceededException(
        'A entrada "${entry.name}" tem ${entry.compressedSize} bytes '
        'comprimidos; o limite é ${limits.maxEntrySize}.',
      );
    }
    final size = entry.uncompressedSize;
    if (size > limits.maxEntrySize) {
      throw ArchiveLimitExceededException(
        'A entrada "${entry.name}" tem $size bytes; o limite é '
        '${limits.maxEntrySize}.',
      );
    }
    if (size > limits.ratioCheckThreshold) {
      final ratio =
          size / (entry.compressedSize < 1 ? 1 : entry.compressedSize);
      if (ratio > limits.maxCompressionRatio) {
        throw ArchiveLimitExceededException(
          'A entrada "${entry.name}" tem razão de compressão acima de '
          '${limits.maxCompressionRatio}.',
        );
      }
    }
  }

  Future<Uint8List> _readCompressed(ZipEntry entry) async {
    final total = _source.length;
    final offset = entry.localHeaderOffset;
    if (offset < 0 || total - offset < _localHeaderSize) {
      throw _corrupt('cabeçalho local de "${entry.name}" fora da fonte');
    }
    final header = await _source.read(offset, _localHeaderSize);
    final view = ByteData.sublistView(header);
    if (view.getUint32(0, Endian.little) != _localSig) {
      throw _corrupt('assinatura local inválida em "${entry.name}"');
    }
    final nameLen = view.getUint16(26, Endian.little);
    final extraLen = view.getUint16(28, Endian.little);
    final dataStart = offset + _localHeaderSize + nameLen + extraLen;
    if (dataStart > total || entry.compressedSize > total - dataStart) {
      throw _corrupt('dados de "${entry.name}" ultrapassam a fonte');
    }
    return _source.read(dataStart, entry.compressedSize);
  }

  Uint8List _storedBytes(ZipEntry entry, Uint8List bytes) {
    if (entry.compressedSize != entry.uncompressedSize) {
      throw _corrupt('tamanhos de "${entry.name}" divergem no método stored');
    }
    return bytes;
  }

  Uint8List _inflate(ZipEntry entry, Uint8List compressed) {
    final expected = entry.uncompressedSize;
    final out = _BoundedSink(expected, entry.name);
    final input = ZLibDecoder(raw: true).startChunkedConversion(out);
    const chunk = 64 * 1024;
    for (var i = 0; i < compressed.length; i += chunk) {
      final end = i + chunk < compressed.length ? i + chunk : compressed.length;
      input.addSlice(compressed, i, end, false);
    }
    input.close();
    final bytes = out.takeBytes();
    if (bytes.length != expected) {
      throw _corrupt(
        '"${entry.name}" descomprimiu para ${bytes.length} bytes; '
        'esperado $expected',
      );
    }
    return bytes;
  }

  /// Fecha a fonte de bytes subjacente. Chamadas repetidas são inofensivas.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _source.close();
  }
}

/// Coletor que recusa saída acima do tamanho declarado (zip bomb).
final class _BoundedSink implements Sink<List<int>> {
  _BoundedSink(this._max, this._name);

  final int _max;
  final String _name;
  final BytesBuilder _builder = BytesBuilder(copy: false);

  @override
  void add(List<int> data) {
    if (_builder.length + data.length > _max) {
      throw _corrupt('"$_name" descomprime além do tamanho declarado');
    }
    _builder.add(data);
  }

  @override
  void close() {}

  Uint8List takeBytes() => _builder.takeBytes();
}

CorruptArchiveException _corrupt(String detail) =>
    CorruptArchiveException('Zip inconsistente: $detail.');

/// Entradas na ordem do diretório central e o índice por nome, montados na
/// mesma passada.
///
/// Classe, não record: o `Future` de [_readDirectory] confere o tipo do
/// valor, e um record com campos genéricos (`List<ZipEntry>`, `Map<…>`) não
/// cabe no cache de testes de subtipo do AOT. Cada abertura ia ao runtime
/// (`Instance::RuntimeTypeIsSubtypeOf`): ~20 mil instruções por abertura, o
/// dobro do leitor inteiro de um EPUB pequeno.
final class _Directory {
  _Directory(this.entries, this.byName);

  final List<ZipEntry> entries;
  final Map<String, ZipEntry> byName;
}

Future<_Directory> _readDirectory(
  ByteSource source,
  ZipLimits limits,
  DiagnosticSink sink,
) async {
  final total = source.length;
  if (total < _eocdMin) {
    throw const NotAnEpubException('Arquivo pequeno demais para ser um zip.');
  }
  final tailLength = total < _eocdMin + _maxComment
      ? total
      : _eocdMin + _maxComment;
  final tailStart = total - tailLength;
  final tail = await source.read(tailStart, tailLength);
  final tailView = ByteData.sublistView(tail);

  var eocd = -1;
  for (var i = tail.length - _eocdMin; i >= 0; i--) {
    if (tailView.getUint32(i, Endian.little) == _eocdSig) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) {
    throw const NotAnEpubException('Diretório central do zip não encontrado.');
  }

  var count = tailView.getUint16(eocd + 10, Endian.little);
  var cdSize = tailView.getUint32(eocd + 12, Endian.little);
  var cdOffset = tailView.getUint32(eocd + 16, Endian.little);

  final eocdAbs = tailStart + eocd;
  if (eocdAbs >= 20) {
    final loc = ByteData.sublistView(await source.read(eocdAbs - 20, 20));
    if (loc.getUint32(0, Endian.little) == _locator64Sig) {
      final eocd64Offset = loc.getUint64(8, Endian.little);
      if (eocd64Offset < 0 || eocd64Offset > eocdAbs - 56) {
        throw _corrupt('EOCD64 fora dos limites');
      }
      final r = ByteData.sublistView(await source.read(eocd64Offset, 56));
      if (r.getUint32(0, Endian.little) != _eocd64Sig) {
        throw _corrupt('assinatura do EOCD64 inválida');
      }
      count = r.getUint64(32, Endian.little);
      cdSize = r.getUint64(40, Endian.little);
      cdOffset = r.getUint64(48, Endian.little);
    }
  }

  if (count < 0 || count > limits.maxEntries) {
    throw ArchiveLimitExceededException(
      'O zip declara $count entradas; o limite é ${limits.maxEntries}.',
    );
  }
  if (cdSize < 0 ||
      cdOffset < 0 ||
      cdOffset > eocdAbs ||
      cdSize > eocdAbs - cdOffset) {
    throw _corrupt('diretório central fora dos limites');
  }

  final cd = await source.read(cdOffset, cdSize);
  return _parseEntries(cd, count, sink, total);
}

/// Lê as [count] entradas do diretório central [cd].
///
/// Laço quente da abertura (uma volta por entrada; 2000 entradas no benchmark
/// `container/zip-central-dir-2000`). Sem chamadas pela tabela de despacho
/// por entrada além do inevitável (`hashCode` no índice): o nome sai direto
/// de [cd] (sem `sublistView`), um laço sobre os bytes ([_scanName]) detecta
/// `\`, não ASCII e caminho inseguro (sem `split`) e o índice por nome é
/// montado aqui, uma vez, no lugar de um
/// `Set` de vistos mais um mapa refeito no construtor. A versão anterior
/// fazia ~10 chamadas indiretas por entrada e, como o `crc32` no SP3, era
/// sensível ao layout do executável AOT: +8% em AMD EPYC 7763 só porque o
/// executável cresceu (benchmark/README.md, modo `ab`).
_Directory _parseEntries(
  Uint8List cd,
  int count,
  DiagnosticSink sink,
  int sourceLength,
) {
  final view = ByteData.sublistView(cd);
  final cdLength = cd.length;
  final entries = <ZipEntry>[];
  final byName = <String, ZipEntry>{};
  var pos = 0;

  for (var n = 0; n < count; n++) {
    if (pos + 46 > cdLength || view.getUint32(pos, Endian.little) != _cdSig) {
      throw _corrupt('entrada $n do diretório central inválida');
    }
    final flags = view.getUint16(pos + 8, Endian.little);
    final method = view.getUint16(pos + 10, Endian.little);
    final crc = view.getUint32(pos + 16, Endian.little);
    var compressed = view.getUint32(pos + 20, Endian.little);
    var uncompressed = view.getUint32(pos + 24, Endian.little);
    final nameLen = view.getUint16(pos + 28, Endian.little);
    final extraLen = view.getUint16(pos + 30, Endian.little);
    final commentLen = view.getUint16(pos + 32, Endian.little);
    var offset = view.getUint32(pos + 42, Endian.little);

    final nameStart = pos + 46;
    final extraStart = nameStart + nameLen;
    final next = extraStart + extraLen + commentLen;
    if (next > cdLength) throw _corrupt('entrada $n ultrapassa o diretório');

    if (uncompressed == 0xFFFFFFFF ||
        compressed == 0xFFFFFFFF ||
        offset == 0xFFFFFFFF) {
      (uncompressed, compressed, offset) = _zip64Extra(
        view,
        extraStart,
        extraStart + extraLen,
        n,
        uncompressed,
        compressed,
        offset,
      );
    }

    if (compressed < 0 || uncompressed < 0 || offset < 0) {
      throw _corrupt('tamanho ou offset negativo na entrada $n');
    }
    if (offset >= sourceLength) {
      throw _corrupt('offset do cabeçalho local fora da fonte na entrada $n');
    }

    pos = next;

    final scan = _scanName(cd, nameStart, extraStart);
    final name = _decodeName(cd, nameStart, extraStart, scan, flags, sink);
    if (scan & _nameUnsafe != 0) {
      sink.report(
        Diagnostic(
          severity: DiagnosticSeverity.warning,
          code: DiagnosticCodes.zipUnsafePath,
          message: 'Entrada com caminho inseguro ignorada.',
          location: name,
        ),
      );
      continue;
    }
    final entry = ZipEntry(
      name: name,
      method: method,
      compressedSize: compressed,
      uncompressedSize: uncompressed,
      crc32: crc,
      localHeaderOffset: offset,
      isEncrypted: flags & 0x1 != 0,
    );
    // Com nome repetido, `??=` devolve a entrada já indexada.
    if (!identical(byName[name] ??= entry, entry)) {
      sink.report(
        Diagnostic(
          severity: DiagnosticSeverity.warning,
          code: DiagnosticCodes.zipDuplicateEntry,
          message: 'Entrada duplicada ignorada; vale a primeira.',
          location: name,
        ),
      );
      continue;
    }
    entries.add(entry);
  }
  return _Directory(entries, byName);
}

/// Lê o extra ZIP64 (0x0001) em `[start, end)`: só traz os campos que
/// estavam saturados, nesta ordem: tamanho descomprimido, comprimido, offset.
///
/// Fora do laço de [_parseEntries] para que o fecho `take` não aloque um
/// contexto a cada entrada.
(int, int, int) _zip64Extra(
  ByteData view,
  int start,
  int end,
  int n,
  int uncompressed,
  int compressed,
  int offset,
) {
  var e = start;
  while (e + 4 <= end) {
    final id = view.getUint16(e, Endian.little);
    final size = view.getUint16(e + 2, Endian.little);
    final body = e + 4;
    if (body + size > end) break;
    if (id == 0x0001) {
      var p = body;
      int take() {
        if (p + 8 > body + size) throw _corrupt('extra ZIP64 truncado');
        final v = view.getUint64(p, Endian.little);
        p += 8;
        return v;
      }

      if (uncompressed == 0xFFFFFFFF) uncompressed = take();
      if (compressed == 0xFFFFFFFF) compressed = take();
      if (offset == 0xFFFFFFFF) offset = take();
      return (uncompressed, compressed, offset);
    }
    e = body + size;
  }
  throw _corrupt('extra ZIP64 ausente na entrada $n');
}

const Utf8Decoder _utf8Strict = Utf8Decoder();
const Utf8Decoder _utf8Lenient = Utf8Decoder(allowMalformed: true);

/// Bits de [_scanName].
const int _nameNonAscii = 1;
const int _nameBackslash = 2;
const int _nameUnsafe = 4;

/// Uma passada sobre os bytes do nome em `cd[start, end)`: diz se há byte
/// não ASCII, se há `\` e se o caminho é inseguro (absoluto, com letra de
/// unidade ou com um segmento `..`, com `/` ou `\` como separador).
///
/// Nos bytes, não na `String`: `/`, `\`, `.` e `:` são os mesmos bytes em
/// UTF-8 e em CP437 e nunca aparecem dentro de uma sequência multibyte do
/// UTF-8 (nem são engolidos pela troca de UTF-8 malformado por U+FFFD), então
/// o resultado é o mesmo que olhar o nome decodificado. Um laço sobre
/// `Uint8List` é estável entre CPUs; o laço anterior, com `codeUnitAt` na
/// `String` (que pode ser de 1 ou 2 bytes por unidade), ficava até 67% mais
/// lento em Intel Xeon 6973P só porque o executável mudou.
int _scanName(Uint8List cd, int start, int end) {
  var result = 0;
  var segment = 0;
  var dots = 0;
  for (var i = start; i < end; i++) {
    final b = cd[i];
    if (b == 0x2F || b == 0x5C) {
      if (b == 0x5C) result |= _nameBackslash;
      if (segment == 2 && dots == 2) result |= _nameUnsafe;
      segment = 0;
      dots = 0;
    } else {
      if (b >= 0x80) {
        result |= _nameNonAscii;
      } else if (b == 0x2E) {
        dots++;
      }
      segment++;
    }
  }
  if (segment == 2 && dots == 2) result |= _nameUnsafe;
  if (end > start) {
    final first = cd[start];
    if (first == 0x2F || first == 0x5C) result |= _nameUnsafe;
    if (end - start >= 2 && cd[start + 1] == 0x3A) {
      final c = first | 0x20;
      if (c >= 0x61 && c <= 0x7A) result |= _nameUnsafe;
    }
  }
  return result;
}

/// Nome em `cd[start, end)`, com `\` trocada por `/`; [scan] vem de
/// [_scanName].
String _decodeName(
  Uint8List cd,
  int start,
  int end,
  int scan,
  int flags,
  DiagnosticSink sink,
) {
  String decoded;
  if (scan & _nameNonAscii == 0 || flags & 0x800 != 0) {
    decoded = _utf8Lenient.convert(cd, start, end);
  } else {
    try {
      decoded = _utf8Strict.convert(cd, start, end);
    } on FormatException {
      decoded = decodeCp437(Uint8List.sublistView(cd, start, end));
      sink.report(
        Diagnostic(
          severity: DiagnosticSeverity.info,
          code: DiagnosticCodes.zipNameNotUtf8,
          message: 'Nome sem flag UTF-8 e inválido em UTF-8; lido como CP437.',
          location: decoded,
        ),
      );
    }
  }
  return scan & _nameBackslash != 0 ? decoded.replaceAll(r'\', '/') : decoded;
}
