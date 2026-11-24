# Galley SP2 — Benchmark e corpus — Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Infraestrutura de benchmark do Galley: corpus (público + privado), harness próprio em Dart com os modos `instructions`, `ab`, `local`, `compare` e `size`, gates autônomos por PR, contadores determinísticos, integração com o Bencher e workflows de CI.

**Architecture:** Pacote Dart separado `benchmark/` (não publicado), com dependência `galley` via path e com os concorrentes. Os benchmarks são registrados num catálogo e executados por um binário AOT único (`bench_runner`), um benchmark por processo, sob Valgrind/`perf`/cronômetro. O orquestrador `tool/bench.dart` compila a `main` e o PR, mede, decide o gate e escreve o Bencher Metric Format (BMF).

**Tech Stack:** Dart 3.13 (AOT via `dart compile exe`), Valgrind cachegrind, `perf stat`, GitHub Actions, Bencher CLI. Dependências do pacote `benchmark`: `galley` (path), `epubx`, `epub_plus`, `epub_pro`, `args`, `crypto` (permitidos aqui; o `galley` continua só com `xml`/`meta`).

**Spec:** `docs/superpowers/specs/2026-11-24-galley-sp2-benchmark-design.md` (pai: `2026-11-24-galley-arquitetura-design.md` §6)

## Global Constraints

- Dependências de runtime do pacote `galley` continuam **somente** `xml` e `meta`. Nada de benchmark ou concorrente entra no `pubspec.yaml` da raiz.
- `benchmark/` é um pacote separado com `publish_to: none`. O `.pubignore` da raiz exclui `benchmark/` e `corpus/`.
- Os jobs de benchmark usam Flutter/Dart **fixos em 3.47.5** (Dart 3.13.4). Os jobs de teste mantêm a matriz 3.47.5 + stable.
- Limites:
  - instruções: regressão **> 0,5%** (`0.005`) reprova o PR;
  - A/B: reprova quando a regressão é **≥ 5%** e o IC 95% por bootstrap da razão das medianas fica inteiro **acima de 1,05**;
  - regressão gradual: **10%** desde o baseline (inicial: `d4ef38a`), e reprova **só o noturno**;
  - tamanho: **2 MiB = 2.097.152 bytes**, APK release split-per-abi arm64;
  - contador do livro de 300 MB: no máximo **256 KiB = 262.144 bytes** lidos ao abrir.
- O workflow de PR leva no máximo **~15 min** de parede.
- Nunca rodar código do PR com acesso a secrets: o upload ao Bencher acontece em `workflow_run`.
- Corpus privado: títulos e nomes de arquivo nunca saem da máquina. Só vão agregados ou IDs `sha256` truncados em 12 caracteres hexadecimais.
- Comentários e docs em português do Brasil; identificadores em inglês; commits em português `tipo(escopo): descrição`.

## Review Focus

1. Benchmark novo no PR, sem equivalente na `main`: o gate não reprova e o relatório o marca como `novo` (teste na Task 5).
2. Benchmark que existe na `main` e sumiu no PR: não quebra e é marcado como `removido` (Task 5).
3. Valgrind ausente, ou `perf` bloqueado por `perf_event_paranoid`: erro claro com a instrução de correção, sem stack trace (Tasks 5 e 7).
4. Benchmark que lança exceção ou cujo checksum difere entre `main` e PR: falha explícita, nunca um número 0 ou comparação silenciosa (Tasks 4 e 5).
5. Download do corpus falhando nas duas URLs, ou com `sha256` divergente: o job falha com o `id` do livro e a causa (Task 3).

---

## Estrutura de arquivos

