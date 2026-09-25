# Harness de desempenho e CI da Fase 0 — design

**Data:** 2026-09-25. **Estado:** aprovada e implementada (plano em
`doc/plans/2026-09-25-harness-ci.md`). **Branch:** `fase0/harness-ci`.

## 1. Objetivo

Fechar os dois itens da Fase 0 que ainda faltam ([13](../13-riscos-spikes-fases.md)
§2): **harness de medição com baseline versionado** e **versão mínima do
Flutter fixada**. A partir da Fase 1, toda PR e todo push na `main` passam por
um gate automático de qualidade e de desempenho, para que nenhuma regressão
entre em silêncio ([10](../10-testes.md) §4).

**Critério de sucesso:** uma PR com regressão real de desempenho fica vermelha,
e uma PR sem regressão não fica vermelha por ruído do runner.

### 1.1 O que o usuário decidiu

- Harness completo **com CI** no GitHub Actions antes da Fase 1.
- Flutter mínimo **3.47**.
- Gate de desempenho **normalizado e bloqueante**.
- Jobs extras: **engine real no Linux** e **matriz de versão do Flutter**. Web,
  macOS e Windows ficam fora, anotados em [14](../14-pendencias.md).
- Abordagem **A** para o harness (próprio, sobre `flutter test`, no
  `flutter_tester`). A engine real em `--profile` fica como melhoria futura
  ([14](../14-pendencias.md)).

### 1.2 Premissas

- CI em runners hospedados do GitHub (Ubuntu); o repositório é público.
- O dispositivo de referência de [10](../10-testes.md) §4.1 fica fora do CI.
- Na Fase 0 não há motor: o baseline cobre só primitivas das quais o motor vai
  depender. O código de spike não entra no baseline (é descartável,
  `spike/README.md`).
- Os números do harness são JIT no `flutter_tester`. Servem para detectar
  regressão, não para verificar o orçamento absoluto de [10](../10-testes.md)
  §4.1.

## 2. Harness

### 2.1 Arquivos

| Caminho | Papel |
|---|---|
| `test/perf/support/perf_harness.dart` | `PerfCase`, calibração, `measureCase`, escrita do JSON |
| `test/perf/support/perf_inputs.dart` | Entradas determinísticas dos casos (XHTML, deflate, PNG) |
| `test/perf/perf_test.dart` | Declara os casos; tag `perf` |
| `dart_test.yaml` | Declara a tag `perf` com `skip`, para a execução padrão pulá-la |

`flutter test` sem argumentos **não** mede: os casos `perf` aparecem como
pulados. O harness roda com `flutter test --tags perf --run-skipped test/perf`.
Verificado no Flutter 3.47.5: `exclude_tags: perf` no `dart_test.yaml` não
serve, porque `--tags perf` conflita com ele e o runner recusa a execução;
`tags: perf: skip: "<motivo>"` com `--run-skipped` funciona.

### 2.2 `PerfCase`

```dart
final class PerfCase {
  const PerfCase({
    required this.id,          // estável; é a chave do baseline
    required this.run,         // corpo medido, síncrono
    this.setUp,                // preparação fora do tempo, pode ser async
    this.innerIterations = 1,  // repetições do corpo por amostra
  });
}
```

Casos assíncronos por natureza (decodificação de imagem) expõem `runAsync` em
vez de `run`; exatamente um dos dois é obrigatório.

### 2.3 Normalização

- **Calibração:** carga fixa em Dart puro, ~5 ms no desktop de
  desenvolvimento: FNV-1a 32 sobre 64 KB, construção de `String` com
  `StringBuffer`, inserções e buscas num `Map<String, int>` e `List.sort` de
  inteiros com semente fixa. O resultado é consumido (acumulado num campo) para
  o compilador não eliminar o trabalho.
- **Amostragem:** 3 amostras de aquecimento descartadas, depois 15 amostras.
  Cada amostra mede **a calibração e em seguida o caso**, com `Stopwatch`.
- **Métrica:** `ratio = mediana(tempo_caso_i / tempo_calibração_i)`. A razão
  intercalada cancela o ruído passageiro melhor que uma calibração única.
- Também se registram a mediana em µs do caso e da calibração, para leitura
  humana; o gate usa só `ratio`.

### 2.4 Casos da Fase 0

