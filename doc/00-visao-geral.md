# 00 — Visão geral

## 1. Objetivo e posicionamento

Um pacote Flutter que renderiza EPUB de forma **nativa** (sem WebView), com três
propriedades como razão de existir:

1. **Rápido** — primeira página em menos de 300 ms, virada de página em um frame,
   troca de preferência sem reparse.
2. **Leve** — nenhuma dependência nativa, nenhum plugin, nenhuma árvore de widgets
   por bloco de texto.
3. **Fácil de adotar** — um leitor funcional em dez linhas, com escape hatch para
   quem quer o motor sem a nossa UI.

O ecossistema Flutter hoje não tem isso. As opções existentes ou embrulham
`epub.js` num WebView (fidelidade boa, desempenho e integração ruins) ou usam
`flutter_html` (integração boa, fidelidade e desempenho ruins).

## 2. Fronteira do pacote

> **Regra que resolve toda dúvida de escopo:** o pacote é uma função pura de
> `(bytes, configuração de estilo, viewport)` para `(pixels, locators)`.
> Ele não tem I/O próprio, não tem rede, não tem banco de dados, não tem tela
> de configuração.

**Dentro do pacote:**

- Leitura de container ZIP com acesso aleatório, OPF, NAV e NCX
- Resolução de recursos por `href`
- Parse e cascata de um subconjunto de CSS
- Construção da IR do documento
- Layout, paginação e pintura
- Seleção de texto e geometria de destaques
- Semântica de acessibilidade e navegação por teclado
- API de estilo e preferências
- Extração de texto canônico com offsets
- Modelo de navegação: TOC, metadados, capa, `page-list`, notas de rodapé
- Desofuscação de fontes embutidas (IDPF e Adobe)

**Fora do pacote:**

- Persistência de progresso, destaques e marcadores
- UI de preferências, biblioteca, downloads, DRM
- Download de fontes ou qualquer acesso à rede
- Índice de busca (o pacote entrega texto e offsets; quem indexa é o app)
- Sincronização entre dispositivos
- Rasterização de SVG (o pacote define a interface; o app pluga a implementação,
  ver [05](05-render-selecao-a11y.md) §6.2)

O app injeta uma fonte de bytes (`EpubByteSource`) ou um provedor de recursos já
resolvidos (`EpubResourceProvider`), mais um `EpubCacheStore`. Opcionalmente, um
`EpubFontProvider` e um `EpubSvgRasterizer`. O pacote devolve widget, locators e
diagnósticos. Ver [07](07-api-publica.md) §4.

## 3. Contrato de fidelidade

**Decisão 1: nativo puro com degradação declarada.**

"Renderizar qualquer EPUB sem perda de conteúdo" e "100% nativo em Flutter" não
coexistem literalmente, porque EPUB arbitrário é XHTML e CSS arbitrários. A saída
é separar duas coisas que costumam ser confundidas:

> **Nenhum byte de conteúdo é descartado.** Todo texto e toda imagem chegam à
> tela, sempre. O que degrada é **layout**, e degrada de forma **declarada**: o
> motor emite um diagnóstico, nunca falha em silêncio.

Isso é auditável e verificável automaticamente pelas invariantes de propriedade
(ver [10-testes.md](10-testes.md)).

### 3.1 As três faixas do acervo

| Faixa | Conteúdo | Tratamento |
|---|---|---|
| **A — reflowable comum** | Prosa, headings, listas, tabelas, imagens, blockquote, `pre`, notas, links internos | Fidelidade alta, nativo |
| **B — reflowable difícil** | Float com contorno de texto, multi-column, ruby, `writing-mode` vertical, MathML, `::first-letter` com float, `position: absolute` no fluxo, media queries, SVG sem rasterizador | Degradação declarada |
| **C — fixed-layout** | `rendition:layout=pre-paginated`: mangá, HQ, infantil, arte | Renderizador nativo separado (v1.1) |

Faixa B degrada assim: o conteúdo é emitido no fluxo normal, na ordem de leitura
do documento, e um `EpubDiagnostic` informa o que não foi reproduzido.

### 3.2 A costura de renderizadores

Mesmo sem WebView, existe internamente uma interface `SectionRenderer`. Ela é
necessária de qualquer forma para separar o renderizador de reflow do de
fixed-layout. Como efeito colateral, um pacote **opcional e separado** com
fallback de WebView pode ser plugado no futuro sem que o núcleo ganhe a
dependência.

## 4. Arquitetura em três camadas

O ganho de desempenho central vem de **invalidação independente**:

| Camada | Conteúdo | Invalidada por | Custo |
|---|---|---|---|
| **A — Documento (IR)** | Blocos, texto canônico, atributos semânticos, objetos inline, offsets, âncoras, idioma e direção | Nada (só mudança do arquivo ou do CSS do livro) | Alto |
| **B — Estilo resolvido e texto exibido** | `TextStyle`, métricas, escala tipográfica, `DisplayMap` | Mudança de preferência | Baixo |
| **C — Layout** | Caixas de linha, páginas, `ui.Paragraph` | Preferência ou viewport | Médio |

A Camada A **não conhece pixel, fonte nem largura**. É persistida em disco por
hash de conteúdo e nunca refeita. Reabrir o livro não reparseia nada. Trocar a
fonte refaz só B e C.

A Camada B é onde o texto canônico vira **texto exibido**: `text-transform`,
hifenização por soft hyphen e qualquer outra transformação que altere a string
acontecem aqui, com um mapa de offsets de volta para o canônico
([04](04-layout-paginacao.md) §1.1). É isso que mantém a Camada A estável e o
locator imune a preferência.

## 5. Onde o trabalho roda

| Trabalho | Onde | Por quê |
|---|---|---|
| ZIP, parse, CSS, IR, cache | `EpubWorker`: isolate onde existe, cooperativo no web | CPU pura, sem `dart:ui` |
| Shaping, layout, paginação | Isolate principal, em fatias com orçamento | `dart:ui` exige o isolate principal |
| Pintura, seleção, semântica | Isolate principal | Framework |

Ver [08](08-concorrencia-cache.md).
