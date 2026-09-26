# Como contribuir

O galley está na Fase 0 → Fase 1: a arquitetura está em [`doc/`](doc/README.md)
e a API pública ainda não existe. Antes de propor mudança de comportamento, leia
o documento da camada que ela toca e [`doc/01-decisoes.md`](doc/01-decisoes.md).

Ao participar, você concorda com o [Código de Conduta](CODE_OF_CONDUCT.md).

## EPUB que quebra

É a contribuição mais valiosa. Abra uma issue com o modelo **EPUB que quebra**
e anexe o arquivo, ou um trecho reduzido que reproduza o problema com o texto
trocado por lorem ipsum. Arquivo com direitos autorais não entra no repositório
([doc/10](doc/10-testes.md) §1).

## Ambiente

- Flutter **3.47.0** ou mais novo (o CI testa o mínimo e o `stable`).
- Linux para os testes na engine real (`example/integration_test/`).

## Antes de abrir a PR

```sh
dart format --output=none --set-exit-if-changed lib test tool example/lib example/integration_test
flutter analyze && (cd example && flutter analyze)
flutter test
```

Desempenho (o CI roda e compara com o baseline da CPU do runner):

```sh
flutter test --tags perf --run-skipped --concurrency=1 test/perf
dart run tool/perf/compare.dart
```

Engine real, **um arquivo por invocação**:

```sh
cd example && flutter test integration_test/<arquivo>_test.dart -d linux
```

## PRs

- A `main` é protegida: toda mudança entra por PR, com `analyze`,
  `test (min)`, `test (stable)`, `engine-linux` e `perf` verdes e a branch
  em dia com a `main` (use "Update branch" na PR, ou `git merge origin/main`).
- Commits pequenos e com mensagem no formato `tipo(escopo): resumo`
  (`feat`, `fix`, `docs`, `perf`, `ci`, `chore`, `test`).
- Texto (docs, comentários, mensagens) em português brasileiro;
  identificadores em inglês.
- Nada de arquivo de depuração versionado.
- O que ficar para depois vai para [`doc/14-pendencias.md`](doc/14-pendencias.md)
  no mesmo commit.
- Mudar o baseline de desempenho é commit deliberado: gere pelo workflow
  `perf-baseline` e copie o arquivo para `test/perf/baselines/`
  ([doc/10](doc/10-testes.md) §4.2).