| id | O que mede | Entrada |
|---|---|---|
| `html.parse.500kb` | `html.parse` | XHTML de ~500 KB com a prosa de `tool/corpus/lib/text.dart` |
| `paragraph.shape.1000` | `ui.ParagraphBuilder` + `layout` de 1000 parágrafos | 40 palavras cada, fonte FlutterTest, largura 320 |
| `zlib.inflate.1mb` | `ZLibDecoder` (`raw: true`) | 1 MB de prosa comprimida com `ZLibEncoder(raw: true)` no `setUp` |
| `image.decode.target` | `instantiateImageCodec` + `getNextFrame` com `targetWidth` | PNG gerado por `tool/corpus/lib/png.dart` |

Da Fase 1 em diante, casos novos entram como novas entradas em
`perf_test.dart`, sem mexer no harness.

### 2.5 Saída

`build/perf/result.json` (fora do git, `build/` já é ignorado):

```json
{
  "schema": 1,
  "flutter": "3.47.0",
  "dart": "3.13.0",
  "os": "linux",
  "cpu": "AMD EPYC 7763 64-Core Processor",
  "createdAt": "2026-09-25T12:00:00Z",
  "cases": {
    "html.parse.500kb": {
      "ratio": 7.41,
      "medianUs": 36120,
      "calibrationUs": 4874,
      "samples": [7.38, 7.44]
    }
  }
}
```

A versão do Flutter vem de `FLUTTER_VERSION` quando definida (o CI define) e,
senão, de `Process.run('flutter', ['--version', '--machine'])`; se o processo
falhar, o campo vale `"unknown"` e o comparador avisa como versão diferente. A
versão do Dart vem de `Platform.version`. A CPU vem de `/proc/cpuinfo`
(primeira linha `model name`); fora do Linux, ou se o arquivo não existir ou
não tiver essa linha, o campo vale `"unknown"`.

## 3. Comparador e baseline

### 3.1 Arquivos

| Caminho | Papel |
|---|---|
| `tool/perf/lib/perf_report.dart` | Modelo do JSON, leitura e validação |
| `tool/perf/lib/compare.dart` | Regras de comparação, tabela Markdown |
| `tool/perf/compare.dart` | CLI: `dart run tool/perf/compare.dart [--result R] [--baseline B] [--baselines DIR]` |
| `tool/perf/update_baseline.dart` | CLI: mediana por caso de 1 ou mais `result.json` → baseline; padrão: `--out-dir build/perf/baselines`, um arquivo por CPU |
| `test/perf/baselines/<cpu>.json` | Baselines versionados, um por modelo de CPU (`baselineFileName`, `tool/perf/lib/baseline.dart`) |
| `test/tool/perf_compare_test.dart` | Testes do comparador, na suíte normal |

Dart puro, sem dependências novas.

### 3.2 Regras

| Situação | Resultado |
|---|---|
| `ratio_atual / ratio_baseline > 1,20` | **Falha** (regressão) |
| `ratio_atual / ratio_baseline < 0,80` | Aviso: melhora; sugere atualizar o baseline |
| Caso no resultado, ausente do baseline | Aviso: caso novo sem baseline |
| Caso no baseline, ausente do resultado | **Falha**: caso sumiu sem atualizar o baseline |
| Flutter do resultado ≠ Flutter do baseline | Compara e avisa em destaque |
| CPU do resultado ≠ CPU do baseline | Compara e avisa |
| Arquivo de baseline inexistente | Todos os casos viram "caso novo"; não falha |
| Runner numa CPU sem baseline (nenhum arquivo em `test/perf/baselines/` para o modelo) | Todos os casos viram "caso novo"; não falha; a mensagem lista as CPUs com baseline existente |
| JSON malformado ou `schema` desconhecido | **Falha** com mensagem que diz qual arquivo e qual campo |

Os limites 1,20 e 0,80 são constantes nomeadas no código. A saída é uma tabela
Markdown (caso, baseline, atual, variação, estado) no stdout e, quando
`GITHUB_STEP_SUMMARY` existe, acrescentada a esse arquivo. Código de saída 1 se
houver falha, 0 caso contrário.

### 3.3 Atualização do baseline

Commit deliberado, nunca automático ([10](../10-testes.md) §4.2):

1. O workflow manual `perf-baseline.yml` roda o harness 3 vezes no mesmo runner,
   chama `update_baseline.dart --out-dir build/perf/baselines` sobre os três
   resultados e publica o diretório com o baseline candidato (um arquivo,
   nomeado pelo modelo da CPU do runner) como artefato.
2. O mantenedor baixa o artefato e copia o arquivo para
   `test/perf/baselines/`, commitando com a justificativa na mensagem. Uma CPU
   nova ganha um arquivo novo; uma CPU já coberta tem o arquivo substituído.

Cada arquivo de `test/perf/baselines/` tem o formato de `result.json` sem
`samples` e com `sourceCommit`, `runner` (ex.: `ubuntu-24.04`) e `runs`
(número de execuções combinadas).

