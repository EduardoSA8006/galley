# 09 — Erros, diagnósticos e degradação

Este documento é a implementação concreta do contrato de fidelidade
([00](00-visao-geral.md) §3): "nunca falha em silêncio" precisa de um canal, e
"nenhum byte descartado" precisa de uma política de recuperação.

**Emenda 15: tipos de exceção e momento de lançamento.**

## 1. Princípio

> **Falha de seção nunca derruba o livro.**
> Só quatro condições são fatais para a abertura: ZIP inválido, `container.xml`
> ausente, OPF inválido e spine vazio. Uma quinta, DRM não suportado, é fatal por
> honestidade: não há nada legível para mostrar. Ela inclui `encryption.xml`
> ilegível (sem como provar que não há DRM) e ZIP com a criptografia do próprio
> formato (bit 0 da flag).

Qualquer outra falha produz uma seção degradada mais um diagnóstico.

## 2. Taxonomia de exceções

```dart
abstract base class EpubException implements Exception {
  String get message;
  String? get href;
  Object? get cause;
}
```

`abstract base`, não `sealed`: adicionar uma exceção nova não deve quebrar
`switch` de consumidores ([11](11-empacotamento-versionamento.md) §3.3).

| Exceção | Quando | Fatal? | Recuperação |
|---|---|---|---|
| `EpubContainerException` | ZIP corrompido (EOCD ou central directory ilegível), `container.xml` ausente; depois de `open`, entrada ilegível (método não suportado, dados corrompidos, acima de `maxEntrySize`) | **Sim**, em `open`; depois dele, é falha de uma entrada | Entrada ilegível vira seção `placeholder` com `resourceUnreadable`; só é fatal quando é o `container.xml` ou o OPF |
| `EpubPackageException` | OPF ausente (nenhum `rootfile` existe), acima de 4 MiB, com XML inválido, raiz que não é `package` ou sem `manifest`/`spine`; spine vazio depois de descartar `idref` sem item; em `strict`, também todo warning da Publicação, com o nome do código na mensagem ([spec da Publicação](specs/2026-09-26-publication-design.md) §9.1) | **Sim**, em `open` | — |
| `EpubEncryptedException` | `META-INF/license.lcpl`, `rights.xml`, o bit 0 da flag do ZIP, ou `encryption.xml` com esquema de DRM sobre conteúdo — inclusive `encryption.xml` ilegível ou acima do teto de tamanho (§4) | **Sim**, em `open`, com o esquema na mensagem (§4) | Provider que decifra ([07](07-api-publica.md) §4) |
| `EpubUnsupportedException` | `EpubFidelity.faithful` na v1.0; `layout == prePaginated` na v1.0 | **Sim**, na construção de `EpubLayoutEngine`/`EpubReader` (não em `open`: o app ainda pode ler metadados e capa) | — |
| `EpubResourceMissingException` | `href` do manifest sem arquivo no ZIP | Não | Seção `placeholder` |
| `EpubSectionParseException` | XHTML irrecuperável; em `strict`, também todo warning do CSS, com o nome do código na mensagem ([spec do CSS](specs/2026-09-26-css-design.md) §12.3); implementada, interna até o sub-projeto 6 | Não | Seção `placeholder` com o texto cru extraído; antes de converter, o placeholder (do sub-projeto 4, que ainda não existe) deve relançar por identidade a última exceção de `strict` do sink da seção e a do sink do contêiner |
| `EpubDecodeException` | Encoding irrecuperável | Não | U+FFFD nos bytes inválidos |
| `EpubCacheException` | Cache corrompido ou store indisponível | Não | Recomputa |
| `EpubCancelledException` | Token cancelado | Não | Silenciosa, esperada |
| `EpubLocatorException` | Locator com `href` que não existe no spine | Não | `LocatorResolution` com confiança 0 apontando para o início do livro, mais diagnóstico |

As não-fatais nunca chegam ao app como exceção; são convertidas em diagnóstico
e degradação dentro do pacote. A tabela as lista porque existem internamente e
aparecem em `EpubDiagnostic.details['exception']`.

### 2.1 Seção de placeholder