```
benchmark/
  pubspec.yaml  analysis_options.yaml  README.md
  bin/bench_runner.dart            # executa 1 benchmark: --bench <id> --iterations N → imprime checksum
  lib/src/catalog.dart             # registro de benchmarks
  lib/src/bench.dart               # contrato Bench
  lib/src/bmf.dart                 # Bencher Metric Format
  lib/src/corpus/{manifest.dart, fetcher.dart, epub_writer.dart, handmade.dart, synthetic.dart, private_corpus.dart}
  lib/src/suites/{container_micro.dart, container_macro.dart}
  lib/src/modes/{instructions.dart, ab.dart, stats.dart, local.dart, compare.dart, size.dart, build.dart}
  lib/src/competitors/{adapter.dart, galley_adapter.dart, epubx_adapter.dart, epub_plus_adapter.dart, epub_pro_adapter.dart}
  size/with_galley/  size/without_galley/   # apps mínimos para o modo size
  tool/bench.dart                  # orquestrador (CLI com subcomandos)
  test/...
corpus/
  manifest.json  README.md
  handmade/                        # fontes (xhtml, css, opf parcial) por livro
  tool/mirror.sh                   # publica a release corpus-v1 (rodado manualmente, com aprovação)
.github/workflows/{bench-pr.yml, bench-pr-upload.yml, bench-nightly.yml}
test/features/container/counters_test.dart   # contadores determinísticos (no pacote galley)
dart_test.yaml                               # tag heavy
```

---

### Task 1: Pacote `benchmark/`, contrato `Bench`, catálogo e BMF

**Files:**
- Create: `benchmark/pubspec.yaml`, `benchmark/analysis_options.yaml`, `benchmark/lib/src/bench.dart`, `benchmark/lib/src/catalog.dart`, `benchmark/lib/src/bmf.dart`, `benchmark/bin/bench_runner.dart`
- Modify: `.pubignore` (acrescentar `benchmark/` e `corpus/`), `.github/workflows/ci.yml` (job `analyze-test` também roda `dart analyze --fatal-infos` e `dart test` em `benchmark/`)
- Test: `benchmark/test/bmf_test.dart`, `benchmark/test/runner_test.dart`

**Interfaces:**
- Produces:
  - `abstract interface class Bench { String get id; /* kebab, ex.: 'container/crc32-1mib' */ Future<void> setUp(); int run(); /* um ciclo de trabalho; devolve checksum */ Future<void> tearDown(); }`
  - `final class Catalog { static List<Bench> all(); static Bench byId(String id); /* ArgumentError se não existir */ }`
  - `final class Measure { final String slug; final double value; final double? lower; final double? upper; }`
  - `Map<String, Object> toBmf(Map<String, List<Measure>> byBenchmark)`: formato `{ "<bench>": { "<slug>": {"value": v, "lower_value": l?, "upper_value": u?} } }`
  - `bench_runner`: `dart run bin/bench_runner.dart --bench <id> --iterations <n>` faz `setUp`, executa `run` n vezes e `tearDown`, e imprime exatamente uma linha `checksum=<int>`. Para id desconhecido: stderr + exit 64.
  - Benchmark `noop` (id `harness/noop`, `run` devolve 0) para descontar a partida do processo.
- Slugs fixos: `instructions`, `wall-time-ns`, `peak-rss-bytes`, `bytes-read`, `size-bytes`.

- [ ] **Step 1: Testes que falham**: `toBmf` gera exatamente o JSON acima (com e sem `lower`/`upper`, omitindo as chaves nulas); `bench_runner --bench harness/noop --iterations 3` imprime `checksum=0` com exit 0; id inexistente sai com exit 64.
- [ ] **Step 2:** Rodar `cd benchmark && dart test` e ver FAIL.
- [ ] **Step 3:** Implementar o scaffolding e as interfaces. `pubspec` com `publish_to: none`, `environment.sdk: ">=3.13.0 <4.0.0"` e as deps do Tech Stack; o `analysis_options` inclui o da raiz.
- [ ] **Step 4:** PASS; `dart analyze --fatal-infos` limpo em `benchmark/`; `flutter test` da raiz continua verde.
- [ ] **Step 5: Commit** `feat(benchmark): pacote de benchmark, contrato Bench, catálogo e formato BMF`

---

