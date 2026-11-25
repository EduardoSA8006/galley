# Galley SP3 — Documento (XHTML → árvore própria) — Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transformar documentos XHTML/HTML/SVG do EPUB numa árvore compacta própria (arena de arranjos tipados, nomes internados, índices para CSS), com extração do `<head>`, recuperação de documentos malformados, entrada segura para isolate e expansão do benchmark.

**Architecture:** `package:xml` em modo de eventos (`parseEvents`) alimenta um montador próprio. Primeiro tenta o caminho estrito (validando); se falhar, ou se o media-type for `text/html`, usa o modo tolerante, em que o montador repara a estrutura e emite diagnósticos. O resultado é um `ParsedDocument` só com dados (árvore, head, diagnósticos), transferível entre isolates.

**Tech Stack:** Dart puro, `xml` (eventos, entidades HTML5), `meta`. Benchmark: pacote `benchmark/` (SP2).

**Spec:** `docs/superpowers/specs/2026-11-25-galley-sp3-documento-design.md` (pai: `2026-11-24-galley-arquitetura-design.md`)

## Global Constraints

- Dependências de runtime do `galley`: **somente `xml` e `meta`**.
- Dart puro, sem `dart:ui`/Flutter na etapa (ela roda em isolate).
- Só `GalleyException` escapa da API pública. Problemas recuperáveis viram `Diagnostic`, e nenhuma exceção crua sai do parser.
- A árvore é interna (`lib/src/features/document/`). Nada novo em `lib/galley.dart`.
- Árvore imutável depois de montada, feita só de arranjos tipados e strings (transferível por `SendPort`/`Isolate.exit`).
- O CFI segue a especificação EPUB:
  - elementos ocupam as posições pares;
  - texto contíguo, incluindo CDATA e o texto em volta de comentários descartados, forma um único nó de texto;
  - nós criados pela recuperação são marcados `virtual`.
- Entidades HTML5 (`XmlDefaultEntityMapping.html5()`) nos dois caminhos.
- Comentários, PIs e doctype são descartados, com contagem num diagnóstico info.
- Os gates do SP2 valem: instruções (0,5%) e A/B; os benchmarks novos entram no catálogo.
- Comentários e docs em pt-BR; commits em português `tipo(escopo): descrição`.

## Review Focus

1. **Aninhamento patológico** (10.000 níveis) e documento de 2 MB: nada de recursão, sem estouro de pilha na montagem nem nos percursos (testes nas Tasks 1 e 5).
2. **Documento com BOM UTF-16 ou declaração latin1:** decodificado pelo `decodeText` do SP1, e a árvore sai correta (Task 3).
3. **Atributos com namespace** (`xml:lang`, `xlink:href` em `<svg:image>`, `epub:type`) resolvidos e acessíveis pela chave (namespace, nome local) (Task 3).
4. **Documento vazio, só espaços ou só um doctype:** vira o caminho "irrecuperável", com `<body>` virtual vazio e `document.unparseable`, sem exceção (Task 5).
5. **`id` duplicado:** o índice por id fica com o primeiro na ordem do documento, e não há exceção (Task 2).

---

## Estrutura de arquivos

```
lib/src/features/document/
  domain/names.dart            # Namespaces (ids fixos), NameTable, TokenTable
  domain/document_tree.dart    # DocumentTree (arena imutável) + leitura
  domain/tree_builder.dart     # TreeBuilder (montagem incremental, sem recursão)
  domain/document_head.dart    # DocumentHead, StyleSheetRef
  domain/parsed_document.dart  # ParsedDocument
  data/event_adapter.dart      # parseEvents → TreeBuilder (estrito e tolerante), pilha de namespaces
  data/recovery.dart           # regras de reparo do modo tolerante
  data/head_extractor.dart     # extração do <head>
  data/parse_document.dart     # parseDocumentBytes / parseDocument
lib/src/core/diagnostics/diagnostic_codes.dart   # códigos document.*
test/features/document/...
benchmark/lib/src/suites/document_suites.dart
benchmark/lib/src/modes/docdiff.dart
```

---

### Task 1: Nomes internados, `DocumentTree` e `TreeBuilder`

**Files:**
- Create: `lib/src/features/document/domain/names.dart`, `lib/src/features/document/domain/document_tree.dart`, `lib/src/features/document/domain/tree_builder.dart`
- Test: `test/features/document/domain/tree_builder_test.dart`

