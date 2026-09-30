# 03 — Camada A: parse e IR do documento

**Decisão 3: lista plana de blocos com containers rasos.
Emenda 1: mapa de âncoras. Emenda 3: forma do texto canônico.
Emenda 4: idioma, direção e estrutura dos runs. Emenda 8: fonte de bytes.**

## 1. Pipeline

```
EpubByteSource (faixas de bytes do .epub)
  → leitor de ZIP (central directory, lazy)          §2
  → container.xml → OPF                              §3
  → META-INF/encryption.xml                          (ver 09 §4)
  → NAV / NCX → TOC, page-list                       §3
  → por seção do spine:
        bytes → decodificação                        §7
        → XHTML → DOM (pacote html)
        → cascata de CSS do subconjunto              §6
        → normalização de texto                      §5
        → blocos + runs + objetos + âncoras          §4
  → serialização binária → EpubCacheStore            (ver 08)
```

Tudo isso roda no `EpubWorker` ([08](08-concorrencia-cache.md) §1). Nenhuma
etapa toca `dart:ui`.

Ordem entre cascata e normalização: a cascata vem **antes** porque `display:
none` remove subárvores e `white-space` decide o colapso. A normalização precisa
saber os dois.

A cascata está em `lib/src/css/` (Fase 1, sub-projeto 3;
[spec do CSS](specs/2026-09-26-css-design.md)): o prólogo assíncrono da seção
junta as folhas (`loadSectionSheets`, com `@import` e um cache de folhas por
publicação) e a cascata (`computeStyles`, um gerador que cede a cada 4 096
passos) entrega ao IR um `SectionStyles` — o `ComputedStyle` de cada elemento,
com cascata, herança e propagação de `text-decoration` resolvidas. O IR só lê o
resultado; não refaz cascata.

## 2. Fonte de bytes e leitor de ZIP

### 2.1 `EpubByteSource` (Emenda 8)

```dart
abstract interface class EpubByteSource {
  Future<int> get length;
  Future<Uint8List> readRange(int offset, int length);
  Future<void> close();
}
```

Implementações padrão: `FileEpubByteSource` (sobre `RandomAccessFile`, atrás de
import condicional) e `MemoryEpubByteSource` (sobre `Uint8List`, para web e
testes). Um app pode implementar sobre HTTP com `Range` para leitura remota, e
isso é inteiramente problema dele.

### 2.2 Leitor de ZIP

Próprio, em `lib/src/container/zip/`. Toda a arquitetura repousa sobre acesso
aleatório lazy, e nenhum pacote existente entrega essa forma. Detalhes em
[specs/2026-09-25-container-design.md](specs/2026-09-25-container-design.md) §5.

- Lê o fim do arquivo (os últimos 65 577 bytes: o maior comentário do EOCD, o
  EOCD e o locator ZIP64) numa leitura e o **central directory** inteiro
  noutra, uma única vez na abertura, montando o índice por nome (exato e sem
  diferenciar maiúsculas)
- Suporta **ZIP64** para EOCD e central directory, porque arquivos acima de 4 GB
  são raros mas arquivos com mais de 65 535 entradas existem; percorre o
  central directory pelo tamanho, não pela contagem
- **Prefixo** (EPUB colado depois de outro arquivo): todos os offsets recebem o
  deslocamento, com diagnóstico `mimetypeIrregular` (`reason: prefix`)
