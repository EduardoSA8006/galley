# S4 — Layout de tabela

**Data:** 2026-09-25. **Ambiente:** Flutter 3.47.5 stable (Dart 3.13.4),
`flutter_tester` em JIT, fonte FlutterTest (1 glifo = fontSize px; altura de
linha = fontSize). **Código:** `test/spike/support/s4_table_layout.dart`,
`test/spike/s4_table_layout_test.dart` (16 testes, todos passam).

## Pergunta

O algoritmo de tabela de doc/04 §9 (Emenda 12) — min/max content por célula
com `ui.Paragraph`, distribuição de colunas, `colspan`/`rowspan`, escala até
0.8×, rolagem horizontal como degradação declarada, linha como unidade de
quebra, cabeçalho repetido — produz layouts corretos, e a que custo?

## Como foi feito

- `ui.ParagraphBuilder`/`ui.Paragraph` direto, sem widgets. Modelo
  `TableModel → RowModel → CellModel{text, colSpan, rowSpan, isHeader}`; saída
  `TableLayout{colWidths, rowHeights, cellRects, scale, overflow, pages}`.
- **Grade** como no modelo de tabela do HTML: cada célula vai para o primeiro
  slot livre da linha, pulando slots ocupados por `rowSpan` de cima.
- **Medir → colunas → distribuir → layout final → linhas → paginar**, na ordem
  de doc/04 §9. Padding de 4 px por lado entra em min/max (`+ 2×padding`).
- O trabalho é um `sync*` que cede depois de cada célula: o mesmo código roda
  inteiro ou fatiado no orçamento de 4 ms de doc/08 §2.
- Variantes medidas lado a lado, para separar o que o texto de doc/04 diz do
  que funciona:
  - `MinContentProbe.docLiteral` (leitura literal: `maxIntrinsicWidth` após
    `layout(0)`, `longestLine` após `layout(∞)`, 3 layouts por célula) contra
    `infinityOnly` (um `layout(∞)` dá as duas medidas, 2 layouts por célula);
  - `SpanDistribution.equal` (doc/04: divisão igual) contra `deficit` (estilo
    CSS: só reparte o que falta);
  - `ScaleMode.rebuildFont` (reconstruir cada parágrafo com `fontSize × s`)
    contra `transform` (layout em 1× na largura / s, pintura com
    `canvas.scale(s)`).

## 1. O que `layout(0)` e `layout(∞)` fazem de fato

Texto `abc defgh ij` (palavra mais longa `defgh` = 50 px; linha inteira 120 px):

| Após | `minIntrinsicWidth` | `maxIntrinsicWidth` | `longestLine` | Linhas |
|---|---|---|---|---|
| `layout(0)` | **10** (1 glifo) | **120** (max-content) | 10 | 10 (1 glifo por linha) |
| `layout(∞)` | **50** (palavra) | 120 | **120** | 1 |

- **`layout(width: 0)` não devolve a palavra mais longa nem zero.** Quebra por
  caractere (um glifo por linha); `maxIntrinsicWidth` passa a ser o
  max-content, e `minIntrinsicWidth`/`longestLine` são a largura de um glifo.
  Com quebra dura, `maxIntrinsicWidth` após `layout(0)` ainda **soma as linhas
  duras**: `x\ny long` dá 80 após `layout(0)` e 60 (correto) após `layout(∞)`.
- **`double.infinity` é aceito** (`paragraph.width == Infinity`) e é a única
  largura que dá as duas medidas certas de uma vez: `minIntrinsicWidth` = palavra
  mais longa, `longestLine` = max-content. `1e6` dá os mesmos valores.
- **`minIntrinsicWidth` depende da largura do último `layout`**: após
  `layout(35)` em `x\ny long` (palavra de 40 px) ele cai para 10. Só é confiável
  com largura ≥ palavra mais longa, isto é, com `∞`.
