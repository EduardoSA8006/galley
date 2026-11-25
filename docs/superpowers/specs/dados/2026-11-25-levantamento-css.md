# Levantamento de CSS em EPUBs reais (escopo do motor CSS do Galley)

Gerado por `extract.py` + `agg.py` (tinycss2 1.5.1, Python) (scripts descartáveis, fora do repositório). Contagens são em **livros** (um livro conta uma vez por característica), nunca ocorrências.

## Corpora

- **público**: 20 livros de `corpus/manifest.json` (cache `.corpus-cache/<sha256>.epub`).
- **amplo**: 300 livros do Project Gutenberg (`corpus/pg-wide.json`, cache `.corpus-cache/pg-wide/`, EPUBs sem imagens).
- **privado**: 52 livros comerciais e de fãs do mantenedor (fora do repositório). Só agregados foram gravados: nenhum título, nome de arquivo ou texto.
- **Total: 372 livros**. Atenção: o amplo (PG) é 81% do total, e é CSS homogêneo gerado pelo Gutenberg; o combinado reflete isso. Veja as colunas por corpus.

Escopo da extração: todos os `text/css` do manifest, blocos `<style>` e atributos `style=` dos XHTML do spine. Propriedades vêm de regras de estilo (inclusive dentro de @media/@supports) e `style=`; descritores de @font-face e @page são contados à parte.

## Fontes de CSS por livro
| item | combinado | público | amplo | privado |
|---|---|---|---|---|
| folha ligada (text/css) | 97.8% (364) | 80% | 100% | 92% |
| bloco <style> | 8.1% (30) | 5% | 0% | 54% |
| atributo style= | 92.5% (344) | 45% | 100% | 67% |
| sem nenhum CSS | 1.1% (4) | 10% | 0% | 4% |
| sem nenhuma declaração | 1.1% (4) | 10% | 0% | 4% |
| folha no manifest ausente do zip | 0.3% (1) | 5% | 0% | 0% |
| erro de parse tolerado (declaração/regra inválida) | 0.0% (0) | 0% | 0% | 0% |
| aninhamento CSS (nesting) | 0.0% (0) | 0% | 0% | 0% |

## Propriedades — top 60 (% de livros)
| propriedade | combinado | público (20) | amplo (300) | privado (52) |
|---|---|---|---|---|
| `font-size` | 97.6% (363) | 70% | 100% | 94% |
| `margin` | 97.3% (362) | 70% | 100% | 92% |
| `text-align` | 97.3% (362) | 60% | 100% | 96% |
| `padding` | 97.0% (361) | 65% | 100% | 92% |
| `display` | 96.5% (359) | 60% | 100% | 90% |
| `max-width` | 95.4% (355) | 35% | 100% | 92% |
| `width` | 94.9% (353) | 55% | 100% | 81% |
| `margin-left` | 93.8% (349) | 50% | 100% | 75% |
| `border` | 92.7% (345) | 50% | 100% | 67% |
| `font-family` | 92.5% (344) | 60% | 100% | 62% |
| `margin-right` | 92.5% (344) | 40% | 100% | 69% |
| `text-decoration` | 91.9% (342) | 45% | 100% | 63% |
| `page-break-after` | 91.7% (341) | 40% | 100% | 63% |
| `color` | 91.1% (339) | 40% | 100% | 60% |
| `margin-top` | 90.3% (336) | 50% | 93% | 92% |
| `page-break-before` | 89.5% (333) | 25% | 100% | 54% |
| `margin-bottom` | 89.0% (331) | 50% | 93% | 81% |
| `padding-top` | 88.7% (330) | 30% | 100% | 46% |
| `text-indent` | 88.7% (330) | 40% | 92% | 87% |
| `background-color` | 84.4% (314) | 50% | 100% | 8% |
| `font-weight` | 80.9% (301) | 60% | 81% | 90% |
| `clear` | 71.0% (264) | 15% | 76% | 65% |
| `line-height` | 60.2% (224) | 45% | 56% | 90% |
| `padding-left` | 53.5% (199) | 35% | 55% | 52% |
| `font-variant` | 53.2% (198) | 20% | 64% | 6% |
| `font-style` | 50.0% (186) | 50% | 48% | 60% |
| `vertical-align` | 46.0% (171) | 25% | 43% | 71% |
| `height` | 35.5% (132) | 45% | 25% | 92% |
| `letter-spacing` | 29.3% (109) | 20% | 21% | 79% |
| `padding-right` | 28.8% (107) | 10% | 27% | 46% |
| `list-style-type` | 27.4% (102) | 25% | 21% | 65% |
| `visibility` | 26.1% (97) | 5% | 21% | 63% |
| `border-collapse` | 25.0% (93) | 10% | 18% | 69% |
| `page-break-inside` | 24.2% (90) | 15% | 14% | 85% |
| `background` | 23.7% (88) | 25% | 20% | 44% |
| `border-bottom` | 22.3% (83) | 10% | 27% | 0% |
| `padding-bottom` | 20.2% (75) | 0% | 17% | 44% |
| `word-spacing` | 15.3% (57) | 10% | 7% | 67% |
| `max-height` | 14.5% (54) | 25% | 1% | 88% |
| `border-top` | 14.0% (52) | 25% | 14% | 8% |
| `orphans` | 12.4% (46) | 0% | 0% | 87% |
| `widows` | 12.4% (46) | 0% | 0% | 87% |
| `border-left` | 11.8% (44) | 5% | 13% | 6% |
| `text-transform` | 11.0% (41) | 15% | 11% | 8% |
| `float` | 9.9% (37) | 10% | 12% | 0% |
| `border-right` | 9.1% (34) | 5% | 11% | 0% |
| `white-space` | 8.9% (33) | 25% | 9% | 0% |
| `border-style` | 8.6% (32) | 10% | 10% | 0% |
| `border-width` | 7.8% (29) | 5% | 9% | 0% |
| `min-height` | 6.5% (24) | 5% | 0% | 44% |
| `content` | 5.9% (22) | 25% | 3% | 15% |
| `border-color` | 5.6% (21) | 5% | 7% | 0% |
| `border-radius` | 5.6% (21) | 0% | 0% | 40% |
| `overflow` | 5.6% (21) | 5% | 0% | 37% |
| `-webkit-hyphens` | 4.8% (18) | 15% | 0% | 29% |
| `list-style` | 4.8% (18) | 5% | 3% | 17% |
| `border-spacing` | 3.0% (11) | 5% | 3% | 2% |
| `break-inside` | 3.0% (11) | 15% | 0% | 15% |
| `hyphens` | 3.0% (11) | 15% | 0% | 15% |
| `min-width` | 3.0% (11) | 10% | 3% | 0% |