- **Nomes:** com o bit 11, UTF-8 tolerante; sem ele, UTF-8 se válido, senão
  CP437. `\` vira `/`, `/` e `./` iniciais caem; diretórios ficam fora do índice
- **Duplicatas:** vence a primeira entrada do central directory; as outras
  emitem `zipDuplicateEntry`
- `fetch` faz **uma** ida à fonte (local header e dados); `decode()` é `sync*`,
  infla em fatias de 16 KiB e tem um passo a cada 64 KiB de saída
- **Nunca** carrega o arquivo inteiro em memória (medido no teste de corpus)
- `maxEntrySize` (256 MiB descomprimidos): entrada maior, ou saída maior que a
  declarada, é ilegível; proteção contra zip bomb
- **Dados sobrepostos:** o teto acima é só por entrada, então várias entradas
  do central directory apontando para o mesmo local header/stream deflate
  (zip bomb por sobreposição) também são cobertas: a partir da segunda, em
  ordem de `localHeaderOffset`, ficam inválidas
- Suporta `stored` (método 0) e `deflate` (método 8); qualquer outro método
  levanta `EpubContainerException` daquela entrada
- Do local file header só usa o tamanho do nome e do extra field, que precisa
  pular para achar os dados; tamanhos e CRC vêm sempre do central directory,
  inclusive com data descriptor
- **CRC-32 sempre verificado** durante o `decode()`: em produção, um CRC errado
  (ou saída curta) vira diagnóstico `zipCrcMismatch`; em `strict`
  ([09](09-erros-diagnosticos.md) §5), exceção

Nota: o `mimetype` deve ser a primeira entrada e não comprimido. Se não for,
emitimos diagnóstico mas seguimos, porque muitos arquivos reais violam isso.

## 3. Publicação

```dart
final class EpubPublication {             // interna: lib/src/publication/model.dart
  final String opfPath, version;
  final EpubMetadata metadata;            // pública (06 §5)
  final Map<String, ManifestItem> manifest; // por id, caminho resolvido, missing/remote
  final List<SpineItem> spine;            // doc.readingOrder no sub-projeto 6
  final List<NavPoint> toc;               // reconciliado (§3.1); EpubTocEntry no 6
  final List<NavPoint> pageList;          // NAV, senão NCX (06 §3); EpubPageMark no 6
  final List<NavPoint> landmarks;         // NAV, senão guide do OPF
  final String? coverPath;                // passos de pacote de 06 §5.1; coverHref no 6
  final String? navPath, ncxPath;         // documentos lidos (chave do livro, 08 §4.1)
  final EpubReadingDirection direction;   // page-progression-direction
  final EpubLayoutMode layout;            // reflowable | prePaginated
  final List<String> uniqueIdentifiers, identifiers; // chaves IDPF e Adobe (09 §4)
}
```

Implementada em `lib/src/publication/` (Fase 1, sub-projeto 2;
[spec](specs/2026-09-26-publication-design.md)): só o nível do pacote
(`container.xml`, OPF, NAV e NCX), sem abrir seção. Os tipos públicos com
`Locator` (`EpubTocEntry`, `EpubPageMark`) são montados pelo `EpubDocument`
no sub-projeto 6 a partir de `NavPoint`; `totalChars` (soma das seções, para
progresso) vem da IR, no sub-projeto 4.

### 3.1 Reconciliação NCX × spine

EPUBs reais têm navegação incompleta. Quando o NAV/NCX não cobre todos os itens
do spine:

1. Preserva a hierarquia da navegação para os itens que ela contém
2. Inclui itens órfãos do spine (com `linear` verdadeiro, `content` final
   local e presente, e sem entrada, em nenhum nível, que aponte para o item ou
   para o `content`) como entradas de nível raiz marcadas
   `synthesized`, logo depois da última entrada raiz, na ordem do TOC, cujo
   menor índice do spine (dela e dos descendentes) é anterior ao do órfão; sem
   nenhuma, no início; órfãos no mesmo ponto ficam na ordem do spine. O alvo
   é o `content.path` e o título, o nome desse arquivo sem extensão; o primeiro heading da seção fica como
   gancho para a IR (sub-projeto 4). Emite `tocReconciled` uma vez
3. A ordem de leitura vem **sempre** do spine, nunca do TOC
4. Itens com `linear="no"` ficam no spine (participam do progresso e podem ser
   alvo de link), mas são pulados por `next()`/`prev()` e marcados em
   `SpineItem.linear`

É o comportamento do Apple Books e dos leitores comerciais.

Quando NAV e NCX coexistem (EPUB3 com NCX de compatibilidade), o NAV vence.

### 3.2 Itens problemáticos

| Caso | Tratamento |
|---|---|
| `href` com separador do Windows (`\`) | Normalizado para `/` |
| `href` URL-encoded | Decodificado segmento a segmento; tentativa dupla (decodificado, depois cru); `%2e%2e` que sairia da raiz e `%2F` ficam crus |
| `href` relativo ao OPF em subpasta | Resolvido contra o diretório do OPF, depois normalizado (`..` colapsado); `..` além da raiz recusa o `href` |
| `href` recusado (esquema que não é `http:`/`https:`, fora da raiz, vazio) | Item `missing`, `resourceMissing` com `href: null` e `details: {id, raw}` |
| `href` `http:`/`https:` | Item `remote`; sem diagnóstico fora do spine; quando o `content` final de um item do spine é remoto (sem `fallback` local), `resourceMissing` com `href` = a URL e `details: {id, reason: 'remote'}` |
| Diferença de caixa entre manifest e ZIP | Segunda tentativa case-insensitive, com diagnóstico `pathCaseMismatch` |
| Item do manifest sem arquivo no ZIP | Item `missing` com `resourceMissing` (`href` = caminho); seção de placeholder na IR |
| Item só-imagem no spine (`image/*` no media-type) | Seção com um único `Block(kind: object)` |
| Item com media-type não renderizável (PDF, áudio) | Segue a cadeia de `fallback` (até 16 passos, com detecção de ciclo) até um XHTML ou imagem existente; sem ela, seção de placeholder com o nome e o tipo e `unsupportedMediaType` (`href` = caminho) |
| Spine vazio | `EpubPackageException` (fatal) |
| `idref` do spine sem item no manifest | Item ignorado, diagnóstico `spineItemUnresolved` (`href` = OPF) |
| `idref` ou caminho repetido no spine | Vale o primeiro, diagnóstico `spineItemDuplicate` (`href` = OPF) |

## 4. A IR

```dart
final class Section {
  final String href;
  final String? lang;                // xml:lang / lang do <html>, BCP 47
  final String canonicalText;        // NFC, whitespace colapsado, §5
  final List<Block> blocks;          // ordem de leitura
  final List<LinkTarget> links;      // alvos de runs com attr link/noteRef
  final Map<String, int> anchors;    // id do documento → offset (Emenda 1)
  final int totalChars;              // == canonicalText.length
  final List<EpubDiagnostic> diagnostics;
}

final class Block {
  final BlockKind kind;
  final ContainerKind? container;    // só quando kind == container
  final int level;                   // heading 1..6, ou profundidade de lista
  final int textStart, textEnd;      // range em Section.canonicalText, §5
  final String? lang;                // só quando difere da seção
  final TextDirection? dir;          // só quando explícito (dir=, direction:)
  final List<StyleRun> runs;         // segmentos não sobrepostos, cobrem o range
  final List<InlineObject> objects;
  final BreakHint breakBefore, breakAfter;   // page-break-*/break-* (Classe 1)

  // container
  final List<Block>? children;

  // lista (container list) e item (listItem)
  final ListMarker? marker;          // disc, circle, square, decimal, lowerAlpha, ...
  final int? start;                  // valor inicial do <ol>
  final int? ordinal;                // número do item já resolvido

  // célula (tableCell)
  final int colSpan, rowSpan;        // padrão 1
  final bool isHeaderCell;           // th

  // objeto em bloco
  final InlineObject? object;        // só quando kind == object
}

