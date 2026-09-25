# Contêiner (Fase 1, sub-projeto 1) — design

**Data:** 2026-09-25. **Estado:** aprovada (revisão delegada pelo dono do
repositório ao executor, com uma revisão independente cujos achados estão
incorporados). **Branch:** `fase1/container`.

## 1. Objetivo

Primeiro dos seis sub-projetos da Fase 1 ([13](../13-riscos-spikes-fases.md)
§2): tudo o que fica **abaixo** da Publicação. Entrega a leitura de recursos de
um EPUB, a partir de um `.epub` (ZIP) ou de um `EpubResourceProvider` do app,
com detecção de DRM, desofuscação de fontes, limites contra arquivo hostil e o
canal de exceções e diagnósticos que as camadas de cima vão usar.

**Critério de sucesso:** o teste de corpus de §9 passa nos 65 EPUBs; nenhuma
leitura carrega o arquivo inteiro na memória (medido, §9); nenhum EPUB
malformado derruba o processo ou produz exceção fora da taxonomia de §8.

### 1.1 Decisões tomadas no brainstorming

- Seis sub-projetos na Fase 1, nesta ordem: **Contêiner**, Publicação, CSS, IR
  de seção, Cache e worker, Documento e fechamento. Cada um com spec, plano e
  PR próprios.
- **Inflate no web adiado para a 1.0.x** (P7 continua pendente): no nativo,
  `ZLibDecoder` de `dart:io`; no web, stub por import condicional que compila e
  falha com mensagem clara.
- **Abordagem A** para recursos: interface interna `EpubContainer` com duas
  implementações (`ZipContainer`, `ProviderContainer`).
- **Leitura assíncrona separada da decodificação síncrona:** `fetch` é
  assíncrono e faz uma ida ao `EpubByteSource`; `decode()` é `sync*` com
  checkpoints. Resolve o conflito entre `readRange` devolver `Future` e as
  tarefas do worker serem `sync*` ([08](../08-concorrencia-cache.md) §1).
- **CRC-32 sempre verificado** durante o `decode()`: `warning` em produção,
  exceção em `strict`. Corrige a contradição de [03](../03-camada-a-ir.md)
  §2.2.
- A estrutura segue [11](../11-empacotamento-versionamento.md) §4 (pacote, zero
  dependências além de `html`, `xml` e `meta`, erros por exceção e
  diagnóstico). A preferência global por feature-first, MVVM, Result e Riverpod
  vale para apps, não para este pacote.

### 1.2 Fora do escopo

- Ler `container.xml` e o OPF, e lançar `EpubContainerException` quando o
  `container.xml` falta (sub-projeto 2, Publicação).
- Normalizar `href` vindo do OPF (barra invertida, URL-encoding, `..`) e
  conferir o `media-type` do manifest (sub-projeto 2).
- Converter falha de entrada em seção placeholder (sub-projetos 2 e 4, §4.1).
- Chave NFC no índice de nomes (sub-projeto 4, quando a normalização existir;
  anotado em [14](../14-pendencias.md)).
- Cache e worker (sub-projeto 5); `EpubDocument`, `onDiagnostic` e
  `diagnosticStream` (sub-projeto 6); inflate no web (1.0.x, P7).

## 2. Arquivos

