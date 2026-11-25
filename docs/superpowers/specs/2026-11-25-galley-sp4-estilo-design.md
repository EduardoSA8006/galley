# Galley — Subprojeto 4: Estilo (motor CSS + preferências do leitor)

- **Data:** 2026-11-25
- **Status:** em revisão
- **Documento pai:** `2026-11-24-galley-arquitetura-design.md` (§7 etapa 3, §8 item 4)
- **Depende de:** SP1 (Container), SP2 (Benchmark) e SP3 (Documento), mergeados.
- **Dados:** `dados/2026-11-25-levantamento-css.md` (levantamento de CSS em 372 livros).

## 1. Intenção

Dar a cada elemento da árvore do SP3 um **estilo calculado**: o valor final de cada propriedade CSS que o layout (SP5) precisa, depois de juntar a folha padrão do HTML, o CSS da editora, o atributo `style=` e as **preferências do leitor**. As preferências entram como uma camada explícita da cascata, com política por propriedade, para que o app ofereça fonte, tamanho, tema, espaçamentos e alinhamento sem destruir a estrutura do livro.

A etapa roda em isolate (pai §7) e entrega um resultado compacto, barato de transferir para o isolate raiz onde o layout roda.

## 2. O que a medição mostrou (2026-11-25)

Levantamento em 372 livros: 20 do corpus público, 300 do Gutenberg amplo e 52 privados do mantenedor (só agregados). Contagens em **livros**. Detalhes em `dados/2026-11-25-levantamento-css.md`.

- **Origem do CSS:** folhas ligadas em quase todos; `style=` inline em 92,5% dos livros (100% do Gutenberg, que centraliza com `style="text-align: center"`); blocos `<style>` em 54% dos privados.
- **Seletores:** tipo, classe, id e descendente dominam. Filho `>` 24%, irmão adjacente `+` 19%, universal 3%, irmão geral `~` 0%. Atributo quase só `[href]`. Pseudo-classes: `:hover`/`:link`/`:visited`/`:active` 8–12%, `:first-child` 4%, `:not` 1%; `:nth-child` 0%. Pseudo-elementos: `::first-letter` 8%, `::after` 5%, `::before` 2%.
- **Propriedades:** 120 distintas no total; as 108 mais usadas cobrem 99% dos livros. Prefixos `-epub-`, `-webkit-`, `-moz-` e `adobe-` aparecem entre as 85 mais usadas.
- **At-rules:** `@media` 20% (`all`, `print`, `screen`, `prefers-color-scheme`, `max-width`), `@page` 2%, `@font-face` 1% (mais nos privados), `@namespace` 1%, `@supports` 1%, `@import` 0%.
- **Valores:** `!important` em 51% dos livros não-Gutenberg; `calc()` 1%; `var()` 0%; unidades dominantes `em` e `%`; `rem` e `vw` 0%.
- **Layout:** `display:none` 36%, `inline-block` 19%, `float` 7%, `display:table*` 7%, `position:absolute` 2%, flex 3%, `writing-mode` 1%, grid e colunas 0%.

## 3. Metas

1. **Leitor de CSS próprio** conforme o CSS Syntax Level 3, com a mesma recuperação de erros dos navegadores.
2. **Seletores nível 3 completos**, mais `:not` simples, com casamento rápido.
3. **Cascata completa:** origens, `!important`, especificidade, ordem, `style=`, herança e valores calculados das ~110 propriedades do escopo (§8.4).
4. **Camada de preferências do leitor** com política por propriedade (`editora`, `ajustar`, `forçar`) e o padrão "ajustar" da §8.7.
5. **Fontes:** `@font-face` interpretado; famílias resolvidas por elemento; mapeamento das genéricas configurável pelo app.
6. **Desempenho:** estilos calculados **compartilhados** entre elementos equivalentes, e **casamento guardado** para que trocar uma preferência só recalcule valores, sem casar seletores de novo.
7. **Resultado transferível** entre isolates, compacto.
8. **Benchmark expandido** (pendência permanente do SP2), com o `csslib` como concorrente informativo.

## 4. Não-metas

