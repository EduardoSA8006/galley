# 01 — Registro de decisões

## Decisões fechadas

| # | Decisão | Escolha | Onde está documentada |
|---|---|---|---|
| 1 | Contrato de fidelidade | Nativo puro com degradação declarada | [00](00-visao-geral.md) §3 |
| 2 | CSS do publisher vs. usuário | Três classes; perfil `uniform` na v1 | [02](02-modelo-de-estilo.md) |
| 3 | Forma da IR | Lista plana com containers rasos; runs semânticos; NFC + whitespace colapsado | [03](03-camada-a-ir.md) |
| 4.1 | Paginação | Híbrida: incremental para exibir, background para contagem | [04](04-layout-paginacao.md) §3 |
| 4.2 | Construção da página | `RenderObject` próprio pintando `Paragraph`s | [05](05-render-selecao-a11y.md) |
| 5 | Camada de render | Absorvida pela 4.2 | — |
| 6.1 | Formato do locator | Readium Locator, offset em `otherLocations`, sem CFI | [06](06-locator-navegacao.md) §1 |
| 6.2 | Reparo do locator | Reparar e sinalizar | [06](06-locator-navegacao.md) §4 |
| 7.1 | Controle da leitura | Declarativo com controller fino opcional | [07](07-api-publica.md) §1 |
| 7.2 | Escopo do widget | Seleção e gestos inclusos; menu e configurações no app | [07](07-api-publica.md) §1 |
| 8.1 | Paginação em background | Orçamento por frame no isolate principal | [08](08-concorrencia-cache.md) §2 |
| 8.2 | Cache da Camada A | Binário compacto próprio, atrás de `EpubCacheStore` | [08](08-concorrencia-cache.md) §4 |
| 9.1 | Gate de teste | Métricas e IR como gate; goldens de imagem em subconjunto | [10](10-testes.md) §3 |
| 10.1 | Dependências | `html` + `xml`; ZIP e hash próprios; sem `epub_pro` | [11](11-empacotamento-versionamento.md) §1 |
| 10.2 | Escopo da v1.0 | Reflow, seleção, destaques, busca; fixed-layout na 1.1 | [12](12-roadmap.md) |

## Emendas aceitas

### Emenda 1 à Decisão 3 — mapa de âncoras

**Problema.** A IR plana descarta o DOM, e com ele descartava os atributos `id`.
Sem eles, três coisas quebram: entradas de TOC que apontam para
`cap03.xhtml#secao2`, links internos do livro, e notas de rodapé (o
`InlineAttr.noteRef` não tinha destino).

**Emenda.** `Section` passa a carregar `Map<String, int> anchors`, mapeando cada
`id` do documento para o offset em `canonicalText`. Preenchido durante o parse,
serializado no cache.

**Status:** aceita. Ver [03-camada-a-ir.md](03-camada-a-ir.md) §4.

### Emenda 2 à Decisão 2 — `EpubFidelity` na v1.0

**Problema.** Eu afirmei que adicionar `EpubFidelity.faithful` depois seria
mudança não-quebrante. Em Dart isso é **falso**: adicionar valor a um enum
público quebra todo `switch` exaustivo no código dos consumidores.

**Emenda.** O enum já declara os dois valores na v1.0. `faithful` lança
`EpubUnsupportedException` até ser implementado, com a limitação documentada.

**Status:** aceita. Ver [02-modelo-de-estilo.md](02-modelo-de-estilo.md) §4 e
[11-empacotamento-versionamento.md](11-empacotamento-versionamento.md) §3.

## Emendas da revisão v0.3

Propostas na revisão v0.3 e **aceitas em 2026-09-07**. Cada uma está integrada
ao documento correspondente.

### Emenda 3 à Decisão 3 — forma do texto canônico