### Task 2: Corpus escrito à mão e livros sintéticos (geração determinística)

**Files:**
- Create: `benchmark/lib/src/corpus/epub_writer.dart`, `benchmark/lib/src/corpus/handmade.dart`, `benchmark/lib/src/corpus/synthetic.dart`, `corpus/handmade/**` (fontes)
- Test: `benchmark/test/corpus/handmade_test.dart`, `benchmark/test/corpus/synthetic_test.dart`

**Interfaces:**
- Consumes: `package:galley/galley.dart` (`EpubBook`) e `package:galley/src/features/container/data/crypto/sha1.dart` (ofuscação IDPF).
- Produces:
  - `Future<Map<String, Uint8List>> buildHandmadeCorpus()`: id → bytes, **determinístico** (mesmo conteúdo a cada execução; timestamps zip fixos em 1980-01-01 e ordem de entradas fixa).
  - Ids: `hm/typography`, `hm/publisher-css`, `hm/tables`, `hm/notes`, `hm/images`, `hm/cjk`, `hm/rtl-bidi`, `hm/fonts-idpf`, `hm/fonts-adobe`, `hm/epub2-ncx`, `hm/malformed-no-mimetype`, `hm/malformed-case-mismatch`.
  - `Future<File> writeSyntheticBook(String path, {required int targetBytes, int chapters = 200})`: gera em streaming (sem montar tudo na memória) um EPUB válido de ~`targetBytes`. Os capítulos são texto de preenchimento determinístico, mais uma imagem *stored* grande para ocupar o tamanho.
  - Constantes `kSynthetic50MiB = 50 * 1024 * 1024`, `kSynthetic300MiB = 300 * 1024 * 1024`.
- O conteúdo textual dos livros à mão é de autoria própria (PT-BR, EN, JA, AR/HE), sem trechos de obras protegidas.

- [ ] **Step 1: Testes que falham**:
  - duas chamadas a `buildHandmadeCorpus()` devolvem os mesmos `sha256` por id;
  - cada livro `hm/*` não malformado abre com `EpubBook.fromBytes` sem diagnóstico de severidade `error`;
  - `hm/malformed-*` abre e emite o código esperado (`container.mimetypeMissing`, `resource.caseMismatch`);
  - `writeSyntheticBook` com 5 MiB gera um arquivo de 5 MiB ±5% que abre e cujo spine tem 200 itens;
  - durante a geração, o pico de RSS do processo cresce menos de 64 MiB (medido via `ProcessInfo.maxRss`).
- [ ] **Step 2:** FAIL. **Step 3:** Implementar. **Step 4:** PASS.
- [ ] **Step 5: Commit** `feat(benchmark): corpus escrito à mão e livros sintéticos determinísticos`

---

### Task 3: Manifesto do corpus público e fetcher com espelho e verificação

**Files:**
- Create: `corpus/manifest.json`, `corpus/README.md`, `corpus/tool/mirror.sh`, `benchmark/lib/src/corpus/manifest.dart`, `benchmark/lib/src/corpus/fetcher.dart`
- Test: `benchmark/test/corpus/fetcher_test.dart`

**Interfaces:**
- Produces:
  - `final class CorpusEntry { final String id; final Uri url; final Uri? mirrorUrl; final String sha256; final String license; final String source; final Set<String> tags; final bool mirrorable; }`. As tags vêm de `epub2`, `epub3`, `fixed-layout`, `cjk`, `rtl`, `tables`, `illustrated`, `technical`, `w3c-tests`, `large`.
  - `List<CorpusEntry> loadManifest(String path)`
  - `final class CorpusFetcher { CorpusFetcher({required Directory cacheDir, HttpClient? client}); Future<File> fetch(CorpusEntry e); }`. A ordem é: cache (`<cacheDir>/<sha256>.epub`) → `mirrorUrl` → `url`. Verifica o `sha256`. Em falha, lança `CorpusFetchException(id, causes)` com a causa de cada tentativa.