- **Layout:** float, tabela, posicionamento, flex, `writing-mode` e colunas são implementados pelo SP5/SP8. O SP4 só calcula e entrega os valores dessas propriedades.
- **Registrar fontes no engine** (`loadFontFromList`): exige o isolate raiz e fica para o SP5/SP6. O SP4 só resolve nomes.
- **Estados interativos:** `:hover`, `:active`, `:focus` e `:visited` nunca casam num leitor.
- **`var()`/propriedades customizadas:** zero livros hoje. Fica em `docs/PENDENCIAS.md`.
- **CSS além do nível de livro:** animações, transições, transformações 3D, `@keyframes`, `@container`, `@layer`. Lidos e ignorados com diagnóstico.
- **API pública final das preferências:** o modelo é decidido aqui, mas a forma exportada em `lib/galley.dart` fica para o SP6 (mesma regra do SP3). *(Chamada minha.)*

## 5. Anti-metas

- Trocar uma preferência e ter de casar todos os seletores de novo.
- Uma preferência do leitor que destrua a estrutura do livro: títulos do tamanho do texto, poemas justificados, epígrafes reformatadas (§8.7).
- Recusar um livro ou um capítulo por CSS inválido: o CSS quebrado é recuperado como nos navegadores, com diagnóstico.
- Um objeto de estilo por elemento quando há milhares de parágrafos iguais.
- Embutir fontes no pacote (estouraria o teto de 2 MB e imporia escolhas do app).

## 6. Restrições

- Herdadas: Dart puro; dependências de runtime continuam **só `xml` e `meta`** (o `csslib` entra apenas no pacote `benchmark/` como concorrente); só `GalleyException` escapa; recuperáveis viram `Diagnostic`; docs e commits em pt-BR; arquitetura feature-first (`lib/src/features/style/`, camadas `data`/`domain`).
- Roda em isolate: nada de `dart:ui` nem Flutter na etapa.
- Gates do SP2 valem desde o primeiro PR (instruções 0,5% e A/B); as suítes novas entram no catálogo.
- Entrada é a saída do SP3 (`ParsedDocument`: `DocumentTree` + `DocumentHead` com `LinkedStyleSheet`/`InlineStyleSheet`) e os recursos do `EpubBook` (SP1).

## 7. Abordagens

| Abordagem | Trade-off | Decisão |
|---|---|---|
| A) `csslib` para ler o CSS; cascata própria | economiza o tokenizador e o parser; árvore pesada pensada para pré-processamento (Sass); recuperação de erros diferente dos navegadores; dependência nova no caminho quente | descartada |
| **B) Leitor próprio (CSS Syntax Level 3) e cascata própria, formato compacto** | fidelidade na recuperação de erros; propriedades como ids e valores pré-interpretados; mais código, mas a especificação de sintaxe é pequena e bem definida | **escolhida pelo usuário** |

Valem para B, também por decisão do usuário: **estilos compartilhados** e **casamento guardado** (§8.6).

## 8. Desenho

### 8.1 Pipeline da etapa

```
ParsedDocument (SP3) + folhas do livro (EpubBook) + Ambiente + Preferências
  └─► 1. Folhas   ler CSS (ligadas, <style>, @import), cache por livro
        └─► 2. Regras   índice de regras por id / classe / nome / universal
              └─► 3. Casamento   regras casadas por elemento (e pseudo-elemento) — guardado
                    └─► 4. Valores   cascata + preferências + herança → estilos calculados
                          └─► StyledDocument (transferível)
```

- **Folhas por livro:** cada folha ligada é lida e interpretada uma vez por livro e reaproveitada entre capítulos (o mesmo `style.css` costuma servir todos). O cache é por caminho, dentro do isolate que trabalha o livro.
- **Ambiente** (`StyleEnvironment`): dados para `@media`: tipo de mídia (`screen`), largura e altura da página em px lógicos, esquema de cor (claro/escuro, vindo do tema). O tamanho `medium` é fixo em 16 px lógicos; o tamanho escolhido pelo leitor é preferência (§8.7), não ambiente.
- **Troca de preferência:** reexecuta só o passo 4 sobre o casamento guardado. Troca de ambiente que mude o resultado de algum `@media` refaz do passo 3 em diante (raro: rotação da tela). Troca de largura sem efeito em `@media` não recalcula nada no SP4 (`%` e `vw` ficam simbólicos, §8.5).

### 8.2 Leitor de CSS

