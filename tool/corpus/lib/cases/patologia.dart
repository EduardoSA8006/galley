import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../corpus_case.dart';
import '../epub_builder.dart';
import 'common.dart';

const _group = 'patologia';

const _idpfAlgorithm = 'http://www.idpf.org/2008/embedding';
const _adobeAlgorithm = 'http://ns.adobe.com/pdf/enc#RC';

String _encryptionXml(String algorithm, String uri, {String? keyInfo}) => '''
<?xml version="1.0" encoding="UTF-8"?>
<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container" xmlns:enc="http://www.w3.org/2001/04/xmlenc#">
  <enc:EncryptedData>
    <enc:EncryptionMethod Algorithm="$algorithm"/>
${keyInfo ?? ''}    <enc:CipherData>
      <enc:CipherReference URI="$uri"/>
    </enc:CipherData>
  </enc:EncryptedData>
</encryption>
''';

/// XOR dos primeiros [prefix] bytes com a chave repetida (IDPF: 1040, Adobe: 1024).
Uint8List obfuscate(List<int> font, List<int> key, int prefix) {
  final out = Uint8List.fromList(font);
  final n = min(prefix, out.length);
  for (var i = 0; i < n; i++) {
    out[i] ^= key[i % key.length];
  }
  return out;
}

/// Livro com uma fonte embutida em `OEBPS/Fonts/`, referenciada por `@font-face`.
EpubBuilder _bookWithFont(String slug, List<int> fontBytes) {
  final b = EpubBuilder(slug: slug, title: 'Fonte embutida');
  final prose = proseFor(slug);
  b.resources.add(EpubResource(
    path: 'OEBPS/Fonts/NotoSansOgham-Regular.ttf',
    bytes: fontBytes,
    mediaType: 'font/ttf',
    id: 'fonte',
  ));
  b.addCss('estilo.css', '@font-face { font-family: "Ogham"; src: url(../Fonts/NotoSansOgham-Regular.ttf); }\n.ogham { font-family: "Ogham"; }\n');
  final r = b.addChapter(
    'cap01.xhtml',
    xhtml(
      title: 'Fonte embutida',
      cssHrefs: const ['../Styles/estilo.css'],
      body: '<h1>Fonte embutida</h1><p class="ogham">ᚐᚑᚒᚓᚔ ᚁᚂᚃᚄᚅ</p>${prose.paragraphs(3)}',
    ),
  );
  b.chapterInSpineAndToc(r, 'Fonte embutida');
  return b;
}