- Conteúdo do manifesto: o implementador escolhe **15–25 livros** de domínio público ou licença livre cobrindo todas as tags acima. Fontes: Standard Ebooks, Project Gutenberg, um acervo japonês de domínio público e W3C `epub-tests` num commit fixo (os EPUBs empacotados dos testes, não o repositório inteiro). Calcula o `sha256` real de cada um e registra licença e procedência no `corpus/README.md`. Os `mirrorUrl` apontam para `https://github.com/EduardoSA8006/galley/releases/download/corpus-v1/<id>.epub` só nos itens `mirrorable: true`.
- `mirror.sh` cria a release `corpus-v1` e envia os arquivos `mirrorable`. **Não executar.** Rodar só com aprovação do mantenedor, porque publica conteúdo.

- [ ] **Step 1: Testes que falham** (servidor `HttpServer` local nos testes):
  - cache presente → nenhuma requisição;
  - espelho OK → usa o espelho;
  - espelho 404 + url OK → usa a url;
  - `sha256` divergente → `CorpusFetchException` com `id` e causa `sha256 mismatch`;
  - as duas falham → exceção com as duas causas;
  - o manifesto real (`corpus/manifest.json`) carrega e cobre todas as tags.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar; montar o manifesto real (baixar, calcular `sha256`, conferir que cada livro abre com `EpubBook` e anotar no README os diagnósticos `error` observados). **Step 4:** PASS.
- [ ] **Step 5: Commit** `feat(corpus): manifesto do corpus público com fetcher, espelho e verificação sha256`

---

### Task 4: Suítes de benchmark da etapa Container

**Files:**
- Create: `benchmark/lib/src/suites/container_micro.dart`, `benchmark/lib/src/suites/container_macro.dart`; Modify: `benchmark/lib/src/catalog.dart`
- Test: `benchmark/test/suites_test.dart`

**Interfaces:**
- Consumes: `Bench`, `Catalog` (Task 1), `buildHandmadeCorpus` (Task 2); internos do galley via `package:galley/src/...`.
- Produces (ids). Cada benchmark leva de **10–50 ms** por ciclo nativo; o implementador calibra o tamanho da entrada para isso:
  - micro: `container/crc32-1mib`, `container/zip-central-dir-2000`, `container/inflate-1mib`, `container/opf-parse-large`, `container/nav-parse-large`, `container/ncx-parse-large`, `container/deobfuscate-idpf`, `container/decode-text-utf16`;
  - macro: `container/open-<hm-id>` e `container/open-read-spine-<hm-id>` para cada livro `hm/*` não malformado.
- Regra: `run()` devolve um checksum derivado do resultado (ex.: CRC, número de itens, soma de comprimentos), para o compilador não eliminar o trabalho. Uma exceção em `run()` propaga, e o `bench_runner` sai com exit 70 e a mensagem.

- [ ] **Step 1: Testes que falham**:
  - todos os ids do catálogo são únicos e em kebab-case;
  - rodar cada benchmark 2× dá o mesmo checksum, diferente de 0 (exceto `harness/noop`);
  - um `Bench` de teste que lança faz o `bench_runner` sair com 70.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar. **Step 4:** PASS. Medir uma vez o tempo nativo de cada benchmark e registrar no relatório.
- [ ] **Step 5: Commit** `feat(benchmark): suítes micro e macro da etapa container`

---

### Task 5: Modo `instructions` (Valgrind/perf) e gate

**Files:**
- Create: `benchmark/lib/src/modes/build.dart`, `benchmark/lib/src/modes/instructions.dart`; Modify: `benchmark/tool/bench.dart`
- Test: `benchmark/test/modes/instructions_test.dart`