```dart
Section(
  href: href,
  canonicalText: /* texto cru extraído, se houver, mais "\n" */,
  blocks: [Block(kind: BlockKind.placeholder, ...)],
  diagnostics: [/* a causa */],
)
```

Ela participa normalmente do spine, do progresso e da paginação. É isso que
garante que o **contrato de cobertura de texto** ([10](10-testes.md) §2) continue
válido mesmo em livro parcialmente quebrado.

O placeholder é pintado como um bloco de texto normal com a mensagem em `info`
(por exemplo "Recurso `cap07.xhtml` ausente do arquivo"), na tipografia do
motor. Nunca uma caixa vazia.

## 3. Diagnósticos

Diagnóstico não é erro. É o canal da "degradação declarada".

```dart
final class EpubDiagnostic {
  final EpubDiagnosticCode code;
  final EpubSeverity severity;   // info, warning
  final String? href;
  final int? charOffset;
  final String message;
  final Map<String, Object?> details;
}

/// Classe com constantes, não enum: cresce sem quebrar consumidores
/// (11 §3.3). Compare por identidade ou por `name`.
final class EpubDiagnosticCode {
  final String name;
  final EpubSeverity defaultSeverity;
  const EpubDiagnosticCode._(this.name, this.defaultSeverity);

  static const unsupportedLayout = EpubDiagnosticCode._('unsupportedLayout', EpubSeverity.warning);
  // ...
}
```

| Código | Severidade | Significado |
|---|---|---|
| `unsupportedLayout` | warning | Faixa B: `float`, `columns`, `writing-mode`, `position`; emitido quando o valor degradado vence a cascata num elemento, uma vez por (seção, propriedade), com `href` = seção e `details.property`/`value` |
| `unsupportedMath` | warning | MathML presente; renderizado o fallback ou o texto |
| `unsupportedMediaType` | warning | Item do spine que não é XHTML nem imagem |
| `rubyFlattened` | info | Ruby renderizado sem anotação sobreposta |
| `resourceMissing` | warning | Recurso do manifest ausente |
| `spineItemUnresolved` | warning | `idref` do spine sem item no manifest |
| `encodingFallback` | info | Encoding declarado falhou; qual foi usado |
| `unknownEntity` | info | Entidade de DTD externa não resolvida |
| `imageWithoutAlt` | info | Imagem sem `alt`, impacto de acessibilidade |
| `imageWithoutIntrinsicSize` | info | Repaginação ocorreu quando a imagem chegou |
| `imageDecodeFailed` | warning | Bytes da imagem não decodificaram |
| `inlineImagePromoted` | info | Imagem inline alta demais virou bloco |
| `svgUnrasterized` | warning | SVG sem rasterizador injetado |
| `anchorNotFound` | warning | `id` de link ou TOC ausente no documento |
| `locatorRepaired` | warning | Offset não validou; offset antigo, novo e confiança |
| `tocReconciled` | info | Itens órfãos do spine inseridos no TOC |
| `coverHeuristic` | info | Capa encontrada por heurística, qual |
| `navIgnored` | info | NAV ou NCX não usado; `details.reason`: `missing`, `too-large`, `unreadable`, `invalid`, `no-toc` ou `truncated` |
| `spineItemDuplicate` | info | `idref` (ou caminho) repetido no spine; vale o primeiro |
| `stylesheetIgnored` | warning | Folha, ou parte dela, perdida; `details.reason`: `too-large`, `cycle`, `depth`, `limit` (com `details.limit`: `sheets`, `attempts`, `bytes`, `rules`, `nesting` ou `dom-depth`), `late-import`, `unsupported-import` ou `budget` |
| `stylesheetMediaIgnored` | info | `media` que não casa com `screen`/`all` (`<link>`, `<style>`, `@import`, blocos `@media`); `details.media` |
| `cssRuleIgnored` | info | Regra, seletor ou declaração de CSS descartada; `details.reason`: `parse-error`, `unsupported-selector` ou `nested-rule`; agregado por folha, com `details.discarded` e `details.sample` |
| `cacheMiss` | info | Recomputou por falha de cache |
| `mimetypeIrregular` | info | `mimetype` ausente, fora do primeiro lugar, comprimido, com conteúdo errado ou ilegível, ou ZIP com prefixo; o motivo em `details.reason` |
| `zipCrcMismatch` | warning | CRC-32 divergente (`reason: crc`) ou saída menor que a declarada (`reason: size`); sempre verificado |
| `zipDuplicateEntry` | info | Nome repetido no central directory; vale a primeira entrada |
| `pathCaseMismatch` | info | Caminho achado só sem diferenciar maiúsculas; o nome real em `details.actual` |
| `resourceUnreadable` | warning | Entrada ilegível convertida em placeholder; `details.reason` e `details.exception` |
| `encryptionIgnored` | info | `encryption.xml` inválido num livro servido por `EpubResourceProvider`; ofuscação ignorada |
| `indivisibleBlock` | warning | Bloco não divisível maior que a página |
| `tableOverflow` | warning | Tabela mais larga que a página mesmo após escala; rolagem horizontal |
| `truncatedColSpan` | info | `colspan` colidiria com um slot já ocupado da grade; truncado para não sobrepor células ([04](04-layout-paginacao.md) §9) |
| `truncatedRowSpan` | info | `rowspan` passa do fim da tabela; truncado |
| `fragmentedRowSpan` | info | Grupo de linhas ligadas por `rowspan` maior que a página; quebrado entre as linhas do grupo |
| `headerNotRepeated` | info | Cabeçalho de tabela acima de 50% da altura da página; não repetido nas páginas seguintes |
| `viewportTooSmall` | warning | Coluna com menos de 3 linhas; regras de órfã e viúva desligadas |
| `fontObfuscationUnknown` | warning | Fonte com algoritmo de ofuscação não reconhecido; fonte ignorada |
| `sectionTooLarge` | info | Seção acima de 2 MB de XHTML; parse fatiado com prioridade reduzida |

