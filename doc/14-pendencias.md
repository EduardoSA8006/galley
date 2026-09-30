# 14 — Pendências

Lista viva do que ficou para depois: melhorias adiadas de propósito, pontos que
um spike deixou em aberto e verificações que dependem de algo que ainda não
existe (motor, aparelho, versão). Quem adia alguma coisa anota aqui, com a
origem; quem resolve move a linha para **Concluídas** com a data e o commit.

A decisão de arquitetura continua morando no documento de origem. Esta lista só
aponta para ela e diz **quando** voltar ao assunto.

## Abertas

### Infraestrutura, medição e CI

| Item | Origem | Quando |
|---|---|---|
| Segunda fonte de métricas no harness de desempenho: engine real em `--profile` via `flutter drive` no Linux, com timeline, alimentando o mesmo baseline e o mesmo comparador. O harness da Fase 0 roda em JIT no `flutter_tester` e só detecta regressão; não mede o orçamento de [10](10-testes.md) §4.1 | Brainstorming do harness (2026-09-25) | Fase 2, junto com o teste de jank de [10](10-testes.md) §4.3 |
| Medir o orçamento de [10](10-testes.md) §4.1 no dispositivo de referência (Android classe Pixel 6a, `--profile`), fora do CI | [10](10-testes.md) §4.1 | A partir da Fase 2 |
| Métrica de memória (pico e memória nativa de `ui.Paragraph`/`ui.Image`) no harness | [10](10-testes.md) §4.1 | Fase 2 |
| Jobs de CI em macOS e Windows (diferenças de caminho e de fonte) | Brainstorming do CI (2026-09-25) | Antes da Fase 6 |
| Job de CI no web (`flutter test --platform chrome`, corretude no DDC) e medição de P10 em build de release no Chrome | Brainstorming do CI (2026-09-25); [10](10-testes.md) §4.4 | Quando começar o trabalho da 1.0.x |
| O workflow `perf-baseline` não publica o candidato quando a conferência final falha (sem `if: always()` no upload); decidir se deve publicar para inspeção | Implementação do harness (2026-09-25) | Na primeira vez que o baseline for regenerado |
| `combineBaseline` confere Flutter e casos entre execuções, mas não `dart`/`os`; herda do primeiro | Implementação do harness (2026-09-25) | Se o baseline passar a combinar runners diferentes |
| Completar com os casos do contêiner e `publication.read.800` os modelos de CPU do runner que ainda só têm os 4 casos da Fase 0 (EPYC 9V45, Xeon Platinum 8370C), disparando o `perf-baseline` até cair neles. O Xeon Platinum 8573C já tem baseline próprio, com os 8 casos | Sub-tarefa 10b (2026-09-25); baselines do contêiner (2026-09-26); baselines da Publicação (2026-09-26) | Contínuo |
| Versão do pacote `html` não travada para o perf (`/pubspec.lock` é ignorado): registrar as versões resolvidas dos pacotes medidos no `result.json` e avisar quando divergirem do baseline | Revisão final do harness (2026-09-25) | Fase 1 |
| Contêiner em `strict`: `rights.xml` (ou `encryption.xml` com KeyInfo LCP) com CRC errado sai como `EpubContainerException(zipCrcMismatch)` em vez de `EpubEncryptedException`, contra a frase de [09](09-erros-diagnosticos.md) §4. Só afeta `strict` (testes). Ler os metadados com sink não estrito e reemitir o diagnóstico depois da checagem de DRM | Revisão final do contêiner (2026-09-26) | Sub-projeto 6, junto da revisão do `strict` do documento ([spec da Publicação](specs/2026-09-26-publication-design.md) §1.3) |
| Endurecimento do contêiner abaixo dos tetos: `encryption.xml` válido de 4 MiB com aninhamento profundo ainda custa ~1 s e ~250 MiB (baixar o teto para 1 MiB?); entrada stored com `compressedSize` enorme e tamanho declarado pequeno lê o arquivo antes de recusar (conferir `compressedSize` com folga); um `compressedSize` corrompido invalida as entradas seguintes pela regra de sobreposição | Revisão final do contêiner (2026-09-26) | Sub-projeto 5 (worker), ou antes se aparecer caso real |
| Ruído do gate dentro da mesma CPU acima do limite: no Xeon Platinum 8573C, `image.decode.target` variou 21% entre as 3 rodadas de uma VM (a conferência do `perf-baseline` reprovou); no EPYC 7763, `font.deobfuscate.idpf` variou 16% entre 5 VMs. Opções: mais amostras ou `innerIterations` nesses casos, limite por caso, ou repetir e reprovar só se duas execuções regredirem | Baselines do contêiner (2026-09-26) | Antes de o gate de desempenho bloquear uma PR por ruído |

