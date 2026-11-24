import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/core/diagnostics/diagnostic_codes.dart';
import 'package:galley/src/core/diagnostics/diagnostic_sink.dart';
import 'package:galley/src/core/errors/galley_exception.dart';
import 'package:galley/src/features/container/data/zip/byte_source.dart';
import 'package:galley/src/features/container/data/zip/zip_archive.dart';
import 'package:galley/src/features/container/data/zip/zip_limits.dart';

import '../../../../support/zip_builder.dart';

Future<ZipArchive> _open(
  Uint8List bytes, {
  ZipLimits limits = const ZipLimits(),
  DiagnosticSink sink = const NullDiagnosticSink(),
}) => ZipArchive.open(MemoryByteSource(bytes), limits: limits, sink: sink);

ZipBuilder _three() => ZipBuilder()
  ..addFile('a', [1])
  ..addFile('b/c.txt', [2, 3])
  ..addFile('d', [4]);

void main() {
  test('lista entradas na ordem e por nome', () async {
    final zip = await _open(_three().build());
    expect(zip.entries.map((e) => e.name), ['a', 'b/c.txt', 'd']);
    final e = zip.entry('b/c.txt')!;
    expect(e.uncompressedSize, 2);
    expect(e.method, 8);
    expect(e.isDirectory, isFalse);
    expect(e.isEncrypted, isFalse);
    expect(zip.entry('x'), isNull);
  });

  test('lê ZIP64', () async {
    final zip = await _open(_three().build(zip64: true));
    expect(zip.entries.map((e) => e.name), ['a', 'b/c.txt', 'd']);
    expect(zip.entry('d')!.localHeaderOffset, greaterThan(0));
    expect(zip.entry('b/c.txt')!.uncompressedSize, 2);
    final plain = await _open(_three().build());
    for (final e in plain.entries) {
      final z = zip.entry(e.name)!;
      expect(z.compressedSize, e.compressedSize);
      expect(z.uncompressedSize, e.uncompressedSize);
      expect(z.localHeaderOffset, e.localHeaderOffset);
      expect(z.crc32, e.crc32);
    }
  });

  test('EOCD após comentário longo', () async {
    final zip = await _open(_three().build(comment: 'x' * 60000));
    expect(zip.entries, hasLength(3));
  });

  test('normaliza barra invertida', () async {
    final b = ZipBuilder()..addFile(r'OEBPS\content.opf', [1]);
    final zip = await _open(b.build());
    expect(zip.entry('OEBPS/content.opf'), isNotNull);
  });

  test('nome sem flag UTF-8 em CP437', () async {
    final sink = CollectingDiagnosticSink();
    final b = ZipBuilder()..addRawName([0x82], [1]);
    final zip = await _open(b.build(), sink: sink);
    expect(zip.entry('é'), isNotNull);
    expect(sink.diagnostics.single.code, DiagnosticCodes.zipNameNotUtf8);
  });

  test('ignora caminho inseguro', () async {
    final sink = CollectingDiagnosticSink();
    final b = ZipBuilder()
      ..addFile('../evil', [1])
      ..addFile('/abs', [1])
      ..addFile('ok', [1]);
    final zip = await _open(b.build(), sink: sink);
    expect(zip.entries.map((e) => e.name), ['ok']);
    expect(
      sink.diagnostics.where((d) => d.code == DiagnosticCodes.zipUnsafePath),
      hasLength(2),
    );
  });

  test('duplicata mantém a primeira', () async {
    final sink = CollectingDiagnosticSink();
    final b = ZipBuilder()
      ..addFile('a', [1])
      ..addFile('a', [1, 2]);
    final zip = await _open(b.build(), sink: sink);
    expect(zip.entries, hasLength(1));
    expect(zip.entry('a')!.uncompressedSize, 1);
    expect(sink.diagnostics.single.code, DiagnosticCodes.zipDuplicateEntry);
  });

  test('marca entrada cifrada', () async {
    final b = ZipBuilder()..addFile('s', [1], encrypted: true);
    expect((await _open(b.build())).entry('s')!.isEncrypted, isTrue);
  });

  test('busca sem diferenciar caixa', () async {
    final b = ZipBuilder()..addFile('Images/cover.jpg', [1]);
    final zip = await _open(b.build());
    expect(zip.entryIgnoringCase('images/COVER.jpg')!.name, 'Images/cover.jpg');
    expect(zip.entryIgnoringCase('nada'), isNull);
  });

  test('bytes que não são zip', () async {
    expect(
      _open(Uint8List.fromList(List.filled(100, 7))),
      throwsA(isA<NotAnEpubException>()),
    );
    expect(_open(Uint8List(5)), throwsA(isA<NotAnEpubException>()));
  });

  test('diretório central fora dos limites é corrupto', () async {
    final bytes = _three().build();
    // Corrompe o offset do diretório central (EOCD sem comentário: -6..-2).
    ByteData.sublistView(bytes)
        .setUint32(bytes.length - 6, 0x7FFFFFFF, Endian.little);
    expect(_open(bytes), throwsA(isA<CorruptArchiveException>()));
  });

  test('limite de entradas', () async {
    expect(
      _open(_three().build(), limits: const ZipLimits(maxEntries: 2)),
      throwsA(isA<ArchiveLimitExceededException>()),
    );
  });

  group('valores gigantes (uint64) viram CorruptArchiveException', () {
    const huge = 0x7FFFFFFFFFFFFFF0;

    // Offsets a partir do fim: EOCD (22), locator (20), EOCD64 (56).
    ByteData patch(Uint8List b) => ByteData.sublistView(b);

    test('offset do EOCD64', () {
      final b = _three().build(zip64: true);
      patch(b).setUint64(b.length - 22 - 20 + 8, huge, Endian.little);
      expect(_open(b), throwsA(isA<CorruptArchiveException>()));
    });

    test('offset + tamanho do diretório central somam com overflow', () {
      final b = _three().build(zip64: true);
      final e64 = b.length - 22 - 20 - 56;
      patch(b)
        ..setUint64(e64 + 40, 1 << 62, Endian.little)
        ..setUint64(e64 + 48, 1 << 62, Endian.little);
      expect(_open(b), throwsA(isA<CorruptArchiveException>()));
    });

    test('tamanho negativo (>= 2^63) no extra ZIP64', () {
      final b = _three().build(zip64: true);
      final e64 = b.length - 22 - 20 - 56;
      final cd = ByteData.sublistView(b).getUint64(e64 + 48, Endian.little);
      // Extra começa após o cabeçalho (46) e o nome ('a' = 1 byte) + 4.
      patch(b).setUint64(cd + 46 + 1 + 4, -1, Endian.little);
      expect(_open(b), throwsA(isA<CorruptArchiveException>()));
    });

    test('offset do cabeçalho local além da fonte', () {
      final b = _three().build(zip64: true);
      final e64 = b.length - 22 - 20 - 56;
      final cd = ByteData.sublistView(b).getUint64(e64 + 48, Endian.little);
      patch(b).setUint64(cd + 46 + 1 + 4 + 16, huge, Endian.little);
      expect(_open(b), throwsA(isA<CorruptArchiveException>()));
    });
  });
}
