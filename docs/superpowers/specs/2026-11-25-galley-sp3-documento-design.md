# Galley — Subprojeto 3: Documento (XHTML → árvore própria)

- **Data:** 2026-11-25
- **Status:** aprovado; implementado na branch `sp3/documento`
- **Documento pai:** `2026-11-24-galley-arquitetura-design.md` (§7 etapa 2, §8 item 3)
- **Depende de:** SP1 (Container) e SP2 (Benchmark), mergeados.

## 1. Intenção

Transformar cada documento de conteúdo do EPUB (XHTML do spine, nav e páginas auxiliares) numa **árvore de documento própria do Galley**: compacta, imutável, barata de transferir entre isolates e organizada para o que vem depois:

- a cascata de CSS (SP4) precisa casar seletores depressa;
- o layout (SP5) precisa percorrer a árvore;
- os recursos de leitura (SP7: CFI, busca, TTS, notas) precisam apontar posições estáveis nela.

## 2. O que a medição mostrou (2026-11-25)

| Corpus | Documentos | Falhas no parser XML estrito |
|---|---|---|
| Público (20 livros) | 1.250 | 0 |
| Gutenberg amplo (300 livros) | 4.064 | 0 |
| Livros privados do mantenedor (56 livros comerciais e de fãs) | 3.014 | 0 |
| Saídas do Calibre (6 conversões, inclusive AZW3 → EPUB) | 434 | 0 |

- **XHTML malformado é raro** nos EPUBs que circulam: as ferramentas de geração (Calibre, Ebookmaker do Gutenberg, Sigil/InDesign) reserializam o conteúdo como XML. A recuperação de erros continua obrigatória (anti-meta do pai: livros malformados abrem sempre que possível), mas é uma **rede de segurança**, não o caminho principal.
- **Construções frequentes:** `epub:type` (2.842 docs), `style=` inline (2.582), tabelas (576), MathML (99), SVG (31), *ruby* (13), `<script>` (1). Doctype: HTML5 (`<!DOCTYPE html>`), XHTML 1.1 ou nenhum.
- **Velocidade do `package:xml` (DOM completo):** 40–70 MB/s; o maior documento (2 MB) em algumas dezenas de ms.

## 3. Metas

1. Árvore própria **compacta**: nós num arranjo (arena), nomes de elemento e de atributo **internados**, texto num buffer compartilhado, poucos objetos por nó.
2. **Fidelidade estrutural** suficiente para o CFI do EPUB: ordem e contagem exatas de filhos elemento e de nós de texto, com o texto original (inclusive espaços em branco) preservado.
3. **Consulta rápida** para o SP4: por id, por classe, por nome de elemento; pais, filhos e irmãos em O(1).
4. **Tolerância:** documento bem formado → caminho rápido. Malformado → recuperação (tags desencontradas fechadas, entidades HTML), com diagnósticos; nunca exceção crua.
5. **Transferível entre isolates** com custo baixo (a etapa roda em isolate, pai §7).
6. **Extração do `<head>`** para o SP4: folhas de estilo ligadas (`<link rel="stylesheet">`, com href resolvido), blocos `<style>` em ordem, `<title>`, `lang` e `dir` do documento.
7. **Benchmark expandido** (pendência permanente do SP2): suítes de parsing de documento e contadores determinísticos.

## 4. Não-metas

- Aplicar CSS, calcular estilos ou decidir o que é bloco ou inline (SP4).
- Layout, pintura ou medição de texto (SP5/SP6).
- Implementar CFI, busca ou TTS (SP7). Esta etapa só garante que a árvore permite implementá-los.
- Executar `<script>`: scripts são preservados na árvore como elementos, mas nunca executados.
- API pública estável: a árvore fica interna (`lib/src/`) até o SP6 definir a API de leitura. *(Chamada minha.)*

## 5. Anti-metas

- Recusar um livro inteiro por causa de um documento malformado.
- Perder conteúdo silenciosamente na recuperação: tudo o que for descartado ou corrigido gera diagnóstico.
- Árvore que obrigue o SP4 a percorrer tudo para casar um seletor simples, ou o SP7 a reconstruir índices de CFI.
- Alocação proporcional a "um objeto Dart por atributo/nó de texto" (o DOM do `package:xml` é o contraexemplo).
- Regressão de desempenho na abertura do livro: o parsing é por documento e sob demanda, nunca na abertura.

## 6. Restrições

