# Galley SP1 — Fundação + Container — Plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Criar o pacote `galley` com núcleo de erros/diagnósticos, CI base, leitor de zip próprio sob demanda e a etapa Container (EPUB 2/3: OPF, spine, navegação, recursos, fontes ofuscadas, DRM), mais a sonda de medição de texto em isolate.

**Architecture:** Pacote Flutter feature-first (`lib/src/core`, `lib/src/features/container/{data,domain}`), única API pública em `lib/galley.dart`. O zip lê só o diretório central e descompacta cada entrada sob demanda via `ZLibDecoder(raw: true)`. Parsers XML puros (texto → modelos imutáveis) relatam problemas recuperáveis a um `DiagnosticSink`; só falhas que impedem abrir lançam `GalleyException`.

**Tech Stack:** Flutter ≥ 3.47 / Dart ≥ 3.13, `xml`, `meta`; dev: `flutter_test`, `flutter_lints`, `integration_test`.

**Spec:** `docs/superpowers/specs/2026-11-24-galley-sp1-fundacao-container-design.md` (pai: `docs/superpowers/specs/2026-11-24-galley-arquitetura-design.md`)

## Global Constraints

- SDK: `environment: sdk: ">=3.13.0 <4.0.0"`, `flutter: ">=3.47.0"`.
- Dependências de runtime: **somente** `xml` e `meta`. Nenhuma outra (nem `archive`, nem `crypto`, nem `path`).
- Licença BSD-3-Clause; nome do pacote `galley`.
- API pública exportada apenas por `lib/galley.dart`; tudo o mais em `lib/src/`.
- `flutter analyze --fatal-infos` sem avisos; `dart format` aplicado.
- Modelos de domínio imutáveis (`final class`, campos `final`, coleções não modificáveis).
- Erros recuperáveis → `Diagnostic` no sink, nunca exceção; exceções apenas `GalleyException` (nunca `RangeError`, `FormatException` etc. escapando da API pública).
- Commits em português no formato `tipo(escopo): descrição`.
- Plataformas-alvo: Android, iOS, Linux, macOS, Windows (sem web).

## Review Focus

