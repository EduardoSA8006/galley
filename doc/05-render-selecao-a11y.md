# 05 — Camada de render, seleção e acessibilidade

**Decisão 4.2: `RenderObject` próprio pintando `Paragraph`s. Emenda 13: SVG.**

## 1. A página é um render object

```dart
final class RenderEpubPage extends RenderBox {
  Page page;
  ParagraphCache cache;
  EpubStyle style;
  List<HighlightRange> highlights;
  TextSelectionRange? selection;
  ImageCache images;
}
```

Dentro do `paint`:

1. Fundo (`style.backgroundColor`)
2. Retângulos de destaque, derivados de `Paragraph.getBoxesForRange`
3. Retângulos de seleção, da mesma fonte
4. `canvas.drawParagraph` por fragmento, com `translate` e `clipRect`
5. Marcadores de lista, réguas de tabela e de `sceneBreak` (quando habilitada)
6. Imagens via `canvas.drawImageRect`, decodificadas em tamanho-alvo
7. Alças de seleção, por cima de tudo

**Zero widget por bloco. Zero `Element`. Zero churn de árvore ao virar página.**

Ordem importa: destaques antes do texto (fundo), seleção antes do texto
(fundo), nunca por cima. Destaque com `HighlightStyle.underline` ou
`strikethrough` é pintado **depois** do texto, porque é traço, não fundo.

O `RenderEpubPage` não guarda `ui.Paragraph`; pede ao cache a cada `paint`
([04](04-layout-paginacao.md) §2.4). Se o cache não tem (eviction por pressão de
memória), re-shapeia sincronamente nesse frame; é o único caminho em que um
frame pode estourar, e é medido no teste de jank.

### 1.1 Repaint × relayout

- Cor, destaque, seleção: `markNeedsPaint`
- Página, estilo com hash diferente, viewport: `markNeedsLayout` e o motor entrega
  uma `Page` nova

O widget que envolve o `RenderEpubPage` é um `LeafRenderObjectWidget`. O
`EpubReader` ([07](07-api-publica.md)) monta um `PageView`-like próprio com dois
ou três `RenderEpubPage` (anterior, atual, próximo) para a animação de virada,
reciclando-os.

## 2. O custo, explicitamente

Pintar o próprio texto significa perder tudo que o Flutter dá de graça:

| Perdido | Precisa implementar | Onde |
|---|---|---|
| `SelectableText` | Alças, hit test, extensão por arraste | §3 |
| Menu de contexto | Callback `onSelection`; a UI é do app | §3.4 |
| Acessibilidade | `SemanticsNode` por bloco/fragmento | §4 |
| Gestos | Virada, arraste, duplo toque, long press | §5 |
| Teclado e foco | Setas, PageUp/Down, Home/End, atalhos de seleção | §5.1 |
| Escala de texto do sistema | Aplicação de `MediaQuery.textScaler` | §4.3 |
| Cursor de mouse | `MouseRegion` com `SystemMouseCursors.text` sobre texto e `click` sobre links | §5.1 |

Essa tabela é o orçamento real do spike S2 e S3
([13-riscos-spikes-fases.md](13-riscos-spikes-fases.md)).

## 3. Seleção

### 3.1 Primitivas que `ui.Paragraph` já dá

- `getPositionForOffset(Offset)` → posição de texto a partir de coordenada
- `getBoxesForRange(start, end)` → retângulos de um range
- `getWordBoundary(position)` → limites de palavra para o duplo toque
- `getLineBoundary(position)` → limites de linha
- `getClosestGlyphInfoForOffset` → glifo mais próximo, útil para alças em RTL

Não estamos reimplementando tipografia, só o fluxo acima dela.

### 3.2 Do toque ao offset canônico

```
Offset local na página
  → fragmento que contém o ponto (busca linear, poucos fragmentos)
  → Paragraph do bloco, com o translate desfeito
  → getPositionForOffset → offset no texto EXIBIDO do bloco
  → DisplayMap.toCanonical                          (04 §1.1)
  → + block.textStart → charOffset em canonicalText
```