**Interfaces:**
- Produces:
  - `abstract final class Namespaces { static const int none = 0, xhtml = 1, ops = 2, svg = 3, mathml = 4, xml = 5, xlink = 6, xmlns = 7; static int idForUri(String? uri); static String? uriOf(int id); }`
    - URIs: `http://www.w3.org/1999/xhtml`, `http://www.idpf.org/2007/ops`, `http://www.w3.org/2000/svg`, `http://www.w3.org/1998/Math/MathML`, `http://www.w3.org/XML/1998/namespace`, `http://www.w3.org/1999/xlink`, `http://www.w3.org/2000/xmlns/`.
    - URIs desconhecidas recebem ids ≥ 64, atribuídos por documento através da `NameTable`.
  - `final class NameTable` (por documento):
    - `int intern(int namespace, String localName)`
    - `int namespaceOf(int nameId)`
    - `String localNameOf(int nameId)`
    - `int? lookup(int namespace, String localName)`
    - `int internNamespace(String uri)`, para URIs desconhecidas.
  - `final class TokenTable`: `int intern(String token)`, `String tokenOf(int id)`, `int? lookup(String)`. Usada para os tokens de `class` e de `epub:type`.
  - `enum NodeKind { document, element, text }`
  - `final class DocumentTree`:
    - **Estrutura:** `int get documentNode` (sempre 0), `int get nodeCount`, `NodeKind kindOf(int n)`, `int parentOf(int n)` (−1 se não houver), `int firstChildOf(int n)`, `int nextSiblingOf(int n)`, `int previousSiblingOf(int n)`, `Iterable<int> childrenOf(int n)`, `bool isVirtual(int n)`.
    - **Elementos:** `int nameOf(int element)`, `String localNameOf(int element)`, `int namespaceOf(int element)`.
    - **Texto:** `String textOf(int textNode)`.
    - **Atributos:** `int attributeCountOf(int element)`, `String? attribute(int element, int namespace, String localName)`, `Iterable<({int name, String value})> attributesOf(int element)`.
    - **Tabelas e memória:** `NameTable get names`, `TokenTable get tokens`, `int get retainedBytes` (soma dos bytes dos arranjos tipados e do texto em UTF-16).
  - `final class TreeBuilder`:
    - `void startElement(int nameId, {bool virtual = false})`
    - `void attribute(int nameId, String value)` (só antes do primeiro filho)
    - `void text(String data)` (funde com o texto imediatamente anterior)
    - `void endElement()`
    - `int get depth`
    - `int get openElementName`
    - `DocumentTree build()`: lança `StateError` se `depth > 0`, porque fechar os elementos abertos é responsabilidade do montador e um elemento aberto aqui é erro de programação.
  - Representação: arranjos `Int32List` crescentes (pai, primeiro filho, próximo e anterior irmão, tipo/flags, nome ou início do texto, fim do texto, início e fim dos atributos); texto num `StringBuffer` congelado em `String` no `build`. Nenhuma recursão.

- [ ] **Step 1: Testes que falham**
  - `<html><body><p>a</p>b</body></html>` montado via builder: os percursos `childrenOf`, `parentOf`, `nextSiblingOf` e `previousSiblingOf` estão corretos, e `textOf` devolve `'a'` e `'b'`.
  - `text('a'); text('b')` seguidos geram **um** nó com `'ab'`.
  - Elemento `virtual` preserva a flag.
  - O mesmo nome internado duas vezes devolve o mesmo id.
  - `Namespaces.idForUri(xhtml) == Namespaces.xhtml` e `uriOf` faz o caminho inverso.
  - 10.000 níveis de aninhamento montam e percorrem (iterativamente, no teste) sem estouro.
  - `retainedBytes > 0` e cresce de forma monotônica com o tamanho.
  - `build()` com elemento aberto lança `StateError`.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar. **Step 4:** PASS (`flutter test test/features/document`).
- [ ] **Step 5: Commit** `feat(document): árvore compacta com nomes internados e montador`

---

### Task 2: Índices de consulta (id, classe, nome, `epub:type`)

**Files:**
- Modify: `lib/src/features/document/domain/document_tree.dart`, `lib/src/features/document/domain/tree_builder.dart`
- Test: `test/features/document/domain/document_queries_test.dart`

**Interfaces:**
- Produces (em `DocumentTree`), com índices montados no `build`:
  - `String? idOf(int element)`
  - `int? elementById(String id)`: o primeiro elemento com esse id, na ordem do documento.
  - `List<int> classesOf(int element)`: ids de tokens.
  - `List<int> elementsWithClass(String className)`: na ordem do documento.
  - `List<int> elementsNamed(int namespace, String localName)`: na ordem do documento.
  - `List<String> epubTypesOf(int element)`: tokens de `epub:type`, no namespace OPS.