1. Zip gerado no Windows com `\` nos nomes das entradas → nomes normalizados para `/`, livro abre (teste na Task 3).
2. href com percent-encoding, espaços e não-ASCII (`Text/Cap%C3%ADtulo%201.xhtml`) → resolve para a entrada `Text/Capítulo 1.xhtml` (Task 5 e Task 10).
3. Caixa divergente entre href e entrada (`Images/Cover.JPG` vs `images/cover.jpg`) → encontrado por busca sem diferenciar caixa, com diagnóstico `resource.caseMismatch` (Task 10).
4. OPF/NCX em UTF-16 com BOM, ou UTF-8 com BOM → decodificado corretamente (Task 5).
5. `resource()` chamado várias vezes em paralelo sobre arquivo → leituras serializadas, conteúdos corretos (Task 2).

---

## Estrutura de arquivos

```
pubspec.yaml, analysis_options.yaml, LICENSE, README.md, CHANGELOG.md
.github/workflows/ci.yml
lib/galley.dart
lib/src/core/errors/galley_exception.dart
lib/src/core/diagnostics/{diagnostic.dart, diagnostic_sink.dart, diagnostic_codes.dart}
lib/src/features/container/data/zip/{byte_source.dart, crc32.dart, zip_limits.dart, zip_entry.dart, zip_archive.dart, cp437.dart}
lib/src/features/container/data/text/decode_text.dart
lib/src/features/container/data/path/epub_path.dart
lib/src/features/container/data/crypto/sha1.dart
lib/src/features/container/data/parsers/{container_xml_parser.dart, opf_metadata_parser.dart, opf_parser.dart, nav_parser.dart, ncx_parser.dart, encryption_parser.dart}
lib/src/features/container/data/fonts/font_deobfuscator.dart
lib/src/features/container/domain/models/{epub_metadata.dart, manifest.dart, spine.dart, rendition.dart, navigation.dart, opf_document.dart}
lib/src/features/container/domain/epub_book.dart
test/support/{zip_builder.dart, epub_builder.dart}
test/... (espelha lib/src)
example/ (app mínimo) + example/integration_test/text_measure_isolate_test.dart
```

---

### Task 1: Scaffolding, núcleo de erros/diagnósticos e CI base

**Files:**
- Create: `pubspec.yaml`, `analysis_options.yaml`, `LICENSE`, `README.md`, `CHANGELOG.md`, `lib/galley.dart`, `lib/src/core/errors/galley_exception.dart`, `lib/src/core/diagnostics/diagnostic.dart`, `lib/src/core/diagnostics/diagnostic_sink.dart`, `lib/src/core/diagnostics/diagnostic_codes.dart`, `.github/workflows/ci.yml`, `.gitignore`
- Test: `test/core/diagnostics_test.dart`, `test/core/galley_exception_test.dart`

**Interfaces:**
- Produces:
  - `sealed class GalleyException implements Exception { String get message; }` com subclasses `final`: `NotAnEpubException(String message)`, `CorruptArchiveException(String message)`, `ArchiveLimitExceededException(String message)`, `MissingPackageDocumentException(String message)`, `DrmProtectedException(List<String> algorithms)`, `ResourceNotFoundException(String path)`, `BookClosedException()`. `toString()` = `'<NomeDaClasse>: $message'`.
  - `enum DiagnosticSeverity { info, warning, error }`
  - `final class Diagnostic { const Diagnostic({required this.severity, required this.code, required this.message, this.location}); final DiagnosticSeverity severity; final String code; final String message; final String? location; }` com `==`/`hashCode` por valor.
  - `abstract interface class DiagnosticSink { void report(Diagnostic diagnostic); }`
  - `final class CollectingDiagnosticSink implements DiagnosticSink { List<Diagnostic> get diagnostics /* não modificável */; Stream<Diagnostic> get stream /* broadcast */; }`
  - `final class NullDiagnosticSink implements DiagnosticSink { const NullDiagnosticSink(); }` (descarta; usado como valor padrão `const`).
  - `abstract final class DiagnosticCodes` com constantes `String` (o arquivo é a fonte única; tasks seguintes acrescentam as suas): começa com nada além da classe vazia documentada.

- [ ] **Step 1:** Criar o pacote: `flutter create --template=package --project-name galley .` na raiz; remover o código de exemplo gerado; `pubspec.yaml` com descrição, `repository` em branco por ora, SDK da Global Constraints, deps `xml: ^6.5.0`, `meta: ^1.15.0`, dev `flutter_test`, `flutter_lints: ^6.0.0`. `analysis_options.yaml`: inclui `package:flutter_lints/flutter.yaml`, `analyzer.language: {strict-casts: true, strict-inference: true, strict-raw-types: true}`, regras extras `prefer_final_locals`, `public_member_api_docs`, `always_declare_return_types`. LICENSE BSD-3-Clause com `Copyright (c) 2026, Galley contributors`.

- [ ] **Step 2: Escrever testes que falham**

```dart
test('CollectingDiagnosticSink acumula e emite no stream', () async {
  final sink = CollectingDiagnosticSink();
  final d = Diagnostic(severity: DiagnosticSeverity.warning, code: 'x.y', message: 'm');
  final next = sink.stream.first;
  sink.report(d);
  expect(sink.diagnostics, [d]);
  expect(await next, d);
  expect(() => (sink.diagnostics as List).add(d), throwsUnsupportedError);
});
test('Diagnostic tem igualdade por valor', () {
  expect(const Diagnostic(severity: DiagnosticSeverity.info, code: 'a', message: 'b', location: 'c'),
      const Diagnostic(severity: DiagnosticSeverity.info, code: 'a', message: 'b', location: 'c'));
});
test('DrmProtectedException expõe algoritmos e mensagem', () {
  final e = DrmProtectedException(['urn:x']);
  expect(e, isA<GalleyException>());
  expect(e.algorithms, ['urn:x']);
  expect(e.toString(), startsWith('DrmProtectedException: '));
});
```

- [ ] **Step 3:** `flutter test test/core` → FAIL (símbolos inexistentes).
- [ ] **Step 4:** Implementar os tipos de Interfaces; `lib/galley.dart` exporta `GalleyException` e subclasses, `Diagnostic`, `DiagnosticSeverity`, `DiagnosticSink`, `CollectingDiagnosticSink`.
- [ ] **Step 5:** `flutter test test/core` → PASS; `dart format --output=none --set-exit-if-changed .` e `flutter analyze --fatal-infos` → sem saída de erro.
- [ ] **Step 6:** `.github/workflows/ci.yml`: gatilhos `pull_request` e `push` em `main`; job `analyze-test` em `ubuntu-latest`, matriz `flutter-version: ['3.47.5', 'stable']` via `subosito/flutter-action@v2`, passos: `flutter pub get`, `dart format --output=none --set-exit-if-changed .`, `flutter analyze --fatal-infos`, `flutter test`. (Job da sonda entra na Task 11.)
- [ ] **Step 7: Commit** `git add -A && git commit -m "chore(core): scaffolding do pacote, erros, diagnósticos e CI base"`

---

### Task 2: Fontes de bytes, CRC-32 e ZipBuilder de teste

**Files:**
- Create: `lib/src/features/container/data/zip/byte_source.dart`, `lib/src/features/container/data/zip/crc32.dart`, `test/support/zip_builder.dart`
- Test: `test/features/container/data/zip/byte_source_test.dart`, `test/features/container/data/zip/crc32_test.dart`

**Interfaces:**
- Produces:
  - `abstract interface class ByteSource { int get length; Future<Uint8List> read(int offset, int length); Future<void> close(); }` — `read` além do fim lança `CorruptArchiveException`.
  - `final class MemoryByteSource implements ByteSource { MemoryByteSource(Uint8List bytes); }` (`read` devolve view sem cópia via `Uint8List.sublistView`).
  - `final class FileByteSource implements ByteSource { static Future<FileByteSource> open(String path); }` — `RandomAccessFile`; leituras concorrentes serializadas por fila interna (encadear `Future`s), porque `RandomAccessFile` não aceita operações simultâneas.
  - `int crc32(List<int> bytes, [int crc = 0])` — tabela polinômio `0xEDB88320`, resultado sem sinal 32 bits; o parâmetro permite cálculo incremental.
  - Teste: `class ZipBuilder { void addFile(String name, List<int> data, {bool deflate = true, bool utf8Flag = true, bool encrypted = false, bool dataDescriptor = false}); void addRawName(List<int> nameBytes, List<int> data, {bool utf8Flag = false}); Uint8List build({bool zip64 = false, String comment = ''}); }` — escreve local headers, central directory e EOCD (ZIP64 EOCD + locator + extra `0x0001` quando `zip64: true`); deflate via `ZLibEncoder(raw: true)`.

- [ ] **Step 1: Testes que falham**

```dart
test('crc32 de vetores conhecidos', () {
  expect(crc32(utf8.encode('')), 0x00000000);
  expect(crc32(utf8.encode('123456789')), 0xCBF43926);
  expect(crc32(utf8.encode('56789'), crc32(utf8.encode('1234'))), 0xCBF43926);
});
test('MemoryByteSource lê faixas e rejeita além do fim', () async {
  final s = MemoryByteSource(Uint8List.fromList(List.generate(10, (i) => i)));
  expect(await s.read(2, 3), [2, 3, 4]);
  expect(() => s.read(8, 5), throwsA(isA<CorruptArchiveException>()));
});
test('FileByteSource serializa leituras concorrentes', () async {
  final f = File('${Directory.systemTemp.createTempSync().path}/b.bin')
    ..writeAsBytesSync(List.generate(4096, (i) => i % 256));
  final s = await FileByteSource.open(f.path);
  final rs = await Future.wait([for (var i = 0; i < 50; i++) s.read(i * 64, 64)]);
  for (var i = 0; i < 50; i++) { expect(rs[i].first, (i * 64) % 256); expect(rs[i].length, 64); }
  await s.close();
});
```

- [ ] **Step 2:** `flutter test test/features/container/data/zip` → FAIL.
- [ ] **Step 3:** Implementar `crc32`, `MemoryByteSource`, `FileByteSource`, `ZipBuilder` conforme Interfaces.
- [ ] **Step 4:** mesmos testes → PASS.
- [ ] **Step 5: Commit** `feat(container): fontes de bytes, crc32 e zip builder de teste`

---

### Task 3: Leitura do diretório central (ZipArchive.open)

**Files:**
- Create: `lib/src/features/container/data/zip/{zip_limits.dart, zip_entry.dart, zip_archive.dart, cp437.dart}`; Modify: `diagnostic_codes.dart`
- Test: `test/features/container/data/zip/zip_archive_directory_test.dart`

**Interfaces:**
- Consumes: `ByteSource`, `ZipBuilder`, `DiagnosticSink`.
- Produces:
  - `final class ZipLimits { const ZipLimits({this.maxEntries = 100000, this.maxEntrySize = 512 * 1024 * 1024, this.maxCompressionRatio = 1000, this.ratioCheckThreshold = 1024 * 1024}); }`
  - `final class ZipEntry { final String name; final int method; final int compressedSize; final int uncompressedSize; final int crc32; final int localHeaderOffset; final bool isEncrypted; bool get isDirectory /* name termina com '/' */; }`
  - `final class ZipArchive { static Future<ZipArchive> open(ByteSource source, {ZipLimits limits = const ZipLimits(), DiagnosticSink sink = const NullDiagnosticSink()}); List<ZipEntry> get entries /* ordem do diretório central */; ZipEntry? entry(String name) /* exato */; ZipEntry? entryIgnoringCase(String name); Future<void> close(); }`
  - `String decodeCp437(List<int> bytes)`.
  - Códigos: `zip.nameNotUtf8` (info), `zip.unsafePath` (warning), `zip.duplicateEntry` (warning).

Regras: EOCD (`0x06054b50`) procurado de trás para frente nos últimos `22 + 65535` bytes; se houver locator ZIP64 (`0x07064b50`) imediatamente antes, ler o EOCD64 (`0x06064b50`) e usar seus totais/offset; campos `0xFFFFFFFF`/`0xFFFF` em entradas são lidos do extra `0x0001`. Nome: flag bit 11 → UTF-8; senão tentar UTF-8 estrito e, se inválido, CP437 + diagnóstico `zip.nameNotUtf8`. Normalizar `\` → `/`. Nome absoluto (`/…`, `C:`) ou com segmento `..` → entrada ignorada + `zip.unsafePath`. Duplicata → mantém a primeira + `zip.duplicateEntry`. Sem EOCD ou estrutura inconsistente → `NotAnEpubException` (sem EOCD) / `CorruptArchiveException` (inconsistente). `> maxEntries` → `ArchiveLimitExceededException`. `isEncrypted` = flag bit 0.

- [ ] **Step 1: Testes que falham**

```dart
test('lista entradas na ordem e por nome', ...);              // 3 arquivos → entries.map(name) == [a, b/c.txt, d]
test('lê ZIP64', ...);                                         // ZipBuilder.build(zip64: true) → mesmas entradas
test('EOCD após comentário longo', ...);                       // comment de 60000 chars → abre
test('normaliza barra invertida', ...);                        // addFile('OEBPS\\content.opf') → entry('OEBPS/content.opf') != null
test('nome sem flag UTF-8 em CP437', ...);                     // addRawName([0x82], .., utf8Flag:false) → 'é'; diagnóstico zip.nameNotUtf8
test('ignora caminho inseguro', ...);                          // '../evil', '/abs' → ausentes; 2× zip.unsafePath
test('busca sem diferenciar caixa', ...);                      // entryIgnoringCase('images/COVER.jpg') acha 'Images/cover.jpg'
test('bytes que não são zip', ...);                            // throwsA(isA<NotAnEpubException>())
test('limite de entradas', ...);                               // limits: ZipLimits(maxEntries: 2), 3 arquivos → ArchiveLimitExceededException
```

- [ ] **Step 2:** rodar → FAIL. **Step 3:** implementar. **Step 4:** rodar → PASS.
- [ ] **Step 5: Commit** `feat(container): leitura do diretório central do zip (zip64, cp437, caminhos seguros)`

---

### Task 4: Extração de entradas (stored/deflate, CRC, limites)

**Files:**
- Modify: `lib/src/features/container/data/zip/zip_archive.dart`, `diagnostic_codes.dart`
- Test: `test/features/container/data/zip/zip_archive_read_test.dart`

**Interfaces:**
- Produces: `Future<Uint8List> ZipArchive.read(ZipEntry entry)`; código `zip.crcMismatch` (error).

Regras: ler local header (30 bytes) no `localHeaderOffset`, validar assinatura `0x04034b50`, dados começam em `offset + 30 + nameLen + extraLen` (tamanhos sempre do diretório central, por causa do data descriptor). Método 0 → cópia; 8 → `ZLibDecoder(raw: true)`; outro → `CorruptArchiveException`. `isEncrypted` → `DrmProtectedException(['zip-encryption'])`. Antes de descompactar: `uncompressedSize > maxEntrySize` ou (`uncompressedSize > ratioCheckThreshold` e `uncompressedSize / max(compressedSize,1) > maxCompressionRatio`) → `ArchiveLimitExceededException`. Saída com tamanho ≠ `uncompressedSize` → `CorruptArchiveException`. CRC divergente → diagnóstico `zip.crcMismatch` e devolve os bytes (tolerância). Falha do zlib → `CorruptArchiveException`. Após `close()` → `BookClosedException`.

- [ ] **Step 1: Testes que falham** — `read` devolve conteúdo idêntico para stored, deflate, com data descriptor e ZIP64; conteúdo vazio; CRC alterado no builder → bytes devolvidos + `zip.crcMismatch`; entrada cifrada → `DrmProtectedException`; deflate corrompido (bytes trocados) → `CorruptArchiveException`; `uncompressedSize` 2 MiB a partir de 1 KiB com `ZipLimits(maxCompressionRatio: 100)` → `ArchiveLimitExceededException`; `read` após `close` → `BookClosedException`.
- [ ] **Step 2:** FAIL. **Step 3:** implementar. **Step 4:** PASS.
- [ ] **Step 5: Commit** `feat(container): extração de entradas do zip com crc e limites de segurança`

---

### Task 5: Decodificação de texto, resolução de caminhos, container.xml e EpubBuilder

**Files:**
- Create: `lib/src/features/container/data/text/decode_text.dart`, `lib/src/features/container/data/path/epub_path.dart`, `lib/src/features/container/data/parsers/container_xml_parser.dart`, `test/support/epub_builder.dart`; Modify: `diagnostic_codes.dart`
- Test: `test/features/container/data/text/decode_text_test.dart`, `test/features/container/data/path/epub_path_test.dart`, `test/features/container/data/parsers/container_xml_parser_test.dart`

**Interfaces:**
- Produces:
  - `String decodeText(Uint8List bytes)` — BOM UTF-8 (removido), BOM UTF-16 LE/BE; sem BOM: se começa com `<?xml` e declara `encoding="ISO-8859-1"`/`latin1`/`windows-1252` decodifica latin1, senão UTF-8 com `allowMalformed: true`.
  - `typedef ResolvedHref = ({String path, String? fragment});`
  - `ResolvedHref? resolveHref(String baseFilePath, String href)` — `null` para href com esquema (`http:`, `mailto:` etc.) ou que escapa da raiz; separa `#fragmento`; remove `?query`; aplica percent-decoding (UTF-8) depois de separar; resolve relativo ao diretório de `baseFilePath`, normalizando `.` e `..`; `href` vazio com fragmento → mesmo arquivo.
  - `List<String> parseContainerXml(String xml, DiagnosticSink sink)` — caminhos dos `rootfile` com `media-type="application/oebps-package+xml"` (ordem do documento); XML inválido → `[]` + `container.xmlInvalid`; mais de um → `container.multipleRenditions` (info).
  - Teste: `Uint8List buildEpub(Map<String, Object> files, {bool includeMimetype = true, String mimetype = 'application/epub+zip', bool mimetypeFirst = true, bool includeContainer = true, String opfPath = 'OEBPS/content.opf'})` — valores `String` (UTF-8) ou `List<int>`; gera `META-INF/container.xml` apontando para `opfPath`. Mais `String opf3({String title = 'T', String identifier = 'urn:uuid:12345678-1234-1234-1234-123456789abc', String manifest = '', String spine = '', String extraMetadata = '', String spineAttrs = ''})` e `String opf2(...)` com os mesmos parâmetros.
  - Códigos: `container.xmlInvalid` (error), `container.multipleRenditions` (info).

