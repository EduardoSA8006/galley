# 04 — Camadas B e C: layout e paginação

**Decisão 4.1: paginação híbrida — incremental para exibir, background para
contagem. Emenda 6: texto exibido. Emenda 10: paginação ancorada.
Emendas 11 e 12: justificação e tabelas.**

## 1. Camada B: resolução de estilo

Entrada: um `Block` da Camada A + `EpubStyle` + escala de texto do sistema.
Saída: `ui.TextStyle` por run, mais métricas de bloco (margens, recuo,
alinhamento) e o texto exibido.

É a única camada que conhece `dart:ui` e preferência ao mesmo tempo. É barata:
uma passada linear sobre os runs, sem alocação de texto no caso comum.

```dart
final class ResolvedBlock {
  final Block block;
  final DisplayText text;                       // §1.1
  final ui.ParagraphStyle paragraphStyle;       // inclui textDirection, locale, strut
  final List<(int start, int end, ui.TextStyle style)> spans;  // offsets em text.display
  final List<(int offset, ui.PlaceholderDimensions dims)> placeholders;
  final EdgeInsets margins;
  final double indent;
}
```

`ParagraphStyle` recebe `locale` do `lang` do bloco ou da seção e `textDirection`
do `dir` do bloco, do `dir` do `<html>`, ou inferido do primeiro caractere forte
do bloco, nessa ordem. Recebe também `height` igual a `EpubStyle.lineHeight`,
para que linhas com `sup`, `sub` ou fallback de fonte não fiquem mais altas que
as vizinhas. Sem entrelinha fixa, uma página com uma nota de rodapé em cada
parágrafo tem entrelinha irregular, e é o tipo de defeito que o leitor sente sem
saber nomear.

Por que `ParagraphStyle.height` e não `StrutStyle`: o spike S5 mostrou que, no
Flutter 3.44.1, `StrutStyle(height: 2.0, forceStrutHeight: true)` **não altera**
a altura da linha em `ui.Paragraph` (27.0 → 27.0), tanto em `flutter_tester`
quanto na engine Linux, enquanto `ParagraphStyle.height` e `TextStyle.height`
funcionam (27.0 → 40.0). Reexaminar strut na Fase 2; até lá, `height` é a
ferramenta.

### 1.1 Texto exibido e `DisplayMap` (Emenda 6)

```dart
final class DisplayText {
  final String display;              // o que vai para o ParagraphBuilder
  final DisplayMap map;              // display offset ↔ canonical offset
}

abstract interface class DisplayMap {
  int toCanonical(int displayOffset);
  int toDisplay(int canonicalOffset);
  static const identity = _IdentityMap();
}
```

Transformações que alteram a string, e portanto exigem mapa:

| Transformação | Origem | Efeito no comprimento |
|---|---|---|
| `text-transform: uppercase/lowercase/capitalize` | Run com bit `uppercase` etc. | Pode mudar (`ß` → `SS`, ligaduras, `İ`) |
| Hifenização (v1.2) | `EpubStyle.hyphenate` | Insere U+00AD |
| Remoção de U+00AD do fonte quando `hyphenate: false` | Preferência | Remove |

Regras:

- Sem transformação, `DisplayMap.identity` é usado e nenhuma string é copiada
- Com transformação, o mapa é um `Uint32List` de pontos de mudança, consultado
  por busca binária. Para um bloco de 2 mil caracteres com dez hifens, são dez
  entradas
- O mapa é **monotônico**. `toCanonical` de um offset dentro de um trecho
  expandido (o segundo `S` de `SS`) devolve o offset do caractere canônico de
  origem (`ß`)
- Inserção (U+00AD da hifenização): `toCanonical` de um offset dentro dela
  devolve o offset canônico **seguinte**, e `toDisplay` de um caractere
  precedido por inserção cai depois dela. Por isso o toque sobre o hífen
  pendurado de §8 resolve para a letra seguinte sem código extra (spike S2)
