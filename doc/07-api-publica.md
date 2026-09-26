# 07 — API pública

**Decisão 7.1: declarativo com controller fino.
Decisão 7.2: seleção e gestos inclusos, menu e configurações no app.
Emenda 8: `EpubByteSource`.**

Três camadas públicas. É o que permite ser simultaneamente fácil de adotar e
super personalizável.

## 1. Camada 1 — pronto em dez linhas

```dart
final doc = await EpubDocument.open(
  source: FileEpubByteSource(path),
  cache: FileEpubCacheStore(cacheDir),
);

EpubReader(
  document: doc,
  state: readerState,                    // seu; você persiste
  onStateChanged: (s) => setState(() => readerState = s),
  style: EpubStyle.sepia().copyWith(
    fontSize: 18,
    family: myFontFamily,
    textAlign: EpubTextAlign.start,
  ),
  onSelection: (selection) => showMyMenu(selection),
  onLinkTap: (locator) => controller.goTo(locator),
  onExternalLinkTap: (uri) => launchUrl(uri),
  onNoteTap: (note) => showNoteSheet(note),
  onDiagnostic: (d) => log(d),
);
```

O widget é **função de um `ReaderState` imutável que o app possui**. Funciona com
Riverpod, Bloc ou `setState` sem atrito, e é testável sem bombear estado interno.

```dart
@immutable
final class ReaderState {
  final Locator? position;             // intenção de navegação, §1.2
  final ReadingMode mode;              // paginated | continuous
  final List<HighlightRange> highlights;
  final List<Locator> jumpHistory;     // ver 06 §6.2
  const ReaderState({...});
  ReaderState copyWith({...});
}
```

### 1.1 Controller fino, opcional

Para quem prefere imperativo, um wrapper que só embrulha o estado:

```dart
final class EpubReaderController extends ChangeNotifier {
  ReaderState get state;
  void goTo(Locator locator);
  void next(); void prev();
  void back();
  void setMode(ReadingMode mode);
  void addHighlight(HighlightRange h);
  void removeHighlight(String id);
  void clearSelection();
}
```

Ele **não** contém lógica de motor. É açúcar sobre o estado, e é por isso que não
reproduz os bugs de ciclo de vida dos controllers-deus dos pacotes existentes.

`setStyle` não está no controller: estilo é parâmetro do widget, e mudá-lo é
reconstruir o widget com outro `EpubStyle`, como qualquer propriedade Flutter.

### 1.2 O ciclo declarativo sem loop

Um estado declarativo com posição gera um problema clássico: o leitor vira a
página, emite `onStateChanged` com a nova posição, o app grava no estado, o
widget é reconstruído com `state.position` novo, e o leitor **não pode** tratar
isso como um pedido de navegação, senão anima duas vezes ou entra em ciclo.

Regra:

> `ReaderState.position` é **intenção**. O leitor navega até ele quando, e só
> quando, ele muda para um locator que **não está na página atual**.

Implementação: em `didUpdateWidget`, o leitor compara o `charOffset` do novo
`position` com o `[textStart, textEnd)` da página exibida (mesmo `href`). Se está
contido, é eco do próprio `onStateChanged`; nada acontece. Se não está, é
navegação. A comparação é por offset, nunca por identidade do objeto `Locator`,
para funcionar com estado serializado e desserializado.

`onStateChanged` é emitido no fim da virada (não durante a animação), na mudança
de modo, e ao adicionar ou remover destaque via controller. O app grava tudo ou
só `position`; é problema dele.

`onLocatorChanged(Locator)` continua existindo como atalho para quem só quer
persistir progresso.

### 1.3 O que o widget pinta além do texto

Nada. Sem barra de progresso, sem número de página, sem botões. Esses são do app,
alimentados por `controller.state`, `engine.pageCount` e `doc.pageMarkAt`. O app
de exemplo mostra como montar tudo em cerca de 200 linhas.

## 2. Camada 2 — motor sem a nossa UI

```dart
final engine = EpubLayoutEngine(
  document: doc,
  style: style,
  viewport: Size(360, 640),
  direction: doc.direction,
  textScaler: MediaQuery.textScalerOf(context),
);

final page = await engine.pageAt(locator);
final int? total = await engine.pageCount(href);   // null = ainda calculando
final next = await engine.pageAfter(page);
final prev = await engine.pageBefore(page);
engine.paginationState(href);                      // Stream<SectionPaginationState>
engine.dispose();
```

Para quem quer viewport próprio, paginação customizada, renderização fora de tela
ou exportação para imagem.

`RenderEpubPage` também é público, então é possível montar um widget próprio em
cima da nossa pintura. `EpubPagePainter` expõe a mesma pintura como
`CustomPainter`, para quem quer desenhar numa `Canvas` própria (thumbnail,
exportação para PNG via `PictureRecorder`).

## 3. Camada 3 — IR crua

```dart
final text = await doc.sectionText(href);      // String canônica + totalChars
final blocks = await doc.sectionBlocks(href);  // List<Block>
final anchors = await doc.sectionAnchors(href);
final section = await doc.section(href);       // Section completa
```

Para busca, TTS, indexação e exportação. Evita que alguém tenha que reparsear o
EPUB por fora do pacote, que é o desperdício mais comum em apps de leitura.