### Cauda: propriedades usadas por >=1 livro, fora do top 60 (resumo)

Total de propriedades distintas: 115. Entre 61 e 150:

`position` 3.0%, `break-after` 2.4%, `justify-content` 2.4%, `left` 2.2%, `font` 1.9%, `-epub-hyphens` 1.6%, `-webkit-box-shadow` 1.6%, `-webkit-tap-highlight-color` 1.6%, `overflow-wrap` 1.3%, `-moz-hyphens` 1.1%, `adobe-hyphenate` 1.1%, `filter` 1.1%, `top` 1.1%, `adobe-text-layout` 0.8%, `all` 0.8%, `font-variant-numeric` 0.8%, `hanging-punctuation` 0.8%, `pointer-events` 0.8%, `text-wrap` 0.8%, `z-index` 0.8%, `-epub-writing-mode` 0.5%, `background-image` 0.5%, `background-repeat` 0.5%, `break-before` 0.5%, `empty-cells` 0.5%, `opacity` 0.5%, `table-layout` 0.5%, `-epub-text-combine` 0.3%, `-epub-text-emphasis-color` 0.3%, `-epub-text-emphasis-style` 0.3%, `-ms-hyphens` 0.3%, `-webkit-filter` 0.3%, `align-items` 0.3%, `background-attachment` 0.3%, `background-position` 0.3%, `background-size` 0.3%, `border-bottom-style` 0.3%, `border-top-color` 0.3%, `border-top-width` 0.3%, `box-sizing` 0.3%, `counter-increment` 0.3%, `direction` 0.3%, `flex-direction` 0.3%, `list-style-position` 0.3%, `object-fit` 0.3%, `pause-before` 0.3%, `richness` 0.3%, `right` 0.3%, `speak` 0.3%, `speak-as` 0.3%, `speak-punctuation` 0.3%, `speech-rate` 0.3%, `stress` 0.3%, `volume` 0.3%, `writing-mode` 0.3%

### Propriedades prefixadas (por livro)
| propriedade | combinado | público (20) | amplo (300) | privado (52) |
|---|---|---|---|---|
| `-webkit-hyphens` | 4.8% (18) | 15% | 0% | 29% |
| `-epub-hyphens` | 1.6% (6) | 5% | 0% | 10% |
| `-webkit-box-shadow` | 1.6% (6) | 0% | 0% | 12% |
| `-webkit-tap-highlight-color` | 1.6% (6) | 0% | 0% | 12% |
| `-moz-hyphens` | 1.1% (4) | 15% | 0% | 2% |
| `-epub-writing-mode` | 0.5% (2) | 10% | 0% | 0% |
| `-epub-text-combine` | 0.3% (1) | 5% | 0% | 0% |
| `-epub-text-emphasis-color` | 0.3% (1) | 5% | 0% | 0% |
| `-epub-text-emphasis-style` | 0.3% (1) | 5% | 0% | 0% |
| `-ms-hyphens` | 0.3% (1) | 0% | 0% | 2% |
| `-webkit-filter` | 0.3% (1) | 0% | 0% | 2% |

### Prefixos de fornecedor (propriedade, valor, at-rule ou pseudo)
| prefixo | combinado | público (20) | amplo (300) | privado (52) |
|---|---|---|---|---|
| `-webkit-` | 4.8% (18) | 15% | 0% | 29% |
| `-epub-` | 2.2% (8) | 15% | 0% | 10% |
| `-moz-` | 1.1% (4) | 15% | 0% | 2% |
| `-ms-` | 0.3% (1) | 0% | 0% | 2% |

### Valores prefixados
| prefixo | combinado | público (20) | amplo (300) | privado (52) |
|---|---|---|---|---|

## Valores mais comuns das top-40 propriedades (números trocados por N; valores com string/url omitidos)

