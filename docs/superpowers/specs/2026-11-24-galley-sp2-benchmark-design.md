# Galley — Subprojeto 2: Benchmark e corpus

- **Data:** 2026-11-24
- **Status:** rascunho para aprovação
- **Documento pai:** `2026-11-24-galley-arquitetura-design.md` (§6 Benchmarks e CI, §8 item 2)
- **Depende de:** SP1 (Fundação + Container), mergeado.

## 1. Intenção

Montar desde já a infraestrutura que mede o Galley contra si mesmo (regressões a cada PR) e contra os concorrentes, para que todo subprojeto seguinte nasça medido. Hoje só a etapa Container existe; o benchmark cobre o que existe e nasce preparado para crescer.

## 2. Metas

1. **Gate por PR** que reprova regressões de desempenho de forma confiável nos runners gratuitos do GitHub (VMs compartilhadas e ruidosas).
2. **Histórico** de todas as métricas, com detecção de regressão gradual e comentário automático "antes × depois" no PR.
3. **Comparação com concorrentes** no que hoje é comparável: abertura, memória e leitura de recursos contra os parsers `epubx`, `epub_plus` e `epub_pro`.
4. **Corpus de teste** público e reproduzível, mais um corpus privado que nunca sai da máquina do mantenedor.
5. **Números registrados de medição precisa** (tempo absoluto, memória de pico, `perf` nativo, corpus privado) mesmo antes de haver máquina dedicada, rodando localmente entre as mudanças.

## 3. Não-metas

- Paginação, FPS/jank, compatibilidade visual contra Chromium e comparação com leitores que renderizam (`flutter_epub_viewer`, Readium etc.): entram quando as etapas existirem (ver §9).
- Máquina dedicada (VM no Proxmox ou servidor físico): adição futura (ver §9).
- Serviço de dispositivos físicos (Android/iOS) para medições noturnas: subprojeto 6.

## 4. Anti-metas

- Gate instável: um PR não pode reprovar por ruído do runner. Gate que "pisca" é pior que nenhum.
- Livros com direitos autorais (ou seus títulos) publicados em qualquer lugar: repositório, logs de CI, Bencher.
- Dependências de concorrentes ou de benchmark vazando para o `pubspec.yaml` do pacote `galley`.
- Rodar o CI em máquina pessoal ou de produção (decisão: nada de runner self-hosted por enquanto).

## 5. Restrições

- Tudo gratuito por enquanto: runners do GitHub (minutos ilimitados em repositório público) e Bencher Cloud (gratuito para open source).
- Herdadas do pai e do SP1: Dart puro; dependências de runtime do `galley` continuam só `xml` e `meta`; comentários e docs em português do Brasil.
- Os runners hospedados do GitHub geralmente não expõem contadores de hardware: o gate de instruções em CI usa **Valgrind** (sondado em 2026-11-24: Dart AOT roda limpo em `cachegrind --cache-sim=no`, variação ~0,001% entre execuções, ~230× mais lento que nativo). Consequência: os benchmarks de instruções precisam ser curtos (alvo 10–50 ms nativos cada).
- `perf stat -e instructions:u` funciona na máquina local do mantenedor (sondado: mesma estabilidade, em velocidade nativa).

## 6. Abordagens (harness)

| Abordagem | Trade-off | Decisão |
|---|---|---|
| **A) Harness próprio em Dart** — programas de benchmark compilados AOT + orquestrador com modos, saída no formato JSON do Bencher | controle total; os mesmos programas servem a todos os modos; mais código nosso | **escolhida pelo usuário** |
| B) `package:benchmark_harness` | oficial, mas mede só tempo dentro da VM; ainda precisaria de wrapper para instruções, A/B e memória | descartada |
| C) Serviço pronto (CodSpeed) | instruções por simulação, grátis para open source; não suporta Dart oficialmente; dependência do que ele oferece | descartada |

Outras decisões tomadas na conversa:

