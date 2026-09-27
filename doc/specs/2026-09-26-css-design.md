# CSS (Fase 1, sub-projeto 3) — design

**Data:** 2026-09-26. **Estado:** a implementar (escrita a partir do desenho
em cinco seções aprovado pelo usuário, `.superpowers/sdd/2026-09-26-css/design-aprovado.md`;
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
`<?xml-stylesheet?>`; a folha de estilo implícita de `align`, `bgcolor` e
outros atributos de apresentação do HTML, fora `hidden` e `dir` (§8.2); o
worker e o cache em disco (sub-projeto 5), dos quais aqui só sai a lista de
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
no ponto indicado:

| # | Decisão | Onde |
|---|---|---|
| 1 | O `emit` do CSS usa `onStrict: EpubSectionParseException`, criada agora em `exceptions.dart` (interna até o sub-projeto 6) | §12.3 |
| 2 | `unsupportedLayout` entra no código agora (está em doc/09 e no `knownDiagnostics`, mas não em `EpubDiagnosticCode`) e é emitido quando a declaração degradada **vence a cascata** num elemento, uma vez por (seção, propriedade) | §10.7 |
| 3 | `text-align` guarda internamente a palavra computada (`left`, `right`, `start`, `end`, `center`) para herdar como o CSS herda, e expõe `start`/`center`/`end` resolvido pela direção do próprio elemento | §3, §7 |
| 4 | `font-weight` guarda o peso numérico (1–1000) para `bolder`/`lighter` seguirem a tabela do CSS Fonts, e expõe `normal`/`bold` (≥ 600) | §3, §7 |
| 5 | `rem` conta como `em`; `ex` e `ch` como 0,5em (o valor que o CSS Values manda assumir sem métrica de fonte); `vw`, `vh`, `calc()`, `var()` e demais descartam a declaração | §7.2 |
| 6 | `width`/`height` convertidos como as margens e limitados a [0, 100] em `em` e em `%` | §7.1 |
| 7 | Tamanho de fonte absoluto (px, pt, palavras-chave) descarta a declaração; `initial`/`unset` em `font-size` dão `same` | §7.1 |
| 8 | Tipo de lista desconhecido resolve no elemento onde a declaração vale: `decimal` se ele é `ol` ou `li` filho de `ol`, senão `disc` | §7.1 |
| 9 | Dicas de apresentação `hidden` e `dir` entram como declarações da origem da folha padrão com especificidade (0,1,0), porque o subconjunto de seletores não tem presença de atributo nem comparação sem caixa | §8.2 |
| 10 | `rp` não é escondido (o galley achata o ruby, [09](../09-erros-diagnosticos.md) §3 `rubyFlattened`, e `rp` existe para quem não tem ruby) | §8.1 |
| 11 | Seletor de atributo com prefixo (`[epub|type="x"]`) casa o atributo literal `epub:type`; `@namespace` é ignorado | §6.1 |
| 12 | Uma lista de seletores com um seletor fora do subconjunto descarta a regra inteira (como o CSS faz com lista inválida) | §6.3 |
| 13 | Teto novo de 4 MiB de CSS por seção (soma das folhas aplicadas), além do teto de 1 MiB por folha | §11 |
| 14 | O limite de 20 000 regras conta seletores (entradas do índice), não blocos | §11 |
| 15 | Cache de folhas parseadas por caminho e por texto de `<style>`, LRU com teto de 8 Mi unidades de código de fonte; os diagnósticos de parse ficam na folha e são reemitidos a cada seção que a aplica | §9.6 |
| 16 | Diagnósticos de parse agregados por folha: no máximo um `cssRuleIgnored` por motivo e um `stylesheetIgnored` `media` por folha e por seção, com `details.discarded` | §12.1 |
| 17 | Elemento abaixo da profundidade 256 recebe o estilo "herdado puro" do pai (herdadas copiadas, não herdadas no valor inicial), sem casar regras | §10.2 |
| 18 | Esgotado o orçamento, `style=""` continua valendo (não é casamento de seletor e custa O(1) por elemento) | §10.6 |
| 19 | A lista de folhas para a chave leva o hash FNV-1a 64 dos bytes de cada arquivo (em `lib/src/container/fnv1a64.dart`, exato na VM e no JS) e o texto de cada `<style>` | §9.7 |
| 20 | `computeStyles` escreve o resultado num `CascadeResult` passado pelo chamador (o gerador `sync*` só cede `void`), e tem a variante `computeStylesSync` | §10.1 |
| 21 | `recordOrigins` (só testes): `SectionStyles.originOf` diz a origem da declaração vencedora, para o corpus checar "itálico salvo sobrescrita" | §10.1, §14.1 |
| 22 | O CDATA em volta do texto de `<style>` (`<![CDATA[ … ]]>`) é tirado antes do parse ([03](../03-camada-a-ir.md) §8) | §9.1 |
| 23 | O parse das folhas roda no prólogo assíncrono do loader, sem ceder; se o sub-projeto 5 medir fatia acima do tolerado, vira `sync*` | §9.5, [14](../14-pendencias.md) |

## 2. Arquivos

| Caminho | Papel |
|---|---|
| `lib/src/css/tokenizer.dart` | `CssTokenizer`, `CssToken`, `CssTokenType` (§4) |
| `lib/src/css/parser.dart` | `parseStyleSheet`, `parseStyleAttribute`, `StyleSheet`, `StyleRule`, `CssImport`, `CssIssue`, `mediaMatches` (§5) |
| `lib/src/css/selector.dart` | `parseSelectorList`, `Selector`, `CompoundSelector`, `CssCombinator`, `CssAttributeTest`, especificidade (§6) |
| `lib/src/css/properties.dart` | `CssProperty`, `StyleClass`, `Declaration`, `CssValue` e subtipos, `parseDeclaration` (expansão de `margin`, `padding`, `font`, `list-style`, `columns`) (§7) |
| `lib/src/css/ua_sheet.dart` | `userAgentCss` (texto), `userAgentSheet` (parseada uma vez) (§8) |
| `lib/src/css/loader.dart` | `loadSectionSheets`, `decodeCss`, `StyleSheetCache`, `SectionSheets`, `AppliedSheet`, `SheetRef`, `SheetSource` (§9) |
| `lib/src/css/rule_index.dart` | `RuleIndex`, `RuleEntry`, `CssOrigin` (§10.3) |
| `lib/src/css/cascade.dart` | `computeStyles`, `computeStylesSync`, `CascadeResult`, `SectionStyles` (§10) |
| `lib/src/css/computed_style.dart` | `ComputedStyle`, `EmEdges`, `CssLength` e os enums de §3 |
| `lib/src/container/fnv1a64.dart` | `Fnv1a64` (§9.7) |
| `lib/src/diagnostics/diagnostic.dart` | + `unsupportedLayout`, `stylesheetIgnored`, `cssRuleIgnored` (§12) |
| `lib/src/diagnostics/exceptions.dart` | + `EpubSectionParseException` (§12.3) |

Testes em `test/css/` (§14), e `test/container/fnv1a64_test.dart`.
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
  final CssAlignKeyword alignKeyword;     // o que herda
  CssTextAlign get textAlign;             // alignKeyword resolvido pela direction deste elemento
  final CssVerticalAlign verticalAlign;
  final CssListStyleType listStyleType;
  final CssBreak breakBefore, breakAfter, breakInside;
  final CssLength? width, height;         // null = auto

  // Classe 2 — tipografia relativa.
  final CssFontStyle fontStyle;
  final int weight;                       // 1–1000, o que herda (bolder/lighter)
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

`ComputedStyle` é internado pelo valor dentro de uma cascata (§10.5): dois
elementos com o mesmo estilo recebem a mesma instância.

```dart
/// Resultado da cascata de uma seção.
final class SectionStyles {
  /// Estilo de [element], ou `null` se ele não é do documento processado.
  ComputedStyle? styleOf(Element element);

  /// Elementos com estilo (todos os do documento, inclusive os de
  /// `display: none` e os abaixo da profundidade de casamento).
  int get length;

  /// O orçamento de §10.6 acabou; o resto da seção teve só a folha padrão e
  /// os `style=""`.
  bool get budgetExhausted;

  /// Origem da declaração que venceu [property] em [element]; `null` quando o
  /// valor veio de herança ou do inicial. Só com `recordOrigins: true` (§10.1);
  /// senão lança `StateError` — é API de teste.
  CssOrigin? originOf(Element element, CssProperty property);
}
```

O mapa é por identidade (`Map<Element, ComputedStyle>.identity()`), com todos
os elementos da árvore de `document.documentElement`.

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

`lib/src/css/parser.dart`, CSS Syntax Level 3 §5 ("consume a stylesheet's
contents", "consume a qualified rule", "consume an at-rule", "consume a list of
declarations") sobre o `CssTokenizer`.

```dart
final class CssImport {
  final String href;               // cru, como escrito na folha
}

final class StyleRule {
  final List<Selector> selectors;  // a lista de seletores, na ordem
  final List<Declaration> declarations; // já expandidas e tipadas (§7), na ordem
}

/// Diagnóstico de parse guardado na folha e reemitido pelo loader a cada
/// seção que a aplica (§9.6). No máximo um por (código, motivo) por folha.
final class CssIssue {
  final EpubDiagnosticCode code;   // cssRuleIgnored ou stylesheetIgnored
  final String reason;             // §12.1
  final int discarded;             // quantas regras, blocos ou @import
  final Map<String, Object?> details; // amostra (seletor truncado, media, href do @import)
}

final class StyleSheet {
  final List<CssImport> imports;   // só os que valem (antes das regras, media casada)
  final List<StyleRule> rules;     // fora das @media que não casam
  final List<CssIssue> issues;
  final int sourceLength;          // unidades de código do texto
}

/// Folha inteira. Nunca lança.
StyleSheet parseStyleSheet(String text);

/// Conteúdo de `style=""`: as declarações, sem seletor, e quantas foram
/// descartadas por sintaxe (§10.5 soma e emite uma vez por seção).
(List<Declaration> declarations, int parseErrors) parseStyleAttribute(String text);

/// Lista de media queries (atributo `media`, `@import`, `@media`): `true` se
/// alguma query é `all` ou `screen` (com `only` opcional) sem condição, ou se
/// a lista é vazia ou só espaço. `print`, `not screen`,
/// `screen and (max-width: 600px)` e palavra desconhecida não casam.
bool mediaMatches(String? media);
```

### 5.1 Nível de topo

- `cdo`/`cdc` e espaço são ignorados.
- **Regra qualificada:** o prelúdio vai até o `{` do bloco; o bloco é uma lista
  de declarações (§5.3). O prelúdio passa por `parseSelectorList` (§6):
  - inválido pela gramática → regra descartada, `cssRuleIgnored`
    `parse-error`;
  - válido mas fora do subconjunto → regra descartada, `cssRuleIgnored`
    `unsupported-selector` (§6.3);
  - prelúdio que chega ao fim do texto sem `{` → descartado, `parse-error`.
- **At-rules:**
  - `@charset` → ignorada (a codificação é de §9.4).
  - `@import` → §5.2.
  - `@media` → se `mediaMatches` do prelúdio, as regras do bloco entram na
    folha como se estivessem fora dele (aninhamento de `@media` vale, cada
    nível filtrado); se não, o bloco some e conta num `stylesheetIgnored`
    `media` (`info`) da folha.
  - `@namespace`, `@font-face`, `@page`, `@supports`, `@keyframes` (e prefixadas),
    `@layer`, `@counter-style`, `@font-feature-values`, `@property`,
    `@container`, `@document`/`@-moz-document`, `@viewport` e qualquer outra
    desconhecida → descartadas **em silêncio** (o bloco e o `;` são consumidos).
    `@font-face` é aparência sem efeito no perfil `uniform`
    ([03](../03-camada-a-ir.md) §6); `@supports` com o conteúdo inteiro
    descartado é a leitura conservadora (o bloco pode depender de `flex`,
    `grid` e outras coisas que o galley não faz).

### 5.2 `@import`

- Forma: `@import <string> | url(<…>) [lista de media]? ;`. O href sai cru.
- Com `layer`, `layer(…)` ou `supports(…)` no prelúdio → ignorado como
  `stylesheetIgnored` `media` (a condição não é avaliada, e ignorar o
  `@import` é o lado seguro).
- Media que não casa → ignorado, `stylesheetIgnored` `media` (`info`).
- **Posição** (a regra do `@import` do CSS Cascade 4): um `@import` só vale se nenhuma regra de
  estilo **válida** nem at-rule **reconhecida** (a lista de §5.1, exceto
  `@charset` e `@layer` sem bloco) apareceu antes dele. Regra com seletor fora
  do subconjunto conta como válida (a gramática aceita); regra descartada por
  `parse-error` e at-rule desconhecida não contam. `@import` fora de posição →
  ignorado, `stylesheetIgnored` `late-import` (`warning`), `details.import` =
  o href cru.
- Prelúdio sem string nem `url` → `cssRuleIgnored` `parse-error`.

### 5.3 Declarações e recuperação de erro

Dentro de um bloco de estilo e em `style=""`:

- `nome : valor [! important]` até o `;` do nível do bloco. O nome é
  comparado em minúsculas ASCII; `!important` é o par `delim !` + `ident
  important` (sem caixa, espaço e comentário no meio aceitos) no fim do valor.
- **Recuperação** (a de "consume a list of declarations" do CSS Syntax):
  declaração sem `:`, com `badString` ou `badUrl` no valor, ou que não começa
  por `ident` → descartada até o próximo `;` do bloco (blocos aninhados
  `{}`, `()` e `[]` no meio são consumidos inteiros); o resto da regra fica. Conta como `cssRuleIgnored`
  `parse-error`.
- **Regra aninhada** (CSS Nesting, `p { .x { … } }`) → descartada com o bloco,
  `parse-error`; o galley não implementa aninhamento.
- Propriedade fora da tabela (§7), propriedade customizada (`--x`) e valor fora
  do aceito → declaração descartada **em silêncio** (é a classe "ignorado" de
  [03](../03-camada-a-ir.md) §6, e reportar cada uma inundaria o canal).
- Um valor com `var()` descarta a declaração em silêncio: o galley não
  resolve propriedades customizadas.

### 5.4 Aninhamento

`maxCssNesting = 32` blocos abertos (`{`, `(`, `[`, função). Ao abrir o 33º, o
parser entra em modo de salto: consome tokens até fechar o bloco que passou do
limite, sem construir nada, e emite `stylesheetIgnored` `limit`
(`details.limit: 'nesting'`) uma vez por folha. O salto casa fechamentos com
uma pilha de tipos (um `)` solto dentro de `{` é só um token, como no CSS); a
pilha cresce no máximo até o número de aberturas do trecho.

### 5.5 Por que é linear

- Cada token é pedido ao tokenizador uma vez; o reconsumo é de um token só.
- O prelúdio de cada regra é juntado uma vez numa lista (soma ≤ tokens da
  folha) e entregue a `parseSelectorList`; o valor de cada declaração, idem,
  a `parseDeclaration`. Nenhum dos dois volta ao texto.
- A recuperação de erro só avança (salta até `;` ou até o fim do bloco);
  nunca reparseia.
- A recursão por bloco é limitada a 32 níveis; além disso o salto é iterativo.
- Os diagnósticos são agregados por (código, motivo) por folha: uma folha com
  um milhão de regras inválidas gera um `CssIssue`, não um milhão.

## 6. Seletores

`lib/src/css/selector.dart`.

```dart
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
  final int? nthChild;   // n ≥ 1; 0 quando o argumento não pode casar (0, negativo, enorme)
}

final class Selector {
  final List<CompoundSelector> compounds;  // da esquerda para a direita, ≤ 32
  final List<CssCombinator> combinators;   // compounds.length - 1
  final int specificity;                   // (a << 20) | (b << 10) | c, cada um saturado em 1023
  final List<int> ancestorHashes;          // até 4, para o filtro de Bloom (§10.4)
}

sealed class SelectorListParse {}
final class SelectorList extends SelectorListParse { final List<Selector> selectors; }
final class SelectorInvalid extends SelectorListParse { final String sample; }     // parse-error
final class SelectorUnsupported extends SelectorListParse { final String sample; } // unsupported-selector

/// [prelude]: os tokens entre o fim da regra anterior e o `{`.
SelectorListParse parseSelectorList(List<CssToken> prelude);
```

### 6.1 Subconjunto ([03](../03-camada-a-ir.md) §6)

| Forma | Casa com |
|---|---|
| `p`, `P` | elemento HTML de nome `p` (tipo sem diferença de caixa só no namespace HTML); fora dele (SVG, MathML), o nome exato |
| `*` | qualquer elemento |
| `.nota` | token `nota` do atributo `class`, **com** diferença de caixa (o XHTML não tem modo quirks), tokens separados por espaço ASCII |
| `#x` | atributo `id` igual a `x`, com diferença de caixa; só `hash` com `isIdHash` |
| `[a="v"]`, `[a=v]` | atributo `a` com valor exatamente `v` |
| `[epub|type="noteref"]` | atributo literal `epub:type` (o `package:html` guarda o nome com o prefixo, [03](../03-camada-a-ir.md) §8) **(decisão da spec, #11)**: `@namespace` é ignorado, e o prefixo escrito é o que o DOM tem. `[|a=v]` é `a` sem prefixo |
| `A B` | `B` com um ancestral `A` |
| `A > B` | `B` com pai `A` |
| `A + B` | `B` cujo irmão-**elemento** anterior é `A` (texto e comentário entre os dois não contam) |
| `:first-child`, `:last-child` | primeiro/último entre os irmãos-elemento |
| `:nth-child(n)` | `n` inteiro ≥ 1, contado a partir de 1 entre os irmãos-elemento; `+3` vale 3; `:nth-child(0)`, negativo ou acima de 2^30 nunca casa |

Nomes de atributo comparados em minúsculas ASCII no namespace HTML (o
`package:html` já os baixa) e exatos fora dele; valores sempre exatos.

### 6.2 Especificidade

(a, b, c) do Selectors Level 4: a = ids, b = classes, atributos e
pseudo-classes, c = tipos; `*` e combinadores não contam. Cada componente
satura em 1023 e o conjunto vira `(a << 20) | (b << 10) | c` — o número que a
cascata compara (§10.5). A saturação só muda a ordem em seletor com mais de
1 023 classes num composto, que não existe fora de arquivo hostil.

### 6.3 Fora do subconjunto

`SelectorUnsupported` (a regra inteira é descartada, `cssRuleIgnored`
`unsupported-selector`, `details.sample` = o prelúdio truncado em 64 unidades
de código, sem cortar um par de surrogates): `~`; `:not()`, `:is()`,
`:where()`, `:has()`; qualquer outra pseudo-classe (`:hover`, `:link`,
`:root`, `:nth-child(odd)`, `:nth-child(2n+1)`, `:only-child`, `:lang()`…);
pseudo-elemento (`::before`, `::first-letter`, e as formas antigas
`:before`, `:after`, `:first-line`, `:first-letter`); atributo por presença
(`[href]`), por `~=`, `|=`, `^=`, `$=`, `*=` ou com flag `i`/`s`; tipo com
namespace (`svg|rect`, `*|p`); atributo `[*|a]`; mais de 32 compostos.

`SelectorInvalid` (`parse-error`): o que a gramática de Selectors não aceita —
item vazio na lista (`a,,b`), combinador sem composto, `#` que não é
identificador (`#1a`), `.` sem identificador, colchete sem fechar, token
inesperado (`{`, `;`, string solta).

**Uma lista com um seletor fora do subconjunto descarta a regra inteira**
**(decisão da spec, #12)**: o desenho disse "regra com seletor fora do
subconjunto é descartada inteira", e é o que o CSS faz com uma lista em que um
seletor é inválido (a lista de seletores do Selectors 4 não é tolerante).
Manter os seletores suportados da lista seria mais fiel ao navegador numa
regra como `p.x, p:not(.y)`; a troca não muda interface nenhuma.

### 6.4 Por que é linear

- Uma passada sobre os tokens do prelúdio; a divisão por vírgula é feita na
  mesma passada.
- Ao chegar ao 33º composto o seletor já é `SelectorUnsupported`, sem olhar o
  resto do item.
- Os hashes de ancestral são tirados do composto já montado (no máximo 4).
- `:nth-child` lê o número do token (`double`), nunca por `int.parse`.

## 7. Propriedades

`lib/src/css/properties.dart`.

```dart
enum CssProperty {
  display, whiteSpace, direction, textAlign, verticalAlign, listStyleType,
  breakBefore, breakAfter, breakInside, width, height,
  fontStyle, fontWeight, fontVariant, textTransform, fontSize,
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
final class CssWeightValue extends CssValue { final int? absolute; final bool bolder; }
/// Margens, padding e text-indent: já convertidos e limitados.
final class CssEmValue extends CssValue { final double em; }
/// width/height.
final class CssLengthValue extends CssValue { final CssLength? length; } // null = auto
/// font-size relativo: a razão sobre o pai, ou smaller/larger.
final class CssFontSizeValue extends CssValue { final CssFontSizeStep step; }
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
| `text-align` | E | sim | `start` | `left`, `right`, `center`, `justify`, `start`, `end` | palavra guardada em `alignKeyword`; `justify` → `start` (justificar é aparência global, [02](../02-modelo-de-estilo.md) §3.1); `textAlign` resolve `left`/`right` pela `direction` do elemento (§3). `match-parent` e `-webkit-center` descartam |
| `vertical-align` | E | não | `baseline` | `baseline`, `super`, `sub`, `top`, `text-top`, `middle`, `bottom`, `text-bottom`, comprimento, `%` | `super` → `sup`; `sub` → `sub`; os demais → `baseline` (válidos no CSS: tiram o sobrescrito da folha padrão) |
| `list-style-type` | E | sim | `disc` | `disc`, `circle`, `square`, `decimal`, `lower-alpha`, `lower-latin`, `upper-alpha`, `upper-latin`, `lower-roman`, `upper-roman`, `none`; outro identificador ou string | `*-latin` = `*-alpha`; nome desconhecido (`lower-greek`, `"–"`) → `decimal` se o elemento onde a declaração vale é `ol` ou `li` filho de `ol`, senão `disc` **(decisão da spec, #8)**; número e lixo descartam |
| `list-style` (atalho) | E | — | — | tipo, posição (`inside`/`outside`) e imagem (`url()`/`none`), em qualquer ordem | só o tipo entra; sem tipo, `none` sozinho → `none`; sem tipo nem `none` → `disc` (o atalho reinicia) |
| `break-before`, `break-after` | E | não | `auto` | `auto`, `avoid`, `avoid-page`, `page`, `left`, `right`, `recto`, `verso`, `always`, `column`, `avoid-column`, `region`, `avoid-region` | `page`/`left`/`right`/`recto`/`verso`/`always` → `page`; `avoid`/`avoid-page` → `avoid`; os de coluna e região → `auto` |
| `page-break-before`, `page-break-after` | E | não | — | `auto`, `always`, `avoid`, `left`, `right` | **mesma propriedade** que `break-*` (no CSS Fragmentation são atalhos legados dela), então a ordem da cascata decide entre as duas grafias; `always`/`left`/`right` → `page` |
| `break-inside`, `page-break-inside` | E | não | `auto` | `auto`, `avoid`, `avoid-page`, `avoid-column`, `avoid-region` | `avoid*` → `avoid`; nunca `page` |
| `width`, `height` | E | não | `auto` | comprimento ≥ 0, `%` ≥ 0, `auto` | conversão de §7.2; limitado a [0, 100] em `em` e em `%` **(decisão da spec, #6)**; `auto` → `null`; negativo descarta. `max-*`/`min-*` ignoradas |
| `font-style` | T | sim | `normal` | `normal`, `italic`, `oblique` (com ângulo opcional) | `oblique` → `italic` |
| `font-weight` | T | sim | `normal` (400) | `normal`, `bold`, `bolder`, `lighter`, número 1–1000 | peso numérico em `weight`; `bolder`/`lighter` sobre o pai (§3); `fontWeight` = `bold` se ≥ 600 |
| `font-variant`, `font-variant-caps` | T | sim | `normal` | qualquer lista de identificadores | contém `small-caps` ou `all-small-caps` → `smallCaps`; senão `normal` (o atalho reinicia o `caps`); número ou string descartam |
| `text-transform` | T | sim | `none` | `none`, `uppercase`, `lowercase`, `capitalize` | direto; `full-width` e outros descartam |
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
`visibility`. E tudo o que não está em §7.1 nem em §7.4 (`all`, `hyphens`,
`text-decoration*`, propriedades lógicas como `margin-inline-start`, prefixos
`-webkit-`/`-epub-` fora de `writing-mode`, `content`, `quotes`…). O que disso
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

### 7.5 Por que é linear

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
h1, h2, h3, h4, h5, h6, dl, dt, dd, ol, ul, menu,
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

ul, menu { list-style-type: disc }
ol { list-style-type: decimal }
ul ul, ol ul, menu ul, ul menu { list-style-type: circle }
ul ul ul, ol ul ul, ul ol ul, ol ol ul { list-style-type: square }
ol[type="1"], li[type="1"] { list-style-type: decimal }
ol[type="a"], li[type="a"] { list-style-type: lower-alpha }
ol[type="A"], li[type="A"] { list-style-type: upper-alpha }
ol[type="i"], li[type="i"] { list-style-type: lower-roman }
ol[type="I"], li[type="I"] { list-style-type: upper-roman }
ul, ol, menu { padding-left: 2.5em }
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
efeito no perfil `uniform`, que não honra padding.

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

## 9. Carregamento

`lib/src/css/loader.dart`, assíncrono (o prólogo de
[08](../08-concorrencia-cache.md) §1).

```dart
const int maxStyleSheetBytes = 1024 * 1024;      // por folha, antes do decode()
const int maxSectionStyleBytes = 4 * 1024 * 1024; // soma por seção (decisão da spec, #13)
const int maxSheetsPerSection = 64;
const int maxImportDepth = 8;
const int maxCachedStyleSource = 8 * 1024 * 1024; // unidades de código (decisão da spec, #15)

enum SheetSource { link, style, import }

/// Uma folha aplicada, para a chave do cache (doc/08 §4.1).
final class SheetRef {
  final SheetSource source;
  final String? path;       // arquivo: caminho real no contêiner (PendingResource.path)
  final String? bytesHash;  // arquivo: FNV-1a 64 dos bytes crus, 16 hex
  final String? text;       // <style>: o texto, depois do CDATA tirado
}

final class AppliedSheet {
  final SheetRef ref;
  final StyleSheet sheet;
  final String href;        // href dos diagnósticos desta folha: path, ou a seção para <style>
}

/// Folhas de uma seção, **na ordem da cascata** (importadas antes de quem
/// importa; a mesma folha importada duas vezes aparece duas vezes).
final class SectionSheets {
  static const empty = SectionSheets._(<AppliedSheet>[]);
  final List<AppliedSheet> sheets;
  List<SheetRef> get cacheKey;   // sheets.map((s) => s.ref)
}

/// Folhas parseadas, reaproveitadas entre as seções de uma publicação
/// (os capítulos repetem a folha). LRU pelo tamanho do fonte.
final class StyleSheetCache {
  StyleSheetCache({int maxSource = maxCachedStyleSource});
}

/// Junta as folhas de [document] (a seção em [sectionPath]). Não fecha o
/// contêiner. Nunca lança por causa do CSS; a exceção do [sink] em `strict`
/// propaga como está.
Future<SectionSheets> loadSectionSheets(
  EpubContainer container,
  Document document, {
  required String sectionPath,
  required StyleSheetCache cache,
  required DiagnosticSink sink,
});

/// Bytes de uma folha para texto (§9.4).
String decodeCss(Uint8List bytes, {required String path, required DiagnosticSink sink});
```

### 9.1 Coleta

Uma caminhada em ordem de documento sobre `document.nodes` (pilha explícita,
iterando `nodes`, nunca indexando `children`, [03](../03-camada-a-ir.md) §8),
em qualquer ponto da árvore (`head` ou `body`):

- `<link>` no namespace HTML com `rel` contendo o token `stylesheet` e não
  `alternate` (tokens por espaço ASCII, sem caixa), `type` ausente, vazio ou
  `text/css` (sem caixa, antes de `;`), `mediaMatches(media)`, `href` não
  vazio depois de `trim`. `media` que não casa → `stylesheetIgnored` `media`
  (`info`, `href` = o caminho resolvido, ou a seção se o `href` for
  recusado), sem busca.
- `<style>` em qualquer namespace (o `<style>` dentro de SVG inline também vale
  para o documento, como no navegador), com `type` e `media` pela mesma regra.
  O texto é o dos filhos de texto; um `<![CDATA[` inicial e um `]]>` final
  (depois de espaço) saem **(decisão da spec, #22)**; `<!--`/`-->` são
  tratados pelo tokenizador.
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
- Soma dos `sourceLength` já aplicados na seção mais este passaria de
  `maxSectionStyleBytes` → `stylesheetIgnored` `limit` (`details.limit:
  'bytes'`). O mesmo teto vale para o texto de `<style>`, cujo tamanho por
  folha também é limitado por `maxStyleSheetBytes` (em unidades de código).
- `decode()` drenado inteiro; o `EpubException` que o `fetch` ou o `decode()`
  lançarem é reconhecido **por identidade**: `identical(e,
  sink.lastStrictException)` → propaga (é o `strict`, por exemplo
  `zipCrcMismatch`); senão `resourceUnreadable` (`warning`, `href` = caminho,
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

### 9.5 `@import` e a ordem

Para cada folha, na ordem de coleta (§9.1), o loader aplica recursivamente:

```
aplicar(folha, profundidade, pilha):
  para cada @import válido da folha (§5.2), em ordem:
    resolver (§9.2); se profundidade + 1 > maxImportDepth → stylesheetIgnored depth
    se o caminho real (em minúsculas, como o ZipContainer) está na pilha → stylesheetIgnored cycle
    se já há maxSheetsPerSection folhas aplicadas → stylesheetIgnored limit (sheets)
    ler (§9.3, com o cache de §9.6) e aplicar(importada, profundidade + 1, pilha + [caminho])
  anexar a folha a SectionSheets.sheets
```

A pilha tem no máximo 9 caminhos. Uma folha importada duas vezes aplica duas
vezes (desenho), e o teto de 64 folhas fecha o leque exponencial (A importa B
duas vezes, B importa C duas vezes…). `href` dos diagnósticos de `depth`,
`cycle` e `limit`: o caminho da folha não aplicada, com `details.from` = a
folha que importa. O parse de cada folha nova roda aqui, dentro do prólogo
assíncrono, sem ceder **(decisão da spec, #23)**: tokenizar 1 MiB custou ~11
ms no protótipo (§11), e o sub-projeto 5 decide se vira `sync*`.

### 9.6 Cache de folhas

`StyleSheetCache` guarda `(StyleSheet, caminho real, bytesHash)` por caminho
pedido (cada candidato da tentativa dupla é consultado antes do `fetch`) e
`StyleSheet` por texto de `<style>` (o parse não resolve `href`, então a mesma
folha serve a seções em pastas diferentes). LRU, com teto de
`maxCachedStyleSource` unidades de código somadas; a folha maior que o teto
não entra. **(Decisão da spec, #15.)** Uma falta custa só um reparse.

Os `CssIssue` ficam na `StyleSheet` e o loader os **reemite** a cada seção que
aplica a folha, com o `href` da `AppliedSheet`: o conjunto de diagnósticos de
uma seção não depende de a folha ter vindo do cache, que é o que
[09](../09-erros-diagnosticos.md) §3.1 pede para os diagnósticos por seção.

### 9.7 Lista de folhas para a chave

`SectionSheets.cacheKey`: a lista ordenada de `SheetRef` de todas as folhas
aplicadas (arquivo com caminho e `bytesHash`; `<style>` com o texto),
inclusive repetidas. A folha padrão não entra (é coberta por
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
  `getElementsByTagName` ou `children` indexado.
- Cada folha é buscada, decodificada e parseada uma vez por publicação
  (cache); `decodeCss` é linear como `decodeXml`.
- O leque de `@import` é limitado a 64 folhas por seção; a pilha de ciclo tem
  ≤ 9 entradas, então a verificação de ciclo é O(1) por `@import`.
- O teto de 4 MiB por seção limita o texto que o parse pode receber de uma
  seção nova, e o de 1 MiB por folha evita drenar uma entrada enorme.

## 10. Índice de regras e cascata

### 10.1 Entrada e saída

```dart
const int maxCascadeDepth = 256;
const int cascadeBudget = 1 << 24;
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
do namespace HTML, `id`, classes (tokens por espaço ASCII, **sem repetição**:
`class="a a"` vira `[a]`), o índice (base 1) entre os irmãos-elemento, o total
deles e o quadro do pai. `:first-child`, `:last-child`, `:nth-child(n)` e `+`
(o irmão anterior é `infos[i - 1]`) ficam O(1).

Cada elemento, em ordem de documento:

1. Profundidade ≤ `maxCascadeDepth` (a raiz `html` é 1): casamento e cascata
   (§10.4, §10.5).
2. Abaixo dela: o estilo "herdado puro" do pai — as propriedades herdadas
   copiadas, as não herdadas no inicial, `fontSizeStep: same` — sem casar
   regras nem ler `style=""`, e um `stylesheetIgnored` `limit`
   (`details.limit: 'dom-depth'`, `href` = a seção) por seção **(decisão da
   spec, #17)**. O desenho diz "herda o estilo do pai"; herdar pela regra do
   CSS, e não copiar o estilo inteiro, evita que um `fontSizeStep: larger` do
   pai se repita em cada nível (o IR acumula).
3. O `ComputedStyle` (internado, §10.5) vai para o mapa, **inclusive** de
   elemento com `display: none` e dos filhos dele.

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
retroceder. Com
só descendentes, o custo por candidato é O(compostos × profundidade) ≤ 32 ×
256.

**Filtro de Bloom** dos ancestrais, contador, `Uint8List(4096)`: ao descer
para os filhos de um elemento, soma 1 nas duas posições (os 12 bits baixos e
os 12 seguintes do `hashCode`, com uma semente por tipo: nome, classe, `id`)
do nome, do `id` e de cada classe dele; ao subir, subtrai. Contador que chega a
255 fica preso (nunca desce): só gera falso positivo. Cada `Selector` guarda
até 4 hashes dos compostos que **precisam** ser ancestrais — os que têm à
direita um combinador descendente ou `>` (`a > b + c`: `a` é ancestral de `c`;
`a + b c`: `a` não é) — primeiro `id`, depois classes, depois tipo. Antes de
testar um candidato com hashes, se algum não está no filtro, o candidato é
rejeitado em O(1).

Ordem dos testes num composto: `id`, tipo, classes, atributos,
pseudo-classes (o mais barato e mais seletivo primeiro).

### 10.5 Cascata

Para cada elemento, um vetor de slots, um por `CssProperty` (31), zerado em
O(1) por geração. Cada declaração casada disputa o slot da propriedade dela
pela chave lexicográfica `(camada, anexado, especificidade, seq)`; a maior
vence (a ordem da cascata do CSS Cascade 4: origem e importância, estilo
anexado ao elemento, especificidade, ordem de aparição):

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
— a regra do CSS para listas. A chave cabe em dois `int` (`camada << 32 |
anexado << 31 | especificidade` e `seq`), exatos no JS.

Não há ordenação: cada declaração custa uma comparação. Depois, para cada
propriedade (`direction` é computada antes de `textAlign`):

- sem vencedor: herdada → valor do pai; não herdada → inicial (§7.1);
- `inherit` → valor do pai; `initial` → inicial; `unset` → herdada ? pai :
  inicial (`fontSize`: sempre `same`, §7.1);
- relativos: `bolder`/`lighter` sobre o `weight` do pai; tipo de lista
  desconhecido pelo elemento (§7.1); `alignKeyword` guardado e `textAlign`
  resolvido pela `direction` já computada do elemento.

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

Um **passo** é: visitar um elemento; testar um composto num elemento (inclusive
cada ancestral tentado pelo descendente); aplicar uma declaração casada. O
contador cresce sempre; a cada `cascadeYieldSteps` passos, `yield`, no padrão
do `decode()` do contêiner (um `yield` por lote de trabalho). A linha da
cascata em [08](../08-concorrencia-cache.md) §3 passa a dizer "a cada 4 096
passos" em vez de "a cada regra".

`cascadeBudget` (2^24, o mesmo número de `navParseBudget`) limita os passos das
**regras do livro**. Esgotado: as regras do livro deixam de ser casadas no
resto da seção; a folha padrão, as dicas e os `style=""` continuam
**(decisão da spec, #18)** — nenhum dos três é casamento de seletor contra o
livro, e o custo deles por elemento é constante; emite `stylesheetIgnored`
`budget` (`href` = a seção) uma vez e marca `budgetExhausted`.

### 10.7 `unsupportedLayout`

Os slots de `float`, `position`, `columnCount`, `columnWidth` e `writingMode`
disputam a cascata como os outros. Se, no fim, o vencedor de um deles degrada
(§7.4), emite `unsupportedLayout` (`warning`, `href` = a seção, `details:
{property, value}`) **uma vez por (seção, propriedade)** **(decisão da spec,
#2)**. Emitir no vencedor, e não no parse, evita o falso positivo de uma regra
com `float` que nenhum elemento usa, ou que um `float: none` posterior
desfaz.

### 10.8 Por que é linear

- A caminhada visita cada nó uma vez; cada `ElementInfo` é montado uma vez,
  quando o pai é visitado (a passada pelos `nodes` do pai soma, no total, o
  número de nós).
- As classes do elemento são deduplicadas: `class="a a a …"` não visita o
  balde `a` N vezes. O mesmo `id` em muitos elementos é só uma consulta O(1)
  por elemento.
- Candidatos vêm de mapas, O(1) por balde; o filtro de Bloom rejeita em O(1) a
  maioria dos seletores com descendente; `failsCompletely` impede o retrocesso;
  32 compostos e 256 níveis limitam cada teste; tudo o que sobra é pago em
  passos contra o orçamento, então o casamento do livro custa no máximo 2^24
  passos por seção, e o resto é O(elementos).
- A cascata não ordena: uma comparação por declaração casada, e um vetor de 31
  slots por elemento.
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
| CSS por seção | 4 MiB (`maxSectionStyleBytes`) **(decisão da spec, #13)** | 14 KB (as três folhas do SE) | sem ele, 64 folhas de 1 MiB dariam 64 MiB de parse numa seção; 4 MiB fica em ~50 ms de tokenização e ainda é ~290× o real |
| Folhas por seção | 64 | 3 | fecha o leque de `@import` repetido |
| Seletores por seção | 20 000 (`maxRulesPerSection`) | 123 seletores em 77 regras | 160× o real |
| Profundidade de `@import` | 8 | 0 (o corpus não tem `@import`) | cadeias reais têm 1 ou 2 |
| Aninhamento de blocos | 32 | 2 (`@media { regra { } }`) | recursão do parser limitada |
| `style=""` | 8 KiB | 78 caracteres (562 atributos) | 100× o real |
| Compostos por seletor | 32 | 6 (`hgroup > h2 + p + p + p + p`) | limita o retrocesso |
| Profundidade de casamento | 256 | 7 | o filtro de Bloom e o descendente sobem no máximo 256 |
| Orçamento | 2^24 passos | ~0,85 M (5%) no capítulo de 200 mil palavras (1,2 MB, 3 749 elementos) com a folha do SE; ~0,25 M em `song-of-myself` | 20× o maior real; 2^24 passos sintéticos custaram 23 ms (limite inferior); o custo real por passo sai da tarefa de desempenho, e os testes hostis travam o teto em tempo |
| Cessão | 4 096 passos | — | lote pequeno o bastante para a fatia de 4 ms de [08](../08-concorrencia-cache.md) §2 mesmo com passo caro, grande o bastante para o `yield` não pesar |
| Cache de folhas | 8 Mi unidades de código **(decisão da spec, #15)** | 106 KB (o corpus inteiro) | 8 folhas no teto por publicação |
| Amostra em `details` | 64 unidades de código | — | como a data crua da Publicação |
| Literal numérico | 64 caracteres | — | `double.tryParse` sobre fatia curta |

Passou de um limite: corta com diagnóstico (§12) e a cascata continua.

## 12. Diagnósticos e exceções

### 12.1 Códigos

Três em `EpubDiagnosticCode`: `unsupportedLayout` entra agora (estava em doc/09
e no `knownDiagnostics` do corpus, não no código); `stylesheetIgnored` e
`cssRuleIgnored` são novos, no formato do `navIgnored` (`details.reason`).

| Código | Severidade | `href` | `details` | Quando |
|---|---|---|---|---|
| `stylesheetIgnored` | warning (`media`: info, por `severity:`) | a folha ignorada ou cortada; a seção para `<style>`, `style=""`, `dom-depth` e `budget` | `reason`; `from` (folha que importa, em `depth`/`cycle`/`limit` de `@import`); `limit` (`sheets`, `bytes`, `rules`, `nesting`, `dom-depth`); `media` (a lista, truncada); `import` (href cru, em `late-import`); `discarded` (blocos `@media` agregados); `source: 'style-attribute'` | ver `reason` abaixo |
| `cssRuleIgnored` | info | a folha; a seção para `style=""` | `reason`; `sample` (prelúdio truncado em 64); `discarded`; `source` | regra ou declaração descartada |
| `unsupportedLayout` | warning | a seção | `property` (`float`, `position`, `columns`, `writing-mode`), `value` | valor degradado venceu a cascata (§10.7) |

`reason` de `stylesheetIgnored`:

| `reason` | Situação |
|---|---|
| `too-large` | folha acima de 1 MiB, `<style>` acima de 1 MiB, `style=""` acima de 8 KiB |
| `cycle` | `@import` que volta a uma folha da pilha |
| `depth` | `@import` além da profundidade 8 |
| `limit` | teto de folhas, de bytes por seção, de seletores, de aninhamento ou de profundidade de DOM (`details.limit`) |
| `late-import` | `@import` depois de regra (§5.2) |
| `media` (`info`) | `<link>`/`<style>` com `media` que não casa; `@import` com media ou condição; blocos `@media` que não casam (um por folha, com `discarded`) |
| `budget` | orçamento da cascata esgotado |

`reason` de `cssRuleIgnored`: `parse-error` (sintaxe: prelúdio inválido,
declaração sem `:`, `badString`/`badUrl`, regra aninhada) e
`unsupported-selector` (§6.3). **Agregado** **(decisão da spec, #16)**: no
máximo um por (motivo, folha, seção), com `discarded` = quantos e `sample` =
o primeiro; é o `count` do `DiagnosticSink` que soma as seções. (`count` é
reservado do sink; por isso `discarded`.)

Reusados: `resourceMissing` (§9.2), `resourceUnreadable` (§9.3),
`encodingFallback` (§9.4). O `DiagnosticSink` deduplica por (código, `href`):
dois motivos de `stylesheetIgnored` na mesma folha viram um registro, com os
`details` do último e a severidade do último — com `strict` o `warning` já
lançou antes; fora dele, o conjunto de códigos, que é o que o corpus compara,
não muda. Registrado em [14](../14-pendencias.md), como a fusão parecida da
Publicação.

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
`exceptions.dart`, interna até o sub-projeto 6. Em `strict`, então, `resourceMissing`,
`resourceUnreadable`, `unsupportedLayout` e `stylesheetIgnored` (menos
`media`) lançam `EpubSectionParseException` com o nome do código na mensagem;
a exceção do sink que atravessa o `fetch`/`decode()` (por exemplo
`zipCrcMismatch` do contêiner) propaga como está, reconhecida por identidade
(§9.3).

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
| Tempo quadrático: `substring` em laço | Tokenizador com índice que só avança e uma fatia por token (§4.1); nenhum `split`/`RegExp` sobre o texto do livro; o prelúdio é juntado uma vez (§5.5) |
| Tempo quadrático: busca de descendente | Uma caminhada só, sobre `nodes` com pilha explícita (§9.1, §10.2); nada de `querySelectorAll`, `children` indexado ou subida pelo `parent` em laço fora do casamento, que é limitado por `failsCompletely`, Bloom, 32 compostos, 256 níveis e orçamento (§10.4, §10.6) |
| Tempo quadrático: ids repetidos | Classes do elemento deduplicadas (§10.2); balde por `id` consultado em O(1), qualquer que seja o número de elementos com o mesmo `id`; a mesma folha importada N vezes é limitada a 64 folhas e 20 000 seletores; diagnósticos agregados por folha (§12.1) |
| Exceção fora da taxonomia | Funções totais, sem `int.parse`, com `NaN` para literal longo (§4, §12.2); só `EpubException` do contêiner é capturada, e a do `strict` por identidade (§9.3); fuzz com contagem zero (§14.2) |
| Travessia de caminho | `normalizeHref` e `decodePath` da Publicação, `..` além da raiz e `%2e%2e` recusados; só `fetch` do contêiner (§9.2); ciclo pela pilha de caminhos reais (§9.5) |
| Semântica copiada errada de um padrão | Cada ponto marcado com a fonte: recuperação de erro do CSS Syntax (§5.3), posição do `@import` do CSS Cascade 4 (§5.2), camadas de origem e importância com `style=""` anexado (§10.5), `left` herdado como `left` (§3), `bolder`/`lighter` do CSS Fonts 4 (§3), `page-break-*` como a mesma propriedade (§7.1), `@charset` só na forma exata (§9.4), `:nth-child` e `+` contando só elementos (§6.1), classe com diferença de caixa (§6.1), `hidden` vencível pelo livro (§8.2), lista de seletores sem tolerância (§6.3) |

## 14. Testes

Em `test/css/`, com CSS e XHTML de texto nos testes de unidade (o DOM por
`html.parse` de fragmentos pequenos, ou montado por código nos hostis):

| Arquivo | O que cobre |
|---|---|
| `tokenizer_test.dart` | cada tipo de token; comentários (inclusive sem fim); strings com `}` e `;` dentro, com `\` + LF, sem fim, `badString`; escapes (hex curto, 6 dígitos, espaço depois, `\0`, surrogate, acima de U+10FFFF, `\` no fim); `url()` sem aspas, com espaço, com aspas (vira `function`), `badUrl`; números (`.5`, `1e3`, `+3`, `-0`, literal de 100 dígitos → `NaN`); `<!--`/`-->`; CR/CRLF/FF; U+0000 |
| `parser_test.dart` | regras, lista de seletores, recuperação (declaração ruim some, o resto fica; `{` e `(` no valor; regra aninhada); `!important` com espaço e caixa; `@media` que casa e que não casa, aninhado; `@import` antes e depois de regra (`late-import`), depois de `@charset`, depois de regra `parse-error` (vale), depois de `@namespace` (não vale), com media, com `layer`; at-rules descartadas; aninhamento 33 (`limit`); agregação de `CssIssue`; `parseStyleAttribute`; `mediaMatches` (tabela: ausente, vazio, `all`, `screen`, `only screen`, `SCREEN`, `screen, print`, `print`, `not screen`, `screen and (max-width: 600px)`, `amzn-kf8`) |
| `selector_test.dart` | cada forma de §6.1 e cada exclusão de §6.3 com o tipo de resultado; especificidade (tabela do Selectors 4 e saturação); lista com um seletor fora; 32 e 33 compostos; hashes de ancestral (`a > b + c`, `a + b c`) |
| `properties_test.dart` | cada linha de §7.1 com valores aceitos, mapeados, limitados e descartados; conversões de §7.2; atalhos (`margin` 1–4, `font` completo e mínimo, `font` com tamanho absoluto, `list-style`, `columns`); `inherit`/`initial`/`unset`/`revert`; degradadas de §7.4 |
| `ua_sheet_test.dart` | zero `CssIssue`; `h1`–`h6` com as razões de §8.1; `em`/`i` itálico, `b`/`strong` negrito, `head`/`script`/`style` `none`, `pre` `pre`, listas aninhadas, `ol[type]` com caixa |
| `loader_test.dart` | com `ProviderContainer` (`MapProvider`) e `ZipContainer` (`epubZip`): `<link>` (rel com vários tokens, `alternate`, `type`, `media`); `<style>` em `head`, `body` e SVG, com CDATA; ordem de coleta; `@import` relativo à folha, em `<style>` relativo à seção, em cadeia, duas vezes, ciclo, profundidade 9, 65 folhas, 4 MiB; folha de 1 MiB + 1 byte (não drenada); remota; `data:`; `..` além da raiz; `%20` e `%2e%2e`; ausente; `fetch` que lança (`resourceUnreadable`) e `strict` (a exceção do sink propaga; warning do CSS lança `EpubSectionParseException`); `decodeCss` (BOM × 3, `@charset` Latin-1, `@charset 'x'` que não conta, `@charset "utf-16"` → UTF-8, UTF-8 inválido → `encodingFallback`); cache (mesma folha em duas seções: um `fetch`; diagnósticos reemitidos; LRU); `cacheKey` com hash e texto |
| `rule_index_test.dart` | balde por `id`, primeira classe, tipo, universal; `seq`; teto de 20 000 com `truncatedAt` |
| `cascade_test.dart` | herança de cada propriedade herdada e não herdada; `inherit`/`initial`/`unset`; camadas (`!important` do livro vence `style=""` normal; `style=""` vence `#id`; ordem; última declaração do bloco); especificidade de lista; `text-align: left` herdado por filho `rtl`; `bolder`/`lighter` sobre 900; tipo de lista desconhecido em `ul`, `ol`, `li`; `fontSizeStep` relativo por nível; dicas `hidden` e `dir` e o livro vencendo `hidden`; `+`, `>`, descendente, `:nth-child`, `:last-child` com texto entre irmãos; `unsupportedLayout` só no vencedor e uma vez; profundidade 257; orçamento (`budgetExhausted`, a folha padrão continua); cessão a cada 4 096 passos (contagem de `yield`); internação (mesma instância); `originOf` |
| `computed_style_test.dart` | `initial`; igualdade e `hashCode`; `textAlign` e `fontWeight` derivados |
| `css_corpus_test.dart` | §14.1 |
| `css_fuzz_test.dart` | §14.2 |
| `css_hostile_test.dart` | §14.3 |

E `test/container/fnv1a64_test.dart` com os vetores do FNV (`""` →
`cbf29ce484222325`, `"a"` → `af63dc4c8601ec8c`, `"foobar"` →
`85944171f73967e8`) e a mesma saída em `add` fatiado.

### 14.1 Corpus

Para cada caso de `test/corpus/**` que abre (os de `exception.expected` ficam
de fora, como na Publicação): o `ZipContainer` é aberto com o sink do CSS (os
`decode()` das folhas emitem no sink do contêiner); `readPublication` recebe
um sink próprio, sem `strict` (a Publicação tem o teste dela); para cada
item do spine com `content` `xhtml`, local e presente, `fetch` + `decodeXml(…,
htmlMeta: true)` (um sink descartável: a decodificação do XHTML é do
sub-projeto 4) + `html.parse`; `loadSectionSheets` com **um** `StyleSheetCache`
por livro e o sink do CSS; `computeStylesSync(recordOrigins: true)`.

- **Códigos comparados:** o conjunto de `stylesheetIgnored`, `cssRuleIgnored`
  e `unsupportedLayout` emitido pelo sink do CSS é igual ao desses códigos em
  `diagnostics.expected`; `resourceMissing`, `resourceUnreadable` e
  `encodingFallback` emitidos pelo CSS precisam constar do `.expected` (podem
  ser de outra camada).
- **Modo:** a regra de [10](../10-testes.md) §5: `strict: true` fora de
  `patologia/` e `faixa-b/`, exceto os casos cujo `.expected` lista um
  `warning` do CSS (`unsupportedLayout`, `stylesheetIgnored`,
  `resourceMissing`, `resourceUnreadable`), que rodam sem `strict` e ganham a
  segunda passada em `strict` esperando `EpubSectionParseException` com o nome
  de um desses códigos na mensagem.
- **Estruturais, em toda seção:** `styles.length` = número de elementos do
  documento; `head`, `script`, `style` e `title` presentes têm `display:
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
    url(x.css) print`. `diagnostics.expected`: `stylesheetIgnored`.
    Afirmações: só as regras de `screen`/`all` sem condição valem.
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
  no `h1` da página de rosto e no `h2` do colofão) e `stylesheetIgnored`
  (`@media all and (prefers-color-scheme…)`); `alice-ilustrada-en` ganha
  `unsupportedLayout` (`float` em `.figleft`/`.figright`).
- `test/corpus/corpus_test.dart`: `knownDiagnostics` com `stylesheetIgnored` e
  `cssRuleIgnored`.

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
`var(--x)`, U+0000, BOM, bytes Latin-1 e UTF-8 inválido. Afirmações: só
`EpubException` escapa (contada, e zero fora da taxonomia); fora de `strict`,
todo elemento tem estilo. **Fuzz grande** (dezenas de milhares de mutações,
semente aleatória, local) na revisão final da branch, como na Publicação.

### 14.3 Hostis

`css_hostile_test.dart`, cada um com teto de tempo (`Stopwatch`, como o
`href_test` da Publicação; o número sai da medição da tarefa e fica com folga
para o CI) e a afirmação de corte certo:

| Entrada | Afirmação |
|---|---|
| Folha de 1 MiB com um seletor `a a a … b` de 200 000 compostos | `unsupported-selector`, linear |
| 20 000 regras `* { font-style: italic }` sobre 5 000 elementos | `budget`, `budgetExhausted`, folha padrão ainda aplicada |
| 20 000 regras `div div … div p` (31 compostos) sobre 256 `div` aninhados | Bloom/`failsCompletely` e orçamento, linear |
| DOM de 10 000 níveis montado por código (sem `html.parse`, que é quadrático nesse aninhamento) | `dom-depth` uma vez, todos os elementos com estilo |
| 100 000 elementos com o mesmo `style=""` e 1 000 com textos diferentes de 8 KiB; um de 8 KiB + 1 | um parse por texto; `too-large` |
| `{`, `(` e `[` repetidos 500 000 vezes; comentário, string e `url(` sem fim de 1 MiB | `limit` (`nesting`), linear |
| Escapes `\` e `\FFFFFFFF` repetidos; literal numérico de 1 MiB | sem exceção, linear |
| `@import` em leque (cada folha importa a seguinte duas vezes) e ciclo `a → b → a` | 64 folhas; `cycle` |
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
  `sizeSmaller`/`sizeLarger` já guardam (§4, sem mudança no IR), margens e
  recuo em `em` como adição, as degradadas de §7.4, a folha padrão, as dicas
  `hidden`/`dir`, a fonte de CSS em `<style>` de SVG e a ordem com `@import`.
- [08](../08-concorrencia-cache.md) §3: checkpoint da cascata "a cada 4 096
  passos" (não "a cada regra"). §4.1: a chave usa a lista ordenada de
  `SheetRef` (`bytesHash` de cada arquivo, texto de cada `<style>`) no lugar
  dos bytes de cada CSS, e a folha padrão entra por `IR_SCHEMA_VERSION`;
  `Fnv1a64` existe em `lib/src/container/`.
- [09](../09-erros-diagnosticos.md) §2: `EpubSectionParseException`
  implementada, e em `strict` também todo warning do CSS. §3: `stylesheetIgnored`
  e `cssRuleIgnored` com os `reason`; `unsupportedLayout` com `href` = seção,
  `details.property`/`value`, e emitido pelo vencedor da cascata.
- [10](../10-testes.md) §1.1: os três casos novos (68 no total). §5: os
  warnings do CSS na regra da segunda passada. §6: o fuzz de CSS. §4.2: os
  casos `css.parse` e `css.cascade`.
- [14](../14-pendencias.md): regenerar baselines com `css.parse` e
  `css.cascade`; fuzz grande do CSS na revisão final; parse das folhas no
  prólogo sem ceder (sub-projeto 5); fusão de motivos de `stylesheetIgnored`
  pelo dedupe do sink; `text-decoration` (sublinhado e riscado por CSS) fora
  da tabela; propriedades lógicas (`margin-inline-*`) ignoradas; dicas de
  apresentação além de `hidden`/`dir` (`align`, `width`/`height` de `img` como
  CSS); `[attr]`, `~=` e `:not()` simples; lista de seletores descartada
  inteira por um seletor fora do subconjunto (§6.3); `@supports` descartado
  inteiro;
  aninhamento do CSS Nesting; `@layer` e `@import … layer`; `vw`/`vh`/`calc()`;
  codificação do documento que referencia (passo do CSS Syntax omitido);
  recuo de lista físico (`padding-left`) em livro `rtl`; filhos de `flex`/`grid`
  sem "blocoficação".
- `CHANGELOG.md`: "Fase 1, sub-projeto 3 (CSS): tokenizador e parser do CSS
  Syntax recortado, `@import` e `@media` com limites, seletores do subconjunto
  com índice pela direita e filtro de Bloom, cascata com herança e estilo
  computado classificado nas três classes, folha padrão do HTML, diagnósticos
  `stylesheetIgnored`, `cssRuleIgnored` e `unsupportedLayout`."
- `test/corpus/corpus_test.dart` (`knownDiagnostics`), os `.expected` de §14.1,
  e os testes que contam 65 casos.