- **`ß → SS` não vem de `String.toUpperCase`.** Na VM, `'straße'.toUpperCase()`
  devolve `STRAßE`, `ﬁ` e `ŉ` não mudam e `'İ'.toLowerCase()` devolve `i` com uma
  unidade; o `toUpperCase` do JS faz `ß → SS` (S2, Flutter 3.47.5). Usar a função
  da plataforma faria o texto exibido, a paginação e o mapa **divergirem entre
  web e nativo**. A Camada B usa uma tabela própria gerada de `SpecialCasing.txt`
  (cerca de 100 entradas para maiúsculas, mais as sensíveis a locale: `tr`, `az`,
  `lt`), igual em todas as plataformas. Custo estimado: 1 dia na Fase 2
- **Toda** conversão entre posição visual e offset canônico passa por aqui:
  seleção, destaques, âncoras, semântica, locator. O caminho de
  [05](05-render-selecao-a11y.md) §3.2 é `getPositionForOffset` (caret) ou
  `getClosestGlyphInfoForOffset` (caractere) `→ map.toCanonical →
  + block.textStart`

O protótipo do S2 validou a forma: identidade sem cópia (a mesma instância de
`String`), pontos de mudança em `Uint32List` com busca binária, e 300 casos
aleatórios com `ß`, `ﬁ` e U+00AD satisfazendo a Invariante 7
([10](10-testes.md) §2).

Isso é o que permite a Camada A ignorar completamente como o texto será exibido.

## 2. Camada C: o mecanismo de fluxo

Para cada bloco folha, monte um `ui.Paragraph` com o estilo resolvido, chame
`layout(ParagraphConstraints(width: w))` e leia `computeLineMetrics()`. Isso dá
as caixas de linha exatas.

**Paginar é acumular caixas de linha numa coluna de altura `H` até encher.**

```dart
final class LineBox {
  final int blockIndex, lineIndex;
  final int textStart, textEnd;      // range em canonicalText (via DisplayMap)
  final double top, height, baseline;
}

final class PageFragment {
  final int blockIndex;
  final int firstLine, lastLine;
  final double yOffset;              // translate aplicado ao pintar
}

final class Page {
  final List<PageFragment> fragments;
  final int textStart, textEnd;
  final Locator start;
}

final class FlowCursor {             // retomada incremental e âncora (§3.1)
  final int blockIndex, lineIndex;
}
```

Largura de layout de um bloco = largura da coluna − margens laterais do bloco
(recuo de blockquote, nível de lista, padding de célula). Como a largura entra na
chave do cache de shaping (§5), blocos com recuos diferentes são `Paragraph`s
diferentes, e isso é esperado.

### 2.1 Quebra de parágrafo entre páginas

Quando as linhas de um parágrafo transbordam, corte **na fronteira de linha** e
pinte o **mesmo** `Paragraph` duas vezes, com `translate` e `clipRect`
diferentes em cada página. Nada é re-shapeado.

Um parágrafo de 40 linhas atravessando três páginas custa **um** shaping, não
três.

Esse `clipRect` é vertical: esconde as linhas do mesmo `Paragraph` que estão em
outra página. Os retângulos de seleção e de destaque, que vêm de
`getBoxesForRange`, precisam de clip também **horizontal**, à coluna do
fragmento: o spike S2 mediu a caixa do espaço final de uma linha cheia de 0 a
210 px numa coluna de 200 px, e sem o clip o realce invade a margem direita.
Esse espaço fica sem retângulo visível, que é o comportamento certo. Com os dois
clips, um range que atravessa a quebra de página tem cada caractere com
retângulo em exatamente uma página, e cada página pinta só os seus
([05](05-render-selecao-a11y.md) §3.2).

Consequência de produto: o defeito de "bloco maior que a tela vira página que
rola internamente" desaparece por construção. Nenhum leitor comercial faz aquilo,
e nós também não vamos.

### 2.2 Regras de quebra