- Herdadas do pai e do SP1/SP2: Dart puro; dependências de runtime continuam **só `xml` e `meta`**; só `GalleyException` escapa da API pública; recuperáveis viram `Diagnostic`; comentários e docs em pt-BR; commits em português.
- Etapa executada em isolate (pai §7): a árvore e o parser não podem depender de `dart:ui` nem de Flutter.
- Gates do SP2 valem desde o primeiro PR: instruções (0,5%) e A/B; os benchmarks novos entram no catálogo.

## 7. Abordagens

| Abordagem | Trade-off | Decisão |
|---|---|---|
| A) Tokenizador próprio em uma passada, montando direto a árvore | o mais rápido e enxuto, sem dependência nova; mais trabalho, e o tokenizador precisa ser validado contra o `package:xml` no corpus | adiada: só se o benchmark mostrar o B como gargalo |
| **B) Eventos do `package:xml` (`parseEvents`), montando a árvore compacta** | reaproveita um tokenizador já provado nos 8.780 documentos; pouco código e risco; velocidade limitada pela do `package:xml` | **escolhida pelo usuário** |
| C) DOM do `package:xml` como árvore do Galley | o mais simples; pesado em memória (objeto por nó/atributo), sem controle do formato para CSS e CFI | descartada |
| D) `package:html` (parser HTML5) | dependência nova, mais lento, trata namespaces e `epub:type` de forma estranha | descartada |

Decisão do usuário (2026-11-25): **B**; se um dia virar gargalo, o tokenizador é reescrito (caminho A) por trás da mesma interface do montador.

## 8. Desenho

### 8.1 Pipeline da etapa

```
bytes do recurso (EpubBook.resource)
  └─► decodeText (SP1)
        └─► parseEvents do package:xml
              ├─ caminho estrito: validateNesting + validateDocuments ligados
              └─ em XmlException: recomeça em modo tolerante
                   (validateNesting/validateDocuments desligados, entidades HTML5)
                   e o montador repara a estrutura, emitindo diagnósticos
        └─► montador → DocumentTree (arena compacta, imutável)
```

- O caminho estrito e o tolerante usam o **mesmo montador**. A única diferença é a política de reparo.
- **Entidades:** HTML5 completas (`XmlDefaultEntityMapping.html5()`) nos dois caminhos, porque é barato e cobre `&nbsp;` e afins em XHTML sem DTD. *(Chamada minha.)*
- **Descartados, com contagem em diagnóstico de nível info:** comentários, instruções de processamento (exceto a declaração XML) e o doctype.

### 8.2 Forma da árvore (`DocumentTree`)

Arena de nós em arranjos tipados, índices `int` como identidade de nó:

- **Por nó:** tipo (elemento ou texto), índice do pai, primeiro filho, próximo irmão, irmão anterior, e o índice do nome internado (elementos) ou a faixa no buffer de texto (texto).
- **Nomes:** tabela de interning por documento, compartilhada entre nomes de elemento, nomes de atributo e namespaces. Os namespaces conhecidos (XHTML, `epub:`/OPS, SVG, MathML, XML, XLink) têm ids fixos.
- **Atributos:** arranjo plano por elemento (faixa início/fim), com nome internado e valor no buffer de texto. Acesso direto a `id`, `class` (já quebrado em tokens internados), `epub:type` (tokens), `lang`/`xml:lang`, `dir`, `style` (string bruta, que o SP4 interpreta), `href`/`src`.
- **Texto:** buffer único (`String` ou `Uint16List` do documento todo). Nós de texto guardam a faixa. O texto é preservado como no original depois da decodificação de entidades, inclusive espaços. Nós de texto adjacentes são fundidos (CDATA vira texto), coerente com o CFI.
- **Índices prontos para o SP4:** id → nó, classe → lista de nós, nome de elemento → lista de nós.
- **Transferência entre isolates:** a árvore é feita só de arranjos tipados e strings, e é enviada por `SendPort`/`Isolate.exit` sem reconstrução. O formato exato (por exemplo `TransferableTypedData`) fica para o construtor, medido no benchmark.
- **Imutável depois de montada.** Não há API de mutação.

### 8.3 Extração do `<head>` (`DocumentHead`)

- **Folhas de estilo**, em ordem de documento: `<link rel="stylesheet">` (href resolvido para o caminho no zip com `resolveHref` do SP1; `media` e `title` preservados) e `<style>` (texto bruto, `media`).
- **Outros campos:** `<title>`, `lang` e `dir` do `<html>`, e as `<meta>` relevantes (`viewport`, para o layout fixo do SP8).
- **Fora do `<head>`:** um `<link>` ou `<style>` no `<body>` também é coletado (navegadores aceitam), com diagnóstico de nível info.

