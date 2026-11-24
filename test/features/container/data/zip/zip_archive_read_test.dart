import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/core/diagnostics/diagnostic_codes.dart';
import 'package:galley/src/core/diagnostics/diagnostic_sink.dart';
import 'package:galley/src/core/errors/galley_exception.dart';
import 'package:galley/src/features/container/data/zip/byte_source.dart';
import 'package:galley/src/features/container/data/zip/zip_archive.dart';
import 'package:galley/src/features/container/data/zip/zip_limits.dart';

import '../../../../support/zip_builder.dart';

/// Fonte que conta leituras e pode falhar sob demanda.
class _SpySource implements ByteSource {
  _SpySource(this.inner, {this.failWith});

  final ByteSource inner;
  final Object? failWith;
  int reads = 0;
  bool failing = false;

  @override
  int get length => inner.length;

  @override
  Future<Uint8List> read(int offset, int length) {
    reads++;
    if (failing && failWith != null) throw failWith!;
    return inner.read(offset, length);
  }

  @override
  Future<void> close() => inner.close();
}

/// Posição (no zip) do cabeçalho do diretório central da entrada [index].
int _cdPos(Uint8List zip, int index) {
  final view = ByteData.sublistView(zip);
  var found = -1;
  for (var i = 0; i + 4 <= zip.length; i++) {
    if (view.getUint32(i, Endian.little) == 0x02014b50) {
      found++;
      if (found == index) return i;
    }
  }
  throw StateError('entrada $index não encontrada');
}

void _patch32(Uint8List zip, int index, int fieldOffset, int value) {
  ByteData.sublistView(zip)
      .setUint32(_cdPos(zip, index) + fieldOffset, value, Endian.little);
}

void _patch16(Uint8List zip, int index, int fieldOffset, int value) {
  ByteData.sublistView(zip)
      .setUint16(_cdPos(zip, index) + fieldOffset, value, Endian.little);
}

Future<ZipArchive> _open(
  ByteSource source, {
  ZipLimits limits = const ZipLimits(),
  DiagnosticSink sink = const NullDiagnosticSink(),
}) => ZipArchive.open(source, limits: limits, sink: sink);

final _text = utf8.encode('olá mundo ' * 50);

