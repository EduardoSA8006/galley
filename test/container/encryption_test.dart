// encryption.xml, rights.xml, LCP e ofuscação de fontes (spec §6).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/container/byte_source.dart';
import 'package:galley/src/container/container.dart';
import 'package:galley/src/container/encryption.dart';
import 'package:galley/src/container/zip/zip_container.dart';
import 'package:galley/src/diagnostics/diagnostic.dart';
import 'package:galley/src/diagnostics/exceptions.dart';
import 'package:xml/xml.dart';

import 'support/zip_fixtures.dart';

const _aes = 'http://www.w3.org/2001/04/xmlenc#aes256-cbc';
const _font = 'OEBPS/Fonts/a.ttf';
const _text = 'OEBPS/Text/cap01.xhtml';

/// Um `EncryptedData` com o prefixo `enc:`.
String _data(String? uri, {String? algorithm = _aes, String keyInfo = ''}) =>
    '<enc:EncryptedData>'
    '${algorithm == null ? '' : '<enc:EncryptionMethod Algorithm="$algorithm"/>'}'
    '$keyInfo'
    '${uri == null ? '' : '<enc:CipherData><enc:CipherReference URI="$uri"/></enc:CipherData>'}'
    '</enc:EncryptedData>';

String _encryption(List<String> data) =>
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container" '
    'xmlns:enc="http://www.w3.org/2001/04/xmlenc#">${data.join()}</encryption>';

Uint8List _book(Map<String, String> meta, {Map<String, List<int>>? extra}) =>
    epubZip({
      'META-INF/container.xml': utf8.encode('<container/>'),
      for (final MapEntry(:key, :value) in meta.entries)
        key: utf8.encode(value),
      _text: prose(2000),
      _font: noise(3000),
      ...?extra,
    });

Future<ZipContainer> _open(Uint8List zip, {DiagnosticSink? sink}) =>
    ZipContainer.open(
      MemoryEpubByteSource(zip),
      sink: sink ?? DiagnosticSink(),
    );

Matcher _encrypted(String scheme) => throwsA(
  isA<EpubEncryptedException>()
      .having((e) => e.scheme, 'scheme', scheme)
      .having((e) => e.message, 'message', contains(scheme)),
);

