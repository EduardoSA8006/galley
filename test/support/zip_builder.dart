import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:galley/src/features/container/data/zip/crc32.dart';

class _Entry {
  _Entry({
    required this.name,
    required this.raw,
    required this.stored,
    required this.method,
    required this.flags,
    required this.dataDescriptor,
  });

  final List<int> name;
  final List<int> raw;
  final List<int> stored;
  final int method;
  final int flags;
  final bool dataDescriptor;
  int offset = 0;
}

/// Monta zips válidos em memória para os testes (apenas uso em testes).
class ZipBuilder {
  final List<_Entry> _entries = [];

  /// Adiciona um arquivo. [encrypted] só liga o bit 0 das flags (sem cifra
  /// real); [dataDescriptor] liga o bit 3 e move crc/tamanhos para depois dos
  /// dados.
  void addFile(
    String name,
    List<int> data, {
    bool deflate = true,
    bool utf8Flag = true,
    bool encrypted = false,
    bool dataDescriptor = false,
  }) {
    _add(
      utf8.encode(name),
      data,
      deflate: deflate,
      utf8Flag: utf8Flag,
      encrypted: encrypted,
      dataDescriptor: dataDescriptor,
    );
  }

  /// Adiciona um arquivo com nome em bytes arbitrários (ex.: CP437).
  void addRawName(
    List<int> nameBytes,
    List<int> data, {
    bool utf8Flag = false,
  }) {
    _add(
      nameBytes,
      data,
      deflate: false,
      utf8Flag: utf8Flag,
      encrypted: false,
      dataDescriptor: false,
    );
  }

  void _add(
    List<int> name,
    List<int> data, {
    required bool deflate,
    required bool utf8Flag,
    required bool encrypted,
    required bool dataDescriptor,
  }) {
    final stored = deflate ? ZLibEncoder(raw: true).convert(data) : data;
    _entries.add(
      _Entry(
        name: name,
        raw: data,
        stored: stored,
        method: deflate ? 8 : 0,
        flags:
            (encrypted ? 0x1 : 0) |
            (dataDescriptor ? 0x8 : 0) |
            (utf8Flag ? 0x800 : 0),
        dataDescriptor: dataDescriptor,
      ),
    );
  }

  /// Serializa o zip. Com [zip64], escreve o extra `0x0001` no diretório
  /// central e o EOCD64 com seu locator.
  Uint8List build({bool zip64 = false, String comment = ''}) {
    final out = BytesBuilder(copy: false);
    final version = zip64 ? 45 : 20;

    for (final e in _entries) {
      e.offset = out.length;
      final crc = crc32(e.raw);
      final w = _Writer()
        ..u32(0x04034b50)
        ..u16(version)
        ..u16(e.flags)
        ..u16(e.method)
        ..u16(0) // hora
        ..u16(0x21) // data 1980-01-01
        ..u32(e.dataDescriptor ? 0 : crc)
        ..u32(e.dataDescriptor ? 0 : e.stored.length)
        ..u32(e.dataDescriptor ? 0 : e.raw.length)
        ..u16(e.name.length)
        ..u16(0)
        ..bytes(e.name)
        ..bytes(e.stored);
      if (e.dataDescriptor) {
        w
          ..u32(0x08074b50)
          ..u32(crc)
          ..u32(e.stored.length)
          ..u32(e.raw.length);
      }
      out.add(w.take());
    }

    final cdOffset = out.length;
    for (final e in _entries) {
      final crc = crc32(e.raw);
      final extra = _Writer();
      if (zip64) {
        extra
          ..u16(0x0001)
          ..u16(24)
          ..u64(e.raw.length)
          ..u64(e.stored.length)
          ..u64(e.offset);
      }
      final extraBytes = extra.take();
      final w = _Writer()
        ..u32(0x02014b50)
        ..u16(version)
        ..u16(version)
        ..u16(e.flags)
        ..u16(e.method)
        ..u16(0)
        ..u16(0x21)
        ..u32(crc)
        ..u32(zip64 ? 0xFFFFFFFF : e.stored.length)
        ..u32(zip64 ? 0xFFFFFFFF : e.raw.length)
        ..u16(e.name.length)
        ..u16(extraBytes.length)
        ..u16(0) // comentário
        ..u16(0) // disco
        ..u16(0) // atributos internos
        ..u32(0) // atributos externos
        ..u32(zip64 ? 0xFFFFFFFF : e.offset)
        ..bytes(e.name)
        ..bytes(extraBytes);
      out.add(w.take());
    }
    final cdSize = out.length - cdOffset;

    if (zip64) {
      final eocd64Offset = out.length;
      out.add(
        (_Writer()
              ..u32(0x06064b50)
              ..u64(44)
              ..u16(45)
              ..u16(45)
              ..u32(0)
              ..u32(0)
              ..u64(_entries.length)
              ..u64(_entries.length)
              ..u64(cdSize)
              ..u64(cdOffset))
            .take(),
      );
      out.add(
        (_Writer()
              ..u32(0x07064b50)
              ..u32(0)
              ..u64(eocd64Offset)
              ..u32(1))
            .take(),
      );
    }

    final commentBytes = utf8.encode(comment);
    out.add(
      (_Writer()
            ..u32(0x06054b50)
            ..u16(0)
            ..u16(0)
            ..u16(zip64 ? 0xFFFF : _entries.length)
            ..u16(zip64 ? 0xFFFF : _entries.length)
            ..u32(zip64 ? 0xFFFFFFFF : cdSize)
            ..u32(zip64 ? 0xFFFFFFFF : cdOffset)
            ..u16(commentBytes.length)
            ..bytes(commentBytes))
          .take(),
    );
    return out.takeBytes();
  }
}

class _Writer {
  final BytesBuilder _b = BytesBuilder(copy: false);

  void u16(int v) => _b.add([v & 0xFF, (v >> 8) & 0xFF]);

  void u32(int v) =>
      _b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);

  void u64(int v) {
    u32(v & 0xFFFFFFFF);
    u32((v >> 32) & 0xFFFFFFFF);
  }

  void bytes(List<int> v) => _b.add(v);

  Uint8List take() => _b.takeBytes();
}
