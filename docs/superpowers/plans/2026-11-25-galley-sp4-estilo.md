# Galley SP4 — Estilo (motor CSS + preferências do leitor) — Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dar a cada elemento da árvore do SP3 um estilo calculado (folha padrão + CSS da editora + `style=` + preferências do leitor), com estilos internados e compartilhados, casamento guardado para trocar preferências sem casar seletores de novo, resultado transferível entre isolates e benchmark expandido.

**Architecture:** Leitor de CSS próprio (CSS Syntax Level 3) produz folhas com propriedades como ids inteiros e valores pré-interpretados; um contexto por livro guarda as folhas lidas. `matchDocument` indexa as regras, casa da direita para a esquerda com filtro de ancestrais e resolve a cascata da editora num `MatchedDocument` (conjuntos de valores declarados internados por elemento + marcas de texto corrido). `restyle` percorre a árvore uma vez: calcula valores, aplica a passada de preferências e interna `ComputedStyle` num `StyledDocument` de arranjos tipados.

**Tech Stack:** Dart puro, `xml` e `meta` (runtime); benchmark no pacote `benchmark/` (SP2), com `csslib` só como concorrente do `compare`.

**Spec:** `docs/superpowers/specs/2026-11-25-galley-sp4-estilo-design.md` (dados: `docs/superpowers/specs/dados/2026-11-25-levantamento-css.md`; pai: `2026-11-24-galley-arquitetura-design.md`)

## Global Constraints

- Dependências de runtime do `galley`: **somente `xml` e `meta`**; o `csslib` entra **apenas** em `benchmark/pubspec.yaml`.
- Dart puro, sem `dart:ui`/Flutter na etapa (roda em isolate).
- Só `GalleyException` escapa; CSS quebrado nunca recusa livro nem capítulo: é recuperado como nos navegadores, com `Diagnostic`.
- Tudo interno (`lib/src/features/style/`, camadas `data`/`domain`); nada novo em `lib/galley.dart` (a forma exportada das preferências é do SP6).
- Nenhuma recursão proporcional à entrada: percursos da árvore, blocos do CSS e `calc()` usam pilha explícita ou limite de profundidade.
- `medium` = **16 px lógicos**; tipo de mídia do ambiente sempre `screen`.
- Sem preferência alguma (`ReaderPreferences.none`) o resultado é idêntico ao da editora.
- Preferências **não** são origem da cascata: passada sobre os valores calculados, valendo mesmo contra `!important` da editora.
- `%`, `vw`/`vh` e `calc()` com termos dependentes da largura ficam simbólicos até o layout.
- Limite de diagnósticos: **20 por código + 1 resumo** (o `reportLimit` do SP3).
- Gates do SP2 desde o primeiro PR (instruções 0,5% e A/B); suítes novas entram no catálogo.
- Comentários e docs em pt-BR; commits `tipo(escopo): descrição` em português.

## Review Focus

1. **Preferência aplicada duas vezes pela herança** (fator de tamanho num filho em `em`; multiplicador de entrelinha num `em` sem `line-height` próprio dentro do parágrafo; espaçamento de letras herdado): aplica uma vez só — `h1 { font-size: 2em }` com fator 1,5 dá 48 px, não 72 (Task 10).
2. **Caixa alta no CSS** (`COLOR: RED`, `Margin-Top: 1EM`, `!IMPORTANT`, `@MEDIA SCREEN`, `#ABC`, `:FIRST-CHILD`, `P { }` contra `<p>`): funciona como nos navegadores (Tasks 2, 3, 4 e 5).
3. **Aninhamento patológico** (100.000 `{`, `(` ou `@media all {` sem fechar; documento com 10.000 níveis no casamento e no `restyle`): sem estouro de pilha, tempo linear (Tasks 2, 7 e 8).
4. **Valores numéricos extremos** (`font-size: 1e30px`, `1000%` aninhado 40 vezes, `font-size: 0`, `z-index: 99999999999`): valores calculados finitos e limitados, sem NaN/Infinity, hash estável inalterado (Tasks 3 e 8).
5. **Documento sem `<body>` XHTML** (item SVG do spine, documento recuperado com `body` virtual, `body { display: none }`): classificação de texto corrido e preferências não lançam e usam o tamanho da raiz como referência (Tasks 9 e 10).

---

## Estrutura de arquivos

```
lib/src/core/diagnostics/limited_diagnostic_sink.dart  # limite por código (extraído do SP3)
lib/src/core/diagnostics/diagnostic_codes.dart          # códigos css.*
lib/src/features/style/
  data/css_decode.dart          # bytes → texto (BOM, @charset, UTF-8)
  data/css_tokenizer.dart       # CssToken, tokenizeCss
  data/css_syntax.dart          # regras e declarações cruas, recuperação de erros
  data/property_parser.dart     # valores pré-interpretados, abreviadas, aliases
  data/selector_parser.dart     # prelúdio → Selector
  data/stylesheet_builder.dart  # at-rules → StyleSheet
  data/book_style_context.dart  # BookStyleContext: cache, @import, @font-face
  data/default_stylesheet.dart  # folha padrão (texto + instância lida uma vez)
  data/style_document.dart      # matchDocument, styleDocument
  domain/css_value.dart         # CssValue e variantes, CssKeywords
  domain/properties.dart        # PropertyId, tabela (herdada, inicial)
  domain/selector.dart          # Selector, PseudoElement, NamespaceMap
  domain/selector_matcher.dart  # casamento + filtro de ancestrais
  domain/stylesheet.dart        # StyleSheet, StyleRule, Declaration, FontFaceRule, PageMargins
  domain/style_environment.dart # StyleEnvironment, MediaQueryList
  domain/rule_index.dart        # baldes id/classe/nome/universal
  domain/cascade.dart           # cascata → CascadedValues
  domain/matched_document.dart  # MatchedDocument, ElementFlags
  domain/text_run.dart          # classificação de texto corrido
  domain/value_computer.dart    # especificado → calculado, herança
  domain/computed_style.dart    # ComputedStyle, StyleInterner, hash estável
  domain/reader_preferences.dart
  domain/preference_pass.dart
  domain/restyle.dart
  domain/styled_document.dart
benchmark/lib/src/suites/style_suites.dart
benchmark/lib/src/competitors/css_adapter.dart
```

---

### Task 1: Decodificação e tokenizador (CSS Syntax 3)

**Files:**
- Create: `lib/src/features/style/data/css_decode.dart`, `lib/src/features/style/data/css_tokenizer.dart`
- Test: `test/features/style/data/css_decode_test.dart`, `test/features/style/data/css_tokenizer_test.dart`

**Interfaces:**
- Produces:
  - `String decodeCss(Uint8List bytes)`: BOM (UTF-8, UTF-16LE/BE) → `@charset "<rótulo>";` com os bytes exatos da especificação → UTF-8. Rótulos `iso-8859-1`, `latin1`, `us-ascii`, `windows-1252` decodificam como windows-1252 (latin1 com 0x80–0x9F pela tabela windows-1252, como no HTML); `utf-16*` e desconhecidos → UTF-8. Bytes inválidos → U+FFFD.
  - `enum CssTokenType { ident, function, atKeyword, hash, string, badString, url, badUrl, delim, number, percentage, dimension, whitespace, cdo, cdc, colon, semicolon, comma, leftSquare, rightSquare, leftParen, rightParen, leftBrace, rightBrace }`
  - `final class CssToken { final CssTokenType type; final String value; final double number; final bool isInteger; final String unit; final bool isIdHash; final int start; final int end; }` (`value`: nome do ident/função/hash, conteúdo da string/url ou caractere do delim; offsets no texto pré-processado).
  - `List<CssToken> tokenizeCss(String source)`: pré-processa (CR, CRLF, FF → LF; NUL e surrogates soltos → U+FFFD), descarta comentários, sem token EOF; números e escapes pelo algoritmo da especificação.

- [ ] **Step 1: Testes que falham**
  - `'a{color:red}'` → tipos `[ident, leftBrace, ident, colon, ident, rightBrace]`.
  - `'12'` → number 12, `isInteger`; `'+.5e1'` → 5.0, não inteiro; `'10%'` → percentage 10; `'1e3px'` → dimension 1000 `'px'`; `'1EM'` → unidade `'EM'` (caixa tratada na Task 3).
  - `'"a\\62 c"'` → string `'abc'`; `'"ab\ncd"'` começa com `badString`; `'\\31 0'` → ident `'10'`.
  - `'url( a.png )'` → url `'a.png'`; `'url(a b)'` → badUrl; `'url("a.png")'` → `[function 'url', string, rightParen]`.
  - `'#id'` → `isIdHash` true; `'#1a'` → false. `'<!-- -->'` → `[cdo, whitespace, cdc]`; `'/* x'` → `[]`; `'\u0000'` → ident `'�'`.
  - 1 MiB de string sem fim, de comentário sem fim e de `\\` repetidos: cada um < 2 s.
  - `decodeCss`: BOM UTF-8 e BOM UTF-16LE de `'a{}'` → `'a{}'`; `@charset "iso-8859-1";` + 0xE9 → `é` e + 0x93 → U+201C; `@charset "UTF-8";` → UTF-8; `@charset "utf-16";` com bytes ASCII → UTF-8; `@charset 'latin1';` (aspas simples) → UTF-8; 0xFF solto → U+FFFD.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar. **Step 4:** PASS (`flutter test test/features/style`).