void main() {
  group('arquivos de licença', () {
    test('META-INF/license.lcpl → lcp', () async {
      await expectLater(
        _open(_book({'META-INF/license.lcpl': '{}'})),
        _encrypted('lcp'),
      );
    });

    test('rights.xml com namespace do ADEPT → adobe-adept', () async {
      const rights =
          '<adept:rights xmlns:adept="http://ns.adobe.com/adept">'
          '<adept:licenseToken/></adept:rights>';
      await expectLater(
        _open(_book({'META-INF/rights.xml': rights})),
        _encrypted('adobe-adept'),
      );
    });

    test('rights.xml sem namespace conhecido → unknown:rights.xml', () async {
      await expectLater(
        _open(_book({'META-INF/rights.xml': '<rights/>'})),
        _encrypted('unknown:rights.xml'),
      );
    });

    test('rights.xml inválido → unknown:rights.xml', () async {
      await expectLater(
        _open(_book({'META-INF/rights.xml': '<rights'})),
        _encrypted('unknown:rights.xml'),
      );
    });

    test('licença LCP vence encryption.xml de fonte', () async {
      final meta = {
        'META-INF/license.lcpl': '{}',
        'META-INF/encryption.xml': _encryption([
          _data(_font, algorithm: idpfObfuscationAlgorithm),
        ]),
      };
      await expectLater(_open(_book(meta)), _encrypted('lcp'));
    });

    test('DRM é checado antes do mimetype: LCP com mimetype fora de ordem em '
        'strict ainda lança lcp', () async {
      final zip =
          (ZipWriter()
                ..add(
                  'META-INF/license.lcpl',
                  utf8.encode('{}'),
                  compress: false,
                )
                ..add('OEBPS/a.xhtml', prose(100))
                ..add('mimetype', utf8.encode(epubMimetype), compress: false))
              .build();
      await expectLater(
        _open(zip, sink: DiagnosticSink(strict: true)),
        _encrypted('lcp'),
      );
    });

    test('DRM é checado antes do prefixo: LCP com prefixo em strict ainda '
        'lança lcp', () async {
      final zip = withPrefix(
        (ZipWriter()
              ..add('META-INF/license.lcpl', utf8.encode('{}'), compress: false)
              ..add('mimetype', utf8.encode(epubMimetype), compress: false)
              ..add('OEBPS/a.xhtml', prose(100)))
            .build(),
        64,
      );
      await expectLater(
        _open(zip, sink: DiagnosticSink(strict: true)),
        _encrypted('lcp'),
      );
    });

    test('bit 0 (criptografia do ZIP) com prefixo em strict lança '
        'zip-encryption, não o mimetypeIrregular do prefixo', () async {
      final zip = withPrefix(
        withFlagBits(
          (ZipWriter()
                ..add('mimetype', utf8.encode(epubMimetype), compress: false)
                ..add('OEBPS/a.xhtml', prose(100)))
              .build(),
          1,
          0x0001,
        ),
        64,
      );
      await expectLater(
        _open(zip, sink: DiagnosticSink(strict: true)),
        throwsA(
          isA<EpubEncryptedException>().having(
            (e) => e.scheme,
            'scheme',
            'zip-encryption',
          ),
        ),
      );
    });
  });

  group('encryption.xml', () {
    Future<ZipContainer> withEncryption(
      List<String> data, {
      DiagnosticSink? sink,
    }) => _open(
      _book({'META-INF/encryption.xml': _encryption(data)}),
      sink: sink,
    );

    test('XML inválido → unknown:encryption.xml-invalido com cause', () async {
      await expectLater(
        _open(_book({'META-INF/encryption.xml': '<encryption><enc:Encrypted'})),
        throwsA(
          isA<EpubEncryptedException>()
              .having(
                (e) => e.scheme,
                'scheme',
                'unknown:encryption.xml-invalido',
              )
              .having((e) => e.cause, 'cause', isA<XmlException>()),
        ),
      );
    });

    test('RetrievalMethod do LCP → lcp', () async {
      const keyInfo =
          '<ds:KeyInfo xmlns:ds="http://www.w3.org/2000/09/xmldsig#">'
          '<ds:RetrievalMethod URI="license.lcpl#/encryption/content_key" '
          'Type="http://readium.org/2014/01/lcp#EncryptedContentKey"/>'
          '</ds:KeyInfo>';
      await expectLater(
        withEncryption([_data(_text, keyInfo: keyInfo)]),
        _encrypted('lcp'),
      );
    });

    test('KeyInfo com namespace do ADEPT → adobe-adept', () async {
      const keyInfo =
          '<KeyInfo xmlns="http://www.w3.org/2000/09/xmldsig#">'
          '<resource xmlns="http://ns.adobe.com/adept">urn:uuid:1</resource>'
          '</KeyInfo>';
      await expectLater(
        withEncryption([_data(_text, keyInfo: keyInfo)]),
        _encrypted('adobe-adept'),
      );
    });

    test(
      'cifra sobre caminho que não é fonte → unknown:<primeiro URI>',
      () async {
        await expectLater(
          withEncryption([
            _data(_font, algorithm: idpfObfuscationAlgorithm),
            _data(_text, algorithm: 'urn:cifra:primeira'),
            _data('OEBPS/Text/cap02.xhtml', algorithm: 'urn:cifra:segunda'),
          ]),
          _encrypted('unknown:urn:cifra:primeira'),
        );
      },
    );

    test(
      'ofuscação IDPF sobre caminho que não é fonte → unknown:<uri>',
      () async {
        await expectLater(
          withEncryption([_data(_text, algorithm: idpfObfuscationAlgorithm)]),
          _encrypted('unknown:$idpfObfuscationAlgorithm'),
        );
      },
    );

    test(
      'ofuscação Adobe sobre caminho que não é fonte → unknown:<uri>',
      () async {
        await expectLater(
          withEncryption([_data(_text, algorithm: adobeObfuscationAlgorithm)]),
          _encrypted('unknown:$adobeObfuscationAlgorithm'),
        );
      },
    );

    test('IDPF sobre fonte → idpf', () async {
      final c = await withEncryption([
        _data(_font, algorithm: idpfObfuscationAlgorithm),
      ]);
      expect(c.obfuscationOf(_font), FontObfuscation.idpf);
      expect(c.obfuscationOf(_text), isNull);
    });

    test('Adobe sobre fonte → adobe', () async {
      final c = await withEncryption([
        _data(_font, algorithm: adobeObfuscationAlgorithm),
      ]);
      expect(c.obfuscationOf(_font), FontObfuscation.adobe);
    });

    test(
      'algoritmo desconhecido só sobre fontes → unknown + warning',
      () async {
        final sink = DiagnosticSink();
        final c = await withEncryption([
          _data(_font, algorithm: _aes),
        ], sink: sink);
        expect(c.obfuscationOf(_font), FontObfuscation.unknown);
        final d = sink.diagnostics.single;
        expect(d.code, EpubDiagnosticCode.fontObfuscationUnknown);
        expect(d.severity, EpubSeverity.warning);
        expect(d.href, _font);
        expect(d.details['algorithm'], _aes);
      },
    );

    test('EncryptionMethod ausente é tratado como algoritmo vazio', () async {
      final sink = DiagnosticSink();
      final c = await withEncryption([
        _data(_font, algorithm: null),
      ], sink: sink);
      expect(c.obfuscationOf(_font), FontObfuscation.unknown);
      expect(sink.diagnostics.single.details['algorithm'], '');
      await expectLater(
        withEncryption([_data(_text, algorithm: null)]),
        _encrypted('unknown:'),
      );
    });

    test('strict: fonte desconhecida lança', () async {
      await expectLater(
        withEncryption([_data(_font)], sink: DiagnosticSink(strict: true)),
        throwsA(isA<EpubContainerException>()),
      );
    });

    test('BOM UTF-8 antes da declaração XML não torna o XML inválido', () async {
      final xml =
          '\uFEFF'
          '${_encryption([_data(_font, algorithm: idpfObfuscationAlgorithm)])}';
      final c = await _open(_book({'META-INF/encryption.xml': xml}));
      expect(c.obfuscationOf(_font), FontObfuscation.idpf);
    });

    test('EncryptedData sem CipherReference é ignorado', () async {
      final c = await withEncryption([_data(null)]);
      expect(c.obfuscationOf(_text), isNull);
    });

    test('extensão de fonte em maiúsculas', () async {
      final zip = _book(
        {
          'META-INF/encryption.xml': _encryption([
            _data('OEBPS/Fonts/B.OTF', algorithm: idpfObfuscationAlgorithm),
          ]),
        },
        extra: {'OEBPS/Fonts/B.OTF': noise(100)},
      );
      final c = await _open(zip);
      expect(c.obfuscationOf('OEBPS/Fonts/B.OTF'), FontObfuscation.idpf);
    });

    test('%xx válido é decodificado; inválido fica cru', () async {
      final zip = _book(
        {
          'META-INF/encryption.xml': _encryption([
            _data(
              'OEBPS/Fonts/minha%20fonte.ttf',
              algorithm: idpfObfuscationAlgorithm,
            ),
            _data('OEBPS/Fonts/100%.ttf', algorithm: adobeObfuscationAlgorithm),
          ]),
        },
        extra: {
          'OEBPS/Fonts/minha fonte.ttf': noise(100),
          'OEBPS/Fonts/100%.ttf': noise(100),
        },
      );
      final c = await _open(zip);
      expect(
        c.obfuscationOf('OEBPS/Fonts/minha fonte.ttf'),
        FontObfuscation.idpf,
      );
      expect(c.obfuscationOf('OEBPS/Fonts/100%.ttf'), FontObfuscation.adobe);
    });

    test(
      'URI com / ou ./ inicial e caixa diferente casa pelo índice',
      () async {
        final c = await withEncryption([
          _data('/oebps/fonts/A.ttf', algorithm: idpfObfuscationAlgorithm),
        ]);
        expect(c.obfuscationOf(_font), FontObfuscation.idpf);
        expect(c.obfuscationOf('oebps/FONTS/a.TTF'), FontObfuscation.idpf);
      },
    );

    test('prefixo de namespace diferente e namespace padrão', () async {
      const xml =
          '<container:encryption '
          'xmlns:container="urn:oasis:names:tc:opendocument:xmlns:container">'
          '<x:EncryptedData xmlns:x="http://www.w3.org/2001/04/xmlenc#">'
          '<x:EncryptionMethod Algorithm="$idpfObfuscationAlgorithm"/>'
          '<x:CipherData><x:CipherReference URI="$_font"/></x:CipherData>'
          '</x:EncryptedData>'
          '<EncryptedData xmlns="http://www.w3.org/2001/04/xmlenc#">'
          '<EncryptionMethod Algorithm="$_aes"/>'
          '<CipherData><CipherReference URI="$_text"/></CipherData>'
          '</EncryptedData>'
          '</container:encryption>';
      await expectLater(
        _open(_book({'META-INF/encryption.xml': xml})),
        _encrypted('unknown:$_aes'),
      );
    });

    test('20 000 níveis de EncryptedData aninhado não são quadráticos', () {
      const depth = 20000;
      final buffer = StringBuffer(
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container" '
        'xmlns:enc="http://www.w3.org/2001/04/xmlenc#">',
      );
      for (var i = 0; i < depth; i++) {
        buffer.write(
          '<enc:EncryptedData>'
          '<enc:EncryptionMethod Algorithm="$idpfObfuscationAlgorithm"/>'
          '<enc:CipherData>'
          '<enc:CipherReference URI="OEBPS/Fonts/f$i.ttf"/>'
          '</enc:CipherData>',
        );
      }
      for (var i = 0; i < depth; i++) {
        buffer.write('</enc:EncryptedData>');
      }
      buffer.write('</encryption>');
      final stopwatch = Stopwatch()..start();
      final items = parseEncryptionXml(buffer.toString());
      stopwatch.stop();
      expect(items.length, depth);
      // Folgado de propósito: só para pegar regressão quadrática (o custo
      // linear é bem menor que 1 s; o quadrático não termina nessa ordem).
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('20 000 níveis de EncryptedData > KeyInfo > EncryptedData > … não '
        'são quadráticos', () {
      const depth = 20000;
      const dsigNamespace = 'http://www.w3.org/2000/09/xmldsig#';
      final buffer = StringBuffer(
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container" '
        'xmlns:enc="http://www.w3.org/2001/04/xmlenc#">',
      );
      for (var i = 0; i < depth; i++) {
        buffer.write(
          '<enc:EncryptedData>'
          '<enc:EncryptionMethod Algorithm="$idpfObfuscationAlgorithm"/>'
          '<enc:CipherData>'
          '<enc:CipherReference URI="OEBPS/Fonts/f$i.ttf"/>'
          '</enc:CipherData>'
          '<ds:KeyInfo xmlns:ds="$dsigNamespace">',
        );
      }
      for (var i = 0; i < depth; i++) {
        buffer.write('</ds:KeyInfo></enc:EncryptedData>');
      }
      buffer.write('</encryption>');
      final stopwatch = Stopwatch()..start();
      final items = parseEncryptionXml(buffer.toString());
      stopwatch.stop();
      expect(items.length, depth);
      for (final item in items) {
        expect(item.adeptKey, isFalse);
      }
      // Folgado de propósito: só para pegar regressão quadrática na
      // checagem do namespace ADEPT dentro de KeyInfo aninhado.
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('CipherReference de fonte dentro de KeyInfo/EncryptedKey não engana: '
        'AES sobre cap01.xhtml continua fatal', () async {
      const keyInfo =
          '<ds:KeyInfo xmlns:ds="http://www.w3.org/2000/09/xmldsig#">'
          '<enc:EncryptedKey>'
          '<enc:CipherData>'
          '<enc:CipherReference URI="$_font"/>'
          '</enc:CipherData>'
          '</enc:EncryptedKey>'
          '</ds:KeyInfo>';
      await expectLater(
        withEncryption([_data(_text, algorithm: _aes, keyInfo: keyInfo)]),
        throwsA(
          isA<EpubEncryptedException>().having(
            (e) => e.scheme,
            'scheme',
            startsWith('unknown:'),
          ),
        ),
      );
    });
  });

  group('CRC errado em encryption.xml', () {
    Uint8List badCrc() {
      final zip = _book({'META-INF/encryption.xml': '<encryption/>'});
      return patchCentralU32(zip, 2, cdCrc, 0);
    }

    test(
      'strict: propaga zipCrcMismatch, não vira DRM falso (invalido)',
      () async {
        await expectLater(
          _open(badCrc(), sink: DiagnosticSink(strict: true)),
          throwsA(
            isA<EpubContainerException>().having(
              (e) => e.message,
              'message',
              contains('zipCrcMismatch'),
            ),
          ),
        );
      },
    );

    test('sem strict: abre com o warning (comportamento atual)', () async {
      final sink = DiagnosticSink();
      final c = await _open(badCrc(), sink: sink);
      expect(c.obfuscationOf(_font), isNull);
      expect(sink.diagnostics.single.code, EpubDiagnosticCode.zipCrcMismatch);
    });
  });

  group('teto de 4 MiB para metadados', () {
    // Altamente compressível: o ZIP fica pequeno mesmo com 5 MiB declarados.
    final huge = List<int>.filled(5 * 1024 * 1024, 0x41);

    test('encryption.xml acima do teto: unknown:encryption.xml-invalido sem '
        'buscar nem parsear', () async {
      final zip = _book({}, extra: {'META-INF/encryption.xml': huge});
      final counting = CountingByteSource(MemoryEpubByteSource(zip));
      final stopwatch = Stopwatch()..start();
      await expectLater(
        ZipContainer.open(counting, sink: DiagnosticSink()),
        _encrypted('unknown:encryption.xml-invalido'),
      );
      stopwatch.stop();
      expect(stopwatch.elapsedMilliseconds, lessThan(200));
      // Só o fim do arquivo e o central directory: nenhuma ida extra para
      // ler ou parsear os dados de encryption.xml.
      expect(counting.calls, 2);
    });

    test(
      'rights.xml acima do teto: unknown:rights.xml sem buscar nem parsear',
      () async {
        final zip = _book({}, extra: {'META-INF/rights.xml': huge});
        final counting = CountingByteSource(MemoryEpubByteSource(zip));
        final stopwatch = Stopwatch()..start();
        await expectLater(
          ZipContainer.open(counting, sink: DiagnosticSink()),
          _encrypted('unknown:rights.xml'),
        );
        stopwatch.stop();
        expect(stopwatch.elapsedMilliseconds, lessThan(200));
        expect(counting.calls, 2);
      },
    );
  });

  group('isFontPath e normalizeCipherReference', () {
    test('extensões de fonte', () {
      for (final p in [
        'a.ttf',
        'a.OTF',
        'a.ttc',
        'a.otc',
        'a.woff',
        'a.WOFF2',
      ]) {
        expect(isFontPath(p), isTrue, reason: p);
      }
      for (final p in ['a.xhtml', 'a.ttf.bak', 'ttf', 'a.svg']) {
        expect(isFontPath(p), isFalse, reason: p);
      }
    });

    test('normalização', () {
      expect(normalizeCipherReference('./a%20b.ttf'), 'a b.ttf');
      expect(
        normalizeCipherReference(r'OEBPS\Fonts\a.ttf'),
        'OEBPS/Fonts/a.ttf',
      );
      expect(normalizeCipherReference('a%zz.ttf'), 'a%zz.ttf');
    });

    test(
      '%xx que decodifica para UTF-8 inválido fica cru (FormatException)',
      () {
        for (final raw in [
          'a%FF.ttf',
          'a%C3.ttf',
          'a%C3%28.ttf',
          'a%ED%A0%80.ttf',
          'fonte%E9.ttf',
        ]) {
          expect(normalizeCipherReference(raw), raw, reason: raw);
        }
      },
    );

    test(
      'encryption.xml com %xx Latin-1 de produtor abre sem exceção crua',
      () async {
        final zip = _book(
          {
            'META-INF/encryption.xml': _encryption([
              _data(
                'OEBPS/Fonts/fonte%E9.ttf',
                algorithm: idpfObfuscationAlgorithm,
              ),
            ]),
          },
          extra: {'OEBPS/Fonts/fonte%E9.ttf': noise(100)},
        );
        final c = await _open(zip);
        expect(
          c.obfuscationOf('OEBPS/Fonts/fonte%E9.ttf'),
          FontObfuscation.idpf,
        );
      },
    );
  });
}
