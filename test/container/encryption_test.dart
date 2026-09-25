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
          '﻿${_encryption([_data(_font, algorithm: idpfObfuscationAlgorithm)])}';
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
  });
}