**Problema.** Com "quebras de bloco não geram caractere", dois blocos adjacentes
concatenam no `canonicalText` (`"...aberta.Capítulo 2"`). Isso quebra a
tokenização de qualquer índice de busca construído sobre a Camada 3, produz
`text.before`/`text.after` de locator com palavras coladas, e faz `getWordBoundary`
devolver uma "palavra" que atravessa blocos. Além disso, `InlineObject` não ocupa
posição no texto, então "antes da imagem" e "depois da imagem" são o mesmo offset,
e uma seleção não consegue incluir ou excluir a imagem de forma inequívoca.

**Emenda.** Cada bloco folha termina com exatamente um `\n` (U+000A) que pertence
ao seu range. Cada `InlineObject` ocupa exatamente um U+FFFC (object replacement
character) em `canonicalText`, no seu `offset`. Os dois entram em `totalChars`.
A Invariante 1 continua exata, porque a união dos ranges de bloco cobre a string
inteira. Ver [03](03-camada-a-ir.md) §5.

**Status:** aceita (2026-09-07).

### Emenda 4 à Decisão 3 — idioma, direção e estrutura dos runs

**Problema.** (a) A IR não guarda `lang`/`xml:lang` nem `dir`. Sem idioma, o
fallback de fonte CJK escolhe glifos errados (unificação Han: o mesmo code point
tem forma diferente em japonês e chinês), a hifenização futura não sabe qual
dicionário usar, e TTS pronuncia errado. Sem `dir`, um bloco em hebraico dentro de
livro em português é alinhado do lado errado. (b) `InlineAttr.link` refere um
`StyleRun.target` que não existe na definição. (c) Runs sobrepostos (ênfase dentro
de link) não têm regra de resolução. (d) Tabela não tem linha, célula não tem
`colspan`; lista não tem tipo de marcador nem valor inicial.

**Emenda.** `Section.lang`, `Block.lang` (quando difere da seção), `Block.dir`.
Runs viram **segmentos não sobrepostos** com um bitmask `attrs`, e alvos de link
vão para uma lista `links` separada. Containers ganham `ContainerKind`
(`table`, `tableRow`, `list`, `blockquote`, `figure`, `aside`, `generic`); célula
ganha `colSpan`/`rowSpan`; lista ganha `marker` e `start`; item ganha `ordinal`.
Imagem em nível de bloco vira `BlockKind.object`. Ver [03](03-camada-a-ir.md) §4.

**Status:** aceita (2026-09-07).

### Emenda 5 à Decisão 2 — precedência exata do perfil `uniform`

**Problema.** [02](02-modelo-de-estilo.md) §2 diz que a Classe 2 é preservada
("preserve o relativo"), e §3 diz que a tipografia do motor **substitui** a do
publisher. Os dois não podem ser verdade ao mesmo tempo. Caso concreto: `p {
text-indent: 1.5em }` é Classe 2, mas `EpubStyle.indent` é preferência do
usuário. Quem ganha não estava definido.

**Emenda.** No perfil `uniform`, a regra semântica do motor é a **base**. Do
publisher, honra-se: propriedades inline semânticas (`font-style`, `font-weight`,
`font-variant`, `text-transform`, `vertical-align`), `text-align` em elementos
estruturais, e tamanho de fonte **relativo**, com clamp em `[0.75, 1.6]` do corpo.
Métricas de bloco (`text-indent`, `margin`, `padding`, `line-height`) vêm do
motor e do `EpubStyle`. Ver [02](02-modelo-de-estilo.md) §3.1.

**Status:** aceita (2026-09-07).

### Emenda 6 — texto exibido e `DisplayMap`

**Problema.** `text-transform: uppercase` e hifenização alteram a string que vai
para o `ui.Paragraph`. `ß` em caixa alta vira `SS` e muda o comprimento; um soft
hyphen inserido é um caractere a mais. Todo o mapeamento toque → offset canônico
de [05](05-render-selecao-a11y.md) §3.2 assumia identidade entre as duas strings.

