# S2 — Seleção sobre `RenderBox` próprio

**Data:** 2026-09-25. **Ambiente:** Flutter 3.47.5 stable (Dart 3.13.4),
`flutter_tester`, fonte `FlutterTest` (1 glifo = `fontSize` = 10 px, linha de
10 px). **Código:** `test/spike/support/s2_display_map.dart`,
`test/spike/support/s2_page_render_box.dart`, `test/spike/s2_selection_test.dart`
(14 testes, todos passando).

## Pergunta

Seleção de texto sobre um `RenderBox` que pinta vários `ui.Paragraph`
clipados e transladados funciona de ponta a ponta, inclusive atravessando
blocos, atravessando "páginas" e com texto exibido diferente do canônico
(doc/05 §3, doc/04 §1.1 e §2.1, doc/13 §1.1)?

**Resposta curta: sim para o núcleo** (ponto ↔ offset canônico, retângulos,
palavra, arraste, alças simples, bloco dividido entre páginas, `text-transform`,
U+00AD, U+FFFC). Surgiram cinco achados que mudam a documentação, e um deles
(alças por plataforma) contradiz doc/05 §3.5. O que ficou fora (alças da
plataforma, auto-avanço, modo contínuo) é justamente a parte de interação que
pesa mais na estimativa da Fase 4.

## Como foi feito

- **Modelo.** `S2Section.layout` shapeia cada bloco uma vez (`ui.Paragraph`,
  coluna de 200 px) e junta os canônicos com `\n` em `canonicalText`. Após o
  `layout`, cada bloco guarda `lineTops` (alturas acumuladas de
  `computeLineMetrics`), `lineRights` e `lineStarts`. `LineMetrics` não traz o
  range de texto; `lineStarts` vem de iterar `getLineBoundary`, cujo `end`
  inclui o espaço final e coincide com o início da linha seguinte (sondado).
  `paginate` corta blocos na fronteira de linha. Um bloco dividido gera dois
  `S2Fragment` com o **mesmo** `Paragraph`, cada um com seu
  `translate = (left, yOffset − lineTops[firstLine])` e seu `clipRect`
  (doc/04 §2.1).
- **`DisplayMap`.** `DisplayMap.identity` é constante e, sem transformação,
  `buildDisplayText` devolve a **mesma** instância de `String`.
  `ChangePointMap` usa um `Uint32List` de quádruplos `(displayStart,
  canonicalStart, displayLength, canonicalLength)` só para os trechos não
  lineares, com busca binária. A semântica é a de doc/04 §1.1: dentro de `SS`,
  `toCanonical` → `ß`; dentro de um U+00AD inserido, `toCanonical` → o offset
  canônico **seguinte**. `toDisplay(c)` de um caractere precedido por inserção
  cai depois dela.
- **`S2PageRenderBox`.** Oferece `hitAt(Offset)`, que devolve `caret` e `char`,
  e `canonicalOffsetAt(Offset)`, que devolve o caret. Oferece também
  `rectsFor(start, end)`, `coveredRanges`, `wordAt(canonical)`,
  `handleAnchors` e `handleAt`. A pintura segue doc/05 §1: retângulos de
  seleção, depois o texto por fragmento (`save / clipRect / drawParagraph /
  restore`), depois o hífen pendurado de doc/04 §8 e, por cima, as alças
  (círculos).
- **Gestos.** `S2SelectablePage` usa `RawGestureDetector` com um
  `LongPressGestureRecognizer`: o long press seleciona a palavra e o arraste
  estende a partir dela. Há também um `PanGestureRecognizer` que só entra na
  arena quando o toque começa numa alça (`isPointerAllowed`). A seleção é um
  `ValueNotifier<S2Selection?>` de `(base, extent)` canônicos, fora do render
  box. Duas páginas lado a lado compartilham o mesmo controlador.

## Resultados

