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
| `compare` | CI noturno e local | Galley × `epubx` × `epub_plus` × `epub_pro`; o parse de documento do Galley × DOM do `package:xml` (par à parte, `--doc-adapter`); e a leitura de CSS do Galley × `package:csslib` (par à parte, `--css-adapter`) | relatório; não bloqueia antes da 1.0 |
| `size` | CI noturno e local | bytes que o Galley acrescenta ao APK release arm64 | teto de **2 MiB** (2.097.152 bytes); acima disso sai com 1 |
| `wide` | CI noturno e local | robustez: abre e lê todos os recursos de 300 livros do Project Gutenberg (`corpus/pg-wide.json`), parseia todos os documentos do spine e conta por classe | sai com 1 **só** se houver `crashed` (exceção que não é `GalleyException`: bug do Galley) |
| `docdiff` | CI noturno e local | diferencial: em cada documento do spine do corpus público, a árvore do Galley × o DOM do `package:xml` | sai com 1 se houver **divergência** ou **erro interno** (bug do Galley); 70 se nenhum documento foi comparado |

Exemplos:

```
dart run tool/bench.dart instructions --base origin/main --head HEAD --out instr.json --report instr.md
dart run tool/bench.dart ab --base origin/main --head HEAD --out ab.json
dart run tool/bench.dart local --out local.json --report local.md [--upload]
dart run tool/bench.dart compare --out compare.json
dart run tool/bench.dart size --out size.json
dart run tool/bench.dart wide --out wide.json --report wide.md
dart run tool/bench.dart docdiff --out docdiff.json --report docdiff.md
dart run tool/bench.dart wide-refresh --count 300 --seed 2026   # só manual
```

### O modo `instructions`: flags da VM

O harness roda o `bench_runner` de base e head com as mesmas flags em
`DART_VM_OPTIONS` (`deterministicVmOptions`, em
`lib/src/modes/instructions.dart`, com o motivo de cada uma). As flags vêm do
harness do checkout que roda o modo, não da base: mudar as flags muda as duas
versões medidas no mesmo job. Em resumo:

- GC sem marcação nem varredura concorrentes, uma tarefa por fase,
  crescimento do heap velho só por espaço (`--old_gen_growth_time_ratio=100`)
  e semente fixa: execuções repetidas variam ~0,001%.
- Folga fixa de ~200 MB no heap velho antes do primeiro mark-sweep
  (`--old_gen_growth_space_ratio=99`, `--old_gen_growth_rate=400`). O custo
  de um mark-sweep cresce com os objetos do próprio programa AOT no heap
  velho; com o heap no mínimo, crescer o executável com código que o
  benchmark nem executa mudava benchmarks de outro subsistema (no SP3,
  +5% em `container/deobfuscate-idpf`, ~80% de GC, sem mudança no
  container). Com a folga, nenhum benchmark do catálogo faz mark-sweep nas
  execuções medidas.

O que a contagem inclui: o trabalho do código, a alocação (e a cópia ou a
inicialização do que se aloca) e os scavenges da geração nova. O que não
inclui: o mark-sweep do heap velho, a não ser num benchmark que aloque mais
de ~200 MB no heap velho em 4 iterações. O custo real do GC em tempo de
parede fica com o gate `ab`, que usa as flags padrão da VM. Uma regressão de
alocação continua reprovando: uma cópia extra de 256 KiB por chamada em
`deobfuscateIdpf` dá +88,8%; só alocar um buffer extra de 256 KiB, +5,5%.

Um efeito do tamanho do programa que as flags não removem: o AOT
desvirtualiza menos quando o programa tem mais implementações das mesmas
classes. Com o código de documento no executável, os benchmarks que
parseiam XML no container (`opf`/`nav`/`ncx-parse-large`,
`open-*-epub2-ncx`) ficaram +0,2–0,3% mais caros. Esse custo é real: um app
que usa o Galley também tem o código de documento.

Mudar estas flags muda os números absolutos de todo o catálogo. O gate do
PR e a regressão gradual do noturno não sentem (base e head, ou
`bench-baseline` e head, são medidos com as mesmas flags no mesmo job); no
Bencher, a série de cada benchmark dá um degrau no commit da mudança, que
não é regressão.

### O modo `ab`: layout do código AOT

