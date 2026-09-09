# 13 — Riscos, spikes e fases

## 1. Riscos abertos

Ordem de execução **antes** de escrever arquitetura definitiva.

| # | Risco | Spike | Custo | Impacto se falhar |
|---|---|---|---|---|
| **S1** | `ui.Paragraph` em isolate de background | **Fechado, negativo** (2026-09-09, Flutter 3.44.1, engine Linux): `ParagraphBuilder` em `Isolate.run` e em `Isolate.spawn` lança `UI actions are only available on root isolate`. Orçamento por frame confirmado ([08](08-concorrencia-cache.md) §2) | 0,5 dia | Nenhum |
| **S2** | Seleção sobre `RenderObject` | Alças, arraste, extensão, multi-parágrafo, multi-página, `DisplayMap` com `text-transform` | 2 dias | **Alto** — é a parte mais subestimada do projeto |
| **S3** | Acessibilidade | `assembleSemanticsNode` com nós cacheados por fragmento, testado com TalkBack e VoiceOver reais | 1 dia | **Alto** — bloqueia lançamento |
| **S4** | Layout de tabela | Algoritmo da Emenda 12 com `colspan`, `rowspan`, conteúdo variável, largura maior que a página, cabeçalho repetido | 2 dias | **Médio** — tabela é conteúdo (Classe 1), não estética |
| **S5** | Justificação e hifenização | **Fechado parcialmente** (2026-09-09): `ui.Paragraph` quebra no U+00AD, largura zero fora da quebra, mas **não pinta o hífen**; pintura pelo motor via hanging hyphen ([04](04-layout-paginacao.md) §8). `justify` sem controle de espaçamento. Cor não altera métricas. `StrutStyle` não altera altura de linha; usar `ParagraphStyle.height` ([04](04-layout-paginacao.md) §1). Pendente para a 1.2: medir rios com `hyph-pt` | 1 dia | Baixo |
| **S6** | Desofuscação de fonte | **Fechado** (2026-09-09): IDPF e Adobe com ida e volta byte a byte sobre Noto Serif e carregamento via `FontLoader`; SHA-1 próprio em ~95 linhas validado em 6 vetores. Achado: SHA-1 custa ~16 µs/KB em JIT, o que reabre P8 ([08](08-concorrencia-cache.md) §4.1) | 0,5 dia | Baixo |
| **S7** | Imagens e SVG | **Fechado parcialmente** (2026-09-09): `addPlaceholder(baseline)` ocupa um U+FFFC, `getBoxesForRange` sobre ele devolve a caixa, linha cresce de 10 para 43 px com placeholder de 40 px; `targetWidth` reduz memória retida 31× com tempo igual ([05](05-render-selecao-a11y.md) §6). `headingLevel` só no web. Pendente: SVG-invólucro e repaginação quando a dimensão chega | 1 dia | Médio |
| **S8** | Paginação ancorada | **Fechado** (2026-09-09): protótipo com predicado único de fronteira; 500 casos aleatórios com cobertura exata, nenhuma fronteira ilegal, diferença de contagem em {0, +1}, snap do âncora ≤ 2 linhas; 150 mil linhas em 3,7 ms ([04](04-layout-paginacao.md) §3.1) | 1 dia | Nenhum |
| **S9** | Worker cooperativo no web | Parse de seção de 500 KB como `sync*` fatiado a 4 ms sem jank; inflate próprio; medir tempo total contra o isolate | 1 dia | **Médio** — define se o web fica na 1.0 ou na 1.0.x |

Total da Fase 0: cerca de 10 dias de spike, mais o corpus.

**Estado em 2026-09-09:** S1, S6 e S8 fechados; S5 e S7 fechados no que
dependia de `dart:ui`, com pendências que só fazem sentido na Fase 2 (rios com
`hyph-pt`) e na Fase 1 (SVG-invólucro). Abertos: S2, S3, S4 e S9. Corpus: 57
casos sintéticos e 8 EPUBs reais em `test/corpus/`, gerador em `tool/corpus/`.
Resultados detalhados em `spike/RESULTADO-S*.md`.

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
| **6** | API pública polida, app de exemplo nas seis plataformas, README, esta documentação revisada | **Teste de adoção:** dev que nunca viu o pacote monta um leitor com preferências e progresso em < 30 min lendo só o README |
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
