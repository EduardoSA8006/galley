# 06 — Locator, navegação e metadados

**Decisão 6.1: Readium Locator. Decisão 6.2: reparar e sinalizar.
Emenda 14: notas de rodapé.**

## 1. Formato do locator

Adotamos o [Readium Locator](https://readium.org/architecture/models/locators/),
formato JSON padronizado exatamente para os casos de uso que temos: retomar a
última posição, marcadores, destaques, resultados de busca e referência
compartilhável. Interoperabilidade com o ecossistema Readium sai de graça.

```json
{
  "href": "OEBPS/cap03.xhtml",
  "type": "application/xhtml+xml",
  "title": "Capítulo 3",
  "locations": {
    "fragments": ["secao2"],
    "progression": 0.412,
    "totalProgression": 0.187,
    "position": 84,
    "otherLocations": { "charOffset": 12873, "irSchema": 1 }
  },
  "text": {
    "before": "…e então percebeu que a porta",
    "highlight": "estava aberta desde o princípio",
    "after": ", o que mudava tudo…"
  }
}
```

| Campo | Papel |
|---|---|
| `href` | **Autoridade** da seção, relativo à raiz do ZIP, decodificado. O índice do spine é guardado só como dica interna |
| `otherLocations.charOffset` | Nosso offset canônico, no ponto de extensão sancionado pelo modelo |
| `otherLocations.irSchema` | `IR_SCHEMA_VERSION` que gerou o offset. Permite ao reparo saber se a regra de normalização mudou (§4.1) |
| `fragments` | O `id` de origem, quando o locator veio de TOC, link ou `page-list`. Ajuda o reparo e a exportação |
| `text` | Âncora de reparo: `highlight` de até 64 caracteres e `before`/`after` de ~32 |
| `progression` | Fração dentro da seção, derivada de `charOffset / totalChars` |
| `totalProgression` | Fração no livro, do acumulado do spine |
| `position` | Compatibilidade Readium (§2.1) |

**CFI é ausente.** Ele exigiria manter caminho de DOM, que a IR plana descarta de
propósito. Se um dia for necessário para exportação, dá para gerar sob demanda
reparseando a seção.

Por que `href` e não índice: se o usuário substituir o arquivo por outra edição,
o índice mente em silêncio e o `href` falha de forma detectável.

Locator de posição de leitura (o que `onLocatorChanged` emite) aponta para o
**primeiro caractere da página** e tem `text.highlight` com as primeiras
palavras. Locator de destaque cobre o range e tem `highlight` com o texto
selecionado, truncado a 64 caracteres com o resto verificado por comprimento.

## 2. Progresso

`totalChars` por seção é calculado no parse e acumulado sobre o spine na abertura
do documento.

```
totalProgression = (charsAntesDaSecao + charOffset) / totalCharsDoLivro
```

Percentual global disponível **no primeiro frame, sem renderizar nada**. Nenhum
equivalente de `locations.generate()`, que é o que faz os leitores baseados em
epub.js demorarem segundos para abrir.

Requer que todas as seções tenham sido parseadas ao menos uma vez, para que
`totalChars` exista. Na primeira abertura de um livro sem cache, o worker parseia
o spine inteiro em prioridade baixa ([08](08-concorrencia-cache.md) §1.1), e
`totalProgression` fica `null` até terminar. Para um livro típico isso leva
menos de um segundo; nas seguintes, vem do cache. A UI trata `null` como "ainda
não sei", como faz com `pageCount`.

Contagem de páginas é assunto separado e chega depois
([04](04-layout-paginacao.md) §3), porque depende de layout.

### 2.1 `position`

No Readium, `position` é o índice (a partir de 1) numa lista de posições
sintéticas gerada dividindo cada recurso em blocos de 1024 **bytes**. Como não
queremos guardar os bytes de cada seção, usamos 1024 **caracteres** de
`canonicalText`. É compatível em espírito (ordem e granularidade), não em valor
exato. Documentado como tal; nenhum consumidor deve comparar `position` entre
implementações.

## 3. `page-list`: números de página do livro físico

Muito EPUB de editora traz `<nav epub:type="page-list">` no NAV, mapeando páginas
da edição impressa para pontos no texto. É o que permite citar "p. 214" numa
referência acadêmica.

```dart
final class EpubPageMark {
  final String label;        // "214"
  final Locator locator;
}
```

Sai quase de graça do parse do NAV, e é diferencial forte para conteúdo técnico e
acadêmico. Resolvido via mapa de âncoras.

Na ausência de `page-list` no NAV, o NCX pode ter `<pageList>` (EPUB2), e há
EPUBs com `<span epub:type="pagebreak" id="pg214" title="214"/>` no corpo sem
NAV correspondente. Os três são fontes; a prioridade é NAV, NCX, corpo.

`doc.pageMarkAt(Locator)` devolve a marca de página impressa em vigor no
locator (a última marca com offset ≤ `charOffset`), para a UI exibir "p. 214"
junto do progresso.

## 4. Reparo

Quando `charOffset` não valida (o texto naquele offset não corresponde a
`text.highlight`):

1. Busca a citação numa janela de ±2000 caracteres em volta do offset esperado
2. Se falhar, busca na seção inteira
3. Se houver múltiplas ocorrências, escolhe a que melhor casa `before` e `after`
4. Se `highlight` não existe (locator antigo ou de outra origem) mas `fragments`
   existe, resolve pela âncora
5. Devolve o locator corrigido com um grau de confiança em `[0, 1]`
6. Emite `EpubDiagnostic.locatorRepaired` com offset antigo, novo e confiança

```dart
final class LocatorResolution {
  final Locator locator;
  final double confidence;     // 1.0 = offset validou direto
  final bool repaired;
}
```

Confiança: `1.0` validou direto; `0.9` achou a citação única na janela; `0.7`
achou única na seção; `0.5` múltiplas ocorrências, escolhida por contexto; `0.3`
só a âncora; `0.0` nada achado, e o locator devolvido aponta para
`progression × totalChars` como último recurso.

O app decide se persiste a correção. **Nunca descartar em silêncio** — isso é
perda de dados do usuário, e é o comportamento que estamos deliberadamente
substituindo.

Comparação de texto no reparo é feita após NFC e colapso de whitespace nos dois
lados, e ignora diferenças em U+00AD e U+200B, para que um locator gerado antes
da hifenização (v1.2) valide depois dela.

### 4.1 Por que o reparo é necessário

O offset é estável contra mudança de fonte, tamanho, viewport e versão do app.
Ele **não** é estável contra mudança no nosso próprio pipeline de normalização de
texto ([03](03-camada-a-ir.md) §5). Se um dia a regra de whitespace mudar, todos
os offsets deslocam. A âncora de citação é o seguro contra isso, e o
`irSchema` no locator diz ao reparo que deve **esperar** deslocamento e pular
direto para a busca por citação, sem confiar no offset.

## 5. Metadados e navegação

```dart
final class EpubMetadata {
  final String? title, subtitle;
  final List<String> authors, contributors;
  final String? language, publisher, identifier, description;
  final DateTime? published, modified;
  final List<String> subjects;
  final String? rights;
  final String? series;              // calibre:series / belongs-to-collection
  final double? seriesIndex;
  final Map<String, List<String>> raw;   // todo <dc:*> e <meta> não mapeado, por nome
}
```

`raw` existe porque metadados de EPUB são um pântano de convenções (`calibre:`,
`schema:`, `rendition:`), e o app sempre acaba precisando de um campo que não
previmos.

```dart
final class EpubTocEntry {
  final String title;
  final Locator? locator;              // null para entradas puramente de agrupamento
  final List<EpubTocEntry> children;
  final int depth;
}
```

Acesso:

```dart
doc.metadata;                     // EpubMetadata
doc.toc;                          // List<EpubTocEntry>
doc.landmarks;                    // List<EpubTocEntry>: bodymatter, toc, cover...
doc.pageList;                     // List<EpubPageMark>
doc.readingOrder;                 // List<SpineItem>
await doc.cover();                // Uint8List? — bytes brutos, o app decodifica
doc.direction;                    // EpubReadingDirection
doc.layout;                       // reflowable | prePaginated
doc.totalChars;                   // int? até o spine inteiro estar parseado
doc.tocEntryAt(Locator);          // a entrada de TOC em vigor no locator
```

`cover()` devolve bytes, não `ImageProvider`, para manter o pacote fora de
decisões de cache de imagem do app.

### 5.1 Como a capa é encontrada

Em ordem, a primeira que resolver:

1. EPUB3: item do manifest com `properties="cover-image"`
2. EPUB2: `<meta name="cover" content="ID">` no OPF, apontando para um item do
   manifest
3. Landmark `epub:type="cover"` ou `guide/reference[@type="cover"]`, cuja
   seção tem uma única imagem (inclusive embrulhada em SVG,
   [05](05-render-selecao-a11y.md) §6.2)
4. Item do manifest cujo `id` ou `href` contém "cover" e é imagem
5. Primeira imagem da primeira seção do spine

Cada passo abaixo do 2 emite `coverHeuristic` como diagnóstico `info`.

## 6. Navegação programática

```dart
controller.goTo(Locator);                    // qualquer locator
controller.goToHref(String href, {String? anchorId});
controller.goToProgression(double fraction); // 0.0–1.0 no livro
controller.goToTocEntry(EpubTocEntry);
controller.next(); controller.prev();        // página, respeitando a direção
controller.nextSection(); controller.prevSection();
controller.back();                           // volta ao ponto anterior a um salto (§6.2)
```

Links internos do documento chegam ao app via `onLinkTap(Locator)`; links externos
via `onExternalLinkTap(Uri)`. **O pacote nunca abre URL** — não tem rede
([00](00-visao-geral.md) §2).

### 6.1 Notas de rodapé (Emenda 14)

Um run com `noteRef` aponta, via `links`, para um alvo interno. O pacote resolve
o alvo até o **bloco** que contém o `id` (ou até o `container(aside)` com
`epub:type="footnote"`/`"endnote"`/`"rearnote"` que o contém) e entrega:

```dart
final class EpubNote {
  final Locator ref;                 // onde está a chamada
  final Locator target;              // onde está a nota
  final String text;                 // canonicalText dos blocos da nota, sem o marcador de retorno
  final List<Block> blocks;          // para o app renderizar com formatação, se quiser
  final Rect anchorRect;             // posição da chamada, coordenadas globais
}

Future<EpubNote?> doc.resolveNote(Locator ref);
```

`onNoteTap(EpubNote)` no widget. O app mostra popup, bottom sheet ou navega com
`goTo(note.target)`. O pacote não mostra nada.

O "marcador de retorno" (um link de volta com `epub:type="backlink"` ou texto
`↩`) é removido de `text`, porque num popup ele não faz sentido.

### 6.2 Histórico de salto

Ao seguir um link, nota ou entrada de TOC, o `ReaderState` guarda o locator de
origem numa pilha de até 10 entradas. `controller.back()` desempilha. O app pode
mostrar "voltar para a página 84" como fazem Kindle e Apple Books. A pilha é
parte do `ReaderState`, então persiste se o app quiser.

## 7. Busca: o que é nosso

O pacote **não** indexa. Ele entrega o material:

```dart
final text = await doc.sectionText(href);        // canonicalText + totalChars
Locator locatorAt(String href, int charOffset);  // offset → locator completo
Locator rangeLocator(String href, int start, int end);  // com text.highlight do range
```

O app indexa `canonicalText` com FTS5 ou o que preferir, guarda os offsets, e usa
`locatorAt` para transformar resultado de busca em posição navegável. O `\n` de
fim de bloco ([03](03-camada-a-ir.md) §5) é o que faz o tokenizador do índice
não colar palavras de blocos vizinhos.

É a mesma unidade de offset dos destaques e do progresso, então busca, anotação e
posição de leitura falam a mesma língua sem conversão.

Conveniência para quem não quer índice: `doc.findAll(String query, {bool
caseSensitive})` faz busca linear por seção no worker, devolvendo `Stream<Locator>`
conforme encontra. Para livros de até algumas centenas de milhares de palavras é
rápido o bastante e evita que o app de exemplo precise de banco.