- **Tokenizador e parser** pelo CSS Syntax Level 3: tokens, blocos, regras, declarações e recuperação de erros conforme a especificação (declaração inválida descartada até o próximo `;`, regra inválida até o fim do bloco etc.).
- **Codificação:** BOM, depois `@charset`, depois UTF-8 (o `@charset` está em 86% dos livros, quase sempre `utf-8`). Bytes inválidos viram U+FFFD.
- **`@import`:** resolvido relativo à folha, com proteção contra ciclos e limite de profundidade e de quantidade (diagnóstico ao atingir). Media queries do `@import` respeitadas.
- **Propriedades** viram ids inteiros numa tabela fixa; os valores são **pré-interpretados** na leitura (palavras-chave como ids, números, dimensões com unidade, cores, listas de famílias, `calc()` como expressão), não guardados como texto.
- **Aliases de prefixo:** `-epub-hyphens`, `-webkit-hyphens`, `-moz-hyphens`, `adobe-hyphenate` → `hyphens`; `-epub-writing-mode`/`-webkit-writing-mode` → `writing-mode`; `-epub-text-combine` → `text-combine-upright`; demais prefixos do levantamento mapeados quando houver equivalente padrão. A versão padrão declarada vence o alias pela ordem normal da cascata.
- **Desconhecidos:** propriedade fora do escopo ou valor inválido → declaração ignorada com diagnóstico (`css.unsupportedProperty`, `css.invalidValue`), agregado por livro para não inundar o coletor (mesmo limite por código do SP3).
- **`style=`** lido como lista de declarações com o mesmo leitor.

### 8.3 Seletores e casamento

- **Suporte:** seletores CSS nível 3 completos (tipo, universal, classe, id, atributo com todos os operadores e `i`, combinadores descendente, `>`, `+`, `~`), pseudo-classes estruturais (`:root`, `:first-child`, `:last-child`, `:only-child`, `:nth-*`, `:*-of-type`, `:empty`), `:lang()`, `:not()` (nível 3: argumento simples), `:link` (casa `a[href]`) e pseudo-elementos `::before`, `::after`, `::first-letter`, `::first-line` (e a sintaxe antiga com `:`). Estados interativos (`:hover`, `:active`, `:focus`, `:visited`) nunca casam.
- **Namespaces:** `@namespace` e `ns|tipo` respeitados; elementos XHTML casam seletores de tipo sem namespace como nos navegadores; nomes de tipo em HTML sem diferença de caixa.
- **Índice de regras:** cada regra entra num balde pela parte mais à direita do seletor (id → classe → nome → universal), como nos navegadores, usando os índices do SP3 (`elementById`, `elementsWithClass`, `elementsNamed`) quando compensar.
- **Casamento** da direita para a esquerda, com um filtro de ancestrais (ex.: Bloom) para descartar seletores descendentes cedo. Resultado por elemento: lista ordenada de declarações casadas (origem, importância, especificidade, ordem).

### 8.4 Escopo de propriedades

As ~110 propriedades que cobrem 99% dos livros do levantamento, agrupadas: fonte (`font-*`, `font` abreviada), texto (`text-align`, `text-indent`, `text-transform`, `text-decoration*`, `letter-spacing`, `word-spacing`, `white-space`, `hyphens`, `line-height`, `vertical-align`, `direction`, `unicode-bidi`, `writing-mode`, `text-combine-upright`, `hanging-punctuation`), caixa (`display`, `margin*`, `padding*`, `border*` incl. `border-radius`, `width`/`height`/`min-*`/`max-*`, `box-sizing`), fluxo (`float`, `clear`, `position`, `top`/`right`/`bottom`/`left`, `z-index`, `overflow`), cor e fundo (`color`, `background*`, `opacity`), listas (`list-style*`), tabela (`border-collapse`, `border-spacing`, `caption-side`, `table-layout`, `empty-cells`), fragmentação (`page-break-*`, `break-*`, `orphans`, `widows`), conteúdo gerado (`content`, `quotes`, `counter-*`), `visibility`, abreviadas expandidas na leitura. A lista exata sai do levantamento (top-108) no plano.

### 8.5 Cascata e valores calculados