| Tema | Decisão |
|---|---|
| Concorrentes nesta fase | só parsers: `epubx`, `epub_plus`, `epub_pro` (opção A) |
| Histórico/PR | Bencher Cloud |
| Runner privado / máquina dedicada | por enquanto **nenhum**; o que precisa de máquina dedicada roda **localmente na máquina do mantenedor, entre as mudanças**, e envia números ao Bencher como ambiente `local-dev` |
| Máquina dedicada | adição futura, entra como mais um ambiente no Bencher sem mudar o harness |
| Expansão | **pendência permanente:** cada subprojeto novo acrescenta suas métricas e comparações |

## 7. Desenho

### 7.1 Estrutura

```
benchmark/                      # pacote Dart separado (pubspec próprio), NÃO publicado
  pubspec.yaml                  # deps: galley (path: ..), epubx, epub_plus, epub_pro
  bin/                          # programas de benchmark (um por cenário ou família)
  lib/src/                      # harness: medição, saída Bencher, carregamento do corpus
  tool/bench.dart               # orquestrador: dart run tool/bench.dart <modo> [opções]
corpus/
  manifest.json                 # livros públicos externos: id, URL, sha256, licença, origem
  handmade/                     # fontes dos EPUBs escritos à mão + gerador determinístico
  README.md                     # licenças e procedência de cada item
```

- `benchmark/` é um pacote à parte para que as dependências dos concorrentes nunca entrem no `galley`. Ele pode importar `package:galley/src/...` para medir etapas internas (é código do próprio repositório, não API pública).
- `.pubignore` do `galley` exclui `benchmark/` e `corpus/`.
- `pub workspaces` é opcional e fica a critério do construtor.

### 7.2 Corpus

**Público (reproduzível por qualquer pessoa):**
- **Externos fixados por hash** (`corpus/manifest.json`): livros de domínio público ou licença livre, baixados pelo harness e verificados por `sha256`; cache no CI. Fontes sugeridas: Standard Ebooks (CC0, EPUB 3 com CSS de qualidade), Project Gutenberg (EPUB 2 e 3), Aozora Bunko ou equivalente para japonês, livros em árabe/hebraico de domínio público, e a suíte W3C `epub-tests` em commit fixo (licença W3C, com aviso). Alvo inicial: ~15–25 livros cobrindo EPUB 2 e 3, texto corrido, técnico com tabelas, ilustrado, layout fixo, CJK e RTL.
- **Escritos à mão** (`corpus/handmade/`): fontes legíveis + gerador Dart determinístico que produz os `.epub` (mesmos bytes a cada execução). Cobrem: tipografia variada, CSS de editora típico, tabelas, notas, imagens, CJK, RTL/bidi, fontes ofuscadas IDPF/Adobe, livros grandes **gerados em tempo de execução** (ex.: 50 MB e 300 MB, nunca versionados) e malformados.
- Binários grandes não são versionados no git; só fontes, geradores e o manifesto.

**Amplo (robustez, decisão do usuário em 2026-11-24):** uma amostra de **300 livros do Project Gutenberg**, escolhidos por semente fixa entre os EPUBs disponíveis. O objetivo não é medir desempenho; é verificar que **todos abrem** sem exceção e sem diagnósticos de severidade `error` inesperados, como um fuzz com livros reais (codificações, navegação malformada, nomes de arquivo incomuns).

- **Download:** pelos canais que o Gutenberg oferece a robôs (o mirror oficial e a política de *harvest*), nunca por raspagem do site, com cache local.
- **Lista:** fica em `corpus/pg-wide.json` (número do livro + sha256 da primeira coleta).
- **Atualização do Gutenberg:** se o Gutenberg atualizar um arquivo, o caso é relatado e a lista pode ser atualizada por ferramenta. Não reprova.
- **Onde roda:** no job noturno e localmente; não é gate de PR. Também não é espelhado.

O corpus privado **continua** no SP2, por decisão do usuário: os livros do Gutenberg são homogêneos (mesmo conversor, CSS mínimo) e não substituem EPUBs comerciais.

**Privado (máquina do mantenedor):**
- Diretório indicado por variável de ambiente (`GALLEY_PRIVATE_CORPUS`); nunca copiado para o repositório.
- Os resultados vão ao Bencher apenas como **agregados** (ex.: mediana/p95 de abertura sobre o corpus inteiro) ou com **identificadores anônimos** (hash do arquivo); títulos e nomes de arquivo nunca saem da máquina.