**Interfaces:**
- Consumes: `bench_runner`, `Catalog`, `toBmf`.
- Produces:
  - `Future<File> compileRunner({required Directory checkout, required String outPath})`: `dart compile exe benchmark/bin/bench_runner.dart` dentro de `checkout`.
  - `Future<Directory> prepareCheckout(String gitRef, Directory workDir)`: `git worktree add` da ref (ex.: merge-base com `origin/main`).
  - `enum Counter { valgrind, perf }`; `Future<int> countInstructions(File exe, String benchId, int iterations, Counter c)`:
    - valgrind: `valgrind --tool=cachegrind --cache-sim=no --cachegrind-out-file=/dev/null`, contagem de `I refs` lida do stderr;
    - perf: `perf stat -x, -e instructions:u`.
    - Devolve `instruções(benchId) − instruções(harness/noop)` com as mesmas iterações.
  - `CounterUnavailable` com mensagem de correção:
    - valgrind ausente → `instale valgrind (ex.: sudo apt-get install -y valgrind)`;
    - perf bloqueado → `perf_event_paranoid=<v>; rode: sudo sysctl kernel.perf_event_paranoid=1 ou use --counter valgrind`.
  - `final class GateRow { final String benchId; final double? base; final double? head; final double? ratio; final GateStatus status; }` com `enum GateStatus { ok, improved, regressed, added, removed }`.
  - `List<GateRow> compareInstructions(Map<String,int> base, Map<String,int> head, {double threshold = 0.005})`.
  - CLI: `dart run tool/bench.dart instructions --base <ref> --head <ref> --counter valgrind|perf --out bmf.json --report report.md`. Exit 1 se algum `regressed`, 0 caso contrário. Os checksums da base e do head precisam bater por benchmark; se divergirem, exit 2 com a lista.

- [ ] **Step 1: Testes que falham**:
  - `compareInstructions`: +0,4% → `ok`; +0,6% → `regressed`; −3% → `improved`; só no head → `added` (não reprova); só na base → `removed` (não reprova);
  - parser do stderr do cachegrind (fixture real `I refs: 968,757,243`) → 968757243;
  - parser da saída CSV do `perf`;
  - `CounterUnavailable` quando o binário não existe (PATH vazio no teste);
  - integração (tag `slow`): `instructions` com `--base HEAD --head HEAD --counter valgrind` em 2 benchmarks dá todos `ok` e variação < 0,01%.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar. **Step 4:** PASS (a integração roda localmente; registrar no relatório o tempo total).
- [ ] **Step 5: Commit** `feat(benchmark): modo instructions com valgrind/perf e gate de 0,5%`

---

### Task 6: Modo `ab` (tempo intercalado + bootstrap)

**Files:**
- Create: `benchmark/lib/src/modes/stats.dart`, `benchmark/lib/src/modes/ab.dart`; Modify: `benchmark/tool/bench.dart`
- Test: `benchmark/test/modes/stats_test.dart`, `benchmark/test/modes/ab_test.dart`

**Interfaces:**
- Consumes: `compileRunner`, `prepareCheckout` (Task 5).
- Produces:
  - `double median(List<double> xs)`
  - `({double lower, double point, double upper}) bootstrapMedianRatio(List<double> base, List<double> head, {int resamples = 10000, double confidence = 0.95, int seed = 42})`: razão `mediana(head)/mediana(base)`, IC por percentis.
  - `AbVerdict decideAb(({double lower, double point, double upper}) ci, {double threshold = 0.05})`: `regressed` se `ci.lower > 1 + threshold`; `improved` se `ci.upper < 1 - threshold`; senão `inconclusive_or_ok`.
  - Execução: para cada benchmark, `rounds` rodadas intercaladas (base, head, base, head…; padrão 15). Cada amostra é o tempo de parede de `bench_runner --iterations k`, com `k` calibrado para ~200 ms, e já desconta o `noop`. A saída é BMF `wall-time-ns` com `lower`/`upper`.
  - CLI: `dart run tool/bench.dart ab --base <ref> --head <ref> --rounds 15 --out bmf.json --report report.md`. Exit 1 se algum `regressed`.