- `font-size` (363 livros): `Nem` 96%; `N%` 50%; `smaller` 26%; `large` 18%; `small` 16%; `x-small` 10%; `x-large` 10%; `medium` 9%; `xx-large` 6%; `Npt` 5%
- `margin` (362 livros): `N` 95%; `Nem` 91%; `auto` 33%; `Nem auto` 23%; `Nem N` 15%; `Nem N Nem N` 13%; `N auto` 13%; `N N%` 9%; `Nem N%` 7%; `N% N%` 6%
- `text-align` (362 livros): `center` 97%; `justify` 87%; `right` 68%; `left` 60%; `initial` 3%; `inherit` 1%; `axis` 0%
- `padding` (361 livros): `N` 90%; `Nem` 41%; `Npt` 7%; `Npx` 6%; `Npx Npx` 6%; `Nem N Nem Nem` 6%; `Nem Nem` 5%; `Nem Nem Nem Nem` 4%; `N Nem` 4%; `Nem N` 3%
- `display` (359 livros): `block` 96%; `none` 36%; `inline` 27%; `inline-block` 19%; `table` 4%; `inline-table` 3%; `flex` 3%; `table-row` 1%; `table-cell` 1%
- `max-width` (355 livros): `N%` 95%; `Nem` 14%; `Nex` 0%; `inherit` 0%; `Npx` 0%
- `width` (353 livros): `auto` 92%; `N%` 87%; `Npx` 27%; `Nem` 23%; `N` 1%; `Nex` 0%; `inherit` 0%
- `margin-left` (349 livros): `N` 87%; `N%` 83%; `auto` 58%; `Nem` 54%; `Npt` 9%; `Npx` 1%; `Nex` 1%; `inherit` 0%
- `border` (345 livros): `N` 83%; `Npx solid black` 21%; `none` 16%; `dashed Npx` 12%; `solid Npx` 7%; `Npx solid #N` 6%; `Npt solid black` 6%; `Npx solid` 4%; `Npx solid silver` 4%; `thin solid silver` 3%
- `font-family` (344 livros): `monospace` 82%; `sans-serif` 16%; `sans-serif, serif` 10%; `serif` 9%; `monospaced` 6%; `helvetica` 5%; `arial, helvetica, sans-serif` 4%; `georgia, serif` 2%; `garamond, serif` 1%; `times` 1%
- `margin-right` (344 livros): `N` 87%; `N%` 73%; `auto` 57%; `Nem` 34%; `Npt` 6%; `Nex` 0%; `Npx` 0%
- `text-decoration` (342 livros): `none` 91%; `underline` 90%; `line-through` 4%; `overline` 2%; `overline underline` 0%; `inherit` 0%
- `page-break-after` (341 livros): `always` 90%; `avoid` 6%
- `color` (339 livros): `black` 83%; `#N` 15%; `gray` 9%; `white` 8%; `red` 6%; `blue` 6%; `silver` 5%; `inherit` 4%; `#fN` 4%; `purple` 2%
- `margin-top` (336 livros): `Nem` 86%; `N` 31%; `N%` 19%; `Npt` 10%; `Npx` 3%; `auto` 2%; `Npc` 0%
- `page-break-before` (333 livros): `always` 90%; `avoid` 20%; `auto` 3%; `right` 1%
- `margin-bottom` (331 livros): `Nem` 86%; `N` 44%; `N%` 12%; `Npt` 10%; `auto` 1%; `Npx` 1%
- `padding-top` (330 livros): `Nem` 88%; `N` 4%; `N%` 2%; `Npx` 1%; `Nex` 1%
- `text-indent` (330 livros): `Nem` 78%; `N` 65%; `N%` 13%; `Npt` 9%; `Nin` 1%; `inherit` 0%; `Npx` 0%
- `background-color` (314 livros): `white` 82%; `#eNfa` 15%; `inherit` 9%; `#fff` 7%; `#dde` 5%; `#fNfNfN` 4%; `#eee` 4%; `#ccccff` 2%; `black` 2%; `transparent` 1%
- `font-weight` (301 livros): `normal` 61%; `bold` 51%; `N` 1%; `lighter` 1%; `bolder` 0%
- `clear` (264 livros): `both` 70%; `left` 12%; `right` 9%; `none` 1%
- `line-height` (224 livros): `Nem` 39%; `N` 20%; `N%` 19%; `normal` 2%; `Npx` 1%; `inherit` 0%
- `padding-left` (199 livros): `Nem` 46%; `Nex` 10%; `N` 7%; `N%` 4%; `Npx` 1%; `Npt` 0%; `Nin` 0%
- `font-variant` (198 livros): `small-caps` 51%; `normal` 20%
- `font-style` (186 livros): `normal` 38%; `italic` 25%; `oblique` 1%
- `vertical-align` (171 livros): `top` 32%; `super` 25%; `middle` 14%; `bottom` 13%; `sub` 9%; `N%` 4%; `Nem` 3%; `baseline` 2%; `text-top` 1%
- `height` (132 livros): `auto` 16%; `Nem` 16%; `Npx` 8%; `N%` 7%; `N` 2%; `Nvh` 0%
- `letter-spacing` (109 livros): `Nem` 23%; `N` 8%; `normal` 3%; `Npx` 0%
- `padding-right` (107 livros): `Nem` 21%; `Npt` 6%; `N` 3%; `N%` 2%; `Npx` 1%; `Nex` 0%
- `list-style-type` (102 livros): `none` 23%; `decimal` 3%; `lower-roman` 2%; `lower-alpha` 2%; `disc` 2%; `square` 1%; `upper-roman` 1%; `upper-alpha` 1%; `inherit` 1%; `circle` 1%
- `visibility` (97 livros): `hidden` 26%; `visible` 6%
- `border-collapse` (93 livros): `collapse` 24%; `separate` 1%
- `page-break-inside` (90 livros): `avoid` 24%
- `background` (88 livros): `#N` 6%; `rgb(N,N,N)` 5%; `#fff` 4%; `white` 4%; `#faebdN` 3%; `#eee` 3%; `#fdfdfd` 2%; `transparent` 1%; `currentcolor` 1%; `inherit` 1%
- `border-bottom` (83 livros): `Npx solid black` 4%; `solid Npx` 3%; `thin solid` 3%; `thin dotted gray` 2%; `Npx solid` 2%; `thin solid silver` 1%; `thin dotted red` 1%; `Npx solid silver` 1%; `none` 1%; `Npx dotted gray` 1%
- `padding-bottom` (75 livros): `Nem` 18%; `N` 2%; `N%` 1%; `Nex` 1%; `Npx` 0%
- `word-spacing` (57 livros): `Nem` 11%; `N` 4%; `Nex` 0%
- `max-height` (54 livros): `N%` 12%; `Nvh` 3%; `Nem` 1%; `Npx` 0%
- `border-top` (52 livros): `Npx solid` 3%; `solid Npx` 3%; `Npx solid black` 2%; `none` 1%; `thin solid black` 1%; `thin solid` 1%; `Npx solid currentcolor` 1%; `Npx dotted #N` 0%; `solid Nem` 0%; `solid thin` 0%

## Valores enumerados de propriedades de layout (% de livros)

