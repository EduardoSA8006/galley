# Publicação (Fase 1, sub-projeto 2) — plano de implementação

> **Para agentes:** SUB-SKILL OBRIGATÓRIA: use superpowers:subagent-driven-development
> (recomendado) ou superpowers:executing-plans para executar tarefa por tarefa. Os
> passos usam checkbox (`- [ ]`).

**Objetivo:** a partir de um `EpubContainer` (sub-projeto 1), produzir a
`EpubPublication` — metadados, manifest com caminhos resolvidos, ordem de
leitura com `fallback`, TOC reconciliado com o spine, landmarks, `page-list`,
capa, direção e layout —, sem nunca abrir uma seção e sem deixar escapar
exceção fora de `EpubException` com arquivo hostil.

**Arquitetura:** parsers puros e síncronos em `lib/src/publication/`, um por
documento (`parseContainerXml`, `parseOpf`, `parseNcx` com `package:xml`;
`parseNav` com `package:html`), funções puras de caminho (`normalizeHref`,
`splitFragment`, `decodePath`), de decodificação (`decodeXml`), de
reconciliação (`reconcileToc`) e de capa (`findCover`), e um orquestrador
assíncrono, `readPublication`, que faz as leituras com `fetch`/`exists`,
resolve os caminhos contra o contêiner e emite os diagnósticos pelo
`DiagnosticSink`. Os parsers devolvem `href` crus; só o orquestrador resolve.
Todo laço e toda recursão sobre dado do arquivo tem teto (§7.2) ou é linear
por construção, e o NAV passa por uma estimativa linear do custo do parser
HTML5 antes do parse.

**Stack:** Flutter 3.47.0 (Dart 3.13), `package:xml` 7.0.1 (`namespaceUri:`),
`package:html` 0.15.x (resolvido 0.15.7), `flutter_test`. Nada novo no
`pubspec.yaml`.

**Spec:** `doc/specs/2026-09-26-publication-design.md`. Leia inteira antes de
começar; este plano argumenta a partir dela (os `§` sem documento são dela).

## Restrições globais

- Dart `^3.13.0`, Flutter `>=3.47.0`. Nenhuma dependência nova, nem de
  desenvolvimento (`html`, `xml` e `meta` já estão no `pubspec.yaml`).
- A preferência global por feature-first, MVVM, Result e Riverpod **não** vale
  aqui: é pacote, com erros por exceção e diagnóstico (spec §1.1).
- Código em `lib/` nunca importa `tool/` nem `test/`; `lib/src/publication/`
  não importa `dart:io` (o teste de API da Tarefa 11 confere a regra do
  `*_io.dart`).
- Testes importam `lib/` por `package:galley/...` (inclusive `src/`). Arquivo
  de teste que importa `tool/` por caminho relativo leva, antes dos imports:
  `// ignore_for_file: avoid_relative_lib_imports — tool/ não é pacote; importar por caminho é intencional.`
  (só o `perf_test.dart` faz isso aqui; os testes da Publicação chegam ao
  `ZipWriter` por `test/container/support/zip_fixtures.dart`).
- `analysis_options.yaml` tem `strict-casts`, `strict-inference`,
  `strict-raw-types`, `prefer_final_locals`, `prefer_const_constructors` e
  `unawaited_futures`: todo passo termina com `flutter analyze` limpo e
  `dart format` sem mudança.
- Constantes: `maxPackageDocumentSize = 4 * 1024 * 1024`; `maxNavDepth = 64`;
  `maxNavEntries = 100000` (por `nav`/lista); `maxFallbackSteps = 16`;
  `encodingSniffBytes = 1024`; `navParseBudget = 1 << 24`.
- Nomes dos diagnósticos exatamente como na spec §9.2: `resourceMissing`,
  `spineItemUnresolved`, `unsupportedMediaType`, `encodingFallback`,
  `tocReconciled`, `coverHeuristic`, `navIgnored`, `spineItemDuplicate`
  (e o `resourceUnreadable` que já existe).
- Todo `emit` da Publicação passa `onStrict: (m) => EpubPackageException(m, href: …)`.
- Custo: nenhum laço, recursão ou alocação controlados por dados do arquivo
  sem limite. Proibido: `substring` em laço sobre o texto inteiro,
  `innerText`/`descendants` repetidos por elemento aninhado, indexar
  `children` do `package:html` (doc/03 §8). Cada tarefa de parser diz por que
  ele é linear.
- Nenhuma exceção fora de `EpubException` escapa de `readPublication` com
  arquivo hostil (`XmlException`, `FormatException`, `RangeError`,
  `StateError`); o fuzz da Tarefa 12 conta e exige zero.
- Texto em português brasileiro com acentuação; identificadores em inglês.
- Shell com alias interativo: use `\cp -f`, `\mv -f`, `\rm -rf` (o `cp` puro
  pede confirmação e trava comando não interativo); `ls` é `eza`.
- Nenhum arquivo de depuração versionado; rascunhos no scratchpad da sessão.
- Tudo na branch `fase1/publicacao` (já em checkout). Commits
  `feat(publication): …`, `test: …`, `docs: …`.

## O que foi verificado antes de escrever o plano

Todo o código deste plano rodou numa cópia do repositório no scratchpad
(`flutter analyze` limpo, `dart format` sem mudança, `flutter test` inteiro
verde e o `publication_corpus_test` passando nos 65 EPUBs). Depois de escrito,
o próprio plano foi reaplicado tarefa a tarefa sobre um `git worktree` limpo do
`HEAD` (um script extraiu cada bloco "Criar/Substituir" e cada troca, na ordem,
rodou o teste da tarefa antes da implementação — e viu falhar — e depois
dela): toda tarefa terminou com `dart format` sem mudança, `flutter analyze`
limpo e os testes dela verdes, com as contagens indicadas nos passos; o
bloco de commit de cada tarefa foi executado como está e deixou o
`git status` vazio (as listas de `git add` estão completas). A suíte passa
de 598 testes no `HEAD` para 846 (mais o de `perf`, pulado), e `lib/` e
`test/` do worktree reaplicado ficaram idênticos aos da cópia de trabalho. O
que se observou e o código depende:

- **`package:html` fica quadrático com aninhamento de elementos de bloco.** O
  parser HTML5 percorre a pilha de elementos abertos em várias tags (escopo de
  `p`, de lista, de botão). `<ol><li><a>` aninhado: 1 000 níveis 166 ms,
  2 000 375 ms, 4 000 1,3 s, 10 000 9,2 s, 50 000 **353 s**. `<div>` aninhado
  cresce igual; `<span>` aninhado e muitos atributos são lineares. Um NAV
  hostil de 1 MiB travaria o processo por minutos antes de qualquer teto de
  §7.2 entrar em jogo. Daí `htmlWorkCut` (Tarefa 7): uma varredura linear que
  estima o trabalho do parser (profundidade × tags) e corta o texto antes de
  passar de `navParseBudget`; o corte marca `truncated`, como a spec já prevê
  para "a parte lida é usada". Medido com o corte: NAV hostil de 4 MiB em
  0,4–0,6 s (profundidades 64, 256 e 2 000 com enxurrada de `<p>`); 100 000
  níveis de `<ol><li>` em 0,5 s; um NAV legítimo de 7 MB com 2 × 100 000
  entradas **não** é cortado (1,2 s).
- **`package:xml` 7.0.1:** `XmlDocument.parse` é por eventos e iterativo (200 000
  níveis aninhados em 314 ms, sem estouro de pilha); `descendantElements` usa
  pilha explícita; `getAttribute(nome, namespaceUri: '*')` casa por nome local
  (`opf:role` → `role`); `dc:title` com prefixo não declarado parseia
  (`namespaceUri` `null`, `name.prefix` `'dc'`); entidades desconhecidas
  (`&nbsp;`) ficam literais e `&#xD800;` é aceito; `DOCTYPE` externo (OEB 1.2 e
  NCX 2005-1) parseia sem buscar a DTD. `XmlParserException` e
  `XmlTagException` são `XmlException` **e** `FormatException` (mixin
  `XmlFormatException`): o orquestrador captura `XmlException`.
- `RegExp(r'\s')` do Dart casa U+00A0; o colapso de whitespace dos títulos de
  NAV e NCX usa a classe explícita do HTML/XML, para o `&nbsp;` sobreviver.
- `Uri.decodeComponent` lança `ArgumentError` com `%` malformado e
  `FormatException` com UTF-8 inválido; `DateTime.parse('+275760-09-14')`
  lança (fora do intervalo): as duas chamadas ficam em `try`.
- **Corpus:** com o código deste plano, os 65 casos batem com os `.expected`,
  exceto exatamente os quatro `reais/` que a spec §10.1 aponta, todos por
  `tocReconciled`: o invólucro da capa (`wrap0000.xhtml`) nos quatro, mais uma
  seção de texto em `candide-fr` e `dom-casmurro-pt` e 27 páginas de
  ilustração na Alice. Nenhum caso emite `navIgnored`. O NAV da Alice tem um
  `nav epub:type="landmarks"` que é, na verdade, uma lista de páginas (47
  entradas com `epub:type="normal"`): lido literalmente, como a spec manda.
- `readPublication` sobre `spine-800-itens` (contêiner já aberto) leva ≈ 27 ms
  no i5-11400H (OPF 5 ms, NAV 4 ms, NCX 6,4 ms, 800 `exists` 2 ms, três `fetch`
  1,4 ms): `innerIterations` fica em 1.
- Fuzz (Tarefa 12): 400 mutações de `container.xml`, OPF, NAV e NCX de quatro
  EPUBs do corpus, metade por `ZipContainer` e metade por `ProviderContainer`,
  um terço em `strict`: 242 `EpubException`, **0** fora da taxonomia. Com o
  `on XmlException` do NCX trocado por outro tipo, o mesmo fuzz acha 64
  `XmlParserException`/`XmlTagException` escapando: ele detecta a regressão.
- Harness local: `publication.read.800` com razão ≈ 5,6 (27 793 µs contra
  4 937 µs de calibração); sem baseline, aparece como "novo, sem baseline" e o
  `compare.dart` passa.

## Decisões onde a spec é ambígua

1. **Ordem das tarefas.** As tarefas 6 e 7 propostas (OPF em duas partes)
   viraram uma: `parseOpf` é uma função sobre um `OpfDocument` só, e dividi-la
   obrigaria a reescrever `opf.dart` inteiro na segunda. A tarefa 12 proposta
   virou duas (11: exports, teste de API e `details.delta`; 12: corpus,
   `.expected` dos `reais/` e fuzz), porque um revisor pode aprovar os exports
   e reprovar o corpus. O `knownDiagnostics` do `corpus_test.dart` vai na
   Tarefa 1, com os códigos. São 15 tarefas.
2. **`decodeXml` e o `<meta charset>` "só no NAV":** a assinatura da spec não
   diz qual documento é; ganha o parâmetro opcional `htmlMeta` (padrão
   `false`), passado `true` só para o NAV.
3. **Declaração de UTF-16 sem BOM:** a leitura "como ASCII" dos primeiros
   1 024 bytes pula os bytes 0, senão uma declaração em UTF-16 nunca seria
   legível. `utf-16` e `utf-16le` → UTF-16 LE; `utf-16be` → UTF-16 BE (a spec
   só cita `utf-16`). Byte ≥ 0x80 no trecho vira `?`.
4. **`encodingFallback.details.declared`:** o rótulo em minúsculas;
   `utf-8`/`utf-16le`/`utf-16be` quando veio do BOM; `null` sem declaração.
5. **`normalizeHref`:** faz `trim`; "caminho vazio" (passo 6) vale para o
   caminho **antes** da resolução (sem `?query`/`#fragmento`) e para o
   resultado. Assim `href=""`, `#x` e `?q` são recusados no manifest (no NAV,
   `#x` é tratado antes, §5.4).
6. **Manifest:** "sem `id`" inclui `id` vazio; `details.reason` é `no-id` ou
   `no-href`. `id` duplicado não emite diagnóstico. Item cujo caminho é o
   próprio OPF ou um diretório emite `resourceMissing` com `href` = caminho e
   `details.reason` `opf`/`directory` (a spec só diz `missing`).
7. **`exists` que lança:** o orquestrador captura `EpubContainerException`,
   que é o que o `ProviderContainer` produz para qualquer falha do provider;
   `StateError` de contêiner fechado é erro de programação e propaga.
8. **`opfPath`** é o nome real da entrada (`PendingResource.path`), que pode
   diferir em caixa do `full-path`: os `href` do OPF resolvem contra o
   diretório real. Um `pathCaseMismatch` sai no `fetch`.
9. **`container.xml` acima de `maxPackageDocumentSize`:**
   `EpubContainerException` (a spec só fala de OPF, NAV e NCX).
10. **Metadados (§6.2):** o texto de um `dc:*`/`meta` vem só dos filhos diretos
    (texto e CDATA), com `trim` — `innerText` seria quadrático em metadado
    aninhado; elemento de texto vazio é ignorado. "Virou campo" inclui os
    refinamentos usados para decidir (`title-type`, `role` de
    criador/colaborador, `collection-type`/`group-position` da série) e os
    `meta` que viram campo do `OpfDocument` (`cover`, `rendition:layout`
    global). Os `dc:identifier` que não são `metadata.identifier` vão para
    `raw['identifier']`, porque `EpubMetadata` (pública) só expõe um.
11. **Datas:** `YYYY-MM-DD` também sai em UTC; data de calendário inválida
    (`2021-02-29`, mês 13) e texto acima de 64 caracteres são `null`. O
    candidato escolhido pela regra que não parseia deixa o campo `null` (não
    se tenta o seguinte) e fica em `raw`.
12. **Série:** a primeira coleção que qualifica; coleção `set` fica em `raw`
    com os refinamentos; `seriesIndex` por `double.tryParse`.
13. **NAV:** `nav` de `toc` sem nenhuma entrada conta como "sem `nav` de `toc`"
    (`navIgnored` `no-toc`, e o NCX dá o TOC). `type` só é preenchido em
    landmarks. Listas dentro do rótulo não entram no título; `nav` aninhado
    não é revisitado (custo linear).
14. **Corte do NAV antes do parse** (`htmlWorkCut`, "O que foi verificado"):
    não está na spec; é o que torna §7.2 efetivo contra o custo do próprio
    parser. O corte usa `truncated`, com `navIgnored` `truncated`.
15. **Quando ler o NCX:** só se o NAV não deu TOC ou não deu `page-list`
    (precedência de §7.4). `navPath`/`ncxPath` são os documentos lidos e
    parseados (entram na chave do livro, doc/08 §4.1), mesmo que um deles não
    tenha contribuído com lista nenhuma.
16. **`strict` na leitura do NAV/NCX:** a exceção é do `DiagnosticSink` quando a
    mensagem é a de um warning registrado (`"<code>: <message>"`); generaliza
    o teste de prefixo `zipCrcMismatch:` do contêiner.
17. **Fontes (§8.1):** `application/octet-stream` também é aceito como
    `media-type` de fonte: é genérico, não declara conteúdo, produtores
    antigos o usam para fontes, e a IR não o renderiza como seção. Sem isso,
    um livro legítimo com fonte ofuscada declarada assim seria fatal.
18. **OEB 1.x:** `text/x-oeb1-document` conta como `SectionKind.xhtml`. A spec
    já lê OPF de OEB (`dc-metadata`, `dc:Title`); sem isso, todo livro OEB
    teria o spine inteiro `unsupported`.
19. **NAV ou NCX `remote`:** `navIgnored` com `reason: missing`.
20. **Landmarks do `guide`:** título com `trim`; título vazio vira o nome do
    arquivo do alvo, como no NAV.
21. **Segunda passada do corpus:** para todo caso cujo `diagnostics.expected`
    tem um código comparado `warning`, qualquer que seja o grupo; espera
    `EpubPackageException` com a mensagem começando por `"<código>: "`.
22. **`publication.read.800`:** `innerIterations: 1` (uma leitura já passa de
    5 ms).

## Foco de revisão

Os cinco modos de falha mais prováveis que a spec implica e que nenhum teste
das tarefas cobria (cada um ganhou o teste na tarefa dona):

1. **Livro OEB 1.2** (`DOCTYPE` externo, `dc` 1.0 em `dc-metadata`,
   `text/x-oeb1-document`): esperado ler metadados e ter o spine `xhtml`, não
   `unsupportedMediaType` em toda seção. Testes nas Tarefas 2 (`sectionKindOf`),
   6 (OPF) e 10 (orquestrador).
2. **NCX com o `DOCTYPE` do NCX 2005-1**, que quase todo EPUB2 traz: esperado
   ler normalmente, não `navIgnored` `invalid`. Teste na Tarefa 8.
3. **OPF na raiz do contêiner** (`full-path="content.opf"`, diretório vazio):
   esperado resolver `href` sem prefixo nem `/` inicial. Teste na Tarefa 10.
4. **OPF em UTF-16 com BOM** pelo orquestrador: esperado decodificar e
   parsear (a declaração `encoding="UTF-16"` fica no texto e o `package:xml`
   a ignora). Teste na Tarefa 10.
5. **Aninhamento hostil de 100 000 níveis** em `metadata` e em `navPoint`:
   esperado custo linear e nenhum `StackOverflowError`. Testes nas Tarefas 6
   e 8.

---

### Tarefa 1: Diagnósticos e `EpubPackageException`

Spec §9.1 e §9.2. Base das outras tarefas: os oito códigos novos e a exceção
que um warning da Publicação lança em `strict`. O `knownDiagnostics` do
`corpus_test.dart` ganha os dois códigos novos de doc/09 (spec §12).

**Arquivos:**
- Modificar: `lib/src/diagnostics/exceptions.dart` (substituir inteiro)
- Modificar: `lib/src/diagnostics/diagnostic.dart` (substituir inteiro)
- Modificar: `test/diagnostics/diagnostic_test.dart` (um grupo novo)
- Modificar: `test/corpus/corpus_test.dart` (`knownDiagnostics`)

**Interfaces:**
- Consome: `abstract base class EpubException implements Exception { EpubException(String message, {String? href, Object? cause}); @protected String get typeName; }`; `DiagnosticSink.emit(EpubDiagnosticCode code, {required String message, String? href, Map<String, Object?> details = const {}, EpubSeverity? severity, EpubException Function(String message)? onStrict})` — deduplica por `(code, href)` somando `details['count']` e, em `strict`, registra e lança `onStrict('<code.name>: <message>')` para todo `warning`.
- Produz: `final class EpubPackageException extends EpubException { EpubPackageException(String message, {String? href, Object? cause}); }` (`typeName` `'EpubPackageException'`).
- Produz: `EpubDiagnosticCode.resourceMissing` (warning), `.spineItemUnresolved` (warning), `.unsupportedMediaType` (warning), `.encodingFallback` (info), `.tocReconciled` (info), `.coverHeuristic` (info), `.navIgnored` (info), `.spineItemDuplicate` (info).

- [ ] **Passo 1: Escrever o teste que falha**

Em `test/diagnostics/diagnostic_test.dart`, trocar:

```dart
  group('EpubDiagnostic', () {
```

por:

```dart
  group('códigos da Publicação', () {
    test('oito códigos com a severidade de doc/09 §3', () {
      final codes = {
        EpubDiagnosticCode.resourceMissing: EpubSeverity.warning,
        EpubDiagnosticCode.spineItemUnresolved: EpubSeverity.warning,
        EpubDiagnosticCode.unsupportedMediaType: EpubSeverity.warning,
        EpubDiagnosticCode.encodingFallback: EpubSeverity.info,
        EpubDiagnosticCode.tocReconciled: EpubSeverity.info,
        EpubDiagnosticCode.coverHeuristic: EpubSeverity.info,
        EpubDiagnosticCode.navIgnored: EpubSeverity.info,
        EpubDiagnosticCode.spineItemDuplicate: EpubSeverity.info,
      };
      for (final MapEntry(key: code, value: severity) in codes.entries) {
        expect(code.defaultSeverity, severity, reason: code.name);
        expect(code.toString(), code.name);
      }
      expect(codes.keys.map((c) => c.name).toSet(), {
        'resourceMissing',
        'spineItemUnresolved',
        'unsupportedMediaType',
        'encodingFallback',
        'tocReconciled',
        'coverHeuristic',
        'navIgnored',
        'spineItemDuplicate',
      });
    });

    test('EpubPackageException: toString, href e cause', () {
      const cause = FormatException('xml');
      final e = EpubPackageException(
        'OPF ausente',
        href: 'a.opf',
        cause: cause,
      );
      expect(e.toString(), 'EpubPackageException(a.opf): OPF ausente');
      expect(e.cause, same(cause));
      expect(e, isA<EpubException>());
    });

    test('strict: onStrict da Publicação lança EpubPackageException', () {
      final sink = DiagnosticSink(strict: true);
      expect(
        () => sink.emit(
          EpubDiagnosticCode.resourceMissing,
          href: 'OEBPS/a.xhtml',
          message: 'sem arquivo',
          onStrict: (m) => EpubPackageException(m, href: 'OEBPS/a.xhtml'),
        ),
        throwsA(
          isA<EpubPackageException>().having(
            (e) => e.message,
            'message',
            'resourceMissing: sem arquivo',
          ),
        ),
      );
    });
  });

  group('EpubDiagnostic', () {
```

- [ ] **Passo 2: Rodar e ver falhar**

Run: `flutter test test/diagnostics/diagnostic_test.dart`
Expected: FAIL na compilação, com `Member not found: 'resourceMissing'` e
`Method not found: 'EpubPackageException'`.

- [ ] **Passo 3: A exceção**

Substituir `lib/src/diagnostics/exceptions.dart` inteiro por:

```dart
/// Exceções do pacote (doc/09 §2). As desta etapa: contêiner, pacote e DRM.
library;

import 'package:meta/meta.dart';

/// Raiz da taxonomia. `abstract base`, não `sealed`: uma exceção nova não
/// quebra `switch` de consumidores (doc/11 §3.3).
abstract base class EpubException implements Exception {
  EpubException(this.message, {this.href, this.cause});

  final String message;

  /// Caminho da entrada envolvida, quando há uma.
  final String? href;

  /// Exceção embrulhada (FormatException, XmlException, FileSystemException).
  final Object? cause;

  /// Nome do tipo em `toString`. Literal, e não `runtimeType`, porque o
  /// dart2js minifica nomes de tipo em release.
  @protected
  String get typeName;

  @override
  String toString() =>
      href == null ? '$typeName: $message' : '$typeName($href): $message';
}

/// ZIP ilegível. Fatal em `ZipContainer.open`; depois dele, é falha de uma
/// entrada (spec do contêiner §4.1).
final class EpubContainerException extends EpubException {
  EpubContainerException(super.message, {super.href, super.cause});

  @override
  String get typeName => 'EpubContainerException';
}

/// DRM que o pacote não decifra. Fatal em `open` (doc/09 §4).
final class EpubEncryptedException extends EpubException {
  EpubEncryptedException(
    super.message, {
    required this.scheme,
    super.href,
    super.cause,
  });

  /// `lcp`, `adobe-adept`, `zip-encryption` ou `unknown:<detalhe>`.
  final String scheme;

  @override
  String get typeName => 'EpubEncryptedException';
}

/// Pacote inválido: OPF ausente, ilegível como XML, sem `manifest` ou
/// `spine`, spine vazio (spec da Publicação §9.1). Também é o tipo que um
/// warning da Publicação lança em `strict`.
final class EpubPackageException extends EpubException {
  EpubPackageException(super.message, {super.href, super.cause});

  @override
  String get typeName => 'EpubPackageException';
}
```

- [ ] **Passo 4: Os códigos**

Substituir `lib/src/diagnostics/diagnostic.dart` inteiro por (as sete
constantes do contêiner, o `EpubDiagnostic` e o `DiagnosticSink` não mudam):

```dart
/// Diagnósticos (doc/09 §3) e o coletor usado por todas as camadas.
library;

import 'exceptions.dart';

enum EpubSeverity { info, warning }

/// Classe com constantes, não enum: cresce sem quebrar consumidores
/// (doc/11 §3.3). Compare por identidade ou por [name].
final class EpubDiagnosticCode {
  const EpubDiagnosticCode._(this.name, this.defaultSeverity);

  final String name;
  final EpubSeverity defaultSeverity;

  /// `mimetype` ausente, fora do lugar, comprimido, com conteúdo errado,
  /// ilegível, ou ZIP com prefixo. `details.reason` diz qual.
  static const mimetypeIrregular = EpubDiagnosticCode._(
    'mimetypeIrregular',
    EpubSeverity.info,
  );

  /// CRC-32 divergente (`reason: 'crc'`) ou saída menor que a declarada
  /// (`reason: 'size'`).
  static const zipCrcMismatch = EpubDiagnosticCode._(
    'zipCrcMismatch',
    EpubSeverity.warning,
  );

  /// Nome repetido no central directory; vale a primeira entrada.
  static const zipDuplicateEntry = EpubDiagnosticCode._(
    'zipDuplicateEntry',
    EpubSeverity.info,
  );

  /// Caminho achado só sem diferenciar maiúsculas; `details.actual`.
  static const pathCaseMismatch = EpubDiagnosticCode._(
    'pathCaseMismatch',
    EpubSeverity.info,
  );

  /// Fonte com ofuscação não reconhecida ou sem chave utilizável.
  static const fontObfuscationUnknown = EpubDiagnosticCode._(
    'fontObfuscationUnknown',
    EpubSeverity.warning,
  );

  /// `encryption.xml` inválido num livro servido por provider.
  static const encryptionIgnored = EpubDiagnosticCode._(
    'encryptionIgnored',
    EpubSeverity.info,
  );

  /// Entrada ilegível convertida em placeholder (sub-projetos 2 e 4).
  static const resourceUnreadable = EpubDiagnosticCode._(
    'resourceUnreadable',
    EpubSeverity.warning,
  );

  /// Item do manifest sem arquivo no contêiner, com `href` recusado, ou
  /// descartado por falta de `id`/`href` (spec da Publicação §5.3, §6.3).
  static const resourceMissing = EpubDiagnosticCode._(
    'resourceMissing',
    EpubSeverity.warning,
  );

  /// `idref` do spine sem item no manifest; o `itemref` é ignorado.
  static const spineItemUnresolved = EpubDiagnosticCode._(
    'spineItemUnresolved',
    EpubSeverity.warning,
  );

  /// Item do spine que não é XHTML nem imagem e cuja cadeia de `fallback`
  /// não resolve; `details.mediaType`.
  static const unsupportedMediaType = EpubDiagnosticCode._(
    'unsupportedMediaType',
    EpubSeverity.warning,
  );

  /// Encoding declarado (ou UTF-8 padrão) falhou; `details.declared` e
  /// `details.used`.
  static const encodingFallback = EpubDiagnosticCode._(
    'encodingFallback',
    EpubSeverity.info,
  );

  /// Itens órfãos do spine inseridos no TOC; `details.orphans`.
  static const tocReconciled = EpubDiagnosticCode._(
    'tocReconciled',
    EpubSeverity.info,
  );

  /// Capa achada por heurística (id ou caminho com "cover").
  static const coverHeuristic = EpubDiagnosticCode._(
    'coverHeuristic',
    EpubSeverity.info,
  );

  /// NAV ou NCX não usado; o motivo em `details.reason`.
  static const navIgnored = EpubDiagnosticCode._(
    'navIgnored',
    EpubSeverity.info,
  );

  /// `idref` (ou caminho) repetido no spine; vale o primeiro.
  static const spineItemDuplicate = EpubDiagnosticCode._(
    'spineItemDuplicate',
    EpubSeverity.info,
  );

  @override
  String toString() => name;
}

/// Diagnóstico imutável; [details] é unmodifiable.
final class EpubDiagnostic {
  EpubDiagnostic({
    required this.code,
    required this.severity,
    required this.message,
    this.href,
    this.charOffset,
    Map<String, Object?> details = const {},
  }) : details = Map.unmodifiable(details);

  final EpubDiagnosticCode code;
  final EpubSeverity severity;
  final String? href;
  final int? charOffset;
  final String message;
  final Map<String, Object?> details;

  @override
  String toString() =>
      'EpubDiagnostic(${code.name}, ${severity.name}'
      '${href == null ? '' : ', $href'}): $message';
}

/// Coletor de diagnósticos de um documento. Deduplica por `(code, href)` e,
/// em [strict], transforma `warning` em exceção (doc/09 §5).
final class DiagnosticSink {
  DiagnosticSink({this.strict = false});

  final bool strict;

  final List<EpubDiagnostic> _items = [];
  final Map<(String, String?), int> _index = {};

  /// Em ordem de primeira emissão.
  List<EpubDiagnostic> get diagnostics => List.unmodifiable(_items);

  /// Registra um diagnóstico. A repetição de `(code, href)` substitui a
  /// instância anterior, na mesma posição, com `details['count']` somado.
  ///
  /// Em [strict], `mimetypeIrregular` sobe para `warning`, e todo `warning` é
  /// registrado e depois lançado como a exceção de [onStrict] (padrão:
  /// [EpubContainerException] com [href]), com o nome do código na mensagem.
  void emit(
    EpubDiagnosticCode code, {
    required String message,
    String? href,
    Map<String, Object?> details = const {},
    EpubSeverity? severity,
    EpubException Function(String message)? onStrict,
  }) {
    var effective = severity ?? code.defaultSeverity;
    if (strict && identical(code, EpubDiagnosticCode.mimetypeIrregular)) {
      effective = EpubSeverity.warning;
    }
    final key = (code.name, href);
    final at = _index[key];
    final previous = at == null ? 0 : (_items[at].details['count']! as int);
    final diagnostic = EpubDiagnostic(
      code: code,
      severity: effective,
      href: href,
      message: message,
      details: {...details, 'count': previous + 1},
    );
    if (at == null) {
      _index[key] = _items.length;
      _items.add(diagnostic);
    } else {
      _items[at] = diagnostic;
    }
    if (strict && effective == EpubSeverity.warning) {
      final text = '${code.name}: $message';
      throw (onStrict ?? (m) => EpubContainerException(m, href: href))(text);
    }
  }
}
```

- [ ] **Passo 5: `knownDiagnostics` do corpus**

Em `test/corpus/corpus_test.dart`, trocar:

```dart
  'resourceUnreadable',
  'encryptionIgnored',
};
```

por:

```dart
  'resourceUnreadable',
  'encryptionIgnored',
  'navIgnored',
  'spineItemDuplicate',
};
```

- [ ] **Passo 6: Rodar e ver passar**

Run: `flutter test test/diagnostics/diagnostic_test.dart test/corpus/corpus_test.dart`
Expected: `All tests passed!` (212 testes: 16 do diagnóstico e 196 do corpus).

- [ ] **Passo 7: Formatar e analisar**

Run: `dart format --output=none --set-exit-if-changed lib test && flutter analyze`
Expected: nada a formatar e `No issues found!`.

- [ ] **Passo 8: Commit**

```bash
git add lib/src/diagnostics test/diagnostics test/corpus/corpus_test.dart
git commit -m "feat(publication): EpubPackageException e os códigos da Publicação

Os oito códigos de diagnóstico da spec §9.2 (resourceMissing,
spineItemUnresolved, unsupportedMediaType, encodingFallback,
tocReconciled, coverHeuristic, navIgnored, spineItemDuplicate) e a
exceção do pacote; knownDiagnostics do corpus com os dois novos."
```

---

### Tarefa 2: Modelo e `EpubMetadata`

Spec §3. Tipos imutáveis (toda lista, conjunto e mapa é cópia não
modificável). `EpubMetadata`, `EpubReadingDirection` e `EpubLayoutMode` ficam
públicos na Tarefa 11; o resto é interno. `sectionKindOf` (§6.4) mora aqui
porque `ManifestItem.kind` e `SpineItem.kind` dependem dela; inclui
`text/x-oeb1-document` (decisão 18, Foco de revisão 1).

**Arquivos:**
- Criar: `lib/src/publication/metadata.dart`
- Criar: `lib/src/publication/model.dart`
- Teste: `test/publication/model_test.dart`

**Interfaces:**
- Consome: nada.
- Produz (`metadata.dart`): `final class EpubMetadata { EpubMetadata({String? title, String? subtitle, List<String> authors = const [], List<String> contributors = const [], String? language, String? publisher, String? identifier, String? description, DateTime? published, DateTime? modified, List<String> subjects = const [], String? rights, String? series, double? seriesIndex, Map<String, List<String>> raw = const {}}); }` com os campos homônimos finais.
- Produz (`model.dart`): `enum EpubReadingDirection { ltr, rtl, auto }`; `enum EpubLayoutMode { reflowable, prePaginated }`; `enum SectionKind { xhtml, image, unsupported }`; `SectionKind sectionKindOf(String mediaType)`.
- Produz: `final class ManifestItem { ManifestItem({required String id, required String path, required String mediaType, Set<String> properties = const {}, String? fallback, bool missing = false, bool remote = false}); SectionKind get kind; }`.
- Produz: `final class SpineItem { SpineItem({required String idref, required ManifestItem item, required ManifestItem content, required bool linear}); final SectionKind kind; }` (`kind` = `content.kind`).
- Produz: `final class NavTarget { const NavTarget(String path, [String? fragment]); }` com `==`/`hashCode` por valor e `toString` `path#fragment`.
- Produz: `final class NavPoint { NavPoint({required String title, NavTarget? target, List<NavPoint> children = const [], String? type, bool synthesized = false}); }`.
- Produz: `final class EpubPublication { EpubPublication({required String opfPath, required String version, required EpubMetadata metadata, required Map<String, ManifestItem> manifest, required List<SpineItem> spine, required List<NavPoint> toc, required List<NavPoint> landmarks, required List<NavPoint> pageList, required String? coverPath, required String? navPath, required String? ncxPath, required EpubReadingDirection direction, required EpubLayoutMode layout, required List<String> uniqueIdentifiers, required List<String> identifiers}); }`.

- [ ] **Passo 1: Escrever o teste que falha**

Criar `test/publication/model_test.dart`:

