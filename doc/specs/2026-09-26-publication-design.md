# Publicação (Fase 1, sub-projeto 2) — design

**Data:** 2026-09-26. **Estado:** aprovada em conversa (desenho em quatro seções),
com uma revisão independente cujos achados estão incorporados.
**Branch:** `fase1/publicacao`.

## 1. Objetivo

Segundo dos seis sub-projetos da Fase 1 ([13](../13-riscos-spikes-fases.md) §2).
A partir de um `EpubContainer` (sub-projeto 1), produz a `EpubPublication`:
metadados, manifest, ordem de leitura, TOC reconciliado com o spine, landmarks,
`page-list`, capa, direção e layout. Inclui a normalização de `href` e o
tratamento dos itens problemáticos de [03](../03-camada-a-ir.md) §3.2.

**Critério de sucesso:** o teste de corpus de §10 passa nos 65 EPUBs; nenhum EPUB
malformado derruba o processo ou produz exceção fora da taxonomia `EpubException`;
as condições fatais da Publicação ([09](../09-erros-diagnosticos.md) §1:
`container.xml` ausente, OPF ausente ou inválido, spine vazio) lançam o tipo de
§9.1.

### 1.1 Decisões tomadas no brainstorming

- **Só o nível do pacote.** Lê `container.xml`, OPF, NAV e NCX; nunca abre uma
  seção. O que depende de conteúdo de seção fica como gancho para os
  sub-projetos 4 (IR) e 6 (Documento): título de órfão pelo primeiro heading,
  passos 3 e 5 da capa, `page-list` a partir de `epub:type="pagebreak"` no corpo,
  `totalChars`, resolução de alvo (`caminho#fragmento`) para offset.
- **Diretório próprio**, `lib/src/publication/`, separado de `lib/src/container/`
  (que passou a significar bytes de um recurso). Corrige
  [11](../11-empacotamento-versionamento.md) §4.
- **Parsers puros e síncronos**, um por documento (`parseContainerXml`,
  `parseOpf`, `parseNav`, `parseNcx`), mais funções puras de normalização,
  reconciliação e capa; um orquestrador assíncrono, `readPublication`, faz as
  leituras, resolve caminhos contra o contêiner e chama as partes.
- **NAV com `package:html`** (tolerante, [03](../03-camada-a-ir.md) §8); **OPF,
  NCX e `container.xml` com `package:xml`**.
- Estrutura do pacote de [11](../11-empacotamento-versionamento.md) §4, erros por
  exceção e diagnóstico ([09](../09-erros-diagnosticos.md)); a preferência global
  por feature-first, MVVM, Result e Riverpod não se aplica ao galley.

### 1.2 Fora do escopo

Ler seções; os ganchos de §1.1; `EpubDocument` e a API pública de navegação
(`doc.toc`, `doc.pageList`… com `Locator`, sub-projeto 6); cache da publicação
(sub-projeto 5); fixed-layout além de registrar `EpubLayoutMode.prePaginated`
(P9, 1.1). `readPublication` **não** fecha o contêiner (quem abriu fecha).

### 1.3 Pendências do doc/14 endereçadas a este sub-projeto

| Pendência | Destino |
|---|---|
| Conferir pelo `media-type` do manifest que a ofuscação declarada é sobre fonte (spec do contêiner §6) | **Feito aqui** (§8.1) |
| Teste do diagnóstico de prefixo do ZIP sem asserção de `details.delta` | **Feito aqui** (§10, uma asserção no `zip_container_test`) |
| `CipherReference` relativo ao diretório do OPF | Movido para o sub-projeto 6, que cruza fontes, manifest e `encryption.xml` ao carregar fontes |
| Contêiner em `strict`: `rights.xml`/`encryption.xml` com CRC errado saem como corrupção e não como DRM | Movido para o sub-projeto 6, junto da revisão do `strict` do documento |

## 2. Arquivos