- [ ] **Step 1: Testes que falham**

```dart
expect(decodeText(Uint8List.fromList([0xEF,0xBB,0xBF, ...utf8.encode('ação')])), 'ação');
expect(decodeText(Uint8List.fromList([0xFF,0xFE, 0x61,0x00, 0xE7,0x00])), 'aç');
expect(decodeText(Uint8List.fromList([0xFE,0xFF, 0x00,0x61])), 'a');
expect(decodeText(Uint8List.fromList([...ascii.encode('<?xml version="1.0" encoding="ISO-8859-1"?><a>'), 0xE9])), endsWith('é'));
expect(resolveHref('OEBPS/content.opf', 'Text/Cap%C3%ADtulo%201.xhtml#p2'), (path: 'OEBPS/Text/Capítulo 1.xhtml', fragment: 'p2'));
expect(resolveHref('OEBPS/Text/c1.xhtml', '../Images/a.png'), (path: 'OEBPS/Images/a.png', fragment: null));
expect(resolveHref('OEBPS/Text/c1.xhtml', '#n1'), (path: 'OEBPS/Text/c1.xhtml', fragment: 'n1'));
expect(resolveHref('content.opf', '../../x'), isNull);
expect(resolveHref('content.opf', 'https://e.com/a'), isNull);
expect(parseContainerXml(validWithTwoRootfiles, sink), ['OEBPS/a.opf', 'OEBPS/b.opf']); // + container.multipleRenditions
expect(parseContainerXml('<nope', sink), isEmpty); // + container.xmlInvalid
```