- [ ] **Step 1: Testes que falham** (amostras sintéticas com `Random(7)`):
  - amostras idênticas → IC contém 1,0 → não reprova;
  - head 10% mais lento com ruído de 2% → `regressed`;
  - head 3% mais lento com ruído de 5% → não reprova;
  - head 10% mais rápido → `improved`;
  - mesma seed → mesmo IC.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar. **Step 4:** PASS.
- [ ] **Step 5: Commit** `feat(benchmark): modo ab com rodadas intercaladas e bootstrap da razão das medianas`

---

### Task 7: Modo `local` (máquina do mantenedor) e corpus privado

**Files:**
- Create: `benchmark/lib/src/corpus/private_corpus.dart`, `benchmark/lib/src/modes/local.dart`; Modify: `benchmark/tool/bench.dart`
- Test: `benchmark/test/modes/local_test.dart`

**Interfaces:**
- Consumes: `countInstructions(..., Counter.perf)`, `writeSyntheticBook`, `CorpusFetcher`.
- Produces:
  - `String anonymousId(File f)` = os 12 primeiros hex do `sha256` do conteúdo.
  - `Future<List<File>> listPrivateCorpus()`: lê `GALLEY_PRIVATE_CORPUS`; ausente → lista vazia + aviso.
  - Medições, cada uma num processo próprio do `bench_runner` (um modo `--measure-open <path>` acrescentado ao runner):
    - `wall-time-ns` absoluto (mediana de 9);
    - `peak-rss-bytes` (`ProcessInfo.maxRss` impresso pelo runner);
    - `instructions` com `perf`.
    - Cobertura: livros sintéticos de 50 e 300 MiB, corpus público e privado.
  - Saída BMF: livros privados aparecem só como `private/<anonymousId>` e como agregados `private/aggregate` (mediana e p95 de abertura, RSS máximo).
  - CLI: `dart run tool/bench.dart local --out bmf.json --report report.md [--upload]`. Com `--upload`, chama `bencher run` com testbed `local-dev` (Task 10).

- [ ] **Step 1: Testes que falham**:
  - com `GALLEY_PRIVATE_CORPUS` apontando para um diretório temporário com 2 EPUBs nomeados `Livro Secreto.epub`, o BMF e o relatório **não contêm** `Livro Secreto` nem o caminho, e contêm `private/<12hex>`;
  - variável ausente → sem erro, aviso no relatório;
  - `anonymousId` é estável.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar. **Step 4:** PASS; rodar `local` uma vez na máquina do mantenedor sem `--upload` e anexar o relatório ao report da task.
- [ ] **Step 5: Commit** `feat(benchmark): modo local com perf nativo, memória de pico e corpus privado anonimizado`

---

### Task 8: Modo `compare` com os parsers concorrentes

**Files:**
- Create: `benchmark/lib/src/competitors/{adapter.dart, galley_adapter.dart, epubx_adapter.dart, epub_plus_adapter.dart, epub_pro_adapter.dart}`, `benchmark/lib/src/modes/compare.dart`; Modify: `benchmark/bin/bench_runner.dart` (`--adapter <nome> --measure <open|read-all|read-one> <path>`), `benchmark/tool/bench.dart`
- Test: `benchmark/test/competitors_test.dart`

**Interfaces:**
- Produces:
  - `abstract interface class ParserAdapter { String get name; Future<void> open(String path); Future<int> readAllSpine(); /* soma de bytes dos documentos do spine */ Future<int> readOne(String hrefOrPath); Future<void> close(); }`
  - Adaptadores `galley`, `epubx` (`EpubReader.readBook`), `epub_plus`, `epub_pro`, cada um usando a API idiomática do pacote para abrir de arquivo.
  - Métricas por adaptador e livro, cada medição num processo próprio: `wall-time-ns` de abrir, `wall-time-ns` de ler o spine inteiro, `peak-rss-bytes`, mais `read-one` no livro sintético de 50 MiB (capítulo do meio).
  - BMF com ids `compare/<adaptador>/<métrica>/<livro>` e relatório markdown em tabela (livro × adaptador). Não reprova (antes da 1.0).
  - Falha de um concorrente num livro (exceção) → célula `falhou` no relatório, sem abortar.