- [ ] **Step 5: Commit** `feat(style): decodificação e tokenizador de CSS (Syntax Level 3)`

---

### Task 2: Sintaxe — regras, declarações e recuperação de erros; limite de diagnósticos compartilhado

**Files:**
- Create: `lib/src/features/style/data/css_syntax.dart`, `lib/src/core/diagnostics/limited_diagnostic_sink.dart`
- Modify: `lib/src/core/diagnostics/diagnostic_codes.dart`; `lib/src/features/document/data/head_extractor.dart` (trocar o `_LimitedSink` privado pelo compartilhado); `lib/src/features/document/data/event_adapter.dart` (`reportLimit = kDiagnosticReportLimit`)
- Test: `test/features/style/data/css_syntax_test.dart`, `test/core/limited_diagnostic_sink_test.dart`

**Interfaces:**
- Consumes: `tokenizeCss`, `CssToken` (Task 1).
- Produces:
  - `const int kDiagnosticReportLimit = 20;` e `final class LimitedDiagnosticSink implements DiagnosticSink { LimitedDiagnosticSink(DiagnosticSink target, {int limit = kDiagnosticReportLimit}); void report(Diagnostic d); void flush(); }` — `flush` emite, por código excedido, `mais N ocorrência(s) de <código> omitida(s) (total T)` com a gravidade e o `location` da primeira ocorrência.
  - `sealed class CssRule { int get offset; }`:
    - `final class QualifiedRule extends CssRule { final List<CssToken> prelude; final List<RawDeclaration> declarations; }`
    - `final class AtRule extends CssRule { final String name; final List<CssToken> prelude; final List<CssRule>? rules; final List<RawDeclaration>? declarations; }` — `name` em minúsculas; `rules` só em `media`/`supports`/`document`; `declarations` só em `font-face`/`page`; bloco de outras at-rules consumido e descartado.
  - `final class RawDeclaration { final String name; final List<CssToken> value; final bool important; final int offset; final int valueStart; final int valueEnd; }` — `name` em minúsculas ASCII (`--*` mantém a caixa); `value` aparado e sem `!important`; `valueStart`/`valueEnd` delimitam o texto cru (usado pelo `unicode-range`).
  - `final class ParsedCss { final List<CssRule> rules; int lineOf(int offset); }`
  - `ParsedCss parseCss(String source, {required String location, required DiagnosticSink sink})` e `List<RawDeclaration> parseCssDeclarations(String source, {required String location, required DiagnosticSink sink})` (para `style=`).
  - `DiagnosticCodes.cssParseError = 'css.parseError'` (warning), um por ponto de recuperação, `location` = `'<location>:<linha>'`.
- Regras: algoritmo do CSS Syntax 3 **sem aninhamento CSS** (0% dos livros); CDO/CDC ignorados no topo; declaração sem `:` descartada até o próximo `;`; at-rule dentro de lista de declarações consumida e descartada; `!important` = `!` + ident `important` nos dois últimos tokens não-espaço (sem diferença de caixa, espaço permitido entre eles); blocos `{}`/`[]`/`()` consumidos com pilha explícita; at-rules aninhadas além de **32** níveis têm o bloco descartado com `css.parseError`.

- [ ] **Step 1: Testes que falham**
  - `'p{color:red;;margin:0}'` → 1 regra, declarações `color` e `margin`; `'p{color red; margin:0}'` → só `margin` + 1 `css.parseError`.
  - `'p{color:red} } q{margin:0}'` → 2 `QualifiedRule`, o prelúdio da segunda começa com `rightBrace` (o seletor é rejeitado na Task 4).
  - `'@media print { p{x:y} } q{color:red}'` → `AtRule('media')` com 1 regra interna, depois `q`.
  - Revisão 2: `'P{COLOR:Red !IMPORTANT}'` → nome `color`, valor `[ident 'Red']`, `important`; `'p{color:red ! important}'` → `important`.
  - `'p{a:b'` → 1 regra com `a`; `'@import "a.css";p{}'` → `AtRule('import')` sem bloco, depois `p`; `'p{color:red; @media x {}; margin:0}'` mantém `color` e `margin`; `'<!-- p{color:red} -->'` → 1 regra; `parseCssDeclarations('color: red; text-align:center')` → 2; `lineOf` de uma declaração na linha 3 → 3.
  - Revisão 3: `'p{a:${'(' * 100000}'`, `'{' * 100000` e `'@media all{' * 100000` não lançam, cada um < 2 s, e no máximo 21 `css.parseError` após o `flush`.
  - `LimitedDiagnosticSink`: 25 relatos do mesmo código → 20 + 1 resumo contendo `'total 25'`; dois códigos contados à parte. Os testes do `head_extractor` do SP3 seguem verdes.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar. **Step 4:** PASS (`flutter test`).
- [ ] **Step 5: Commit** `feat(style): regras e declarações CSS com recuperação de erros`

---

### Task 3: Propriedades e valores pré-interpretados

**Files:**
- Create: `lib/src/features/style/domain/css_value.dart`, `lib/src/features/style/domain/properties.dart`, `lib/src/features/style/data/property_parser.dart`
- Test: `test/features/style/data/property_parser_test.dart`

**Interfaces:**
- Consumes: `CssToken` (Task 1); `resolveHref` (SP1, `lib/src/features/container/data/path/epub_path.dart`).
- Produces:
  - `@immutable sealed class CssValue` (igualdade por valor), variantes: `CssKeyword(int id)`; `CssLengthSpec({double px = 0, em = 0, ex = 0, rem = 0, percent = 0, vw = 0, vh = 0})` (**especificado**; absolutas viram px na leitura: 1pt = 4/3 px, 1pc = 16 px, 1in = 96 px, 1cm = 96/2,54 px, 1mm = cm/10, 1Q = cm/40; `ch` conta como 0,5 em no coeficiente `ex`); `CssLength({double px = 0, percent = 0, vw = 0, vh = 0})` (**calculado**, `bool get isAbsolute`); `CssNumber(double)`; `CssColor(int argb)`; `CssFontFamilies(List<FontFamilyName>)` com `FontFamilyName(String name, {bool generic = false})`; `CssString(String)`; `CssUrl(String path)` (já resolvido no zip); `CssContent(List<ContentItem>)` com `sealed ContentItem` = `ContentText(String)`, `ContentQuote(QuoteKind)` (`open`, `close`, `noOpen`, `noClose`), `ContentAttr(String)`, `ContentCounter(String name, int style)`; `CssQuotes(List<(String, String)>)`; `CssCounterChanges(List<(String, int)>)`; `CssList(List<CssValue>)`.
  - `abstract final class CssKeywords { static int? idOf(String name); static String nameOf(int id); }` — sem diferença de caixa ASCII, com constantes para as palavras usadas em lógica (`inherit`, `initial`, `unset`, `none`, `auto`, `normal`, `block`, `listItem`, `start`, `end`, `left`, `right`, `center`, `justify`, `currentcolor`, `transparent`…).
  - `abstract final class PropertyId { static const int ...; }`, `const int kPropertyCount` (só longhands), `final class PropertyInfo { final String name; final bool inherited; final CssValue initial; }`, `PropertyInfo propertyInfo(int id)`.
  - `sealed class PropertyParseResult` = `ParsedLonghands(List<(int, CssValue)> values)` | `UnsupportedProperty()` | `IgnoredProperty()` | `InvalidValue()`.
  - `PropertyParseResult parseProperty(String name, List<CssToken> value, {required String sheetPath})` — abreviadas viram longhands; `inherit`/`initial`/`unset` sozinhos valem para todas as longhands.
- **Escopo (lista exata, levantamento + o que a folha padrão exige; longhands entre parênteses):**
  - Fonte: `font-family`, `font-size`, `font-style`, `font-weight`, `font-variant`, `font-variant-numeric`, `font` (abreviada; reinicia as demais, aceita `size/line-height`; fontes de sistema → `InvalidValue`).
  - Texto: `text-align`, `text-indent`, `text-transform`, `text-decoration` (`-line`, `-style`, `-color`), `letter-spacing`, `word-spacing`, `white-space`, `hyphens`, `line-height`, `vertical-align`, `direction`, `unicode-bidi`, `writing-mode`, `text-combine-upright`, `hanging-punctuation`, `overflow-wrap`, `text-emphasis-style`, `text-emphasis-color`, `text-wrap`.
  - Caixa: `display`; `margin`, `padding` (1–4 valores; `-top/-right/-bottom/-left`); `border`, `border-top/-right/-bottom/-left`, `border-width/-style/-color` (12 longhands `border-<lado>-<width|style|color>`; `thin` 1 px, `medium` 3 px, `thick` 5 px); `border-radius` (1–4 valores, a parte após `/` ignorada; 4 longhands de canto); `width`, `height`, `min-width`, `min-height`, `max-width`, `max-height`, `box-sizing`, `object-fit`.
  - Fluxo: `float`, `clear`, `position`, `top`, `right`, `bottom`, `left`, `z-index`, `overflow`, `flex-direction`, `justify-content`, `align-items`.
  - Cor e fundo: `color`, `background-color`, `background-image`, `background-repeat`, `background-position`, `background-size`, `background` (abreviada; `attachment` ignorado), `opacity`.
  - Listas: `list-style` (`-type`, `-position`, `-image`). Tabela: `border-collapse`, `border-spacing`, `caption-side`, `table-layout`, `empty-cells`.
  - Fragmentação: `break-before`, `break-after`, `break-inside`, `orphans`, `widows`. Conteúdo: `content`, `quotes`, `counter-increment`, `counter-reset`, `visibility`.