- [ ] **Step 2:** FAIL. **Step 3:** implementar. **Step 4:** PASS.
- [ ] **Step 5: Commit** `feat(container): decodificação de texto, resolução de href e container.xml`

---

### Task 6: Metadados do OPF (EPUB 2 e 3)

**Files:**
- Create: `lib/src/features/container/domain/models/epub_metadata.dart`, `lib/src/features/container/data/parsers/opf_metadata_parser.dart`; Modify: `diagnostic_codes.dart`
- Test: `test/features/container/data/parsers/opf_metadata_parser_test.dart`

**Interfaces:**
- Produces:
  - `enum EpubVersion { epub2, epub3 }`
  - `final class EpubContributor { final String name; final String? fileAs; final String? role; }`
  - `final class EpubIdentifier { final String value; final String? scheme; final String? id; }`
  - `final class EpubMetadata { final List<String> titles; String? get title => titles.firstOrNull; final List<EpubContributor> creators; final List<EpubContributor> contributors; final List<String> languages; final List<EpubIdentifier> identifiers; final String? uniqueIdentifier; final String? publisher; final String? description; final List<String> subjects; final String? date; final String? modified; final String? rights; final Map<String, String> otherMeta; }`
  - `EpubVersion parseEpubVersion(XmlElement package, DiagnosticSink sink)` — `version` começando com `3` → epub3; `2` → epub2; ausente/inválido → epub3 se houver item com `properties~=nav`, senão epub2, + `opf.versionInvalid`.
  - `EpubMetadata parseOpfMetadata(XmlElement metadata, {required EpubVersion version, required String? uniqueIdentifierId, required DiagnosticSink sink})`

