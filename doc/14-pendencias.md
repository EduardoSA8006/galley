# 14 — Pendências

Lista viva do que ficou para depois: melhorias adiadas de propósito, pontos que
um spike deixou em aberto e verificações que dependem de algo que ainda não
existe (motor, aparelho, versão). Quem adia alguma coisa anota aqui, com a
origem; quem resolve move a linha para **Concluídas** com a data e o commit.

A decisão de arquitetura continua morando no documento de origem. Esta lista só
aponta para ela e diz **quando** voltar ao assunto.

## Abertas

### Infraestrutura, medição e CI

| Item | Origem | Quando |
|---|---|---|
| Segunda fonte de métricas no harness de desempenho: engine real em `--profile` via `flutter drive` no Linux, com timeline, alimentando o mesmo baseline e o mesmo comparador. O harness da Fase 0 roda em JIT no `flutter_tester` e só detecta regressão; não mede o orçamento de [10](10-testes.md) §4.1 | Brainstorming do harness (2026-09-25) | Fase 2, junto com o teste de jank de [10](10-testes.md) §4.3 |
| Medir o orçamento de [10](10-testes.md) §4.1 no dispositivo de referência (Android classe Pixel 6a, `--profile`), fora do CI | [10](10-testes.md) §4.1 | A partir da Fase 2 |
| Métrica de memória (pico e memória nativa de `ui.Paragraph`/`ui.Image`) no harness | [10](10-testes.md) §4.1 | Fase 2 |
| Jobs de CI em macOS e Windows (diferenças de caminho e de fonte) | Brainstorming do CI (2026-09-25) | Antes da Fase 6 |
| Job de CI no web (`flutter test --platform chrome`, corretude no DDC) e medição de P10 em build de release no Chrome | Brainstorming do CI (2026-09-25); [10](10-testes.md) §4.4 | Quando começar o trabalho da 1.0.x |
| Reformatar os spikes S5–S8 no formatter do Dart 3.13 (7 arquivos de `test/spike/` divergem do `dart format`) | Consolidação dos spikes (2026-09-25) | Junto com o CI da Fase 0 |

### Fase 1

| Item | Origem | Quando |
|---|---|---|
| P7: inflate no web, implementação própria ou `archive` por import condicional, pelo tamanho do bundle | [01](01-decisoes.md) P7; [11](11-empacotamento-versionamento.md) §1 | Fase 1 |
| Confirmar em AOT que a chave FNV-1a de uma seção de 500 KB fica abaixo de 1 ms (P8) | [08](08-concorrencia-cache.md) §4.1 | Fase 1 |
| Confirmar o custo de spawn de isolate (0,07–0,24 ms no desktop) em Android AOT | [08](08-concorrencia-cache.md) §1; S9 | Fase 1 |
| Parse fatiável para o web: medir `parseFragment` em pedaços de ~16 KB, tokenizer próprio e Web Worker | [08](08-concorrencia-cache.md) §1; S9 | Fase 1 (pré-requisito da 1.0.x) |
| Cessão entre fatias por `MessageChannel` (ou `scheduler.postTask`) em vez de `Timer`, por causa do clamp de ~4,2 ms do navegador | [08](08-concorrencia-cache.md) §2; S9 | Fase 1 (pré-requisito da 1.0.x) |
| SVG-invólucro desembrulhado e repaginação quando a dimensão da imagem chega | S7; [13](13-riscos-spikes-fases.md) §1 | Fase 1 |
| Tamanho do pacote no web (inflate, SHA-1, CSS), teto de 300 KB minificado | [13](13-riscos-spikes-fases.md) §1.2 | Fase 1 |

### Fase 2

| Item | Origem | Quando |
|---|---|---|
| Tabela de SpecialCasing própria no `DisplayMap` (`ß → SS` igual em VM e web), ~1 dia | S2; [04](04-layout-paginacao.md) §1.1 | Fase 2 |
| Primeira página rápida com tabela grande no início da seção: declarar a exceção ou medir as primeiras N linhas e repaginar | S4; [04](04-layout-paginacao.md) §2.3 | Fase 2 |
| Tabela: `rowSpan` que sai do cabeçalho para o corpo e tabela que começa no meio de uma página (não tratados no protótipo) | S4; [04](04-layout-paginacao.md) §9 | Fase 2 |
| Reexaminar `StrutStyle` na versão mínima fixada (no 3.44.1 não alterava a altura de linha) | S5; [04](04-layout-paginacao.md) §1 | Fase 2 |

### Fase 4

| Item | Origem | Quando |
|---|---|---|
| S3: acessibilidade com TalkBack e VoiceOver reais, incluindo se `headingLevel` chega fora do web | [13](13-riscos-spikes-fases.md) S3; [05](05-render-selecao-a11y.md) §4.3 | Quando houver aparelho físico; fecha na Fase 4 |
| Seleção completa (~14 dias): alças da plataforma, auto-avanço, modo contínuo, gestos, RTL/CJK | S2; [13](13-riscos-spikes-fases.md) §1.1 | Fase 4 |
| Verificação da seleção em aparelho real (alças, lupa, háptico, arena de gestos, auto-avanço, Impeller) | S2; [13](13-riscos-spikes-fases.md) §1.1 | Fase 4 |
| `text-transform`: `capitalize`, `lowercase` com `İ`, locale `tr`, ligaduras de fonte real | S2; [13](13-riscos-spikes-fases.md) §1.1 | Fase 4 |

### Depois da 1.0

| Item | Origem | Quando |
|---|---|---|
| Medir rios de `justify` com U+00AD e o dicionário `hyph-pt`; min-content de célula hifenizada calculado pelo motor | S5; [04](04-layout-paginacao.md) §8 | 1.2 |
| P9: fixed-layout no núcleo ou em `galley_fixed_layout` | [01](01-decisoes.md) P9; [12](12-roadmap.md) | Antes da 1.1 |

## Concluídas

| Item | Data | Commit |
|---|---|---|