### Fase 1

| Item | Origem | Quando |
|---|---|---|
| P7: inflate no web, implementação própria ou `archive` por import condicional, pelo tamanho do bundle | [01](01-decisoes.md) P7; [11](11-empacotamento-versionamento.md) §1 | Fase 1 |
| Confirmar em AOT que a chave FNV-1a de uma seção de 500 KB fica abaixo de 1 ms (P8) | [08](08-concorrencia-cache.md) §4.1 | Fase 1 |
| Confirmar o custo de spawn de isolate (0,07–0,24 ms no desktop) em Android AOT | [08](08-concorrencia-cache.md) §1; S9 | Fase 1 |
| Parse fatiável para o web: medir `parseFragment` em pedaços de ~16 KB, tokenizer próprio e Web Worker | [08](08-concorrencia-cache.md) §1; S9 | Fase 1 (pré-requisito da 1.0.x) |
| Cessão entre fatias por `MessageChannel` (ou `scheduler.postTask`) em vez de `Timer`, por causa do clamp de ~4,2 ms do navegador | [08](08-concorrencia-cache.md) §2; S9 | Fase 1 (pré-requisito da 1.0.x) |
| SVG-invólucro desembrulhado e repaginação quando a dimensão da imagem chega | S7; [13](13-riscos-spikes-fases.md) §1 | Fase 1 |
| Tamanho do pacote no web (inflate, SHA-1, CSS), teto de 300 KB minificado | [13](13-riscos-spikes-fases.md) §1.2 | Fase 1 |
| Chave NFC no índice de nomes do contêiner: nomes do ZIP e caminhos pedidos comparados em NFC | [Spec do contêiner](specs/2026-09-25-container-design.md) §1.2 | Sub-projeto 4 (IR de seção), quando a normalização existir |
| `tool/corpus/lib/hashes.dart` duplica o CRC-32 e o SHA-1 de `lib/src/container/`; unificar quando `tool/` puder importar o pacote | [Spec do contêiner](specs/2026-09-25-container-design.md) §7 | Antes da 1.0 |
| `test/container/inflate_web_test.dart` só roda com `--platform chrome`; entra no CI junto com o job web | [Spec do contêiner](specs/2026-09-25-container-design.md) §7 | Com o job web (1.0.x) |
| `encryption.xml` em UTF-16 ou com `encoding` Latin-1 declarado é decodificado como UTF-8 (UTF-16 vira falso positivo `unknown:encryption.xml-invalido`) | Implementação do contêiner (2026-09-26) | Sub-projeto 4, junto com a detecção de encoding da IR |
| `CipherReference` relativo ao diretório do OPF (em vez da raiz do contêiner) não casa com a entrada, e a fonte segue ofuscada sem diagnóstico | Implementação do contêiner (2026-09-26) | Sub-projeto 6, que cruza fontes, manifest e `encryption.xml` ao carregar fontes ([spec da Publicação](specs/2026-09-26-publication-design.md) §1.3) |
| `CipherReference` fora de `CipherData` e `RetrievalMethod` LCP fora de filho direto do `KeyInfo` (XML-Enc fora do esquema) não são detectados; nenhum produtor conhecido gera isso | Implementação do contêiner (2026-09-26) | Se aparecer um EPUB real assim |
| `ProviderContainer` só aplica `maxEntrySize` depois que `provider.read` materializa o recurso inteiro, porque `EpubResourceProvider` não expõe tamanho nem leitura em fatias | Implementação do contêiner (2026-09-26) | Sub-projeto 6, ao revisar a API pública |
| Os passos do `decode()` saem em rajada com taxa de compressão alta: uma fatia de 16 KiB pode gerar até 16 MiB de saída e ~56 ms sem ceder o isolate | Revisão final do contêiner (2026-09-26) | Sub-projeto 5 (worker) |
| O fallback do EOCD64 assume 56 bytes colados ao locator (`eocdPos - locatorSize - eocd64Size`); prefixo com um extensible data sector entre o central directory e o locator faria essa busca falhar e o arquivo virar fatal | Revisão final do contêiner (2026-09-26) | Se aparecer um EPUB real assim |
| Título de entrada órfã do TOC pelo primeiro heading da seção (hoje: nome do arquivo sem extensão) | [Spec da Publicação](specs/2026-09-26-publication-design.md) §1.1, §7.6 | Sub-projeto 4 (IR de seção) |
| Capa pelos passos 3 e 5 de [06](06-locator-navegacao.md) §5.1 (landmark ou `guide` de capa cuja seção tem uma imagem só; primeira imagem da primeira seção) | [Spec da Publicação](specs/2026-09-26-publication-design.md) §1.1, §8.2 | Sub-projeto 6 |
| `page-list` a partir de `epub:type="pagebreak"` no corpo, quando NAV e NCX não têm | [Spec da Publicação](specs/2026-09-26-publication-design.md) §1.1 | Sub-projeto 4 |
| `totalChars` da publicação (soma das seções, para progresso) | [Spec da Publicação](specs/2026-09-26-publication-design.md) §1.1 | Sub-projeto 4 |
| Resolução de alvo de TOC, landmark e `page-list` (`caminho#fragmento`) para offset, e `EpubTocEntry`/`EpubPageMark` com `Locator` | [Spec da Publicação](specs/2026-09-26-publication-design.md) §1.1, §3 | Sub-projeto 6 |
| Entradas sintetizadas com nome de arquivo em livros com páginas de imagem (a Alice do corpus ganha 28, como `7491619335329807298_i001.jpg.id-1492325526376266811.wrap-0.html`); a UI pode escondê-las por `synthesized` | Implementação da Publicação (2026-09-26) | Sub-projeto 6, ao montar `doc.toc` |
| Regenerar os baselines por CPU com `publication.read.800` (disparar o `perf-baseline`); até lá aparece como "novo, sem baseline" | [Spec da Publicação](specs/2026-09-26-publication-design.md) §11 | Logo depois do merge da PR da Publicação |
| Regenerar os baselines por CPU com `css.parse` e `css.cascade` (disparar o `perf-baseline`); até lá aparecem como "novo, sem baseline" | [Spec do CSS](specs/2026-09-26-css-design.md) §15 | Logo depois do merge da PR do CSS |