O caminho inverso (offset canônico → `toDisplay` → `getBoxesForRange`) serve
para posicionar alças e para restaurar destaques.

Toque fora de qualquer fragmento (margem, espaço entre blocos) resolve para o
fragmento mais próximo verticalmente, e dentro dele para o início ou o fim,
conforme o lado. É o comportamento de todo editor de texto e evita "toque morto".

### 3.3 Seleção que atravessa blocos e páginas

Uma seleção é um par de `charOffset` na seção, não um par de posições visuais.
Isso significa que ela sobrevive a virada de página, mudança de fonte e rotação.

Seleção **não atravessa seções**. É a mesma limitação do Apple Books e do Kindle,
e a alternativa (offsets de duas seções num só objeto) complica tudo por um caso
raro.

No modo paginado, arrastar até a borda da página **estende para a página
seguinte** com auto-avanço após 500 ms de permanência na borda. No modo contínuo,
arrastar até a borda do viewport rola com velocidade proporcional à distância da
borda, como em campos de texto.

O `text` da seleção é extraído de `canonicalText`, com os `\n` de separador de
bloco preservados e os U+FFFC removidos. Isso é o que vai para o clipboard.

### 3.4 Contrato com o app

```dart
final class EpubSelection {
  final int startOffset, endOffset;
  final String href;
  final String text;
  final Rect anchorRect;        // para posicionar o menu, em coordenadas globais
  final Locator locator;        // já com text.before/highlight/after preenchidos
}
```

O pacote emite `onSelection` (a cada mudança, com debounce de um frame) e
`onSelectionEnd` (quando a alça é solta) e pinta as alças. **O menu é do app**,
porque é identidade visual. O pacote não abre nenhum popup.

`controller.clearSelection()` existe para o app fechar a seleção depois de agir.

### 3.5 Alças

Formas por plataforma via `TextSelectionControls` do próprio Flutter
(`materialTextSelectionControls`, `cupertinoTextSelectionControls`), pintadas pelo
`RenderEpubPage`. Reaproveitar os controles do framework garante a forma correta
em iOS e Android sem desenhar nada.

## 4. Acessibilidade

**Requisito de primeira classe desde o primeiro commit.** Um leitor que TalkBack
e VoiceOver não conseguem ler é um defeito grave, não um refinamento.

### 4.1 Granularidade

`SemanticsNode` **por bloco** quando o bloco cabe inteiro na página, e **por
fragmento** quando o bloco é dividido. Por linha é granularidade errada: o leitor
de tela recitaria linha por linha, quebrando a frase.

### 4.2 API correta

Um `RenderBox` que expõe **vários** nós semânticos não usa só
`describeSemanticsConfiguration` (que descreve um único nó). O caminho é:

```dart
@override
void describeSemanticsConfiguration(SemanticsConfiguration config) {
  super.describeSemanticsConfiguration(config);
  config.isSemanticBoundary = true;   // este render object é um nó pai
}

@override
void assembleSemanticsNode(
  SemanticsNode node,
  SemanticsConfiguration config,
  Iterable<SemanticsNode> children,
) {
  final nodes = <SemanticsNode>[];
  for (final fragment in page.fragments) {
    final child = _cachedNodeFor(fragment)      // reutiliza por (blockIndex, firstLine)
      ..rect = _rectOf(fragment)
      ..updateWith(config: _configFor(fragment));
    nodes.add(child);
  }
  node.updateWith(config: config, childrenInInversePaintOrder: nodes.reversed.toList());
}
```

Os `SemanticsNode` filhos são **cacheados** por fragmento e reutilizados entre
frames, senão o leitor de tela perde o foco a cada repaint. É o mesmo padrão do
`RenderParagraph` do framework com `InlineSpan`s semânticos.

### 4.3 Atributos por tipo de bloco