| Caminho | Papel |
|---|---|
| `lib/galley.dart` | Exports públicos desta etapa |
| `lib/src/container/byte_source.dart` | `EpubByteSource`, `MemoryEpubByteSource` |
| `lib/src/container/resource_provider.dart` | `EpubResourceProvider` |
| `lib/src/container/container.dart` | `EpubContainer`, `PendingResource`, `FontObfuscation`, `maxEntrySize` |
| `lib/src/container/zip/binary.dart` | Leitura little-endian de u16/u32/u64 (u64 como dois u32, compatível com dart2js) |
| `lib/src/container/zip/cp437.dart` | Tabela CP437 dos 128 bytes altos |
| `lib/src/container/zip/central_directory.dart` | EOCD, EOCD64, `ZipEntry`, leitura e validação do central directory |
| `lib/src/container/zip/zip_container.dart` | `ZipContainer` |
| `lib/src/container/zip/crc32.dart` | CRC-32 por tabela, incremental |
| `lib/src/container/inflate/inflate.dart` | Interface do inflate chunked + import condicional |
| `lib/src/container/inflate/inflate_io.dart` | `ZLibDecoder(raw: true)` em modo chunked |
| `lib/src/container/inflate/inflate_stub.dart` | Web: lança `UnsupportedError` com mensagem que cita P7 e 1.0.x |
| `lib/src/container/provider_container.dart` | `ProviderContainer` |
| `lib/src/container/encryption.dart` | Parse de `encryption.xml` e detecção de DRM |
| `lib/src/container/font_obfuscation.dart` | `deobfuscateFont`, chaves IDPF e Adobe, `looksLikeFont` |
| `lib/src/container/sha1.dart` | SHA-1 próprio (vem do spike S6) |
| `lib/src/io/file_byte_source.dart` | `FileEpubByteSource` por import condicional |
| `lib/src/io/file_byte_source_io.dart` | Sobre `RandomAccessFile`, com fila de leituras |
| `lib/src/io/file_byte_source_stub.dart` | Web: construtor lança `UnsupportedError` |
| `lib/src/diagnostics/exceptions.dart` | `EpubException` e as subclasses desta etapa |
| `lib/src/diagnostics/diagnostic.dart` | `EpubDiagnostic`, `EpubDiagnosticCode`, `EpubSeverity`, `DiagnosticSink` |

Testes em `test/container/` e `test/diagnostics/`, com apoio em
`test/container/support/`.

## 3. Tipos públicos

Exportados por `lib/galley.dart`: `EpubByteSource`, `MemoryEpubByteSource`,
`FileEpubByteSource`, `EpubResourceProvider`, `EpubException`,
`EpubContainerException`, `EpubEncryptedException`, `EpubDiagnostic`,
`EpubDiagnosticCode`, `EpubSeverity`.

```dart
abstract interface class EpubByteSource {
  Future<int> get length;
  /// Exatamente [length] bytes a partir de [offset]. O resultado pode ser uma
  /// view: quem chama não altera o conteúdo.
  /// RangeError se offset < 0, length < 0 ou offset + length > tamanho.
  /// StateError depois de close().
  Future<Uint8List> readRange(int offset, int length);
  /// Idempotente.
  Future<void> close();
}

final class MemoryEpubByteSource implements EpubByteSource {
  MemoryEpubByteSource(Uint8List bytes);
}

final class FileEpubByteSource implements EpubByteSource {
  /// Abre o arquivo na primeira chamada a length ou readRange; arquivo
  /// inexistente ou ilegível lança FileSystemException nesse momento.
  FileEpubByteSource(String path);
  /// O worker (sub-projeto 5) usa para abrir um segundo handle dentro do
  /// isolate (08 §1).
  String get path;
}

abstract interface class EpubResourceProvider {
  Future<Uint8List> read(String href);
  Future<bool> exists(String href);
  Future<void> close();
}
```

`FileEpubByteSource` **serializa as leituras numa fila interna**: o
`RandomAccessFile` não aceita duas operações assíncronas ao mesmo tempo, e a
Publicação e a pré-busca (08 §1.1) chamam `readRange` concorrentemente. Cada
`readRange` lê em laço até ter `length` bytes. `close()` espera as leituras
pendentes e depois fecha o handle.

`EpubResourceProvider` e `EpubByteSource` são interfaces do app; `07` §1 passa
a mostrar `FileEpubByteSource(path)`.

## 4. `EpubContainer` (interno)