O `ab` compila base e head com `dart compile exe` padrão e roda cada amostra
com as flags padrão da VM. Um efeito que ele sente e o `instructions` não:
o tempo de um laço quente pode mudar com o **endereço** do código no
executável, sem nenhuma instrução a mais. Isso depende da CPU do runner, que
varia entre jobs (o GitHub sorteia AMD EPYC 7763/Zen 3, 9V74/Zen 4 e
9V45/Zen 5; a linha "CPU do runner" no resumo de cada fatia diz qual foi).

Caso do SP3 (PR #6): o `crc32` recebia `List<int>` e fazia duas chamadas
indiretas por byte (`length` e `[]` pela tabela de despacho). Experimento no
CI com executáveis da `main` que só diferem por código morto noutra função
(mesmas instruções executadas): `crc32-1mib` +5–8% e `inflate-1mib` +4–6% em
Zen 3 e Zen 5, nada em Zen 4. O gate reprovava sem mudança no container.
Com o laço sobre `Uint8List` (sem chamadas), os mesmos deslocamentos ficam em
±1% nas três CPUs, e o laço é ~2× mais rápido.

Não adotado: `--align_all_loops` (flag do `gen_snapshot`, via
`--extra-gen-snapshot-options`). Alinha o cabeçalho dos laços a 32 bytes, mas
os destinos das chamadas e o resto do layout continuam mudando: em Zen 5 o
deslocamento ainda dava −8%, e a flag deixou o `crc32` 8% mais lento. Também
mediria um programa que nenhum app compila.

Se o `ab` reprovar um benchmark cujo código não mudou e cujas instruções
(gate `instructions`) ficaram iguais, suspeite de layout: veja a CPU do
runner, procure chamadas indiretas ou despacho dinâmico no laço quente e
prefira corrigir o laço (tipo exato, sem chamada por elemento). O limite de
5% e o método não mudam; uma regressão real de tempo continua reprovando.

### O modo `wide`

Baixa (uma vez; cache em `.corpus-cache/pg-wide/`, pausa de 2 s entre
requisições ao espelho oficial) e abre os 300 livros de `corpus/pg-wide.json`,
lendo cada recurso do manifest uma vez e parseando com `parseDocumentBytes`
os bytes já lidos de cada documento do spine. Cada livro cai em uma classe:
`ok`, `diagnostics-error`, `failed` (`GalleyException`), `crashed` (qualquer
outra exceção, ou um documento com `internalError`, a exceção inesperada que
o leitor de documentos capturou: bug), `drift` (o PG regerou o arquivo;
`sha256` mudou) ou `unavailable` (404, rede, prazo). O BMF traz
`wide/<classe>` com `count`, e o resumo lista os números dos ebooks de cada
classe que importa (para `crashed`, com o início da stack e, num
`internalError`, o tipo da exceção e o caminho do documento). Os documentos
que caíram no modo tolerante não reprovam: são contados (`wide/documents` e
`wide/documents-tolerant` no BMF; no resumo, os livros que os têm). Só
`crashed` reprova. Como e por que os 300 livros foram escolhidos:
`corpus/README.md`. Um `Retry-After` longo (acima de 2 min) faz o `wide`
parar de pedir ao espelho: os livros que ainda não estão no cache viram
`unavailable`.

### O modo `docdiff`

Para cada livro de `corpus/manifest.json` (cache em `.corpus-cache/`, o
mesmo do `compare`), lê cada documento do spine (cada caminho uma vez) com
`parseDocumentBytes` e com `XmlDocument.parse` do `package:xml` (entidades
HTML5 do próprio `package:xml`, não a variante linear do Galley) e compara as
duas sequências de eventos: entrar no elemento (URI do namespace, nome local
e atributos ordenados por URI e nome local, sem `xmlns*`), texto (fundido,
CDATA como texto, comentários e PIs ignorados) e sair do elemento.

O lado do DOM reproduz as diferenças intencionais do Galley antes de
comparar (CRLF → LF, TAB/LF/CR → espaço nos atributos, caracteres proibidos
→ U+FFFD, prefixos `xml:`/`epub:`/`xlink:` sem declaração resolvidos e os
demais no namespace reservado, atributo repetido: vale o primeiro); a lista
está no código (`lib/src/modes/docdiff.dart`). A decodificação dos bytes
(`decodeText`) é a mesma nos dois lados e não é verificada por este
diferencial.

Cada documento cai em uma classe:

- **bateu** ou **divergência** (bug do Galley; reprova);
- **erro interno** (`internalError`: o leitor capturou uma exceção
  inesperada; bug do Galley; reprova);
- **tolerante**: o Galley leu pelo modo tolerante; fica fora da comparação;
- **XHTML tolerante que o DOM leu**: `application/xhtml+xml` que o Galley
  mandou ao modo tolerante, mas o DOM aceitou; fora da comparação e não
  reprova, mas aparece no relatório para revelar uma regressão que mande
  XHTML válido ao modo tolerante;
- **DOM não leu**: o Galley leu pelo caminho estrito e o DOM lançou; fora da
  comparação.

O relatório traz as contagens e, até 10 de cada, as divergências (caminho
`<livro>/<documento>` e primeiro evento divergente), os erros internos, o
XHTML tolerante que o DOM leu e os que o DOM não leu. O BMF traz
`docdiff/mismatch`, `docdiff/internal-error` e
`docdiff/tolerant-dom-parsed` (`count`). Sai com 1 se houver divergência ou
erro interno e com 70 se nenhum documento foi comparado.

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
  ao Bencher no testbed `local-dev`, com o commit medido (`--hash`, o sha do
  `HEAD`) e o branch atual (`--branch`, normalizado; checkout destacado vira
  `main`); sem a chave o upload é pulado com aviso. Com mudanças não
  commitadas (inclusive arquivos novos), o envio é **recusado** com aviso,
  porque o resultado não corresponderia ao commit; o BMF e o relatório saem
  assim mesmo. Commite antes, ou use `--allow-dirty` se souber o que está
  enviando.
- **Cache do corpus público:** `.corpus-cache/` (na raiz do repositório, fora
  do git) guarda os livros baixados, verificados por `sha256`. Enquanto os
  arquivos não forem baixados novamente do espelho da release `corpus-v1`
  (já publicada), esse cache guarda a **única cópia local dos bytes exatos**.
  Não o apague sem necessidade.

## CI (`.github/workflows/`)

- **`bench-pr.yml`** (`pull_request`, sem secrets): o gate `instructions`
  (Valgrind) roda em 4 fatias paralelas e o `ab` (15 rodadas) em 2, com
  `--shard i/n` (os ids do catálogo, ordenados, repartidos em rodízio). A
  base é o `merge-base` entre a base do PR e o head. O índice e o total de
  cada fatia vêm de `strategy.job-index`/`strategy.job-total` (a lista da
  `matrix` só define quantas são). Os jobs finais **`instructions`** e
  **`ab`** juntam as fatias com `.github/scripts/bench-aggregate.sh` (BMF em
  artefato e relatório no resumo do job), conferem que **todas** as fatias
  produziram BMF e concordam no total (senão reprovam: parte do catálogo não
  foi medida) e reprovam se alguma fatia reprovou: são eles os checks
  obrigatórios. Regressão (código 1) ou checksum divergente (2) passam com
  aviso se o PR tiver o rótulo `perf-regression-accepted` (ver
  [Aceitar uma regressão intencional](#aceitar-uma-regressão-intencional));
  falha de medição (69, 70) reprova sempre. O catálogo usa só livros escritos
  à mão e sintéticos: não há rede nos gates. O "antes × depois" do PR está no
  resumo desses jobs (relatório do harness, base × head no mesmo job).
- **`bench-pr-upload.yml`** (`workflow_run` do `bench-pr`): baixa os
  artefatos, sem checkout nem execução de código do PR, identifica o PR pela
  API do GitHub (PR aberto cujo head é o commit medido; nada vem do
  artefato além do BMF), valida o BMF com `jq` antes de a chave entrar em
  qualquer passo (ids no formato do catálogo, medidas conhecidas, números
  finitos, no máximo 2000 benchmarks e 512 KiB; senão pula com aviso) e
  envia ao Bencher (`--branch pr-<número>`, `--start-point main`, nos
  testbeds `github-ubuntu-valgrind` e `github-ubuntu-ab`, comentário no PR).
  Sem `BENCHER_API_KEY`, pula com aviso. O GitHub
  só dispara `workflow_run` a partir da cópia do arquivo na branch padrão: o
  envio começa a valer depois do merge.
- **`bench-nightly.yml`** (diário às 06:00 UTC, a cada push na `main` e
  manual): `instructions` (com a regressão gradual contra `bench-baseline`,
  10%, quando a tag existe; sem ela, mede só o head e avisa), `ab` longo (31
  rodadas, só o head), `compare` (só relatório; nunca reprova o noturno),
  `size`, `docdiff` (diferencial de documentos; **reprova** o noturno com
  divergência ou erro interno), `wide` (job independente, prazo de 150 min
  por causa da primeira execução sem cache; roda **só na agenda e no
  disparo manual**, nunca a cada push) e o envio de tudo ao Bencher
  (`--branch main`) em jobs sem checkout: instruções em
  `github-ubuntu-valgrind` e A/B em `github-ubuntu-ab` (os mesmos testbeds
  do PR, para o `--start-point main` do PR trazer este histórico),
  `compare`, `size`, `docdiff` e `wide` em `github-ubuntu-nightly`. Os
  caches de corpus do `compare`, do `docdiff` (mesmo prefixo de chave do
  `compare`, com sufixo próprio no save) e do `wide` usam
  `actions/cache/restore` e `actions/cache/save` com `if: always()`: são
  salvos mesmo se o job falhar (um `crashed`, uma divergência ou o prazo
  estourado), sempre que chegaram livros novos.

Para medir uma fatia localmente:
`dart run tool/bench.dart instructions --base origin/main --head HEAD --shard 2/4`.

## Bencher

O Bencher guarda o histórico e os gráficos, e comenta nos PRs. **Os gates de PR funcionam sem ele**: quem aprova ou reprova é o próprio
harness (base e head medidos no mesmo job, com o mesmo toolchain).

`bencherRun` (`lib/src/bencher.dart`) monta e executa:

```
bencher run --project galley --testbed <testbed> --adapter json --file <bmf> [--branch <b>] [--start-point <p>] [--hash <sha>]
```

A chave de API é lida de `BENCHER_API_KEY` pela própria CLI (não entra na
linha de comando). Sem a chave, o envio é pulado com aviso e não falha. (Os
antigos tokens de API do Bencher, passados com `--token`, estão obsoletos e
não podem mais ser criados: use sempre `BENCHER_API_KEY`.)

Testbeds (o histórico do Bencher é indexado por branch × testbed, por isso
PR e noturno usam o mesmo testbed por tipo de medida):

| Testbed | Medidas | Quem envia |
|---|---|---|
| `github-ubuntu-valgrind` | instruções | PR (`pr-<número>`) e noturno (`main`) |
| `github-ubuntu-ab` | A/B de tempo de parede | PR (`pr-<número>`) e noturno (`main`) |
| `github-ubuntu-nightly` | `compare`, `size`, `wide`, `docdiff` | só o noturno (`main`) |
| `local-dev` | modo `local` | máquina do mantenedor (branch atual) |

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
4. Criar o rótulo **`perf-regression-accepted`** no repositório (Issues >
   Labels), com uma descrição como "Regressão de desempenho ou checksum de
   benchmark aceitos de propósito".
5. Marcar como **checks obrigatórios** da `main` (Settings > Branches ou
   rulesets): **`bench-pr / instructions`** e **`bench-pr / ab`**. Antes,
   abra um PR inócuo (ex.: um comentário em `lib/`) para exercitar no CI a
   comparação base × head pela primeira vez e conferir o tempo de parede.

O Bencher é **só histórico**: o noturno envia para `--branch main`, e os PRs
para `--branch pr-<número> --start-point main`. Não há thresholds a configurar nele:
todos os limites são verificados pelo próprio harness.

### Aceitar uma regressão intencional

Os gates são determinísticos: rodar de novo não muda o resultado. Quando a
regressão ou a mudança de checksum é **de propósito**, há dois caminhos:

- **A carga do benchmark mudou** (o benchmark passou a fazer outro trabalho:
  livro de entrada diferente, outra API medida, correção de um benchmark
  que media errado): dê a ele um **id novo** (ex.:
  `container/deobfuscate-idpf-v2`) e remova o antigo. Ele aparece como
  `added`/`removed`, não como regressão, e o histórico do Bencher não mistura
  duas séries diferentes sob o mesmo nome. Esta é a regra; o rótulo abaixo
  não a substitui.
- **O código do Galley ficou mais caro de propósito** (ex.: a abertura passa
  a fazer mais trabalho, como no SP3), ou o checksum mudou porque o
  resultado mudou de propósito (ex.: um diagnóstico novo entra em
  `book.diagnostics`): quem tem **acesso de escrita** aplica ao PR o rótulo
  **`perf-regression-accepted`**. Aplicar ou tirar o rótulo roda o
  `bench-pr` de novo; os agregadores `instructions` e `ab` leem o rótulo do
  evento `pull_request` (metadado, nunca do código do PR), medem e relatam
  tudo, e aprovam com um aviso e uma nota no resumo listando as regressões
  e os checksums aceitos. Falhas de medição (69, 70) continuam reprovando.
  Justifique no PR o que foi aceito e por quê.

Uma regressão aceita no PR também conta na regressão gradual do noturno
(10% desde `bench-baseline`): se ela for grande, mova a tag depois do merge
(ver abaixo).

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

- [x] **SP3, documento:** parsing de XHTML. Catálogo (cada ciclo de 10–50 ms
      nativos): `document/build-large-1mib` (XHTML sintético textual de 1 MiB, um
      capítulo de romance, com tabelas, *ruby*, MathML, `style=` e
      `epub:type`), `document/build-dense-256kib` (denso em marcação, pouco
      texto: pega regressão por elemento/atributo),
      `document/query-id-class`, `document/build-tolerant` (documento
      malformado), `document/transfer-large` (`Isolate.run` que faz o
      parse de 1 MiB e devolve a árvore: mede parse + spawn + transferência;
      a diferença para `document/build-large-1mib` estima o custo do envio) e `document/parse-spine-hm-<livro>` (todos os
      documentos do spine de cada livro `hm/*` não malformado). Comparação
      informativa, sem gate, no `compare`: `parseDocumentBytes` ×
      `XmlDocument.parse` (entidades HTML5) em cada livro `hm/*`, no XHTML
      textual (`synthetic/xhtml-1mib`) e no denso (`synthetic/dense-256kib`), com `wall-time-ns` e
      `peak-rss-bytes` em `compare/galley-document/parse/<doc>` e
      `compare/xml-dom/parse/<doc>`. Teto de memória no pacote `galley`:
      `test/features/document/memory_counter_test.dart`
      (`retainedBytes` ÷ bytes do XHTML ≤ K). Diferencial noturno, que
      reprova: `docdiff` (árvore × DOM do `package:xml` no corpus
      público); o `wide` parseia todos os documentos do spine.
- [x] **SP4, estilo:** cascata e seletores. Catálogo: `style/parse-sheet-256kib`
      (`buildStyleSheet` sobre uma folha sintética de 256 KiB),
      `style/full-large-1mib` (`matchDocument` + `restyle` do XHTML sintético
      de 1 MiB com a folha de editora de ~40 KiB, contexto aquecido no `setUp`,
      como num capítulo N), `style/restyle-large-1mib` (só o `restyle` sobre o
      casamento guardado: Literata/1,2/tema escuro e `none`),
      `style/match-descendant-heavy` (2.000 regras descendentes no mesmo XHTML)
      e `style/spine-hm-<livro>` (`styleDocument` em todo o spine de cada livro
      `hm/*` bem formado). Ciclos de ~30–40 ms nativos, salvo `full-large-1mib`
      (~85 ms) e `match-descendant-heavy` (~75 ms), cujo trabalho prescrito
      (1 MiB, 2.000 regras) não cabe em 50 ms. **Meta da spec como registro
      permanente:** o `restyle` custa no máximo 1/5 do estilo completo do mesmo
      capítulo; `test/suites_style_test.dart` (tag `slow`, `-t slow`) conta as
      instruções das duas suítes (cada uma faz duas passadas de preferências,
      para a conta ser simétrica) e exige razão ≥ 5. Comparação informativa,
      sem gate, no `compare`: `buildStyleSheet` × `parse` do `package:csslib`
      (versão fixada em `pubspec.yaml`, só aqui, nunca no pacote `galley`) em
      `hm/publisher-css`, nos livros do corpus público e em
      `synthetic/css-256kib`, com `wall-time-ns` e `peak-rss-bytes` em
      `compare/galley-css/parse/<livro>` e `compare/csslib/parse/<livro>`.
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
