// SHA-1, desofuscação IDPF/Adobe e looksLikeFont (spec do contêiner §6.1).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/container/container.dart';
import 'package:galley/src/container/font_obfuscation.dart';
import 'package:galley/src/container/sha1.dart';
import 'package:galley/src/container/zip/zip_container.dart';
import 'package:galley/src/diagnostics/diagnostic.dart';
import 'package:galley/src/io/file_byte_source.dart';
import 'package:xml/xml.dart';

import 'support/zip_fixtures.dart';

Uint8List _ascii(String s) => ascii.encode(s);

const _uuid = 'urn:uuid:b7e2f1a0-4c3d-4e5f-8a9b-0c1d2e3f4a5b';

/// Cabeçalho TrueType seguido de ruído: passa em looksLikeFont.
final Uint8List _font = Uint8List.fromList([0, 1, 0, 0, ...noise(4096)]);

Uint8List _idpf(Uint8List bytes, List<String> ids) => deobfuscateFont(
  bytes,
  FontObfuscation.idpf,
  uniqueIdentifiers: ids,
  identifiers: const [],
)!;

Uint8List? _adobe(Uint8List bytes, List<String> ids) => deobfuscateFont(
  bytes,
  FontObfuscation.adobe,
  uniqueIdentifiers: const [],
  identifiers: ids,
);

