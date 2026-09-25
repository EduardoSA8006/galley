# S9 — Worker cooperativo no web

**Data:** 2026-09-25. **Ambiente:** Flutter 3.47.5 stable, Dart 3.13.4, pacote
`html` 0.15.7, Chromium 153.0.8010.52 (`CHROME_EXECUTABLE=/usr/bin/chromium`),
Intel i5-11400H, Linux 7.2.6 (Arch). **Código:**
`test/spike/support/s9_cooperative_worker.dart`,
`test/spike/support/s9_sample_xhtml.dart`,
`test/spike/s9_cooperative_worker_test.dart`.

## Pergunta

A Camada A escrita como gerador `sync*` com um `yield` por checkpoint, fatiada
em orçamento de 4 ms no isolate principal, é viável no web para uma seção
grande, e quanto perde em relação ao isolate nativo? Decide P10 (web na 1.0 ou
na 1.0.x).

## Como foi feito

- **Tarefa:** `parseSectionSteps(xhtml, sink)` é um `sync*` em dois estágios:
  (1) `html.parse(xhtml)` seguido de um `yield`; (2) caminhada iterativa no DOM
  (pilha explícita), emitindo um bloco por `p`, `h1`–`h6`, `li`, `pre`,
  `blockquote`, `td` que não contenha outro bloco (`blockquote > p` vira blocos
  `p`), texto normalizado com `RegExp(r'\s+')` (`pre` preserva), e um `yield`
  por bloco. O parse do `html` é **uma chamada atômica** sobre a string inteira:
  não há onde pôr um `yield` dentro dele sem reescrever o tokenizer. O executor
  o vê como a fatia que contém o passo 0.
- **Executor:** `CooperativeRunner` drena o iterador em fatias limitadas por
  `Stopwatch` a 4 ms (orçamento verificado depois de cada passo, como o `_slice`
  de doc/08 §2) e cede com `await Future.delayed(Duration.zero)`. Não há
  `SchedulerBinding` num teste de lógica pura (e no `--platform chrome` fora de
  widget test), então a cessão é o `Timer` de zero, o fallback que a Emenda 9 já
  prevê. Ele registra a duração de cada fatia e de cada cessão.
- **Amostras:** gerador determinístico (Park–Miller, exato em JS): prosa de light
  novel com diálogo curto, parágrafos longos, `h2`, `blockquote > p`, `ul > li`,
  `table > td`, `hr`, marcação inline e entidades. 500 049 unidades UTF-16
  (4 861 blocos, 4 778 `p`) e 3 000 336 (28 728 blocos). Bloco gigante: 200
  parágrafos com um `pre` de 1 MB no meio e, como caso extra, o mesmo texto num
  `p` (passa pelo regex de whitespace).
- **Plataforma:** o teste registra `vm`, `chrome-js` ou `chrome-wasm` (`kIsWeb`,
  `kIsWasm`) e pula o `Isolate.run` com `skip: kIsWeb`.
- **`dart:isolate` no web:** importado direto, sem import condicional. Com Dart
  3.13.4 ele **compila** no DDC e no dart2wasm; só falha em runtime
  (`UnsupportedError: dart:isolate is not supported on dart4web` no DDC,
  `Unsupported operation: RawReceivePort` no wasm), verificado com uma sonda no
  scratchpad. Como o teste de isolate é pulado no web, nenhuma chamada acontece.
- **Compiladores do `flutter test` no web:** `flutter test --platform chrome`
  **não usa dart2js**: compila com DDC (`TargetModel.dartdevc` em
  `flutter_tools/lib/src/test/web_test_compiler.dart`), o compilador de
  desenvolvimento. `--wasm` usa dart2wasm com `-O0` e `--enable-asserts`. Por
  isso há duas tabelas: a do teste (harness) e a de **release**, com os mesmos
  arquivos de suporte num `main` à parte (no scratchpad, não versionado),
  compilado com `dart compile exe`, `dart compile js -O4` e
  `dart compile wasm -O2`, e rodado no Chromium headless.
- **Relógio:** VM com `Stopwatch.frequency` de 1 GHz; no web 1 MHz, com leituras
  quantizadas em 0,1 ms no DDC e no release (`performance.now()` sem isolamento
  cross-origin); o harness do `--wasm` mostrou resolução mais fina.

Tempos em ms. "Mediana de 3" salvo indicação; faixas entre parênteses são das 3
rodadas do teste (ou das 2 rodadas do release).

## Resultados — harness do teste (rodada final; faixa das 3 rodadas)