- **Origens, em ordem crescente:** folha padrão (§8.9) → editora normal (folhas, `<style>`, `style=`) → editora `!important` → folha padrão `!important`. Dentro da mesma origem: especificidade, depois ordem; `style=` acima das folhas.
- **Preferências não são origem da cascata.** Depois da cascata e da herança, uma passada de preferências transforma os valores calculados: "ajustar" opera sobre o valor da editora (multiplica, substitui no texto corrido), "forçar" substitui. Por isso a preferência vale **mesmo quando a editora usa `!important`** (63% dos livros privados usam `!important` em `line-height`, `text-align` ou `width`; uma entrelinha escolhida pelo leitor que não pegasse nesses livros violaria o pedido do usuário). As transformações respeitam a herança: um valor ajustado no bloco é o que os descendentes herdam.
- **Herança** pelas regras de cada propriedade; `inherit`, `initial` e `unset` suportados.
- **Valores calculados:** `em`, `ex` e `rem` resolvidos para px lógicos; `pt`/`pc`/`in`/`cm`/`mm` convertidos; `font-size` sempre absoluto (palavras-chave `small`, `larger` etc. pela tabela da especificação). **`%` e `vw`/`vh` em comprimentos de caixa ficam simbólicos** (o layout resolve com a largura real); `calc()` com termos simbólicos também fica como expressão normalizada. `line-height` sem unidade fica como fator.
- **Pseudo-elementos:** `::before`/`::after` com `content` de texto e aspas (`open-quote`/`close-quote`; contadores ficam para o SP8) geram estilo próprio; `::first-letter`/`::first-line` entregam o estilo que o layout aplica ao trecho.

### 8.6 Estilos compartilhados e casamento guardado

- **Estilo calculado** (`ComputedStyle`) é imutável e **internado**: dois elementos com o mesmo resultado apontam para o mesmo objeto. Atalho como nos navegadores: irmão com o mesmo elemento-pai, mesmo nome, mesmas classes, mesmo `style=` (vazio) e mesmas regras casadas reaproveita o estilo do anterior sem recalcular.
- **Resultado** (`StyledDocument`): uma tabela de estilos distintos e um arranjo `Int32List` com o índice do estilo de cada elemento (mais o dos pseudo-elementos presentes). Transferível entre isolates sem cópia profunda de objetos por elemento.
- **Identidade:** índices valem dentro de um `StyledDocument`. Estilos têm igualdade por valor e um hash estável (igual entre isolates e entre execuções); o cache de medição do SP5 usa o valor/hash do estilo, não o índice, então um `restyle` não exige índices estáveis.
- **Casamento guardado** (`MatchedDocument`): o resultado da cascata da editora por elemento (antes da passada de preferências) e a marca de texto corrido. `restyle(matched, preferences)` refaz só a passada de preferências e o internamento. Quem guarda e por quanto tempo (capítulo atual, vizinhos) é decisão do orquestrador do SP6; o SP4 só garante que o objeto é autocontido e informa seus bytes retidos. Meta: restyle de um capítulo ao menos 5× mais rápido que o estilo completo (medido no benchmark).

### 8.7 Preferências do leitor

Cada preferência é opcional (nula = vale a editora) e tem uma política (`editora`, `ajustar` padrão, `forçar`) escolhida pelo app. Sem preferência alguma, o resultado é idêntico ao do livro.

| Preferência | "Ajustar" (padrão) | "Forçar" |
|---|---|---|
| Família da fonte | substitui a família em todo o texto; preserva monoespaçada; itálico e negrito continuam (são estilo, não família). Opção "preservar fonte dos títulos", desligada por padrão | substitui em tudo, inclusive monoespaçada |
| Tamanho da fonte | fator (1,0 = editora): todos os tamanhos calculados multiplicados por ele, mantendo a hierarquia | tamanho-alvo em px para o texto corrido; o fator `alvo / tamanho do corpo da editora` é aplicado a todo o documento, então títulos mantêm a proporção |
| Espaçamento entre linhas | multiplicador no texto corrido; títulos recebem metade do acréscimo (`1 + (m − 1)/2`) | o valor em tudo |
| Espaçamento entre parágrafos | no texto corrido, `margin-top` vira 0 e `margin-bottom` vira o valor escolhido (em `em`), de modo que o colapso de margens do layout produza exatamente esse espaço entre parágrafos consecutivos; títulos, citações, listas e figuras mantêm as da editora | em todos os blocos |
| Recuo da primeira linha | `text-indent` do texto corrido; controle separado, o app decide se liga ao espaçamento entre parágrafos | em todos os blocos |
| Alinhamento | só texto corrido cujo alinhamento da editora seja início/fim/justificado; centralizados e à direita ficam | em tudo |
| Hifenização | liga/desliga `hyphens` no texto corrido | em tudo |
| Espaço entre palavras e letras | acréscimo relativo no texto corrido | em tudo |
| Margens da página | não é estilo de elemento: o SP4 entrega as margens do `@page` da editora e o SP5/SP6 combina com a preferência (fator sobre a margem da editora) | o valor |
| Tema (fundo, texto, links) | fundo da página e cor do texto forçados; links com cor própria do tema; fundos de elemento ficam transparentes e bordas herdam a cor do texto; imagens intactas | igual (o tema já é forte por natureza) |