### Publicação

| Item | Origem | Quando |
|---|---|---|
| `li` que não é filho direto da lista (`<ol><div><li>…`) é ignorado pelo `parseNav`; tolerância barata a considerar (aceitar o `li` descendente sem descer em listas aninhadas) | Revisão da T7 da Publicação (2026-09-26) | Sub-projeto 6 (Documento), ou se aparecer em EPUB real |
| O parse do conteúdo XHTML do sub-projeto 6 (Documento) precisa da mesma proteção do NAV contra o `package:html` (0.15.7): referência numérica fora de faixa (`&#99999999999999999999;`) faz o `int.parse` do tokenizador lançar `FormatException`; fechamento de nome longo dentro de texto cru (`<title></aaa…`) e nome de tag ou DOCTYPE longo são quadráticos; e o estado do tokenizador depende da árvore (SVG/MathML, `select`, escape de `script`), o que um modelo de fora não acompanha. O NAV resolve com um pré-passe que tokeniza e re-serializa um HTML canônico (sem comentários, texto cru, SVG/MathML nem atributos não lidos; referência fora de faixa como `&#xFFFD;`), mais uma captura estreita de `FormatException` em volta do `html.parse` | Revisão da T7 da Publicação (2026-09-26) | Sub-projeto 6 |
| O texto dentro de `svg`/`math` some dos rótulos do NAV (o pré-passe tira as subárvores inteiras): um rótulo só com MathML cai para o atributo `title` ou para `''` | Revisão da T7 da Publicação (2026-09-26) | Se aparecer em EPUB real |
| §8.1 fatal demais: fonte ofuscada com media-type fora da lista (`application/x-opentype`, vazio) lança `EpubEncryptedException`; considerar inverter — fatal só quando o media-type é consumido como conteúdo (xhtml, html, imagem, css, svg) — o que dispensaria o caso especial de `application/octet-stream` | Revisão da T10 da Publicação (2026-09-26) | Quando aparecer EPUB real com fonte ofuscada, ou no sub-projeto 6 |
| Um ZIP com dois nomes que só diferem na caixa perde o segundo no spine e nos alvos (a caixa é dobrada por `toLowerCase`, como o `ZipContainer`); o OCF proíbe essa dupla, mas nada barra o arquivo | Revisão da T10 da Publicação (2026-09-26) | Se aparecer em EPUB real |
| Lacuna de cobertura do corpus: nenhum caso exercita `spineItemUnresolved`/`spineItemDuplicate`; a segunda passada `strict` só roda em `capa-ausente`; os `reais/` comparam só o conjunto de códigos, não a estrutura do TOC | Revisão da T12 da Publicação (2026-09-26) | Sub-projeto 6, ao criar casos novos |
| Diagnósticos de `href` recusado se fundem: o `resourceMissing` de um item com `href` recusado por `normalizeHref` sai com `href: null`, e o `DiagnosticSink` agrupa por (código, `href`), então N itens recusados viram um registro com `count` N e só os `details` (`id`, `raw`) do último | Revisão final da Publicação (2026-09-26) | Sub-projeto 6, se a UI ou o relatório de diagnóstico precisar listar cada item recusado |
| OPF, NAV e NCX de 4 MiB cada (no teto) somam ~2 s de leitura da Publicação (custo linear; um NAV sem `page-list` puxa o NCX também) | Revisão final da Publicação (2026-09-26) | Sub-projeto 5 (worker), que tira a leitura da thread de UI |
| `normalizeHref` não confere o `baseDir` (seguro só porque ele sempre vem de um caminho já normalizado); surrogate solto no `href` vira U+FFFD no decode | Revisão da T4 da Publicação (2026-09-26) | Se `normalizeHref` passar a receber `baseDir` de outra origem |
| Metadados do OPF: `EpubMetadata.raw` é copiado duas vezes (o `for` e o `Map.unmodifiable`); todo `collection-type` é marcado como usado (numa série com `series` e `set`, o `set` some do `raw`); um `meta` com `id` igual ao de um `dc:creator` anterior vira dono do `id`; `rendition:layout` só é marcado como usado na forma com `content` | Revisões das T2 e T6 da Publicação (2026-09-26) | Se aparecer em EPUB real |
| Decodificação de XML: sem teste dedicado de declaração de `encoding` truncada (o fuzz confirmou que é segura); `utf-8`/`utf8` caem no ramo padrão de `_encodingOf`, sem caso explícito | Revisão da T3 da Publicação (2026-09-26) | Sub-projeto 4, junto da detecção de encoding da IR |
| NAV: a re-serialização canônica amplia `"` em `&quot;` (6×) e `<` em `&lt;` (4×) sem cobrar no orçamento (~1,7 s, linear, com 4 MiB); sem DOCTYPE, o `html.parse` fica em modo quirks (`table` não fecha `p`), sem efeito medido | Revisão da T7 da Publicação (2026-09-26) | Sub-projeto 5 (custo, no worker), ou se aparecer em EPUB real |
| NCX: `pageTarget` com rótulo vazio não usa o atributo `value`; atributo com prefixo vence o sem prefixo (convenção do projeto); entidades indefinidas ficam literais no rótulo | Revisão da T8 da Publicação (2026-09-26) | Se aparecer em EPUB real |
| Reconciliação e capa: o órfão cujo vizinho está aninhado entra na raiz depois da parte inteira (conforme a spec §7.6; a UI pode agrupar por `synthesized`); o título sintetizado só tira a última extensão (`cap.htm.xhtml` → `cap.htm`); `<meta name="cover">` com `href` no lugar do id compara com o `path` sem decodificar `%xx` nem dobrar a caixa (diverge de §5.4) | Revisão da T9 da Publicação (2026-09-26) | Sub-projeto 6, ao montar `doc.toc` e a capa |
| `decodePath` pode deixar espaço no fim de um segmento (`x.xhtm%20` → `x.xhtm `): um alvo de TOC que não casa com item nenhum sai com esse caminho, que o Win32 grava sem o espaço final. Achado no fuzz de 440 mil casos (1 caso) | Onda de correção da revisão final da Publicação (2026-09-26) | Sub-projeto 6, ao resolver os alvos contra as seções |