| # | Teste | Resultado |
|---|---|---|
| 1 | Ida e volta toque → offset → retângulo, 50 pontos `Random(2)`, na 2ª página (1º fragmento continuado, translate não trivial), 6 fragmentos, blocos com uppercase e U+00AD | **50/50** retângulos contêm o ponto; 19 dos pontos caíram em blocos com mapa não identidade; `caret ∈ {char, char+1}` em todos |
| 2 | Long press seleciona palavra de `canonicalText` | `janela` → `"janela"`; sobre o `E` de `STRASSE` → **`"straße"`** (canônico), com exibido `"STRASSE"`; as duas alças aparecem |
| 3 | Arraste de bloco para bloco | Long press em `gato` + arraste até o bloco 1 → `2..68`, texto com `\n`, retângulos nos dois fragmentos e **nenhum fora dos fragmentos**. A alça final foi arrastada até o bloco 2 e a seleção passou a cobrir 3 blocos. A alça inicial arrastada para depois da final **inverte** a seleção (base = antiga extremidade final) |
| 4 | Bloco dividido entre duas páginas (linhas 0–4 na p. 1, 5–13 na p. 2), range `91..207` | 4 + 3 retângulos, cada um dentro do fragmento da sua página; **sem clip, 3 das 7 caixas** cairiam fora do fragmento da p. 1; `r1 + r2 = caixas brutas`; união dos `coveredRanges` = range pedido, sem lacuna nem sobreposição; cada caractere tem retângulo em exatamente uma página (exceto 1 espaço final além da coluna, ver achado A2); alça inicial só na p. 1, final só na p. 2; cada página pinta exatamente os seus retângulos |
| 5 | `text-transform: uppercase` com `ß` | Toque no 2º `S` → offset canônico do `ß` (16). Caret na metade esquerda do 2º `S` → 16, na metade direita → 17. `rectsFor(ß)` → **um** retângulo `120–140` (20 px = os dois `S`), e o `E` seguinte começa em 140 |
| 6 | U+00AD inserido (`Par­alele­pipedo`, coluna de 85 px) | Caret antes e depois de cada U+00AD → mesmo offset canônico (3,3 e 8,8). `rectsFor(7, 9)` = `"ep"` em 2 linhas, sem U+00AD no texto. Hífen pendurado pintado em `(80, 0)` da linha. Toque sobre o hífen (dentro da coluna e na margem) → caret e char = **8** (`p`, o offset seguinte). U+00AD no meio da linha: toque à esquerda e à direita dão o mesmo caret, e `rectsFor` sobre `ra` soma 20 px sem retângulo de largura zero |
| 7 | Toque fora de fragmento | Margem esquerda → início da linha; margem direita → fim da linha; espaço entre blocos → fragmento mais próximo verticalmente; cantos → início e fim da página; **500 pontos aleatórios** sobre a página inteira: nenhum `null`, todos dentro do range da página |
| + | U+FFFC (imagem inline 30×20) | Um dos retângulos da seleção `figura ￼ ao` é exatamente a caixa do placeholder; toque na imagem → offset do U+FFFC |
| + | Ordem de pintura | `rect` (seleção) → `clipRect`/`paragraph` por fragmento → `circle` × 2 (alças), verificado com `paints`; trocar a seleção marca só `needsPaint`, sem `needsLayout` |
| + | `DisplayMap` | Identidade sem cópia; 300 casos `Random(7)` com `ß`, `ﬁ` e U+00AD aleatórios: `toCanonical` monotônico e `toCanonical(toDisplay(c)) == c` para todo `c` |

### 8. Custo (JIT, `flutter_tester`, mediana de 5 × 1000 chamadas, 3 execuções)

Página de **12 fragmentos**, 38 linhas e 647 caracteres canônicos, com 6 blocos
de `DisplayMap` não identidade:

| Chamada | µs por chamada |
|---|---|
| `canonicalOffsetAt` (ponto aleatório na página inteira) | **4,3 – 5,0** |
| `rectsFor` (range aleatório de até meia página) | **4,0 – 4,9** |
| `rectsFor` (página inteira) | **13 – 19** |
| `wordAt` | 1,8 – 3,5 |

Um frame de arraste chama `canonicalOffsetAt` uma vez e `rectsFor` duas (na
pintura e nas alças): cerca de 40 µs, **0,25% de um frame de 16 ms**. A busca
linear por fragmento é suficiente, e não há motivo para cachear retângulos.

## Achados que a documentação não previa

