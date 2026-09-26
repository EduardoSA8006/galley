// ProviderContainer (spec do contêiner §6.2).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/container/container.dart';
import 'package:galley/src/container/encryption.dart';
import 'package:galley/src/container/provider_container.dart';
import 'package:galley/src/container/resource_provider.dart';
import 'package:galley/src/diagnostics/diagnostic.dart';
import 'package:galley/src/diagnostics/exceptions.dart';

/// Provider em memória; [failing] lança FileSystemException em read.
final class _MapProvider implements EpubResourceProvider {
  _MapProvider(this.files, {this.failing = const {}});

  final Map<String, List<int>> files;
  final Set<String> failing;
  int closeCalls = 0;

  @override
  Future<bool> exists(String href) async => files.containsKey(href);

  @override
  Future<Uint8List> read(String href) async {
    if (failing.contains(href)) throw FileSystemException('sem acesso', href);
    return Uint8List.fromList(files[href]!);
  }

  @override
  Future<void> close() async => closeCalls++;
}

String _encryption(String algorithm, String uri, {String keyInfo = ''}) =>
    '<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container" '
    'xmlns:enc="http://www.w3.org/2001/04/xmlenc#"><enc:EncryptedData>'
    '<enc:EncryptionMethod Algorithm="$algorithm"/>$keyInfo'
    '<enc:CipherData><enc:CipherReference URI="$uri"/></enc:CipherData>'
    '</enc:EncryptedData></encryption>';

Future<Uint8List> _read(PendingResource r) async {
  expect(r.decode().length, 1);
  return r.bytes;
}