- Regras:
  - `class` e `epub:type` são separados por espaços em branco ASCII.
  - A lista de classes de um elemento não repete tokens.
  - `id` vazio é ignorado.

- [ ] **Step 1: Testes que falham**
  - `elementById('n1')` acha o elemento certo.
  - Com dois elementos `id="dup"`, devolve o primeiro.
  - `class=" a  b a "` resulta em `classesOf` = [a, b].
  - `elementsWithClass('b')` vem na ordem do documento.
  - `elementsNamed(Namespaces.xhtml, 'p')` vem na ordem do documento.
  - `epub:type="noteref chapter"` resulta em ['noteref', 'chapter'].
  - Busca por id ou classe inexistente devolve `null` ou `[]`.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar. **Step 4:** PASS.
- [ ] **Step 5: Commit** `feat(document): índices por id, classe, nome e epub:type`

---

### Task 3: Caminho estrito — eventos do `package:xml`, namespaces e texto

**Files:**
- Create: `lib/src/features/document/data/event_adapter.dart`, `lib/src/features/document/domain/parsed_document.dart`, `lib/src/features/document/data/parse_document.dart`
- Modify: `lib/src/core/diagnostics/diagnostic_codes.dart`
- Test: `test/features/document/data/parse_strict_test.dart`

**Interfaces:**
- Consumes: `TreeBuilder`, `NameTable` (Tasks 1–2); `decodeText` (SP1, `lib/src/features/container/data/text/decode_text.dart`).
- Produces:
  - `final class ParsedDocument`: `final DocumentTree tree`, `final DocumentHead head`, `final List<Diagnostic> diagnostics` (não modificável), `final bool recovered`.
    - O head fica com um placeholder vazio até a Task 4. Crie `DocumentHead.empty` em `domain/document_head.dart` já nesta task.
  - `ParsedDocument parseDocumentBytes(Uint8List bytes, {required String path, String mediaType = 'application/xhtml+xml'})`. Nesta task, só o caminho estrito; em `XmlException`, a Task 5 assume.
  - Códigos de diagnóstico:
    - `document.droppedNodes` (info): contagem de comentários, PIs e doctype na mensagem;
    - `document.undeclaredPrefix` (info);
    - `document.recovered` (warning);
    - `document.strayEndTag` (warning);
    - `document.unclosedElement` (warning);
    - `document.duplicateAttribute` (info);
    - `document.unparseable` (error);
    - `document.headInBody` (info).
- Regras do adaptador:
  - `parseEvents(text, entityMapping: XmlDefaultEntityMapping.html5(), validateNesting: true, validateDocuments: true)`.
  - Pilha própria de declarações `xmlns` e `xmlns:p`.
  - Os nomes viram (namespace, nome local).
  - O prefixo `epub:` sem declaração cai em OPS, com `document.undeclaredPrefix`.
  - O prefixo `xml:` cai sempre no namespace XML.
  - Atributos sem prefixo ficam em `Namespaces.none`.
  - Declarações `xmlns*` **não** viram atributos da árvore.
  - CDATA vira texto.
  - Comentário, PI e doctype são descartados e contados. O texto ao redor de um comentário descartado é fundido, porque o builder funde texto adjacente.

- [ ] **Step 1: Testes que falham**
  - XHTML com `xmlns`, `xmlns:epub` e `epub:type`: elemento no namespace XHTML e atributo `epub:type` no namespace OPS.
  - Sem `xmlns:epub`: mesmo resultado, mais `document.undeclaredPrefix`.
  - `<html:p>` com `xmlns:html` ligado ao XHTML vira `p` XHTML.
  - `<svg:image xlink:href="a.png"/>` tem `attribute(el, Namespaces.xlink, 'href') == 'a.png'`.
  - `xml:lang="ja"` é acessível por `Namespaces.xml`.
  - `&nbsp;` vira U+00A0.
  - CDATA é fundido com o texto vizinho.
  - `a<!-- c -->b` gera um único nó de texto `'ab'` e `document.droppedNodes`.
  - Espaços e quebras de linha entre elementos são preservados como nós de texto.
  - Bytes com BOM UTF-16 geram a mesma árvore que os UTF-8.
  - Documento de 2 MB sintético (gerado no teste) monta sem erro.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar. **Step 4:** PASS.