| Bloco | Semântica |
|---|---|
| `heading` | `SemanticsFlag.isHeader`, `headingLevel`. Atenção: em Flutter 3.44.1 `SemanticsConfiguration.headingLevel` é documentado como usado **só no web** e ignorado nas outras plataformas; TalkBack e VoiceOver recebem apenas `isHeader`. Verificar em S3 se o nível chega por outro caminho |
| `paragraph`, `verse`, `code` | `label` = texto do fragmento, via `DisplayMap` de volta ao canônico (o leitor de tela lê o texto do autor, não o transformado) |
| `InlineObject` com `alt` | Nó próprio com `label: alt`, `isImage: true` |
| `InlineObject` sem `alt` | Nó com `label` genérico e `isImage: true`, mais diagnóstico |
| Run `link` | Nó filho com `isLink: true`, `SemanticsAction.tap` que navega |
| Run `noteRef` | `isLink: true`, label "nota" mais o texto do run |
| `tableCell` | `SemanticsSortKey` ordinal; a tabela toda tem `label` com "tabela, N linhas, M colunas" |
| `listItem` | `label` prefixado pelo marcador ("1.", "•") |
| Página | O nó raiz expõe `scopesRoute` e `label` "página X de Y" quando Y é conhecido; ações `scrollLeft`/`scrollRight` mapeadas para virar |

`textDirection` do nó vem do bloco. `locale`, do `lang`, para que o TTS do
sistema escolha a voz certa.

### 4.4 Escala de texto do sistema

`MediaQuery.textScaler` **deve** ser respeitado. Multiplica `style.fontSize`,
limitado por `style.maxTextScale` para que a paginação não degenere. Entra no
hash de estilo, então mudá-lo é uma mudança de preferência normal.

### 4.5 Outras configurações do sistema

- `MediaQuery.boldText`: força `FontWeight.bold` no corpo. Entra no hash.
- `MediaQuery.disableAnimations`: virada de página sem animação.
- `MediaQuery.highContrast`: sem efeito automático (as cores são do app), mas
  documentado para que o app escolha um preset adequado.

### 4.6 Testes

Testes de semântica automatizados sobre o corpus, verificando que:

- todo texto de `canonicalText` visível na página aparece em algum nó semântico
  da página (Invariante 6)
- headings expõem nível correto
- ordem de leitura dos nós corresponde à ordem do documento
- links e notas expõem ação de toque
- imagens expõem `alt`

## 5. Gestos

| Gesto | Ação padrão | Configurável |
|---|---|---|
| Toque na borda lateral | Virar página | Zona e comportamento |
| Arraste horizontal | Virar página com animação | Curva e duração |
| Toque no centro | `onTap` para o app (mostrar/esconder chrome) | Sim |
| Toque em link | `onLinkTap` / `onExternalLinkTap` / `onNoteTap` | Não |
| Long press | Iniciar seleção por palavra | Não |
| Duplo toque | Selecionar palavra | Não |
| Triplo toque | Selecionar bloco | Não |
| Arraste em alça | Estender seleção | Não |
| Arraste vertical (modo contínuo) | Scroll | Física |
| Pinça | Nada por padrão; `onScaleGesture` para o app mapear em `fontSize` | Sim |

Direção da virada respeita `EpubReadingDirection`
([04](04-layout-paginacao.md) §7).

Um toque é classificado **antes** de agir: se cai sobre um run `link`, é link;
senão, se cai na zona de borda, é virada; senão é `onTap`. A zona de borda é
padrão 20% da largura de cada lado.

### 5.1 Teclado, foco e mouse

Desktop e web são plataformas de primeira classe
([11](11-empacotamento-versionamento.md) §2), e um leitor sem teclado nelas é
inutilizável.

| Tecla | Ação |
|---|---|
| `→` / `←` (invertidas em RTL), `PageDown` / `PageUp`, `Espaço` / `Shift+Espaço` | Página seguinte / anterior |
| `Home` / `End` | Início / fim da seção |
| `Ctrl+Home` / `Ctrl+End` | Início / fim do livro |
| `↑` / `↓` no modo contínuo | Scroll de uma linha |
| `Shift+setas` com seleção ativa | Estender seleção |
| `Ctrl+A` | Selecionar o bloco sob o cursor (não a página, não o livro) |
| `Ctrl+C` | `onCopy(EpubSelection)`; o pacote **não** toca o clipboard |
| `Esc` | Limpar seleção |
| `Tab` / `Shift+Tab` | Percorrer links da página, com anel de foco pintado |
| `Enter` sobre link focado | Ativar |