- `layout(0)` é o layout mais caro dos três: 40 palavras, 1000 build+layout,
  71 ms com largura 0 contra 16 ms com `∞` (um glifo por linha gera centenas de
  linhas).
- **O shaping acontece no primeiro `layout`**; os seguintes no mesmo parágrafo
  só refazem a quebra de linha (8 palavras, parágrafos frios: `layout(∞)`
  21,3 µs, re-layout em 60 px 5,5 µs, em 200 px 3,7 µs). O SkParagraph também
  guarda o shaping de ~128 parágrafos por (texto, estilo): repetir o mesmo
  conjunto de ≤ 128 textos custa ~10 µs por parágrafo, com 140 ou mais volta a
  ~26 µs. Os números de custo abaixo usam textos novos a cada execução.

Casos limite da medição:

| Texto | `minIntrinsicWidth` | `longestLine` | Observação |
|---|---|---|---|
| `''` | 0 | **−3,4e38** (−FLT_MAX) | precisa ser zerado; altura 10 (uma linha) |
| `' '` | **1,2e−38** (FLT_MIN) | 10 | só espaço: zerar o min |
| `'abc '` | 30 | 30 | `maxIntrinsicWidth` = 40 inclui o espaço final; `longestLine` não |
| `Para­lele­pipedo` (2 U+00AD) | **140** | 140 | o min **ignora** o soft hyphen como oportunidade de quebra |
| URL de 33 caracteres | 330 | 330 | min = URL inteira: força escala ou overflow |
| `日本語のテキスト` | 10 | 80 | CJK: min = 1 ideograma |

## 2. Resultados

| # | Teste | Resultado |
|---|---|---|
| 1 | 3×3 que cabe (W = 400) | colunas = colMax `[58, 58, 148]`, scale 1, largura 264 < W (sobra vai para margem) |
| 2 | ΣcolMin = 294 ≤ W = 604 < ΣcolMax = 914 | proporcional `[118, 318, 168]`, **Σ = W** exato, cada coluna igual à fórmula com erro < 1e−9 |
| 3 | W = 0,9 × ΣcolMin | scale **0,9**, cabe (Σ = 192,6 = W), nenhuma quebra por caractere; `transform` dá as mesmas alturas com metade dos builds (9 contra 18) |
| 4 | W = 0,5 × ΣcolMin | scale **0,8**, `overflow`, largura **171,2 = 0,8 × 214**, diagnóstico `tableOverflow` |
| L | Leitura literal (célula de 44 caracteres em W = 200) | literal: colMin = colMax = `[438, 28]`, escala 0,8 e **overflow**; corrigido: colMin `[88, 28]`, regime proporcional, cabe em 200 sem escala |
| 5 | `colspan=2` no cabeçalho | retângulo cobre exatamente as colunas 0–1 nos dois modos. `equal`: coluna "b" (conteúdo 18 px) vai a colMax **99**, soma 377 contra 296 necessários (**+81 px**). `deficit`: `[278, 18]`, soma 296, inflação 0; span mais largo que as colunas: soma = largura do span exata |
| 6 | `rowspan=2` com 5 linhas duras (58 px) sobre linhas de 18 | rowHeights `[18, 40, 18]`: a última linha coberta cresce 22; retângulo = 58 = soma das duas. Rowspan mais baixo que a soma: nada estica |
| — | Casos limite da grade | ver §3 |
| 7 | Propriedade, 200 tabelas `Random(7)` (1–8 colunas, 1–30 linhas, 1–40 palavras, 13 900 células, spans esporádicos, W 150–1500, os 4 pares de modo) | **200/200** sem sobreposição, todos os retângulos dentro da caixa, retângulo ≥ altura do conteúdo, largura ≤ W quando não há overflow, **0 quebras por caractere** no layout final. Regimes: cabe 1, proporcional 79, escala 15, overflow 105; colSpan truncado em 103 tabelas, rowSpan truncado em 103 |
| 8 | 60 linhas com `thead`, W = 360, H = 600 | 9 páginas; cabeçalho `[0]` no topo das páginas 2–9; união das linhas de conteúdo = 0..59 cada uma uma vez; nenhuma página > 600; toda fronteira é "a próxima linha não caberia" |
| — | Rowspan e linha > H (H = 100) | grupo de 3 linhas ligadas fica na mesma página; linha de 128 px vira página própria **com cabeçalho** (146 px), `indivisible`; rowspan de 20 linhas (360 px) é **quebrado entre linhas** em 5 páginas (`fragmentedRowSpan`), nenhuma linha perdida |
| — | Cabeçalho de 48 px em H = 80 | não repetido (`headerNotRepeated`), ver §4 |