### CSS

| Item | Origem | Quando |
|---|---|---|
| Fuzz grande do CSS (dezenas de milhares de mutações, semente aleatória), como o da Publicação | [Spec do CSS](specs/2026-09-26-css-design.md) §14.2 | Revisão final da branch `fase1/css` |
| O parse das folhas roda no prólogo assíncrono sem ceder (~11 ms por MiB tokenizado); se a fatia medida passar do tolerado, vira `sync*` | [Spec do CSS](specs/2026-09-26-css-design.md) §9.5, #23 | Sub-projeto 5 (worker) |
| Pior caso da cascata: com o orçamento baixado para 2^22 na revisão do plano (era 2^24, ~0,9 s), o hostil mais caro por passo custa ~0,17 s por seção (JIT, i5-11400H) e ~0,45 s com a máquina carregada; o maior uso real do corpus é 71 525 passos. Medir em AOT e no aparelho de referência | [Spec do CSS](specs/2026-09-26-css-design.md) §11, #38 | Sub-projeto 5 (worker) |
| Memória com muitas classes: os `ElementInfo` dos irmãos vivem juntos, e 1 000 irmãos com 20 000 classes cada guardariam ~20 milhões de `String` (~1,5 GiB); considerar um teto de classes por elemento | Implementação do CSS (2026-09-26) | Sub-projeto 4, junto do teto de seção, ou sub-projeto 5 |
| Tamanhos reduzidos nos testes hostis por memória e tempo do CI: classe e `id` de 1 MiB em 100 elementos (não 1 000), 20 000 classes em 30 elementos (não 1 000) e `budget: 1 << 20` em todos os que só precisam esgotar o orçamento, menos o `div … div p` | Plano do CSS, decisão 22 | Revisão final da branch, junto do fuzz grande |
| Fusões pelo dedupe (código, `href`) do `DiagnosticSink`: dois motivos de `stylesheetIgnored` da mesma folha, e `float` com `position` da mesma seção em `unsupportedLayout`, viram um registro com os `details` do último | [Spec do CSS](specs/2026-09-26-css-design.md) §7.5, §12.1 | Sub-projeto 6, se a UI ou o relatório precisar listar cada motivo |
| Aproximações de §7.5: `em` herdado vale sobre a fonte do filho; `bolder` sobre peso 300 dá 400 (normal); `script`/`style` além da profundidade 256 ficam visíveis; `text-decoration` propaga para dentro de `inline-block`, `float` e posicionado; `<!-- -->` dentro de `<style>` é aplicado, e não tirado como comentário do XML; links (`a[href]`) sem o sublinhado de `:link` da folha do HTML | [Spec do CSS](specs/2026-09-26-css-design.md) §7.5 | Se aparecer em EPUB real |
| Propriedades lógicas (`margin-inline-*`, `padding-inline-*`) ignoradas; recuo de lista físico (`padding-left`) em livro `rtl`; filhos de `flex`/`grid` sem "blocoficação" | [Spec do CSS](specs/2026-09-26-css-design.md) §7.3, §7.5, §8.1 | Fase 2 (Camada B), se o perfil honrar margens |
| Dicas de apresentação além de `hidden`/`dir` (`align`, `width`/`height` de `img` como CSS) | [Spec do CSS](specs/2026-09-26-css-design.md) §1.2, §8.2 | Sub-projeto 4 |
| Seletores fora do subconjunto que o corpus usa: `[attr]` (`a[href]`), `~=`, `:not()` simples, `:root`, `a:link` | [Spec do CSS](specs/2026-09-26-css-design.md) §6.3; corpus | Depois da 1.0, se o custo couber |
| `@supports` descartado inteiro; regras aninhadas do CSS Nesting descartadas; `@layer` e `@import … layer`; `vw`/`vh`/`calc()`/`var()` | [Spec do CSS](specs/2026-09-26-css-design.md) §5.1, §5.3, §7.2 | Depois da 1.0 |
| Codificação do documento que referencia (passo do CSS Syntax §3.2 omitido): folha sem BOM nem `@charset` num livro Latin-1 só cai para Latin-1 por UTF-8 inválido; e `decodeCss` duplica ~40 linhas de `decodeXml` (os auxiliares são privados) | [Spec do CSS](specs/2026-09-26-css-design.md) §9.4; plano do CSS, decisão 24 | Sub-projeto 4, junto da detecção de encoding da IR |
| Como o sink da seção entra no agregado do documento, e o placeholder que relança por identidade a exceção de `strict` dos dois sinks | [Spec do CSS](specs/2026-09-26-css-design.md) §9, §12.3 | Sub-projeto 4 |
| Divergências do Chromium 153 nas listas fechadas de pseudo-classes e pseudo-elementos (seguem o Selectors 4): o galley aceita `:target-within`, `:local-link`, `:playing`, `:paused`, `:has(:foo)`, `:lang(1)`, `:dir(1)` e `::cue()`, que o Chromium rejeita; e rejeita `::-webkit-*`, `:-webkit-any-link`, `:host`, `:autofill`, `:modal`, `:open`, `:user-invalid`, `::part()`, `::highlight()`, `::spelling-error` e `::target-text`, que o Chromium aceita — com isso `p, ::-webkit-scrollbar` derruba a regra de `p` | [Spec do CSS](specs/2026-09-26-css-design.md) §6.3 | Revisão da T3 do CSS (2026-09-28) — Se aparecer em EPUB real |
| `}` em `style=""` diverge do Chromium, que o trata como token comum; a decisão 10 do plano segue a letra do CSS Syntax | [Spec do CSS](specs/2026-09-26-css-design.md) §5.3; plano do CSS, decisão 10 | Revisão da T6/T8 do CSS (2026-09-30) — Se aparecer em EPUB real |
| `@supports not foo {}`, `@supports (a:b) junk {}`, `@counter-style {}` e `@keyframes {}` inválidos ainda tiram o `@import` de posição | [Spec do CSS](specs/2026-09-26-css-design.md) §5.2 | Revisão da T6/T8 do CSS (2026-09-30) — Se aparecer em EPUB real |
| `@layer` depois de `@import` não encerra a posição do `@namespace` | [Spec do CSS](specs/2026-09-26-css-design.md) §5.2 | Revisão da T6/T8 do CSS (2026-09-30) — Se aparecer em EPUB real |
| Latin-1 contra windows-1252: o Encoding Standard mapeia `latin1`/`iso-8859-1` para windows-1252, e 0x80–0x9F viram controles C1; comum ao `decodeCss` e ao `decodeXml` | [Spec do CSS](specs/2026-09-26-css-design.md) §9.4 | Revisão da T6/T8 do CSS (2026-09-30) — Sub-projeto 4, junto da detecção de encoding da IR |
| No `<style>` dentro de SVG as entidades são decodificadas duas vezes: `&amp;lt;` vira `<` | [Spec do CSS](specs/2026-09-26-css-design.md) §9.1 | Revisão da T6/T8 do CSS (2026-09-30) — Se aparecer em EPUB real |

