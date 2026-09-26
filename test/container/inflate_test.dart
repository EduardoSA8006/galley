// decode() de PendingResource: passos, fatias, limites e CRC (spec §5.4).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/container/container.dart';
import 'package:galley/src/container/inflate/inflate.dart';
import 'package:galley/src/container/zip/crc32.dart';
import 'package:galley/src/diagnostics/diagnostic.dart';
import 'package:galley/src/diagnostics/exceptions.dart';

import 'support/zip_fixtures.dart';

Uint8List _deflate(List<int> data) =>
    Uint8List.fromList(ZLibCodec(raw: true, level: 6).encode(data));

PendingResource _stored(
  Uint8List data, {
  int? size,
  int? crc,
  DiagnosticSink? sink,
}) => PendingResource.zip(
  path: 'a.bin',
  size: size ?? data.length,
  method: 0,
  data: data,
  crc32: crc ?? crc32(data),
  sink: sink ?? DiagnosticSink(),
);

PendingResource _deflated(
  Uint8List plain, {
  Uint8List? data,
  int? size,
  int? crc,
  DiagnosticSink? sink,
  InflaterFactory inflaterFactory = createInflater,
}) => PendingResource.zip(
  path: 'a.xhtml',
  size: size ?? plain.length,
  method: 8,
  data: data ?? _deflate(plain),
  crc32: crc ?? crc32(plain),
  sink: sink ?? DiagnosticSink(),
  inflaterFactory: inflaterFactory,
);

int _drain(PendingResource r) => r.decode().length;

/// Inflater que registra o tamanho de cada fatia recebida.
final class _Recording implements ChunkedInflater {
  _Recording(this._inner, this.slices);
  final ChunkedInflater _inner;
  final List<int> slices;
  @override
  void add(Uint8List chunk) {
    slices.add(chunk.length);
    _inner.add(chunk);
  }

  @override
  void close() => _inner.close();
}