- **A1. `String.toUpperCase()` da VM não aplica SpecialCasing.** Na VM,
  `'straße'.toUpperCase()` devolve `STRAßE`; `ﬁ` e `ŉ` também não mudam, e
  `'İ'.toLowerCase()` devolve `i` com 1 unidade. O `toUpperCase` do JS faz
  `ß → SS`. Se a Camada B usar `String.toUpperCase`, o texto exibido (e com
  ele a paginação e o mapa) **diverge entre web e nativo**, e `ß → SS` nunca
  acontece fora do web. Solução: tabela própria gerada de `SpecialCasing.txt`
  (cerca de 100 entradas para maiúsculas, mais as sensíveis a locale: `tr`,
  `az`, `lt`), usada em todas as plataformas. O protótipo usa um recorte com
  `ß`, `ﬀ`, `ﬁ`, `ﬂ` e `ŉ`.
- **A2. `getBoxesForRange` devolve o espaço final de uma linha cheia fora da
  coluna.** Numa coluna de 200 px, a caixa foi de 0 a 210. O clip de
  doc/04 §2.1 é vertical (esconde as linhas do mesmo `Paragraph` que estão em
  outra página), mas o retângulo de **seleção** também precisa ser clipado na
  horizontal, à coluna do fragmento. Sem isso, o realce invade a margem direita.
  Consequência: esse espaço fica sem retângulo visível, o que é o comportamento
  certo.
- **A3. Caret e glifo são duas saídas diferentes.** `getPositionForOffset` dá o
  caret (com afinidade): um toque na metade direita do último caractere de uma
  palavra devolve o offset **depois** da palavra, e `getWordBoundary` ali
  seleciona o espaço. Long press, toque em `ß`, toque em link e toque em
  imagem precisam do caractere sob o dedo (`getClosestGlyphInfoForOffset`).
  Arraste e alças precisam do caret. O `hitAt` devolve os dois.
- **A4. `TextSelectionControls` não pinta, constrói widget.**
  `buildHandle(context, type, textLineHeight)` devolve um `Widget`. O do
  Material depende de `Theme.of(context)`/`TextSelectionTheme` e usa um painter
  privado. Um `LeafRenderObjectWidget` não consegue pintar isso. Para
  reaproveitar as formas da plataforma, as alças têm de ser **widgets numa
  camada acima da página** (dois por leitor, não por bloco), posicionados com
  `handleAnchors` do render box mais `getHandleAnchor`/`getHandleSize` dos
  controles, como o `SelectionOverlay` do framework faz com
  `CompositedTransformFollower`.
- **A5. Arraste de alça precisa de `DragStartBehavior.down`.** Com o padrão
  (`start`), `onStart` recebe a posição onde o pan foi aceito, que fica
  `kPanSlop` = 36 px depois do toque. Foi o que fez o teste 3 falhar na primeira
  versão. Além disso, o recognizer da alça só pode entrar na arena quando o toque
  começa sobre ela (`isPointerAllowed`); caso contrário, disputa com a virada de
  página.
- **A6 (menor). Retângulos de altura mista na linha da imagem.** Na linha com
  U+FFFC, o texto dá caixas de 10 px (25–35) e a imagem de 20 px (20–40), então
  o realce fica "serrilhado". Se a Fase 4 quiser realce uniforme, deve
  normalizar a altura pelos `lineTops` da linha. É decisão visual, não bug.
- **A7 (menor). O separador `\n` não pertence a fragmento nenhum.** A união dos
  ranges cobertos de uma seleção que atravessa blocos tem um "buraco" de 1
  caractere por separador. O texto vem de `canonicalText` e inclui o `\n`
  (teste 3), então nada quebra, mas invariantes de "cobertura" precisam
  excluir os separadores.

## Os itens de doc/13 §1.1