void main() {
  test('leitura: um passo, sem CRC; paths vazio', () async {
    final p = _MapProvider({'OEBPS/a.xhtml': utf8.encode('<p>oi</p>')});
    final sink = DiagnosticSink(strict: true);
    final c = await ProviderContainer.open(p, sink: sink);
    expect(c.paths, isEmpty);
    expect(await c.exists('OEBPS/a.xhtml'), isTrue);
    final r = (await c.fetch('OEBPS/a.xhtml'))!;
    expect(r.path, 'OEBPS/a.xhtml');
    expect(r.size, 9);
    expect(utf8.decode(await _read(r)), '<p>oi</p>');
    expect(sink.diagnostics, isEmpty);
  });

  test('ausente devolve null; sem busca sem diferenciar maiúsculas', () async {
    final c = await ProviderContainer.open(
      _MapProvider({
        'OEBPS/a.xhtml': [1],
      }),
      sink: DiagnosticSink(),
    );
    expect(await c.fetch('OEBPS/nada.xhtml'), isNull);
    expect(await c.fetch('oebps/A.xhtml'), isNull);
    expect(await c.exists('oebps/A.xhtml'), isFalse);
  });

  test(
    'exceção do provider vira EpubContainerException(href, cause)',
    () async {
      final c = await ProviderContainer.open(
        _MapProvider(
          {
            'a.xhtml': [1],
          },
          failing: {'a.xhtml'},
        ),
        sink: DiagnosticSink(),
      );
      await expectLater(
        c.fetch('a.xhtml'),
        throwsA(
          isA<EpubContainerException>()
              .having((e) => e.href, 'href', 'a.xhtml')
              .having((e) => e.cause, 'cause', isA<FileSystemException>()),
        ),
      );
    },
  );

  test('LCP e cifra sobre conteúdo nunca são fatais', () async {
    const lcp =
        '<ds:KeyInfo xmlns:ds="http://www.w3.org/2000/09/xmldsig#">'
        '<ds:RetrievalMethod Type="$lcpContentKeyType"/></ds:KeyInfo>';
    final p = _MapProvider({
      'META-INF/license.lcpl': utf8.encode('{}'),
      'META-INF/rights.xml': utf8.encode('<rights/>'),
      'META-INF/encryption.xml': utf8.encode(
        _encryption(
          'http://www.w3.org/2001/04/xmlenc#aes256-cbc',
          'OEBPS/a.xhtml',
          keyInfo: lcp,
        ),
      ),
      'OEBPS/a.xhtml': [1, 2, 3],
    });
    final sink = DiagnosticSink(strict: true);
    final c = await ProviderContainer.open(p, sink: sink);
    expect(await _read((await c.fetch('OEBPS/a.xhtml'))!), [1, 2, 3]);
    expect(c.obfuscationOf('OEBPS/a.xhtml'), isNull);
    expect(sink.diagnostics, isEmpty);
  });

  test('cifra de DRM (LCP/ADEPT) sobre fonte já decifrada é ignorada pelo '
      'provider', () async {
    const lcp =
        '<ds:KeyInfo xmlns:ds="http://www.w3.org/2000/09/xmldsig#">'
        '<ds:RetrievalMethod Type="$lcpContentKeyType"/></ds:KeyInfo>';
    final sink = DiagnosticSink(strict: true);
    final c = await ProviderContainer.open(
      _MapProvider({
        'META-INF/encryption.xml': utf8.encode(
          _encryption(
            'http://www.w3.org/2001/04/xmlenc#aes256-cbc',
            'OEBPS/Fonts/a.otf',
            keyInfo: lcp,
          ),
        ),
      }),
      sink: sink,
    );
    expect(c.obfuscationOf('OEBPS/Fonts/a.otf'), isNull);
    expect(sink.diagnostics, isEmpty);
  });

  test(
    'algoritmo de xmlenc# sem KeyInfo de DRM sobre fonte também é ignorado',
    () async {
      final sink = DiagnosticSink(strict: true);
      final c = await ProviderContainer.open(
        _MapProvider({
          'META-INF/encryption.xml': utf8.encode(
            _encryption(
              'http://www.w3.org/2001/04/xmlenc#aes256-cbc',
              'OEBPS/Fonts/a.otf',
            ),
          ),
        }),
        sink: sink,
      );
      expect(c.obfuscationOf('OEBPS/Fonts/a.otf'), isNull);
      expect(sink.diagnostics, isEmpty);
    },
  );

  test(
    'algoritmo realmente desconhecido sobre fonte continua unknown',
    () async {
      final sink = DiagnosticSink();
      final c = await ProviderContainer.open(
        _MapProvider({
          'META-INF/encryption.xml': utf8.encode(
            _encryption('urn:x-desconhecido', 'OEBPS/Fonts/a.otf'),
          ),
        }),
        sink: sink,
      );
      expect(c.obfuscationOf('OEBPS/Fonts/a.otf'), FontObfuscation.unknown);
      expect(
        sink.diagnostics.single.code,
        EpubDiagnosticCode.fontObfuscationUnknown,
      );
    },
  );

  group('obfuscationOf', () {
    for (final (algorithm, kind) in [
      (idpfObfuscationAlgorithm, FontObfuscation.idpf),
      (adobeObfuscationAlgorithm, FontObfuscation.adobe),
    ]) {
      test(kind.name, () async {
        final c = await ProviderContainer.open(
          _MapProvider({
            'META-INF/encryption.xml': utf8.encode(
              _encryption(algorithm, 'OEBPS/Fonts/a.otf'),
            ),
          }),
          sink: DiagnosticSink(),
        );
        expect(c.obfuscationOf('OEBPS/Fonts/a.otf'), kind);
        expect(c.obfuscationOf('oebps/fonts/a.otf'), isNull);
      });
    }

    test('algoritmo desconhecido sobre fonte → unknown + warning', () async {
      final sink = DiagnosticSink();
      final c = await ProviderContainer.open(
        _MapProvider({
          'META-INF/encryption.xml': utf8.encode(
            _encryption('urn:x', 'Fonts/a.woff'),
          ),
        }),
        sink: sink,
      );
      expect(c.obfuscationOf('Fonts/a.woff'), FontObfuscation.unknown);
      expect(
        sink.diagnostics.single.code,
        EpubDiagnosticCode.fontObfuscationUnknown,
      );
    });
  });

  test(
    'encryption.xml inválido: encryptionIgnored e obfuscationOf null',
    () async {
      final sink = DiagnosticSink(strict: true);
      final c = await ProviderContainer.open(
        _MapProvider({'META-INF/encryption.xml': utf8.encode('<encryption')}),
        sink: sink,
      );
      final d = sink.diagnostics.single;
      expect(d.code, EpubDiagnosticCode.encryptionIgnored);
      expect(d.severity, EpubSeverity.info);
      expect(d.details['reason'], 'invalid-xml');
      expect(c.obfuscationOf('OEBPS/Fonts/a.otf'), isNull);
    },
  );

  test(
    'encryption.xml acima de 4 MiB: encryptionIgnored too-large, sem parse',
    () async {
      final sink = DiagnosticSink(strict: true);
      final huge = List<int>.filled(5 * 1024 * 1024, 0x41);
      final c = await ProviderContainer.open(
        _MapProvider({'META-INF/encryption.xml': huge}),
        sink: sink,
      );
      final d = sink.diagnostics.single;
      expect(d.code, EpubDiagnosticCode.encryptionIgnored);
      expect(d.details['reason'], 'too-large');
      expect(c.obfuscationOf('OEBPS/Fonts/a.otf'), isNull);
    },
  );

  test('encryption.xml ilegível pelo provider: encryptionIgnored', () async {
    final sink = DiagnosticSink();
    await ProviderContainer.open(
      _MapProvider(
        {
          'META-INF/encryption.xml': [1],
        },
        failing: {'META-INF/encryption.xml'},
      ),
      sink: sink,
    );
    expect(sink.diagnostics.single.details['reason'], 'unreadable');
  });

  test('close fecha o provider uma vez e bloqueia fetch', () async {
    final p = _MapProvider({});
    final c = await ProviderContainer.open(p, sink: DiagnosticSink());
    await c.close();
    await c.close();
    expect(p.closeCalls, 1);
    await expectLater(c.fetch('a'), throwsStateError);
  });
}
