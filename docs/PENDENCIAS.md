# Pendências

Itens que ficaram de fora de propósito: não valiam o custo no momento, dependem de
outro subprojeto ou esperam algo externo. Cada um diz de onde veio e quando
retomar. Ao resolver um item, apague-o deste arquivo no mesmo commit.

## Dependem de upstream

- **Migrar `xml` 6.6.1 → 7.x** quando o upstream lançar uma versão com os PRs
  já mergeados (2026-11-25): renggli/dart-xml#222 (decodificação linear de
  entidades, issue #221), #224 (parser de nomes, +10–30 % nos eventos) e #225
  (normalização de espaço em atributos, §3.3.3). Falta só a release. Ao migrar:
  remover `LinearHtml5EntityMapping`
  (`lib/src/features/document/data/event_adapter.dart`, manter os testes de
  equivalência e de tempo), a normalização de CRLF do mesmo arquivo
  (dart-xml#220) e a nossa normalização de espaço em atributos (`&#10;`/`&#9;`
  viram espaço hoje; ajustar o `docdiff` na mesma migração), e ganhar o parser
  de nomes.
- **Velocidade do `package:xml`:** o perfil (2026-11-25) mostra ~25 % do tempo
  em `substring`. Patches upstream (parser de nome com tabela ASCII, cache de
  nomes, bitmap no petitparser) dão +10–39 %, com teto ~1,5×. Um tokenizador
  próprio que guarde posições em vez de strings curtas chegaria a 5–10× o
  `parseEvents`. Retomar se a leitura do documento virar gargalo medido.
- **Layout fora do isolate raiz:** quando flutter/flutter#30604 for resolvida
  (o teste-canário em `example/integration_test` avisa), reescrever a etapa de
  layout para rodar em isolate (hoje: plano B, layout fatiado no raiz).

## Benchmark

- **Expandir o benchmark a cada subprojeto** (pendência permanente): estilo,
  layout, render e recursos de leitura devem acrescentar suas métricas e
  comparações (leitores com renderização a partir do SP6).
- **Abertura de livros pequenos:** concorrentes ~0,8 ms, Galley ~1,3 ms.
  Otimizar antes da 1.0.
- **wide-refresh via rsync** em vez de baixar o corpus amplo de novo.
- **Chave de cache com `run_attempt`** nos workflows.
- **Cache duplicado** entre os jobs `compare` e `docdiff` do noturno (só custo
  de cache; as chaves já não colidem).
- **Linhas `compare` dos livros `hm/*`** são ruído (documentos minúsculos);
  informativas, sem gate.
- **Teto de memória do documento** só mede `retainedBytes`; a memória real
  (RSS) entra no SP6.
- **Linhas > 80 colunas** em `benchmark/bin/bench_runner.dart:30` e
  `benchmark/tool/bench.dart:307` (string que o formatador não quebra), no
  README do benchmark e nos testes de estilo; o README não explica a razão
  do `restyle`; o teste de `internalError` do `wide` monta o
  `StyledDocument` campo a campo.
- **Suítes de estilo de ~80 ms** ficam fora da janela de medida ideal.
- **Job `size` do noturno** não foi conferido depois do SP4 (tabela de cores
  e folha padrão novas): conferir o teto de 2 MiB do APK no primeiro
  noturno depois do merge.

## SP4 — Estilo

- **`var()` e propriedades customizadas:** zero livros no levantamento de
  2026-11-25 (372 livros); hoje `--*` é descartado com
  `css.unsupportedProperty`. Retomar quando aparecer num livro real.
