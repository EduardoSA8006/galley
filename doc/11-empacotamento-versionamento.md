# 11 — Empacotamento e versionamento

**Decisão 10.1: dependências mínimas. Emenda 15: tipos extensíveis.**

## 1. Dependências

| Pacote | Papel | Justificativa |
|---|---|---|
| `html` | Parse de XHTML | Mantido pelo time do Dart, sem dependências transitivas relevantes; tolerante a HTML malformado |
| `xml` | OPF, NAV, NCX, `container.xml`, `encryption.xml` | Padrão do ecossistema, estável |
| `meta` | `@immutable`, `@visibleForTesting` | Já é dependência transitiva do Flutter |
| — | ZIP | Leitor de central directory próprio, ~300 linhas, com ZIP64 |
| — | Hash | Implementação própria (FNV-1a para chaves internas, SHA-1 para o cache; ~150 linhas) |
| — | Inflate | `dart:io` `ZLibDecoder` onde disponível; implementação própria no web (~400 linhas, ou `archive` só no web via import condicional, a decidir na Fase 1 pelo tamanho do bundle) |

Zero plugins nativos. Zero dependências de UI. Zero rede.

`crypto` (do time do Dart) seria aceitável para o SHA-1, mas são 150 linhas e
evitar a dependência mantém a árvore trivial. Decisão da Fase 1.

### 1.1 Por que não `epub_pro`

Ele funciona bem e é bem mantido, mas:

- Traz `image`, `word_count`, `collection` e `path`. O `image` é peso morto num
  motor que decodifica via `dart:ui`
- Não entrega ZIP com acesso aleatório lazy na forma que
  [08](08-concorrencia-cache.md) §1 exige, e essa forma é a base de toda a
  arquitetura de desempenho
- O modelo de dados dele é uma árvore de capítulos, não a IR plana da
  [Decisão 3](01-decisoes.md)

Reusá-lo custaria uma camada de adaptação e um teto de desempenho. A conversão
não vale.

### 1.2 Por que não `flutter_html`

Foi a viga podre da geração anterior de leitores nativos: precisa de
`flutter_html_table` porque o 3.x abandonou tabelas, tem bugs de altura zero com
`text-align` inline, e renderiza capítulos em branco em certos arquivos. Mais
grave: usá-lo apenas no "caso geral" com um fast-path próprio para o caso simples
cria **dois motores de tipografia com comportamentos divergentes**, o que produz
inconsistência invisível em review e visível na leitura.

### 1.3 Por que não `TextPainter`

`TextPainter` é o wrapper do framework sobre `ui.Paragraph`, com escala de texto,
`InlineSpan` e placeholders. Ele aloca e mantém estado por instância e é feito
para um texto por widget. O motor usa `ui.ParagraphBuilder` e `ui.Paragraph`
diretamente: menos uma camada, controle do ciclo de vida (`dispose`), e chave de
cache que é nossa. O que `TextPainter` faria por nós (escala, placeholder) são
poucas linhas.

## 2. Plataformas

Todas as seis: Android, iOS, macOS, Windows, Linux, web.

Sendo Dart e Flutter puros, sem plugin nativo, isso sai de graça. Pontos de
atenção:

| Plataforma | Ponto |
|---|---|
| web | `dart:io` indisponível. `FileEpubByteSource` e `FileEpubCacheStore` atrás de import condicional; o app fornece implementações sobre IndexedDB ou memória |
| web | Sem isolates. `CooperativeEpubWorker` ([08](08-concorrencia-cache.md) §1) |
| web | Inflate próprio, sem `ZLibDecoder` |
| web | Só o renderer CanvasKit/Skwasm é suportado. O renderer HTML (removido do Flutter) não tem `computeLineMetrics` confiável |
| Desktop | Redimensionamento contínuo exige o debounce de [04](04-layout-paginacao.md) §6; teclado e mouse de [05](05-render-selecao-a11y.md) §5.1 |
| iOS/Android | `didHaveMemoryPressure` é o gatilho de eviction; `AppLifecycleState` pausa o agendador |

Versão mínima do Flutter: a **stable mais antiga que tem
`Paragraph.getClosestGlyphInfoForOffset` e `SemanticsFlag.isHeader` com nível**,
fixada na Fase 0 e coberta por testes das APIs de `dart:ui` que usamos
(`computeLineMetrics`, `getBoxesForRange`, `addPlaceholder`, soft hyphen).

## 3. Política de versionamento

Semver estrito. O que conta como quebra:

### 3.1 Quebra (major)

- Mudança em qualquer assinatura pública
- **Adição de valor a enum público** (quebra `switch` exaustivo em Dart). É por
  isso que `EpubFidelity` já declara `faithful` na 1.0
  ([Emenda 2](01-decisoes.md))