```dart
/// Maior entrada aceita, descomprimida. Proteção contra zip bomb.
const int maxEntrySize = 256 * 1024 * 1024;

abstract interface class EpubContainer {
  /// Caminhos de arquivo presentes (sem diretórios), na ordem do contêiner.
  Iterable<String> get paths;

  /// Caminho existe: exato, senão sem diferenciar maiúsculas. Não emite
  /// diagnóstico (quem emite é fetch).
  Future<bool> exists(String path);

  /// Busca os bytes crus numa ida à fonte. null se ausente.
  /// EpubContainerException(href: path) se a entrada não é legível (§4.1).
  Future<PendingResource?> fetch(String path);

  /// Ofuscação de fonte declarada para o caminho (resolvido pelo mesmo índice
  /// de fetch).
  FontObfuscation? obfuscationOf(String path);

  /// Fecha a fonte (EpubByteSource ou EpubResourceProvider): o contêiner é
  /// dono dela. Idempotente.
  Future<void> close();
}

final class PendingResource {
  String get path;           // nome resolvido da entrada
  int get size;              // tamanho descomprimido declarado (≤ maxEntrySize)
  /// Passos do decode (inflate se deflate, e CRC). Ver §5.4.
  Iterable<void> decode();
  /// Bytes decodificados. StateError antes de decode() ser drenado ou
  /// depois de uma exceção no decode.
  Uint8List get bytes;
}

enum FontObfuscation { idpf, adobe, unknown }
```