- **Aliases:** `page-break-before/-after` → `break-*` (`always` → `page`; `avoid`, `auto`, `left`, `right` iguais); `page-break-inside` → `break-inside`; `-webkit-hyphens`, `-epub-hyphens`, `-moz-hyphens`, `-ms-hyphens`, `adobe-hyphenate` → `hyphens`; `-epub-writing-mode`, `-webkit-writing-mode` → `writing-mode`; `-epub-text-combine` → `text-combine-upright` (`horizontal` → `all`); `-epub-text-emphasis-style/-color` → `text-emphasis-*`; `word-wrap` → `overflow-wrap`.
- **`IgnoredProperty`** (sem diagnóstico): `speak`, `speak-as`, `speak-punctuation`, `speech-rate`, `stress`, `volume`, `richness`, `pause`, `pause-before`, `pause-after`, `-webkit-tap-highlight-color`, `pointer-events`, `adobe-text-layout`, `background-attachment`. **`UnsupportedProperty`:** todo o resto, inclusive `--*`, `filter`, `box-shadow`, `all`, `transform`, `transition*`.
- **Valores:** cores por nome (147 + `transparent`, `currentcolor`), `#rgb(a)`, `#rrggbb(aa)`, `rgb()/rgba()`, `hsl()/hsla()` (sintaxes com vírgula e com espaço); `0` sem unidade é comprimento; número sem unidade só em `line-height`, `z-index`, `orphans`, `widows`, `opacity` e `font-weight` (1–1000); negativos inválidos em `padding*`, `width/height/min-*/max-*`, larguras de borda, `font-size` e `line-height`; `calc()` com `+ - * /` e parênteses vira a forma linear de `CssLengthSpec` (inválido: produto de dimensões, divisão por zero, aninhamento > 32); `min()`, `max()`, `clamp()`, `var()` → `InvalidValue`; inteiros limitados a [−2³¹, 2³¹−1]; `url()` resolvido por `resolveHref(sheetPath, url)`, externo ou fora do zip → inválido.

- [ ] **Step 1: Testes que falham**
  - Revisão 2: `color: RED` → `CssColor(0xFFFF0000)`; `#ABC` → `0xFFAABBCC`; `margin-top: 1EM` → `CssLengthSpec(em: 1)`. `rgb(255 0 0 / 50%)` → `0x80FF0000`; `rgba(0,0,0,.5)` → `0x80000000`.
  - `margin: 1em 2px` → topo/base `em: 1`, lados `px: 2`; `font-size: 12pt` → `px: 16`; `calc(100% - 2em)` → `(percent: 100, em: -2)`; `calc(2em * 3)` → `em: 6`; `calc(1px * 1px)` e `calc(1px / 0)` → `InvalidValue`.
  - `-webkit-hyphens: auto` → `(hyphens, auto)`; `page-break-after: always` → `(break-after, page)`; `-epub-text-combine: horizontal` → `(text-combine-upright, all)`.
  - `font: italic bold 12px/1.5 Georgia, serif` → estilo `italic`, peso `CssNumber(700)`, tamanho `px: 12`, `line-height` `CssNumber(1.5)`, família `[Georgia, serif(generic)]`, `font-variant` `normal`; `border: 1px solid black` → 12 longhands; `text-decoration: underline overline` → `CssList[underline, overline]`; `margin: inherit` → 4 × `inherit`.
  - `padding: -1px`, `font-size: -2em`, `color: 12px` → `InvalidValue`; `speak: none` → `IgnoredProperty`; `filter: invert(1)`, `--x: 1` → `UnsupportedProperty`.
  - `content: "«" attr(title) open-quote` → `[ContentText('«'), ContentAttr('title'), ContentQuote(open)]`; `font-family: "Body Text", monospaced` → dois nomes não genéricos; `line-height: 150%` → `percent: 150`; `background-image: url(../img/a.png)` com `OEBPS/css/s.css` → `CssUrl('OEBPS/img/a.png')`.
  - Revisão 4: `z-index: 99999999999` → `CssNumber(2147483647)`; `font-weight: 0` → `InvalidValue`.
  - Todo nome do escopo, dos aliases e das ignoradas é reconhecido.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar. **Step 4:** PASS.
- [ ] **Step 5: Commit** `feat(style): tabela de propriedades e valores pré-interpretados`

---

### Task 4: Seletores — leitura, especificidade e casamento

**Files:**
- Create: `lib/src/features/style/domain/selector.dart`, `lib/src/features/style/data/selector_parser.dart`, `lib/src/features/style/domain/selector_matcher.dart`
- Modify: `lib/src/core/diagnostics/diagnostic_codes.dart`
- Test: `test/features/style/data/selector_parser_test.dart`, `test/features/style/domain/selector_matcher_test.dart`

**Interfaces:**
- Consumes: `CssToken` (Task 1); `DocumentTree`, `Namespaces` (SP3).
- Produces:
  - `enum PseudoElement { before, after, firstLetter, firstLine }`; `final class NamespaceMap { final String? defaultUri; final Map<String, String> prefixes; static const empty; }`
  - `final class Selector { int get specificity; PseudoElement? get pseudoElement; String? get rightmostId; String? get rightmostClass; String? get rightmostType; List<int> get ancestorHashes; }` — especificidade empacotada `a << 20 | b << 10 | c`; `ancestorHashes` = ids, classes e nomes dos compostos à esquerda de combinadores descendente/filho (usados na Task 7); representação interna livre.
  - `List<Selector>? parseSelectorList(List<CssToken> prelude, NamespaceMap namespaces)` — `null` se **qualquer** seletor da lista for inválido (a regra inteira cai, como no CSS).
  - `final class SelectorMatcher { SelectorMatcher(DocumentTree tree, {String? documentLang}); bool matches(Selector selector, int element); }`
  - `DiagnosticCodes.cssUnsupportedSelector = 'css.unsupportedSelector'` (info; emitido pela Task 5).
- Regras (spec §8.3): nível 3 completo — tipo, universal, classe, id, atributo (`= ~= |= ^= $= *=`, flag `i`), combinadores descendente, `>`, `+`, `~`; `:root`, `:first-child`, `:last-child`, `:only-child`, `:nth-child()`, `:nth-last-child()`, `:nth-of-type()`, `:nth-last-of-type()`, `:first-of-type`, `:last-of-type`, `:only-of-type`, `:empty` (qualquer texto, mesmo espaço, é conteúdo); `:lang()` pelo `xml:lang`/`lang` do ancestral mais próximo (`xml:lang` vence), senão `documentLang`, casando `x` ou `x-*` sem caixa; `:not()` com argumento **simples**; `:link` = `a`/`area` XHTML com `href`; `::before`, `::after`, `::first-letter`, `::first-line` (também com `:`), só no fim. `:hover`, `:active`, `:focus`, `:visited` são válidos e nunca casam. Pseudo desconhecido, `:has`, `:is` e `:nth-child(… of S)` invalidam. `an+b` com `odd`, `even`, `-n+3`, `+5` e espaços. Caixa: nomes de pseudo/função sem caixa; tipo **sem caixa** contra elementos XHTML (qualquer tipo de documento) e com caixa nos demais namespaces; classe e id com caixa; nome de atributo sem caixa em elementos XHTML. Namespaces: sem `@namespace` padrão o tipo casa qualquer namespace; `ns|tipo`, `*|tipo`, `|tipo`, `[ns|attr]`; prefixo não declarado invalida.