```dart
// Modelo da Publicação: imutabilidade, NavTarget e SectionKind (spec §3, §6.4).
import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/publication/metadata.dart';
import 'package:galley/src/publication/model.dart';

void main() {
  test('sectionKindOf', () {
    expect(sectionKindOf('application/xhtml+xml'), SectionKind.xhtml);
    expect(sectionKindOf('text/html'), SectionKind.xhtml);
    expect(sectionKindOf('text/x-oeb1-document'), SectionKind.xhtml);
    expect(sectionKindOf('image/png'), SectionKind.image);
    expect(sectionKindOf('image/svg+xml'), SectionKind.image);
    expect(sectionKindOf('application/pdf'), SectionKind.unsupported);
    expect(sectionKindOf(''), SectionKind.unsupported);
  });

  test('SpineItem.kind vem do content', () {
    final pdf = ManifestItem(
      id: 'p',
      path: 'a.pdf',
      mediaType: 'application/pdf',
    );
    final png = ManifestItem(id: 'i', path: 'a.png', mediaType: 'image/png');
    final s = SpineItem(idref: 'p', item: pdf, content: png, linear: true);
    expect(pdf.kind, SectionKind.unsupported);
    expect(s.kind, SectionKind.image);
  });

  test('NavTarget tem igualdade de valor', () {
    final built = NavTarget('a.xhtml', ['x'].single);
    expect(built, const NavTarget('a.xhtml', 'x'));
    expect(built.hashCode, const NavTarget('a.xhtml', 'x').hashCode);
    expect({built, const NavTarget('a.xhtml', 'x')}, hasLength(1));
    expect(const NavTarget('a.xhtml'), isNot(const NavTarget('a.xhtml', 'x')));
    expect(built.toString(), 'a.xhtml#x');
  });

  test('coleções do modelo são não modificáveis', () {
    final item = ManifestItem(
      id: 'c',
      path: 'c.xhtml',
      mediaType: 'application/xhtml+xml',
      properties: {'nav'},
    );
    expect(() => item.properties.add('x'), throwsUnsupportedError);
    final point = NavPoint(
      title: 't',
      children: [NavPoint(title: 'f')],
    );
    expect(() => point.children.clear(), throwsUnsupportedError);
    final spine = [
      SpineItem(idref: 'c', item: item, content: item, linear: true),
    ];
    final p = EpubPublication(
      opfPath: 'content.opf',
      version: '3.0',
      metadata: EpubMetadata(),
      manifest: {'c': item},
      spine: spine,
      toc: [point],
      landmarks: const [],
      pageList: const [],
      coverPath: null,
      navPath: null,
      ncxPath: null,
      direction: EpubReadingDirection.auto,
      layout: EpubLayoutMode.reflowable,
      uniqueIdentifiers: const ['u'],
      identifiers: const ['u'],
    );
    spine.clear();
    expect(p.spine, hasLength(1), reason: 'cópia, não view');
    expect(() => p.manifest['x'] = item, throwsUnsupportedError);
    expect(() => p.toc.add(point), throwsUnsupportedError);
    expect(() => p.identifiers.add('v'), throwsUnsupportedError);
  });

  test('EpubMetadata: listas e raw não modificáveis, inclusive os valores', () {
    final m = EpubMetadata(
      authors: ['A'],
      subjects: ['S'],
      raw: {
        'source': ['x'],
      },
    );
    expect(() => m.authors.add('B'), throwsUnsupportedError);
    expect(() => m.subjects.clear(), throwsUnsupportedError);
    expect(() => m.raw['y'] = [], throwsUnsupportedError);
    expect(() => m.raw['source']!.add('z'), throwsUnsupportedError);
    expect(EpubMetadata().title, isNull);
  });
}
```

- [ ] **Passo 2: Rodar e ver falhar**

Run: `flutter test test/publication/model_test.dart`
Expected: FAIL na compilação, com `Error when reading 'lib/src/publication/model.dart': No such file or directory` (e o mesmo para `metadata.dart`).

- [ ] **Passo 3: `EpubMetadata`**

Criar `lib/src/publication/metadata.dart`:

```dart
/// Metadados da publicação (doc/06 §5; spec da Publicação §3 e §6.2).
library;

/// Metadados do OPF. Pública desde já (nome de doc/11 §3.3); o
/// `EpubDocument` do sub-projeto 6 a expõe como `doc.metadata`.
final class EpubMetadata {
  EpubMetadata({
    this.title,
    this.subtitle,
    List<String> authors = const [],
    List<String> contributors = const [],
    this.language,
    this.publisher,
    this.identifier,
    this.description,
    this.published,
    this.modified,
    List<String> subjects = const [],
    this.rights,
    this.series,
    this.seriesIndex,
    Map<String, List<String>> raw = const {},
  }) : authors = List.unmodifiable(authors),
       contributors = List.unmodifiable(contributors),
       subjects = List.unmodifiable(subjects),
       raw = Map.unmodifiable({
         for (final MapEntry(:key, :value) in raw.entries)
           key: List<String>.unmodifiable(value),
       });

  final String? title;
  final String? subtitle;
  final List<String> authors;
  final List<String> contributors;
  final String? language;
  final String? publisher;

  /// O primeiro dos identificadores únicos (a chave IDPF, doc/09 §4).
  final String? identifier;
  final String? description;
  final DateTime? published;
  final DateTime? modified;
  final List<String> subjects;
  final String? rights;

  /// `belongs-to-collection` de série, ou `calibre:series`.
  final String? series;
  final double? seriesIndex;

  /// O que não virou campo: chave = nome local do `dc:*` (em minúsculas), ou
  /// o `property`/`name` do `meta`; valores em ordem de documento.
  final Map<String, List<String>> raw;
}
```

- [ ] **Passo 4: O modelo**

Criar `lib/src/publication/model.dart`:

```dart
/// Modelo da publicação (spec da Publicação §3). Interno nesta etapa, exceto
/// [EpubReadingDirection] e [EpubLayoutMode] (públicos, doc/11 §3.3).
library;

import 'metadata.dart';

/// `page-progression-direction` do spine.
enum EpubReadingDirection { ltr, rtl, auto }

/// `rendition:layout` global do OPF.
enum EpubLayoutMode { reflowable, prePaginated }

/// Como a IR trata um item do spine (spec §6.4).
enum SectionKind { xhtml, image, unsupported }

/// Um item do manifest, com o caminho já resolvido contra o contêiner.
final class ManifestItem {
  ManifestItem({
    required this.id,
    required this.path,
    required this.mediaType,
    Set<String> properties = const {},
    this.fallback,
    this.missing = false,
    this.remote = false,
  }) : properties = Set.unmodifiable(properties);

  final String id;

  /// Normalizado e resolvido; para `href` recusado ou remoto, o `href` cru.
  final String path;

  /// Em minúsculas, sem parâmetros (antes de `;`), sem espaços nas pontas.
  final String mediaType;
  final Set<String> properties;

  /// `id` de outro item.
  final String? fallback;

  /// Não existe no contêiner (ou `href` recusado).
  final bool missing;

  /// `href` `http:`/`https:` (recurso remoto do EPUB3).
  final bool remote;

  /// Tipo de seção pelo `media-type` (spec §6.4).
  SectionKind get kind => sectionKindOf(mediaType);

  @override
  String toString() =>
      'ManifestItem($id, $path, $mediaType'
      '${missing ? ', missing' : ''}${remote ? ', remote' : ''})';
}

/// `application/xhtml+xml`, `text/html` e `text/x-oeb1-document` (o XHTML
/// do OEB 1.x, cujo OPF a Publicação já lê) → [SectionKind.xhtml];
/// `image/*` → [SectionKind.image]; o resto → [SectionKind.unsupported].
SectionKind sectionKindOf(String mediaType) {
  if (mediaType == 'application/xhtml+xml' ||
      mediaType == 'text/html' ||
      mediaType == 'text/x-oeb1-document') {
    return SectionKind.xhtml;
  }
  if (mediaType.startsWith('image/')) return SectionKind.image;
  return SectionKind.unsupported;
}

/// Um item da ordem de leitura.
final class SpineItem {
  SpineItem({
    required this.idref,
    required this.item,
    required this.content,
    required this.linear,
  }) : kind = content.kind;

  final String idref;

  /// O item referenciado pelo `itemref`.
  final ManifestItem item;

  /// O item a renderizar: [item], ou o fim da cadeia de `fallback`.
  final ManifestItem content;

  /// `false` só com `linear="no"`.
  final bool linear;

  /// Tipo de [content].
  final SectionKind kind;
}

/// Alvo de uma entrada de navegação.
final class NavTarget {
  const NavTarget(this.path, [this.fragment]);

  /// Caminho de item do manifest (ou o resolvido, spec §5.4).
  final String path;

  /// Sem `#`, decodificado de `%xx`; `null` se ausente ou vazio.
  final String? fragment;

  @override
  bool operator ==(Object other) =>
      other is NavTarget && other.path == path && other.fragment == fragment;

  @override
  int get hashCode => Object.hash(path, fragment);

  @override
  String toString() => fragment == null ? path : '$path#$fragment';
}

/// Entrada de TOC, landmark ou `page-list`.
final class NavPoint {
  NavPoint({
    required this.title,
    this.target,
    List<NavPoint> children = const [],
    this.type,
    this.synthesized = false,
  }) : children = List.unmodifiable(children);

  final String title;

  /// `null` em entrada só de agrupamento ou com alvo externo.
  final NavTarget? target;
  final List<NavPoint> children;

  /// Landmark: `epub:type` (NAV) ou `reference@type` (guide).
  final String? type;

  /// Órfão inserido pela reconciliação (a UI pode escondê-lo).
  final bool synthesized;

  @override
  String toString() =>
      'NavPoint($title${target == null ? '' : ' → $target'}'
      '${synthesized ? ', synthesized' : ''})';
}

/// A publicação lida do pacote (spec §3). Não abre nenhuma seção.
final class EpubPublication {
  EpubPublication({
    required this.opfPath,
    required this.version,
    required this.metadata,
    required Map<String, ManifestItem> manifest,
    required List<SpineItem> spine,
    required List<NavPoint> toc,
    required List<NavPoint> landmarks,
    required List<NavPoint> pageList,
    required this.coverPath,
    required this.navPath,
    required this.ncxPath,
    required this.direction,
    required this.layout,
    required List<String> uniqueIdentifiers,
    required List<String> identifiers,
  }) : manifest = Map.unmodifiable(manifest),
       spine = List.unmodifiable(spine),
       toc = List.unmodifiable(toc),
       landmarks = List.unmodifiable(landmarks),
       pageList = List.unmodifiable(pageList),
       uniqueIdentifiers = List.unmodifiable(uniqueIdentifiers),
       identifiers = List.unmodifiable(identifiers);

  /// Caminho do OPF no contêiner.
  final String opfPath;

  /// Atributo `version` do `<package>`, cru (`''` se ausente).
  final String version;
  final EpubMetadata metadata;

  /// Por `id`, na ordem do OPF.
  final Map<String, ManifestItem> manifest;

  /// Ordem de leitura; nunca vazio; sem repetição de caminho.
  final List<SpineItem> spine;

  /// Reconciliado com o spine.
  final List<NavPoint> toc;
  final List<NavPoint> landmarks;
  final List<NavPoint> pageList;

  /// Caminho no contêiner, ou `null`.
  final String? coverPath;

  /// NAV efetivamente lido (entra na chave do livro, doc/08 §4.1).
  final String? navPath;

  /// NCX efetivamente lido.
  final String? ncxPath;
  final EpubReadingDirection direction;
  final EpubLayoutMode layout;

  /// Chave IDPF (doc/09 §4).
  final List<String> uniqueIdentifiers;

  /// Todos os `dc:identifier`, em ordem (chave Adobe).
  final List<String> identifiers;
}
```

- [ ] **Passo 5: Rodar e ver passar**

Run: `flutter test test/publication/model_test.dart`
Expected: `All tests passed!` (5 testes).

- [ ] **Passo 6: Formatar e analisar**

Run: `dart format --output=none --set-exit-if-changed lib test && flutter analyze`
Expected: nada a formatar e `No issues found!`.

- [ ] **Passo 7: Commit**

```bash
git add lib/src/publication/metadata.dart lib/src/publication/model.dart test/publication/model_test.dart
git commit -m "feat(publication): modelo da publicação e EpubMetadata

EpubPublication, ManifestItem, SpineItem, NavPoint, NavTarget,
SectionKind, EpubReadingDirection e EpubLayoutMode (spec §3), com
coleções não modificáveis; sectionKindOf com o XHTML do OEB 1.x."
```

---

### Tarefa 3: `decodeXml`

Spec §4. BOM, declaração (e `<meta charset>` no NAV, decisão 2), UTF-8 por
padrão, Latin-1 com `encodingFallback` quando falha.

**Por que é linear:** a detecção olha no máximo 1 024 bytes, com duas regex
ancoradas sobre esse trecho; a decodificação é uma passada (`utf8.decode`,
`latin1.decode` ou o laço de pares do UTF-16), e o fallback faz no máximo
uma segunda passada.

**Arquivos:**
- Criar: `lib/src/publication/xml_text.dart`
- Teste: `test/publication/xml_text_test.dart`

**Interfaces:**
- Consome: `DiagnosticSink.emit`, `EpubDiagnosticCode.encodingFallback`, `EpubPackageException` (Tarefa 1).
- Produz: `const int encodingSniffBytes = 1024;` e `String decodeXml(Uint8List bytes, {required String path, required DiagnosticSink sink, bool htmlMeta = false})`. `encodingFallback` com `href: path` e `details: {declared, used: 'latin1'}`.

- [ ] **Passo 1: Escrever o teste que falha**

Criar `test/publication/xml_text_test.dart`:

```dart
// decodeXml: BOM, declaração, <meta charset> e fallback (spec da Publicação §4).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/diagnostics/diagnostic.dart';
import 'package:galley/src/publication/xml_text.dart';

Uint8List _bytes(List<int> b) => Uint8List.fromList(b);

Uint8List _utf16(String s, {required bool little}) {
  final out = <int>[];
  for (final u in s.codeUnits) {
    out.addAll(little ? [u & 0xFF, u >> 8] : [u >> 8, u & 0xFF]);
  }
  return _bytes(out);
}

String _decode(Uint8List bytes, DiagnosticSink sink, {bool htmlMeta = false}) =>
    decodeXml(bytes, path: 'OEBPS/a.opf', sink: sink, htmlMeta: htmlMeta);

void main() {
  const text = '<?xml version="1.0"?><a>çé</a>';

  test('BOM UTF-8 sai do texto e vence a declaração Latin-1', () {
    final sink = DiagnosticSink();
    final bytes = _bytes([
      0xEF,
      0xBB,
      0xBF,
      ...utf8.encode('<?xml version="1.0" encoding="ISO-8859-1"?><a>çé</a>'),
    ]);
    expect(
      _decode(bytes, sink),
      '<?xml version="1.0" encoding="ISO-8859-1"?><a>çé</a>',
    );
    expect(sink.diagnostics, isEmpty);
  });

  test('BOM UTF-16 LE e BE', () {
    final sink = DiagnosticSink();
    expect(
      _decode(_bytes([0xFF, 0xFE, ..._utf16(text, little: true)]), sink),
      text,
    );
    expect(
      _decode(_bytes([0xFE, 0xFF, ..._utf16(text, little: false)]), sink),
      text,
    );
    expect(sink.diagnostics, isEmpty);
  });

  test('declaração Latin-1 (e seus sinônimos) sem BOM', () {
    for (final label in ['ISO-8859-1', 'latin1', 'windows-1252', 'US-ASCII']) {
      final sink = DiagnosticSink();
      final bytes = _bytes([
        ...ascii.encode('<?xml version="1.0" encoding="$label"?><a>'),
        0xE7,
        0xE9,
        ...ascii.encode('</a>'),
      ]);
      expect(
        _decode(bytes, sink),
        '<?xml version="1.0" encoding="$label"?><a>çé</a>',
        reason: label,
      );
      expect(sink.diagnostics, isEmpty, reason: label);
    }
  });

  test("declaração com aspas simples e 'utf8'", () {
    final sink = DiagnosticSink();
    const source = "<?xml version='1.0' encoding='utf8'?><a>çé</a>";
    expect(_decode(_bytes(utf8.encode(source)), sink), source);
  });

  test('utf-16 declarado sem BOM vira UTF-16 LE', () {
    const source = '<?xml version="1.0" encoding="utf-16"?><a>çé</a>';
    final sink = DiagnosticSink();
    expect(_decode(_utf16(source, little: true), sink), source);
  });

  test('rótulo desconhecido vira UTF-8', () {
    const source = '<?xml version="1.0" encoding="Shift_JIS"?><a>çé</a>';
    final sink = DiagnosticSink();
    expect(_decode(_bytes(utf8.encode(source)), sink), source);
    expect(sink.diagnostics, isEmpty);
  });

  test('<meta charset> só com htmlMeta (NAV)', () {
    final bytes = _bytes([
      ...ascii.encode('<html><head><meta charset="iso-8859-1"/></head>'),
      0xE9,
      ...ascii.encode('</html>'),
    ]);
    final nav = DiagnosticSink();
    expect(_decode(bytes, nav, htmlMeta: true), endsWith('é</html>'));
    expect(nav.diagnostics, isEmpty);
    final opf = DiagnosticSink();
    expect(_decode(bytes, opf), endsWith('é</html>'));
    expect(
      opf.diagnostics.single.code,
      EpubDiagnosticCode.encodingFallback,
      reason: 'fora do NAV, o meta não conta: UTF-8 inválido',
    );
  });

  test('UTF-8 inválido cai para Latin-1 com encodingFallback', () {
    final sink = DiagnosticSink(strict: true);
    final bytes = _bytes([
      ...ascii.encode('<?xml version="1.0" encoding="UTF-8"?><a>'),
      0xE9,
      ...ascii.encode('</a>'),
    ]);
    expect(_decode(bytes, sink), endsWith('<a>é</a>'));
    final d = sink.diagnostics.single;
    expect(d.code, EpubDiagnosticCode.encodingFallback);
    expect(d.severity, EpubSeverity.info);
    expect(d.href, 'OEBPS/a.opf');
    expect(d.details, {'declared': 'utf-8', 'used': 'latin1', 'count': 1});
  });

  test('sem declaração, UTF-8 inválido: declared null', () {
    final sink = DiagnosticSink();
    expect(_decode(_bytes([0x3C, 0x61, 0x3E, 0xE9]), sink), '<a>é');
    expect(sink.diagnostics.single.details['declared'], isNull);
  });

  test('UTF-16 com número ímpar de bytes cai para Latin-1', () {
    final sink = DiagnosticSink();
    final bytes = _bytes([0xFF, 0xFE, 0x3C, 0x00, 0x61]);
    expect(_decode(bytes, sink), '<\u0000a');
    expect(sink.diagnostics.single.details, {
      'declared': 'utf-16le',
      'used': 'latin1',
      'count': 1,
    });
  });

  test('declaração depois dos primeiros 1 024 bytes não conta', () {
    final sink = DiagnosticSink();
    final bytes = _bytes([
      ...List<int>.filled(encodingSniffBytes, 0x20),
      ...ascii.encode('<?xml version="1.0" encoding="latin1"?><a>'),
      0xE9,
    ]);
    _decode(bytes, sink);
    expect(sink.diagnostics.single.code, EpubDiagnosticCode.encodingFallback);
  });
}
```

- [ ] **Passo 2: Rodar e ver falhar**

Run: `flutter test test/publication/xml_text_test.dart`
Expected: FAIL na compilação, com `Error when reading 'lib/src/publication/xml_text.dart': No such file or directory`.

- [ ] **Passo 3: Implementar**

Criar `lib/src/publication/xml_text.dart`:

```dart
/// Bytes de `container.xml`, OPF, NCX e NAV para texto (spec da Publicação
/// §4). A detecção completa de encoding (Shift-JIS e outros) é da IR.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../diagnostics/diagnostic.dart';
import '../diagnostics/exceptions.dart';

/// Bytes do começo lidos como ASCII para achar a declaração.
const int encodingSniffBytes = 1024;

final RegExp _xmlDeclaration = RegExp(
  r'''^\s*<\?xml\s[^>]*?encoding\s*=\s*["']([^"']*)["']''',
);
final RegExp _metaCharset = RegExp(
  r'''<meta\s[^>]*?charset\s*=\s*["']?\s*([A-Za-z0-9_.:\-]+)''',
  caseSensitive: false,
);

enum _Encoding { utf8, latin1, utf16le, utf16be }

/// Decodifica [bytes] de [path]: BOM, senão a declaração `encoding` (e, com
/// [htmlMeta], o `<meta charset>` do NAV) nos primeiros
/// [encodingSniffBytes] bytes, senão UTF-8. UTF-8 inválido e UTF-16 com
/// número ímpar de bytes caem para Latin-1 com `encodingFallback`.
String decodeXml(
  Uint8List bytes, {
  required String path,
  required DiagnosticSink sink,
  bool htmlMeta = false,
}) {
  final n = bytes.length;
  if (n >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
    return _decode(
      Uint8List.sublistView(bytes, 3),
      _Encoding.utf8,
      'utf-8',
      path,
      sink,
    );
  }
  if (n >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _decode(
      Uint8List.sublistView(bytes, 2),
      _Encoding.utf16le,
      'utf-16le',
      path,
      sink,
    );
  }
  if (n >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _decode(
      Uint8List.sublistView(bytes, 2),
      _Encoding.utf16be,
      'utf-16be',
      path,
      sink,
    );
  }
  final declared = _declaredEncoding(bytes, htmlMeta: htmlMeta);
  return _decode(bytes, _encodingOf(declared), declared, path, sink);
}

/// Rótulo declarado, em minúsculas; `null` se não há declaração. Os bytes 0
/// são pulados, para uma declaração em UTF-16 sem BOM ser legível.
String? _declaredEncoding(Uint8List bytes, {required bool htmlMeta}) {
  final end = bytes.length < encodingSniffBytes
      ? bytes.length
      : encodingSniffBytes;
  final ascii = StringBuffer();
  for (var i = 0; i < end; i++) {
    final b = bytes[i];
    if (b != 0) ascii.writeCharCode(b < 0x80 ? b : 0x3F);
  }
  final head = ascii.toString();
  final xml = _xmlDeclaration.firstMatch(head);
  if (xml != null) return xml.group(1)!.trim().toLowerCase();
  if (htmlMeta) {
    final meta = _metaCharset.firstMatch(head);
    if (meta != null) return meta.group(1)!.trim().toLowerCase();
  }
  return null;
}

_Encoding _encodingOf(String? label) => switch (label) {
  'iso-8859-1' || 'latin1' || 'windows-1252' || 'us-ascii' => _Encoding.latin1,
  'utf-16' || 'utf-16le' => _Encoding.utf16le,
  'utf-16be' => _Encoding.utf16be,
  _ => _Encoding.utf8,
};

String _decode(
  Uint8List bytes,
  _Encoding encoding,
  String? declared,
  String path,
  DiagnosticSink sink,
) {
  switch (encoding) {
    case _Encoding.latin1:
      return latin1.decode(bytes);
    case _Encoding.utf8:
      try {
        return utf8.decode(bytes);
      } on FormatException {
        return _fallback(bytes, declared, path, sink);
      }
    case _Encoding.utf16le:
    case _Encoding.utf16be:
      if (bytes.length.isOdd) return _fallback(bytes, declared, path, sink);
      final little = encoding == _Encoding.utf16le;
      final units = Uint16List(bytes.length ~/ 2);
      for (var i = 0; i < units.length; i++) {
        final a = bytes[2 * i];
        final b = bytes[2 * i + 1];
        units[i] = little ? a | b << 8 : a << 8 | b;
      }
      return String.fromCharCodes(units);
  }
}

String _fallback(
  Uint8List bytes,
  String? declared,
  String path,
  DiagnosticSink sink,
) {
  sink.emit(
    EpubDiagnosticCode.encodingFallback,
    href: path,
    message:
        'bytes inválidos em ${declared ?? 'utf-8'}; decodificado como latin1',
    details: {'declared': declared, 'used': 'latin1'},
    onStrict: (m) => EpubPackageException(m, href: path),
  );
  return latin1.decode(bytes);
}
```

- [ ] **Passo 4: Rodar e ver passar**

Run: `flutter test test/publication/xml_text_test.dart`
Expected: `All tests passed!` (11 testes).

- [ ] **Passo 5: Formatar e analisar**

Run: `dart format --output=none --set-exit-if-changed lib test && flutter analyze`
Expected: nada a formatar e `No issues found!`.

- [ ] **Passo 6: Commit**

```bash
git add lib/src/publication/xml_text.dart test/publication/xml_text_test.dart
git commit -m "feat(publication): decodeXml com BOM, declaração e fallback Latin-1

BOM UTF-8/UTF-16, declaração encoding (e meta charset no NAV) nos
primeiros 1 024 bytes, UTF-8 por padrão; UTF-8 inválido e UTF-16 ímpar
caem para Latin-1 com encodingFallback (spec §4)."
```

---

### Tarefa 4: Caminhos

Spec §5.1 e §5.2, mais os auxiliares que o orquestrador e a reconciliação
usam (`hasScheme`, `isRemoteHref`, `dirnameOf`, `basenameWithoutExtension`).
Decisão 5 (`trim` e caminho vazio).

**Por que é linear:** um `split('/')`, uma pilha de segmentos e um `join`; o
`%xx` é decodificado segmento a segmento, cada um uma vez.

**Arquivos:**
- Criar: `lib/src/publication/href.dart`
- Teste: `test/publication/href_test.dart`

**Interfaces:**
- Consome: nada.
- Produz: `bool hasScheme(String raw)`; `bool isRemoteHref(String raw)`; `String dirnameOf(String path)`; `String basenameWithoutExtension(String path)`; `String? normalizeHref(String baseDir, String raw)`; `(String, String?) splitFragment(String raw)`; `String? decodePath(String normalized)`.

- [ ] **Passo 1: Escrever o teste que falha**

Criar `test/publication/href_test.dart`:

```dart
// normalizeHref, splitFragment e decodePath (spec da Publicação §5.1, §5.2).
import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/publication/href.dart';

void main() {
  group('normalizeHref', () {
    final table = <(String, String, String?)>[
      ('OEBPS', 'Text/cap01.xhtml', 'OEBPS/Text/cap01.xhtml'),
      ('', 'cap01.xhtml', 'cap01.xhtml'),
      ('OEBPS/content', '../Text/cap01.xhtml', 'OEBPS/Text/cap01.xhtml'),
      ('OEBPS', '../../fora.xhtml', null),
      ('', '../fora.xhtml', null),
      ('OEBPS', r'Text\cap01.xhtml', 'OEBPS/Text/cap01.xhtml'),
      ('OEBPS/Text', '/Images/capa.png', 'Images/capa.png'),
      ('OEBPS', 'http://example.com/a.xhtml', null),
      ('OEBPS', 'mailto:a@b.c', null),
      ('OEBPS', 'data:image/png;base64,AAAA', null),
      ('OEBPS', r'C:\livro\a.xhtml', null),
      ('OEBPS', 'Text/cap01.xhtml?v=2#sec', 'OEBPS/Text/cap01.xhtml'),
      ('OEBPS', 'Text/cap01.xhtml#a?b', 'OEBPS/Text/cap01.xhtml'),
      ('OEBPS', 'Text//./cap01.xhtml', 'OEBPS/Text/cap01.xhtml'),
      ('OEBPS', 'Text/../cap01.xhtml', 'OEBPS/cap01.xhtml'),
      ('OEBPS', '', null),
      ('OEBPS', '#frag', null),
      ('OEBPS', '?q', null),
      ('OEBPS', 'Text/..', 'OEBPS'),
      ('', 'a/..', null),
      ('OEBPS', '  Text/cap01.xhtml  ', 'OEBPS/Text/cap01.xhtml'),
      ('OEBPS', 'Text/cap%20um.xhtml', 'OEBPS/Text/cap%20um.xhtml'),
    ];
    for (final (base, raw, expected) in table) {
      test('"$raw" em "$base" → $expected', () {
        expect(normalizeHref(base, raw), expected);
      });
    }
  });

  group('splitFragment', () {
    test('separa no primeiro #', () {
      expect(splitFragment('a.xhtml#x#y'), ('a.xhtml', 'x#y'));
      expect(splitFragment('a.xhtml'), ('a.xhtml', null));
      expect(splitFragment('a.xhtml#'), ('a.xhtml', null));
      expect(splitFragment('#só'), ('', 'só'));
    });

    test('decodifica o fragmento de forma tolerante', () {
      expect(splitFragment('a.xhtml#se%C3%A7%C3%A3o'), ('a.xhtml', 'seção'));
      expect(splitFragment('a.xhtml#50%'), ('a.xhtml', '50%'));
      expect(splitFragment('a.xhtml#%E9'), ('a.xhtml', '%E9'));
    });
  });

  group('decodePath', () {
    final table = <(String, String?)>[
      ('OEBPS/Text/cap%20um.xhtml', 'OEBPS/Text/cap um.xhtml'),
      ('OEBPS/Text/cap%C3%ADtulo%201.xhtml', 'OEBPS/Text/capítulo 1.xhtml'),
      ('OEBPS/%2e%2e/a.xhtml', 'a.xhtml'),
      ('%2e%2e/a.xhtml', null),
      ('OEBPS/%2E%2E/%2e%2e/a.xhtml', null),
      ('OEBPS/Text%5Ccap01.xhtml', 'OEBPS/Text/cap01.xhtml'),
      ('OEBPS/a%2Fb.xhtml', 'OEBPS/a%2Fb.xhtml'),
      ('OEBPS/caf%E9.xhtml', 'OEBPS/caf%E9.xhtml'),
      ('OEBPS/100%.xhtml', 'OEBPS/100%.xhtml'),
      ('OEBPS/%2e', 'OEBPS'),
      ('%2e', null),
      ('OEBPS/sem-escape.xhtml', 'OEBPS/sem-escape.xhtml'),
    ];
    for (final (input, expected) in table) {
      test('$input → $expected', () {
        expect(decodePath(input), expected);
      });
    }
  });

  group('auxiliares', () {
    test('hasScheme e isRemoteHref', () {
      expect(hasScheme('https://x/a.css'), isTrue);
      expect(hasScheme('Text/a.xhtml'), isFalse);
      expect(hasScheme('a:b'), isTrue);
      expect(isRemoteHref(' HTTP://x/a.mp3'), isTrue);
      expect(isRemoteHref('https://x/a.mp3'), isTrue);
      expect(isRemoteHref('ftp://x/a.mp3'), isFalse);
    });

    test('dirnameOf e basenameWithoutExtension', () {
      expect(dirnameOf('OEBPS/Text/a.xhtml'), 'OEBPS/Text');
      expect(dirnameOf('content.opf'), '');
      expect(basenameWithoutExtension('OEBPS/Text/cap02.xhtml'), 'cap02');
      expect(basenameWithoutExtension('a.b.html.xhtml'), 'a.b.html');
      expect(basenameWithoutExtension('OEBPS/.oculto'), '.oculto');
      expect(basenameWithoutExtension('LEIAME'), 'LEIAME');
    });
  });
}
```

- [ ] **Passo 2: Rodar e ver falhar**

Run: `flutter test test/publication/href_test.dart`
Expected: FAIL na compilação, com `Error when reading 'lib/src/publication/href.dart': No such file or directory`.

- [ ] **Passo 3: Implementar**

Criar `lib/src/publication/href.dart`:

```dart
/// Normalização de `href` (spec da Publicação §5.1 e §5.2). Funções puras e
/// lineares no tamanho da entrada: um `split` e uma pilha de segmentos.
library;

final RegExp _scheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*:');

/// `href` com esquema (`http:`, `mailto:`, `data:`, `C:`…).
bool hasScheme(String raw) => _scheme.hasMatch(raw.trim());

/// Esquema `http:` ou `https:` (recurso remoto do EPUB3).
bool isRemoteHref(String raw) {
  final lower = raw.trim().toLowerCase();
  return lower.startsWith('http:') || lower.startsWith('https:');
}

/// Diretório de [path] (sem `/` final; `''` na raiz).
String dirnameOf(String path) {
  final slash = path.lastIndexOf('/');
  return slash < 0 ? '' : path.substring(0, slash);
}

/// Nome do arquivo de [path], sem a última extensão.
String basenameWithoutExtension(String path) {
  final name = path.substring(path.lastIndexOf('/') + 1);
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}

/// Caminho de [raw] relativo à raiz do contêiner, resolvido contra
/// [baseDir] (diretório do documento que contém o `href`, sem `/` final;
/// vazio na raiz). `null` se tem esquema, sai da raiz ou fica vazio. Tira
/// `?query` e `#fragmento`, troca `\` por `/` e colapsa `.`, `..` e barras
/// repetidas. Não decodifica `%xx`.
String? normalizeHref(String baseDir, String raw) {
  var s = raw.trim();
  if (_scheme.hasMatch(s)) return null;
  final hash = s.indexOf('#');
  if (hash >= 0) s = s.substring(0, hash);
  final query = s.indexOf('?');
  if (query >= 0) s = s.substring(0, query);
  s = s.replaceAll(r'\', '/');
  if (s.isEmpty) return null;
  final joined = s.startsWith('/') || baseDir.isEmpty ? s : '$baseDir/$s';
  return _collapse(joined);
}

/// Separa no primeiro `#`. Fragmento vazio → `null`; o fragmento é
/// decodificado de `%xx` (fica cru se não decodificar).
(String, String?) splitFragment(String raw) {
  final hash = raw.indexOf('#');
  if (hash < 0) return (raw, null);
  final fragment = raw.substring(hash + 1);
  return (
    raw.substring(0, hash),
    fragment.isEmpty ? null : _tryDecode(fragment) ?? fragment,
  );
}

/// Decodifica `%xx` de [normalized] segmento a segmento e reaplica os passos
/// 3–6 de [normalizeHref]. Segmento que não decodifica, ou que decodificado
/// contém `/`, fica cru. `null` se o resultado sai da raiz ou fica vazio.
String? decodePath(String normalized) {
  if (!normalized.contains('%')) return normalized;
  final segments = normalized.split('/');
  for (var i = 0; i < segments.length; i++) {
    final segment = segments[i];
    if (!segment.contains('%')) continue;
    final decoded = _tryDecode(segment);
    if (decoded != null && !decoded.contains('/')) segments[i] = decoded;
  }
  return _collapse(segments.join('/').replaceAll(r'\', '/'));
}

String? _tryDecode(String s) {
  try {
    return Uri.decodeComponent(s);
  } on ArgumentError {
    return null;
  } on FormatException {
    return null;
  }
}

/// Colapsa `.`, `..` e barras repetidas; `null` se sai da raiz ou fica
/// vazio. Um `/` inicial não muda nada (a raiz é a do contêiner).
String? _collapse(String path) {
  final out = <String>[];
  for (final segment in path.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (out.isEmpty) return null;
      out.removeLast();
    } else {
      out.add(segment);
    }
  }
  return out.isEmpty ? null : out.join('/');
}
```

- [ ] **Passo 4: Rodar e ver passar**

Run: `flutter test test/publication/href_test.dart`
Expected: `All tests passed!` (38 testes).

- [ ] **Passo 5: Formatar e analisar**

Run: `dart format --output=none --set-exit-if-changed lib test && flutter analyze`
Expected: nada a formatar e `No issues found!`.

- [ ] **Passo 6: Commit**

```bash
git add lib/src/publication/href.dart test/publication/href_test.dart
git commit -m "feat(publication): normalizeHref, splitFragment e decodePath

Esquema, query e fragmento fora, \\ vira /, resolução contra o diretório
do documento e colapso de . e ..; %xx decodificado segmento a segmento
sem deixar %2e%2e atravessar a raiz nem %2F virar separador (spec §5)."
```

---

### Tarefa 5: `parseContainerXml`

Spec §9.1 (as linhas do `container.xml`). Devolve os `full-path` crus; o
orquestrador resolve e faz a tentativa dupla.

**Por que é linear:** um parse do `package:xml` e uma passada por
`findAllElements` (iterador de descendentes com pilha explícita).

**Arquivos:**
- Criar: `lib/src/publication/container_xml.dart`
- Teste: `test/publication/container_xml_test.dart`

**Interfaces:**
- Consome: `EpubContainerException`.
- Produz: `const String containerXmlPath = 'META-INF/container.xml';`, `const String opfMediaType = 'application/oebps-package+xml';` e `List<String> parseContainerXml(String text)` — `EpubContainerException(href: containerXmlPath)` com XML inválido (`cause`: a `XmlException`), sem `rootfile` de OPF ou só com `full-path` vazio.

- [ ] **Passo 1: Escrever o teste que falha**

Criar `test/publication/container_xml_test.dart`:

```dart
// parseContainerXml (spec da Publicação §9.1).
import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/diagnostics/exceptions.dart';
import 'package:galley/src/publication/container_xml.dart';

String _container(String rootfiles) =>
    '<?xml version="1.0"?>'
    '<container version="1.0" '
    'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
    '<rootfiles>$rootfiles</rootfiles></container>';

Matcher _containerError(String text) => throwsA(
  isA<EpubContainerException>()
      .having((e) => e.href, 'href', 'META-INF/container.xml')
      .having((e) => e.message, 'message', contains(text)),
);

void main() {
  test('rootfile do OPF', () {
    expect(
      parseContainerXml(
        _container(
          '<rootfile full-path="OEBPS/content.opf" '
          'media-type="application/oebps-package+xml"/>',
        ),
      ),
      ['OEBPS/content.opf'],
    );
  });

  test('outras renditions: só os de OPF, em ordem', () {
    expect(
      parseContainerXml(
        _container(
          '<rootfile full-path="livro.pdf" media-type="application/pdf"/>'
          '<rootfile full-path="a/um.opf" '
          'media-type="application/oebps-package+xml"/>'
          '<rootfile full-path=" b/dois.opf " '
          'media-type=" Application/OEBPS-Package+XML "/>',
        ),
      ),
      ['a/um.opf', 'b/dois.opf'],
    );
  });

  test('sem namespace e com prefixo também servem', () {
    expect(
      parseContainerXml(
        '<container><rootfiles><rootfile full-path="c.opf" '
        'media-type="application/oebps-package+xml"/></rootfiles></container>',
      ),
      ['c.opf'],
    );
    expect(
      parseContainerXml(
        '<o:container xmlns:o="urn:x"><o:rootfile o:full-path="d.opf" '
        'o:media-type="application/oebps-package+xml"/></o:container>',
      ),
      ['d.opf'],
    );
  });

  test('media-type errado', () {
    expect(
      () => parseContainerXml(
        _container(
          '<rootfile full-path="OEBPS/content.opf" media-type="text/xml"/>',
        ),
      ),
      _containerError('sem rootfile'),
    );
  });

  test('full-path vazio ou ausente', () {
    expect(
      () => parseContainerXml(
        _container(
          '<rootfile full-path=" " '
          'media-type="application/oebps-package+xml"/>'
          '<rootfile media-type="application/oebps-package+xml"/>',
        ),
      ),
      _containerError('full-path vazio'),
    );
  });

  test('XML inválido guarda a XmlException em cause', () {
    expect(
      () => parseContainerXml('<container><rootfiles>'),
      throwsA(
        isA<EpubContainerException>()
            .having((e) => e.href, 'href', 'META-INF/container.xml')
            .having((e) => e.cause, 'cause', isNotNull),
      ),
    );
  });
}
```

- [ ] **Passo 2: Rodar e ver falhar**

Run: `flutter test test/publication/container_xml_test.dart`
Expected: FAIL na compilação, com `Error when reading 'lib/src/publication/container_xml.dart': No such file or directory`.

- [ ] **Passo 3: Implementar**

Criar `lib/src/publication/container_xml.dart`:

```dart
/// `META-INF/container.xml` (spec da Publicação §9.1).
library;

import 'package:xml/xml.dart';

import '../diagnostics/exceptions.dart';

const String containerXmlPath = 'META-INF/container.xml';
const String opfMediaType = 'application/oebps-package+xml';

/// Os `full-path` dos `rootfile` com `media-type`
/// `application/oebps-package+xml` e `full-path` não vazio, em ordem de
/// documento (crus: quem resolve é o orquestrador). Uma passada pelos
/// descendentes (iterativa no `package:xml`), linear.
///
/// [EpubContainerException] (`href: META-INF/container.xml`) se o XML é
/// inválido ou se não sobra nenhum `rootfile`.
List<String> parseContainerXml(String text) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(text);
  } on XmlException catch (e) {
    throw EpubContainerException(
      'container.xml não é XML válido: ${e.message}',
      href: containerXmlPath,
      cause: e,
    );
  }
  final paths = <String>[];
  var sawPackageRootfile = false;
  for (final rootfile in document.findAllElements(
    'rootfile',
    namespaceUri: '*',
  )) {
    final mediaType = rootfile.getAttribute('media-type', namespaceUri: '*');
    if (mediaType?.trim().toLowerCase() != opfMediaType) continue;
    sawPackageRootfile = true;
    final fullPath = rootfile.getAttribute('full-path', namespaceUri: '*');
    if (fullPath != null && fullPath.trim().isNotEmpty) {
      paths.add(fullPath.trim());
    }
  }
  if (paths.isEmpty) {
    throw EpubContainerException(
      sawPackageRootfile
          ? 'container.xml só tem rootfile com full-path vazio'
          : 'container.xml sem rootfile de media-type $opfMediaType',
      href: containerXmlPath,
    );
  }
  return paths;
}
```

- [ ] **Passo 4: Rodar e ver passar**

Run: `flutter test test/publication/container_xml_test.dart`
Expected: `All tests passed!` (6 testes).

- [ ] **Passo 5: Formatar e analisar**

Run: `dart format --output=none --set-exit-if-changed lib test && flutter analyze`
Expected: nada a formatar e `No issues found!`.

- [ ] **Passo 6: Commit**

```bash
git add lib/src/publication/container_xml.dart test/publication/container_xml_test.dart
git commit -m "feat(publication): parseContainerXml

Os full-path dos rootfile de OPF em ordem, por nome local;
EpubContainerException com XML inválido, sem rootfile de OPF ou só com
full-path vazio (spec §9.1)."
```

---

### Tarefa 6: `parseOpf`

Spec §6.1, §6.2 e §6.3 (as propostas 6 e 7, juntas: decisão 1). Decisões 6,
10, 11 e 12. Os itens do Foco de revisão 1 (OEB 1.2) e 5 (aninhamento hostil
em `metadata`) estão no grupo `foco de revisão` do teste.

**Por que é linear:** um parse do `package:xml`; uma passada iterativa por
`metadata.descendantElements`, em que o texto de cada elemento vem só dos
filhos diretos (nunca `innerText`, que repercorreria a subárvore a cada nível
de metadado aninhado: com 100 000 níveis, quadrático); os refinamentos ficam
num mapa por `id`, então cada `dc:*` acha os seus em O(1); `manifest`,
`spine` e `guide` são uma passada pelos filhos diretos cada. As regras de
§6.2 fazem um número fixo de passadas pela lista de elementos.

**Arquivos:**
- Criar: `lib/src/publication/opf.dart`
- Teste: `test/publication/opf_test.dart`

**Interfaces:**
- Consome: `EpubMetadata` (Tarefa 2), `EpubReadingDirection`, `EpubLayoutMode` (Tarefa 2), `DiagnosticSink.emit`, `EpubPackageException` e os códigos `resourceMissing`, `spineItemUnresolved`, `spineItemDuplicate` (Tarefa 1).
- Produz: `const String dcNamespace = 'http://purl.org/dc/elements/1.1/';`.
- Produz: `final class OpfItem { const OpfItem({required String id, required String href, required String mediaType, required Set<String> properties, String? fallback}); }` (`href` e `mediaType` crus).
- Produz: `final class OpfItemRef { const OpfItemRef({required String idref, required bool linear}); }`; `final class OpfReference { const OpfReference({required String type, required String title, required String href}); }`.
- Produz: `final class OpfDocument` com `String version`, `EpubMetadata metadata`, `List<String> identifiers`, `List<String> uniqueIdentifiers`, `List<OpfItem> items` (id único, ordem do OPF), `List<OpfItemRef> itemrefs` (com item, sem `idref` repetido), `String? spineToc`, `EpubReadingDirection direction`, `EpubLayoutMode layout`, `List<OpfReference> guide`, `String? coverId`.
- Produz: `OpfDocument parseOpf(String text, {required String opfPath, required DiagnosticSink sink})` — `EpubPackageException(href: opfPath)` com XML inválido (`cause`), raiz que não é `package`, sem `manifest`, sem `spine`.
- Produz: `DateTime? parseEpubDate(String text)`.

- [ ] **Passo 1: Escrever o teste que falha**

Criar `test/publication/opf_test.dart`:

```dart
// parseOpf: leitura por nome local, metadados, manifest, spine, guide e
// fatais (spec da Publicação §6).
import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/diagnostics/diagnostic.dart';
import 'package:galley/src/diagnostics/exceptions.dart';
import 'package:galley/src/publication/model.dart';
import 'package:galley/src/publication/opf.dart';

const _manifest =
    '<manifest><item id="c1" href="Text/c1.xhtml" '
    'media-type="application/xhtml+xml"/></manifest>';
const _spine = '<spine><itemref idref="c1"/></spine>';

String _opf({
  String metadata = '',
  String manifest = _manifest,
  String spine = _spine,
  String extra = '',
  String package =
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
      'unique-identifier="uid">',
}) =>
    '<?xml version="1.0"?>$package'
    '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/" '
    'xmlns:opf="http://www.idpf.org/2007/opf">$metadata</metadata>'
    '$manifest$spine$extra</package>';

OpfDocument _parse(String text, {DiagnosticSink? sink}) => parseOpf(
  text,
  opfPath: 'OEBPS/content.opf',
  sink: sink ?? DiagnosticSink(),
);

void main() {
  group('leitura por nome local', () {
    test('sem namespace nenhum', () {
      final opf = _parse(
        '<package version="2.0"><metadata><dc:title>Sem ns</dc:title>'
        '</metadata>$_manifest$_spine</package>',
      );
      expect(opf.metadata.title, 'Sem ns');
      expect(opf.version, '2.0');
      expect(opf.items.single.href, 'Text/c1.xhtml');
    });

    test('estrutura com prefixo opf:', () {
      final opf = _parse(
        '<opf:package xmlns:opf="http://www.idpf.org/2007/opf" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<opf:metadata><dc:title>Prefixado</dc:title>'
        '<dc:creator opf:role="trl">Tradutor</dc:creator></opf:metadata>'
        '<opf:manifest><opf:item id="c1" href="c1.xhtml" '
        'media-type="application/xhtml+xml"/></opf:manifest>'
        '<opf:spine><opf:itemref idref="c1"/></opf:spine></opf:package>',
      );
      expect(opf.metadata.title, 'Prefixado');
      expect(opf.metadata.contributors, ['Tradutor']);
      expect(opf.itemrefs.single.idref, 'c1');
    });

    test('dc: sem namespace declarado e dc:Title (OEB antigo)', () {
      final opf = _parse(
        '<package><metadata><dc-metadata><dc:Title>Antigo</dc:Title>'
        '<dc:Creator>Autor</dc:Creator></dc-metadata>'
        '<x-metadata><meta name="cover" content="capa"/></x-metadata>'
        '</metadata>$_manifest$_spine</package>',
      );
      expect(opf.metadata.title, 'Antigo');
      expect(opf.metadata.authors, ['Autor']);
      expect(opf.coverId, 'capa');
    });

    test('dc no namespace com outro prefixo', () {
      final opf = _parse(
        '<package><metadata xmlns:d="http://purl.org/dc/elements/1.1/">'
        '<d:title>Outro prefixo</d:title></metadata>$_manifest$_spine'
        '</package>',
      );
      expect(opf.metadata.title, 'Outro prefixo');
    });
  });

  group('títulos', () {
    test('vários dc:title sem refinamento: o primeiro; os outros em raw', () {
      final m = _parse(
        _opf(metadata: '<dc:title>Um</dc:title><dc:title>Dois</dc:title>'),
      ).metadata;
      expect(m.title, 'Um');
      expect(m.subtitle, isNull);
      expect(m.raw['title'], ['Dois']);
    });

    test('title-type main, subtitle e expanded', () {
      final m = _parse(
        _opf(
          metadata:
              '<dc:title id="t1">Completo</dc:title>'
              '<meta refines="#t1" property="title-type">expanded</meta>'
              '<dc:title id="t2">Sub</dc:title>'
              '<meta refines="#t2" property="title-type">subtitle</meta>'
              '<dc:title id="t3">Principal</dc:title>'
              '<meta refines="#t3" property="title-type">main</meta>',
        ),
      ).metadata;
      expect(m.title, 'Principal');
      expect(m.subtitle, 'Sub');
      expect(m.raw['title'], ['Completo']);
      expect(m.raw.containsKey('title-type'), isFalse);
    });

    test('sem main: o primeiro que não é subtitle nem expanded', () {
      final m = _parse(
        _opf(
          metadata:
              '<dc:title id="t1">Sub</dc:title>'
              '<meta refines="#t1" property="title-type">subtitle</meta>'
              '<dc:title id="t2">Título</dc:title>',
        ),
      ).metadata;
      expect(m.title, 'Título');
      expect(m.subtitle, 'Sub');
    });

    test('só subtitle: vira título, e não é também subtítulo', () {
      final m = _parse(
        _opf(
          metadata:
              '<dc:title id="t1">Só</dc:title>'
              '<meta refines="#t1" property="title-type">subtitle</meta>',
        ),
      ).metadata;
      expect(m.title, 'Só');
      expect(m.subtitle, isNull);
    });
  });

  group('autores e colaboradores', () {
    test('creator sem papel é autor; contributor é colaborador', () {
      final m = _parse(
        _opf(
          metadata:
              '<dc:creator>Autora</dc:creator>'
              '<dc:contributor>Revisor</dc:contributor>'
              '<dc:creator opf:role="ill">Ilustrador</dc:creator>'
              '<dc:creator opf:role="aut">Coautor</dc:creator>',
        ),
      ).metadata;
      expect(m.authors, ['Autora', 'Coautor']);
      expect(m.contributors, ['Revisor', 'Ilustrador']);
    });

    test('role refinado, vários, algum aut', () {
      final m = _parse(
        _opf(
          metadata:
              '<dc:creator id="a">Herman</dc:creator>'
              '<meta property="role" refines="#a" scheme="marc:relators">'
              'ann</meta>'
              '<meta property="role" refines="#a">aut</meta>'
              '<dc:creator id="b">Artista</dc:creator>'
              '<meta property="role" refines="#b">art</meta>',
        ),
      ).metadata;
      expect(m.authors, ['Herman']);
      expect(m.contributors, ['Artista']);
      expect(m.raw.containsKey('role'), isFalse);
    });

    test('role refinando publisher fica em raw', () {
      final m = _parse(
        _opf(
          metadata:
              '<dc:publisher id="p">Editora</dc:publisher>'
              '<meta property="role" refines="#p">pbl</meta>',
        ),
      ).metadata;
      expect(m.publisher, 'Editora');
      expect(m.raw['role'], ['pbl']);
    });
  });

  group('série', () {
    test('collection-type series, com group-position', () {
      final m = _parse(
        _opf(
          metadata:
              '<meta property="belongs-to-collection" id="c">Saga</meta>'
              '<meta refines="#c" property="collection-type">series</meta>'
              '<meta refines="#c" property="group-position">2.5</meta>',
        ),
      ).metadata;
      expect(m.series, 'Saga');
      expect(m.seriesIndex, 2.5);
      expect(m.raw, isEmpty);
    });

    test('collection-type set vai para raw, com os refinamentos', () {
      final m = _parse(
        _opf(
          metadata:
              '<meta property="belongs-to-collection" id="c">Lista</meta>'
              '<meta refines="#c" property="collection-type">set</meta>'
              '<meta refines="#c" property="group-position">17</meta>',
        ),
      ).metadata;
      expect(m.series, isNull);
      expect(m.raw['belongs-to-collection'], ['Lista']);
      expect(m.raw['collection-type'], ['set']);
      expect(m.raw['group-position'], ['17']);
    });

    test('sem collection-type é série; o set antes é pulado', () {
      final m = _parse(
        _opf(
          metadata:
              '<meta property="belongs-to-collection" id="c1">Lista</meta>'
              '<meta refines="#c1" property="collection-type">set</meta>'
              '<meta property="belongs-to-collection">Série</meta>',
        ),
      ).metadata;
      expect(m.series, 'Série');
      expect(m.seriesIndex, isNull);
    });

    test('calibre:series na falta do EPUB3', () {
      final m = _parse(
        _opf(
          metadata:
              '<meta name="calibre:series" content="Discworld"/>'
              '<meta name="calibre:series_index" content="3"/>',
        ),
      ).metadata;
      expect(m.series, 'Discworld');
      expect(m.seriesIndex, 3.0);
      expect(m.raw, isEmpty);
    });

    test('com série EPUB3, calibre:series fica em raw', () {
      final m = _parse(
        _opf(
          metadata:
              '<meta property="belongs-to-collection">EPUB3</meta>'
              '<meta name="calibre:series" content="Calibre"/>',
        ),
      ).metadata;
      expect(m.series, 'EPUB3');
      expect(m.raw['calibre:series'], ['Calibre']);
    });
  });

  group('datas', () {
    test('completa, parcial e opf:event', () {
      final m = _parse(
        _opf(
          metadata:
              '<dc:date opf:event="creation">1990</dc:date>'
              '<dc:date opf:event="publication">2001-05</dc:date>'
              '<dc:date opf:event="modification">2010-01-02</dc:date>',
        ),
      ).metadata;
      expect(m.published, DateTime.utc(2001, 5));
      expect(m.modified, DateTime.utc(2010, 1, 2));
      expect(m.raw['date'], ['1990']);
    });

    test('sem publication: o primeiro que não é modification', () {
      final m = _parse(
        _opf(
          metadata:
              '<dc:date opf:event="modification">2010</dc:date>'
              '<dc:date>1851</dc:date>',
        ),
      ).metadata;
      expect(m.published, DateTime.utc(1851));
      expect(m.modified, DateTime.utc(2010));
    });

    test('dcterms:modified vence o dc:date de modification', () {
      final m = _parse(
        _opf(
          metadata:
              '<dc:date>2018-03-27T22:02:30Z</dc:date>'
              '<dc:date opf:event="modification">2010</dc:date>'
              '<meta property="dcterms:modified">2026-08-04T14:52:50Z</meta>',
        ),
      ).metadata;
      expect(m.published, DateTime.utc(2018, 3, 27, 22, 2, 30));
      expect(m.modified, DateTime.utc(2026, 8, 4, 14, 52, 50));
      expect(m.raw['date'], ['2010']);
    });

    test('inválida fica null e o texto vai para raw', () {
      final m = _parse(
        _opf(
          metadata:
              '<dc:date>por volta de 1900</dc:date>'
              '<meta property="dcterms:modified">2020-13</meta>',
        ),
      ).metadata;
      expect(m.published, isNull);
      expect(m.modified, isNull);
      expect(m.raw['date'], ['por volta de 1900']);
      expect(m.raw['dcterms:modified'], ['2020-13']);
    });

    test('parseEpubDate', () {
      expect(parseEpubDate('2020'), DateTime.utc(2020));
      expect(parseEpubDate('2020-02'), DateTime.utc(2020, 2));
      expect(parseEpubDate('2020-02-29'), DateTime.utc(2020, 2, 29));
      expect(parseEpubDate('2021-02-29'), isNull);
      expect(parseEpubDate('2021-00'), isNull);
      expect(parseEpubDate('+275760-09-14'), isNull);
      expect(parseEpubDate('9' * 100), isNull);
      expect(parseEpubDate(''), isNull);
    });
  });

  group('demais campos e raw', () {
    test('primeiro de cada, subjects todos, raw só o não mapeado', () {
      final m = _parse(
        _opf(
          metadata:
              '<dc:identifier id="uid">urn:isbn:1</dc:identifier>'
              '<dc:title>T</dc:title>'
              '<dc:language>pt-BR</dc:language>'
              '<dc:language>en</dc:language>'
              '<dc:publisher>P</dc:publisher>'
              '<dc:description> D </dc:description>'
              '<dc:rights>R</dc:rights>'
              '<dc:subject>S1</dc:subject><dc:subject>S2</dc:subject>'
              '<dc:source>fonte</dc:source>'
              '<dc:title id="alt">Outro</dc:title>'
              '<meta property="file-as" refines="#alt">Outro, O</meta>'
              '<meta name="generator" content="Sigil"/>'
              '<meta property="schema:accessMode">textual</meta>'
              '<meta property="rendition:layout">reflowable</meta>'
              '<meta name="cover" content="img"/>'
              '<link rel="x" href="y"/>',
        ),
      ).metadata;
      expect(m.title, 'T');
      expect(m.language, 'pt-BR');
      expect(m.publisher, 'P');
      expect(m.description, 'D');
      expect(m.rights, 'R');
      expect(m.subjects, ['S1', 'S2']);
      expect(m.identifier, 'urn:isbn:1');
      expect(m.raw, {
        'language': ['en'],
        'source': ['fonte'],
        'title': ['Outro'],
        'file-as': ['Outro, O'],
        'generator': ['Sigil'],
        'schema:accessMode': ['textual'],
      });
    });

    test('listas e raw são não modificáveis', () {
      final m = _parse(_opf(metadata: '<dc:creator>A</dc:creator>')).metadata;
      expect(() => m.authors.add('B'), throwsUnsupportedError);
      expect(() => m.raw['x'] = [], throwsUnsupportedError);
    });

    test('texto vem só dos filhos diretos', () {
      final m = _parse(
        _opf(
          metadata:
              '<dc:title>Fora<dc:title>Dentro</dc:title></dc:title>'
              '<dc:description><![CDATA[<p>html</p>]]></dc:description>',
        ),
      ).metadata;
      expect(m.title, 'Fora');
      expect(m.raw['title'], ['Dentro']);
      expect(m.description, '<p>html</p>');
    });
  });

  group('identificadores', () {
    test('todos em ordem, com trim; o único pelo unique-identifier', () {
      final opf = _parse(
        _opf(
          metadata:
              '<dc:identifier>  urn:isbn:9780000000001 </dc:identifier>'
              '<dc:identifier id="uid">urn:uuid:abc</dc:identifier>',
        ),
      );
      expect(opf.identifiers, ['urn:isbn:9780000000001', 'urn:uuid:abc']);
      expect(opf.uniqueIdentifiers, ['urn:uuid:abc']);
      expect(opf.metadata.identifier, 'urn:uuid:abc');
      expect(opf.metadata.raw['identifier'], ['urn:isbn:9780000000001']);
    });

    test('sem casamento com unique-identifier: o primeiro', () {
      final opf = _parse(
        _opf(
          metadata:
              '<dc:identifier id="x">primeiro</dc:identifier>'
              '<dc:identifier>segundo</dc:identifier>',
        ),
      );
      expect(opf.uniqueIdentifiers, ['primeiro']);
    });

    test('sem dc:identifier: listas vazias', () {
      final opf = _parse(_opf());
      expect(opf.identifiers, isEmpty);
      expect(opf.uniqueIdentifiers, isEmpty);
      expect(opf.metadata.identifier, isNull);
    });
  });

  group('manifest', () {
    test('item cru: href, media-type, properties e fallback', () {
      final opf = _parse(
        _opf(
          manifest:
              '<manifest><item id="c1" href="Text/c1.xhtml" '
              'media-type="application/xhtml+xml" properties="nav  scripted" '
              'fallback="c2"/></manifest>',
        ),
      );
      final item = opf.items.single;
      expect(item.href, 'Text/c1.xhtml');
      expect(item.mediaType, 'application/xhtml+xml');
      expect(item.properties, {'nav', 'scripted'});
      expect(item.fallback, 'c2');
    });

    test('id duplicado: vale o primeiro', () {
      final opf = _parse(
        _opf(
          manifest:
              '<manifest><item id="c1" href="a.xhtml" media-type="x"/>'
              '<item id="c1" href="b.xhtml" media-type="y"/></manifest>',
        ),
      );
      expect(opf.items.map((i) => i.href), ['a.xhtml']);
    });

    test('sem id ou sem href: descartado com resourceMissing', () {
      final sink = DiagnosticSink();
      final opf = _parse(
        _opf(
          manifest:
              '<manifest><item href="a.xhtml" media-type="x"/>'
              '<item id="b" media-type="y"/>'
              '<item id="c1" href="Text/c1.xhtml" media-type="z"/></manifest>',
        ),
        sink: sink,
      );
      expect(opf.items.map((i) => i.id), ['c1']);
      final d = sink.diagnostics.single;
      expect(d.code, EpubDiagnosticCode.resourceMissing);
      expect(d.href, isNull);
      expect(d.details, {'reason': 'no-href', 'id': 'b', 'count': 2});
    });

    test('resourceMissing em strict lança EpubPackageException', () {
      expect(
        () => _parse(
          _opf(
            manifest:
                '<manifest><item href="a.xhtml"/>'
                '<item id="c1" href="c1.xhtml"/></manifest>',
          ),
          sink: DiagnosticSink(strict: true),
        ),
        throwsA(
          isA<EpubPackageException>().having(
            (e) => e.message,
            'message',
            startsWith('resourceMissing: '),
          ),
        ),
      );
    });
  });

  group('spine', () {
    const manifest =
        '<manifest>'
        '<item id="a" href="a.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="b" href="b.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>'
        '</manifest>';

    test('idref sem item, repetido e linear', () {
      final sink = DiagnosticSink();
      final opf = _parse(
        _opf(
          manifest: manifest,
          spine:
              '<spine toc="ncx"><itemref idref="a"/><itemref idref="x"/>'
              '<itemref idref="b" linear="no"/><itemref idref="a"/></spine>',
        ),
        sink: sink,
      );
      expect(opf.itemrefs.map((r) => (r.idref, r.linear)), [
        ('a', true),
        ('b', false),
      ]);
      expect(opf.spineToc, 'ncx');
      final [unresolved, duplicate] = sink.diagnostics;
      expect(unresolved.code, EpubDiagnosticCode.spineItemUnresolved);
      expect(unresolved.severity, EpubSeverity.warning);
      expect(unresolved.href, 'OEBPS/content.opf');
      expect(unresolved.details, {'idref': 'x', 'count': 1});
      expect(duplicate.code, EpubDiagnosticCode.spineItemDuplicate);
      expect(duplicate.severity, EpubSeverity.info);
      expect(duplicate.href, 'OEBPS/content.opf');
      expect(duplicate.details, {'idref': 'a', 'count': 1});
    });

    test('spineItemUnresolved em strict lança EpubPackageException', () {
      expect(
        () => _parse(
          _opf(spine: '<spine><itemref idref="nada"/></spine>'),
          sink: DiagnosticSink(strict: true),
        ),
        throwsA(
          isA<EpubPackageException>()
              .having((e) => e.href, 'href', 'OEBPS/content.opf')
              .having(
                (e) => e.message,
                'message',
                startsWith('spineItemUnresolved: '),
              ),
        ),
      );
    });

    test('page-progression-direction', () {
      EpubReadingDirection of(String attr) =>
          _parse(_opf(spine: '<spine $attr><itemref idref="c1"/></spine>'))
              .direction;
      expect(of('page-progression-direction="rtl"'), EpubReadingDirection.rtl);
      expect(of('page-progression-direction="ltr"'), EpubReadingDirection.ltr);
      expect(
        of('page-progression-direction="default"'),
        EpubReadingDirection.auto,
      );
      expect(of(''), EpubReadingDirection.auto);
    });
  });

  group('layout e guide', () {
    test('rendition:layout global pre-paginated', () {
      expect(
        _parse(
          _opf(
            metadata: '<meta property="rendition:layout">pre-paginated</meta>',
          ),
        ).layout,
        EpubLayoutMode.prePaginated,
      );
      expect(_parse(_opf()).layout, EpubLayoutMode.reflowable);
      expect(
        _parse(
          _opf(
            metadata:
                '<meta refines="#x" property="rendition:layout">'
                'pre-paginated</meta>',
          ),
        ).layout,
        EpubLayoutMode.reflowable,
        reason: 'só o global conta',
      );
    });

    test('guide: reference com href, na ordem', () {
      final opf = _parse(
        _opf(
          extra:
              '<guide><reference type="cover" title="Capa" href="capa.xhtml"/>'
              '<reference type="toc" title="Sumário"/>'
              '<reference type="text" href="Text/c1.xhtml#i"/></guide>',
        ),
      );
      expect(opf.guide.map((r) => (r.type, r.title, r.href)), [
        ('cover', 'Capa', 'capa.xhtml'),
        ('text', '', 'Text/c1.xhtml#i'),
      ]);
    });
  });

  group('fatais', () {
    Matcher fatal(String text) => throwsA(
      isA<EpubPackageException>()
          .having((e) => e.href, 'href', 'OEBPS/content.opf')
          .having((e) => e.message, 'message', contains(text)),
    );

    test('XML inválido, com a XmlException em cause', () {
      expect(
        () => _parse('<package><metadata>'),
        throwsA(
          isA<EpubPackageException>().having(
            (e) => e.cause,
            'cause',
            isNotNull,
          ),
        ),
      );
    });

    test('raiz que não é package', () {
      expect(() => _parse('<pacote/>'), fatal('não <package>'));
    });

    test('sem manifest e sem spine', () {
      expect(() => _parse('<package>$_spine</package>'), fatal('<manifest>'));
      expect(() => _parse('<package>$_manifest</package>'), fatal('<spine>'));
    });
  });

  group('foco de revisão', () {
    test('OEB 1.2: DOCTYPE externo, dc 1.0 e dc-metadata', () {
      final opf = _parse(
        '<?xml version="1.0"?>\n'
        '<!DOCTYPE package PUBLIC "+//ISBN 0-9673008-1-9//DTD OEB 1.2 '
        'Package//EN" "http://openebook.org/dtds/oeb-1.2/oebpkg12.dtd">\n'
        '<package unique-identifier="id"><metadata><dc-metadata '
        'xmlns:dc="http://purl.org/dc/elements/1.0/">'
        '<dc:Title>Velho</dc:Title><dc:Identifier id="id">oeb:1</dc:Identifier>'
        '</dc-metadata></metadata><manifest><item id="a" href="a.html" '
        'media-type="text/x-oeb1-document"/></manifest>'
        '<spine><itemref idref="a"/></spine></package>',
      );
      expect(opf.metadata.title, 'Velho');
      expect(opf.uniqueIdentifiers, ['oeb:1']);
      expect(opf.items.single.mediaType, 'text/x-oeb1-document');
    });

    test('metadata aninhado 100 000 níveis: linear, sem estouro de pilha', () {
      final deep =
          '<package><metadata>${'<dc:title>t' * 100000}'
          '${'</dc:title>' * 100000}</metadata>$_manifest$_spine</package>';
      final sw = Stopwatch()..start();
      final m = _parse(deep).metadata;
      sw.stop();
      expect(m.title, 't');
      expect(m.raw['title'], hasLength(99999));
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
    });
  });
}
```

- [ ] **Passo 2: Rodar e ver falhar**

Run: `flutter test test/publication/opf_test.dart`
Expected: FAIL na compilação, com `Error when reading 'lib/src/publication/opf.dart': No such file or directory`.

- [ ] **Passo 3: Implementar**

Criar `lib/src/publication/opf.dart`:

```dart
/// OPF: leitura por nome local, metadados, manifest, spine e guide (spec da
/// Publicação §6). Pura: os `href` saem crus e quem resolve é o orquestrador.
///
/// Linear no tamanho do OPF: um parse do `package:xml`, uma passada
/// iterativa pelos descendentes de `metadata` (o texto de cada elemento vem
/// só dos filhos diretos, nunca de `innerText`, que repercorreria a
/// subárvore em metadado aninhado), uma pelos filhos de `manifest`, `spine`
/// e `guide`, e refinamentos por mapa de `id`.
library;

import 'package:xml/xml.dart';

import '../diagnostics/diagnostic.dart';
import '../diagnostics/exceptions.dart';
import 'metadata.dart';
import 'model.dart';

const String dcNamespace = 'http://purl.org/dc/elements/1.1/';

/// `<item>` do manifest, cru.
final class OpfItem {
  const OpfItem({
    required this.id,
    required this.href,
    required this.mediaType,
    required this.properties,
    this.fallback,
  });

  final String id;

  /// Cru, como no OPF.
  final String href;

  /// Cru, como no OPF (`''` se ausente).
  final String mediaType;
  final Set<String> properties;
  final String? fallback;
}

/// `<itemref>` do spine com `idref` resolvido e não repetido.
final class OpfItemRef {
  const OpfItemRef({required this.idref, required this.linear});

  final String idref;
  final bool linear;
}

/// `<reference>` do `guide` (EPUB2).
final class OpfReference {
  const OpfReference({
    required this.type,
    required this.title,
    required this.href,
  });

  final String type;
  final String title;

  /// Cru, relativo ao OPF.
  final String href;
}

/// O que o orquestrador precisa do OPF.
final class OpfDocument {
  OpfDocument({
    required this.version,
    required this.metadata,
    required List<String> identifiers,
    required List<String> uniqueIdentifiers,
    required List<OpfItem> items,
    required List<OpfItemRef> itemrefs,
    required this.spineToc,
    required this.direction,
    required this.layout,
    required List<OpfReference> guide,
    required this.coverId,
  }) : identifiers = List.unmodifiable(identifiers),
       uniqueIdentifiers = List.unmodifiable(uniqueIdentifiers),
       items = List.unmodifiable(items),
       itemrefs = List.unmodifiable(itemrefs),
       guide = List.unmodifiable(guide);

  /// Atributo `version` do `<package>`, cru (`''` se ausente).
  final String version;
  final EpubMetadata metadata;

  /// Todos os `dc:identifier` não vazios, em ordem, com `trim`.
  final List<String> identifiers;

  /// O `dc:identifier` do `unique-identifier`; sem casamento,
  /// `[identifiers.first]` (se houver).
  final List<String> uniqueIdentifiers;

  /// Itens com `id` e `href`, na ordem do OPF; `id` repetido: o primeiro.
  final List<OpfItem> items;

  /// `itemref` com item, sem `idref` repetido, em ordem.
  final List<OpfItemRef> itemrefs;

  /// Atributo `toc` do `<spine>` (id do NCX).
  final String? spineToc;
  final EpubReadingDirection direction;
  final EpubLayoutMode layout;
  final List<OpfReference> guide;

  /// `content` do `<meta name="cover">`.
  final String? coverId;
}

/// Lê o OPF. [EpubPackageException] (`href: opfPath`) com XML inválido,
/// raiz que não é `package`, sem `manifest` ou sem `spine`. Emite
/// `resourceMissing` (item sem `id`/`href`), `spineItemUnresolved` e
/// `spineItemDuplicate`; em `strict`, os warnings lançam
/// [EpubPackageException].
OpfDocument parseOpf(
  String text, {
  required String opfPath,
  required DiagnosticSink sink,
}) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(text);
  } on XmlException catch (e) {
    throw EpubPackageException(
      'OPF não é XML válido: ${e.message}',
      href: opfPath,
      cause: e,
    );
  }
  final root = document.rootElement;
  if (root.name.local != 'package') {
    throw EpubPackageException(
      'raiz do OPF é <${root.name.qualified}>, não <package>',
      href: opfPath,
    );
  }
  final manifest = _child(root, 'manifest');
  if (manifest == null) {
    throw EpubPackageException('OPF sem <manifest>', href: opfPath);
  }
  final spine = _child(root, 'spine');
  if (spine == null) {
    throw EpubPackageException('OPF sem <spine>', href: opfPath);
  }
  EpubPackageException strictError(String m) =>
      EpubPackageException(m, href: opfPath);

  final items = <OpfItem>[];
  final ids = <String>{};
  for (final e in manifest.childElements) {
    if (e.name.local != 'item') continue;
    final id = _attr(e, 'id');
    final href = e.getAttribute('href', namespaceUri: '*');
    if (id == null || id.isEmpty || href == null) {
      sink.emit(
        EpubDiagnosticCode.resourceMissing,
        message: id == null || id.isEmpty
            ? 'item do manifest sem id descartado'
            : 'item do manifest "$id" sem href descartado',
        details: {
          'reason': id == null || id.isEmpty ? 'no-id' : 'no-href',
          if (id != null && id.isNotEmpty) 'id': id,
        },
        onStrict: strictError,
      );
      continue;
    }
    if (!ids.add(id)) continue;
    items.add(
      OpfItem(
        id: id,
        href: href,
        mediaType: _attr(e, 'media-type') ?? '',
        properties: _tokens(_attr(e, 'properties')),
        fallback: _attr(e, 'fallback'),
      ),
    );
  }

  final itemrefs = <OpfItemRef>[];
  final seen = <String>{};
  for (final e in spine.childElements) {
    if (e.name.local != 'itemref') continue;
    final idref = _attr(e, 'idref') ?? '';
    if (!ids.contains(idref)) {
      sink.emit(
        EpubDiagnosticCode.spineItemUnresolved,
        href: opfPath,
        message: 'itemref "$idref" sem item no manifest; ignorado',
        details: {'idref': idref},
        onStrict: strictError,
      );
      continue;
    }
    if (!seen.add(idref)) {
      sink.emit(
        EpubDiagnosticCode.spineItemDuplicate,
        href: opfPath,
        message: 'itemref "$idref" repetido; vale o primeiro',
        details: {'idref': idref},
        onStrict: strictError,
      );
      continue;
    }
    itemrefs.add(
      OpfItemRef(
        idref: idref,
        linear: _attr(e, 'linear')?.toLowerCase() != 'no',
      ),
    );
  }

  final guide = <OpfReference>[];
  final guideElement = _child(root, 'guide');
  if (guideElement != null) {
    for (final e in guideElement.childElements) {
      if (e.name.local != 'reference') continue;
      final href = e.getAttribute('href', namespaceUri: '*');
      if (href == null) continue;
      guide.add(
        OpfReference(
          type: _attr(e, 'type') ?? '',
          title: _attr(e, 'title') ?? '',
          href: href,
        ),
      );
    }
  }

  final meta = _Metadata(
    _child(root, 'metadata'),
    uniqueIdentifierId: _attr(root, 'unique-identifier'),
  );
  return OpfDocument(
    version: root.getAttribute('version', namespaceUri: '*') ?? '',
    metadata: meta.metadata,
    identifiers: meta.identifiers,
    uniqueIdentifiers: meta.uniqueIdentifiers,
    items: items,
    itemrefs: itemrefs,
    spineToc: _attr(spine, 'toc'),
    direction: switch (_attr(
      spine,
      'page-progression-direction',
    )?.toLowerCase()) {
      'ltr' => EpubReadingDirection.ltr,
      'rtl' => EpubReadingDirection.rtl,
      _ => EpubReadingDirection.auto,
    },
    layout: meta.layout,
    guide: guide,
    coverId: meta.coverId,
  );
}

XmlElement? _child(XmlElement parent, String local) {
  for (final e in parent.childElements) {
    if (e.name.local == local) return e;
  }
  return null;
}

/// Atributo por nome local (`opf:role` = `role`), com `trim`.
String? _attr(XmlElement e, String local) =>
    e.getAttribute(local, namespaceUri: '*')?.trim();

Set<String> _tokens(String? value) => value == null
    ? const {}
    : value.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toSet();

/// Texto dos filhos diretos (texto e CDATA), com `trim`.
String _ownText(XmlElement e) {
  final buffer = StringBuffer();
  for (final node in e.children) {
    if (node is XmlText) {
      buffer.write(node.value);
    } else if (node is XmlCDATA) {
      buffer.write(node.value);
    }
  }
  return buffer.toString().trim();
}

/// Um `dc:*` ou `meta` de `metadata`, em ordem de documento.
final class _Element {
  _Element.dc(XmlElement e)
    : isDc = true,
      name = e.name.local.toLowerCase(),
      text = _ownText(e),
      id = _attr(e, 'id'),
      role = _attr(e, 'role')?.toLowerCase(),
      event = _attr(e, 'event')?.toLowerCase(),
      metaName = null,
      content = null,
      property = null,
      refines = null;

  _Element.meta(XmlElement e)
    : isDc = false,
      name = 'meta',
      text = _ownText(e),
      id = _attr(e, 'id'),
      role = null,
      event = null,
      metaName = _attr(e, 'name'),
      content = _attr(e, 'content'),
      property = _attr(e, 'property'),
      refines = _refinedId(_attr(e, 'refines'));

  final bool isDc;

  /// Nome local em minúsculas do `dc:*` (`title`, `creator`…), ou `meta`.
  final String name;
  final String text;
  final String? id;
  final String? role;
  final String? event;
  final String? metaName;
  final String? content;
  final String? property;
  final String? refines;

  static String? _refinedId(String? refines) {
    if (refines == null || refines.isEmpty) return null;
    return refines.startsWith('#') ? refines.substring(1) : refines;
  }
}

bool _isDc(XmlElement e) =>
    e.namespaceUri == dcNamespace || e.name.prefix == 'dc';

/// Montagem dos metadados (spec §6.2) e dos identificadores (§6.3).
final class _Metadata {
  _Metadata(XmlElement? element, {required String? uniqueIdentifierId}) {
    if (element != null) {
      for (final e in element.descendantElements) {
        if (_isDc(e)) {
          _all.add(_Element.dc(e));
        } else if (e.name.local == 'meta') {
          _all.add(_Element.meta(e));
        }
      }
    }
    for (final e in _all) {
      final refined = e.refines;
      if (!e.isDc && refined != null) {
        (_refinements[refined] ??= []).add(e);
      }
    }
    _identifiers(uniqueIdentifierId);
    _build();
  }

  final List<_Element> _all = [];
  final Map<String, List<_Element>> _refinements = {};
  final Set<_Element> _used = Set.identity();

  final List<String> identifiers = [];
  final List<String> uniqueIdentifiers = [];
  late final EpubMetadata metadata;
  EpubLayoutMode layout = EpubLayoutMode.reflowable;
  String? coverId;

  Iterable<_Element> _dc(String name) =>
      _all.where((e) => e.isDc && e.name == name && e.text.isNotEmpty);

  Iterable<_Element> _meta({String? property, String? name}) => _all.where(
    (e) =>
        !e.isDc &&
        e.refines == null &&
        (property == null || e.property == property) &&
        (name == null || e.metaName == name),
  );

  /// `meta` que refinam [e] com [property] e texto não vazio.
  List<_Element> _refinedBy(_Element e, String property) => [
    for (final r in _refinements[e.id] ?? const <_Element>[])
      if (r.property == property && r.text.isNotEmpty) r,
  ];

  /// Valores dos refinamentos de [e] com [property], marcados como usados.
  List<String> _refinedValues(_Element e, String property) {
    final refs = _refinedBy(e, property);
    _used.addAll(refs);
    return [for (final r in refs) r.text];
  }

  String? _first(String name) {
    final e = _dc(name).firstOrNull;
    if (e == null) return null;
    _used.add(e);
    return e.text;
  }

  void _identifiers(String? uniqueIdentifierId) {
    _Element? unique;
    for (final e in _dc('identifier')) {
      identifiers.add(e.text);
      if (unique == null && e.id != null && e.id == uniqueIdentifierId) {
        unique = e;
      }
    }
    unique ??= _dc('identifier').firstOrNull;
    if (unique != null) {
      uniqueIdentifiers.add(unique.text);
      _used.add(unique);
    }
  }

  void _build() {
    // Títulos.
    final titles = _dc('title').toList();
    String? typeOf(_Element t) =>
        _refinedValues(t, 'title-type').firstOrNull?.toLowerCase();
    final types = {for (final t in titles) t: typeOf(t)};
    final title =
        titles.where((t) => types[t] == 'main').firstOrNull ??
        titles
            .where((t) => types[t] != 'subtitle' && types[t] != 'expanded')
            .firstOrNull ??
        titles.firstOrNull;
    final subtitle = titles
        .where((t) => !identical(t, title) && types[t] == 'subtitle')
        .firstOrNull;
    if (title != null) _used.add(title);
    if (subtitle != null) _used.add(subtitle);

    // Autores e colaboradores.
    final authors = <String>[];
    final contributors = <String>[];
    for (final e in _all) {
      if (!e.isDc || e.text.isEmpty) continue;
      if (e.name != 'creator' && e.name != 'contributor') continue;
      final roles = [
        ?e.role,
        for (final r in _refinedValues(e, 'role')) r.toLowerCase(),
      ];
      final isAuthor =
          e.name == 'creator' && (roles.isEmpty || roles.contains('aut'));
      (isAuthor ? authors : contributors).add(e.text);
      _used.add(e);
    }

    // Série.
    String? series;
    double? seriesIndex;
    for (final c in _meta(property: 'belongs-to-collection')) {
      if (c.text.isEmpty) continue;
      final kinds = [
        for (final k in _refinedBy(c, 'collection-type')) k.text.toLowerCase(),
      ];
      // Coleção que não é série (`set`) fica em raw, com os refinamentos.
      if (kinds.isNotEmpty && !kinds.contains('series')) continue;
      series = c.text;
      _used
        ..add(c)
        ..addAll(_refinedBy(c, 'collection-type'));
      final position = _refinedValues(c, 'group-position').firstOrNull;
      seriesIndex = position == null ? null : double.tryParse(position);
      break;
    }
    if (series == null) {
      final calibre = _meta(name: 'calibre:series')
          .where((e) => (e.content ?? '').isNotEmpty)
          .firstOrNull;
      if (calibre != null) {
        series = calibre.content;
        _used.add(calibre);
        final index = _meta(name: 'calibre:series_index').firstOrNull;
        if (index != null) {
          seriesIndex = double.tryParse(index.content ?? '');
          _used.add(index);
        }
      }
    }

    // Datas.
    final dates = _dc('date').toList();
    final publication =
        dates.where((d) => d.event == 'publication').firstOrNull ??
        dates.where((d) => d.event != 'modification').firstOrNull;
    final published = _date(publication);
    final modifiedMeta = _meta(property: 'dcterms:modified')
        .where((e) => e.text.isNotEmpty)
        .firstOrNull;
    final modified = _date(
      modifiedMeta ?? dates.where((d) => d.event == 'modification').firstOrNull,
    );

    // Layout e capa (campos do OpfDocument, não de raw).
    final layoutMeta = _meta(property: 'rendition:layout').firstOrNull;
    if (layoutMeta != null) {
      _used.add(layoutMeta);
      if (layoutMeta.text == 'pre-paginated') {
        layout = EpubLayoutMode.prePaginated;
      }
    }
    final cover = _meta(name: 'cover')
        .where((e) => (e.content ?? '').isNotEmpty)
        .firstOrNull;
    if (cover != null) {
      coverId = cover.content;
      _used.add(cover);
    }

    final language = _first('language');
    final publisher = _first('publisher');
    final description = _first('description');
    final rights = _first('rights');
    final subjects = [for (final s in _dc('subject')) s.text];
    _used.addAll(_dc('subject'));

    metadata = EpubMetadata(
      title: title?.text,
      subtitle: subtitle?.text,
      authors: authors,
      contributors: contributors,
      language: language,
      publisher: publisher,
      identifier: uniqueIdentifiers.firstOrNull,
      description: description,
      published: published,
      modified: modified,
      subjects: subjects,
      rights: rights,
      series: series,
      seriesIndex: seriesIndex,
      raw: _raw(),
    );
  }

  /// Data do elemento, marcado como usado só se parseia.
  DateTime? _date(_Element? e) {
    if (e == null) return null;
    final value = parseEpubDate(e.text);
    if (value != null) _used.add(e);
    return value;
  }

  Map<String, List<String>> _raw() {
    final raw = <String, List<String>>{};
    for (final e in _all) {
      if (_used.contains(e)) continue;
      if (e.isDc) {
        if (e.text.isNotEmpty) (raw[e.name] ??= []).add(e.text);
      } else if (e.property != null && e.property!.isNotEmpty) {
        if (e.text.isNotEmpty) (raw[e.property!] ??= []).add(e.text);
      } else if (e.metaName != null && e.metaName!.isNotEmpty) {
        final content = e.content;
        if (content != null) (raw[e.metaName!] ??= []).add(content);
      }
    }
    return raw;
  }
}

final RegExp _partialDate = RegExp(r'^(\d{4})(?:-(\d{2}))?(?:-(\d{2}))?$');

/// `YYYY` → 1º de janeiro, `YYYY-MM` → dia 1, `YYYY-MM-DD` (UTC); o resto
/// por `DateTime.parse`. O que não parseia (ou passa de 64 caracteres) é
/// `null`.
DateTime? parseEpubDate(String text) {
  final s = text.trim();
  if (s.isEmpty || s.length > 64) return null;
  final m = _partialDate.firstMatch(s);
  if (m != null) {
    final year = int.parse(m.group(1)!);
    final month = int.parse(m.group(2) ?? '1');
    final day = int.parse(m.group(3) ?? '1');
    final value = DateTime.utc(year, month, day);
    return value.month == month && value.day == day ? value : null;
  }
  try {
    return DateTime.parse(s);
  } on FormatException {
    return null;
  } on ArgumentError {
    return null;
  }
}
```

- [ ] **Passo 4: Rodar e ver passar**

Run: `flutter test test/publication/opf_test.dart`
Expected: `All tests passed!` (41 testes).

- [ ] **Passo 5: Formatar e analisar**

Run: `dart format --output=none --set-exit-if-changed lib test && flutter analyze`
Expected: nada a formatar e `No issues found!`.

- [ ] **Passo 6: Commit**

```bash
git add lib/src/publication/opf.dart test/publication/opf_test.dart
git commit -m "feat(publication): parseOpf com metadados, manifest, spine e guide

Leitura por nome local (dc: com ou sem namespace, dc:Title do OEB),
título/subtítulo por title-type, autores por role, série, datas
parciais, raw só com o não mapeado, identificadores, manifest cru,
spine com spineItemUnresolved/spineItemDuplicate, direção, layout e
guide; fatais em EpubPackageException (spec §6.1–§6.3)."
```

---

### Tarefa 7: `parseNav`

Spec §7.2, decisões 13 e 14. O NAV é parseado com `package:html` (tolerante),
mas o texto passa antes por `htmlWorkCut`, que estima o trabalho do parser
HTML5 e corta onde ele passaria de `navParseBudget` ("O que foi verificado":
sem o corte, 50 000 níveis de `<ol><li>` levam 6 minutos).

**Por que é linear:**
- `htmlWorkCut` lê cada índice do texto uma vez (`indexOf` a partir do
  último ponto, nunca `substring` do resto); o resto do trabalho dele —
  profundidade somada a cada tag, busca do fechamento na pilha — é
  contabilizado no próprio orçamento, então fica em O(n + orçamento);
- o parser HTML5 recebe um texto cujo custo estimado cabe no orçamento;
- a caminhada itera `nodes` com pilha explícita (nunca indexa `children`);
  cada nó é visitado no máximo uma vez pela busca dos `nav`, uma pela busca da
  primeira lista do `nav`, uma pela varredura do `li` dono e uma pelo título,
  porque nenhuma dessas buscas desce em `ol`/`ul` (a lista aninhada é do `li`
  filho) nem em `nav` aninhado;
- a recursão por nível de lista para em `maxNavDepth` (64) e a contagem em
  `maxNavEntries` por `nav`.

**Arquivos:**
- Criar: `lib/src/publication/nav.dart`
- Teste: `test/publication/nav_test.dart`

**Interfaces:**
- Consome: nada do pacote (só `package:html`).
- Produz: `const int maxNavDepth = 64;`, `const int maxNavEntries = 100000;`, `const int navParseBudget = 1 << 24;`.
- Produz: `final class NavEntry { NavEntry({required String title, String? href, String? type, List<NavEntry> children = const []}); }` (entrada crua de NAV **e** de NCX; `href` cru).
- Produz: `final class NavDocument { NavDocument({required List<NavEntry> toc, required List<NavEntry> pageList, required List<NavEntry> landmarks, required bool truncated}); }`.
- Produz: `NavDocument parseNav(String text)` e `int? htmlWorkCut(String text, {int budget = navParseBudget})`.

- [ ] **Passo 1: Escrever o teste que falha**

Criar `test/publication/nav_test.dart`:

```dart
// parseNav: toc, page-list, landmarks, títulos e limites (spec da
// Publicação §7.2).
import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/publication/nav.dart';

String _html(String body) =>
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<html xmlns="http://www.w3.org/1999/xhtml" '
    'xmlns:epub="http://www.idpf.org/2007/ops"><head><title>N</title></head>'
    '<body>$body</body></html>';

List<Object> _shape(List<NavEntry> entries) => [
  for (final e in entries)
    e.children.isEmpty
        ? '${e.title}|${e.href}'
        : ['${e.title}|${e.href}', _shape(e.children)],
];

int _depth(List<NavEntry> entries) {
  var max = 0;
  for (final e in entries) {
    final d = 1 + _depth(e.children);
    if (d > max) max = d;
  }
  return max;
}

int _count(List<NavEntry> entries) =>
    entries.fold(0, (n, e) => n + 1 + _count(e.children));

void main() {
  test('toc aninhado com ol e ul', () {
    final nav = parseNav(
      _html(
        '<nav epub:type="toc"><h1>Sumário</h1><ol>'
        '<li><a href="c1.xhtml">Um</a><ul>'
        '<li><a href="c1.xhtml#s1">Um.um</a></li>'
        '<li><a href="c1.xhtml#s2">Um.dois</a><ol>'
        '<li><a href="c1.xhtml#s2a">Fundo</a></li></ol></li></ul></li>'
        '<li><a href="c2.xhtml">Dois</a></li></ol></nav>',
      ),
    );
    expect(_shape(nav.toc), [
      [
        'Um|c1.xhtml',
        [
          'Um.um|c1.xhtml#s1',
          [
            'Um.dois|c1.xhtml#s2',
            ['Fundo|c1.xhtml#s2a'],
          ],
        ],
      ],
      'Dois|c2.xhtml',
    ]);
    expect(nav.truncated, isFalse);
  });

  test('a dentro de p e strong; whitespace colapsado', () {
    final nav = parseNav(
      _html(
        '<nav epub:type="toc"><ol><li><p><strong><a href="c1.xhtml">'
        '\n  Capítulo\n\t <em>primeiro</em>  </a></strong></p></li></ol></nav>',
      ),
    );
    expect(_shape(nav.toc), ['Capítulo primeiro|c1.xhtml']);
  });

  test('span de agrupamento e a sem href não têm alvo', () {
    final nav = parseNav(
      _html(
        '<nav epub:type="toc"><ol><li><span>Parte I</span><ol>'
        '<li><a href="c1.xhtml">Um</a></li></ol></li>'
        '<li><a>Sem alvo</a></li></ol></nav>',
      ),
    );
    expect(_shape(nav.toc), [
      [
        'Parte I|null',
        ['Um|c1.xhtml'],
      ],
      'Sem alvo|null',
    ]);
  });

  test('título vazio: alt do img, depois title, depois vazio', () {
    final nav = parseNav(
      _html(
        '<nav epub:type="toc"><ol>'
        '<li><a href="a.xhtml"><img src="x.png" alt=" Mapa "/></a></li>'
        '<li><a href="b.xhtml" title="Pelo título"><img src="y.png"/></a></li>'
        '<li><a href="c.xhtml"> </a></li></ol></nav>',
      ),
    );
    expect(nav.toc.map((e) => e.title), ['Mapa', 'Pelo título', '']);
  });

  test('a lista aninhada não entra no título nem na busca do rótulo', () {
    final nav = parseNav(
      _html(
        '<nav epub:type="toc"><ol><li><ol><li><a href="f.xhtml">Filho</a>'
        '</li></ol><a href="p.xhtml">Pai</a></li></ol></nav>',
      ),
    );
    expect(_shape(nav.toc), [
      [
        'Pai|p.xhtml',
        ['Filho|f.xhtml'],
      ],
    ]);
  });

  test('landmarks com type e page-list', () {
    final nav = parseNav(
      _html(
        '<nav epub:type="landmarks"><ol>'
        '<li><a epub:type="cover" href="capa.xhtml">Capa</a></li>'
        '<li><a epub:type="bodymatter" href="c1.xhtml">Início</a></li></ol>'
        '</nav><nav epub:type="page-list" hidden=""><ol>'
        '<li><a href="c1.xhtml#p1">1</a></li><li><a href="c1.xhtml#p2">2</a>'
        '</li></ol></nav>',
      ),
    );
    expect(nav.toc, isEmpty);
    expect(nav.landmarks.map((e) => (e.type, e.href)), [
      ('cover', 'capa.xhtml'),
      ('bodymatter', 'c1.xhtml'),
    ]);
    expect(nav.pageList.map((e) => e.title), ['1', '2']);
    expect(nav.pageList.first.type, isNull);
  });

  test('dois nav do mesmo tipo: vale o primeiro; token no epub:type', () {
    final nav = parseNav(
      _html(
        '<nav epub:type="x toc"><ol><li><a href="a.xhtml">A</a></li></ol></nav>'
        '<nav epub:type="toc"><ol><li><a href="b.xhtml">B</a></li></ol></nav>'
        '<nav epub:type="tocx"><ol><li><a href="c.xhtml">C</a></li></ol></nav>',
      ),
    );
    expect(_shape(nav.toc), ['A|a.xhtml']);
  });

  test('HTML malformado e sem declaração', () {
    final nav = parseNav(
      '<nav epub:type="toc"><ol><li><a href="a.xhtml">A &amp; B&nbsp;C'
      '<li><a href="b.xhtml">B',
    );
    expect(nav.toc.map((e) => e.title), ['A & B C', 'B']);
  });

  test('profundidade 64: o nível 65 é descartado e marca truncated', () {
    String nested(int levels) => levels == 0
        ? ''
        : '<ol><li><a href="n$levels.xhtml">N</a>${nested(levels - 1)}'
              '</li></ol>';
    final ok = parseNav(_html('<nav epub:type="toc">${nested(64)}</nav>'));
    expect(_depth(ok.toc), 64);
    expect(ok.truncated, isFalse);
    final deep = parseNav(_html('<nav epub:type="toc">${nested(65)}</nav>'));
    expect(_depth(deep.toc), 64);
    expect(deep.truncated, isTrue);
  });

  test('100 000 entradas por nav: o excedente é descartado', () {
    final items = '<li><a href="a.xhtml">x</a></li>' * (maxNavEntries + 5);
    final nav = parseNav(
      _html(
        '<nav epub:type="toc"><ol>$items</ol></nav>'
        '<nav epub:type="page-list"><ol><li><a href="p.xhtml">1</a></li>'
        '</ol></nav>',
      ),
    );
    expect(_count(nav.toc), maxNavEntries);
    expect(nav.pageList, hasLength(1), reason: 'o limite é por nav');
    expect(nav.truncated, isTrue);
  });

  test('aninhamento hostil: corte linear antes do parse, truncated', () {
    final body = '<ol><li><a href="x.xhtml">t</a>' * 20000;
    final sw = Stopwatch()..start();
    final nav = parseNav(_html('<nav epub:type="toc">$body</nav>'));
    sw.stop();
    expect(nav.truncated, isTrue);
    expect(_depth(nav.toc), maxNavDepth);
    expect(
      sw.elapsed,
      lessThan(const Duration(seconds: 3)),
      reason: 'sem o corte, 20 000 níveis levam minutos',
    );
  });

  group('htmlWorkCut', () {
    test('documento comum cabe inteiro', () {
      expect(
        htmlWorkCut(_html('<nav><ol><li><a href="a">A</a></li></ol></nav>')),
        isNull,
      );
    });

    test('comentário, doctype, void e /> não empilham', () {
      final text =
          '<!DOCTYPE html><!-- <div><div> --><br><img src="x"><div/>' * 1000;
      expect(htmlWorkCut(text, budget: 20000), isNull);
    });

    test('fechamento sem abertura não desempilha a pilha real', () {
      final text = '${'<div>' * 100}${'</p>' * 1000}';
      expect(htmlWorkCut(text, budget: 50000), isNotNull);
    });

    test('corta no < da tag que estoura o orçamento', () {
      final text = '<div>' * 10;
      // 1 + 2 + … + 10 = 55; com orçamento 45 a 10ª tag (9 + 1) estoura.
      expect(htmlWorkCut(text, budget: 45), 45);
    });
  });
}
```

- [ ] **Passo 2: Rodar e ver falhar**

Run: `flutter test test/publication/nav_test.dart`
Expected: FAIL na compilação, com `Error when reading 'lib/src/publication/nav.dart': No such file or directory`.

- [ ] **Passo 3: Implementar**

Criar `lib/src/publication/nav.dart`:

```dart
/// NAV do EPUB3 com `package:html` (spec da Publicação §7.2; doc/03 §8).
///
/// Linear no tamanho do NAV:
/// - antes do parse, [htmlWorkCut] corta o texto onde o trabalho estimado do
///   parser HTML5 passaria de [navParseBudget] (o parser percorre a pilha de
///   elementos abertos em várias tags, e aninhamento hostil o deixaria
///   quadrático: 4 000 níveis de `<ol><li>` custam 1,3 s, 50 000 custam
///   6 min);
/// - a caminhada itera `nodes` com pilha explícita, nunca indexa `children`;
/// - cada nó é visitado no máximo uma vez pela busca dos `nav`, uma pela
///   busca da lista do `nav`, uma pela varredura do `li` dono e uma pelo
///   título: nenhuma delas desce em `ol`/`ul` (a lista aninhada é do `li`
///   filho) nem em `nav` aninhado;
/// - a recursão por nível de lista para em [maxNavDepth].
library;

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

/// Profundidade máxima de entradas (spec §7.2).
const int maxNavDepth = 64;

/// Máximo de entradas por `nav` (spec §7.2).
const int maxNavEntries = 100000;

/// Teto do trabalho estimado do parser HTML5 no NAV (~0,7 s no pior caso
/// medido; um NAV real de 100 000 entradas usa ~3 milhões).
const int navParseBudget = 1 << 24;

/// Entrada crua de NAV ou NCX: o `href` como está no documento.
final class NavEntry {
  NavEntry({
    required this.title,
    this.href,
    this.type,
    List<NavEntry> children = const [],
  }) : children = List.unmodifiable(children);

  /// Texto com whitespace colapsado; `''` se não houver.
  final String title;

  /// Cru; `null` em entrada sem alvo.
  final String? href;

  /// `epub:type` do `a` (só em landmarks).
  final String? type;
  final List<NavEntry> children;

  @override
  String toString() => 'NavEntry($title, $href)';
}

/// O que o NAV fornece.
final class NavDocument {
  NavDocument({
    required List<NavEntry> toc,
    required List<NavEntry> pageList,
    required List<NavEntry> landmarks,
    required this.truncated,
  }) : toc = List.unmodifiable(toc),
       pageList = List.unmodifiable(pageList),
       landmarks = List.unmodifiable(landmarks);

  final List<NavEntry> toc;
  final List<NavEntry> pageList;
  final List<NavEntry> landmarks;

  /// Algum limite de §7.2 (ou o [navParseBudget]) foi atingido; a parte lida
  /// está nas listas.
  final bool truncated;
}

/// Lê os `nav` de `toc`, `page-list` e `landmarks` (o primeiro de cada tipo).
NavDocument parseNav(String text) {
  final cut = htmlWorkCut(text);
  final document = html.parse(cut == null ? text : text.substring(0, cut));
  Element? toc;
  Element? pageList;
  Element? landmarks;
  final stack = <Node>[document];
  while (stack.isNotEmpty) {
    final node = stack.removeLast();
    if (node is Element && node.localName == 'nav') {
      final types = _tokens(node.attributes['epub:type']);
      if (toc == null && types.contains('toc')) toc = node;
      if (pageList == null && types.contains('page-list')) pageList = node;
      if (landmarks == null && types.contains('landmarks')) landmarks = node;
    }
    _pushChildren(stack, node);
  }
  final reader = _Reader();
  return NavDocument(
    toc: _navEntries(toc, reader.reset(), landmark: false),
    pageList: _navEntries(pageList, reader.reset(), landmark: false),
    landmarks: _navEntries(landmarks, reader.reset(), landmark: true),
    truncated: cut != null || reader.truncatedAny,
  );
}

/// Filhos de [node] na pilha, em ordem reversa (sai em ordem de documento).
void _pushChildren(List<Node> stack, Node node) {
  final children = node.nodes;
  for (var i = children.length - 1; i >= 0; i--) {
    stack.add(children[i]);
  }
}

Set<String> _tokens(String? value) => value == null
    ? const {}
    : value.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toSet();

bool _isList(Node node) =>
    node is Element && (node.localName == 'ol' || node.localName == 'ul');

/// Contagem de entradas de um `nav`.
final class _Reader {
  int count = 0;
  bool truncated = false;
  bool truncatedAny = false;

  _Reader reset() {
    count = 0;
    truncated = false;
    return this;
  }

  void truncate() {
    truncated = true;
    truncatedAny = true;
  }
}

List<NavEntry> _navEntries(
  Element? nav,
  _Reader reader, {
  required bool landmark,
}) {
  if (nav == null) return const [];
  // A primeira lista do nav, sem descer em nav aninhado.
  final stack = <Node>[];
  _pushChildren(stack, nav);
  while (stack.isNotEmpty) {
    final node = stack.removeLast();
    if (_isList(node)) {
      return _list(node as Element, 1, reader, landmark: landmark);
    }
    if (node is Element && node.localName == 'nav') continue;
    _pushChildren(stack, node);
  }
  return const [];
}

List<NavEntry> _list(
  Element list,
  int depth,
  _Reader reader, {
  required bool landmark,
}) {
  if (depth > maxNavDepth) {
    reader.truncate();
    return const [];
  }
  final out = <NavEntry>[];
  for (final node in list.nodes) {
    if (node is! Element || node.localName != 'li') continue;
    if (reader.count >= maxNavEntries) {
      reader.truncate();
      break;
    }
    reader.count++;
    final (label, sublist) = _scanItem(node);
    final children = sublist == null
        ? const <NavEntry>[]
        : _list(sublist, depth + 1, reader, landmark: landmark);
    out.add(
      NavEntry(
        title: label == null ? '' : _title(label),
        href: label?.localName == 'a' ? label!.attributes['href'] : null,
        type: landmark ? label?.attributes['epub:type']?.trim() : null,
        children: children,
      ),
    );
  }
  return out;
}

/// O primeiro `a`/`span` e a primeira lista descendentes de [li], sem descer
/// em listas nem em `nav`.
(Element?, Element?) _scanItem(Element li) {
  Element? label;
  Element? sublist;
  final stack = <Node>[];
  _pushChildren(stack, li);
  while (stack.isNotEmpty && (label == null || sublist == null)) {
    final node = stack.removeLast();
    if (node is! Element) continue;
    if (_isList(node)) {
      sublist ??= node;
      continue;
    }
    if (node.localName == 'nav') continue;
    if (label == null && (node.localName == 'a' || node.localName == 'span')) {
      label = node;
    }
    _pushChildren(stack, node);
  }
  return (label, sublist);
}

/// Whitespace do HTML (U+00A0 não entra: é conteúdo).
final RegExp _whitespace = RegExp(r'[ \t\n\r\f]+');

/// Texto dos descendentes de [label] (sem descer em listas), colapsado;
/// vazio → `alt` do primeiro `img`; vazio → atributo `title`; vazio → `''`.
String _title(Element label) {
  final text = StringBuffer();
  String? alt;
  final stack = <Node>[];
  _pushChildren(stack, label);
  while (stack.isNotEmpty) {
    final node = stack.removeLast();
    if (node is Text) {
      text.write(node.data);
      continue;
    }
    if (node is! Element || _isList(node)) continue;
    if (alt == null && node.localName == 'img') alt = node.attributes['alt'];
    _pushChildren(stack, node);
  }
  for (final candidate in [
    text.toString(),
    alt ?? '',
    label.attributes['title'] ?? '',
  ]) {
    final collapsed = candidate.replaceAll(_whitespace, ' ').trim();
    if (collapsed.isNotEmpty) return collapsed;
  }
  return '';
}

const Set<String> _voidElements = {
  'area',
  'base',
  'br',
  'col',
  'embed',
  'hr',
  'img',
  'input',
  'link',
  'meta',
  'param',
  'source',
  'track',
  'wbr',
};

bool _isLetter(int c) => (c | 0x20) >= 0x61 && (c | 0x20) <= 0x7A;

bool _isNameChar(int c) =>
    _isLetter(c) ||
    (c >= 0x30 && c <= 0x39) ||
    c == 0x2D ||
    c == 0x3A ||
    c == 0x5F ||
    c == 0x2E;

/// Índice onde cortar [text] para o parse HTML5 não passar de [budget]
/// passos estimados, ou `null` se cabe inteiro.
///
/// Estimativa: uma pilha de nomes de tag. Abertura empilha (menos elementos
/// vazios e `/>`); fechamento desempilha até o nome, se ele está na pilha;
/// cada tag soma a profundidade corrente, e a busca do fechamento soma o que
/// percorre. Aninhamento real custa `profundidade × tags`, e o corte cai
/// antes de a conta passar do orçamento. Um índice de [text] é lido uma vez,
/// e o resto do trabalho está no orçamento: linear.
int? htmlWorkCut(String text, {int budget = navParseBudget}) {
  final stack = <String>[];
  final n = text.length;
  var work = 0;
  var i = 0;
  while (i < n) {
    final lt = text.indexOf('<', i);
    if (lt < 0 || lt + 1 >= n) return null;
    final c = text.codeUnitAt(lt + 1);
    if (c == 0x21) {
      // <!-- comentário -->, <!DOCTYPE>, <![CDATA[ ]]>
      final comment = text.startsWith('<!--', lt);
      final end = comment
          ? text.indexOf('-->', lt + 4)
          : text.indexOf('>', lt + 2);
      if (end < 0) return null;
      i = end + (comment ? 3 : 1);
      continue;
    }
    final closing = c == 0x2F;
    final start = closing ? lt + 2 : lt + 1;
    if (start >= n || !_isLetter(text.codeUnitAt(start))) {
      i = lt + 1;
      continue;
    }
    var p = start + 1;
    while (p < n && _isNameChar(text.codeUnitAt(p))) {
      p++;
    }
    final gt = text.indexOf('>', p);
    if (gt < 0) return null;
    work += stack.length + 1;
    if (work > budget) return lt;
    final name = text.substring(start, p).toLowerCase();
    if (closing) {
      final at = stack.lastIndexOf(name);
      work += at < 0 ? stack.length : stack.length - at;
      if (at >= 0) stack.length = at;
    } else if (text.codeUnitAt(gt - 1) != 0x2F &&
        !_voidElements.contains(name)) {
      stack.add(name);
    }
    i = gt + 1;
  }
  return null;
}
```

- [ ] **Passo 4: Rodar e ver passar**

Run: `flutter test test/publication/nav_test.dart`
Expected: `All tests passed!` (15 testes). O teste "aninhamento
hostil" leva ~0,5 s; sem o `htmlWorkCut`, só o `html.parse` daquele texto
(20 000 níveis) leva 76 s.

- [ ] **Passo 5: Formatar e analisar**

Run: `dart format --output=none --set-exit-if-changed lib test && flutter analyze`
Expected: nada a formatar e `No issues found!`.

- [ ] **Passo 6: Commit**

```bash
git add lib/src/publication/nav.dart test/publication/nav_test.dart
git commit -m "feat(publication): parseNav com corte linear antes do parse HTML5

toc, page-list e landmarks do primeiro nav de cada tipo, com ol ou ul,
rótulo no primeiro a/span fora de lista aninhada, título colapsado com
fallback para alt e title, limites de 64 níveis e 100 000 entradas por
nav (spec §7.2). htmlWorkCut estima o custo do parser (profundidade ×
tags) e corta antes de 2^24: aninhamento hostil deixava o package:html
quadrático (50 000 níveis em 6 min)."
```

---

### Tarefa 8: `parseNcx`

Spec §7.3. Mesmos limites e `truncated` do NAV. O Foco de revisão 2 (`DOCTYPE`
do NCX 2005-1) e o 5 (100 000 níveis de `navPoint`) estão no grupo `foco de
revisão` do teste.

**Por que é linear:** um parse do `package:xml` (iterativo); cada
`navPoint`/`pageTarget` olha só os próprios filhos diretos, um número fixo de
vezes (`navLabel`, `content`, os filhos `navPoint`); o rótulo vem do texto
direto de `navLabel/text`, nunca de `innerText`; a recursão para em
`maxNavDepth` e a contagem em `maxNavEntries`.

**Arquivos:**
- Criar: `lib/src/publication/ncx.dart`
- Teste: `test/publication/ncx_test.dart`

**Interfaces:**
- Consome: `NavEntry`, `maxNavDepth`, `maxNavEntries` (Tarefa 7).
- Produz: `final class NcxDocument { NcxDocument({required List<NavEntry> toc, required List<NavEntry> pageList, required bool truncated}); }` e `NcxDocument parseNcx(String text)` — lança `XmlException` com XML inválido (o orquestrador captura).

- [ ] **Passo 1: Escrever o teste que falha**

Criar `test/publication/ncx_test.dart`:

```dart
// parseNcx: navMap, pageList, playOrder e limites (spec da Publicação §7.3).
import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/publication/nav.dart';
import 'package:galley/src/publication/ncx.dart';
import 'package:xml/xml.dart';

String _ncx(String body) =>
    '<?xml version="1.0"?>'
    '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">'
    '<head/><docTitle><text>Livro</text></docTitle>$body</ncx>';

String _point(String label, String? src, {String children = '', int? order}) =>
    '<navPoint id="p"${order == null ? '' : ' playOrder="$order"'}>'
    '<navLabel><text>$label</text></navLabel>'
    '${src == null ? '' : '<content src="$src"/>'}$children</navPoint>';

int _depth(List<NavEntry> entries) {
  var max = 0;
  for (final e in entries) {
    final d = 1 + _depth(e.children);
    if (d > max) max = d;
  }
  return max;
}

void main() {
  test('navMap aninhado', () {
    final ncx = parseNcx(
      _ncx(
        '<navMap>${_point('Um', 'c1.xhtml', children: _point('Um.um', 'c1.xhtml#s1'))}'
        '${_point('Dois', 'c2.xhtml')}</navMap>',
      ),
    );
    expect(ncx.toc.map((e) => (e.title, e.href)), [
      ('Um', 'c1.xhtml'),
      ('Dois', 'c2.xhtml'),
    ]);
    expect(ncx.toc.first.children.single.href, 'c1.xhtml#s1');
    expect(ncx.truncated, isFalse);
  });

  test('pageList com pageTarget', () {
    final ncx = parseNcx(
      _ncx(
        '<navMap/><pageList>'
        '<pageTarget type="normal" value="1"><navLabel><text>1</text>'
        '</navLabel><content src="c1.xhtml#pg1"/></pageTarget>'
        '<pageTarget type="normal" value="2"><navLabel><text>2</text>'
        '</navLabel><content src="c1.xhtml#pg2"/></pageTarget></pageList>',
      ),
    );
    expect(ncx.pageList.map((e) => (e.title, e.href)), [
      ('1', 'c1.xhtml#pg1'),
      ('2', 'c1.xhtml#pg2'),
    ]);
  });

  test('playOrder fora de ordem é ignorado: vale a ordem do documento', () {
    final ncx = parseNcx(
      _ncx(
        '<navMap>${_point('B', 'b.xhtml', order: 2)}'
        '${_point('A', 'a.xhtml', order: 1)}</navMap>',
      ),
    );
    expect(ncx.toc.map((e) => e.title), ['B', 'A']);
  });

  test('navPoint sem content não tem alvo; rótulo colapsado', () {
    final ncx = parseNcx(
      _ncx('<navMap>${_point('  Parte\n  I ', null)}</navMap>'),
    );
    expect(ncx.toc.single.title, 'Parte I');
    expect(ncx.toc.single.href, isNull);
  });

  test('sem namespace e com prefixo', () {
    final ncx = parseNcx(
      '<n:ncx xmlns:n="http://www.daisy.org/z3986/2005/ncx/"><n:navMap>'
      '<n:navPoint><n:navLabel><n:text>X</n:text></n:navLabel>'
      '<n:content src="x.xhtml"/></n:navPoint></n:navMap></n:ncx>',
    );
    expect(ncx.toc.single.href, 'x.xhtml');
    expect(
      parseNcx('<ncx><navMap>${_point('Y', 'y.xhtml')}</navMap></ncx>')
          .toc
          .single
          .title,
      'Y',
    );
  });

  test('XML inválido lança XmlException', () {
    expect(() => parseNcx('<ncx><navMap>'), throwsA(isA<XmlException>()));
  });

  test('limites: profundidade 64 e 100 000 entradas', () {
    var nested = '';
    for (var i = 0; i < 70; i++) {
      nested = _point('N$i', 'n.xhtml', children: nested);
    }
    final deep = parseNcx(_ncx('<navMap>$nested</navMap>'));
    expect(_depth(deep.toc), maxNavDepth);
    expect(deep.truncated, isTrue);

    final many = parseNcx(
      _ncx('<navMap>${_point('x', 'x.xhtml') * (maxNavEntries + 1)}</navMap>'),
    );
    expect(many.toc, hasLength(maxNavEntries));
    expect(many.truncated, isTrue);
  });

  group('foco de revisão', () {
    test('DOCTYPE do NCX 2005-1 (EPUB2)', () {
      final ncx = parseNcx(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN" '
        '"http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">\n'
        '${_ncx('<navMap>${_point('A', 'a.xhtml')}</navMap>').substring('<?xml version="1.0"?>'.length)}',
      );
      expect(ncx.toc.single.href, 'a.xhtml');
    });

    test('100 000 níveis de navPoint: sem estouro de pilha, truncated', () {
      final deep =
          '<ncx><navMap>'
          '${'<navPoint><navLabel><text>t</text></navLabel>' * 100000}'
          '${'</navPoint>' * 100000}</navMap></ncx>';
      final sw = Stopwatch()..start();
      final ncx = parseNcx(deep);
      sw.stop();
      expect(_depth(ncx.toc), maxNavDepth);
      expect(ncx.truncated, isTrue);
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
    });
  });
}
```

- [ ] **Passo 2: Rodar e ver falhar**

Run: `flutter test test/publication/ncx_test.dart`
Expected: FAIL na compilação, com `Error when reading 'lib/src/publication/ncx.dart': No such file or directory`.

- [ ] **Passo 3: Implementar**

Criar `lib/src/publication/ncx.dart`:

```dart
/// NCX do EPUB2 com `package:xml` (spec da Publicação §7.3).
///
/// Linear no tamanho do NCX: um parse, e cada `navPoint`/`pageTarget` olha
/// só os próprios filhos diretos (o rótulo vem do texto direto de
/// `navLabel/text`, nunca de `innerText`); a recursão por nível para em
/// [maxNavDepth] e a contagem em [maxNavEntries], como no NAV.
library;

import 'package:xml/xml.dart';

import 'nav.dart';

/// O que o NCX fornece.
final class NcxDocument {
  NcxDocument({
    required List<NavEntry> toc,
    required List<NavEntry> pageList,
    required this.truncated,
  }) : toc = List.unmodifiable(toc),
       pageList = List.unmodifiable(pageList);

  final List<NavEntry> toc;
  final List<NavEntry> pageList;

  /// Algum limite de §7.2 foi atingido; a parte lida está nas listas.
  final bool truncated;
}

/// `navMap/navPoint` recursivo e `pageList/pageTarget`, por nome local.
/// `playOrder` é ignorado. [XmlException] com XML inválido.
NcxDocument parseNcx(String text) {
  final root = XmlDocument.parse(text).rootElement;
  final navMap = _child(root, 'navMap');
  final pageList = _child(root, 'pageList');
  final tocCount = _Count();
  final pageCount = _Count();
  return NcxDocument(
    toc: navMap == null ? const [] : _points(navMap, 'navPoint', 1, tocCount),
    pageList: pageList == null
        ? const []
        : _points(pageList, 'pageTarget', 1, pageCount),
    truncated: tocCount.truncated || pageCount.truncated,
  );
}

final class _Count {
  int count = 0;
  bool truncated = false;
}

List<NavEntry> _points(XmlElement parent, String local, int depth, _Count c) {
  if (depth > maxNavDepth) {
    c.truncated = true;
    return const [];
  }
  final out = <NavEntry>[];
  for (final e in parent.childElements) {
    if (e.name.local != local) continue;
    if (c.count >= maxNavEntries) {
      c.truncated = true;
      break;
    }
    c.count++;
    final label = _child(e, 'navLabel');
    final text = label == null ? null : _child(label, 'text');
    out.add(
      NavEntry(
        title: text == null ? '' : _ownText(text),
        href: _child(e, 'content')?.getAttribute('src', namespaceUri: '*'),
        children: local == 'navPoint'
            ? _points(e, local, depth + 1, c)
            : const [],
      ),
    );
  }
  return out;
}

XmlElement? _child(XmlElement parent, String local) {
  for (final e in parent.childElements) {
    if (e.name.local == local) return e;
  }
  return null;
}

/// Whitespace do XML (U+00A0 não entra: é conteúdo).
final RegExp _whitespace = RegExp(r'[ \t\n\r]+');

String _ownText(XmlElement e) {
  final buffer = StringBuffer();
  for (final node in e.children) {
    if (node is XmlText) {
      buffer.write(node.value);
    } else if (node is XmlCDATA) {
      buffer.write(node.value);
    }
  }
  return buffer.toString().replaceAll(_whitespace, ' ').trim();
}
```

- [ ] **Passo 4: Rodar e ver passar**

Run: `flutter test test/publication/ncx_test.dart`
Expected: `All tests passed!` (9 testes).

- [ ] **Passo 5: Formatar e analisar**

Run: `dart format --output=none --set-exit-if-changed lib test && flutter analyze`
Expected: nada a formatar e `No issues found!`.

- [ ] **Passo 6: Commit**

```bash
git add lib/src/publication/ncx.dart test/publication/ncx_test.dart
git commit -m "feat(publication): parseNcx

navMap/navPoint recursivo e pageList/pageTarget por nome local,
playOrder ignorado, navPoint sem content sem alvo, mesmos limites do
NAV; XML inválido lança XmlException (spec §7.3)."
```

---

### Tarefa 9: `reconcileToc` e `findCover`

Spec §7.6 e §8.2. Duas funções puras sobre o modelo.

**Por que é linear (`reconcileToc`):** um mapa caminho → índice do spine; uma
caminhada iterativa pelo TOC que marca os caminhos cobertos e o menor índice
de cada raiz; um vetor `lastBefore[i]` (maior raiz com menor índice `< i`)
por prefixo máximo, em vez de procurar a raiz de cada órfão; e uma montagem
única. O(entradas + spine) — o teste de 20 000 raízes e 20 000 órfãos conferia
isso. **`findCover`:** no máximo duas passadas pelo manifest e uma consulta
por `id`.

**Arquivos:**
- Criar: `lib/src/publication/reconcile.dart`
- Criar: `lib/src/publication/cover.dart`
- Teste: `test/publication/reconcile_test.dart`
- Teste: `test/publication/cover_test.dart`

**Interfaces:**
- Consome: `NavPoint`, `NavTarget`, `SpineItem`, `ManifestItem` (Tarefa 2); `basenameWithoutExtension` (Tarefa 4); `OpfDocument.coverId` e `parseOpf` (Tarefa 6, o teste de capa monta o `OpfDocument` por ele); `EpubDiagnosticCode.tocReconciled`, `.coverHeuristic`, `EpubPackageException` (Tarefa 1).
- Produz: `List<NavPoint> reconcileToc(List<NavPoint> toc, List<SpineItem> spine, {required DiagnosticSink sink})` — devolve o próprio `toc` (mesma instância) se não há órfão; `tocReconciled` com `href: null` e `details: {orphans: n}`.
- Produz: `String? findCover(OpfDocument opf, Map<String, ManifestItem> manifest, {required DiagnosticSink sink})` — `coverHeuristic` com `href` = caminho e `details: {id}` no passo 3.

- [ ] **Passo 1: Escrever os testes que falham**

Criar `test/publication/reconcile_test.dart`:

```dart
// reconcileToc: órfãos do spine no TOC (spec da Publicação §7.6).
import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/diagnostics/diagnostic.dart';
import 'package:galley/src/publication/model.dart';
import 'package:galley/src/publication/reconcile.dart';

List<SpineItem> _spine(List<String> names, {Set<String> nonLinear = const {}}) {
  return [
    for (final n in names)
      () {
        final item = ManifestItem(
          id: n,
          path: 'OEBPS/$n.xhtml',
          mediaType: 'application/xhtml+xml',
        );
        return SpineItem(
          idref: n,
          item: item,
          content: item,
          linear: !nonLinear.contains(n),
        );
      }(),
  ];
}

NavPoint _entry(String name, {List<NavPoint> children = const []}) => NavPoint(
  title: name.toUpperCase(),
  target: NavTarget('OEBPS/$name.xhtml', 'f'),
  children: children,
);

List<String> _titles(List<NavPoint> toc) => [
  for (final e in toc) e.synthesized ? '+${e.title}' : e.title,
];

void main() {
  test('sem órfão: o mesmo TOC e nenhum diagnóstico', () {
    final sink = DiagnosticSink();
    final toc = [_entry('a'), _entry('b')];
    expect(reconcileToc(toc, _spine(['a', 'b']), sink: sink), same(toc));
    expect(sink.diagnostics, isEmpty);
  });

  test('órfãos no começo, no meio, no fim e consecutivos', () {
    final sink = DiagnosticSink();
    final out = reconcileToc(
      [_entry('c'), _entry('f')],
      _spine(['a', 'b', 'c', 'd', 'e', 'f', 'g']),
      sink: sink,
    );
    expect(_titles(out), ['+a', '+b', 'C', '+d', '+e', 'F', '+g']);
    final synthesized = out.first;
    expect(synthesized.target, const NavTarget('OEBPS/a.xhtml'));
    expect(synthesized.children, isEmpty);
    final d = sink.diagnostics.single;
    expect(d.code, EpubDiagnosticCode.tocReconciled);
    expect(d.severity, EpubSeverity.info);
    expect(d.href, isNull);
    expect(d.details, {'orphans': 5, 'count': 1});
  });

  test('coberto em qualquer nível não é órfão; posição pelo descendente', () {
    final out = reconcileToc(
      [
        NavPoint(title: 'Parte', children: [_entry('b')]),
        _entry('d'),
      ],
      _spine(['a', 'b', 'c', 'd']),
      sink: DiagnosticSink(),
    );
    expect(_titles(out), ['+a', 'Parte', '+c', 'D']);
  });

  test('ordem do TOC manda: raiz fora de ordem não se move', () {
    final out = reconcileToc(
      [_entry('d'), _entry('b')],
      _spine(['a', 'b', 'c', 'd', 'e']),
      sink: DiagnosticSink(),
    );
    // c (índice 2): última raiz com primeira < 2 é "b" (posição 1).
    // e (índice 4): a última raiz, na ordem do TOC, com primeira < 4 é "b".
    expect(_titles(out), ['+a', 'D', 'B', '+c', '+e']);
  });

  test('linear="no" nunca é órfão, e a entrada para ele é mantida', () {
    final sink = DiagnosticSink();
    final withEntry = reconcileToc(
      [_entry('a'), _entry('notas')],
      _spine(['a', 'notas'], nonLinear: {'notas'}),
      sink: sink,
    );
    expect(_titles(withEntry), ['A', 'NOTAS']);
    final without = reconcileToc(
      [_entry('a')],
      _spine(['a', 'notas'], nonLinear: {'notas'}),
      sink: sink,
    );
    expect(_titles(without), ['A']);
    expect(sink.diagnostics, isEmpty);
  });

  test('alvo fora do spine e entrada sem alvo são mantidos', () {
    final out = reconcileToc(
      [
        NavPoint(title: 'Externo'),
        NavPoint(title: 'Fora', target: const NavTarget('OEBPS/x.xhtml')),
        _entry('b'),
      ],
      _spine(['a', 'b', 'c']),
      sink: DiagnosticSink(),
    );
    expect(_titles(out), ['+a', 'Externo', 'Fora', 'B', '+c']);
  });

  test('sem TOC: tudo sintetizado, na ordem do spine', () {
    final sink = DiagnosticSink();
    final out = reconcileToc(const [], _spine(['a', 'b']), sink: sink);
    expect(_titles(out), ['+a', '+b']);
    expect(sink.diagnostics.single.details['orphans'], 2);
  });

  test('custo linear: 20 000 raízes e 20 000 órfãos', () {
    final names = [for (var i = 0; i < 40000; i++) 'c$i'];
    final toc = [for (var i = 1; i < 40000; i += 2) _entry('c$i')];
    final sw = Stopwatch()..start();
    final out = reconcileToc(toc, _spine(names), sink: DiagnosticSink());
    sw.stop();
    expect(out, hasLength(40000));
    expect(out.first.synthesized, isTrue);
    expect(out[1].synthesized, isFalse);
    expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
  });
}
```

Criar `test/publication/cover_test.dart`:

```dart
// findCover: os três passos de pacote (spec da Publicação §8.2).
import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/diagnostics/diagnostic.dart';
import 'package:galley/src/publication/cover.dart';
import 'package:galley/src/publication/model.dart';
import 'package:galley/src/publication/opf.dart';

OpfDocument _opf({String? coverId}) => parseOpf(
  '<package><metadata>'
  '${coverId == null ? '' : '<meta name="cover" content="$coverId"/>'}'
  '</metadata><manifest><item id="c1" href="c1.xhtml" '
  'media-type="application/xhtml+xml"/></manifest>'
  '<spine><itemref idref="c1"/></spine></package>',
  opfPath: 'content.opf',
  sink: DiagnosticSink(),
);

ManifestItem _item(
  String id,
  String path, {
  String mediaType = 'image/jpeg',
  Set<String> properties = const {},
  bool missing = false,
  bool remote = false,
}) => ManifestItem(
  id: id,
  path: path,
  mediaType: mediaType,
  properties: properties,
  missing: missing,
  remote: remote,
);

Map<String, ManifestItem> _manifest(List<ManifestItem> items) => {
  for (final i in items) i.id: i,
};

void main() {
  test('1: properties cover-image', () {
    final sink = DiagnosticSink();
    final manifest = _manifest([
      _item('capa-velha', 'Images/cover.jpg'),
      _item('img', 'Images/frente.jpg', properties: {'cover-image'}),
    ]);
    expect(
      findCover(_opf(coverId: 'capa-velha'), manifest, sink: sink),
      'Images/frente.jpg',
    );
    expect(sink.diagnostics, isEmpty);
  });

  test('2: meta name="cover", sem diagnóstico', () {
    final sink = DiagnosticSink();
    final manifest = _manifest([
      _item('cover-a', 'Images/cover-a.jpg'),
      _item('frente', 'Images/frente.png', mediaType: 'image/png'),
    ]);
    expect(
      findCover(_opf(coverId: 'frente'), manifest, sink: sink),
      'Images/frente.png',
    );
    expect(sink.diagnostics, isEmpty);
  });

  test('3: imagem com "cover" no id ou no caminho, com coverHeuristic', () {
    final sink = DiagnosticSink(strict: true);
    final manifest = _manifest([
      _item(
        'texto-cover',
        'Text/cover.xhtml',
        mediaType: 'application/xhtml+xml',
      ),
      _item('i1', 'Images/MyCOVER.JPG'),
    ]);
    expect(findCover(_opf(), manifest, sink: sink), 'Images/MyCOVER.JPG');
    final d = sink.diagnostics.single;
    expect(d.code, EpubDiagnosticCode.coverHeuristic);
    expect(d.severity, EpubSeverity.info);
    expect(d.href, 'Images/MyCOVER.JPG');
  });

  test('missing e remote são pulados em todos os passos', () {
    final sink = DiagnosticSink();
    final manifest = _manifest([
      _item(
        'a',
        'Images/cover.png',
        properties: {'cover-image'},
        missing: true,
      ),
      _item(
        'b',
        'https://x/cover.jpg',
        properties: {'cover-image'},
        remote: true,
      ),
      _item('cover', 'Images/c.jpg', missing: true),
      _item('capa', 'Images/cover2.jpg'),
    ]);
    expect(
      findCover(_opf(coverId: 'cover'), manifest, sink: sink),
      'Images/cover2.jpg',
    );
    expect(sink.diagnostics.single.code, EpubDiagnosticCode.coverHeuristic);
  });

  test('nenhum: null', () {
    final sink = DiagnosticSink();
    expect(
      findCover(
        _opf(coverId: 'nao-existe'),
        _manifest([_item('i', 'Images/foto.jpg')]),
        sink: sink,
      ),
      isNull,
    );
    expect(sink.diagnostics, isEmpty);
  });
}
```

- [ ] **Passo 2: Rodar e ver falhar**

Run: `flutter test test/publication/reconcile_test.dart test/publication/cover_test.dart`
Expected: FAIL na compilação, com `Error when reading 'lib/src/publication/reconcile.dart'` e `'lib/src/publication/cover.dart': No such file or directory`.

- [ ] **Passo 3: `reconcileToc`**

Criar `lib/src/publication/reconcile.dart`:

```dart
/// Reconciliação do TOC com o spine (spec da Publicação §7.6; doc/03 §3.1).
///
/// Linear em entradas + spine: uma caminhada iterativa pelo TOC para os
/// caminhos cobertos e o menor índice do spine de cada raiz, um vetor de
/// "última raiz antes do índice i" por prefixo máximo e uma montagem única.
library;

import '../diagnostics/diagnostic.dart';
import '../diagnostics/exceptions.dart';
import 'href.dart';
import 'model.dart';

/// [toc] com os órfãos do spine inseridos como entradas raiz
/// `synthesized`. Órfão: item com `linear` verdadeiro cujo `item.path`
/// nenhuma entrada, em qualquer nível, tem como `target.path`. O órfão de
/// índice `i` entra logo depois da última raiz, na ordem do TOC, cujo menor
/// índice do spine (dela e dos descendentes) é menor que `i`; sem nenhuma,
/// no início. Emite `tocReconciled` uma vez, se houver órfão.
List<NavPoint> reconcileToc(
  List<NavPoint> toc,
  List<SpineItem> spine, {
  required DiagnosticSink sink,
}) {
  final spineIndex = <String, int>{};
  for (var i = 0; i < spine.length; i++) {
    spineIndex.putIfAbsent(spine[i].item.path, () => i);
  }
  final covered = <String>{};
  // Menor índice do spine por raiz (spine.length = sem alvo no spine).
  final first = List<int>.filled(toc.length, spine.length);
  for (var r = 0; r < toc.length; r++) {
    final stack = <NavPoint>[toc[r]];
    while (stack.isNotEmpty) {
      final point = stack.removeLast();
      final path = point.target?.path;
      if (path != null) {
        covered.add(path);
        final index = spineIndex[path];
        if (index != null && index < first[r]) first[r] = index;
      }
      stack.addAll(point.children);
    }
  }
  final orphans = <int>[
    for (var i = 0; i < spine.length; i++)
      if (spine[i].linear &&
          !covered.contains(spine[i].item.path) &&
          spineIndex[spine[i].item.path] == i)
        i,
  ];
  if (orphans.isEmpty) return toc;

  // lastBefore[i] = maior r com first[r] < i, ou -1.
  final lastAt = List<int>.filled(spine.length + 1, -1);
  for (var r = 0; r < toc.length; r++) {
    if (first[r] < spine.length && r > lastAt[first[r]]) lastAt[first[r]] = r;
  }
  final lastBefore = List<int>.filled(spine.length + 1, -1);
  for (var i = 1; i <= spine.length; i++) {
    final candidate = lastAt[i - 1];
    lastBefore[i] = candidate > lastBefore[i - 1]
        ? candidate
        : lastBefore[i - 1];
  }

  // Órfãos por posição de inserção (antes da raiz `slot`), na ordem do spine.
  final bySlot = <int, List<NavPoint>>{};
  for (final i in orphans) {
    final path = spine[i].item.path;
    (bySlot[lastBefore[i] + 1] ??= []).add(
      NavPoint(
        title: basenameWithoutExtension(path),
        target: NavTarget(path),
        synthesized: true,
      ),
    );
  }
  final out = <NavPoint>[];
  for (var slot = 0; slot <= toc.length; slot++) {
    out.addAll(bySlot[slot] ?? const []);
    if (slot < toc.length) out.add(toc[slot]);
  }
  sink.emit(
    EpubDiagnosticCode.tocReconciled,
    message: '${orphans.length} itens do spine fora do TOC inseridos',
    details: {'orphans': orphans.length},
    onStrict: EpubPackageException.new,
  );
  return out;
}
```

- [ ] **Passo 4: `findCover`**

Criar `lib/src/publication/cover.dart`:

```dart
/// Capa pelo pacote (spec da Publicação §8.2; doc/06 §5.1, passos 1, 2 e 4).
/// Os passos que olham a seção (3 e 5 de doc/06) são do sub-projeto 6.
library;

import '../diagnostics/diagnostic.dart';
import '../diagnostics/exceptions.dart';
import 'model.dart';
import 'opf.dart';

/// Caminho da capa, na ordem: `properties` com `cover-image`; o item do
/// `<meta name="cover">`; um `image/*` cujo `id` ou caminho contém `cover`
/// (sem diferenciar maiúsculas, com `coverHeuristic`). Itens `missing` ou
/// `remote` são pulados. Uma passada pelo manifest por passo.
String? findCover(
  OpfDocument opf,
  Map<String, ManifestItem> manifest, {
  required DiagnosticSink sink,
}) {
  bool usable(ManifestItem item) => !item.missing && !item.remote;
  for (final item in manifest.values) {
    if (usable(item) && item.properties.contains('cover-image')) {
      return item.path;
    }
  }
  final byMeta = opf.coverId == null ? null : manifest[opf.coverId];
  if (byMeta != null && usable(byMeta)) return byMeta.path;
  for (final item in manifest.values) {
    if (!usable(item) || !item.mediaType.startsWith('image/')) continue;
    if (item.id.toLowerCase().contains('cover') ||
        item.path.toLowerCase().contains('cover')) {
      sink.emit(
        EpubDiagnosticCode.coverHeuristic,
        href: item.path,
        message: 'capa achada por heurística (id ou caminho com "cover")',
        details: {'id': item.id},
        onStrict: (m) => EpubPackageException(m, href: item.path),
      );
      return item.path;
    }
  }
  return null;
}
```

- [ ] **Passo 5: Rodar e ver passar**

Run: `flutter test test/publication/reconcile_test.dart test/publication/cover_test.dart`
Expected: `All tests passed!` (13 testes).

- [ ] **Passo 6: Formatar e analisar**

Run: `dart format --output=none --set-exit-if-changed lib test && flutter analyze`
Expected: nada a formatar e `No issues found!`.

- [ ] **Passo 7: Commit**

```bash
git add lib/src/publication/reconcile.dart lib/src/publication/cover.dart test/publication/reconcile_test.dart test/publication/cover_test.dart
git commit -m "feat(publication): reconcileToc e findCover

Órfãos do spine (linear, fora do TOC em qualquer nível) como raízes
sintetizadas logo depois da última raiz com menor índice anterior, em
tempo linear, com tocReconciled (spec §7.6); capa por cover-image, meta
cover e heurística de id/caminho com coverHeuristic, pulando missing e
remote (spec §8.2)."
```

---

### Tarefa 10: `readPublication`

Spec §5.3, §5.4, §6.4, §7.4, §7.5, §8.1 e §9, na ordem de §9: `container.xml`
→ OPF → itens do manifest → conferência de fontes → spine e `fallback` →
NAV/NCX → alvos → reconciliação → capa. Decisões 7, 8, 9, 15, 16, 17, 19 e
20. Os itens 1, 3 e 4 do Foco de revisão estão no grupo `foco de revisão` do
teste. O apoio de teste monta EPUBs com o `ZipWriter` do corpus (pelo
`zip_fixtures.dart` do contêiner) e serve os mesmos arquivos por um provider
em memória.

**Por que é linear:** cada documento é lido uma vez e entregue ao parser
linear dele; o manifest é uma passada com no máximo duas chamadas de `exists`
por item; o spine, uma passada com conjunto de caminhos vistos; a cadeia de
`fallback` tem no máximo 16 passos por item do spine; os alvos são casados por
dois mapas (exato e em minúsculas), montados uma vez; a conversão de entradas
em `NavPoint` é uma recursão com profundidade ≤ 64 (os parsers já cortaram).

**Arquivos:**
- Criar: `lib/src/publication/read_publication.dart`
- Criar: `test/publication/support/epub_fixtures.dart`
- Teste: `test/publication/read_publication_test.dart`

**Interfaces:**
- Consome: `EpubContainer` (`exists`, `fetch`, `obfuscationOf`), `PendingResource` (`path`, `size`, `decode()`, `bytes`), `ZipContainer.open`, `ProviderContainer.open`, `MemoryEpubByteSource`, `EpubResourceProvider` (sub-projeto 1); `epubZip` e `ZipWriter` (`test/container/support/zip_fixtures.dart`); tudo das Tarefas 1–9.
- Produz: `const int maxPackageDocumentSize = 4 * 1024 * 1024;`, `const int maxFallbackSteps = 16;`, `const String ncxMediaType = 'application/x-dtbncx+xml';`.
- Produz: `Future<EpubPublication> readPublication(EpubContainer container, {required DiagnosticSink sink})` — não fecha o contêiner.
- Produz: `bool isFontMediaType(String mediaType)`.
- Produz (apoio de teste): `String containerXml([List<String> fullPaths])`, `String item(String id, String href, {String mediaType, String? properties, String? fallback})`, `String itemref(String idref, {bool linear = true})`, `String opfXml({String metadata, required List<String> items, required List<String> itemrefs, String spineAttributes = '', String extra = ''})`, `String navXml(String navs)`, `String tocNav(List<(String, String)> entries, {String type = 'toc'})`, `String ncxXml(List<(String, String)> entries, {String pageList = ''})`, `const String chapter`, `Map<String, List<int>> epubFiles(Map<String, Object?> files)`, `Future<ZipContainer> openZip(Map<String, Object?> files, {required DiagnosticSink sink})`, `final class MapProvider implements EpubResourceProvider { MapProvider(Map<String, Object?> files, {Set<String> failingRead = const {}, Set<String> failingExists = const {}}); bool closed; }`.

- [ ] **Passo 1: Apoio de teste**

Criar `test/publication/support/epub_fixtures.dart`:

```dart
/// EPUBs de teste da Publicação: `container.xml`, OPF, NAV e NCX de texto,
/// montados com o `ZipWriter` do corpus ou servidos por um provider em
/// memória (spec da Publicação §10).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:galley/src/container/byte_source.dart';
import 'package:galley/src/container/resource_provider.dart';
import 'package:galley/src/container/zip/zip_container.dart';
import 'package:galley/src/diagnostics/diagnostic.dart';

import '../../container/support/zip_fixtures.dart';

export '../../container/support/zip_fixtures.dart' show ZipWriter, epubZip;

const String xhtmlType = 'application/xhtml+xml';
const String ncxType = 'application/x-dtbncx+xml';

String containerXml([List<String> fullPaths = const ['OEBPS/content.opf']]) =>
    '<?xml version="1.0"?><container version="1.0" '
    'xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles>'
    '${[for (final p in fullPaths) '<rootfile full-path="$p" media-type="application/oebps-package+xml"/>'].join()}'
    '</rootfiles></container>';

/// `<item>` do manifest.
String item(
  String id,
  String href, {
  String mediaType = xhtmlType,
  String? properties,
  String? fallback,
}) =>
    '<item id="$id" href="$href" media-type="$mediaType"'
    '${properties == null ? '' : ' properties="$properties"'}'
    '${fallback == null ? '' : ' fallback="$fallback"'}/>';

/// `<itemref>` do spine.
String itemref(String idref, {bool linear = true}) =>
    '<itemref idref="$idref"${linear ? '' : ' linear="no"'}/>';

String opfXml({
  String metadata =
      '<dc:identifier id="uid">urn:uuid:teste</dc:identifier>'
      '<dc:title>Teste</dc:title>',
  required List<String> items,
  required List<String> itemrefs,
  String spineAttributes = '',
  String extra = '',
}) =>
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
    'unique-identifier="uid"><metadata '
    'xmlns:dc="http://purl.org/dc/elements/1.1/">$metadata</metadata>'
    '<manifest>${items.join()}</manifest>'
    '<spine$spineAttributes>${itemrefs.join()}</spine>$extra</package>';

/// NAV com os `nav` dados.
String navXml(String navs) =>
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<html xmlns="http://www.w3.org/1999/xhtml" '
    'xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Nav</title>'
    '</head><body>$navs</body></html>';

/// `nav` de `toc` com uma lista de `(título, href)`.
String tocNav(List<(String, String)> entries, {String type = 'toc'}) =>
    '<nav epub:type="$type"><ol>'
    '${[for (final (t, h) in entries) '<li><a href="$h">$t</a></li>'].join()}'
    '</ol></nav>';

String ncxXml(List<(String, String)> entries, {String pageList = ''}) =>
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">'
    '<head/><docTitle><text>T</text></docTitle><navMap>'
    '${[for (final (t, h) in entries) '<navPoint><navLabel><text>$t</text></navLabel><content src="$h"/></navPoint>'].join()}'
    '</navMap>$pageList</ncx>';

const String chapter =
    '<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml">'
    '<body><p>texto</p></body></html>';

/// [files] com `container.xml` padrão (a menos que dado, ou `null` para
/// omitir); valores `String` (UTF-8) ou `List<int>`.
Map<String, List<int>> epubFiles(Map<String, Object?> files) {
  final all = <String, Object?>{
    'META-INF/container.xml': containerXml(),
    ...files,
  };
  return {
    for (final MapEntry(:key, :value) in all.entries)
      if (value != null)
        key: value is String ? utf8.encode(value) : value as List<int>,
  };
}

Future<ZipContainer> openZip(
  Map<String, Object?> files, {
  required DiagnosticSink sink,
}) => ZipContainer.open(
  MemoryEpubByteSource(epubZip(epubFiles(files))),
  sink: sink,
);

/// Provider em memória. [failingRead] lança em `read`; [failingExists]
/// lança em `exists`.
final class MapProvider implements EpubResourceProvider {
  MapProvider(
    Map<String, Object?> files, {
    this.failingRead = const {},
    this.failingExists = const {},
  }) : files = epubFiles(files);

  final Map<String, List<int>> files;
  final Set<String> failingRead;
  final Set<String> failingExists;
  bool closed = false;

  @override
  Future<bool> exists(String href) async {
    if (failingExists.contains(href)) {
      throw FileSystemException('exists falhou', href);
    }
    return files.containsKey(href);
  }

  @override
  Future<Uint8List> read(String href) async {
    if (failingRead.contains(href)) {
      throw FileSystemException('read falhou', href);
    }
    return Uint8List.fromList(files[href]!);
  }

  @override
  Future<void> close() async => closed = true;
}
```

- [ ] **Passo 2: Escrever o teste que falha**

Criar `test/publication/read_publication_test.dart`:

```dart
// readPublication sobre EPUBs montados e sobre ProviderContainer (spec da
// Publicação §5.3, §5.4, §6.4, §7.4, §7.5, §8.1 e §9).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/container/byte_source.dart';
import 'package:galley/src/container/container.dart';
import 'package:galley/src/container/provider_container.dart';
import 'package:galley/src/container/zip/zip_container.dart';
import 'package:galley/src/diagnostics/diagnostic.dart';
import 'package:galley/src/diagnostics/exceptions.dart';
import 'package:galley/src/publication/model.dart';
import 'package:galley/src/publication/read_publication.dart';

import 'support/epub_fixtures.dart';

/// Livro mínimo: dois capítulos, NAV e NCX; [files] substitui ou acrescenta
/// (valor `null` remove).
Map<String, Object?> _book([Map<String, Object?> files = const {}]) => {
  'OEBPS/content.opf': opfXml(
    items: [
      item('nav', 'nav.xhtml', properties: 'nav'),
      item('ncx', 'toc.ncx', mediaType: ncxType),
      item('c1', 'Text/c1.xhtml'),
      item('c2', 'Text/c2.xhtml'),
    ],
    itemrefs: [itemref('c1'), itemref('c2')],
    spineAttributes: ' toc="ncx"',
  ),
  'OEBPS/nav.xhtml': navXml(
    tocNav([('Um', 'Text/c1.xhtml'), ('Dois', 'Text/c2.xhtml')]),
  ),
  'OEBPS/toc.ncx': ncxXml([('Um (NCX)', 'Text/c1.xhtml')]),
  'OEBPS/Text/c1.xhtml': chapter,
  'OEBPS/Text/c2.xhtml': chapter,
  ...files,
};

Future<(EpubPublication, DiagnosticSink)> _read(
  Map<String, Object?> files, {
  bool strict = false,
}) async {
  final sink = DiagnosticSink(strict: strict);
  final container = await openZip(files, sink: sink);
  try {
    return (await readPublication(container, sink: sink), sink);
  } finally {
    await container.close();
  }
}

List<String> _codes(DiagnosticSink sink) => [
  for (final d in sink.diagnostics) d.code.name,
];

EpubDiagnostic _only(DiagnosticSink sink, EpubDiagnosticCode code) =>
    sink.diagnostics.singleWhere((d) => identical(d.code, code));

void main() {
  group('livro bem formado', () {
    test('modelo completo, sem diagnóstico, strict', () async {
      final (p, sink) = await _read(_book(), strict: true);
      expect(sink.diagnostics, isEmpty);
      expect(p.opfPath, 'OEBPS/content.opf');
      expect(p.version, '3.0');
      expect(p.metadata.title, 'Teste');
      expect(p.uniqueIdentifiers, ['urn:uuid:teste']);
      expect(p.identifiers, ['urn:uuid:teste']);
      expect(p.manifest.keys, ['nav', 'ncx', 'c1', 'c2']);
      expect(p.spine.map((s) => s.item.path), [
        'OEBPS/Text/c1.xhtml',
        'OEBPS/Text/c2.xhtml',
      ]);
      expect(p.spine.first.kind, SectionKind.xhtml);
      expect(p.toc.map((e) => (e.title, e.target)), [
        ('Um', const NavTarget('OEBPS/Text/c1.xhtml')),
        ('Dois', const NavTarget('OEBPS/Text/c2.xhtml')),
      ]);
      expect(p.navPath, 'OEBPS/nav.xhtml');
      // Sem page-list no NAV, o NCX é lido (e não tem page-list).
      expect(p.ncxPath, 'OEBPS/toc.ncx');
      expect(p.pageList, isEmpty);
      expect(p.direction, EpubReadingDirection.auto);
      expect(p.layout, EpubLayoutMode.reflowable);
      expect(p.coverPath, isNull);
    });

    test('coleções não modificáveis e o contêiner continua aberto', () async {
      final sink = DiagnosticSink();
      final container = await openZip(_book(), sink: sink);
      final p = await readPublication(container, sink: sink);
      expect(() => p.spine.clear(), throwsUnsupportedError);
      expect(() => p.manifest.clear(), throwsUnsupportedError);
      expect(
        () => p.toc.first.children.add(p.toc.first),
        throwsUnsupportedError,
      );
      expect(await container.exists('OEBPS/Text/c1.xhtml'), isTrue);
      await container.close();
    });
  });

  group('caminhos do manifest (§5.3)', () {
    test('tentativa dupla: decodificado, cru e nenhum', () async {
      final (p, sink) = await _read(
        _book({
          'OEBPS/content.opf': opfXml(
            items: [
              item('dec', 'Text/cap%C3%ADtulo%201.xhtml'),
              item('cru', 'Text/100%25.xhtml'),
              item('nada', 'Text/n%C3%A3o.xhtml'),
            ],
            itemrefs: [itemref('dec'), itemref('cru'), itemref('nada')],
          ),
          'OEBPS/Text/capítulo 1.xhtml': chapter,
          'OEBPS/Text/100%25.xhtml': chapter,
        }),
      );
      expect(p.manifest['dec']!.path, 'OEBPS/Text/capítulo 1.xhtml');
      expect(p.manifest['dec']!.missing, isFalse);
      expect(p.manifest['cru']!.path, 'OEBPS/Text/100%25.xhtml');
      expect(p.manifest['cru']!.missing, isFalse);
      expect(p.manifest['nada']!.path, 'OEBPS/Text/não.xhtml');
      expect(p.manifest['nada']!.missing, isTrue);
      final d = _only(sink, EpubDiagnosticCode.resourceMissing);
      expect(d.href, 'OEBPS/Text/não.xhtml');
      expect(d.details, {'id': 'nada', 'count': 1});
      expect(p.spine, hasLength(3), reason: 'item missing fica no spine');
    });

    test('%2e%2e não atravessa a raiz: vale a forma crua', () async {
      final (p, sink) = await _read(
        _book({
          'OEBPS/content.opf': opfXml(
            items: [
              item('c1', 'Text/c1.xhtml'),
              item('fora', '%2e%2e/%2e%2e/segredo.xhtml'),
            ],
            itemrefs: [itemref('c1')],
          ),
          'segredo.xhtml': chapter,
        }),
      );
      final fora = p.manifest['fora']!;
      expect(fora.path, 'OEBPS/%2e%2e/%2e%2e/segredo.xhtml');
      expect(fora.missing, isTrue);
      expect(_codes(sink), ['resourceMissing', 'tocReconciled']);
    });

    test('href recusado: path cru, resourceMissing sem href', () async {
      final (p, sink) = await _read(
        _book({
          'OEBPS/content.opf': opfXml(
            items: [
              item('c1', 'Text/c1.xhtml'),
              item('fora', '../../fora.xhtml'),
              item('mail', 'mailto:x@y.z'),
            ],
            itemrefs: [itemref('c1')],
          ),
        }),
      );
      expect(p.manifest['fora']!.path, '../../fora.xhtml');
      expect(p.manifest['fora']!.missing, isTrue);
      expect(p.manifest['mail']!.missing, isTrue);
      final d = _only(sink, EpubDiagnosticCode.resourceMissing);
      expect(d.href, isNull);
      expect(d.details, {'id': 'mail', 'raw': 'mailto:x@y.z', 'count': 2});
    });

    test('remote: sem diagnóstico, nunca missing', () async {
      final (p, sink) = await _read(
        _book({
          'OEBPS/content.opf': opfXml(
            items: [
              item('c1', 'Text/c1.xhtml'),
              item('audio', 'https://ex.com/a.mp3', mediaType: 'audio/mpeg'),
            ],
            itemrefs: [itemref('c1')],
          ),
        }),
      );
      final audio = p.manifest['audio']!;
      expect(audio.remote, isTrue);
      expect(audio.missing, isFalse);
      expect(audio.path, 'https://ex.com/a.mp3');
      expect(_codes(sink), ['tocReconciled'], reason: 'sem NAV no OPF');
    });

    test('item que é o próprio OPF ou um diretório é missing', () async {
      final (p, sink) = await _read(
        _book({
          'OEBPS/content.opf': opfXml(
            items: [
              item('c1', 'Text/c1.xhtml'),
              item(
                'opf',
                'content.opf',
                mediaType: 'application/oebps-package+xml',
              ),
              item('dir', 'Text/'),
            ],
            itemrefs: [itemref('c1')],
          ),
        }),
      );
      expect(p.manifest['opf']!.missing, isTrue);
      expect(p.manifest['dir']!.missing, isTrue);
      expect(
        sink.diagnostics
            .where((d) => identical(d.code, EpubDiagnosticCode.resourceMissing))
            .map((d) => (d.href, d.details['reason'])),
        [('OEBPS/content.opf', 'opf'), ('OEBPS/Text', 'directory')],
      );
    });

    test('media-type em minúsculas e sem parâmetros', () async {
      final (p, _) = await _read(
        _book({
          'OEBPS/content.opf': opfXml(
            items: [
              item(
                'c1',
                'Text/c1.xhtml',
                mediaType: ' Application/XHTML+XML; charset=utf-8',
              ),
            ],
            itemrefs: [itemref('c1')],
          ),
        }),
      );
      expect(p.manifest['c1']!.mediaType, 'application/xhtml+xml');
      expect(p.spine.single.kind, SectionKind.xhtml);
    });
  });

  group('spine e fallback (§6.3, §6.4)', () {
    test('fallback em cadeia até o primeiro XHTML existente', () async {
      final (p, sink) = await _read(
        _book({
          'OEBPS/content.opf': opfXml(
            items: [
              item('pdf', 'a.pdf', mediaType: 'application/pdf', fallback: 'x'),
              item('x', 'x.xhtml', fallback: 'img'),
              item('img', 'i.png', mediaType: 'image/png'),
            ],
            itemrefs: [itemref('pdf')],
          ),
          'OEBPS/a.pdf': [1, 2, 3],
          'OEBPS/i.png': [1, 2, 3],
        }),
      );
      final s = p.spine.single;
      expect(s.item.id, 'pdf');
      expect(s.content.id, 'img', reason: 'x.xhtml é missing: pula');
      expect(s.kind, SectionKind.image);
      expect(_codes(sink), ['resourceMissing', 'tocReconciled']);
    });

    test(
      'fallback em ciclo: content é o próprio item, unsupportedMediaType',
      () async {
        final (p, sink) = await _read(
          _book({
            'OEBPS/content.opf': opfXml(
              items: [
                item('a', 'a.pdf', mediaType: 'application/pdf', fallback: 'b'),
                item(
                  'b',
                  'b.epub',
                  mediaType: 'application/epub+zip',
                  fallback: 'a',
                ),
              ],
              itemrefs: [itemref('a')],
            ),
            'OEBPS/a.pdf': [1],
            'OEBPS/b.epub': [1],
          }),
        );
        expect(p.spine.single.content.id, 'a');
        expect(p.spine.single.kind, SectionKind.unsupported);
        final d = _only(sink, EpubDiagnosticCode.unsupportedMediaType);
        expect(d.href, 'OEBPS/a.pdf');
        expect(d.details['mediaType'], 'application/pdf');
      },
    );

    test('cadeia de fallback para em 16 passos', () async {
      final items = [
        for (var i = 0; i < 20; i++)
          item(
            'f$i',
            'f$i.bin',
            mediaType: 'application/octet-stream',
            fallback: 'f${i + 1}',
          ),
        item('f20', 'f20.xhtml'),
      ];
      final (p, sink) = await _read(
        _book({
          'OEBPS/content.opf': opfXml(items: items, itemrefs: [itemref('f0')]),
          for (var i = 0; i < 20; i++) 'OEBPS/f$i.bin': [0],
          'OEBPS/f20.xhtml': chapter,
        }),
      );
      expect(p.spine.single.content.id, 'f0');
      expect(_codes(sink), ['unsupportedMediaType', 'tocReconciled']);
    });

    test(
      'mesmo caminho por dois ids: spineItemDuplicate, vale o primeiro',
      () async {
        final (p, sink) = await _read(
          _book({
            'OEBPS/content.opf': opfXml(
              items: [item('a', 'Text/c1.xhtml'), item('b', 'Text/./c1.xhtml')],
              itemrefs: [itemref('a'), itemref('b')],
            ),
          }),
        );
        expect(p.spine.map((s) => s.idref), ['a']);
        final d = _only(sink, EpubDiagnosticCode.spineItemDuplicate);
        expect(d.href, 'OEBPS/content.opf');
        expect(d.details['idref'], 'b');
      },
    );

    test('spine vazio depois de descartar idrefs sem item é fatal', () async {
      await expectLater(
        _read(
          _book({
            'OEBPS/content.opf': opfXml(
              items: [item('c1', 'Text/c1.xhtml')],
              itemrefs: [itemref('x'), itemref('y')],
            ),
          }),
        ),
        throwsA(
          isA<EpubPackageException>()
              .having((e) => e.href, 'href', 'OEBPS/content.opf')
              .having((e) => e.message, 'message', 'spine vazio'),
        ),
      );
    });
  });

  group('NAV e NCX (§7)', () {
    test('NAV quebrado (missing) → NCX', () async {
      final (p, sink) = await _read(_book({'OEBPS/nav.xhtml': null}));
      expect(p.navPath, isNull);
      expect(p.ncxPath, 'OEBPS/toc.ncx');
      expect(p.toc.first.title, 'Um (NCX)');
      expect(p.toc.first.synthesized, isFalse);
      final ignored = _only(sink, EpubDiagnosticCode.navIgnored);
      expect(ignored.href, 'OEBPS/nav.xhtml');
      expect(ignored.details['reason'], 'missing');
      expect(_codes(sink), ['resourceMissing', 'navIgnored', 'tocReconciled']);
    });

    test(
      'NAV sem nav de toc: no-toc, NCX dá o TOC, NAV dá landmarks',
      () async {
        final (p, sink) = await _read(
          _book({
            'OEBPS/nav.xhtml': navXml(
              tocNav([('Início', 'Text/c1.xhtml')], type: 'landmarks'),
            ),
          }),
        );
        expect(p.toc.map((e) => e.title), ['Um (NCX)', 'c2']);
        expect(
          p.landmarks.single.target,
          const NavTarget('OEBPS/Text/c1.xhtml'),
        );
        expect(p.navPath, 'OEBPS/nav.xhtml');
        expect(
          _only(sink, EpubDiagnosticCode.navIgnored).details['reason'],
          'no-toc',
        );
      },
    );

    test('NCX com XML inválido: invalid; sem TOC, tudo sintetizado', () async {
      final (p, sink) = await _read(
        _book({'OEBPS/nav.xhtml': null, 'OEBPS/toc.ncx': '<ncx><navMap>'}),
      );
      expect(p.ncxPath, isNull);
      expect(p.toc.map((e) => (e.title, e.synthesized)), [
        ('c1', true),
        ('c2', true),
      ]);
      final reasons = [
        for (final d in sink.diagnostics)
          if (identical(d.code, EpubDiagnosticCode.navIgnored))
            (d.href, d.details['reason']),
      ];
      expect(reasons, [
        ('OEBPS/nav.xhtml', 'missing'),
        ('OEBPS/toc.ncx', 'invalid'),
      ]);
    });

    test('sem NAV nem NCX no manifest', () async {
      final (p, sink) = await _read(
        _book({
          'OEBPS/content.opf': opfXml(
            items: [item('c1', 'Text/c1.xhtml')],
            itemrefs: [itemref('c1')],
          ),
        }),
      );
      expect(p.navPath, isNull);
      expect(p.ncxPath, isNull);
      expect(p.toc.single.synthesized, isTrue);
      expect(_codes(sink), ['tocReconciled']);
    });

    test('NAV em diretório diferente do OPF e #frag do próprio NAV', () async {
      final (p, _) = await _read(
        _book({
          'OEBPS/content.opf': opfXml(
            items: [
              item('nav', 'nav/toc.xhtml', properties: 'nav'),
              item('c1', 'Text/c1.xhtml'),
            ],
            itemrefs: [itemref('c1')],
          ),
          'OEBPS/nav/toc.xhtml': navXml(
            tocNav([('Um', '../Text/c1.xhtml#s1'), ('Aqui', '#topo')]),
          ),
        }),
      );
      expect(p.toc.map((e) => e.target), [
        const NavTarget('OEBPS/Text/c1.xhtml', 's1'),
        const NavTarget('OEBPS/nav/toc.xhtml', 'topo'),
      ]);
    });

    test(
      'alvos: maiúsculas, %xx, externo, fora da raiz, sem casamento',
      () async {
        final (p, sink) = await _read(
          _book({
            'OEBPS/content.opf': opfXml(
              items: [
                item('nav', 'nav.xhtml', properties: 'nav'),
                item('c1', 'Text/Cap%C3%ADtulo.xhtml'),
              ],
              itemrefs: [itemref('c1')],
            ),
            'OEBPS/Text/Capítulo.xhtml': chapter,
            'OEBPS/nav.xhtml': navXml(
              tocNav([
                ('Caixa', 'TEXT/CAP%C3%8DTULO.XHTML#a%20b'),
                ('Externo', 'https://ex.com/x.html'),
                ('Fora', '../../x.xhtml'),
                ('', 'Text/outro.xhtml'),
              ]),
            ),
          }),
        );
        expect(p.toc.map((e) => (e.title, e.target)), [
          ('Caixa', const NavTarget('OEBPS/Text/Capítulo.xhtml', 'a b')),
          ('Externo', null),
          ('Fora', null),
          ('outro', const NavTarget('OEBPS/Text/outro.xhtml')),
        ]);
        expect(sink.diagnostics, isEmpty);
      },
    );

    test('page-list: NAV; senão NCX', () async {
      const ncxPages =
          '<pageList><pageTarget><navLabel><text>7</text></navLabel>'
          '<content src="Text/c1.xhtml#p7"/></pageTarget></pageList>';
      final fromNcx = (await _read(
        _book({
          'OEBPS/toc.ncx': ncxXml([
            ('Um', 'Text/c1.xhtml'),
          ], pageList: ncxPages),
        }),
      )).$1;
      expect(fromNcx.pageList.single.title, '7');
      expect(
        fromNcx.pageList.single.target,
        const NavTarget('OEBPS/Text/c1.xhtml', 'p7'),
      );

      final fromNav = (await _read(
        _book({
          'OEBPS/nav.xhtml': navXml(
            tocNav([('Um', 'Text/c1.xhtml'), ('Dois', 'Text/c2.xhtml')]) +
                tocNav([('1', 'Text/c1.xhtml#p1')], type: 'page-list'),
          ),
          'OEBPS/toc.ncx': ncxXml([
            ('Um', 'Text/c1.xhtml'),
          ], pageList: ncxPages),
        }),
      )).$1;
      expect(fromNav.pageList.single.title, '1');
      expect(fromNav.ncxPath, isNull);
    });

    test('landmarks: guide do OPF quando o NAV não tem', () async {
      final (p, _) = await _read(
        _book({
          'OEBPS/content.opf': opfXml(
            items: [
              item('nav', 'nav.xhtml', properties: 'nav'),
              item('c1', 'Text/c1.xhtml'),
            ],
            itemrefs: [itemref('c1')],
            extra:
                '<guide><reference type="text" title="Começo" '
                'href="Text/c1.xhtml#i"/></guide>',
          ),
        }),
      );
      expect(p.landmarks.single.type, 'text');
      expect(p.landmarks.single.title, 'Começo');
      expect(
        p.landmarks.single.target,
        const NavTarget('OEBPS/Text/c1.xhtml', 'i'),
      );
    });

    test('NAV truncado: navIgnored truncated, a parte lida é usada', () async {
      var nested = '';
      for (var i = 0; i < 70; i++) {
        nested = '<ol><li><a href="Text/c1.xhtml#n$i">N$i</a>$nested</li></ol>';
      }
      final (p, sink) = await _read(
        _book({
          'OEBPS/nav.xhtml': navXml('<nav epub:type="toc">$nested</nav>'),
        }),
      );
      expect(p.toc.first.title, 'N69');
      expect(
        _only(sink, EpubDiagnosticCode.navIgnored).details['reason'],
        'truncated',
      );
    });

    test('NAV acima do teto: too-large, sem drenar', () async {
      final big = navXml(
        '<nav epub:type="toc"><ol><li><a href="Text/c1.xhtml">x</a></li></ol>'
        '</nav><p>${'a' * maxPackageDocumentSize}</p>',
      );
      final (p, sink) = await _read(_book({'OEBPS/nav.xhtml': big}));
      expect(p.navPath, isNull);
      expect(p.toc.first.title, 'Um (NCX)');
      expect(
        _only(sink, EpubDiagnosticCode.navIgnored).details['reason'],
        'too-large',
      );
    });
  });

  group('fatais (§9.1)', () {
    test('container.xml ausente', () async {
      await expectLater(
        _read(_book({'META-INF/container.xml': null})),
        throwsA(
          isA<EpubContainerException>().having(
            (e) => e.href,
            'href',
            'META-INF/container.xml',
          ),
        ),
      );
    });

    test('rootfile inexistente seguido de válido', () async {
      final (p, _) = await _read(
        _book({
          'META-INF/container.xml': containerXml([
            'nao/existe.opf',
            'OEBPS/content.opf',
          ]),
        }),
      );
      expect(p.opfPath, 'OEBPS/content.opf');
    });

    test(
      'nenhum rootfile existe: OPF ausente com o primeiro full-path',
      () async {
        await expectLater(
          _read(
            _book({
              'META-INF/container.xml': containerXml(['a.opf', 'b.opf']),
            }),
          ),
          throwsA(
            isA<EpubPackageException>()
                .having((e) => e.href, 'href', 'a.opf')
                .having((e) => e.message, 'message', 'OPF ausente'),
          ),
        );
      },
    );

    test('full-path com outra caixa: opfPath é o nome real', () async {
      final (p, sink) = await _read(
        _book({
          'META-INF/container.xml': containerXml(['oebps/CONTENT.opf']),
        }),
      );
      expect(p.opfPath, 'OEBPS/content.opf');
      expect(p.spine.first.item.path, 'OEBPS/Text/c1.xhtml');
      expect(_codes(sink), ['pathCaseMismatch']);
    });

    test('OPF acima do teto e OPF inválido', () async {
      await expectLater(
        _read(
          _book({
            'OEBPS/content.opf':
                '<package>${' ' * maxPackageDocumentSize}</package>',
          }),
        ),
        throwsA(
          isA<EpubPackageException>().having(
            (e) => e.message,
            'message',
            contains('teto'),
          ),
        ),
      );
      await expectLater(
        _read(_book({'OEBPS/content.opf': '<package><manifest>'})),
        throwsA(
          isA<EpubPackageException>().having(
            (e) => e.href,
            'href',
            'OEBPS/content.opf',
          ),
        ),
      );
    });

    test('ofuscação sobre conteúdo é EpubEncryptedException', () async {
      String encryption(String uri) =>
          '<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container" '
          'xmlns:enc="http://www.w3.org/2001/04/xmlenc#"><enc:EncryptedData>'
          '<enc:EncryptionMethod Algorithm="http://www.idpf.org/2008/embedding"/>'
          '<enc:CipherData><enc:CipherReference URI="$uri"/></enc:CipherData>'
          '</enc:EncryptedData></encryption>';
      Map<String, Object?> withFont(String mediaType) => _book({
        'META-INF/encryption.xml': encryption('OEBPS/Fonts/f.ttf'),
        'OEBPS/content.opf': opfXml(
          items: [
            item('c1', 'Text/c1.xhtml'),
            item('f', 'Fonts/f.ttf', mediaType: mediaType),
          ],
          itemrefs: [itemref('c1')],
        ),
        'OEBPS/Fonts/f.ttf': Uint8List(2000),
      });
      await expectLater(
        _read(withFont(xhtmlType)),
        throwsA(
          isA<EpubEncryptedException>()
              .having(
                (e) => e.scheme,
                'scheme',
                'unknown:obfuscation-on-content',
              )
              .having((e) => e.href, 'href', 'OEBPS/Fonts/f.ttf'),
        ),
      );
      for (final type in [
        'font/ttf',
        'application/vnd.ms-opentype',
        'application/x-font-ttf',
        'application/font-woff',
        'application/octet-stream',
      ]) {
        final (p, _) = await _read(withFont(type));
        expect(p.manifest['f']!.missing, isFalse, reason: type);
      }
    });
  });

  group('strict (§9.1)', () {
    test('warning da Publicação lança EpubPackageException', () async {
      await expectLater(
        _read(_book({'OEBPS/Text/c2.xhtml': null}), strict: true),
        throwsA(
          isA<EpubPackageException>()
              .having((e) => e.href, 'href', 'OEBPS/Text/c2.xhtml')
              .having(
                (e) => e.message,
                'message',
                startsWith('resourceMissing: '),
              ),
        ),
      );
    });

    test(
      'exceção do sink na leitura do NAV propaga (não vira unreadable)',
      () async {
        final files = epubFiles(_book());
        final w = ZipWriter()
          ..add(
            'mimetype',
            ascii.encode('application/epub+zip'),
            compress: false,
          );
        for (final MapEntry(:key, :value) in files.entries) {
          w.add(key, value, crcOverride: key == 'OEBPS/nav.xhtml' ? 1 : null);
        }
        final zip = w.build();
        Future<EpubPublication> run(DiagnosticSink sink) async {
          final c = await ZipContainer.open(
            MemoryEpubByteSource(zip),
            sink: sink,
          );
          return readPublication(c, sink: sink);
        }

        await expectLater(
          run(DiagnosticSink(strict: true)),
          throwsA(
            isA<EpubContainerException>().having(
              (e) => e.message,
              'message',
              startsWith('zipCrcMismatch: '),
            ),
          ),
        );
        final relaxed = DiagnosticSink();
        final p = await run(relaxed);
        expect(
          p.navPath,
          'OEBPS/nav.xhtml',
          reason: 'fora de strict, só diagnóstico',
        );
        expect(_codes(relaxed), ['zipCrcMismatch']);
      },
    );
  });

  group('ProviderContainer', () {
    Future<(EpubPublication, DiagnosticSink)> readProvider(
      MapProvider provider,
    ) async {
      final sink = DiagnosticSink();
      final container = await ProviderContainer.open(provider, sink: sink);
      return (await readPublication(container, sink: sink), sink);
    }

    test('lê o livro sem ZIP', () async {
      final (p, sink) = await readProvider(MapProvider(_book()));
      expect(p.toc.map((e) => e.title), ['Um', 'Dois']);
      expect(sink.diagnostics, isEmpty);
    });

    test('exists que lança: missing e resourceUnreadable', () async {
      final (p, sink) = await readProvider(
        MapProvider(_book(), failingExists: {'OEBPS/Text/c2.xhtml'}),
      );
      expect(p.manifest['c2']!.missing, isTrue);
      final d = _only(sink, EpubDiagnosticCode.resourceUnreadable);
      expect(d.href, 'OEBPS/Text/c2.xhtml');
      expect(d.details['reason'], 'exists');
      expect(d.details['exception'], contains('exists falhou'));
    });

    test('read do NAV que lança: unreadable e NCX', () async {
      final (p, sink) = await readProvider(
        MapProvider(_book(), failingRead: {'OEBPS/nav.xhtml'}),
      );
      expect(p.toc.first.title, 'Um (NCX)');
      expect(_codes(sink), [
        'resourceUnreadable',
        'navIgnored',
        'tocReconciled',
      ]);
      expect(
        _only(sink, EpubDiagnosticCode.navIgnored).details['reason'],
        'unreadable',
      );
    });

    test(
      'read do container.xml que lança: a EpubContainerException propaga',
      () async {
        final sink = DiagnosticSink();
        final container = await ProviderContainer.open(
          MapProvider(_book(), failingRead: {'META-INF/container.xml'}),
          sink: sink,
        );
        await expectLater(
          readPublication(container, sink: sink),
          throwsA(
            isA<EpubContainerException>()
                .having((e) => e.href, 'href', 'META-INF/container.xml')
                .having((e) => e.cause, 'cause', isNotNull),
          ),
        );
      },
    );

    test('read do OPF que lança: a EpubContainerException propaga', () async {
      final sink = DiagnosticSink();
      final container = await ProviderContainer.open(
        MapProvider(_book(), failingRead: {'OEBPS/content.opf'}),
        sink: sink,
      );
      await expectLater(
        readPublication(container, sink: sink),
        throwsA(
          isA<EpubContainerException>().having(
            (e) => e.href,
            'href',
            'OEBPS/content.opf',
          ),
        ),
      );
    });

    test('readPublication não fecha o contêiner', () async {
      final provider = MapProvider(_book());
      final EpubContainer container = await ProviderContainer.open(
        provider,
        sink: DiagnosticSink(),
      );
      await readPublication(container, sink: DiagnosticSink());
      expect(provider.closed, isFalse);
      await container.close();
      expect(provider.closed, isTrue);
    });
  });

  group('foco de revisão', () {
    test('OPF na raiz do contêiner', () async {
      final (p, sink) = await _read({
        'META-INF/container.xml': containerXml(['content.opf']),
        'content.opf': opfXml(
          items: [
            item('nav', 'nav.xhtml', properties: 'nav'),
            item('c1', 'c1.xhtml'),
          ],
          itemrefs: [itemref('c1')],
        ),
        'nav.xhtml': navXml(tocNav([('Um', 'c1.xhtml')])),
        'c1.xhtml': chapter,
      });
      expect(p.opfPath, 'content.opf');
      expect(p.spine.single.item.path, 'c1.xhtml');
      expect(p.toc.single.target, const NavTarget('c1.xhtml'));
      expect(sink.diagnostics, isEmpty);
    });

    test('OPF em UTF-16 LE com BOM', () async {
      final opf = opfXml(
        metadata:
            '<dc:identifier id="uid">u</dc:identifier>'
            '<dc:title>Título em UTF-16</dc:title>',
        items: [item('c1', 'Text/c1.xhtml')],
        itemrefs: [itemref('c1')],
      ).replaceFirst('encoding="UTF-8"', 'encoding="UTF-16"');
      final bytes = <int>[0xFF, 0xFE];
      for (final u in opf.codeUnits) {
        bytes.addAll([u & 0xFF, u >> 8]);
      }
      final (p, sink) = await _read(_book({'OEBPS/content.opf': bytes}));
      expect(p.metadata.title, 'Título em UTF-16');
      expect(p.spine.single.kind, SectionKind.xhtml);
      expect(_codes(sink), ['tocReconciled']);
    });

    test('OEB 1.2: text/x-oeb1-document é seção xhtml', () async {
      final (p, sink) = await _read(
        _book({
          'OEBPS/content.opf': opfXml(
            items: [
              item('a', 'Text/c1.xhtml', mediaType: 'text/x-oeb1-document'),
            ],
            itemrefs: [itemref('a')],
          ),
        }),
      );
      expect(p.spine.single.kind, SectionKind.xhtml);
      expect(_codes(sink), isNot(contains('unsupportedMediaType')));
    });
  });
}
```

- [ ] **Passo 3: Rodar e ver falhar**

Run: `flutter test test/publication/read_publication_test.dart`
Expected: FAIL na compilação, com `Error when reading 'lib/src/publication/read_publication.dart': No such file or directory`.

- [ ] **Passo 4: Implementar**

Criar `lib/src/publication/read_publication.dart`:

```dart
/// Orquestrador da Publicação (spec §9): lê `container.xml`, OPF, NAV e NCX
/// do contêiner, resolve caminhos e chama os parsers puros.
library;

import 'dart:typed_data';

import 'package:xml/xml.dart';

import '../container/container.dart';
import '../diagnostics/diagnostic.dart';
import '../diagnostics/exceptions.dart';
import 'container_xml.dart';
import 'cover.dart';
import 'href.dart';
import 'model.dart';
import 'nav.dart';
import 'ncx.dart';
import 'opf.dart';
import 'reconcile.dart';
import 'xml_text.dart';

/// Teto de `container.xml`, OPF, NAV e NCX: acima dele o recurso não é
/// drenado (OPF → fatal; NAV/NCX → `navIgnored`).
const int maxPackageDocumentSize = 4 * 1024 * 1024;

/// Máximo de passos na cadeia de `fallback` (spec §6.4).
const int maxFallbackSteps = 16;

const String ncxMediaType = 'application/x-dtbncx+xml';

/// Lê a publicação de [container]. Não fecha o contêiner (quem abriu fecha).
///
/// Fatais (spec §9.1): [EpubContainerException] para `container.xml`
/// ausente, ilegível ou sem `rootfile`; [EpubPackageException] para OPF
/// ausente, grande demais, inválido ou com spine vazio;
/// [EpubEncryptedException] para ofuscação declarada sobre conteúdo. A
/// exceção do [sink] em `strict` propaga como está.
Future<EpubPublication> readPublication(
  EpubContainer container, {
  required DiagnosticSink sink,
}) => _Reader(container, sink).read();

final class _Reader {
  _Reader(this.container, this.sink);

  final EpubContainer container;
  final DiagnosticSink sink;

  late final String opfPath;
  late final String opfDir;
  final Map<String, ManifestItem> manifest = {};

  /// `path` → item, exato e em minúsculas (o primeiro vence), para os alvos.
  final Map<String, ManifestItem> _byPath = {};
  final Map<String, ManifestItem> _byLowerPath = {};

  void _emit(
    EpubDiagnosticCode code, {
    required String message,
    String? href,
    Map<String, Object?> details = const {},
  }) => sink.emit(
    code,
    message: message,
    href: href,
    details: details,
    onStrict: (m) => EpubPackageException(m, href: href),
  );

  Future<EpubPublication> read() async {
    final rootfiles = parseContainerXml(await _readContainerXml());
    final (path, text) = await _readOpf(await _findOpf(rootfiles));
    opfPath = path;
    opfDir = dirnameOf(opfPath);
    final opf = parseOpf(text, opfPath: opfPath, sink: sink);

    for (final item in opf.items) {
      manifest[item.id] = await _resolveItem(item);
    }
    for (final item in manifest.values) {
      if (item.remote) continue;
      _byPath.putIfAbsent(item.path, () => item);
      _byLowerPath.putIfAbsent(item.path.toLowerCase(), () => item);
    }
    _checkFontObfuscation();

    final spine = _spine(opf);

    // NAV e NCX (spec §7).
    NavDocument? nav;
    String? navPath;
    final navItem = manifest.values
        .where((i) => i.properties.contains('nav'))
        .firstOrNull;
    if (navItem != null) {
      final text = await _readNavigation(navItem, isNav: true);
      if (text != null) {
        nav = parseNav(text);
        navPath = navItem.path;
        if (nav.toc.isEmpty) _navIgnored(navItem.path, 'no-toc');
        if (nav.truncated) _navIgnored(navItem.path, 'truncated');
      }
    }
    NcxDocument? ncx;
    String? ncxPath;
    if (nav == null || nav.toc.isEmpty || nav.pageList.isEmpty) {
      final ncxItem =
          manifest.values
              .where((i) => i.id == opf.spineToc && i.mediaType == ncxMediaType)
              .firstOrNull ??
          manifest.values.where((i) => i.mediaType == ncxMediaType).firstOrNull;
      if (ncxItem != null) {
        final text = await _readNavigation(ncxItem, isNav: false);
        if (text != null) {
          try {
            ncx = parseNcx(text);
            ncxPath = ncxItem.path;
            if (ncx.truncated) _navIgnored(ncxItem.path, 'truncated');
          } on XmlException catch (e) {
            _navIgnored(ncxItem.path, 'invalid', exception: e);
          }
        }
      }
    }

    // Precedência (spec §7.4) e alvos (§5.4).
    final List<NavPoint> toc;
    if (nav != null && nav.toc.isNotEmpty) {
      toc = _points(nav.toc, navPath!);
    } else if (ncx != null) {
      toc = _points(ncx.toc, ncxPath!);
    } else {
      toc = const [];
    }
    final List<NavPoint> pageList;
    if (nav != null && nav.pageList.isNotEmpty) {
      pageList = _points(nav.pageList, navPath!);
    } else if (ncx != null) {
      pageList = _points(ncx.pageList, ncxPath!);
    } else {
      pageList = const [];
    }
    final List<NavPoint> landmarks;
    if (nav != null && nav.landmarks.isNotEmpty) {
      landmarks = _points(nav.landmarks, navPath!);
    } else {
      landmarks = [
        for (final r in opf.guide)
          _point(
            NavEntry(title: r.title.trim(), href: r.href, type: r.type),
            opfPath,
          ),
      ];
    }

    return EpubPublication(
      opfPath: opfPath,
      version: opf.version,
      metadata: opf.metadata,
      manifest: manifest,
      spine: spine,
      toc: reconcileToc(toc, spine, sink: sink),
      landmarks: landmarks,
      pageList: pageList,
      coverPath: findCover(opf, manifest, sink: sink),
      navPath: navPath,
      ncxPath: ncxPath,
      direction: opf.direction,
      layout: opf.layout,
      uniqueIdentifiers: opf.uniqueIdentifiers,
      identifiers: opf.identifiers,
    );
  }

  // --- container.xml e OPF (spec §9.1) ---

  Future<String> _readContainerXml() async {
    final pending = await container.fetch(containerXmlPath);
    if (pending == null) {
      throw EpubContainerException(
        'container.xml ausente',
        href: containerXmlPath,
      );
    }
    if (pending.size > maxPackageDocumentSize) {
      throw EpubContainerException(
        'container.xml acima do teto de $maxPackageDocumentSize bytes',
        href: containerXmlPath,
      );
    }
    return decodeXml(_drain(pending), path: containerXmlPath, sink: sink);
  }

  /// O primeiro `full-path` que existe, com a tentativa dupla de §5.3.
  Future<String> _findOpf(List<String> rootfiles) async {
    for (final fullPath in rootfiles) {
      final normalized = normalizeHref('', fullPath);
      if (normalized == null) continue;
      for (final candidate in _candidates(normalized)) {
        if (await container.exists(candidate)) return candidate;
      }
    }
    throw EpubPackageException('OPF ausente', href: rootfiles.first);
  }

  /// Caminho real do OPF (o nome da entrada, que pode diferir em caixa do
  /// `full-path`) e o texto.
  Future<(String, String)> _readOpf(String located) async {
    final pending = await container.fetch(located);
    if (pending == null) {
      throw EpubPackageException('OPF ausente', href: located);
    }
    if (pending.size > maxPackageDocumentSize) {
      throw EpubPackageException(
        'OPF acima do teto de $maxPackageDocumentSize bytes',
        href: located,
      );
    }
    final bytes = _drain(pending);
    return (pending.path, decodeXml(bytes, path: pending.path, sink: sink));
  }

  static Uint8List _drain(PendingResource pending) {
    for (final _ in pending.decode()) {}
    return pending.bytes;
  }

  /// Forma decodificada (se houver e diferir) e depois a crua.
  static List<String> _candidates(String normalized) {
    final decoded = decodePath(normalized);
    return [if (decoded != null && decoded != normalized) decoded, normalized];
  }

  // --- Manifest (spec §5.3, §6.3) ---

  Future<ManifestItem> _resolveItem(OpfItem raw) async {
    ManifestItem make(
      String path, {
      bool missing = false,
      bool remote = false,
    }) => ManifestItem(
      id: raw.id,
      path: path,
      mediaType: _mediaType(raw.mediaType),
      properties: raw.properties,
      fallback: raw.fallback,
      missing: missing,
      remote: remote,
    );

    final href = raw.href;
    if (isRemoteHref(href)) return make(href, remote: true);
    final normalized = normalizeHref(opfDir, href);
    if (normalized == null) {
      _emit(
        EpubDiagnosticCode.resourceMissing,
        message: 'href recusado no item "${raw.id}": $href',
        details: {'id': raw.id, 'raw': href},
      );
      return make(href, missing: true);
    }
    final candidates = _candidates(normalized);
    final preferred = candidates.first;
    final isOpf = candidates.contains(opfPath);
    if (isOpf || _pointsToDirectory(href)) {
      _emit(
        EpubDiagnosticCode.resourceMissing,
        href: preferred,
        message: isOpf
            ? 'item "${raw.id}" aponta para o próprio OPF'
            : 'item "${raw.id}" aponta para um diretório',
        details: {'id': raw.id, 'reason': isOpf ? 'opf' : 'directory'},
      );
      return make(preferred, missing: true);
    }
    try {
      for (final candidate in candidates) {
        if (await container.exists(candidate)) return make(candidate);
      }
    } on EpubContainerException catch (e) {
      _emit(
        EpubDiagnosticCode.resourceUnreadable,
        href: preferred,
        message: 'exists falhou para o item "${raw.id}"',
        details: {'reason': 'exists', 'exception': '$e'},
      );
      return make(preferred, missing: true);
    }
    _emit(
      EpubDiagnosticCode.resourceMissing,
      href: preferred,
      message: 'item "${raw.id}" sem arquivo no contêiner',
      details: {'id': raw.id},
    );
    return make(preferred, missing: true);
  }

  /// O caminho do `href` (sem `?query` e `#fragmento`) termina em `/` ou `\`.
  static bool _pointsToDirectory(String href) {
    var path = href.trim();
    final hash = path.indexOf('#');
    if (hash >= 0) path = path.substring(0, hash);
    final query = path.indexOf('?');
    if (query >= 0) path = path.substring(0, query);
    return path.endsWith('/') || path.endsWith(r'\');
  }

  static String _mediaType(String raw) {
    final semicolon = raw.indexOf(';');
    return (semicolon < 0 ? raw : raw.substring(0, semicolon))
        .trim()
        .toLowerCase();
  }

  /// Spec §8.1: ofuscação declarada sobre um item que não é fonte é DRM
  /// disfarçado pela extensão.
  void _checkFontObfuscation() {
    for (final item in manifest.values) {
      if (item.missing || item.remote) continue;
      if (container.obfuscationOf(item.path) == null) continue;
      if (isFontMediaType(item.mediaType)) continue;
      throw EpubEncryptedException(
        'ofuscação de fonte declarada sobre ${item.path} '
        '(${item.mediaType}), que não é fonte',
        scheme: 'unknown:obfuscation-on-content',
        href: item.path,
      );
    }
  }

  // --- Spine (spec §6.3, §6.4) ---

  List<SpineItem> _spine(OpfDocument opf) {
    final spine = <SpineItem>[];
    final paths = <String>{};
    for (final ref in opf.itemrefs) {
      final item = manifest[ref.idref]!;
      if (!paths.add(item.path)) {
        _emit(
          EpubDiagnosticCode.spineItemDuplicate,
          href: opfPath,
          message: 'itemref "${ref.idref}" repete o caminho ${item.path}',
          details: {'idref': ref.idref},
        );
        continue;
      }
      spine.add(
        SpineItem(
          idref: ref.idref,
          item: item,
          content: _content(item),
          linear: ref.linear,
        ),
      );
    }
    if (spine.isEmpty) {
      throw EpubPackageException('spine vazio', href: opfPath);
    }
    return spine;
  }

  static bool _renderable(ManifestItem item) =>
      !item.missing && item.kind != SectionKind.unsupported;

  ManifestItem _content(ManifestItem item) {
    if (_renderable(item)) return item;
    final visited = <String>{item.id};
    var current = item;
    for (var step = 0; step < maxFallbackSteps; step++) {
      final next = current.fallback == null ? null : manifest[current.fallback];
      if (next == null || !visited.add(next.id)) break;
      if (_renderable(next)) return next;
      current = next;
    }
    if (item.kind == SectionKind.unsupported) {
      _emit(
        EpubDiagnosticCode.unsupportedMediaType,
        href: item.path,
        message: 'item do spine "${item.id}" com media-type ${item.mediaType}',
        details: {'mediaType': item.mediaType},
      );
    }
    return item;
  }

  // --- NAV e NCX (spec §7.5) ---

  void _navIgnored(String path, String reason, {Object? exception}) => _emit(
    EpubDiagnosticCode.navIgnored,
    href: path,
    message: 'navegação ignorada ($reason)',
    details: {'reason': reason, 'exception': ?exception?.toString()},
  );

  /// Texto do NAV ou do NCX, ou `null` com `navIgnored`. Só falha do próprio
  /// `fetch`/`decode()` vira `unreadable`; a exceção do [sink] em `strict`
  /// propaga.
  Future<String?> _readNavigation(
    ManifestItem item, {
    required bool isNav,
  }) async {
    if (item.missing || item.remote) {
      _navIgnored(item.path, 'missing');
      return null;
    }
    final Uint8List bytes;
    try {
      final pending = await container.fetch(item.path);
      if (pending == null) {
        _navIgnored(item.path, 'missing');
        return null;
      }
      if (pending.size > maxPackageDocumentSize) {
        _navIgnored(item.path, 'too-large');
        return null;
      }
      bytes = _drain(pending);
    } on EpubException catch (e) {
      if (_raisedBySink(e)) rethrow;
      _emit(
        EpubDiagnosticCode.resourceUnreadable,
        href: item.path,
        message: '${isNav ? 'NAV' : 'NCX'} ilegível',
        details: {'reason': 'unreadable', 'exception': '$e'},
      );
      _navIgnored(item.path, 'unreadable', exception: e);
      return null;
    }
    return decodeXml(bytes, path: item.path, sink: sink, htmlMeta: isNav);
  }

  /// A exceção veio do [sink] em `strict` (a mensagem é a de um warning
  /// registrado), e não do `fetch`/`decode()`.
  bool _raisedBySink(EpubException e) =>
      sink.strict &&
      sink.diagnostics.any(
        (d) =>
            d.severity == EpubSeverity.warning &&
            e.message == '${d.code.name}: ${d.message}',
      );

  // --- Alvos (spec §5.4) ---

  List<NavPoint> _points(List<NavEntry> entries, String documentPath) => [
    for (final e in entries) _point(e, documentPath),
  ];

  NavPoint _point(NavEntry entry, String documentPath) {
    final target = _target(entry.href, documentPath);
    return NavPoint(
      title: entry.title.isNotEmpty || target == null
          ? entry.title
          : basenameWithoutExtension(target.path),
      target: target,
      type: entry.type,
      children: _points(entry.children, documentPath),
    );
  }

  NavTarget? _target(String? href, String documentPath) {
    if (href == null) return null;
    final raw = href.trim();
    if (hasScheme(raw)) return null;
    final (_, fragment) = splitFragment(raw);
    if (raw.startsWith('#')) return NavTarget(documentPath, fragment);
    final normalized = normalizeHref(dirnameOf(documentPath), raw);
    if (normalized == null) return null;
    final decoded = decodePath(normalized);
    final item =
        (decoded == null ? null : _byPath[decoded]) ??
        _byPath[normalized] ??
        (decoded == null ? null : _byLowerPath[decoded.toLowerCase()]) ??
        _byLowerPath[normalized.toLowerCase()];
    return NavTarget(item?.path ?? decoded ?? normalized, fragment);
  }
}

/// `font/*`, `application/font-*`, `application/x-font-*`,
/// `application/vnd.ms-opentype` e `application/octet-stream` (genérico:
/// não declara conteúdo, e produtores antigos o usam para fontes).
bool isFontMediaType(String mediaType) =>
    mediaType.startsWith('font/') ||
    mediaType.startsWith('application/font-') ||
    mediaType.startsWith('application/x-font-') ||
    mediaType == 'application/vnd.ms-opentype' ||
    mediaType == 'application/octet-stream';
```

- [ ] **Passo 5: Rodar e ver passar**

Run: `flutter test test/publication/read_publication_test.dart`
Expected: `All tests passed!` (40 testes).

- [ ] **Passo 6: Formatar e analisar**

Run: `dart format --output=none --set-exit-if-changed lib test && flutter analyze`
Expected: nada a formatar e `No issues found!`.

- [ ] **Passo 7: Commit**

```bash
git add lib/src/publication/read_publication.dart test/publication/support test/publication/read_publication_test.dart
git commit -m "feat(publication): readPublication

Orquestrador da spec §9: container.xml e OPF com os fatais de §9.1,
itens do manifest com tentativa dupla, remote e exists que lança
(§5.3), ofuscação sobre conteúdo (§8.1), spine com fallback em cadeia
(§6.4), NAV/NCX com precedência e navIgnored (§7.4, §7.5), alvos
casados com o manifest (§5.4), reconciliação e capa. Em strict, a
exceção do sink propaga e o warning da Publicação lança
EpubPackageException."
```

---

### Tarefa 11: Exports públicos e a asserção de `details.delta`

Spec §9.2 (exports) e §1.3 (a pendência do teste de prefixo, que só conferia
`reason`). A asserção nova passa de primeira: é o que faltava no teste, não um
comportamento novo.

**Arquivos:**
- Modificar: `lib/galley.dart` (substituir inteiro)
- Modificar: `test/container/public_api_test.dart` (substituir inteiro)
- Modificar: `test/container/zip_container_test.dart` (uma asserção)

**Interfaces:**
- Consome: `EpubPackageException` (Tarefa 1), `EpubMetadata`, `EpubReadingDirection`, `EpubLayoutMode` (Tarefa 2).
- Produz: `package:galley/galley.dart` exporta, além do que já exportava, `EpubPackageException`, `EpubMetadata`, `EpubReadingDirection` e `EpubLayoutMode` — e nada mais da Publicação (`EpubPublication`, `readPublication` e o resto ficam internos até o sub-projeto 6).

- [ ] **Passo 1: Escrever o teste que falha**

Substituir `test/container/public_api_test.dart` inteiro por (o primeiro e o
último teste não mudam):

```dart
// Exports públicos do contêiner (spec §3) e a regra do import condicional.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/galley.dart';

void main() {
  test('lib/galley.dart exporta os tipos da spec §3', () async {
    final EpubByteSource memory = MemoryEpubByteSource(Uint8List(4));
    expect(await memory.length, 4);
    expect(FileEpubByteSource('x.epub').path, 'x.epub');
    const EpubResourceProvider? provider = null;
    expect(provider, isNull);
    final EpubException e = EpubContainerException('m', href: 'a');
    expect(e, isA<Exception>());
    expect(EpubEncryptedException('m', scheme: 'lcp').scheme, 'lcp');
    final d = EpubDiagnostic(
      code: EpubDiagnosticCode.zipCrcMismatch,
      severity: EpubSeverity.warning,
      message: 'm',
    );
    expect(d.code.name, 'zipCrcMismatch');
  });

  test('lib/galley.dart exporta os tipos da Publicação (spec §9.2)', () {
    final EpubException e = EpubPackageException('spine vazio', href: 'a.opf');
    expect(e.toString(), 'EpubPackageException(a.opf): spine vazio');
    final m = EpubMetadata(title: 'T', authors: ['A']);
    expect(m.authors, ['A']);
    expect(m.raw, isEmpty);
    expect(EpubReadingDirection.values, hasLength(3));
    expect(EpubLayoutMode.prePaginated.name, 'prePaginated');
  });

  test('dart:io só é importado por arquivos *_io.dart de lib/', () {
    final offenders = [
      for (final f in Directory(
        'lib',
      ).listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.dart') &&
            !f.path.endsWith('_io.dart') &&
            f.readAsStringSync().contains("import 'dart:io'"))
          f.path,
    ];
    expect(offenders, isEmpty, reason: 'quebraria a compilação para o web');
  });
}
```

- [ ] **Passo 2: Rodar e ver falhar**

Run: `flutter test test/container/public_api_test.dart`
Expected: FAIL na compilação, com `Method not found: 'EpubPackageException'` e `Undefined name 'EpubReadingDirection'`.

- [ ] **Passo 3: Exports**

Substituir `lib/galley.dart` inteiro por:

```dart
/// Motor de renderização de EPUB nativo para Flutter.
///
/// Fase 1, sub-projetos 1 (contêiner: fonte de bytes, provider de recursos,
/// exceções e diagnósticos) e 2 (publicação: metadados, direção e layout).
/// Ver `doc/` para a arquitetura.
library;

export 'src/container/byte_source.dart'
    show EpubByteSource, MemoryEpubByteSource;
export 'src/container/resource_provider.dart' show EpubResourceProvider;
export 'src/diagnostics/diagnostic.dart'
    show EpubDiagnostic, EpubDiagnosticCode, EpubSeverity;
export 'src/diagnostics/exceptions.dart'
    show
        EpubContainerException,
        EpubEncryptedException,
        EpubException,
        EpubPackageException;
export 'src/io/file_byte_source.dart' show FileEpubByteSource;
export 'src/publication/metadata.dart' show EpubMetadata;
export 'src/publication/model.dart' show EpubLayoutMode, EpubReadingDirection;
```

- [ ] **Passo 4: `details.delta` no teste do prefixo**

Em `test/container/zip_container_test.dart`, trocar:

```dart
      final ds = await diagnosticsOf(withPrefix(build(), 10));
      expect(ds.single.details['reason'], 'prefix');
```

por:

```dart
      final ds = await diagnosticsOf(withPrefix(build(), 10));
      expect(ds.single.details['reason'], 'prefix');
      expect(ds.single.details['delta'], 10);
```

- [ ] **Passo 5: Rodar e ver passar**

Run: `flutter test test/container/public_api_test.dart test/container/zip_container_test.dart`
Expected: `All tests passed!` (27 testes).

- [ ] **Passo 6: Formatar e analisar**

Run: `dart format --output=none --set-exit-if-changed lib test && flutter analyze`
Expected: nada a formatar e `No issues found!`.

- [ ] **Passo 7: Commit**

```bash
git add lib/galley.dart test/container/public_api_test.dart test/container/zip_container_test.dart
git commit -m "feat(publication): exports públicos e details.delta no teste de prefixo

EpubPackageException, EpubMetadata, EpubReadingDirection e
EpubLayoutMode em lib/galley.dart (spec §9.2); o teste do diagnóstico
de prefixo do ZIP volta a conferir details.delta (pendência do doc/14)."
```

---

### Tarefa 12: Corpus e fuzz

Spec §10.1 e o critério de sucesso de §1. Teste de aceitação sobre as Tarefas
1–10: fora os quatro `reais/` que a spec aponta, deve passar de primeira; se
falhar em outro caso, o defeito é da tarefa dona do comportamento (não afrouxe
o teste nem edite um `.expected` sintético). Decisão 21 (segunda passada).

**Arquivos:**
- Teste: `test/publication/publication_corpus_test.dart`
- Criar: `test/corpus/reais/alice-ilustrada-en/diagnostics.expected`
- Criar: `test/corpus/reais/candide-fr/diagnostics.expected`
- Criar: `test/corpus/reais/dom-casmurro-pt/diagnostics.expected`
- Criar: `test/corpus/reais/os-lusiadas-pt/diagnostics.expected`
- Teste: `test/publication/publication_fuzz_test.dart`

**Interfaces:**
- Consome: `readPublication` (Tarefa 10), `ZipContainer.open`, `ProviderContainer.open`, `FileEpubByteSource`, `MemoryEpubByteSource`; `epubZip` e `MapProvider` (apoio da Tarefa 10); a convenção do corpus (`test/corpus/README.md`).
- Produz: nada de código.

- [ ] **Passo 1: Escrever o teste de corpus**

Criar `test/publication/publication_corpus_test.dart`:

```dart
// A Publicação sobre os 65 EPUBs do corpus (spec da Publicação §10.1).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/container/zip/zip_container.dart';
import 'package:galley/src/diagnostics/diagnostic.dart';
import 'package:galley/src/diagnostics/exceptions.dart';
import 'package:galley/src/io/file_byte_source.dart';
import 'package:galley/src/publication/model.dart';
import 'package:galley/src/publication/read_publication.dart';

/// Códigos que a Publicação emite e que o corpus compara (spec §10.1).
const publicationCodes = {
  'resourceMissing',
  'spineItemUnresolved',
  'spineItemDuplicate',
  'unsupportedMediaType',
  'tocReconciled',
  'coverHeuristic',
  'navIgnored',
  'resourceUnreadable',
};

/// Dos acima, os `warning`: o caso roda sem `strict` e ganha a segunda
/// passada.
const publicationWarnings = {
  'resourceMissing',
  'spineItemUnresolved',
  'unsupportedMediaType',
  'resourceUnreadable',
};

/// Grupos que rodam com `strict: false` (doc/10 §5).
const relaxedGroups = {'patologia', 'faixa-b'};

List<String> _lines(File f) => f.existsSync()
    ? f.readAsLinesSync().where((l) => l.isNotEmpty).toList()
    : const [];

int _depth(List<NavPoint> points) {
  var max = 0;
  for (final p in points) {
    final d = 1 + _depth(p.children);
    if (d > max) max = d;
  }
  return max;
}

/// Asserções específicas de §10.1, por caso.
final Map<String, void Function(EpubPublication)> _specific = {
  'estrutura/opf-em-subpasta': (p) {
    expect(p.opfPath, 'OEBPS/content/content.opf');
    expect(p.manifest.values.where((i) => i.missing), isEmpty);
    expect(p.spine.map((s) => s.item.path), [
      'OEBPS/Text/cap01.xhtml',
      'OEBPS/Text/cap02.xhtml',
      'OEBPS/Text/cap03.xhtml',
    ]);
  },
  'regressoes/href-barra-invertida': (p) {
    final item = p.manifest['OEBPS_Text_cap01_xhtml']!;
    expect(item.path, 'OEBPS/Text/cap01.xhtml');
    expect(item.missing, isFalse);
  },
  'regressoes/href-url-encoded': (p) {
    final item = p.manifest['cap1']!;
    expect(item.path, 'OEBPS/Text/capítulo 1.xhtml');
    expect(item.missing, isFalse);
  },
  'estrutura/nav-ncx-divergentes': (p) {
    expect(p.toc.map((e) => e.title), [
      'Capítulo 1',
      'Capítulo 2',
      'Capítulo 3',
      'Capítulo 4',
    ]);
    expect(p.toc.where((e) => e.synthesized), isEmpty);
    expect(p.navPath, 'OEBPS/nav.xhtml');
  },
  'regressoes/ncx-incompleto-orfaos': (p) {
    expect(p.navPath, isNull);
    expect(p.ncxPath, 'OEBPS/toc.ncx');
    expect(p.toc.map((e) => e.target!.path), [
      for (var i = 1; i <= 6; i++) 'OEBPS/Text/cap0$i.xhtml',
    ]);
    expect(
      [
        for (var i = 0; i < p.toc.length; i++)
          if (p.toc[i].synthesized) i,
      ],
      [1, 3, 5],
    );
    expect(p.toc[1].title, 'cap02');
  },
  'estrutura/linear-no': (p) {
    final notas = p.toc.singleWhere((e) => e.title == 'Notas');
    expect(notas.synthesized, isFalse);
    expect(p.toc.where((e) => e.synthesized), isEmpty);
    final spineNotas = p.spine.singleWhere((s) => s.idref == 'notas');
    expect(spineNotas.linear, isFalse);
  },
  'estrutura/page-list-tres-fontes': (p) {
    expect(p.pageList.map((e) => e.title), [
      for (var i = 1; i <= 12; i++) '$i',
    ]);
    expect(p.pageList.map((e) => e.target!.fragment), [
      for (var i = 1; i <= 12; i++) 'pg$i',
    ]);
    expect(p.pageList.map((e) => e.target!.path).toSet(), {
      'OEBPS/Text/cap01.xhtml',
    });
    // Do NAV: com toc e page-list no NAV, o NCX nem é lido.
    expect(p.navPath, 'OEBPS/nav.xhtml');
    expect(p.ncxPath, isNull);
  },
  'estrutura/toc-6-niveis': (p) => expect(_depth(p.toc), 6),
  'estrutura/spine-800-itens': (p) => expect(p.spine, hasLength(800)),
  'regressoes/spine-so-imagem': (p) {
    expect(p.spine[1].kind, SectionKind.image);
    expect(p.spine[1].content.path, 'OEBPS/Images/pagina.png');
  },
  'regressoes/capa-ausente': (p) => expect(p.coverPath, isNull),
  'reais/moby-dick-en': (p) {
    expect(p.metadata.authors, ['Herman Melville']);
    expect(p.metadata.title, 'Moby Dick');
    expect(p.metadata.subtitle, 'Or, The Whale');
    expect(p.metadata.series, isNull);
  },
};

void main() {
  final root = Directory('test/corpus');
  final cases =
      root
          .listSync()
          .whereType<Directory>()
          .expand((group) => group.listSync().whereType<Directory>())
          .map(
            (d) => d.path.substring(root.path.length + 1).replaceAll(r'\', '/'),
          )
          .toList()
        ..sort();

  test('corpus tem os 65 casos e as asserções específicas existem', () {
    expect(cases, hasLength(65));
    expect(cases, containsAll(_specific.keys));
  });

  for (final name in cases) {
    final dir = '${root.path}/$name';
    final group = name.split('/').first;
    final exception = _lines(File('$dir/exception.expected')).firstOrNull;
    if (exception == 'EpubContainerException' ||
        exception == 'EpubEncryptedException') {
      continue; // falham no contêiner (spec §10.1)
    }
    final expectedAll = _lines(File('$dir/diagnostics.expected')).toSet();
    final expected = expectedAll.where(publicationCodes.contains).toSet();
    final hasWarning = expected.any(publicationWarnings.contains);
    final strict = !relaxedGroups.contains(group) && !hasWarning;

    test('$name (strict: $strict)', () async {
      final sink = DiagnosticSink(strict: strict);
      final container = await ZipContainer.open(
        FileEpubByteSource('$dir/book.epub'),
        sink: sink,
      );
      try {
        final read = readPublication(container, sink: sink);
        if (exception == 'EpubPackageException') {
          await expectLater(read, throwsA(isA<EpubPackageException>()));
          return;
        }
        final publication = await read;
        final emitted = sink.diagnostics.map((d) => d.code.name).toSet();
        expect(emitted.where(publicationCodes.contains).toSet(), expected);
        if (emitted.contains('encodingFallback')) {
          expect(expectedAll, contains('encodingFallback'));
        }
        for (final item in publication.manifest.values) {
          if (item.missing || item.remote) continue;
          expect(
            await container.exists(item.path),
            isTrue,
            reason: 'item ${item.id} (${item.path})',
          );
        }
        _specific[name]?.call(publication);
      } finally {
        await container.close();
      }
    });

    if (hasWarning) {
      test('$name (segunda passada, strict: true)', () async {
        final sink = DiagnosticSink(strict: true);
        final container = await ZipContainer.open(
          FileEpubByteSource('$dir/book.epub'),
          sink: sink,
        );
        try {
          await expectLater(
            readPublication(container, sink: sink),
            throwsA(
              isA<EpubPackageException>().having(
                (e) => publicationWarnings.any(
                  (c) => expected.contains(c) && e.message.startsWith('$c: '),
                ),
                'mensagem com o código',
                isTrue,
              ),
            ),
          );
        } finally {
          await container.close();
        }
      });
    }
  }
}
```

- [ ] **Passo 2: Rodar e ver falhar nos quatro `reais/`**

Run: `flutter test test/publication/publication_corpus_test.dart`
Expected: `Some tests failed.` com exatamente quatro falhas —
`reais/alice-ilustrada-en`, `reais/candide-fr`, `reais/dom-casmurro-pt` e
`reais/os-lusiadas-pt` —, cada uma com `Expected: Set:[]` e
`Actual: Set:['tocReconciled']` (o invólucro da capa e, na Alice, as páginas
de ilustração não estão no NAV).

- [ ] **Passo 3: Corrigir o corpus**

Criar `test/corpus/reais/alice-ilustrada-en/diagnostics.expected`:

```text
tocReconciled
```

Criar `test/corpus/reais/candide-fr/diagnostics.expected`:

```text
tocReconciled
```

Criar `test/corpus/reais/dom-casmurro-pt/diagnostics.expected`:

```text
tocReconciled
```

Criar `test/corpus/reais/os-lusiadas-pt/diagnostics.expected`:

```text
tocReconciled
```

- [ ] **Passo 4: Rodar e ver passar**

Run: `flutter test test/publication/publication_corpus_test.dart test/corpus/corpus_test.dart test/container/container_corpus_test.dart`
Expected: `All tests passed!` (332 testes: 65 da Publicação — a
contagem, 63 casos e a segunda passada de `regressoes/capa-ausente` —, 196 da
convenção do corpus e 71 do contêiner, que ignora `tocReconciled`).

- [ ] **Passo 5: Escrever o fuzz**

Criar `test/publication/publication_fuzz_test.dart`:

```dart
// Fuzz curto e determinístico da Publicação (spec §1, critério de sucesso):
// mutações de container.xml, OPF, NAV e NCX de EPUBs do corpus; nenhuma
// exceção fora de EpubException pode escapar de readPublication.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/container/byte_source.dart';
import 'package:galley/src/container/provider_container.dart';
import 'package:galley/src/container/zip/zip_container.dart';
import 'package:galley/src/diagnostics/diagnostic.dart';
import 'package:galley/src/diagnostics/exceptions.dart';
import 'package:galley/src/publication/read_publication.dart';

import 'support/epub_fixtures.dart';

const _books = [
  'estrutura/nav-ncx-divergentes',
  'estrutura/opf-em-subpasta',
  'regressoes/href-url-encoded',
  'estrutura/page-list-tres-fontes',
];

/// Trechos que costumam quebrar parsers e resolução de caminho.
const _tokens = [
  '<',
  '>',
  '"',
  "'",
  '&',
  '&#0;',
  '&#xD800;',
  '&#99999999;',
  '&nbsp;',
  '<![CDATA[',
  ']]>',
  '<!--',
  '\u0000',
  '﻿',
  '%',
  '%E9',
  '%2e%2e/',
  '%2F',
  '../../',
  r'\',
  '#',
  '?',
  'http:',
  'mailto:',
  '<ol><li>',
  '</li></ol>',
  '<nav epub:type="toc">',
  '<item id="x" href="" media-type=""/>',
  '<item id="c" href="a.pdf" media-type="application/pdf" fallback="c"/>',
  '<itemref idref="nope"/>',
  '<itemref idref="nav"/>',
  '<meta refines="#" property="role"/>',
  '<dc:date>+275760-09-14</dc:date>',
  '</manifest>',
  '</spine>',
  '</package>',
  '<package>',
  'full-path=""',
];

Future<Map<String, Uint8List>> _entries(String book) async {
  final container = await ZipContainer.open(
    MemoryEpubByteSource(File('test/corpus/$book/book.epub').readAsBytesSync()),
    sink: DiagnosticSink(),
  );
  final out = <String, Uint8List>{};
  for (final path in container.paths) {
    if (path == 'mimetype') continue; // epubZip grava o seu
    final r = (await container.fetch(path))!;
    for (final _ in r.decode()) {}
    out[path] = r.bytes;
  }
  await container.close();
  return out;
}

Uint8List _mutate(Uint8List bytes, Random random) {
  final b = bytes.toList();
  final at = b.isEmpty ? 0 : random.nextInt(b.length);
  switch (random.nextInt(5)) {
    case 0:
      for (var k = 0; k < 1 + random.nextInt(4) && b.isNotEmpty; k++) {
        b[random.nextInt(b.length)] = random.nextInt(256);
      }
    case 1:
      b.removeRange(at, min(b.length, at + 1 + random.nextInt(40)));
    case 2:
      final end = min(b.length, at + 1 + random.nextInt(200));
      b.insertAll(at, b.sublist(at, end));
    case 3:
      b.insertAll(at, utf8.encode(_tokens[random.nextInt(_tokens.length)]));
    default:
      b.removeRange(at, b.length);
  }
  return Uint8List.fromList(b);
}

bool _isPackageDocument(String path) =>
    path == 'META-INF/container.xml' ||
    path.endsWith('.opf') ||
    path.endsWith('.ncx') ||
    path.endsWith('nav.xhtml');

void main() {
  test('400 mutações: nenhuma exceção fora de EpubException', () async {
    final random = Random(20260926);
    final escaped = <String>[];
    var taxonomy = 0;
    var iteration = 0;
    for (final book in _books) {
      final original = await _entries(book);
      final targets = original.keys.where(_isPackageDocument).toList();
      for (var k = 0; k < 100; k++, iteration++) {
        final files = Map.of(original);
        for (var m = 0; m < 1 + random.nextInt(3); m++) {
          final target = targets[random.nextInt(targets.length)];
          files[target] = _mutate(files[target]!, random);
        }
        final sink = DiagnosticSink(strict: iteration % 3 == 0);
        try {
          final container = iteration.isEven
              ? await ZipContainer.open(
                  MemoryEpubByteSource(epubZip(files, compress: false)),
                  sink: sink,
                )
              : await ProviderContainer.open(MapProvider(files), sink: sink);
          try {
            await readPublication(container, sink: sink);
          } finally {
            await container.close();
          }
        } on EpubException {
          taxonomy++;
        } on Object catch (e, stack) {
          escaped.add(
            '$book #$k: ${e.runtimeType}: $e\n'
            '${stack.toString().split('\n').take(6).join('\n')}',
          );
        }
      }
    }
    // ignore: avoid_print
    print(
      'fuzz: $iteration casos, $taxonomy EpubException, ${escaped.length} fora',
    );
    expect(escaped, isEmpty, reason: escaped.join('\n\n'));
    expect(iteration, 400);
  });
}
```

- [ ] **Passo 6: Rodar o fuzz**

Run: `flutter test test/publication/publication_fuzz_test.dart`
Expected: `All tests passed!` (1 teste) e a linha
`fuzz: 400 casos, 242 EpubException, 0 fora`. A semente é fixa: outra
contagem de `EpubException` significa que o comportamento de algum parser
mudou — confira antes de seguir. Um escape aparece com o tipo, o caso e as
seis primeiras linhas da pilha.

- [ ] **Passo 7: Suíte inteira, formatação e analyze**

Run: `dart format --output=none --set-exit-if-changed lib test tool example/lib example/integration_test && flutter analyze && flutter test`
Expected: nada a formatar, `No issues found!` e `All tests passed!` (846 testes e 1 pulado, o de `perf`).

- [ ] **Passo 8: Commit**

```bash
git add test/publication/publication_corpus_test.dart test/publication/publication_fuzz_test.dart test/corpus/reais
git commit -m "test: a Publicação sobre o corpus e fuzz de documentos do pacote

Os 65 EPUBs (spec §10.1): conjunto dos códigos da Publicação igual ao
diagnostics.expected, encodingFallback só se esperado, todo item não
missing existe no contêiner, strict fora de patologia/faixa-b com
segunda passada nos casos com warning, e as asserções específicas.
Os quatro reais/ ganham tocReconciled. Fuzz determinístico de 400
mutações: nenhuma exceção fora de EpubException."
```

---

### Tarefa 13: Caso de desempenho `publication.read.800`

Spec §11. `readPublication` sobre um `ZipContainer` de
`spine-800-itens` aberto uma vez no `setUp` (o harness não tem teardown; o
contêiner é reusado entre amostras, como o `zip.fetch.inflate.1mb`). Decisão
22: `innerIterations: 1`.

**Arquivos:**
- Modificar: `test/perf/perf_test.dart` (substituir inteiro)

**Interfaces:**
- Consome: `PerfCase({required String id, void Function()? run, Future<void> Function()? runAsync, Future<void> Function()? setUp, int innerIterations = 1})`, `measureCase`, `writeResultIfAny` (`test/perf/support/perf_harness.dart`); `readPublication` (Tarefa 10); `ZipContainer`, `MemoryEpubByteSource`, `DiagnosticSink`.
- Produz: o caso `publication.read.800` no `build/perf/result.json`.

- [ ] **Passo 1: Acrescentar o caso**

Substituir `test/perf/perf_test.dart` inteiro por (os sete casos anteriores
não mudam):

```dart
// Casos de desempenho: primitivas da Fase 0 (spec do harness §2.4), o
// contêiner (spec do contêiner §10) e a Publicação (spec da Publicação §11)
// da Fase 1. Rodar com:
//
//   flutter test --tags perf --run-skipped test/perf
//
// e comparar com `dart run tool/perf/compare.dart`.
// ignore_for_file: avoid_relative_lib_imports — tool/ não é pacote; importar por caminho é intencional.
@Tags(['perf'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/container/byte_source.dart';
import 'package:galley/src/container/container.dart';
import 'package:galley/src/container/font_obfuscation.dart';
import 'package:galley/src/container/zip/zip_container.dart';
import 'package:galley/src/diagnostics/diagnostic.dart';
import 'package:galley/src/publication/read_publication.dart';
import 'package:html/parser.dart' as html;

import '../../tool/corpus/lib/png.dart';
import '../../tool/corpus/lib/zip_writer.dart';
import '../../tool/perf/lib/perf_report.dart';
import 'support/perf_harness.dart';
import 'support/perf_inputs.dart';

int _sink = 0;

List<PerfCase> _phase0Cases() {
  late String xhtml;
  late List<String> paragraphs;
  late Uint8List deflated;
  late Uint8List pngBytes;
  return [
    PerfCase(
      id: 'html.parse.500kb',
      setUp: () async => xhtml = xhtmlOfLength(500 * 1024),
      run: () => _sink += html.parse(xhtml).body!.nodes.length,
    ),
    PerfCase(
      id: 'paragraph.shape.1000',
      setUp: () async => paragraphs = paragraphsOfWords(1000, 40),
      run: () {
        for (final text in paragraphs) {
          final builder =
              ui.ParagraphBuilder(
                  ui.ParagraphStyle(fontFamily: 'FlutterTest', fontSize: 16),
                )
                ..pushStyle(
                  ui.TextStyle(fontFamily: 'FlutterTest', fontSize: 16),
                )
                ..addText(text);
          final p = builder.build()
            ..layout(const ui.ParagraphConstraints(width: 320));
          _sink += p.height.toInt();
          p.dispose();
        }
      },
    ),
    PerfCase(
      id: 'zlib.inflate.1mb',
      setUp: () async => deflated = deflateRaw(proseBytes(1024 * 1024)),
      run: () => _sink += ZLibDecoder(raw: true).convert(deflated).length,
      innerIterations: 6, // ≈ 5 ms por amostra, como a calibração
    ),
    PerfCase(
      id: 'image.decode.target',
      setUp: () async => pngBytes = png(1200, 1600, seed: 5),
      runAsync: () async {
        final codec = await ui.instantiateImageCodec(
          pngBytes,
          targetWidth: 300,
        );
        final frame = await codec.getNextFrame();
        _sink += frame.image.width;
        frame.image.dispose();
        codec.dispose();
      },
    ),
  ];
}

List<PerfCase> _containerCases() {
  late Uint8List spine800;
  late ZipContainer inflateContainer;
  late Uint8List font;
  return [
    PerfCase(
      id: 'zip.open.800',
      setUp: () async =>
          spine800 = File('test/corpus/estrutura/spine-800-itens/book.epub')
              .readAsBytesSync(),
      runAsync: () async {
        final c = await ZipContainer.open(
          MemoryEpubByteSource(spine800),
          sink: DiagnosticSink(),
        );
        _sink += c.paths.length;
        await c.close();
      },
      innerIterations: 10, // ≈ 5 ms por amostra
    ),
    PerfCase(
      id: 'zip.fetch.inflate.1mb',
      setUp: () async {
        // Contêiner reusado entre amostras de propósito (o harness não tem teardown).
        final zip =
            (ZipWriter()
                  ..add(
                    'mimetype',
                    ascii.encode('application/epub+zip'),
                    compress: false,
                  )
                  ..add('OEBPS/Text/grande.xhtml', proseBytes(1024 * 1024)))
                .build();
        inflateContainer = await ZipContainer.open(
          MemoryEpubByteSource(zip),
          sink: DiagnosticSink(),
        );
      },
      runAsync: () async {
        final r = (await inflateContainer.fetch('OEBPS/Text/grande.xhtml'))!;
        for (final _ in r.decode()) {}
        _sink += r.bytes.length;
      },
    ),
    PerfCase(
      id: 'font.deobfuscate.idpf',
      setUp: () async => font = proseBytes(64 * 1024),
      run: () => _sink += deobfuscateFont(
        font,
        FontObfuscation.idpf,
        uniqueIdentifiers: const [
          'urn:uuid:b7e2f1a0-4c3d-4e5f-8a9b-0c1d2e3f4a5b',
        ],
        identifiers: const [],
      )!.length,
      innerIterations: 400, // ≈ 5 ms por amostra
    ),
  ];
}

List<PerfCase> _publicationCases() {
  late ZipContainer spine800;
  return [
    PerfCase(
      id: 'publication.read.800',
      // Contêiner aberto uma vez e reusado: o caso mede só a Publicação.
      setUp: () async => spine800 = await ZipContainer.open(
        MemoryEpubByteSource(
          File('test/corpus/estrutura/spine-800-itens/book.epub')
              .readAsBytesSync(),
        ),
        sink: DiagnosticSink(),
      ),
      runAsync: () async {
        final p = await readPublication(spine800, sink: DiagnosticSink());
        _sink += p.spine.length;
      },
      // Uma leitura já passa de 5 ms (≈ 27 ms no i5-11400H).
    ),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final results = <String, PerfCaseResult>{};

  for (final c in [
    ..._phase0Cases(),
    ..._containerCases(),
    ..._publicationCases(),
  ]) {
    test(c.id, () async {
      final r = await measureCase(c);
      results[c.id] = r;
      print(
        '[perf] ${c.id}: razão ${r.ratio.toStringAsFixed(3)}, '
        'caso ${r.medianUs.round()} µs, calibração ${r.calibrationUs.round()} µs',
      );
    }, timeout: const Timeout(Duration(minutes: 5)));
  }

  tearDownAll(() async {
    if (await writeResultIfAny(results)) {
      print(
        '[perf] $defaultResultPath escrito (${results.length} casos, sink $_sink)',
      );
    }
  });
}
```

- [ ] **Passo 2: Rodar o harness**

Run: `flutter test --tags perf --run-skipped --concurrency=1 test/perf/perf_test.dart`
Expected: `All tests passed!` e oito linhas `[perf] …`; a nova,
`publication.read.800`, com caso entre ~15 000 e ~50 000 µs (27 793 µs no
i5-11400H). Acima de 100 000 µs, algo ficou quadrático: pare e investigue
antes de seguir.

- [ ] **Passo 3: Comparar**

Run: `dart run tool/perf/compare.dart`
Expected: `publication.read.800` como `novo, sem baseline` e
`**Resultado: passou.**` (numa CPU sem baseline, todos os casos aparecem
assim).

- [ ] **Passo 4: Suíte normal pula o perf**

Run: `flutter test test/perf`
Expected: `All tests passed!` com os casos `perf` pulados.

- [ ] **Passo 5: Formatar e analisar**

Run: `dart format --output=none --set-exit-if-changed lib test && flutter analyze`
Expected: nada a formatar e `No issues found!`.

- [ ] **Passo 6: Commit**

```bash
git add test/perf/perf_test.dart
git commit -m "test: caso de desempenho publication.read.800

readPublication sobre o ZipContainer de spine-800-itens já aberto
(spec §11), uma leitura por amostra (~27 ms no desktop). Sem baseline
até o perf-baseline ser disparado depois do merge."
```

---

### Tarefa 14: Documentação

Spec §12. Cada troca abaixo é de um trecho que aparece **uma vez** no arquivo;
se não achar o trecho exato, pare e confira com `grep -n`.

**Arquivos:**
- Modificar: `doc/03-camada-a-ir.md` (§3, §3.1 e §3.2)
- Modificar: `doc/06-locator-navegacao.md` (§3, §5 e §5.1)
- Modificar: `doc/09-erros-diagnosticos.md` (§2, §3 e §4)
- Modificar: `doc/10-testes.md` (§5)
- Modificar: `doc/11-empacotamento-versionamento.md` (§4)
- Modificar: `doc/14-pendencias.md` (Infraestrutura, Fase 1 e Concluídas)
- Modificar: `doc/specs/2026-09-26-publication-design.md` (estado)
- Modificar: `CHANGELOG.md`

**Interfaces:** nenhuma.

- [ ] **Passo 1: `doc/03` §3 (o modelo)**

Em `doc/03-camada-a-ir.md`, trocar:

```dart
final class EpubPublication {
  final EpubMetadata metadata;
  final List<SpineItem> readingOrder;
  final Map<String, ManifestItem> manifest;
  final List<EpubTocEntry> toc;
  final List<EpubPageMark> pageList;      // do NAV epub:type="page-list"
  final List<EpubTocEntry> landmarks;     // do NAV epub:type="landmarks"
  final String? coverHref;                // ver 06 §5.1
  final EpubReadingDirection direction;   // page-progression-direction
  final EpubLayoutMode layout;            // reflowable | prePaginated
  final int totalChars;                   // soma das seções, para progresso
}
```

por:

```dart
final class EpubPublication {             // interna: lib/src/publication/model.dart
  final String opfPath, version;
  final EpubMetadata metadata;            // pública (06 §5)
  final Map<String, ManifestItem> manifest; // por id, caminho resolvido, missing/remote
  final List<SpineItem> spine;            // doc.readingOrder no sub-projeto 6
  final List<NavPoint> toc;               // reconciliado (§3.1); EpubTocEntry no 6
  final List<NavPoint> pageList;          // NAV, senão NCX (06 §3); EpubPageMark no 6
  final List<NavPoint> landmarks;         // NAV, senão guide do OPF
  final String? coverPath;                // passos de pacote de 06 §5.1; coverHref no 6
  final String? navPath, ncxPath;         // documentos lidos (chave do livro, 08 §4.1)
  final EpubReadingDirection direction;   // page-progression-direction
  final EpubLayoutMode layout;            // reflowable | prePaginated
  final List<String> uniqueIdentifiers, identifiers; // chaves IDPF e Adobe (09 §4)
}
```

- [ ] **Passo 2: `doc/03` §3 (de onde vem cada parte)**

Em `doc/03-camada-a-ir.md`, trocar:

```markdown
### 3.1 Reconciliação NCX × spine
```

por:

```markdown
Implementada em `lib/src/publication/` (Fase 1, sub-projeto 2;
[spec](specs/2026-09-26-publication-design.md)): só o nível do pacote
(`container.xml`, OPF, NAV e NCX), sem abrir seção. Os tipos públicos com
`Locator` (`EpubTocEntry`, `EpubPageMark`) são montados pelo `EpubDocument`
no sub-projeto 6 a partir de `NavPoint`; `totalChars` (soma das seções, para
progresso) vem da IR, no sub-projeto 4.

### 3.1 Reconciliação NCX × spine
```

- [ ] **Passo 3: `doc/03` §3.1 (posição dos órfãos)**

Em `doc/03-camada-a-ir.md`, trocar:

```markdown
2. Inclui itens órfãos do spine como entradas de nível raiz, na posição correta
   da ordem de leitura, com título derivado do primeiro heading da seção ou, na
   falta dele, do nome do arquivo
```

por:

```markdown
2. Inclui itens órfãos do spine (com `linear` verdadeiro e sem entrada, em
   nenhum nível, que aponte para eles) como entradas de nível raiz marcadas
   `synthesized`, logo depois da última entrada raiz, na ordem do TOC, cujo
   menor índice do spine (dela e dos descendentes) é anterior ao do órfão; sem
   nenhuma, no início; órfãos no mesmo ponto ficam na ordem do spine. O título
   é o nome do arquivo sem extensão; o primeiro heading da seção fica como
   gancho para a IR (sub-projeto 4). Emite `tocReconciled` uma vez
```

- [ ] **Passo 4: `doc/03` §3.2 (itens problemáticos)**

Em `doc/03-camada-a-ir.md`, trocar:

```markdown
| `href` URL-encoded | Decodificado; tentativa dupla (cru e decodificado) |
| `href` relativo ao OPF em subpasta | Resolvido contra o diretório do OPF, depois normalizado (`..` colapsado) |
| Diferença de caixa entre manifest e ZIP | Segunda tentativa case-insensitive, com diagnóstico `pathCaseMismatch` |
| Item do manifest sem arquivo no ZIP | Seção de placeholder + `EpubDiagnostic.resourceMissing` |
| Item só-imagem no spine (`image/*` no media-type) | Seção com um único `Block(kind: object)` |
| Item com media-type não renderizável (PDF, áudio) | Seção de placeholder com o nome e o tipo, diagnóstico `unsupportedMediaType` |
| Spine vazio | `EpubPackageException` (fatal) |
| `idref` do spine sem item no manifest | Item ignorado, diagnóstico `spineItemUnresolved` |
```

por:

```markdown
| `href` URL-encoded | Decodificado segmento a segmento; tentativa dupla (decodificado, depois cru); `%2e%2e` que sairia da raiz e `%2F` ficam crus |
| `href` relativo ao OPF em subpasta | Resolvido contra o diretório do OPF, depois normalizado (`..` colapsado); `..` além da raiz recusa o `href` |
| `href` recusado (esquema que não é `http:`/`https:`, fora da raiz, vazio) | Item `missing`, `resourceMissing` com `href: null` e `details: {id, raw}` |
| `href` `http:`/`https:` | Item `remote`, sem diagnóstico |
| Diferença de caixa entre manifest e ZIP | Segunda tentativa case-insensitive, com diagnóstico `pathCaseMismatch` |
| Item do manifest sem arquivo no ZIP | Item `missing` com `resourceMissing` (`href` = caminho); seção de placeholder na IR |
| Item só-imagem no spine (`image/*` no media-type) | Seção com um único `Block(kind: object)` |
| Item com media-type não renderizável (PDF, áudio) | Segue a cadeia de `fallback` (até 16 passos, com detecção de ciclo) até um XHTML ou imagem existente; sem ela, seção de placeholder com o nome e o tipo e `unsupportedMediaType` (`href` = caminho) |
| Spine vazio | `EpubPackageException` (fatal) |
| `idref` do spine sem item no manifest | Item ignorado, diagnóstico `spineItemUnresolved` (`href` = OPF) |
| `idref` ou caminho repetido no spine | Vale o primeiro, diagnóstico `spineItemDuplicate` (`href` = OPF) |
```

- [ ] **Passo 5: `doc/06` §3 (fontes do `page-list`)**

Em `doc/06-locator-navegacao.md`, trocar:

```markdown
NAV correspondente. Os três são fontes; a prioridade é NAV, NCX, corpo.
```

por:

```markdown
NAV correspondente. Os três são fontes; a prioridade é NAV, NCX, corpo. NAV e
NCX são lidos pela Publicação (sub-projeto 2); o corpo, pela IR (sub-projeto
4).
```

- [ ] **Passo 6: `doc/06` §5 (`raw`)**

Em `doc/06-locator-navegacao.md`, trocar:

```dart
  final Map<String, List<String>> raw;   // todo <dc:*> e <meta> não mapeado, por nome
```

por:

```dart
  final Map<String, List<String>> raw;   // só o que não virou campo, por nome local
```

- [ ] **Passo 7: `doc/06` §5 (regras de preenchimento)**

Em `doc/06-locator-navegacao.md`, trocar:

```markdown
`schema:`, `rendition:`), e o app sempre acaba precisando de um campo que não
previmos.
```

por:

```markdown
`schema:`, `rendition:`), e o app sempre acaba precisando de um campo que não
previmos.

Regras de preenchimento ([spec da Publicação](specs/2026-09-26-publication-design.md)
§6.2): o título é o `dc:title` com `title-type` `main`, senão o primeiro que
não é `subtitle` nem `expanded`; o subtítulo, o primeiro `subtitle`; um
`dc:creator` é autor sem papel ou com algum papel `aut` (`opf:role` ou
`<meta refines property="role">`), senão colaborador; a série vem de
`belongs-to-collection` com `collection-type` `series` (ou sem tipo), senão de
`calibre:series`; `published` é o `dc:date` de `opf:event="publication"` (ou o
primeiro que não é de modificação) e `modified` o `dcterms:modified`, com
datas parciais (`YYYY`, `YYYY-MM`) no primeiro dia. `raw` guarda só o que não
virou campo, pelo nome local do `dc:*` ou pelo `property`/`name` do `meta`.
```

- [ ] **Passo 8: `doc/06` §5.1 (passos feitos e pendentes)**

Em `doc/06-locator-navegacao.md`, trocar:

```markdown
Cada passo abaixo do 2 emite `coverHeuristic` como diagnóstico `info`.
```

por:

```markdown
Cada passo abaixo do 2 emite `coverHeuristic` como diagnóstico `info`. Os
passos 1, 2 e 4 são da Publicação (sub-projeto 2), que pula itens `missing` e
`remote`; os passos 3 e 5 olham a seção e ficam para o sub-projeto 6.
```

- [ ] **Passo 9: `doc/09` §2 (`EpubPackageException`)**

Em `doc/09-erros-diagnosticos.md`, trocar:

```markdown
| `EpubPackageException` | OPF malformado, spine vazio | **Sim**, em `open` | — |
```

por:

```markdown
| `EpubPackageException` | OPF ausente (nenhum `rootfile` existe), acima de 4 MiB, com XML inválido, raiz que não é `package` ou sem `manifest`/`spine`; spine vazio depois de descartar `idref` sem item; em `strict`, também todo warning da Publicação, com o nome do código na mensagem ([spec da Publicação](specs/2026-09-26-publication-design.md) §9.1) | **Sim**, em `open` | — |
```

- [ ] **Passo 10: `doc/09` §3 (códigos novos)**

Em `doc/09-erros-diagnosticos.md`, trocar:

```markdown
| `coverHeuristic` | info | Capa encontrada por heurística, qual |
```

por:

```markdown
| `coverHeuristic` | info | Capa encontrada por heurística, qual |
| `navIgnored` | info | NAV ou NCX não usado; `details.reason`: `missing`, `too-large`, `unreadable`, `invalid`, `no-toc` ou `truncated` |
| `spineItemDuplicate` | info | `idref` (ou caminho) repetido no spine; vale o primeiro |
```

- [ ] **Passo 11: `doc/09` §4 (ofuscação pelo `media-type`)**

Em `doc/09-erros-diagnosticos.md`, trocar:

```markdown
qualquer namespace; a busca do namespace ADEPT dentro do `KeyInfo` não desce
para `EncryptedData` aninhados.
```

por:

```markdown
qualquer namespace; a busca do namespace ADEPT dentro do `KeyInfo` não desce
para `EncryptedData` aninhados.

A checagem do contêiner é pela extensão; a Publicação confere, pelo
`media-type` do manifest, que a ofuscação declarada é mesmo sobre fonte
(`font/*`, `application/font-*`, `application/x-font-*`,
`application/vnd.ms-opentype` ou o genérico `application/octet-stream`): um
item de conteúdo com extensão de fonte e ofuscação declarada é
`EpubEncryptedException` com `unknown:obfuscation-on-content`
([spec da Publicação](specs/2026-09-26-publication-design.md) §8.1).
```

- [ ] **Passo 12: `doc/10` §5 (strict com warning esperado)**

Em `doc/10-testes.md`, trocar:

```markdown
Isso impede que uma regressão de parse se disfarce de "degradação aceitável".
```

por:

```markdown
Isso impede que uma regressão de parse se disfarce de "degradação aceitável".

Um caso cujo `diagnostics.expected` lista um código `warning` de uma camada
(na Publicação: `resourceMissing`, `spineItemUnresolved`,
`unsupportedMediaType`, `resourceUnreadable`) roda sem `strict`, porque o
warning é o esperado, e ganha uma segunda passada em `strict` que exige a
exceção com o nome do código na mensagem
([spec da Publicação](specs/2026-09-26-publication-design.md) §10.1).
```

- [ ] **Passo 13: `doc/11` §4 (`lib/src/publication/`)**

Em `doc/11-empacotamento-versionamento.md`, trocar:

```markdown
      container/                  # byte source, zip, inflate, opf, nav, ncx, encryption
```

por:

```markdown
      container/                  # byte source, zip, inflate, encryption, fontes
      publication/                # container.xml, OPF, NAV, NCX, href, reconciliação, capa
```

- [ ] **Passo 14: `doc/11` §4 (`test/publication/`)**

Em `doc/11-empacotamento-versionamento.md`, trocar:

```markdown
    diagnostics/                  # exceções e DiagnosticSink
```

por:

```markdown
    diagnostics/                  # exceções e DiagnosticSink
    publication/                  # parsers, orquestrador, Publicação sobre o corpus, fuzz
```

- [ ] **Passo 15: `doc/14` (pendências do sub-projeto 1 endereçadas)**

Em `doc/14-pendencias.md`, trocar:

```markdown
| Contêiner em `strict`: `rights.xml` (ou `encryption.xml` com KeyInfo LCP) com CRC errado sai como `EpubContainerException(zipCrcMismatch)` em vez de `EpubEncryptedException`, contra a frase de [09](09-erros-diagnosticos.md) §4. Só afeta `strict` (testes). Ler os metadados com sink não estrito e reemitir o diagnóstico depois da checagem de DRM | Revisão final do contêiner (2026-09-26) | Sub-projeto 2 |
| Teste do diagnóstico de prefixo do ZIP confere só `reason`, não `details.delta` (a asserção saiu com a mudança do diagnóstico para o `ZipContainer`) | Revisão final do contêiner (2026-09-26) | Sub-projeto 2 |
```

por:

```markdown
| Contêiner em `strict`: `rights.xml` (ou `encryption.xml` com KeyInfo LCP) com CRC errado sai como `EpubContainerException(zipCrcMismatch)` em vez de `EpubEncryptedException`, contra a frase de [09](09-erros-diagnosticos.md) §4. Só afeta `strict` (testes). Ler os metadados com sink não estrito e reemitir o diagnóstico depois da checagem de DRM | Revisão final do contêiner (2026-09-26) | Sub-projeto 6, junto da revisão do `strict` do documento ([spec da Publicação](specs/2026-09-26-publication-design.md) §1.3) |
```

- [ ] **Passo 16: `doc/14` (`CipherReference` relativo)**

Em `doc/14-pendencias.md`, trocar:

```markdown
| Implementação do contêiner (2026-09-26) | Sub-projeto 2 (Publicação, que conhece o diretório do OPF) |
```

por:

```markdown
| Implementação do contêiner (2026-09-26) | Sub-projeto 6, que cruza fontes, manifest e `encryption.xml` ao carregar fontes ([spec da Publicação](specs/2026-09-26-publication-design.md) §1.3) |
```

- [ ] **Passo 17: `doc/14` (ganchos da Publicação)**

Em `doc/14-pendencias.md`, trocar:

```markdown
| O fallback do EOCD64 assume 56 bytes colados ao locator (`eocdPos - locatorSize - eocd64Size`); prefixo com um extensible data sector entre o central directory e o locator faria essa busca falhar e o arquivo virar fatal | Revisão final do contêiner (2026-09-26) | Se aparecer um EPUB real assim |
```

por:

```markdown
| O fallback do EOCD64 assume 56 bytes colados ao locator (`eocdPos - locatorSize - eocd64Size`); prefixo com um extensible data sector entre o central directory e o locator faria essa busca falhar e o arquivo virar fatal | Revisão final do contêiner (2026-09-26) | Se aparecer um EPUB real assim |
| Título de entrada órfã do TOC pelo primeiro heading da seção (hoje: nome do arquivo sem extensão) | [Spec da Publicação](specs/2026-09-26-publication-design.md) §1.1, §7.6 | Sub-projeto 4 (IR de seção) |
| Capa pelos passos 3 e 5 de [06](06-locator-navegacao.md) §5.1 (landmark ou `guide` de capa cuja seção tem uma imagem só; primeira imagem da primeira seção) | [Spec da Publicação](specs/2026-09-26-publication-design.md) §1.1, §8.2 | Sub-projeto 6 |
| `page-list` a partir de `epub:type="pagebreak"` no corpo, quando NAV e NCX não têm | [Spec da Publicação](specs/2026-09-26-publication-design.md) §1.1 | Sub-projeto 4 |
| `totalChars` da publicação (soma das seções, para progresso) | [Spec da Publicação](specs/2026-09-26-publication-design.md) §1.1 | Sub-projeto 4 |
| Resolução de alvo de TOC, landmark e `page-list` (`caminho#fragmento`) para offset, e `EpubTocEntry`/`EpubPageMark` com `Locator` | [Spec da Publicação](specs/2026-09-26-publication-design.md) §1.1, §3 | Sub-projeto 6 |
| Entradas sintetizadas com nome de arquivo em livros com páginas de imagem (a Alice do corpus ganha 28, como `7491619335329807298_i001.jpg.id-1492325526376266811.wrap-0.html`); a UI pode escondê-las por `synthesized` | Implementação da Publicação (2026-09-26) | Sub-projeto 6, ao montar `doc.toc` |
| Regenerar os baselines por CPU com `publication.read.800` (disparar o `perf-baseline`); até lá aparece como "novo, sem baseline" | [Spec da Publicação](specs/2026-09-26-publication-design.md) §11 | Logo depois do merge da PR da Publicação |
```

- [ ] **Passo 18: `doc/14` (concluída)**

Em `doc/14-pendencias.md`, trocar:

```markdown
| Regenerar os baselines por CPU com os casos do contêiner: EPYC 7763 (mediana de 5 VMs), EPYC 9V74 (novo) e Xeon 6973P-C; os casos antigos ficaram entre −4% e +0,5% dos baselines anteriores, sem regressão | 2026-09-26 | 34beb62 |
```

por:

```markdown
| Regenerar os baselines por CPU com os casos do contêiner: EPYC 7763 (mediana de 5 VMs), EPYC 9V74 (novo) e Xeon 6973P-C; os casos antigos ficaram entre −4% e +0,5% dos baselines anteriores, sem regressão | 2026-09-26 | 34beb62 |
| Teste do diagnóstico de prefixo do ZIP voltou a conferir `details.delta`, além de `reason` | 2026-09-26 | @HASH_DELTA@ |
```

- [ ] **Passo 19: Preencher o commit da pendência concluída**

```bash
h=$(git log --format=%h -1 -- test/container/zip_container_test.dart)
sed -i "s/@HASH_DELTA@/$h/" doc/14-pendencias.md
grep -n "details.delta" doc/14-pendencias.md
```

Expected: uma linha em **Concluídas** com o hash do commit da Tarefa 11.

- [ ] **Passo 20: Estado da spec**

Em `doc/specs/2026-09-26-publication-design.md`, trocar:

```markdown
**Data:** 2026-09-26. **Estado:** aprovada em conversa (desenho em quatro seções),
com uma revisão independente cujos achados estão incorporados.
```

por:

```markdown
**Data:** 2026-09-26. **Estado:** aprovada e implementada (plano em
`doc/plans/2026-09-26-publication.md`; desenho em quatro seções, com uma
revisão independente cujos achados estão incorporados).
```

- [ ] **Passo 21: `CHANGELOG.md`**

Em `CHANGELOG.md`, trocar:

```markdown
## Não lançado

```

por:

```markdown
## Não lançado

- Fase 1, sub-projeto 2 (publicação): `container.xml`, OPF (metadados com
  `refines`, série, datas parciais e `raw`), NAV e NCX com limites contra
  arquivo hostil, normalização de `href` com tentativa dupla de `%xx`,
  `fallback` do spine, TOC reconciliado com o spine, landmarks, `page-list`,
  capa, direção e layout; `EpubPackageException`, `EpubMetadata`,
  `EpubReadingDirection` e `EpubLayoutMode` públicos.

```

- [ ] **Passo 22: Conferir**

Run: `flutter test test/corpus/corpus_test.dart && grep -c 'navIgnored' doc/09-erros-diagnosticos.md && grep -n 'lib/src/publication\|publication/ ' doc/11-empacotamento-versionamento.md doc/03-camada-a-ir.md && grep -n '@HASH_DELTA@\|| Sub-projeto 2 |' doc/14-pendencias.md; echo "restos: $?"`
Expected: `All tests passed!`, contagem 1 no doc/09, as linhas de
`publication/` nos dois documentos e `restos: 1`.

- [ ] **Passo 23: Commit**

```bash
git add doc CHANGELOG.md
git commit -m "docs: Publicação nos documentos de arquitetura e pendências

Modelo, órfãos e itens problemáticos (03), fontes do page-list, regras
dos metadados e passos da capa (06), EpubPackageException, navIgnored,
spineItemDuplicate e a conferência de ofuscação pelo media-type (09),
strict com warning esperado (10), lib/src/publication/ (11), ganchos
e pendências movidas para o sub-projeto 6 (14), estado da spec e
CHANGELOG."
```

---

### Tarefa 15: PR e CI verde

**Arquivos:** nenhum novo; correções que o CI exigir vão no arquivo afetado,
com commit próprio.

**Interfaces:** nenhuma.

- [ ] **Passo 1: Verificação local completa**

Run: `dart format --output=none --set-exit-if-changed lib test tool example/lib example/integration_test && flutter analyze && (cd example && flutter analyze) && flutter test && git status --short`
Expected: nada a formatar, `No issues found!` duas vezes, `All tests passed!` e
`git status` vazio.

- [ ] **Passo 2: Branch em dia com a `main`**

A `main` é protegida e exige a branch em dia antes do merge.

Run: `git fetch origin && git log --oneline HEAD..origin/main`
Expected: vazio. Se não for, `git rebase origin/main`, repetir o Passo 1 e
seguir.

- [ ] **Passo 3: Push e PR**

O repositório é pessoal: a conta ativa do `gh` deve ser `EduardoSA8006`
(`gh auth status`; se não for, `gh auth switch --user EduardoSA8006`).

Escrever o corpo da PR num arquivo do scratchpad
(`/tmp/claude-1000/-home-eduardo8006-Documentos-projetos-galley/003640ed-5627-4a8b-81ed-13354cf11bdd/scratchpad/pr-publication.md`),
no formato do `.github/pull_request_template.md`: **Resumo** (o que o
sub-projeto entrega, citando a spec e doc/09), **Commits** (a lista de
`git log --oneline main..HEAD`), **Verificação** (as caixas do template
marcadas, mais "Publicação sobre os 65 EPUBs do corpus", "fuzz de 400
mutações sem exceção fora da taxonomia" e "`publication.read.800` sem
baseline") e **Pontos para revisar** (as decisões 3, 10, 14, 17 e 18 da
seção "Decisões onde a spec é ambígua" e os quatro `diagnostics.expected`
novos de `reais/`).

```bash
git push -u origin fase1/publicacao
gh pr create --repo EduardoSA8006/galley --base main --head fase1/publicacao \
  --title "Fase 1, sub-projeto 2: Publicação (OPF, NAV, NCX, href, reconciliação, capa)" \
  --body-file /tmp/claude-1000/-home-eduardo8006-Documentos-projetos-galley/003640ed-5627-4a8b-81ed-13354cf11bdd/scratchpad/pr-publication.md
```

Expected: URL da PR.

- [ ] **Passo 4: Acompanhar o CI**

Run: `gh pr checks --watch --repo EduardoSA8006/galley`
Expected: `analyze`, `test (min)`, `test (stable)`, `engine-linux` e `perf`
verdes; no resumo do `perf`, `publication.read.800` como "novo, sem baseline".

Falha no `test (min)` ou `test (stable)` que não aparece localmente: rodar o
arquivo que falhou com `flutter test <arquivo>` na versão do job
(`FLUTTER_MIN` 3.47.0 ou o `stable` do log) e investigar a causa antes de
mexer (superpowers:systematic-debugging). Os testes com tempo (`aninhamento
hostil` do NAV, 100 000 níveis no OPF e no NCX, custo linear da
reconciliação) têm folga de 5× a 10× sobre o medido; se um deles estourar no
runner, meça antes de afrouxar. O que for adiado vai para
`doc/14-pendencias.md`, com commit `docs: …`.

- [ ] **Passo 5: Depois do merge (pelo mantenedor)**

Disparar o `perf-baseline` para regenerar os baselines com o caso novo
(pendência registrada na Tarefa 14):

```bash
gh workflow run perf-baseline.yml --repo EduardoSA8006/galley --ref main
```

O resto do fluxo do baseline (baixar, conferir, PR) segue o
`doc/plans/2026-09-25-harness-ci.md`, Tarefa 10.