### 7.3 Modos do orquestrador

| Modo | Onde roda | O que mede | Uso |
|---|---|---|---|
| `instructions` | CI (Valgrind) e local (`perf`) | instruções por benchmark curto, por etapa: CRC-32, diretório central, extração deflate, OPF, nav/NCX, desofuscação, `decodeText`, abertura completa de livros pequenos | **gate do PR** |
| `ab` | CI | tempo de parede da `main` × PR, as duas compiladas AOT no mesmo job, execuções intercaladas (A B A B…) | **gate do PR** |
| `local` | máquina do mantenedor | tempo absoluto, memória de pico (RSS), `perf` nativo, corpus privado, livros grandes | registro manual entre mudanças (ambiente `local-dev`) |
| `compare` | CI noturno (e local) | Galley × `epubx` × `epub_plus` × `epub_pro`: abertura, memória, ler todos os recursos do spine, ler um recurso de um livro grande | relatório; não bloqueia antes da 1.0 |
| `size` | CI noturno | bytes adicionados ao app (release Android arm64 do exemplo com e sem o `galley`) | teto de 2 MB do design pai |

Todos os modos escrevem o **Bencher Metric Format** (JSON) e/ou um relatório legível no terminal.

### 7.4 Gates e limites

- **Instruções (PR):** reprova se algum benchmark ficar **mais de 0,5% acima** do resultado da `main`. Melhorias não reprovam.
- **A/B de tempo (PR):** reprova só com regressão **≥ 5%** e significância estatística (intervalo de confiança de 95% por bootstrap da razão das medianas inteiramente acima de 1,05). Sem significância, não reprova.
- **Regressão gradual:** além da comparação com a `main`, o Bencher compara com um **baseline fixo** (última release ou um marco fixado manualmente); acúmulo acima de **10%** desde o baseline reprova.
- **Contadores determinísticos:** ficam na suíte de testes normal (não no benchmark), com limites exatos. Exemplo: abrir o livro sintético de 300 MB lê no máximo **256 KB** da fonte de bytes; ler um capítulo lê só a entrada dele. Os números exatos são calibrados pelo construtor na primeira medição e então congelados.
- **Concorrentes:** só relatório antes da 1.0 (regra do pai: trava releases a partir da 1.0).
- **Tamanho:** teto absoluto de 2 MB (pai, §6); ultrapassar reprova o job noturno.

### 7.4.1 Decisões de operação dos gates *(chamadas minhas, após a revisão do construtor)*

- **Referência da `main` medida no mesmo job.** Os gates de instruções e de A/B compilam e medem a `main` (merge-base) e o PR **no mesmo job, com o mesmo toolchain**. O gate não depende do histórico do Bencher; o próprio harness decide aprovar ou reprovar. Isso elimina falso positivo por mudança de versão do Dart, do Valgrind ou da imagem do runner. O custo em dobro é aceito: os benchmarks de instruções são curtos.
- **Toolchain fixo nos jobs de benchmark.** Os jobs de benchmark usam uma versão fixa do Flutter (a mínima suportada, hoje 3.47.5), atualizada de forma deliberada num PR próprio. Os jobs de teste continuam com a matriz 3.47.5 + stable.
- **Orçamento do workflow de PR:** no máximo ~15 min de parede. Se o conjunto de benchmarks ou as repetições do A/B passarem disso, divida em jobs paralelos ou reduza as repetições, preservando a significância estatística.
- **Bencher só como histórico e comentário.** Os gates funcionam de forma autônoma pelo harness. O Bencher guarda o histórico, os gráficos e a regressão gradual, e comenta no PR. Os jobs de gate (`instructions` e `ab`) viram status obrigatórios da `main`. O SP2 está pronto quando os gates funcionam sem o Bencher **e** a integração com o Bencher está implementada. A validação de ponta a ponta com o Bencher real depende de o mantenedor criar o projeto e o token (passo manual documentado).
- **Regressão gradual.** O marco inicial é o commit do merge do SP1 (`d4ef38a`). O mantenedor o atualiza manualmente a cada release, ou ao aceitar de propósito uma regressão, com o procedimento documentado no `benchmark/README.md`. O limite de 10% reprova **só o job noturno**, nunca o PR.
- **Corpus público espelhado.** Os livros externos do manifesto, todos de domínio público ou com licença que permite redistribuição, são espelhados como asset de uma release dedicada do próprio repositório (`corpus-v1`), com as licenças e os avisos exigidos. A URL original fica como alternativa. O harness verifica o `sha256` nos dois casos. Livros cuja licença não permita espelhamento ficam só com a URL original e fora dos gates de PR.
- **Tamanho (2 MB).** Mede-se o APK **release, split por ABI, arm64** de um app mínimo, em duas variantes idênticas, uma com e outra sem a dependência `galley` e uma chamada a `EpubBook.fromBytes`. Conta a diferença de bytes. O job é noturno.
- **Contadores com o livro sintético de 300 MB.** Ficam marcados com a tag `heavy` e rodam num único job (stable, Linux), não na matriz inteira. O arquivo é gerado em streaming num diretório temporário e apagado ao final. Os contadores com livros pequenos rodam na suíte normal.