| Situação | Regra |
|---|---|
| Órfã (1 linha de parágrafo no fim da página) | Empurra a linha para a página seguinte |
| Viúva (1 linha de parágrafo no início da página) | Puxa 2 linhas juntas |
| Heading no fim da página | Empurra junto com pelo menos 2 linhas do bloco seguinte |
| `breakBefore == page` / `breakAfter == page` | Respeitado (Classe 1); `avoid` tratado como heading |
| Imagem que não cabe | Escala para caber na coluna; se ainda não couber, página própria |
| Container (tabela/lista) que não cabe | Quebra entre `children`; linha de tabela indivisível maior que a página vira página própria com aviso `indivisibleBlock` |
| `sceneBreak` no fim ou no início da página | Suprimido visualmente (o espaço em branco da margem já separa) |
| Coluna menor que 3 linhas (viewport degenerado) | Regras de órfã e viúva desligadas, diagnóstico `viewportTooSmall` |

Órfã e viúva são desligáveis por `EpubStyle` no futuro; na 1.0 são fixas.

### 2.3 Por que a primeira página é rápida

Você shapeia **para frente até a coluna encher** e para. A primeira página custa
dois ou três parágrafos, não o capítulo.

Essa é a diferença estrutural em relação a medir a altura de todos os blocos
antes de paginar, que é o que os leitores nativos existentes fazem e é o teto de
desempenho deles.

**Exceção: seção que começa com tabela grande.** A largura das colunas depende
de **todas** as linhas (§9), então a primeira linha só aparece depois de medir a
tabela inteira. O spike S4 mediu isso para 200 × 8: as 1 600 células custam
~25 ms de medição, mais os layouts finais da primeira página (JIT). Opções, a
decidir na Fase 2: aceitar e declarar a exceção, ou medir as primeiras N linhas,
mostrar e repaginar quando as demais chegarem.

### 2.4 Ciclo de vida do `ui.Paragraph`

`ui.Paragraph` guarda memória nativa. Cada instância removida do cache de shaping
(§5) recebe `dispose()`. O `RenderEpubPage` nunca guarda referência a um
`Paragraph` fora do cache; ele pede ao cache a cada `paint`. Isso evita a classe
inteira de bugs de "paragraph disposed" após eviction por pressão de memória.

## 3. Paginação híbrida

Três estados por seção:

```dart
enum SectionPaginationState { none, partial, complete }
```

1. **`none` → exibir.** Paginação incremental sob demanda a partir de um
   `FlowCursor`. A UI mostra a página, sem total.
2. **`partial` → completar.** O agendador com orçamento por frame
   ([08](08-concorrencia-cache.md) §2) avança a paginação da seção em fatias de
   ~4 ms, em background.
3. **`complete`.** `pageCount(href)` passa a retornar valor, e a UI mostra
   "página 7 de 23".

`EpubLayoutEngine.pageCount(href)` retorna `int?` — `null` significa "ainda não
sei", e a UI deve tratar isso, não esperar.

O cache de paginação é indexado por `(href, hashDeEstilo, larguraViewport,
alturaViewport, âncora)`.

### 3.1 Paginação ancorada (Emenda 10)

Toda paginação de seção tem um **âncora**, um `FlowCursor`. Páginas são
calculadas para frente a partir dele acumulando linhas de cima para baixo, e
para trás acumulando linhas **de baixo para cima** até a coluna encher.

| Situação | Âncora |
|---|---|
| Entrada na seção por `next()` ou pelo início | `(0, 0)` |
| Entrada por locator (TOC, link, restauração ao abrir) | `(0, 0)`, e a página exibida é a que contém o offset (§6.1) |
| Mudança de estilo ou viewport com o leitor aberto | A linha que contém o `charOffset` do locator atual, ajustada pelo snap |

**Snap do âncora.** Antes de paginar, o âncora é movido para a fronteira legal
mais próxima **antes** da linha pedida. Sem isso, a costura entre a última página
de trás e a página ancorada violaria as regras de §2.2: um âncora na segunda
linha de um parágrafo deixaria uma órfã na página anterior, e um âncora na
última linha começaria a página com viúva. O spike S8 mediu o deslocamento
máximo em **2 linhas** (viúva e órfã encadeadas, ou heading seguido de uma
linha). A linha pedida está sempre na página ancorada, no topo ou até duas
linhas abaixo.