void main() {
  group('SHA-1', () {
    test('6 vetores conhecidos', () {
      expect(
        sha1Hex(_ascii('abc')),
        'a9993e364706816aba3e25717850c26c9cd0d89d',
      );
      expect(sha1Hex(Uint8List(0)), 'da39a3ee5e6b4b0d3255bfef95601890afd80709');
      expect(
        sha1Hex(_ascii('The quick brown fox jumps over the lazy dog')),
        '2fd4e1c67a2d28fced849ee1bb76e7391b93eb12',
      );
      // Fronteiras do padding: 55, 56 e 64 bytes.
      expect(
        sha1Hex(_ascii('a' * 55)),
        'c1c8bbdc22796e28c0e15163d20899b65621d65a',
      );
      expect(
        sha1Hex(_ascii('a' * 56)),
        'c2db330f6083854c99d4b5bfb6e8f29f201be699',
      );
      expect(
        sha1Hex(_ascii('a' * 64)),
        '0098ba824b5c16427bd7a1122a5a442a25ec644d',
      );
    });
  });

  group('IDPF', () {
    test('ida e volta; só os primeiros 1040 bytes mudam', () {
      final obfuscated = _idpf(_font, [_uuid]);
      expect(obfuscated.sublist(0, 1040), isNot(_font.sublist(0, 1040)));
      expect(obfuscated.sublist(1040), _font.sublist(1040));
      expect(looksLikeFont(obfuscated), isFalse);
      expect(_idpf(obfuscated, [_uuid]), _font);
    });

    test('chave é o SHA-1 dos identificadores sem espaço, CR, LF e TAB', () {
      final a = _idpf(_font, ['urn:uuid:abc', 'def']);
      final b = _idpf(_font, [' urn:uuid:abc\n', '\tdef\r ']);
      expect(a, b);
      final key = sha1(_ascii('urn:uuid:abcdef'));
      expect(a[0], _font[0] ^ key[0]);
      expect(a[20], _font[20] ^ key[0]);
    });

    test('lista vazia ou só whitespace → null', () {
      expect(
        deobfuscateFont(
          _font,
          FontObfuscation.idpf,
          uniqueIdentifiers: const [],
          identifiers: const [_uuid],
        ),
        isNull,
      );
      expect(
        deobfuscateFont(
          _font,
          FontObfuscation.idpf,
          uniqueIdentifiers: const [' \n'],
          identifiers: const [],
        ),
        isNull,
      );
    });

    test('fonte menor que 1040 bytes', () {
      final small = Uint8List.fromList([0, 1, 0, 0, 9, 9]);
      expect(_idpf(_idpf(small, [_uuid]), [_uuid]), small);
    });
  });

  group('Adobe', () {
    test('ida e volta; só os primeiros 1024 bytes mudam', () {
      final obfuscated = _adobe(_font, [_uuid])!;
      expect(obfuscated.sublist(1024), _font.sublist(1024));
      expect(obfuscated[0], _font[0] ^ 0xb7);
      expect(obfuscated[15], _font[15] ^ 0x5b);
      expect(_adobe(obfuscated, [_uuid]), _font);
    });

    test('UUID em qualquer posição; vale o primeiro utilizável', () {
      final expected = _adobe(_font, [_uuid]);
      expect(
        _adobe(_font, ['isbn:978-85-000', 'urn:uuid:curto', _uuid]),
        expected,
      );
      expect(
        _adobe(_font, [_uuid, 'urn:uuid:00000000-0000-0000-0000-000000000001']),
        expected,
      );
    });

    test('prefixo sem diferenciar maiúsculas e 32 hex sem prefixo', () {
      final expected = _adobe(_font, [_uuid]);
      expect(_adobe(_font, [_uuid.toUpperCase()]), expected);
      expect(_adobe(_font, ['b7e2f1a04c3d4e5f8a9b0c1d2e3f4a5b']), expected);
    });

    test('nenhum identificador utilizável → null', () {
      expect(_adobe(_font, const []), isNull);
      expect(_adobe(_font, ['isbn:978-85-000', 'urn:uuid:zz']), isNull);
    });
  });

  test('unknown lança ArgumentError', () {
    expect(
      () => deobfuscateFont(
        _font,
        FontObfuscation.unknown,
        uniqueIdentifiers: const [_uuid],
        identifiers: const [_uuid],
      ),
      throwsArgumentError,
    );
  });

  test('looksLikeFont reconhece os seis magics', () {
    for (final magic in [
      [0x00, 0x01, 0x00, 0x00],
      ...['OTTO', 'true', 'ttcf', 'wOFF', 'wOF2'].map(ascii.encode),
    ]) {
      expect(looksLikeFont(Uint8List.fromList([...magic, 0, 0])), isTrue);
    }
    expect(looksLikeFont(_ascii('<?xm')), isFalse);
    expect(looksLikeFont(Uint8List.fromList([0, 1, 0])), isFalse);
  });

  group('corpus', () {
    final original = File('tool/corpus/assets/NotoSansOgham-Regular.ttf')
        .readAsBytesSync();

    for (final (slug, kind) in [
      ('fonte-ofuscada-idpf', FontObfuscation.idpf),
      ('fonte-ofuscada-adobe', FontObfuscation.adobe),
    ]) {
      test(
        '$slug: desofuscada passa em looksLikeFont e é a fonte original',
        () async {
          final c = await ZipContainer.open(
            FileEpubByteSource('test/corpus/patologia/$slug/book.epub'),
            sink: DiagnosticSink(strict: true),
          );
          const fontPath = 'OEBPS/Fonts/NotoSansOgham-Regular.ttf';
          expect(c.obfuscationOf(fontPath), kind);

          final opf = (await c.fetch('OEBPS/content.opf'))!;
          for (final _ in opf.decode()) {}
          final doc = XmlDocument.parse(utf8.decode(opf.bytes));
          final uniqueId = doc.rootElement.getAttribute('unique-identifier');
          final ids = doc.findAllElements(
            'identifier',
            namespaceUri: 'http://purl.org/dc/elements/1.1/',
          );

          final font = (await c.fetch(fontPath))!;
          for (final _ in font.decode()) {}
          expect(looksLikeFont(font.bytes), isFalse);
          final restored = deobfuscateFont(
            font.bytes,
            kind,
            uniqueIdentifiers: [
              for (final e in ids)
                if (e.getAttribute('id') == uniqueId) e.innerText,
            ],
            identifiers: [for (final e in ids) e.innerText],
          )!;
          expect(looksLikeFont(restored), isTrue);
          expect(restored, original);
          await c.close();
        },
      );
    }
  });
}