**Emenda.** A Camada B produz, por bloco, um `DisplayText` com a string exibida e
um `DisplayMap` monotônico de offsets exibidos para canônicos. Toda conversão de
posição passa pelo mapa. O caso comum (sem transformação) usa um mapa identidade
sem alocação. Ver [04](04-layout-paginacao.md) §1.1.

**Status:** aceita (2026-09-07).

### Emenda 7 à Decisão 8.2 — chave do cache inclui o CSS

**Problema.** A chave era `sha1(bytes da seção)`. Mas a IR depende também das
folhas de estilo aplicáveis: `display: none` remove conteúdo, `list-style` e
`text-transform` entram nos blocos e runs. Dois EPUBs com o mesmo XHTML e CSS
diferente colidiriam no cache e o segundo receberia a IR do primeiro.

**Emenda.** Chave = `hash(bytes da seção ‖ bytes de cada CSS aplicável, na ordem
da cascata) : IR_SCHEMA_VERSION`. O hash é FNV-1a 64 desde a P8. Ver
[08](08-concorrencia-cache.md) §4.1.

**Status:** aceita (2026-09-07).

### Emenda 8 à Decisão 7 — `EpubByteSource` separado de `EpubResourceProvider`

**Problema.** `EpubResourceProvider.read(href)` devolve um recurso inteiro por
nome. O leitor de ZIP lazy de [03](03-camada-a-ir.md) §2 precisa de leitura por
**faixa de bytes** do container. A interface não permitia a arquitetura de
acesso aleatório em que todo o desempenho de abertura se apoia.

**Emenda.** Duas interfaces em níveis diferentes. `EpubByteSource` entrega
`readRange(offset, length)` sobre o arquivo `.epub`; o ZIP do pacote consome isso.
`EpubResourceProvider` continua existindo para EPUBs já extraídos ou decifrados
por DRM externo, e é o nível em que um decorator de decriptação se encaixa. O app
fornece um ou outro. `EpubFontProvider` passa a ser opcional. Ver
[07](07-api-publica.md) §4.

**Status:** aceita (2026-09-07).

### Emenda 9 à Decisão 8.1 — agendador e worker

**Problema.** (a) `addPostFrameCallback` só dispara **depois de um frame**. Com o
app parado numa página, nenhum frame é agendado e a paginação em background
congela. (b) Isolates não existem em dart2js nem, até onde se sabe, em dart2wasm.
O desenho da Camada A "em isolate" contradiz a promessa de web de
[11](11-empacotamento-versionamento.md) §2.

**Emenda.** (a) O agendador usa `SchedulerBinding.scheduleTask` com
`Priority.idle` e um `Stopwatch` de orçamento, com fallback para `Timer.run`
entre fatias quando não há frame pendente. (b) A Camada A roda atrás de um
`EpubWorker` abstrato com duas implementações: `IsolateEpubWorker` e
`CooperativeEpubWorker`, esta última fatiando a Camada A por bloco no isolate
principal com o mesmo orçamento. O web usa a segunda. O spike S9 (Flutter
3.47.5) mostrou que o fatiamento vale para a caminhada no DOM e a construção da
IR, mas **não para o parse do `html`**, que é uma chamada atômica (~50 ms para
500 KB em release no Chrome): o primeiro checkpoint só existe depois dele. No
web, o parse precisa ser feito em pedaços ou fora do thread principal, e a
cessão entre fatias não pode ser por `Timer` (P10). Ver
[08](08-concorrencia-cache.md) §1 e §2.

**Status:** aceita (2026-09-07).

### Emenda 10 à Decisão 4.1 — paginação ancorada

**Problema.** [04](04-layout-paginacao.md) §2.3 pagina sempre a partir do início
da seção. Ao trocar o tamanho da fonte no fim de um capítulo de 200 mil palavras,
"restaurar pelo locator" exige shapear o capítulo inteiro até chegar ao offset. O
orçamento de 200 ms de [10](10-testes.md) §4.1 é inatingível nesse caso.

