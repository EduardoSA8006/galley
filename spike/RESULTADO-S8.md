# S8 — Paginação ancorada

**Data:** 2026-09-09. **Ambiente:** Flutter 3.44.1 stable, `flutter_tester`
(lógica pura, sem `dart:ui`). **Código:** `test/spike/support/s8_paginator.dart`,
`test/spike/s8_anchored_pagination_test.dart`.

## Pergunta

Paginar a partir de um âncora arbitrário `(bloco, linha)` — para trás até o
início da seção e para frente até o fim — cobre a seção inteira, respeita órfã,
viúva, heading e `break-before` nas duas direções, e difere da paginação a partir
de `(0, 0)` em no máximo uma página (doc/04 §3.1, Emenda 10, doc/10 Invariante 8)?

## Como foi feito

- Blocos modelados como listas de alturas de linha (18–26 px) com `kind`
  (`paragraph`, `heading`, `sceneBreak`) e `breakBefore`. Espaço entre blocos
  (12 px) conta na altura da página, nunca no topo.
- **Uma única função `isLegalBreak(t)`** decide se a fronteira entre a linha
  global `t-1` e a linha `t` é aceitável (órfã, viúva, heading no fim, heading +
  1 linha de bloco que continua, `breakBefore`, regras desligadas quando a coluna
  tem menos de 3 linhas). Paginar para frente preenche e **recua** a fronteira
  até ficar legal; paginar para trás preenche de baixo para cima e **avança** a
  fronteira até ficar legal. As regras "espelham" por construção, não por
  duplicação.
- **Snap do âncora:** antes de paginar, o âncora é movido para a fronteira legal
  mais próxima antes dele. Sem isso, a costura entre a última página de trás e a
  ancorada violaria as regras (âncora na 2ª linha de um parágrafo deixaria uma
  órfã na página anterior; âncora na última linha começaria a página com viúva).
- 500 casos com `Random(42)`: 1–80 blocos, 1–60 linhas, headings em 10%,
  `sceneBreak` em 5%, `breakBefore` em 5%, `H` de 300 a 900, âncora aleatória.

## Resultados

| Propriedade | Resultado |
|---|---|
| (a) Cobertura: união dos ranges de linha de todas as páginas == todas as linhas, sem lacuna nem sobreposição | **500/500** |
| (b) Nenhuma página excede `H` | **500/500** |
| (c) `páginas(âncora) − páginas((0,0))` | **0 em 235 casos, +1 em 265 casos, nunca −1, nunca ≥ 2** |
| (c') Âncora colocado numa fronteira real da paginação `(0,0)` | diferença ≤ 1 em todos os casos verificados (> 100) |
| (d) A página ancorada começa exatamente no âncora após snap; o âncora pedido está sempre nela | **500/500**; deslocamento máximo do snap: **2 linhas** |
| (e) Nenhuma fronteira ilegal (órfã, viúva, heading) em nenhuma das direções, quando as regras estão ativas | **500/500** |
| Unitários: órfã empurra, viúva puxa 2, heading vai com ≥ 2 linhas, heading + 1 linha empurra, `breakBefore` força, coluna < 3 linhas desliga regras, para trás espelha para frente | 7/7 |

**Tempo:** 5 000 blocos × 30 linhas = 150 000 linhas, 5 334 páginas, âncora no
meio: `paginateAnchored` em **3 753 µs** (mediana de 5; min 3 531, max 3 809).
Linear no número de linhas; irrelevante perto do shaping.

## Leitura dos números

- A diferença de contagem é **sempre 0 ou +1** e nunca negativa: a paginação
  ancorada só pode "desperdiçar" espaço na costura, nunca ganhar. A afirmação da
  Emenda 10 ("no máximo uma página") **sustenta-se** neste modelo.
- A distribuição (53% dos casos com +1) mostra que a diferença de 1 é o caso
  comum, não a exceção. A UI precisa mesmo tratar o número de página como
  efêmero, como doc/04 §3.1 já diz.
- O snap do âncora move no máximo 2 linhas para cima (viúva + órfã encadeadas, ou
  heading + 1 linha). O usuário sempre vê a linha que estava lendo na primeira
  página, no topo ou até duas linhas abaixo do topo.

## Sustenta / contradiz

| Doc | Seção | Veredito |
|---|---|---|
| 04 | §3.1 paginação ancorada | **Sustenta.** Acrescentar o **snap do âncora** ao texto: "o âncora é ajustado para a fronteira legal mais próxima antes da linha pedida (no máximo 2 linhas), para que a costura entre a página anterior e a ancorada respeite órfã, viúva e heading". Hoje o texto diz que a página "começa nela", o que só vale após o snap |
| 04 | §3.1 "diferença de no máximo uma página" | **Sustenta**, com a precisão de que a diferença é sempre 0 ou +1, nunca −1 |
| 04 | §2.2 regras de quebra | **Sustenta.** Sugestão de implementação: expressar as regras como um único predicado sobre a fronteira e usar o mesmo predicado nas duas direções, como aqui |
| 10 | Invariante 8 | **Sustenta.** Sugerir a formulação: "`páginas(âncora) − páginas((0,0)) ∈ {0, 1}`" em vez de "difere em no máximo 1", porque o sinal é informação útil e testável |
| 10 | Invariante 8, "cobre a seção inteira" | **Sustenta** |

## Limites do spike

- Alturas de linha por bloco são uniformes (um parágrafo tem todas as linhas
  iguais), o que é o caso real com `StrutStyle` (doc/04 §1). Sem strut, linhas
  de altura variável não mudam a lógica, só as somas.
- Não modela imagens maiores que a página, tabelas nem containers com
  `children`; a regra "quebra entre filhos" é a mesma lógica de fronteira e deve
  entrar no mesmo predicado na Fase 2.
- Não modela `break-after` nem `break-*: avoid`; entram como casos do predicado.
