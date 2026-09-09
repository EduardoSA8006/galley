# 10 — Testes

**Decisão 9.1: métricas como gate, goldens de imagem num subconjunto.**

## 1. Corpus antes de código

Cada bug conhecido de EPUB real vira um caso de teste **com o arquivo que o
originou**. É o ativo mais valioso do projeto, porque cada arquivo representa
conhecimento adquirido sobre algo que já derrubou um leitor em produção.

### 1.1 Corpus mínimo (Fase 0)

| Grupo | Casos |
|---|---|
| **Regressões conhecidas** | `text-align` inline causando altura zero; capítulo renderizando em branco; item só-imagem no spine; `href` com separador do Windows; `href` URL-encoded; encoding declarado errado (Latin-1, Shift-JIS, BOM lido como UTF-8); NCX incompleto com órfãos; imagem de capa ausente do manifest; `<a id="x"/>` auto-fechado antes de texto |
| **Estrutura** | Capítulo de 200 mil palavras; capítulo de 3 palavras; spine de 800 itens; TOC com 6 níveis; `page-list` presente; OPF em subpasta com `href` relativos com `..`; `linear="no"` |
| **Conteúdo difícil** | Tabela larga com `colspan`; tabela aninhada; tabela com `thead` repetível; lista de 5 níveis; `<ol start="7">`; 400 notas de rodapé; SVG inline; SVG embrulhando raster; imagem sem dimensão intrínseca; `pre` com linhas de 300 colunas; `text-transform: uppercase` com `ß`; `&nbsp;` e U+200B |
| **Faixa B** | `float` com contorno; `columns`; `writing-mode: vertical-rl`; ruby/furigana; MathML |
| **Escrita** | RTL (árabe, hebraico) com `page-progression-direction: rtl`; CJK japonês e chinês com `lang` (unificação Han); grego politônico; devanágari; bidi misto (hebraico em livro em português) |
| **Patologia** | ZIP com `mimetype` comprimido; ZIP64; `encryption.xml` de ofuscação de fonte IDPF e Adobe; `encryption.xml` de DRM LCP; OPF sem spine; arquivo truncado; CRC errado; seção de 3 MB |

Alvo: 40 a 50 arquivos. Cada um com um `README` de uma linha dizendo o que ele
testa e de onde veio, e uma lista **exata** de diagnósticos esperados quando não
for zero.

Arquivos com direitos autorais não entram no repositório. O corpus é montado de
domínio público (Gutenberg, Standard Ebooks, que é a melhor fonte de EPUB3 bem
feito), de arquivos sintéticos gerados por script a partir de um template, e de
arquivos reais **reduzidos** ao trecho que reproduz o bug, com o texto trocado por
lorem ipsum preservando a estrutura.

## 2. Invariantes de propriedade

O contrato de fidelidade precisa de verificação **automática**, não de inspeção
visual. Estes rodam sobre todo o corpus, para uma matriz de estilos e viewports.

### Invariante 1 — Cobertura de texto

> A união dos ranges `[textStart, textEnd)` de todas as páginas de uma seção é
> exatamente `[0, canonicalText.length)`, sem lacuna e sem sobreposição.

É a prova mecânica de "nenhum byte de conteúdo é descartado". Com o `\n` de fim
de bloco pertencendo ao bloco ([03](03-camada-a-ir.md) §5), a igualdade é exata.

### Invariante 2 — Cobertura de objetos

> Todo `InlineObject` da IR aparece em exatamente uma página.

Decorre da 1 (cada objeto é um U+FFFC), mas é testada separadamente porque a
pintura da imagem tem caminho próprio.

### Invariante 3 — Idempotência de locator

> `locator → página → locator` devolve o mesmo locator, para qualquer estilo e
> qualquer viewport.

### Invariante 4 — Estabilidade de offset

> Mudar qualquer campo de `EpubStyle` não muda nenhum `charOffset`.

É a prova de que a Camada A é realmente independente de estilo, e portanto de que
o cache em disco é válido.

### Invariante 5 — Simetria de modo

> Um locator resolvido no modo paginado e no modo contínuo aponta para o mesmo
> `charOffset`.

### Invariante 6 — Cobertura semântica

> Todo caractere de `canonicalText` visível numa página aparece em algum
> `SemanticsNode` daquela página.

### Invariante 7 — Consistência do `DisplayMap`

> Para todo bloco, `map.toCanonical(map.toDisplay(c)) == c` para todo `c` no
> range, e `toCanonical` é monotônica não-decrescente.

### Invariante 8 — Paginação ancorada

> A paginação a partir de qualquer âncora cobre a seção inteira (Invariante 1
> vale), a linha pedida está na página ancorada, e
> `páginas(âncora) − páginas((0, 0)) ∈ {0, 1}`.

O sinal importa: a costura só pode desperdiçar espaço, nunca ganhar, então −1
é bug. Verificado no protótipo do spike S8 em 500 casos aleatórios.

### Invariante 9 — Ida e volta do cache

> `deserialize(serialize(section)) == section`, campo a campo, para toda seção do
> corpus.

Se as nove passam, "sem perda de conteúdo" e "acessível" deixam de ser retórica.

### 2.1 Matriz

Cada invariante roda para o produto de:

- 4 tamanhos de fonte (12, 16, 22, 32)
- 3 viewports (360×640, 768×1024, 1440×900)
- 2 modos (paginado, contínuo)
- 2 direções (ltr, rtl) quando aplicável
- 2 âncoras (início da seção; meio da seção) para a Invariante 8