**Emenda.** A paginação de uma seção é definida a partir de um **âncora**
`(blockIndex, lineIndex)`. Por padrão, o âncora é o início da seção. Após uma
mudança de estilo ou viewport, o âncora passa a ser a linha que contém o
`charOffset` do locator atual: a página exibida começa nela, as páginas seguintes
são calculadas para frente e as anteriores para trás, preenchendo de baixo para
cima. O âncora é ajustado para a fronteira legal mais próxima antes da linha
pedida (no máximo 2 linhas, spike S8), para que a costura respeite órfã, viúva e
heading. A contagem total continua em background e difere da paginação a partir
do início em 0 ou +1 página, nunca −1 (500 casos, S8). Ver [04](04-layout-paginacao.md)
§3.1.

**Status:** aceita (2026-09-07).

### Emenda 11 — decisão de P1 (justificação e hifenização)

**Emenda.** A opção 3 ("justificar com limite de espaçamento") **não é
implementável** sobre `ui.Paragraph`: `TextAlign.justify` não expõe controle de
espaçamento máximo nem permite alinhamento diferente por linha dentro do mesmo
parágrafo. Restam as opções 1 e 2. Decisão: `textAlign` padrão é `start` na 1.0,
com `justify` disponível e documentado como "melhor com hifenização". Na 1.2,
hifenização Knuth-Liang inserindo **U+00AD (soft hyphen)** no texto exibido. O
`ui.Paragraph` quebra a linha no soft hyphen, mas **não pinta o hífen** (spike S5,
Flutter 3.44.1): a pintura é do motor, um `drawParagraph` de `"-"` pré-shapeado
no fim de cada linha hifenizada, sem relayout. Isso é exatamente o caso de uso da
Emenda 6. Ver [04](04-layout-paginacao.md) §8.

**Status:** aceita (2026-09-07).

### Emenda 12 — decisão de P2 (algoritmo de tabela)

**Emenda.** Layout automático simplificado: para cada célula, mede-se largura
mínima (`minIntrinsicWidth`) e máxima (`longestLine`) com **um** layout em
largura infinita; as colunas recebem a máxima quando cabe, senão distribuem o
excedente proporcionalmente acima da mínima. Se a soma das mínimas excede a
página, a tabela é escalada até o piso de 0.8× e, se ainda não couber, o bloco
ganha **rolagem horizontal própria** com diagnóstico `tableOverflow`. A linha é
a unidade de quebra entre páginas. O spike S4 (Flutter 3.47.5) corrigiu a
medição: o layout em largura zero quebra por glifo e não dá a palavra mais
longa. Corrigiu também o `colSpan`, que reparte só o déficit, e a escala, que é
uma transformação de pintura. Ver [04](04-layout-paginacao.md) §9.

**Status:** aceita (2026-09-07).

### Emenda 13 — SVG

**Problema.** A IR tem `ObjectKind.svg`, mas o Flutter não rasteriza SVG sem
dependência, e o núcleo não pode ter uma. Nada dizia o que acontece.

**Emenda.** Interface `EpubSvgRasterizer` injetável, opcional. Sem ela, SVG vira
placeholder com `alt` e diagnóstico `svgUnrasterized`. Caso especial tratado no
núcleo: SVG que é só um invólucro de imagem raster (`<svg><image href="capa.jpg"/>
</svg>`, padrão em capas) é desembrulhado e a imagem é renderizada diretamente.
Ver [05](05-render-selecao-a11y.md) §6.2.

**Status:** aceita (2026-09-07).

### Emenda 14 — notas de rodapé

**Emenda.** `noteRef` resolve via `anchors` para um bloco-alvo. O pacote expõe
`doc.resolveNote(Locator)` devolvendo o texto e os blocos do alvo (o `aside` com
`epub:type="footnote"`, ou o bloco que contém o `id`), e `onNoteTap(EpubNote)` no
widget. O popup é do app. Ver [06](06-locator-navegacao.md) §6.1.

**Status:** aceita (2026-09-07).