- `display` (359 livros): `block` 95.7%; `none` 36.3%; `inline` 27.2%; `inline-block` 18.8%; `table` 4.0%; `inline-table` 3.0%; `flex` 2.7%; `table-row` 1.1%; `table-cell` 1.1%
- `float` (37 livros): `left` 5.9%; `none` 3.8%; `right` 2.4%
- `position` (11 livros): `absolute` 1.9%; `relative` 0.5%; `static` 0.5%
- `text-align` (362 livros): `center` 96.8%; `justify` 87.4%; `right` 68.0%; `left` 59.9%; `initial` 2.7%; `inherit` 1.3%; `axis` 0.3%
- `vertical-align` (171 livros): `top` 32.0%; `super` 24.7%; `middle` 13.7%; `bottom` 13.4%; `sub` 8.9%; `N%` 4.3%; `Nem` 3.0%; `baseline` 2.4%; `text-top` 0.8%
- `clear` (264 livros): `both` 70.4%; `left` 11.8%; `right` 9.4%; `none` 1.3%
- `overflow` (21 livros): `hidden` 3.5%; `visible` 2.2%; `auto` 0.3%
- `visibility` (97 livros): `hidden` 25.5%; `visible` 6.2%
- `white-space` (33 livros): `nowrap` 8.3%; `pre` 0.8%; `pre-wrap` 0.3%; `normal` 0.3%
- `page-break-before` (333 livros): `always` 89.5%; `avoid` 20.4%; `auto` 3.2%; `right` 0.5%
- `page-break-after` (341 livros): `always` 90.3%; `avoid` 5.9%
- `page-break-inside` (90 livros): `avoid` 24.2%
- `break-before` (2 livros): `page` 0.5%
- `break-after` (9 livros): `avoid` 2.4%; `page` 1.3%
- `break-inside` (11 livros): `avoid` 3.0%
- `list-style-type` (102 livros): `none` 23.4%; `decimal` 3.5%; `lower-roman` 1.6%; `lower-alpha` 1.6%; `disc` 1.6%; `square` 0.5%; `upper-roman` 0.5%; `upper-alpha` 0.5%; `inherit` 0.5%; `circle` 0.5%
- `list-style-position` (1 livros): `outside` 0.3%
- `text-transform` (41 livros): `lowercase` 7.8%; `uppercase` 4.3%; `none` 1.3%
- `font-style` (186 livros): `normal` 38.2%; `italic` 24.7%; `oblique` 0.5%
- `font-weight` (301 livros): `normal` 61.0%; `bold` 51.3%; `N` 1.3%; `lighter` 1.1%; `bolder` 0.3%
- `font-variant` (198 livros): `small-caps` 50.8%; `normal` 20.4%
- `text-decoration` (342 livros): `none` 91.4%; `underline` 90.3%; `line-through` 4.3%; `overline` 1.9%; `overline underline` 0.3%; `inherit` 0.3%
- `border-collapse` (93 livros): `collapse` 24.5%; `separate` 0.5%
- `box-sizing` (1 livros): `border-box` 0.3%
- `writing-mode` (1 livros): `rl-tb` 0.3%
- `-epub-writing-mode` (2 livros): `vertical-rl` 0.5%; `horizontal-tb` 0.3%; `vertical-lr` 0.3%
- `hyphens` (11 livros): `auto` 3.0%; `none` 3.0%
- `-webkit-hyphens` (18 livros): `none` 4.6%; `auto` 3.2%
- `-epub-hyphens` (6 livros): `auto` 1.3%; `none` 0.3%
- `direction` (1 livros): `ltr` 0.3%
- `-epub-text-combine` (1 livros): `horizontal` 0.3%
- `-epub-text-emphasis-style` (1 livros): `sesame` 0.3%
- `orphans` (46 livros): `N` 12.4%
- `widows` (46 livros): `N` 12.4%
- `overflow-wrap` (5 livros): `break-word` 1.3%
- `table-layout` (2 livros): `fixed` 0.5%; `auto` 0.3%
- `empty-cells` (2 livros): `show` 0.5%
- `flex-direction` (1 livros): `column` 0.3%
- `align-items` (1 livros): `center` 0.3%
- `justify-content` (9 livros): `center` 2.4%
- `object-fit` (1 livros): `contain` 0.3%

## Unidades (livros que usam a unidade em pelo menos uma declaração)

(combinado, % de livros; `*` = qualquer propriedade; `unitless` só medido nas propriedades listadas)

| unidade | `*` | `font-size` | `margin` | `margin-top` | `margin-bottom` | `margin-left` | `margin-right` | `padding` | `text-indent` | `line-height` | `width` | `height` | `max-width` | `border-width` |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| em | 97.6% | 96.2% | 95.4% | 86.3% | 86.0% | 54.0% | 33.6% | 47.6% | 78.5% | 38.7% | 23.1% | 15.6% | 13.7% | 1.1% |
| % | 97.3% | 49.7% | 29.0% | 19.4% | 12.4% | 82.5% | 73.1% | 3.5% | 12.6% | 18.8% | 87.4% | 7.0% | 95.2% | 0.0% |
| px | 71.8% | 1.1% | 0.5% | 3.5% | 0.5% | 1.1% | 0.3% | 8.1% | 0.3% | 0.5% | 26.9% | 8.1% | 0.3% | 6.2% |
| pt | 17.2% | 5.4% | 1.3% | 9.9% | 9.9% | 9.1% | 5.6% | 7.0% | 9.4% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% |
| rem | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% |
| vw | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% |
| vh | 2.7% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.3% | 0.0% | 0.0% |
| ex | 11.8% | 0.0% | 0.8% | 0.0% | 0.0% | 0.5% | 0.3% | 1.1% | 0.0% | 0.0% | 0.3% | 0.0% | 0.3% | 0.0% |
| ch | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% |
| cm | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% |
| mm | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% |
| in | 1.3% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 1.3% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% |
| pc | 0.3% | 0.0% | 0.0% | 0.3% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% |
| unitless | 0.0% | 0.0% | 0.3% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 19.4% | 0.0% | 0.0% | 0.0% | 0.0% |
| vmin | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% |
| vmax | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% |
| q | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% |
| fr | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% |
| deg | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% |
| s | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% |
| ms | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% |