### Custo (teste 9)

Cabeçalho `Coluna k` + linhas de 1–15 palavras de 1–12 letras (média ~60
caracteres por célula), textos novos a cada execução, mediana de 5 após
aquecimento. "Cabe" = W 20 000 (scale 1); "escala" = W 360 (scale 0,8, overflow).

| Tabela | Variante | Layouts/célula | Builds | Cabe | Escala |
|---|---|---|---|---|---|
| 20×5 | `docLiteral` | 3 | 100 / 200 | 3 854 µs (38,5/célula) | 6 643 µs |
| 20×5 | `infinityOnly` + `rebuildFont` | 2 | 100 / 200 | **2 964 µs** (29,6/célula) | 5 490 µs |
| 20×5 | `infinityOnly` + `transform` | 2 | 100 / 100 | 2 876 µs | **4 621 µs** |
| 200×8 | `docLiteral` | 3 | 1 600 / 3 200 | 73 091 µs (45,7/célula) | 113 608 µs |
| 200×8 | `infinityOnly` + `rebuildFont` | 2 | 1 600 / 3 200 | **51 091 µs** (31,9/célula) | 98 219 µs |
| 200×8 | `infinityOnly` + `transform` | 2 | 1 600 / 1 600 | 50 165 µs | **53 172 µs** |

A contagem de layouts foi verificada célula a célula: exatamente 3 (`layout(0)`,
`layout(∞)`, final) na leitura literal e exatamente 2 (`layout(∞)`, final) na
corrigida. Com a mesma tabela repetida (cache do SkParagraph quente), 20×5 cabe
em ~1 000 µs (10 µs/célula): o número frio é o que vale para um livro.

**Fatiado a 4 ms** (`TableLayoutJob.steps()`, um passo por célula medida e por
célula com layout final, `infinityOnly` + `rebuildFont`):

| Tabela | W | Fatias | Maior fatia | Passo mais longo | Total |
|---|---|---|---|---|---|
| 20×5 | 20 000 | 1 | 3 189 µs | 115 µs | 3 189 µs |
| 20×5 | 360 | 2 | 4 028 µs | 181 µs | 5 707 µs |
| 200×8 | 20 000 | 13 | 4 030 µs | 711 µs | 49 566 µs |
| 200×8 | 360 | 24 | 4 062 µs | 1 565 µs | 95 867 µs |

Um passo típico custa 15–70 µs; os picos de 0,7–1,6 ms são isolados (GC/JIT) e
cabem no orçamento. A maior fatia passa de 4 000 µs só pelo último passo, como no
agendador de doc/08 §2.

## 3. Casos limite encontrados

- **Célula vazia**: `longestLine` = −FLT_MAX; sem zerar, colMax fica negativo.
  Zerada, a célula mede só o padding (8 px) e tem altura de uma linha vazia
  (10 + 8 = 18 px), não zero. Célula só com espaço: `minIntrinsicWidth` = FLT_MIN.
- **Uma coluna**: sem caso especial; 5 células de 30 palavras em W = 200 ficam
  no regime proporcional com a coluna em exatamente 200.