### 3.1 Entrega

- **Por seção:** `Section.diagnostics`, acessível pela Camada 3
- **Em tempo real:** callback `onDiagnostic` do `EpubReader` e
  `doc.diagnosticStream`
- **Agregado:** `doc.diagnostics` acumula tudo emitido até agora

Diagnósticos são **deduplicados por `(code, href)`**, senão um livro com 400
imagens sem `alt` produz 400 eventos idênticos. O agregado guarda a contagem em
`details['count']`.

O CSS emite no sink **da seção** e reemite, a cada seção que aplica uma folha,
o que ele mesmo registrou dela (o `encodingFallback`, os diagnósticos de parse
e a falta), mesmo quando a folha vem do cache de folhas; os do contêiner
(`pathCaseMismatch`, `zipCrcMismatch`) ficam no sink dele, uma vez por
publicação. Os de parse do CSS saem agregados por folha: no máximo um por
(código, motivo), com `details.discarded`
([spec do CSS](specs/2026-09-26-css-design.md) §9.6 e §12.1).

Diagnósticos de parse (Camada A) são serializados no cache com a seção e
re-emitidos ao carregar do cache, para que a telemetria do app não dependa de
cache frio.

### 3.2 Uso esperado pelo app

Nada obriga o app a mostrar diagnóstico ao usuário. O uso pretendido é telemetria
e depuração: você descobre que 8% do seu acervo usa `writing-mode` vertical antes
de o usuário reclamar.

## 4. `encryption.xml`

`META-INF/encryption.xml` aparece em dois cenários bem diferentes, e confundi-los
produz tela em branco sem explicação.

