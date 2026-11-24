# Corpus público do benchmark do Galley

Livros externos usados pelos benchmarks, todos de domínio público ou com
licença que permite redistribuição. Nenhum EPUB fica no repositório: o
`manifest.json` fixa cada arquivo por `sha256`, e o harness o baixa com o
`CorpusFetcher` (`benchmark/lib/src/corpus/fetcher.dart`).

## Como os arquivos são obtidos

Ordem de tentativa para cada livro:

1. cache local `<cacheDir>/<sha256>.epub` (no repositório: `.corpus-cache/`,
   ignorado pelo git);
2. `mirrorUrl` — asset `<id>.epub` da release
   [`corpus-v1`](https://github.com/EduardoSA8006/galley/releases/tag/corpus-v1)
   deste repositório (só nos itens `mirrorable: true`);
3. `url` — a origem.

O `sha256` é verificado em todas as fontes; arquivo divergente nunca entra no
cache. Se tudo falhar, o fetcher lança `CorpusFetchException` com a causa de
cada tentativa.

**Por que o espelho é a fonte principal:** Standard Ebooks e Project Gutenberg
regeram seus EPUBs quando corrigem o texto ou mudam o conversor, e o GitHub
Pages do W3C reempacota os testes a cada deploy (os zips mudam de data). Os
bytes da origem, portanto, deixam de bater com o `sha256` com o tempo; a URL
original fica como alternativa e como prova de procedência. As amostras do
EPUB 3 Samples vêm de assets de uma release antiga de um repositório arquivado
e devem continuar estáveis.

**Gentileza com os servidores:** cada arquivo foi baixado uma vez, em
sequência, com User-Agent genérico
`galley-benchmark-corpus-fetcher/1 (+https://github.com/EduardoSA8006/galley)`.
O `www.gutenberg.org` bloqueia acesso automatizado (respondeu 503 com
`retry-after` de 6 h), por isso as URLs do Project Gutenberg apontam para o
espelho oficial da PGLAF, `gutenberg.pglaf.org`.

## Espelho (`corpus/tool/mirror.sh`)

O script cria a release `corpus-v1` (com este README como notas e como asset
`CORPUS-README.md`, para levar as atribuições exigidas) e envia os arquivos
`mirrorable`, depois de conferir o `sha256` de cada um. **Publica conteúdo de
terceiros: só roda com aprovação explícita do mantenedor.** `--dry-run` baixa e
confere sem publicar. Até a release existir, o fetcher recebe 404 do espelho e
cai na URL original.

## Formato do manifesto

```json
{
  "version": 1,
  "mirrorRelease": "corpus-v1",
  "books": [
    {
      "id": "se-pride-and-prejudice",
      "url": "https://…",
      "mirrorUrl": "https://github.com/EduardoSA8006/galley/releases/download/corpus-v1/se-pride-and-prejudice.epub",
      "sha256": "…64 hex…",
      "size": 831931,
      "license": "…",
      "source": "…",
      "tags": ["epub3"],
      "mirrorable": true
    }
  ]
}
```

`mirrorUrl` só existe quando `mirrorable` é `true`. `size` é informativo
(bytes). Tags: `epub2`, `epub3`, `fixed-layout`, `cjk`, `rtl`, `tables`,
`illustrated`, `technical`, `w3c-tests`, `large`.

## Livros

Todos os 20 abriram com `EpubBook.open` (com leitura de todos os recursos do
manifest) em 2026-11-24, **sem nenhum diagnóstico** (nem `error`, nem
`warning`, nem `info`).

### Standard Ebooks — CC0 1.0 + domínio público

Standard Ebooks dedica a produção (marcação, CSS, capa) ao domínio público via
[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/); o texto e as
ilustrações são de domínio público nos EUA (declaração em `dc:rights` de cada
livro). Os autores, ilustradores e tradutores abaixo morreram há mais de 70
anos, então as obras também são de domínio público nos países de origem.
Espelháveis.

| id | Obra | Autoria | Procedência | Tags |
|---|---|---|---|---|
| `se-pride-and-prejudice` | *Pride and Prejudice* | Jane Austen (1775–1817) | [standardebooks.org](https://standardebooks.org/ebooks/jane-austen/pride-and-prejudice); fonte: PG #42671 | epub3 |
| `se-alice-tenniel` | *Alice's Adventures in Wonderland* | Lewis Carroll (1832–1898); ilustrações de John Tenniel (1820–1914) | [standardebooks.org](https://standardebooks.org/ebooks/lewis-carroll/alices-adventures-in-wonderland/john-tenniel); fonte: PG #11, Internet Archive | epub3, illustrated, large (18,6 MB) |
| `se-les-miserables` | *Les Misérables* | Victor Hugo (1802–1885); tradução de Isabel F. Hapgood (1851–1928) | [standardebooks.org](https://standardebooks.org/ebooks/victor-hugo/les-miserables/isabel-f-hapgood); fonte: PG #135 | epub3, large |

### Project Gutenberg — domínio público + licença do Project Gutenberg

Textos em domínio público nos EUA (`dcterms:rights` do RDF: "Public domain in
the USA."), com autores e tradutores mortos há mais de 70 anos (domínio público
também nos países de origem; Akutagawa morreu em 1927, e o Japão aplica a regra
de 50 anos a quem morreu antes de 1968). Os arquivos vêm do espelho da PGLAF.

Sobre a [licença do Project Gutenberg](https://www.gutenberg.org/policy/license.html):
o nome "Project Gutenberg" é marca registrada. Ela permite copiar e redistribuir
gratuitamente os arquivos **sem modificação e com o cabeçalho e a licença
completos** (o próprio EPUB os inclui); cobrar pela distribuição ou alterar o
arquivo mantendo a marca exigiria cumprir termos adicionais (royalties ou
remoção da marca). O espelho redistribui os arquivos byte a byte, sem cobrança,
então fica dentro da licença: marcados `mirrorable: true`.

| id | Obra | Autoria | Procedência | Tags |
|---|---|---|---|---|
| `pg-frankenstein` | *Frankenstein; or, The Modern Prometheus* | Mary Wollstonecraft Shelley (1797–1851) | [PG #84](https://www.gutenberg.org/ebooks/84), arquivo `pg84.epub` (EPUB 2 sem imagens) | epub2 |
| `pg-war-and-peace` | *War and Peace* | Liev Tolstói (1828–1910); tradução de Aylmer Maude (1858–1938) e Louise Maude (1855–1939) | [PG #2600](https://www.gutenberg.org/ebooks/2600), `pg2600-images.epub` | epub2, large |
| `pg-rashomon` | 羅生門 (*Rashōmon*) | 芥川龍之介 Akutagawa Ryūnosuke (1892–1927) | [PG #1982](https://www.gutenberg.org/ebooks/1982), `pg1982-images-3.epub` | epub3, cjk |
| `pg-erter-tashlich` | הצופה לבית ישראל: תשליך | Isaac Erter (1791–1851) | [PG #45252](https://www.gutenberg.org/ebooks/45252), `pg45252-images.epub` | epub2, rtl |

### EPUB 3 Samples (IDPF / W3C EPUB 3 Community Group)

Do repositório [IDPF/epub3-samples](https://github.com/IDPF/epub3-samples)
(arquivado), arquivos prontos da release
[`20230704`](https://github.com/IDPF/epub3-samples/releases/tag/20230704). O
README do repositório diz: "Unless specified otherwise in the
[sample table](http://idpf.github.io/epub3-samples/30/samples.html), all
samples are licensed under [CC-BY-SA 3.0](http://creativecommons.org/licenses/by-sa/3.0/)".
Todas as licenças abaixo permitem redistribuição com atribuição (e, no caso da
GFDL, com o texto da licença, que já vem dentro do EPUB). Espelháveis, sem
modificação.

| id | Obra | Autoria e licença | Tags |
|---|---|---|---|
| `es-kusamakura-japanese-vertical-writing` | 草枕 (*Kusamakura*), escrita vertical, ruby, media overlay | Texto de 夏目漱石 Natsume Sōseki (1867–1916), domínio público, digitado pelo [Aozora Bunko](https://www.aozora.gr.jp/) (入力: 柴田卓治, 校正: 伊藤時也). Pacote © EPUB日本語拡張仕様策定プロジェクト (narração: 持田怜香), CC-BY-SA 3.0 | epub3, cjk, large (17,9 MB) |
| `es-haruko-html-jpeg` | ハルコさんの彼氏 (*Haruko*), mangá em layout fixo | CC-BY-SA 3.0 pela declaração geral do repositório (o OPF não traz `dc:rights` nem autor) | epub3, fixed-layout, cjk, illustrated |
| `es-jlreq-in-japanese` | 日本語組版処理の要件 (*Requirements for Japanese Text Layout*, W3C Note, em japonês) | © 2012 W3C (MIT, ERCIM, Keio); [W3C Document License](https://www.w3.org/copyright/document-license/) | epub3, cjk, technical, tables, illustrated |
| `es-regime-anticancer-arabic` | *Le Vrai Régime anti-cancer* (trecho em árabe) | David Khayat, Nathalie Hutter-Lardeau, Marina Khalil Fayad; Hachette Antoine; CC-BY-SA 3.0 (declarado no OPF) | epub3, rtl |
| `es-israelsailing` | מפליגים בישראל (*Israel Sailing*) | אורי עידן (Uri Idan); הליקון ספרים; CC-BY-SA 2.5 (declarado no OPF) | epub3, rtl |
| `es-linear-algebra` | *A First Course in Linear Algebra* (MathML) | © 2004 Robert A. Beezer; [GNU FDL 1.2](https://www.gnu.org/licenses/old-licenses/fdl-1.2.html) (texto da licença incluído no EPUB) | epub3, technical, tables |
| `es-page-blanche` | *Page Blanche* (trecho, layout fixo) | Boulet e Pénélope Bagieu; éditions Delcourt; CC-BY-SA 3.0 (declarado no OPF) | epub3, fixed-layout, illustrated |
| `es-cole-voyage-of-life` | *Thomas Cole – The Voyage of Life* (reflow + layout fixo por item) | Pinturas de Thomas Cole (1801–1848), domínio público; pacote de Jesse Dylan, CC-BY-SA 3.0 (declarado no OPF) | epub3, fixed-layout, illustrated |

### W3C `epub-tests` — W3C Software and Document License

Repositório [w3c/epub-tests](https://github.com/w3c/epub-tests), commit fixo
[`12237fcbf91ea6cfe8908b8ebcaa840776ccbc1c`](https://github.com/w3c/epub-tests/tree/12237fcbf91ea6cfe8908b8ebcaa840776ccbc1c)
(2026-11-18). O `LICENSE.md` diz: "All documents (EPUB, Markdown, or HTML
files) in this Repository are licensed by contributors under the
[W3C Software and Document License](https://www.w3.org/copyright/software-license/)",
que permite copiar e redistribuir em qualquer meio com o aviso de copyright e o
link para a licença. Espelháveis.

O repositório não versiona EPUBs: os testes são diretórios, empacotados pelo
workflow `generate.yml` (com `tests/generateEpubs.sh`:
`zip -X x.epub mimetype; zip -rDX9 x.epub * -x mimetype`) e publicados no
GitHub Pages. Usamos esses pacotes oficiais, baixados de
`https://w3c.github.io/epub-tests/tests/<teste>.epub` logo após o deploy do
commit acima (execução do workflow concluída em 2026-11-18T07:51Z, arquivos
com `last-modified` de 2026-11-18 07:51 GMT). Nada foi reempacotado por nós.
Como cada deploy refaz os zips, o `sha256` da URL original muda no próximo
deploy; o espelho guarda os bytes deste commit.

| id | Teste | Autoria | Tags |
|---|---|---|---|
| `w3c-lay-fxl-layout-pre-paginated` | `lay-fxl-layout-pre-paginated` | Wendy Reid / W3C | epub3, w3c-tests, fixed-layout |
| `w3c-css-epub-writing-mode` | `css-epub-writing-mode` (texto japonês vertical) | Wendy Reid / W3C | epub3, w3c-tests, cjk |
| `w3c-pkg-spine-progression_rtl` | `pkg-spine-progression_rtl` | Dave Cramer / W3C | epub3, w3c-tests, rtl |
| `w3c-ocf-font_obfuscation` | `ocf-font_obfuscation` | Ivan Herman / W3C | epub3, w3c-tests |
| `w3c-nav-spine_in-spine` | `nav-spine_in-spine` | Dave Cramer / W3C | epub3, w3c-tests |

Copyright © W3C® (MIT, ERCIM, Keio, Beihang) e contribuidores, sob a W3C
Software and Document License.

## Lacunas conhecidas

- **Japonês direto do Aozora Bunko:** o Aozora Bunko não publica EPUBs
  prontos (só texto e HTML). O japonês do corpus vem de EPUBs prontos com
  licença clara: o *Kusamakura* do EPUB 3 Samples (texto digitado pelo Aozora
  Bunko), o *Rashōmon* do Project Gutenberg, o mangá *Haruko*, o JLReq do W3C e
  o teste `css-epub-writing-mode`.
- **Árabe em domínio público:** não achamos EPUB árabe de domínio público com
  procedência clara; o árabe vem do trecho CC-BY-SA do EPUB 3 Samples. O
  hebraico tem um livro de domínio público (Erter, PG) e um CC-BY-SA.