| Caminho | Papel |
|---|---|
| `lib/src/publication/model.dart` | `EpubPublication`, `ManifestItem`, `SpineItem`, `SectionKind`, `NavPoint`, `NavTarget`, `EpubReadingDirection`, `EpubLayoutMode` |
| `lib/src/publication/metadata.dart` | `EpubMetadata` (pública) |
| `lib/src/publication/xml_text.dart` | `decodeXml` |
| `lib/src/publication/href.dart` | `normalizeHref`, `splitFragment`, `decodePath` |
| `lib/src/publication/container_xml.dart` | `parseContainerXml` |
| `lib/src/publication/opf.dart` | `parseOpf` e o modelo cru (`OpfDocument`) |
| `lib/src/publication/nav.dart` | `parseNav` e `NavDocument` |
| `lib/src/publication/ncx.dart` | `parseNcx` e `NcxDocument` |
| `lib/src/publication/reconcile.dart` | `reconcileToc` |
| `lib/src/publication/cover.dart` | `findCover` |
| `lib/src/publication/read_publication.dart` | `readPublication` (orquestrador) |
| `lib/src/diagnostics/exceptions.dart` | + `EpubPackageException` |
| `lib/src/diagnostics/diagnostic.dart` | + os códigos de §9.2 |

Testes em `test/publication/`.

## 3. Modelo

Interno nesta etapa, exceto `EpubMetadata`, `EpubReadingDirection`,
`EpubLayoutMode` e `EpubPackageException`, que já são públicos (nomes de
[11](../11-empacotamento-versionamento.md) §3.3). Os tipos públicos de
[06](../06-locator-navegacao.md) §5 com `Locator` (`EpubTocEntry`,
`EpubPageMark`) são montados pelo `EpubDocument` no sub-projeto 6 a partir de
`NavPoint`. Todas as listas, conjuntos e mapas do modelo são não modificáveis.

```dart
final class EpubPublication {
  final String opfPath;                     // caminho do OPF no contêiner
  final String version;                     // atributo version do <package>, cru ('' se ausente)
  final EpubMetadata metadata;
  final Map<String, ManifestItem> manifest; // por id, na ordem do OPF
  final List<SpineItem> spine;              // ordem de leitura; nunca vazio; sem repetição de caminho
  final List<NavPoint> toc;                 // reconciliado com o spine
  final List<NavPoint> landmarks;
  final List<NavPoint> pageList;
  final String? coverPath;                  // caminho no contêiner, ou null
  final String? navPath;                    // NAV efetivamente usado (chave do livro, 08 §4.1)
  final String? ncxPath;                    // NCX efetivamente usado
  final EpubReadingDirection direction;
  final EpubLayoutMode layout;
  final List<String> uniqueIdentifiers;     // chave IDPF (09 §4)
  final List<String> identifiers;           // todos os dc:identifier, em ordem (chave Adobe)
}

final class ManifestItem {
  final String id;
  final String path;          // normalizado e resolvido; para href recusado, o href cru
  final String mediaType;     // em minúsculas, sem parâmetros (antes de ';'), trim
  final Set<String> properties;
  final String? fallback;     // id de outro item
  final bool missing;         // não existe no contêiner (ou href recusado)
  final bool remote;          // href http:/https: (recurso remoto do EPUB3)
}

enum SectionKind { xhtml, image, unsupported }

final class SpineItem {
  final String idref;
  final ManifestItem item;    // o item referenciado
  final ManifestItem content; // o item a renderizar: item, ou o fim da cadeia de fallback (§6.4)
  final bool linear;          // false só com linear="no"
  final SectionKind kind;     // do content
}

final class NavPoint {
  final String title;
  final NavTarget? target;    // null em entrada só de agrupamento ou alvo externo
  final List<NavPoint> children;
  final String? type;         // landmark: epub:type (NAV) ou reference@type (guide)
  final bool synthesized;     // órfão inserido pela reconciliação (a UI pode escondê-lo)
}

final class NavTarget {
  final String path;          // caminho de item do manifest (ou o resolvido, §5.4)
  final String? fragment;     // sem '#', decodificado de %xx (tolerante); null se ausente ou vazio
}

enum EpubReadingDirection { ltr, rtl, auto }
enum EpubLayoutMode { reflowable, prePaginated }
```

`EpubMetadata`: campos de [06](../06-locator-navegacao.md) §5 (título,
subtítulo, autores, colaboradores, idioma, editora, identificador, descrição,
datas de publicação e modificação, assuntos, direitos, série e índice da série) e
`raw` com **o que não foi mapeado** para um campo (06 §5), chave = nome local do
`dc:*`, ou o `property`/`name` do `meta`, valores em ordem de documento. Regras
de preenchimento em §6.2.

## 4. Decodificação de XML

`String decodeXml(Uint8List bytes, {required String path, required DiagnosticSink sink})`,
usada para `container.xml`, OPF, NCx **e** NAV:

1. BOM: UTF-8 (`EF BB BF`), UTF-16 LE (`FF FE`), UTF-16 BE (`FE FF`); o BOM sai do
   texto.
2. Sem BOM: a declaração `encoding` (XML) ou o `<meta charset>` (só no NAV), nos
   primeiros 1 024 bytes lidos como ASCII. `utf-8`/`utf8` → UTF-8;
   `iso-8859-1`/`latin1`/`windows-1252`/`us-ascii` → Latin-1; `utf-16` sem BOM →
   UTF-16 LE; outro valor → UTF-8.
3. Sem declaração: UTF-8.
4. UTF-8 inválido cai para Latin-1 e emite `encodingFallback` (`info`,
   `href: path`, `details: {declared, used: 'latin1'}`). UTF-16 com número ímpar
   de bytes cai para Latin-1 do mesmo jeito.

A detecção completa de encoding (Shift-JIS e outros) é da IR.

## 5. Caminhos

### 5.1 `normalizeHref`

`String? normalizeHref(String baseDir, String raw)` devolve o caminho
normalizado relativo à raiz do contêiner, ou `null` quando o `href` é inválido.
Não decodifica `%xx`.

1. Esquema (`[a-zA-Z][a-zA-Z0-9+.-]*:` no início, ex.: `http:`, `mailto:`,
   `data:`) → `null`.
2. Tira `?query` e `#fragmento` (o fragmento sai por `splitFragment`).
3. Troca `\` por `/`.
4. Resolve contra `baseDir` (diretório do documento que contém o `href`, sem `/`
   final; vazio na raiz); `href` que começa com `/` é relativo à raiz.
5. Colapsa `.`, `..` e barras repetidas. Um `..` que sai da raiz → `null`.
6. Caminho vazio → `null`.

`(String path, String? fragment) splitFragment(String raw)` separa no primeiro
`#`; fragmento vazio → `null`; o fragmento é decodificado de `%xx` de forma
tolerante (fica cru se não decodificar).

### 5.2 `decodePath`