enum BlockKind {
  paragraph, heading, listItem, tableCell, verse, code, caption,
  object,                            // imagem/svg em nível de bloco
  sceneBreak,                        // <hr>
  container,                         // ver ContainerKind
  placeholder,                       // recurso ausente ou seção que falhou
}

enum ContainerKind {
  table, tableRow, list, blockquote, figure,
  aside,                             // notas, sidebars (epub:type)
  generic,                           // div/section que precisou de agrupamento
}

final class StyleRun {
  final int start, end;              // absolutos em canonicalText
  final int attrs;                   // bitmask de InlineAttr
  final int linkIndex;               // índice em Section.links, ou -1
}

/// Valores são bits. Um run pode ter vários.
abstract final class InlineAttr {
  static const emphasis      = 1 << 0;
  static const strong        = 1 << 1;
  static const code          = 1 << 2;
  static const superscript   = 1 << 3;
  static const subscript     = 1 << 4;
  static const link          = 1 << 5;   // destino em Section.links[linkIndex]
  static const noteRef       = 1 << 6;   // idem; alvo é interno
  static const smallCaps     = 1 << 7;
  static const strikethrough = 1 << 8;
  static const underline     = 1 << 9;
  static const uppercase     = 1 << 10;  // text-transform (ver 04 §1.1)
  static const lowercase     = 1 << 11;
  static const capitalize    = 1 << 12;
  static const sizeSmaller   = 1 << 13;  // font-size relativo < 1, clamp em 04
  static const sizeLarger    = 1 << 14;  // font-size relativo > 1
  static const preserveSpace = 1 << 15;  // white-space: pre dentro de bloco normal
}

