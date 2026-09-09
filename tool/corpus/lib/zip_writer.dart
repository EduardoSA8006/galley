import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'hashes.dart';

/// Escritor de ZIP mínimo: stored (0) e deflate (8), ZIP64 opcional.
///
/// Só o que o corpus precisa. Sem streaming, sem criptografia, sem comentários.
class ZipWriter {
  ZipWriter({this.forceZip64 = false});

  /// Grava EOCD64 + locator e marca os tamanhos e offsets com 0xFFFFFFFF,
  /// como um arquivo acima de 4 GB faria, mesmo com conteúdo pequeno.
  final bool forceZip64;

  final List<_Entry> _entries = [];

  void add(
    String name,
    List<int> data, {
    bool compress = true,
    int? crcOverride,
  }) {
    final payload = compress
        ? Uint8List.fromList(ZLibCodec(raw: true, level: 6).encode(data))
        : Uint8List.fromList(data);
    _entries.add(
      _Entry(
        name: utf8.encode(name),
        payload: payload,
        size: data.length,
        crc: crcOverride ?? crc32(data),
        method: compress ? 8 : 0,
      ),
    );
  }

  Uint8List build() {
    final out = _Buf();
    final offsets = <int>[];
    for (final e in _entries) {
      offsets.add(out.length);
      _localHeader(out, e);
      out.bytes(e.payload);
    }
    final cdOffset = out.length;
    for (var i = 0; i < _entries.length; i++) {
      _centralHeader(out, _entries[i], offsets[i]);
    }
    final cdSize = out.length - cdOffset;

    if (forceZip64) {
      final eocd64Offset = out.length;
      out
        ..u32(0x06064b50)
        ..u64(44) // tamanho do registro após este campo
        ..u16(45)
        ..u16(45)
        ..u32(0)
        ..u32(0)
        ..u64(_entries.length)
        ..u64(_entries.length)
        ..u64(cdSize)
        ..u64(cdOffset)
        // locator
        ..u32(0x07064b50)
        ..u32(0)
        ..u64(eocd64Offset)
        ..u32(1);
      _eocd(out, 0xFFFF, 0xFFFFFFFF, 0xFFFFFFFF);
    } else {
      _eocd(out, _entries.length, cdSize, cdOffset);
    }
    return out.toBytes();
  }

  static const _dosDate = ((2026 - 1980) << 9) | (1 << 5) | 1; // 2026-01-01
  static const _dosTime = 0;

  void _localHeader(_Buf out, _Entry e) {
    final zip64 = forceZip64;
    out
      ..u32(0x04034b50)
      ..u16(zip64 ? 45 : 20)
      ..u16(0x0800) // nomes em UTF-8
      ..u16(e.method)
      ..u16(_dosTime)
      ..u16(_dosDate)
      ..u32(e.crc)
      ..u32(zip64 ? 0xFFFFFFFF : e.payload.length)
      ..u32(zip64 ? 0xFFFFFFFF : e.size)
      ..u16(e.name.length)
      ..u16(zip64 ? 20 : 0)
      ..bytes(e.name);
    if (zip64) {
      out
        ..u16(0x0001)
        ..u16(16)
        ..u64(e.size)
        ..u64(e.payload.length);
    }
  }

  void _centralHeader(_Buf out, _Entry e, int localOffset) {
    final zip64 = forceZip64;
    out
      ..u32(0x02014b50)
      ..u16(zip64 ? 45 : 20)
      ..u16(zip64 ? 45 : 20)
      ..u16(0x0800)
      ..u16(e.method)
      ..u16(_dosTime)
      ..u16(_dosDate)
      ..u32(e.crc)
      ..u32(zip64 ? 0xFFFFFFFF : e.payload.length)
      ..u32(zip64 ? 0xFFFFFFFF : e.size)
      ..u16(e.name.length)
      ..u16(zip64 ? 28 : 0)
      ..u16(0)
      ..u16(0)
      ..u16(0)
      ..u32(0)
      ..u32(zip64 ? 0xFFFFFFFF : localOffset)
      ..bytes(e.name);
    if (zip64) {
      out
        ..u16(0x0001)
        ..u16(24)
        ..u64(e.size)
        ..u64(e.payload.length)
        ..u64(localOffset);
    }
  }

  void _eocd(_Buf out, int count, int cdSize, int cdOffset) {
    out
      ..u32(0x06054b50)
      ..u16(0)
      ..u16(0)
      ..u16(count)
      ..u16(count)
      ..u32(cdSize)
      ..u32(cdOffset)
      ..u16(0);
  }
}

class _Entry {
  _Entry({
    required this.name,
    required this.payload,
    required this.size,
    required this.crc,
    required this.method,
  });
  final List<int> name;
  final Uint8List payload;
  final int size;
  final int crc;
  final int method;
}

class _Buf {
  final BytesBuilder _b = BytesBuilder(copy: false);
  final ByteData _scratch = ByteData(8);

  int get length => _b.length;

  void u16(int v) {
    _scratch.setUint16(0, v, Endian.little);
    _b.add(_scratch.buffer.asUint8List(0, 2).toList());
  }

  void u32(int v) {
    _scratch.setUint32(0, v, Endian.little);
    _b.add(_scratch.buffer.asUint8List(0, 4).toList());
  }

  void u64(int v) {
    _scratch.setUint64(0, v, Endian.little);
    _b.add(_scratch.buffer.asUint8List(0, 8).toList());
  }

  void bytes(List<int> v) => _b.add(v);

  Uint8List toBytes() => _b.toBytes();
}