| Medida | VM (`flutter_tester`, JIT) | Chrome DDC (`--platform chrome`) | Chrome wasm `-O0` (`--wasm`) |
|---|---|---|---|
| 1. Corretude direto == fatiado (500 KB, `pre` e `p` gigantes) | igual | igual | igual |
| 2. Parse atômico 500 KB | 41,2 (30,5–41,2) | **244,9** (239,9–244,9) | 57,7 (53,0–57,7) |
| 2. Parse atômico 3 MB | 207,4 (188,8–207,8) | **1 480** (1 480–1 513) | 367,6 (367,6–391,0) |
| Caminhada sozinha 500 KB / 3 MB | 37,7 / 171,7 | 22,6 / 100,2 | 9,0 / 49,3 |
| 3. Fatiado 500 KB: fatias; fatia do parse | 8; 32,4 | 6; 233,3 | 4; 46,4 |
| 3. Caminhada 500 KB: mediana / máx (3 execuções) | 4,00 / 5,56 | 4,00 / 4,00 | 4,00 / 4,00 |
| 3. Caminhada 500 KB: máx nas 3 rodadas; fatias > 8 ms | 7,53; 0/68 | 8,50; 1/48 | 13,42; 1/28 |
| 3. Cessão média 500 KB | 0,10 | 4,48 (0,20–4,48) | 6,70 (2,34–6,70) |
| 3. Parede fatiado 500 KB | 60,9 | 272,6 | 77,1 |
| 4. Direto 500 KB; razão fatiado/direto | 63,4; **0,96** (0,96–1,08) | 229,9; **1,19** (1,05–1,19) | 72,6; **1,06** (1,05–1,16) |
| 3. Fatiado 3 MB: fatias; fatia do parse | 41; 197,5 | 28; 1 508,6 | 15; 388,3 |
| 3. Caminhada 3 MB: mediana / máx (3 execuções) | 4,00 / 5,82 | 4,00 / 6,20 | 4,00 / 4,00 |
| 3. Caminhada 3 MB: máx nas 3 rodadas; fatias > 8 ms | 14,90; 4/412 | 13,10; 3/261 | 6,67; 0/130 |
| 3. Cessão média 3 MB | 0,09 | **4,23** (4,23–4,87) | **4,43** (4,32–4,43) |
| 3. Parede fatiado 3 MB (sem a fatia do parse) | 361,9 (164,4) | 1 730,4 (221,8) | 503,7 (115,5) |
| 4. Direto 3 MB; razão fatiado/direto | 386,0; **0,94** (0,94–1,04) | 1 572,2; **1,10** (1,06–1,10) | 423,3; **1,19** (1,08–1,29) |
| 5. `Isolate.run` 500 KB (spawn + parse + cópia do resultado) | 70,6 (70,6–100,5) | — | — |
| 5. `Isolate.run` 3 MB | 382,8 (381,9–408,3) | — | — |
| 5. `Isolate.run(() => 0)` vazio | 0,09–0,24 | — | — |
| 5. Cooperativo / isolate (500 KB; 3 MB) | 0,86; 0,95 (0,65–1,13) | — | — |
| 6. `pre` 1 MB: fatia que o contém | 1,7–2,7 (201 passos: a caminhada inteira) | 0,9–1,0 | 0,5 |
| 6. `pre` 1 MB: só o passo | 0,33 | < 0,1 | < 0,01 |
| 6. `p` 1 MB (regex): só o passo; fatia | **51,7**; 50,2–54,0 | 5,4; 5,0–5,8 | 7,5; 6,6–7,1 |
| Parse do documento de 1 MB com `pre` | 21,3 | 58,1 | 21,8 |

## Resultados — release (2 rodadas, faixa)