### 7.5 CI

- **Workflow de PR:** roda `instructions` e `ab` e envia ao Bencher.
- **PRs de forks:** secrets não ficam disponíveis em PRs de forks. Use o padrão de dois workflows que o Bencher documenta (`pull_request` gera os resultados como artefato; `workflow_run` com o token envia e comenta). Nunca rode código do PR com acesso a secrets.
- **Workflow noturno** (agenda) e em push na `main`: `instructions`, `compare`, `size` e uma bateria `ab` mais longa, para formar o histórico da `main` no Bencher.
- **Cache:** cache do corpus baixado (chave = hash do manifesto) e do toolchain.
- **Segredo:** `BENCHER_API_TOKEN` como secret do repositório. O mantenedor cria o projeto no Bencher (passo manual documentado).

### 7.6 Execução local

- `dart run tool/bench.dart local` na máquina do mantenedor:
  - roda `perf`, tempo absoluto, memória, livros grandes e corpus privado;
  - envia ao Bencher como ambiente `local-dev`, junto com o commit medido.
- Documentado no `benchmark/README.md`: quando rodar (depois de mudanças de desempenho e antes de releases) e como configurar o `perf` (`perf_event_paranoid`) e o `GALLEY_PRIVATE_CORPUS`.

## 8. Atualização do design pai

Atualizar §6 de `2026-11-24-galley-arquitetura-design.md` com:
- gate por instruções (Valgrind no CI, `perf` local) e A/B estatístico;
- Bencher;
- execução local no lugar do runner privado;
- máquina dedicada como adição futura;
- a pendência permanente de expansão.

## 9. Pendências registradas

- **Expansão permanente:** cada subprojeto acrescenta ao benchmark as métricas e comparações das etapas que criar:
  - SP3 documento: parsing de XHTML.
  - SP4 estilo: cascata e seletores.
  - SP5 layout: paginação, repaginação ao mudar a fonte, medição fatiada.
  - SP6 render e API: FPS/jank, memória real em dispositivo, compatibilidade visual contra Chromium e comparação com os leitores que renderizam.
  - SP7 recursos de leitura: busca, CFI.
- **Máquina dedicada:** VM no Proxmox (núcleos fixos, `cpu: host`, memória fixa, isolada de produção) ou servidor físico de entrada. Entra como ambiente novo no Bencher e assume o modo `local` de forma agendada, com o corpus privado.
- **Serviço de dispositivos físicos:** SP6.

## 10. O que fica para o construtor

- Lista exata de livros do manifesto (respeitando licenças e a cobertura de §7.2).
- Conjunto exato de benchmarks curtos por etapa.
- Número de repetições do A/B.
- Detalhes do formato JSON e configuração dos thresholds no Bencher.
- Calibragem dos limites dos contadores determinísticos.
- Uso ou não de `pub workspaces`.