### Unidades por corpus, em font-size e margin/padding (qualquer lado)
| item | combinado | público | amplo | privado |
|---|---|---|---|---|
| font-size em em | 96.2% (358) | 55% | 100% | 90% |
| font-size em % | 49.7% (185) | 40% | 57% | 10% |
| font-size em px | 1.1% (4) | 5% | 0% | 4% |
| font-size em pt | 5.4% (20) | 15% | 6% | 0% |
| font-size em rem | 0.0% (0) | 0% | 0% | 0% |
| font-size em vw | 0.0% (0) | 0% | 0% | 0% |
| font-size em ex | 0.0% (0) | 0% | 0% | 0% |
| margin* em em | 97.3% (362) | 70% | 100% | 92% |
| margin* em % | 92.5% (344) | 20% | 98% | 88% |
| margin* em px | 5.1% (19) | 10% | 1% | 27% |
| margin* em pt | 11.3% (42) | 0% | 1% | 73% |
| margin* em rem | 0.0% (0) | 0% | 0% | 0% |
| margin* em vw | 0.0% (0) | 0% | 0% | 0% |

## Seletores

| item | combinado | público | amplo | privado |
|---|---|---|---|---|
| `sel:type` | 97.8% (364) | 80% | 100% | 92% |
| `sel:class` | 97.6% (363) | 75% | 100% | 92% |
| `sel:id` | 91.4% (340) | 50% | 100% | 58% |
| `sel:universal` | 2.7% (10) | 20% | 2% | 2% |
| `sel:descendant` | 96.0% (357) | 60% | 100% | 87% |
| `sel:child` | 23.7% (88) | 35% | 25% | 12% |
| `sel:adjacent-sibling` | 18.8% (70) | 25% | 19% | 15% |
| `sel:general-sibling` | 0.0% (0) | 0% | 0% | 0% |
| `sel:attribute` | 91.9% (342) | 45% | 100% | 63% |
| `sel:namespace` | 0.0% (0) | 0% | 0% | 0% |
| `sel:type.class` | 97.0% (361) | 65% | 100% | 92% |
| `sel:compound-multi-class` | 82.8% (308) | 40% | 100% | 0% |
| `sel:depth>=4` | 3.0% (11) | 25% | 2% | 0% |
| `sel:depth>=6` | 0.8% (3) | 15% | 0% | 0% |
| `sel:simple-compound-only` | 98.1% (365) | 85% | 100% | 92% |

### Atributo: operadores
| operador | combinado | público (20) | amplo (300) | privado (52) |
|---|---|---|---|---|
| `presence` | 91.7% (341) | 40% | 100% | 63% |
| `=` | 0.3% (1) | 5% | 0% | 0% |

### Atributo: nomes (lista branca)
| atributo | combinado | público (20) | amplo (300) | privado (52) |
|---|---|---|---|---|
| `href` | 82.0% (305) | 25% | 100% | 0% |
| `title` | 2.7% (10) | 0% | 3% | 0% |
| `class` | 0.3% (1) | 0% | 0% | 0% |

### Pseudo-classes
| pseudo-classe | combinado | público (20) | amplo (300) | privado (52) |
|---|---|---|---|---|
| `hover` | 11.6% (43) | 30% | 10% | 15% |
| `link` | 11.0% (41) | 15% | 12% | 4% |
| `visited` | 9.9% (37) | 15% | 11% | 4% |
| `active` | 8.3% (31) | 5% | 2% | 44% |
| `first-child` | 4.3% (16) | 0% | 4% | 6% |
| `not` | 1.1% (4) | 15% | 0% | 2% |
| `root` | 0.8% (3) | 15% | 0% | 0% |
| `first-of-type` | 0.5% (2) | 0% | 0% | 4% |
| `lang` | 0.5% (2) | 5% | 0% | 2% |

### Pseudo-elementos (inclui sintaxe legada `:before`)
| pseudo-elemento | combinado | público (20) | amplo (300) | privado (52) |
|---|---|---|---|---|
| `first-letter` | 7.8% (29) | 0% | 10% | 0% |
| `after` | 5.1% (19) | 20% | 3% | 13% |
| `before` | 1.9% (7) | 20% | 1% | 2% |
| `first-line` | 0.5% (2) | 0% | 1% | 0% |

## At-rules
| at-rule | combinado | público (20) | amplo (300) | privado (52) |
|---|---|---|---|---|
| `charset` | 85.8% (319) | 55% | 100% | 15% |
| `media` | 20.4% (76) | 30% | 23% | 2% |
| `page` | 1.6% (6) | 0% | 0% | 12% |
| `font-face` | 1.1% (4) | 20% | 0% | 0% |
| `namespace` | 1.1% (4) | 20% | 0% | 0% |
| `supports` | 0.8% (3) | 15% | 0% | 0% |

### Consultas @media (nomes/recursos)
| termo | combinado | público (20) | amplo (300) | privado (52) |
|---|---|---|---|---|
| `all` | 15.6% (58) | 25% | 18% | 0% |
| `print` | 5.4% (20) | 5% | 6% | 0% |
| `screen` | 3.8% (14) | 10% | 4% | 2% |
| `and` | 1.3% (5) | 15% | 0% | 2% |
| `(prefers-color-scheme)` | 1.1% (4) | 15% | 0% | 2% |
| `comma-list` | 0.8% (3) | 0% | 1% | 0% |
| `(max-width)` | 0.5% (2) | 0% | 0% | 2% |
| `aural` | 0.3% (1) | 5% | 0% | 0% |

### @media — consultas completas mais comuns (todos os corpora públicos/amplo; privado omitido)