- **Spans que saem da grade** (`[a rs=5, b, c rs=0] / [d cs=3] / [e]` em 3 linhas):
  `rowSpan=5` truncado para 3 (`truncatedRowSpan`); `rowSpan=0` segue o HTML e
  vai até o fim (3); `d cs=3` colide com o slot de `c` e é truncado para 1
  (`truncatedColSpan`); `e` vai para a coluna 1. O HTML deixaria `d` e `c` se
  sobreporem ("table model error"); truncar é o que garante a propriedade 7.
  Linha com menos células que as outras deixa slots vazios, sem retângulo.
- **Soft hyphen**: `minIntrinsicWidth` trata a palavra com U+00AD como
  inquebrável, embora o `ui.Paragraph` quebre nela (S5). Com hifenização (v1.2),
  o min-content fica maior do que o necessário e empurra tabelas para a escala.
- **URL ou palavra muito longa**: min-content = palavra inteira; uma única célula
  com URL de 33 caracteres já exige 338 px de coluna. É o caminho mais comum para
  `tableOverflow` em livro técnico.
- **Arredondamento em tamanho fracionário** (`rebuildFont`): com FlutterTest o
  avanço em 8,333 px é 8,328 (quantizado), e a altura de linha é arredondada
  para inteiro (9,12 → 9). Aqui o arredondamento foi para baixo e não houve
  quebra por caractere em 13 900 células, mas com fonte real nada garante o
  sentido; `transform` elimina o problema porque faz o layout em 1× na largura
  exata do min-content.
- **Rowspan maior que a página**: a regra "linhas ligadas por rowSpan ficam na
  mesma página" levada ao pé da letra põe 20 linhas numa página só e clipa quase
  tudo. O protótipo mantém o grupo junto quando ele cabe numa página vazia e, se
  não cabe, quebra entre as linhas do grupo (a célula com rowSpan é fragmentada
  como um parágrafo, `fragmentedRowSpan`). Só a linha isolada maior que a página
  vira `indivisible`.
- **Cabeçalho alto**: repetido em toda página ele pode comer a página inteira.
  Política do protótipo: repetir só se o grupo do cabeçalho tiver ≤ 50% de H
  (`headerNotRepeated` caso contrário). A progressão é garantida mesmo sem a
  regra (cada página leva pelo menos uma linha), a regra evita desperdício.
- Não tratados: `rowSpan` saindo do cabeçalho para o corpo (o grupo do
  cabeçalho passaria a incluir linhas do corpo e elas seriam repetidas); tabela
  começando no meio de uma página (primeira página com altura menor que H).

## 4. Leitura dos números

- **Correção**: com as duas correções de medição (min = `minIntrinsicWidth`
  após `layout(∞)`, valores sentinela zerados) o algoritmo produz layouts
  corretos em todos os regimes: 200/200 tabelas aleatórias sem sobreposição,
  dentro da caixa e sem quebra por caractere; paginação com cobertura exata e
  cabeçalho repetido.
- **Custo**: o que pesa é o **shaping**, uma vez por build. Os layouts extras
  no mesmo parágrafo são baratos (4–6 µs), exceto `layout(0)`. Por isso
  "3 layouts por célula" custa ~30% a mais que 2 (38,5 contra 29,6 µs/célula em
  20×5), e reconstruir o parágrafo para aplicar a escala custa quase o dobro
  (98 ms contra 53 ms em 200×8), porque refaz o shaping com outro tamanho.
- **Orçamento de 4 ms**: 20×5 frio cabe numa fatia com folga de ~25% (2,9 ms) só
  quando não há escala; com escala e `rebuildFont` passa (5,5 ms), com
  `transform` fica no limite (4,6 ms). 200×8 custa **50 ms = 13 fatias** (98 ms =
  24 fatias com `rebuildFont`). **A tabela precisa ser medida em fatias**, com a
  célula como unidade; o algoritmo permite isso sem esforço porque medir é
  independente por célula e a distribuição é O(células) e barata.
- **Dependência global**: a largura das colunas depende de **todas** as linhas.
  Uma tabela de 200×8 na primeira página de uma seção só pode mostrar a primeira
  linha depois de medir as 1 600 células (~25 ms de medição mais os layouts
  finais da primeira página). Isso é uma exceção à "primeira página rápida" de
  doc/04 §2.3 que o texto não menciona.