Regras: EPUB 3 — `<meta refines="#id" property="file-as|role|title-type|display-seq">` aplicados ao elemento `dc:*` de mesmo `id`; títulos ordenados com `title-type="main"` primeiro, depois `display-seq`; `dcterms:modified` → `modified`; demais `<meta property>` sem refines → `otherMeta[property]`. EPUB 2 — `opf:file-as`, `opf:role`, `opf:scheme` como atributos; `<meta name content>` → `otherMeta[name]`. `uniqueIdentifier` = valor do `dc:identifier` cujo `id` == `uniqueIdentifierId`; se não houver, o primeiro identificador + `opf.uniqueIdentifierMissing`. Sem título → `opf.titleMissing` (warning). Texto com espaços aparados e espaços internos colapsados. Elementos `dc:` reconhecidos pelo namespace `http://purl.org/dc/elements/1.1/`, aceitando prefixo diferente de `dc`.

- [ ] **Step 1: Testes que falham** — EPUB 3 com dois títulos (`subtitle` antes, `main` depois) → `title` é o main; criador com `refines` `file-as`/`role=aut` → `EpubContributor(name, fileAs, role: 'aut')`; `uniqueIdentifier` correto entre dois identificadores; `modified` lido; EPUB 2 com `opf:file-as`, `opf:role`, `opf:scheme="ISBN"` → mapeados; `<meta name="cover" content="img">` → `otherMeta['cover'] == 'img'`; prefixo `dcx:` com namespace DC → reconhecido; sem título → `title == null` + `opf.titleMissing`; versão `"3.0"` → epub3, `"2.0.1"` → epub2, ausente sem nav → epub2 + `opf.versionInvalid`.
- [ ] **Step 2:** FAIL. **Step 3:** implementar. **Step 4:** PASS.
- [ ] **Step 5: Commit** `feat(container): metadados do OPF (epub 2 e 3, refines)`

---

### Task 7: Manifest, spine, rendition, capa (parseOpf)

**Files:**
- Create: `lib/src/features/container/domain/models/{manifest.dart, spine.dart, rendition.dart, opf_document.dart}`, `lib/src/features/container/data/parsers/opf_parser.dart`; Modify: `diagnostic_codes.dart`
- Test: `test/features/container/data/parsers/opf_parser_test.dart`

**Interfaces:**
- Consumes: `parseEpubVersion`, `parseOpfMetadata`, `resolveHref`, `decodeText` (não aqui; recebe `String`).
- Produces:
  - `final class ManifestItem { final String id; final String path /* caminho no zip, resolvido */; final String mediaType; final Set<String> properties; final String? fallbackId; }`
  - `enum PageProgressionDirection { ltr, rtl, unspecified }`
  - `final class SpineItem { final ManifestItem item; final bool linear; final Set<String> properties; }`
  - `final class EpubSpine { final List<SpineItem> items; final PageProgressionDirection direction; }`
  - `enum RenditionLayout { reflowable, prePaginated }`, `enum RenditionOrientation { auto, portrait, landscape }`, `enum RenditionSpread { auto, none, landscape, both }`
  - `final class EpubRendition { final RenditionLayout layout; final RenditionOrientation orientation; final RenditionSpread spread; }` (padrões: reflowable/auto/auto)
  - `final class OpfDocument { final EpubVersion version; final EpubMetadata metadata; final Map<String, ManifestItem> manifest /* por id */; final EpubSpine spine; final EpubRendition rendition; final ManifestItem? cover; final ManifestItem? navItem; final ManifestItem? ncxItem; }`
  - `OpfDocument parseOpf(String xml, {required String opfPath, required DiagnosticSink sink})` — XML inválido → `MissingPackageDocumentException`.

