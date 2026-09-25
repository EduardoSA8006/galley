# 13 — Riscos, spikes e fases

## 1. Riscos abertos

Ordem de execução **antes** de escrever arquitetura definitiva.

| # | Risco | Spike | Custo | Impacto se falhar |
|---|---|---|---|---|
| **S1** | `ui.Paragraph` em isolate de background | **Fechado, negativo** (2026-09-09, Flutter 3.44.1, engine Linux): `ParagraphBuilder` em `Isolate.run` e em `Isolate.spawn` lança `UI actions are only available on root isolate`. Orçamento por frame confirmado ([08](08-concorrencia-cache.md) §2) | 0,5 dia | Nenhum |
| **S2** | Seleção sobre `RenderObject` | **Fechado no núcleo** (2026-09-25, Flutter 3.47.5): ponto ↔ offset canônico (50/50 idas e voltas), retângulos, palavra, arraste e alças simples através de blocos e de páginas, bloco dividido entre páginas, `text-transform` (`ß` ↔ `SS`), U+00AD e U+FFFC; `canonicalOffsetAt` e `rectsFor` custam µs ([05](05-render-selecao-a11y.md) §3.2). Achados: clip horizontal dos retângulos à coluna; saída dupla caret × caractere; alças são widgets numa camada acima das páginas, não pintadas pelo render box ([05](05-render-selecao-a11y.md) §3.5); `String.toUpperCase` da VM não faz `ß → SS` ([04](04-layout-paginacao.md) §1.1). Fica para a Fase 4: alças da plataforma, auto-avanço e modo contínuo (§1.1) | 2 dias | **Alto** na Fase 4: a interação é ~3 semanas (§1.1) |
| **S3** | Acessibilidade | `assembleSemanticsNode` com nós cacheados por fragmento, testado com TalkBack e VoiceOver reais | 1 dia | **Alto** — bloqueia lançamento |
| **S4** | Layout de tabela | **Fechado** (2026-09-25, Flutter 3.47.5): 200 tabelas aleatórias sem sobreposição e sem quebra por caractere; paginação com cobertura exata e cabeçalho repetido. Correções em [04](04-layout-paginacao.md) §9: medição por um `layout(∞)` (`minIntrinsicWidth` e `longestLine`; `layout(0)` quebra por glifo), 2 layouts por célula, `colSpan` repartindo só o déficit, escala por `canvas.scale`, regras de paginação para `rowspan`, linha maior que a página e cabeçalho alto. Tabela grande é medida em fatias, uma célula por etapa (200 × 8 ≈ 13 fatias de 4 ms), exceção declarada à primeira página rápida ([04](04-layout-paginacao.md) §2.3) | 2 dias | Baixo |
| **S5** | Justificação e hifenização | **Fechado parcialmente** (2026-09-09): `ui.Paragraph` quebra no U+00AD, largura zero fora da quebra, mas **não pinta o hífen**; pintura pelo motor via hanging hyphen ([04](04-layout-paginacao.md) §8). `justify` sem controle de espaçamento. Cor não altera métricas. `StrutStyle` não altera altura de linha; usar `ParagraphStyle.height` ([04](04-layout-paginacao.md) §1). Pendente para a 1.2: medir rios com `hyph-pt` | 1 dia | Baixo |
| **S6** | Desofuscação de fonte | **Fechado** (2026-09-09): IDPF e Adobe com ida e volta byte a byte sobre Noto Serif e carregamento via `FontLoader`; SHA-1 próprio em ~95 linhas validado em 6 vetores. Achado: SHA-1 custa ~16 µs/KB em JIT, o que reabre P8 ([08](08-concorrencia-cache.md) §4.1) | 0,5 dia | Baixo |
| **S7** | Imagens e SVG | **Fechado parcialmente** (2026-09-09): `addPlaceholder(baseline)` ocupa um U+FFFC, `getBoxesForRange` sobre ele devolve a caixa, linha cresce de 10 para 43 px com placeholder de 40 px; `targetWidth` reduz memória retida 31× com tempo igual ([05](05-render-selecao-a11y.md) §6). `headingLevel` só no web. Pendente: SVG-invólucro e repaginação quando a dimensão chega | 1 dia | Médio |
| **S8** | Paginação ancorada | **Fechado** (2026-09-09): protótipo com predicado único de fronteira; 500 casos aleatórios com cobertura exata, nenhuma fronteira ilegal, diferença de contagem em {0, +1}, snap do âncora ≤ 2 linhas; 150 mil linhas em 3,7 ms ([04](04-layout-paginacao.md) §3.1) | 1 dia | Nenhum |
| **S9** | Worker cooperativo no web | **Fechado parcialmente** (2026-09-25, Flutter 3.47.5, Chromium 153): a caminhada fatia a 4 ms (mediana 4,00 ms, > 8 ms em ~1% das fatias) e o web cooperativo em release leva ≈ 1,0–1,1× (dart2js) e 1,1–1,6× (dart2wasm) o isolate nativo. Mas o parse do `html` é atômico (~50 ms/500 KB em release, 245 ms no DDC) e a cessão por `Timer` custa ~4,2 ms no navegador ([08](08-concorrencia-cache.md) §1 e §2). **P10 fechada: web na 1.0.x.** Pendentes para a Fase 1: parse fatiável e cessão por `MessageChannel`. O inflate próprio ficou fora do S9 e segue com P7 na Fase 1 | 1 dia | **Médio** — o web depende das pendências |