### 8.4 Recuperação de documentos malformados

Política do montador no modo tolerante:

- **Fechamento sem abertura correspondente:** fecha os elementos abertos até o correspondente, ou descarta o fechamento se não houver nenhum.
- **Fim do documento:** fecha tudo o que ficou aberto.
- **Elementos vazios do HTML** (`br`, `img`, `hr`, `meta`, `link`, `input` etc.) sem `/>`: tratados como vazios.
- **Texto ou elementos fora de `<html>`/`<body>`:** envolvidos num `<body>` sintético.
- **Atributo duplicado:** o primeiro vence.

Cada reparo gera um `Diagnostic` com código estável (por exemplo `document.unclosedElement`, `document.strayEndTag`, `document.recovered`) e a localização (caminho do recurso e linha).

Um documento irrecuperável vira uma árvore com um único `<body>` vazio e o diagnóstico `document.unparseable` (error). O livro continua abrindo, e o capítulo aparece vazio. Irrecuperável é só o documento vazio ou só com espaços (ou sem nenhum conteúdo além de comentários, PIs e doctype); um documento só com texto, sem elementos, vira esse texto dentro de `html`/`body` virtuais, com `document.recovered`.

### 8.5 Onde a etapa se encaixa

- **Feature nova:** `lib/src/features/document/`, com as camadas `data` (montador, adaptador de eventos do `package:xml`) e `domain` (`DocumentTree`, `DocumentHead`, consultas).
- **Ponto de entrada interno:** `Future<ParsedDocument> parseDocument(EpubBook book, String path, {DiagnosticSink? sink})`. Lê `book.resource(path)`, decodifica e monta. *(Nome final no plano.)*
- **Sem efeito na abertura:** o `EpubBook` continua sem parsear nada ao abrir. O parsing é sob demanda, por documento.

### 8.6 Benchmark (expansão obrigatória)

- **Suítes micro**, entrando no catálogo e passando a valer nos gates:
  - montagem a partir de um documento grande sintético (~2 MB, com tabelas, *ruby*, MathML, `style=` e `epub:type`);
  - consulta por id e por classe;
  - montagem em modo tolerante de um documento malformado sintético.
- **Suítes macro:** parsear todos os documentos do spine de cada livro `hm/*`.
- **Comparação informativa** (modo `compare`, sem gate): o nosso montador contra o DOM do `package:xml` (`XmlDocument.parse`) nos mesmos documentos, em tempo e memória de pico. É o número que justifica a árvore própria e mostra quando o caminho A valeria a pena.
- **Contadores determinísticos nos testes:** a memória da árvore (bytes dos arranjos) por KB de XHTML fica abaixo de um teto calibrado na primeira medição.
- **Robustez:** o modo `wide` (300 livros do Gutenberg) passa a também parsear todos os documentos do spine. Um `crashed` (exceção não-`GalleyException`) reprova.

### 8.7 Testes

- **Documentos sintéticos por comportamento:** namespaces (`epub:type`, SVG, MathML), entidades, CDATA, espaços em branco preservados, `<head>` completo, `<link>`/`<style>` no body.
- **Cada regra de recuperação** da §8.4, com o diagnóstico esperado.
- **Fuzz:** XHTML mutado (truncado, tags trocadas, bytes aleatórios) só pode gerar diagnósticos ou árvores, nunca exceção crua nem travamento.
- **Diferencial contra o `package:xml`** nos corpora público e Gutenberg: para cada documento, a sequência de elementos, atributos e texto da nossa árvore precisa bater com a do DOM do `package:xml`.

## 8.8 Decisões após a revisão do construtor *(chamadas minhas)*