Regras: item sem `id`/`href`/`media-type` → ignorado + `opf.manifestItemInvalid`; `href` não resolvível → ignorado + mesmo código; id duplicado → primeiro vence + `opf.duplicateId`. `itemref` com `idref` inexistente → ignorado + `opf.spineRefMissing`; `linear="no"` → `false`. `spine@page-progression-direction`. `rendition:*` lidos de `<meta property="rendition:layout">` etc. (valor `portrait` em spread → `both`; desconhecido → padrão + `opf.renditionValueInvalid`). `navItem` = item com property `nav`; `ncxItem` = `spine@toc` ou, se ausente, primeiro item `application/x-dtbncx+xml`. Capa, em ordem: item com property `cover-image`; `otherMeta['cover']` como id de item; `<guide><reference type="cover">` apontando para imagem (se apontar para XHTML, ignorar). Spine vazio → `opf.spineEmpty` (error, não fatal).

- [ ] **Step 1: Testes que falham** — manifest com href percent-encoded resolvido; item inválido e id duplicado → ignorados com diagnósticos; spine com `idref` faltante → pulado + `opf.spineRefMissing`; `linear="no"`; `page-progression-direction="rtl"`; `rendition:layout pre-paginated` + `rendition:spread portrait` → `prePaginated`/`both`; capa por `cover-image`, por `meta name=cover` (EPUB 2) e por guide; `navItem`/`ncxItem` detectados; XML quebrado → `MissingPackageDocumentException`.
- [ ] **Step 2:** FAIL. **Step 3:** implementar. **Step 4:** PASS.
- [ ] **Step 5: Commit** `feat(container): manifest, spine, rendition e capa do OPF`

---

### Task 8: Navegação (nav.xhtml e NCX)

**Files:**
- Create: `lib/src/features/container/domain/models/navigation.dart`, `lib/src/features/container/data/parsers/{nav_parser.dart, ncx_parser.dart}`; Modify: `diagnostic_codes.dart`
- Test: `test/features/container/data/parsers/nav_parser_test.dart`, `test/features/container/data/parsers/ncx_parser_test.dart`

**Interfaces:**
- Consumes: `resolveHref`, `ResolvedHref`.
- Produces:
  - `final class NavPoint { final String label; final String? path; final String? fragment; final String? type /* epub:type, landmarks */; final List<NavPoint> children; }`
  - `final class EpubNavigation { final List<NavPoint> toc; final List<NavPoint> pageList; final List<NavPoint> landmarks; static const empty; }`
  - `EpubNavigation? parseNavDocument(String xhtml, {required String navPath, required DiagnosticSink sink})` — `null` se não parsear (+ `nav.invalid`).
  - `EpubNavigation? parseNcx(String xml, {required String ncxPath, required DiagnosticSink sink})` — idem com `ncx.invalid`.

Regras nav: `XmlDocument.parse(text, entityMapping: XmlDefaultEntityMapping.html5())`; localizar `<nav>` por `epub:type` (namespace `http://www.idpf.org/2007/ops`, aceitando também atributo literal `epub:type` e `role="doc-toc"`) com valores `toc`, `page-list`, `landmarks`; percorrer `ol > li` recursivamente; rótulo = texto de `a` ou `span` (espaços colapsados; vazio → atributo `title`); `li` sem `a` (só `span`) → `path` nulo, mantém filhos; href externo → `path` nulo. NCX: `navMap/navPoint` recursivo (ordenado por `playOrder` quando todos têm, senão ordem do documento), `navLabel/text`, `content@src`; `pageList/pageTarget` → `pageList`.

- [ ] **Step 1: Testes que falham** — nav com toc aninhado 3 níveis, `&nbsp;` no rótulo, `span` sem link com filhos, href `../Text/c%201.xhtml#x` resolvido a partir de `OEBPS/nav/nav.xhtml`, page-list e landmarks com `type`; nav inválido → `null` + `nav.invalid`; NCX com navPoints aninhados fora de ordem de `playOrder` → ordenados; pageList; NCX inválido → `null` + `ncx.invalid`.
- [ ] **Step 2:** FAIL. **Step 3:** implementar. **Step 4:** PASS.
- [ ] **Step 5: Commit** `feat(container): navegação via nav.xhtml e ncx`

---

### Task 9: encryption.xml, desofuscação de fontes e detecção de DRM

**Files:**
- Create: `lib/src/features/container/data/crypto/sha1.dart`, `lib/src/features/container/data/parsers/encryption_parser.dart`, `lib/src/features/container/data/fonts/font_deobfuscator.dart`; Modify: `diagnostic_codes.dart`
- Test: `test/features/container/data/crypto/sha1_test.dart`, `test/features/container/data/fonts/font_deobfuscator_test.dart`, `test/features/container/data/parsers/encryption_parser_test.dart`

**Interfaces:**
- Produces:
  - `Uint8List sha1(List<int> bytes)`
  - `const idpfObfuscation = 'http://www.idpf.org/2008/embedding'; const adobeObfuscation = 'http://ns.adobe.com/pdf/enc#RC';`
  - `final class EncryptedResource { final String path; final String algorithm; }`
  - `List<EncryptedResource> parseEncryptionXml(String xml, DiagnosticSink sink)` — `EncryptedData > EncryptionMethod@Algorithm` + `CipherData > CipherReference@URI` (URI relativo à raiz do container, percent-decoded); inválido → `[]` + `encryption.invalid`.
  - `Uint8List deobfuscateIdpf(Uint8List data, String uniqueIdentifier)` — chave = `sha1(utf8(identifier sem U+0020, U+0009, U+000D, U+000A))`; XOR dos primeiros `min(1040, len)` bytes com a chave de 20 bytes ciclada.
  - `Uint8List deobfuscateAdobe(Uint8List data, String uniqueIdentifier)` — chave = 16 bytes do UUID (remove `urn:uuid:` e `-`, hex); XOR dos primeiros `min(1024, len)` bytes com a chave ciclada; UUID inválido → lança `FormatException` capturada pelo chamador (Task 10 converte em diagnóstico).
  - Ambos devolvem cópia (não mutam a entrada) e são involutivos.

