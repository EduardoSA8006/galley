// ZipContainer: fetch, leituras, mimetype e close (spec do contêiner §5).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/container/byte_source.dart';
import 'package:galley/src/container/container.dart';
import 'package:galley/src/container/zip/zip_container.dart';
import 'package:galley/src/diagnostics/diagnostic.dart';
import 'package:galley/src/diagnostics/exceptions.dart';

import 'support/zip_fixtures.dart';

Future<Uint8List> _read(PendingResource r) async {
  for (final _ in r.decode()) {}
  return r.bytes;
}

Future<ZipContainer> _open(Uint8List zip, {DiagnosticSink? sink}) =>
    ZipContainer.open(
      MemoryEpubByteSource(zip),
      sink: sink ?? DiagnosticSink(),
    );

void main() {
  final chapter = prose(40000);
  final image = noise(3000);
  final zip = epubZip({
    'META-INF/container.xml': utf8.encode('<container/>'),
    'OEBPS/Text/cap01.xhtml': chapter,
  });
  final mixed =
      (ZipWriter()
            ..add('mimetype', ascii.encode(epubMimetype), compress: false)
            ..add('OEBPS/Text/cap01.xhtml', chapter)
            ..add('OEBPS/Images/a.png', image, compress: false))
          .build();

  group('fetch', () {
    test('stored e deflate', () async {
      final c = await _open(mixed);
      final text = (await c.fetch('OEBPS/Text/cap01.xhtml'))!;
      expect(text.path, 'OEBPS/Text/cap01.xhtml');
      expect(text.size, chapter.length);
      expect(await _read(text), chapter);
      expect(await _read((await c.fetch('OEBPS/Images/a.png'))!), image);
      expect(c.paths, [
        'mimetype',
        'OEBPS/Text/cap01.xhtml',
        'OEBPS/Images/a.png',
      ]);
    });

    test('ausente devolve null', () async {
      final c = await _open(zip);
      expect(await c.fetch('OEBPS/nada.xhtml'), isNull);
      expect(await c.exists('OEBPS/nada.xhtml'), isFalse);
    });

    test('uma readRange por fetch, dentro do orçamento', () async {
      final counting = CountingByteSource(MemoryEpubByteSource(mixed));
      final c = await ZipContainer.open(counting, sink: DiagnosticSink());
      final entry = c.centralDirectory.lookup('OEBPS/Text/cap01.xhtml')!.entry;
      counting.reset();
      final r = (await c.fetch('OEBPS/Text/cap01.xhtml'))!;
      expect(counting.calls, 1);
      expect(
        counting.bytesRead,
        lessThanOrEqualTo(30 + entry.nameLength + entry.compressedSize + 1024),
      );
      expect(await _read(r), chapter);
      expect(counting.calls, 1, reason: 'decode não lê da fonte');
    });

    test('extra field grande no local header: duas leituras', () async {
      final big = withLocalExtra(mixed, 1, 5000);
      final counting = CountingByteSource(MemoryEpubByteSource(big));
      final c = await ZipContainer.open(counting, sink: DiagnosticSink());
      final entry = c.centralDirectory.lookup('OEBPS/Text/cap01.xhtml')!.entry;
      counting.reset();
      final r = (await c.fetch('OEBPS/Text/cap01.xhtml'))!;
      expect(counting.calls, 2);
      expect(counting.ranges.last.$2, entry.compressedSize);
      expect(await _read(r), chapter);
      expect(await _read((await c.fetch('OEBPS/Images/a.png'))!), image);
    });

    test(
      'extra do local header que empurra os dados para além do fim',
      () async {
        final bad = patchLocalU16(mixed, 2, 28, 60000);
        final c = await _open(bad);
        await expectLater(
          c.fetch('OEBPS/Images/a.png'),
          throwsA(
            isA<EpubContainerException>().having(
              (e) => e.href,
              'href',
              'OEBPS/Images/a.png',
            ),
          ),
        );
      },
    );

    test(
      'data descriptor: valem os tamanhos e o CRC do central directory',
      () async {
        final sink = DiagnosticSink(strict: true);
        final c = await _open(withDataDescriptor(mixed, 1), sink: sink);
        expect(
          await _read((await c.fetch('OEBPS/Text/cap01.xhtml'))!),
          chapter,
        );
        expect(sink.diagnostics, isEmpty);
      },
    );

    test('método 12 lança EpubContainerException(href)', () async {
      final c = await _open(withMethod(mixed, 1, 12));
      await expectLater(
        c.fetch('OEBPS/Text/cap01.xhtml'),
        throwsA(
          isA<EpubContainerException>()
              .having((e) => e.href, 'href', 'OEBPS/Text/cap01.xhtml')
              .having((e) => e.message, 'message', contains('12')),
        ),
      );
    });

    test('assinatura do local header errada', () async {
      final l = ZipLayout(mixed);
      final bad = Uint8List.fromList(mixed)..[l.local[2]] = 0;
      final c = await _open(bad);
      await expectLater(
        c.fetch('OEBPS/Images/a.png'),
        throwsA(isA<EpubContainerException>()),
      );
    });

    test(
      'entrada inválida lança EpubContainerException com o motivo',
      () async {
        final bad = patchCentralU32(mixed, 2, cdUncompressed, maxEntrySize + 1);
        final c = await _open(bad);
        expect(await c.exists('OEBPS/Images/a.png'), isTrue);
        await expectLater(
          c.fetch('OEBPS/Images/a.png'),
          throwsA(
            isA<EpubContainerException>().having(
              (e) => e.message,
              'message',
              contains('$maxEntrySize'),
            ),
          ),
        );
      },
    );

    test('entradas com dados sobrepostos: a segunda fica inválida, a '
        'primeira lê normalmente', () async {
      final l = ZipLayout(mixed);
      final overlapped = patchCentralU32(mixed, 2, cdLocalOffset, l.local[1]);
      final c = await _open(overlapped);
      await expectLater(
        c.fetch('OEBPS/Images/a.png'),
        throwsA(
          isA<EpubContainerException>().having(
            (e) => e.message,
            'message',
            'dados sobrepostos a outra entrada',
          ),
        ),
      );
      expect(await _read((await c.fetch('OEBPS/Text/cap01.xhtml'))!), chapter);
    });

    test(
      'falha da fonte no fetch vira EpubContainerException com cause',
      () async {
        final inner = MemoryEpubByteSource(mixed);
        final c = await ZipContainer.open(inner, sink: DiagnosticSink());
        await inner.close(); // a fonte some por baixo do contêiner
        await expectLater(
          c.fetch('OEBPS/Images/a.png'),
          throwsA(
            isA<EpubContainerException>().having(
              (e) => e.cause,
              'cause',
              isStateError,
            ),
          ),
        );
      },
    );
  });

  test('bit 0 ligado lança EpubEncryptedException na abertura', () async {
    await expectLater(
      _open(withFlagBits(mixed, 2, 0x0001)),
      throwsA(
        isA<EpubEncryptedException>().having(
          (e) => e.scheme,
          'scheme',
          'zip-encryption',
        ),
      ),
    );
  });

  group('sem diferenciar maiúsculas', () {
    test('fetch acha e emite pathCaseMismatch; exists não emite', () async {
      final sink = DiagnosticSink();
      final c = await _open(mixed, sink: sink);
      expect(await c.exists('oebps/text/CAP01.xhtml'), isTrue);
      expect(sink.diagnostics, isEmpty);
      final r = (await c.fetch('oebps/text/CAP01.xhtml'))!;
      expect(r.path, 'OEBPS/Text/cap01.xhtml');
      expect(await _read(r), chapter);
      final d = sink.diagnostics.single;
      expect(d.code, EpubDiagnosticCode.pathCaseMismatch);
      expect(d.href, 'oebps/text/CAP01.xhtml');
      expect(d.details['actual'], 'OEBPS/Text/cap01.xhtml');
    });
  });

  group('mimetype', () {
    Future<List<EpubDiagnostic>> diagnosticsOf(Uint8List z) async {
      final sink = DiagnosticSink();
      await _open(z, sink: sink);
      return sink.diagnostics;
    }

    Uint8List build({
      bool include = true,
      bool first = true,
      bool compress = false,
      String content = epubMimetype,
    }) {
      final w = ZipWriter();
      void mimetype() =>
          w.add('mimetype', ascii.encode(content), compress: compress);
      if (include && first) mimetype();
      w.add('OEBPS/a.xhtml', prose(100));
      if (include && !first) mimetype();
      return w.build();
    }

    test('regular: nenhum diagnóstico', () async {
      expect(await diagnosticsOf(build()), isEmpty);
    });

    for (final (reason, z) in [
      ('missing', build(include: false)),
      ('notFirst', build(first: false)),
      ('compressed', build(compress: true)),
      ('content', build(content: 'application/zip')),
      ('unreadable', Uint8List.fromList(build())..[0] = 0),
    ]) {
      test('$reason: mimetypeIrregular info, nunca fatal', () async {
        final d = (await diagnosticsOf(z)).single;
        expect(d.code, EpubDiagnosticCode.mimetypeIrregular);
        expect(d.severity, EpubSeverity.info);
        expect(d.details['reason'], reason);
      });
    }

    test('com prefixo: só o diagnóstico do prefixo', () async {
      final ds = await diagnosticsOf(withPrefix(build(), 10));
      expect(ds.single.details['reason'], 'prefix');
    });

    test('strict: vira warning e lança', () async {
      await expectLater(
        _open(build(first: false), sink: DiagnosticSink(strict: true)),
        throwsA(isA<EpubContainerException>()),
      );
    });
  });

  group('close', () {
    test('fecha a fonte, é idempotente e bloqueia fetch', () async {
      final counting = CountingByteSource(MemoryEpubByteSource(zip));
      final c = await ZipContainer.open(counting, sink: DiagnosticSink());
      await c.close();
      await c.close();
      expect(counting.closed, isTrue);
      await expectLater(c.fetch('mimetype'), throwsStateError);
    });

    test('abertura que falha fecha a fonte', () async {
      final counting = CountingByteSource(
        MemoryEpubByteSource(Uint8List.sublistView(zip, 0, zip.length - 10)),
      );
      await expectLater(
        ZipContainer.open(counting, sink: DiagnosticSink()),
        throwsA(isA<EpubContainerException>()),
      );
      expect(counting.closed, isTrue);
    });
  });

  test('obfuscationOf é null sem encryption.xml', () async {
    final c = await _open(zip);
    expect(c.obfuscationOf('OEBPS/Text/cap01.xhtml'), isNull);
  });
}