No terceiro caso, o usuário vê a linha que estava lendo no topo da página,
imediatamente, ao custo de shapear só os blocos vizinhos. As páginas anteriores
são calculadas para trás sob demanda ou em background. A contagem total difere
da paginação a partir de `(0, 0)` em **0 ou +1 página, nunca −1** (S8, 500 casos
aleatórios: 0 em 47%, +1 em 53%), porque a costura só pode desperdiçar espaço,
nunca ganhar. É exibida quando `complete`.

Por que isso é aceitável: nenhum leitor comercial garante que "página 7" seja o
mesmo trecho antes e depois de mudar a fonte. O que o usuário exige é não perder
a linha. O `charOffset` é a identidade da posição; o número da página é
derivado e efêmero.

Regras de órfã e viúva valem nas duas direções. Implementação sugerida pelo S8:
um único predicado `isLegalBreak(fronteira)` que decide se a fronteira entre
duas linhas consecutivas é aceitável (órfã, viúva, heading no fim, heading mais
uma linha, `breakBefore`, coluna com menos de 3 linhas). Paginar para frente
preenche e **recua** a fronteira até ficar legal; para trás, preenche de baixo
para cima e **avança** até ficar legal. As regras espelham por construção, não
por duplicação. Custo medido: 150 mil linhas em 3,7 ms, irrelevante perto do
shaping.

## 4. Um motor de fluxo, dois viewports

O fluxo de caixas de linha é **idêntico** nos dois modos:

- **Paginado:** fatia o fluxo em colunas de altura `H`
- **Contínuo:** expõe o fluxo como faixa rolável, sem fatiar

Consequências importantes:

1. O locator mapeia igual nos dois modos
2. **Trocar de modalidade preserva a posição exata.** Nenhum pacote existente faz
   isso
3. Os testes de invariante valem para os dois modos sem duplicação

No modo contínuo, a faixa de uma seção tem altura conhecida só depois de
`complete`. Antes disso, o scroll usa uma estimativa (`totalChars × altura média
por caractere das seções já medidas`) e corrige sem salto visível ancorando o
scroll offset na linha visível no topo, não no pixel. É a mesma técnica de listas
com itens de altura variável.

## 5. Cache de shaping

```
chave = (hashDoBloco, hashDeEstilo, largura)
valor = ui.Paragraph já com layout aplicado + LineMetrics
```

`hashDeEstilo` está definido em [02](02-modelo-de-estilo.md) §5.2.
`hashDoBloco` = FNV-1a de `(href, blockIndex, textStart, textEnd)`, que é único
por IR e barato.

Shaping é o custo dominante do motor. **Este cache é a otimização de maior
alavancagem do projeto inteiro.** Orçamento de memória separado, eviction LRU por
bytes estimados (≈ `2 × display.length + 64 × linhas` mais uma constante).

Cor não entra na chave. Trocar cor reconstrói o `Paragraph` (o `ui.TextStyle`
carrega a cor) mas reaproveita as `LineMetrics`, então não repagina. Ver
[02](02-modelo-de-estilo.md) §5.2.

## 6. Política de mudança de viewport

Toda mudança de viewport invalida a Camada C. A regra é única e absoluta:

> **Guarde o locator, invalide, repagine ancorado no locator, restaure.**
> Nunca por índice de página.

| Evento | Tratamento |
|---|---|
| Rotação | Guarda locator, repagina, restaura. Sem debounce (é discreto) |
| Redimensionamento contínuo (desktop, split screen) | Debounce de 150 ms; durante o arraste, mostra a última pintura válida escalada com `FittedBox`-like clip, sem relayout |
| Teclado subindo | Modo contínuo: ignora (só muda o viewport de scroll). Modo paginado: trata como resize |
| Mudança de `MediaQuery.textScaler` | Entra no hash de estilo; trata como mudança de preferência |
| Safe area / notch | Entra em `pageMargins` efetivas |
| Mudança de fonte do sistema (Android) | Não afeta: o motor usa a família de `EpubStyle`, não a do tema |