- Números em JIT no `flutter_tester`; release AOT na engine real deve ser mais
  rápido, mas a proporção entre as variantes (dominada por shaping) deve se
  manter. Não foi medido na engine real (o spike é só de `test/spike/`).

## Sustenta / contradiz

| Doc | Seção | Veredito |
|---|---|---|
| 04 | §9 passo 1, "`minWidth` = `maxIntrinsicWidth` após `layout` com largura 0 (a palavra mais longa)" | **Contradiz.** `maxIntrinsicWidth` após `layout(0)` é o max-content (e soma quebras duras); `minIntrinsicWidth` após `layout(0)` é um glifo. Trocar por: "`minWidth` = `minIntrinsicWidth` e `maxWidth` = `longestLine`, ambos após **um** `layout` com largura infinita; `longestLine` de parágrafo vazio (−FLT_MAX) e `minIntrinsicWidth` de texto só com espaço (FLT_MIN) são zerados" |
| 04 | §9 passo 1, divisão igual do `colSpan` | **Contradiz em parte.** Correta no retângulo, mas infla colunas estreitas (+81 px no teste 5, coluna de 18 px levada a 99). Trocar por: "células de span 1 primeiro; depois, em ordem crescente de span, cada célula com span reparte igualmente só o **déficit** entre sua largura e a soma das colunas cobertas" |
| 04 | §9 passo 3, três regimes, piso 0.8×, rolagem horizontal | **Sustenta.** Σ = W exato nos regimes 2 e 3, largura 0,8 × ΣcolMin no overflow. Sugerir aplicar a escala por **transformação de pintura** (layout em 1× na largura / s, `canvas.scale(s)`), não reconstruindo parágrafos com fonte menor: metade dos builds, custo igual ao caso sem escala e sem risco de arredondamento de avanço em tamanho fracionário. Seleção e hit-test precisam da mesma transformação |
| 04 | §9 passo 4, alturas e rowSpan | **Sustenta.** Precisar a ordem: rowSpans resolvidos em ordem crescente de span, depois de todas as células de span 1 |
| 04 | §9 passo 5, linha como unidade e cabeçalho repetido | **Sustenta**, com três acréscimos: (a) linhas ligadas por rowSpan formam um grupo indivisível **enquanto couber numa página vazia**; se não couber, quebra entre as linhas do grupo e a célula com rowSpan é fragmentada; (b) linha maior que a página vai para página própria **com** o cabeçalho repetido; (c) política para cabeçalho alto (o protótipo usa "repetir só se ≤ 50% da página") |
| 04 | §9 "Custo: dois layouts por célula … 20 × 5 … dentro de uma fatia" | **Sustenta para 20×5 sem escala** (2,9 ms frio, 2 layouts); **contradiz** a implicação para tabelas maiores e para tabela escalada. Acrescentar: "a medição é fatiada por célula no agendador de doc/08 §2; 200×8 custa ~13 fatias de 4 ms (JIT); a tabela só pode ser paginada depois de medida inteira, o que é uma exceção declarada à primeira página rápida (§2.3)" |
| 04 | §2.3 primeira página rápida | **Contradiz** para seções que começam com tabela grande: a largura das colunas é global. Opções para decidir em revisão: aceitar e declarar; ou medir as primeiras N linhas, mostrar e repaginar quando as demais chegarem |
| 08 | §2 orçamento de 4 ms, unidade de trabalho = bloco | **Sustenta** se a tabela for fatiada por célula (passo típico 15–70 µs); **contradiz** se a tabela for tratada como um bloco atômico (50–100 ms, muito acima da tolerância de 8 ms) |
| 04 | §8 hifenização (v1.2) | Acrescentar: com U+00AD, `minIntrinsicWidth` não considera a quebra; o min-content de célula hifenizada terá de ser calculado pelo motor |