Total da Fase 0: cerca de 10 dias de spike, mais o corpus.

**Estado em 2026-09-25:** S1, S4, S6 e S8 fechados; S2 fechado no núcleo, com a
interação para a Fase 4 (§1.1); S5, S7 e S9 fechados parcialmente, com
pendências que só fazem sentido na Fase 2 (rios com `hyph-pt`) e na Fase 1
(SVG-invólucro; parse fatiável e cessão sem clamp no web). Aberto: S3, que
depende de aparelho físico. P10 decidida: web na 1.0.x. S1 e S5–S8 rodaram em
Flutter 3.44.1; S2, S4 e S9 em 3.47.5, sem mudar o mínimo declarado no
`pubspec.yaml` (3.44). Corpus: 57 casos sintéticos e 8 EPUBs reais em
`test/corpus/`, gerador em `tool/corpus/`. Resultados detalhados em
`spike/RESULTADO-S*.md`.

### 1.1 Por que S2 é o mais perigoso

Escolher `RenderObject` próprio ([Decisão 4.2](01-decisoes.md)) foi o que compra
o desempenho, e o preço é reimplementar seleção. As partes que costumam ser
descobertas tarde:

- Extensão de seleção **através de blocos** (o range é de offsets, mas as alças
  são visuais, e o mapeamento entre os dois precisa funcionar nas bordas)
- Extensão **através de páginas** no modo paginado, com auto-avanço
- Alças que respeitam a convenção da plataforma (elas são diferentes no iOS e no
  Android); reaproveitar `TextSelectionControls` do framework
- Interação com o scroll no modo contínuo (arrastar a alça não deve rolar, exceto
  na borda)
- Seleção sobre `PageFragment`, onde o `Paragraph` está clipado e transladado
- Seleção em bloco com `text-transform`, onde o offset visual não é o canônico
- Seleção que inclui um U+FFFC (imagem): o retângulo de seleção deve cobrir a
  imagem

Descobrir o tamanho disso na Fase 4 seria caro. É por isso que o spike vem
primeiro, mesmo parecendo improdutivo.

**O que o S2 respondeu (2026-09-25).** O protótipo cobriu o núcleo geométrico;
o que ficou de fora é interação, e é onde os dias vão:

| Item | Provado no S2 | Fica para a Fase 4 |
|---|---|---|
| Através de blocos | Long press + arraste e arraste de alça atravessam blocos; alça invertida mantém `base`; nenhum retângulo fora de fragmento | Duplo e triplo toque, "snap" por palavra durante a extensão (varia por plataforma) |
| Através de páginas | Range de duas páginas renderiza certo nas duas, cada caractere numa página só; cada alça só na página da sua extremidade | Auto-avanço de 500 ms, gesto contínuo durante a virada (reconhecedor acima do carrossel), alça em página não visível |
| Alças da plataforma | Nada; só círculos. Desenho definido: widgets numa camada acima das páginas, `DragStartBehavior.down` ([05](05-render-selecao-a11y.md) §3.5) | Forma e âncora Material e Cupertino, lupa, háptico, RTL |
| Scroll no modo contínuo | Nada | Tudo: autoscroll na borda, scroll travado durante o arraste, fragmentos que entram e saem do viewport |
| `PageFragment` clipado e transladado | 50/50 idas e voltas; o mesmo `Paragraph` em duas páginas | — |
| `text-transform` | Palavra e texto vêm do canônico, `ß` ↔ `SS` nos dois sentidos, U+00AD e hífen pendurado → offset seguinte | `capitalize`, `lowercase` com `İ`, locale `tr`, ligaduras de fonte real |
| U+FFFC | O retângulo inclui exatamente a caixa do placeholder; toque na imagem → offset do U+FFFC | Imagem em bloco próprio |

Estimativa da seleção completa na Fase 4, pelo S2:

| Parte | Dias |
|---|---|
| Núcleo no `RenderEpubPage`: caret e caractere, retângulos com clip de coluna, palavra/linha/bloco, realce normalizado por linha, integração com o cache de `Paragraph` | 1,5 |
| Gestos no leitor: toque × link × borda × long press × duplo/triplo toque × virada por arraste, arena com o carrossel | 2 |
| Alças da plataforma em camada de widgets, âncoras, inversão, lupa, háptico, RTL | 2,5 |
| Multipágina: auto-avanço, gesto acima do carrossel, alça em página não visível | 2 |
| Modo contínuo: autoscroll na borda, scroll travado, fragmentos reciclados | 2 |
| Contrato de [05](05-render-selecao-a11y.md) §3.4: `EpubSelection`, `anchorRect`, locator, debounce, `onSelectionEnd`, `clearSelection` | 1 |
| Bidi/RTL e CJK | 1 |
| Testes de widget e de integração, mais a rodada em aparelho | 2 |
| **Total** | **14 (≈ 3 semanas; faixa 12–17)** |