### Fase 2

| Item | Origem | Quando |
|---|---|---|
| Tabela de SpecialCasing própria no `DisplayMap` (`ß → SS` igual em VM e web), ~1 dia | S2; [04](04-layout-paginacao.md) §1.1 | Fase 2 |
| Primeira página rápida com tabela grande no início da seção: declarar a exceção ou medir as primeiras N linhas e repaginar | S4; [04](04-layout-paginacao.md) §2.3 | Fase 2 |
| Tabela: `rowSpan` que sai do cabeçalho para o corpo e tabela que começa no meio de uma página (não tratados no protótipo) | S4; [04](04-layout-paginacao.md) §9 | Fase 2 |
| Reexaminar `StrutStyle` na versão mínima fixada (no 3.44.1 não alterava a altura de linha) | S5; [04](04-layout-paginacao.md) §1 | Fase 2 |

### Fase 4

| Item | Origem | Quando |
|---|---|---|
| S3: acessibilidade com TalkBack e VoiceOver reais, incluindo se `headingLevel` chega fora do web | [13](13-riscos-spikes-fases.md) S3; [05](05-render-selecao-a11y.md) §4.3 | Quando houver aparelho físico; fecha na Fase 4 |
| Seleção completa (~14 dias): alças da plataforma, auto-avanço, modo contínuo, gestos, RTL/CJK | S2; [13](13-riscos-spikes-fases.md) §1.1 | Fase 4 |
| Verificação da seleção em aparelho real (alças, lupa, háptico, arena de gestos, auto-avanço, Impeller) | S2; [13](13-riscos-spikes-fases.md) §1.1 | Fase 4 |
| `text-transform`: `capitalize`, `lowercase` com `İ`, locale `tr`, ligaduras de fonte real | S2; [13](13-riscos-spikes-fases.md) §1.1 | Fase 4 |

