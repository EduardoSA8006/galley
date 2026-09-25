# Motor de renderização de EPUB para Flutter — Documentação

**Versão do documento:** v0.5
**Pacote:** `galley` — [github.com/EduardoSA8006/galley](https://github.com/EduardoSA8006/galley)

Um pacote Flutter que renderiza EPUB de forma nativa, sem WebView, com três
propriedades como razão de existir: rápido, leve e fácil de adotar.

## Índice

| Arquivo | Conteúdo |
|---|---|
| [00-visao-geral.md](00-visao-geral.md) | Objetivo, fronteira do pacote, contrato de fidelidade, as três faixas do acervo |
| [01-decisoes.md](01-decisoes.md) | Registro de decisões de arquitetura e emendas |
| [02-modelo-de-estilo.md](02-modelo-de-estilo.md) | As três classes de propriedade CSS, precedência no perfil `uniform`, `EpubStyle` |
| [03-camada-a-ir.md](03-camada-a-ir.md) | Pipeline de parse, fonte de bytes, leitor de ZIP, IR do documento, texto canônico |
| [04-layout-paginacao.md](04-layout-paginacao.md) | Camada B, texto exibido, motor de fluxo, paginação ancorada, tabelas, viewport |
| [05-render-selecao-a11y.md](05-render-selecao-a11y.md) | `RenderEpubPage`, seleção, acessibilidade, gestos, teclado, imagens e SVG |
| [06-locator-navegacao.md](06-locator-navegacao.md) | Readium Locator, progresso, reparo, TOC, notas, metadados, `page-list` |
| [07-api-publica.md](07-api-publica.md) | As três camadas públicas, interfaces injetadas, ciclo de estado declarativo |
| [08-concorrencia-cache.md](08-concorrencia-cache.md) | Worker da Camada A, agendador, caches, cancelamento, web |
| [09-erros-diagnosticos.md](09-erros-diagnosticos.md) | Taxonomia de exceções, diagnósticos, degradação, `encryption.xml` |
| [10-testes.md](10-testes.md) | Corpus, invariantes de propriedade, gates, desempenho no CI |
| [11-empacotamento-versionamento.md](11-empacotamento-versionamento.md) | Dependências, plataformas, política de semver, extensibilidade de tipos |
| [12-roadmap.md](12-roadmap.md) | Roadmap versionado com critérios de entrada |
| [13-riscos-spikes-fases.md](13-riscos-spikes-fases.md) | Riscos abertos, spikes, fases de implementação |
| [14-pendencias.md](14-pendencias.md) | Lista viva do que ficou para depois, com origem e quando voltar |

## Como ler

Para entender **o que** o pacote é: 00, 01.
Para implementar: 03 → 04 → 05, na ordem.
Para consumir o pacote como app: 07, 06.
Para planejar: 13, 12.

## Convenções deste documento

- Trechos de código são **assinaturas de intenção**, não código final. Nomes
  podem mudar na implementação; semântica não.
- "Classe 1/2/3" refere-se sempre às classes de propriedade CSS de
  [02](02-modelo-de-estilo.md).
- "Offset" sem qualificador significa sempre índice em `canonicalText`
  ([03](03-camada-a-ir.md) §5).

## Alterações da v0.4 para a v0.5

Incorporação dos resultados dos spikes S2, S4 e S9 (2026-09-25, Flutter 3.47.5):

| Arquivo | O que mudou |
|---|---|
| 01 | P10 fechada: web na 1.0.x, com critério objetivo de entrada; Emenda 9 com o parse atômico do `html`; Emenda 12 e P2 com as correções do S4 |
| 03 | §8 parse atômico e armadilha O(n²) de `Element.children` |
| 04 | §1.1 semântica de inserção e SpecialCasing próprio (`ß → SS`); §2.1 clip horizontal da seleção; §2.3 exceção da tabela grande; §8 min-content com U+00AD; §9 medição por `layout(∞)`, `colSpan` por déficit, escala por `canvas.scale`, regras de paginação, custo e fatiamento por célula |
| 05 | §1 alças fora do `paint`; §3.1 e §3.2 saída dupla caret × caractere, clip de coluna, toque fora de fragmento nos dois eixos, custo; §3.3 reconhecedor acima do carrossel; §3.5 alças como widgets com `DragStartBehavior.down` |
| 08 | §1 parse atômico com números, caminhos do parse fatiável, custo de spawn medido; §2 clamp de ~4,2 ms na cessão do web, tabela por célula, bloco gigante da Camada A; §3 checkpoints revistos |
| 09 | Diagnósticos de tabela: `truncatedColSpan`, `truncatedRowSpan`, `fragmentedRowSpan`, `headerNotRepeated` |
| 10 | Invariante 7 verificada no S2; §4.4 desempenho no web exige build de release |
| 11 | §2 web na 1.0.x |
| 12 | v1.0 nas cinco plataformas nativas; seção v1.0.x (web) |
| 13 | S2, S4 e S9 com resultados; estado da Fase 0; §1.1 com o que o S2 respondeu e a estimativa da Fase 4; Fase 6 sem o web |

## Alterações da v0.3 para a v0.4

Incorporação dos resultados dos spikes S1, S5, S6, S7 e S8 (2026-09-09):

| Arquivo | O que mudou |
|---|---|
| 01 | Emenda 10 com snap do âncora; Emenda 11 com pintura do hífen pelo motor; P4 com o erro literal do S1; P8 reaberta (SHA-1 × FNV-1a 64) |
| 04 | §1 entrelinha via `ParagraphStyle.height` (strut não funciona); §3.1 snap e diferença {0, +1}; §8 hanging hyphen com números |
| 05 | `headingLevel` só no web; números do decode com `targetWidth` |
| 08 | Custo real do SHA-1 e remissão a P8 |
| 09 | Chave IDPF é a concatenação de todos os `unique-identifier` |
| 10 | Invariante 8 reformulada como `∈ {0, 1}` |
| 12 | Custo da hifenização corrigido |
| 13 | S1, S5, S6, S7, S8 com resultados e estado da Fase 0 |

## Alterações da v0.2 para a v0.3

Revisão crítica completa. As mudanças de decisão estão registradas como
Emendas 3 a 15 em [01-decisoes.md](01-decisoes.md), aceitas em 2026-09-07.
Resumo por arquivo:

| Arquivo | O que mudou |
|---|---|
| 00 | Fronteira: entra a fonte de bytes com acesso aleatório; sai a promessa implícita de isolate em toda plataforma |
| 01 | Emendas 3–15 aceitas; P1–P5 decididas; P6–P10 abertas |
| 02 | Precedência exata do perfil `uniform` (resolve o conflito `text-indent` × `EpubIndentStyle`); `text-transform` movido para "texto exibido" |
| 03 | `EpubByteSource`; separador de bloco e U+FFFC no texto canônico; `lang`/`dir`; runs como segmentos com bitmask; links, tabelas e listas modelados; chave do cache inclui CSS |
| 04 | Texto exibido e `DisplayMap` (Camada B); paginação **ancorada**; algoritmo de tabela (P2); P1 decidida; `Paragraph.dispose` |
| 05 | API correta de semântica (`assembleSemanticsNode`); teclado e foco; SVG via rasterizador injetável; capa embrulhada em SVG |
| 06 | `position` com semântica Readium explícita; notas de rodapé (`resolveNote`); heurística de capa EPUB2/EPUB3 |
| 07 | Ciclo declarativo sem loop (`position` é intenção, não espelho); `EpubFontProvider` opcional; `EpubByteSource` |
| 08 | `EpubWorker` com duas implementações (isolate e cooperativa); agendador com `scheduleTask`, não `addPostFrameCallback`; web |
| 09 | `EpubUnsupportedException` unificada e momento de lançamento; novos códigos de diagnóstico |
| 10 | Snapshots dependem da fonte de teste embutida; orçamento de contagem de páginas por tamanho de capítulo |
| 11 | Correção: classe selada **também** quebra `switch` exaustivo; padrão de tipos extensíveis; nome `galley` |
| 12 | Hifenização por soft hyphen; SVG e notas no escopo da 1.0; MathML reavaliado |
| 13 | S1 presumido negativo; S7 (SVG) e S8 (paginação ancorada) adicionados |