Os caminhos recebidos por `exists`, `fetch` e `obfuscationOf` são relativos à
raiz do contêiner, já normalizados pela Publicação (sem `\`, sem `%xx`, sem
`..`, sem `/` inicial).

Semântica do `sync*`: cada chamada a `decode()` devolve um iterável novo, e a
proteção contra dupla drenagem fica no corpo (um segundo `decode()` ou uma
segunda iteração lança `StateError` no primeiro passo). Um gerador abandonado
no meio (cancelamento) não roda `finally`; o filtro nativo do zlib é liberado
pelo GC, o que é aceitável porque o abandono é raro e o filtro é pequeno.

### 4.1 Falha de entrada não é fatal

[09](../09-erros-diagnosticos.md) §2 diz que `EpubContainerException` é fatal
em `open`. Depois de `open`, ela é **falha de uma entrada**: `fetch` ou
`decode()` a lançam com `href` da entrada, e quem chama (sub-projetos 2 e 4)
converte em seção placeholder com o diagnóstico novo `resourceUnreadable`
(`warning`, `details: {reason, exception}`). Só é fatal quando a entrada é o
`container.xml` ou o OPF, decisão do sub-projeto 2. A linha de 09 §2 é
atualizada para dizer isso.

## 5. `ZipContainer`

```dart
static Future<ZipContainer> open(EpubByteSource source,
    {required DiagnosticSink sink});
```

`strict` vive só no `DiagnosticSink` (§8), que é do chamador e é o mesmo que as
camadas de cima vão usar, para o agregado de 09 §3.1 ser um só. Qualquer
exceção da fonte durante `open` (`FileSystemException`, `RangeError`) vira
`EpubContainerException(cause: e)`.

### 5.1 Fim do arquivo e central directory

1. Lê os últimos `min(tamanho, 65 557 + 20)` bytes numa `readRange` e procura a
   assinatura do EOCD (`0x06054b50`) de trás para frente. Um candidato só vale
   se `pos + 22 + commentLength == fim do bloco lido`; senão, continua
   procurando (a assinatura pode aparecer dentro do comentário).
2. Com o locator ZIP64 (`0x07064b50`) nos 20 bytes antes do EOCD, lê o EOCD64
   (`0x06064b50`) e usa os valores dele. "Total de discos" do locator aceita 0
   ou 1. Campos `0xFFFF`/`0xFFFFFFFF` nas entradas vêm do extra field `0x0001`,
   na ordem da especificação (original, comprimido, offset, disco).
3. **Prefixo** (EPUB colado depois de outro arquivo): `delta = posEOCD −
   cdSize − cdOffset`. Com `delta > 0`, todos os offsets recebem `+ delta` e
   emite `mimetypeIrregular` (`details: {reason: 'prefix', delta}`). `delta <
   0` é fatal.
4. Lê o central directory inteiro numa `readRange` e o percorre **por
   `cdSize`**, não pela contagem de entradas (que dá a volta acima de 65 535
   sem ZIP64); contagem divergente não é fatal.
5. **Nomes:** com o bit 11 da flag, `utf8.decode(allowMalformed: true)`; sem
   ele, UTF-8 se os bytes forem UTF-8 válido, senão CP437 pela tabela. O nome
   indexado troca `\` por `/` e remove `/` e `./` iniciais; o nome cru fica em
   `ZipEntry.rawName`. Nomes terminados em `/` são diretórios: ficam fora de
   `paths` e do índice.
6. **Duplicatas:** vence a primeira entrada em ordem de central directory; as
   seguintes emitem `zipDuplicateEntry` (`info`, novo). No índice sem
   diferenciar maiúsculas, também vence a primeira.
7. **Validação por entrada:** `localHeaderOffset < tamanho`, `localHeaderOffset
   + 30 + compressedSize ≤ tamanho` e `uncompressedSize ≤ maxEntrySize`. Entrada
   que falha é mantida no índice como inválida: `fetch` dela lança
   `EpubContainerException(href)` com o motivo. Valores u64 acima de 2^53
   (inteiro seguro também no dart2js) contam como fora de limite.
8. **Criptografia do ZIP:** entrada com o bit 0 da flag ligado lança, na
   abertura, `EpubEncryptedException(scheme: 'zip-encryption')`.
9. **Fatal** (`EpubContainerException`): EOCD não encontrado; central directory
   que não cabe no arquivo; assinatura de entrada do central directory errada;
   `delta < 0`; disco múltiplo (disco do EOCD ou do CD diferente de 0).

`ZipEntry`: `name` (normalizado), `rawName`, `flags`, `method`,
`compressedSize`, `uncompressedSize`, `localHeaderOffset` (já com `delta`),
`crc32`, `invalidReason` (`String?`).

### 5.2 `mimetype`

"Primeira entrada" é a de menor `localHeaderOffset`, que precisa ser 0 (depois
do `delta`). Se não for a primeira, não estiver em `stored`, o conteúdo não for
exatamente `application/epub+zip`, a entrada faltar ou não puder ser lida,
emite `mimetypeIrregular` (`info`; o motivo em `details.reason`). Nunca fatal.
Em `strict`, o sink promove a `warning` (09 §5).

### 5.3 `fetch`

- Busca exata no índice; senão, no índice sem diferenciar maiúsculas, emitindo
  `pathCaseMismatch` (`info`, `href` = caminho pedido, `details: {actual}`).
- Entrada inválida (§5.1 item 7): `EpubContainerException(href)`.
- Uma `readRange` de `min(30 + nomeCD + compressedSize + 1024, tamanho −
  offset)` a partir do local header. Se o local header declarar nome + extra
  que não cabem no que foi lido, faz uma segunda `readRange` só com os dados.
- Assinatura do local header (`0x04034b50`) errada: `EpubContainerException`.
- **Data descriptor** (bit 3): os tamanhos e o CRC do local header podem estar
  zerados; valem sempre os do central directory.
- Método 0 (stored) e 8 (deflate); qualquer outro: `EpubContainerException`.

### 5.4 `decode()`

Regras, em qualquer modo:

- A entrada comprimida é passada ao decoder em fatias de **16 KiB** no máximo.
- A saída **nunca** passa de `uncompressedSize`: byte excedente interrompe o
  inflate na hora e lança `EpubContainerException(href)` (zip bomb ou
  metadado mentiroso).
- Saída **menor** que `uncompressedSize`, ou stream deflate que termina antes
  do fim dos dados: diagnóstico `zipCrcMismatch` com `details: {reason:
  'size', expected, actual}` e os bytes curtos são entregues. Stream deflate
  inválido (erro do decoder): `EpubContainerException(href)`.
- CRC-32 incremental sobre a saída. Divergência: `zipCrcMismatch` (`warning`,
  `details: {reason: 'crc', expected, actual}`).
- Em `strict`, `zipCrcMismatch` é `warning` e o sink lança
  `EpubContainerException(href)`.

Passos (`yield`): um a cada 64 KiB (65 536 bytes) **completos** de saída, e
mais um ao terminar, depois do CRC. Vale para deflate e para stored (no stored,
o passo é o CRC de cada 64 KiB). Entrada vazia: 1 passo; 100 KiB: 2; exatamente
1 MiB: 16 + 1 = 17.

## 6. `encryption.xml`, DRM e fontes

Na abertura do `ZipContainer`, depois do central directory e nesta ordem:

| Sinal | Resultado |
|---|---|
| `META-INF/license.lcpl` presente | `EpubEncryptedException(scheme: 'lcp')` |
| `META-INF/rights.xml` presente com namespace `http://ns.adobe.com/adept` | `EpubEncryptedException(scheme: 'adobe-adept')` |
| `META-INF/rights.xml` presente e ilegível ou sem namespace conhecido | `EpubEncryptedException(scheme: 'unknown:rights.xml')` |
| `encryption.xml` que não é XML válido | `EpubEncryptedException(scheme: 'unknown:encryption.xml-invalido')` — sem como provar que não há DRM, falha com honestidade (é a quinta condição fatal de 09 §1) |
| `KeyInfo/RetrievalMethod` com `Type` `http://readium.org/2014/01/lcp#EncryptedContentKey` | `EpubEncryptedException(scheme: 'lcp')` |
| `KeyInfo` com namespace `http://ns.adobe.com/adept` | `EpubEncryptedException(scheme: 'adobe-adept')` |
| `EncryptedData` com algoritmo que não é de ofuscação de fonte, sobre caminho que não é fonte | `EpubEncryptedException(scheme: 'unknown:<uri>')`, com o primeiro URI em ordem de documento |
| Algoritmo de ofuscação (IDPF ou Adobe) sobre caminho que não é fonte | idem, `unknown:<uri>` |
| IDPF (`http://www.idpf.org/2008/embedding`) sobre fonte | `obfuscationOf(path) == FontObfuscation.idpf` |
| Adobe (`http://ns.adobe.com/pdf/enc#RC`) sobre fonte | `obfuscationOf(path) == FontObfuscation.adobe` |
| Algoritmo desconhecido (ou `EncryptionMethod` ausente, tratado como `''`) só sobre fontes | `FontObfuscation.unknown` + `fontObfuscationUnknown` (`warning`) |
| `EncryptedData` sem `CipherReference` | Ignorado |

- **É fonte** quando a extensão, sem diferenciar maiúsculas, é `.ttf`, `.otf`,
  `.ttc`, `.otc`, `.woff` ou `.woff2`. A conferência pelo `media-type` do
  manifest é do sub-projeto 2.
- O XML é lido por **nome local e namespace**, não pelo prefixo.
- O `CipherReference URI` passa por decodificação de `%xx` tolerante (mantém o
  texto cru se a decodificação falhar) e pela mesma normalização de nome de
  §5.1 item 5, e casa com a entrada pelo mesmo índice de `fetch`. É o único
  ponto do contêiner que normaliza um caminho, porque ele vem do próprio
  contêiner.

### 6.1 Desofuscação

```dart
/// null se não houver identificador utilizável para o algoritmo.
/// ArgumentError para FontObfuscation.unknown.
Uint8List? deobfuscateFont(
  Uint8List bytes,
  FontObfuscation kind, {
  required List<String> uniqueIdentifiers, // IDPF
  required List<String> identifiers,       // todos os dc:identifier, em ordem (Adobe)
});

/// Magic de fonte conhecido: 00010000, OTTO, true, ttcf, wOFF, wOF2.
bool looksLikeFont(Uint8List bytes);
```

- IDPF: XOR dos primeiros 1040 bytes com o SHA-1 da concatenação de
  `uniqueIdentifiers` sem espaço, CR, LF e TAB. Lista vazia → `null`.
- Adobe: XOR dos primeiros 1024 bytes com os 16 bytes do primeiro de
  `identifiers` que for `urn:uuid:` (prefixo sem diferenciar maiúsculas) ou 32
  dígitos hex, sem hifens. Nenhum → `null`.
- Quem chama (Camada B) ignora a fonte quando o resultado é `null` ou
  `looksLikeFont` é falso, emitindo `fontObfuscationUnknown` com
  `details.reason`.
- Código e vetores vêm do spike S6 (`test/spike/support/s6_font_obfuscation.dart`,
  `sha1.dart`).

### 6.2 `ProviderContainer`

```dart
static Future<ProviderContainer> open(EpubResourceProvider provider,
    {required DiagnosticSink sink});
```

- `paths` é vazio (o provider não lista); `exists` delega a
  `provider.exists`.
- `fetch` chama `provider.exists` e `provider.read`; o `decode()` tem um passo,
  sem CRC. Exceção do provider vira `EpubContainerException(href, cause: e)`.
- Busca sem diferenciar maiúsculas não se aplica (o provider é a autoridade).
- **Nunca** trata `encryption.xml` como fatal, nem LCP ou ADEPT (o provider já
  decifrou, 09 §4). Se `encryption.xml` existir, lê só as entradas de
  ofuscação sobre fontes, com a mesma tabela de §6 para `idpf`, `adobe` e
  `unknown`. XML inválido emite `encryptionIgnored` (`info`, novo, `details:
  {reason}`), e `obfuscationOf` devolve `null` para todo caminho.
- Sem `mimetype` nem CRC.

## 7. Documentos a atualizar

- [03](../03-camada-a-ir.md) §2.2: CRC sempre verificado; uma ida à fonte por
  `fetch`; `fetch`/`decode()`; `maxEntrySize`; prefixo; duplicatas; nomes.
  §3.2: o diagnóstico da diferença de caixa é `pathCaseMismatch`.
- [07](../07-api-publica.md) §1: `FileEpubByteSource(path)`.
- [08](../08-concorrencia-cache.md) §1 e §3: tarefa com prólogo assíncrono
  (busca de bytes) e corpo `sync*`; checkpoint de inflate a cada 64 KiB, também
  no CRC de entrada stored.
- [09](../09-erros-diagnosticos.md) §1: a quinta condição fatal inclui
  `encryption.xml` ilegível e ZIP com criptografia própria. §2:
  `EpubContainerException` fatal em `open`, por entrada depois disso (§4.1).
  §3: códigos novos `pathCaseMismatch`, `zipDuplicateEntry`,
  `resourceUnreadable` e `encryptionIgnored`; `mimetypeIrregular` cobre
  ausência, conteúdo errado e prefixo; `zipCrcMismatch` sempre verificado, com
  `reason` `crc` ou `size`. §4: detecção de LCP e ADEPT por arquivo de licença
  e por `KeyInfo`.
- [11](../11-empacotamento-versionamento.md) §4: `lib/src/diagnostics/`,
  `test/container/`, `test/diagnostics/`.
- `test/corpus/corpus_test.dart`: `knownDiagnostics` ganha os códigos novos.
- [14](../14-pendencias.md): chave NFC no índice de nomes (sub-projeto 4);
  `tool/corpus/lib/hashes.dart` duplica CRC-32 e SHA-1 do pacote; o
  `inflate_web_test` só roda quando existir o job web; regenerar baselines com
  os casos novos de §10 depois do merge.

## 8. Exceções e diagnósticos

```dart
abstract base class EpubException implements Exception {
  EpubException(this.message, {this.href, this.cause});
  final String message;
  final String? href;
  /// Exceção embrulhada (FormatException, XmlException, FileSystemException).
  final Object? cause;
  /// "<Tipo>(<href>): <message>", ou "<Tipo>: <message>" sem href.
  @override
  String toString();
}

final class EpubContainerException extends EpubException { ... }

final class EpubEncryptedException extends EpubException {
  /// 'lcp', 'adobe-adept', 'zip-encryption' ou 'unknown:<detalhe>'.
  final String scheme;
}
```

As demais exceções de [09](../09-erros-diagnosticos.md) §2 entram nos
sub-projetos que as lançam.

```dart
enum EpubSeverity { info, warning }

final class EpubDiagnosticCode {
  const EpubDiagnosticCode._(this.name, this.defaultSeverity);
  final String name;
  final EpubSeverity defaultSeverity;

  static const mimetypeIrregular = ...info;
  static const zipCrcMismatch = ...warning;
  static const zipDuplicateEntry = ...info;
  static const pathCaseMismatch = ...info;
  static const fontObfuscationUnknown = ...warning;
  static const encryptionIgnored = ...info;
  static const resourceUnreadable = ...warning;   // emitido pelos sub-projetos 2 e 4
}

final class EpubDiagnostic {  // imutável; details é unmodifiable
  final EpubDiagnosticCode code;
  final EpubSeverity severity;
  final String? href;
  final int? charOffset;
  final String message;
  final Map<String, Object?> details;
}

final class DiagnosticSink {
  DiagnosticSink({this.strict = false});
  final bool strict;
  void emit(EpubDiagnosticCode code, {String? href, required String message,
      Map<String, Object?> details = const {}, EpubSeverity? severity,
      EpubException Function(String message)? onStrict});
  List<EpubDiagnostic> get diagnostics;  // em ordem de primeira emissão
}
```

- `emit` deduplica por `(code, href)`: a repetição **substitui** a instância
  por uma com `details['count']` incrementado (começa em 1).
- Com `strict: true`, `mimetypeIrregular` é promovido a `warning`, e todo
  diagnóstico `warning` é **registrado e depois** lançado como a exceção de
  `onStrict` (padrão: `EpubContainerException`), com o nome do código na
  mensagem. `info` nunca lança.

## 9. Testes

`test/container/support/` monta ZIPs com o `ZipWriter` de
`tool/corpus/lib/zip_writer.dart` e ajusta bytes quando ele não cobre o caso:
comentário no EOCD (inclusive com a assinatura do EOCD dentro dele); disco
múltiplo; data descriptor com local header zerado; entrada duplicada; nome em
CP437 e em UTF-8 sem o bit 11; nome com `\`, `/` ou `./` inicial; diretório
como entrada; método 12; bit 0 ligado; extra field grande no local header;
`uncompressedSize` gigante; saída maior e menor que a declarada; deflate
truncado; offset além do fim; prefixo antes do ZIP; central directory
truncado. Também uma fonte que **conta chamadas e bytes** lidos.

| Arquivo | O que cobre |
|---|---|
| `byte_source_test.dart` | `Memory` e `File`: leitura; faixas inválidas (`RangeError`); leitura depois de `close` (`StateError`); `close` idempotente; 50 `readRange` concorrentes com `Future.wait`, conteúdo de cada uma conferido; `close` durante uma leitura; arquivo inexistente |
| `central_directory_test.dart` | EOCD simples, com comentário e com assinatura falsa no comentário; ZIP64 com locator; prefixo; nomes (CP437, UTF-8 sem bit 11, bit 11 malformado, normalização); diretórios fora de `paths`; duplicatas; validação por entrada; contagem divergente; fatais de §5.1 item 9 |
| `zip_container_test.dart` | `fetch` stored e deflate; uma `readRange` por `fetch` e duas com extra field grande; data descriptor; método 12; bit 0 na abertura; busca sem diferenciar maiúsculas com `pathCaseMismatch`; `mimetype` nos cinco casos; `close` fecha a fonte |
| `inflate_test.dart` | contagem exata de passos (0 B, 100 KiB, 1 MiB, stored e deflate); fatias de 16 KiB; saída maior que a declarada lança; menor dá `zipCrcMismatch` (`size`); CRC errado → `warning` e, em `strict`, exceção; deflate inválido lança; dupla drenagem; `bytes` antes e depois de exceção |
| `encryption_test.dart` | cada linha da tabela de §6; extensão em maiúsculas; `%xx` inválido; prefixo de namespace diferente |
| `font_obfuscation_test.dart` | 6 vetores de SHA-1; ida e volta IDPF e Adobe; identificadores vazios → `null`; Adobe com UUID em qualquer posição; `unknown` lança; as fontes dos casos `fonte-ofuscada-idpf` e `fonte-ofuscada-adobe` do corpus desofuscadas passam em `looksLikeFont` |
| `provider_container_test.dart` | leitura, ausência, exceção do provider embrulhada, LCP e `encryption.xml` nunca fatais, `obfuscationOf`, XML inválido com `encryptionIgnored`, `close` fecha o provider |
| `../diagnostics/diagnostic_test.dart` | dedupe com `count` e substituição; `strict` registra e lança em `warning`; `info` nunca lança; promoção do `mimetypeIrregular`; `toString` com e sem `href`; `cause` |
| `container_corpus_test.dart` | os 65 EPUBs (§9.1) |
| `inflate_web_test.dart` | só `--platform chrome` (pulado na VM): o stub lança `UnsupportedError` com a mensagem esperada |

### 9.1 Teste de corpus

Códigos "do contêiner": `mimetypeIrregular`, `zipCrcMismatch`,
`zipDuplicateEntry`, `pathCaseMismatch`, `fontObfuscationUnknown`.

- **Modo**, como em [10](../10-testes.md) §5: `strict: true` em todos os
  grupos exceto `patologia/` e `faixa-b/`, que rodam com `strict: false`.
- Quando `exception.expected` é `EpubContainerException` ou
  `EpubEncryptedException`, `ZipContainer.open` lança exatamente esse tipo. Em
  todos os outros casos (inclusive `EpubPackageException`, que é da
  Publicação), abre.
- Nos que abrem: `fetch` + drenar `decode()` de todo caminho de `paths`.
- O **conjunto** de nomes de códigos do contêiner emitidos é igual ao conjunto
  dos códigos do contêiner em `diagnostics.expected` (que não tem repetição).
- Nos casos de `patologia/` com código `warning` do contêiner esperado, abrir e
  ler de novo com `strict: true` e esperar a exceção.
- **Nada de arquivo inteiro:** com a fonte que conta bytes, a abertura lê no
  máximo `65 577 + tamanho do EOCD64 + cdSize + tamanho do mimetype +
  encryption.xml + rights.xml` (mais o que for lido da licença LCP), e cada
  `fetch` no máximo `30 + nome + compressedSize + 1024` (mais nome + extra na
  segunda leitura).

## 10. Desempenho

Casos novos no harness (`test/perf/perf_test.dart`):

| id | O que mede |
|---|---|
| `zip.open.800` | `ZipContainer.open` sobre `test/corpus/estrutura/spine-800-itens/book.epub` com `MemoryEpubByteSource` (central directory grande) |
| `zip.fetch.inflate.1mb` | `fetch` + drenar `decode()` de uma entrada deflate de 1 MiB, com CRC e fatias de 16 KiB; comparado ao `zlib.inflate.1mb`, dá o custo do CRC e do chunking |
| `font.deobfuscate.idpf` | `deobfuscateFont` IDPF sobre 64 KiB (chave + XOR) |

Casos curtos recebem `innerIterations` para ~5 ms por amostra, como os
existentes. Depois do merge, o `perf-baseline` é disparado para regenerar os
baselines por CPU com os casos novos; até lá eles aparecem como "novo, sem
baseline" e não falham.