## 4. CI

### 4.1 `.github/workflows/ci.yml`

Gatilhos: `push` em `main` e `pull_request`. `permissions: contents: read` no
topo. `concurrency` por branch com `cancel-in-progress` só quando o evento é
`pull_request` (execuções da `main` nunca são canceladas). Instalação por
`subosito/flutter-action@v2` com `cache: true`. Variável única no topo:
`FLUTTER_MIN: 3.47.0`. Todo job tem `timeout-minutes`.

| Job | Flutter | Timeout | Passos |
|---|---|---|---|
| `analyze` | `FLUTTER_MIN` | 15 | `flutter pub get`; `dart format --output=none --set-exit-if-changed lib test tool example/lib example/integration_test`; `flutter analyze`; `cd example && flutter analyze` |
| `test` | matriz `FLUTTER_MIN` e canal `stable` | 30 | `flutter test` (sem `perf`) |
| `engine-linux` | `FLUTTER_MIN` | 30 | `apt-get install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev xvfb fonts-noto-core fonts-liberation`; para cada arquivo de `example/integration_test/`: `xvfb-run -a flutter test <arquivo> -d linux`, **um arquivo por invocação**. As fontes Noto Serif e Liberation Serif atendem o S5.7: sem elas o fontconfig troca a fonte em silêncio |
| `perf` | `FLUTTER_MIN` | 30 | `flutter test --tags perf --run-skipped --concurrency=1 test/perf`; `dart run tool/perf/compare.dart`; `result.json` como artefato |

`--concurrency=1` no harness de `perf` evita que o `perf_harness_test.dart`
compita por CPU com a própria medição.

Uma falha só no `stable` deixa a PR vermelha: sinaliza incompatibilidade real
com o Flutter que os usuários vão instalar.

### 4.2 `.github/workflows/perf-baseline.yml`

Gatilho: `workflow_dispatch`. `permissions: contents: read` no topo.
`timeout-minutes: 45` no job `baseline`. Mesmo runner e `FLUTTER_MIN` do job
`perf`. Roda o harness 3 vezes (`--concurrency=1`, mesmo motivo do job `perf`),
copiando cada `result.json` para um nome distinto, chama
`update_baseline.dart --out-dir build/perf/baselines` e publica o diretório
como artefato `perf-baseline`.

### 4.3 Primeira execução

O baseline inicial foi gerado pelo `perf-baseline.yml` e entrou num commit
próprio: um arquivo por modelo de CPU observado no runner `ubuntu-24.04`
([14](../14-pendencias.md)). Uma CPU sem arquivo em `test/perf/baselines/`
não falha o job `perf`: todos os casos viram "caso novo" e a mensagem lista as
CPUs já cobertas (§3.2). A cobertura cresce a cada disparo do
`perf-baseline` numa CPU nova.

## 5. Versão mínima e limpeza

- `pubspec.yaml`: `flutter: ">=3.47.0"` e `sdk: ^3.13.0` (Dart da 3.47.0); sai
  a nota "revisar após os spikes". `example/pubspec.yaml` segue o mesmo mínimo.
- A troca do `sdk:` sobe a versão de linguagem; `dart format` e
  `flutter analyze` são rodados depois dela e o que mudar entra no mesmo commit.
- Os 7 arquivos de spike que divergem do formatter do Dart 3.13 são
  reformatados; o diff é conferido para ser só formatação.

## 6. Documentação

- [10](../10-testes.md) §4: harness como implementado (calibração intercalada,
  20% sobre a razão, baseline registrado no runner, JIT no `flutter_tester`).
- [11](../11-empacotamento-versionamento.md) §2: mínimo 3.47 e o critério (é o
  que o CI testa; subir é commit deliberado).
- [13](../13-riscos-spikes-fases.md) §2: Fase 0 concluída exceto S3.
- [14](../14-pendencias.md): a reformatação dos spikes vai para Concluídas;
  pendências novas da implementação entram no mesmo commit.
- `spike/README.md`: a nota "um arquivo por invocação" passa a citar o CI.

## 7. Entrega

Branch `fase0/harness-ci`, uma PR, commits separados:

1. Esta spec e `doc/14-pendencias.md`.
2. Versão mínima 3.47 e formatação.
3. Harness, casos e comparador, com testes.
4. Workflows.
5. Documentação.

## 8. Fora do escopo

Engine real em `--profile`, métricas de memória, dispositivo de referência,
jobs de web, macOS e Windows. Todos estão em [14](../14-pendencias.md) com o
momento de voltar a eles.