- **Texto corrido** (classificação, *chamada minha*): elemento de bloco com texto direto (não só espaço), que não seja título (`h1`–`h6`), célula ou legenda de tabela, `pre`, `figcaption`, nem esteja dentro de `pre`/tabela, e cujo tamanho de fonte da editora fique a até ±15% do tamanho do corpo (`body`). Epígrafes e créditos menores e centralizados ficam de fora. Calculado uma vez no casamento e guardado. **Vale para os descendentes em linha** (`em`, `span`, `a`, `sup`…): a marca é herdada, e as transformações de texto corrido também se aplicam a eles; por exemplo, a entrelinha multiplicada também vale para um `span` com `line-height` próprio dentro do parágrafo.
- **Fontes do app:** o app passa nomes de família já registrados no Flutter. Mapeamento das genéricas (`serif`, `sans-serif`, `monospace`, `cursive`, `fantasy`, `system-ui`) configurável; sem mapeamento, caem nas do sistema.

### 8.8 Fontes do livro

- `@font-face` interpretado: família, `src` (`url()` relativo à folha, `local()`, formatos), `font-weight`, `font-style`, `font-stretch`, `unicode-range`.
- Cada família do livro recebe um **nome interno por livro** (ex.: prefixo derivado do identificador do livro) para que dois livros com a família "Body" não se misturem no engine. O estilo calculado guarda a lista de famílias já traduzida; a tabela `@font-face` do livro (nome interno → recurso, peso, estilo, faixas) segue no `StyledDocument` para o SP5/SP6 registrar sob demanda.
- Fontes ofuscadas já são tratadas pelo SP1; o SP4 só referencia o caminho do recurso.

### 8.9 Folha padrão, `@media`, `@page`, `@supports`

- **Folha padrão própria**, baseada na seção "Rendering" da especificação HTML (margens de `p`, tamanhos de `h1`–`h6`, listas, `blockquote`, tabelas, `ruby`, elementos ocultos), mais o mínimo para SVG/MathML embutidos. Imutável e lida uma vez.
- **`@media`**: avaliado contra o ambiente: `all`/`screen` verdadeiros, `print` falso; `amazon-kf8`/`amzn-mobi`/`amzn-kf8` falsos; `prefers-color-scheme` pelo tema; `width`/`height`/`orientation`/`aspect-ratio` pela página; `min-`/`max-` e a sintaxe de intervalo.
- **`@page`**: só as margens (entregues ao layout).
- **`@supports`**: responde verdadeiro para propriedade/valor que o motor suporta.
- **`@namespace`**: suportado; demais at-rules ignoradas com diagnóstico.

### 8.10 Onde a etapa se encaixa

- **Feature nova:** `lib/src/features/style/` (`data`: tokenizador, parser, folhas; `domain`: seletores, cascata, `ComputedStyle`, `StyledDocument`, preferências, ambiente).
- **Entradas internas** *(nomes finais no plano)*, no mesmo espírito do SP3 (funções puras, isolate-safe, orquestração no SP6):
  - `BookStyleContext`: contexto por livro com o cache de folhas já lidas e as `@font-face`; recebe um **resolvedor de recursos** (`Uint8List? Function(String path)`) em vez do `EpubBook`, para não depender de I/O assíncrono dentro da etapa. O SP6 cria um por livro, no isolate que trabalha o livro.
  - `MatchedDocument matchDocument(BookStyleContext ctx, ParsedDocument doc, StyleEnvironment env, {DiagnosticSink? sink})`.
  - `StyledDocument restyle(MatchedDocument matched, ReaderPreferences prefs)` — também usado para o primeiro estilo.
  - Atalho de conveniência `styleDocument(...)` = `matchDocument` + `restyle`.
- **Diagnósticos novos** `css.*` (lista final no plano): `css.parseError`, `css.unsupportedProperty`, `css.invalidValue`, `css.unsupportedAtRule`, `css.importCycle`, `css.importLimit`, `css.missingStyleSheet`, `css.fontFaceInvalid`.

### 8.11 Benchmark (expansão obrigatória)