void main() {
  group('contagem exata de passos', () {
    for (final (label, n, steps) in [
      ('0 B', 0, 1),
      ('100 KiB', 100 * 1024, 2),
      ('1 MiB', 1024 * 1024, 17),
      ('64 KiB - 1', 64 * 1024 - 1, 1),
      ('64 KiB', 64 * 1024, 2),
    ]) {
      test('stored $label: $steps passos', () {
        final data = noise(n);
        final r = _stored(data);
        expect(_drain(r), steps);
        expect(r.bytes, data);
      });

      test('deflate $label: $steps passos', () {
        final plain = prose(n);
        final r = _deflated(plain);
        expect(_drain(r), steps);
        expect(r.bytes, plain);
      });
    }
  });

  test('entrada comprimida vai ao decoder em fatias de até 16 KiB', () {
    final plain = noise(100 * 1024); // não comprime: ~100 KiB de entrada
    final slices = <int>[];
    final r = _deflated(
      plain,
      inflaterFactory: (out) => _Recording(createInflater(out), slices),
    );
    _drain(r);
    expect(r.bytes, plain);
    expect(slices.length, greaterThan(6));
    expect(slices.every((s) => s <= inflateSliceBytes), isTrue);
    expect(
      slices.sublist(0, slices.length - 1),
      everyElement(inflateSliceBytes),
    );
  });

  group('saída maior que a declarada', () {
    test('deflate: lança EpubContainerException sem passar do limite', () {
      final plain = prose(200 * 1024);
      final r = _deflated(plain, size: 100 * 1024);
      expect(
        () => _drain(r),
        throwsA(
          isA<EpubContainerException>()
              .having((e) => e.href, 'href', 'a.xhtml')
              .having((e) => e.message, 'message', contains('maior')),
        ),
      );
      expect(() => r.bytes, throwsStateError);
    });

    test('zip bomb: 16 MiB de zeros declarados como 1 MiB', () {
      final bomb = _deflate(Uint8List(16 * 1024 * 1024));
      final r = _deflated(Uint8List(0), data: bomb, size: 1024 * 1024, crc: 0);
      expect(() => _drain(r), throwsA(isA<EpubContainerException>()));
    });

    test('stored: dados maiores que o declarado lançam', () {
      final data = noise(1000);
      expect(
        () => _drain(_stored(data, size: 999)),
        throwsA(isA<EpubContainerException>()),
      );
    });
  });

  group('saída menor que a declarada', () {
    test('deflate: zipCrcMismatch com reason size e bytes curtos', () {
      final plain = prose(10000);
      final sink = DiagnosticSink();
      final r = _deflated(plain, size: 10100, sink: sink);
      expect(_drain(r), 1);
      expect(r.bytes, plain);
      final d = sink.diagnostics.single;
      expect(d.code, EpubDiagnosticCode.zipCrcMismatch);
      expect(d.severity, EpubSeverity.warning);
      expect(d.href, 'a.xhtml');
      expect(d.details, {
        'reason': 'size',
        'expected': 10100,
        'actual': 10000,
        'count': 1,
      });
    });

    test('deflate truncado: bytes curtos e reason size', () {
      final plain = prose(300 * 1024);
      final full = _deflate(plain);
      final sink = DiagnosticSink();
      final r = _deflated(
        plain,
        data: Uint8List.sublistView(full, 0, full.length ~/ 2),
        sink: sink,
      );
      _drain(r);
      expect(r.bytes.length, lessThan(plain.length));
      expect(r.bytes, plain.sublist(0, r.bytes.length));
      expect(sink.diagnostics.single.details['reason'], 'size');
    });

    test('stored: dados menores que o declarado', () {
      final sink = DiagnosticSink();
      final r = _stored(noise(500), size: 600, sink: sink);
      _drain(r);
      expect(r.bytes, hasLength(500));
      expect(sink.diagnostics.single.details['reason'], 'size');
    });
  });

  group('CRC', () {
    test('divergente: warning com reason crc; bytes entregues', () {
      final plain = prose(5000);
      final sink = DiagnosticSink();
      final r = _deflated(plain, crc: 0xDEADBEEF, sink: sink);
      _drain(r);
      expect(r.bytes, plain);
      final d = sink.diagnostics.single;
      expect(d.severity, EpubSeverity.warning);
      expect(d.details, {
        'reason': 'crc',
        'expected': 0xDEADBEEF,
        'actual': crc32(plain),
        'count': 1,
      });
    });

    test('stored também confere o CRC', () {
      final sink = DiagnosticSink();
      _drain(_stored(noise(70000), crc: 1, sink: sink));
      expect(sink.diagnostics.single.details['reason'], 'crc');
    });

    test(
      'strict: registra e lança EpubContainerException; bytes indisponível',
      () {
        final sink = DiagnosticSink(strict: true);
        final r = _deflated(prose(5000), crc: 1, sink: sink);
        expect(
          () => _drain(r),
          throwsA(
            isA<EpubContainerException>()
                .having((e) => e.href, 'href', 'a.xhtml')
                .having(
                  (e) => e.message,
                  'message',
                  contains('zipCrcMismatch'),
                ),
          ),
        );
        expect(sink.diagnostics.single.code, EpubDiagnosticCode.zipCrcMismatch);
        expect(() => r.bytes, throwsStateError);
      },
    );

    test('CRC certo não emite nada', () {
      final sink = DiagnosticSink(strict: true);
      _drain(_deflated(prose(5000), sink: sink));
      expect(sink.diagnostics, isEmpty);
    });
  });

  test('deflate inválido lança EpubContainerException com cause', () {
    final r = _deflated(Uint8List(0), data: noise(100), size: 1000, crc: 0);
    expect(
      () => _drain(r),
      throwsA(
        isA<EpubContainerException>().having(
          (e) => e.cause,
          'cause',
          isA<FormatException>(),
        ),
      ),
    );
  });

  group('drenagem', () {
    test('bytes antes do decode lança StateError', () {
      expect(() => _stored(noise(10)).bytes, throwsStateError);
    });

    test('bytes antes do fim da drenagem lança StateError', () {
      final r = _deflated(prose(200 * 1024));
      final it = r.decode().iterator..moveNext();
      expect(() => r.bytes, throwsStateError);
      while (it.moveNext()) {}
      expect(r.bytes, hasLength(200 * 1024));
    });

    test('segundo decode() lança StateError no primeiro passo', () {
      final r = _stored(noise(10));
      final second = r.decode();
      _drain(r);
      expect(() => second.iterator.moveNext(), throwsStateError);
      expect(() => _drain(r), throwsStateError);
    });

    test('segunda iteração do mesmo iterável lança StateError', () {
      final r = _stored(noise(10));
      final steps = r.decode();
      expect(steps.length, 1);
      expect(() => steps.length, throwsStateError);
    });

    test('size é o declarado', () {
      expect(_deflated(prose(100), size: 150).size, 150);
    });
  });

  group('PendingResource.ready', () {
    test('um passo, sem CRC', () {
      final r = PendingResource.ready(path: 'p.xhtml', bytes: noise(200000));
      expect(r.size, 200000);
      expect(_drain(r), 1);
      expect(r.bytes, hasLength(200000));
    });
  });
}