| Medida | Nativo AOT (`dart compile exe`) | dart2js `-O4` | dart2wasm `-O2` |
|---|---|---|---|
| Parse atômico 500 KB | 29,1–30,0 | **48,8–53,4** | **49,1–52,3** |
| Parse atômico 3 MB | 191,5–207,1 | 269,4–277,9 | 380,7–395,7 |
| Caminhada sozinha 500 KB / 3 MB | 25,0–26,9 / 158,0–177,4 | 10,1–16,3 / 56,9–60,5 | 21,0–25,9 / 47,0–51,8 |
| Direto 500 KB | 63,1–64,4 | 55,0–58,7 | 50,2–61,6 |
| Fatiado 500 KB (parede) | 53,8–56,1 | 61,0–65,2 | 71,2–73,6 |
| Fatiado/direto 500 KB | 0,83–0,89 | 1,04–1,19 | 1,19–1,42 |
| Fatiado 3 MB (parede) | 360,4–412,6 | 365,5–373,0 | 466,4–550,5 |
| Fatiado/direto 3 MB | 0,94–1,08 | 1,09–1,12 | 1,04–1,28 |
| Caminhada: máx de fatia 500 KB / 3 MB | 7,7–9,2 / 8,1–11,9 | 6,6–7,1 / 4,0 | 17,1–17,9 / 4,0 |
| Fatias > 8 ms (500 KB; 3 MB) | 1/43; 4/256 | 0/20; 0/80 | 2/20; 0/81 |
| Cessão média 3 MB | 0,02 | **4,28** | **4,12–4,22** |
| 3 MB: parede sem o parse vs caminhada sozinha | 184–197 vs 158–177 (**1,1×**) | 106 vs 57–60 (**1,8×**) | 103–121 vs 47–52 (**2,2×**) |
| `Isolate.run` 500 KB / 3 MB | 57,6–65,0 / 352,3–404,8 | — | — |
| `Isolate.run(() => 0)` vazio | 0,07–0,09 | — | — |
| `pre` 1 MB: só o passo | 0,33 | 0,5–0,7 | < 0,1 |
| `p` 1 MB (regex): só o passo (mediana); fatia | **53,6**; 55,5 | 9,1–9,9; 4,9–5,3 | 8,1–8,2; 7,6–8,6 |

**Web cooperativo (release) contra isolate nativo (AOT), tempo de parede total:**
500 KB: dart2js 61–65 contra 58–65 (**≈ 1,0–1,1×**), dart2wasm 71–74
(**≈ 1,1–1,3×**). 3 MB: dart2js 366–373 contra 352–405 (**≈ 0,9–1,1×**),
dart2wasm 466–551 (**≈ 1,2–1,6×**).

**Tamanho de seção no corpus real** (365 seções dos 8 EPUBs de
`test/corpus/reais/`, tamanho descomprimido): mediana 9 KB, p90 34 KB, p99
132 KB, máximo 206 KB (Dom Casmurro). Acima de 80 KB: 14 (3,8%); acima de
160 KB: 2 (0,5%). A Patologia tem seções de 1,2 MB e 3,2 MB.

## Leitura dos números

- **O parse atômico do `html` de 500 KB custa ~49–53 ms no Chrome em release
  (dart2js `-O4` e dart2wasm `-O2`) e 245 ms no DDC do `flutter test`, e é a
  única parte não fatiável.** São 3 frames perdidos a 60 Hz em release, 15 no
  DDC. O custo é linear: ~0,1 ms/KB em dart2js release (49 ms/500 KB, 270 ms/3
  MB), ~0,5 ms/KB no DDC. Com a tolerância de 8 ms de doc/08 §2, o parse cabe
  em seções de até ~80 KB em release: 96% das seções reais, mas não a seção de
  500 KB que doc/13 S9 pede, nem a Patologia (3,2 MB → ~270 ms travado).
- **A caminhada fatia como prometido.** Mediana de fatia 4,00 ms em todos os
  alvos; o passo indivisível (um bloco de prosa) é de microssegundos, então a
  fatia só passa do orçamento pelo último passo. Estouros acima de 8 ms são
  raros (16 de 1 447 fatias somando harness e release, ~1%; o pior caso é o
  wasm release de 500 KB, 2 de 20) e com cara de GC: aparecem em rodadas
  isoladas, em qualquer alvo, inclusive na VM, com máximos de 9 a 18 ms.
- **A cessão por `Timer` de zero custa ~4,2 ms no navegador.** É o clamp do
  HTML para `setTimeout` aninhado mais de 5 níveis: a cessão média é 0,02–0,2 ms
  na VM, e 4,1–4,9 ms no Chrome sempre que há mais que ~5 fatias seguidas. Com
  fatias de 4 ms, o estágio fatiável roda a ~50% de ciclo útil: a caminhada de
  3 MB leva 1,8× (dart2js) a 2,2× (wasm) o tempo direto. `scheduleTask` do
  `SchedulerBinding` não escapa disso: no Flutter 3.47.5 ele agenda com
  `Timer.run(_runTasks)` (`scheduler/binding.dart`, `_ensureEventLoopCallback`).
- **No total, o cooperativo perde pouco.** Fatiado/direto fica em 0,83–1,42
  em todos os alvos, porque o parse domina e não é fatiado. Contra o isolate
  nativo em release, o web cooperativo leva ~1,0–1,1× (dart2js) e ~1,1–1,6×
  (wasm). Na VM, o próprio `Isolate.run` não é mais rápido que rodar no isolate
  principal (cooperativo/isolate 0,65–1,13): a vantagem do isolate é não
  bloquear a UI, não o tempo.
