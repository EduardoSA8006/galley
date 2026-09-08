# 08 — Concorrência e cache

**Decisão 8.1: orçamento por frame no isolate principal.
Decisão 8.2: binário compacto próprio.
Emenda 7: chave do cache inclui CSS. Emenda 9: worker e agendador.**

## 1. Worker da Camada A (Emenda 9)

A Camada A roda atrás de uma abstração:

```dart
abstract interface class EpubWorker {
  Future<T> run<T>(EpubTask<T> task, {EpubPriority priority, EpubCancellationToken? token});
  Future<void> dispose();
}
```

Duas implementações, escolhidas por import condicional:

| Implementação | Onde | Como |
|---|---|---|
| `IsolateEpubWorker` | Android, iOS, macOS, Windows, Linux | Um **isolate de vida longa com fila de tarefas**, criado na abertura do documento e morto no `dispose` |
| `CooperativeEpubWorker` | Web (dart2js e dart2wasm não têm isolates) e testes | Mesma fila, no isolate principal; cada tarefa é um `Iterable<void>` fatiado pelo agendador de §2 com o mesmo orçamento |

A interface é a mesma e o código da Camada A não sabe onde está rodando. Para
isso, **toda tarefa da Camada A é escrita como gerador síncrono (`sync*`) com um
`yield` por checkpoint** (§3). No isolate, o gerador é drenado de uma vez; no
cooperativo, é drenado por fatias. É o mesmo mecanismo que dá cancelamento de
graça.

Nunca um isolate por seção: o custo de spawn é de 50 a 200 ms, o que anula o
ganho em qualquer navegação normal.

Roda lá: leitura do ZIP, inflate, parse de XHTML, cascata de CSS, construção da
IR, serialização e desserialização do cache, busca linear (`findAll`). **Tudo CPU
pura sem `dart:ui`**, o que torna esse worker trivial e seguro.

O `EpubByteSource` vive no isolate principal (um `RandomAccessFile` não é
enviável). O worker pede faixas de bytes por mensagem, e o isolate principal
responde. Para evitar ida e volta por entrada, o worker pede o central directory
uma vez e depois pede cada seção com **uma** mensagem (offset e tamanho já
conhecidos). Alternativa para `FileEpubByteSource`: passar o caminho e abrir um
segundo handle dentro do isolate, o que elimina o ping-pong. As duas são
implementações do mesmo `EpubByteSource`; a segunda é a padrão em plataformas com
`dart:io`.

### 1.1 Prioridade da fila

1. Seção sendo exibida (ou a do `initialLocator` na abertura)
2. Seções vizinhas (anterior e próxima) para pré-busca
3. Resto do spine, quando ocioso, para `totalChars` e cache

Uma tarefa de prioridade maior **preempta** a fila, mas não aborta a tarefa em
execução (ela termina no próximo checkpoint, §3).

## 2. Paginação em background

Shaping e layout usam `dart:ui`, que exige o isolate principal. O spike S1
existe para confirmar que isso continua verdade na versão mínima do Flutter que
adotarmos, e **presume-se negativo**: o desenho não depende dele.

A paginação em background usa um agendador com orçamento no isolate principal:

```dart
final class BudgetedScheduler {
  static const _budget = Duration(microseconds: 4000);
  final _queue = PriorityQueue<_Job>();
  bool _scheduled = false;

  void add(Iterator<void> work, EpubPriority priority) { ... _pump(); }

  void _pump() {
    if (_scheduled) return;
    _scheduled = true;
    // Roda entre frames, quando o framework está ocioso. Não depende de um
    // frame ser agendado, ao contrário de addPostFrameCallback.
    SchedulerBinding.instance.scheduleTask(_slice, Priority.idle);
  }

  void _slice() {
    _scheduled = false;
    final sw = Stopwatch()..start();
    while (sw.elapsed < _budget && _queue.isNotEmpty) {
      final job = _queue.first;
      if (!job.work.moveNext()) _queue.removeFirst();
    }
    if (_queue.isNotEmpty) _pump();
  }
}
```

Por que não `addPostFrameCallback` (v0.2): ele só dispara **após um frame**, e
um app parado numa página não agenda frames. A contagem de páginas congelaria
até o usuário tocar a tela. `scheduleTask` com `Priority.idle` roda quando não há
frame pendente e cede quando há.

Funciona sempre, nunca engasga, e é como editores de texto fazem layout
incremental.

Unidade de trabalho: uma linha de `LineBox`. Na prática, um `Paragraph.layout`
inteiro é atômico (não dá para parar no meio), então a unidade real é **um
bloco**; blocos gigantes (um `pre` de 5 mil linhas) podem estourar uma fatia, e
isso é medido no teste de jank e tolerado até 8 ms.

O mesmo agendador serve o `CooperativeEpubWorker` (§1) e a decodificação de
imagens fora do caminho crítico.

## 3. Cancelamento

Sem isso você vaza trabalho quando o usuário fecha o livro no meio de uma
paginação.

```dart
final class EpubCancellationToken {
  void cancel();
  bool get isCancelled;
  void throwIfCancelled();   // lança EpubCancelledException
}
```

Toda tarefa carrega um id e um token. Cancelar:

1. Remove da fila as tarefas não iniciadas
2. Marca a tarefa em execução, que aborta no próximo **checkpoint**

Checkpoints obrigatórios (cada um é um `yield` no gerador da tarefa):