Mouse: arraste seleciona (sem long press); clique em link ativa; roda vertical
no modo paginado vira página, no modo contínuo rola; cursor `text` sobre texto e
`click` sobre links.

O `EpubReader` é um `Focus` e recebe foco ao ser tocado. O app pode passar
`autofocus` e um `FocusNode`.

## 6. Imagens

- Decodificadas via `ui.instantiateImageCodec` com `targetWidth`/`targetHeight`
  calculados do viewport e do `devicePixelRatio`, nunca em resolução original.
  Medido (spike S7): PNG de 2000×2000 decodificado para 360 px ocupa 31× menos
  memória retida (0.49 MB contra 15.3 MB), com tempo de decode igual (19 contra
  21 ms). O ganho é em retenção, não no pico transitório do decode, então
  decodificar fora do caminho crítico continua necessário
- Cache LRU **por bytes decodificados**, não por contagem
  ([08](08-concorrencia-cache.md) §5); `ui.Image.dispose()` na eviction
- Enquanto decodifica, o espaço é reservado usando as dimensões intrínsecas do
  `InlineObject`, para que a paginação não salte quando a imagem chega
- Sem dimensões intrínsecas: reserva `4:3` na largura da coluna e repagina a
  seção quando a real chegar, emitindo diagnóstico. A repaginação usa a
  paginação ancorada ([04](04-layout-paginacao.md) §3.1) para a linha do topo
  não se mover
- Dimensões intrínsecas vêm do atributo `width`/`height` do XHTML ou do CSS
  (Classe 1). Como o parse da Camada A não decodifica imagem, um EPUB sem esses
  atributos paga a repaginação uma vez; depois a dimensão real é guardada no
  cache de paginação
- GIF animado: primeiro frame. Não animamos.
- Decodificação falhou (formato não suportado, bytes corrompidos): caixa com
  `alt` e diagnóstico `imageDecodeFailed`. O espaço reservado é mantido.

### 6.1 Toque em imagem

`onImageTap(EpubImageRef)` com `href`, `alt` e o `Rect` global. O app decide se
abre em tela cheia. O pacote não abre visualizador.

### 6.2 SVG (Emenda 13)

Flutter não rasteriza SVG sem dependência, e o núcleo não pode ter uma.

```dart
abstract interface class EpubSvgRasterizer {
  Future<ui.Image?> rasterize(Uint8List svgBytes, int targetWidth, int targetHeight);
}
```

- Com rasterizador injetado: SVG é tratado como imagem
- Sem rasterizador: placeholder com `alt` (ou o texto dentro do `<svg>`, se houver
  `<text>`), e diagnóstico `svgUnrasterized`
- **Caso especial resolvido no núcleo:** SVG cujo único conteúdo gráfico é um
  `<image href="...">` de raster (o padrão para capas em EPUB2 e em muitos EPUB3)
  é desembrulhado durante o parse: vira `InlineObject(kind: image, href:
  raster)`, com o `viewBox` como dimensão intrínseca. Isso cobre a maioria dos
  SVGs do acervo sem nenhum rasterizador
- SVG inline (`<svg>` dentro do XHTML) é serializado de volta para bytes e segue
  o mesmo caminho

Um pacote irmão `galley_svg` pode entregar a implementação
sobre `flutter_svg`/`vector_graphics`, fora do núcleo.

## 7. Links

- Interno com fragmento: `onLinkTap(Locator)` com o locator já resolvido via
  `anchors` da seção alvo (o que pode exigir parsear a seção alvo; é feito no
  worker antes de emitir)
- Interno sem fragmento: locator no início da seção
- Externo (`http`, `https`, `mailto`, qualquer esquema): `onExternalLinkTap(Uri)`
- `noteRef` (`epub:type="noteref"` ou `role="doc-noteref"`, ou link para `aside`
  com `epub:type="footnote"`): `onNoteTap(EpubNote)`
  ([06](06-locator-navegacao.md) §6.1)

Links visitados não são rastreados. É estado, e estado é do app.