TTS: o app itera `blocks`, fala `canonicalText.substring(textStart, textEnd)` de
cada folha e pinta a posição corrente como destaque temporário via `highlights`.
Idioma por bloco vem de `Block.lang ?? Section.lang`.

## 4. Interfaces injetadas

```dart
/// Faixas de bytes do arquivo .epub. É o que o ZIP do pacote consome.
abstract interface class EpubByteSource {
  Future<int> get length;
  Future<Uint8List> readRange(int offset, int length);
  Future<void> close();
}

/// Recursos já resolvidos por href (EPUB extraído, ou decifrado por DRM externo).
abstract interface class EpubResourceProvider {
  Future<Uint8List> read(String href);
  Future<bool> exists(String href);
  Future<void> close();
}

/// Opcional. Bytes de fontes que o motor não encontra registradas.
abstract interface class EpubFontProvider {
  Future<Uint8List?> load(String family, FontWeight weight, FontStyle style);
}

abstract interface class EpubCacheStore {
  Future<Uint8List?> get(String key);
  Future<void> put(String key, Uint8List bytes);
  Future<void> evict(String keyPrefix);
}

/// Opcional. Ver 05 §6.2.
abstract interface class EpubSvgRasterizer { ... }
```

`EpubDocument.open` aceita `source:` **ou** `provider:`, nunca os dois. Com
`source`, o ZIP do pacote faz a resolução. Com `provider`, o pacote pede
`META-INF/container.xml` e segue dali; é o caminho para DRM externo (um
`provider` que decifra) e para EPUBs distribuídos extraídos.

`EpubFontProvider` é chamado quando (a) o perfil é `faithful` e o livro declara
`@font-face`, ou (b) o app pediu uma `family` em `EpubStyle` que não está
registrada no `FontManifest`. O pacote registra os bytes via `FontLoader` uma
vez por família. No perfil `uniform` com fontes do app, ele nunca é chamado, e
por isso é opcional. Fontes embutidas no EPUB são lidas do próprio container
(com desofuscação, [09](09-erros-diagnosticos.md) §4), sem passar pelo provider.

Implementações padrão de arquivo (`FileEpubByteSource`, `FileEpubCacheStore`)
são enviadas atrás de **import condicional**, para o web não quebrar. No web, o
app fornece `MemoryEpubByteSource` ou uma implementação sobre IndexedDB.

Essas interfaces são o motivo de o pacote não ter I/O próprio: quem controla
local, criptografia, eviction e origem dos bytes é o app.

## 5. Estilo

Ver [02-modelo-de-estilo.md](02-modelo-de-estilo.md) §5 para a definição completa
de `EpubStyle`, os presets e o hash de invalidação.

## 6. Destaques

```dart
final class HighlightRange {
  final String id;                 // do app
  final String href;
  final int startOffset, endOffset;
  final Color color;
  final HighlightStyle style;      // fill, underline, strikethrough
  final Locator locator;           // com text.* para reparo
}
```

O app passa a lista em `ReaderState`. O pacote pinta e resolve; **não guarda
nada**. Quando um destaque precisa de reparo, o pacote emite diagnóstico com o
locator corrigido e `onHighlightRepaired(String id, LocatorResolution)`, e o app
decide se persiste.

Toque em destaque: `onHighlightTap(HighlightRange, Rect anchor)`. Destaques
sobrepostos: pintados na ordem da lista, o último por cima.

Só destaques cujo `href` é o da seção exibida (ou vizinhas, para pré-busca) são
resolvidos. Uma lista com 5 mil destaques não custa nada até a seção deles
aparecer.

## 7. Ciclo de vida

```dart
final doc = await EpubDocument.open(...);
// ...
await doc.dispose();   // cancela tudo, drena a fila, mata o worker, fecha o source
```

`dispose` é obrigatório e documentado como tal: sem ele você vaza o isolate da
Camada A e o handle do arquivo. `EpubReader` **não** faz dispose do documento,
porque o documento pode ser compartilhado entre telas.

`EpubDocument.open` é o único ponto assíncrono obrigatório. Ele retorna quando o
container, o OPF e a navegação foram lidos e a **primeira seção do spine** (ou a
seção do `initialLocator`, se passado) está parseada. Tudo mais é sob demanda.

```dart
EpubDocument.open(
  source: ...,
  cache: ...,
  initialLocator: saved,        // prioriza o parse dessa seção
  budgets: EpubMemoryBudgets(...),
  strict: false,
  fontProvider: null,
  svgRasterizer: null,
);
```

## 8. Teste de adoção

Critério de aceite da Fase 6
([13-riscos-spikes-fases.md](13-riscos-spikes-fases.md)): um desenvolvedor Flutter
que nunca viu o pacote consegue um leitor funcional, com preferências e progresso
persistido, em **menos de 30 minutos**, lendo apenas o README.

O README do pacote deve conter, nessa ordem: o exemplo de dez linhas; como
persistir `ReaderState` com `toJson`/`fromJson`; como montar barra de progresso e
TOC; como fazer um menu de seleção; a lista de callbacks. Nada de arquitetura no
README; isso fica em `doc/`.