- [ ] **Step 1: Testes que falham** sobre (via `parseDocumentBytes`):
  `<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xmlns:svg="http://www.w3.org/2000/svg" xml:lang="pt"><body><div id="d" class="a b"><p class="x" title="hello world" lang="en-US">1</p><p>2</p><span/><p epub:type="footnote">3</p></div><a href="#n">l</a><svg:svg><svg:rect/></svg:svg></body></html>`
  - `p` → os 3 `p`; Revisão 2: `P` → os 3 `p` e `:FIRST-CHILD` é aceito; `.X` → nada.
  - `#d > p:first-child` → p1; `p + p` → p2; `p ~ p` → p2, p3; `p:nth-child(odd)` → p1; `#d > :nth-child(2n + 1)` → p1, span; `p:nth-of-type(3)` e `p:last-of-type` → p3; `span:empty` → span.
  - `[title~=world]`, `[title^=hel]`, `[title$=LD i]`, `[lang|=en]` → p1; `:lang(pt)` → p2 e não p1; `:lang(en)` → p1.
  - `a:link` → `a`; `a:hover`, `a:visited` → válidos, nada; `p:not(.x)` → p2, p3; `:not(p.x)` → `null`.
  - Com `@namespace svg url(http://www.w3.org/2000/svg)`: `svg|rect` → rect; `rect` → rect; com `@namespace epub url(http://www.idpf.org/2007/ops)`: `[epub|type~=footnote]` → p3; `foo|p` sem declaração → `null`. `:root` → `html`.
  - Especificidade: `#a .b c` → (1,1,1); `p::before` → (0,0,2); `:not(#x)` → (1,0,0); `*` → 0. `p:before` → `pseudoElement == before`; `p::before span` → `null`.
  - `p:nth-child(2 of .x)`, `:has(p)` e `p, q:desconhecida` → `null`.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar. **Step 4:** PASS.
- [ ] **Step 5: Commit** `feat(style): seletores CSS nível 3 com especificidade e casamento`

---

### Task 5: Folhas — at-rules, ambiente e montagem da `StyleSheet`

**Files:**
- Create: `lib/src/features/style/domain/stylesheet.dart`, `lib/src/features/style/domain/style_environment.dart`, `lib/src/features/style/data/stylesheet_builder.dart`
- Modify: `lib/src/core/diagnostics/diagnostic_codes.dart`
- Test: `test/features/style/domain/media_query_test.dart`, `test/features/style/data/stylesheet_builder_test.dart`

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces:
  - `enum ColorScheme { light, dark }`; `final class StyleEnvironment { const StyleEnvironment({required double pageWidth, required double pageHeight, ColorScheme colorScheme = ColorScheme.light}); }`
  - `final class MediaQueryList { bool evaluate(StyleEnvironment env); }`; `MediaQueryList parseMediaQueryList(List<CssToken> tokens)`; `MediaQueryList parseMediaQueryText(String text)` (atributo `media`).
  - `final class Declaration { final int property; final CssValue value; final bool important; }`
  - `final class StyleRule { final Selector selector; final List<Declaration> declarations; final int order; final List<MediaQueryList> conditions; }` — uma por seletor da lista (declarações compartilhadas); `conditions` = `@media` aninhados (todos precisam valer).
  - `sealed class FontSource` = `FontUrlSource(String path, String? format)` | `FontLocalSource(String name)`; `final class FontFaceRule { final String family; final String internalFamily; final List<FontSource> sources; final int weightMin, weightMax; final int style; final String? stretch; final List<(int, int)> unicodeRanges; }`
  - `final class PageMargins { final CssLengthSpec? top, right, bottom, left; }`; `final class ImportRef { final String path; final MediaQueryList? media; }`
  - `final class StyleSheet { final List<StyleRule> rules; final List<FontFaceRule> fontFaces; final List<(PageMargins, List<MediaQueryList>)> pages; final List<ImportRef> imports; static final StyleSheet empty; }` — **não depende do ambiente** (o `@media` é avaliado no casamento), por isso pode ser guardada por livro.
  - `StyleSheet buildStyleSheet(String css, {required String path, required String fontPrefix, required DiagnosticSink sink})` — `internalFamily = fontPrefix + family` em minúsculas.
  - Códigos (`location` `'<path>:<linha>'`): `css.unsupportedProperty` (info), `css.invalidValue` (info), `css.unsupportedAtRule` (info), `css.fontFaceInvalid` (warning); emissão de `css.unsupportedSelector`.
- Regras (spec §8.9):
  - `@media`: `all`, `screen` verdadeiros; `print`, `speech`, `aural`, `tv`, `handheld`, `projection`, `braille`, `embossed`, `tty`, `amazon-kf8`, `amzn-mobi`, `amzn-kf8` falsos; `not`, `only`, `and`, `,`; `width`/`height` com `min-`/`max-` e sintaxe de intervalo; `orientation` (`portrait` se altura ≥ largura); `aspect-ratio` (`a/b`); `prefers-color-scheme` (sem valor = verdadeiro); `em` = 16 px; recurso desconhecido ou consulta malformada → falsa.
  - `@supports` (avaliado na montagem): `(prop: valor)` verdadeiro sse `parseProperty` → `ParsedLonghands`; `not`/`and`/`or`/parênteses; `selector(...)` verdadeiro se o seletor for válido.
  - `@import` e `@namespace` só antes da primeira regra que não seja `@charset`/`@import`/`@namespace`; depois → `css.parseError`.
  - `@page` sem seletor: margens (`margin` e os quatro lados), demais descritores ignorados; com seletor (`:first`, `:left`, nome) → ignorado com `css.unsupportedAtRule`.
  - `@font-face`: `font-family` e `src` obrigatórios; `src` com `url() format()` e `local()` (url pela folha; externas descartadas); `font-weight` palavra-chave/número/intervalo; `font-style`; `font-stretch`; `unicode-range` lido do texto cru (`U+X`, `U+X-Y`, curingas `?`); sem família ou sem fonte usável → `css.fontFaceInvalid`, regra descartada.
  - Demais at-rules (`@keyframes`, `@layer`, `@container`, `@counter-style`, `@-webkit-*`…) → `css.unsupportedAtRule`.

- [ ] **Step 1: Testes que falham**
  - Ambiente 600×800 claro — verdadeiras: `screen`, `all`, `only screen and (min-width: 500px)`, `screen, print`, `(400px <= width <= 700px)`, `(orientation: portrait)`, `(prefers-color-scheme)`, `(min-width: 30em)`; falsas: `print`, `amzn-kf8`, `not screen`, `(max-width: 599px)`, `(min-aspect-ratio: 1/1)`, `(foo: 1)`, `(prefers-color-scheme: dark)` (verdadeira no ambiente escuro). Revisão 2: `@MEDIA SCREEN { p{} }` é aceita.
  - `@media print { p {color:red} } p{margin:0}` → 2 regras, a primeira com condição falsa no ambiente acima.
  - `@supports (display:flex) { p{} }` → incluída; `@supports (filter: invert(1)) { p{} }` → excluída; `@supports not (filter: x) { p{} }` → incluída.
  - `@namespace svg url(http://www.w3.org/2000/svg); svg|rect{}` → 1 regra; `p{} @namespace x url(y);` → `css.parseError`.
  - `@page { margin: 1em 2em }` → `top: em 1`, `right: em 2`; `@page :first {margin:0}` → ignorada com `css.unsupportedAtRule`.
  - `@font-face { font-family: "Body"; src: url(../fonts/b.otf) format("opentype"), local(Georgia); font-weight: bold; unicode-range: U+0000-00FF, U+4?? }` em `OEBPS/css/s.css` com `fontPrefix: 'gf1-'` → família `Body`, `internalFamily` `'gf1-body'`, fontes `[FontUrlSource('OEBPS/fonts/b.otf', 'opentype'), FontLocalSource('Georgia')]`, peso 700–700, faixas `[(0, 0xFF), (0x400, 0x4FF)]`. `@font-face { src: url(a.otf) }` e `@font-face { font-family: X; src: url(http://x/a.otf) }` → `css.fontFaceInvalid`.
  - `@keyframes k { from {} }` → `css.unsupportedAtRule`, nenhuma regra.
  - `p{speak:none; filter:x; color:12px; color:red}` → 1 declaração (vermelho), 1 `css.unsupportedProperty`, 1 `css.invalidValue`. `p, q:desconhecida {color:red}` → 0 regras e `css.unsupportedSelector`.
  - `order` cresce na ordem do texto; um erro na linha 4 tem `location` `'OEBPS/css/s.css:4'`.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar. **Step 4:** PASS.
- [ ] **Step 5: Commit** `feat(style): at-rules, media queries e montagem das folhas`

---

### Task 6: Contexto do livro — cache de folhas, `@import` e fontes

**Files:**
- Create: `lib/src/features/style/data/book_style_context.dart`
- Modify: `lib/src/core/diagnostics/diagnostic_codes.dart`
- Test: `test/features/style/data/book_style_context_test.dart`

**Interfaces:**
- Consumes: `decodeCss` (Task 1), `buildStyleSheet` (Task 5), `DocumentHead`/`LinkedStyleSheet`/`InlineStyleSheet` (SP3), `resolveHref` (SP1).
- Produces:
  - `typedef ResourceResolver = Uint8List? Function(String path);`
  - `final class SheetEntry { final StyleSheet sheet; final List<MediaQueryList> conditions; }`
  - `final class BookStyleContext { BookStyleContext({required ResourceResolver resolve, required String bookKey}); List<SheetEntry> sheetsFor(DocumentHead head, {required String documentPath, required DiagnosticSink sink}); String get fontPrefix; String internalFamilyName(String family); List<FontFaceRule> get fontFaces; @visibleForTesting int get cachedSheetCount; }`
    - `sheetsFor`: folhas na ordem da cascata, cada `@import` expandido **antes** das regras de quem importa; `conditions` junta o `media` do `<link>`/`<style>` com os dos `@import`.
    - `fontPrefix` = `'gf'` + FNV-1a de 32 bits de `bookKey` em 8 dígitos hexadecimais + `'-'`.
  - Códigos (warning): `css.importCycle`, `css.importLimit`, `css.missingStyleSheet`.