- `all`: 55 livros
- `print`: 17 livros
- `screen`: 10 livros
- `all and (prefers-color-scheme: dark)`: 3 livros
- `all and (prefers-color-scheme)`: 3 livros
- `screen, print`: 3 livros
- `aural`: 1 livros
- `screen and (max-width: 1500px)`: 1 livros

### @supports (condições, públicos/amplo)
- `(font-size: 0)`: 3
- `(filter: invert(100%))`: 3
- `(display: flex) and (min-height: calc(98vh - 3em))`: 1

### @import
| forma | combinado | público (20) | amplo (300) | privado (52) |
|---|---|---|---|---|

### @font-face: formatos e descritores
| format() | combinado | público (20) | amplo (300) | privado (52) |
|---|---|---|---|---|
| `truetype` | 0.3% (1) | 5% | 0% | 0% |

| descritor | combinado | público (20) | amplo (300) | privado (52) |
|---|---|---|---|---|
| `font-family` | 1.1% (4) | 20% | 0% | 0% |
| `src` | 1.1% (4) | 20% | 0% | 0% |
| `font-style` | 0.5% (2) | 10% | 0% | 0% |
| `font-weight` | 0.5% (2) | 10% | 0% | 0% |
| `unicode-range` | 0.3% (1) | 5% | 0% | 0% |

| src | combinado | público (20) | amplo (300) | privado (52) |
|---|---|---|---|---|

### @page: descritores
| descritor | combinado | público (20) | amplo (300) | privado (52) |
|---|---|---|---|---|
| `margin` | 1.3% (5) | 0% | 0% | 10% |
| `padding` | 1.3% (5) | 0% | 0% | 10% |
| `margin-bottom` | 1.1% (4) | 0% | 0% | 8% |
| `margin-top` | 1.1% (4) | 0% | 0% | 8% |
| `margin-left` | 0.3% (1) | 0% | 0% | 2% |
| `margin-right` | 0.3% (1) | 0% | 0% | 2% |

## Flags
| item | combinado | público | amplo | privado |
|---|---|---|---|---|
| !important | 10.5% (39) | 20% | 1% | 63% |
| var() / custom properties (--*) | 0.0% (0) | 0% | 0% | 0% |
|   var() | 0.0% (0) | 0% | 0% | 0% |
|   custom property declarada | 0.0% (0) | 0% | 0% | 0% |
| calc() | 0.3% (1) | 5% | 0% | 0% |
| min()/max()/clamp() | 0.0% (0) | 0% | 0% | 0% |
| url() | 0.0% (0) | 0% | 0% | 0% |
| gradientes | 0.0% (0) | 0% | 0% | 0% |
| counter()/counters() | 0.3% (1) | 0% | 0% | 0% |
| attr() | 2.2% (8) | 5% | 2% | 0% |
| rgb()/rgba() | 7.8% (29) | 10% | 1% | 44% |
| hsl()/hsla() | 0.0% (0) | 0% | 0% | 0% |
| cor hexadecimal | 54.6% (203) | 40% | 56% | 50% |
| transform functions | 0.0% (0) | 0% | 0% | 0% |

### Propriedades mais usadas com !important
| propriedade | combinado | público (20) | amplo (300) | privado (52) |
|---|---|---|---|---|
| `line-height` | 8.9% (33) | 0% | 0% | 63% |
| `text-align` | 8.9% (33) | 0% | 0% | 63% |
| `width` | 8.9% (33) | 0% | 0% | 63% |
| `background` | 0.8% (3) | 15% | 0% | 0% |
| `font-style` | 0.8% (3) | 15% | 0% | 0% |
| `hanging-punctuation` | 0.8% (3) | 15% | 0% | 0% |
| `text-indent` | 0.5% (2) | 0% | 1% | 0% |
| `border` | 0.3% (1) | 0% | 0% | 0% |
| `color` | 0.3% (1) | 5% | 0% | 0% |
| `margin` | 0.3% (1) | 0% | 0% | 0% |
| `padding` | 0.3% (1) | 0% | 0% | 0% |
| `padding-left` | 0.3% (1) | 0% | 0% | 0% |

## Recursos de layout (% de livros, CSS apenas)

| item | combinado | público | amplo | privado |
|---|---|---|---|---|
| display: table/table-* (qualquer) | 6.7% (25) | 5% | 8% | 2% |
|   display: table | 4.0% (15) | 5% | 4% | 2% |
|   display: table-cell | 1.1% (4) | 0% | 1% | 2% |
| float (valor != none) | 7.0% (26) | 10% | 8% | 0% |
|   float: left | 5.9% (22) | 5% | 7% | 0% |
|   float: right | 2.4% (9) | 5% | 3% | 0% |
| float qualquer (inclui none) | 9.9% (37) | 10% | 12% | 0% |
| position: absolute/fixed | 1.9% (7) | 30% | 0% | 0% |
|   position: absolute | 1.9% (7) | 30% | 0% | 0% |
|   position: fixed | 0.0% (0) | 0% | 0% | 0% |
|   position: relative | 0.5% (2) | 0% | 1% | 0% |
|   position: sticky | 0.0% (0) | 0% | 0% | 0% |
| writing-mode (qualquer prefixo) | 0.8% (3) | 15% | 0% | 0% |
|   valor vertical-* | 0.5% (2) | 10% | 0% | 0% |
| columns (column-count/width/columns/gap/rule, qualquer prefixo) | 0.0% (0) | 0% | 0% | 0% |
| flex (display ou propriedades flex*) | 2.7% (10) | 5% | 3% | 0% |
| grid (display ou propriedades grid*) | 0.0% (0) | 0% | 0% | 0% |
| display: inline-block | 18.8% (70) | 15% | 22% | 4% |
| display: none | 36.3% (135) | 35% | 31% | 65% |
| display: list-item | 0.0% (0) | 0% | 0% | 0% |
| display: run-in | 0.0% (0) | 0% | 0% | 0% |
| transform | 0.0% (0) | 0% | 0% | 0% |
| transition/animation | 0.0% (0) | 0% | 0% | 0% |
| opacity | 0.5% (2) | 0% | 0% | 4% |
| box-shadow/text-shadow | 1.6% (6) | 0% | 0% | 12% |
| border-radius | 5.6% (21) | 0% | 0% | 40% |
| background-image/background com url | 0.0% (0) | 0% | 0% | 0% |
| page-break-* / break-* | 95.7% (356) | 40% | 100% | 92% |
| orphans/widows | 12.4% (46) | 0% | 0% | 87% |
| hyphens (qualquer prefixo) | 4.8% (18) | 15% | 0% | 29% |
| ruby / text-emphasis / text-combine | 0.3% (1) | 5% | 0% | 0% |
| content (geração de conteúdo) | 5.9% (22) | 25% | 3% | 15% |
| counter-reset/-increment | 0.3% (1) | 0% | 0% | 0% |
| inline style= com propriedades de layout (float/position/display) | 9.4% (35) | 5% | 11% | 2% |