- [ ] **Step 1: Testes que falham**

```dart
expect(hex(sha1(utf8.encode('abc'))), 'a9993e364706816aba3e25717850c26c9cd0d89d');
expect(hex(sha1(utf8.encode(''))), 'da39a3ee5e6b4b0d3255bfef95601890afd80709');
expect(hex(sha1(List.filled(1000000, 0x61))), '34aa973cd4c4daa4f61eeb2bdbad27316534016f');
// involução e fronteira: bytes após 1040 (IDPF) / 1024 (Adobe) inalterados
final font = Uint8List.fromList(List.generate(2000, (i) => i % 251));
expect(deobfuscateIdpf(deobfuscateIdpf(font, ' urn:uuid:abc \n'), 'urn:uuid:abc'), font); // espaços ignorados
expect(deobfuscateIdpf(font, 'id').sublist(1040), font.sublist(1040));
expect(deobfuscateAdobe(font, 'urn:uuid:12345678-1234-1234-1234-123456789abc').sublist(1024), font.sublist(1024));
expect(deobfuscateAdobe(font, 'urn:uuid:12345678-1234-1234-1234-123456789abc')[0], font[0] ^ 0x12);
// parse: dois recursos (idpf + algoritmo desconhecido) → lista com paths decodificados
```

- [ ] **Step 2:** FAIL. **Step 3:** implementar. **Step 4:** PASS.
- [ ] **Step 5: Commit** `feat(container): desofuscação de fontes idpf/adobe e parser de encryption.xml`

---

### Task 10: EpubBook — API pública de ponta a ponta

**Files:**
- Create: `lib/src/features/container/domain/epub_book.dart`; Modify: `lib/galley.dart`, `diagnostic_codes.dart`
- Test: `test/features/container/domain/epub_book_test.dart`, `test/fixtures/` (gerados pelo `EpubBuilder` em `setUpAll`, nunca binários versionados)

**Interfaces:**
- Consumes: tudo das Tasks 2–9.
- Produces:
  ```dart
  final class EpubBook {
    static Future<EpubBook> open(String path, {DiagnosticSink? diagnostics, ZipLimits limits = const ZipLimits()});
    static Future<EpubBook> fromBytes(Uint8List bytes, {DiagnosticSink? diagnostics, ZipLimits limits = const ZipLimits()});
    EpubVersion get version; EpubMetadata get metadata; Map<String, ManifestItem> get manifest;
    EpubSpine get spine; EpubNavigation get navigation; EpubRendition get rendition;
    ManifestItem? get cover; String get packagePath; List<Diagnostic> get diagnostics;
    ManifestItem? manifestItemByPath(String path);
    Future<Uint8List> resource(String path);   // desofusca fontes listadas em encryption.xml
    Future<String> resourceText(String path);  // decodeText(resource(path))
    Future<void> close();
  }
  ```
  `diagnostics` = todos os diagnósticos da abertura e dos `resource()` posteriores (internamente um `CollectingDiagnosticSink`, que também repassa ao sink do chamador se fornecido).
- `lib/galley.dart` exporta `EpubBook`, todos os modelos de domínio (`EpubVersion`, `EpubMetadata`, `EpubContributor`, `EpubIdentifier`, `ManifestItem`, `SpineItem`, `EpubSpine`, `PageProgressionDirection`, `EpubRendition`, `RenditionLayout`, `RenditionOrientation`, `RenditionSpread`, `EpubNavigation`, `NavPoint`), `ZipLimits` e o núcleo da Task 1. Nada de `data/`.
- Códigos: `container.mimetypeMissing`, `container.mimetypeInvalid`, `container.mimetypeNotFirst` (info), `container.containerMissing`, `resource.caseMismatch`, `font.deobfuscationFailed`, `nav.fallbackToNcx` (info), `nav.missing` (warning).

Fluxo de abertura: `ZipArchive.open` (bytes não-zip → `NotAnEpubException`) → `mimetype`: ausente / conteúdo ≠ `application/epub+zip` (aparado) / não é a primeira entrada → diagnósticos respectivos → DRM: existe `META-INF/rights.xml` ou `META-INF/license.lcpl`, ou `encryption.xml` lista algoritmo diferente de `idpfObfuscation`/`adobeObfuscation` → `DrmProtectedException(algoritmos)` → `container.xml` → primeiro rootfile; ausente ou sem rootfile → `container.containerMissing` e usar a primeira entrada terminada em `.opf`; nenhuma → `MissingPackageDocumentException` → `parseOpf` → navegação: `navItem` (se `parseNavDocument` der `null` ou `navItem` ausente, tentar `ncxItem` com `nav.fallbackToNcx`; nenhum → `EpubNavigation.empty` + `nav.missing`). Busca de recurso: `entry(path)`, senão `entryIgnoringCase(path)` + `resource.caseMismatch`, senão `ResourceNotFoundException(path)`. Itens do spine cujo arquivo não existe no zip continuam no spine (o diagnóstico aparece só no acesso). `open(path)` fecha o `FileByteSource` se a abertura falhar. Qualquer exceção não-`GalleyException` vinda de parsing é convertida em `CorruptArchiveException` (nenhum erro cru escapa).

