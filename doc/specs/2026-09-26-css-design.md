# CSS (Fase 1, sub-projeto 3) — design

**Data:** 2026-09-26. **Estado:** aprovada e implementada (plano em
`doc/plans/2026-09-26-css.md`; escrita a partir do desenho em cinco seções
aprovado pelo usuário, `.superpowers/sdd/2026-09-26-css/design-aprovado.md`;
o que o desenho deixou para a spec fechar está marcado **(decisão da spec)**
no texto e reunido em §1.4).
**Branch:** `fase1/css`.

## 1. Objetivo

Terceiro dos seis sub-projetos da Fase 1 ([13](../13-riscos-spikes-fases.md) §2).
A partir do DOM de uma seção (`package:html`), do caminho dela e do
`EpubContainer` (sub-projeto 1), produz o **estilo computado** de cada
elemento: cascata e herança resolvidas, só as propriedades da tabela de §7,
classificadas nas três classes de [02](../02-modelo-de-estilo.md) §2. Junto,
a lista ordenada das folhas aplicadas, que é o que
[08](../08-concorrencia-cache.md) §4.1 precisa para a chave do cache. O IR
(sub-projeto 4) só lê o resultado.

**Critério de sucesso:** o teste de corpus de §14.1 passa nos 68 EPUBs (os 65
de hoje e os três casos novos de §14.1); nenhum CSS, `style=""` ou DOM hostil
produz exceção fora da taxonomia `EpubException` (fuzz de §14.2) nem tempo
superlinear no tamanho da entrada (testes hostis de §14.3, com teto de
tempo); o CSS nunca é fatal.

### 1.1 Decisões tomadas no brainstorming

- **Entrega ao IR: estilo computado**, por elemento, só com as propriedades da
  tabela, classificado nas três classes. O IR não refaz cascata.
- **`@import` é seguido, com limites:** relativo à folha que importa, lido pelo
  contêiner, na posição certa da cascata; profundidade, total de folhas e
  tamanho limitados; ciclo e excesso viram diagnóstico; `@import` com media
  fora de `screen`/`all` é ignorado.
- **`margin`, `padding` e `text-indent` relativos em `em`:** `em` e `%`
  passam (`%` sobre uma largura aproximada), `px`/`pt`/`cm` são convertidos
  com a base fixa 16px = 1em, e a faixa é limitada.
- **Abordagem A:** tokenizador próprio (CSS Syntax Level 3 recortado) e índice
  de regras pela parte mais à direita do seletor. Rejeitadas: B (parser por
  `split` e casamento ingênuo, O(elementos × regras), recuperação de erro
  frágil) e C (autômato de seletores, cujo ganho não paga a complexidade).
- **DOM do `package:html`**, como o NAV; o casamento é feito direto sobre
  `Element`, sem interface própria. Se o sub-projeto 4 decidir outra coisa, isto
  muda.
- **Intenção do usuário** (tamanho, família) é da Camada B, na Fase 2: o CSS
  entrega só o que o livro pede, classificado.
- **API pública:** nada muda; tudo é interno até o sub-projeto 6.
- A preferência global por feature-first, MVVM, Result e Riverpod não se aplica
  ao galley ([11](../11-empacotamento-versionamento.md) §4, erros por exceção e
  diagnóstico de [09](../09-erros-diagnosticos.md)).

### 1.2 Fora do escopo

`@font-face` e fontes do livro (perfil `faithful`, v2.0); `:not()`, `~`,
`:nth-*` com fórmula e `:has()` ([03](../03-camada-a-ir.md) §6);
pseudo-elementos, inclusive `::first-letter` (degradação declarada por
`cssRuleIgnored`); aplicação da intenção do usuário e a Camada B (Fase 2); o IR
(sub-projeto 4), inclusive a decodificação e o parse do XHTML da seção;
`<?xml-stylesheet?>`; a subárvore de `<template>` (conteúdo inerte no HTML:
não fornece folha nem recebe estilo, §9.1, §10.2); a folha de estilo implícita
de `align`, `bgcolor` e outros atributos de apresentação do HTML, fora `hidden`
e `dir` (§8.2); o worker e o cache em disco (sub-projeto 5), dos quais aqui só sai a lista de
folhas para a chave.

### 1.3 Pendências do doc/14 endereçadas a este sub-projeto

Nenhuma linha de [14](../14-pendencias.md) é do CSS. Duas tocam nele e seguem
abertas, com o dono de hoje:

| Pendência | Destino |
|---|---|
| Tamanho do pacote no web (inflate, SHA-1, CSS), teto de 300 KB minificado | Continua na Fase 1; o CSS não adiciona dependência, e a medição fica para quando o web entrar no CI |
| Proteção do parse do XHTML de conteúdo contra o `package:html` (referência numérica fora de faixa, nomes longos, aninhamento) | Continua com os sub-projetos 4 e 6: o CSS recebe o `Document` pronto e não chama `html.parse`; os testes hostis de §14.3 montam o DOM profundo por código |

### 1.4 Decisões desta spec

Tudo o que o desenho deixou em aberto e esta spec fechou, com a justificativa
no ponto indicado. As marcadas **(controlador)** vieram da revisão
independente da spec e das respostas do controlador às dúvidas; as que mudam a
letra do desenho aprovado estão marcadas **(muda o desenho)**.