- **Suítes micro** no catálogo (passam a valer nos gates): ler uma folha grande sintética; estilo completo de um capítulo grande (≈1 MiB) com CSS de editora realista; `restyle` do mesmo capítulo após trocar fonte/tamanho/tema; casamento com muitos seletores descendentes.
- **Suítes macro:** estilo de todos os documentos do spine de cada livro `hm/*`.
- **Comparação informativa** (modo `compare`): nosso leitor de CSS contra o `csslib` nas folhas do corpus (tempo e memória).
- **Robustez:** o modo `wide` passa a estilizar todos os documentos do spine; exceção que não seja `GalleyException` reprova.
- **Contadores determinísticos:** estilos distintos por capítulo (prova do compartilhamento) e bytes retidos do `StyledDocument` por KB de XHTML abaixo de tetos calibrados na primeira medição.

### 8.12 Testes

- Tokenizador e parser contra os casos da especificação de sintaxe (incluindo recuperação de erros).
- Especificidade, ordem, origens e `!important`, com casos de cada linha da tabela da §8.5.
- Casamento de cada tipo de seletor e combinador; namespaces; caixa de nomes.
- Valores calculados por propriedade do escopo (herança, palavras-chave, unidades, simbólicos).
- Preferências: um teste por linha da tabela da §8.7, nas três políticas, incluindo os casos que **não** devem mudar (título centralizado, poema, epígrafe, monoespaçada, imagem).
- Igualdade: sem preferências, resultado idêntico ao da editora; `restyle` com as mesmas preferências produz o mesmo `StyledDocument` que o estilo completo.
- Fuzz do leitor de CSS: nunca lança, tempo linear no tamanho da entrada (mesmo estilo dos testes de linearidade do SP3).

## 9. Decisões do usuário (registradas)

- Política de preferências: o livro fica como a editora fez e cada preferência só age quando definida; padrão "ajustar" conforme a tabela da §8.7; políticas `editora`/`ajustar`/`forçar` por propriedade, escolhidas pelo app.
- Fontes: o pacote não embute fontes; o app entrega as do leitor (nomes de família registrados no Flutter); as do livro o motor carrega; genéricas mapeáveis pelo app; registro no engine fica para o SP5/SP6.
- Escopo de CSS: seletores nível 3 completos; ~110 propriedades (99% dos livros); `@media`, `@font-face`, `@page` (margens), `@namespace`, `@supports` e `@import`; `calc()` básico; `!important`; `var()` fora; folha padrão própria baseada no HTML.
- Abordagem B (leitor de CSS e cascata próprios), com estilos compartilhados e casamento guardado.
- Preferências de espaçamento entre linhas e entre parágrafos são essenciais; aceitas também recuo, hifenização, espaço entre palavras/letras e margens.

## 10. Chamadas minhas (para revisão)

- Critério de "texto corrido" da §8.7 (±15% do tamanho do corpo, exclusões listadas).
- Títulos recebem metade do acréscimo de entrelinha.
- Preferências como passada sobre os valores calculados (não origem da cascata), valendo mesmo contra `!important` da editora.
- Tamanho da fonte como fator ("ajustar") ou tamanho-alvo do texto corrido ("forçar"); `medium` fixo em 16 px lógicos.
- Espaçamento entre parágrafos aplicado como `margin-top: 0` + `margin-bottom: valor` no texto corrido; margens da página combinadas no SP5/SP6.
- Entradas puras com resolvedor de recursos e contexto por livro; retenção do `MatchedDocument` decidida pelo SP6.
- Estilos com igualdade por valor e hash estável; índices só dentro do documento.
- No tema, fundos de elemento ficam transparentes e bordas herdam a cor do texto.
- `%`, `vw`/`vh` e `calc()` com termos dependentes da largura ficam simbólicos até o layout.
- Meta de `restyle` ≥ 5× mais rápido que o estilo completo.
- Forma exportada das preferências fica para o SP6; no SP4 tudo é interno.
- `@page` só margens; `::before`/`::after` com texto e aspas (contadores no SP8).

## 11. O que fica para o construtor

Representação exata de `ComputedStyle` e dos valores; algoritmo de filtro de ancestrais; formato do índice de regras; lista exata das ~110 propriedades (a partir do top-108 do levantamento, mais as que a folha padrão exige); conteúdo da folha padrão; nomes finais das entradas e dos diagnósticos; limites de `@import`; tetos de memória e metas de tempo dos benchmarks, calibrados na primeira medição.
