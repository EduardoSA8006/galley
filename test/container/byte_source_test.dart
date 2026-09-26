// MemoryEpubByteSource e FileEpubByteSource (spec do contêiner §3).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/container/byte_source.dart';
import 'package:galley/src/io/file_byte_source.dart';

Uint8List _pattern(int n) =>
    Uint8List.fromList(List<int>.generate(n, (i) => (i * 7 + 3) & 0xFF));

void main() {
  final data = _pattern(200 * 1024);
  late Directory tmp;
  late String path;

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('galley_byte_source_');
    path = '${tmp.path}/book.epub';
    File(path).writeAsBytesSync(data);
  });

  tearDownAll(() => tmp.deleteSync(recursive: true));

  final factories = <String, EpubByteSource Function()>{
    'Memory': () => MemoryEpubByteSource(data),
    'File': () => FileEpubByteSource(path),
  };

  for (final MapEntry(key: name, value: create) in factories.entries) {
    group(name, () {
      test('length e leitura', () async {
        final s = create();
        expect(await s.length, data.length);
        expect(await s.readRange(0, 4), data.sublist(0, 4));
        expect(
          await s.readRange(data.length - 10, 10),
          data.sublist(data.length - 10),
        );
        expect(await s.readRange(100, 0), isEmpty);
        await s.close();
      });

      test('faixas inválidas lançam RangeError', () async {
        final s = create();
        await expectLater(s.readRange(-1, 4), throwsRangeError);
        await expectLater(s.readRange(0, -1), throwsRangeError);
        await expectLater(s.readRange(data.length - 3, 4), throwsRangeError);
        // A fonte continua utilizável depois do erro.
        expect(await s.readRange(0, 2), data.sublist(0, 2));
        await s.close();
      });

      test(
        'leitura depois de close lança StateError; close idempotente',
        () async {
          final s = create();
          await s.readRange(0, 1);
          await s.close();
          await s.close();
          await expectLater(s.readRange(0, 1), throwsStateError);
          await expectLater(s.length, throwsStateError);
        },
      );

      test('50 readRange concorrentes devolvem cada faixa certa', () async {
        final s = create();
        final offsets = List<int>.generate(50, (i) => (i * 3989) % 150000);
        final results = await Future.wait([
          for (final o in offsets) s.readRange(o, 4096 + o % 1000),
        ]);
        for (var i = 0; i < offsets.length; i++) {
          final o = offsets[i];
          expect(
            results[i],
            data.sublist(o, o + 4096 + o % 1000),
            reason: 'offset $o',
          );
        }
        await s.close();
      });

      test(
        'close durante uma leitura: a leitura termina, as novas falham',
        () async {
          final s = create();
          final pending = s.readRange(1000, 50000);
          final closing = s.close();
          expect(await pending, data.sublist(1000, 51000));
          await closing;
          await expectLater(s.readRange(0, 1), throwsStateError);
        },
      );
    });
  }

  group('File', () {
    test('path é o caminho recebido', () {
      expect(FileEpubByteSource(path).path, path);
    });

    test(
      'arquivo inexistente lança FileSystemException na primeira leitura',
      () async {
        final s = FileEpubByteSource('${tmp.path}/nao-existe.epub');
        await expectLater(s.length, throwsA(isA<FileSystemException>()));
        await expectLater(
          s.readRange(0, 1),
          throwsA(isA<FileSystemException>()),
        );
        await s.close();
      },
    );

    test('arquivo inexistente: close sem leitura não lança', () async {
      await FileEpubByteSource('${tmp.path}/nao-existe.epub').close();
    });
  });
}