- [ ] **Step 5: Commit** `feat(document): leitura estrita via eventos do package:xml com namespaces`

---

### Task 4: Extração do `<head>`

**Files:**
- Create: `lib/src/features/document/data/head_extractor.dart`
- Modify: `lib/src/features/document/domain/document_head.dart`, `lib/src/features/document/data/parse_document.dart`
- Test: `test/features/document/data/head_test.dart`

**Interfaces:**
- Consumes: `DocumentTree`, `resolveHref` (SP1, `lib/src/features/container/data/path/epub_path.dart`).
- Produces:
  - `sealed class StyleSheetRef`, com as variantes `final class LinkedStyleSheet extends StyleSheetRef { final String path; final String? media; final String? title; }` e `final class InlineStyleSheet extends StyleSheetRef { final String css; final String? media; }`.
  - `final class DocumentHead { final List<StyleSheetRef> styleSheets; final String? title; final String? lang; final String? dir; final String? viewport; static const empty; }`
  - `DocumentHead extractHead(DocumentTree tree, {required String documentPath, required DiagnosticSink sink})`
- Regras:
  - As folhas de estilo seguem a ordem do documento.
  - `<link>` entra se `rel` contém o token `stylesheet`, sem diferenciar maiúsculas; o href é resolvido para um caminho no zip. Um href externo ou que escapa do zip é ignorado, com diagnóstico info `document.externalStyleSheet` (código novo).
  - `<style>` guarda o texto bruto.
  - `<link>`/`<style>` dentro do `<body>` são coletados, com `document.headInBody`.
  - `lang` vem de `<html lang>` ou de `xml:lang`, nessa ordem de preferência.
  - `viewport` vem de `<meta name="viewport" content>`.

- [ ] **Step 1: Testes que falham**
  - Três folhas (link, style, link) aparecem em ordem.
  - `href="../css/a.css"` a partir de `OEBPS/text/c1.xhtml` resolve para `OEBPS/css/a.css`.
  - `rel="alternate stylesheet"` conta como folha de estilo.
  - `<style media="print">` preserva o `media`.
  - `<link>` no `<body>` é coletado e gera `document.headInBody`.
  - `title`, `lang` (os dois casos) e `dir` são lidos.
  - `viewport="width=600, height=800"` é lido.
  - `href="http://x/y.css"` é ignorado e gera o diagnóstico.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar. **Step 4:** PASS.
- [ ] **Step 5: Commit** `feat(document): extração de folhas de estilo, título, idioma e viewport`

---

### Task 5: Modo tolerante e recuperação

**Files:**
- Create: `lib/src/features/document/data/recovery.dart`
- Modify: `lib/src/features/document/data/event_adapter.dart`, `lib/src/features/document/data/parse_document.dart`
- Test: `test/features/document/data/recovery_test.dart`

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces:
  - Em `parseDocumentBytes`, o modo tolerante entra quando:
    - o caminho estrito lança `XmlException`, emitindo `document.recovered` com a linha do erro original;
    - **ou** o `mediaType` é `text/html`, sem diagnóstico de recuperação.
  - `ParsedDocument.recovered == true` no modo tolerante.
- Regras (spec §8.4 e §8.8), cada uma com diagnóstico:
  - `parseEvents(..., validateNesting: false, validateDocuments: false)`.
  - Captura `XmlParserException` no meio do fluxo: devolve `<` ao texto e retoma depois do caractere problemático.
  - Fechamento sem abertura correspondente: fecha até o correspondente (`document.unclosedElement` para cada elemento fechado implicitamente) ou descarta o fechamento (`document.strayEndTag`).
  - A comparação de nomes no fechamento ignora maiúsculas.
  - Fechamento implícito de `p` (ao abrir um bloco HTML: `p`, `div`, `ul`, `ol`, `table`, `h1`–`h6`, `pre`, `blockquote`, `section`, `article`, `aside`, `header`, `footer`, `nav`, `figure`, `hr`), de `li` ao abrir `li`, de `dt`/`dd` ao abrir `dt`/`dd`, de `tr` ao abrir `tr`, de `td`/`th` ao abrir `td`/`th`/`tr` e de `option` ao abrir `option`.
  - Elementos vazios do HTML (`area`, `base`, `br`, `col`, `embed`, `hr`, `img`, `input`, `link`, `meta`, `source`, `track`, `wbr`) são fechados na hora.
  - `<script>`/`<style>`: o conteúdo é texto bruto até o fechamento correspondente.
  - Atributo duplicado: o primeiro vence, com `document.duplicateAttribute`.
  - Fim do documento: fecha tudo, com `document.unclosedElement`.
  - Conteúdo fora de `<html>`/`<body>` é envolvido em elementos `html`/`body` **virtuais**.
  - Documento vazio, só espaços ou sem elemento: árvore `html > body` virtuais vazios, com `document.unparseable`.
  - Nenhuma exceção não-`GalleyException` escapa: qualquer erro inesperado no montador vira `document.unparseable`.

