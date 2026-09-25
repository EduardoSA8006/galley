// Fim do arquivo e central directory (spec do contêiner §5.1).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/container/byte_source.dart';
import 'package:galley/src/container/container.dart';
import 'package:galley/src/container/zip/central_directory.dart';
import 'package:galley/src/diagnostics/diagnostic.dart';
import 'package:galley/src/diagnostics/exceptions.dart';

import 'support/zip_fixtures.dart';

Future<CentralDirectory> _read(Uint8List zip, {DiagnosticSink? sink}) =>
    readCentralDirectory(
      MemoryEpubByteSource(zip),
      sink: sink ?? DiagnosticSink(),
    );

Matcher _containerError(String text) => throwsA(
  isA<EpubContainerException>().having(
    (e) => e.message,
    'message',
    contains(text),
  ),
);

void main() {
  final files = {
    'META-INF/container.xml': utf8.encode('<container/>'),
    'OEBPS/cap01.xhtml': prose(5000),
  };
  final zip = epubZip(files);

  group('EOCD', () {
    test('simples', () async {
      final cd = await _read(zip);
      expect(cd.paths, [
        'mimetype',
        'META-INF/container.xml',
        'OEBPS/cap01.xhtml',
      ]);
      expect(cd.delta, 0);
      expect(cd.zip64, isFalse);
      expect(cd.length, zip.length);
      final e = cd.lookup('OEBPS/cap01.xhtml')!.entry;
      expect(e.uncompressedSize, 5000);
      expect(e.method, 8);
    });

    test('com comentário', () async {
      final cd = await _read(withComment(zip, utf8.encode('comentário')));
      expect(cd.paths, hasLength(3));
    });

    test('com assinatura falsa de EOCD dentro do comentário', () async {
      final cd = await _read(withFakeEocdInComment(zip));
      expect(cd.paths, hasLength(3));
      expect(cd.delta, 0);
    });

    test('comentário de 65 535 bytes', () async {
      final cd = await _read(withComment(zip, List<int>.filled(65535, 0x20)));
      expect(cd.paths, hasLength(3));
    });
  });

  group('ZIP64', () {
    final z64 = epubZip(files, zip64: true);

    test('segue o locator e o extra 0x0001', () async {
      final cd = await _read(z64);
      expect(cd.zip64, isTrue);
      expect(cd.paths, hasLength(3));
      final e = cd.lookup('OEBPS/cap01.xhtml')!.entry;
      expect(e.uncompressedSize, 5000);
      expect(e.localHeaderOffset, lessThan(z64.length));
      expect(e.invalidReason, isNull);
    });

    test('com prefixo: acha o EOCD64 antes do locator', () async {
      final sink = DiagnosticSink();
      final cd = await _read(withPrefix(z64, 64), sink: sink);
      expect(cd.delta, 64);
      expect(cd.lookup('mimetype')!.entry.localHeaderOffset, 64);
      expect(sink.diagnostics.single.details['reason'], 'prefix');
    });

    test('total de discos 0 e 1 aceitos; 2 é fatal', () async {
      expect((await _read(withZip64TotalDisks(z64, 0))).zip64, isTrue);
      await expectLater(
        _read(withZip64TotalDisks(z64, 2)),
        _containerError('vários discos'),
      );
    });

    test('valor u64 acima de 2^53 torna a entrada inválida', () async {
      final big = withZip64ExtraValue(z64, 2, 0, lo: 1, hi: 0x200000);
      final e = (await _read(big)).lookup('OEBPS/cap01.xhtml')!.entry;
      expect(e.invalidReason, contains('2^53'));
    });
  });

  group('prefixo', () {
    test('offsets recebem delta e emite mimetypeIrregular', () async {
      final sink = DiagnosticSink();
      final cd = await _read(withPrefix(zip, 100), sink: sink);
      expect(cd.delta, 100);
      expect(cd.lookup('mimetype')!.entry.localHeaderOffset, 100);
      final d = sink.diagnostics.single;
      expect(d.code, EpubDiagnosticCode.mimetypeIrregular);
      expect(d.details, {'reason': 'prefix', 'delta': 100, 'count': 1});
    });

    test('delta negativo é fatal', () async {
      final l = ZipLayout(zip);
      await expectLater(
        _read(withEocdCdOffset(zip, l.cdOffset + 5)),
        _containerError('não cabe'),
      );
    });
  });

  group('nomes', () {
    Uint8List single(String name) =>
        (ZipWriter()..add(name, utf8.encode('x'), compress: false)).build();

    test('CP437 sem bit 11 quando não é UTF-8 válido', () async {
      var z = single('caXitulo.xhtml');
      final raw = ascii.encode('caXitulo.xhtml')..[2] = 0x87; // ç em CP437
      z = withoutFlagBits(withRawName(z, 0, raw), 0, 0x0800);
      expect((await _read(z)).paths, ['caçitulo.xhtml']);
    });

    test('UTF-8 sem bit 11 quando os bytes são UTF-8 válido', () async {
      final z = withoutFlagBits(single('capítulo.xhtml'), 0, 0x0800);
      expect((await _read(z)).paths, ['capítulo.xhtml']);
    });

    test('bit 11 com UTF-8 malformado decodifica tolerante', () async {
      final raw = ascii.encode('caXitulo.xhtml')..[2] = 0xFF;
      final z = withRawName(single('caXitulo.xhtml'), 0, raw);
      expect((await _read(z)).paths.single, 'ca�itulo.xhtml');
    });

    test('normaliza \\, / e ./ iniciais; rawName guarda o original', () async {
      final w = ZipWriter()
        ..add(r'OEBPS\Text\a.xhtml', [1], compress: false)
        ..add('/abs.xhtml', [2], compress: false)
        ..add('./rel.xhtml', [3], compress: false)
        ..add('.//dupla.xhtml', [4], compress: false);
      final cd = await _read(w.build());
      expect(cd.paths, [
        'OEBPS/Text/a.xhtml',
        'abs.xhtml',
        'rel.xhtml',
        'dupla.xhtml',
      ]);
      expect(cd.entries.first.rawName, r'OEBPS\Text\a.xhtml');
    });

    test('normalizeEntryName: só barras vira vazio', () {
      expect(normalizeEntryName('/' * 65535), '');
    });

    test('normalizeEntryName: repetição de ./ some inteira', () {
      expect(normalizeEntryName('${'./' * 30000}a'), 'a');
    });

    test('normalizeEntryName: nomes hostis não custam quadrático', () {
      final stopwatch = Stopwatch()..start();
      normalizeEntryName('/' * 65535);
      normalizeEntryName('${'./' * 30000}a');
      stopwatch.stop();
      // Folgado de propósito: só para pegar regressão quadrática (o bug
      // original levava ~0,77 s só para o caso de 65 535 barras).
      expect(stopwatch.elapsedMilliseconds, lessThan(100));
    });

    test('diretórios ficam fora de paths e do índice', () async {
      final w = ZipWriter()
        ..add('OEBPS/', const [], compress: false)
        ..add('OEBPS/a.xhtml', [1], compress: false);
      final cd = await _read(w.build());
      expect(cd.entries, hasLength(2));
      expect(cd.paths, ['OEBPS/a.xhtml']);
      expect(cd.lookup('OEBPS/'), isNull);
    });
  });

  group('duplicatas', () {
    test('vence a primeira; as seguintes emitem zipDuplicateEntry', () async {
      final w = ZipWriter()
        ..add('a.txt', [1, 1, 1], compress: false)
        ..add('a.txt', [2, 2], compress: false)
        ..add('a.txt', [3], compress: false);
      final sink = DiagnosticSink();
      final cd = await _read(w.build(), sink: sink);
      expect(cd.paths, ['a.txt']);
      expect(cd.lookup('a.txt')!.entry.uncompressedSize, 3);
      final d = sink.diagnostics.single;
      expect(d.code, EpubDiagnosticCode.zipDuplicateEntry);
      expect(d.severity, EpubSeverity.info);
      expect(d.href, 'a.txt');
      expect(d.details['count'], 2);
    });

    test('sem diferenciar maiúsculas também vence a primeira', () async {
      final w = ZipWriter()
        ..add('Cap.xhtml', [1], compress: false)
        ..add('CAP.xhtml', [2, 2], compress: false);
      final cd = await _read(w.build());
      expect(cd.paths, ['Cap.xhtml', 'CAP.xhtml']);
      final hit = cd.lookup('cap.xhtml')!;
      expect(hit.exact, isFalse);
      expect(hit.entry.name, 'Cap.xhtml');
      expect(cd.lookup('CAP.xhtml')!.exact, isTrue);
    });
  });

  group('validação por entrada', () {
    test('local header além do fim', () async {
      final z = patchCentralU32(zip, 2, cdLocalOffset, zip.length + 10);
      final e = (await _read(z)).lookup('OEBPS/cap01.xhtml')!.entry;
      expect(e.invalidReason, contains('local header além do fim'));
    });

    test('dados além do fim', () async {
      final z = patchCentralU32(zip, 2, cdCompressed, zip.length);
      final e = (await _read(z)).lookup('OEBPS/cap01.xhtml')!.entry;
      expect(e.invalidReason, contains('dados da entrada além do fim'));
    });

    test('uncompressedSize acima de maxEntrySize', () async {
      final z = patchCentralU32(zip, 2, cdUncompressed, maxEntrySize + 1);
      final e = (await _read(z)).lookup('OEBPS/cap01.xhtml')!.entry;
      expect(e.invalidReason, contains('$maxEntrySize'));
    });

    test('entrada inválida continua em paths', () async {
      final z = patchCentralU32(zip, 2, cdLocalOffset, zip.length + 10);
      expect((await _read(z)).paths, contains('OEBPS/cap01.xhtml'));
    });
  });

  test('contagem divergente não é fatal', () async {
    final cd = await _read(withEocdCount(zip, 99));
    expect(cd.paths, hasLength(3));
  });

  test('bit 0 (criptografia do ZIP) lança EpubEncryptedException', () async {
    await expectLater(
      _read(withFlagBits(zip, 1, 0x0001)),
      throwsA(
        isA<EpubEncryptedException>()
            .having((e) => e.scheme, 'scheme', 'zip-encryption')
            .having((e) => e.href, 'href', 'META-INF/container.xml'),
      ),
    );
  });

  group('fatais', () {
    test('EOCD não encontrado (arquivo cortado)', () async {
      await expectLater(
        _read(Uint8List.sublistView(zip, 0, zip.length - 10)),
        _containerError('EOCD'),
      );
    });

    test('fonte vazia', () async {
      await expectLater(_read(Uint8List(0)), _containerError('EOCD'));
    });

    test('assinatura de entrada do central directory errada', () async {
      await expectLater(
        _read(withBadCentralSignature(zip, 1)),
        _containerError('assinatura'),
      );
    });

    test('central directory truncado', () async {
      await expectLater(
        _read(withTruncatedCentralDirectory(zip, 10)),
        _containerError('truncado'),
      );
    });

    test('disco múltiplo', () async {
      await expectLater(
        _read(withEocdDisks(zip, disk: 1)),
        _containerError('vários discos'),
      );
      await expectLater(
        _read(withEocdDisks(zip, cdDisk: 1)),
        _containerError('vários discos'),
      );
    });

    test('exceção da fonte vira EpubContainerException com cause', () async {
      const error = FileSystemException('disco sumiu');
      await expectLater(
        readCentralDirectory(FailingByteSource(error), sink: DiagnosticSink()),
        throwsA(
          isA<EpubContainerException>().having(
            (e) => e.cause,
            'cause',
            same(error),
          ),
        ),
      );
    });
  });
}
