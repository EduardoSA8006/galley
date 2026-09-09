# 12 — Roadmap versionado

**Decisão 10.2: reflow completo na 1.0, fixed-layout na 1.1.**

Cada linha tem um **critério de entrada**: a condição objetiva que autoriza
começar o trabalho. Sem isso, roadmap é lista de desejos.

## v1.0 — Reflow completo

| Item | Critério de entrada |
|---|---|
| `EpubByteSource`, ZIP lazy com ZIP64, OPF, NAV, NCX, `encryption.xml` | Fase 0 concluída |
| Camada A com âncoras, `lang`/`dir`, runs em segmentos, texto canônico com separadores | — |
| Cache em disco com chave incluindo CSS | Camada A estável |
| Três classes de CSS, perfil `uniform` com a precedência de [02](02-modelo-de-estilo.md) §3.1 | — |
| Camada B com `DisplayText`/`DisplayMap` (`text-transform`) | Camada A |
| Motor de fluxo, paginação híbrida e **ancorada** | S8 concluído |
| Modos paginado e contínuo | Motor de fluxo |
| `RenderEpubPage` | — |
| Seleção de texto, alças por plataforma | S2 concluído |
| Acessibilidade (`assembleSemanticsNode`, nós cacheados) | S3 concluído |
| Teclado, foco e mouse | `RenderEpubPage` |
| Destaques | Seleção |
| Locator, progresso, reparo, `position`, histórico de salto | Camada A |
| TOC, landmarks, metadados com `raw`, capa por heurística, `page-list` de três fontes | Camada A + âncoras |
| Notas de rodapé (`resolveNote`, `onNoteTap`) | Âncoras |
| Extração de texto para busca, `findAll` linear | Camada A |
| Diagnósticos e degradação declarada | — |
| Tabelas (algoritmo da Emenda 12) | S4 concluído |
| Imagens em bloco e inline, SVG-invólucro desembrulhado, `EpubSvgRasterizer` | S7 concluído |
| Desofuscação de fonte IDPF e Adobe | S6 concluído |
| `EpubWorker` isolate e cooperativo (web) | — |
| Justificação com `start` como padrão (P1) | — |

**Critério de release:** as 9 invariantes passando em todo o corpus, orçamento de
desempenho cumprido, teste de adoção de 30 minutos cumprido, app de exemplo
publicado nas seis plataformas.

## v1.1 — Fixed-layout

| Item | Motivação | Critério de entrada |
|---|---|---|
| Renderizador `prePaginated` | Mangá, HQ, infantil, arte: segmento inteiro que nenhum pacote Flutter atende hoje | v1.0 estável, corpus de fixed-layout montado |
| Zoom e pan com inércia | Requisito da faixa | Renderizador |
| Spread (página dupla em paisagem), `rendition:spread` e `page-spread-*` | Convenção do formato | Renderizador |
| Locator para fixed-layout | `charOffset` não se aplica; usa `position` do Readium e `progression` da seção | Renderizador |
| Texto selecionável em fixed-layout | O XHTML de fixed-layout tem texto posicionado; expor via IR com coordenadas | Renderizador; pode ficar para 1.1.x |

**Nota de arquitetura:** entra pela costura `SectionRenderer`
([00](00-visao-geral.md) §3.2), sem tocar o motor de reflow. Decisão pendente se
vira pacote separado `galley_fixed_layout` ou fica no núcleo; a favor do núcleo
está o fato de não adicionar dependência, e contra está o tamanho. Decidir ao
montar o corpus.

## v1.2 — Hifenização

| Item | Motivação | Critério de entrada |
|---|---|---|
| Padrões Knuth-Liang inserindo U+00AD via `DisplayMap` | Justificação sem hifenização produz rios brancos, especialmente em português e em coluna estreita. **Nenhum leitor Flutter hifeniza hoje** — é diferencial real. Custo de shaping ~1× (medido no S5); um `drawParagraph` de `"-"` extra por linha hifenizada, porque o `ui.Paragraph` quebra no soft hyphen mas não pinta o hífen | Emenda 6 e Emenda 11 implementadas |
| Dicionários pt, en, es, fr, de, it | Dicionários TeX são pequenos (20 a 100 KB) e permissivamente licenciados | Implementação do algoritmo |
| Dicionários carregados sob demanda por `Section.lang` | Não inflar o tamanho do pacote; escolher o idioma certo por bloco | Emenda 4 (`lang` na IR) |
| Pacote irmão `galley_hyphenation` com os dicionários | Núcleo sem dados de idioma | Empacotamento definido |

