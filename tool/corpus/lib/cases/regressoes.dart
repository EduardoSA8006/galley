import 'dart:convert';
import 'dart:typed_data';

import '../corpus_case.dart';
import '../epub_builder.dart';
import '../png.dart';
import 'common.dart';

const _group = 'regressoes';

List<CorpusCase> regressoesCases() => [
  CorpusCase(
    group: _group,
    slug: 'href-barra-invertida',
    readme: 'Manifest com href `Text\\cap01.xhtml` (separador do Windows) que precisa ser normalizado para `/`.',
    build: () {
      final b = standardBook('href-barra-invertida', chapters: 2);
      final first = b.resources.first;
      b.resources[0] = EpubResource(
        path: first.path,
        bytes: first.bytes,
        mediaType: first.mediaType,
        id: first.id,
        manifestHrefOverride: r'Text\cap01.xhtml',
      );
      return b.build();
    },
  ),
  CorpusCase(
    group: _group,
    slug: 'href-url-encoded',
    readme: 'Arquivo `Text/capítulo 1.xhtml` no ZIP e href `Text/cap%C3%ADtulo%201.xhtml` no manifest: precisa de tentativa dupla (cru e decodificado).',
    build: () {
      final b = EpubBuilder(slug: 'href-url-encoded');
      final prose = proseFor('href-url-encoded');
      final r = b.addChapter(
        'capítulo 1.xhtml',
        xhtml(
          title: 'Capítulo 1',
          body: '<h1>Capítulo 1</h1>${prose.paragraphs(4)}',
        ),
        id: 'cap1',
      );
      b.resources[0] = EpubResource(
        path: r.path,
        bytes: r.bytes,
        mediaType: r.mediaType,
        id: r.id,
        manifestHrefOverride: 'Text/cap%C3%ADtulo%201.xhtml',
      );
      b.spine.add(const SpineRef('cap1'));
      b.toc = [const TocEntry('Capítulo 1', 'Text/cap%C3%ADtulo%201.xhtml')];
      return b.build();
    },
  ),
  CorpusCase(
    group: _group,
    slug: 'encoding-latin1-declarado-utf8',
    readme: 'XHTML em ISO-8859-1 com declaração `encoding="UTF-8"`: bytes inválidos em UTF-8 devem cair na heurística sem derrubar a seção.',
    diagnostics: ['encodingFallback'],
    build: () {
      final b = EpubBuilder(slug: 'encoding-latin1-declarado-utf8');
      final source = xhtml(
        title: 'Acentuação',
        body:
            '<h1>Acentuação</h1><p>Coração, ação, Ávila, pêssego, açúcar, órgão, não, até.</p>'
            '<p>Este parágrafo só tem sentido se a decodificação recuperar os acentos.</p>',
      );
      final r = b.addChapter(
        'cap01.xhtml',
        source,
        bytes: latin1.encode(source),
      );
      b.chapterInSpineAndToc(r, 'Acentuação');
      return b.build();
    },
  ),
  CorpusCase(
    group: _group,
    slug: 'encoding-shift-jis',
    readme: 'XHTML em Shift_JIS sem declaração XML, só `<meta charset>`: exercita a ordem BOM → XML → meta.',
    build: () {
      final b = EpubBuilder(
        slug: 'encoding-shift-jis',
        language: 'ja',
        title: 'テスト',
      );
      // 日本語のテスト em Shift_JIS.
      const nihongo = [
        0x93,
        0xFA,
        0x96,
        0x7B,
        0x8C,
        0xEA,
        0x82,
        0xCC,
        0x83,
        0x65,
        0x83,
        0x58,
        0x83,
        0x67,
      ];
      final head = ascii.encode(
        '<html xmlns="http://www.w3.org/1999/xhtml" lang="ja" xml:lang="ja"><head>'
        '<meta http-equiv="Content-Type" content="text/html; charset=Shift_JIS"/>'
        '<title>Test</title></head><body><h1>',
      );
      final mid = ascii.encode('</h1><p>');
      final tail = ascii.encode('</p></body></html>');
      final bytes = Uint8List.fromList([
        ...head,
        ...nihongo,
        ...mid,
        ...nihongo,
        ...tail,
      ]);
      final r = b.addChapter('cap01.xhtml', '', bytes: bytes);
      b.chapterInSpineAndToc(r, 'テスト');
      return b.build();
    },
  ),
  CorpusCase(
    group: _group,
    slug: 'encoding-bom-utf8-declarado-latin1',
    readme: 'BOM UTF-8 seguido de declaração `encoding="ISO-8859-1"`: o BOM vence a declaração.',
    build: () {
      final b = EpubBuilder(slug: 'encoding-bom-utf8-declarado-latin1');
      final source = xhtml(
        title: 'BOM',
        xmlEncoding: 'ISO-8859-1',
        body: '<h1>BOM</h1><p>Texto com acentuação em UTF-8: coração, ação, Ávila — e um travessão.</p>',
      );
      final r = b.addChapter(
        'cap01.xhtml',
        source,
        bytes: [0xEF, 0xBB, 0xBF, ...utf8.encode(source)],
      );
      b.chapterInSpineAndToc(r, 'BOM');
      return b.build();
    },
  ),
  CorpusCase(
    group: _group,
    slug: 'ncx-incompleto-orfaos',
    readme: 'Seis capítulos no spine, NCX cobrindo só 1, 3 e 5, sem NAV: órfãos entram no TOC na posição da ordem de leitura.',
    diagnostics: ['tocReconciled'],
    build: () {
      final b = standardBook('ncx-incompleto-orfaos', chapters: 6)
        ..includeNav = false;
      b.toc = [b.toc[0], b.toc[2], b.toc[4]];
      return b.build();
    },
  ),
  CorpusCase(
    group: _group,
    slug: 'capa-ausente',
    readme: '`<meta name="cover">` e item de manifest apontando para `Images/cover.png` que não existe no ZIP.',
    diagnostics: ['resourceMissing'],
    build: () {
      final b = standardBook('capa-ausente', chapters: 2);
      b.resources.add(
        EpubResource(
          path: 'OEBPS/Images/cover.png',
          bytes: const [],
          mediaType: 'image/png',
          id: 'cover-img',
          inZip: false,
        ),
      );
      b.coverId = 'cover-img';
      b.epub2CoverMeta = true;
      return b.build();
    },
  ),
  CorpusCase(
    group: _group,
    slug: 'ancora-autofechada',
    readme: '`<a id="nota1"/>` auto-fechado antes de texto: o parser HTML5 não pode engolir o texto seguinte dentro da âncora.',
    build: () {
      const body =
          '<h1>Âncoras</h1>'
          '<p><a id="nota1"/>Texto imediatamente após a âncora auto-fechada, que deve ficar fora dela.</p>'
          '<p>Segundo parágrafo, com <a href="#nota1">link de volta para a âncora</a>.</p>'
          '<p><span id="vazio"></span>Span vazio com id antes de texto.</p>';
      return singleChapterBook(
        'ancora-autofechada',
        body,
        title: 'Âncoras',
      ).build();
    },
  ),
  CorpusCase(
    group: _group,
    slug: 'spine-so-imagem',
    readme: 'Item do spine com media-type `image/png` (sem XHTML): vira seção com um único bloco `object`.',
    build: () {
      final b = standardBook('spine-so-imagem', chapters: 2);
      final img = b.addImage(
        'pagina.png',
        png(120, 160, seed: 7),
        id: 'pagina',
      );
      b.spine.insert(1, const SpineRef('pagina'));
      b.toc.insert(1, TocEntry('Ilustração', b.hrefOf(img)));
      return b.build();
    },
  ),
  CorpusCase(
    group: _group,
    slug: 'text-align-inline-span',
    readme: '`text-align: center` em `<span>` inline (regressão histórica de altura zero em flutter_html).',
    build: () {
      final prose = proseFor('text-align-inline-span');
      final body =
          '<h1>Alinhamento inline</h1>'
          '<p><span style="text-align: center">${prose.sentence()}</span> ${prose.sentence()}</p>'
          '<p class="c"><span class="c">${prose.sentence()}</span></p>'
          '${prose.paragraphs(3)}';
      return singleChapterBook(
        'text-align-inline-span',
        body,
        css: 'span.c { text-align: center; }',
      ).build();
    },
  ),
];
