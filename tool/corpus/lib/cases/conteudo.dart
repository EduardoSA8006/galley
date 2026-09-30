import '../corpus_case.dart';
import '../epub_builder.dart';
import '../png.dart';
import 'common.dart';

const _group = 'conteudo';

String _cells(String tag, int n, String Function(int) text) =>
    List.generate(n, (i) => '<$tag>${text(i)}</$tag>').join();

List<CorpusCase> conteudoCases() => [
  CorpusCase(
    group: _group,
    slug: 'tabela-colspan-larga',
    readme: 'Tabela de 10 colunas com `colspan` no cabeçalho e em células do corpo, mais larga que uma coluna de 360 px.',
    build: () {
      final rows = StringBuffer();
      rows.writeln(
        '<tr><th colspan="3">Identificação</th><th colspan="4">Medidas trimestrais</th><th colspan="3">Totais acumulados</th></tr>',
      );
      rows.writeln('<tr>${_cells('th', 10, (i) => 'Col ${i + 1}')}</tr>');
      for (var r = 0; r < 8; r++) {
        rows.writeln(
          r == 3
              ? '<tr><td colspan="2">Subtotal parcial</td>${_cells('td', 8, (i) => '${(r + 1) * (i + 1) * 13}')}</tr>'
              : '<tr>${_cells('td', 10, (i) => 'Valor ${r + 1}.${i + 1}')}</tr>',
        );
      }
      final body =
          '<h1>Tabela larga</h1><p>Antes da tabela.</p><table>$rows</table><p>Depois da tabela.</p>';
      return singleChapterBook(
        'tabela-colspan-larga',
        body,
        title: 'Tabela larga',
      ).build();
    },
  ),
  CorpusCase(
    group: _group,
    slug: 'tabela-aninhada',
    readme: 'Tabela com uma segunda tabela dentro de uma célula e células com dois parágrafos.',
    build: () {
      const inner =
          '<table><tr><td>a</td><td>b</td></tr><tr><td>c</td><td>d</td></tr></table>';
      const body =
          '<h1>Tabela aninhada</h1>'
          '<table><tr><th>Chave</th><th>Valor</th></tr>'
          '<tr><td>Simples</td><td>Um valor</td></tr>'
          '<tr><td>Aninhada</td><td>$inner</td></tr>'
          '<tr><td>Dois parágrafos</td><td><p>Primeiro parágrafo da célula.</p><p>Segundo parágrafo da célula.</p></td></tr>'
          '</table>';
      return singleChapterBook(
        'tabela-aninhada',
        body,
        title: 'Tabela aninhada',
      ).build();
    },
  ),
  CorpusCase(
    group: _group,
    slug: 'tabela-thead-60-linhas',
    readme: 'Tabela com `thead` e 60 linhas em `tbody`: atravessa páginas e o cabeçalho deve repetir.',
    build: () {
      final rows = List.generate(
        60,
        (i) =>
            '<tr><td>${i + 1}</td><td>Item ${i + 1}</td><td>${(i + 1) * 7}</td></tr>',
      ).join('\n');
      final body =
          '<h1>Sessenta linhas</h1><table><thead><tr><th>#</th><th>Nome</th><th>Valor</th></tr></thead><tbody>$rows</tbody></table>';
      return singleChapterBook(
        'tabela-thead-60-linhas',
        body,
        title: 'Sessenta linhas',
      ).build();
    },
  ),
  CorpusCase(
    group: _group,
    slug: 'lista-5-niveis',
    readme: 'Lista não ordenada aninhada em cinco níveis, com marcadores disc, circle e square por CSS.',
    build: () {
      String nest(int level) => level > 5
          ? ''
          : '<ul class="l$level"><li>Nível $level, item 1${nest(level + 1)}</li><li>Nível $level, item 2</li></ul>';
      final body = '<h1>Cinco níveis</h1>${nest(1)}';
      const css =
          'ul.l1{list-style-type:disc} ul.l2{list-style-type:circle} ul.l3{list-style-type:square} ul.l4{list-style-type:disc} ul.l5{list-style-type:none}';
      return singleChapterBook(
        'lista-5-niveis',
        body,
        title: 'Cinco níveis',
        css: css,
      ).build();
    },
  ),
  CorpusCase(
    group: _group,
    slug: 'ol-start-reversed',
    readme: '`<ol start="7">`, `<ol reversed>`, `<ol type="a">` e `<li value="20">`: o ordinal do item é resolvido no parse.',
    build: () {
      const body =
          '<h1>Ordinais</h1>'
          '<ol start="7"><li>sete</li><li>oito</li><li>nove</li></ol>'
          '<ol reversed=""><li>três</li><li>dois</li><li>um</li></ol>'
          '<ol type="a"><li>a</li><li>b</li><li value="20">t (valor 20)</li><li>u</li></ol>'
          '<ol style="list-style-type: upper-roman"><li>I</li><li>II</li></ol>';
      return singleChapterBook(
        'ol-start-reversed',
        body,
        title: 'Ordinais',
      ).build();
    },
  ),
  CorpusCase(
    group: _group,
    slug: 'notas-400',
    readme: '400 chamadas `epub:type="noteref"` e 400 `<aside epub:type="footnote">` com backlink: resolução de nota e deduplicação de diagnósticos.',
    build: () {
      final prose = proseFor('notas-400');
      final text = StringBuffer('<h1>Quatrocentas notas</h1>');
      final notes = StringBuffer(
        '<section epub:type="endnotes"><h2>Notas</h2>',
      );
      for (var i = 1; i <= 400; i++) {
        text.writeln(
          '<p>${prose.sentence()}<a id="ref$i" href="#n$i" epub:type="noteref" role="doc-noteref">$i</a> ${prose.sentence()}</p>',
        );
        notes.writeln(
          '<aside id="n$i" epub:type="footnote" role="doc-footnote"><p>$i. ${prose.sentence()} <a href="#ref$i" epub:type="backlink">↩</a></p></aside>',
        );
      }
      notes.writeln('</section>');
      return singleChapterBook(
        'notas-400',
        '$text$notes',
        title: 'Quatrocentas notas',
      ).build();
    },
  ),
  CorpusCase(
    group: _group,
    slug: 'svg-inline-text',
    readme: '`<svg>` inline com `<rect>`, `<circle>` e `<text>`: sem rasterizador vira placeholder com o texto do SVG.',
    diagnostics: ['svgUnrasterized'],
    build: () {
      const body =
          '<h1>SVG inline</h1><p>Antes.</p>'
          '<svg xmlns="http://www.w3.org/2000/svg" width="200" height="100" viewBox="0 0 200 100">'
          '<rect x="5" y="5" width="190" height="90" fill="#eee" stroke="#333"/>'
          '<circle cx="50" cy="50" r="30" fill="#c33"/>'
          '<text x="100" y="55" font-size="16">Figura 1</text>'
          '</svg><p>Depois.</p>';
      return singleChapterBook(
        'svg-inline-text',
        body,
        title: 'SVG inline',
      ).build();
    },
  ),
  CorpusCase(
    group: _group,
    slug: 'svg-involucro-capa',
    readme: 'Capa como `<svg><image href="capa.png"/></svg>` (padrão de capa EPUB2): o invólucro é desembrulhado e a imagem renderizada.',
    build: () {
      final b = standardBook('svg-involucro-capa', chapters: 2);
      b.addImage('capa.png', png(300, 450, seed: 3), id: 'capa-img');
      b.coverId = 'capa-img';
      final cover = b.addChapter(
        'capa.xhtml',
        xhtml(
          title: 'Capa',
          body:
              '<div style="text-align:center;padding:0;margin:0">'
              '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" version="1.1" width="100%" height="100%" viewBox="0 0 300 450" preserveAspectRatio="xMidYMid meet">'
              '<image width="300" height="450" xlink:href="../Images/capa.png"/></svg></div>',
        ),
        id: 'capa',
        properties: const ['svg'],
      );
      b.spine.insert(0, const SpineRef('capa'));
      b.toc.insert(0, TocEntry('Capa', b.hrefOf(cover)));
      return b.build();
    },
  ),
  CorpusCase(
    group: _group,
    slug: 'imagem-sem-dimensao',
    readme: 'Imagem em bloco sem `width`/`height` no XHTML nem no CSS: o espaço é reservado em 4:3 e a seção repaginada quando a dimensão real chega.',
    diagnostics: ['imageWithoutIntrinsicSize'],
    build: () {
      final b = EpubBuilder(slug: 'imagem-sem-dimensao');
      final prose = proseFor('imagem-sem-dimensao');
      b.addImage('foto.png', png(320, 200, seed: 11));
      final r = b.addChapter(
        'cap01.xhtml',
        xhtml(
          title: 'Sem dimensão',
          body:
              '<h1>Sem dimensão</h1>${prose.paragraphs(2)}<p><img src="../Images/foto.png" alt="Uma foto sem dimensões declaradas"/></p>${prose.paragraphs(6)}',
        ),
      );
      b.chapterInSpineAndToc(r, 'Sem dimensão');
      return b.build();
    },
  ),
  CorpusCase(
    group: _group,
    slug: 'pre-300-colunas',
    readme: '`<pre>` com linhas de 300 colunas: whitespace preservado, sem quebra automática, rolagem horizontal do bloco.',
    build: () {
      final lines = List.generate(12, (i) {
        final cols = List.generate(
          29,
          (j) => 'col${j.toString().padLeft(2, '0')}[${(i * j) % 97}]',
        ).join(' ');
        return 'linha ${i.toString().padLeft(2, '0')} $cols';
      }).join('\n');
      final body =
          '<h1>Pré-formatado</h1><p>Abaixo, 300 colunas.</p><pre>$lines</pre><p>Fim.</p>';
      return singleChapterBook(
        'pre-300-colunas',
        body,
        title: 'Pré-formatado',
      ).build();
    },
  ),
  CorpusCase(
    group: _group,
    slug: 'text-transform-uppercase',
    readme: '`text-transform: uppercase` sobre "ß" e "ﬁ" (mudam de comprimento em caixa alta) e `capitalize`: exercita o DisplayMap.',
    build: () {
      const body =
          '<h1 class="up">Straße com ﬁnal em ligadura</h1>'
          '<p class="up">der große fluß, die straße, das maß — offiziell und ﬁnal.</p>'
          '<p class="cap">palavras em caixa baixa que devem virar título.</p>'
          '<p class="low">TEXTO EM CAIXA ALTA QUE DEVE DESCER.</p>'
          '<p>Parágrafo normal com <span class="up">um trecho ß em caixa alta</span> no meio.</p>';
      const css =
          '.up{text-transform:uppercase} .cap{text-transform:capitalize} .low{text-transform:lowercase}';
      return singleChapterBook(
        'text-transform-uppercase',
        body,
        title: 'Transformações',
        css: css,
      ).build();
    },
  ),
  CorpusCase(
    group: _group,
    slug: 'nbsp-zwsp-shy',
    readme: '`&nbsp;` como entidade nomeada sem DTD (mal-formado em XML estrito, comum no acervo real), U+200B e U+00AD no fonte: o nbsp não colapsa, os outros dois são mantidos como intenção do autor.',
    build: () {
      const body =
          '<h1>Espaços especiais</h1>'
          '<p>Dr.&nbsp;Silva e Sra.&nbsp;Souza chegaram às 10&nbsp;h. Espaços   múltiplos   colapsam.</p>'
          '<p>Palavra­compos­ta com soft hyphens e outra​sem​largura com zero width spaces.</p>'
          '<p>Um&#160;nbsp numérico e um nbsp literal.</p>';
      return singleChapterBook(
        'nbsp-zwsp-shy',
        body,
        title: 'Espaços especiais',
      ).build();
    },
  ),
  CorpusCase(
    group: _group,
    slug: 'imagem-inline-alta',
    readme: 'Imagem inline de 200×300 no meio de um parágrafo (mais alta que 2× a entrelinha): promovida a bloco com diagnóstico.',
    diagnostics: ['inlineImagePromoted'],
    build: () {
      final b = EpubBuilder(slug: 'imagem-inline-alta');
      final prose = proseFor('imagem-inline-alta');
      b.addImage('alta.png', png(200, 300, seed: 5));
      b.addImage('icone.png', png(16, 16, seed: 9));
      final r = b.addChapter(
        'cap01.xhtml',
        xhtml(
          title: 'Inline alta',
          body:
              '<h1>Inline alta</h1><p>${prose.sentence()} <img src="../Images/alta.png" width="200" height="300" alt="Imagem alta"/> ${prose.sentence()}</p>'
              '<p>${prose.sentence()} <img src="../Images/icone.png" width="16" height="16" alt="ícone"/> ${prose.sentence()}</p>',
        ),
      );
      b.chapterInSpineAndToc(r, 'Inline alta');
      return b.build();
    },
  ),
  CorpusCase(
    group: _group,
    slug: 'hr-quebra-cena',
    readme: '`<hr/>` entre cenas, inclusive no fim e no início de página em potencial, e `<hr/>` com classe de ornamento.',
    build: () {
      final prose = proseFor('hr-quebra-cena');
      final body =
          '<h1>Quebras de cena</h1>${prose.paragraphs(4)}<hr/>${prose.paragraphs(3)}<hr class="ornamento"/>${prose.paragraphs(3)}<hr/><hr/>${prose.paragraphs(2)}';
      return singleChapterBook(
        'hr-quebra-cena',
        body,
        title: 'Quebras de cena',
      ).build();
    },
  ),
  CorpusCase(
    group: _group,
    slug: 'blockquote-varios-paragrafos',
    readme: '`<blockquote>` com três parágrafos e um `<cite>`, e blockquote dentro de blockquote.',
    build: () {
      final prose = proseFor('blockquote-varios-paragrafos');
      final body =
          '<h1>Citações</h1>${prose.paragraphs(1)}'
          '<blockquote><p>${prose.sentence()}</p><p>${prose.sentence()} ${prose.sentence()}</p><p>${prose.sentence()}</p><cite>Autor Fictício</cite></blockquote>'
          '${prose.paragraphs(1)}'
          '<blockquote><p>Externa.</p><blockquote><p>Interna, com recuo duplo.</p></blockquote></blockquote>';
      return singleChapterBook(
        'blockquote-varios-paragrafos',
        body,
        title: 'Citações',
      ).build();
    },
  ),
  CorpusCase(
    group: _group,
    slug: 'display-none-com-texto',
    readme: '`display: none` por classe, por atributo `style` e por `hidden`: o texto escondido não entra no `canonicalText`.',
    build: () {
      const body =
          '<h1>Escondidos</h1><p>Visível um.</p>'
          '<div class="oculto"><p>ESCONDIDO POR CLASSE: não deve aparecer.</p></div>'
          '<p style="display:none">ESCONDIDO POR STYLE: não deve aparecer.</p>'
          '<p hidden="">ESCONDIDO POR HIDDEN: não deve aparecer.</p>'
          '<p>Visível dois, com <span class="oculto">trecho inline escondido</span> no meio.</p>';
      const css = '.oculto { display: none; }';
      return singleChapterBook(
        'display-none-com-texto',
        body,
        title: 'Escondidos',
        css: css,
      ).build();
    },
  ),
  CorpusCase(
    group: _group,
    slug: 'css-import-cadeia',
    readme: '`@import` em cadeia: relativo à folha que importa, com `%20` no caminho, uma folha importada duas vezes e uma regra importada sobrescrita.',
    build: () {
      final b = EpubBuilder(slug: 'css-import-cadeia', title: 'Importações');
      b
        ..addCss(
          'main.css',
          '@import "base/tipo%20grafia.css";\n'
              '@import "repetida.css";\n'
              '@import "repetida.css";\n'
              '.sobrescrita { font-style: normal }\n'
              '.do-main { text-transform: uppercase }\n',
        )
        ..addCss(
          'base/tipo grafia.css',
          '@import "../extra/listas.css";\n'
              '.do-tipo { font-weight: bold }\n'
              '.sobrescrita { font-style: italic }\n',
        )
        ..addCss('extra/listas.css', '.do-listas { list-style-type: square }\n')
        ..addCss(
          'repetida.css',
          '.da-repetida { text-decoration: underline }\n',
        );
      final r = b.addChapter(
        'cap01.xhtml',
        xhtml(
          title: 'Importações',
          cssHrefs: const ['../Styles/main.css'],
          body:
              '<h1>Importações</h1>'
              '<ul class="do-listas"><li>Item da lista.</li></ul>'
              '<p class="do-tipo">Negrito vindo da folha importada.</p>'
              '<p class="sobrescrita">Itálico importado, desfeito pela folha que importa.</p>'
              '<p class="da-repetida">Sublinhado da folha importada duas vezes.</p>'
              '<p class="do-main">Caixa alta da folha principal.</p>',
        ),
      );
      b.chapterInSpineAndToc(r, 'Importações');
      return b.build();
    },
  ),
  CorpusCase(
    group: _group,
    slug: 'css-media-misto',
    readme: '`media` em `<link>`, `<style>`, `@media` e `@import`: só vale o que é de `screen`/`all` sem condição, e o `not print`.',
    diagnostics: ['stylesheetMediaIgnored'],
    build: () {
      final b = EpubBuilder(slug: 'css-media-misto', title: 'Media');
      b
        ..addCss('impressao.css', '.so-impressao { display: none }\n')
        ..addCss('tela.css', '.da-tela { font-weight: bold }\n')
        ..addCss('x.css', '.do-x { display: none }\n');
      const head =
          '<link rel="stylesheet" type="text/css" href="../Styles/impressao.css" media="print"/>\n'
          '<link rel="stylesheet" type="text/css" href="../Styles/tela.css" media="screen, print"/>\n'
          '<style type="text/css" media="all and (min-width: 600px)">.largo { font-weight: bold }</style>\n'
          '<style type="text/css">\n'
          '@import url(../Styles/x.css) print;\n'
          '@media screen { .tela-media { font-style: italic } }\n'
          '@media print { .impressa { display: none } }\n'
          '@media screen and (orientation: portrait) { .retrato { display: none } }\n'
          '</style>\n'
          '<style type="text/css" media="not print">.nao-impressa { text-transform: uppercase }</style>';
      final r = b.addChapter(
        'cap01.xhtml',
        xhtml(
          title: 'Media',
          head: head,
          body:
              '<h1>Media</h1>'
              '<p class="so-impressao">Visível: a folha é só de impressão.</p>'
              '<p class="da-tela">Negrito: a folha vale na tela.</p>'
              '<p class="largo">Normal: o style tem condição de largura.</p>'
              '<p class="tela-media">Itálico: @media screen.</p>'
              '<p class="impressa">Visível: @media print.</p>'
              '<p class="retrato">Visível: @media com condição.</p>'
              '<p class="do-x">Visível: @import só de impressão.</p>'
              '<p class="nao-impressa">Caixa alta: media not print.</p>',
        ),
      );
      b.chapterInSpineAndToc(r, 'Media');
      return b.build();
    },
  ),
];