### Emenda 15 — tipos extensíveis e exceções

**Problema.** [11](11-empacotamento-versionamento.md) §3.3 sugeria classes
seladas para tipos que crescem. Em Dart 3, `sealed` é justamente o que torna o
`switch` exaustivo, então adicionar um subtipo quebra os consumidores da mesma
forma que adicionar um valor a um enum. Além disso, [02](02-modelo-de-estilo.md)
falava em `UnsupportedError` e [09](09-erros-diagnosticos.md) em
`EpubUnsupportedException`.

**Emenda.** Tipos que crescem (`EpubDiagnosticCode`) são classes `final` com
constantes estáticas e sem exaustividade. Tipos fechados por natureza
(`EpubFidelity`, `ReadingMode`, `EpubReadingDirection`) continuam enums. Modelos
públicos são `final class`. `EpubException` é `abstract base`, não `sealed`. A
exceção de fidelidade é `EpubUnsupportedException`, lançada na construção de
`EpubLayoutEngine`/`EpubReader`, não em `open`. Ver
[11](11-empacotamento-versionamento.md) §3.3 e [09](09-erros-diagnosticos.md) §2.

**Status:** aceita (2026-09-07).

## Decisões fechadas na revisão v0.3

| # | Assunto | Decisão | Data |
|---|---|---|---|
| P1 | Hifenização e justificação | `start` como padrão na 1.0; `justify` disponível; hifenização por U+00AD na 1.2 (Emenda 11). S5 valida | 2026-09-07 |
| P2 | Layout de tabela | Auto-layout min/max content, escala até 0.8×, depois rolagem horizontal declarada (Emenda 12). S4 validou (Flutter 3.47.5) com correções na medição (`layout(∞)` único), no `colSpan` (só o déficit) e na escala (`canvas.scale`) | 2026-09-07 |
| P3 | Nome do pacote | **`galley`**. Repositório `github.com/EduardoSA8006/galley` | 2026-09-07 |
| P4 | Paginação em isolate vs. orçamento por frame | Orçamento por frame no isolate principal. S1 confirmou a negativa em `Isolate.run` e `Isolate.spawn`: `UI actions are only available on root isolate` (Flutter 3.44.1) | 2026-09-07 |
| P5 | Separador de bloco | `\n` (U+000A) | 2026-09-07 |
| P6 | Licença | **MIT** (`LICENSE` no repositório) | 2026-09-09 |
| P8 | Hash da chave do cache | **FNV-1a 64** para chaves de cache e internas; SHA-1 próprio só para a chave IDPF. Motivo: S6 mediu SHA-1 em ~16 µs/KB, no caminho da abertura com cache quente. Confirmar em AOT na Fase 1 | 2026-09-09 |
| P10 | Web na 1.0 ou na 1.0.x | **Web na 1.0.x.** S9 (Flutter 3.47.5, Chromium 153): o parse do `html` é atômico e trava ~50 ms numa seção de 500 KB em release no Chrome; o resto fatia a 4 ms e custa ≈ 1,0–1,6× o isolate nativo. **Critério de entrada:** seção de 500 KB, parse incluído, build de release no Chrome (dart2js `-O4` e dart2wasm `-O2`), nenhuma fatia acima de 16 ms e p99 das fatias ≤ 8 ms. Falta: parse fatiável (três caminhos a medir na Fase 1: `parseFragment` em pedaços, tokenizer próprio ou Web Worker) e cessão por `MessageChannel` em vez de `Timer`. Ver [08](08-concorrencia-cache.md) §1 e §2 | 2026-09-25 |

## Decisões pendentes

| # | Assunto | Bloqueada por | Prazo |
|---|---|---|---|
| P7 | Inflate no web: implementação própria ou `archive` via import condicional | Tamanho do bundle, medido na Fase 1 | Fase 1 |
| P9 | Fixed-layout no núcleo ou em `galley_fixed_layout` | Corpus de fixed-layout | Antes da 1.1 |