## Cortes de escopo (cobertura)

Método: ordena-se as propriedades por % de livros; para um corte de k propriedades, "livro totalmente coberto" = todas as propriedades que ele usa estão entre as k primeiras. Também "declarações cobertas" = fração média, por livro, das declarações (ocorrências) cuja propriedade está no corte. Livros sem declaração contam como cobertos. Para o corte por livros inclusive pesando cada corpus por igual, veja a coluna "equilibrado".

### Propriedades: livros totalmente cobertos pelo top-k
| k | combinado | público | amplo | privado | equilibrado |
|---|---|---|---|---|---|
| 10 | 1.3% | 15% | 0% | 4% | 6.3% |
| 20 | 2.7% | 15% | 2% | 4% | 6.8% |
| 30 | 27.4% | 15% | 32% | 8% | 18.1% |
| 40 | 48.1% | 35% | 56% | 8% | 32.9% |
| 50 | 66.7% | 35% | 78% | 12% | 41.6% |
| 60 | 83.1% | 40% | 89% | 65% | 64.8% |
| 80 | 93.8% | 70% | 96% | 90% | 85.5% |
| 100 | 97.6% | 80% | 99% | 98% | 92.2% |
| 120 | 100.0% | 100% | 100% | 100% | 100.0% |
| 150 | 100.0% | 100% | 100% | 100% | 100.0% |
| 200 | 100.0% | 100% | 100% | 100% | 100.0% |
| 115 | 100.0% | 100% | 100% | 100% | 100.0% |

- k mínimo para >=90% dos livros totalmente cobertos: combinado **69**, equilibrado **90**, privado **69**, público **103**.

- k mínimo para >=95% dos livros totalmente cobertos: combinado **85**, equilibrado **103**, privado **91**, público **114**.

- k mínimo para >=99% dos livros totalmente cobertos: combinado **108**, equilibrado **115**, privado **105**, público **115**.

### Propriedades: fração das declarações cobertas (média por livro / pior livro / percentil 5)
| k | média | mínimo | p5 |
|---|---|---|---|
| 10 | 49.7% | 6.4% | 21.9% |
| 20 | 85.0% | 14.4% | 64.0% |
| 30 | 95.5% | 14.7% | 81.8% |
| 40 | 97.6% | 23.7% | 88.4% |
| 60 | 99.3% | 50.0% | 97.2% |
| 80 | 99.8% | 50.0% | 99.4% |
| 100 | 100.0% | 95.7% | 100.0% |

Propriedades até o ponto de >=95% e >=99% de livros totalmente cobertos (lista, combinado):

- **>=95% (k=85)**: `font-size`, `margin`, `text-align`, `padding`, `display`, `max-width`, `width`, `margin-left`, `border`, `font-family`, `margin-right`, `text-decoration`, `page-break-after`, `color`, `margin-top`, `page-break-before`, `margin-bottom`, `padding-top`, `text-indent`, `background-color`, `font-weight`, `clear`, `line-height`, `padding-left`, `font-variant`, `font-style`, `vertical-align`, `height`, `letter-spacing`, `padding-right`, `list-style-type`, `visibility`, `border-collapse`, `page-break-inside`, `background`, `border-bottom`, `padding-bottom`, `word-spacing`, `max-height`, `border-top`, `orphans`, `widows`, `border-left`, `text-transform`, `float`, `border-right`, `white-space`, `border-style`, `border-width`, `min-height`, `content`, `border-color`, `border-radius`, `overflow`, `-webkit-hyphens`, `list-style`, `border-spacing`, `break-inside`, `hyphens`, `min-width`, `position`, `break-after`, `justify-content`, `left`, `font`, `-epub-hyphens`, `-webkit-box-shadow`, `-webkit-tap-highlight-color`, `overflow-wrap`, `-moz-hyphens`, `adobe-hyphenate`, `filter`, `top`, `adobe-text-layout`, `all`, `font-variant-numeric`, `hanging-punctuation`, `pointer-events`, `text-wrap`, `z-index`, `-epub-writing-mode`, `background-image`, `background-repeat`, `break-before`, `empty-cells`
- **Acréscimo para >=99% (k=108)**: `opacity`, `table-layout`, `-epub-text-combine`, `-epub-text-emphasis-color`, `-epub-text-emphasis-style`, `-ms-hyphens`, `-webkit-filter`, `align-items`, `background-attachment`, `background-position`, `background-size`, `border-bottom-style`, `border-top-color`, `border-top-width`, `box-sizing`, `counter-increment`, `direction`, `flex-direction`, `list-style-position`, `object-fit`, `pause-before`, `richness`, `right`