### Depois da 1.0

| Item | Origem | Quando |
|---|---|---|
| Medir rios de `justify` com U+00AD e o dicionário `hyph-pt`; min-content de célula hifenizada calculado pelo motor | S5; [04](04-layout-paginacao.md) §8 | 1.2 |
| P9: fixed-layout no núcleo ou em `galley_fixed_layout` | [01](01-decisoes.md) P9; [12](12-roadmap.md) | Antes da 1.1 |

## Concluídas

| Item | Data | Commit |
|---|---|---|
| Reformatar os spikes S5–S8 no formatter do Dart 3.13 | 2026-09-25 | c6d312a |
| Medir a variação entre VMs antes de commitar o baseline e decidir baseline por CPU. Resultado: dentro do mesmo modelo (EPYC 7763, 3 VMs) a razão varia no máximo 8,3%; entre quatro modelos (EPYC 7763, EPYC 9V45, Xeon 6973P-C, Xeon 8370C) varia até 30% (zlib), 22% (html) e 21% (paragraph). Decisão: baseline por modelo de CPU, um arquivo por modelo em `test/perf/baselines/`; CPU sem baseline só avisa | 2026-09-25 | 28f10e8, db3a518 |
| A CLI `update_baseline.dart` não tinha teste automatizado próprio; ganhou `test/tool/perf_update_baseline_test.dart` ao adicionar `--out-dir` por TDD | 2026-09-25 | 28f10e8 |
| Proteção de branch na `main` exigindo `analyze`, `test (min)`, `test (stable)`, `engine-linux` e `perf` vindos do GitHub Actions, com a PR em dia com a `main` antes do merge; vale também para admin; sem revisão obrigatória; force-push e exclusão bloqueados | 2026-09-25 (branch em dia e checks amarrados ao Actions em 2026-09-26) | configuração do repositório |
| `encryption.xml` sem teto próprio de tamanho: é lido até `maxEntrySize` (256 MiB) e parseado de forma síncrona | 2026-09-26 | d07f676 |
| Regenerar os baselines por CPU com os casos do contêiner: EPYC 7763 (mediana de 5 VMs), EPYC 9V74 (novo) e Xeon 6973P-C; os casos antigos ficaram entre −4% e +0,5% dos baselines anteriores, sem regressão | 2026-09-26 | 34beb62 |
| Teste do diagnóstico de prefixo do ZIP voltou a conferir `details.delta`, além de `reason` | 2026-09-26 | 32042c3 |
| `S5.5` (`test/spike/s5_soft_hyphen_test.dart`) falhava às vezes sob carga (mediana de 3 rodadas intercaladas, limite 1.5; visto 1,45 sob `stress-ng --cpu 12` e um pico de 1,79 com duas suítes inteiras rodando em paralelo). Passou a intercalar (A, B, A, B, …) 15 rodadas com aquecimento e limite 1.6, sem perder o que o spike prova (SHY não deveria multiplicar o custo do shaping); 10 execuções sequenciais e várias rodadas com duas suítes inteiras em paralelo ficaram entre 1,02 e 1,32 | 2026-09-26 | 6a7f4c4 |
