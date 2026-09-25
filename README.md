# galley

[![CI](https://github.com/EduardoSA8006/galley/actions/workflows/ci.yml/badge.svg)](https://github.com/EduardoSA8006/galley/actions/workflows/ci.yml)

Motor de renderização de EPUB para Flutter, nativo, sem WebView.

Três propriedades como razão de existir: **rápido** (primeira página em menos de
300 ms, virada em um frame), **leve** (zero plugins nativos, zero dependências
de UI) e **fácil de adotar** (um leitor funcional em dez linhas).

## Estado

Fase 0 concluída (exceto o spike S3, de acessibilidade, que depende de aparelho
físico): spikes, corpus de 65 EPUBs, harness de desempenho com baseline por
modelo de CPU e CI. Próximo passo: Fase 1 (contêiner, OPF/NAV/NCX e Camada A).
Nenhuma API pública ainda. Flutter mínimo: 3.47.0.

O que ficou para depois está em [`doc/14-pendencias.md`](doc/14-pendencias.md).
Para contribuir, veja [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Documentação

A arquitetura completa está em [`doc/`](doc/README.md): contrato de fidelidade,
modelo de estilo, IR do documento, layout e paginação, render e acessibilidade,
locator, API pública, concorrência, diagnósticos, testes, roadmap e fases.

Para entender o que o pacote é: [00](doc/00-visao-geral.md) e
[01](doc/01-decisoes.md). Para implementar: [03](doc/03-camada-a-ir.md) →
[04](doc/04-layout-paginacao.md) → [05](doc/05-render-selecao-a11y.md).
