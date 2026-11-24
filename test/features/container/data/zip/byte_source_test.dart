import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/core/errors/galley_exception.dart';
import 'package:galley/src/features/container/data/zip/byte_source.dart';

import '../../../../support/zip_builder.dart';

void main() {
  test('MemoryByteSource lê faixas e rejeita além do fim', () async {
    final s = MemoryByteSource(Uint8List.fromList(List.generate(10, (i) => i)));
    expect(await s.read(2, 3), [2, 3, 4]);
    expect(() => s.read(8, 5), throwsA(isA<CorruptArchiveException>()));
  });

  test('FileByteSource serializa leituras concorrentes', () async {
    final dir = Directory.systemTemp.createTempSync();
    addTearDown(() => dir.deleteSync(recursive: true));
    final f = File('${dir.path}/b.bin')
      ..writeAsBytesSync(List.generate(4096, (i) => i % 256));
    final s = await FileByteSource.open(f.path);
    final rs = await Future.wait([
      for (var i = 0; i < 50; i++) s.read(i * 64, 64),
    ]);
    for (var i = 0; i < 50; i++) {
      expect(rs[i].first, (i * 64) % 256);
      expect(rs[i].length, 64);
    }
    await expectLater(
      s.read(4090, 10),
      throwsA(isA<CorruptArchiveException>()),
    );
    await s.close();
  });

  group('ZipBuilder', () {
    final tmp = Directory.systemTemp.createTempSync();
    tearDownAll(() => tmp.deleteSync(recursive: true));

    Future<ProcessResult> unzipTest(Uint8List bytes, String name) async {
      final p = '${tmp.path}/$name.zip';
      File(p).writeAsBytesSync(bytes);
      return Process.run('python3', ['-m', 'zipfile', '-t', p]);
    }

    test('gera zips válidos (deflate, stored, descriptor, zip64)', () async {
      for (final zip64 in [false, true]) {
        final b = ZipBuilder()
          ..addFile(
            'mimetype',
            utf8.encode('application/epub+zip'),
            deflate: false,
          )
          ..addFile('a/b.txt', utf8.encode('olá ' * 200))
          ..addFile('d.txt', utf8.encode('descritor'), dataDescriptor: true)
          ..addFile('vazio.txt', const []);
        final r = await unzipTest(
          b.build(zip64: zip64, comment: 'c'),
          'z$zip64',
        );
        expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      }
    });
  });
}