| # | Decisão | Onde |
|---|---|---|
| 1 | O `emit` do CSS usa `onStrict: EpubSectionParseException`, criada agora em `exceptions.dart` (interna até o sub-projeto 6) **(controlador)** | §12.3 |
| 2 | `unsupportedLayout` entra no código agora (está em doc/09 e no `knownDiagnostics`, mas não em `EpubDiagnosticCode`), continua `warning`, e é emitido quando a declaração degradada **vence a cascata** num elemento, uma vez por (seção, propriedade) | §10.7 |
| 3 | `text-align` guarda internamente a palavra computada (`left`, `right`, `start`, `end`, `center`) para herdar como o CSS herda, e expõe `start`/`center`/`end` resolvido pela direção do próprio elemento | §3, §7 |
| 4 | `font-weight` guarda o peso numérico (1–1000, fracionário, #45) para `bolder`/`lighter` seguirem a tabela do CSS Fonts, e expõe `normal`/`bold` (≥ 600) | §3, §7 |
| 5 | `rem` conta como `em`; `ex` e `ch` como 0,5em (o valor que o CSS Values manda assumir sem métrica de fonte); `vw`, `vh`, `calc()`, `var()` e demais descartam a declaração | §7.2 |
| 6 | `width`/`height` convertidos como as margens e limitados a [0, 100] em `em` e em `%` | §7.1 |
| 7 | Tamanho de fonte absoluto (px, pt, palavras-chave) descarta a declaração; `initial`/`unset` em `font-size` dão `same` | §7.1 |
| 8 | Tipo de lista desconhecido resolve no elemento onde a declaração vale: `decimal` se ele é `ol` ou `li` filho de `ol`, senão `disc` | §7.1 |
| 9 | Dicas de apresentação `hidden` e `dir` entram como declarações da origem da folha padrão com especificidade (0,1,0), porque o subconjunto de seletores não tem presença de atributo nem comparação sem caixa | §8.2 |
| 10 | `rp` não é escondido (o galley achata o ruby, [09](../09-erros-diagnosticos.md) §3 `rubyFlattened`, e `rp` existe para quem não tem ruby) | §8.1 |
| 11 | Seletor de atributo com prefixo (`[epub|type="x"]`) casa o atributo literal `epub:type`; `@namespace` só serve para declarar o prefixo (#41) | §6.1 |
| 12 | Lista de seletores: um seletor **inválido** pela gramática (inclusive pseudo-classe ou pseudo-elemento fora da lista fechada de §6.3) descarta a regra inteira, como no CSS; um seletor **válido fora do subconjunto** cai sozinho, com `cssRuleIgnored`, e os outros da lista continuam valendo **(controlador; muda o desenho)** | §6.3 |
| 13 | Teto novo de 4 MiB de CSS por seção, somando `PendingResource.size` das folhas de arquivo antes do `decode()`, além do teto de 1 MiB por folha; `<style>` tem teto próprio em unidades de código (o texto de `<style>` também conta, #39) | §9.3, §11 |
| 14 | O limite de 20 000 regras conta seletores (entradas do índice), não blocos | §11 |
| 15 | Cache de folhas parseadas por caminho e por texto de `<style>`, LRU com teto de 8 Mi unidades de código de fonte, com entradas negativas (ausente, grande demais, ilegível); a entrada guarda só o que o **CSS** emite (o `encodingFallback` de `decodeCss`, os `CssIssue`, a falta), reemitido no sink da seção a cada seção que aplica a folha | §9.6 |
| 16 | Diagnósticos de parse agregados por folha: no máximo um `cssRuleIgnored` por motivo e um `stylesheetMediaIgnored` por folha e por seção, com `details.discarded` | §12.1 |
| 17 | Elemento abaixo da profundidade 256 recebe o estilo "herdado puro" do pai (herdadas copiadas, não herdadas no valor inicial), sem casar regras **(muda o desenho)** | §10.2 |
| 18 | Esgotado o orçamento, a folha padrão, as dicas e o `style=""` continuam valendo (nenhum é casamento de seletor do livro, e o custo deles por elemento é constante) **(muda o desenho)** | §10.6 |
| 19 | A lista de folhas para a chave leva o hash FNV-1a 64 dos bytes de cada arquivo (em `lib/src/container/fnv1a64.dart`, exato na VM e no JS) e o texto de cada `<style>` | §9.7 |
| 20 | `computeStyles` escreve o resultado num `CascadeResult` passado pelo chamador (o gerador `sync*` só cede `void`), e tem a variante `computeStylesSync` | §10.1 |
| 21 | `recordOrigins` (só testes): `SectionStyles.originOf` diz a origem da declaração vencedora, para o corpus checar "itálico salvo sobrescrita" | §10.1, §14.1 |
| 22 | O texto de `<style>` é lido como dado de caractere do XML: seções CDATA ficam literais e, fora delas, as entidades predefinidas e as referências numéricas são decodificadas (o `package:html` trata `<style>` como texto cru e deixaria `div &gt; p` literal); exceção: `<!-- -->` não é tirado como comentário, fica para o tokenizador do CSS, como no HTML (§7.5) | §9.1 |
| 23 | O parse das folhas roda no prólogo assíncrono do loader, sem ceder; se o sub-projeto 5 medir fatia acima do tolerado, vira `sync*` | §9.5, [14](../14-pendencias.md) |
| 24 | `text-decoration` entra na Classe 2, com `underline` e `lineThrough` (o resto ignorado), pela **propagação** do CSS, que não é herança **(controlador; muda o desenho)** | §3, §7.1, §8.1, §10.5 |
| 25 | `media` que não casa ganha código próprio, `stylesheetMediaIgnored` (`info`), fora dos motivos de `stylesheetIgnored`, que fica sempre `warning` **(controlador; muda o desenho)** | §12.1 |
| 26 | `text-align` vai para a Classe 2, tipografia relativa, como em [02](../02-modelo-de-estilo.md) §2 e §3.1; valores e mapeamento não mudam **(controlador; muda o desenho, que o punha em estrutura)** | §3, §7.1 |
| 27 | O orçamento conta cada consulta a balde, cada candidato considerado (inclusive os rejeitados pelo Bloom), cada seletor simples testado e cada declaração aplicada; composto com mais de 32 seletores simples fica fora do subconjunto **(controlador)** | §6.3, §10.6 |
| 28 | Teto de 256 tentativas de folha por seção (`<link>` e `@import`, achadas ou não); o teto de 64 folhas conta `<link>`, `<style>` e `@import`; profundidade, teto e ciclo são checados pelo caminho normalizado antes do `fetch` **(controlador)** | §9.5 |
| 29 | Recuperação de erro pelo modelo atual do CSS Syntax ("consume a block's contents"): regra e at-rule aninhadas são parseadas e descartadas com `cssRuleIgnored` `nested-rule` **(controlador)** | §5.3 |
| 30 | `mediaMatches` recebe tokens; `not <tipo>` com tipo que não é `all`/`screen` casa (como no navegador); vírgula dentro de parênteses não separa queries | §5 |
| 31 | O elemento em andamento quando o orçamento acaba recomeça só com a folha padrão, as dicas e o `style=""`, como os seguintes | §10.6 |
| 32 | O loader recebe o sink **da seção** (onde emite) e o sink **do contêiner** (parâmetro `containerSink`: o `EpubContainer` não expõe o dele); a exceção de `strict` que atravessa `fetch`/`decode()` é reconhecida por `identical(e, containerSink.lastStrictException)`; os diagnósticos do contêiner ficam no sink dele, uma vez por publicação, sem reemissão; `decodeCss` emite num sink temporário, cuja lista vai para a entrada do cache (sem `DiagnosticSink.capture`) **(controlador)** | §9, §9.6 |
| 33 | A subárvore de `<template>` fica fora da coleta e da cascata **(muda o desenho, que pedia todos os elementos no mapa)** | §9.1, §10.2 |
| 34 | Identificador (tipo, classe, `id`, nome de atributo) e valor de atributo no seletor com no máximo 256 unidades de código; acima disso, o seletor fica fora do subconjunto. Do lado do elemento, hash e minúsculas de cada classe, do `id` e do nome saem uma vez, ao montar o `ElementInfo` **(controlador)** | §6.3, §10.2, §10.4 |
| 35 | A tentativa de declaração para no ponto em que a falha já é certa (sem `ident` ou sem `:`; primeiro `{}` de topo depois de outro conteúdo; primeiro token depois de um `{}` inicial), com o mesmo resultado do algoritmo do CSS Syntax, que varre até o `;` antes de decidir e fica quadrático **(controlador)** | §5.3 |
| 36 | O teto de 64 folhas é reservado no `tentar`, antes do `fetch` e da recursão, e devolvido se a folha falta: numa cadeia de `@import` a lista não passa de 64 **(controlador)** | §9.5 |
| 37 | `@import` com `layer`/`supports()` vai para `stylesheetIgnored` com `reason: 'unsupported-import'`, não para `stylesheetMediaIgnored` **(controlador)** | §5.2, §12.1 |
| 38 | Orçamento da cascata de 2^22 passos (era 2^24): o maior uso real no corpus é 71 525 (`song-of-myself.xhtml`), e o pior caso cai para ~0,2 s por seção no desktop **(revisão do plano)** | §10.1, §10.6, §11 |
| 39 | O texto de `<style>` conta no teto de 4 MiB por seção, com `limit` `bytes` **(revisão do plano)** | §9.3, §11 |
| 40 | O `circle`/`square` das listas aninhadas do HTML §15.3.8 (com `dir`) sai do nível de lista herdado, não de seletores descendentes na folha padrão, que não tem combinador nenhum: a folha padrão não sobe ancestrais **(revisão do plano)** | §8.1, §8.2, §10.2 |
| 41 | Prefixo de namespace no seletor (`[epub|type]`, `svg|rect`) só vale se declarado por `@namespace` em posição na folha; não declarado, o seletor é inválido, como no Chromium **(revisão do plano; muda #11)** | §5.1, §6.1, §6.3 |
| 42 | Nada vem depois de um pseudo-elemento (exceto `::marker` depois de `::before`/`::after`): nem pseudo-classe, nem combinador; `:not()` e o `of` do `:nth-child` são validados como lista de seletores, e `:not()` não aceita pseudo-elemento; `:has()`, `:lang()` e `:dir()` vazios são inválidos; `:is()`/`:where()` são tolerantes **(revisão do plano)** | §6.3 |
| 43 | A especificidade conta cada seletor simples, com repetição (`#a#a` é (2,0,0)); `#a#b` e dois `:nth-child` diferentes ficam no subconjunto e nunca casam **(revisão do plano)** | §6.2, §6.3 |
| 44 | At-rules que o navegador não conhece (`@-moz-document`, `@document`, `@viewport`, `@-ms-viewport`, `@-moz-keyframes`) não tiram o `@import` seguinte de posição **(revisão do plano)** | §5.1, §5.2 |
| 45 | `text-decoration` (atalho) aceita cada componente no máximo uma vez e só palavras conhecidas (cores com nome e de sistema incluídas): `foo` e `red blue` descartam; `oblique <ângulo>` só entre −90° e 90°; o peso é fracionário (349,5 + `bolder` = 400) **(revisão do plano)** | §3, §7.1 |
| 46 | No corpus, só `unsupportedLayout` e `stylesheetIgnored` do `.expected` tiram o caso do `strict` e dão a segunda passada **(revisão do plano)** | §14.1 |
| 47 | O `type` do `<style>` só vale ausente, vazio ou exatamente `text/css` (sem caixa), como no HTML e no Chromium; o do `<link>` segue aceitando parâmetro e espaço **(revisão da Tarefa 8)** | §9.1 |
| 48 | No cache de folhas, toda entrada, inclusive a negativa, pesa a chave mais o que guarda (no ilegível, o texto da exceção), para o LRU expulsar faltas de caminho longo **(revisão da Tarefa 8)** | §9.6 |

## 2. Arquivos

| Caminho | Papel |
|---|---|
| `lib/src/css/tokenizer.dart` | `CssTokenizer`, `CssToken`, `CssTokenType` (§4) |
| `lib/src/css/parser.dart` | `parseStyleSheet`, `parseStyleAttribute`, `StyleSheet`, `StyleRule`, `CssImport`, `CssIssue`, `mediaMatches` (§5) |
| `lib/src/css/selector.dart` | `parseSelectorList`, `Selector`, `CompoundSelector`, `CssCombinator`, `CssAttributeTest`, especificidade (§6) |
| `lib/src/css/properties.dart` | `CssProperty`, `StyleClass`, `Declaration`, `CssValue` e subtipos, `parseDeclaration` (expansão de `margin`, `padding`, `font`, `list-style`, `columns`, `text-decoration`) (§7) |
| `lib/src/css/ua_sheet.dart` | `userAgentCss` (texto), `userAgentSheet` (parseada uma vez) (§8) |
| `lib/src/css/loader.dart` | `loadSectionSheets`, `decodeCss`, `StyleSheetCache`, `SectionSheets`, `AppliedSheet`, `SheetRef`, `SheetSource` (§9) |
| `lib/src/css/rule_index.dart` | `RuleIndex`, `RuleEntry`, `CssOrigin` (§10.3) |
| `lib/src/css/cascade.dart` | `computeStyles`, `computeStylesSync`, `CascadeResult`, `SectionStyles` (§10) |
| `lib/src/css/computed_style.dart` | `ComputedStyle`, `EmEdges`, `CssLength` e os enums de §3 |
| `lib/src/container/fnv1a64.dart` | `Fnv1a64` (§9.7) |
| `lib/src/diagnostics/diagnostic.dart` | + `unsupportedLayout`, `stylesheetIgnored`, `stylesheetMediaIgnored`, `cssRuleIgnored` (§12) |
| `lib/src/diagnostics/exceptions.dart` | + `EpubSectionParseException` (§12.3) |

Testes em `test/css/` (§14) e `test/container/fnv1a64_test.dart`.
`lib/src/css/` não importa `dart:io`, `dart:ui` nem `package:flutter`.

## 3. Modelo

Interno. Todas as listas e mapas são não modificáveis.

```dart
enum CssDisplay { inline, block, listItem, none }
enum CssWhiteSpace { normal, pre, nowrap, preWrap, preLine }
enum CssDirection { ltr, rtl }
enum CssTextAlign { start, center, end }
/// A palavra computada, que é o que herda (no CSS Text, um filho `rtl` de
/// um pai com `left` continua `left`). `justify` vira `start` no parse.
enum CssAlignKeyword { start, end, left, right, center }
enum CssVerticalAlign { baseline, sup, sub }
enum CssListStyleType {
  disc, circle, square, decimal, lowerAlpha, upperAlpha, lowerRoman, upperRoman, none,
}
/// `breakInside` nunca é `page`.
enum CssBreak { auto, page, avoid }
enum CssFontStyle { normal, italic }
enum CssFontWeight { normal, bold }
enum CssFontVariant { normal, smallCaps }
enum CssTextTransform { none, uppercase, lowercase, capitalize }
/// Direção do tamanho em relação ao pai; o IR acumula (doc/03 §4,
/// `InlineAttr.sizeSmaller`/`sizeLarger`).
enum CssFontSizeStep { same, smaller, larger }
enum CssLengthUnit { em, percent }

/// As três classes de doc/02 §2. `globalAppearance` nunca chega ao
/// `ComputedStyle`: é a classe das propriedades ignoradas em silêncio (§7.3).
enum StyleClass { structure, relativeTypography, globalAppearance }

final class CssLength {
  const CssLength(this.value, this.unit);
  final double value;          // em [0, 100] (§7.1)
  final CssLengthUnit unit;
}

/// Quatro lados, em em.
final class EmEdges {
  const EmEdges(this.top, this.right, this.bottom, this.left);
  static const zero = EmEdges(0, 0, 0, 0);
  final double top, right, bottom, left;
}

@immutable
final class ComputedStyle {
  const ComputedStyle({/* todos os campos, com os valores iniciais de §7.1 */});

  /// Valores iniciais de todas as propriedades (§7.1).
  static const ComputedStyle initial = ComputedStyle();

  // Classe 1 — estrutura: o usuário nunca sobrepõe (doc/02 §2).
  final CssDisplay display;
  final CssWhiteSpace whiteSpace;
  final CssDirection direction;
  final CssVerticalAlign verticalAlign;
  final CssListStyleType listStyleType;
  final CssBreak breakBefore, breakAfter, breakInside;
  final CssLength? width, height;         // null = auto

  // Classe 2 — tipografia relativa.
  final CssAlignKeyword alignKeyword;     // o que herda
  CssTextAlign get textAlign;             // alignKeyword resolvido pela direction deste elemento
  final bool underline, lineThrough;      // decorações em vigor (propagadas, §10.5)
  final CssFontStyle fontStyle;
  final double weight;                    // 1–1000, fracionário, o que herda (bolder/lighter, #45)
  CssFontWeight get fontWeight;           // bold se weight >= 600
  final CssFontVariant fontVariant;
  final CssTextTransform textTransform;
  final CssFontSizeStep fontSizeStep;     // relativo ao pai, não herda
  final EmEdges margin, padding;          // em
  final double textIndent;                // em, em [-4, 8]

  @override bool operator ==(Object other); // todos os campos
  @override int get hashCode;
}
```

`textAlign`: `left` → `start` se `direction` é `ltr`, senão `end`; `right` → o
contrário; `start`, `end` e `center` ficam. **(Decisão da spec, #3.)** O
desenho fixou a saída em três valores; guardar a palavra computada é o que
evita a semântica errada de herdar o valor já convertido (um `<p dir="rtl">`
dentro de `<div style="text-align: left">` alinha à esquerda no navegador, não
ao `start`).

`weight`: `normal` = 400, `bold` = 700; `bolder` e `lighter` pela tabela do CSS
Fonts 4 sobre o `weight` do pai (`bolder`: < 350 → 400, < 550 → 700, < 900
→ 900, senão o do pai; `lighter`: < 100 → o do pai, < 550 → 100, < 750 →
400, senão 700).
**(Decisão da spec, #4.)** Com só dois estados, `lighter` num pai com peso 900
sairia `normal` em vez de `bold`.

`underline`/`lineThrough` são as decorações **em vigor** no elemento: as que
ele declara mais as que vêm dos ancestrais pela propagação do CSS Text
Decoration, que não é herança (§10.5) **(controlador, #24)**. O IR as traduz
nos bits `InlineAttr.underline` e `InlineAttr.strikethrough` que já existem
([03](../03-camada-a-ir.md) §4).

`ComputedStyle` é internado pelo valor dentro de uma cascata (§10.5): dois
elementos com o mesmo estilo recebem a mesma instância.

```dart
/// Resultado da cascata de uma seção.
final class SectionStyles {
  /// Estilo de [element], ou `null` se ele não é do documento processado.
  ComputedStyle? styleOf(Element element);

  /// Elementos com estilo: todos os do documento fora da subárvore de
  /// `<template>`, inclusive os de `display: none` e os abaixo da
  /// profundidade de casamento.
  int get length;

  /// O orçamento de §10.6 acabou; o resto da seção teve só a folha padrão,
  /// as dicas de §8.2 e os `style=""`.
  bool get budgetExhausted;

  /// Origem da declaração que venceu [property] em [element]; `null` quando o
  /// valor veio de herança ou do inicial. Só com `recordOrigins: true` (§10.1);
  /// senão lança `StateError` — é API de teste.
  CssOrigin? originOf(Element element, CssProperty property);
}
```

O mapa é por identidade (`Map<Element, ComputedStyle>.identity()`), com todos
os elementos da árvore de `document.documentElement` menos os descendentes de
`<template>` (o próprio `template` tem estilo, `display: none`) **(muda o
desenho, #33)**: no HTML o conteúdo de `template` é inerte e não participa da
renderização.

## 4. Tokenizador

`lib/src/css/tokenizer.dart`, CSS Syntax Level 3 §4, recortado ao que o
parser usa.

```dart
enum CssTokenType {
  ident, function, atKeyword, hash, string, badString, url, badUrl, delim,
  number, percentage, dimension, whitespace, cdo, cdc, colon, semicolon,
  comma, leftBracket, rightBracket, leftParen, rightParen, leftBrace,
  rightBrace, eof,
}

final class CssToken {
  final CssTokenType type;
  final String value;        // ident/function/at/hash/string/url: com escapes resolvidos; delim: o caractere
  final double number;       // number/percentage/dimension; NaN se o literal passa de 64 caracteres
  final bool isInteger;      // literal sem '.' nem expoente
  final String unit;         // dimension, em minúsculas ASCII; '' nos outros
  final bool isIdHash;       // hash cujo valor começa como identificador (serve de #id)
}

/// Lê [text] do começo ao fim; depois do último token, [next] devolve `eof`
/// para sempre.
final class CssTokenizer {
  CssTokenizer(String text);
  CssToken next();
}
```

Regras, na ordem do CSS Syntax:

1. **Pré-processamento** na leitura (sem cópia do texto): CR, CRLF e FF contam
   como LF; U+0000 e surrogate solto viram U+FFFD no valor do token.
2. **Comentário** `/* … */` some; não terminado consome até o fim.
3. **String** com `"` ou `'`: `\` + LF é continuação (some); LF literal fecha
   como `badString` (o LF não é consumido); fim do texto fecha a string.
4. **Escape** (`\` seguido de algo que não é LF): até 6 dígitos hex e um
   espaço opcional; o código 0, surrogate ou acima de U+10FFFF viram U+FFFD;
   outro caractere vira ele mesmo. `\` no fim do texto vira U+FFFD em ident e
   some em string.
5. **`url(` sem aspas** vira `url`, com escapes; espaço antes do `)` final é
   aceito; `"`, `'`, `(`, espaço no meio, caractere não imprimível ou escape
   inválido viram `badUrl`, que consome até o `)` seguinte (respeitando
   escapes) ou o fim. `url(` seguido de aspas vira `function` `url` e uma
   `string`.
6. **Número:** sinal opcional, dígitos, parte decimal e expoente (`1e3`,
   `.5`). O valor sai de `double.tryParse` sobre a fatia; uma fatia com mais
   de 64 caracteres dá `NaN`, que invalida a declaração que o usar (nunca
   `int.parse`, nunca exceção). Seguido de identificador → `dimension`; de
   `%` → `percentage`.
7. `<!--` e `-->` viram `cdo`/`cdc` (o parser os ignora no nível de topo).
8. Identificador segue o CSS Syntax (`--x`, `-a`, não ASCII, escapes);
   `ident(` vira `function`; `@ident` vira `atKeyword`; `#nome` vira `hash`.

### 4.1 Por que é linear

- Um índice só avança sobre o texto; cada unidade de código é lida um número
  constante de vezes (o escape lê no máximo 7 à frente e não volta). Não há
  `RegExp`, nem `split`, nem busca para trás.
- O valor de cada token é **uma** `substring` do trecho dele (sem escape) ou um
  `StringBuffer` (com escape): a soma dos valores é ≤ o tamanho do texto. Não
  há `substring` do resto do texto em laço.
- Comentário, string e `url` sem fim consomem até o fim do texto uma vez e
  terminam.
- O tokenizador não guarda a lista de tokens: o parser pede um de cada vez,
  com uma posição de "reconsumo" (CSS Syntax "reconsume the current input
  token"), então a memória é O(1) além dos valores em uso.

## 5. Parser

`lib/src/css/parser.dart`, o algoritmo de parse do CSS Syntax Level 3 no
modelo atual ("consume a stylesheet's contents", "consume a block's contents",
"consume a qualified rule", "consume an at-rule", "consume a declaration")
sobre o `CssTokenizer`. Nomes de at-rule, de pseudo-classe e de
pseudo-elemento e palavras-chave de valor são comparados **sem diferença de
caixa ASCII** (`@MEDIA`, `:First-Child`, `ITALIC`); nomes de classe, `id` e
valores de atributo, com diferença (§6.1).

```dart
final class CssImport {
  final String href;               // cru, como escrito na folha
}

final class StyleRule {
  final List<Selector> selectors;  // só os seletores suportados da lista, na ordem (§6.3)
  final List<Declaration> declarations; // já expandidas e tipadas (§7), na ordem
}

/// Diagnóstico de parse guardado na folha e reemitido pelo loader a cada
/// seção que a aplica (§9.6). No máximo um por (código, motivo) por folha.
final class CssIssue {
  final EpubDiagnosticCode code;   // cssRuleIgnored, stylesheetIgnored ou stylesheetMediaIgnored
  final String? reason;            // §12.1 (null em stylesheetMediaIgnored)
  final int discarded;             // quantas regras, seletores, blocos ou @import
  final Map<String, Object?> details; // amostra (seletor truncado, media, href do @import)
}

final class StyleSheet {
  final List<CssImport> imports;   // só os que valem (em posição, media casada)
  final List<StyleRule> rules;     // fora das @media que não casam
  final List<CssIssue> issues;
  final int sourceLength;          // unidades de código do texto
}

/// Folha inteira. Nunca lança.
StyleSheet parseStyleSheet(String text);

/// Conteúdo de `style=""`: as declarações, sem seletor, e quantas foram
/// descartadas por sintaxe (§10.5 soma e emite uma vez por seção).
(List<Declaration> declarations, int parseErrors) parseStyleAttribute(String text);

/// Lista de media queries, já em tokens (o prelúdio de `@media` e o resto do
/// `@import`). Ver as regras abaixo.
bool mediaMatches(List<CssToken> tokens);

/// Atributo `media` de `<link>` e `<style>`: `null` casa; senão, o texto é
/// tokenizado por `CssTokenizer` e vai a [mediaMatches].
bool mediaAttributeMatches(String? media);
```

**`mediaMatches`** **(decisão da spec, #30)**, pelo Media Queries 4, sem
avaliar característica nenhuma:

- A lista é dividida pelas vírgulas **do nível de topo**: uma vírgula dentro de
  `(…)` ou de função pertence à query em que está (é um bloco, como em todo o
  CSS Syntax). Lista vazia, ou só espaço → casa.
- Cada query, ignorando espaço, casa se for exatamente: `all`, `screen`,
  `only all`, `only screen`, ou `not <tipo>` com um `<tipo>` que não é `all`
  nem `screen` (`not print`, `not amzn-kf8`: o navegador casa, porque a tela
  não é impressora).
- Casa nada: `print`, `speech`, tipo desconhecido, `not all`, `not screen`,
  qualquer query com `and`, parênteses, `or`, função ou token inesperado
  (`screen and (max-width: 600px)`, `(prefers-color-scheme: dark)`); uma query
  malformada vale `not all`, como no Media Queries.
- A lista casa se alguma query casa.

### 5.1 Nível de topo

"Consume a stylesheet's contents":

- Espaço, `cdo` e `cdc` são ignorados.
- `atKeyword` → at-rule (abaixo).
- Qualquer outro token começa uma **regra qualificada**: o prelúdio vai até o
  `{`, e o bloco é lido por "consume a block's contents" (§5.3). No nível de
  topo, `;` não termina nada: faz parte do prelúdio. O prelúdio passa por
  `parseSelectorList` (§6):
  - inválido → regra descartada, `cssRuleIgnored` `parse-error`;
  - válido, com seletores fora do subconjunto → esses caem, `cssRuleIgnored`
    `unsupported-selector`, e a regra fica com os outros; sem nenhum, a regra
    some (§6.3);
  - prelúdio que chega ao fim do texto sem `{` → descartado, `parse-error`.
- **At-rules:**
  - `@charset` → ignorada (a codificação é de §9.4).
  - `@import` → §5.2.
  - `@media` → se `mediaMatches` do prelúdio, o bloco é lido como uma lista
    de regras (o mesmo algoritmo do nível de topo, com `@media` aninhado
    filtrado nível a nível) e as regras entram na folha como se estivessem fora
    dele; se não, o bloco é consumido e conta num `stylesheetMediaIgnored` da
    folha.
  - `@namespace`, `@font-face`, `@page`, `@supports`, `@keyframes` (e
    `@-webkit-keyframes`), `@layer`, `@counter-style`, `@font-feature-values`,
    `@property`, `@container` e qualquer outra desconhecida → descartadas
    **em silêncio** (o bloco e o `;` são consumidos). `@namespace prefixo url;`
    em posição (depois de `@charset` e `@import`, antes de qualquer regra de
    estilo válida ou outra at-rule reconhecida; uma regra inválida antes não
    conta) só registra o prefixo para os seletores (#41). Só as reconhecidas pelo
    navegador contam para a posição do `@import` (§5.2): `@-moz-document`,
    `@document`, `@viewport`, `@-ms-viewport` e `@-moz-keyframes` são
    desconhecidas no Chromium e não contam (#44).
    `@font-face` é aparência sem efeito no perfil `uniform`
    ([03](../03-camada-a-ir.md) §6); `@supports` com o conteúdo inteiro
    descartado é a leitura conservadora (o bloco pode depender de `flex`,
    `grid` e outras coisas que o galley não faz).

### 5.2 `@import`

- Forma: `@import <string> | url(<…>) [lista de media]? ;`. O href sai cru.
- Com `layer`, `layer(…)` ou `supports(…)` no prelúdio → ignorado,
  `stylesheetIgnored` `unsupported-import` (`warning`, `href` = a folha que
  importa, `details.import` = o href cru) **(controlador, #37)**: a condição
  não é avaliada, e ignorar o `@import` é o lado seguro; não é media, então
  não vai para `stylesheetMediaIgnored`.
- Media que não casa → ignorado, `stylesheetMediaIgnored`.
- **Posição** (a regra do `@import` do CSS Cascade 4): um `@import` só vale
  **no nível de topo** e se nenhuma regra de estilo **válida** nem at-rule
  **reconhecida** (a lista de §5.1, exceto `@charset` e `@layer` sem bloco)
  apareceu antes dele. Regra cujos seletores estão todos fora do subconjunto
  conta como válida (a gramática aceita); regra descartada por `parse-error` e
  at-rule desconhecida não contam. `@import` fora de posição — depois de
  regra, dentro de `@media`, dentro de um bloco de estilo → ignorado,
  `stylesheetIgnored` `late-import` (`warning`), `details.import` = o href cru.
- Prelúdio sem string nem `url` → `cssRuleIgnored` `parse-error`.

### 5.3 Blocos de estilo e recuperação de erro

"Consume a block's contents", dentro de um bloco de regra de estilo e em
`style=""` **(controlador, #29)**:

- Espaço e `;` são ignorados; `}` (ou o fim, em `style=""`) termina o bloco.
- `atKeyword` → uma at-rule **aninhada**. Com bloco (`@media`, `@supports`,
  qualquer outra), é consumida e descartada, `cssRuleIgnored` `nested-rule`;
  `@import` → `stylesheetIgnored` `late-import` (§5.2); outra sem bloco
  (`@foo;`) → descartada em silêncio, como no topo.
- Outro token → tenta **uma declaração**: `ident`, espaço, `:`, e o valor até o
  `;` ou `}` do nível do bloco (blocos `{}`, `()` e `[]` no meio são consumidos
  inteiros), com `!important` (o par `delim !` + `ident important`, sem
  caixa, espaço e comentário no meio aceitos) no fim. O nome é comparado em
  minúsculas ASCII.
- **Quando a tentativa falha, e onde ela para** **(controlador, #35)**. No CSS
  Syntax atual, "consume a declaration" devolve nada (a) sem `ident` ou sem
  `:` — depois de "consume the remnants of a bad declaration", que varre até o
  `;` ou o `}` do bloco —, e (b), no passo que examina o valor, quando o valor
  tem um bloco `{}` de topo e **também** outro conteúdo que não é espaço (um
  `{}` só é aceito como o valor inteiro de uma propriedade que não é
  customizada, e em customizada vale qualquer coisa); então "consume a
  block's contents" restaura a marca e relê os mesmos tokens como regra
  qualificada aninhada, que para no `;`. Seguido ao pé da letra, isso é
  quadrático: em `p { a:b{} a:b{} … }` sem `;`, cada tentativa varre o resto
  do bloco até o `}` antes de falhar, e depois só um `a:b{}` é consumido como
  regra. O galley para **no ponto em que a falha já é certa**, com o mesmo
  resultado:
  - sem `ident` no começo, ou sem `:` depois do nome → falha ali, sem varrer os
    "remnants" (o que eles consumiriam é jogado fora pelo restore de qualquer
    jeito);
  - nome que não é customizado e primeiro `{}` de topo **depois** de outro
    conteúdo → falha ao fechar esse bloco;
  - nome que não é customizado, valor que **começa** por `{}` → falha no
    primeiro token que não é espaço depois dele (se vier `;`/`}`, a declaração
    é sintaticamente válida e só é descartada por não estar na tabela). Esse
    token que sobra **volta ao fluxo**: a regra aninhada relida do buffer
    termina no `}` do bloco, e o token é reconsumido como o início do próximo
    item do bloco, não descartado com o buffer.
  Propriedade customizada (`--x`) vai sempre até o `;`/`}` e é descartada em
  silêncio (sucesso sintático, sem releitura). `badString` ou `badUrl` no valor
  deixam a declaração inválida: ela vai até o `;`/`}` e é descartada,
  `cssRuleIgnored` `parse-error`, sem releitura — a regra qualificada do CSS
  Syntax consumiria os mesmos tokens e não devolveria nada, porque um `{}`
  depois de conteúdo já teria parado a tentativa antes.
- Se a declaração falha, os tokens que ela consumiu são relidos como **regra
  qualificada aninhada**, que no aninhamento para no `;`: se ela tem prelúdio
  e bloco, é consumida inteira e descartada, `cssRuleIgnored` `nested-rule` (o
  galley não implementa CSS Nesting); se chega ao `;` ou ao `}` sem bloco, é
  lixo: descartada até ali, `cssRuleIgnored` `parse-error`. O resto do bloco
  segue.
- Propriedade fora da tabela (§7), propriedade customizada (`--x`) e valor fora
  do aceito → declaração descartada **em silêncio** (é a classe "ignorado" de
  [03](../03-camada-a-ir.md) §6, e reportar cada uma inundaria o canal).
- Um valor com `var()` descarta a declaração em silêncio: o galley não
  resolve propriedades customizadas.

Casos fechados (cada um com teste, §14):

| Entrada | Resultado |
|---|---|
| `p { .x { font-weight: bold } font-style: italic; color: blue }` | `.x {…}` não é declaração (começa por `delim .`) → regra aninhada, descartada com `nested-rule`; `font-style: italic` vale em `p`; `color` é ignorado em silêncio (§7.3). No modelo antigo ("consume a list of declarations") o `.x {…} font-style: italic` inteiro sumiria até o `;` |
| `p { a:hover { font-weight: bold } font-style: italic }` | a tentativa de declaração `a: hover {…}` falha (bloco `{}` com outro conteúdo) → regra aninhada, `nested-rule`; `font-style` vale |
| `a{};p{font-style: italic}` | no topo, `;` não fecha nada: o prelúdio da segunda regra é `;p`, inválido → a regra de `p` some, `parse-error` (o mesmo que o navegador faz); `a{}` vale, vazia |
| `p { @media screen { font-weight: bold } font-style: italic }` | at-rule aninhada com bloco → `nested-rule`; `font-style` vale; `font-weight` não |
| `@media screen { @import "x.css"; p { font-style: italic } }` | o `@import` não está no topo → `late-import`, nada é buscado; a regra de `p` vale |
| `p { font-style: italic; @foo; font-weight: bold }` | `@foo;` some em silêncio; as duas declarações valem |
| `p { a:b{} a:b{} … a:b{} }` (100 000 vezes, sem `;`), e o mesmo em `style=""` | cada tentativa falha ao fechar o seu `{}` e cada `a:b{}` vira uma regra aninhada (`nested-rule`, agregado); linear (§5.5), com teste hostil em §14.3 |

### 5.4 Aninhamento

`maxCssNesting = 32` blocos abertos (`{`, `(`, `[`, função). Ao abrir o 33º, o
parser entra em modo de salto: consome tokens até fechar o bloco que passou do
limite, sem construir nada, e emite `stylesheetIgnored` `limit`
(`details.limit: 'nesting'`) uma vez por folha. O salto casa fechamentos com
uma pilha de tipos (um `)` solto dentro de `{` é só um token, como no CSS); a
pilha cresce no máximo até o número de aberturas do trecho.

### 5.5 Por que é linear

- Cada token é pedido ao tokenizador uma vez; o reconsumo é de um token só.
  A tentativa de declaração guarda os tokens dela num buffer, e a releitura
  como regra aninhada (§5.3) usa esse buffer. Como a tentativa para no ponto
  em que falha (§5.3), ela nunca consome além do que a regra aninhada vai
  consumir — no máximo o bloco `{}` que a fez falhar e um token depois dele —,
  então cada token é examinado **no máximo duas vezes**, e o buffer é
  descartado a cada item. Sem a parada antecipada a frase seria falsa: a
  tentativa varreria o resto do bloco a cada item.
- O prelúdio de cada regra é juntado uma vez numa lista (soma ≤ tokens da
  folha) e entregue a `parseSelectorList`; o valor de cada declaração, idem,
  a `parseDeclaration`. Nenhum dos dois volta ao texto.
- A recuperação de erro só avança (salta até `;` ou até o fim do bloco),
  fora a releitura única do buffer acima.
- A recursão por bloco é limitada a 32 níveis; além disso o salto é iterativo.
- Os diagnósticos são agregados por (código, motivo) por folha: uma folha com
  um milhão de regras inválidas gera um `CssIssue`, não um milhão.

## 6. Seletores

`lib/src/css/selector.dart`.

```dart
const int maxCompoundsPerSelector = 32;
const int maxSimpleSelectorsPerCompound = 32;   // (controlador, #27)
const int maxSelectorIdentifierLength = 256;    // tipo, classe, id, nome e valor de atributo (#34)

enum CssCombinator { descendant, child, adjacent }

final class CssAttributeTest {
  final String name;     // nome no DOM: 'epub:type' para [epub|type=…]; minúsculas
  final String value;    // comparado com diferença de caixa
}

final class CompoundSelector {
  final String? tag;     // minúsculas ASCII; null = universal ou ausente
  final String? tagAsWritten; // para elemento fora do namespace HTML
  final String? id;
  final List<String> classes;
  final List<CssAttributeTest> attributes;
  final bool firstChild, lastChild;
  final int? nthChild;   // n ≥ 1; 0 quando o argumento não pode casar (0, negativo, > 2^30, dois diferentes)
  final int ids, pseudoClasses; // contagem com repetição, para a especificidade (#43)
  final bool impossible; // #a#b: nunca casa (#43)
  // ≤ 32 seletores simples no total (§6.3)
}

final class Selector {
  final List<CompoundSelector> compounds;  // da esquerda para a direita, ≤ 32
  final List<CssCombinator> combinators;   // compounds.length - 1
  final int specificity;                   // (a << 20) | (b << 10) | c, cada um saturado em 1023
  final List<int> ancestorHashes;          // até 4, para o filtro de Bloom (§10.4)
}

sealed class SelectorListParse {}

/// A gramática aceitou a lista inteira. [selectors] tem só os que estão no
/// subconjunto (pode ser vazia); os outros caíram.
final class SelectorList extends SelectorListParse {
  final List<Selector> selectors;
  final int unsupported;          // quantos seletores da lista caíram
  final String? unsupportedSample; // o primeiro que caiu, truncado em 64
}

/// Algum seletor da lista é inválido: a regra inteira cai (parse-error).
final class SelectorInvalid extends SelectorListParse { final String sample; }

/// [prelude]: os tokens entre o fim da regra anterior e o `{`; [namespaces]:
/// os prefixos declarados por `@namespace` na folha (#41).
SelectorListParse parseSelectorList(List<CssToken> prelude, {Set<String> namespaces = const {}});
```

### 6.1 Subconjunto ([03](../03-camada-a-ir.md) §6)

| Forma | Casa com |
|---|---|
| `p`, `P` | elemento HTML de nome `p` (tipo sem diferença de caixa só no namespace HTML); fora dele (SVG, MathML), o nome exato |
| `*` | qualquer elemento |
| `.nota` | token `nota` do atributo `class`, **com** diferença de caixa (o XHTML não tem modo quirks), tokens separados por espaço ASCII |
| `#x` | atributo `id` igual a `x`, com diferença de caixa; só `hash` com `isIdHash` |
| `[a="v"]`, `[a=v]` | atributo `a` com valor exatamente `v` |
| `[epub|type="noteref"]` | atributo literal `epub:type` (o `package:html` guarda o nome com o prefixo, [03](../03-camada-a-ir.md) §8) **(decisão da spec, #11)**: o prefixo precisa ter sido declarado por `@namespace` na folha (senão o seletor é inválido, #41), e o prefixo escrito é o que o DOM tem, qualquer que seja o URI declarado. `[|a=v]` é `a` sem prefixo |
| `A B` | `B` com um ancestral `A` |
| `A > B` | `B` com pai `A` |
| `A + B` | `B` cujo irmão-**elemento** anterior é `A` (texto e comentário entre os dois não contam) |
| `:first-child`, `:last-child` | primeiro/último entre os irmãos-elemento |
| `:nth-child(n)` | `n` token `number` **inteiro** (`isInteger`), com sinal opcional (`+3` vale 3), contado a partir de 1 entre os irmãos-elemento. A faixa é conferida no `double` antes de virar `int`: `n` < 1 ou > 2^30 guarda 0 e nunca casa. `:nth-child(3.0)` é **inválido** (o An+B só aceita inteiro) |

O argumento de `:nth-child()` segue a microsintaxe An+B do CSS Syntax Level 3
§6, que é definida **sobre tokens**, não sobre texto: `2n-1` chega como **uma**
`dimension` (número 2, unidade `n-1`), `-n+3` como `ident` `-n` seguido de
`number` `+3`, `n` como `ident`, `+n` como `delim +` e `ident n`. O parser
reconhece essas formas pelos tokens, como o CSS Syntax manda, e só a forma
"um `number` inteiro" está no subconjunto.

Nomes de atributo comparados em minúsculas ASCII no namespace HTML (o
`package:html` já os baixa) e exatos fora dele; valores sempre exatos.

### 6.2 Especificidade

(a, b, c) do Selectors Level 4: a = ids, b = classes, atributos e
pseudo-classes, c = tipos; `*` e combinadores não contam. Cada componente
satura em 1023 e o conjunto vira `(a << 20) | (b << 10) | c`, menor que 2^30
(os `<<` e `|` ficam dentro dos 32 bits, seguros no dart2js) — o número que a
cascata compara (§10.5). Com no máximo 32 compostos de 32 seletores simples,
um componente chega a 1 024; a saturação só pesa nesse extremo.

### 6.3 Válido, fora do subconjunto, e inválido

Três destinos para cada seletor da lista **(controlador, #12; muda o
desenho)**:

- **No subconjunto** (§6.1) → entra em `SelectorList.selectors`.
- **Válido, fora do subconjunto** → cai sozinho; os outros da lista continuam.
  `SelectorList.unsupported` conta, e o parser emite um `cssRuleIgnored`
  `unsupported-selector` (agregado por folha, §12.1, `details.sample` = o
  primeiro seletor que caiu, truncado em 64 unidades de código sem cortar um
  par de surrogates). Se todos caem, a regra some. É o que o navegador faria
  com `p.x, p:not(.y)`: aplica `p.x`.
- **Inválido** → `SelectorInvalid`, a **regra inteira** cai, `cssRuleIgnored`
  `parse-error`, como no CSS (a lista de seletores do Selectors 4 não é
  tolerante).

**Válido, fora do subconjunto:**

- combinador `~`;
- pseudo-classes da lista fechada abaixo, fora `:first-child`, `:last-child` e
  `:nth-child(<inteiro>)`;
- `:nth-child()` com argumento An+B válido que não é um inteiro só (`odd`,
  `even`, `2n+1`, `-n+3`, `n`, com ou sem `of <seletores>`);
- pseudo-elementos da lista fechada abaixo;
- atributo por presença (`[href]`), por `~=`, `|=`, `^=`, `$=`, `*=`, ou com
  flag `i`/`s`;
- tipo com namespace (`svg|rect` com `@namespace svg` declarado, `*|p`, `|p`) e atributo `[*|a]`;
- mais de 32 compostos, ou um composto com mais de 32 seletores simples
  (`.a.b.c…`) **(controlador, #27)**;
- identificador (tipo, classe, `id`, nome de atributo) ou valor de atributo
  com mais de `maxSelectorIdentifierLength` (256) unidades de código
  **(controlador, #34)**: o maior do corpus tem 65
  (`.epub-type-contains-word-se-image-color-depth-black-on-transparent`, do
  Standard Ebooks); acima de 256, o custo de
  hash e de comparação por passo (§10.4) deixaria de ser constante.

**Pseudo-classes reconhecidas** (nome sem caixa): `first-child`, `last-child`,
`only-child`, `first-of-type`, `last-of-type`, `only-of-type`, `nth-child()`,
`nth-last-child()`, `nth-of-type()`, `nth-last-of-type()`, `root`, `empty`,
`not()`, `is()`, `where()`, `has()`, `link`, `visited`, `any-link`,
`local-link`, `target`, `target-within`, `scope`, `hover`, `active`, `focus`,
`focus-visible`, `focus-within`, `enabled`, `disabled`, `checked`,
`indeterminate`, `default`, `required`, `optional`, `valid`, `invalid`,
`in-range`, `out-of-range`, `read-only`, `read-write`, `placeholder-shown`,
`defined`, `lang()`, `dir()`, `fullscreen`, `playing`, `paused`, e as formas
antigas de pseudo-elemento com um `:` — `before`, `after`, `first-line`,
`first-letter`. **Pseudo-elementos reconhecidos** (com `::`): `before`,
`after`, `first-line`, `first-letter`, `marker`, `selection`, `placeholder`,
`backdrop`, `cue`, `file-selector-button`. O argumento de `:not()` é validado
como lista de seletores sem pseudo-elemento (vazio, inválido ou com
pseudo-elemento derruba: `:not(p::before)`), e o do `of` do `:nth-child` como
lista de seletores (que aceita pseudo-elemento, como no Chromium); `:is()` e `:where()` são tolerantes (qualquer conteúdo vale);
`:has()`, `:lang()` e `:dir()` precisam de argumento, sem validação a fundo
(#42). Um pseudo-elemento, inclusive as formas antigas com um `:`, fecha o
composto e o seletor: depois dele só vale `::marker` depois de
`::before`/`::after` (#42). Repetição no mesmo composto conta na
especificidade (`#a#a` é (2,0,0), `li:first-child:first-child` é (0,2,1)), e
`#a#b` ou dois `:nth-child` diferentes ficam no subconjunto e nunca casam
(#43).

**Inválido:** pseudo-classe ou pseudo-elemento fora dessas listas, inclusive
os prefixados (`:foo`, `::-moz-x`, `:-webkit-any()`); `:nth-child()` com
argumento que não é An+B (`3.0`, `foo`, vazio); item vazio na lista (`a,,b`);
combinador sem composto, ou `>>`, `||`; `#` que não é identificador (`#1a`);
`.` sem identificador; colchete sem fechar; operador de atributo
desconhecido; flag de atributo que não é `i`/`s`; token inesperado (`{`, `;`,
string solta); qualquer seletor simples ou combinador depois de um
pseudo-elemento (`p::before:hover`, `p::before span`); `:not()`, `:has()`,
`:lang()` e `:dir()` vazios; `:not(:foo)` e `:nth-child(2n of 1+)`; prefixo
de namespace não declarado (`ns|p`, `[epub|type]` sem `@namespace epub`,
#41).

**Divergências do Chromium 153 (revisão da Tarefa 3).** As listas fechadas de
pseudo-classes e pseudo-elementos acima seguem o Selectors 4 e o padrão de
cada nome, não o Chromium, e divergem dele nos dois sentidos:

- o galley **aceita** (válido, fora do subconjunto) o que o Chromium rejeita:
  `:target-within`, `:local-link`, `:playing`, `:paused`, `:has(:foo)`,
  `:lang(1)`, `:dir(1)` e `::cue()`;
- o galley **rejeita** (seletor inválido, derruba a regra) o que o Chromium
  aceita: `::-webkit-*`, `:-webkit-any-link`, `:host`, `:autofill`, `:modal`,
  `:open`, `:user-invalid`, `::part()`, `::highlight()`, `::spelling-error` e
  `::target-text`.

O efeito prático é o segundo: `p, ::-webkit-scrollbar { … }` vale no
Chromium para `p` e, no galley, some inteira. Fica em [14](../14-pendencias.md).

### 6.4 Por que é linear

- Uma passada sobre os tokens do prelúdio; a divisão por vírgula é feita na
  mesma passada.
- Ao passar do 32º composto (ou do 32º seletor simples de um composto), o
  seletor já é "fora do subconjunto" e deixa de ser **montado**, mas o resto
  do item continua sendo **validado** pela gramática, na mesma passada e sem
  guardar nada — um `a a … a :foo` de 200 000 compostos ainda é inválido e
  descarta a regra.
- Os hashes de ancestral são tirados do composto já montado (no máximo 4).
- `:nth-child` lê o número do token (`double`) e confere a faixa antes de
  converter; nunca `int.parse`.

## 7. Propriedades

`lib/src/css/properties.dart`.

```dart
enum CssProperty {
  display, whiteSpace, direction, verticalAlign, listStyleType,
  breakBefore, breakAfter, breakInside, width, height,
  textAlign, textDecoration, fontStyle, fontWeight, fontVariant, textTransform, fontSize,
  marginTop, marginRight, marginBottom, marginLeft,
  paddingTop, paddingRight, paddingBottom, paddingLeft, textIndent,
  // Degradadas (§7.4): participam da cascata, não do ComputedStyle.
  float, position, columnCount, columnWidth, writingMode;

  StyleClass get styleClass;
  bool get inherited;
  bool get degraded;
}

final class Declaration {
  final CssProperty property;
  final CssValue value;
  final bool important;
}

sealed class CssValue {}
/// inherit, initial, unset.
final class CssWideKeyword extends CssValue { final CssWide keyword; }
enum CssWide { inherit, initial, unset }
/// Palavra já mapeada para o enum da propriedade (CssDisplay, CssBreak…).
final class CssKeywordValue<E extends Enum> extends CssValue { final E value; }
/// list-style-type com nome desconhecido (resolvido no elemento, §7.1).
final class CssUnknownListStyle extends CssValue {}
/// font-weight: absolute 1–1000, ou relativo ao pai.
final class CssWeightValue extends CssValue { final double? absolute; final bool bolder; }
/// Margens, padding e text-indent: já convertidos e limitados.
final class CssEmValue extends CssValue { final double em; }
/// width/height.
final class CssLengthValue extends CssValue { final CssLength? length; } // null = auto
/// font-size relativo: a razão sobre o pai, ou smaller/larger.
final class CssFontSizeValue extends CssValue { final CssFontSizeStep step; }
/// text-decoration(-line): as linhas que o próprio elemento declara.
final class CssDecorationValue extends CssValue { final bool underline, lineThrough; }
/// Propriedade degradada: se o valor degrada (float: left) e a palavra.
final class CssDegradedValue extends CssValue { final bool degrades; final String keyword; }

/// Expande e tipa uma declaração. Lista vazia: propriedade fora da tabela
/// ou valor fora do aceito (descarte em silêncio, §5.3). [name] em
/// minúsculas ASCII; [value] sem o `!important`.
List<Declaration> parseDeclaration(String name, List<CssToken> value, {required bool important});
```

`inherit`, `initial` e `unset` valem em todas as propriedades, inclusive nos
atalhos (expandem para todas as longhands). `revert` e `revert-layer`
descartam a declaração (o galley não tem a origem do usuário, e voltar à
folha padrão aproximaria mal).

### 7.1 Tabela

Classe: **E** = estrutura (Classe 1), **T** = tipografia relativa (Classe 2).
"Descarta" = a declaração some (vale a anterior na cascata).

| Propriedade | Classe | Herda | Inicial | Valores aceitos | Mapeamento |
|---|---|---|---|---|---|
| `display` | E | não | `inline` | `inline`, `inline-block`, `inline-flex`, `inline-grid`, `inline-table`, `block`, `flex`, `grid`, `flow-root`, `table` e `table-*`, `list-item`, `none` | `inline-*` → `inline`; `flex`, `grid`, `flow-root`, `table*` → `block`; `list-item` → `listItem`; `none`. Outro (`contents`, `ruby`, forma de dois valores) descarta |
| `white-space` | E | sim | `normal` | `normal`, `pre`, `nowrap`, `pre-wrap`, `pre-line`, `break-spaces` | `break-spaces` → `preWrap`; forma nova do CSS Text 4 (`collapse`, `preserve nowrap`) descarta |
| `direction` | E | sim | `ltr` | `ltr`, `rtl` | direto (`unicode-bidi` é ignorado) |
| `text-align` | T **(#26)** | sim | `start` | `left`, `right`, `center`, `justify`, `start`, `end` | palavra guardada em `alignKeyword`; `justify` → `start` (justificar é aparência global, [02](../02-modelo-de-estilo.md) §3.1); `textAlign` resolve `left`/`right` pela `direction` do elemento (§3). `match-parent` e `-webkit-center` descartam |
| `vertical-align` | E | não | `baseline` | `baseline`, `super`, `sub`, `top`, `text-top`, `middle`, `bottom`, `text-bottom`, comprimento, `%` | `super` → `sup`; `sub` → `sub`; os demais → `baseline` (válidos no CSS: tiram o sobrescrito da folha padrão) |
| `list-style-type` | E | sim | `disc` | `disc`, `circle`, `square`, `decimal`, `lower-alpha`, `lower-latin`, `upper-alpha`, `upper-latin`, `lower-roman`, `upper-roman`, `none`; outro identificador ou string | `*-latin` = `*-alpha`; nome desconhecido (`lower-greek`, `"–"`) → `decimal` se o elemento onde a declaração vale é `ol` ou `li` filho de `ol`, senão `disc` **(decisão da spec, #8)**; número e lixo descartam |
| `list-style` (atalho) | E | — | — | tipo, posição (`inside`/`outside`) e imagem (`url()`/`none`), em qualquer ordem | só o tipo entra; sem tipo, `none` sozinho → `none`; sem tipo nem `none` → `disc` (o atalho reinicia) |
| `break-before`, `break-after` | E | não | `auto` | `auto`, `avoid`, `avoid-page`, `page`, `left`, `right`, `recto`, `verso`, `always`, `column`, `avoid-column`, `region`, `avoid-region` | `page`/`left`/`right`/`recto`/`verso`/`always` → `page`; `avoid`/`avoid-page` → `avoid`; os de coluna e região → `auto` |
| `page-break-before`, `page-break-after` | E | não | — | `auto`, `always`, `avoid`, `left`, `right` | **mesma propriedade** que `break-*` (no CSS Fragmentation são atalhos legados dela), então a ordem da cascata decide entre as duas grafias; `always`/`left`/`right` → `page` |
| `break-inside`, `page-break-inside` | E | não | `auto` | `auto`, `avoid`, `avoid-page`, `avoid-column`, `avoid-region` | `avoid*` → `avoid`; nunca `page` |
| `width`, `height` | E | não | `auto` | comprimento ≥ 0, `%` ≥ 0, `auto` | conversão de §7.2; limitado a [0, 100] em `em` e em `%` **(decisão da spec, #6)**; `auto` → `null`; negativo descarta. `max-*`/`min-*` ignoradas |
| `font-style` | T | sim | `normal` | `normal`, `italic`, `oblique` (com ângulo opcional, entre −90° e 90°, #45) | `oblique` → `italic` |
| `font-weight` | T | sim | `normal` (400) | `normal`, `bold`, `bolder`, `lighter`, número 1–1000 | peso numérico em `weight`; `bolder`/`lighter` sobre o pai (§3); `fontWeight` = `bold` se ≥ 600 |
| `font-variant`, `font-variant-caps` | T | sim | `normal` | qualquer lista de identificadores | contém `small-caps` ou `all-small-caps` → `smallCaps`; senão `normal` (o atalho reinicia o `caps`); número ou string descartam |
| `text-transform` | T | sim | `none` | `none`, `uppercase`, `lowercase`, `capitalize` | direto; `full-width` e outros descartam |
| `text-decoration-line` | T | não (propaga, §10.5) | `none` | `none`, ou uma ou mais de `underline`, `overline`, `line-through`, `blink` | `underline` → `underline`; `line-through` → `lineThrough`; `overline` e `blink` aceitos e ignorados; outra palavra, número ou string descartam **(controlador, #24)** |
| `text-decoration` (atalho) | T | — | — | linha, estilo, cor e espessura, em qualquer ordem, cada um no máximo uma vez | só a linha entra, pela regra de `text-decoration-line`; estilo (`solid`, `double`, `dotted`, `dashed`, `wavy`), cor (nome do CSS Color 4, de sistema, `#hex`, função de cor, `currentcolor`, `transparent`) e espessura (`auto`, `from-font`, comprimento, `%`, `calc()`) são aceitos e ignorados; outra palavra (`foo`) ou componente repetido (`red blue`) descarta a declaração (#45); sem linha, vale `none` (o atalho reinicia) |
| `font-size` | T | não (relativo ao pai) | `same` | `em`, `%`, `rem`, `ex`, `ch`, `smaller`, `larger` | razão r sobre o pai (`em`/`rem`: o número; `%`: /100; `ex`/`ch`: × 0,5): r < 0,95 → `smaller`, r > 1,05 → `larger`, senão `same`; `smaller`/`larger` direto. Absoluto (`px`, `pt`, `medium`, `x-large`…) e negativo **descartam** (ignorado em silêncio, [03](../03-camada-a-ir.md) §6); `inherit`, `initial` e `unset` → `same` **(decisão da spec, #7)** |
| `font` (atalho) | T | — | — | `[estilo ‖ variante ‖ peso ‖ largura]? tamanho [/ entrelinha]? família` | até 4 prefixos (`normal`, `italic`, `oblique`, `small-caps`, `bold`, `bolder`, `lighter`, número 1–1000, palavras de `font-stretch`, estas aceitas e ignoradas), o tamanho (obrigatório) e a família (obrigatória, ignorada); reinicia estilo, variante e peso para `normal` quando ausentes; tamanho absoluto não gera `fontSize` (o resto do atalho vale); fonte de sistema (`caption`, `menu`…) sozinha descarta |
| `margin-top/right/bottom/left` | T | não | 0 | comprimento, `%`, `auto` | §7.2, `auto` → 0; limitado a [0, 8]em, **negativo → 0** |
| `margin` (atalho) | T | — | — | 1 a 4 valores | expansão padrão (topo, direita, base, esquerda); um componente inválido descarta o atalho |
| `padding-top/right/bottom/left` | T | não | 0 | comprimento ≥ 0, `%` ≥ 0 | §7.2; limitado a [0, 8]em; negativo **descarta** (inválido no CSS) |
| `padding` (atalho) | T | — | — | 1 a 4 valores | como `margin` |
| `text-indent` | T | sim | 0 | comprimento, `%` | §7.2; limitado a [−4, 8]em; palavras `hanging`/`each-line` descartam |

"Registrado" de [03](../03-camada-a-ir.md) §6 passa a significar isto: o valor
entra no `ComputedStyle` com a classe dele; quem decide se é honrado é a
Camada B pelo perfil ([02](../02-modelo-de-estilo.md) §3.1). No perfil
`uniform`, `text-indent`, `margin` e `padding` chegam ao IR mas não à
tipografia.

`display` de flex e grid vira `block` sem "blocoficar" os filhos, e o de
`float`/`position` não muda: a degradação declarada é o fluxo normal
([09](../09-erros-diagnosticos.md) §3 `unsupportedLayout`).

`text-decoration` **não herda**: ela **propaga** (CSS Text Decoration 3).
A decoração de um elemento é desenhada sobre todo o conteúdo em fluxo dele,
inclusive os descendentes, e um `text-decoration: none` no descendente **não**
a tira — só acrescenta as próprias linhas às que já vêm de cima. O CSS abre
três exceções: a propagação não entra em inline atômico (`inline-block`,
`inline-table`, imagem), em `float` nem em elemento posicionado. No galley as
três se perdem: `inline-block` e `inline-table` viram `inline` (§7.1), e
`float`/`position` só degradam (§7.4); a decoração do ancestral passa para
dentro deles. Está nas aproximações de §7.5.

### 7.2 Comprimentos

| Unidade | Em `em` | Nota |
|---|---|---|
| `em` | ×1 | |
| `rem` | ×1 | aproximação: sem a raiz do publisher, vale como `em` **(decisão da spec, #5)** |
| `ex`, `ch` | ×0,5 | o valor que o CSS Values 4 manda assumir sem métrica de fonte |
| `px` | ÷16 | base fixa 16px = 1em (desenho) |
| `pt` | ÷12 | 16px = 12pt |
| `pc` | ×1 | 1pc = 12pt |
| `in` | ×6 | 96px |
| `cm` | ×2,3622 | 96/2,54/16 |
| `mm` | ×0,23622 | |
| `q` | ×0,059055 | |
| `%` (margem, padding, recuo) | ×0,3 | sobre a medida de 30em (desenho), aproximado |
| `%` (`width`, `height`) | fica `%` | |
| `0` sem unidade | 0 | outro número sem unidade descarta (sem modo quirks) |

`vw`, `vh`, `vmin`, `vmax`, `lh`, `cap`, `calc()`, `min()`, `max()`,
`clamp()`, `var()` e unidade desconhecida descartam a declaração em silêncio.
Um `NaN` do tokenizador (§4, literal longo) e um valor infinito descartam.

### 7.3 Ignoradas em silêncio

Classe 3 (aparência global, [02](../02-modelo-de-estilo.md) §2): `color`,
`background*`, `font-family`, `line-height`, `border*`, `outline*`,
`box-shadow`, `text-shadow`, `letter-spacing`, `word-spacing`, `opacity`,
`visibility`, `text-decoration-color`, `text-decoration-style`,
`text-decoration-thickness`. E tudo o que não está em §7.1 nem em §7.4 (`all`,
`hyphens`, `text-decoration-skip*`, `text-underline-*`, propriedades lógicas
como `margin-inline-start`, prefixos `-webkit-`/`-epub-` fora de
`writing-mode`, `content`, `quotes`…). O que disso
pode fazer falta vai para [14](../14-pendencias.md) (§16).

### 7.4 Degradadas

Participam da cascata como as outras (§10.5), não entram no `ComputedStyle` e,
quando o valor vencedor degrada, emitem `unsupportedLayout` (§10.7):

| Propriedade | Degrada quando | Não degrada |
|---|---|---|
| `float` | `left`, `right`, `inline-start`, `inline-end` | `none` |
| `position` | `absolute`, `fixed`, `sticky` | `static`, `relative` ([03](../03-camada-a-ir.md) §6) |
| `columns`, `column-count`, `column-width` | contagem inteira > 1 ou largura com comprimento (`columns` expande nas duas) | `auto`, `1` |
| `writing-mode`, `-epub-writing-mode`, `-webkit-writing-mode` | `vertical-rl`, `vertical-lr`, `sideways-*`, `tb`, `tb-rl` | `horizontal-tb`, `lr`, `lr-tb`, `rl`, `rl-tb` |

As três grafias de `writing-mode` são a mesma propriedade (o corpus tem
`writing-mode` e `-epub-writing-mode` juntas, `faixa-b/writing-mode-vertical`).

### 7.5 Aproximações registradas

O que o galley faz diferente do navegador, de propósito, e fica em
[14](../14-pendencias.md):

- **`em` herdado.** No CSS, `text-indent: 2em` (e qualquer `inherit` de
  comprimento) herda o valor **absoluto** calculado sobre a fonte do pai; aqui
  o número em `em` passa ao filho e vale sobre a fonte **do filho**. Só difere
  quando o filho muda de tamanho, e o perfil `uniform` não honra o recuo.
- **`bolder` sobre peso leve.** `bolder` sobre um pai de peso 300 dá 400 pela
  tabela do CSS Fonts, que sai `normal`: o texto "mais forte" fica igual ao
  corpo.
- **Profundidade acima de 256.** O estilo herdado puro (§10.2) não passa pela
  folha padrão: um `script` ou `style` nesse fundo fica com `display: inline`,
  visível para o IR.
- **Propagação de `text-decoration`** para dentro de `inline-block`, `float` e
  posicionado (acima).
- **Links sem o sublinhado de `:link`.** A folha do HTML sublinha `a[href]`
  por `:link`, que está fora do subconjunto: o link sai sem sublinhado na
  cascata (o IR marca `InlineAttr.link` de qualquer forma).
- **`unsupportedLayout` fundido.** O dedupe do `DiagnosticSink` por (código,
  `href`) junta `float` e `position` da mesma seção num registro, com os
  `details` do último (§12.1).
- **`<!-- -->` dentro de `<style>`** é aplicado como CSS, e não tirado como
  comentário do XML (§9.1), ao contrário do resto da leitura do `<style>` como
  dado de caractere.
- **Margens verticais do HTML §15.3 fora da folha padrão.** `p`, listas
  (`ul`, `ol`, `menu`, `dir`, `dl`), títulos, `pre`, `figure` e `hr` não
  recebem a margem vertical de §15.3 (`1em`, `0.67em` e assim por diante):
  o espaçamento entre parágrafos e blocos é do perfil de fidelidade
  (`EpubStyle.paragraphSpacing`, múltiplo da entrelinha, e a margem dos
  títulos, doc/02 §3), decidido pela Camada B e não pelo livro, e a
  Classe 2 só o honra em `faithful`. Também ficam de fora: os tamanhos de
  título dentro de `article`/`section`/`aside`/`nav` (§15.3.3, que encolhem
  `h1` aninhado), a margem horizontal de `figure` (`40px`) e `basefont` em
  `display: none`. O `blockquote` e o `dd` mantêm as margens horizontais.
- `rem` como `em`, `ex`/`ch` como 0,5em, `%` sobre 30em (§7.2); recuo de lista
  por `padding-left` em livro `rtl` (§8.1); filhos de `flex`/`grid` sem
  "blocoficação" (acima).

### 7.6 Por que é linear

- Cada declaração percorre os tokens do próprio valor uma vez; os atalhos
  têm número fixo de componentes (`margin` ≤ 4, `font` ≤ 4 prefixos mais
  tamanho) e param no primeiro que sobra.
- A busca do nome é um `switch` sobre a string (ou um mapa constante), O(1).
- Conversão e limite são aritmética; nada é reparseado na cascata.

## 8. Folha padrão e dicas de apresentação

### 8.1 `userAgentCss`

Texto embutido em `ua_sheet.dart`, parseado uma vez (`final userAgentSheet =
parseStyleSheet(userAgentCss)`, preguiçoso) e indexado uma vez (§10.3). Tirado
da seção 15 do HTML (Rendering), recortado às propriedades de §7.1. O teste
exige zero `CssIssue`.

```css
html, body, address, blockquote, center, div, figure, figcaption, footer,
header, hgroup, main, nav, section, article, aside, search, details, summary,
form, fieldset, legend, hr, p, pre, listing, xmp, plaintext,
h1, h2, h3, h4, h5, h6, dl, dt, dd, ol, ul, menu, dir,
table, caption, thead, tbody, tfoot, tr, td, th, colgroup, col { display: block }
li { display: list-item }
head, script, style, title, meta, link, base, template, area, param,
datalist, source, track, noembed, noframes { display: none }

pre, listing, xmp, plaintext { white-space: pre }
nobr { white-space: nowrap }

center, caption, th { text-align: center }

h1, h2, h3, h4, h5, h6, th { font-weight: bold }
b, strong { font-weight: bolder }
i, cite, em, var, dfn, address { font-style: italic }
u, ins { text-decoration: underline }
s, strike, del { text-decoration: line-through }

h1 { font-size: 2em }
h2 { font-size: 1.5em }
h3 { font-size: 1.17em }
h4 { font-size: 1em }
h5 { font-size: 0.83em }
h6 { font-size: 0.67em }
small, sub, sup { font-size: smaller }
big { font-size: larger }
sup { vertical-align: super }
sub { vertical-align: sub }

ul, menu, dir { list-style-type: disc }
ol { list-style-type: decimal }
ol[type="1"], li[type="1"] { list-style-type: decimal }
ol[type="a"], li[type="a"] { list-style-type: lower-alpha }
ol[type="A"], li[type="A"] { list-style-type: upper-alpha }
ol[type="i"], li[type="i"] { list-style-type: lower-roman }
ol[type="I"], li[type="I"] { list-style-type: upper-roman }
ul, ol, menu, dir { padding-left: 2.5em }
dd { margin-left: 2.5em }
blockquote { margin: 1em 2.5em }
```

Resultado: `h1`, `h2` e `h3` saem `larger`; `h4`, `same`; `h5` e `h6`,
`smaller` (razões 2, 1,5, 1,17, 1, 0,83 e 0,67). `rp` **não** está no
`display: none` do HTML aqui **(decisão da spec, #10)**: o galley achata o
ruby, e o `rp` existe justamente para quem não tem ruby (sem ele, "漢字(かんじ)"
vira "漢字かんじ"). `noscript` fica visível (o galley não roda script, como o
HTML manda para esse caso). O recuo de lista usa `padding-left` (o HTML usa
`padding-inline-start`, que é lógico): em livro `rtl` o lado fica errado, sem
efeito no perfil `uniform`, que não honra padding. A folha não tem nenhum
combinador: o `circle`/`square` das listas aninhadas do HTML §15.3.8
(`:is(dir, menu, ol, ul) :is(dir, menu, ul)` e o de três níveis) vem do nível
de lista herdado, como as dicas de §8.2 (#40), porque um descendente na folha
padrão subiria até 256 ancestrais por lista sem pagar orçamento.

Mudar esta folha muda a IR: a mudança exige bump de `IR_SCHEMA_VERSION`
([08](../08-concorrencia-cache.md) §4.1), porque a folha padrão não está na
lista de folhas da chave.

### 8.2 Dicas de apresentação

Duas regras do HTML dependem de presença de atributo ou de comparação sem
caixa, que o subconjunto de seletores não tem; a cascata as aplica direto,
como declarações da origem **folha padrão**, normais, com especificidade
(0,1,0) — a de `[hidden]` e `[dir=rtl]` — e ordem depois das regras da folha
padrão **(decisão da spec, #9)**:

| Atributo | Declaração |
|---|---|
| `hidden` presente, com qualquer valor exceto `until-found` (sem caixa) | `display: none` |
| `dir` igual a `rtl` ou `ltr` (sem caixa, sem espaço) | `direction: rtl`/`ltr` |

Como são da folha padrão, uma regra do livro com `display: block` vence o
`hidden`, exatamente como no navegador. Sem isso, o caso
`conteudo/display-none-com-texto` (`<p hidden="">`) mostraria o texto
escondido. `dir="auto"` fica com o IR (bidi).

Do mesmo jeito, com a mesma origem e depois das regras da folha padrão, sai o
tipo das listas aninhadas do HTML §15.3.8 (#40): um `ul`, `menu` ou `dir` com
uma lista (`dir`, `menu`, `ol`, `ul`) entre os ancestrais recebe
`list-style-type: circle`, com especificidade (0,0,2); com duas ou mais,
`square`, com (0,0,3). O nível é herdado do pai em O(1) (`listDepth` do
`ElementInfo`, §10.2).

## 9. Carregamento

`lib/src/css/loader.dart`, assíncrono (o prólogo de
[08](../08-concorrencia-cache.md) §1).

```dart
const int maxStyleSheetBytes = 1024 * 1024;       // por folha de arquivo, PendingResource.size
const int maxSectionStyleBytes = 4 * 1024 * 1024; // soma dos PendingResource.size por seção (#13)
const int maxStyleElementLength = 1024 * 1024;    // texto de um <style>, em unidades de código
const int maxSheetsPerSection = 64;               // <link>, <style> e @import aplicados
const int maxSheetAttemptsPerSection = 256;       // <link> e @import tentados (#28)
const int maxImportDepth = 8;                     // a folha de topo tem profundidade 0
const int maxCachedStyleSource = 8 * 1024 * 1024; // unidades de código (#15)

enum SheetSource { link, style, import }

/// Uma folha aplicada, para a chave do cache (doc/08 §4.1).
final class SheetRef {
  final SheetSource source;
  final String? path;       // arquivo: caminho real no contêiner (PendingResource.path)
  final String? bytesHash;  // arquivo: FNV-1a 64 dos bytes crus, 16 hex
  final String? text;       // <style>: o texto já lido como dado de caractere (§9.1)
}

final class AppliedSheet {
  final SheetRef ref;
  final StyleSheet sheet;
  final String href;        // href dos diagnósticos desta folha: path, ou a seção para <style>
}

/// Folhas de uma seção, **na ordem da cascata** (importadas antes de quem
/// importa; a mesma folha importada duas vezes aparece duas vezes). No
/// máximo [maxSheetsPerSection].
final class SectionSheets {
  static const empty = SectionSheets._(<AppliedSheet>[]);
  final List<AppliedSheet> sheets;
  List<SheetRef> get cacheKey;   // sheets.map((s) => s.ref)
}

/// Folhas parseadas, e as faltas, reaproveitadas entre as seções de uma
/// publicação (os capítulos repetem a folha). LRU pelo tamanho do fonte.
final class StyleSheetCache {
  StyleSheetCache({int maxSource = maxCachedStyleSource});
}

/// Junta as folhas de [document] (a seção em [sectionPath]). Não fecha o
/// contêiner. Nunca lança por causa do CSS; a exceção de `strict` do [sink]
/// ou do [containerSink] propaga como está.
///
/// [sink]: o sink **da seção**, onde o CSS emite (o conjunto por seção de
/// doc/09 §3.1; como ele entra no agregado do documento é do sub-projeto 4).
/// [containerSink]: o sink com que [container] foi aberto. O `EpubContainer`
/// não o expõe (a interface tem `paths`, `exists`, `fetch`, `obfuscationOf` e
/// `close`; o `ZipContainer` e o `PendingResource` guardam o sink em campo
/// privado), então ele vem por parâmetro. Só serve para reconhecer, por
/// identidade, a exceção de `strict` que o contêiner lança no `decode()`
/// (por exemplo `zipCrcMismatch`, §9.3); o loader nunca emite nele.
Future<SectionSheets> loadSectionSheets(
  EpubContainer container,
  Document document, {
  required String sectionPath,
  required StyleSheetCache cache,
  required DiagnosticSink sink,
  required DiagnosticSink containerSink,
});

/// Bytes de uma folha para texto (§9.4).
String decodeCss(Uint8List bytes, {required String path, required DiagnosticSink sink});
```

O placeholder de seção do sub-projeto 4, que captura as exceções da seção
para degradá-la, precisa do mesmo cuidado: relançar por identidade quando a
exceção é a última de **qualquer um** dos dois sinks (`identical(e,
sink.lastStrictException) || identical(e, containerSink.lastStrictException)`)
antes de converter.

### 9.1 Coleta

Uma caminhada em ordem de documento sobre `document.nodes` (pilha explícita,
iterando `nodes`, nunca indexando `children`, [03](../03-camada-a-ir.md) §8),
em qualquer ponto da árvore (`head` ou `body`), **sem descer em `<template>`**
(conteúdo inerte, #33):

- `<link>` no namespace HTML com `rel` contendo o token `stylesheet` e não
  `alternate` (tokens por espaço ASCII, sem caixa), `type` ausente, vazio ou
  `text/css` (sem caixa, antes de `;`), `mediaAttributeMatches(media)`,
  `href` não vazio depois de `trim`. `media` que não casa →
  `stylesheetMediaIgnored` (`href` = o caminho resolvido, ou a seção se o
  `href` for recusado), sem busca e sem contar tentativa.
- `<style>` em qualquer namespace (o `<style>` dentro de SVG inline também vale
  para o documento, como no navegador), com `media` pela mesma regra e
  `type` ausente, vazio ou **exatamente** `text/css`, sem caixa, sem parâmetro
  e sem espaço em volta (HTML, "update a `style` block"; o Chromium idem):
  `<style type="text/css; charset=utf-8">` e `<style type=" text/css ">`
  ficam de fora, enquanto o `<link>` com esses `type` vale **(#47)**.
  O texto (a concatenação dos filhos de texto) é lido como **dado de caractere
  do XML** **(decisão da spec, #22)**: o `package:html` trata `<style>` como
  texto cru do HTML, mas o arquivo é XHTML. Numa passada: `<![CDATA[ … ]]>`
  fica literal (sem os marcadores); fora de CDATA, `&lt;`, `&gt;`, `&amp;`,
  `&quot;`, `&apos;`, `&#N;` e `&#xH;` são decodificados (referência fora de
  faixa, surrogate ou `&#0;` → U+FFFD; outra entidade fica literal). Assim
  `div &gt; p` vira `div > p`, como num leitor XML. **Exceção:** num leitor
  XML, `<!-- … -->` dentro de `<style>` é comentário e o conteúdo some; aqui
  ele fica no texto e vai ao tokenizador do CSS, que trata `<!--` e `-->` como
  `cdo`/`cdc` e aplica o que está entre eles — o comportamento do HTML e dos
  leitores que parseiam EPUB como HTML, e o que o autor do velho truque
  `<style><!-- p {…} --></style>` quer (§7.5). Texto acima de `maxStyleElementLength` →
  `stylesheetIgnored` `too-large` (`href` = a seção).
- `type` diferente (`text/less`) → ignorado em silêncio (não é CSS).

### 9.2 Caminhos

`href` de `<link>` resolvido contra `dirnameOf(sectionPath)`; `href` de
`@import`, contra `dirnameOf` do caminho real da folha que importa; `@import`
num `<style>`, contra a pasta da seção. Para cada `href`:

- `isRemoteHref` → `resourceMissing` (`warning`, `href` = a URL, `details:
  {reason: 'remote'}`), sem busca.
- `normalizeHref` devolve `null` (outro esquema, como `data:`; `..` além da
  raiz; `:` em segmento; controle) → `resourceMissing` (`href` = o documento
  que referencia, `details: {reason: 'refused', raw}`), sem busca.
- **Tentativa dupla** (spec da Publicação §5.3): `decodePath` da forma
  normalizada, se não `null` e diferente, e depois a crua; a primeira que o
  `fetch` achar vence. `%2e%2e`, `%2F` e `%00` não atravessam nada: é o
  mesmo `decodePath` da Publicação. Nenhuma achada → `resourceMissing`
  (`href` = a forma decodificada, ou a crua, `details: {from: documento que
  referencia}`).

Nada fora do contêiner é tocado: `fetch` é a única leitura.

### 9.3 Leitura

- `PendingResource.size > maxStyleSheetBytes` → `stylesheetIgnored`
  `too-large`, sem drenar o `decode()` (como o OPF da Publicação).
- Soma dos `PendingResource.size` das folhas de arquivo já aplicadas na seção
  mais o desta passaria de `maxSectionStyleBytes` → `stylesheetIgnored`
  `limit` (`details.limit: 'bytes'`), também antes do `decode()`. O texto de
  cada `<style>`, em unidades de código, soma no mesmo teto (#39): 16
  `<style>` de 1 Mi dariam 16 Mi de parse síncrono numa seção; o `<style>` que
  passaria do teto é `limit` `bytes` com `href` = a seção.
- `decode()` drenado inteiro; o `EpubException` que o `fetch` ou o `decode()`
  lançarem é reconhecido **por identidade**: `identical(e,
  containerSink.lastStrictException)` → propaga (é o `strict` do contêiner,
  por exemplo `zipCrcMismatch`); `identical(e, sink.lastStrictException)`, o
  do sink da seção, também propaga (nada da seção emite dentro desse `try`
  hoje; a checagem é por robustez, para uma emissão futura no meio não virar
  `resourceUnreadable`); senão `resourceUnreadable` (`warning`, `href` = o candidato cuja leitura falhou,
  que pode ser o segundo da tentativa dupla,
  `details: {reason: 'unreadable', exception}`) e a folha é pulada. O contêiner
  só lança `EpubException` (o `ProviderContainer` embrulha a exceção do
  provider).

### 9.4 Codificação

`decodeCss` segue o desenho de `decodeXml` (spec da Publicação §4) com a
ordem do CSS Syntax §3.2, sem o passo do documento que referencia:

1. BOM UTF-8, UTF-16 LE ou BE → essa codificação (o BOM sai).
2. Sem BOM, os bytes começam exatamente por `@charset "` (ASCII, minúsculas,
   um espaço) e o rótulo vai até `";` dentro dos primeiros
   `encodingSniffBytes` (1 024) → o rótulo, em minúsculas, pela mesma tabela
   de `decodeXml` (`iso-8859-1`, `latin1`, `windows-1252`, `us-ascii` →
   Latin-1; outro → UTF-8), com uma diferença do CSS: `utf-16`, `utf-16le` e
   `utf-16be` declarados sem BOM contam como UTF-8 (se o `@charset` foi lido
   como ASCII, os bytes não são UTF-16). `@charset` com aspas simples, sem o
   espaço ou depois de outro byte não conta, como no CSS.
3. Senão, UTF-8.
4. UTF-8 inválido cai para Latin-1 com `encodingFallback` (`info`, `href` =
   caminho, `details: {declared, used: 'latin1'}`); UTF-16 com número ímpar de
   bytes, idem.

### 9.5 Ordem, `@import` e tetos

Na ordem de coleta (§9.1), cada `<link>` passa por `tentar` com profundidade
0 (a folha de topo), pilha vazia e `from` = a seção; cada `<style>` confere
`reservadas == maxSheetsPerSection` (se sim, `stylesheetIgnored` `limit`
`sheets`, `href` = a seção, e fim), reserva uma vaga e vai direto a `aplicar`, com profundidade 0 (os `@import` dele
resolvem contra a pasta da seção). `reservadas` conta as folhas já anexadas
**e** as em andamento **(controlador, #36)**:

```
tentar(href, base, profundidade, pilha, from):             # <link> e @import
  se tentativas == maxSheetAttemptsPerSection → stylesheetIgnored limit (attempts), uma vez; fim
  tentativas += 1
  resolver (§9.2) → candidatos normalizados (sem fetch); recusado/remoto → resourceMissing; fim
  se profundidade > maxImportDepth → stylesheetIgnored depth; fim
  se algum candidato, em minúsculas, está na pilha → stylesheetIgnored cycle; fim
  se reservadas == maxSheetsPerSection → stylesheetIgnored limit (sheets); fim
  reservadas += 1                                     # a vaga é desta folha, antes do fetch e da recursão
  ler pelo cache (§9.6) ou por fetch (§9.3); falta → reservadas -= 1; o diagnóstico dela; fim
  aplicar(folha, profundidade, pilha + candidatos + [caminho real], em minúsculas)

aplicar(folha, profundidade, pilha):
  para cada @import válido da folha (§5.2), em ordem:
    tentar(import.href, dirnameOf(caminho da folha), profundidade + 1, pilha, folha)
  anexar a folha a SectionSheets.sheets              # ocupa a vaga reservada
```

Reservar no `tentar`, e não contar só as anexadas, é o que fecha o teto numa
cadeia: sem isso, A → B → … com oito níveis em andamento veria só as folhas
já anexadas e a lista chegaria a 64 + 8. Com a reserva, `sheets` nunca passa
de 64.

Profundidade, tetos e ciclo são checados **pelo caminho normalizado, antes do
`fetch`** **(controlador, #28)**: um ciclo, um `@import` além da profundidade
8 ou um além do teto não custam leitura nenhuma. A pilha tem no máximo 9
níveis (2 candidatos e o caminho real por nível).

- **Tentativas:** `maxSheetAttemptsPerSection` (256) conta cada `<link>` e
  cada `@import` que chega a `tentar`, achado ou não, do cache ou não. Sem
  ele, 250 000 `@import` de um arquivo ausente ou grande demais dariam 250 000
  `fetch` (ou consultas ao cache) numa seção.
- **Folhas:** `maxSheetsPerSection` (64) conta toda folha reservada —
  `<link>`, `<style>` e `@import` —, inclusive repetidas. Uma folha importada
  duas vezes aplica duas vezes (desenho), e o teto fecha o leque exponencial
  (A importa B duas vezes, B importa C duas vezes…) e a folha vazia ligada
  100 000 vezes: `sheets` e `cacheKey` nunca passam de 64 entradas.

`href` dos diagnósticos de `depth`, `cycle` e `limit`: o caminho da folha não
aplicada (o candidato preferido), com `details.from` = a folha que importa (ou
a seção, para `<link>`). O parse de cada folha nova roda aqui, dentro do
prólogo assíncrono, sem ceder **(decisão da spec, #23)**: tokenizar 1 MiB
custou ~11 ms no protótipo (§11), e o sub-projeto 5 decide se vira `sync*`.

### 9.6 Cache de folhas

`StyleSheetCache` guarda, por caminho pedido (cada candidato da tentativa
dupla é consultado antes do `fetch`), uma de duas entradas **(decisão da spec,
#15)**:

- **positiva:** `StyleSheet` (com os `CssIssue`), caminho real, `bytesHash`,
  `PendingResource.size` e o `encodingFallback` de `decodeCss`, se houve;
- **negativa:** o motivo da falta — ausente (nenhum candidato achado),
  `too-large`, ilegível (com o texto da exceção).

E guarda `StyleSheet` por texto de `<style>` (o parse não resolve `href`, então
a mesma folha serve a seções em pastas diferentes). LRU, com teto de
`maxCachedStyleSource` unidades de código somadas. **Toda** entrada pesa o
comprimento da chave (o caminho pedido, ou o texto do `<style>`) mais o que
guarda: a positiva de arquivo, o fonte e o caminho real; a de `<style>`, o
fonte; `too-large`, o caminho real; ilegível, o caminho e o texto da exceção;
ausente, só a chave **(#48)**. Com peso 0, as faltas nunca eram expulsas, e
como o `href` não tem teto, 1 000 seções com 256 `<link>` ausentes e
distintos de 4 KiB retinham ~2 GB a partir de um EPUB de ~10 MB. A entrada
mais pesada que o teto não entra. Uma falta de cache custa só uma releitura.

**Dois sinks, e o que cada um recebe** **(controlador, #32)**:

- O **sink do contêiner** recebe o que o contêiner emite — `pathCaseMismatch`
  no `fetch`, `zipCrcMismatch` no `decode()` —, **uma vez por publicação**,
  quando a folha é lida de fato. Não há reemissão: são diagnósticos do
  recurso, não da seção, e o cache existe justamente para não reler.
- O **sink da seção** recebe o que o **CSS** emite, e é isso que a entrada do
  cache guarda para reemitir, de modo que o conjunto por seção de
  [09](../09-erros-diagnosticos.md) §3.1 não dependa de a folha ter vindo do
  cache: o `encodingFallback` de `decodeCss`, os `CssIssue` do parse e a falta
  (`resourceMissing`, `stylesheetIgnored` `too-large`, `resourceUnreadable`),
  esta montada de novo com o `href` e o `from` da seção atual.

`decodeCss` é síncrono e emite num `DiagnosticSink()` **temporário**, não
estrito, criado pelo loader para a chamada (o único diagnóstico possível é o
`encodingFallback`, `info`); a lista dele vai para a entrada e é emitida no
sink da seção, na primeira carga e em cada acerto. Por isso
`DiagnosticSink.capture` não é necessário, e nenhum contrato novo é pedido ao
`fetch`. Em `strict`, um warning da falta lança no sink da seção, como na
primeira carga.

### 9.7 Lista de folhas para a chave

`SectionSheets.cacheKey`: a lista ordenada de `SheetRef` de todas as folhas
aplicadas (arquivo com caminho e `bytesHash`; `<style>` com o texto),
inclusive repetidas, no máximo 64. A folha padrão não entra (é coberta por
`IR_SCHEMA_VERSION`, §8.1); folhas ignoradas não entram (não mudam a IR).

`bytesHash` = `Fnv1a64` dos bytes crus, antes da decodificação, em 16 dígitos
hex. `lib/src/container/fnv1a64.dart` (ao lado de `sha1.dart` e `crc32.dart`)
**(decisão da spec, #19)**:

```dart
/// FNV-1a de 64 bits, incremental, exato na VM e no JS (quatro palavras de 16
/// bits; o `int` do web não tem 64 bits).
final class Fnv1a64 {
  void add(List<int> bytes, [int start = 0, int? end]);
  String get hex;   // 16 dígitos, minúsculos
}
```

É o hash que [08](../08-concorrencia-cache.md) §4.1 já escolheu (P8); o
sub-projeto 5 o reaproveita para a chave da seção.

### 9.8 Por que é linear

- Uma caminhada sobre os nós do documento; nada de `querySelectorAll`,
  `getElementsByTagName` ou `children` indexado. A leitura do `<style>` como
  dado de caractere é uma passada.
- Cada folha é buscada, decodificada e parseada uma vez por publicação
  (cache, positivo ou negativo); `decodeCss` é linear como `decodeXml`.
- No máximo 256 tentativas e 64 folhas por seção, seja qual for o número de
  `<link>` e `@import`; a pilha de ciclo tem ≤ 27 entradas, então a
  verificação de ciclo é O(1) por tentativa, e vem antes do `fetch`.
- O teto de 4 MiB por seção limita os bytes que o parse pode receber de uma
  seção nova, e o de 1 MiB por folha evita drenar uma entrada enorme.
- A reemissão do cache custa O(`CssIssue` + 1) por folha aplicada, limitado
  pela agregação por folha (§12.1).

## 10. Índice de regras e cascata

### 10.1 Entrada e saída

```dart
const int maxCascadeDepth = 256;
const int cascadeBudget = 1 << 22;
const int cascadeYieldSteps = 4096;
const int maxRulesPerSection = 20000;
const int maxStyleAttributeLength = 8 * 1024;    // unidades de código

/// Recebe o resultado de computeStyles (decisão da spec, #20).
final class CascadeResult {
  /// `StateError` antes de o gerador terminar.
  SectionStyles get styles;
}

/// Cascata da seção (doc/08 §1): um `yield` a cada [cascadeYieldSteps] passos
/// (§10.6). Ao terminar, [into] recebe o resultado. Não muda o DOM.
Iterable<void> computeStyles(
  Document document,
  SectionSheets sheets, {
  required String sectionPath,
  required DiagnosticSink sink,
  required CascadeResult into,
  bool recordOrigins = false,
});

/// Drena [computeStyles] (testes e chamadores síncronos).
SectionStyles computeStylesSync(
  Document document,
  SectionSheets sheets, {
  required String sectionPath,
  required DiagnosticSink sink,
  bool recordOrigins = false,
});
```

### 10.2 Caminhada

Pilha explícita de quadros sobre `nodes` (sem recursão, sem indexar
`children`). Ao entrar num elemento-pai, uma passada pelos `nodes` dele monta,
para cada filho-elemento, um `ElementInfo` (privado): nome em minúsculas, se é
do namespace HTML, `id`, classes num **`Set<String>`** (tokens por espaço
ASCII: `class="a a"` vira `{a}`, e o teste de classe de um composto é O(1),
não um `contains` numa lista), o índice (base 1) entre os irmãos-elemento, o
total deles, o quadro do pai e o nível de lista (quantos ancestrais são
`dir`, `menu`, `ol` ou `ul`, herdado do pai em O(1), #40). Ao montar o `ElementInfo`, cada identificador
do elemento — o nome, o `id` e cada classe — é baixado para minúsculas e tem
o `hashCode` calculado **uma vez**: esses dois valores ficam no `ElementInfo`
e servem ao filtro de Bloom (entrada e saída), que nunca refaz hash de texto
do elemento (#34). As consultas a balde usam `Map` padrão e, no dart2js,
refazem o `hashCode` da classe ou do `id` do elemento a cada consulta; mas há
uma consulta por índice (o do livro e o da folha padrão) por identificador e
por elemento, então o custo total é O(2 × o texto de `id` e `class` do
documento), linear, e fica fora do casamento (§10.4). A caminhada não desce em
`<template>` (#33): o
`template` recebe estilo (`display: none` da folha padrão), os descendentes
dele não. `:first-child`, `:last-child`, `:nth-child(n)` e `+`
(o irmão anterior é `infos[i - 1]`) ficam O(1).

Cada elemento, em ordem de documento:

1. Profundidade ≤ `maxCascadeDepth` (a raiz `html` é 1): casamento e cascata
   (§10.4, §10.5).
2. Abaixo dela: o estilo "herdado puro" do pai — as propriedades herdadas
   copiadas, as não herdadas no inicial, `fontSizeStep: same` — sem casar
   regras nem ler `style=""`, e um `stylesheetIgnored` `limit`
   (`details.limit: 'dom-depth'`, `href` = a seção) por seção **(decisão da
   spec, #17; muda o desenho)**. O desenho diz "herda o estilo do pai"; herdar pela regra do
   CSS, e não copiar o estilo inteiro, evita que um `fontSizeStep: larger` do
   pai se repita em cada nível (o IR acumula).
3. O `ComputedStyle` (internado, §10.5) vai para o mapa, **inclusive** de
   elemento com `display: none` e dos filhos dele (fora a subárvore de
   `template`).

A raiz herda de `ComputedStyle.initial`.

### 10.3 Índice

```dart
enum CssOrigin { userAgent, author, styleAttribute }

final class RuleEntry {
  final Selector selector;
  final List<Declaration> declarations; // o bloco, partilhado pelos seletores da lista
  final int seqBase;                    // ordem: seq da 1ª declaração do bloco
  final CssOrigin origin;               // userAgent ou author
}

final class RuleIndex {
  RuleIndex(Iterable<(StyleRule, CssOrigin, String href)> rules, {int maxEntries});
  List<RuleEntry> byId(String id);
  List<RuleEntry> byClass(String className);
  List<RuleEntry> byTag(String lowerName);
  List<RuleEntry> get universal;
  int get length;
  String? get truncatedAt;              // href da folha onde o teto cortou
}
```

Uma entrada por seletor da lista, no balde da parte mais à direita: o `id` se
houver; senão a **primeira** classe; senão o tipo (minúsculas); senão
`universal` (atributo e pseudo-classe sozinhos, `*`). O `seq` é um contador
global crescente na ordem da cascata: as folhas de `SectionSheets` em ordem,
as regras de cada uma em ordem, as declarações de cada bloco em ordem. O índice
da folha padrão é montado uma vez (junto de `userAgentSheet`); o do livro, por
seção. Passou de `maxRulesPerSection` entradas: o resto não entra e emite
`stylesheetIgnored` `limit` (`details.limit: 'rules'`, `href` = a folha em que
parou) **(decisão da spec, #14: conta seletores, que é o que custa)**.

Candidatos de um elemento: `byId(id)` + `byClass(c)` para cada classe (sem
repetição, §10.2) + `byTag(nome)` + `universal`, nas duas origens. Cada entrada
está num balde só, então não há candidato repetido.

### 10.4 Casamento

Da direita para a esquerda, a partir do composto mais à direita, com os
estados do casador do Blink (`SelectorChecker`):

- **composto** falha no elemento → `failsLocally`;
- **`+`:** sem irmão anterior → `failsAllSiblings`; senão, o resultado do resto
  no irmão anterior;
- **`>`:** sem pai → `failsCompletely`; senão, o resultado do resto no pai;
- **descendente:** para cada ancestral, de baixo para cima, casa o resto; para
  no primeiro `matches` ou `failsCompletely` (`failsLocally` e
  `failsAllSiblings` seguem para o ancestral de cima); esgotados os
  ancestrais → `failsCompletely`.

`failsCompletely` é o que torna `a a a … b` linear: se o resto não casa em
nenhum ancestral a partir de `X`, não vai casar a partir de um ancestral de
`X`, que vê um subconjunto deles; então o laço externo para em vez de
retroceder. Com só descendentes, o custo por candidato é O(seletores simples
× profundidade) ≤ 32 × 32 × 256.

**Filtro de Bloom** dos ancestrais, contador, `Uint8List(4096)`: ao descer
para os filhos de um elemento, soma 1 nas duas posições (os 12 bits baixos e
os 12 seguintes do `hashCode`, com uma semente por tipo: nome, classe, `id`)
do nome, do `id` e de cada classe dele; ao subir, subtrai. Os dois lados
**baixam para minúsculas ASCII** antes do hash — o elemento ao entrar no
filtro e o seletor ao montar os hashes —, para que um tipo fora do namespace
HTML, uma classe ou um `id` com maiúsculas nunca deem falso negativo; a
comparação exata (com caixa, §6.1) continua no teste do composto. Contador
que chega a 255 fica preso (nunca desce): só gera falso positivo. Cada
`Selector` guarda até 4 hashes dos compostos que **precisam** ser ancestrais —
os que têm, **imediatamente** à direita, um combinador descendente ou `>`
(`a > b + c`: `a` é ancestral de `c`; `a + b c`: `a` não é, porque o
combinador imediatamente à direita dele é `+`) — primeiro `id`, depois
classes, depois tipo. Antes de testar um candidato com hashes, se algum não
está no filtro, o candidato é rejeitado em O(1) — e essa rejeição também
custa um passo (§10.6).

Ordem dos testes num composto: `id`, tipo, classes, atributos,
pseudo-classes (o mais barato e mais seletivo primeiro); cada seletor simples
testado custa um passo.

**Por que cada passo é O(1)** **(controlador, #34)**. Três operações dependem
do tamanho de uma `String`: calcular `hashCode`, comparar com `==` e baixar a
caixa. No dart2js o `hashCode` de `String` não fica em cache (é recalculado a
cada chamada, em O(tamanho)), então nenhuma delas pode tocar texto sem limite
dentro de um passo:

- **Lado do seletor:** tipo, classe, `id`, nome e valor de atributo têm no
  máximo 256 unidades de código (§6.3), e os hashes do seletor (baldes e
  Bloom) são calculados uma vez, no parse. Um passo que faz hash de um
  identificador do seletor (o `Set.contains` da classe, o `attributes[nome]`)
  custa ≤ 256.
- **Lado do elemento:** a classe ou o `id` do elemento podem ser enormes (um
  `class` de 1 MiB). O `==` com o identificador do seletor para no primeiro
  caractere diferente e, com tamanhos diferentes, nem começa: custa ≤ 256
  (com um só lado limitado, o `==` é limitado). O hash e as minúsculas do
  elemento saem uma vez por elemento, ao montar o `ElementInfo` (§10.2), e
  entram no contador de cessão pelo tamanho (um passo a cada 64 unidades de
  código lidas). As consultas a balde refazem o hash do identificador do
  elemento (`Map` padrão, no dart2js), mas são uma por índice, por
  identificador e por elemento, e são pagas como uma passada extra sobre o
  texto de `id` e `class` do documento, linear; dentro do casamento, nenhum
  passo faz hash de texto do elemento. O `Set<String>` das classes guarda as strings do elemento, cujo hash é
  calculado ao inserir; o `contains` faz hash do lado do seletor.
- **Valor de atributo:** `attributes[nome]` faz hash do nome do seletor
  (≤ 256); o `==` com o valor do elemento, ≤ 256.

Um `.x…` ou um `[a="…"]` de 1 MiB no seletor fica fora do subconjunto no
parse (linear), e um elemento com `class` de 1 MiB custa O(1 MiB) uma vez, ao
entrar na caminhada: o caso hostil de §14.3 cobre os dois.

### 10.5 Cascata

Para cada elemento, um vetor de slots, um por `CssProperty`
(`CssProperty.values.length`: as de §7.1, `textDecoration` incluída, e as cinco
degradadas de §7.4), zerado em O(1) por geração. Cada declaração casada
disputa o slot da propriedade dela pela chave `(camada, anexado,
especificidade, seq)`, comparada **campo a campo** (quatro inteiros, sem
empacotar num só); a maior vence (a ordem da cascata do CSS Cascade 4: origem
e importância, estilo anexado ao elemento, especificidade, ordem de aparição):

| Camada | Declarações |
|---|---|
| 0 | folha padrão e dicas de §8.2, normais |
| 1 | livro, normais (folhas e `style=""`) |
| 2 | livro, `!important` (folhas e `style=""`) |
| 3 | folha padrão, `!important` (a folha de §8.1 não tem nenhuma; a camada existe para a ordem ficar certa) |

`anexado` = 1 para `style=""` (vence qualquer seletor da mesma camada, mas um
`!important` de folha vence o `style=""` normal); `seq` desempata e, dentro de
um bloco, a última declaração vence. Um mesmo bloco casado por dois seletores
da lista disputa duas vezes com o mesmo `seq`, e vence a maior especificidade
— a regra do CSS para listas. Nada de `<<` nem `|` para juntar os campos: no
dart2js os operadores de bits truncam em 32 bits, e `camada << 32` daria 0.

Não há ordenação: cada declaração custa uma comparação. Depois, para cada
propriedade (`direction` é computada antes de `textAlign`):

- sem vencedor: herdada → valor do pai; não herdada → inicial (§7.1);
- `inherit` → valor do pai; `initial` → inicial; `unset` → herdada ? pai :
  inicial (`fontSize`: sempre `same`, §7.1);
- relativos: `bolder`/`lighter` sobre o `weight` do pai; tipo de lista
  desconhecido pelo elemento (§7.1); `alignKeyword` guardado e `textAlign`
  resolvido pela `direction` já computada do elemento;
- **decoração** (#24): `underline` = `underline` em vigor no pai **ou** a linha
  que o vencedor do slot `textDecoration` declara neste elemento; idem
  `lineThrough`. `none`, `inherit`, `initial` e `unset` não tiram nada do que
  vem do pai (propagação, não herança: §7.1).

O `ComputedStyle` montado passa por um mapa de internação da cascata
(`Map<ComputedStyle, ComputedStyle>`, igualdade por valor). `style=""` é lido
do atributo, e o texto parseado uma vez por seção (cache
`Map<String, List<Declaration>>`); acima de `maxStyleAttributeLength` →
ignorado, `stylesheetIgnored` `too-large` (`href` = a seção,
`details.source: 'style-attribute'`), uma vez por seção. Declarações de
`style=""` descartadas por sintaxe somam num `cssRuleIgnored` `parse-error`
(`href` = a seção, `details.source: 'style-attribute'`) emitido no fim.

Com `recordOrigins`, a origem do vencedor de cada slot fica num mapa paralelo
(`originOf`, §3) **(decisão da spec, #21)**.

### 10.6 Orçamento e cessão

Dois contadores **(controlador, #27)**:

- **Cessão** — conta **todo** o trabalho: cada elemento visitado, cada 64
  unidades de código de nome, `id` e `class` lidas ao montar o `ElementInfo`
  (partir, baixar a caixa, fazer hash), cada 2 unidades de código de um
  `style=""` novo parseado (o parse custa ~10 µs por KiB contra ~60 ns de um
  passo; só na cessão, revisão do plano), cada consulta a balde, cada
  candidato considerado, cada seletor simples testado, cada declaração aplicada, da
  folha padrão, das dicas, do `style=""` e do livro. A cada
  `cascadeYieldSteps` desses passos, `yield`, no padrão do `decode()` do
  contêiner (um `yield` por lote de trabalho). A linha da cascata em
  [08](../08-concorrencia-cache.md) §3 passa a dizer "a cada 4 096 passos" em
  vez de "a cada regra".
- **Orçamento** — conta só o trabalho das **regras do livro**: cada consulta a
  balde do índice do livro (o do `id`, um por classe do elemento, o do tipo e
  o universal), cada candidato considerado, **inclusive** os rejeitados pelo
  filtro de Bloom, cada seletor simples testado (inclusive em cada ancestral
  tentado pelo descendente) e cada declaração do livro aplicada. Cada passo
  desses é O(1): classes em `Set`, compostos de no máximo 32 seletores
  simples (§6.3), comparação por campo.

`cascadeBudget` (2^22, #38; o maior uso real no corpus é 71 525 passos, em
`song-of-myself.xhtml`) é o teto do orçamento. Esgotado:

- **o elemento em andamento** descarta o que já tinha aplicado do livro e é
  refeito só com a folha padrão, as dicas e o `style=""` **(decisão da spec,
  #31)** — custo constante, e o resultado não depende de em que candidato o
  orçamento acabou;
- **o resto da seção** não casa mais regras do livro; a folha padrão, as dicas
  e os `style=""` continuam **(decisão da spec, #18; muda o desenho, que dizia
  "só a folha padrão vale")** — nenhum dos três é casamento de seletor do livro,
  e o custo deles por elemento é constante;
- emite `stylesheetIgnored` `budget` (`href` = a seção) uma vez e marca
  `budgetExhausted`.

### 10.7 `unsupportedLayout`

Os slots de `float`, `position`, `columnCount`, `columnWidth` e `writingMode`
disputam a cascata como os outros. Se, no fim, o vencedor de um deles degrada
(§7.4), emite `unsupportedLayout` (`warning`, `href` = a seção, `details:
{property, value}`) **uma vez por (seção, propriedade)** **(decisão da spec,
#2)**. Emitir no vencedor, e não no parse, evita o falso positivo de uma regra
com `float` que nenhum elemento usa, ou que um `float: none` posterior
desfaz. Como o `DiagnosticSink` deduplica por (código, `href`), `float` e
`position` da mesma seção viram um registro, com os `details` do último
(aproximação de §7.5).

### 10.8 Por que é linear

- A caminhada visita cada nó uma vez; cada `ElementInfo` é montado uma vez,
  quando o pai é visitado (a passada pelos `nodes` do pai soma, no total, o
  número de nós), e os tokens de classe entram na cessão.
- As classes do elemento são um `Set`: `class="a a a …"` não visita o balde
  `a` N vezes, e o teste de classe é O(1). Identificadores do seletor têm no
  máximo 256 unidades de código e os do elemento têm hash e minúsculas
  calculados uma vez por elemento (§10.4): nenhum passo toca texto sem
  limite. O mesmo `id` em muitos elementos é
  só uma consulta O(1) por elemento.
- **Todo** o trabalho das regras do livro paga orçamento: consulta a balde,
  candidato (aceito ou rejeitado pelo Bloom), seletor simples, declaração. Um
  livro com 20 000 regras `x p` sobre 100 000 `<p>` esgota 2^22 passos em vez
  de fazer 2×10⁹ operações de graça. Cada passo é O(1) (32 seletores simples
  por composto, `Set`, comparação por campo), então o casamento do livro custa
  O(2^22) por seção, e o resto — folha padrão (índice fixo, pequeno e sem
  combinador, #40), dicas,
  `style=""` — é O(elementos + texto dos atributos).
- `failsCompletely` impede o retrocesso; 32 compostos e 256 níveis limitam
  cada teste.
- A cascata não ordena: uma comparação por declaração casada, e um vetor de
  `CssProperty.values.length` slots por elemento.
- Internação e `style=""` são mapas: O(campos) e O(texto) uma vez por texto.
- Profundidade do DOM sem limite na caminhada (pilha explícita), com casamento
  só até 256.

## 11. Limites

Números medidos no corpus (65 EPUBs) e num protótipo de tokenizador e de
contagem de candidatos (Dart 3.13.4, JIT, i5-11400H; rascunho fora do
repositório; a tarefa de desempenho do plano refaz com o código real):

| Limite | Valor | Maior visto no corpus | Justificativa |
|---|---|---|---|
| Folha | 1 MiB (`maxStyleSheetBytes`), por `PendingResource.size` antes do `decode()` | 7 175 bytes (`core.css` do Standard Ebooks); 54 folhas, 106 KB somadas | 146× o maior real; tokenizar 1 MiB de CSS real repetido custou ~11 ms no protótipo |
| CSS por seção | 4 MiB (`maxSectionStyleBytes`), soma dos `PendingResource.size` antes do `decode()` e das unidades de código dos `<style>` **(decisão da spec, #13, #39)** | 14 KB (as três folhas do SE) | sem ele, 64 folhas de 1 MiB dariam 64 MiB de parse numa seção; 4 MiB fica em ~50 ms de tokenização e ainda é ~290× o real |
| Folhas por seção | 64 (`<link>`, `<style>` e `@import` aplicados) | 3 | fecha o leque de `@import` repetido e limita `sheets`/`cacheKey` |
| Tentativas por seção | 256 `<link>` + `@import` (`maxSheetAttemptsPerSection`) **(controlador, #28)** | 3 | 4× o teto de folhas: sobra para faltas legítimas sem permitir 250 000 `fetch` |
| `<style>` | 1 Mi unidades de código (`maxStyleElementLength`) | 7 blocos, todos curtos | o mesmo número da folha de arquivo, na unidade do texto |
| Seletores por seção | 20 000 (`maxRulesPerSection`) | 123 seletores em 77 regras | 160× o real |
| Profundidade de `@import` | 8 | 0 (o corpus não tem `@import`) | cadeias reais têm 1 ou 2 |
| Aninhamento de blocos | 32 | 2 (`@media { regra { } }`) | recursão do parser limitada |
| `style=""` | 8 KiB | 78 caracteres (562 atributos) | 100× o real |
| Compostos por seletor | 32 | 6 (`hgroup > h2 + p + p + p + p`) | limita o retrocesso |
| Seletores simples por composto | 32 **(controlador, #27)** | 3 | torna O(1) cada teste de composto contado no orçamento |
| Identificador ou valor de atributo no seletor | 256 unidades de código (`maxSelectorIdentifierLength`) **(controlador, #34)** | 65 (`.epub-type-contains-word-se-image-color-depth-black-on-transparent`); nos elementos, 73 | mantém O(1) o hash e a comparação dentro de um passo (§10.4) |
| Profundidade de casamento | 256 | 7 | o filtro de Bloom e o descendente sobem no máximo 256 |
| Orçamento | 2^22 passos das regras do livro (consultas a balde, candidatos, seletores simples, declarações, §10.6) **(#38)** | 71 525 (1,7%) em `song-of-myself.xhtml` (131 KB, 2 816 elementos, com `core.css` e `local.css` do SE), medido com o código real | ~58× o maior real. O pior caso medido (20 000 regras `div … div p` de 32 compostos sobre 250 `div` aninhados) custa ~0,17 s na cascata (JIT, i5-11400H) e ~0,45 s com duas suítes de teste em paralelo; era ~0,9 s com 2^24 |
| Cessão | 4 096 passos de todo o trabalho (§10.6) | — | lote pequeno o bastante para a fatia de 4 ms de [08](../08-concorrencia-cache.md) §2 mesmo com passo caro, grande o bastante para o `yield` não pesar |
| Cache de folhas | 8 Mi unidades de código **(decisão da spec, #15)** | 106 KB (o corpus inteiro) | 8 folhas no teto por publicação |
| Amostra em `details` | 64 unidades de código | — | como a data crua da Publicação |
| Literal numérico | 64 caracteres | — | `double.tryParse` sobre fatia curta |

Passou de um limite: corta com diagnóstico (§12) e a cascata continua.

## 12. Diagnósticos e exceções

### 12.1 Códigos

Quatro em `EpubDiagnosticCode`: `unsupportedLayout` entra agora (estava em
doc/09 e no `knownDiagnostics` do corpus, não no código); `stylesheetIgnored`,
`stylesheetMediaIgnored` e `cssRuleIgnored` são novos, os de motivo no formato
do `navIgnored` (`details.reason`).

| Código | Severidade | `href` | `details` | Quando |
|---|---|---|---|---|
| `stylesheetIgnored` | warning | a folha ignorada ou cortada; a folha que importa, para `late-import` e `unsupported-import`; a seção para `<style>`, `style=""`, `dom-depth` e `budget` | `reason`; `from` (quem referencia, em `depth`/`cycle`/`limit`); `limit` (`sheets`, `attempts`, `bytes`, `rules`, `nesting`, `dom-depth`); `import` (href cru, em `late-import` e `unsupported-import`); `source: 'style-attribute'` | folha (ou parte dela) perdida por limite, ciclo ou posição; ver `reason` abaixo |
| `stylesheetMediaIgnored` | info | a folha ignorada (`<link>`, `@import`); a seção para `<style>`; a folha que contém, para blocos `@media` | `media` (a lista, truncada em 64); `discarded` (blocos `@media` agregados, §5.1) | `media` que não casa (§5.1, §5.2, §9.1) **(controlador, #25)** |
| `cssRuleIgnored` | info | a folha; a seção para `style=""` | `reason`; `sample` (prelúdio ou seletor truncado em 64); `discarded`; `source` | regra, seletor ou declaração descartada |
| `unsupportedLayout` | warning | a seção | `property` (`float`, `position`, `columns`, `writing-mode`), `value` | valor degradado venceu a cascata (§10.7) |

**Por que `media` tem código próprio.** A severidade é do código
(`EpubDiagnosticCode.defaultSeverity`), e a regra de `strict` do corpus
([10](../10-testes.md) §5) lê só os códigos do `.expected`: com `media` como um
motivo `info` de um código `warning`, um caso com uma folha `print` teria de
sair do `strict` por um diagnóstico que não é defeito nenhum — e o dedupe por
(código, `href`) ainda podia fundir um `media` com um `late-import` da mesma
folha. Um código `info` separado deixa `stylesheetIgnored` sempre `warning`.

`reason` de `stylesheetIgnored`:

| `reason` | Situação |
|---|---|
| `too-large` | folha acima de 1 MiB, `<style>` acima de 1 Mi unidades de código, `style=""` acima de 8 KiB |
| `cycle` | `@import` que volta a uma folha da pilha |
| `depth` | `@import` além da profundidade 8 |
| `limit` | teto de folhas, de tentativas, de bytes por seção, de seletores, de aninhamento ou de profundidade de DOM (`details.limit`) |
| `late-import` | `@import` fora de posição: depois de regra, dentro de `@media` ou de bloco de estilo (§5.2, §5.3) |
| `unsupported-import` | `@import` com `layer`, `layer(…)` ou `supports(…)` (§5.2) |
| `budget` | orçamento da cascata esgotado |

`reason` de `cssRuleIgnored`: `parse-error` (sintaxe: prelúdio inválido,
declaração que não parseia, lixo até o `;`), `unsupported-selector` (seletor
válido fora do subconjunto, §6.3) e `nested-rule` (regra ou at-rule aninhada
num bloco de estilo, §5.3). **Agregado** **(decisão da spec, #16)**: no máximo
um por (motivo, folha, seção), com `discarded` = quantos e `sample` = o
primeiro; `stylesheetMediaIgnored` de blocos `@media`, idem, um por folha e
seção. É o `count` do `DiagnosticSink` que soma as seções. (`count` é reservado
do sink; por isso `discarded`.)

Reusados: `resourceMissing` (§9.2), `resourceUnreadable` (§9.3),
`encodingFallback` (§9.4), no sink da seção. Os do contêiner
(`pathCaseMismatch`, `zipCrcMismatch`) ficam no sink do contêiner, uma vez por
publicação, sem reemissão (§9.6). O `DiagnosticSink` deduplica por
(código, `href`): dois motivos de `stylesheetIgnored` na mesma folha viram um
registro, com os `details` do último — ambos `warning`, e com `strict` o
primeiro já lançou; fora dele, o conjunto de códigos, que é o que o corpus
compara, não muda. Registrado em [14](../14-pendencias.md), como a fusão
parecida da Publicação.

### 12.2 Nunca fatal

Nenhuma falha de CSS derruba a seção nem o livro ([09](../09-erros-diagnosticos.md)
§1). Tokenizador, parser, seletores, propriedades e cascata são funções
totais sobre a entrada: não chamam `int.parse`/`double.parse` (só
`double.tryParse`), não indexam fora do tamanho (todo acesso por índice é
guardado pelo laço), não usam `RegExp` sobre dado do livro, não lançam
`StateError` (o `StateError` de `CascadeResult.styles` e de `originOf` é erro de
programação do chamador, não de entrada). O loader só captura `EpubException`
do contêiner (§9.3).

### 12.3 `strict`

Todo `emit` do CSS passa `onStrict: (m) => EpubSectionParseException(m, href:
href)` **(decisão da spec, #1)**: a exceção já está na taxonomia de
[09](../09-erros-diagnosticos.md) §2 ("XHTML irrecuperável", não fatal) e o CSS
é parte do parse da seção ([03](../03-camada-a-ir.md) §1); é criada agora em
`exceptions.dart`, interna até o sub-projeto 6. Em `strict`, então,
`resourceMissing`, `resourceUnreadable`, `unsupportedLayout` e
`stylesheetIgnored` lançam `EpubSectionParseException` com o nome do código na
mensagem (`stylesheetMediaIgnored`, `cssRuleIgnored` e `encodingFallback` são
`info` e não lançam);
a exceção do sink do contêiner que atravessa o `fetch`/`decode()` (por
exemplo `zipCrcMismatch`) propaga como está, reconhecida por identidade
contra `containerSink.lastStrictException` (§9, §9.3); e o placeholder do
sub-projeto 4 relança por identidade a última exceção de qualquer um dos dois
sinks, o da seção e o do contêiner (§9).

```dart
/// Falha de parse de uma seção (doc/09 §2). Nunca chega ao app fora de
/// `strict`: vira seção degradada e diagnóstico. Em `strict`, é também o
/// tipo que um warning do CSS lança.
final class EpubSectionParseException extends EpubException {
  EpubSectionParseException(super.message, {super.href, super.cause});
  @override
  String get typeName => 'EpubSectionParseException';
}
```

## 13. Defeitos recorrentes da Publicação

Os tipos de bug que mais apareceram na revisão da Publicação (o tempo
quadrático em três formas), e onde esta spec os fecha:

| Defeito | Como o CSS evita |
|---|---|
| Tempo quadrático: `substring` em laço | Tokenizador com índice que só avança e uma fatia por token (§4.1); nenhum `split`/`RegExp` sobre o texto do livro; o prelúdio é juntado uma vez (§5.5); a tentativa de declaração para no ponto em que falha, em vez de varrer o resto do bloco a cada item (§5.3, §5.5); nenhum passo de casamento faz hash ou compara texto sem limite (256 unidades no seletor, hash do elemento uma vez, §10.4) |
| Tempo quadrático: busca de descendente | Uma caminhada só, sobre `nodes` com pilha explícita (§9.1, §10.2); nada de `querySelectorAll`, `children` indexado ou subida pelo `parent` em laço fora do casamento, que é limitado por `failsCompletely`, Bloom, 32 compostos de 32 seletores simples, 256 níveis e orçamento; e o orçamento paga **todo** o trabalho do livro — consulta a balde, candidato (inclusive o rejeitado pelo Bloom), seletor simples, declaração —, cada um O(1) (§10.4, §10.6) |
| Tempo quadrático: ids repetidos | Classes do elemento num `Set` (§10.2); balde por `id` consultado em O(1), qualquer que seja o número de elementos com o mesmo `id`; a mesma folha ligada ou importada N vezes é limitada a 256 tentativas e 64 folhas, com a vaga reservada no `tentar`, com cache negativo para a que falta (§9.5, §9.6); diagnósticos agregados por folha (§12.1) |
| Exceção fora da taxonomia | Funções totais, sem `int.parse`, com `NaN` para literal longo e faixa conferida antes de `int` (§4, §6.1, §12.2); só `EpubException` do contêiner é capturada, e a do `strict` por identidade (§9.3); fuzz com contagem zero (§14.2) |
| Travessia de caminho | `normalizeHref` e `decodePath` da Publicação, `..` além da raiz e `%2e%2e` recusados; só `fetch` do contêiner (§9.2); ciclo, profundidade e tetos checados pelo caminho normalizado antes do `fetch` (§9.5) |
| Semântica copiada errada de um padrão | Cada ponto marcado com a fonte: recuperação pelo "consume a block's contents" atual do CSS Syntax, com os casos fechados (§5.3), posição do `@import` do CSS Cascade 4 (§5.2), `mediaMatches` do Media Queries com `not print` e vírgula em parênteses (§5), camadas de origem e importância com `style=""` anexado (§10.5), `left` herdado como `left` (§3), `bolder`/`lighter` do CSS Fonts 4 (§3), `text-decoration` propagada e não herdada (§7.1), `page-break-*` como a mesma propriedade (§7.1), `@charset` só na forma exata (§9.4), `<style>` como dado de caractere do XML (§9.1), `:nth-child` inteiro e `+` contando só elementos (§6.1), classe com diferença de caixa (§6.1), `hidden` vencível pelo livro (§8.2), lista de seletores com inválido derrubando a regra e fora do subconjunto caindo sozinho (§6.3), chave da cascata sem operador de bits (§10.5); e o que é aproximado de propósito está listado em §7.5 |

## 14. Testes

Em `test/css/`, com CSS e XHTML de texto nos testes de unidade (o DOM por
`html.parse` de fragmentos pequenos, ou montado por código nos hostis):

| Arquivo | O que cobre |
|---|---|
| `tokenizer_test.dart` | cada tipo de token; comentários (inclusive sem fim); strings com `}` e `;` dentro, com `\` + LF, sem fim, `badString`; escapes (hex curto, 6 dígitos, espaço depois, `\0`, surrogate, acima de U+10FFFF, `\` no fim); `url()` sem aspas, com espaço, com aspas (vira `function`), `badUrl`; números (`.5`, `1e3`, `+3`, `-0`, literal de 100 dígitos → `NaN`); `<!--`/`-->`; CR/CRLF/FF; U+0000 |
| `parser_test.dart` | regras, lista de seletores (parcial: um seletor fora cai, os outros ficam; um inválido derruba a regra); recuperação pelo modelo "consume a block's contents" com os seis casos da tabela de §5.3 (`p { .x{…} font-style: italic }`, `a:hover{…}` aninhado, `a{};p{…}` no topo, at-rule dentro de bloco, `@import` dentro de `@media`, `@foo;` dentro de bloco); `{` e `(` no valor; `!important` com espaço e caixa; `@MEDIA`/`@Import` sem caixa; `@media` que casa e que não casa, aninhado; `@import` antes e depois de regra (`late-import`), depois de `@charset`, depois de regra `parse-error` (vale), depois de regra só com seletores fora do subconjunto (não vale), depois de `@namespace` (não vale), com media, com `layer`; at-rules descartadas; aninhamento 33 (`limit`); agregação de `CssIssue`; `parseStyleAttribute`; `mediaMatches` sobre tokens (tabela: vazio, `all`, `screen`, `only screen`, `SCREEN`, `screen, print`, `print`, `not print` (casa), `not screen`, `not all`, `not amzn-kf8` (casa), `screen and (max-width: 600px)`, `(a, b), screen` (a vírgula do parêntese não separa: casa pela segunda query), `screen and (a, b)` (não casa), `amzn-kf8`, lixo); `mediaAttributeMatches(null)` |
| `selector_test.dart` | cada forma de §6.1 e cada caso de §6.3 com o destino certo (no subconjunto, válido fora, inválido): lista fechada de pseudo-classes e pseudo-elementos, `:foo` e `::-moz-x` inválidos, `:hover` e `::before` válidos fora, `:nth-child(3)`, `(+3)`, `(0)`, `(99999999999)`, `(odd)`, `(2n+1)`, `(3.0)` e `(foo)`; nomes sem caixa; especificidade (tabela do Selectors 4 e saturação); lista parcial com `unsupported` e `unsupportedSample`; 32 e 33 compostos; 32 e 33 seletores simples num composto; 33 compostos seguidos de `:foo` (inválido: a gramática é validada depois do teto); hashes de ancestral (`a > b + c`, `a + b c`) em minúsculas |
| `properties_test.dart` | cada linha de §7.1 com valores aceitos, mapeados, limitados e descartados, palavras-chave sem caixa (`ITALIC`, `Bold`); conversões de §7.2; atalhos (`margin` 1–4, `font` completo e mínimo, `font` com tamanho absoluto, `list-style`, `columns`, `text-decoration` com estilo, cor e espessura); `text-decoration-line` com `overline`/`blink` ignorados e com palavra inválida; `inherit`/`initial`/`unset`/`revert`; degradadas de §7.4; `CssProperty.values.length` = número de slots |
| `ua_sheet_test.dart` | zero `CssIssue`; `h1`–`h6` com as razões de §8.1; `em`/`i` itálico, `b`/`strong` negrito, `u`/`ins` sublinhado, `s`/`strike`/`del` riscado, `head`/`script`/`style`/`template` `none`, `pre` `pre`, listas aninhadas, `ol[type]` com caixa |
| `loader_test.dart` | com `ProviderContainer` (`MapProvider`) e `ZipContainer` (`epubZip`): `<link>` (rel com vários tokens, `alternate`, `type`, `media` → `stylesheetMediaIgnored`); `<style>` em `head`, `body` e SVG, com CDATA, com `div &gt; p`, `&#x2014;`, `&#0;` e entidade desconhecida; `<style>` e `<link>` dentro de `<template>` ignorados; ordem de coleta; `@import` com `layer` (`unsupported-import`); `@import` relativo à folha, em `<style>` relativo à seção, em cadeia, duas vezes, ciclo (checado antes do `fetch`: nenhum `fetch` a mais), profundidade 9 (idem), 65 folhas contando `<link>` e `<style>`, e uma cadeia de 8 `@import` a partir da 60ª folha (a reserva no `tentar` segura em 64), 257 tentativas (250 000 `@import` de um ausente: 256 consultas, uma `limit` `attempts`), 4 MiB por `PendingResource.size`; folha de 1 MiB + 1 byte (não drenada); remota; `data:`; `..` além da raiz; `%20` e `%2e%2e`; ausente; `fetch` que lança (`resourceUnreadable`) e `strict` (a exceção do sink do contêiner propaga, reconhecida por `containerSink.lastStrictException`, com os dois sinks distintos; warning do CSS lança `EpubSectionParseException` pelo sink da seção); `decodeCss` (BOM × 3, `@charset` Latin-1, `@charset 'x'` que não conta, `@charset "utf-16"` → UTF-8, UTF-8 inválido → `encodingFallback`); cache: mesma folha em duas seções, com sinks de seção distintos, faz um `fetch` e deixa **os mesmos diagnósticos do CSS** nos dois (`encodingFallback`, `CssIssue`), enquanto o `pathCaseMismatch` de um `href` com caixa trocada aparece uma vez só, no sink do contêiner, entradas negativas (ausente, grande, ilegível: um `fetch` por publicação, o diagnóstico reemitido por seção), LRU; `cacheKey` com hash e texto, nunca acima de 64 com uma folha vazia ligada 100 000 vezes |
| `rule_index_test.dart` | balde por `id`, primeira classe, tipo, universal; `seq`; teto de 20 000 com `truncatedAt` |
| `cascade_test.dart` | herança de cada propriedade herdada e não herdada; `inherit`/`initial`/`unset`; camadas (`!important` do livro vence `style=""` normal; `style=""` vence `#id`; ordem; última declaração do bloco); especificidade de lista; `text-align: left` herdado por filho `rtl`; `bolder`/`lighter` sobre 900 e 300; tipo de lista desconhecido em `ul`, `ol`, `li`; `fontSizeStep` relativo por nível; decoração propagada (`u` dentro de `s` fica com as duas; `text-decoration: none` num filho de `u` continua sublinhado; `inherit` não soma nada novo); dicas `hidden` e `dir` e o livro vencendo `hidden`; `+`, `>`, descendente, `:nth-child`, `:last-child` com texto entre irmãos; classe e `id` com maiúsculas no Bloom; `unsupportedLayout` só no vencedor e uma vez; profundidade 257; subárvore de `template` fora do mapa; orçamento (`budgetExhausted`, a folha padrão, as dicas e o `style=""` continuam, o elemento em andamento refeito sem o livro, candidatos rejeitados pelo Bloom contados); cessão a cada 4 096 passos com o contador separado do orçamento (contagem de `yield` numa seção só com folha padrão); internação (mesma instância); `originOf` |
| `computed_style_test.dart` | `initial`; igualdade e `hashCode`; `textAlign` e `fontWeight` derivados |
| `css_corpus_test.dart` | §14.1 |
| `css_fuzz_test.dart` | §14.2 |
| `css_hostile_test.dart` | §14.3 |

E `test/container/fnv1a64_test.dart` com os vetores do FNV (`""` →
`cbf29ce484222325`, `"a"` → `af63dc4c8601ec8c`, `"foobar"` →
`85944171f73967e8`) e a mesma saída em `add` fatiado.

### 14.1 Corpus

Para cada caso de `test/corpus/**` que abre (os de `exception.expected` ficam
de fora, como na Publicação): o `ZipContainer` é aberto com um sink do
contêiner, com o `strict` do caso; `readPublication` recebe um sink próprio,
sem `strict` (a Publicação tem o teste dela); o CSS emite num sink do CSS, um
por livro no teste (o conjunto comparado é o do livro), com o `strict` do
caso, e recebe o do contêiner como `containerSink`; para cada
item do spine com `content` `xhtml`, local e presente, `fetch` + `decodeXml(…,
htmlMeta: true)` (um sink descartável: a decodificação do XHTML é do
sub-projeto 4) + `html.parse`; `loadSectionSheets` com **um** `StyleSheetCache`
por livro, o sink do CSS e o do contêiner; `computeStylesSync(recordOrigins:
true)` com o sink do CSS.

- **Códigos comparados:** o conjunto de `stylesheetIgnored`,
  `stylesheetMediaIgnored`, `cssRuleIgnored` e `unsupportedLayout` emitido pelo
  sink do CSS é igual ao desses códigos em `diagnostics.expected`; `resourceMissing`, `resourceUnreadable` e
  `encodingFallback` emitidos pelo CSS precisam constar do `.expected` (podem
  ser de outra camada).
- **Modo:** a regra de [10](../10-testes.md) §5: `strict: true` fora de
  `patologia/` e `faixa-b/`, exceto os casos cujo `.expected` lista um
  `warning` só do CSS (`unsupportedLayout`, `stylesheetIgnored`), que rodam
  sem `strict` e ganham a segunda passada em `strict` esperando
  `EpubSectionParseException` com o nome de um desses códigos na mensagem
  (#46). `resourceMissing` e `resourceUnreadable` não entram no critério: o
  `.expected` os lista também quando vêm da Publicação
  (`regressoes/capa-ausente`); se o CSS emitir um deles num caso em
  `strict`, a primeira passada lança, e o caso precisa ser revisto. Como `stylesheetMediaIgnored` é um código
  `info` (§12.1), um caso com folha `print` continua em `strict`: a regra, que
  só lê códigos, não confunde mais `media` com um `warning`.
- **Estruturais, em toda seção:** `styles.length` = número de elementos do
  documento fora das subárvores de `template`; `head`, `script`, `style` e `title` presentes têm `display:
  none`; todo `em`/`i` tem `fontStyle: italic` ou `originOf(e, fontStyle)` é
  `author`/`styleAttribute`; todo `b`/`strong`, `fontWeight: bold` com a mesma
  ressalva; nenhum `ComputedStyle` fora das faixas de §7.1.
- **Específicas:**
  - `conteudo/display-none-com-texto`: os quatro escondidos (classe,
    `style`, `hidden`, `span` inline) com `display: none`, os visíveis sem.
  - `conteudo/text-transform-uppercase`: `.up` `uppercase`, `.cap`
    `capitalize`, `.low` `lowercase`, o `span.up` dentro de `p` também.
  - `conteudo/lista-5-niveis`: os `li` de `ul.l1`…`ul.l5` com `disc`,
    `circle`, `square`, `disc`, `none`.
  - `regressoes/text-align-inline-span`: os dois `span` com `display: inline`
    e `textAlign: center`.
  - `faixa-b/float-com-contorno`, `faixa-b/columns`,
    `faixa-b/writing-mode-vertical`: `unsupportedLayout` com `property`
    `float`, `columns` e `writing-mode`.
  - `reais/moby-dick-en`, `epub/text/chapter-1.xhtml`: o `h2` com
    `fontVariant: smallCaps`, `textAlign: center` e `breakAfter: avoid`; o
    `p` do `hgroup` e o primeiro `p` depois dele com `textIndent: 0`
    (`hgroup > p`, `hgroup + p` do `core.css`), o seguinte com `textIndent:
    1`.
  - os três casos novos, abaixo.
- **Casos novos** (sintéticos, em `tool/corpus/lib/cases/`, com `README` de
  uma linha; o corpus passa de 65 para 68, e os testes que contam casos —
  `container_corpus_test`, `publication_corpus_test`, `css_corpus_test` —
  passam a esperar 68):
  - `conteudo/css-import-cadeia`: `Text/cap01.xhtml` com `<link
    href="../Styles/main.css">`; `main.css` importa `base/tipo%20grafia.css`
    (arquivo `tipo grafia.css`, exercita a tentativa dupla), que importa
    `../extra/listas.css` (relativo à folha que importa); `main.css` importa
    uma folha duas vezes e sobrescreve uma regra importada. Sem diagnóstico.
    Afirmações: cada regra de cada nível vale; a sobrescrita respeita a ordem;
    `cacheKey` com 5 entradas na ordem.
  - `conteudo/css-media-misto`: `<link media="print">`, `<link media="screen,
    print">`, `<style media="all and (min-width: 600px)">`, `@media screen`,
    `@media print`, `@media screen and (orientation: portrait)` e `@import
    url(x.css) print`, e um `<style media="not print">` que vale.
    `diagnostics.expected`: `stylesheetMediaIgnored` (roda em `strict`).
    Afirmações: só as regras de `screen`/`all` sem condição e as de `not
    print` valem.
  - `regressoes/css-latin1`: uma folha Latin-1 sem `@charset` com a classe
    `.citação` (bytes `E7 E3`) e uma com `@charset "iso-8859-1";`.
    `diagnostics.expected`: `encodingFallback` (da primeira). Afirmação: as
    duas classes casam os elementos com o nome certo.
- **Correção do corpus** (a conferir na tarefa de corpus, que atualiza os
  `.expected` pelo que o código emitir e justifica cada linha no commit): os
  8 `reais/` ganham `cssRuleIgnored` (pseudo-elementos, `:not()`,
  `:root[…]`, `a[href]`, `a:link`); os 4 do Standard Ebooks
  (`leaves-of-grass-en`, `moby-dick-en`, `origin-of-species-en`,
  `pride-and-prejudice-en`) ganham `unsupportedLayout` (`position: absolute`
  no `h1` da página de rosto e no `h2` do colofão) e `stylesheetMediaIgnored`
  (`@media all and (prefers-color-scheme…)`); `alice-ilustrada-en` ganha
  `unsupportedLayout` (`float` em `.figleft`/`.figright`).
- `test/corpus/corpus_test.dart`: `knownDiagnostics` com `stylesheetIgnored`,
  `stylesheetMediaIgnored` e `cssRuleIgnored`.

### 14.2 Fuzz

`css_fuzz_test.dart`, determinístico no CI (semente fixa): 400 mutações de
folhas e de `style=""` de quatro livros do corpus (`reais/pride-and-prejudice-en`,
`conteudo/text-transform-uppercase`, `conteudo/css-import-cadeia`,
`conteudo/css-media-misto`), metade por `ZipContainer` e metade por
`ProviderContainer`, um terço em `strict`. Mutação = inserir, trocar ou repetir
trechos de uma lista: `{`, `}`, `(`, `)`, `[`, `]`, `"`, `'`, `\`, `/*`,
`*/`, `url(`, `@import "a.css";`, `@import url(../../../x.css);`, `@media`,
`@charset "utf-16";`, `!important`, `;`, `:`, `,`, `+`, `>`, `~`, `*`, `#`,
`.`, `a a a a`, `:nth-child(99999999999999999999)`, `1e999em`,
`99999999999999999999px`, `\0`, `\FFFFFF`, `\D800`, `<!--`, `-->`,
`var(--x)`, `:foo`, `::-moz-x`, `:not(`, `:nth-child(3.0)`, `.a` repetido,
`&gt;`, `<![CDATA[`, `]]>`, U+0000, BOM, bytes Latin-1 e UTF-8 inválido. Afirmações: só
`EpubException` escapa (contada, e zero fora da taxonomia); fora de `strict`,
todo elemento tem estilo. **Fuzz grande** (dezenas de milhares de mutações,
semente aleatória, local) na revisão final da branch, como na Publicação.

### 14.3 Hostis

`css_hostile_test.dart`, cada um com teto de tempo (`Stopwatch`, como o
`href_test` da Publicação; o número sai da medição da tarefa e fica com folga
para o CI) e a afirmação de corte certo:

| Entrada | Afirmação |
|---|---|
| Folha de 1 MiB com um seletor `a a a … b` de 200 000 compostos; o mesmo terminando em `:foo` | `unsupported-selector`; o segundo `parse-error` (gramática validada até o fim); linear |
| 20 000 regras `x p` sobre 100 000 `<p>` (nenhum `x` na árvore) | os candidatos rejeitados pelo Bloom esgotam o orçamento: `budget`, tempo linear em vez de 2×10⁹ testes |
| Composto `.a.b.c…` de 200 000 classes contra elemento com 200 000 classes | fora do subconjunto (> 32 seletores simples); a montagem do `Set` do elemento conta na cessão; linear |
| Seletor `.x…` com uma classe de 1 MiB, `#…` de 1 MiB e `[a="…"]` com valor de 1 MiB; e 20 000 regras `.c` contra 1 000 elementos com `class` e `id` de 1 MiB cada (sem casar) | os três seletores ficam fora do subconjunto (> 256); do lado do elemento, hash e minúsculas uma vez por elemento; tempo linear no tamanho do documento, não em regras × tamanho |
| `p { a:b{} a:b{} … }` com 100 000 itens sem `;`, numa folha e num `style=""` de 8 KiB | parada antecipada da tentativa de declaração (§5.3): linear, `nested-rule` agregado |
| 20 000 regras `.c1`…`.c20000` e 1 000 elementos, cada um com as 20 000 classes | uma consulta a balde por classe, contada no orçamento: `budget`, linear |
| 20 000 regras `* { font-style: italic }` sobre 5 000 elementos | `budget`, `budgetExhausted`, folha padrão ainda aplicada |
| 20 000 regras `div div … div p` (31 compostos) sobre 256 `div` aninhados | Bloom/`failsCompletely` e orçamento, linear |
| DOM de 10 000 níveis montado por código (sem `html.parse`, que é quadrático nesse aninhamento) | `dom-depth` uma vez, todos os elementos com estilo |
| 100 000 elementos com o mesmo `style=""` e 1 000 com textos diferentes de 8 KiB; um de 8 KiB + 1 | um parse por texto; `too-large` |
| `{`, `(` e `[` repetidos 500 000 vezes; comentário, string e `url(` sem fim de 1 MiB | `limit` (`nesting`), linear |
| Escapes `\` e `\FFFFFFFF` repetidos; literal numérico de 1 MiB | sem exceção, linear |
| `@import` em leque (cada folha importa a seguinte duas vezes) e ciclo `a → b → a` | 64 folhas; `cycle` sem `fetch` |
| 250 000 `@import` de um arquivo ausente, e de um acima de 1 MiB | 256 tentativas, `limit` `attempts`; um `fetch` por publicação (cache negativo) |
| Folha vazia ligada por 100 000 `<link>` | 64 folhas, `cacheKey` com 64 entradas |
| Elemento com 100 000 classes (iguais e distintas) | dedupe; linear |
| Bloco com 100 000 declarações casado por 1 000 elementos | orçamento pelas declarações aplicadas |

## 15. Desempenho

Dois casos novos no harness, em `test/perf/perf_test.dart`:

- `css.parse`: `parseStyleSheet` sobre as três folhas do Standard Ebooks de
  `reais/leaves-of-grass-en` (`core.css`, `se.css`, `local.css`, ~11 KB),
  lidas no `setUp`, com `innerIterations` para ~5 ms por amostra.
- `css.cascade`: `computeStylesSync` sobre `epub/text/song-of-myself.xhtml`
  do mesmo livro (131 KB, 2 816 elementos, o maior capítulo do SE no corpus)
  com as folhas reais dele (`core.css` e `local.css`); o `Document` e as
  `SectionSheets` são montados no `setUp`, o caso mede só a cascata (que não
  muda o DOM). No protótipo, a caminhada com a contagem de candidatos levou
  ~14 ms; `innerIterations` se a medição ficar abaixo de 5 ms.

Os baselines por CPU ganham os dois casos na próxima regeneração (até lá, "novo,
sem baseline"). Os tetos de tempo dos testes hostis (§14.3) são a outra metade
da medição, e saem dos números medidos na tarefa.

## 16. Documentos a atualizar

- [03](../03-camada-a-ir.md) §1: a cascata entrega `SectionStyles` ao IR. §6
  (é a seção de propriedades e seletores; o desenho a chamou de §5): o que
  "registrado" significa (§7.1), a tabela de mapeamentos de §7.1 e §7.2 (ou um
  resumo com o link para esta spec), `fontSizeStep` como a direção que
  `sizeSmaller`/`sizeLarger` já guardam (§4, sem mudança no IR),
  `text-decoration` (sublinhado e riscado propagados) na lista de suportadas,
  alimentando `InlineAttr.underline`/`strikethrough`, `text-align` na Classe
  2, margens e recuo em `em` como adição, as degradadas de §7.4, a folha
  padrão, as dicas `hidden`/`dir`, a fonte de CSS em `<style>` de SVG (e não
  em `template`), a ordem com `@import` e a regra da lista de seletores
  (§6.3).
- [08](../08-concorrencia-cache.md) §3: checkpoint da cascata "a cada 4 096
  passos" (não "a cada regra"). §4.1: a chave usa a lista ordenada de
  `SheetRef` (`bytesHash` de cada arquivo, texto de cada `<style>`, no máximo
  64) no lugar dos bytes de cada CSS, e a folha padrão entra por
  `IR_SCHEMA_VERSION`; `Fnv1a64` existe em `lib/src/container/`.
- [09](../09-erros-diagnosticos.md) §2: `EpubSectionParseException`
  implementada, e em `strict` também todo warning do CSS; o placeholder de
  seção relança por identidade a exceção do sink da seção e a do sink do
  contêiner; o CSS emite no sink da seção, e os diagnósticos do contêiner
  ficam no dele, uma vez por publicação. §3: `stylesheetIgnored`
  (sempre `warning`), `stylesheetMediaIgnored` (`info`) e `cssRuleIgnored`
  com os `reason`; `unsupportedLayout` continua `warning`, com `href` =
  seção, `details.property`/`value`, e emitido pelo vencedor da cascata.
- [10](../10-testes.md) §1.1: os três casos novos (68 no total). §5: os
  warnings do CSS na regra da segunda passada, e `stylesheetMediaIgnored` como
  `info`. §6: o fuzz de CSS. §4.2: os casos `css.parse` e `css.cascade`.
- [14](../14-pendencias.md): regenerar baselines com `css.parse` e
  `css.cascade`; fuzz grande do CSS na revisão final; parse das folhas no
  prólogo sem ceder (sub-projeto 5); fusão de motivos de `stylesheetIgnored`,
  e de `float` com `position` em `unsupportedLayout`, pelo dedupe do sink; as
  aproximações de §7.5 (`em` herdado sobre a fonte do filho, `bolder` sobre
  peso 300, `script`/`style` visíveis além da profundidade 256, propagação de
  `text-decoration` para dentro de `inline-block`/`float`/posicionado);
  propriedades lógicas (`margin-inline-*`) ignoradas; dicas de apresentação
  além de `hidden`/`dir` (`align`, `width`/`height` de `img` como CSS);
  `[attr]`, `~=` e `:not()` simples; `@supports` descartado inteiro;
  aninhamento do CSS Nesting (regras aninhadas descartadas); `@layer` e
  `@import … layer`; `vw`/`vh`/`calc()`; codificação do documento que
  referencia (passo do CSS Syntax omitido); recuo de lista físico
  (`padding-left`) em livro `rtl`; filhos de `flex`/`grid` sem "blocoficação";
  `<!-- -->` dentro de `<style>` aplicado, e não tirado como comentário do XML
  (§7.5); como o sink da seção entra no agregado do documento (sub-projeto 4).
- `CHANGELOG.md`: "Fase 1, sub-projeto 3 (CSS): tokenizador e parser do CSS
  Syntax recortado, `@import` e `@media` com limites, seletores do subconjunto
  com índice pela direita e filtro de Bloom, cascata com herança, propagação de
  `text-decoration` e estilo computado classificado nas três classes, folha
  padrão do HTML, diagnósticos `stylesheetIgnored`, `stylesheetMediaIgnored`,
  `cssRuleIgnored` e `unsupportedLayout`."
- `test/corpus/corpus_test.dart` (`knownDiagnostics`), os `.expected` de §14.1,
  e os testes que contam 65 casos.
