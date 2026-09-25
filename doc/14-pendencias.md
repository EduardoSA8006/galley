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
| O workflow `perf-baseline` não publica o candidato quando a conferência final falha (sem `if: always()` no upload); decidir se deve publicar para inspeção | Implementação do harness (2026-09-25) | Na primeira vez que o baseline for regenerado |
| `combineBaseline` confere Flutter e casos entre execuções, mas não `dart`/`os`; herda do primeiro | Implementação do harness (2026-09-25) | Se o baseline passar a combinar runners diferentes |
| Cobrir o EPYC 9V74 e outros modelos que aparecerem com baseline próprio (disparar o `perf-baseline` até cair neles) | Sub-tarefa 10b — baseline por modelo de CPU (2026-09-25) | Contínuo |
| Versão do pacote `html` não travada para o perf (`/pubspec.lock` é ignorado): registrar as versões resolvidas dos pacotes medidos no `result.json` e avisar quando divergirem do baseline | Revisão final do harness (2026-09-25) | Fase 1 |

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
| Reformatar os spikes S5–S8 no formatter do Dart 3.13 | 2026-09-25 | c6d312a |
| Medir a variação entre VMs antes de commitar o baseline e decidir baseline por CPU. Resultado: dentro do mesmo modelo (EPYC 7763, 3 VMs) a razão varia no máximo 8,3%; entre quatro modelos (EPYC 7763, EPYC 9V45, Xeon 6973P-C, Xeon 8370C) varia até 30% (zlib), 22% (html) e 21% (paragraph). Decisão: baseline por modelo de CPU, um arquivo por modelo em `test/perf/baselines/`; CPU sem baseline só avisa | 2026-09-25 | 28f10e8, db3a518 |
| A CLI `update_baseline.dart` não tinha teste automatizado próprio; ganhou `test/tool/perf_update_baseline_test.dart` ao adicionar `--out-dir` por TDD | 2026-09-25 | 28f10e8 |
| Proteção de branch na `main` exigindo `analyze`, `test (min)`, `test (stable)`, `engine-linux` e `perf` (sem revisão obrigatória, sem exigir branch atualizada, admin pode passar por cima; force-push e exclusão bloqueados) | 2026-09-25 | configuração do repositório |