| Cenário | Detecção | Tratamento na v1.0 |
|---|---|---|
| **Ofuscação de fonte** | `EncryptionMethod Algorithm` igual a `http://www.idpf.org/2008/embedding` ou `http://ns.adobe.com/pdf/enc#RC`, aplicado só a arquivos de fonte | Desofuscar: XOR dos primeiros 1040 bytes (IDPF) ou 1024 bytes (Adobe) com chave derivada do identificador: IDPF usa o SHA-1 da **concatenação de todos os `unique-identifier`** com espaço, CR, LF e TAB removidos; Adobe usa os 16 bytes do UUID (sem `urn:uuid:` e hifens). Validado no spike S6 com ida e volta byte a byte sobre uma fonte real e carregamento via `FontLoader`. **Suportado** |
| **DRM real** (LCP, ACS, proprietário) | `META-INF/license.lcpl` (LCP); `META-INF/rights.xml` (ADEPT pelo namespace `http://ns.adobe.com/adept`, senão desconhecido); `KeyInfo` com o `RetrievalMethod` do LCP ou com elemento do namespace do ADEPT; qualquer outro algoritmo, ou algoritmo de fonte aplicado a conteúdo; `encryption.xml` que não é XML válido; bit 0 da flag do ZIP | `EpubEncryptedException`, fatal, com o esquema identificado na mensagem (`lcp`, `adobe-adept`, `zip-encryption`, `unknown:<detalhe>`) |
| **Ofuscação desconhecida em fonte** | Algoritmo não reconhecido aplicado só a fontes | Fonte ignorada, diagnóstico `fontObfuscationUnknown`, texto renderiza com fallback. Não é fatal: fonte é Classe 3 |

Na abertura do `ZipContainer`, a detecção de DRM roda **antes** da checagem do
`mimetype` (inclusive do diagnóstico de prefixo, item 4 da lista acima), para
que um livro com DRM em `strict` não apareça como arquivo corrompido. A
leitura do `encryption.xml` navega pela estrutura do XML-Enc por filhos
diretos (`EncryptedData > CipherData > CipherReference`,
`EncryptedData > KeyInfo`, `KeyInfo > RetrievalMethod`), por nome local em
qualquer namespace; a busca do namespace ADEPT dentro do `KeyInfo` não desce
para `EncryptedData` aninhados.

A checagem do contêiner é pela extensão; a Publicação confere, pelo
`media-type` do manifest, que a ofuscação declarada é mesmo sobre fonte
(`font/*`, `application/font-*`, `application/x-font-*`,
`application/vnd.ms-opentype` ou o genérico `application/octet-stream`): um
item de conteúdo com extensão de fonte e ofuscação declarada é
`EpubEncryptedException` com `unknown:obfuscation-on-content`
([spec da Publicação](specs/2026-09-26-publication-design.md) §8.1).

`encryption.xml` e `rights.xml` têm um teto próprio de tamanho,
`maxMetadataSize` (4 MiB): livros reais têm poucos KiB, e ler/parsear um
arquivo maior só serviria para um atacante gastar tempo e memória na
abertura (a checagem usa o `uncompressedSize` do central directory, sem
buscar nem descomprimir a entrada). Acima do teto, o resultado é o mesmo do
XML inválido: `unknown:encryption.xml-invalido` ou `unknown:rights.xml`.

O pacote **não implementa DRM** e não pretende. Mas identificar o esquema e
falhar com mensagem clara é obrigação: o app precisa poder dizer ao usuário
"este arquivo tem proteção LCP" em vez de "erro ao abrir".

Ganchos para DRM externo já existem via `EpubResourceProvider` customizado que
decifra antes de devolver os bytes ([07](07-api-publica.md) §4). Com `provider`,
o pacote **não** lê `encryption.xml` para decidir fatalidade; presume que o
provider entrega bytes claros. Por isso o `ProviderContainer` **ignora** uma
entrada de cifra de DRM (LCP, ADEPT ou algoritmo do namespace
`http://www.w3.org/2001/04/xmlenc#`) sobre uma fonte: ela já chega decifrada,
e tratá-la como "ofuscação desconhecida" seria um falso `fontObfuscationUnknown`
sobre um recurso legível. Só a ofuscação de fonte de verdade (IDPF, Adobe) e
um algoritmo realmente desconhecido continuam pela tabela acima. Falta
documentar o padrão com um exemplo ([12-roadmap.md](12-roadmap.md)).

## 5. Modo estrito para testes

```dart
EpubDocument.open(..., strict: true)
```

Com `strict: true`:

- qualquer diagnóstico de severidade `warning` vira exceção
- CRC-32 divergente (sempre verificado) vira exceção
- `mimetype` irregular vira `warning`

Usado **apenas** nos testes de corpus, para que uma regressão de parse não passe
como "degradação aceitável".