- Regras: cache das ligadas por caminho (ausência também fica no cache); dos `<style>` pela chave (diretório do documento, texto exato), porque `url()` é relativo ao documento; os diagnósticos de uma folha saem **uma vez por livro**, na primeira leitura, para o `sink` dessa chamada (é assim que se cumpre o "agregado por livro" da §8.2). `@import` relativo à folha; ciclo (caminho já na pilha) → `css.importCycle`, pulado; profundidade > **8** ou mais de **64** importações por folha raiz → `css.importLimit`, pulado.

- [ ] **Step 1: Testes que falham** (resolvedor de mapa que conta chamadas)
  - Dois documentos ligando `OEBPS/css/s.css` → o resolvedor é chamado uma vez para ele; só a primeira chamada emite os diagnósticos da folha.
  - `a.css` importa `b.css`, que importa `a.css` → 1 `css.importCycle`, regras de `b` antes das de `a`. Cadeia `a0 → … → a10` → `a0`–`a8` lidas, `a9` → `css.importLimit`.
  - `@import url(x.css) print;` e `<link media="print">` → entradas com condição falsa em 600×800.
  - Folha ausente → `css.missingStyleSheet` uma vez para dois documentos.
  - O mesmo `<style>` em dois documentos do mesmo diretório soma 1 a `cachedSheetCount`; em diretórios diferentes, 2.
  - `bookKey` `'a'` e `'b'` → `internalFamilyName('Body')` diferentes; no mesmo contexto `'Body'` e `'body'` → o mesmo nome. Folha UTF-16 com BOM é lida.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar. **Step 4:** PASS.
- [ ] **Step 5: Commit** `feat(style): contexto por livro com cache de folhas e @import`

---

### Task 7: Índice de regras, filtro de ancestrais e cascata → `MatchedDocument`

**Files:**
- Create: `lib/src/features/style/domain/rule_index.dart`, `lib/src/features/style/domain/cascade.dart`, `lib/src/features/style/domain/matched_document.dart`, `lib/src/features/style/data/default_stylesheet.dart`, `lib/src/features/style/data/style_document.dart`
- Modify: `lib/src/features/style/domain/selector_matcher.dart` (filtro de ancestrais)
- Test: `test/features/style/domain/cascade_test.dart`, `test/features/style/domain/rule_index_test.dart`

**Interfaces:**
- Consumes: Tasks 4–6; `ParsedDocument` (SP3).
- Produces:
  - `final class CascadedValues { final Int32List properties; final List<CssValue> values; CssValue? valueOf(int property); bool declares(int property); }` (vencedor por propriedade declarada, `properties` ordenado).
  - `final class MatchedDocument { final DocumentTree tree; final List<CascadedValues> sets; final Int32List elementSets; final Int32List pseudoElements; final Uint8List pseudoKinds; final Int32List pseudoSets; final List<FontFaceRule> fontFaces; final PageMargins? pageMargins; bool isValidFor(StyleEnvironment env); int get retainedBytes; }` — `elementSets`: índice em `sets` por nó, −1 para não-elemento; pseudo em arranjos paralelos ordenados por elemento; `pageMargins`: por lado, o último `@page` com condições verdadeiras; `isValidFor` reavalia as `MediaQueryList` registradas no casamento e devolve `true` se todas dão o mesmo resultado.
  - `const String kDefaultStyleSheetCss = ''` e `StyleSheet get defaultStyleSheet` (lida uma vez, `final` de topo). **Vazia nesta task; a Task 9 preenche.**
  - `MatchedDocument matchDocument(BookStyleContext context, ParsedDocument document, StyleEnvironment environment, {DiagnosticSink? sink, @visibleForTesting StyleSheet? userAgentSheet})`
  - `SelectorMatcher`: `@visibleForTesting int get fullMatchAttempts`.
- Regras (spec §8.3, §8.5, §8.6):
  - **Índice:** cada `StyleRule` com condições verdadeiras entra num balde pelo composto mais à direita (id → classe → tipo em minúsculas → universal). Por documento, as chaves viram ids da `TokenTable`/`NameTable` da árvore uma vez, e regras com chave ausente no documento são descartadas de cara. Por elemento, os candidatos vêm de `idOf`, `classesOf` e `nameOf`, mais o balde universal.
  - **Filtro de ancestrais:** Bloom com contadores sobre os hashes de id, classes e nome dos ancestrais, empilhado/desempilhado num percurso em ordem de documento **sem recursão**; seletor com `ancestorHashes` ausente do filtro é rejeitado sem percorrer ancestrais (tamanho e nº de hashes a critério do construtor).
  - **Ordem da cascata:** agente normal < editora normal (folhas, depois `style=`) < editora `!important` (folhas, depois `style=`) < agente `!important`; dentro do nível, especificidade e depois ordem (folha, regra).
  - `style=` lido com `parseCssDeclarations` + `parseProperty`, uma vez por texto distinto no documento.
  - **Internamento:** chave do conjunto = lista de identidades das `Declaration` vencedoras; elementos com o mesmo conjunto apontam para o mesmo índice. Pseudo-elementos só entram se alguma regra casar.
  - Diagnósticos do documento (`style=`, `<style>`) passam por `LimitedDiagnosticSink` sobre `sink`, com `flush` no fim.

- [ ] **Step 1: Testes que falham** (agente injetado por `userAgentSheet`)
  - Agente `p{color:blue}` × editora `p{color:red}` → vermelho; agente `p{color:blue !important}` × editora `p{color:red !important}` → azul; folha `p{color:red !important}` × `style="color:green"` → vermelho; `style="color:green !important"` × folha `!important` → verde.
  - `#x{color:red} p{color:blue}` → vermelho; `p{color:red} p{color:blue}` → azul; a segunda folha vence a primeira; regras de um `@import` perdem para as de quem importa; folha com `<link media="print">` não conta; regra com `:hover` não casa.
  - 1.000 `<p class="t">` → o mesmo índice de conjunto; `sets.length <= 5` num documento só com `html`, `body`, `p`. O mesmo `style="x"` em 100 elementos é lido 1 vez (`@visibleForTesting int styleAttributeParses`).
  - 2.000 `<p>` dentro de `<div class="w">`, 1.000 regras `.k$i p{color:red}` + `.w p{color:blue}` → todos azuis, `fullMatchAttempts < 100000`.
  - Revisão 3: 10.000 `<div>` aninhados com um `<p>` no fundo e `div div div p{color:red}` → `p` vermelho, sem estouro, < 2 s.
  - `@media (max-width: 600px){p{color:red}}` casado em largura 500 → `isValidFor` true em 550, false em 700, true em 500 escuro; sem `@media`, sempre true.
  - `p::before{content:"x"}` → entrada `before` para cada `p`; `p::first-letter{}` também gera entrada. `@page{margin:1em}` → `pageMargins.top` `em: 1`.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar. **Step 4:** PASS.
- [ ] **Step 5: Commit** `feat(style): índice de regras, filtro de ancestrais e cascata guardada`

---

### Task 8: Valores calculados, `ComputedStyle` internado e `restyle` sem preferências

**Files:**
- Create: `lib/src/features/style/domain/value_computer.dart`, `lib/src/features/style/domain/computed_style.dart`, `lib/src/features/style/domain/styled_document.dart`, `lib/src/features/style/domain/restyle.dart`, `lib/src/features/style/domain/reader_preferences.dart` (só o modelo; a passada é da Task 10)
- Test: `test/features/style/domain/value_computer_test.dart`, `test/features/style/domain/restyle_test.dart`

