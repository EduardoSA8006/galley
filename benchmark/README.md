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
| `instructions` | CI (Valgrind) e local (`--counter perf`) | instruções por benchmark curto, base × head no mesmo job | **gate do PR**: reprova com regressão > 0,5% |
| `ab` | CI | tempo de parede base × head, rodadas intercaladas, IC 95% bootstrap da razão das medianas | **gate do PR**: reprova se o IC fica inteiro acima de +5% |
| `local` | máquina do mantenedor | tempo absoluto, RSS de pico, `perf` nativo, livros de 50 e 300 MiB, corpus público e privado | registro manual (`local-dev`); rode depois de mudanças de desempenho e antes de releases |
| `compare` | CI noturno e local | Galley × `epubx` × `epub_plus` × `epub_pro` | relatório; não bloqueia antes da 1.0 |
| `size` | CI noturno e local | bytes que o Galley acrescenta ao APK release arm64 | teto de **2 MiB** (2.097.152 bytes); acima disso sai com 1 |

Exemplos:

```
dart run tool/bench.dart instructions --base origin/main --head HEAD --out instr.json --report instr.md
dart run tool/bench.dart ab --base origin/main --head HEAD --out ab.json
dart run tool/bench.dart local --out local.json --report local.md [--upload]
dart run tool/bench.dart compare --out compare.json
dart run tool/bench.dart size --out size.json
```

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
  cada release. Com `--upload` (e `BENCHER_API_TOKEN` definido) o resultado vai
  ao Bencher no testbed `local-dev`; sem o token o upload é pulado com aviso.
- **Cache do corpus público:** `.corpus-cache/` (na raiz do repositório, fora
  do git) guarda os livros baixados, verificados por `sha256`. Enquanto os
  arquivos não forem baixados novamente do espelho da release `corpus-v1`
  (já publicada), esse cache guarda a **única cópia local dos bytes exatos**.
  Não o apague sem necessidade.

## Bencher

O Bencher guarda o histórico, os gráficos e a regressão gradual, e comenta nos
PRs. **Os gates de PR funcionam sem ele**: quem aprova ou reprova é o próprio
harness (base e head medidos no mesmo job, com o mesmo toolchain).

`bencherRun` (`lib/src/bencher.dart`) monta e executa:

```
bencher run --project galley --testbed <testbed> --adapter json --file <bmf> [--branch <b>] [--start-point <p>]
```

O token é lido de `BENCHER_API_TOKEN` pela própria CLI (não entra na linha de
comando). Sem o token, o envio é pulado com aviso e não falha.

Testbeds: `github-ubuntu-valgrind` (instruções no PR), `github-ubuntu-ab`
(A/B no PR), `github-ubuntu-nightly` (noturno: compare, size, instruções, A/B
longo) e `local-dev` (máquina do mantenedor).

### Passo a passo manual do mantenedor (uma vez)

Nada disto é feito pelo código; exige a sua conta.

1. Criar a conta em <https://bencher.dev> e, nela, o projeto **`galley`**
   (slug `galley`, público ou privado, a seu critério).
2. Gerar um token de API (Console > Tokens) e cadastrá-lo como secret do
   repositório no GitHub com o nome **`BENCHER_API_TOKEN`**
   (Settings > Secrets and variables > Actions). Para rodar `local --upload`,
   exporte a mesma variável no seu shell.
3. Criar os testbeds (o primeiro `bencher run` também os cria sozinho):
   `github-ubuntu-valgrind`, `github-ubuntu-ab`, `github-ubuntu-nightly` e
   `local-dev`.
4. Criar o branch **`baseline`** do Bencher começando em **`d4ef38a`** (o
   commit do merge do SP1, marco inicial da regressão gradual). Meça esse
   commit e envie-o já com o branch:
   ```
   git checkout d4ef38a   # em um worktree; use o harness do checkout atual
   dart run tool/bench.dart instructions --base d4ef38a --head d4ef38a --out baseline.json
   BENCHER_API_TOKEN=... bencher run --project galley --testbed github-ubuntu-nightly \
     --branch baseline --adapter json --file baseline.json
   ```
   (Se o commit não tiver o harness, rode o `tool/bench.dart` da `main` com
   `--base`/`--head` apontando para ele.)
5. Configurar os **thresholds**:
   - **Regressão gradual de 10%, só no noturno:** no branch `baseline` e
     **somente** no testbed `github-ubuntu-nightly`, um threshold percentual
     com limite superior de 10% (`0.10`) por medida usada
     (`instructions`, `wall-time-ns`, `peak-rss-bytes`, `size-bytes`), p.ex.:
     ```
     bencher threshold create --project galley --branch baseline \
       --testbed github-ubuntu-nightly --measure instructions \
       --test percentage --upper-boundary 0.10
     ```
     Nenhum threshold desse tipo nos testbeds de PR: o limite de 10% nunca
     reprova PR.
   - Os limites de PR (0,5% em instruções; 5% com significância no A/B) são
     decididos pelo harness, não pelo Bencher.
6. Marcar como **checks obrigatórios** da `main` (Settings > Branches ou
   rulesets): **`bench-pr / instructions`** e **`bench-pr / ab`**.

### Atualizar o baseline (a cada release ou ao aceitar uma regressão)

O limite de 10% é contra o baseline fixo. Ao lançar uma release, ou ao aceitar
de propósito uma regressão, mova o marco: meça o commit novo e envie-o ao
branch `baseline` (passo 4, com o hash novo no lugar de `d4ef38a`). Registre o
novo hash e o motivo no PR da release.

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