- [ ] **Step 1: Testes que falham**, um por regra, verificando a árvore e o código do diagnóstico:
  - `<p>a<p>b` resulta em dois `p` irmãos.
  - `<ul><li>a<li>b</ul>`.
  - `<table><tr><td>1<td>2<tr><td>3</table>`.
  - `<P>x</p>`.
  - `a < b` no texto.
  - `<br>` sem barra.
  - `<script>if (a<b) {}</script>`.
  - `id="1" id="2"` fica com o primeiro.
  - `</div>` solto.
  - `<div><span>` sem fechar.
  - Texto antes de `<html>` vai para dentro do `body` virtual.
  - `''` e `'   '` caem no caminho irrecuperável.
  - `text/html` bem formado não gera `document.recovered`, mas `recovered == true`.
  - Um documento bem formado **não** passa pelo modo tolerante.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar. **Step 4:** PASS.
- [ ] **Step 5: Commit** `feat(document): modo tolerante com recuperação e diagnósticos`

---

### Task 6: Entrada pelo `EpubBook`, documentos SVG, isolate e fuzz

**Files:**
- Modify: `lib/src/features/document/data/parse_document.dart`
- Test: `test/features/document/data/parse_document_test.dart`, `test/features/document/fuzz_test.dart`

**Interfaces:**
- Consumes: `EpubBook` (SP1: `resource(path)`, `manifestItemByPath(path)`), Tasks 1–5.
- Produces:
  - `Future<ParsedDocument> parseDocument(EpubBook book, String path, {DiagnosticSink? sink})`:
    - lê os bytes e usa o media-type do manifest (padrão `application/xhtml+xml`);
    - repassa os diagnósticos ao `sink`;
    - um media-type fora de XHTML, HTML e SVG lança `ArgumentError`, porque é erro de programação do chamador e não da entrada.
  - Documento `image/svg+xml`: raiz `svg` no namespace SVG, sem `head`/`body` sintéticos.

- [ ] **Step 1: Testes que falham**
  - Um EPUB do `buildEpub` (test/support) com capítulo XHTML, capítulo `text/html` e item SVG no spine: `parseDocument` em cada um dá a raiz e o modo esperados, e os diagnósticos chegam ao sink.
  - `await Isolate.run(() => parseDocumentBytes(bytes, path: p))` devolve uma árvore igual à montada no isolate atual. A comparação percorre a árvore e compara tipo, nome, atributos e texto.
  - Fuzz com `Random(42)` e 2.000 variações de um XHTML válido (truncar, trocar bytes, apagar `<` e `>`, duplicar tags): cada variação devolve um `ParsedDocument` em menos de 2 s, nunca lança, e a árvore resultante sempre tem raiz `html` ou `svg`.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar. **Step 4:** PASS (`flutter test`, suíte toda).
- [ ] **Step 5: Commit** `feat(document): entrada pelo EpubBook, documentos SVG, isolate e fuzz`

---

### Task 7: Benchmark — suítes, comparação com o DOM do `package:xml` e teto de memória

**Files:**
- Create: `benchmark/lib/src/suites/document_suites.dart`
- Modify: `benchmark/lib/src/catalog.dart`, `benchmark/lib/src/modes/compare.dart` (ou um adaptador novo de comparação), `benchmark/README.md` (checklist de expansão: SP3 ✅)
- Create (galley): `test/features/document/memory_counter_test.dart`
- Test: `benchmark/test/suites_document_test.dart`

