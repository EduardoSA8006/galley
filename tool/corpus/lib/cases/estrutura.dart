import 'dart:convert';

import '../corpus_case.dart';
import '../epub_builder.dart';
import 'common.dart';

const _group = 'estrutura';

List<CorpusCase> estruturaCases() => [
      CorpusCase(
        group: _group,
        slug: 'capitulo-200k-palavras',
        readme: 'Um capítulo de ~200 mil palavras: paginação incremental e agendador precisam lidar com uma seção gigante.',
        build: () {
          final b = EpubBuilder(slug: 'capitulo-200k-palavras', title: 'Capítulo gigante');
          final prose = proseFor('capitulo-200k-palavras');
          final r = b.addChapter(
            'cap01.xhtml',
            xhtml(title: 'Capítulo gigante', body: '<h1>Capítulo gigante</h1>\n${prose.paragraphsForWords(200000)}'),
          );
          b.chapterInSpineAndToc(r, 'Capítulo gigante');
          return b.build();
        },
      ),
      CorpusCase(
        group: _group,
        slug: 'capitulo-3-palavras',
        readme: 'Capítulo com três palavras entre dois capítulos normais: página quase vazia e progresso por caracteres.',
        build: () {
          final b = standardBook('capitulo-3-palavras', chapters: 2);
          final r = b.addChapter('curto.xhtml', xhtml(title: 'Curto', body: '<p>Só três palavras.</p>'), id: 'curto');
          b.spine.insert(1, const SpineRef('curto'));
          b.toc.insert(1, TocEntry('Curto', b.hrefOf(r)));
          return b.build();
        },
      ),
      CorpusCase(
        group: _group,
        slug: 'spine-800-itens',
        readme: 'Spine com 800 seções minúsculas: central directory grande, fila do worker e TOC longos.',
        build: () {
          final b = EpubBuilder(slug: 'spine-800-itens', title: 'Oitocentas seções');
          final prose = proseFor('spine-800-itens');
          for (var i = 1; i <= 800; i++) {
            final r = b.addChapter(
              's${i.toString().padLeft(3, '0')}.xhtml',
              xhtml(title: 'Seção $i', body: '<h2>Seção $i</h2><p>${prose.sentence()}</p>'),
            );
            b.chapterInSpineAndToc(r, 'Seção $i');
          }
          return b.build();
        },
      ),
      CorpusCase(
        group: _group,
        slug: 'toc-6-niveis',
        readme: 'TOC aninhado em seis níveis apontando para `h1`–`h6` com ids no mesmo capítulo.',
        build: () {
          final b = EpubBuilder(slug: 'toc-6-niveis', title: 'Seis níveis');
          final prose = proseFor('toc-6-niveis');
          final body = StringBuffer();
          for (var level = 1; level <= 6; level++) {
            body.writeln('<h$level id="n$level">Nível $level</h$level>');
            body.writeln(prose.paragraphs(2));
          }
          final r = b.addChapter('cap01.xhtml', xhtml(title: 'Seis níveis', body: body.toString()));
          b.spine.add(SpineRef(r.id));
          final href = b.hrefOf(r);
          TocEntry nest(int level) => TocEntry(
                'Nível $level',
                '$href#n$level',
                children: level == 6 ? const [] : [nest(level + 1)],
              );
          b.toc = [nest(1)];
          return b.build();
        },
      ),
      CorpusCase(
        group: _group,
        slug: 'page-list-tres-fontes',
        readme: 'Números de página impressa em três fontes: `page-list` no NAV, `pageList` no NCX e `epub:type="pagebreak"` no corpo.',
        build: () {
          final b = EpubBuilder(slug: 'page-list-tres-fontes', title: 'Páginas impressas');
          final prose = proseFor('page-list-tres-fontes');
          final body = StringBuffer('<h1>Páginas impressas</h1>');
          for (var page = 1; page <= 12; page++) {
            body.writeln('<span epub:type="pagebreak" role="doc-pagebreak" id="pg$page" title="$page"/>');
            body.writeln(prose.paragraphs(3));
          }
          final r = b.addChapter('cap01.xhtml', xhtml(title: 'Páginas impressas', body: body.toString()));
          b.chapterInSpineAndToc(r, 'Páginas impressas');
          final marks = List.generate(12, (i) => PageMark('${i + 1}', '${b.hrefOf(r)}#pg${i + 1}'));
          b.navPageList = marks;
          b.ncxPageList = marks;
          return b.build();
        },
      ),
      CorpusCase(
        group: _group,
        slug: 'opf-em-subpasta',
        readme: 'OPF em `OEBPS/content/` e recursos em `OEBPS/Text/`: hrefs do manifest começam com `../`.',
        build: () {
          final b = EpubBuilder(slug: 'opf-em-subpasta', opfDir: 'OEBPS/content');
          final prose = proseFor('opf-em-subpasta');
          for (var i = 1; i <= 3; i++) {
            final r = b.addChapter(
              'cap0$i.xhtml',
              xhtml(title: 'Capítulo $i', body: '<h1>Capítulo $i</h1>${prose.paragraphs(4)}'),
              path: 'OEBPS/Text/cap0$i.xhtml',
            );
            b.chapterInSpineAndToc(r, 'Capítulo $i');
          }
          return b.build();
        },
      ),
      CorpusCase(
        group: _group,
        slug: 'linear-no',
        readme: 'Seção de notas com `linear="no"`: fica fora de next/prev mas é alvo de link e conta no progresso.',
        build: () {
          final b = standardBook('linear-no', chapters: 2);
          final notes = b.addChapter(
            'notas.xhtml',
            xhtml(title: 'Notas', body: '<h1>Notas</h1><p id="n1">1. Primeira nota.</p><p id="n2">2. Segunda nota.</p>'),
            id: 'notas',
          );
          b.spine.add(const SpineRef('notas', linear: false));
          b.toc.add(TocEntry('Notas', b.hrefOf(notes)));
          final first = b.resources.first;
          b.resources[0] = EpubResource(
            path: first.path,
            bytes: utf8.encode(xhtml(
              title: 'Capítulo 1',
              body: '<h1>Capítulo 1</h1><p>Texto com chamada de nota<a href="notas.xhtml#n1" epub:type="noteref">1</a>.</p>',
            )),
            mediaType: first.mediaType,
            id: first.id,
          );
          return b.build();
        },
      ),
      CorpusCase(
        group: _group,
        slug: 'nav-ncx-divergentes',
        readme: 'NAV e NCX coexistem com títulos e cobertura diferentes: o NAV deve vencer.',
        build: () {
          final b = standardBook('nav-ncx-divergentes', chapters: 4);
          b.ncxToc = [
            TocEntry('Título antigo 1', b.toc[0].href),
            TocEntry('Título antigo 3', b.toc[2].href),
          ];
          return b.build();
        },
      ),
    ];