**Interfaces:**
- Consumes: `MatchedDocument`, `CascadedValues` (Task 7).
- Produces:
  - `@immutable final class ComputedStyle { CssValue operator [](int property); int get stableHash; }` — igualdade por valor; `stableHash` = FNV-1a 32 bits sobre codificação canônica (tipo, números como bits IEEE de 64 bits, strings por unidade de código), **sem** `Object.hash`/`String.hashCode` (não são estáveis entre isolates e execuções); `hashCode` devolve `stableHash`.
  - `final class StyleInterner { ComputedStyle intern(List<CssValue> values); List<ComputedStyle> get styles; }`
  - `final class StyledDocument { final List<ComputedStyle> styles; final Int32List elementStyles; int? pseudoStyleOf(int element, PseudoElement kind); String? generatedTextOf(int element, PseudoElement kind); final List<FontFaceRule> fontFaces; final ({CssLength top, CssLength right, CssLength bottom, CssLength left})? pageMargins; final int? pageBackground; int get distinctStyleCount; int get retainedBytes; }` — `elementStyles` −1 para não-elemento (texto usa o pai); `generatedTextOf` só `before`/`after`; `pageMargins` com `em` sobre 16 px.
  - Modelo em `reader_preferences.dart`: `enum PreferencePolicy { publisher, adjust, force }` (= editora, ajustar, forçar); `final class Preference<T> { const Preference(this.value, {this.policy = PreferencePolicy.adjust}); final T value; final PreferencePolicy policy; }`; `final class ReaderTheme { const ReaderTheme({required int background, required int text, required int link}); }`; `enum ReaderTextAlign { start, end, left, right, center, justify }`; `final class ReaderPreferences { const ReaderPreferences({Preference<String>? fontFamily, bool preserveHeadingFonts = false, Preference<double>? fontSize, Preference<double>? lineHeight, Preference<double>? paragraphSpacing, Preference<double>? textIndent, Preference<ReaderTextAlign>? textAlign, Preference<bool>? hyphenation, Preference<double>? wordSpacing, Preference<double>? letterSpacing, Preference<ReaderTheme>? theme, Map<String, String> genericFamilies = const {}}); static const ReaderPreferences none = ReaderPreferences(); }`
  - `StyledDocument restyle(MatchedDocument matched, ReaderPreferences preferences)` (preferências ainda sem efeito).
- Regras (spec §8.5):
  - Percurso em ordem de documento (pai antes do filho, sem recursão), com memo `(estilo do pai, conjunto, marcas) → índice do estilo`; isso cobre o atalho de irmãos da §8.6 e mais.
  - `font-size` primeiro: `em`/`%` sobre o pai, `rem` sobre a raiz, raiz sobre 16 px; palavras-chave pelo CSS Fonts sobre 16: `xx-small` 9,6, `x-small` 12, `small` 14,2222, `medium` 16, `large` 19,2, `x-large` 24, `xx-large` 32, `xxx-large` 48; `larger` × 1,2 e `smaller` ÷ 1,2 sobre o pai; Revisão 4: limitado a [0, 10000] px.
  - `ex` = 0,5 em; `%`, `vw`, `vh` simbólicos em `CssLength`; resultado não finito → valor inicial.
  - `line-height`: `normal` fica palavra-chave; número fica `CssNumber` (herdado como fator); comprimento ou `%` → px. `font-weight` `bolder`/`lighter` pela tabela do CSS Fonts 4 sobre o pai.
  - Largura de borda 0 com estilo `none`/`hidden`; cores de borda, `text-decoration-color` e `text-emphasis-color` mantêm `currentcolor` (o layout resolve); `color: currentcolor` herda.
  - `display` blocado com `float` ≠ `none`, `position` `absolute`/`fixed` e na raiz. `inherit`/`initial`/`unset` pela regra de cada propriedade.
  - `::before`/`::after` com o elemento como pai, só se `content` ≠ `none`/`normal`; texto gerado = strings + `attr()` (vazio se faltar) + aspas pela profundidade em ordem de documento; contadores → `''` (SP8); `quotes` inicial `"“" "”" "‘" "’"`.

- [ ] **Step 1: Testes que falham**
  - `body` 20 px: `2em` → 40; `150%` → 30; `larger` → 24; `x-large` → 24; `12pt` → 16; com `html` 10 px, `1rem` → 10.
  - fs 10: `margin-left: 2em` → `CssLength(px: 20)`; `width: 50%` → `percent: 50`; `calc(100% - 2em)` → `(px: -20, percent: 100)`; `height: 10vh` → `vh: 10`.
  - `line-height: 1.5` → `CssNumber(1.5)` também no filho com o dobro do tamanho; `2em` com fs 10 → px 20, herdado como 20.
  - `bolder` sobre 400 → 700; `lighter` sobre 700 → 400. `border-top-width: inherit` herda; `color: initial` → `0xFF000000`; `unset` herda numa herdada e dá o inicial numa não herdada.
  - `border-top-style: solid` sem largura → 3 px; `border-top-width: 5px` com estilo `none` → 0. `span{float:left}` e `span{position:absolute}` → `display: block`.
  - 1.000 `p` iguais → o mesmo `elementStyles`, `distinctStyleCount <= 6`.
  - Duas chamadas de `restyle(m, ReaderPreferences.none)` → estilos iguais por valor e mesmo `stableHash`; `await Isolate.run(() => restyle(m, none).styles.map((s) => s.stableHash).toList())` igual à lista local.
  - Revisão 4: `font-size: 1e30px` → 10000; 40 `div{font-size:1000%}` aninhados → 10000, finito; `font-size: 0` com `line-height: 2em` → 0 e 0, sem NaN; o `stableHash` de um estilo com esses valores é o mesmo dentro e fora de um `Isolate.run`.
  - `p::before{content:"[" attr(id) "]"}` com `id="x"` → `'[x]'`; `q::before{content:open-quote} q::after{content:close-quote}` em `<q>a<q>b</q></q>` → `'“'`, `'‘'`, `'’'`, `'”'`; `content: none` → `pseudoStyleOf == null`; `p::first-letter{font-size:2em}` com fs 16 → 32.
  - `@page{margin:1em}` → `pageMargins.top.px == 16`. Revisão 3: 10.000 `div` aninhados passam pelo `restyle` sem estouro. `retainedBytes > 0` e cresce com o documento.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar. **Step 4:** PASS.
- [ ] **Step 5: Commit** `feat(style): valores calculados, estilos internados e restyle`

---

### Task 9: Folha padrão e marcas de texto corrido

**Files:**
- Modify: `lib/src/features/style/data/default_stylesheet.dart` (conteúdo), `lib/src/features/style/domain/matched_document.dart`, `lib/src/features/style/data/style_document.dart`
- Create: `lib/src/features/style/domain/text_run.dart`
- Test: `test/features/style/data/default_stylesheet_test.dart`, `test/features/style/domain/text_run_test.dart`

**Interfaces:**
- Consumes: Tasks 7–8 (tamanho e família da editora vêm do `value_computer`).
- Produces:
  - `kDefaultStyleSheetCss` baseado na seção "Rendering" do HTML: ocultos (`head`, `script`, `style`, `title`, `meta`, `link`, `template`, `[hidden]`); blocos, listas (`ul ul` `circle`, `ul ul ul` `square`) e tabelas; `ruby`/`rt` (`ruby`, `ruby-text`); margens e tamanhos de `h1`–`h6`; `b`/`strong` `bolder`; `i`/`em`/`cite`/`var`/`dfn` itálico; `pre`/`code`/`kbd`/`samp`/`tt` `monospace`; `sub`/`sup` (`vertical-align`, `smaller`); `u`/`ins` sublinhado; `s`/`del`/`strike` riscado; `small`, `big`, `center`, `th` (negrito, centralizado), `hr`, `mark`, `nobr`, `bdo`, `[dir]`; `:link { color: #0000EE; text-decoration: underline }`; `q::before`/`q::after` com aspas; `svg|svg` e `math` em linha.
  - `abstract final class ElementFlags { static const int textRunRoot = 1, inTextRun = 2, heading = 4, link = 8, monospace = 16; }`
  - Em `MatchedDocument`: `final Uint8List flags`; `final double bodyFontSize`; `final Int32List publisherFamilies` com `final List<CssFontFamilies> familyTable`.
- Regras (spec §8.7):
  - `bodyFontSize` = tamanho da editora (sem preferências) do primeiro `body` XHTML; sem ele, o da raiz (Revisão 5).
  - `textRunRoot` exige: `display` calculado `block`, `list-item` ou `flow-root`; filho de texto com algum caractere que não seja espaço ASCII (espaço, tab, LF, CR, FF; U+00A0 conta como texto); não ser `h1`–`h6`, `td`, `th`, `caption`, `pre`, `figcaption`; sem ancestral `pre` ou `table`; `|tamanho / bodyFontSize − 1| <= 0,15`.
  - `inTextRun`: a raiz e todos os descendentes. `heading`: `h1`–`h6` e descendentes. `link`: `a`/`area` XHTML com `href` e descendentes. `monospace`: a família da editora contém o genérico `monospace` ou (sem caixa) `monospaced`, `courier`, `courier new`, `consolas`, `menlo`, `monaco`, `lucida console`.
  - `publisherFamilies`: a família calculada da editora por elemento (índice em `familyTable`).