- **Adição de subtipo a classe `sealed` pública**, pelo mesmo motivo (§3.3)
- Mudança no JSON do `Locator`: é formato **persistido pelo app**, então
  alterá-lo invalida dados de usuário. Adicionar campo em `otherLocations` é
  minor; remover ou renomear é major
- Mudança na regra de normalização de `canonicalText`: desloca todos os
  `charOffset` salvos. Se for inevitável, exige incremento de major **e** um
  migrador documentado; o reparo por citação ([06](06-locator-navegacao.md) §4)
  é a rede de segurança, não a solução

### 3.2 Não quebra (minor/patch)

- Bump de `IR_SCHEMA_VERSION`: o cache em disco regenera sozinho, invisível ao app
- Novo campo opcional em `EpubStyle` com padrão (por isso `EpubStyle` é `final
  class` e não pode ser implementada)
- Novo `EpubDiagnosticCode` (classe com constantes, §3.3)
- Novo callback opcional em `EpubReader`
- Melhoria de layout que muda pixels sem mudar `charOffset`
- Nova exceção não-fatal (nunca chega ao app como exceção)

### 3.3 Tipos que crescem × tipos fechados (Emenda 15)

Em Dart 3, **`sealed` é o que torna o `switch` exaustivo**. Adicionar um subtipo
a uma classe selada quebra os consumidores da mesma forma que adicionar um valor
a um enum. A v0.2 sugeria classes seladas como saída; isso estava errado.

| Tipo | Forma | Motivo |
|---|---|---|
| `EpubFidelity`, `ReadingMode`, `EpubReadingDirection`, `EpubLayoutMode`, `EpubSeverity`, `EpubTextAlign`, `EpubIndentStyle`, `HighlightStyle` | `enum` | Fechados por natureza; se crescerem é major mesmo |
| `BlockKind`, `ContainerKind`, `ObjectKind`, `ListMarker` | `enum` | São a IR; crescer exige bump de `IR_SCHEMA_VERSION` e revisão de todo consumidor da Camada 3, então major é honesto |
| `EpubDiagnosticCode` | `final class` com `static const` | Cresce a cada release; consumidores comparam por identidade e tratam desconhecidos por `default` |
| `InlineAttr` | `abstract final class` com `static const int` (bits) | Bitmask; bits novos são ignorados por consumidores antigos |
| `EpubException` e subclasses | `abstract base class` / `final class` | Nova exceção não deve quebrar `catch` ou `switch` |
| Modelos (`EpubStyle`, `Locator`, `Block`, `Section`, `ReaderState`...) | `final class` | Campos novos com padrão são minor; ninguém implementa ou estende |
| Interfaces injetadas (`EpubByteSource`, `EpubCacheStore`...) | `abstract interface class` | O app implementa; adicionar método é major, então elas são mínimas de propósito |

## 4. Estrutura do repositório

```
galley/
  lib/
    galley.dart                   # export público mínimo
    src/
      container/                  # byte source, zip, inflate, opf, nav, ncx, encryption
      ir/                         # blocos, runs, normalização, serialização
      css/                        # subconjunto, cascata, três classes
      style/                      # camada B: resolução, DisplayText, DisplayMap
      layout/                     # camada C: fluxo, paginação ancorada, tabela, agendador
      render/                     # RenderEpubPage, seleção, semântica, gestos, teclado
      locator/                    # readium locator, reparo, progresso, notas
      api/                        # EpubDocument, EpubReader, controller, ReaderState
      worker/                     # EpubWorker, isolate e cooperativo
      io/                         # byte source e cache store de arquivo (condicional)
  test/
    corpus/                       # os 40–50 arquivos + READMEs + diagnósticos esperados
    invariants/                   # as 9 invariantes
    snapshots/                    # gate textual (FlutterTest e fonte OFL)
    goldens/                      # subconjunto de imagem
    interaction/                  # gestos, teclado, ciclo declarativo
    perf/                         # baseline + jank
    fonts/                        # fonte OFL de teste
  example/                        # leitor completo, é o teste de adoção
  doc/                            # esta documentação
```

## 5. Licença e nome

Licença: **BSD-3-Clause** ou MIT, para não criar atrito de adoção comercial.
Dicionários de hifenização (v1.2) têm licenças próprias (LPPL, MIT), listadas em
`LICENSES/`.

Nome: **`galley`** (P3 em [01](01-decisoes.md), decidida). *Galley proof* é a
prova de gráfica, o texto composto antes de ser paginado, o que é exatamente o
que o motor produz. Verificado livre no pub.dev em 2026-09-07; repositório em
`github.com/EduardoSA8006/galley`. Não contém
`flutter_` nem `epub_`, o que evita colisão com `epub_view`, `epub_viewer` e
`flutter_epub_viewer`. Pacotes irmãos seguem o prefixo: `galley_svg`,
`galley_hyphenation`, `galley_fixed_layout` (se a 1.1 for separada).