final class LinkTarget {
  final String href;                 // externo: URI completa; interno: href da seção
  final String? fragment;            // #id, resolvido via anchors da seção alvo
  final bool isExternal;
}

final class InlineObject {
  final int offset;                  // posição do U+FFFC em canonicalText (§5)
  final ObjectKind kind;             // image, svg, mathFallback
  final String href;
  final double? intrinsicWidth, intrinsicHeight;
  final String? alt;                 // usado na semântica (ver 05)
  final String? title;
}
```

Sobre `sizeSmaller`/`sizeLarger`: a Camada A **não** guarda o fator numérico do
publisher, porque isso é quase um `TextStyle`. Guarda só a direção, e a Camada B
aplica os fatores fixos do motor (`0.85` e `1.25`). Se um dia o perfil `faithful`
precisar do fator exato, ele entra como campo novo com bump de
`IR_SCHEMA_VERSION`.

### 4.1 Por que plana

- **Offset de caractere é índice direto.** Locator, busca, destaque, progresso e
  âncoras falam a mesma unidade, sem travessia de árvore.
- **Um bloco folha mapeia 1:1 em um `ui.Paragraph`**, que é exatamente a chave do
  cache de shaping.
- **Serialização minúscula:** uma string e alguns arrays de inteiros.
- **Blocos guardam ranges, não cópias.** Sem duplicação, e todo offset já é global
  à seção.

Estruturas de fato aninhadas (tabela com parágrafos em células, lista de lista,
blockquote com vários parágrafos) viram blocos **container** com `children`.
Árvore rasa de containers, folhas planas. A profundidade real de EPUBs de
editora raramente passa de 4; o parser **achata** `div` e `section` que não
carregam semântica (sem `epub:type`, sem `display` especial, sem borda), o que é a
maioria.

Tabela: `container(table)` → `container(tableRow)` → `tableCell`. Célula com
mais de um parágrafo vira `tableCell` com `children`. `thead`/`tbody`/`tfoot`
são achatados; `th` marca `isHeaderCell`.

### 4.2 A regra que sustenta o cache

> Os `runs` guardam **atributos semânticos**, nunca `TextStyle` resolvido.

É isso que mantém a Camada A independente de preferência e faz o cache em disco
valer para sempre. Se um dia um `TextStyle` vazar para dentro da Camada A, o
cache em disco perde a validade e a promessa de desempenho cai.

### 4.3 Runs como segmentos (Emenda 4)

Os runs de um bloco **particionam** `[textStart, textEnd)`: não se sobrepõem, não
deixam lacuna, e o primeiro começa em `textStart`. Um trecho em itálico dentro de
um link vira dois ou três segmentos com bitmasks diferentes. Consequências:

- A Camada B faz uma passada linear e emite um `ui.TextStyle` por segmento, sem
  resolver sobreposição
- A serialização é um array de `(end u32, attrs u16, linkIndex i16)`; o `start`
  é implícito
- Um bloco sem formatação tem exatamente um run

### 4.4 Mapa de âncoras

`anchors` é o que faz TOC, links internos e notas de rodapé funcionarem. Cada
`id` presente no XHTML entra no mapa apontando para o offset do primeiro
caractere do elemento correspondente. Para elementos vazios ou sem texto (um
`<a id="x"/>` de ancoragem, um `<span id="pg214"/>` de `page-list`), o offset é
o do próximo caractere emitido.

Consumo: `EpubTocEntry` com `href: "cap03.xhtml#secao2"` resolve para
`Locator(href: "cap03.xhtml", charOffset: anchors["secao2"])`.

Quando o `id` não existe no mapa, o locator aponta para o início da seção e um
diagnóstico é emitido.

## 5. Forma canônica do texto (Emenda 3)

`canonicalText` é a **única fonte de verdade de offsets** em todo o sistema.

- Normalização Unicode **NFC**
- Whitespace colapsado segundo `white-space: normal`, exceto dentro de `pre`,
  `code` em bloco e versos, onde é preservado (e o run recebe `preserveSpace`)
- Entidades HTML resolvidas; `&nbsp;` vira U+00A0 e **não** colapsa
- **Cada bloco folha termina com um `\n`** que pertence ao seu range. Os ranges
  dos blocos folha de uma seção, em ordem, particionam `[0, totalChars)`. Um
  container não tem texto próprio; seu range é a união dos filhos
- **Cada `InlineObject` ocupa um U+FFFC** em `canonicalText`, no seu `offset`. Um
  bloco `object` tem texto igual a `"￼\n"`
- `sceneBreak` tem texto igual a `"\n"`
- Sem caracteres de controle além de `\n` (o separador e as quebras internas de
  `pre`) e dos formatadores bidi (U+200E, U+200F, U+202A–U+202E, U+2066–U+2069),
  que são mantidos porque alteram a renderização
- Espaço de largura zero (U+200B) e soft hyphen (U+00AD) presentes no **fonte**
  são mantidos, porque são intenção do autor sobre onde quebrar

Por que `\n` e não nada (v0.2): sem separador, a Camada 3 entregava
`"...aberta.Capítulo 2"`, que qualquer tokenizador lê como uma palavra. Por que
`\n` e não U+2029: é o que `split`, FTS5 e expressões regulares com `^`/`$`
esperam (P5 em [01](01-decisoes.md)).

Por que U+FFFC: é o mesmo caractere que o Flutter usa para `PlaceholderSpan`, e
torna "selecionar até depois da imagem" um offset distinto de "até antes". A
Camada B monta o `ui.Paragraph` com `addPlaceholder` exatamente nessa posição.

Essa disciplina é o que faz o locator sobreviver a mudanças no próprio pipeline
de parse ([06-locator-navegacao.md](06-locator-navegacao.md) §4).

### 5.1 Texto que muda ao exibir

`text-transform` e hifenização alteram a string exibida, **não** a canônica. A
Camada A registra a intenção (`uppercase`, `lowercase`, `capitalize` no bitmask);
a Camada B aplica e mantém um mapa de offsets ([04](04-layout-paginacao.md)
§1.1). Assim, `canonicalText` segue sendo o texto do autor, que é o que busca e
TTS querem.

## 6. Subconjunto de CSS suportado

Só o que a Classe 1 e a Classe 2 exigem
([02-modelo-de-estilo.md](02-modelo-de-estilo.md)). Implementado em
`lib/src/css/` (Fase 1, sub-projeto 3); a tabela completa de valores,
mapeamentos e limites está na [spec do CSS](specs/2026-09-26-css-design.md)
§7, e este é o resumo.

**Suportado.** "Registrado" quer dizer: o valor entra no `ComputedStyle` com a
classe dele, e quem decide se é honrado é a Camada B, pelo perfil
([02](02-modelo-de-estilo.md) §3.1). Na Classe 1: `display` (`inline-*` →
inline; `flex`, `grid`, `flow-root` e `table*` → block, sem "blocoficar" os
filhos; list-item; none), `white-space`, `direction`, `vertical-align` (só
sup/sub distinguidos), `list-style-type` e o atalho `list-style`, `break-*` e
`page-break-*` (a mesma propriedade), `width`/`height` em `em` ou `%`
(limitados a [0, 100]). Na Classe 2: `text-align` (a palavra herdada;
`justify` vira `start`), `text-decoration` (sublinhado e riscado,
**propagados** aos descendentes, alimentando `InlineAttr.underline` e
`InlineAttr.strikethrough`), `font-style`, `font-weight` (peso numérico, com
`bolder`/`lighter` do CSS Fonts 4), `font-variant` (small-caps),
`text-transform`, `font-size` relativo (só a direção, o `CssFontSizeStep` que
`sizeSmaller`/`sizeLarger` de §4 já guardam), `margin`, `padding` e
`text-indent` em `em` (`px`, `pt` e `cm` convertidos com 16px = 1em, `%` sobre
30em, limitados).

**Reconhecido e reportado como degradação** (`unsupportedLayout` quando o
valor vence a cascata num elemento): `float`, `columns`/`column-count`/
`column-width`, `writing-mode` (e `-epub-`/`-webkit-`), `position` (exceto
`static`/`relative`). Pseudo-elementos, inclusive `::first-letter`, caem com
`cssRuleIgnored`. `@media`: as regras dentro valem quando a lista de media é
vazia ou quando alguma query é `screen`, `all`, `only screen` ou `only all`,
sem condição, ou `not <tipo>` com um tipo que não é `screen`/`all` (sem
caixa, como no Media Queries); caso contrário, são ignoradas com
`stylesheetMediaIgnored` ([spec do CSS](specs/2026-09-26-css-design.md) §5).

**Ignorado em silêncio:** cor, fundo, família, tamanho absoluto, entrelinha,
borda, sombra, propriedades lógicas (`margin-inline-*`), `@font-face` e as
demais at-rules (no perfil `uniform`).

Seletores: tipo, classe, id, universal, descendente, filho (`>`), irmão
adjacente (`+`), atributo por igualdade (`[epub|type="noteref"]`, com o
prefixo declarado por `@namespace`, casado com o atributo literal
`epub:type`), pseudo-classes `:first-child`,
`:last-child` e `:nth-child(n)` com argumento inteiro. Especificidade do
Selectors 4, com `!important`, `style=""` anexado e ordem de fonte como
desempate. Numa lista de seletores, um seletor inválido derruba a regra
inteira, como no CSS; um válido fora do subconjunto (`:not()`, `~`, `:nth-*`
com fórmula, `:has()`, `[attr]`) cai sozinho, com `cssRuleIgnored`, e os
outros continuam.

Fontes de CSS, na ordem da cascata: a folha padrão do HTML recortada, com as
dicas `hidden` e `dir` ([spec do CSS](specs/2026-09-26-css-design.md) §8);
depois `<link rel="stylesheet">` e `<style>` na ordem do documento (inclusive o
`<style>` de SVG inline, e não os de `<template>`), cada folha precedida dos
seus `@import` (relativos à folha que importa, com tetos de profundidade,
número e tamanho); por fim o atributo `style=""`, que vence qualquer seletor
da mesma camada.

## 7. Encoding

Ordem de tentativa: BOM → declaração XML → `<meta charset>` → UTF-8 →
heurística (Latin-1, Windows-1252, Shift-JIS).

Falha de decodificação **nunca** derruba a seção: caracteres inválidos viram
U+FFFD e um `EpubDiagnostic.encodingFallback` é emitido com o encoding usado.

## 8. Parse do XHTML com o pacote `html`

O pacote `html` parseia como HTML5, não como XML. Consequências que o parser da
Camada A precisa conhecer:

- Atributos com namespace chegam com o nome literal: `epub:type`, `xml:lang`.
  O parser procura por essas strings
- Elementos auto-fechados de XHTML (`<div/>`) são interpretados como abertos e
  fechados no lugar certo na maioria dos casos; o corpus precisa de um caso com
  `<a id="x"/>` seguido de texto para garantir que a âncora não engole o texto
- Entidades definidas em DTD externa (raras em EPUB) não são resolvidas; ficam
  como texto literal e emitem diagnóstico `unknownEntity`
- `<![CDATA[...]]>` dentro de `<style>` é tratado como conteúdo do estilo
- `html.parse` é uma chamada atômica sobre a string inteira: não há onde pôr um
  checkpoint dentro dela, e isso decide o web ([08](08-concorrencia-cache.md) §1)
- A caminhada no DOM itera `el.nodes`, **nunca** indexa `el.children`. Este é uma
  `FilteredElementList` cujo `length` e `operator []` refazem
  `nodes.whereType<Element>().toList()` a cada acesso. Indexado em laço, fica
  O(n²): o spike S9 mediu 680 ms para 500 KB e 33 s para 3 MB, contra 27 ms e
  172 ms iterando `nodes`

A tolerância a HTML malformado é a razão da escolha. Um parser XML estrito
rejeitaria uma fração relevante do acervo real.