void main() {
  group('conteúdo', () {
    for (final deflate in [false, true]) {
      test('lê entrada ${deflate ? 'deflate' : 'stored'}', () async {
        final zip = await _open(
          MemoryByteSource(
            (ZipBuilder()
                  ..addFile('x', [9])
                  ..addFile('a.txt', _text, deflate: deflate))
                .build(),
          ),
        );
        expect(await zip.read(zip.entry('a.txt')!), _text);
        expect(await zip.read(zip.entry('x')!), [9]);
      });
    }

    test('lê entrada com data descriptor', () async {
      final zip = await _open(
        MemoryByteSource(
          (ZipBuilder()..addFile('a', _text, dataDescriptor: true)).build(),
        ),
      );
      expect(await zip.read(zip.entry('a')!), _text);
    });

    test('lê entrada em ZIP64', () async {
      final zip = await _open(
        MemoryByteSource(
          (ZipBuilder()
                ..addFile('a', _text)
                ..addFile('b', _text, deflate: false))
              .build(zip64: true),
        ),
      );
      expect(await zip.read(zip.entry('a')!), _text);
      expect(await zip.read(zip.entry('b')!), _text);
    });

    test('lê conteúdo vazio', () async {
      final zip = await _open(
        MemoryByteSource(
          (ZipBuilder()
                ..addFile('e1', const [])
                ..addFile('e2', const [], deflate: false))
              .build(),
        ),
      );
      expect(await zip.read(zip.entry('e1')!), isEmpty);
      expect(await zip.read(zip.entry('e2')!), isEmpty);
    });
  });

  group('integridade', () {
    test('CRC divergente devolve os bytes e reporta zip.crcMismatch', () async {
      final bytes = (ZipBuilder()..addFile('a', _text)).build();
      _patch32(bytes, 0, 16, 0xDEADBEEF);
      final sink = CollectingDiagnosticSink();
      final zip = await _open(MemoryByteSource(bytes), sink: sink);
      expect(await zip.read(zip.entry('a')!), _text);
      expect(sink.diagnostics, hasLength(1));
      expect(sink.diagnostics.single.code, DiagnosticCodes.zipCrcMismatch);
      expect(sink.diagnostics.single.code, 'zip.crcMismatch');
      expect(sink.diagnostics.single.location, 'a');
    });

    test('CRC correto não gera diagnóstico', () async {
      final sink = CollectingDiagnosticSink();
      final zip = await _open(
        MemoryByteSource((ZipBuilder()..addFile('a', _text)).build()),
        sink: sink,
      );
      await zip.read(zip.entry('a')!);
      expect(sink.diagnostics, isEmpty);
    });

    test('deflate corrompido lança CorruptArchiveException', () async {
      final bytes = (ZipBuilder()..addFile('a', _text)).build();
      final zip = await _open(MemoryByteSource(bytes));
      final e = zip.entry('a')!;
      final start = e.localHeaderOffset + 30 + 1;
      for (var i = 0; i < e.compressedSize; i++) {
        bytes[start + i] = 0xFF;
      }
      await expectLater(zip.read(e), throwsA(isA<CorruptArchiveException>()));
    });

    test('tamanho descomprimido divergente é corrupção', () async {
      final bytes = (ZipBuilder()..addFile('a', _text)).build();
      _patch32(bytes, 0, 24, _text.length + 1);
      final zip = await _open(MemoryByteSource(bytes));
      await expectLater(
        zip.read(zip.entry('a')!),
        throwsA(isA<CorruptArchiveException>()),
      );
    });

    test('método desconhecido lança CorruptArchiveException', () async {
      final bytes = (ZipBuilder()..addFile('a', _text)).build();
      _patch16(bytes, 0, 10, 12);
      final zip = await _open(MemoryByteSource(bytes));
      await expectLater(
        zip.read(zip.entry('a')!),
        throwsA(isA<CorruptArchiveException>()),
      );
    });

    test('assinatura de cabeçalho local inválida é corrupção', () async {
      final bytes = (ZipBuilder()..addFile('a', _text)).build();
      bytes[0] = 0;
      final zip = await _open(MemoryByteSource(bytes));
      await expectLater(
        zip.read(zip.entry('a')!),
        throwsA(isA<CorruptArchiveException>()),
      );
    });

    test('dados além do fim da fonte são corrupção', () async {
      final bytes = (ZipBuilder()..addFile('a', _text, deflate: false)).build();
      _patch32(bytes, 0, 20, 100000);
      _patch32(bytes, 0, 24, 100000);
      final zip = await _open(MemoryByteSource(bytes));
      await expectLater(
        zip.read(zip.entry('a')!),
        throwsA(isA<CorruptArchiveException>()),
      );
    });

    test('nome/extra do cabeçalho local além da fonte é corrupção', () async {
      final bytes = (ZipBuilder()..addFile('a', _text)).build();
      final view = ByteData.sublistView(bytes);
      view.setUint16(28, 0xFFFF, Endian.little);
      view.setUint16(26, 0xFFFF, Endian.little);
      final zip = await _open(MemoryByteSource(bytes));
      await expectLater(
        zip.read(zip.entry('a')!),
        throwsA(isA<CorruptArchiveException>()),
      );
    });

    test('falha de E/S da fonte vira CorruptArchiveException', () async {
      final spy = _SpySource(
        MemoryByteSource((ZipBuilder()..addFile('a', _text)).build()),
        failWith: const FormatException('disco'),
      );
      final zip = await _open(spy);
      spy.failing = true;
      await expectLater(
        zip.read(zip.entry('a')!),
        throwsA(isA<CorruptArchiveException>()),
      );
    });

    test('RangeError da fonte vira CorruptArchiveException', () async {
      final spy = _SpySource(
        MemoryByteSource((ZipBuilder()..addFile('a', _text)).build()),
        failWith: RangeError('fora'),
      );
      final zip = await _open(spy);
      spy.failing = true;
      await expectLater(
        zip.read(zip.entry('a')!),
        throwsA(isA<CorruptArchiveException>()),
      );
    });
  });

  group('segurança', () {
    test('entrada cifrada lança DrmProtectedException', () async {
      final zip = await _open(
        MemoryByteSource(
          (ZipBuilder()..addFile('a', _text, encrypted: true)).build(),
        ),
      );
      await expectLater(
        zip.read(zip.entry('a')!),
        throwsA(
          isA<DrmProtectedException>().having(
            (e) => e.algorithms,
            'algorithms',
            ['zip-encryption'],
          ),
        ),
      );
    });

    test('razão de compressão acima do limite é recusada', () async {
      final bytes = (ZipBuilder()..addFile('a', Uint8List(1024))).build();
      _patch32(bytes, 0, 20, 1024);
      _patch32(bytes, 0, 24, 2 * 1024 * 1024);
      final spy = _SpySource(MemoryByteSource(bytes));
      final zip = await _open(
        spy,
        limits: const ZipLimits(maxCompressionRatio: 100),
      );
      final before = spy.reads;
      await expectLater(
        zip.read(zip.entry('a')!),
        throwsA(isA<ArchiveLimitExceededException>()),
      );
      expect(spy.reads, before, reason: 'limite checado antes de ler dados');
    });

    test('tamanho acima de maxEntrySize é recusado', () async {
      final bytes = (ZipBuilder()..addFile('a', _text)).build();
      final spy = _SpySource(MemoryByteSource(bytes));
      final zip = await _open(spy, limits: const ZipLimits(maxEntrySize: 10));
      final before = spy.reads;
      await expectLater(
        zip.read(zip.entry('a')!),
        throwsA(isA<ArchiveLimitExceededException>()),
      );
      expect(spy.reads, before);
    });

    test('razão alta abaixo do limiar de verificação é aceita', () async {
      final data = Uint8List(100 * 1024);
      final zip = await _open(
        MemoryByteSource((ZipBuilder()..addFile('a', data)).build()),
        limits: const ZipLimits(maxCompressionRatio: 2),
      );
      expect(await zip.read(zip.entry('a')!), data);
    });
  });

  group('ciclo de vida', () {
    test('read após close lança BookClosedException', () async {
      final zip = await _open(
        MemoryByteSource((ZipBuilder()..addFile('a', _text)).build()),
      );
      final e = zip.entry('a')!;
      await zip.close();
      await expectLater(zip.read(e), throwsA(isA<BookClosedException>()));
    });

    test('close é idempotente e fecha a fonte uma única vez', () async {
      var closes = 0;
      final source = _CountingClose(
        MemoryByteSource((ZipBuilder()..addFile('a', _text)).build()),
        () => closes++,
      );
      final zip = await _open(source);
      await zip.close();
      await zip.close();
      expect(closes, 1);
    });
  });
}

class _CountingClose implements ByteSource {
  _CountingClose(this.inner, this.onClose);

  final ByteSource inner;
  final void Function() onClose;

  @override
  int get length => inner.length;

  @override
  Future<Uint8List> read(int offset, int length) => inner.read(offset, length);

  @override
  Future<void> close() async {
    onClose();
    await inner.close();
  }
}