- **Memória do leitor de CSS (antes da 1.0):** `buildStyleSheet` usa bem mais
  memória que o `csslib`. Medido no AOT (`VmHWM` acima da base, folha
  sintética `buildLargeCss`), depois do corte do `_name()` (substring sem
  escape, revisão final do SP4):

  | Cenário | antes do corte | depois | `csslib` |
  |---|---|---|---|
  | 1 × 256 KiB: pico | +47 MiB | +27 MiB | +4 MiB |
  | 1 × 256 KiB: tempo | ~142 ns/B | ~93 ns/B | ~109 ns/B |
  | 1 × 1 MiB: pico | +86 MiB | +86 MiB | +36 MiB |
  | 1 × 1 MiB: tempo | ~150 ns/B | ~123 ns/B | ~113 ns/B |
  | 8 × 256 KiB: pico | ~77 MiB | ~74 MiB | — |

  **Causa confirmada:** `tokenizeCss` materializa ≈ 1 token a cada 2,1 bytes
  (123.307 tokens em 256 KiB), a ~100 B por `CssToken`; as regras cruas
  (`ParsedCss`) guardam prelúdios e valores como `sublist` dessa lista, o que
  mantém todos os tokens vivos até o fim da montagem. A `StyleSheet` final é
  pequena (5,5 MiB retidos por 256 KiB). O aumento do tempo por byte de
  256 KiB para 1 MiB vem do GC sobre esse conjunto vivo proporcional à folha
  (o tokenizar puro fica plano), não de algoritmo quadrático.
  **Plano:** (1) buffer compacto de tokens em arranjos paralelos (`Uint8List`
  de tipos, `Int32List` de início/fim, `Float64List` de números, textos
  esparsos), ~21 B por token; (2) montar a `StyleSheet` regra a regra do
  topo, liberando os tokens de cada regra. Mexe na API de tokens de
  `css_syntax`, `css_blocks`, `selector_parser`, `property_parser`,
  `css_value_reader`, `media_query_parser` e `stylesheet_builder`. Fazer
  antes da 1.0, porque a anti-meta do projeto põe o gate contra concorrentes
  a partir dela. Junto: unificar os dois índices de linha (`ParsedCss._lines`
  e `_Parser._lines` sobre o mesmo texto).
- **`@font-face` dentro de `@media`** é aplicado sem avaliar a condição.
- **`format()` do `@font-face`** não é filtrado; quem registra as fontes
  (SP5/SP6) filtra.
- **Fundo e `list-style-image`** ficam intactos no tema; rever no SP6 com
  livros reais.
- **`@import` externo ou fora da raiz** sem diagnóstico.
- **Função CSS sem `)` no fim** é rejeitada (os navegadores aceitam).
- **`font-variant`** é tratado como longhand.
- **`overflow` com dois valores** é rejeitado.
- **`vertical-align` com `%`** é relativo à largura (deveria ser ao
  `line-height`).
- **`display: contents`** deixa os filhos sem a marca de texto corrido.
- Contadores (`counter()`, `counter-*`) só guardados; a geração fica no SP8.
- Aspas iguais para todos os idiomas.
- `@page :first/:left/:right` ignorados.
- Aninhamento CSS sem suporte (0 % dos livros).
- `ex`/`ch` aproximados por 0,5 em, sem métricas da fonte.
- **px de caixa não escala com a fonte** (margens, recuos e bordas em px
  ficam iguais com o fator de fonte): decisão de produto; o spec fala só em
  tamanhos de fonte.
- **Folha padrão reindexada por capítulo** (318 regras): guardar o
  `RuleIndex` dela pronto. Ganho real e simples; SP6 ou próximo passe de
  desempenho.
- Folha padrão: regras universais com atributo ausente; `border-color` cinza
  em tabelas; `audio` sem controles; `span` com `float`/`position: absolute`
  propaga a marca de texto corrido.
- Sem diagnóstico para preferências não finitas (o `PreferencePass` as ignora
  em silêncio); rever quando a API de preferências for exportada (SP6).

Leitura de CSS (diagnóstico e desempenho, sem efeito no estilo):
- Desempenho e duplicação no tokenizador além do `_name()` (5 minors da T1).
- At-rule sem `;` no fim do arquivo não gera erro; falso positivo de
  `@top-center` dentro de `@page`; `!important` comparado via
  `toLowerCase`; o texto é pré-processado 2×; aviso repetido por nível;
  `location` ambíguo para `style=`.