- [ ] **Step 1: Testes que falham**:
  - nos livros `hm/typography` e `hm/epub2-ncx`, `readAllSpine()` dá a mesma soma de bytes nos 4 adaptadores; se um concorrente normalizar o conteúdo, o teste documenta a diferença e compara a contagem de itens do spine;
  - um adaptador que lança gera a célula `falhou` sem abortar o modo.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar. **Step 4:** PASS; rodar `compare` localmente e anexar a tabela ao relatório.
- [ ] **Step 5: Commit** `feat(benchmark): modo compare contra epubx, epub_plus e epub_pro`

---

### Task 9: Contadores determinísticos (suíte do `galley`) e tag `heavy`

**Files:**
- Create: `test/features/container/counters_test.dart`, `test/support/counting_byte_source.dart`, `test/support/synthetic_epub.dart`, `dart_test.yaml`
- Modify: `.github/workflows/ci.yml` (job `heavy`: stable, Linux, `flutter test --tags heavy`; os outros jobs usam `--exclude-tags heavy`)

**Interfaces:**
- Consumes: `EpubBook.fromSource` (`@visibleForTesting`), `ByteSource`.
- Produces:
  - `CountingByteSource implements ByteSource` com `int get bytesRead` e `int get reads`;
  - `writeSyntheticEpubTo(File f, {required int targetBytes})` (gerador em streaming para os testes, independente do pacote `benchmark`);
  - `dart_test.yaml` com `tags: heavy:` e `timeout: 5m` para essa tag.
- Limites, calibrados pelo implementador na primeira medição e então congelados como constantes nomeadas no teste:
  - abrir `hm`-like pequeno: ≤ X bytes;
  - abrir o sintético de 300 MiB: **≤ 262.144 bytes** (fixado pelo spec);
  - `resource()` de um capítulo lê no máximo o tamanho comprimido da entrada + 30 + nome + extra + 64 bytes.

- [ ] **Step 1: Testes que falham**: os três limites acima. O de 300 MiB tem `tags: ['heavy']`, gera o arquivo num diretório temporário e o apaga em `tearDown`.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar e calibrar. **Step 4:** PASS em `flutter test` e em `flutter test --tags heavy`.
- [ ] **Step 5: Commit** `test(container): contadores determinísticos de bytes lidos e tag heavy`

---

### Task 10: Modo `size`, integração com o Bencher e documentação

**Files:**
- Create: `benchmark/size/with_galley/` e `benchmark/size/without_galley/` (apps Flutter mínimos, só Android, idênticos exceto pela dependência e por uma chamada a `EpubBook.fromBytes` num asset vazio), `benchmark/lib/src/modes/size.dart`, `benchmark/README.md`
- Modify: `benchmark/tool/bench.dart`, `docs/superpowers/specs/2026-11-24-galley-arquitetura-design.md` (§6: atualizar conforme §8 do spec do SP2), `README.md` (seção curta "Benchmarks" com link)
- Test: `benchmark/test/modes/size_test.dart`

**Interfaces:**
- Produces:
  - `int sizeDelta(File withApk, File withoutApk)`; `bool sizeWithinBudget(int delta, {int budget = 2097152})`
  - CLI `size`: `flutter build apk --release --split-per-abi --target-platform android-arm64` nos dois apps, BMF `size-bytes` em `size/galley-delta-arm64`. Exit 1 se passar do teto.
  - `bencherRun({required String testbed, required File bmf, String? branch, String? startPoint})`: monta o comando `bencher run --project galley --testbed <testbed> --adapter json --file <bmf> [--branch …] [--start-point …]`. Sem `BENCHER_API_TOKEN` → pula com aviso, sem falhar.
  - Testbeds: `github-ubuntu-valgrind`, `github-ubuntu-ab`, `github-ubuntu-nightly`, `local-dev`.
  - Baseline da regressão gradual: branch `baseline` no Bencher iniciado em `d4ef38a`, com threshold de 10% aplicado só ao noturno. O procedimento de atualização fica no README.