**Interfaces:**
- Consumes: `parseDocumentBytes`; a geração de corpus do SP2 (`buildHandmadeCorpus`).
- Produces:
  - Ids no catálogo, cada um com ciclo de 10–50 ms nativos, calibrado:
    - `document/build-large-2mib`: XHTML sintético de ~2 MB com tabelas, *ruby*, MathML, `style=` e `epub:type`, gerado de forma determinística no `setUp`;
    - `document/query-id-class`;
    - `document/build-tolerant`: documento malformado sintético;
    - `document/transfer-large`: custo de `Isolate.run` devolvendo a `ParsedDocument` de 2 MB;
    - `document/parse-spine-<hm-id>`: todos os documentos do spine de cada livro `hm/*` não malformado.
  - Comparação informativa (sem gate): o nosso `parseDocumentBytes` contra `XmlDocument.parse` (DOM do `package:xml`), com `wall-time-ns` e `peak-rss-bytes` nos documentos dos livros `hm/*` e do 2 MB. Entra no modo `compare` como um par "concorrente" à parte, com ids `compare/xml-dom/...` e `compare/galley-document/...`.
  - Teto de memória (teste do galley): `tree.retainedBytes / bytesDoXhtml <= K`, com K calibrado na primeira medição (medido × 1,25) e congelado como constante nomeada, com comentário registrando o valor medido.

- [ ] **Step 1: Testes que falham**
  - Os ids novos existem e são únicos.
  - Duas execuções dão o mesmo checksum, diferente de 0.
  - O teste de teto de memória passa.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar e calibrar. Rodar `compare` localmente e anexar ao relatório a tabela nosso × DOM. **Step 4:** PASS (`cd benchmark && dart test -x slow`; `flutter test`).
- [ ] **Step 5: Commit** `feat(benchmark): suítes de documento, comparação com o DOM do package:xml e teto de memória`

---

### Task 8: Diferencial no corpus público, `wide` com parsing e CI noturno

**Files:**
- Create: `benchmark/lib/src/modes/docdiff.dart`
- Modify: `benchmark/tool/bench.dart`, `benchmark/lib/src/modes/wide.dart`, `.github/workflows/bench-nightly.yml`, `benchmark/README.md`, `docs/superpowers/specs/2026-11-24-galley-arquitetura-design.md` (§8: SP3 concluído quando mergeado — **não** marcar agora; só acrescentar a nota de que o diferencial roda no noturno)
- Test: `benchmark/test/modes/docdiff_test.dart`, `benchmark/test/modes/wide_test.dart`

**Interfaces:**
- Consumes: `CorpusFetcher` + manifest (SP2), `parseDocumentBytes`.
- Produces:
  - Modo `docdiff`: para cada documento do spine dos livros do manifest público, compara a sequência de eventos da nossa árvore com a do DOM do `package:xml`.
    - Sequência: entrar elemento (namespace, nome local, atributos ordenados, sem `xmlns*`), texto (fundido) e sair elemento.
    - Documentos que caíram no modo tolerante ficam fora da comparação e são contados à parte.
    - A saída é um relatório com o total, quantos bateram, as divergências (os 10 primeiros com o caminho do documento e o primeiro evento divergente) e quantos foram para o modo tolerante, mais um BMF `docdiff/mismatch` (contagem).
    - Exit 1 se houver divergência.
  - `wide`: depois de abrir cada livro, parseia todos os documentos do spine com `parseDocumentBytes`. Uma exceção não-`GalleyException` classifica o livro como `crashed` (exit 1). Um documento que caiu no modo tolerante não reprova e é contado.
  - `bench-nightly.yml`: job `docdiff`, com cache do corpus público igual ao do `compare` e upload ao Bencher no testbed `github-ubuntu-nightly`. O `wide` já roda o parsing por causa da mudança acima. Este job **reprova** o noturno se houver divergência.

- [ ] **Step 1: Testes que falham**
  - `docdiff` em dois documentos idênticos: 0 divergências.
  - Num documento em que a nossa árvore difere (injetada por um montador falso no teste): 1 divergência, com o evento divergente indicado.
  - Um documento malformado conta como tolerante e fica fora da comparação.
  - `wide` com um parser falso que lança `StateError` resulta em `crashed`.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar. Rodar `docdiff` localmente no corpus público (o cache `.corpus-cache` já existe) e anexar o resumo; rodar `wide` local (cache `pg-wide`). Divergência real é bug: corrigir no montador (Tasks 3–5), com teste de regressão. **Step 4:** PASS. Validar o YAML com `actionlint`.
- [ ] **Step 5: Commit** `feat(benchmark): diferencial de documentos contra o package:xml e parsing no wide`

---

## Notas de execução

- Branch `sp3/documento` a partir da `main` (que exige PR e checks `instructions` e `ab`).
- Ordem: Tasks 1 → 8.
- Os benchmarks novos entram nos gates a partir da Task 7. Como a `main` ainda não os tem, aparecem como `added`.
- A Task 8 mexe em workflow: segue as regras de segurança do SP2 (permissões mínimas e nada de interpolação insegura).