- `@import "?x"` vira aviso de ciclo; `parseMediaQueryText` sem cache.
- Seletores: alocação em `[a~=v]` e na flag `i`; `:not` não restaura `_end`;
  `ancestorHashes` sem teto nem deduplicação; `class="a a"` repete a
  candidata (idempotente).
- `CssNumber` não finito aceito dentro de `CssList`; documentar
  `retainedBytes`.

Organização e testes:
- `asciiLower` duplicado (`css_value.dart` × `css_syntax.dart`).
- `property_parser.dart` com ~1580 linhas; `_fontWeight` duplicado. Linhas
  com 82 colunas em `css_syntax.dart:124` e `property_parser.dart:51`.
- `ignore` de `visibleForTesting`; contadores globais de teste em `lib/`;
  `pseudoCount = 4` escrito à mão.
- Testes fracos ou frágeis: os do T2 (`css_syntax`), teste por `location`,
  teste da epígrafe confere `p.ep` e não o `em`, `restyle(match) ==
  styleDocument` quase tautológico, teto do `MatchedDocument` frouxo.
- Testes faltando no `@import`: mais de 64 imports, arquivo ausente, `%20`,
  importação em diamante.
- Testes com teto de tempo absoluto (2 s / 5 s) em `css_tokenizer_test`,
  `css_syntax_test`, `stylesheet_builder_test`, `property_parser_test`,
  `cascade_test` e `fuzz_test`: folgados, mas não provam linearidade. Se
  algum oscilar no CI, trocar por razão entre dois tamanhos.

Reserva do `restyle` (defeito interno):
- Exibe `head`/`title`; perde o `colorScheme` (`restyle.dart:97`); o
  diagnóstico interno leva só o tipo da exceção.

## SP6 — Render e API

- Chamar `BookStyleContext.flush` no fim do livro (totais de diagnósticos
  omitidos).
- Decidir a retenção do `MatchedDocument` (guardar para trocar só as
  preferências × recalcular).

## SP3 — Documento

Desempenho e API:
- `epubTypesOf` aloca uma lista a cada chamada. Devolver ids quando o SP4
  consultar em laço.
- Detectar `\r` e caracteres proibidos já no `decodeText` (bytes) para economizar
  ~2,5 ms por 2 MB. Só otimização; o resultado é o mesmo.

Modo tolerante e cabeçalho:
- `<title>` sem `<head>` em `text/html` vai para o body (texto visível e título
  não extraído). Tratar no SP5; `text/html` no spine é raro.
- `text/html` com conteúdo antes de `<html>` não gera diagnóstico.
- A linha informada no diagnóstico `document.recovered` pode vir de um
  diagnóstico não relacionado.
- Segunda raiz depois de `</svg>` entra dentro do svg.
- Lista de elementos que fecham `<p>` incompleta em relação ao HTML (`address`,
  `details`, `dl`, `fieldset`, `figcaption`, `form`, `hgroup`, `main`, `menu`,
  `summary`…). Só afeta o modo tolerante.
- `<link>` sem `href` é ignorado sem diagnóstico (nada se perde).
- `viewport` é lido mesmo fora do `<head>` (o SP8 decide).
- `<title>` vazio vira `""` em vez de `null`.

Organização e testes:
- Dividir `event_adapter.dart` e `recovery.dart` (~760 linhas cada) quando
  forem mexidos de novo.
- `_isBlank` duplicado e pilha paralela na política de recuperação.
- Fuzz só com ASCII/UTF-8 e sem seed SVG; ampliar.
- `dumpTree` (helper de teste) ordena atributos e imprime namespace como número.

## Antes da primeira publicação no pub.dev

- Forma da API pública: sealed, códigos de diagnóstico,
  `DrmProtectedException.algorithms`, nome `diagnostics`.
- Idioma do README (adiado).
- Atualizar o Flutter local (3.47.5) e conferir a versão mínima no `pubspec`.