- `benchmark/README.md`: modos, como rodar localmente (`perf_event_paranoid`, `GALLEY_PRIVATE_CORPUS`, quando rodar `local`) e **passo a passo manual do mantenedor**: criar a conta e o projeto `galley` no Bencher, gerar o token, cadastrar o secret `BENCHER_API_TOKEN`, criar o branch `baseline` e configurar os thresholds.

- [ ] **Step 1: Testes que falham**: `sizeDelta`/`sizeWithinBudget` nos limites (2.097.152 passa; 2.097.153 reprova); `bencherRun` monta o comando exato esperado; sem token, devolve `skipped`.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar; rodar `size` localmente uma vez (Android SDK presente) e registrar o delta. **Step 4:** PASS.
- [ ] **Step 5: Commit** `feat(benchmark): modo size, integração com bencher e documentação`

---

### Task 11: Workflows de CI (PR, upload e noturno)

**Files:**
- Create: `.github/workflows/bench-pr.yml`, `.github/workflows/bench-pr-upload.yml`, `.github/workflows/bench-nightly.yml`, `.github/CODEOWNERS` (`/.github/ @EduardoSA8006`)

**Interfaces:**
- Consumes: CLI `tool/bench.dart` (Tasks 5–10).
- `bench-pr.yml` (`pull_request`, sem secrets):
  - **job `instructions`:** Flutter 3.47.5 fixo, `apt-get install valgrind`, cache do corpus (chave = hash de `corpus/manifest.json`), `instructions --base origin/main...HEAD (merge-base) --head HEAD --counter valgrind`;
  - **job `ab`:** com `--rounds` dimensionado para caber no orçamento.
  - Os dois jobs enviam `bmf.json`, `report.md` e um `pr-number.txt` como artefato, e escrevem `report.md` no `$GITHUB_STEP_SUMMARY`.
  - `timeout-minutes: 20` em cada job; meta de ~15 min de parede total.
- `bench-pr-upload.yml` (`workflow_run` de `bench-pr`, com `BENCHER_API_TOKEN`):
  - baixa os artefatos **sem fazer checkout nem executar código do PR**;
  - roda `bencher run` com `--branch` do PR, `--start-point main` e comentário no PR (`--github-actions ${{ secrets.GITHUB_TOKEN }}`);
  - valida que `pr-number.txt` é numérico antes de usar.
- `bench-nightly.yml` (`schedule: cron '0 6 * * *'` e `push` em `main`):
  - `instructions` e `ab` mais longo, com upload para o branch `main`;
  - `compare`;
  - `size`;
  - checagem de regressão gradual contra `baseline` (10%, reprova o job).
- Proteção da `main` (passo manual documentado no `benchmark/README.md`): marcar `bench-pr / instructions` e `bench-pr / ab` como checks obrigatórios.

- [ ] **Step 1:** Validar os YAMLs com `python3 -c "import yaml…"` e com `actionlint`, se disponível (`go install` ou binário; senão registrar que não foi usado).
- [ ] **Step 2:** Abrir um PR de teste na branch do SP2 (o próprio PR do subprojeto) e confirmar:
  - os dois jobs passam;
  - o tempo total fica em ~15 min ou menos;
  - o upload pula com aviso enquanto o token não existir.
- [ ] **Step 3: Commit** `ci: workflows de benchmark para PR, upload ao bencher e noturno`

---

## Notas de execução

- Branch `sp2/benchmark`. O PR do SP2 é o primeiro a exercitar `bench-pr.yml`.
- Os passos que publicam ou exigem conta ficam com o mantenedor, com aprovação explícita: executar `corpus/tool/mirror.sh`, criar o Bencher, cadastrar o secret e configurar a proteção da `main`.
- A pendência permanente de expansão (spec §9) fica no `benchmark/README.md` como checklist por subprojeto.
