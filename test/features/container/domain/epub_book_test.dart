import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/galley.dart';
import 'package:galley/src/features/container/data/crypto/sha1.dart';
import 'package:galley/src/features/container/data/zip/byte_source.dart';

import '../../../support/epub_builder.dart';

const String _uuid = '12345678-1234-1234-1234-123456789abc';
const String _identifier = 'urn:uuid:$_uuid';

const String _chapter1Name = 'OEBPS/Text/Capítulo 1.xhtml';
const String _chapter1 =
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>1</title></head>'
    '<body><p>Olá, mundo — ação!</p></body></html>';
const String _chapter2 =
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>2</title></head>'
    '<body><p>Dois</p></body></html>';

const String _nav =
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<html xmlns="http://www.w3.org/1999/xhtml" '
    'xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Nav</title></head>'
    '<body><nav epub:type="toc"><ol>'
    '<li><a href="Text/Cap%C3%ADtulo%201.xhtml">Capítulo 1</a></li>'
    '<li><a href="Text/cap2.xhtml">Capítulo 2</a></li>'
    '</ol></nav></body></html>';

const String _ncx =
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">'
    '<head/><docTitle><text>T</text></docTitle><navMap>'
    '<navPoint id="n1" playOrder="1"><navLabel><text>Do NCX</text></navLabel>'
    '<content src="Text/cap2.xhtml"/></navPoint>'
    '</navMap></ncx>';

const String _chapterItems =
    '<item id="c1" href="Text/Cap%C3%ADtulo%201.xhtml" '
    'media-type="application/xhtml+xml"/>'
    '<item id="c2" href="Text/cap2.xhtml" media-type="application/xhtml+xml"/>';
const String _spine = '<itemref idref="c1"/><itemref idref="c2"/>';

final Uint8List _coverBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1]);

/// EPUB 3 completo usado em vários testes.
Uint8List _fullEpub3() => buildEpub({
  'OEBPS/content.opf': opf3(
    title: 'Livro de Teste',
    identifier: _identifier,
    manifest:
        '$_chapterItems'
        '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" '
        'properties="nav"/>'
        '<item id="cover" href="Images/cover.png" media-type="image/png" '
        'properties="cover-image"/>',
    spine: _spine,
  ),
  _chapter1Name: _chapter1,
  'OEBPS/Text/cap2.xhtml': _chapter2,
  'OEBPS/nav.xhtml': _nav,
  'OEBPS/Images/cover.png': _coverBytes,
});

Uint8List _epub2WithNcx() => buildEpub({
  'OEBPS/content.opf': opf2(
    manifest:
        '$_chapterItems'
        '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>',
    spine: _spine,
    spineAttrs: 'toc="ncx"',
  ),
  _chapter1Name: _chapter1,
  'OEBPS/Text/cap2.xhtml': _chapter2,
  'OEBPS/toc.ncx': _ncx,
});

/// EPUB mínimo, sem navegação; [files] são acrescentados ao zip.
Uint8List _minimal({
  Map<String, Object> files = const {},
  String manifest = '',
  bool includeMimetype = true,
  String mimetype = 'application/epub+zip',
  bool mimetypeFirst = true,
  bool includeContainer = true,
}) => buildEpub(
  {
    'OEBPS/content.opf': opf3(
      identifier: _identifier,
      manifest:
          '<item id="c2" href="Text/cap2.xhtml" '
          'media-type="application/xhtml+xml"/>$manifest',
      spine: '<itemref idref="c2"/>',
    ),
    'OEBPS/Text/cap2.xhtml': _chapter2,
    ...files,
  },
  includeMimetype: includeMimetype,
  mimetype: mimetype,
  mimetypeFirst: mimetypeFirst,
  includeContainer: includeContainer,
);

String _encryptionXml(Map<String, String> uriToAlgorithm) =>
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container" '
    'xmlns:enc="http://www.w3.org/2001/04/xmlenc#">'
    '${uriToAlgorithm.entries.map((e) => '<enc:EncryptedData>'
        '<enc:EncryptionMethod Algorithm="${e.value}"/>'
        '<enc:CipherData><enc:CipherReference URI="${e.key}"/>'
        '</enc:CipherData></enc:EncryptedData>').join()}'
    '</encryption>';

Iterable<String> _codes(EpubBook book) => book.diagnostics.map((d) => d.code);

Diagnostic _diag(EpubBook book, String code) =>
    book.diagnostics.firstWhere((d) => d.code == code);

