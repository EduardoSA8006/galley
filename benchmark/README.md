# Benchmarks do Galley

Pacote Dart separado (`publish_to: none`) que mede o Galley e o compara com
outros parsers de EPUB. Fica fora do pacote publicado (`.pubignore`) e nunca
entra nas dependências do `galley`, que continuam sendo só `xml` e `meta`.

```
dart run tool/bench.dart <modo> [opções]     # dentro de benchmark/
```

Os jobs de benchmark do CI usam Flutter/Dart fixos em **3.47.5 (Dart 3.13.4)**.
Todos os modos escrevem o Bencher Metric Format (BMF, JSON) com `--out` e,
quando fazem sentido, um relatório em Markdown com `--report`.

## Modos e quando rodar cada um

| Modo | Onde | O que mede | Limite / uso |
|---|---|---|---|
| `instructions` | CI (Valgrind) e local (`--counter perf`) | instruções por benchmark curto, base × head no mesmo job | **gate do PR**: reprova com regressão > 0,5% (`--threshold`); o noturno usa 0.10 contra a tag `bench-baseline` |
| `ab` | CI | tempo de parede base × head, rodadas intercaladas, IC 95% bootstrap da razão das medianas | **gate do PR**: reprova se o IC fica inteiro acima de +5% |
| `local` | máquina do mantenedor | tempo absoluto, RSS de pico, `perf` nativo, livros de 50 e 300 MiB, corpus público e privado | registro manual (`local-dev`); rode depois de mudanças de desempenho e antes de releases |
| `compare` | CI noturno e local | Galley × `epubx` × `epub_plus` × `epub_pro` | relatório; não bloqueia antes da 1.0 |
| `size` | CI noturno e local | bytes que o Galley acrescenta ao APK release arm64 | teto de **2 MiB** (2.097.152 bytes); acima disso sai com 1 |
| `wide` | CI noturno e local | robustez: abre e lê todos os recursos de 300 livros do Project Gutenberg (`corpus/pg-wide.json`) e conta por classe | sai com 1 **só** se houver `crashed` (exceção que não é `GalleyException`: bug do Galley) |

Exemplos:

```
dart run tool/bench.dart instructions --base origin/main --head HEAD --out instr.json --report instr.md
dart run tool/bench.dart ab --base origin/main --head HEAD --out ab.json
dart run tool/bench.dart local --out local.json --report local.md [--upload]
dart run tool/bench.dart compare --out compare.json
dart run tool/bench.dart size --out size.json
dart run tool/bench.dart wide --out wide.json --report wide.md
dart run tool/bench.dart wide-refresh --count 300 --seed 2026   # só manual
```

### O modo `wide`

Baixa (uma vez; cache em `.corpus-cache/pg-wide/`, pausa de 2 s entre
requisições ao espelho oficial) e abre os 300 livros de `corpus/pg-wide.json`,
lendo todos os recursos do manifest. Cada livro cai em uma classe: `ok`,
`diagnostics-error`, `failed` (`GalleyException`), `crashed` (qualquer outra
exceção, ou seja, bug), `drift` (o PG regerou o arquivo; `sha256` mudou) ou
`unavailable` (404, rede, prazo). O BMF traz `wide/<classe>` com `count`, e o
resumo lista os números dos ebooks de cada classe que importa (para `crashed`,
com o início da stack). Só `crashed` reprova. Como e por que os 300 livros
foram escolhidos: `corpus/README.md`. Um `Retry-After` longo (acima de 2 min)
faz o `wide` parar de pedir ao espelho: os livros que ainda não estão no cache
viram `unavailable`.

### O modo `size`

Compila (`flutter build apk --release --split-per-abi --target-platform
android-arm64`) os dois apps de `benchmark/size/`: `with_galley` e
`without_galley`. São apps Android mínimos e idênticos, exceto pela dependência
`galley` e por uma linha: `EpubBook.fromBytes` sobre um asset vazio (que
mantém o código do Galley fora do tree-shaking). O resultado é a diferença de
bytes entre os dois APKs, gravada como `size-bytes` em
`size/galley-delta-arm64`. Exige o Android SDK. Cada app tem a sua análise
(`cd benchmark/size/with_galley && flutter analyze`), e os dois ficam fora do
`flutter analyze` da raiz e do `dart analyze` de `benchmark/`.