- **O bloco gigante que custa é o de texto normalizado, não o `pre`.** Um `pre`
  de 1 MB é um único nó de texto: o passo custa < 1 ms em todos os alvos. O
  mesmo 1 MB num `p` passa pelo `replaceAll(RegExp(r'\s+'))`: 5–10 ms no Chrome
  (na tolerância de 8 ms, no limite) e **~52 ms no nativo** (JIT e AOT). O
  `RegExp` da VM é várias vezes mais lento que o do V8 aqui, o que também
  explica a caminhada nativa (25–27 ms) ser mais lenta que a dart2js (10–16 ms)
  para 500 KB.
- **Armadilha do pacote `html`:** `Element.children` é uma
  `FilteredElementList` cujo `length` e `operator []` refazem
  `nodes.whereType<Element>().toList()` a cada acesso. A primeira versão da
  caminhada indexava `children[i]` e ficou O(n²): 680 ms para 500 KB e **33 s**
  para 3 MB na VM. Iterar `el.nodes` resolveu (27 ms e 172 ms).
- **Spawn de isolate:** `Isolate.run(() => 0)` custa 0,07–0,24 ms (JIT e AOT, no
  desktop), e o `Isolate.run` com o trabalho de 500 KB custa 1,0–1,1× o trabalho
  direto em AOT, incluindo a cópia de 4 861 blocos de volta.

## Recomendação para P10

**Web na 1.0.x, não na 1.0.**

Critério (o de doc/13 S9, "seção de 500 KB sem jank"), medido por este mesmo
teste com build de release no Chrome (dart2js `-O4` e dart2wasm `-O2`), seção
de 500 KB, parse incluído: **nenhuma fatia acima de 16 ms e p99 das fatias
≤ 8 ms**. Hoje falha só pelo parse: uma fatia única de ~50 ms (release) a
245 ms (DDC). O restante (caminhada, orçamento, corretude, custo total contra o
isolate) já passa.

O que precisa existir para o web entrar, em ordem de custo:

1. **Parse fatiável.** Opções, a medir na Fase 1: (a) *parse em pedaços*: um
   scanner leve divide o `<body>` em fronteiras de elemento de topo a cada
   ~16 KB e cada pedaço vai a `parseFragment` com um `yield` entre eles
   (≈ 1,6 ms por pedaço em dart2js release, se o custo seguir linear), com
   fallback para o parse inteiro quando o scanner detectar tag desbalanceada
   entre pedaços; (b) tokenizer e tree builder próprios com checkpoint a cada
   N KB (caro: reimplementa a tolerância do HTML5 que é a razão de doc/03 §8);
   (c) um Web Worker com entrypoint Dart compilado à parte, que tira o parse
   do thread principal de vez, ao custo de empacotamento (o pacote precisa
   distribuir o worker compilado).
2. **Cessão sem clamp.** Trocar o `Timer` de zero por `MessageChannel`
   (`postMessage` não sofre o clamp de 4 ms) ou `scheduler.postTask` onde
   existir, no `CooperativeEpubWorker` e no `BudgetedScheduler` do web. Sem
   isso, todo trabalho fatiado no web roda a ~50% de ciclo útil.

Se o time aceitar como limitação documentada "no web, a primeira abertura de
uma seção trava ~0,1 ms por KB", o web caberia na 1.0 para o acervo comum
(p99 de 132 KB ≈ 13 ms, menos de um frame perdido). Não recomendo: a
pré-busca de doc/08 §1.1 (prioridade 3, resto do spine) parseia seções
grandes enquanto o usuário lê, e cada uma vira um engasgo sem causa aparente
para ele. A decisão não custa nada ao nativo: `EpubWorker` já isola a escolha.

## Sustenta / contradiz