| Etapa | Checkpoint |
|---|---|
| Inflate de entrada | A cada 64 KB de saída |
| Parse de seção | A cada bloco emitido |
| Cascata de CSS | A cada regra |
| Paginação | A cada bloco (ver §2) |
| Serialização do cache | A cada seção |
| Busca linear | A cada bloco |

`EpubDocument.dispose()` cancela tudo, drena a fila, mata o worker e fecha o
source, nessa ordem.

## 4. Cache em disco da Camada A

Formato binário próprio: a IR é uma string mais arrays de inteiros, então um
buffer por seção com índice é o formato mais rápido e compacto para essa forma,
sem adicionar dependência.

### 4.1 Chave (Emenda 7)

```
sha1(bytesDaSeção ‖ bytesDoCss[0] ‖ bytesDoCss[1] ‖ ...) + ":" + IR_SCHEMA_VERSION
```

Os CSS entram na ordem da cascata ([03](03-camada-a-ir.md) §6). Sem eles, dois
EPUBs com o mesmo XHTML e CSS diferente colidiriam, e o segundo receberia a IR do
primeiro (com `display: none` errado, marcadores de lista errados, etc.).

Custo: o CSS de um livro tem tipicamente de 5 a 50 KB e é o mesmo para todas as
seções; seu hash parcial é calculado uma vez por abertura e reaproveitado. O
SHA-1 da seção (10 a 500 KB) custa menos de um milissegundo.

Bumpar `IR_SCHEMA_VERSION` invalida tudo automaticamente. **É a proteção para
quando o parser mudar**, e é por isso que ela existe como constante pública
interna e não como número mágico.

Há também uma entrada por livro, chave `sha1(container.xml ‖ OPF ‖ NAV ‖ NCX)`,
com a `EpubPublication` serializada (TOC, `page-list`, metadados, `totalChars`
por seção). É o que faz a segunda abertura mostrar progresso global no primeiro
frame sem tocar nenhuma seção.

### 4.2 Layout do buffer

```
[magic 4B]["EPIR"]
[schemaVersion u16]
[flags u16]
[lang: idx u16 no stringPool]
[canonicalText: len u32 + UTF-8]
[blocks: count u32 + registros de tamanho fixo (kind u8, container u8, level u8,
  flags u8, textStart u32, textEnd u32, lang u16, runStart u32, runCount u16,
  objStart u16, objCount u16, childStart u32, childCount u16, marker u8,
  start i32, ordinal i32, colSpan u8, rowSpan u8, objectIdx i16)]
[runs: count u32 + (end u32, attrs u16, linkIndex i16)]
[links: count u32 + (hrefIdx u16, fragmentIdx u16, flags u8)]
[objects: count u32 + (offset u32, kind u8, hrefIdx u16, w f32, h f32, altIdx u16, titleIdx u16)]
[anchors: count u32 + (idIdx u16, offset u32)]
[stringPool: count u32 + (len u16 + UTF-8)]   // hrefs, ids, alt, títulos, lang
[diagnostics: count u32 + (code u16, severity u8, offset u32, msgIdx u16)]
```

Strings repetidas (hrefs, ids) vão para um pool com índice, o que reduz
significativamente o tamanho em livros com muitos links internos. Blocos são
uma árvore serializada em pré-ordem; `childStart`/`childCount` indexam o mesmo
array.

Little-endian sempre, via `ByteData`. Sem compressão: o cache fica ao lado de um
EPUB que já é comprimido, e inflar na leitura custaria mais que os bytes
economizados.

### 4.3 Política

- Escrita **depois** de servir a UI, nunca no caminho crítico da primeira página
- Falha de cache **nunca** é fatal: degrada para recomputar e emite diagnóstico
- Buffer com `magic` ou `schemaVersion` errados, ou truncado, é tratado como
  miss e sobrescrito
- O app controla o local e a eviction via `EpubCacheStore`. A chave começa com o
  hash do livro (`sha1(OPF)` abreviado a 16 hex), para que `evict(prefix)` apague
  um livro inteiro

## 5. Caches em memória

Eviction **por bytes, não por contagem de capítulos**. Capítulos variam de 200 a
200 mil palavras, então "±1 capítulo" é granularidade grosseira demais.

| Cache | Orçamento sugerido | Chave |
|---|---|---|
| IR de seção | 24 MB | `href` |
| `ui.Paragraph` + `LineMetrics` | 32 MB estimados | `(hashBloco, hashEstilo, largura)` |
| Imagens decodificadas | 48 MB | `(href, larguraAlvo)` |
| Paginação de seção | 4 MB | `(href, hashEstilo, viewport, âncora)` |

Total dentro do orçamento de 120 MB de [10-testes.md](10-testes.md) §4, com
margem para o framework.

Todos os orçamentos são configuráveis em `EpubDocument.open(budgets: ...)`, com
os valores acima como padrão.

A IR da seção exibida e das duas vizinhas é **fixada** (não sofre eviction), e o
mesmo vale para os `Paragraph`s da página exibida e das adjacentes. O resto é
LRU.

### 5.1 Reação a pressão de memória

`WidgetsBindingObserver.didHaveMemoryPressure` esvazia, nessa ordem: imagens,
`Paragraph`, paginação. A IR de seção é a última, porque recomputá-la é o mais
caro. Itens fixados nunca são esvaziados.

### 5.2 Ciclo de vida do app

`AppLifecycleState.paused` (app em background): o agendador para de consumir
fatias (nada de gastar bateria paginando um livro que ninguém está lendo) e a
escrita de cache pendente é concluída. `resumed`: retoma.