## Configuração local

- **Contador de instruções com `perf`:** o processo precisa poder usar
  `instructions:u`. Com `perf_event_paranoid=2` (padrão de várias distros)
  isso já funciona para o espaço do usuário. Se aparecer
  "Instruções não medidas", ajuste:
  `sudo sysctl kernel.perf_event_paranoid=1` (temporário) ou grave
  `kernel.perf_event_paranoid = 1` em `/etc/sysctl.d/`. Valgrind
  (`--counter valgrind`) é o contador do CI; `perf` é o local.
- **Corpus privado:** aponte `GALLEY_PRIVATE_CORPUS` para um diretório com
  `.epub` (busca recursiva). Os livros nunca saem da máquina: o relatório e o
  BMF só levam ids anônimos (`sha256` do conteúdo truncado em 12 hex) e
  agregados (`private/aggregate`: mediana e p95). Sem a variável, o modo
  `local` segue sem o corpus privado e avisa.
- **Quando rodar `local`:** após mudanças que mexam em desempenho e antes de
  cada release. Com `--upload` (e `BENCHER_API_KEY` definido) o resultado vai
  ao Bencher no testbed `local-dev`; sem a chave o upload é pulado com aviso.
- **Cache do corpus público:** `.corpus-cache/` (na raiz do repositório, fora
  do git) guarda os livros baixados, verificados por `sha256`. Enquanto os
  arquivos não forem baixados novamente do espelho da release `corpus-v1`
  (já publicada), esse cache guarda a **única cópia local dos bytes exatos**.
  Não o apague sem necessidade.

## CI (`.github/workflows/`)

- **`bench-pr.yml`** (`pull_request`, sem secrets): o gate `instructions`
  (Valgrind) roda em 4 fatias paralelas e o `ab` (15 rodadas) em 2, com
  `--shard i/n` (os ids do catálogo, ordenados, repartidos em rodízio). A
  base é o `merge-base` entre a base do PR e o head. Os jobs finais
  **`instructions`** e **`ab`** juntam as fatias (BMF em artefato e
  relatório no resumo do job) e reprovam se alguma fatia reprovou:
  são eles os checks obrigatórios. O catálogo usa só livros escritos à mão e
  sintéticos: não há rede nos gates.
- **`bench-pr-upload.yml`** (`workflow_run` do `bench-pr`): baixa os
  artefatos, sem checkout nem execução de código do PR, identifica o PR pela
  API do GitHub (PR aberto cujo head é o commit medido; nada vem do
  artefato além do BMF) e envia ao Bencher (`--branch pr-<número>`,
  `--start-point main`, comentário no PR). Sem `BENCHER_API_KEY`, pula com aviso. O GitHub
  só dispara `workflow_run` a partir da cópia do arquivo na branch padrão: o
  envio começa a valer depois do merge.
- **`bench-nightly.yml`** (diário às 06:00 UTC, a cada push na `main` e
  manual): `instructions` (com a regressão gradual contra `bench-baseline`,
  10%, quando a tag existe; sem ela, mede só o head e avisa), `ab` longo (31
  rodadas, só o head), `compare` (só relatório; nunca reprova o noturno),
  `size`, `wide` (job independente, prazo de 150 min por causa da primeira
  execução sem cache) e o envio de tudo ao Bencher (`--branch main`, testbed
  `github-ubuntu-nightly`) em jobs sem checkout.

Para medir uma fatia localmente:
`dart run tool/bench.dart instructions --base origin/main --head HEAD --shard 2/4`.

## Bencher

O Bencher guarda o histórico e os gráficos, e comenta nos PRs. **Os gates de PR funcionam sem ele**: quem aprova ou reprova é o próprio
harness (base e head medidos no mesmo job, com o mesmo toolchain).

`bencherRun` (`lib/src/bencher.dart`) monta e executa:

```
bencher run --project galley --testbed <testbed> --adapter json --file <bmf> [--branch <b>] [--start-point <p>]
```

A chave de API é lida de `BENCHER_API_KEY` pela própria CLI (não entra na
linha de comando). Sem a chave, o envio é pulado com aviso e não falha. (Os
antigos tokens, `BENCHER_API_TOKEN`/`--token`, estão obsoletos no Bencher e
não podem mais ser criados.)

Testbeds: `github-ubuntu-valgrind` (instruções no PR), `github-ubuntu-ab`
(A/B no PR), `github-ubuntu-nightly` (noturno: compare, size, instruções, A/B
longo) e `local-dev` (máquina do mantenedor).

### Passo a passo manual do mantenedor (uma vez)

Nada disto é feito pelo código; exige a sua conta.

1. Criar a conta em <https://bencher.dev> e, nela, o projeto **`galley`**
   (slug `galley`, público ou privado, a seu critério).
2. Gerar uma chave de API (API key; a de projeto, `bencher_run_*`, basta,
   pois o projeto já existe) e cadastrá-la como secret do
   repositório no GitHub com o nome **`BENCHER_API_KEY`**
   (Settings > Secrets and variables > Actions). Para rodar `local --upload`,
   exporte a mesma variável no seu shell.
3. Criar os testbeds (o primeiro `bencher run` também os cria sozinho):
   `github-ubuntu-valgrind`, `github-ubuntu-ab`, `github-ubuntu-nightly` e
   `local-dev`.
4. Marcar como **checks obrigatórios** da `main` (Settings > Branches ou
   rulesets): **`bench-pr / instructions`** e **`bench-pr / ab`**.

O Bencher é **só histórico**: o noturno envia para `--branch main`, e os PRs
para `--branch pr-<número> --start-point main`. Não há thresholds a configurar nele:
todos os limites são verificados pelo próprio harness.

### Regressão gradual: a tag `bench-baseline`

O acúmulo de regressão desde um marco fixo (10%) é verificado pelo harness,
**só no job noturno**, nunca no PR:

```
dart run tool/bench.dart instructions --base bench-baseline --head HEAD --threshold 0.10
```

Base e head são medidos no mesmo job, com o mesmo toolchain (determinístico),
sem depender do histórico do Bencher. O marco é a **tag git `bench-baseline`**.
Como `d4ef38a` (merge do SP1) ainda não tem `benchmark/`, o marco inicial é o
**commit de merge do SP2 na `main`**; o mantenedor cria a tag logo após o
merge:

```
git tag -f bench-baseline <sha-do-merge-do-SP2> && git push -f origin bench-baseline
```

#### Atualizar o baseline (a cada release ou ao aceitar uma regressão)

Ao lançar uma release, ou ao aceitar de propósito uma regressão, mova a tag
com o mesmo comando, usando o sha novo. Registre o sha e o motivo no PR da
release. O job noturno precisa de `fetch-depth: 0` (ou ao menos da tag) para
resolver `bench-baseline`.

## Expansão permanente

Cada subprojeto acrescenta ao benchmark as métricas e comparações das etapas
que criar. Ao concluir um subprojeto, esta lista deve ser cumprida:

- [ ] **SP3, documento:** parsing de XHTML.
- [ ] **SP4, estilo:** cascata e seletores.
- [ ] **SP5, layout:** paginação, repaginação ao mudar a fonte, medição
      fatiada.
- [ ] **SP6, render e API:** FPS/jank, memória real em dispositivo,
      compatibilidade visual contra Chromium e comparação com os leitores que
      renderizam.
- [ ] **SP7, recursos de leitura:** busca, CFI.

## Futuro: máquina dedicada

Decisão registrada: o runner dedicado **não** faz parte do SP2; é uma adição
futura. Pode ser uma VM no Proxmox (núcleos fixos, `cpu: host`, memória fixa,
isolada da produção) ou um servidor físico de entrada. Entraria como testbed
novo no Bencher e assumiria o modo `local` de forma agendada, com o corpus
privado. Até lá, o modo `local` roda na máquina do mantenedor. O serviço de
dispositivos físicos é do SP6.