- **Comportamento verificado do `package:xml` 6.6.1** (`parseEvents` não validante, com entidades HTML5): aceita atributo sem aspas, atributo sem valor (chega vazio), `&` solto, entidade desconhecida (fica literal), atributo duplicado (os dois chegam; o montador fica com o primeiro) e tags trocadas. **Exceção:** `<` dentro de texto lança `XmlParserException`. O montador captura, devolve o `<` ao texto, retoma a leitura e emite `document.markupAsText` (código próprio do reparo; `document.recovered` sai uma vez por documento, quando o caminho estrito falha).
- **Isolate.** O SP3 entrega uma função **pura e segura para isolate**, sem `EpubBook` nem callback: `ParsedDocument parseDocumentBytes(Uint8List bytes, {required String path})`, que devolve a árvore e a **lista de diagnósticos** como dados. A orquestração do isolate (ler bytes no isolate principal ou num isolate com o próprio `EpubBook`, repassar diagnósticos ao sink) fica para o SP6, onde nasce o pipeline de leitura. No SP3: um atalho `parseDocument(EpubBook, path, {sink})`, que roda no isolate atual e repassa os diagnósticos, e um benchmark do custo de enviar uma `ParsedDocument` entre isolates.
- **CFI.** A árvore segue a **especificação EPUB CFI** sobre o DOM XML do documento, o que garante compatibilidade com outros leitores que seguem a especificação.
  - Elementos ocupam as posições pares.
  - Sequências contíguas de conteúdo não-elemento (texto, CDATA, e o texto em volta de comentários descartados) formam **um** bloco de texto, e a fusão é feita assim.
  - Só os nós sintéticos criados pela recuperação (o `<html>` e o `<body>` sintéticos) são marcados **virtuais** e ficam fora da contagem do CFI. Elementos fechados implicitamente existem no documento e são nós reais.
  - O índice de CFI é calculado sob demanda no SP7, não guardado.
- **Alcance do modo tolerante:** XML com defeitos mais os "vícios de HTML" mais comuns.
  - Nomes de tag sem diferença de maiúsculas no fechamento.
  - Fechamento implícito de `p`, `li`, `dt`/`dd`, `tr`, `td`/`th`, `option` (as regras de "end tag omitida" do HTML).
  - Conteúdo de `<script>` e `<style>` como texto bruto até o fechamento.
  - Elementos vazios do HTML.
  - **Um construtor de árvore HTML5 completo fica fora:** com 0 documentos malformados em 8.780, o custo não se justifica. Um documento muito quebrado ainda abre, com estrutura aproximada e diagnósticos.
- **Namespaces:** pilha própria de declarações. Os nomes são resolvidos para (namespace, nome local), e os índices e o SP4 usam essa chave.
  - Prefixo `epub:` sem declaração cai no namespace OPS, com diagnóstico info `document.undeclaredPrefix`.
  - Qualquer prefixo ligado ao XHTML (ex.: `<html:p>`) é tratado como XHTML.
  - Um prefixo desconhecido sem declaração mantém o nome com prefixo, num namespace "desconhecido".
  - Raiz sem `xmlns` padrão (nos dois caminhos, estrito e tolerante): recebe o namespace XHTML, ou SVG se o nome local da raiz é `svg`, herdado pelos descendentes sem prefixo como se estivesse declarado, com diagnóstico info `document.impliedNamespace` (no `text/html`, sem diagnóstico). Assim o mesmo documento dá o mesmo `<head>` e os mesmos nomes com ou sem um erro de sintaxe. O diferencial contra o DOM do `package:xml` aplica a mesma regra.
- **Documentos no escopo:** todo item do manifest com media-type `application/xhtml+xml`, `text/html` (sempre pelo modo tolerante) ou `image/svg+xml` (documento SVG no spine, com raiz no namespace SVG). Outros tipos não passam por este parser.
- **Onde roda cada verificação:**
  - **A cada PR:** testes sintéticos, testes de recuperação, fuzz e os benchmarks do catálogo (livros `hm/*`), sem rede.
  - **Diferencial contra o DOM do `package:xml`:** corpus público (espelho `corpus-v1`, com cache) no **job noturno** e no modo `local`. Documentos que caíram no modo tolerante ficam fora do diferencial, contados à parte.
  - **`wide` com parsing completo:** só no noturno, como hoje.

## 9. Decisões do usuário (registradas)

- Caminho B (eventos do `package:xml` + árvore compacta própria). Reescrever o tokenizador (caminho A) só se o benchmark mostrar gargalo.
- A medição do próprio corpus privado (anonimizada) serviu de base para tratar a recuperação de erros como rede de segurança.

## 10. Chamadas minhas (para revisão)

- Árvore interna até o SP6 (sem API pública nova agora).
- Entidades HTML5 sempre ligadas, nos dois caminhos.
- Comentários, PIs e doctype descartados (com contagem em diagnóstico info).
- Regras de recuperação da §8.4 e o comportamento de documento irrecuperável (capítulo vazio + diagnóstico).
- Comparação informativa contra o DOM do `package:xml`.
- Todas as decisões da §8.8 (isolate, CFI conforme a especificação, alcance do modo tolerante, namespaces, documentos no escopo, onde roda cada verificação).

## 11. O que fica para o construtor

- Layout exato dos arranjos e formato de transferência entre isolates.
- Nomes finais de tipos e funções, e códigos de diagnóstico.
- Tamanho e conteúdo dos documentos sintéticos.
- Calibragem do teto de memória por KB de XHTML.