- [ ] **Step 1: Testes que falham** (folha padrão real, `restyle(none)`)
  - `html`, `body`, `p` → `block`; `head` → `none`; `li` → `list-item`; `table` → `table`; `td` → `table-cell`; `rt` → `ruby-text`.
  - `body` `margin-top` 8; `p` `margin-top` 16; `h1` 32 px, `margin-top` 21,44, peso 700; `h2` 24; `h3` 18,72; `h4` 16; `h5` 13,28; `h6` 10,72; `blockquote` `margin-left` 40; `ul` `padding-left` 40 e `disc`; `ul ul` `circle`; `ol` `decimal`.
  - `pre` → `white-space: pre`, família `[monospace(generic)]`; `sub` → `vertical-align: sub`, 13,333 px; `a[href]` → cor `0xFF0000EE` e sublinhado; `th` negrito e centralizado; `em` itálico; `strong` 700; `center` centralizado.
  - Corpo 16 px — texto corrido: `<p>texto</p>`; `<p style="font-size:14px">` (−12,5%); `<blockquote><p>x</p></blockquote>` (o `p`); `<div>texto <em>x</em></div>` (o `div` é raiz, o `em` é `inTextRun`). Não é: `<p> </p>`; `<h2>t</h2>`; `<p style="font-size:.8em">` (−20%, epígrafe); `<pre>x</pre>`; `<td><p>x</p></td>`; `<figcaption>`.
  - `body{font-size:120%}` → `bodyFontSize` 19,2. `<a href="#x"><em>y</em></a>` → o `em` tem `link`; `<a name="x">` não. `font-family: "Courier New", serif` e `font-family: monospaced` → `monospace`.
  - Revisão 5: documento `image/svg+xml` (raiz `svg`) não lança, `bodyFontSize` 16, nenhum `textRunRoot`; documento recuperado com `body` virtual classifica normalmente; `body{display:none}` não lança.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar. **Step 4:** PASS.
- [ ] **Step 5: Commit** `feat(style): folha padrão do HTML e marcas de texto corrido`

---

### Task 10: Passada de preferências do leitor

**Files:**
- Create: `lib/src/features/style/domain/preference_pass.dart`
- Modify: `lib/src/features/style/domain/restyle.dart`
- Test: `test/features/style/domain/preference_pass_test.dart`

**Interfaces:**
- Consumes: `ReaderPreferences` (Task 8); `ElementFlags`, `bodyFontSize`, `publisherFamilies` (Task 9).
- Produces: `restyle` aplica as preferências; `StyledDocument.pageBackground` = `theme.background` quando há tema; política `publisher` não age.
- **Regra da fronteira** (decisão que o teste não determina sozinho): por elemento, calcula-se o valor da editora a partir do pai **já ajustado** e depois transforma-se. Uma propriedade herdada só é transformada onde o valor nasce: o elemento a declara (`CascadedValues.declares`) **ou** entra no escopo da preferência (o `inTextRun`/`heading` do pai difere do dele). Nunca se reaplica a um valor só herdado; na saída do escopo o valor herdado segue como está (§8.5).
- **Transformações** (§8.7; `fs` = tamanho calculado do elemento):
  - Tamanho: fator `f` = valor (ajustar) ou valor / `bodyFontSize` (forçar); multiplica o tamanho na raiz e onde ele é declarado com valor absoluto (unidades absolutas, palavras-chave absolutas); relativos (`em`, `%`, `rem`, `larger`, `smaller`) e herdados já acompanham. `line-height` declarado em unidade absoluta também × `f`.
  - Entrelinha: ajustar → na fronteira de texto corrido × `m` (número × `m`, px × `m`, `normal` → `CssNumber(1,2·m)`); na fronteira de título × `1 + (m − 1)/2`. Forçar → `CssNumber(valor)` em todos.
  - Parágrafos: ajustar → só no `textRunRoot`, `margin-top` 0 e `margin-bottom` `valor × fs`; forçar → o mesmo em todo `block`/`list-item`.
  - Recuo: `text-indent` = `valor × fs`; ajustar só no `textRunRoot`, forçar em todo bloco.
  - Alinhamento: ajustar → na fronteira de texto corrido troca se o valor da editora for `start`, `justify`, `left` (em `ltr`) ou `right` (em `rtl`); `center`, `end` e o lado final ficam. Forçar → em todos.
  - Hifenização: `hyphens` `auto` (true) / `manual` (false); ajustar na fronteira de texto corrido, forçar em todos.
  - Palavras/letras: ajustar → na fronteira de texto corrido, valor da editora (`normal` = 0) + `valor × fs`; forçar → `valor × fs` em todos.
  - Família: ajustar → `[valor]` em todo elemento cuja família da editora (`publisherFamilies`) não seja monoespaçada e que não seja título com `preserveHeadingFonts` (aí volta a da editora); itálico e negrito intactos. Forçar → `[valor]` em todos. Por fim `genericFamilies` troca cada genérico mapeado pelo nome do app.
  - Tema (as duas políticas): `color` = `text` (`link` nos elementos com `ElementFlags.link`); `background-color` transparente, exceto raiz e `body`, que recebem `background`; cores de borda, `text-decoration-color` e `text-emphasis-color` → `currentcolor`; nada mais muda (imagens intactas).

- [ ] **Step 1: Testes que falham.** Folha da editora:
  ```
  body{font-size:16px;line-height:1.5;font-family:Georgia,serif}
  h1{font-size:2em;text-align:center}
  p{margin:0 0 1em;text-indent:1.5em;text-align:justify}
  p.r{text-align:right}  p.ep{font-size:.8em}  pre{font-family:monospace}
  div.box{background-color:white;border:1px solid black}
  p.imp{line-height:1.2 !important}
  ```
  Documento: `h1`; `p` com `<em>`, `<span style="line-height:1.2">` e `<span style="font-size:12px">`; `p.r`; `p.ep`; `pre`; `div.box` com `p`; `p.imp`; `<a href="#x"><em>l</em></a>`; `blockquote` com `p`; `ul` com `li`.
  - `none`, e todas as preferências com `publisher` → igual a `none`.
  - Família ajustar `Literata` → `p` `['Literata']`, `pre` monoespaçado, `em` itálico, `h1` `Literata` (com `preserveHeadingFonts` → `[Georgia, serif]`); forçar → `pre` `Literata`.
  - Revisão 1, tamanho ajustar 1,5 → `body` 24, `h1` 48 (não 72), `span` de 12px → 18, `em` do `p` 24; forçar 20 → fator 1,25: `p` 20, `h1` 40.
  - Revisão 1, entrelinha ajustar 2,0 → `p` 3,0; `span` com `1.2` → 2,4; `em` sem declaração herda 3,0 (não 6,0); `h1` 2,25 (1,5 × 1,5); `p.ep` (fora do texto corrido) 1,5; `p.imp` (`!important`) 2,4. Forçar 1,8 → 1,8 em todos.
  - Parágrafos ajustar 0,5 → `p` `margin-top` 0, `margin-bottom` 8; `h1`, `blockquote`, `li` como a editora. Forçar → `h1` `margin-top` 0, `margin-bottom` 16.
  - Recuo ajustar 2 → `p` 32, `h1` intacto; forçar → `h1` 64.
  - Alinhamento ajustar `start` → `p` `start`, `h1` centralizado, `p.r` à direita; forçar → `h1` `start`.
  - Hifenização ajustar true → `p` `auto`, `h1` `manual`; forçar → `h1` `auto`.
  - Revisão 1, letras ajustar 0,1 → `p` 1,6 px e o `em` dentro herda 1,6 (não 3,2); forçar → 1,6 px em todo elemento de 16 px.
  - Tema (fundo `0xFF000000`, texto `0xFFEEEEEE`, link `0xFF88AAFF`) → `p` cor do texto; `a` e seu `em` cor do link; `div.box` fundo transparente e borda `currentcolor`; `body` fundo `0xFF000000`; `pageBackground` `0xFF000000`.
  - `genericFamilies: {'serif': 'Literata'}` → `body` `[Georgia, Literata]`.
  - Revisão 5: todas as preferências acima num documento SVG e com `body{display:none}` não lançam.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar. **Step 4:** PASS.
- [ ] **Step 5: Commit** `feat(style): passada de preferências do leitor (editora, ajustar, forçar)`

---

### Task 11: Entrada completa, isolate, fuzz e tetos de memória

**Files:**
- Modify: `lib/src/features/style/data/style_document.dart`, `lib/src/features/style/domain/matched_document.dart`, `lib/src/core/diagnostics/diagnostic_codes.dart`
- Test: `test/features/style/style_document_test.dart`, `test/features/style/fuzz_test.dart`, `test/features/style/memory_counter_test.dart`

**Interfaces:**
- Consumes: Tasks 1–10; `EpubBook`, `buildEpub` (test/support).
- Produces:
  - `StyledDocument styleDocument(BookStyleContext context, ParsedDocument document, StyleEnvironment environment, ReaderPreferences preferences, {DiagnosticSink? sink})` = `matchDocument` + `restyle`.
  - `MatchedDocument.internalError` (`String?`), como o `ParsedDocument.internalError` do SP3; `@visibleForTesting MatchedDocument guardMatch(ParsedDocument document, MatchedDocument Function() body)` — exceção inesperada vira casamento só com a folha padrão, `css.internalError` (error) e `internalError` com o tipo da exceção.