### Pseudo-classes: livros totalmente cobertos pelo top-k
| k | combinado | público | amplo | privado |
|---|---|---|---|---|
| 0 (`-`) | 75.3% | 55% | 82% | 42% |
| 1 (`hover`) | 77.4% | 70% | 84% | 42% |
| 2 (`link`) | 78.2% | 70% | 85% | 42% |
| 3 (`visited`) | 85.5% | 80% | 93% | 42% |
| 4 (`active`) | 93.5% | 80% | 96% | 87% |
| 5 (`first-child`) | 97.8% | 80% | 100% | 92% |
| 6 (`not`) | 98.1% | 80% | 100% | 94% |
| 7 (`root`) | 98.9% | 95% | 100% | 94% |
| 8 (`first-of-type`) | 99.5% | 95% | 100% | 98% |
| 9 (`lang`) | 100.0% | 100% | 100% | 100% |

### Pseudo-elementos: livros totalmente cobertos pelo top-k
| k | combinado | público | amplo | privado |
|---|---|---|---|---|
| 0 (`-`) | 87.1% | 75% | 88% | 85% |
| 1 (`first-letter`) | 93.5% | 75% | 96% | 85% |
| 2 (`after`) | 97.6% | 80% | 99% | 98% |
| 3 (`before`) | 99.5% | 100% | 99% | 100% |
| 4 (`first-line`) | 100.0% | 100% | 100% | 100% |

### At-rules: livros totalmente cobertos pelo top-k
| k | combinado | público | amplo | privado |
|---|---|---|---|---|
| 0 (`-`) | 11.6% | 25% | 0% | 73% |
| 1 (`charset`) | 76.6% | 45% | 77% | 87% |
| 2 (`media`) | 96.2% | 60% | 100% | 88% |
| 3 (`page`) | 97.8% | 60% | 100% | 100% |
| 4 (`font-face`) | 98.9% | 80% | 100% | 100% |
| 5 (`namespace`) | 99.2% | 85% | 100% | 100% |
| 6 (`supports`) | 100.0% | 100% | 100% | 100% |

### Termos de @media: livros totalmente cobertos pelo top-k
| k | combinado | público | amplo | privado |
|---|---|---|---|---|
| 0 (`-`) | 79.6% | 70% | 77% | 98% |
| 1 (`all`) | 91.4% | 75% | 91% | 98% |
| 2 (`print`) | 95.4% | 75% | 96% | 98% |
| 3 (`screen`) | 97.6% | 80% | 99% | 98% |
| 4 (`and`) | 97.6% | 80% | 99% | 98% |
| 5 (`(prefers-color-scheme)`) | 98.4% | 95% | 99% | 98% |
| 6 (`comma-list`) | 99.2% | 95% | 100% | 98% |
| 7 (`(max-width)`) | 99.7% | 95% | 100% | 100% |
| 8 (`aural`) | 100.0% | 100% | 100% | 100% |

### Seletores: livros totalmente cobertos se o motor suportar apenas o conjunto
| conjunto suportado | combinado |
|---|---|
| type, class | 2.7% |
| type, class, descendant | 3.2% |
| type, class, descendant, child | 3.2% |
| type, class, descendant, child, id | 4.0% |
| type, class, descendant, child, id, universal | 4.3% |
| type, class, descendant, child, id, universal, adjacent-sibling | 4.3% |
| type, class, descendant, child, id, universal, adjacent-sibling, attribute | 68.5% |
| type, class, descendant, child, id, universal, adjacent-sibling, attribute, general-sibling | 68.5% |

(Só tipos de seletor, sem nenhuma pseudo-classe/elemento; esses entram nas tabelas acima. Linha final = todos os combinadores/atributos, sem pseudos.)

### Seletores completos + pseudos incrementais (combinado, ordenados por prevalência)
| acrescentado (cumulativo) | livros cobertos |
|---|---|
| hover | 69.6% |
| link | 69.9% |
| visited | 76.9% |
| active | 84.4% |
| ::first-letter | 89.8% |
| ::after | 92.5% |
| first-child | 96.5% |
| ::before | 97.3% |
| not | 97.6% |
| root | 98.4% |
| lang | 98.9% |
| first-of-type | 99.5% |
| ::first-line | 100.0% |
## Apêndice: só livros não-PG (público + privado, 72 livros)

O amplo (Gutenberg) injeta a folha padrão `pgepub.css` em todo livro (seletores `a[href]`, `#pg-header`, `page-break-*`, `@charset`), o que infla seletor de atributo, id, `@charset` e `page-break-*` no combinado. Aqui, o mesmo levantamento sem ele.

**Propriedades top 40**: `font-size` 88%, `margin` 86%, `text-align` 86%, `padding` 85%, `font-weight` 82%, `display` 82%, `margin-top` 81%, `height` 79%, `line-height` 78%, `max-width` 76%, `text-indent` 74%, `width` 74%, `margin-bottom` 72%, `max-height` 71%, `margin-left` 68%, `page-break-inside` 65%, `border` 62%, `letter-spacing` 62%, `widows` 62%, `orphans` 62%, `font-family` 61%, `margin-right` 61%, `text-decoration` 58%, `vertical-align` 58%, `page-break-after` 57%, `font-style` 57%, `color` 54%, `list-style-type` 54%, `border-collapse` 53%, `clear` 51%, `word-spacing` 51%, `visibility` 47%, `padding-left` 47%, `page-break-before` 46%, `padding-top` 42%, `background` 39%, `padding-right` 36%, `min-height` 33%, `padding-bottom` 32%, `border-radius` 29%

**Seletores**: simple-compound-only 90%, type 89%, class 88%, type.class 85%, descendant 79%, attribute 58%, id 56%, adjacent-sibling 18%, child 18%, compound-multi-class 11%, depth>=4 7%, universal 7%, depth>=6 4%

**Pseudo-classes**: active 33%, hover 19%, link 7%, visited 7%, not 6%, root 4%, first-child 4%, lang 3%, first-of-type 3%

**Pseudo-elementos**: after 15%, before 7%

**At-rules**: charset 26%, media 10%, page 8%, font-face 6%, namespace 6%, supports 4%

**Flags**: important 51%, calc() 1%