= 48 combinações por arquivo de corpus para as invariantes 1 a 7. São testes
rápidos (sem pintura), então isso é viável no CI. As invariantes 4 e 9 não
dependem de viewport e rodam uma vez por arquivo.

## 3. Gates

### 3.1 Gate principal: snapshots textuais

Snapshots de métricas de linha e da IR serializada, em formato textual legível.
Rápidos e determinísticos.

```
cap03.xhtml @ fs=16 w=360
  block[0] paragraph lines=4 h=89.6 range=[0,213)
    line[0] y=0.0 h=22.4 range=[0,54)
    ...
```

Diferença de snapshot é revisada como diff de código, o que torna mudanças de
layout visíveis no PR.

**Estabilidade entre plataformas depende da fonte.** `flutter test` usa a fonte
`FlutterTest` (glifos de caixa com métricas fixas), que é determinística em toda
plataforma, e os snapshots de métricas rodam com ela. Isso valida fluxo, quebra
e paginação, mas não shaping real. Para shaping real, um segundo conjunto de
snapshots roda com uma fonte OFL embutida em `test/fonts/` (Literata ou Source
Serif), em **uma** plataforma no CI, porque a rasterização não muda as métricas
de linha mas o fallback de fonte do sistema muda.

Snapshots da IR (Camada A) não dependem de fonte e rodam em todas.

### 3.2 Complemento: goldens de imagem

Num subconjunto pequeno (5 a 8 arquivos), com a fonte OFL embutida e rodando em
**uma única plataforma** no CI. Rasterização de fonte difere entre sistemas, e
golden de imagem multiplataforma é fonte garantida de flake.

Cobrem o que o snapshot textual não pega: erro de translate, clip errado, ordem
de pintura de destaque, retângulo de seleção deslocado, marcador de lista,
régua de tabela.

### 3.3 Testes de semântica

Automatizados, verificando Invariante 6 mais:

- headings expõem `isHeader` e nível correto
- ordem dos nós corresponde à ordem do documento
- imagens com `alt` expõem `label`
- links e notas expõem `isLink` e ação de ativação
- nós são **reutilizados** entre frames (mesmo `id` de `SemanticsNode` para o
  mesmo fragmento após repaint)

### 3.4 Testes de interação

`flutter_test` com `WidgetTester`: virada por toque na borda e por arraste,
seleção por long press e extensão por alça (incluindo atravessar página), teclado
(cada linha da tabela de [05](05-render-selecao-a11y.md) §5.1), e o ciclo
declarativo de [07](07-api-publica.md) §1.2 (o eco de `onStateChanged` não
navega).

## 4. Desempenho no CI

Limites que **quebram o build**, expressos como **regressão relativa a um
baseline** (na ordem de 20%), não em milissegundos absolutos, porque runner de CI
é ruidoso.

Desempenho é o diferencial do produto. Se não falhar o build, degrada em
silêncio.

### 4.1 Orçamento

Medido sobre um EPUB de ~25 MB com capítulos longos, em dispositivo de referência
de médio porte (Android de 2022, classe Pixel 6a), com `--profile`:

| Métrica | Alvo |
|---|---|
| Abrir e pintar a primeira página (cache frio) | < 300 ms |
| Abrir e pintar a primeira página (cache quente) | < 80 ms |
| Virar página | < 16 ms |
| Trocar cor, alinhamento ou peso | < 50 ms |
| Trocar tamanho ou família de fonte, posição preservada | < 200 ms, **independente do tamanho do capítulo** (paginação ancorada) |
| Contagem de páginas da seção disponível | < 400 ms após abrir, para capítulo de até 8 mil palavras; < 3 s para 200 mil |
| Progresso global disponível (cache frio, spine de 100 seções) | < 1 s |
| Rotação com posição preservada | < 250 ms |
| Pico de memória | < 120 MB |
| Tamanho do cache em disco | < 8% do tamanho do EPUB |
| Consumo em background com o livro parado | zero fatias do agendador após `complete` |

### 4.2 Baseline

Registrado na Fase 0 e versionado no repositório. Atualizar o baseline é um
commit deliberado, revisado, com justificativa — nunca automático.

### 4.3 Frame budget

Além dos números acima, um teste de jank: percorrer 200 páginas em sequência e
verificar que **nenhum** frame passa de 16 ms. É o que valida o agendador com
orçamento ([08](08-concorrencia-cache.md) §2). Uma segunda variante roda com o
cache de `Paragraph` limitado a 1 MB, forçando re-shaping em `paint`
([05](05-render-selecao-a11y.md) §1), e tolera 3 frames acima de 16 ms em 200.

## 5. Modo estrito

Todo teste de corpus roda com `strict: true`
([09](09-erros-diagnosticos.md) §5), exceto os arquivos da Faixa B e do grupo
Patologia, onde a lista **exata** de diagnósticos esperados é parte da assertiva.

Isso impede que uma regressão de parse se disfarce de "degradação aceitável".

## 6. Fuzzing leve

Um teste gera EPUBs sintéticos aleatórios (estrutura válida, conteúdo aleatório
de um gerador de XHTML com todas as tags suportadas, CSS aleatório do
subconjunto) e roda as invariantes 1, 4, 7 e 9 sobre eles, com semente fixa no
CI e semente aleatória em execução local. É barato e acha os bugs de fronteira
(bloco vazio, seção só com imagem, lista sem itens) que o corpus curado não tem.