## v1.3 — Escrita vertical

| Item | Motivação | Critério de entrada |
|---|---|---|
| `writing-mode: vertical-rl` | Move CJK da Faixa B para a Faixa A. Abre o mercado japonês, que é grande em leitura digital | v1.1 (compartilha o trabalho de spread e direção) |
| `text-orientation`, `text-combine-upright` | Correção tipográfica em vertical | `writing-mode` |
| Ruby / furigana | Indissociável de CJK na prática | `writing-mode` |

**Risco conhecido:** `ui.Paragraph` não faz layout vertical. Escrita vertical
exige rotacionar o canvas e tratar caracteres que ficam eretos (`text-orientation:
mixed`) um a um, o que é um subsistema. É a versão de maior incerteza deste
roadmap.

## v2.0 — Perfil fiel

| Item | Motivação | Critério de entrada |
|---|---|---|
| `EpubFidelity.faithful` | Preserva design editorial: poesia, arte, infantil | Demanda comprovada de consumidores |
| Float com contorno de texto | Subsistema de layout | — |
| `::first-letter` (capitular) | Subsistema de layout | Float |
| `font-variant: small-caps` real | Síntese quando a fonte não tem o recorte | — |
| `columns` dentro da seção | Subsistema de layout | — |
| `@font-face` do publisher via `EpubFontProvider` | Fontes do livro no perfil fiel | S6 |
| Fator numérico de `font-size` relativo na IR | `sizeSmaller`/`sizeLarger` viram valor exato | Bump de `IR_SCHEMA_VERSION` |

Major porque muda o significado do perfil padrão em casos de borda, e porque
provavelmente exige campos novos na Camada A (o que bumpa `IR_SCHEMA_VERSION`, e
isso é transparente, mas a superfície da IR pública muda).

## Backlog sem versão

Itens que não têm critério de entrada definido ainda.

| Item | Nota |
|---|---|
| MathML | Grande. Duas rotas: (a) pacote irmão com layout nativo de um subconjunto (frações, índices, raízes cobrem a maioria dos livros didáticos); (b) fallback WebView. A rota (a) é mais coerente com o projeto; avaliar quando houver corpus |
| Media Overlays / TTS sincronizado | `SMIL` do EPUB3. A Camada 3 já entrega o texto e os offsets, então o pacote pode expor os pontos de sincronia (`par` → `charOffset` via `anchors`) sem tocar áudio |
| Pacote opcional de fallback WebView | Para Faixa B, via `SectionRenderer`. Separado, para não poluir a árvore de dependências do núcleo |
| Ganchos de DRM externo | Já possível hoje via `EpubResourceProvider` customizado; falta documentar o padrão com exemplo |
| Geração de CFI sob demanda | Para exportar anotações para outros leitores. Reparse da seção quando pedido |
| Dicionário / tradução inline | Precisa de `getWordBoundary` + callback; barato, mas é feature de app |
| Exportação de página para imagem | `EpubPagePainter` já permite; falta API de conveniência |
| Modo de leitura em duas colunas (tablet, paisagem) | O motor de fluxo suporta; falta viewport de duas colunas e regra de virada |
| Órfã e viúva configuráveis | Fixas na 1.0 |
| Tema de destaque por `HighlightStyle` customizado (pintor injetado) | Para apps com marcação própria |
| Leitura remota por HTTP `Range` | `EpubByteSource` já permite; falta exemplo e política de cache de faixas |

## Como este roadmap muda

Um item só sobe de "backlog" para uma versão quando ganha critério de entrada e
motivação escrita. Um item só entra numa versão em desenvolvimento se algo sair,
e a troca fica registrada em [01-decisoes.md](01-decisoes.md).