`String? decodePath(String normalized)`: decodifica `%xx` segmento a segmento
(`Uri.decodeComponent`; segmento que não decodifica fica cru) e **reaplica os
passos 3–6** de §5.1 ao resultado. `%2F` decodificado não é separador: um segmento
que, decodificado, contém `/` fica cru. Se o resultado sai da raiz ou fica vazio,
devolve `null` (vale só a forma crua). Fecha a travessia por `%2e%2e` e mantém o
contrato do contêiner (caminhos sem `\`, `%xx` e `..`).

### 5.3 Itens do manifest (orquestrador)

Para cada item, a partir do `href` cru e do diretório do OPF:
- **Esquema `http:`/`https:`** → `remote: true`, `missing: false`, `path` = `href`
  cru, sem diagnóstico.
- **Outro `href` recusado** por `normalizeHref` → `missing: true`, `path` = `href`
  cru, `resourceMissing` (`href: null`, `details: {id, raw}`).
- **Tentativa dupla** ([03](../03-camada-a-ir.md) §3.2): pergunta ao contêiner
  (`exists`) primeiro pela forma decodificada (§5.2, se não `null`) e depois pela
  crua; o que existir vence. Nenhuma existe → fica a decodificada (ou a crua, se a
  decodificada for `null`), `missing: true` e `resourceMissing` (`href` = o
  caminho, `details: {id}`).
- **`exists` que lança** (provider do app) → `missing: true` e
  `resourceUnreadable` (`href` = caminho, `details: {reason: 'exists',
  exception}`).

### 5.4 Alvos de NAV e NCX (orquestrador)

Os parsers devolvem o `href` **cru** de cada entrada; o orquestrador resolve
contra o diretório do documento que contém a entrada (NAV ou NCX):
- `href` com esquema → `target: null`, sem diagnóstico.
- `href` só com fragmento (`#frag`) → o próprio documento (caminho do NAV ou NCX)
  com o fragmento.
- Senão, `normalizeHref` e casamento com o `path` de algum item do manifest, nesta
  ordem: forma decodificada exata, forma crua exata, decodificada sem diferenciar
  maiúsculas, crua sem diferenciar maiúsculas. Casou → `target.path` = o `path` do
  item. Não casou → `target.path` = a forma decodificada (ou a crua), sem
  diagnóstico (a resolução é do sub-projeto 6).
- `href` recusado por `normalizeHref` (fora da raiz) → `target: null`.

## 6. OPF

`OpfDocument parseOpf(String text, {required String opfPath, required DiagnosticSink sink})`
— pura; os `href` saem crus (§5.3). `OpfDocument` guarda o que o orquestrador
precisa: metadados já montados, identificadores, itens crus (`id`, `href`,
`media-type`, `properties`, `fallback`), `itemref` (`idref`, `linear`), `toc`
do spine, `page-progression-direction`, layout, `guide` e o `id` do
`<meta name="cover">`.

### 6.1 Leitura

- Elementos da estrutura (`package`, `metadata`, `dc-metadata`, `x-metadata`,
  `manifest`, `item`, `spine`, `itemref`, `meta`, `guide`, `reference`) por
  **nome local**, em qualquer namespace ou sem namespace.
- `dc:*` = descendentes de `metadata` cujo namespace é
  `http://purl.org/dc/elements/1.1/` **ou** cujo prefixo literal é `dc` (com ou
  sem namespace declarado); o nome local é comparado sem diferenciar maiúsculas
  (o OEB antigo usa `dc:Title`).
- Atributos `opf:*` (`opf:role`, `opf:event`, `opf:file-as`, `opf:scheme`) por
  nome local.
- **Fatal** (`EpubPackageException`, `href: opfPath`): XML inválido (`cause`: a
  `XmlException`); raiz que não é `package`; sem `manifest`; sem `spine`. O spine
  vazio depois de descartar os `idref` sem item é fatal no orquestrador.

### 6.2 Metadados

- **Título:** o `dc:title` com `title-type` (refinado) `main`; senão o primeiro
  que não é `subtitle` nem `expanded`; senão o primeiro. **Subtítulo:** o primeiro
  com `title-type` `subtitle`. Os outros títulos ficam em `raw`.
- **Autores e colaboradores:** `dc:creator` é autor quando não tem papel ou quando
  **algum** papel é `aut`; senão colaborador. `dc:contributor` é sempre
  colaborador. Papel = `opf:role` (EPUB2) ou `<meta refines="#id" property="role">`
  (EPUB3; vários permitidos). `role` só vale para `dc:creator`/`dc:contributor`
  (refinando outro elemento, fica em `raw`).
- **Série:** de `belongs-to-collection` só quando algum `collection-type`
  refinado é `series` ou quando não há `collection-type`; índice de
  `group-position`. Com `collection-type` `set` (listas, coleções), vai para
  `raw`. Na falta, `<meta name="calibre:series" content>` e
  `calibre:series_index`.
- **Datas:** `published` = o `dc:date` com `opf:event="publication"`; senão o
  primeiro `dc:date` sem `opf:event` ou com outro evento que não seja
  `modification`; `modified` = `<meta property="dcterms:modified">`; senão o
  `dc:date` com `opf:event="modification"`. Datas parciais: `YYYY` → 1º de
  janeiro, `YYYY-MM` → dia 1; o que não parseia fica `null` (o texto em `raw`).
- **Demais:** `language` = primeiro `dc:language`; `publisher`, `description`,
  `rights` = primeiro de cada; `subjects` = todos os `dc:subject`.
- **`raw`:** o que não virou campo. `<meta name content>` (EPUB2) entra com o
  `content`; `<meta property>` (EPUB3) com o texto.

### 6.3 Identificadores, manifest e spine

- **Identificadores:** `identifiers` = todos os `dc:identifier`, em ordem, com
  `trim`. `uniqueIdentifiers` = o `dc:identifier` cujo `id` é o
  `unique-identifier` do `<package>`; sem casamento, `[identifiers.first]` (se
  houver). `metadata.identifier` = `uniqueIdentifiers.first`, se houver.
- **Manifest:** item sem `id` ou sem `href` é descartado com `resourceMissing`
  (`href: null`, `details: {reason, id?}`); `id` duplicado → vale o primeiro.
  Item cujo caminho resolvido é o próprio OPF ou termina em `/` → `missing`.
- **Spine:** `idref` sem item → `spineItemUnresolved` (`warning`, `href: opfPath`,
  `details: {idref}`) e o `itemref` é ignorado. `idref` (ou caminho) repetido →
  vale o primeiro, e emite `spineItemDuplicate` (`info`, código novo, `href:
  opfPath`, `details: {idref}`). `page-progression-direction` → `direction`
  (`ltr`/`rtl`; ausente ou `default` → `auto`). O `toc` do spine é guardado.
- **Layout:** `<meta property="rendition:layout">pre-paginated</meta>` global →
  `prePaginated`; senão `reflowable`.
- **Guide** (EPUB2): `reference` com `type`, `title`, `href` → landmarks quando o
  NAV não os fornecer.

### 6.4 Tipo da seção e `fallback`

`SectionKind` de um item: `application/xhtml+xml` e `text/html` → `xhtml`;
`image/*` → `image`; outro → `unsupported`. Para cada item do spine, se o item
não é `xhtml` nem `image`, ou é `missing`, segue a cadeia de `fallback` (conjunto
de visitados para ciclo, no máximo 16 passos) até o primeiro item `xhtml`/`image`
não `missing`; esse é o `content`. Se a cadeia não resolve, `content` = o próprio
item, e, quando ele é `unsupported`, emite `unsupportedMediaType` (`warning`,
`href` = caminho, `details: {mediaType}`). Item `missing` continua no spine (a IR
faz a seção placeholder).

## 7. NAV, NCX, landmarks, `page-list` e reconciliação

### 7.1 Onde estão

- **NAV:** o primeiro item do manifest com `properties` contendo `nav`.
- **NCX:** o item cujo `id` é o `toc` do spine **e** cujo `media-type` é
  `application/x-dtbncx+xml`; senão o primeiro item com esse `media-type`.

### 7.2 `parseNav`

`NavDocument parseNav(String text)` (com `package:html`, iterando `nodes`, nunca
indexando `children`, [03](../03-camada-a-ir.md) §8), devolve `toc`,
`pageList`, `landmarks` com `href` crus:
- `nav` cujo atributo literal `epub:type` contém o token `toc`, `page-list` ou
  `landmarks`; havendo mais de um do mesmo tipo, vale o primeiro.
- Listas `ol` **ou** `ul`. Em cada `li`, a entrada vem do primeiro `a` ou `span`
  **descendente** do `li` que não esteja dentro de uma lista aninhada; os filhos,
  da primeira lista aninhada do `li`.
- Título: texto dos descendentes do `a`/`span` com whitespace colapsado e `trim`;
  vazio → `alt` do primeiro `img` descendente; vazio → atributo `title`; vazio →
  `''` (o orquestrador troca pelo nome do arquivo do alvo, sem extensão).
- `a` com `href` → `href` cru; `span` ou `a` sem `href` → sem alvo.
- Em `landmarks`, `type` = `epub:type` do `a`.
- Limites contra arquivo hostil: profundidade 64 e 100 000 entradas **por
  `nav`**; o excedente é descartado e o `NavDocument` marca `truncated: true`.

### 7.3 `parseNcx`

`NcxDocument parseNcx(String text)` com `package:xml`: `navMap/navPoint`
recursivo (`navLabel/text`, `content@src`) e `pageList/pageTarget`, por nome
local. `playOrder` é ignorado (vale a ordem do documento). `navPoint` sem
`content` → sem alvo. Mesmos limites e `truncated` de §7.2. XML inválido lança
`XmlException`.

### 7.4 Precedência

| O quê | Fonte |
|---|---|
| TOC | NAV com pelo menos uma entrada no `toc`; senão NCX; senão vazio |
| `page-list` | NAV; senão NCX |
| Landmarks | NAV; senão `guide` do OPF |

Um NAV sem `nav` de `toc` ainda fornece `page-list` e landmarks.

### 7.5 Falhas do NAV e do NCX

Nunca fatais; `navIgnored` (`info`, `href` = caminho do NAV ou NCX,
`details.reason`) e a precedência segue:

| Situação | `reason` |
|---|---|
| Declarado no manifest mas `missing` | `missing` |
| Acima de `maxPackageDocumentSize` (§9) | `too-large` |
| `fetch`/`decode()` lança (fora de `strict`) — também emite `resourceUnreadable` (`warning`, `details: {reason, exception}`) | `unreadable` |
| NCX com XML inválido | `invalid` |
| NAV sem `nav` de `toc` | `no-toc` |
| Limite de §7.2 atingido (a parte lida é usada) | `truncated` |

Em `strict`, a exceção lançada pelo `DiagnosticSink` durante a leitura (por
exemplo, `zipCrcMismatch`) **propaga**; só falhas do próprio `fetch`/`decode()`
viram `unreadable`.

### 7.6 `reconcileToc`

`List<NavPoint> reconcileToc(List<NavPoint> toc, List<SpineItem> spine, {required DiagnosticSink sink})`:
- **Órfão:** item do spine com `linear` verdadeiro cujo caminho (`item.path`)
  nenhuma entrada do TOC, em qualquer nível, tem como `target.path`. Itens com
  `linear: false` nunca são órfãos, mas entradas existentes que apontam para eles
  são mantidas.
- Cada órfão vira entrada raiz com `synthesized: true`, `target:
  NavTarget(item.path, null)` e título = nome do arquivo sem extensão.
- **Posição:** para cada entrada raiz existente, `primeira(e)` = menor índice do
  spine entre os `target.path` dela e dos descendentes (sem alvo no spine →
  infinito). O órfão de índice `i` entra logo depois da última entrada raiz, **na
  ordem do TOC**, com `primeira(e) < i`; se não houver nenhuma, no início. Órfãos
  que caem no mesmo ponto ficam na ordem do spine. As entradas existentes não
  mudam de ordem.
- Emite `tocReconciled` (`info`, `href: null`, `details: {orphans: n}`) uma vez,
  se houver órfão. (`count` é reservado do `DiagnosticSink`.)
- Entradas cujo alvo não está no spine são mantidas.

## 8. Capa e fontes

### 8.1 Conferência de ofuscação pelo `media-type`

Para cada item do manifest cujo `container.obfuscationOf(path)` não é `null` e cujo
`media-type` não é de fonte (`font/*`, `application/font-*`,
`application/x-font-*`, `application/vnd.ms-opentype`, `application/font-woff*`):
`EpubEncryptedException(scheme: 'unknown:obfuscation-on-content')`, fatal — a
extensão enganou a checagem do contêiner (spec do contêiner §6).

### 8.2 `findCover`

`String? findCover(OpfDocument opf, Map<String, ManifestItem> manifest, {required DiagnosticSink sink})`,
na ordem ([06](../06-locator-navegacao.md) §5.1, só os passos de pacote):
1. item com `properties` contendo `cover-image`;
2. item cujo `id` é o `content` do `<meta name="cover">`;
3. item de `image/*` cujo `id` ou `path`, sem diferenciar maiúsculas, contém
   `cover` — emite `coverHeuristic` (`info`, `href` = caminho).

Itens `missing` ou `remote` são pulados em todos os passos. Nenhum → `null`. Os
passos 3 e 5 de 06 §5.1 (que olham a seção) ficam para o sub-projeto 6.

## 9. Orquestrador, exceções e diagnósticos

```dart
/// Não fecha o contêiner.
Future<EpubPublication> readPublication(EpubContainer container,
    {required DiagnosticSink sink});

const int maxPackageDocumentSize = 4 * 1024 * 1024;
```

Ordem: `container.xml` (§9.1) → OPF (§6) → itens do manifest (§5.3) →
conferência de fontes (§8.1) → spine e `fallback` (§6.3, §6.4; fatal se vazio) →
NAV/NCX (§7) → alvos (§5.4) → reconciliação (§7.6) → capa (§8.2). Cada arquivo é
lido com `fetch`; se o `PendingResource.size` passa de `maxPackageDocumentSize`,
não é drenado (OPF → fatal; NAV/NCX → `navIgnored`, `too-large`); senão o
`decode()` é drenado inteiro.

### 9.1 Fatais

| Situação | Exceção |
|---|---|
| `container.xml` ausente | `EpubContainerException(href: 'META-INF/container.xml')` |
| `container.xml` ilegível: o `fetch`/`decode()` lança | a `EpubContainerException` do contêiner, propagada |
| `container.xml` com XML inválido, sem `rootfile` com `media-type` `application/oebps-package+xml`, ou só com `full-path` vazio | `EpubContainerException(cause)` |
| Nenhum dos `rootfile` válidos existe no contêiner (tentados em ordem, com a tentativa dupla de §5.3) | `EpubPackageException(href: primeiro full-path, 'OPF ausente')` |
| OPF ilegível: o `fetch`/`decode()` lança | a `EpubContainerException` do contêiner, **propagada** (09 §2: a entrada é o OPF) |
| OPF acima de `maxPackageDocumentSize`, XML inválido, raiz errada, sem `manifest`/`spine`, spine vazio | `EpubPackageException(href: opfPath, cause?)` |
| Ofuscação sobre conteúdo (§8.1) | `EpubEncryptedException` |

A exceção lançada pelo `DiagnosticSink` em `strict` sempre propaga como está.
Os `emit` da Publicação passam `onStrict: (m) => EpubPackageException(m, href: …)`,
então um warning da Publicação em `strict` lança `EpubPackageException` com o nome
do código na mensagem.

### 9.2 Diagnósticos

Códigos novos em `EpubDiagnosticCode`, com os nomes e severidades de 09 §3:
`resourceMissing` (warning), `spineItemUnresolved` (warning),
`unsupportedMediaType` (warning), `encodingFallback` (info), `tocReconciled`
(info), `coverHeuristic` (info), e os novos `navIgnored` (info) e
`spineItemDuplicate` (info). `resourceUnreadable` (warning) já existe.

`EpubPackageException extends EpubException` (`href`, `cause`). Exportados por
`galley.dart`: `EpubPackageException`, `EpubMetadata`, `EpubReadingDirection`,
`EpubLayoutMode`.

## 10. Testes

Em `test/publication/`, com XML de texto nos testes de parser:

| Arquivo | O que cobre |
|---|---|
| `xml_text_test.dart` | BOM UTF-8/16 LE/BE; declaração Latin-1; `<meta charset>`; UTF-8 inválido → `encodingFallback`; UTF-16 ímpar |
| `href_test.dart` | tabela de `normalizeHref` (subpasta, `..`, `..` além da raiz, `\`, `/` inicial, esquema, `?` e `#`, barras repetidas, vazio); `splitFragment`; `decodePath` (`%20`, `%C3%AD`, `%2e%2e` que sai da raiz → `null`, `%5C`, `%2F` não separa, `%E9` inválido fica cru) |
| `container_xml_test.dart` | rootfile, outras renditions, `media-type` errado, `full-path` vazio, XML inválido |
| `opf_test.dart` | leitura por nome local (namespace ausente, prefixo `opf:`, `dc` sem declaração, `dc:Title`); título com vários `dc:title`; `refines` (subtítulo, `role` múltiplo, `role` refinando `publisher`); `opf:role`; série com `collection-type` `series`, `set` e ausente; `calibre:series`; datas completas, parciais e inválidas; `opf:event`; `raw` só com o não mapeado; identificadores e fallback do `unique-identifier`; manifest (duplicado, sem `id`/`href`); spine (`idref` sem item, repetido, `linear`); direção; layout; guide; fatais |
| `nav_test.dart` | toc aninhado com `ol` e `ul`; `a` dentro de `p`/`strong`; `span` de agrupamento; título vazio, de `img alt` e de `title`; landmarks com `type`; page-list; dois `nav` do mesmo tipo; limites e `truncated` |
| `ncx_test.dart` | navMap aninhado; pageList; `playOrder` fora de ordem; `navPoint` sem `content`; XML inválido |
| `reconcile_test.dart` | órfãos no começo, no meio, no fim e consecutivos; `linear="no"` não é órfão e entrada existente para ele é mantida; alvo fora do spine mantido; sem TOC → tudo sintetizado; `details.orphans` |
| `cover_test.dart` | os três passos, `missing` e `remote` pulados, nenhum |
| `read_publication_test.dart` | orquestrador sobre EPUBs montados com o `ZipWriter`: tentativa dupla de `%xx`, travessia por `%2e%2e`, `remote`, `fallback` em cadeia e em ciclo, NAV quebrado → NCX, NAV em diretório diferente do OPF, `#frag` do próprio documento, casamento sem diferenciar maiúsculas, sem NAV nem NCX, rootfile inexistente seguido de válido, tetos, `strict` (exceção do sink propaga; warning da Publicação lança `EpubPackageException`), ofuscação sobre conteúdo; e com `ProviderContainer`, inclusive `exists` que lança |
| `publication_corpus_test.dart` | os 65 EPUBs (§10.1) |

Também: uma asserção de `details.delta` no teste de prefixo do
`zip_container_test` (§1.3), e `EpubPackageException`, `EpubMetadata`,
`EpubReadingDirection` e `EpubLayoutMode` no teste da API pública.

### 10.1 Teste de corpus

- Os casos cujo `exception.expected` é `EpubContainerException` ou
  `EpubEncryptedException` falham no contêiner e ficam de fora.
- `patologia/opf-sem-spine` lança `EpubPackageException`.
- **Códigos comparados:** `resourceMissing`, `spineItemUnresolved`,
  `spineItemDuplicate`, `unsupportedMediaType`, `tocReconciled`, `coverHeuristic`,
  `navIgnored`, `resourceUnreadable`. O **conjunto** desses códigos emitidos é
  igual ao conjunto deles em `diagnostics.expected`. `encodingFallback` não entra
  na igualdade (o do `.expected` pode ser de seção, do sub-projeto 4): se a
  Publicação o emitir, ele precisa constar do `.expected`.
- Todo `ManifestItem` com `missing: false` e `remote: false` existe no contêiner.
- **Modo:** `strict: true` em todos os grupos exceto `patologia/` e `faixa-b/`
  ([10](../10-testes.md) §5), **e exceto** os casos cujo `diagnostics.expected`
  lista um código comparado de severidade `warning`; esses rodam sem `strict` e
  ganham uma segunda passada em `strict` esperando `EpubPackageException` com o
  nome do código na mensagem.
- **Correção do corpus:** `reais/alice-ilustrada-en`, `reais/candide-fr`,
  `reais/dom-casmurro-pt` e `reais/os-lusiadas-pt` ganham `diagnostics.expected`
  com `tocReconciled` (a capa e, na Alice, as páginas de ilustração não estão no
  NAV).
- **Asserções específicas:**
  - `opf-em-subpasta`: todos os itens resolvem, nenhum `missing`.
  - `href-barra-invertida` e `href-url-encoded`: o item resolve para o arquivo do
    ZIP.
  - `nav-ncx-divergentes`: TOC com as quatro entradas "Capítulo 1–4" do NAV,
    nenhuma sintetizada.
  - `ncx-incompleto-orfaos`: seis entradas na ordem do spine, três sintetizadas
    (índices 1, 3 e 5).
  - `linear-no`: a entrada "Notas" do NAV é mantida (`synthesized: false`),
    nenhuma entrada é sintetizada, e o item está no spine com `linear: false`.
  - `page-list-tres-fontes`: 12 entradas, rótulos `1`–`12`, fragmentos
    `pg1`–`pg12`, do NAV.
  - `toc-6-niveis`: profundidade 6.
  - `spine-800-itens`: 800 itens no spine.
  - `spine-so-imagem`: `SectionKind.image`.
  - `capa-ausente`: `coverPath` `null`.
  - `reais/moby-dick-en`: `authors == ['Herman Melville']`, `subtitle == 'Or, The
    Whale'`, `series == null`.

## 11. Desempenho

Caso novo no harness: `publication.read.800` — `readPublication` sobre um
`ZipContainer` já aberto de `test/corpus/estrutura/spine-800-itens/book.epub`
(com `MemoryEpubByteSource`; a abertura fica no `setUp`), com `innerIterations`
para ~5 ms por amostra. Os baselines por CPU ganham o caso na próxima
regeneração.

## 12. Documentos a atualizar

- [03](../03-camada-a-ir.md) §3: o modelo (`spine`/`coverPath`/`NavPoint` aqui,
  `readingOrder`/`coverHref`/`EpubTocEntry` públicos no sub-projeto 6; `totalChars`
  da IR); §3.1: regra de posição dos órfãos e o gancho do título pelo heading;
  §3.2: diagnóstico e `href` de cada linha, `remote`, `fallback`.
- [06](../06-locator-navegacao.md) §3: fontes do `page-list` (NAV e NCX aqui, corpo
  no sub-projeto 4); §5: `raw` = não mapeado, regras de título, autor, série e
  datas; §5.1: passos da capa feitos e pendentes.
- [09](../09-erros-diagnosticos.md) §2: `EpubPackageException` implementada, com a
  tabela de §9.1; §3: `navIgnored`, `spineItemDuplicate`; §4: conferência de
  ofuscação pelo `media-type`.
- [10](../10-testes.md) §5: a regra de `strict` de §10.1.
- [11](../11-empacotamento-versionamento.md) §4: `lib/src/publication/`.
- [14](../14-pendencias.md): os ganchos de §1.1 com o sub-projeto dono; as duas
  pendências movidas para o sub-projeto 6 (§1.3); entradas sintetizadas com nome
  de arquivo em livros com páginas de imagem (a UI pode escondê-las por
  `synthesized`); regenerar baselines com `publication.read.800`.
- `test/corpus/corpus_test.dart`: `knownDiagnostics` com `navIgnored` e
  `spineItemDuplicate`.
- `test/corpus/reais/*/diagnostics.expected` dos quatro casos de §10.1.