- [ ] **Step 1: Testes que falham** (EPUBs via `buildEpub`):
  - EPUB 3 completo: metadata, spine (2 itens), toc de `nav.xhtml`, capa, `resourceText` do capítulo com nome `Text/Capítulo 1.xhtml` referenciado no OPF como `Text/Cap%C3%ADtulo%201.xhtml`.
  - EPUB 2 com NCX: toc do NCX.
  - EPUB 3 com `nav.xhtml` quebrado e NCX presente → toc do NCX + `nav.fallbackToNcx`.
  - sem `mimetype`, `mimetype` errado, `mimetype` fora da primeira posição → abre, com os 3 diagnósticos respectivos.
  - sem `container.xml` mas com `OEBPS/content.opf` → abre + `container.containerMissing`.
  - recurso com caixa divergente → bytes + `resource.caseMismatch`; inexistente → `ResourceNotFoundException`.
  - fonte ofuscada IDPF e Adobe → `resource()` devolve a fonte original (comparar com os bytes antes de ofuscar).
  - `encryption.xml` com `http://www.w3.org/2001/04/xmlenc#aes128-cbc` → `DrmProtectedException`; `META-INF/rights.xml` → `DrmProtectedException`.
  - bytes aleatórios → `NotAnEpubException`; zip sem OPF → `MissingPackageDocumentException`.
  - `open(path)` de arquivo em disco equivale a `fromBytes`; `resource` após `close` → `BookClosedException`.
- [ ] **Step 2:** FAIL. **Step 3:** implementar. **Step 4:** PASS (`flutter test`, suíte inteira).
- [ ] **Step 5: Commit** `feat(container): EpubBook — abertura de epub de ponta a ponta`

---

### Task 11: Fuzz do zip e do container

**Files:**
- Test: `test/features/container/fuzz_test.dart`

**Interfaces:**
- Consumes: `EpubBook.fromBytes`, `buildEpub`.

- [ ] **Step 1: Escrever o teste** — semente fixa (`Random(42)`); a partir de um EPUB válido, gerar 2000 variações: truncar em posição aleatória, trocar 1–16 bytes aleatórios, zerar faixas do diretório central, duplicar o EOCD. Para cada uma: abrir com `fromBytes` e, se abrir, ler todos os recursos do manifest. Asserção: cada operação completa em < 2 s (`timeout`) e só lança `GalleyException` (`throwsA(isA<GalleyException>())` ou sucesso); qualquer outro tipo falha o teste mostrando a semente/índice.
- [ ] **Step 2:** rodar `flutter test test/features/container/fuzz_test.dart`; para cada falha, corrigir o código de produção (não o teste) até PASS.
- [ ] **Step 3: Commit** `test(container): fuzz do zip e da abertura de epub`

---

### Task 12: Sonda de medição de texto com dart:ui em isolate + matriz no CI

**Files:**
- Create: `example/` (via `flutter create --platforms=android,ios,linux,macos,windows --project-name galley_example example`, app mínimo que abre um EPUB embutido em assets e mostra título e número de capítulos — também satisfaz o requisito de exemplo do pub.dev), `example/integration_test/text_measure_isolate_test.dart`; Modify: `.github/workflows/ci.yml`, `docs/superpowers/specs/2026-11-24-galley-arquitetura-design.md` (registrar resultado)

**Interfaces:**
- Consumes: nada da lib além de `EpubBook` no app de exemplo.

- [ ] **Step 1: Escrever o teste de integração**

```dart
// Mede o mesmo parágrafo na thread principal e em Isolate.run e compara.
Map<String, Object> measure() {
  final b = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 16))
    ..addText('Galley ação — 漢字かな — עברית mixed bidi ' * 20);
  final p = b.build()..layout(const ui.ParagraphConstraints(width: 300));
  return {'height': p.height, 'longest': p.longestLine, 'lines': p.computeLineMetrics().length};
}
testWidgets('dart:ui mede texto em isolate de fundo igual à thread principal', (t) async {
  final main = measure();
  final bg = await Isolate.run(measure);
  expect(bg, main);
  expect(main['lines'] as int, greaterThan(1));
});
```

- [ ] **Step 2:** Rodar localmente: `cd example && flutter test integration_test -d linux` (com `xvfb-run` se não houver display). Registrar o resultado (PASS, ou a exceção exata).
- [ ] **Step 3:** Adicionar job `probe` em `ci.yml` com matriz: `linux` (`ubuntu-latest`, instalar `ninja-build libgtk-3-dev`, `xvfb-run flutter test integration_test -d linux`), `macos` (`macos-latest`, `-d macos`), `windows` (`windows-latest`, `-d windows`), `android` (`ubuntu-latest` + `reactivecircus/android-emulator-runner@v2`, API 34, `flutter test integration_test`), `ios` (`macos-latest`, `xcrun simctl boot` de um iPhone disponível e `-d <udid>`). `fail-fast: false`. O job não usa `continue-on-error`: falha é um sinal que precisa ser visto.
- [ ] **Step 4:** Registrar no documento pai (§7) uma linha "Resultado da sonda (data): …" com o resultado local; resultados das outras plataformas são acrescentados quando o CI rodar no GitHub. **Se a sonda falhar localmente, parar e reportar ao usuário** — isso aciona a decisão do plano B, que não é do implementador.
- [ ] **Step 5: Commit** `test(probe): sonda de medição de texto dart:ui em isolate e matriz de plataformas no CI`

---

## Notas de execução

- O repositório ainda não tem remote; os jobs do CI só rodam depois que o usuário criar o repositório no GitHub e publicar a branch (fora deste plano, na finalização da branch).
- Trabalhar numa branch `sp1/fundacao-container`, não na `main`.