/// Fonte falsa de 2000 bytes, maior que as faixas ofuscadas.
final Uint8List _font = Uint8List.fromList([
  for (var i = 0; i < 2000; i++) (i * 31 + 7) & 0xFF,
]);

void main() {
  group('EPUB 3 completo', () {
    late EpubBook book;

    setUp(() async => book = await EpubBook.fromBytes(_fullEpub3()));
    tearDown(() => book.close());

    test('metadados, versão, pacote e rendition', () {
      expect(book.version, EpubVersion.epub3);
      expect(book.packagePath, 'OEBPS/content.opf');
      expect(book.metadata.titles, ['Livro de Teste']);
      expect(book.metadata.uniqueIdentifier, _identifier);
      expect(book.rendition.layout, RenditionLayout.reflowable);
      expect(book.manifest.keys, containsAll(['c1', 'c2', 'nav', 'cover']));
    });

    test('spine com 2 itens na ordem', () {
      expect(book.spine.items.map((s) => s.item.id), ['c1', 'c2']);
      expect(book.spine.items.first.item.path, _chapter1Name);
    });

    test('toc vem do nav.xhtml', () {
      expect(book.navigation.toc.map((p) => p.label), [
        'Capítulo 1',
        'Capítulo 2',
      ]);
      expect(book.navigation.toc.first.path, _chapter1Name);
      expect(_codes(book), isNot(contains(DiagnosticCodes.navFallbackToNcx)));
    });

    test('capa', () async {
      expect(book.cover?.id, 'cover');
      expect(await book.resource(book.cover!.path), _coverBytes);
    });

    test('resourceText de capítulo com nome acentuado e espaço', () async {
      expect(await book.resourceText(_chapter1Name), _chapter1);
    });

    test('manifestItemByPath', () {
      expect(book.manifestItemByPath(_chapter1Name)?.id, 'c1');
      expect(book.manifestItemByPath('OEBPS/nada.xhtml'), isNull);
    });

    test('abre sem diagnósticos de container', () {
      expect(book.diagnostics, isEmpty);
    });
  });

  test('EPUB 2: toc do NCX', () async {
    final book = await EpubBook.fromBytes(_epub2WithNcx());
    expect(book.version, EpubVersion.epub2);
    expect(book.navigation.toc.single.label, 'Do NCX');
    expect(book.navigation.toc.single.path, 'OEBPS/Text/cap2.xhtml');
    expect(_codes(book), isNot(contains(DiagnosticCodes.navMissing)));
    await book.close();
  });

  test('EPUB 3 com nav.xhtml quebrado e NCX: toc do NCX', () async {
    final book = await EpubBook.fromBytes(
      _minimal(
        manifest:
            '<item id="nav" href="nav.xhtml" '
            'media-type="application/xhtml+xml" properties="nav"/>'
            '<item id="ncx" href="toc.ncx" '
            'media-type="application/x-dtbncx+xml"/>',
        files: {'OEBPS/nav.xhtml': '<html><body', 'OEBPS/toc.ncx': _ncx},
      ),
    );
    expect(book.navigation.toc.single.label, 'Do NCX');
    final d = _diag(book, DiagnosticCodes.navFallbackToNcx);
    expect(d.severity, DiagnosticSeverity.info);
    await book.close();
  });

  test('sem navegação: EpubNavigation.empty + nav.missing', () async {
    final book = await EpubBook.fromBytes(_minimal());
    expect(book.navigation, same(EpubNavigation.empty));
    expect(
      _diag(book, DiagnosticCodes.navMissing).severity,
      DiagnosticSeverity.warning,
    );
    await book.close();
  });

  group('mimetype', () {
    test('ausente → abre com container.mimetypeMissing', () async {
      final book = await EpubBook.fromBytes(_minimal(includeMimetype: false));
      expect(_codes(book), contains(DiagnosticCodes.mimetypeMissing));
      expect(book.spine.items, hasLength(1));
      await book.close();
    });

    test('conteúdo errado → container.mimetypeInvalid', () async {
      final book = await EpubBook.fromBytes(
        _minimal(mimetype: 'application/zip'),
      );
      expect(_codes(book), contains(DiagnosticCodes.mimetypeInvalid));
      await book.close();
    });

    test('conteúdo com espaços nas pontas é aceito', () async {
      final book = await EpubBook.fromBytes(
        _minimal(mimetype: ' application/epub+zip\n'),
      );
      expect(_codes(book), isNot(contains(DiagnosticCodes.mimetypeInvalid)));
      await book.close();
    });

    test('fora da primeira posição → container.mimetypeNotFirst', () async {
      final book = await EpubBook.fromBytes(_minimal(mimetypeFirst: false));
      expect(
        _diag(book, DiagnosticCodes.mimetypeNotFirst).severity,
        DiagnosticSeverity.info,
      );
      expect(_codes(book), isNot(contains(DiagnosticCodes.mimetypeInvalid)));
      await book.close();
    });
  });

  test('sem container.xml: usa o primeiro .opf', () async {
    final book = await EpubBook.fromBytes(_minimal(includeContainer: false));
    expect(book.packagePath, 'OEBPS/content.opf');
    expect(_codes(book), contains(DiagnosticCodes.containerMissing));
    expect(book.spine.items.single.item.id, 'c2');
    await book.close();
  });

  group('recursos', () {
    test('caixa divergente → bytes + resource.caseMismatch', () async {
      final book = await EpubBook.fromBytes(
        _minimal(files: {'OEBPS/Images/Foto.PNG': _coverBytes}),
      );
      expect(await book.resource('OEBPS/images/foto.png'), _coverBytes);
      final d = _diag(book, DiagnosticCodes.resourceCaseMismatch);
      expect(d.location, 'OEBPS/images/foto.png');
      await book.close();
    });

    test('inexistente → ResourceNotFoundException', () async {
      final book = await EpubBook.fromBytes(_minimal());
      await expectLater(
        book.resource('OEBPS/nada.png'),
        throwsA(
          isA<ResourceNotFoundException>().having(
            (e) => e.path,
            'path',
            'OEBPS/nada.png',
          ),
        ),
      );
      await book.close();
    });

    test('item do spine sem arquivo continua no spine', () async {
      final book = await EpubBook.fromBytes(
        buildEpub({
          'OEBPS/content.opf': opf3(
            manifest:
                '<item id="c2" href="Text/cap2.xhtml" '
                'media-type="application/xhtml+xml"/>'
                '<item id="x" href="Text/sumiu.xhtml" '
                'media-type="application/xhtml+xml"/>',
            spine: '<itemref idref="c2"/><itemref idref="x"/>',
          ),
          'OEBPS/Text/cap2.xhtml': _chapter2,
        }),
      );
      expect(book.spine.items.map((s) => s.item.id), ['c2', 'x']);
      await expectLater(
        book.resource('OEBPS/Text/sumiu.xhtml'),
        throwsA(isA<ResourceNotFoundException>()),
      );
      await book.close();
    });

    test('diagnósticos são repassados ao sink do chamador', () async {
      final sink = CollectingDiagnosticSink();
      final book = await EpubBook.fromBytes(
        _minimal(
          includeMimetype: false,
          files: {'OEBPS/Images/Foto.PNG': _coverBytes},
        ),
        diagnostics: sink,
      );
      await book.resource('OEBPS/images/foto.png');
      expect(sink.diagnostics.map((d) => d.code), [
        DiagnosticCodes.mimetypeMissing,
        DiagnosticCodes.navMissing,
        DiagnosticCodes.resourceCaseMismatch,
      ]);
      expect(book.diagnostics, sink.diagnostics);
      expect(identical(book.diagnostics, book.diagnostics), isTrue);
      await book.close();
    });
  });

  group('fontes ofuscadas', () {
    test('IDPF: known-answer com XOR independente', () async {
      // Chave: SHA-1 do identificador sem espaços em branco.
      const spaced = ' urn:uuid:$_uuid \n';
      final key = sha1(utf8.encode(_identifier));
      final obfuscated = Uint8List.fromList(_font);
      for (var i = 0; i < 1040; i++) {
        obfuscated[i] ^= key[i % 20];
      }
      expect(obfuscated[1039], isNot(_font[1039]));
      expect(obfuscated[1040], _font[1040]);

      final book = await EpubBook.fromBytes(
        buildEpub({
          'META-INF/encryption.xml': _encryptionXml({
            'OEBPS/Fonts/A%20Fonte.otf': 'http://www.idpf.org/2008/embedding',
          }),
          'OEBPS/content.opf': opf3(
            identifier: spaced,
            manifest:
                '<item id="f" href="Fonts/A%20Fonte.otf" '
                'media-type="font/otf"/>',
          ),
          'OEBPS/Fonts/A Fonte.otf': obfuscated,
        }),
      );
      expect(await book.resource('OEBPS/Fonts/A Fonte.otf'), _font);
      await book.close();
    });

    test('Adobe: devolve a fonte original', () async {
      final key = [
        for (var i = 0; i < 32; i += 2)
          int.parse(_uuid.replaceAll('-', '').substring(i, i + 2), radix: 16),
      ];
      final obfuscated = Uint8List.fromList(_font);
      for (var i = 0; i < 1024; i++) {
        obfuscated[i] ^= key[i % 16];
      }
      expect(obfuscated[1024], _font[1024]);

      final book = await EpubBook.fromBytes(
        _minimal(
          manifest: '<item id="f" href="Fonts/a.ttf" media-type="font/ttf"/>',
          files: {
            'META-INF/encryption.xml': _encryptionXml({
              'OEBPS/Fonts/a.ttf': 'http://ns.adobe.com/pdf/enc#RC',
            }),
            'OEBPS/Fonts/a.ttf': obfuscated,
          },
        ),
      );
      expect(await book.resource('OEBPS/Fonts/a.ttf'), _font);
      await book.close();
    });

    test(
      'Adobe com UUID inválido → bytes crus + font.deobfuscationFailed',
      () async {
        final book = await EpubBook.fromBytes(
          buildEpub({
            'META-INF/encryption.xml': _encryptionXml({
              'OEBPS/Fonts/a.ttf': 'http://ns.adobe.com/pdf/enc#RC',
            }),
            'OEBPS/content.opf': opf3(identifier: 'isbn-não-é-uuid'),
            'OEBPS/Fonts/a.ttf': _font,
          }),
        );
        expect(await book.resource('OEBPS/Fonts/a.ttf'), _font);
        expect(
          _diag(book, DiagnosticCodes.fontDeobfuscationFailed).location,
          'OEBPS/Fonts/a.ttf',
        );
        await book.close();
      },
    );
  });

  group('DRM', () {
    test('encryption.xml com aes128-cbc → DrmProtectedException', () async {
      await expectLater(
        EpubBook.fromBytes(
          _minimal(
            files: {
              'META-INF/encryption.xml': _encryptionXml({
                'OEBPS/Text/cap2.xhtml':
                    'http://www.w3.org/2001/04/xmlenc#aes128-cbc',
              }),
            },
          ),
        ),
        throwsA(
          isA<DrmProtectedException>().having(
            (e) => e.algorithms,
            'algorithms',
            ['http://www.w3.org/2001/04/xmlenc#aes128-cbc'],
          ),
        ),
      );
    });

    test('META-INF/rights.xml → DrmProtectedException', () async {
      await expectLater(
        EpubBook.fromBytes(
          _minimal(files: {'META-INF/rights.xml': '<rights/>'}),
        ),
        throwsA(isA<DrmProtectedException>()),
      );
    });

    test('META-INF/license.lcpl → DrmProtectedException', () async {
      await expectLater(
        EpubBook.fromBytes(_minimal(files: {'META-INF/license.lcpl': '{}'})),
        throwsA(isA<DrmProtectedException>()),
      );
    });
  });

  group('erros fatais', () {
    test('bytes aleatórios → NotAnEpubException', () async {
      final bytes = Uint8List.fromList([
        for (var i = 0; i < 4096; i++) (i * 131 + 17) & 0x7F,
      ]);
      await expectLater(
        EpubBook.fromBytes(bytes),
        throwsA(isA<NotAnEpubException>()),
      );
    });

    test('zip sem OPF → MissingPackageDocumentException', () async {
      await expectLater(
        EpubBook.fromBytes(
          buildEpub({'OEBPS/a.txt': 'x'}, includeContainer: false),
        ),
        throwsA(isA<MissingPackageDocumentException>()),
      );
    });

    test('container.xml aponta para OPF inexistente e não há outro', () async {
      await expectLater(
        EpubBook.fromBytes(
          buildEpub({'OEBPS/a.txt': 'x'}, opfPath: 'OEBPS/nada.opf'),
        ),
        throwsA(isA<MissingPackageDocumentException>()),
      );
    });

    test('OPF malformado → MissingPackageDocumentException', () async {
      await expectLater(
        EpubBook.fromBytes(buildEpub({'OEBPS/content.opf': '<package'})),
        throwsA(isA<MissingPackageDocumentException>()),
      );
    });
  });

  group('arquivo em disco', () {
    late Directory dir;
    late String path;

    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('galley_epub_book_');
      path = '${dir.path}/livro.epub';
      await File(path).writeAsBytes(_fullEpub3());
    });

    tearDownAll(() => dir.delete(recursive: true));

    test('open(path) equivale a fromBytes', () async {
      final fromFile = await EpubBook.open(path);
      final fromMemory = await EpubBook.fromBytes(_fullEpub3());
      expect(fromFile.packagePath, fromMemory.packagePath);
      expect(fromFile.metadata.titles, fromMemory.metadata.titles);
      expect(
        fromFile.spine.items.map((s) => s.item.path),
        fromMemory.spine.items.map((s) => s.item.path),
      );
      expect(
        fromFile.navigation.toc.map((p) => p.label),
        fromMemory.navigation.toc.map((p) => p.label),
      );
      expect(
        await fromFile.resourceText(_chapter1Name),
        await fromMemory.resourceText(_chapter1Name),
      );
      expect(fromFile.diagnostics, fromMemory.diagnostics);
      await fromFile.close();
      await fromMemory.close();
    });

    test('arquivo inexistente → NotAnEpubException', () async {
      await expectLater(
        EpubBook.open('${dir.path}/nao-existe.epub'),
        throwsA(isA<NotAnEpubException>()),
      );
    });

    test('arquivo em disco que não é zip → NotAnEpubException', () async {
      final bad = '${dir.path}/ruim.epub';
      await File(bad).writeAsString(
        'não sou um zip, mas sou grande o '
        'bastante para passar do tamanho mínimo de um EOCD.',
      );
      await expectLater(EpubBook.open(bad), throwsA(isA<NotAnEpubException>()));
    });

    test(
      'resource após close → BookClosedException; close idempotente',
      () async {
        final book = await EpubBook.open(path);
        await book.close();
        await book.close();
        await expectLater(
          book.resource(_chapter1Name),
          throwsA(isA<BookClosedException>()),
        );
        await expectLater(
          book.resourceText(_chapter1Name),
          throwsA(isA<BookClosedException>()),
        );
      },
    );
  });

  group('close e leituras concorrentes', () {
    test(
      'close que falha com FileSystemException vira '
      'CorruptArchiveException; livro fica fechado e close é idempotente',
      () async {
        final source = _FlakySource(MemoryByteSource(_fullEpub3()))
          ..closeFails = true;
        final book = await EpubBook.fromSource(source);
        await expectLater(
          book.close(),
          throwsA(isA<CorruptArchiveException>()),
        );
        await book.close();
        expect(source.closeCalls, 1);
        await expectLater(
          book.resource(_chapter1Name),
          throwsA(isA<BookClosedException>()),
        );
      },
    );

    test('resource em andamento durante close → BookClosedException', () async {
      final source = _FlakySource(MemoryByteSource(_fullEpub3()));
      final book = await EpubBook.fromSource(source);
      final results = <Future<Object?>>[
        for (var i = 0; i < 8; i++) book.resource(_chapter1Name),
        book.resourceText(_chapter1Name),
      ].map((f) => f.then<Object?>((v) => v, onError: (Object e) => e));
      final closing = book.close();
      final outcomes = await Future.wait(results);
      await closing;
      expect(outcomes, isNotEmpty);
      for (final o in outcomes) {
        expect(
          o is Uint8List || o is String || o is BookClosedException,
          true,
          reason: 'recebeu $o',
        );
      }
      expect(outcomes.whereType<BookClosedException>(), isNotEmpty);
    });
  });

  test(
    'mimetype com cabeçalho local ilegível → diagnóstico, abre mesmo assim',
    () async {
      final bytes = _minimal();
      // mimetype é a primeira entrada: zera a assinatura do cabeçalho local.
      ByteData.sublistView(bytes).setUint32(0, 0, Endian.little);
      final book = await EpubBook.fromBytes(bytes);
      final d = _diag(book, DiagnosticCodes.mimetypeInvalid);
      expect(d.severity, DiagnosticSeverity.warning);
      expect(d.message, contains('ler'));
      expect(book.spine.items, hasLength(1));
      await book.close();
    },
  );
}

/// Fonte que lê de forma assíncrona e falha após fechada (como um arquivo).
class _FlakySource implements ByteSource {
  _FlakySource(this.inner);

  final ByteSource inner;
  bool closeFails = false;
  bool closed = false;
  int closeCalls = 0;

  @override
  int get length => inner.length;

  @override
  Future<Uint8List> read(int offset, int length) async {
    await Future<void>.delayed(Duration.zero);
    if (closed) throw const FileSystemException('arquivo fechado');
    return inner.read(offset, length);
  }

  @override
  Future<void> close() async {
    closeCalls++;
    closed = true;
    if (closeFails) throw const FileSystemException('falha no close');
  }
}