- [ ] **Step 1: Testes que falham**
  - EPUB do `buildEpub` com `style.css` compartilhado por 2 capítulos, um `<style>`, `style=` e `@font-face`; resolvedor = mapa pré-lido com `book.resource`. `styleDocument` nos dois capítulos devolve as `fontFaces` com nomes internos; diagnósticos chegam ao `sink`, os da folha compartilhada uma vez só.
  - Para `none` e para um conjunto com todas as preferências: `restyle(matchDocument(...), p)` dá, elemento a elemento, estilos iguais (`==` e `stableHash`) aos de `styleDocument(..., p)`.
  - `await Isolate.run(() { contexto criado dentro; return styleDocument(...); })` → estilos iguais aos locais, e o `StyledDocument` volta sem erro.
  - Fuzz `Random(42)`, 2.000 variações de uma folha realista (truncar, trocar bytes, apagar `;`, `{`, `}`, duplicar trechos, inserir `@media(`, `\`, `"`, `/*`): `buildStyleSheet` nunca lança, < 2 s cada; `styleDocument` com cada folha num documento fixo nunca lança e `internalError == null`.
  - Folha de 1 MiB com regras repetidas lida em < 2 s.
  - `guardMatch` com corpo que lança `StateError` → só a folha padrão, `internalError == 'StateError'`, `css.internalError`.
  - Tetos no XHTML sintético de 1 MiB do teste (mesmo gerador do `memory_counter_test` do SP3) com folha realista: `distinctStyleCount <= kMaxDistinctStyles`, `styled.retainedBytes / bytesDoXhtml <= kMaxStyledRatio`, `matched.retainedBytes / bytesDoXhtml <= kMaxMatchedRatio`; constantes calibradas na primeira medição (medido × 1,25), congeladas com nome e comentário que registra o valor medido.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar e calibrar. **Step 4:** PASS (`flutter test`, suíte toda).
- [ ] **Step 5: Commit** `feat(style): entrada styleDocument, isolate, fuzz e tetos de memória`

---

### Task 12: Benchmark — suítes de estilo e comparação com o `csslib`

**Files:**
- Create: `benchmark/lib/src/suites/style_suites.dart`, `benchmark/lib/src/competitors/css_adapter.dart`
- Modify: `benchmark/lib/src/catalog.dart`; `benchmark/lib/src/suites/document_suites.dart` (exportar a lista dos livros `hm/*` como `kHandmadeSpineBooks`); `benchmark/lib/src/modes/compare.dart`; `benchmark/bin/bench_runner.dart`; `benchmark/pubspec.yaml` (`csslib: ^1.0.0`)
- Test: `benchmark/test/suites_style_test.dart`, `benchmark/test/competitors_css_test.dart`

**Interfaces:**
- Consumes: `styleDocument`, `matchDocument`, `restyle`, `buildStyleSheet`, `BookStyleContext`, `decodeCss`; `buildLargeXhtml`, `buildHandmadeCorpus` (SP2/SP3).
- Produces:
  - Geradores determinísticos: `String buildPublisherCss()` (~40 KiB misturando o estilo do Gutenberg e o dos privados: classes, ids, descendente, filho, adjacente, `@media`, `!important` em `line-height`/`text-align`/`width`, `@font-face`) e `String buildLargeCss(int targetBytes)`.
  - Ids no catálogo (ciclo de 10–50 ms nativos, calibrado): `style/parse-sheet-256kib`; `style/full-large-1mib` (`matchDocument` + `restyle` do XHTML de 1 MiB, contexto aquecido no `setUp`, como num capítulo N); `style/restyle-large-1mib` (alterna Literata/1,2/tema escuro e `none`); `style/match-descendant-heavy` (2.000 regras descendentes no XHTML de 1 MiB); `style/spine-hm-<livro>` (todo o spine de cada livro de `kHandmadeSpineBooks`, repetições calibradas).
  - `abstract interface class CssParser { String get name; int parseAll(List<String> sheets); }` com `GalleyCssParser` (`galley-css`, checksum = total de regras) e `CsslibParser` (`csslib`, `parse` de `package:csslib/parser.dart`, checksum = total de `topLevels`); `Future<List<String>> loadStyleSheets(String path)` (`.epub`: todos os `text/css` do manifest via `decodeCss`; `.css`: o arquivo); `runCssMeasure` no formato de `runDocumentMeasure` (`ns=`, `rss=`, `checksum=`).
  - `bench_runner`: `--css-adapter galley-css|csslib` com `--measure parse`. `compare`: seção informativa, sem gate, sobre `hm/publisher-css`, os livros do corpus público e `synthetic/css-256kib`, ids `compare/galley-css/parse/<livro>` e `compare/csslib/parse/<livro>` (`wall-time-ns`, `peak-rss-bytes`) e tabela no relatório (`razão` = csslib ÷ galley-css).

- [ ] **Step 1: Testes que falham:** ids novos existem e são únicos; duas execuções de cada suíte dão o mesmo checksum, ≠ 0; os dois `CssParser` leem uma folha pequena e um mini-EPUB (`benchmark/test/support/mini_epub.dart`) com checksum > 0.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar e calibrar. Rodar o `compare` local e anexar ao relatório a tabela nosso × `csslib`. Medir `style/full-large-1mib` × `style/restyle-large-1mib` no modo de instruções: a meta da spec é **razão ≥ 5**; abaixo disso o `restyle` está fazendo trabalho de casamento e deve ser corrigido antes do commit.
- [ ] **Step 4:** PASS (`cd benchmark && dart test -x slow`; `flutter test`).
- [ ] **Step 5: Commit** `feat(benchmark): suítes de estilo e comparação com o csslib`

---

### Task 13: `wide` estilizando o spine, documentação e pendências

**Files:**
- Modify: `benchmark/lib/src/modes/wide.dart`; `benchmark/README.md` (checklist de expansão); `README.md` (tabela de estado); `docs/PENDENCIAS.md`
- Test: `benchmark/test/modes/wide_test.dart`

**Interfaces:**
- Consumes: `styleDocument`, `BookStyleContext` (Tasks 6, 11); `readWholeBook` (SP3).
- Produces:
  - `typedef DocumentStyler = StyledDocument Function(BookStyleContext context, ParsedDocument document)`; o padrão chama `styleDocument` com `StyleEnvironment(pageWidth: 600, pageHeight: 800)` e `ReaderPreferences.none`.
  - `readWholeBook(file, {parse, style})`: guarda os bytes de todos os recursos num mapa, cria um `BookStyleContext` por livro (`bookKey` = caminho do arquivo, o mapa como resolvedor) e estiliza cada documento do spine depois de parseá-lo. Exceção que não seja `GalleyException` → `crashed`; `MatchedDocument.internalError` → `WideInternalError` (`crashed`). `WideRead.styledDocuments` e BMF `wide/documents-styled`.
- Documentação:
  - `benchmark/README.md`: SP4 `[x]` no formato do SP3 (ids do catálogo; `compare/galley-css` × `compare/csslib`; tetos de `test/features/style/memory_counter_test.dart`; razão `full`/`restyle` medida; `wide` estilizando o spine).
  - `README.md`: `| 4. Estilo (motor CSS + preferências do leitor) | ✅ concluído |` (entra com o merge, como no SP3).
  - `docs/PENDENCIAS.md`: em "Dependem de upstream", os itens dos PRs renggli/dart-xml#224 e #225 passam a dizer **mergeados upstream, falta só a release**, com a mesma migração `xml` 6.x → 7.x. Nova seção `## SP4 — Estilo` com:
    - **`var()`/propriedades customizadas:** zero livros no levantamento de 2026-11-25 (372 livros); hoje `--*` é descartado com `css.unsupportedProperty`; retomar quando aparecer num livro real.
    - Contadores (`counter()`, `counter-*`) só guardados, geração no SP8; aspas iguais para todos os idiomas; `@page :first/:left/:right` ignorados; aninhamento CSS sem suporte (0% dos livros); `ex`/`ch` aproximados por 0,5 em, sem métricas da fonte.

- [ ] **Step 1: Testes que falham:** `wide` com um estilizador falso que lança `StateError` → `crashed`; com um que devolve `internalError` → `crashed`; o livro `hm/publisher-css` tem `styledDocuments == documents`.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar. Rodar o `wide` local (cache `pg-wide`): queda real é bug, corrigida na task dona (2–11) com teste de regressão. Atualizar a documentação.
- [ ] **Step 4:** PASS (`cd benchmark && dart test -x slow`; `flutter test`; `dart format --set-exit-if-changed .`; `flutter analyze`).
- [ ] **Step 5: Commit** `feat(benchmark): wide estiliza o spine; docs e pendências do SP4`

---

## Notas de execução

- Branch `sp4/estilo` (já criada, com o spec); a `main` exige PR e os checks `instructions` e `ab`.
- Ordem: Tasks 1 → 13 (as Tasks 3 e 4 dependem só de 1–2).
- Os benchmarks novos entram nos gates a partir da Task 12 e aparecem como `added` (a `main` ainda não os tem).
- Ao fechar, conferir o job `size` do noturno (teto de 2 MiB no APK): o SP4 acrescenta a tabela de cores e a folha padrão.
