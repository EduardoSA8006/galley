import 'dart:convert';
import 'dart:typed_data';

import 'package:galley/src/core/diagnostics/diagnostic.dart';
import 'package:galley/src/core/diagnostics/diagnostic_codes.dart';
import 'package:galley/src/core/diagnostics/diagnostic_sink.dart';
import 'package:galley/src/core/errors/galley_exception.dart';
import 'package:galley/src/features/container/data/zip/byte_source.dart';
import 'package:galley/src/features/container/data/zip/cp437.dart';
import 'package:galley/src/features/container/data/zip/zip_entry.dart';
import 'package:galley/src/features/container/data/zip/zip_limits.dart';

const int _eocdSig = 0x06054b50;
const int _locator64Sig = 0x07064b50;
const int _eocd64Sig = 0x06064b50;
const int _cdSig = 0x02014b50;
const int _eocdMin = 22;
const int _maxComment = 65535;

/// Leitor preguiçoso de zip: lê só o diretório central na abertura.
final class ZipArchive {
  ZipArchive._(this._source, this.limits, List<ZipEntry> entries)
    : entries = List.unmodifiable(entries),
      _byName = {for (final e in entries.reversed) e.name: e};

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
    final entries = await _readDirectory(source, limits, sink);
    return ZipArchive._(source, limits, entries);
  }

  final ByteSource _source;

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

  // A leitura de conteúdo (`read(ZipEntry)`) será acrescentada aqui.

  /// Fecha a fonte de bytes subjacente.
  Future<void> close() => _source.close();
}

CorruptArchiveException _corrupt(String detail) =>
    CorruptArchiveException('Zip inconsistente: $detail.');

Future<List<ZipEntry>> _readDirectory(
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

List<ZipEntry> _parseEntries(
  Uint8List cd,
  int count,
  DiagnosticSink sink,
  int sourceLength,
) {
  final view = ByteData.sublistView(cd);
  final entries = <ZipEntry>[];
  final seen = <String>{};
  var pos = 0;

  for (var n = 0; n < count; n++) {
    if (pos + 46 > cd.length || view.getUint32(pos, Endian.little) != _cdSig) {
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
    if (next > cd.length) throw _corrupt('entrada $n ultrapassa o diretório');

    // Extra ZIP64 (0x0001): só traz os campos que estavam saturados, nesta
    // ordem: tamanho descomprimido, comprimido, offset.
    if (uncompressed == 0xFFFFFFFF ||
        compressed == 0xFFFFFFFF ||
        offset == 0xFFFFFFFF) {
      var e = extraStart;
      final extraEnd = extraStart + extraLen;
      var found = false;
      while (e + 4 <= extraEnd) {
        final id = view.getUint16(e, Endian.little);
        final size = view.getUint16(e + 2, Endian.little);
        final body = e + 4;
        if (body + size > extraEnd) break;
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
          found = true;
          break;
        }
        e = body + size;
      }
      if (!found) throw _corrupt('extra ZIP64 ausente na entrada $n');
    }

    if (compressed < 0 || uncompressed < 0 || offset < 0) {
      throw _corrupt('tamanho ou offset negativo na entrada $n');
    }
    if (offset >= sourceLength) {
      throw _corrupt('offset do cabeçalho local fora da fonte na entrada $n');
    }

    final rawName = Uint8List.sublistView(cd, nameStart, extraStart);
    pos = next;

    final name = _decodeName(rawName, flags, sink);
    if (_isUnsafe(name)) {
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
    if (!seen.add(name)) {
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
    entries.add(
      ZipEntry(
        name: name,
        method: method,
        compressedSize: compressed,
        uncompressedSize: uncompressed,
        crc32: crc,
        localHeaderOffset: offset,
        isEncrypted: flags & 0x1 != 0,
      ),
    );
  }
  return entries;
}

String _decodeName(Uint8List raw, int flags, DiagnosticSink sink) {
  String decoded;
  if (flags & 0x800 != 0) {
    decoded = utf8.decode(raw, allowMalformed: true);
  } else {
    try {
      decoded = utf8.decode(raw);
    } on FormatException {
      decoded = decodeCp437(raw);
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
  return decoded.replaceAll(r'\', '/');
}

bool _isUnsafe(String name) {
  if (name.startsWith('/')) return true;
  if (name.length >= 2 && name.codeUnitAt(1) == 0x3A) {
    final c = name.codeUnitAt(0) | 0x20;
    if (c >= 0x61 && c <= 0x7A) return true;
  }
  return name.split('/').contains('..');
}