| Item | O que o protótipo provou | O que ficou fora |
|---|---|---|
| Extensão **através de blocos** (range de offsets × alças visuais, nas bordas) | Long press + arraste e arraste de alça atravessam blocos; alça invertida mantém `base`; nenhum retângulo fora de fragmento; as bordas (fim de linha, espaço final, separador) funcionam com A2 e A7 | Triplo toque (bloco), duplo toque (palavra) e as regras de "snap" por palavra durante a extensão, que variam por plataforma |
| Extensão **através de páginas** com auto-avanço | Um range que começa na p. 1 e termina na p. 2 renderiza certo nas duas páginas (clip, cobertura exata, cada caractere numa página só), e cada alça aparece só na página que contém a sua extremidade | **Auto-avanço** (permanência de 500 ms na borda), continuidade do gesto durante a virada e alça de uma extremidade que está em página não visível. Achado de desenho: o reconhecedor do arraste de seleção precisa ficar **acima** do carrossel de páginas, não em cada página, porque o gesto continua depois que o render box sob o dedo muda |
| Alças por **convenção da plataforma** via `TextSelectionControls` | Nada; só círculos. Ver A4 e A5 | Forma, tamanho e âncora Material/Cupertino, lupa (`TextMagnifier`), háptico, espelhamento em RTL |
| **Scroll no modo contínuo** (arrastar alça não rola, exceto na borda) | Nada | Tudo: autoscroll proporcional à distância da borda, travar o scroll durante o arraste da alça, fragmentos que entram e saem do viewport durante a seleção |
| Seleção sobre `PageFragment` **clipado e transladado** | Testes 1 e 4: translate desfeito na ida, clip na volta, o mesmo `Paragraph` em duas páginas; 50/50 idas e voltas | — |
| **`text-transform`**: offset visual ≠ canônico | Testes 2, 5 e 6: palavra e texto vêm do canônico, `ß` ↔ `SS` nos dois sentidos, U+00AD contíguo e toque no hífen pendurado → offset seguinte; ver A1 | `capitalize`, `lowercase` com `İ`, locale `tr`, ligaduras reais de fonte (a `FlutterTest` não tem) |
| **U+FFFC**: o retângulo deve cobrir a imagem | Teste extra: `getBoxesForRange` sobre a seleção inclui exatamente a caixa do placeholder, e o toque na imagem → offset do U+FFFC; ver A6 | Imagem em bloco próprio (não inline), que é outro tipo de fragmento |

## Estimativa realista do S2 completo na Fase 4

O protótipo cobre o núcleo geométrico (boa parte da primeira linha da tabela).
O resto é interação, e é onde os dias vão:

| Parte | Dias |
|---|---|
| Núcleo no `RenderEpubPage`: `hitAt` com caret e glifo, `rectsFor` com clip de coluna, `wordAt`/linha/bloco, rects normalizados por linha (A6), integração com o cache de `Paragraph` (doc/04 §2.4) | 1,5 |
| Gestos no leitor: classificação toque × link × borda × long press × duplo/triplo toque × virada por arraste, arena com o carrossel | 2 |
| Alças da plataforma em camada de widgets (A4), âncoras, inversão, lupa, háptico, RTL | 2,5 |
| Multipágina: auto-avanço de 500 ms, gesto acima do carrossel, alça em página não visível | 2 |
| Modo contínuo: autoscroll na borda, scroll travado durante o arraste, fragmentos reciclados | 2 |
| Contrato (doc/05 §3.4): `EpubSelection`, `anchorRect` global, locator com `before/after`, debounce de 1 frame, `onSelectionEnd`, `clearSelection`, texto sem U+FFFC | 1 |
| Bidi/RTL (`getBoxesForRange` com várias caixas por linha, alças trocadas), CJK (`getWordBoundary` via ICU) | 1 |
| Testes de widget e de integração, mais a rodada em aparelho | 2 |
| **Total** | **14 dias (≈ 3 semanas; faixa 12–17)** |

Fora dessa conta: a tabela SpecialCasing (A1), cerca de 1 dia que pertence ao
`DisplayMap` da Fase 2, e seleção por teclado e mouse de doc/05 §5.1
(Shift+setas, arraste de mouse, duplo clique), mais 1,5–2 dias.

**Tem que ser verificado em aparelho real** (Android e iOS, pelo menos um
aparelho fraco de Android):

- Forma, posição e área de toque das alças Material e Cupertino, lupa e
  háptico no long press
- Arena de gestos contra os gestos do sistema: voltar pela borda no Android,
  swipe-back no iOS e `MediaQuery.systemGestureInsets` perto das alças na
  borda da tela
- Sensação do auto-avanço (500 ms) e do autoscroll com dedo de verdade; tempo
  de long press do sistema contra o `kLongPressTimeout`
- Repintura durante o arraste num Android fraco com Impeller. `rectsFor` custa
  µs, mas a camada da página repinta a cada frame
