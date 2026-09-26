// O contêiner sobre os 65 EPUBs do corpus (spec do contêiner §9.1).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/container/zip/central_directory.dart';
import 'package:galley/src/container/zip/zip_container.dart';
import 'package:galley/src/diagnostics/diagnostic.dart';
import 'package:galley/src/diagnostics/exceptions.dart';
import 'package:galley/src/io/file_byte_source.dart';

import 'support/zip_fixtures.dart';

/// Códigos que o contêiner emite (spec §9.1).
const containerCodes = {
  'mimetypeIrregular',
  'zipCrcMismatch',
  'zipDuplicateEntry',
  'pathCaseMismatch',
  'fontObfuscationUnknown',
};

/// Dos acima, os `warning` (lançam em strict).
const containerWarnings = {'zipCrcMismatch', 'fontObfuscationUnknown'};

/// Grupos que rodam com `strict: false` (doc/10 §5).
const relaxedGroups = {'patologia', 'faixa-b'};

/// Teto de uma ida da fonte por `fetch`: a primeira leitura e, com extra
/// field grande no local header, a segunda só com os dados.
int fetchBound(ZipEntry e, {required int calls}) =>
    30 +
    e.nameLength +
    e.compressedSize +
    1024 +
    (calls > 1 ? e.compressedSize : 0);

Future<void> _drainAll(ZipContainer c, CountingByteSource counting) async {
  for (final path in c.paths) {
    counting.reset();
    final r = (await c.fetch(path))!;
    final entry = c.centralDirectory.lookup(path)!.entry;
    expect(counting.calls, inInclusiveRange(1, 2), reason: path);
    expect(
      counting.bytesRead,
      lessThanOrEqualTo(fetchBound(entry, calls: counting.calls)),
      reason: 'fetch de $path leu demais',
    );
    for (final _ in r.decode()) {}
  }
}

List<String> _lines(File f) => f.existsSync()
    ? f.readAsLinesSync().where((l) => l.isNotEmpty).toList()
    : const [];

void main() {
  final root = Directory('test/corpus');
  final cases =
      root
          .listSync()
          .whereType<Directory>()
          .expand((group) => group.listSync().whereType<Directory>())
          .map(
            (d) => d.path.substring(root.path.length + 1).replaceAll(r'\', '/'),
          )
          .toList()
        ..sort();

  test('corpus tem os 65 casos', () {
    expect(cases, hasLength(65));
  });

  for (final name in cases) {
    final dir = '${root.path}/$name';
    final group = name.split('/').first;
    final strict = !relaxedGroups.contains(group);
    final exception = _lines(File('$dir/exception.expected')).firstOrNull;
    final expectedCodes = _lines(File('$dir/diagnostics.expected'))
        .where(containerCodes.contains)
        .toSet();

    test('$name (strict: $strict)', () async {
      final counting = CountingByteSource(FileEpubByteSource('$dir/book.epub'));
      final sink = DiagnosticSink(strict: strict);
      final open = ZipContainer.open(counting, sink: sink);
      switch (exception) {
        case 'EpubContainerException':
          await expectLater(open, throwsA(isA<EpubContainerException>()));
          return;
        case 'EpubEncryptedException':
          await expectLater(open, throwsA(isA<EpubEncryptedException>()));
          return;
      }
      final c = await open;
      final cd = c.centralDirectory;
      int bound(String path) {
        final e = cd.lookup(path)?.entry;
        return e == null ? 0 : fetchBound(e, calls: 2);
      }

      expect(
        counting.bytesRead,
        lessThanOrEqualTo(
          tailReadSize +
              (cd.zip64 ? 56 : 0) +
              cd.cdSize +
              bound('mimetype') +
              bound('META-INF/encryption.xml') +
              bound('META-INF/rights.xml'),
        ),
        reason: 'a abertura leu demais',
      );

      await _drainAll(c, counting);
      final emitted = sink.diagnostics
          .map((d) => d.code.name)
          .where(containerCodes.contains)
          .toSet();
      expect(emitted, expectedCodes);
      await c.close();
    });

    if (group == 'patologia' && expectedCodes.any(containerWarnings.contains)) {
      test('$name (segunda passada, strict: true)', () async {
        final source = CountingByteSource(FileEpubByteSource('$dir/book.epub'));
        Future<void> run() async {
          final c = await ZipContainer.open(
            source,
            sink: DiagnosticSink(strict: true),
          );
          await _drainAll(c, source);
        }

        await expectLater(run(), throwsA(isA<EpubContainerException>()));
        await source.close();
      });
    }
  }
}