| Doc | Seção | Veredito |
|---|---|---|
| 08 | §1 "toda tarefa da Camada A é um gerador `sync*` com um `yield` por checkpoint; no cooperativo, é drenado por fatias" | **Contradiz em parte.** Vale para a caminhada e para a construção da IR; **não** vale para o parse do `html`, que é atômico (50 ms/500 KB em release no Chrome, 245 ms no DDC). Acrescentar: "o parse do `html` é uma chamada única; no web ele precisa ser feito em pedaços (`parseFragment`) ou fora do thread principal" |
| 08 | §1 "o custo de spawn é de 50 a 200 ms" | **Contradiz.** Medido 0,07–0,24 ms para `Isolate.run` vazio em JIT e AOT no desktop, e `Isolate.run` com o trabalho de 500 KB a 1,0–1,1× do trabalho direto. O isolate de vida longa continua uma boa escolha, mas a justificativa numérica está errada; medir em AOT num Android real antes de reescrever |
| 08 | §2 agendador com `SchedulerBinding.scheduleTask` e fallback `Timer.run` | **Sustenta o orçamento, contradiz o custo da cessão no web.** As fatias ficam em 4 ms, mas no navegador cada cessão por `Timer` custa ~4,2 ms (clamp de `setTimeout` aninhado), e `scheduleTask` usa `Timer.run` por dentro. Acrescentar o mecanismo de cessão do web (`MessageChannel`) |
| 08 | §2 "blocos gigantes (um `pre` de 5 mil linhas) podem estourar uma fatia, tolerado até 8 ms" | **Sustenta para a Camada A, com ressalva.** O `pre` de 1 MB custa < 1 ms na Camada A (o estouro de §2 é do `Paragraph.layout`, não medido aqui). O bloco gigante caro é um `p` de 1 MB pelo regex de whitespace: 5–10 ms no Chrome, 52 ms no nativo. Sugerir checkpoint a cada 64 KB de texto dentro de um bloco (como o inflate) e colapso de whitespace escrito à mão em vez de `RegExp` |
| 08 | §3 checkpoint "Parse de seção: a cada bloco emitido" | **Contradiz.** O checkpoint só existe depois do parse. Trocar por "parse de seção: a cada pedaço de ~16 KB (web) e a cada bloco emitido" |
| 13 | S9 "parse de seção de 500 KB como `sync*` fatiado a 4 ms sem jank" | **Contradiz** no parse (uma fatia de ~50 ms em release); **sustenta** na caminhada (mediana 4,00 ms, > 8 ms em ~1% das fatias, atribuível a GC). "Medir tempo total contra o isolate": web cooperativo ≈ 1,0–1,1× (dart2js) e 1,1–1,6× (wasm) do isolate nativo |
| 13 | S9 "inflate próprio" | **Não coberto** por esta frente (P7, Fase 1) |
| 01 | Emenda 9 (b) "fatiando o parse por bloco no isolate principal" | **Contradiz** pelo mesmo motivo de doc/08 §1 |
| 03 | §8 parse com o pacote `html` | **Acrescentar:** caminhar por `nodes`, nunca indexar `children` (`FilteredElementList` refaz a lista a cada acesso: O(n²), 33 s para 3 MB) |

**O que mudaria (sem editar `doc/`):** P10 fechada como "web na 1.0.x" com o
critério acima; doc/08 §1 e Emenda 9 com o parse em pedaços (ou Web Worker)
como parte do `CooperativeEpubWorker`; doc/08 §1 sem o número de 50–200 ms de
spawn (ou com o número medido em Android AOT); doc/08 §2 com a cessão por
`MessageChannel` no web; doc/08 §3 com checkpoint por pedaço de parse e por
64 KB de texto dentro de bloco; doc/03 §8 com a nota sobre `children`; doc/13
S9 com "fechado parcialmente": caminhada e custo total validados, parse
fatiável e cessão sem clamp pendentes para a Fase 1.

## Como rodar

```sh
flutter test test/spike/s9_cooperative_worker_test.dart
CHROME_EXECUTABLE=/usr/bin/chromium flutter test --platform chrome test/spike/s9_cooperative_worker_test.dart
CHROME_EXECUTABLE=/usr/bin/chromium flutter test --platform chrome --wasm test/spike/s9_cooperative_worker_test.dart
```

Os números saem em linhas `[S9 vm|chrome-js|chrome-wasm]`. Lembrar que
`chrome-js` é DDC. Para release, um `main` que importe os dois arquivos de
suporte e repita as medições, compilado com `dart compile exe`,
`dart compile js -O4` ou `dart compile wasm -O2` e aberto no Chromium.

## Limites do spike

- A "Camada A" aqui é só parse, caminhada e normalização de texto: sem
  cascata de CSS, runs, âncoras nem serialização. O custo real da caminhada
  será maior; o do parse, não.
- Um único computador de desktop; nada de celular. A VM do teste é JIT
  (`flutter_tester`); os números AOT vêm do `dart compile exe` no mesmo
  desktop.
- Sem frames reais: não há Flutter renderizando durante o teste, então "jank"
  aqui é "fatia maior que o orçamento", não frame perdido medido.
- A extrapolação para o corpus real (~0,1 ms/KB) usa a taxa da prosa
  sintética; a densidade de marcação dos EPUBs reais é outra.
- Não foram medidos `MessageChannel`, `parseFragment` em pedaços nem Web
  Worker: são as propostas para a Fase 1.