Fora dessa conta: a tabela de SpecialCasing, cerca de 1 dia do `DisplayMap` na
Fase 2 ([04](04-layout-paginacao.md) §1.1), e a seleção por teclado e mouse de
[05](05-render-selecao-a11y.md) §5.1, mais 1,5 a 2 dias. Precisa de aparelho
real (Android e iOS, ao menos um Android fraco): alças, lupa e háptico; arena
contra os gestos do sistema; sensação do auto-avanço e do autoscroll; repintura
durante o arraste com Impeller. Fontes reais (ligaduras, kerning, fallback de
emoji e CJK) dá para cobrir antes, em `example/integration_test` na engine
Linux.

### 1.2 Riscos que não têm spike

| Risco | Mitigação |
|---|---|
| O corpus não representa o acervo real do app | Instrumentar o app atual para reportar diagnósticos anonimizados e alimentar o corpus com os casos reais |
| Reescrita perde conhecimento acumulado | O corpus **é** o conhecimento. Fase 0 existe exatamente para isso |
| Escopo do pacote inflar de volta para "app" | A regra de fronteira de [00](00-visao-geral.md) §2 é o critério de rejeição em code review |
| Mudança de API do Flutter em `dart:ui` | Fixar versão mínima do SDK e cobrir `computeLineMetrics`, `getBoxesForRange`, `addPlaceholder` e soft hyphen com testes |
| Regra de normalização de texto precisar mudar após a 1.0 | Fase 1 gasta tempo extra na regra; corpus de escrita (CJK, árabe, devanágari) e o fuzzing de [10](10-testes.md) §6 existem para esgotar os casos **antes** de haver offsets persistidos por usuários |
| `html` parseando XHTML de forma diferente do esperado | Casos no corpus para auto-fechamento, namespaces e entidades ([03](03-camada-a-ir.md) §8) |
| Tamanho do pacote no web (inflate, SHA-1, CSS) | Medir na Fase 1; teto de 300 KB minificado para o núcleo |

## 2. Fases de implementação

| Fase | Entrega | Critério de conclusão |
|---|---|---|
| **0** | Spikes S1–S9; corpus de 40–50 arquivos com README e diagnósticos esperados; harness de medição; versão mínima do Flutter fixada | Baseline de desempenho registrado e versionado; P10 decidida; P6–P8 encaminhadas |
| **1** | `EpubByteSource`, ZIP lazy, OPF/NAV/NCX/encryption, Camada A completa (âncoras, `lang`/`dir`, runs, separadores), cache em disco, `EpubWorker` nas duas formas | Invariantes 1, 2, 4 e 9 passando; snapshot textual da IR estável; progresso global em < 1 s cache frio |
| **2** | Camadas B e C (`DisplayMap`, fluxo, paginação ancorada, tabelas, imagens), `RenderEpubPage`, modo paginado, agendador | Orçamento de virada de página, de primeira página e de troca de fonte cumprido; teste de jank passando; Invariantes 7 e 8 |
| **3** | Modo contínuo, locator, progresso, reparo, política de viewport, ciclo declarativo | Invariantes 3 e 5; troca de modo e rotação preservam posição; teste do eco de `onStateChanged` |
| **4** | Seleção, acessibilidade, teclado, destaques | Invariante 6; testes de semântica e de interação; S2 e S3 fechados na prática |
| **5** | Extração de texto, `findAll`, TOC, landmarks, metadados, capa, `page-list`, notas, diagnósticos, degradação | Corpus da Faixa B e Patologia com lista exata de diagnósticos esperados |
| **6** | API pública polida, app de exemplo nas cinco plataformas nativas (web na 1.0.x, P10), README, esta documentação revisada | **Teste de adoção:** dev que nunca viu o pacote monta um leitor com preferências e progresso em < 30 min lendo só o README |
| **1.1** | Fixed-layout | Corpus de mangá e HQ; spread e zoom |

### 2.1 Regra de ordem

As fases **não** se sobrepõem em 1 → 2 → 3, porque cada uma depende
estruturalmente da anterior. Da 4 em diante há paralelismo possível: seleção,
acessibilidade e TOC são independentes entre si.

### 2.2 O que não fazer

- Não começar a Fase 1 antes de o corpus existir. É a única regra rígida deste
  documento
- Não deixar acessibilidade para a Fase 6. Ela é estrutural no `RenderObject`, e
  enxertar depois exige reescrever a pintura
- Não deixar teclado para depois pelo mesmo motivo: foco e hit test de link são
  do `RenderObject`
- Não adicionar dependência para "resolver rápido" um caso do corpus. O caso do
  corpus existe justamente para ser resolvido no nosso código
- Não publicar a 1.0 com regra de normalização de texto em que não se confia. É
  a única coisa do projeto que não dá para consertar depois sem mexer em dados
  de usuário