- Fontes reais (Noto Serif na engine): ligaduras `fi` (um glifo, dois
  graphemes) no `getClosestGlyphInfoForOffset`, kerning, fallback de emoji e
  CJK e runs de altura mista. Isto dá para cobrir em `example/integration_test`
  na engine Linux antes de ir para o aparelho

## Sustenta / contradiz

| Doc | Seção | Veredito |
|---|---|---|
| 05 | §3.1 primitivas | **Sustenta.** Precisão: `getClosestGlyphInfoForOffset` não é "útil para RTL", é **necessário** sempre (A3). Acrescentar que `LineMetrics` não tem range de texto; o range da linha vem de `getLineBoundary`/`getLineNumberAt` |
| 05 | §3.2 do toque ao offset | **Sustenta a cadeia**, com três mudanças no texto: (a) a saída é dupla, caret (`getPositionForOffset`, para arraste e alças) e caractere (`getClosestGlyphInfoForOffset`, para palavra, link e imagem); (b) o caminho inverso clipa o retângulo à **coluna** do fragmento, não só à faixa vertical (A2); (c) "fora de fragmento": verticalmente vai para a linha mais próxima com `x` preservado, e horizontalmente a margem dá início ou fim da linha. Hoje o texto diz "início ou fim conforme o lado" sem distinguir os dois eixos |
| 05 | §3.3 através de blocos e páginas | **Sustenta** o par de offsets canônicos fora do render box, o cruzamento de blocos e de páginas e o texto extraído de `canonicalText` com `\n`. Acrescentar: o reconhecedor de arraste de seleção fica acima do carrossel, não em cada `RenderEpubPage`; e os separadores `\n` não pertencem a fragmento (A7). Auto-avanço e modo contínuo **não verificados** |
| 05 | §3.4 contrato | Não testado |
| 05 | §3.5 alças | **Contradiz.** `TextSelectionControls.buildHandle` devolve `Widget` dependente de `BuildContext`/`Theme`, e o `RenderEpubPage` não pode pintá-lo (A4). Muda para: "o `RenderEpubPage` expõe as âncoras das alças; o leitor mostra as alças como widgets de `TextSelectionControls` numa camada acima das páginas, posicionadas por `getHandleAnchor`; o arraste da alça usa `DragStartBehavior.down` e só entra na arena quando o toque começa na alça" (A5). doc/05 §1, item 7 da pintura ("Alças de seleção, por cima de tudo") sai da lista do `paint` |
| 05 | §1 ordem de pintura e §1.1 repaint | **Sustenta** (seleção antes do texto, `clipRect` + `translate` por fragmento; seleção só faz `markNeedsPaint`), exceto o item 7 conforme §3.5 |
| 04 | §1.1 `DisplayMap` | **Sustenta** a identidade sem alocação, os pontos de mudança em `Uint32List` com busca binária, a monotonicidade e o 2º `S` → `ß`. Acrescentar: (a) a semântica de inserção (dentro de U+00AD → offset canônico seguinte; `toDisplay` cai depois da inserção); (b) **`ß → SS` não vem de `String.toUpperCase`**: é tabela própria de SpecialCasing em todas as plataformas, senão web e nativo divergem (A1) |
| 04 | §2.1 parágrafo entre páginas | **Sustenta**: o mesmo `Paragraph` em duas páginas, com seleção correta em cada uma. Acrescentar o clip horizontal para retângulos de seleção (A2) |
| 04 | §8 hífen pendurado | **Sustenta**: o toque sobre o hífen pintado pelo motor resolve para o offset seguinte sem código extra, pela semântica de inserção do mapa |
| 13 | §1 custo do S2 (2 dias) | **Sustenta para o spike.** Para a Fase 4, a seleção completa é da ordem de **3 semanas**, e a tabela de doc/13 deve dizer isso |

## Nota de ambiente

O Flutter 3.47.5, na primeira execução de `flutter test` desta árvore,
reescreve sozinho `analysis_options.yaml` (acrescenta `analyzer.exclude:
[build/**]`) e atualiza `example/pubspec.lock` (`matcher`, `meta`, `test_api`,
`vector_math`). As duas mudanças foram revertidas; a subida da versão mínima
do Flutter precisa aceitá-las ou fixá-las numa revisão própria.