### 6.1 Restauração precisa

Restaurar significa: encontrar a página cujo `[textStart, textEnd)` contém o
`charOffset` guardado. Se o offset cair exatamente numa fronteira, escolhe a
página que **começa** nele, para que o usuário não perca a linha que estava lendo.

Com paginação ancorada (§3.1), a restauração após mudança de estilo é trivial: a
página exibida é, por construção, a que começa na linha do locator.

## 7. Direção de leitura

`page-progression-direction: rtl` no OPF (Classe 1) afeta:

- A ordem das páginas no modo paginado
- A direção do gesto de virada
- A posição da barra de progresso

```dart
enum EpubReadingDirection { ltr, rtl }
```

Vem da publicação, sobreponível pelo app. Bidi **dentro** do texto é resolvido
pelo `ui.Paragraph` nativamente e não tem relação com isso. O que o motor faz é
passar o `textDirection` correto ao `ParagraphStyle` (§1), porque o alinhamento
`start` depende dele.

## 8. Justificação e hifenização (P1, Emenda 11)

Flutter não hifeniza. `text-align: justify` sem hifenização produz rios brancos
visíveis, especialmente em português, que tem palavras longas, e em coluna
estreita de celular.

Das três opções da v0.2, a terceira ("justificar com limite de espaçamento,
caindo para `start` na linha ruim") **não é implementável** sobre `ui.Paragraph`:
`TextAlign.justify` não expõe espaçamento máximo entre palavras e o alinhamento
é por parágrafo, não por linha. Reimplementar a quebra de linhas por fora do
motor de texto está fora de questão.

**Decisão:**

1. **v1.0:** `EpubStyle.textAlign` padrão `start`. `justify` disponível, e a
   documentação do preset diz que fica melhor com hifenização. Palavras mais
   largas que a coluna são quebradas pelo `ui.Paragraph` em qualquer caractere,
   que é o comportamento padrão e aceitável.
2. **v1.2:** hifenização por padrões Knuth-Liang, inserindo **U+00AD** no texto
   exibido via `DisplayMap` (§1.1). O `ui.Paragraph` quebra a linha no soft
   hyphen e ele tem largura zero quando não quebra, mas **não pinta o hífen na
   quebra** (spike S5, Flutter 3.44.1: zero pixels escuros após a última letra
   com Noto Serif e Liberation Serif, contra 30 com `-` literal). A pintura é do
   motor: após `layout`, para cada linha cuja fronteira cai num U+00AD, um
   `drawParagraph` de um `"-"` pré-shapeado em `(line.left + line.width,
   baseline)`. O hífen invade a margem direita em cerca de 0.3em (*hanging
   hyphen*, prática tipográfica aceita, invisível em `justify` porque a linha já
   ocupa a coluna). Nenhum relayout; o `DisplayMap` não muda. Idioma vem de
   `Block.lang`/`Section.lang`, por isso a Emenda 4 é pré-requisito.

   Alternativas rejeitadas: reservar a largura do hífen em todas as linhas (todas
   perdem 0.3em, inclusive as não hifenizadas) e relayout com `-` literal (2 a 3
   shapings por parágrafo e `DisplayMap` mais complexo).

   Custo medido: um U+00AD a cada 6 letras num parágrafo de 2 mil caracteres
   muda o tempo de shaping em 1.06× (165 → 175 µs).

   Em tabela, `minIntrinsicWidth` trata a palavra com U+00AD como inquebrável,
   embora o `ui.Paragraph` quebre nela (spike S4). Com hifenização, o
   min-content de célula hifenizada terá de ser calculado pelo motor, senão
   empurra tabelas para a escala (§9).

O spike S5 confirmou o resto: `TextAlign.justify` não justifica a última linha, e
`ui.ParagraphStyle`/`ui.TextStyle` só têm `wordSpacing` e `letterSpacing` fixos,
sem máximo nem por linha. Falta medir a diferença de rios entre `start`,
`justify` e `justify + U+00AD` com o dicionário `hyph-pt`, o que fica para a 1.2.

## 9. Tabelas (P2, Emenda 12)

Cada célula folha é um `ui.Paragraph`; uma célula com `children` é um
sub-fluxo. O algoritmo é o layout automático de CSS simplificado:

1. **Medir.** Para cada célula, **um** `layout(double.infinity)` e duas
   leituras: `minWidth` = `minIntrinsicWidth` (a palavra mais longa) e
   `maxWidth` = `longestLine` (o max-content; o `maxIntrinsicWidth` do mesmo
   layout também serve, mas inclui o espaço final). Valores degenerados são
   zerados: `longestLine` de célula vazia é −FLT_MAX, e `minIntrinsicWidth` de
   célula só com espaço é FLT_MIN. A célula vazia mede só o padding e tem a
   altura de uma linha vazia.
   Os valores seguem a grade do HTML: cada célula vai para o primeiro slot livre
   da linha, pulando os ocupados por `rowSpan` de cima. Span que sai da grade é
   truncado (`truncatedRowSpan`, `truncatedColSpan`) em vez de sobrepor células,
   e `rowSpan=0` vai até o fim da tabela, como no HTML.
2. **Colunas.** `colMin[i]` e `colMax[i]` são os máximos das células de span 1
   da coluna. Depois, em ordem crescente de span, cada célula com `colSpan > 1`
   reparte igualmente entre as colunas cobertas **só o déficit** entre a sua
   largura e a soma delas, como no CSS.
3. **Distribuir.** Largura disponível `W` (coluna de texto menos padding):
   - `ΣcolMax ≤ W`: cada coluna recebe `colMax`; sobra vai para margem
   - `ΣcolMin ≤ W < ΣcolMax`: cada coluna recebe `colMin + (W − ΣcolMin) ×
     (colMax − colMin) / Σ(colMax − colMin)`
   - `ΣcolMin > W`: escala a tabela inteira (fonte e padding) por `s = W /
     ΣcolMin`, com piso **0.8×**. A escala é uma **transformação de pintura**: o
     layout é feito em tamanho normal, com as colunas em `colMin` (largura `W /
     s`), e pintado com `canvas.scale(s)`. Não se reconstroem os parágrafos com
     `fontSize × s`. Se ainda não couber, a tabela é pintada a 0.8× com largura
     `ΣcolMin × 0.8` e o bloco ganha **rolagem horizontal própria** dentro da
     página, com diagnóstico `tableOverflow`. É a única exceção à regra "nada
     rola dentro da página", e é declarada. Hit-test e seleção passam pela mesma
     transformação: o ponto do toque pela inversa, os retângulos pela direta
     ([05](05-render-selecao-a11y.md) §3.2).
4. **Linhas.** Altura da linha = máximo das alturas das células de `rowSpan` 1.
   Os `rowSpan` são resolvidos depois, em ordem crescente de span, esticando a
   célula sobre as linhas cobertas; se a célula com `rowSpan` for mais alta que
   a soma, a última linha coberta cresce.
5. **Paginar.** A linha de tabela é a unidade de quebra. A primeira linha com
   `isHeaderCell` em todas as células é **repetida** no topo de cada página em
   que a tabela continua, como fazem processadores de texto. Regras propostas
   pelo spike S4 e validadas no protótipo:
   - Linhas ligadas por `rowSpan` formam um grupo que fica na mesma página
     **enquanto couber numa página vazia**. Se não couber, quebra entre as
     linhas do grupo, e a célula com `rowSpan` é fragmentada como um parágrafo
     (`fragmentedRowSpan`), sem perder linha
   - Linha isolada mais alta que a página: página própria **com** o cabeçalho
     repetido, célula clipada, diagnóstico `indivisibleBlock`
   - O cabeçalho só é repetido se o seu grupo ocupar no máximo **50% da
     altura da página**; acima disso, `headerNotRepeated`. A progressão é
     garantida mesmo sem a regra (cada página leva pelo menos uma linha); a
     regra evita desperdício
   - Não tratados no protótipo: `rowSpan` que sai do cabeçalho para o corpo e
     tabela que começa no meio de uma página

Bordas: uma linha fina na cor do texto a 30% de opacidade entre linhas, sem
bordas verticais. O CSS de borda do publisher é ignorado (Classe 3 de fato).

Por que `layout(double.infinity)` e não `layout(0)` (spike S4, Flutter 3.47.5):
com largura 0 o `ui.Paragraph` quebra por caractere, um glifo por linha. O
`minIntrinsicWidth` passa a ser a largura de um glifo, e o `maxIntrinsicWidth`
vira o max-content e ainda soma as quebras duras (`x\ny long` dá 80 em vez de
60). Além disso, `minIntrinsicWidth` depende da largura do último `layout` e só é
a palavra mais longa com largura ≥ ela, isto é, com `∞`. `layout(0)` é também o
layout mais caro (71 ms contra 16 ms em 1000 parágrafos de 40 palavras). A regra
da v0.4 (`maxIntrinsicWidth` após `layout(0)`) dava colMin = colMax e mandava
para escala e overflow uma tabela que cabia sem escala (célula de 44 caracteres
em 200 px).

Por que só o déficit no `colSpan`: a divisão igual acerta o retângulo, mas infla
colunas estreitas. No S4, uma coluna de conteúdo de 18 px foi a 99 px e a tabela
ficou 81 px mais larga que o necessário.

Por que transformação de pintura na escala: reconstruir o parágrafo com fonte
menor refaz o shaping, que é o que custa (98 ms contra 53 ms em 200 × 8), e
arredonda o avanço em tamanho fracionário num sentido que a fonte real não
garante. O layout em tamanho normal na largura exata do min-content elimina as
duas coisas.

Correção medida no protótipo: 200 tabelas aleatórias (13 900 células, spans
esporádicos, larguras de 150 a 1500 px) sem sobreposição, com todos os
retângulos dentro da caixa, Σ = `W` exato nos regimes proporcional e de escala,
e **nenhuma** quebra por caractere no layout final. A paginação de 60 linhas com
`thead` cobre cada linha uma vez, com o cabeçalho no topo das páginas 2 a 9.

Custo: **dois layouts por célula**, a medição e o final. O shaping acontece no
primeiro; re-layouts no mesmo parágrafo custam 4 a 6 µs. Medido em JIT no
`flutter_tester`, textos novos a cada execução:

| Tabela | Sem escala | Com escala (`canvas.scale`) |
|---|---|---|
| 20 × 5 | 2,9 ms (29,6 µs/célula) | 4,6 ms |
| 200 × 8 | 50 ms | 53 ms |

A de 20 × 5 cabe numa fatia só sem escala. As maiores não cabem, então **a
tabela é medida em fatias, uma célula por etapa** do agendador de
[08](08-concorrencia-cache.md) §2: medir é independente por célula, e a
distribuição é O(células) e barata. Fatiada a 4 ms, a de 200 × 8 sem escala
leva 13 fatias, com passo típico de 15 a 70 µs. Tratada como bloco atômico,
estouraria a tolerância de 8 ms por uma ordem de grandeza. A tabela só pode ser
paginada depois de medida inteira (§2.3). Tabelas gigantes pagam o preço uma
vez e ficam no cache de paginação. Release AOT deve ser mais rápido; a proporção
entre as variantes, dominada por shaping, deve se manter.

## 10. Imagens no fluxo

- Imagem em bloco (`BlockKind.object`): largura = `min(intrínseca, largura da
  coluna)`, centralizada, com a razão de aspecto preservada. Altura máxima =
  altura da coluna menos uma linha (para que sempre caiba uma legenda).
- Imagem inline (`InlineObject` dentro de parágrafo): `addPlaceholder` com
  `PlaceholderAlignment.baseline`, altura limitada a `2 × lineHeight`; acima disso
  vira bloco próprio com diagnóstico `inlineImagePromoted`.
- Sem dimensão intrínseca: reserva `4:3` na largura da coluna e repagina a seção
  quando a dimensão real chegar (ver [05](05-render-selecao-a11y.md) §6).