List<CorpusCase> patologiaCases(Uint8List fontBytes) => [
      CorpusCase(
        group: _group,
        slug: 'mimetype-comprimido',
        readme: 'Entrada `mimetype` em deflate em vez de stored: violação da OCF que muitos arquivos reais cometem; seguir com diagnóstico.',
        diagnostics: ['mimetypeIrregular'],
        build: () => (standardBook('mimetype-comprimido', chapters: 2)..mimetypeCompressed = true).build(),
      ),
      CorpusCase(
        group: _group,
        slug: 'mimetype-fora-de-ordem',
        readme: 'Entrada `mimetype` como última do ZIP em vez de primeira: seguir com diagnóstico.',
        diagnostics: ['mimetypeIrregular'],
        build: () => (standardBook('mimetype-fora-de-ordem', chapters: 2)..mimetypeFirst = false).build(),
      ),
      CorpusCase(
        group: _group,
        slug: 'zip64',
        readme: 'ZIP64 real (EOCD64 + locator, tamanhos e offsets 0xFFFFFFFF com extra 0x0001) em arquivo pequeno: o leitor de central directory precisa seguir o locator.',
        build: () => (standardBook('zip64', chapters: 3)..forceZip64 = true).build(),
      ),
      CorpusCase(
        group: _group,
        slug: 'fonte-ofuscada-idpf',
        readme: 'Fonte com ofuscação IDPF (`encryption.xml`, XOR de 1040 bytes com SHA-1 do identificador): desofuscar e carregar.',
        build: () {
          final b = _bookWithFont('fonte-ofuscada-idpf', const []);
          b.resources[0] = EpubResource(
            path: b.resources[0].path,
            bytes: obfuscate(fontBytes, b.idpfKey, 1040),
            mediaType: 'font/ttf',
            id: 'fonte',
          );
          b.extraFiles['META-INF/encryption.xml'] =
              utf8.encode(_encryptionXml(_idpfAlgorithm, 'OEBPS/Fonts/NotoSansOgham-Regular.ttf'));
          return b.build();
        },
      ),
      CorpusCase(
        group: _group,
        slug: 'fonte-ofuscada-adobe',
        readme: 'Fonte com ofuscação Adobe (XOR de 1024 bytes com os 16 bytes do UUID do identificador): desofuscar e carregar.',
        build: () {
          final b = _bookWithFont('fonte-ofuscada-adobe', const []);
          b.resources[0] = EpubResource(
            path: b.resources[0].path,
            bytes: obfuscate(fontBytes, b.adobeKey, 1024),
            mediaType: 'font/ttf',
            id: 'fonte',
          );
          b.extraFiles['META-INF/encryption.xml'] =
              utf8.encode(_encryptionXml(_adobeAlgorithm, 'OEBPS/Fonts/NotoSansOgham-Regular.ttf'));
          return b.build();
        },
      ),
      CorpusCase(
        group: _group,
        slug: 'ofuscacao-desconhecida',
        readme: '`encryption.xml` com algoritmo desconhecido aplicado só a uma fonte: fonte ignorada, texto com fallback, não é fatal.',
        diagnostics: ['fontObfuscationUnknown'],
        build: () {
          final b = _bookWithFont('ofuscacao-desconhecida', const []);
          b.resources[0] = EpubResource(
            path: b.resources[0].path,
            bytes: obfuscate(fontBytes, const [0x5A, 0xA5, 0x3C], 2048),
            mediaType: 'font/ttf',
            id: 'fonte',
          );
          b.extraFiles['META-INF/encryption.xml'] =
              utf8.encode(_encryptionXml('http://example.com/2026/obfuscation#xor3', 'OEBPS/Fonts/NotoSansOgham-Regular.ttf'));
          return b.build();
        },
      ),
      CorpusCase(
        group: _group,
        slug: 'drm-lcp',
        readme: 'Readium LCP: `encryption.xml` com AES-256-CBC sobre o XHTML e `META-INF/license.lcpl`: fatal, com o esquema `lcp` na mensagem.',
        exception: 'EpubEncryptedException',
        build: () {
          final b = standardBook('drm-lcp', chapters: 2);
          final rng = Random(seedFor('drm-lcp'));
          for (var i = 0; i < b.resources.length; i++) {
            final r = b.resources[i];
            final padded = ((r.bytes.length ~/ 16) + 2) * 16; // IV + blocos
            b.resources[i] = EpubResource(
              path: r.path,
              bytes: List<int>.generate(padded, (_) => rng.nextInt(256)),
              mediaType: r.mediaType,
              id: r.id,
            );
          }
          const keyInfo = '    <ds:KeyInfo xmlns:ds="http://www.w3.org/2000/09/xmldsig#">\n'
              '      <ds:RetrievalMethod URI="license.lcpl#/encryption/content_key" Type="http://readium.org/2014/01/lcp#EncryptedContentKey"/>\n'
              '    </ds:KeyInfo>\n';
          final entries = b.resources
              .map((r) => '''
  <enc:EncryptedData>
    <enc:EncryptionMethod Algorithm="http://www.w3.org/2001/04/xmlenc#aes256-cbc"/>
$keyInfo    <enc:CipherData>
      <enc:CipherReference URI="${r.path}"/>
    </enc:CipherData>
  </enc:EncryptedData>''')
              .join('\n');
          b.extraFiles['META-INF/encryption.xml'] = utf8.encode('''
<?xml version="1.0" encoding="UTF-8"?>
<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container" xmlns:enc="http://www.w3.org/2001/04/xmlenc#">
$entries
</encryption>
''');
          b.extraFiles['META-INF/license.lcpl'] = utf8.encode(jsonEncode({
            'provider': 'https://example.com',
            'id': b.identifier,
            'issued': '2026-01-01T00:00:00Z',
            'encryption': {
              'profile': 'http://readium.org/lcp/basic-profile',
              'content_key': {
                'algorithm': 'http://www.w3.org/2001/04/xmlenc#aes256-cbc',
                'encrypted_value': base64Encode(List<int>.generate(64, (_) => rng.nextInt(256))),
              },
              'user_key': {
                'algorithm': 'http://www.w3.org/2001/04/xmlenc#sha256',
                'text_hint': 'Corpus sintético; não há chave.',
                'key_check': base64Encode(List<int>.generate(64, (_) => rng.nextInt(256))),
              },
            },
            'links': [
              {'rel': 'hint', 'href': 'https://example.com/hint', 'type': 'text/html'},
            ],
          }));
          return b.build();
        },
      ),
      CorpusCase(
        group: _group,
        slug: 'opf-sem-spine',
        readme: 'OPF válido em XML mas com `<spine/>` vazio: fatal.',
        exception: 'EpubPackageException',
        build: () {
          final b = standardBook('opf-sem-spine', chapters: 2);
          b.opfOverride = '''
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="pub-id">${b.identifier}</dc:identifier>
    <dc:title>Sem spine</dc:title>
    <dc:language>pt-BR</dc:language>
    <meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="${b.resources[0].id}" href="${b.hrefOf(b.resources[0])}" media-type="application/xhtml+xml"/>
  </manifest>
  <spine/>
</package>
''';
          return b.build();
        },
      ),
      CorpusCase(
        group: _group,
        slug: 'arquivo-truncado',
        readme: 'EPUB cortado a 60% no meio dos dados de uma entrada: sem central directory nem EOCD; fatal.',
        exception: 'EpubContainerException',
        build: () {
          final full = standardBook('arquivo-truncado', chapters: 4, wordsPerChapter: 2000).build();
          return Uint8List.sublistView(full, 0, (full.length * 0.6).floor());
        },
      ),
      CorpusCase(
        group: _group,
        slug: 'crc-errado',
        readme: 'Entrada com CRC-32 errado no header: em produção vira diagnóstico, em `strict` é verificado.',
        diagnostics: ['zipCrcMismatch'],
        build: () {
          final b = standardBook('crc-errado', chapters: 2);
          final r = b.resources[1];
          b.resources[1] = EpubResource(
            path: r.path,
            bytes: r.bytes,
            mediaType: r.mediaType,
            id: r.id,
            crcOverride: 0xDEADBEEF,
          );
          return b.build();
        },
      ),
      CorpusCase(
        group: _group,
        slug: 'secao-3mb',
        readme: 'Uma seção XHTML com mais de 3 MB: parse fatiado com prioridade reduzida e diagnóstico.',
        diagnostics: ['sectionTooLarge'],
        build: () {
          final b = EpubBuilder(slug: 'secao-3mb', title: 'Seção enorme');
          final prose = proseFor('secao-3mb');
          final body = StringBuffer('<h1>Seção enorme</h1>\n');
          while (body.length < 3 * 1024 * 1024 + 64 * 1024) {
            body.writeln(prose.paragraphs(50));
          }
          final r = b.addChapter('cap01.xhtml', xhtml(title: 'Seção enorme', body: body.toString()));
          b.chapterInSpineAndToc(r, 'Seção enorme');
          return b.build();
        },
      ),
    ];
