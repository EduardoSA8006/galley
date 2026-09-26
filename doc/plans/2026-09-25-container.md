# Contêiner (Fase 1, sub-projeto 1) — plano de implementação

> **Para agentes:** SUB-SKILL OBRIGATÓRIA: use superpowers:subagent-driven-development
> (recomendado) ou superpowers:executing-plans para executar tarefa por tarefa. Os
> passos usam checkbox (`- [ ]`).

**Objetivo:** ler recursos de um EPUB a partir de um `.epub` (ZIP) ou de um
`EpubResourceProvider`, com detecção de DRM, desofuscação de fontes, limites
contra arquivo hostil e o canal de exceções e diagnósticos que as camadas de
cima vão usar, sem nunca carregar o arquivo inteiro na memória.

**Arquitetura:** interface interna `EpubContainer` com duas implementações
(`ZipContainer` sobre um `EpubByteSource` lido por faixas; `ProviderContainer`
sobre o provider do app). `fetch` é assíncrono e faz uma ida à fonte;
`PendingResource.decode()` é `sync*`, infla em fatias de 16 KiB, confere o
CRC-32 e dá um passo a cada 64 KiB. Diagnósticos passam por um
`DiagnosticSink` do chamador, que deduplica e, em `strict`, lança. `dart:io`
só entra por import condicional (`*_io.dart`); no web, o inflate e o
`FileEpubByteSource` são stubs que compilam e falham com mensagem clara.

**Stack:** Flutter 3.47.0 (Dart 3.13), `dart:io` (`ZLibDecoder(raw: true)` em
modo chunked, `RandomAccessFile`), `package:xml` 7.0.1, `package:meta`,
`flutter_test`. Nada novo no `pubspec.yaml`.

**Spec:** `doc/specs/2026-09-25-container-design.md`. Leia inteira antes de
começar; este plano argumenta a partir dela.

## Restrições globais

- Dart `^3.13.0`, Flutter `>=3.47.0`. Nenhuma dependência nova (só `html`,
  `xml` e `meta`, spec §1.1), nem de desenvolvimento.
- A preferência global por feature-first, MVVM, Result e Riverpod **não** vale
  aqui: é pacote, com erros por exceção e diagnóstico (spec §1.1, doc/11 §4).
- Código em `lib/` nunca importa `tool/` nem `test/`. `dart:io` só em arquivos
  `*_io.dart` de `lib/` (import condicional); o teste da Tarefa 10 confere.
- Testes importam `lib/` por `package:galley/...` (inclusive `src/`). Arquivo de
  teste que importa `tool/` por caminho relativo leva, antes dos imports:
  `// ignore_for_file: avoid_relative_lib_imports — tool/ não é pacote; importar por caminho é intencional.`
- `analysis_options.yaml` tem `strict-casts`, `strict-inference`,
  `strict-raw-types`, `prefer_final_locals`, `prefer_const_constructors` e
  `unawaited_futures`: todo passo termina com `flutter analyze` limpo.
- `maxEntrySize = 256 * 1024 * 1024`; fatias de inflate de 16 KiB (16 384);
  passo de decode a cada 65 536 bytes completos; leitura do fim de
  `min(tamanho, 65 557 + 20)` bytes.
- Nomes dos diagnósticos exatamente como na spec §8: `mimetypeIrregular`,
  `zipCrcMismatch`, `zipDuplicateEntry`, `pathCaseMismatch`,
  `fontObfuscationUnknown`, `encryptionIgnored`, `resourceUnreadable`.
- Esquemas de `EpubEncryptedException.scheme`: `lcp`, `adobe-adept`,
  `zip-encryption`, `unknown:<detalhe>` (inclusive `unknown:rights.xml` e
  `unknown:encryption.xml-invalido`).
- Os arquivos do spike S6 (`test/spike/`) ficam como estão: são o registro do
  spike. O código de produção é uma cópia revisada em `lib/src/container/`.
- Texto em português brasileiro com acentuação; identificadores em inglês.
- Shell com alias interativo: use `\cp -f`, `\mv -f`, `\rm -rf` (o `cp` puro
  pede confirmação e trava comando não interativo); `ls` é `eza`.
- Nenhum arquivo de depuração versionado; rascunhos no scratchpad da sessão.
- Tudo na branch `fase1/container` (já em checkout). Commits
  `feat(container): …`, `test: …`, `docs: …`, `chore: …`.

## O que foi verificado antes de escrever o plano

Todo o código deste plano rodou numa cópia do repositório no scratchpad
(`flutter analyze` limpo, `dart format` sem mudança, `flutter test` inteiro
verde, 569 testes, e o `container_corpus_test` passando nos 65 EPUBs). Depois
de escrito, o próprio plano foi reaplicado tarefa a tarefa sobre uma cópia
limpa do `HEAD` (um script extraiu cada bloco "Criar/Substituir" e cada troca
da Tarefa 12, na ordem): toda tarefa terminou com `dart format` sem mudança,
`flutter analyze` limpo e os testes dela verdes, com as contagens indicadas nos
passos. O que se observou e o código depende:

- `ZLibDecoder(raw: true).startChunkedConversion(sink)` (Dart 3.13.4): a saída
  chega **sincronamente** dentro de `add`/`close`, em pedaços de no máximo
  65 536 bytes. Stream **truncado** não lança: `close()` termina e a saída fica
  curta (60% do stream deu 260 534 de 435 550 bytes). Stream **inválido** lança
  `FormatException: Filter error, bad data` no `add`. Lixo depois do fim do
  stream é ignorado. Exceção lançada pelo `add` do sink de saída atravessa o
  `add` do decoder sem ser embrulhada (a zip bomb de 16 MiB parou em 131 072
  bytes). Por isso o `decode()` não precisa distinguir truncamento de
  invalidez: truncado vira saída curta (`reason: 'size'`), inválido vira
  `EpubContainerException`.
- `RandomAccessFile`: `setPosition(int)`, `readInto(List<int>, [int start, int? end])`,
  `length()` e `close()`, todos `Future`. Sem a fila da Tarefa 2, o teste de 50
  leituras concorrentes falha (verificado trocando a fila por `Future(...)`).
- `package:xml` 7.0.1: o parâmetro é `namespaceUri:` (`namespace:` está
  deprecado); `namespaceUri: '*'` casa por nome local em qualquer namespace;
  `XmlElement.namespaceUri` resolve o namespace padrão herdado; um BOM antes da
  declaração XML é aceito por `XmlDocument.parse`. Erros de parse são
  `XmlException` (`XmlParserException`, `XmlTagException`).
- Dart 3.13 aceita parâmetro nomeado privado com formal inicializador
  (`required this._data` é chamado como `data:`); o lint
  `prefer_initializing_formals` pede essa forma.
- O stub do web compila e lança: `flutter test --platform chrome` com
  `CHROME_EXECUTABLE=/usr/bin/chromium` passou os dois testes de
  `inflate_web_test.dart` (inclusive importar `package:galley/galley.dart` e
  `ZipContainer`).
- Harness de desempenho local (i5-11400H): `zip.open.800` ≈ 0,7 ms por
  abertura, `zip.fetch.inflate.1mb` ≈ 4–5 ms, `font.deobfuscate.idpf` ≈ 13 µs;
  daí os `innerIterations` 10, 1 e 400. Casos sem baseline aparecem como "novo,
  sem baseline" e o `compare.dart` passa.

## Decisões onde a spec é ambígua

1. **Ordem das tarefas.** `central_directory.dart` usa `maxEntrySize`, que mora
   em `container.dart`, que depende do inflate; por isso o inflate e o
   `PendingResource` (Tarefa 4) vêm antes do central directory (Tarefa 5), e o
   apoio de teste nasce mínimo na Tarefa 4 e completo na Tarefa 5 (a tarefa de
   apoio proposta foi dobrada nessas duas).
2. **`unknown:<uri>`** é o URI do **algoritmo** (`EncryptionMethod@Algorithm`,
   `''` se ausente) do primeiro `EncryptedData` ofensor em ordem de documento.
3. **"`KeyInfo` com namespace do ADEPT"**: o próprio `KeyInfo` ou qualquer
   descendente dele no namespace `http://ns.adobe.com/adept`.
4. **Elementos de `encryption.xml`** (`EncryptedData`, `EncryptionMethod`,
   `CipherReference`, `KeyInfo`, `RetrievalMethod`) casam por nome local em
   qualquer namespace. Um `EncryptedData` fora do namespace do xmlenc ainda
   indica cifra, e ignorá-lo mostraria bytes cifrados como texto.
5. **Checagem LCP/ADEPT/não-fonte antes das fontes:** a tabela de §6 é
   aplicada em duas passadas (primeiro tudo que é fatal, em ordem de tabela;
   depois o mapa de fontes e os `fontObfuscationUnknown`), para um livro com DRM
   não emitir aviso de fonte antes de falhar.
6. **`mimetype` "offset 0 depois do delta"**: `localHeaderOffset == delta` (o
   offset guardado já tem o delta somado). Um único `mimetypeIrregular` com
   `href: 'mimetype'` e o primeiro motivo, na ordem `missing`, `notFirst`,
   `compressed`, `unreadable`/`content`; o do prefixo é separado (`href: null`,
   `reason: 'prefix'`).
7. **Saída curta**: só o diagnóstico `reason: 'size'`. O CRC não é comparado,
   porque divergiria sempre e o dedupe por `(code, href)` trocaria o motivo.
8. **Segunda `readRange` do `fetch`**: exatamente `compressedSize` bytes a
   partir do início dos dados. Orçamento do teste de corpus: cada `fetch` lê no
   máximo `30 + nome + compressedSize + 1024`, mais `compressedSize` quando
   houve a segunda leitura; a abertura soma `65 577 + 56 (EOCD64) + cdSize` e o
   teto de `fetch` (com a segunda leitura) de `mimetype`, `encryption.xml` e
   `rights.xml`. `META-INF/license.lcpl` não é lido: a presença basta.
9. **Falha na abertura fecha a fonte** (o `FileEpubByteSource` não pode vazar o
   handle quando `open` lança).
10. **Falha da fonte no `fetch`** vira `EpubContainerException(href, cause)`;
    `fetch`/`exists` depois de `close` do contêiner são `StateError` (erro de
    programação, não de arquivo).
11. **`encryption.xml` ou `rights.xml` ilegível** (entrada inválida, local
    header quebrado, CRC em `strict`) tem o mesmo resultado do XML inválido:
    `unknown:encryption.xml-invalido` e `unknown:rights.xml`.
12. **Provider**: exceção do provider ao ler `encryption.xml` emite
    `encryptionIgnored` com `reason: 'unreadable'` e segue; XML inválido,
    `reason: 'invalid-xml'`. Recurso acima de `maxEntrySize` também é
    `EpubContainerException`, para `PendingResource.size ≤ maxEntrySize` valer
    nas duas implementações.
13. **`EpubException.toString`** usa um `typeName` literal (`@protected`), não
    `runtimeType`, que o dart2js minifica em release.
14. **u64 "acima de 2^53"** é estritamente maior que 2^53 (`readU64` devolve
    `null`). O EOCD64 é procurado no offset do locator e, se a assinatura não
    estiver lá (prefixo), logo antes do locator.
15. **SHA-1**: o comprimento em bits é gravado com `~/ 0x100000000` em vez do
    `>> 32` do spike, que não é seguro no dart2js. O resto é o código do S6.
16. **Detalhes dos diagnósticos**: `zipDuplicateEntry` com `{rawName}`;
    `pathCaseMismatch` com `href` = caminho pedido e `{actual}`;
    `fontObfuscationUnknown` com `{algorithm}`; todos ganham `count`.
17. **`example/pubspec.lock`** já estava modificado no checkout (xml 6.6.1 →
    7.0.1, efeito do bump #7). Entra num commit próprio na Tarefa 1, para o
    `git status` das verificações ficar limpo.

## Foco de revisão

1. **Abertura que falha deixa o arquivo aberto** (EOCD ausente, DRM, CRC em
   `strict`): quem chamou não tem contêiner para fechar e o handle do
   `RandomAccessFile` vaza. Esperado: `ZipContainer.open` fecha a fonte antes de
   relançar. Teste na Tarefa 6 ("abertura que falha fecha a fonte").
2. **Extra field do local header que empurra os dados para além do fim**
   (o central directory passou na validação, mas o local header declara nome +
   extra enormes): esperado `EpubContainerException(href)`, não `RangeError` da
   fonte. Teste na Tarefa 6.
3. **Fonte que falha depois da abertura** (arquivo apagado, fonte fechada por
   baixo, HTTP que cai): esperado `EpubContainerException` com `cause`, nunca a
   exceção crua da fonte. Teste na Tarefa 6.
4. **Comentário do EOCD de tamanho máximo** (65 535 bytes, a fronteira exata da
   leitura do fim): o EOCD ainda tem de ser achado. Teste na Tarefa 5.
5. **`import 'dart:io'` fora de um `*_io.dart`**: a VM não percebe, mas o
   pacote deixa de compilar para o web. Esperado: um teste que varre `lib/` e
   falha. Teste na Tarefa 10.

---

### Tarefa 1: Exceções e diagnósticos

Spec §8. Base de todas as outras tarefas: o `DiagnosticSink` é o único canal
de diagnóstico e o único lugar onde `strict` vive.

**Arquivos:**
- Criar: `lib/src/diagnostics/exceptions.dart`
- Criar: `lib/src/diagnostics/diagnostic.dart`
- Teste: `test/diagnostics/diagnostic_test.dart`
- Commit à parte: `example/pubspec.lock` (já modificado no checkout)

**Interfaces:**
- Consome: nada.
- Produz: `abstract base class EpubException implements Exception { EpubException(String message, {String? href, Object? cause}); final String message; final String? href; final Object? cause; @protected String get typeName; String toString(); }` — `toString` é `"<typeName>(<href>): <message>"` ou `"<typeName>: <message>"`.
- Produz: `final class EpubContainerException extends EpubException { EpubContainerException(String message, {String? href, Object? cause}); }`.
- Produz: `final class EpubEncryptedException extends EpubException { EpubEncryptedException(String message, {required String scheme, String? href, Object? cause}); final String scheme; }`.
- Produz: `enum EpubSeverity { info, warning }`.
- Produz: `final class EpubDiagnosticCode { final String name; final EpubSeverity defaultSeverity; }` com as constantes `mimetypeIrregular` (info), `zipCrcMismatch` (warning), `zipDuplicateEntry` (info), `pathCaseMismatch` (info), `fontObfuscationUnknown` (warning), `encryptionIgnored` (info), `resourceUnreadable` (warning).
- Produz: `final class EpubDiagnostic { EpubDiagnostic({required EpubDiagnosticCode code, required EpubSeverity severity, required String message, String? href, int? charOffset, Map<String, Object?> details = const {}}); }` com `details` unmodifiable.
- Produz: `final class DiagnosticSink { DiagnosticSink({bool strict = false}); final bool strict; List<EpubDiagnostic> get diagnostics; void emit(EpubDiagnosticCode code, {required String message, String? href, Map<String, Object?> details = const {}, EpubSeverity? severity, EpubException Function(String message)? onStrict}); }`. Em `strict`, `onStrict` recebe `"<code.name>: <message>"`; o padrão é `EpubContainerException(msg, href: href)`.

- [ ] **Passo 1: Commit do lock do exemplo**

Run: `git diff --stat example/pubspec.lock`
Expected: `1 file changed, 2 insertions(+), 2 deletions(-)` (xml 6.6.1 → 7.0.1).

```bash
git add example/pubspec.lock
git commit -m "chore(example): pubspec.lock com xml 7.0.1"
```

- [ ] **Passo 2: Escrever o teste que falha**

Criar `test/diagnostics/diagnostic_test.dart`:

```dart
// Exceções e DiagnosticSink (spec do contêiner §8).
import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/diagnostics/diagnostic.dart';
import 'package:galley/src/diagnostics/exceptions.dart';

void main() {
  group('EpubException', () {
    test('toString com e sem href', () {
      expect(
        EpubContainerException('CRC divergente', href: 'a.xhtml').toString(),
        'EpubContainerException(a.xhtml): CRC divergente',
      );
      expect(
        EpubContainerException('EOCD não encontrado').toString(),
        'EpubContainerException: EOCD não encontrado',
      );
      expect(
        EpubEncryptedException('DRM lcp', scheme: 'lcp').toString(),
        'EpubEncryptedException: DRM lcp',
      );
    });

    test('guarda cause e scheme', () {
      const cause = FormatException('ruim');
      final e = EpubEncryptedException(
        'encryption.xml inválido',
        scheme: 'unknown:encryption.xml-invalido',
        cause: cause,
      );
      expect(e.cause, same(cause));
      expect(e.scheme, 'unknown:encryption.xml-invalido');
      expect(e, isA<EpubException>());
    });
  });

  group('EpubDiagnosticCode', () {
    test('sete códigos com a severidade padrão da spec', () {
      final codes = {
        EpubDiagnosticCode.mimetypeIrregular: EpubSeverity.info,
        EpubDiagnosticCode.zipCrcMismatch: EpubSeverity.warning,
        EpubDiagnosticCode.zipDuplicateEntry: EpubSeverity.info,
        EpubDiagnosticCode.pathCaseMismatch: EpubSeverity.info,
        EpubDiagnosticCode.fontObfuscationUnknown: EpubSeverity.warning,
        EpubDiagnosticCode.encryptionIgnored: EpubSeverity.info,
        EpubDiagnosticCode.resourceUnreadable: EpubSeverity.warning,
      };
      for (final MapEntry(key: code, value: severity) in codes.entries) {
        expect(code.defaultSeverity, severity, reason: code.name);
      }
      expect(codes.keys.map((c) => c.name).toSet(), {
        'mimetypeIrregular',
        'zipCrcMismatch',
        'zipDuplicateEntry',
        'pathCaseMismatch',
        'fontObfuscationUnknown',
        'encryptionIgnored',
        'resourceUnreadable',
      });
    });
  });

  group('EpubDiagnostic', () {
    test('details é unmodifiable', () {
      final d = EpubDiagnostic(
        code: EpubDiagnosticCode.pathCaseMismatch,
        severity: EpubSeverity.info,
        message: 'caixa',
        details: {'actual': 'A.xhtml'},
      );
      expect(() => d.details['x'] = 1, throwsUnsupportedError);
    });
  });

  group('DiagnosticSink', () {
    test('primeira emissão tem count 1 e a severidade padrão', () {
      final sink = DiagnosticSink()
        ..emit(
          EpubDiagnosticCode.zipDuplicateEntry,
          href: 'a.xhtml',
          message: 'duplicada',
          details: {'index': 3},
        );
      final d = sink.diagnostics.single;
      expect(d.severity, EpubSeverity.info);
      expect(d.details, {'index': 3, 'count': 1});
    });

    test(
      'dedupe por (code, href): substitui na mesma posição e soma count',
      () {
        final sink = DiagnosticSink()
          ..emit(EpubDiagnosticCode.pathCaseMismatch, href: 'a', message: '1')
          ..emit(EpubDiagnosticCode.zipDuplicateEntry, href: 'a', message: '2')
          ..emit(
            EpubDiagnosticCode.pathCaseMismatch,
            href: 'a',
            message: '3',
            details: {'actual': 'A'},
          )
          ..emit(EpubDiagnosticCode.pathCaseMismatch, href: 'b', message: '4');
        final ds = sink.diagnostics;
        expect(ds.map((d) => d.message), ['3', '2', '4']);
        expect(ds[0].details, {'actual': 'A', 'count': 2});
        expect(ds[2].details['count'], 1);
      },
    );

    test('severity explícita vence a padrão', () {
      final sink = DiagnosticSink()
        ..emit(
          EpubDiagnosticCode.zipDuplicateEntry,
          message: 'x',
          severity: EpubSeverity.warning,
        );
      expect(sink.diagnostics.single.severity, EpubSeverity.warning);
    });

    test('fora de strict, warning não lança', () {
      final sink = DiagnosticSink()
        ..emit(EpubDiagnosticCode.zipCrcMismatch, href: 'a', message: 'crc');
      expect(sink.diagnostics.single.severity, EpubSeverity.warning);
    });

    test(
      'strict registra e depois lança EpubContainerException em warning',
      () {
        final sink = DiagnosticSink(strict: true);
        expect(
          () => sink.emit(
            EpubDiagnosticCode.zipCrcMismatch,
            href: 'a.xhtml',
            message: 'CRC divergente',
          ),
          throwsA(
            isA<EpubContainerException>()
                .having((e) => e.href, 'href', 'a.xhtml')
                .having(
                  (e) => e.message,
                  'message',
                  contains('zipCrcMismatch'),
                ),
          ),
        );
        expect(sink.diagnostics.single.code, EpubDiagnosticCode.zipCrcMismatch);
      },
    );

    test('strict usa onStrict quando informado', () {
      final sink = DiagnosticSink(strict: true);
      expect(
        () => sink.emit(
          EpubDiagnosticCode.fontObfuscationUnknown,
          message: 'fonte',
          onStrict: (m) => EpubEncryptedException(m, scheme: 'teste'),
        ),
        throwsA(
          isA<EpubEncryptedException>().having(
            (e) => e.message,
            'message',
            'fontObfuscationUnknown: fonte',
          ),
        ),
      );
    });

    test('strict: info nunca lança', () {
      final sink = DiagnosticSink(strict: true)
        ..emit(EpubDiagnosticCode.zipDuplicateEntry, message: 'x')
        ..emit(EpubDiagnosticCode.pathCaseMismatch, message: 'y')
        ..emit(EpubDiagnosticCode.encryptionIgnored, message: 'z');
      expect(sink.diagnostics, hasLength(3));
    });

    test('strict promove mimetypeIrregular a warning e lança', () {
      final sink = DiagnosticSink(strict: true);
      expect(
        () => sink.emit(EpubDiagnosticCode.mimetypeIrregular, message: 'm'),
        throwsA(isA<EpubContainerException>()),
      );
      expect(sink.diagnostics.single.severity, EpubSeverity.warning);
      final relaxed = DiagnosticSink()
        ..emit(EpubDiagnosticCode.mimetypeIrregular, message: 'm');
      expect(relaxed.diagnostics.single.severity, EpubSeverity.info);
    });

    test('diagnostics devolvido não altera o sink', () {
      final sink = DiagnosticSink()
        ..emit(EpubDiagnosticCode.zipDuplicateEntry, message: 'x');
      expect(() => sink.diagnostics.clear(), throwsUnsupportedError);
    });
  });
}
```

- [ ] **Passo 3: Rodar e ver falhar**

Run: `flutter test test/diagnostics/diagnostic_test.dart`
Expected: FAIL na compilação, com `Error when reading 'lib/src/diagnostics/diagnostic.dart': No such file or directory`.

- [ ] **Passo 4: Implementar as exceções**

Criar `lib/src/diagnostics/exceptions.dart`:

```dart
/// Exceções do pacote (doc/09 §2). As desta etapa: contêiner e DRM.
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
```

- [ ] **Passo 5: Implementar diagnósticos e o sink**

Criar `lib/src/diagnostics/diagnostic.dart`:

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

- [ ] **Passo 6: Rodar e ver passar**

Run: `flutter test test/diagnostics/diagnostic_test.dart`
Expected: `All tests passed!` (13 testes).

- [ ] **Passo 7: Formatar e analisar**

Run: `dart format lib/src/diagnostics test/diagnostics && flutter analyze`
Expected: `Formatted 3 files (0 changed)` e `No issues found!`.

- [ ] **Passo 8: Commit**

```bash
git add lib/src/diagnostics test/diagnostics
git commit -m "feat(container): exceções do contêiner e DiagnosticSink

EpubException, EpubContainerException e EpubEncryptedException (spec §8),
os sete códigos de diagnóstico desta etapa e o DiagnosticSink com dedupe
por (code, href), count e strict."
```

---

### Tarefa 2: Fontes de bytes

Spec §3. `MemoryEpubByteSource` para web e testes; `FileEpubByteSource` sobre
`RandomAccessFile`, com fila de leituras (a Publicação e a pré-busca chamam
`readRange` ao mesmo tempo, e o `RandomAccessFile` não aceita duas operações
assíncronas simultâneas).

**Arquivos:**
- Criar: `lib/src/container/byte_source.dart`
- Criar: `lib/src/container/resource_provider.dart`
- Criar: `lib/src/io/file_byte_source.dart`
- Criar: `lib/src/io/file_byte_source_io.dart`
- Criar: `lib/src/io/file_byte_source_stub.dart`
- Teste: `test/container/byte_source_test.dart`

**Interfaces:**
- Consome: nada.
- Produz: `abstract interface class EpubByteSource { Future<int> get length; Future<Uint8List> readRange(int offset, int length); Future<void> close(); }`.
- Produz: `final class MemoryEpubByteSource implements EpubByteSource { MemoryEpubByteSource(Uint8List bytes); }` (`readRange` devolve view).
- Produz: `void checkRange(int offset, int length, int size)` — `RangeError` para faixa inválida.
- Produz: `final class FileEpubByteSource implements EpubByteSource { FileEpubByteSource(String path); final String path; }`, importado de `package:galley/src/io/file_byte_source.dart` (condicional: `_io` no nativo, `_stub` no web, cujo construtor lança `UnsupportedError`).
- Produz: `abstract interface class EpubResourceProvider { Future<Uint8List> read(String href); Future<bool> exists(String href); Future<void> close(); }`.

- [ ] **Passo 1: Escrever o teste que falha**

Criar `test/container/byte_source_test.dart`:

```dart
// MemoryEpubByteSource e FileEpubByteSource (spec do contêiner §3).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/container/byte_source.dart';
import 'package:galley/src/io/file_byte_source.dart';

Uint8List _pattern(int n) =>
    Uint8List.fromList(List<int>.generate(n, (i) => (i * 7 + 3) & 0xFF));

void main() {
  final data = _pattern(200 * 1024);
  late Directory tmp;
  late String path;

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('galley_byte_source_');
    path = '${tmp.path}/book.epub';
    File(path).writeAsBytesSync(data);
  });

  tearDownAll(() => tmp.deleteSync(recursive: true));

  final factories = <String, EpubByteSource Function()>{
    'Memory': () => MemoryEpubByteSource(data),
    'File': () => FileEpubByteSource(path),
  };

  for (final MapEntry(key: name, value: create) in factories.entries) {
    group(name, () {
      test('length e leitura', () async {
        final s = create();
        expect(await s.length, data.length);
        expect(await s.readRange(0, 4), data.sublist(0, 4));
        expect(
          await s.readRange(data.length - 10, 10),
          data.sublist(data.length - 10),
        );
        expect(await s.readRange(100, 0), isEmpty);
        await s.close();
      });

      test('faixas inválidas lançam RangeError', () async {
        final s = create();
        await expectLater(s.readRange(-1, 4), throwsRangeError);
        await expectLater(s.readRange(0, -1), throwsRangeError);
        await expectLater(s.readRange(data.length - 3, 4), throwsRangeError);
        // A fonte continua utilizável depois do erro.
        expect(await s.readRange(0, 2), data.sublist(0, 2));
        await s.close();
      });

      test(
        'leitura depois de close lança StateError; close idempotente',
        () async {
          final s = create();
          await s.readRange(0, 1);
          await s.close();
          await s.close();
          await expectLater(s.readRange(0, 1), throwsStateError);
          await expectLater(s.length, throwsStateError);
        },
      );

      test('50 readRange concorrentes devolvem cada faixa certa', () async {
        final s = create();
        final offsets = List<int>.generate(50, (i) => (i * 3989) % 150000);
        final results = await Future.wait([
          for (final o in offsets) s.readRange(o, 4096 + o % 1000),
        ]);
        for (var i = 0; i < offsets.length; i++) {
          final o = offsets[i];
          expect(
            results[i],
            data.sublist(o, o + 4096 + o % 1000),
            reason: 'offset $o',
          );
        }
        await s.close();
      });

      test(
        'close durante uma leitura: a leitura termina, as novas falham',
        () async {
          final s = create();
          final pending = s.readRange(1000, 50000);
          final closing = s.close();
          expect(await pending, data.sublist(1000, 51000));
          await closing;
          await expectLater(s.readRange(0, 1), throwsStateError);
        },
      );
    });
  }

  group('File', () {
    test('path é o caminho recebido', () {
      expect(FileEpubByteSource(path).path, path);
    });

    test(
      'arquivo inexistente lança FileSystemException na primeira leitura',
      () async {
        final s = FileEpubByteSource('${tmp.path}/nao-existe.epub');
        await expectLater(s.length, throwsA(isA<FileSystemException>()));
        await expectLater(
          s.readRange(0, 1),
          throwsA(isA<FileSystemException>()),
        );
        await s.close();
      },
    );

    test('arquivo inexistente: close sem leitura não lança', () async {
      await FileEpubByteSource('${tmp.path}/nao-existe.epub').close();
    });
  });
}
```

- [ ] **Passo 2: Rodar e ver falhar**

Run: `flutter test test/container/byte_source_test.dart`
Expected: FAIL na compilação, com `Error when reading 'lib/src/container/byte_source.dart'`.

- [ ] **Passo 3: Interface e fonte em memória**

Criar `lib/src/container/byte_source.dart`:

```dart
/// Fonte de bytes do `.epub` (doc/03 §2.1, Emenda 8).
library;

import 'dart:typed_data';

/// Acesso aleatório ao arquivo. Implementável pelo app (HTTP com `Range`,
/// armazenamento próprio).
abstract interface class EpubByteSource {
  /// Tamanho total em bytes.
  Future<int> get length;

  /// Exatamente [length] bytes a partir de [offset]. O resultado pode ser uma
  /// view: quem chama não altera o conteúdo.
  ///
  /// [RangeError] se `offset < 0`, `length < 0` ou `offset + length` passa do
  /// tamanho. [StateError] depois de [close].
  Future<Uint8List> readRange(int offset, int length);

  /// Idempotente.
  Future<void> close();
}

/// Fonte sobre bytes já em memória (web e testes).
final class MemoryEpubByteSource implements EpubByteSource {
  MemoryEpubByteSource(Uint8List bytes) : _bytes = bytes;

  final Uint8List _bytes;
  bool _closed = false;

  @override
  Future<int> get length async {
    _checkOpen();
    return _bytes.length;
  }

  @override
  Future<Uint8List> readRange(int offset, int length) async {
    _checkOpen();
    checkRange(offset, length, _bytes.length);
    return Uint8List.sublistView(_bytes, offset, offset + length);
  }

  @override
  Future<void> close() async => _closed = true;

  void _checkOpen() {
    if (_closed) throw StateError('MemoryEpubByteSource fechada');
  }
}

/// Validação comum de `readRange`.
void checkRange(int offset, int length, int size) {
  if (offset < 0) throw RangeError.value(offset, 'offset', 'negativo');
  if (length < 0) throw RangeError.value(length, 'length', 'negativo');
  if (offset + length > size) {
    throw RangeError(
      'faixa $offset+$length passa do fim da fonte ($size bytes)',
    );
  }
}
```

Criar `lib/src/container/resource_provider.dart`:

```dart
/// Recursos servidos pelo app, sem ZIP (doc/07 §4).
library;

import 'dart:typed_data';

/// O app entrega os bytes já claros (decifrados, se houver DRM). Caminhos
/// relativos à raiz do contêiner, normalizados pela Publicação.
abstract interface class EpubResourceProvider {
  Future<Uint8List> read(String href);
  Future<bool> exists(String href);
  Future<void> close();
}
```

- [ ] **Passo 4: Fonte em arquivo, por import condicional**

Criar `lib/src/io/file_byte_source.dart`:

```dart
/// `FileEpubByteSource` por import condicional: `dart:io` no nativo, stub no
/// web.
library;

export 'file_byte_source_stub.dart'
    if (dart.library.io) 'file_byte_source_io.dart';
```

Criar `lib/src/io/file_byte_source_io.dart`. A fila é uma cadeia de `Future`:
cada operação espera a anterior (`_tail`), e o erro de uma não contamina a
seguinte (`onError` vazio só na cadeia, não no resultado entregue a quem
chamou). O arquivo abre na primeira operação; `close()` marca a fonte como
fechada, espera a cadeia e fecha o handle.

```dart
import 'dart:io';
import 'dart:typed_data';

import '../container/byte_source.dart';

/// Fonte sobre um arquivo local, com um `RandomAccessFile` aberto na primeira
/// leitura.
///
/// O `RandomAccessFile` não aceita duas operações assíncronas ao mesmo tempo,
/// então as leituras entram numa fila e rodam uma de cada vez. Cada
/// [readRange] lê em laço até ter todos os bytes.
final class FileEpubByteSource implements EpubByteSource {
  /// Abre o arquivo na primeira chamada a [length] ou [readRange]; arquivo
  /// inexistente ou ilegível lança [FileSystemException] nesse momento.
  FileEpubByteSource(this.path);

  /// O worker (sub-projeto 5) usa para abrir um segundo handle no isolate.
  final String path;

  Future<RandomAccessFile>? _file;
  int? _size;
  Future<void> _tail = Future<void>.value();
  bool _closed = false;
  Future<void>? _closing;

  @override
  Future<int> get length => _enqueue(_sizeOf);

  @override
  Future<Uint8List> readRange(int offset, int length) => _enqueue((f) async {
    checkRange(offset, length, await _sizeOf(f));
    final out = Uint8List(length);
    await f.setPosition(offset);
    var read = 0;
    while (read < length) {
      final n = await f.readInto(out, read, length);
      if (n == 0) {
        throw FileSystemException(
          'fim de arquivo antes do esperado ($read de $length bytes)',
          path,
        );
      }
      read += n;
    }
    return out;
  });

  @override
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    await _tail;
    final file = _file;
    if (file == null) return;
    try {
      await (await file).close();
    } on FileSystemException {
      // Abertura falhou: não há handle para fechar.
    }
  }

  Future<int> _sizeOf(RandomAccessFile f) async => _size ??= await f.length();

  Future<T> _enqueue<T>(Future<T> Function(RandomAccessFile f) op) {
    if (_closed) {
      return Future.error(StateError('FileEpubByteSource fechada: $path'));
    }
    final result = _tail.then((_) async => op(await (_file ??= _open())));
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<RandomAccessFile> _open() => File(path).open();
}
```

Criar `lib/src/io/file_byte_source_stub.dart`:

```dart
import 'dart:typed_data';

import '../container/byte_source.dart';

/// Web: não há sistema de arquivos. Use [MemoryEpubByteSource] ou uma fonte
/// própria.
final class FileEpubByteSource implements EpubByteSource {
  FileEpubByteSource(this.path) {
    throw UnsupportedError(
      'FileEpubByteSource precisa de dart:io; no web, use '
      'MemoryEpubByteSource ou uma EpubByteSource própria.',
    );
  }

  final String path;

  @override
  Future<int> get length => throw UnimplementedError();

  @override
  Future<Uint8List> readRange(int offset, int length) =>
      throw UnimplementedError();

  @override
  Future<void> close() => throw UnimplementedError();
}
```

- [ ] **Passo 5: Rodar e ver passar**

Run: `flutter test test/container/byte_source_test.dart`
Expected: `All tests passed!` (13 testes).

- [ ] **Passo 6: Conferir que o teste de concorrência pega a falta da fila**

```bash
SP=/tmp/claude-1000/-home-eduardo8006-Documentos-projetos-galley/003640ed-5627-4a8b-81ed-13354cf11bdd/scratchpad
\cp -f lib/src/io/file_byte_source_io.dart $SP/file_byte_source_io.dart.bak
```

Trocar temporariamente, em `lib/src/io/file_byte_source_io.dart`,
`final result = _tail.then((_) async => op(await (_file ??= _open())));` por
`final result = Future(() async => op(await (_file ??= _open())));`.

Run: `flutter test test/container/byte_source_test.dart`
Expected: FAIL (`+12 -1`: "50 readRange concorrentes devolvem cada faixa certa"
do grupo File).

Restaurar e rodar de novo:

```bash
\cp -f $SP/file_byte_source_io.dart.bak lib/src/io/file_byte_source_io.dart
flutter test test/container/byte_source_test.dart
```

Expected: `All tests passed!`.

- [ ] **Passo 7: Formatar e analisar**

Run: `dart format lib/src/container lib/src/io test/container && flutter analyze`
Expected: nada mudado e `No issues found!`.

- [ ] **Passo 8: Commit**

```bash
git add lib/src/container/byte_source.dart lib/src/container/resource_provider.dart lib/src/io test/container/byte_source_test.dart
git commit -m "feat(container): EpubByteSource em memória e em arquivo

FileEpubByteSource por import condicional, com fila de leituras sobre o
RandomAccessFile e leitura em laço; stub no web. EpubResourceProvider
como interface do app (spec §3)."
```

---

### Tarefa 3: Little-endian, CRC-32 e CP437

Spec §2 (arquivos `binary.dart`, `crc32.dart`, `cp437.dart`). `ByteData.getUint64`
não existe no dart2js, então u64 é lido como dois u32 e vira `null` acima de
2^53 (§5.1 item 7).

**Arquivos:**
- Criar: `lib/src/container/zip/binary.dart`
- Criar: `lib/src/container/zip/crc32.dart`
- Criar: `lib/src/container/zip/cp437.dart`
- Teste: `test/container/binary_test.dart`

**Interfaces:**
- Consome: nada.
- Produz: `const int maxSafeInteger = 9007199254740992;` (2^53).
- Produz: `int readU16(Uint8List bytes, int offset)`, `int readU32(Uint8List bytes, int offset)`, `int? readU64(Uint8List bytes, int offset)` (`null` se > 2^53).
- Produz: `final class Crc32 { void add(List<int> data, [int start = 0, int? end]); int get value; }` e `int crc32(List<int> data)`.
- Produz: `String decodeCp437(List<int> bytes)`.

- [ ] **Passo 1: Escrever o teste que falha**

Criar `test/container/binary_test.dart`:

```dart
// Primitivas do leitor de ZIP: little-endian, CRC-32 e CP437.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/container/zip/binary.dart';
import 'package:galley/src/container/zip/cp437.dart';
import 'package:galley/src/container/zip/crc32.dart';

void main() {
  group('binary', () {
    final b = Uint8List.fromList([
      0x34, 0x12, // u16 0x1234
      0x78, 0x56, 0x34, 0x12, // u32 0x12345678
      0xFF, 0xFF, 0xFF, 0xFF, // u32 0xFFFFFFFF
    ]);

    test('u16 e u32 little-endian', () {
      expect(readU16(b, 0), 0x1234);
      expect(readU32(b, 2), 0x12345678);
      expect(readU32(b, 6), 0xFFFFFFFF);
    });

    Uint8List u64(int lo, int hi) => Uint8List(8)
      ..buffer.asByteData().setUint32(0, lo, Endian.little)
      ..buffer.asByteData().setUint32(4, hi, Endian.little);

    test('u64 como dois u32', () {
      expect(readU64(u64(5, 0), 0), 5);
      expect(readU64(u64(0, 1), 0), 0x100000000);
      expect(readU64(u64(0xFFFFFFFF, 0x1FFFFF), 0), maxSafeInteger - 1);
      expect(readU64(u64(0, 0x200000), 0), maxSafeInteger);
    });

    test('u64 acima de 2^53 devolve null', () {
      expect(readU64(u64(1, 0x200000), 0), isNull);
      expect(readU64(u64(0xFFFFFFFF, 0xFFFFFFFF), 0), isNull);
    });
  });

  group('crc32', () {
    test('vetores conhecidos', () {
      expect(crc32(const []), 0);
      expect(crc32(ascii.encode('123456789')), 0xCBF43926);
      expect(
        crc32(ascii.encode('The quick brown fox jumps over the lazy dog')),
        0x414FA339,
      );
    });

    test('incremental em pedaços é igual ao de uma vez', () {
      final data = List<int>.generate(100000, (i) => (i * 31) & 0xFF);
      final c = Crc32();
      for (var i = 0; i < data.length; i += 7777) {
        c.add(data, i, i + 7777 > data.length ? data.length : i + 7777);
      }
      expect(c.value, crc32(data));
    });
  });

  group('cp437', () {
    test('ASCII passa direto; bytes altos pela tabela', () {
      expect(decodeCp437(ascii.encode('OEBPS/a.xhtml')), 'OEBPS/a.xhtml');
      expect(decodeCp437([0x80, 0x87, 0xA4, 0xE1, 0xFF]), 'Ççñß\u00a0');
    });
  });
}
```

- [ ] **Passo 2: Rodar e ver falhar**

Run: `flutter test test/container/binary_test.dart`
Expected: FAIL na compilação, com `Error when reading 'lib/src/container/zip/binary.dart': No such file or directory`.

- [ ] **Passo 3: Implementar**

Criar `lib/src/container/zip/binary.dart`:

```dart
/// Leitura little-endian para o ZIP. Só `getUint16`/`getUint32` e aritmética,
/// porque `ByteData.getUint64` não existe no dart2js.
library;

import 'dart:typed_data';

/// 2^53: acima disso um inteiro deixa de ser exato no dart2js.
const int maxSafeInteger = 9007199254740992;

int readU16(Uint8List bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8);

int readU32(Uint8List bytes, int offset) =>
    ByteData.sublistView(bytes, offset, offset + 4).getUint32(0, Endian.little);

/// u64 como dois u32. `null` quando o valor passa de 2^53 (fora de limite
/// para qualquer arquivo que o pacote aceita).
int? readU64(Uint8List bytes, int offset) {
  final lo = readU32(bytes, offset);
  final hi = readU32(bytes, offset + 4);
  if (hi > 0x200000 || (hi == 0x200000 && lo > 0)) return null;
  return hi * 0x100000000 + lo;
}
```

Criar `lib/src/container/zip/crc32.dart`:

```dart
/// CRC-32 (IEEE 802.3), o do ZIP, por tabela e incremental.
library;

import 'dart:typed_data';

final Uint32List _table = () {
  final table = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
    }
    table[n] = c;
  }
  return table;
}();

/// Acumulador: [add] em pedaços, [value] a qualquer momento.
final class Crc32 {
  int _c = 0xFFFFFFFF;

  void add(List<int> data, [int start = 0, int? end]) {
    final stop = RangeError.checkValidRange(start, end, data.length);
    var c = _c;
    for (var i = start; i < stop; i++) {
      c = _table[(c ^ data[i]) & 0xFF] ^ (c >>> 8);
    }
    _c = c;
  }

  int get value => (_c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// CRC-32 de [data] de uma vez.
int crc32(List<int> data) => (Crc32()..add(data)).value;
```

Criar `lib/src/container/zip/cp437.dart`. A tabela é a do codec `cp437` do
Python (`bytes([i]).decode('cp437')` para 0x80–0xFF); o último caractere é
U+00A0, escrito como escape:

```dart
/// Nomes de entrada sem o bit 11 que não são UTF-8 válido: CP437, a
/// codificação original do PKZIP.
library;

/// Os 128 bytes altos (0x80–0xFF) do CP437, em ordem. Os 128 baixos são
/// ASCII.
const String _high =
    'ÇüéâäàåçêëèïîìÄÅÉæÆôöòûùÿÖÜ¢£¥₧ƒ'
    'áíóúñÑªº¿⌐¬½¼¡«»░▒▓│┤╡╢╖╕╣║╗╝╜╛┐'
    '└┴┬├─┼╞╟╚╔╩╦╠═╬╧╨╤╥╙╘╒╓╫╪┘┌█▄▌▐▀'
    'αßΓπΣσµτΦΘΩδ∞φε∩≡±≥≤⌠⌡÷≈°∙·√ⁿ²■\u00a0';

/// Decodifica [bytes] como CP437.
String decodeCp437(List<int> bytes) {
  final out = StringBuffer();
  for (final b in bytes) {
    out.writeCharCode(b < 0x80 ? b : _high.codeUnitAt(b - 0x80));
  }
  return out.toString();
}
```

- [ ] **Passo 4: Rodar e ver passar**

Run: `flutter test test/container/binary_test.dart`
Expected: `All tests passed!` (6 testes).

- [ ] **Passo 5: Formatar e analisar**

Run: `dart format lib/src/container/zip test/container/binary_test.dart && flutter analyze`
Expected: nada mudado e `No issues found!`.

- [ ] **Passo 6: Commit**

```bash
git add lib/src/container/zip test/container/binary_test.dart
git commit -m "feat(container): leitura little-endian, CRC-32 incremental e CP437

u64 como dois u32, seguro no dart2js, com null acima de 2^53."
```

---

### Tarefa 4: `PendingResource` e inflate chunked

Spec §4 e §5.4. `container.dart` traz a interface `EpubContainer`, o
`PendingResource` com o `decode()` `sync*` e as constantes. O inflate fica
atrás de uma interface (`ChunkedInflater`) para o teste conferir o tamanho das
fatias e para o web receber o stub.

**Arquivos:**
- Criar: `lib/src/container/container.dart`
- Criar: `lib/src/container/inflate/inflate.dart`
- Criar: `lib/src/container/inflate/inflate_io.dart`
- Criar: `lib/src/container/inflate/inflate_stub.dart`
- Criar: `test/container/support/zip_fixtures.dart` (versão mínima; a Tarefa 5 o completa)
- Teste: `test/container/inflate_test.dart`
- Teste: `test/container/inflate_web_test.dart` (só no navegador)

**Interfaces:**
- Consome: `DiagnosticSink`, `EpubDiagnosticCode.zipCrcMismatch`, `EpubContainerException` (Tarefa 1); `Crc32` (Tarefa 3).
- Produz: `const int maxEntrySize = 256 * 1024 * 1024;`, `const int decodeStepBytes = 64 * 1024;`, `const int inflateSliceBytes = 16 * 1024;`.
- Produz: `enum FontObfuscation { idpf, adobe, unknown }`.
- Produz: `abstract interface class EpubContainer { Iterable<String> get paths; Future<bool> exists(String path); Future<PendingResource?> fetch(String path); FontObfuscation? obfuscationOf(String path); Future<void> close(); }`.
- Produz: `final class PendingResource { PendingResource.zip({required String path, required int size, required int method, required Uint8List data, required int crc32, required DiagnosticSink sink, InflaterFactory inflaterFactory = createInflater}); PendingResource.ready({required String path, required Uint8List bytes}); final String path; final int size; Iterable<void> decode(); Uint8List get bytes; }`.
- Produz: `abstract interface class ChunkedInflater { void add(Uint8List chunk); void close(); }`, `typedef InflaterFactory = ChunkedInflater Function(void Function(Uint8List chunk) onOutput);` e `ChunkedInflater createInflater(void Function(Uint8List chunk) onOutput)` (de `inflate.dart`, condicional). No stub, `const String inflateUnsupportedMessage`.
- Produz (teste): `Uint8List prose(int n, {int seed = 1})`, `Uint8List noise(int n, {int seed = 7})` em `test/container/support/zip_fixtures.dart`.

- [ ] **Passo 1: Criar o apoio mínimo de teste**

Criar `test/container/support/zip_fixtures.dart`:

```dart
/// Dados de teste do contêiner. A Tarefa 5 amplia este arquivo com o
/// `ZipWriter` do corpus e os ajustes de bytes.
library;

import 'dart:convert';
import 'dart:typed_data';

/// [n] bytes de texto repetitivo (comprime bem).
Uint8List prose(int n, {int seed = 1}) {
  final words = ['livro', 'página', 'capítulo', 'nota', 'verso', 'texto'];
  final out = BytesBuilder(copy: false);
  var i = seed;
  while (out.length < n) {
    out.add(utf8.encode('${words[i % words.length]}$i '));
    i = (i * 7 + 3) % 10007;
  }
  return Uint8List.sublistView(out.takeBytes(), 0, n);
}

/// [n] bytes pseudoaleatórios (não comprimem).
Uint8List noise(int n, {int seed = 7}) {
  var x = seed;
  return Uint8List.fromList(
    List<int>.generate(n, (_) {
      x = (x * 1103515245 + 12345) & 0x7FFFFFFF;
      return x >> 16 & 0xFF;
    }),
  );
}
```

- [ ] **Passo 2: Escrever o teste que falha**

Criar `test/container/inflate_test.dart`:

```dart
// decode() de PendingResource: passos, fatias, limites e CRC (spec §5.4).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/container/container.dart';
import 'package:galley/src/container/inflate/inflate.dart';
import 'package:galley/src/container/zip/crc32.dart';
import 'package:galley/src/diagnostics/diagnostic.dart';
import 'package:galley/src/diagnostics/exceptions.dart';

import 'support/zip_fixtures.dart';

Uint8List _deflate(List<int> data) =>
    Uint8List.fromList(ZLibCodec(raw: true, level: 6).encode(data));

PendingResource _stored(
  Uint8List data, {
  int? size,
  int? crc,
  DiagnosticSink? sink,
}) => PendingResource.zip(
  path: 'a.bin',
  size: size ?? data.length,
  method: 0,
  data: data,
  crc32: crc ?? crc32(data),
  sink: sink ?? DiagnosticSink(),
);

PendingResource _deflated(
  Uint8List plain, {
  Uint8List? data,
  int? size,
  int? crc,
  DiagnosticSink? sink,
  InflaterFactory inflaterFactory = createInflater,
}) => PendingResource.zip(
  path: 'a.xhtml',
  size: size ?? plain.length,
  method: 8,
  data: data ?? _deflate(plain),
  crc32: crc ?? crc32(plain),
  sink: sink ?? DiagnosticSink(),
  inflaterFactory: inflaterFactory,
);

int _drain(PendingResource r) => r.decode().length;

/// Inflater que registra o tamanho de cada fatia recebida.
final class _Recording implements ChunkedInflater {
  _Recording(this._inner, this.slices);
  final ChunkedInflater _inner;
  final List<int> slices;
  @override
  void add(Uint8List chunk) {
    slices.add(chunk.length);
    _inner.add(chunk);
  }

  @override
  void close() => _inner.close();
}

void main() {
  group('contagem exata de passos', () {
    for (final (label, n, steps) in [
      ('0 B', 0, 1),
      ('100 KiB', 100 * 1024, 2),
      ('1 MiB', 1024 * 1024, 17),
      ('64 KiB - 1', 64 * 1024 - 1, 1),
      ('64 KiB', 64 * 1024, 2),
    ]) {
      test('stored $label: $steps passos', () {
        final data = noise(n);
        final r = _stored(data);
        expect(_drain(r), steps);
        expect(r.bytes, data);
      });

      test('deflate $label: $steps passos', () {
        final plain = prose(n);
        final r = _deflated(plain);
        expect(_drain(r), steps);
        expect(r.bytes, plain);
      });
    }
  });

  test('entrada comprimida vai ao decoder em fatias de até 16 KiB', () {
    final plain = noise(100 * 1024); // não comprime: ~100 KiB de entrada
    final slices = <int>[];
    final r = _deflated(
      plain,
      inflaterFactory: (out) => _Recording(createInflater(out), slices),
    );
    _drain(r);
    expect(r.bytes, plain);
    expect(slices.length, greaterThan(6));
    expect(slices.every((s) => s <= inflateSliceBytes), isTrue);
    expect(
      slices.sublist(0, slices.length - 1),
      everyElement(inflateSliceBytes),
    );
  });

  group('saída maior que a declarada', () {
    test('deflate: lança EpubContainerException sem passar do limite', () {
      final plain = prose(200 * 1024);
      final r = _deflated(plain, size: 100 * 1024);
      expect(
        () => _drain(r),
        throwsA(
          isA<EpubContainerException>()
              .having((e) => e.href, 'href', 'a.xhtml')
              .having((e) => e.message, 'message', contains('maior')),
        ),
      );
      expect(() => r.bytes, throwsStateError);
    });

    test('zip bomb: 16 MiB de zeros declarados como 1 MiB', () {
      final bomb = _deflate(Uint8List(16 * 1024 * 1024));
      final r = _deflated(Uint8List(0), data: bomb, size: 1024 * 1024, crc: 0);
      expect(() => _drain(r), throwsA(isA<EpubContainerException>()));
    });

    test('stored: dados maiores que o declarado lançam', () {
      final data = noise(1000);
      expect(
        () => _drain(_stored(data, size: 999)),
        throwsA(isA<EpubContainerException>()),
      );
    });
  });

  group('saída menor que a declarada', () {
    test('deflate: zipCrcMismatch com reason size e bytes curtos', () {
      final plain = prose(10000);
      final sink = DiagnosticSink();
      final r = _deflated(plain, size: 10100, sink: sink);
      expect(_drain(r), 1);
      expect(r.bytes, plain);
      final d = sink.diagnostics.single;
      expect(d.code, EpubDiagnosticCode.zipCrcMismatch);
      expect(d.severity, EpubSeverity.warning);
      expect(d.href, 'a.xhtml');
      expect(d.details, {
        'reason': 'size',
        'expected': 10100,
        'actual': 10000,
        'count': 1,
      });
    });

    test('deflate truncado: bytes curtos e reason size', () {
      final plain = prose(300 * 1024);
      final full = _deflate(plain);
      final sink = DiagnosticSink();
      final r = _deflated(
        plain,
        data: Uint8List.sublistView(full, 0, full.length ~/ 2),
        sink: sink,
      );
      _drain(r);
      expect(r.bytes.length, lessThan(plain.length));
      expect(r.bytes, plain.sublist(0, r.bytes.length));
      expect(sink.diagnostics.single.details['reason'], 'size');
    });

    test('stored: dados menores que o declarado', () {
      final sink = DiagnosticSink();
      final r = _stored(noise(500), size: 600, sink: sink);
      _drain(r);
      expect(r.bytes, hasLength(500));
      expect(sink.diagnostics.single.details['reason'], 'size');
    });
  });

  group('CRC', () {
    test('divergente: warning com reason crc; bytes entregues', () {
      final plain = prose(5000);
      final sink = DiagnosticSink();
      final r = _deflated(plain, crc: 0xDEADBEEF, sink: sink);
      _drain(r);
      expect(r.bytes, plain);
      final d = sink.diagnostics.single;
      expect(d.severity, EpubSeverity.warning);
      expect(d.details, {
        'reason': 'crc',
        'expected': 0xDEADBEEF,
        'actual': crc32(plain),
        'count': 1,
      });
    });

    test('stored também confere o CRC', () {
      final sink = DiagnosticSink();
      _drain(_stored(noise(70000), crc: 1, sink: sink));
      expect(sink.diagnostics.single.details['reason'], 'crc');
    });

    test(
      'strict: registra e lança EpubContainerException; bytes indisponível',
      () {
        final sink = DiagnosticSink(strict: true);
        final r = _deflated(prose(5000), crc: 1, sink: sink);
        expect(
          () => _drain(r),
          throwsA(
            isA<EpubContainerException>()
                .having((e) => e.href, 'href', 'a.xhtml')
                .having(
                  (e) => e.message,
                  'message',
                  contains('zipCrcMismatch'),
                ),
          ),
        );
        expect(sink.diagnostics.single.code, EpubDiagnosticCode.zipCrcMismatch);
        expect(() => r.bytes, throwsStateError);
      },
    );

    test('CRC certo não emite nada', () {
      final sink = DiagnosticSink(strict: true);
      _drain(_deflated(prose(5000), sink: sink));
      expect(sink.diagnostics, isEmpty);
    });
  });

  test('deflate inválido lança EpubContainerException com cause', () {
    final r = _deflated(Uint8List(0), data: noise(100), size: 1000, crc: 0);
    expect(
      () => _drain(r),
      throwsA(
        isA<EpubContainerException>().having(
          (e) => e.cause,
          'cause',
          isA<FormatException>(),
        ),
      ),
    );
  });

  group('drenagem', () {
    test('bytes antes do decode lança StateError', () {
      expect(() => _stored(noise(10)).bytes, throwsStateError);
    });

    test('bytes antes do fim da drenagem lança StateError', () {
      final r = _deflated(prose(200 * 1024));
      final it = r.decode().iterator..moveNext();
      expect(() => r.bytes, throwsStateError);
      while (it.moveNext()) {}
      expect(r.bytes, hasLength(200 * 1024));
    });

    test('segundo decode() lança StateError no primeiro passo', () {
      final r = _stored(noise(10));
      final second = r.decode();
      _drain(r);
      expect(() => second.iterator.moveNext(), throwsStateError);
      expect(() => _drain(r), throwsStateError);
    });

    test('segunda iteração do mesmo iterável lança StateError', () {
      final r = _stored(noise(10));
      final steps = r.decode();
      expect(steps.length, 1);
      expect(() => steps.length, throwsStateError);
    });

    test('size é o declarado', () {
      expect(_deflated(prose(100), size: 150).size, 150);
    });
  });

  group('PendingResource.ready', () {
    test('um passo, sem CRC', () {
      final r = PendingResource.ready(path: 'p.xhtml', bytes: noise(200000));
      expect(r.size, 200000);
      expect(_drain(r), 1);
      expect(r.bytes, hasLength(200000));
    });
  });
}
```

Criar `test/container/inflate_web_test.dart`:

```dart
// Stub do inflate no web (P7, adiado para a 1.0.x). Só roda com
// `flutter test --platform chrome test/container/inflate_web_test.dart`; na
// VM, @TestOn pula o arquivo.
@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/container/inflate/inflate.dart';

void main() {
  test('createInflater lança UnsupportedError citando P7 e 1.0.x', () {
    expect(
      () => createInflater((_) {}),
      throwsA(
        isA<UnsupportedError>().having(
          (e) => e.message,
          'message',
          allOf(contains('P7'), contains('1.0.x')),
        ),
      ),
    );
  });
}
```

- [ ] **Passo 3: Rodar e ver falhar**

Run: `flutter test test/container/inflate_test.dart`
Expected: FAIL na compilação, com `Error when reading 'lib/src/container/container.dart'`.

- [ ] **Passo 4: Interface do inflate e as duas implementações**

Criar `lib/src/container/inflate/inflate.dart`:

```dart
/// Inflate chunked (deflate cru, método 8 do ZIP). Nativo em
/// `inflate_io.dart`; no web, `inflate_stub.dart` falha com mensagem clara
/// (P7, adiado para a 1.0.x).
library;

import 'dart:typed_data';

export 'inflate_stub.dart' if (dart.library.io) 'inflate_io.dart';

/// Recebe a entrada comprimida em pedaços e entrega a saída a quem o criou,
/// sincronamente, dentro de [add] e [close].
abstract interface class ChunkedInflater {
  /// FormatException se o stream for inválido. Exceção lançada pelo
  /// callback de saída atravessa [add] sem ser embrulhada.
  void add(Uint8List chunk);

  /// Stream truncado não lança: a saída só fica curta.
  void close();
}

/// Cria um inflater que entrega a saída a [onOutput].
typedef InflaterFactory = ChunkedInflater Function(
  void Function(Uint8List chunk) onOutput,
);
```

Criar `lib/src/container/inflate/inflate_io.dart` (`ByteConversionSink` vem de
`dart:convert`):

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'inflate.dart';

/// `ZLibDecoder(raw: true)` em modo chunked.
ChunkedInflater createInflater(void Function(Uint8List chunk) onOutput) =>
    _IoInflater(onOutput);

final class _IoInflater implements ChunkedInflater {
  _IoInflater(void Function(Uint8List chunk) onOutput)
    : _sink = ZLibDecoder(raw: true).startChunkedConversion(_Output(onOutput));

  final ByteConversionSink _sink;

  @override
  void add(Uint8List chunk) => _sink.add(chunk);

  @override
  void close() => _sink.close();
}

final class _Output implements Sink<List<int>> {
  _Output(this._onOutput);

  final void Function(Uint8List chunk) _onOutput;

  @override
  void add(List<int> data) =>
      _onOutput(data is Uint8List ? data : Uint8List.fromList(data));

  @override
  void close() {}
}
```

Criar `lib/src/container/inflate/inflate_stub.dart`:

```dart
import 'dart:typed_data';

import 'inflate.dart';

/// Mensagem do web; `inflate_web_test.dart` confere.
const String inflateUnsupportedMessage =
    'Inflate (deflate, método 8 do ZIP) ainda não existe no web: pendência '
    'P7, prevista para a 1.0.x. Entradas stored funcionam.';

ChunkedInflater createInflater(void Function(Uint8List chunk) onOutput) =>
    throw UnsupportedError(inflateUnsupportedMessage);
```

- [ ] **Passo 5: `EpubContainer` e `PendingResource`**

Criar `lib/src/container/container.dart`. Pontos que o teste cobre e que não
podem mudar: a guarda de dupla drenagem fica **no corpo** do gerador (lança no
primeiro passo); a saída passa pelo `_Output`, que lança antes de passar de
`size`, e a exceção do callback atravessa o `add` do decoder (verificado no
scratchpad); saída curta emite só `reason: 'size'`; `_bytes` só é gravado
depois do CRC, então uma exceção de `strict` deixa `bytes` em `StateError`.

```dart
/// Contêiner de recursos: a interface interna que a Publicação e a IR usam,
/// com duas implementações (`ZipContainer` e `ProviderContainer`).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../diagnostics/diagnostic.dart';
import '../diagnostics/exceptions.dart';
import 'inflate/inflate.dart';
import 'zip/crc32.dart';

/// Maior entrada aceita, descomprimida. Proteção contra zip bomb.
const int maxEntrySize = 256 * 1024 * 1024;

/// Um passo do `decode()` a cada 64 KiB completos de saída.
const int decodeStepBytes = 64 * 1024;

/// A entrada comprimida vai ao decoder em fatias de no máximo 16 KiB.
const int inflateSliceBytes = 16 * 1024;

enum FontObfuscation { idpf, adobe, unknown }

abstract interface class EpubContainer {
  /// Caminhos de arquivo presentes (sem diretórios), na ordem do contêiner.
  Iterable<String> get paths;

  /// Caminho existe: exato, senão sem diferenciar maiúsculas. Não emite
  /// diagnóstico (quem emite é [fetch]).
  Future<bool> exists(String path);

  /// Busca os bytes crus numa ida à fonte. `null` se ausente.
  /// [EpubContainerException] com `href: path` se a entrada não é legível.
  Future<PendingResource?> fetch(String path);

  /// Ofuscação de fonte declarada para o caminho (resolvido pelo mesmo
  /// índice de [fetch]).
  FontObfuscation? obfuscationOf(String path);

  /// Fecha a fonte: o contêiner é dono dela. Idempotente.
  Future<void> close();
}

/// Bytes crus de uma entrada, ainda por decodificar. [decode] é síncrono e
/// fatiável (doc/08 §3); [bytes] só existe depois dele.
final class PendingResource {
  /// Entrada de ZIP: [method] 0 (stored) ou 8 (deflate), [data] comprimido,
  /// [crc32] e [size] do central directory.
  PendingResource.zip({
    required this.path,
    required this.size,
    required int method,
    required this._data,
    required int crc32,
    required DiagnosticSink this._sink,
    this._inflaterFactory = createInflater,
  }) : assert(method == 0 || method == 8, 'método $method'),
       _method = method,
       _crc = crc32;

  /// Bytes já prontos (provider): um passo, sem CRC.
  PendingResource.ready({required this.path, required Uint8List bytes})
    : size = bytes.length,
      _method = null,
      _data = bytes,
      _crc = 0,
      _sink = null,
      _inflaterFactory = createInflater;

  /// Nome resolvido da entrada.
  final String path;

  /// Tamanho descomprimido declarado (≤ [maxEntrySize]).
  final int size;

  final int? _method;
  final Uint8List _data;
  final int _crc;
  final DiagnosticSink? _sink;
  final InflaterFactory _inflaterFactory;

  bool _started = false;
  Uint8List? _bytes;

  /// Bytes decodificados. [StateError] antes de [decode] ser drenado ou
  /// depois de uma exceção no decode.
  Uint8List get bytes =>
      _bytes ??
      (throw StateError(
        'bytes de $path indisponíveis: decode() não terminou ou falhou',
      ));

  /// Passos do decode: um a cada 64 KiB completos de saída e mais um ao
  /// terminar, depois do CRC. Cada chamada devolve um iterável novo; uma
  /// segunda drenagem lança [StateError] no primeiro passo.
  Iterable<void> decode() sync* {
    if (_started) {
      throw StateError('decode() de $path já foi iniciado');
    }
    _started = true;
    switch (_method) {
      case null:
        _bytes = _data;
        yield null;
      case 0:
        yield* _stored();
      default:
        yield* _inflate();
    }
  }

  Iterable<void> _stored() sync* {
    final data = _data;
    if (data.length > size) throw _overflow();
    final crc = Crc32();
    final whole = data.length - data.length % decodeStepBytes;
    for (var at = 0; at < whole; at += decodeStepBytes) {
      crc.add(data, at, at + decodeStepBytes);
      yield null;
    }
    crc.add(data, whole, data.length);
    _finish(data, crc.value);
    yield null;
  }

  Iterable<void> _inflate() sync* {
    final out = _Output(size);
    final crc = Crc32();
    final inflater = _inflaterFactory((chunk) {
      out.add(chunk); // lança _OutputOverflow antes de passar de size
      crc.add(chunk);
    });
    var steps = 0;
    final data = _data;
    for (var at = 0; at < data.length; at += inflateSliceBytes) {
      final end = math.min(at + inflateSliceBytes, data.length);
      _guard(() => inflater.add(Uint8List.sublistView(data, at, end)));
      while (steps < out.length ~/ decodeStepBytes) {
        steps++;
        yield null;
      }
    }
    _guard(inflater.close);
    while (steps < out.length ~/ decodeStepBytes) {
      steps++;
      yield null;
    }
    _finish(out.bytes, crc.value);
    yield null;
  }

  void _guard(void Function() step) {
    try {
      step();
    } on _OutputOverflow {
      throw _overflow();
    } on FormatException catch (e) {
      throw EpubContainerException(
        'stream deflate inválido',
        href: path,
        cause: e,
      );
    }
  }

  EpubContainerException _overflow() => EpubContainerException(
    'saída maior que o tamanho declarado ($size bytes)',
    href: path,
  );

  void _finish(Uint8List out, int actualCrc) {
    final sink = _sink!;
    if (out.length < size) {
      sink.emit(
        EpubDiagnosticCode.zipCrcMismatch,
        href: path,
        message: 'saída com ${out.length} de $size bytes declarados',
        details: {'reason': 'size', 'expected': size, 'actual': out.length},
      );
    } else if (actualCrc != _crc) {
      sink.emit(
        EpubDiagnosticCode.zipCrcMismatch,
        href: path,
        message: 'CRC-32 divergente',
        details: {'reason': 'crc', 'expected': _crc, 'actual': actualCrc},
      );
    }
    _bytes = out;
  }
}

final class _OutputOverflow implements Exception {
  const _OutputOverflow();
}

/// Saída do inflate que cresce por dobra até o tamanho declarado, sem
/// alocar de uma vez os 256 MiB que um cabeçalho mentiroso pediria.
final class _Output {
  _Output(this._limit) : _buffer = Uint8List(math.min(_limit, 64 * 1024));

  final int _limit;
  Uint8List _buffer;
  int length = 0;

  void add(Uint8List chunk) {
    final end = length + chunk.length;
    if (end > _limit) throw const _OutputOverflow();
    if (end > _buffer.length) {
      final grown = Uint8List(
        math.min(_limit, math.max(end, _buffer.length * 2)),
      )..setRange(0, length, _buffer);
      _buffer = grown;
    }
    _buffer.setRange(length, end, chunk);
    length = end;
  }

  Uint8List get bytes => Uint8List.sublistView(_buffer, 0, length);
}
```

- [ ] **Passo 6: Rodar e ver passar**

Run: `flutter test test/container/inflate_test.dart`
Expected: `All tests passed!` (28 testes).

Run: `flutter test test/container/inflate_web_test.dart`
Expected: `No tests ran.` (o `@TestOn('browser')` pula na VM).

Se houver Chrome ou Chromium na máquina:
Run: `CHROME_EXECUTABLE=/usr/bin/chromium flutter test --platform chrome test/container/inflate_web_test.dart`
Expected: `All tests passed!` (1 teste). Sem navegador, pular: o CI ainda não
tem job web (pendência registrada na Tarefa 12).

- [ ] **Passo 7: Formatar e analisar**

Run: `dart format lib/src/container test/container && flutter analyze`
Expected: nada mudado e `No issues found!`.

- [ ] **Passo 8: Commit**

```bash
git add lib/src/container/container.dart lib/src/container/inflate test/container/support/zip_fixtures.dart test/container/inflate_test.dart test/container/inflate_web_test.dart
git commit -m "feat(container): PendingResource e inflate chunked

decode() sync* com fatias de 16 KiB, um passo a cada 64 KiB completos,
teto de saída no tamanho declarado, CRC-32 sempre conferido e dupla
drenagem barrada (spec §4 e §5.4). ZLibDecoder no nativo; stub no web
citando P7 e 1.0.x."
```

---

### Tarefa 5: Fim do arquivo e central directory

Spec §5.1 inteiro. O apoio de teste ganha o `ZipWriter` do corpus, os ajustes
de bytes da spec §9 e as fontes que contam leituras e que falham.

**Arquivos:**
- Modificar: `test/container/support/zip_fixtures.dart` (substituir inteiro)
- Criar: `lib/src/container/zip/central_directory.dart`
- Teste: `test/container/central_directory_test.dart`

**Interfaces:**
- Consome: `EpubByteSource`, `MemoryEpubByteSource` (Tarefa 2); `readU16`, `readU32`, `readU64`, `decodeCp437` (Tarefa 3); `maxEntrySize` (Tarefa 4); `DiagnosticSink`, `EpubContainerException`, `EpubEncryptedException` (Tarefa 1); `ZipWriter` de `tool/corpus/lib/zip_writer.dart` (`add(String name, List<int> data, {bool compress = true, int? crcOverride})`, `build()`, `forceZip64`).
- Produz: `const int tailReadSize = 65535 + 22 + 20;` (65 577).
- Produz: `final class ZipEntry { final String name; final String rawName; final int nameLength; final int flags; final int method; final int compressedSize; final int uncompressedSize; final int localHeaderOffset; final int crc32; final String? invalidReason; bool get isDirectory; }` (`localHeaderOffset` já com o delta).
- Produz: `typedef ZipLookup = ({ZipEntry entry, bool exact});`.
- Produz: `final class CentralDirectory { final List<ZipEntry> entries; final int length; final int cdOffset; final int cdSize; final int delta; final bool zip64; List<String> get paths; ZipLookup? lookup(String path); }`.
- Produz: `String normalizeEntryName(String raw)`.
- Produz: `Future<CentralDirectory> readCentralDirectory(EpubByteSource source, {required DiagnosticSink sink})`.
- Produz: `Future<Uint8List> readSource(EpubByteSource source, int offset, int length, {String? href})` — exceção da fonte vira `EpubContainerException(cause)`.
- Produz (teste, em `zip_fixtures.dart`): `epubMimetype`; `Uint8List epubZip(Map<String, List<int>> files, {bool compress = true, bool zip64 = false})`; `prose`, `noise`; `final class ZipLayout { ZipLayout(Uint8List bytes); int eocd, cdSize, cdOffset; List<int> central; List<int> local; int centralU16(int entry, int field); int centralU32(int entry, int field); }`; constantes `cdFlags`, `cdMethod`, `cdCrc`, `cdCompressed`, `cdUncompressed`, `cdLocalOffset`, `lhFlags`, `lhMethod`, `lhCrc`, `lhCompressed`, `lhUncompressed`; `patchCentralU16`, `patchCentralU32`, `patchLocalU16(Uint8List zip, int entry, int field, int value)`; `withMethod(zip, entry, method)`, `withFlagBits(zip, entry, bits)`, `withoutFlagBits(zip, entry, bits)`, `withDataDescriptor(zip, entry)`, `withRawName(zip, entry, List<int> name)`, `withComment(zip, List<int> comment)`, `withFakeEocdInComment(zip)`, `withEocdDisks(zip, {int disk = 0, int cdDisk = 0})`, `withEocdCount(zip, count)`, `withEocdCdOffset(zip, cdOffset)`, `withTruncatedCentralDirectory(zip, cut)`, `withBadCentralSignature(zip, entry)`, `withPrefix(zip, length)`, `withLocalExtra(zip, entry, extraLength)`, `withZip64ExtraValue(zip, entry, field, {required int lo, required int hi})`, `withZip64TotalDisks(zip, disks)` (todas devolvem `Uint8List` nova); `final class CountingByteSource implements EpubByteSource { CountingByteSource(EpubByteSource inner); int calls; int bytesRead; bool closed; List<(int, int)> ranges; void reset(); }`; `final class FailingByteSource implements EpubByteSource { FailingByteSource(Object error, {int size = 1000}); bool closed; }`; reexporta `ZipWriter`.

- [ ] **Passo 1: Completar o apoio de teste**

Substituir `test/container/support/zip_fixtures.dart` inteiro por:

```dart
// ignore_for_file: avoid_relative_lib_imports — tool/ não é pacote; importar por caminho é intencional.
/// ZIPs de teste do contêiner: o `ZipWriter` do corpus e ajustes de bytes
/// para o que ele não cobre (spec do contêiner §9).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:galley/src/container/byte_source.dart';

import '../../../tool/corpus/lib/zip_writer.dart';

export '../../../tool/corpus/lib/zip_writer.dart' show ZipWriter;

/// Conteúdo do `mimetype` da OCF.
const String epubMimetype = 'application/epub+zip';

/// ZIP com `mimetype` stored na frente e as [files] dadas, em ordem.
Uint8List epubZip(
  Map<String, List<int>> files, {
  bool compress = true,
  bool zip64 = false,
}) {
  final w = ZipWriter(forceZip64: zip64)
    ..add('mimetype', ascii.encode(epubMimetype), compress: false);
  for (final MapEntry(key: name, value: data) in files.entries) {
    w.add(name, data, compress: compress);
  }
  return w.build();
}

/// [n] bytes de texto repetitivo (comprime bem, CRC conhecido pelo writer).
Uint8List prose(int n, {int seed = 1}) {
  final words = ['livro', 'página', 'capítulo', 'nota', 'verso', 'texto'];
  final out = BytesBuilder(copy: false);
  var i = seed;
  while (out.length < n) {
    out.add(utf8.encode('${words[i % words.length]}$i '));
    i = (i * 7 + 3) % 10007;
  }
  return Uint8List.sublistView(out.takeBytes(), 0, n);
}

/// [n] bytes pseudoaleatórios (não comprimem).
Uint8List noise(int n, {int seed = 7}) {
  var x = seed;
  return Uint8List.fromList(
    List<int>.generate(n, (_) {
      x = (x * 1103515245 + 12345) & 0x7FFFFFFF;
      return x >> 16 & 0xFF;
    }),
  );
}

/// Posições das estruturas de um ZIP sem comentário e sem ZIP64, como o
/// `ZipWriter` produz.
final class ZipLayout {
  ZipLayout(this.bytes) {
    eocd = bytes.length - 22;
    if (_u32(eocd) != 0x06054b50) {
      throw ArgumentError('ZipLayout: EOCD não está nos últimos 22 bytes');
    }
    cdSize = _u32(eocd + 12);
    cdOffset = _u32(eocd + 16);
    var p = cdOffset;
    while (p < cdOffset + cdSize) {
      central.add(p);
      local.add(_u32(p + 42));
      p += 46 + _u16(p + 28) + _u16(p + 30) + _u16(p + 32);
    }
  }

  final Uint8List bytes;
  late final int eocd;
  late final int cdSize;
  late final int cdOffset;

  /// Offset de cada entrada no central directory, em ordem.
  final List<int> central = [];

  /// Offset do local header de cada entrada, na ordem do central directory.
  final List<int> local = [];

  int _u16(int at) => bytes[at] | bytes[at + 1] << 8;
  int _u32(int at) =>
      ByteData.sublistView(bytes, at, at + 4).getUint32(0, Endian.little);

  int centralU16(int entry, int field) => _u16(central[entry] + field);
  int centralU32(int entry, int field) => _u32(central[entry] + field);
}

Uint8List _copy(Uint8List b) => Uint8List.fromList(b);

void _setU16(Uint8List b, int at, int v) =>
    ByteData.sublistView(b)..setUint16(at, v, Endian.little);

void _setU32(Uint8List b, int at, int v) =>
    ByteData.sublistView(b)..setUint32(at, v, Endian.little);

// Campos do central directory (offset dentro da entrada).
const cdFlags = 8;
const cdMethod = 10;
const cdCrc = 16;
const cdCompressed = 20;
const cdUncompressed = 24;
const cdLocalOffset = 42;

// Campos do local header.
const lhFlags = 6;
const lhMethod = 8;
const lhCrc = 14;
const lhCompressed = 18;
const lhUncompressed = 22;

/// Troca um campo u16 da entrada [entry] no central directory.
Uint8List patchCentralU16(Uint8List zip, int entry, int field, int value) {
  final out = _copy(zip);
  _setU16(out, ZipLayout(zip).central[entry] + field, value);
  return out;
}

/// Troca um campo u32 da entrada [entry] no central directory.
Uint8List patchCentralU32(Uint8List zip, int entry, int field, int value) {
  final out = _copy(zip);
  _setU32(out, ZipLayout(zip).central[entry] + field, value);
  return out;
}

/// Troca um campo u16 do local header da entrada [entry].
Uint8List patchLocalU16(Uint8List zip, int entry, int field, int value) {
  final out = _copy(zip);
  _setU16(out, ZipLayout(zip).local[entry] + field, value);
  return out;
}

/// Método de compressão nos dois cabeçalhos.
Uint8List withMethod(Uint8List zip, int entry, int method) => patchLocalU16(
  patchCentralU16(zip, entry, cdMethod, method),
  entry,
  lhMethod,
  method,
);

/// Liga [bits] na flag dos dois cabeçalhos.
Uint8List withFlagBits(Uint8List zip, int entry, int bits) {
  final l = ZipLayout(zip);
  final out = _copy(zip);
  _setU16(out, l.central[entry] + cdFlags, l.centralU16(entry, cdFlags) | bits);
  final lf =
      out[l.local[entry] + lhFlags] | out[l.local[entry] + lhFlags + 1] << 8;
  _setU16(out, l.local[entry] + lhFlags, lf | bits);
  return out;
}

/// Desliga [bits] na flag dos dois cabeçalhos.
Uint8List withoutFlagBits(Uint8List zip, int entry, int bits) {
  final l = ZipLayout(zip);
  final out = _copy(zip);
  _setU16(
    out,
    l.central[entry] + cdFlags,
    l.centralU16(entry, cdFlags) & ~bits,
  );
  final lf =
      out[l.local[entry] + lhFlags] | out[l.local[entry] + lhFlags + 1] << 8;
  _setU16(out, l.local[entry] + lhFlags, lf & ~bits);
  return out;
}

/// Data descriptor (bit 3) com CRC e tamanhos do local header zerados; o
/// descriptor em si não é gravado (o leitor usa o central directory).
Uint8List withDataDescriptor(Uint8List zip, int entry) {
  final out = withFlagBits(zip, entry, 0x0008);
  final at = ZipLayout(out).local[entry];
  _setU32(out, at + lhCrc, 0);
  _setU32(out, at + lhCompressed, 0);
  _setU32(out, at + lhUncompressed, 0);
  return out;
}

/// Troca os bytes do nome da entrada [entry] (mesmo tamanho) nos dois
/// cabeçalhos.
Uint8List withRawName(Uint8List zip, int entry, List<int> name) {
  final l = ZipLayout(zip);
  if (l.centralU16(entry, 28) != name.length) {
    throw ArgumentError('withRawName: o nome novo precisa ter o mesmo tamanho');
  }
  return _copy(zip)
    ..setRange(l.central[entry] + 46, l.central[entry] + 46 + name.length, name)
    ..setRange(l.local[entry] + 30, l.local[entry] + 30 + name.length, name);
}

/// Comentário no EOCD.
Uint8List withComment(Uint8List zip, List<int> comment) {
  final out = Uint8List.fromList([...zip, ...comment]);
  _setU16(out, zip.length - 2, comment.length);
  return out;
}

/// Comentário que contém uma assinatura de EOCD falsa (sem comentário que
/// feche no fim do arquivo).
Uint8List withFakeEocdInComment(Uint8List zip) => withComment(zip, [
  ...ascii.encode('antes '),
  0x50, 0x4b, 0x05, 0x06, // assinatura do EOCD
  ...List<int>.filled(18, 0x41),
  ...ascii.encode(' depois'),
]);

/// Disco do EOCD e disco do central directory.
Uint8List withEocdDisks(Uint8List zip, {int disk = 0, int cdDisk = 0}) {
  final out = _copy(zip);
  final eocd = ZipLayout(zip).eocd;
  _setU16(out, eocd + 4, disk);
  _setU16(out, eocd + 6, cdDisk);
  return out;
}

/// Contagem de entradas do EOCD (as duas).
Uint8List withEocdCount(Uint8List zip, int count) {
  final out = _copy(zip);
  final eocd = ZipLayout(zip).eocd;
  _setU16(out, eocd + 8, count);
  _setU16(out, eocd + 10, count);
  return out;
}

/// Offset do central directory no EOCD.
Uint8List withEocdCdOffset(Uint8List zip, int cdOffset) {
  final out = _copy(zip);
  _setU32(out, ZipLayout(zip).eocd + 16, cdOffset);
  return out;
}

/// Tira os últimos [cut] bytes do central directory e ajusta o `cdSize`:
/// a última entrada passa a atravessar o fim.
Uint8List withTruncatedCentralDirectory(Uint8List zip, int cut) {
  final l = ZipLayout(zip);
  final cdEnd = l.cdOffset + l.cdSize;
  final out = Uint8List.fromList([
    ...zip.sublist(0, cdEnd - cut),
    ...zip.sublist(cdEnd),
  ]);
  _setU32(out, out.length - 22 + 12, l.cdSize - cut);
  return out;
}

/// Assinatura errada na entrada [entry] do central directory.
Uint8List withBadCentralSignature(Uint8List zip, int entry) =>
    patchCentralU32(zip, entry, 0, 0x02014b51);

/// Bytes arbitrários antes do ZIP; os offsets internos não mudam.
Uint8List withPrefix(Uint8List zip, int length) =>
    Uint8List.fromList([...noise(length, seed: 99), ...zip]);

/// Extra field de [extraLength] bytes no local header da entrada [entry],
/// com offsets e EOCD ajustados.
Uint8List withLocalExtra(Uint8List zip, int entry, int extraLength) {
  final l = ZipLayout(zip);
  final at = l.local[entry];
  final nameLength = zip[at + 26] | zip[at + 27] << 8;
  final oldExtra = zip[at + 28] | zip[at + 29] << 8;
  final insertAt = at + 30 + nameLength + oldExtra;
  final extra = Uint8List(extraLength);
  // Um bloco 0xCAFE com o resto do espaço.
  _setU16(extra, 0, 0xCAFE);
  _setU16(extra, 2, extraLength - 4);
  final out = Uint8List.fromList([
    ...zip.sublist(0, insertAt),
    ...extra,
    ...zip.sublist(insertAt),
  ]);
  _setU16(out, at + 28, oldExtra + extraLength);
  // O central directory inteiro fica depois do ponto de inserção.
  _setU32(out, out.length - 22 + 16, l.cdOffset + extraLength);
  for (var i = 0; i < l.central.length; i++) {
    if (l.local[i] > at) {
      _setU32(
        out,
        l.central[i] + extraLength + cdLocalOffset,
        l.local[i] + extraLength,
      );
    }
  }
  return out;
}

/// Fonte que conta chamadas e bytes lidos.
final class CountingByteSource implements EpubByteSource {
  CountingByteSource(this.inner);

  final EpubByteSource inner;
  int calls = 0;
  int bytesRead = 0;
  bool closed = false;

  /// Faixas pedidas, em ordem.
  final List<(int, int)> ranges = [];

  void reset() {
    calls = 0;
    bytesRead = 0;
    ranges.clear();
  }

  @override
  Future<int> get length => inner.length;

  @override
  Future<Uint8List> readRange(int offset, int length) {
    calls++;
    bytesRead += length;
    ranges.add((offset, length));
    return inner.readRange(offset, length);
  }

  @override
  Future<void> close() {
    closed = true;
    return inner.close();
  }
}

/// Fonte cuja leitura sempre falha com [error].
final class FailingByteSource implements EpubByteSource {
  FailingByteSource(this.error, {this.size = 1000});

  final Object error;
  final int size;
  bool closed = false;

  @override
  Future<int> get length async => size;

  @override
  Future<Uint8List> readRange(int offset, int length) async => throw error;

  @override
  Future<void> close() async => closed = true;
}

/// Num ZIP gerado com `forceZip64`, grava [lo]/[hi] no campo [field] do
/// extra 0x0001 da entrada [entry] do central directory (0: tamanho
/// original, 1: comprimido, 2: offset).
Uint8List withZip64ExtraValue(
  Uint8List zip,
  int entry,
  int field, {
  required int lo,
  required int hi,
}) {
  final out = _copy(zip);
  final data = ByteData.sublistView(out);
  final locator = out.length - 22 - 20;
  final eocd64 = data.getUint32(locator + 8, Endian.little);
  var p = data.getUint32(eocd64 + 48, Endian.little);
  for (var i = 0; i < entry; i++) {
    p +=
        46 +
        data.getUint16(p + 28, Endian.little) +
        data.getUint16(p + 30, Endian.little) +
        data.getUint16(p + 32, Endian.little);
  }
  final at = p + 46 + data.getUint16(p + 28, Endian.little) + 4 + field * 8;
  data
    ..setUint32(at, lo, Endian.little)
    ..setUint32(at + 4, hi, Endian.little);
  return out;
}

/// Total de discos no locator ZIP64.
Uint8List withZip64TotalDisks(Uint8List zip, int disks) {
  final out = _copy(zip);
  _setU32(out, out.length - 22 - 20 + 16, disks);
  return out;
}
```

Run: `flutter test test/container/inflate_test.dart`
Expected: `All tests passed!` (o arquivo novo mantém `prose` e `noise`).

- [ ] **Passo 2: Escrever o teste que falha**

Criar `test/container/central_directory_test.dart`. O teste "comentário de
65 535 bytes" é o item 4 do Foco de revisão:

```dart
// Fim do arquivo e central directory (spec do contêiner §5.1).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/container/byte_source.dart';
import 'package:galley/src/container/container.dart';
import 'package:galley/src/container/zip/central_directory.dart';
import 'package:galley/src/diagnostics/diagnostic.dart';
import 'package:galley/src/diagnostics/exceptions.dart';

import 'support/zip_fixtures.dart';

Future<CentralDirectory> _read(Uint8List zip, {DiagnosticSink? sink}) =>
    readCentralDirectory(
      MemoryEpubByteSource(zip),
      sink: sink ?? DiagnosticSink(),
    );

Matcher _containerError(String text) => throwsA(
  isA<EpubContainerException>().having(
    (e) => e.message,
    'message',
    contains(text),
  ),
);

void main() {
  final files = {
    'META-INF/container.xml': utf8.encode('<container/>'),
    'OEBPS/cap01.xhtml': prose(5000),
  };
  final zip = epubZip(files);

  group('EOCD', () {
    test('simples', () async {
      final cd = await _read(zip);
      expect(cd.paths, [
        'mimetype',
        'META-INF/container.xml',
        'OEBPS/cap01.xhtml',
      ]);
      expect(cd.delta, 0);
      expect(cd.zip64, isFalse);
      expect(cd.length, zip.length);
      final e = cd.lookup('OEBPS/cap01.xhtml')!.entry;
      expect(e.uncompressedSize, 5000);
      expect(e.method, 8);
    });

    test('com comentário', () async {
      final cd = await _read(withComment(zip, utf8.encode('comentário')));
      expect(cd.paths, hasLength(3));
    });

    test('com assinatura falsa de EOCD dentro do comentário', () async {
      final cd = await _read(withFakeEocdInComment(zip));
      expect(cd.paths, hasLength(3));
      expect(cd.delta, 0);
    });

    test('comentário de 65 535 bytes', () async {
      final cd = await _read(withComment(zip, List<int>.filled(65535, 0x20)));
      expect(cd.paths, hasLength(3));
    });
  });

  group('ZIP64', () {
    final z64 = epubZip(files, zip64: true);

    test('segue o locator e o extra 0x0001', () async {
      final cd = await _read(z64);
      expect(cd.zip64, isTrue);
      expect(cd.paths, hasLength(3));
      final e = cd.lookup('OEBPS/cap01.xhtml')!.entry;
      expect(e.uncompressedSize, 5000);
      expect(e.localHeaderOffset, lessThan(z64.length));
      expect(e.invalidReason, isNull);
    });

    test('com prefixo: acha o EOCD64 antes do locator', () async {
      final sink = DiagnosticSink();
      final cd = await _read(withPrefix(z64, 64), sink: sink);
      expect(cd.delta, 64);
      expect(cd.lookup('mimetype')!.entry.localHeaderOffset, 64);
      expect(sink.diagnostics.single.details['reason'], 'prefix');
    });

    test('total de discos 0 e 1 aceitos; 2 é fatal', () async {
      expect((await _read(withZip64TotalDisks(z64, 0))).zip64, isTrue);
      await expectLater(
        _read(withZip64TotalDisks(z64, 2)),
        _containerError('vários discos'),
      );
    });

    test('valor u64 acima de 2^53 torna a entrada inválida', () async {
      final big = withZip64ExtraValue(z64, 2, 0, lo: 1, hi: 0x200000);
      final e = (await _read(big)).lookup('OEBPS/cap01.xhtml')!.entry;
      expect(e.invalidReason, contains('2^53'));
    });
  });

  group('prefixo', () {
    test('offsets recebem delta e emite mimetypeIrregular', () async {
      final sink = DiagnosticSink();
      final cd = await _read(withPrefix(zip, 100), sink: sink);
      expect(cd.delta, 100);
      expect(cd.lookup('mimetype')!.entry.localHeaderOffset, 100);
      final d = sink.diagnostics.single;
      expect(d.code, EpubDiagnosticCode.mimetypeIrregular);
      expect(d.details, {'reason': 'prefix', 'delta': 100, 'count': 1});
    });

    test('delta negativo é fatal', () async {
      final l = ZipLayout(zip);
      await expectLater(
        _read(withEocdCdOffset(zip, l.cdOffset + 5)),
        _containerError('não cabe'),
      );
    });
  });

  group('nomes', () {
    Uint8List single(String name) =>
        (ZipWriter()..add(name, utf8.encode('x'), compress: false)).build();

    test('CP437 sem bit 11 quando não é UTF-8 válido', () async {
      var z = single('caXitulo.xhtml');
      final raw = ascii.encode('caXitulo.xhtml')..[2] = 0x87; // ç em CP437
      z = withoutFlagBits(withRawName(z, 0, raw), 0, 0x0800);
      expect((await _read(z)).paths, ['caçitulo.xhtml']);
    });

    test('UTF-8 sem bit 11 quando os bytes são UTF-8 válido', () async {
      final z = withoutFlagBits(single('capítulo.xhtml'), 0, 0x0800);
      expect((await _read(z)).paths, ['capítulo.xhtml']);
    });

    test('bit 11 com UTF-8 malformado decodifica tolerante', () async {
      final raw = ascii.encode('caXitulo.xhtml')..[2] = 0xFF;
      final z = withRawName(single('caXitulo.xhtml'), 0, raw);
      expect((await _read(z)).paths.single, 'ca�itulo.xhtml');
    });

    test('normaliza \\, / e ./ iniciais; rawName guarda o original', () async {
      final w = ZipWriter()
        ..add(r'OEBPS\Text\a.xhtml', [1], compress: false)
        ..add('/abs.xhtml', [2], compress: false)
        ..add('./rel.xhtml', [3], compress: false)
        ..add('.//dupla.xhtml', [4], compress: false);
      final cd = await _read(w.build());
      expect(cd.paths, [
        'OEBPS/Text/a.xhtml',
        'abs.xhtml',
        'rel.xhtml',
        'dupla.xhtml',
      ]);
      expect(cd.entries.first.rawName, r'OEBPS\Text\a.xhtml');
    });

    test('diretórios ficam fora de paths e do índice', () async {
      final w = ZipWriter()
        ..add('OEBPS/', const [], compress: false)
        ..add('OEBPS/a.xhtml', [1], compress: false);
      final cd = await _read(w.build());
      expect(cd.entries, hasLength(2));
      expect(cd.paths, ['OEBPS/a.xhtml']);
      expect(cd.lookup('OEBPS/'), isNull);
    });
  });

  group('duplicatas', () {
    test('vence a primeira; as seguintes emitem zipDuplicateEntry', () async {
      final w = ZipWriter()
        ..add('a.txt', [1, 1, 1], compress: false)
        ..add('a.txt', [2, 2], compress: false)
        ..add('a.txt', [3], compress: false);
      final sink = DiagnosticSink();
      final cd = await _read(w.build(), sink: sink);
      expect(cd.paths, ['a.txt']);
      expect(cd.lookup('a.txt')!.entry.uncompressedSize, 3);
      final d = sink.diagnostics.single;
      expect(d.code, EpubDiagnosticCode.zipDuplicateEntry);
      expect(d.severity, EpubSeverity.info);
      expect(d.href, 'a.txt');
      expect(d.details['count'], 2);
    });

    test('sem diferenciar maiúsculas também vence a primeira', () async {
      final w = ZipWriter()
        ..add('Cap.xhtml', [1], compress: false)
        ..add('CAP.xhtml', [2, 2], compress: false);
      final cd = await _read(w.build());
      expect(cd.paths, ['Cap.xhtml', 'CAP.xhtml']);
      final hit = cd.lookup('cap.xhtml')!;
      expect(hit.exact, isFalse);
      expect(hit.entry.name, 'Cap.xhtml');
      expect(cd.lookup('CAP.xhtml')!.exact, isTrue);
    });
  });

  group('validação por entrada', () {
    test('local header além do fim', () async {
      final z = patchCentralU32(zip, 2, cdLocalOffset, zip.length + 10);
      final e = (await _read(z)).lookup('OEBPS/cap01.xhtml')!.entry;
      expect(e.invalidReason, contains('local header além do fim'));
    });

    test('dados além do fim', () async {
      final z = patchCentralU32(zip, 2, cdCompressed, zip.length);
      final e = (await _read(z)).lookup('OEBPS/cap01.xhtml')!.entry;
      expect(e.invalidReason, contains('dados da entrada além do fim'));
    });

    test('uncompressedSize acima de maxEntrySize', () async {
      final z = patchCentralU32(zip, 2, cdUncompressed, maxEntrySize + 1);
      final e = (await _read(z)).lookup('OEBPS/cap01.xhtml')!.entry;
      expect(e.invalidReason, contains('$maxEntrySize'));
    });

    test('entrada inválida continua em paths', () async {
      final z = patchCentralU32(zip, 2, cdLocalOffset, zip.length + 10);
      expect((await _read(z)).paths, contains('OEBPS/cap01.xhtml'));
    });
  });

  test('contagem divergente não é fatal', () async {
    final cd = await _read(withEocdCount(zip, 99));
    expect(cd.paths, hasLength(3));
  });

  test('bit 0 (criptografia do ZIP) lança EpubEncryptedException', () async {
    await expectLater(
      _read(withFlagBits(zip, 1, 0x0001)),
      throwsA(
        isA<EpubEncryptedException>()
            .having((e) => e.scheme, 'scheme', 'zip-encryption')
            .having((e) => e.href, 'href', 'META-INF/container.xml'),
      ),
    );
  });

  group('fatais', () {
    test('EOCD não encontrado (arquivo cortado)', () async {
      await expectLater(
        _read(Uint8List.sublistView(zip, 0, zip.length - 10)),
        _containerError('EOCD'),
      );
    });

    test('fonte vazia', () async {
      await expectLater(_read(Uint8List(0)), _containerError('EOCD'));
    });

    test('assinatura de entrada do central directory errada', () async {
      await expectLater(
        _read(withBadCentralSignature(zip, 1)),
        _containerError('assinatura'),
      );
    });

    test('central directory truncado', () async {
      await expectLater(
        _read(withTruncatedCentralDirectory(zip, 10)),
        _containerError('truncado'),
      );
    });

    test('disco múltiplo', () async {
      await expectLater(
        _read(withEocdDisks(zip, disk: 1)),
        _containerError('vários discos'),
      );
      await expectLater(
        _read(withEocdDisks(zip, cdDisk: 1)),
        _containerError('vários discos'),
      );
    });

    test('exceção da fonte vira EpubContainerException com cause', () async {
      const error = FileSystemException('disco sumiu');
      await expectLater(
        readCentralDirectory(FailingByteSource(error), sink: DiagnosticSink()),
        throwsA(
          isA<EpubContainerException>().having(
            (e) => e.cause,
            'cause',
            same(error),
          ),
        ),
      );
    });
  });
}
```

- [ ] **Passo 3: Rodar e ver falhar**

Run: `flutter test test/container/central_directory_test.dart`
Expected: FAIL na compilação, com `Error when reading 'lib/src/container/zip/central_directory.dart'`.

- [ ] **Passo 4: Implementar**

Criar `lib/src/container/zip/central_directory.dart`. O EOCD64 é procurado no
offset do locator e, se a assinatura não estiver lá (EPUB com prefixo, cujo
locator guarda o offset sem o delta), logo antes do locator; o delta do ZIP64
é calculado a partir da posição real do EOCD64, onde o central directory
termina. `_guard` só embrulha exceção **da fonte**: erro do próprio parser
(índice fora do buffer) deve aparecer como bug nos testes, não como
`EpubContainerException`.

```dart
/// Fim do arquivo (EOCD, EOCD64) e central directory (spec do contêiner
/// §5.1).
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../diagnostics/diagnostic.dart';
import '../../diagnostics/exceptions.dart';
import '../byte_source.dart';
import '../container.dart';
import 'binary.dart';
import 'cp437.dart';

const int _eocdSignature = 0x06054b50;
const int _locatorSignature = 0x07064b50;
const int _eocd64Signature = 0x06064b50;
const int _centralSignature = 0x02014b50;
const int _eocdSize = 22;
const int _locatorSize = 20;
const int _eocd64Size = 56;

/// Maior comentário do EOCD (65 535) + EOCD (22) + locator ZIP64 (20).
const int tailReadSize = 65535 + _eocdSize + _locatorSize;

/// Uma entrada do central directory.
final class ZipEntry {
  ZipEntry({
    required this.name,
    required this.rawName,
    required this.nameLength,
    required this.flags,
    required this.method,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.localHeaderOffset,
    required this.crc32,
    this.invalidReason,
  });

  /// Normalizado: `\` vira `/`, sem `/` nem `./` iniciais.
  final String name;

  /// Como decodificado do central directory, antes da normalização.
  final String rawName;

  /// Bytes do nome no central directory (orçamento da leitura do `fetch`).
  final int nameLength;

  final int flags;
  final int method;
  final int compressedSize;
  final int uncompressedSize;

  /// Já com o `delta` do prefixo.
  final int localHeaderOffset;

  final int crc32;

  /// Motivo de a entrada não ser legível (§5.1 item 7); `null` se válida.
  final String? invalidReason;

  bool get isDirectory => name.isEmpty || name.endsWith('/');
}

/// Resultado de uma busca no índice.
typedef ZipLookup = ({ZipEntry entry, bool exact});

/// Central directory lido e indexado.
final class CentralDirectory {
  CentralDirectory._({
    required this.entries,
    required this.length,
    required this.cdOffset,
    required this.cdSize,
    required this.delta,
    required this.zip64,
  });

  /// Todas as entradas, na ordem do central directory, inclusive diretórios
  /// e duplicatas.
  final List<ZipEntry> entries;

  /// Tamanho da fonte.
  final int length;

  /// Offset do central directory, já com [delta].
  final int cdOffset;
  final int cdSize;

  /// Bytes antes do ZIP (EPUB colado depois de outro arquivo).
  final int delta;

  final bool zip64;

  final Map<String, ZipEntry> _byName = {};
  final Map<String, ZipEntry> _byLowerName = {};
  final List<String> _paths = [];

  /// Arquivos (sem diretórios), primeira ocorrência de cada nome, na ordem do
  /// central directory.
  List<String> get paths => List.unmodifiable(_paths);

  /// Exato; senão, sem diferenciar maiúsculas (vence a primeira entrada).
  ZipLookup? lookup(String path) {
    final exact = _byName[path];
    if (exact != null) return (entry: exact, exact: true);
    final folded = _byLowerName[path.toLowerCase()];
    if (folded != null) return (entry: folded, exact: false);
    return null;
  }

  void _index(DiagnosticSink sink) {
    for (final e in entries) {
      if (e.isDirectory) continue;
      if (_byName.containsKey(e.name)) {
        sink.emit(
          EpubDiagnosticCode.zipDuplicateEntry,
          href: e.name,
          message: 'entrada repetida no central directory; vale a primeira',
          details: {'rawName': e.rawName},
        );
        continue;
      }
      _byName[e.name] = e;
      _byLowerName.putIfAbsent(e.name.toLowerCase(), () => e);
      _paths.add(e.name);
    }
  }
}

/// Normalização de nome de §5.1 item 5.
String normalizeEntryName(String raw) {
  var name = raw.replaceAll(r'\', '/');
  while (true) {
    if (name.startsWith('/')) {
      name = name.substring(1);
    } else if (name.startsWith('./')) {
      name = name.substring(2);
    } else {
      return name;
    }
  }
}

/// Lê o fim do arquivo e o central directory. Exceções da fonte viram
/// [EpubContainerException] com `cause`.
Future<CentralDirectory> readCentralDirectory(
  EpubByteSource source, {
  required DiagnosticSink sink,
}) async {
  final length = await _guard(() => source.length);
  final tailLength = math.min(length, tailReadSize);
  final tailStart = length - tailLength;
  final tail = await _read(source, tailStart, tailLength);

  final at = _findEocd(tail);
  if (at == null) {
    throw EpubContainerException(
      'fim do central directory (EOCD) não encontrado',
    );
  }
  final eocdPos = tailStart + at;
  var disk = readU16(tail, at + 4);
  var cdDisk = readU16(tail, at + 6);
  int? cdSize = readU32(tail, at + 12);
  int? cdOffset = readU32(tail, at + 16);
  var cdEnd = eocdPos;
  var zip64 = false;

  if (at >= _locatorSize &&
      readU32(tail, at - _locatorSize) == _locatorSignature) {
    final loc = at - _locatorSize;
    final totalDisks = readU32(tail, loc + 16);
    if (readU32(tail, loc + 4) != 0 || totalDisks > 1) {
      throw EpubContainerException('ZIP em vários discos não é suportado');
    }
    final declared = readU64(tail, loc + 8);
    final eocd64 = await _findEocd64(
      source,
      tail,
      tailStart,
      declared,
      eocdPos,
    );
    if (eocd64 == null) {
      throw EpubContainerException('registro EOCD64 não encontrado');
    }
    zip64 = true;
    cdEnd = eocd64.pos;
    disk = readU32(eocd64.bytes, 16);
    cdDisk = readU32(eocd64.bytes, 20);
    cdSize = readU64(eocd64.bytes, 40);
    cdOffset = readU64(eocd64.bytes, 48);
  }

  if (disk != 0 || cdDisk != 0) {
    throw EpubContainerException('ZIP em vários discos não é suportado');
  }
  if (cdSize == null || cdOffset == null || cdSize > cdEnd) {
    throw EpubContainerException('central directory não cabe no arquivo');
  }
  final delta = cdEnd - cdSize - cdOffset;
  if (delta < 0) {
    throw EpubContainerException(
      'central directory não cabe no arquivo (offset além do fim)',
    );
  }
  if (delta > 0) {
    sink.emit(
      EpubDiagnosticCode.mimetypeIrregular,
      message: '$delta bytes antes do ZIP',
      details: {'reason': 'prefix', 'delta': delta},
    );
  }

  final cd = await _read(source, cdOffset + delta, cdSize);
  final entries = _parseEntries(cd, delta: delta, length: length);
  return CentralDirectory._(
    entries: entries,
    length: length,
    cdOffset: cdOffset + delta,
    cdSize: cdSize,
    delta: delta,
    zip64: zip64,
  ).._index(sink);
}

/// Posição do EOCD em [tail], de trás para frente; o candidato só vale se o
/// comentário termina exatamente no fim do bloco.
int? _findEocd(Uint8List tail) {
  for (var pos = tail.length - _eocdSize; pos >= 0; pos--) {
    if (tail[pos] == 0x50 &&
        tail[pos + 1] == 0x4b &&
        readU32(tail, pos) == _eocdSignature &&
        pos + _eocdSize + readU16(tail, pos + 20) == tail.length) {
      return pos;
    }
  }
  return null;
}

/// O EOCD64 no offset declarado pelo locator; se não estiver lá (prefixo),
/// logo antes do locator.
Future<({int pos, Uint8List bytes})?> _findEocd64(
  EpubByteSource source,
  Uint8List tail,
  int tailStart,
  int? declared,
  int eocdPos,
) async {
  final candidates = [?declared, eocdPos - _locatorSize - _eocd64Size];
  for (final pos in candidates) {
    if (pos < 0 || pos + _eocd64Size > eocdPos - _locatorSize) continue;
    final bytes = pos >= tailStart
        ? Uint8List.sublistView(
            tail,
            pos - tailStart,
            pos - tailStart + _eocd64Size,
          )
        : await _read(source, pos, _eocd64Size);
    if (readU32(bytes, 0) == _eocd64Signature) return (pos: pos, bytes: bytes);
  }
  return null;
}

List<ZipEntry> _parseEntries(
  Uint8List cd, {
  required int delta,
  required int length,
}) {
  final entries = <ZipEntry>[];
  var p = 0;
  while (p < cd.length) {
    if (p + 46 > cd.length) {
      throw EpubContainerException('central directory truncado');
    }
    if (readU32(cd, p) != _centralSignature) {
      throw EpubContainerException(
        'assinatura de entrada do central directory errada no byte $p',
      );
    }
    final flags = readU16(cd, p + 8);
    final method = readU16(cd, p + 10);
    final crc = readU32(cd, p + 16);
    int? compressed = readU32(cd, p + 20);
    int? uncompressed = readU32(cd, p + 24);
    final nameLength = readU16(cd, p + 28);
    final extraLength = readU16(cd, p + 30);
    final commentLength = readU16(cd, p + 32);
    int? offset = readU32(cd, p + 42);
    final nameStart = p + 46;
    final extraStart = nameStart + nameLength;
    final end = extraStart + extraLength + commentLength;
    if (end > cd.length) {
      throw EpubContainerException('central directory truncado');
    }
    final nameBytes = Uint8List.sublistView(cd, nameStart, extraStart);
    final rawName = _decodeName(nameBytes, utf8Flag: flags & 0x0800 != 0);
    final name = normalizeEntryName(rawName);
    if (flags & 0x0001 != 0) {
      throw EpubEncryptedException(
        'entrada com a criptografia do próprio ZIP: $name',
        scheme: 'zip-encryption',
        href: name,
      );
    }

    // Campos 0xFFFFFFFF vêm do extra 0x0001, na ordem da especificação.
    var q = extraStart;
    final extraEnd = extraStart + extraLength;
    while (q + 4 <= extraEnd) {
      final id = readU16(cd, q);
      final size = readU16(cd, q + 2);
      final dataEnd = q + 4 + size;
      if (dataEnd > extraEnd) break;
      if (id == 0x0001) {
        var f = q + 4;
        int? next() {
          if (f + 8 > dataEnd) return null;
          final v = readU64(cd, f);
          f += 8;
          return v;
        }

        if (uncompressed == 0xFFFFFFFF) uncompressed = next();
        if (compressed == 0xFFFFFFFF) compressed = next();
        if (offset == 0xFFFFFFFF) offset = next();
        break;
      }
      q = dataEnd;
    }

    String? invalid;
    if (compressed == null || uncompressed == null || offset == null) {
      invalid = 'tamanho ou offset acima de 2^53';
    } else if (offset + delta >= length) {
      invalid = 'local header além do fim do arquivo';
    } else if (offset + delta + 30 + compressed > length) {
      invalid = 'dados da entrada além do fim do arquivo';
    } else if (uncompressed > maxEntrySize) {
      invalid = 'tamanho descomprimido acima de $maxEntrySize bytes';
    }

    entries.add(
      ZipEntry(
        name: name,
        rawName: rawName,
        nameLength: nameLength,
        flags: flags,
        method: method,
        compressedSize: compressed ?? 0,
        uncompressedSize: uncompressed ?? 0,
        localHeaderOffset: (offset ?? 0) + delta,
        crc32: crc,
        invalidReason: invalid,
      ),
    );
    p = end;
  }
  return entries;
}

/// Bit 11: UTF-8 tolerante. Sem ele: UTF-8 se válido, senão CP437.
String _decodeName(Uint8List bytes, {required bool utf8Flag}) {
  if (utf8Flag) return utf8.decode(bytes, allowMalformed: true);
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return decodeCp437(bytes);
  }
}

/// `readRange` com as exceções da fonte (`FileSystemException`,
/// `RangeError`, `StateError`) embrulhadas em [EpubContainerException].
Future<Uint8List> readSource(
  EpubByteSource source,
  int offset,
  int length, {
  String? href,
}) => _guard(() => source.readRange(offset, length), href: href);

Future<Uint8List> _read(EpubByteSource source, int offset, int length) =>
    readSource(source, offset, length);

Future<T> _guard<T>(Future<T> Function() op, {String? href}) async {
  try {
    return await op();
  } on EpubException {
    rethrow;
  } on Object catch (e) {
    throw EpubContainerException(
      'falha ao ler a fonte: $e',
      href: href,
      cause: e,
    );
  }
}
```

- [ ] **Passo 5: Rodar e ver passar**

Run: `flutter test test/container/central_directory_test.dart`
Expected: `All tests passed!` (29 testes).

- [ ] **Passo 6: Formatar e analisar**

Run: `dart format lib/src/container/zip test/container && flutter analyze`
Expected: nada mudado e `No issues found!`.

- [ ] **Passo 7: Commit**

```bash
git add lib/src/container/zip/central_directory.dart test/container/central_directory_test.dart test/container/support/zip_fixtures.dart
git commit -m "feat(container): EOCD, ZIP64 e central directory

Busca do EOCD com comentário (e assinatura falsa dentro dele), locator e
EOCD64, prefixo com delta, percurso por cdSize, nomes em UTF-8 ou CP437
com normalização, duplicatas, validação por entrada e os fatais de §5.1."
```

---

### Tarefa 6: `ZipContainer` (sem DRM)

Spec §5 (`open`, `paths`, `exists`, `fetch` com uma `readRange`, `mimetype`
de §5.2, `close`). O DRM entra na Tarefa 7; aqui `obfuscationOf` devolve
`null`.

**Arquivos:**
- Criar: `lib/src/container/zip/zip_container.dart`
- Teste: `test/container/zip_container_test.dart`

**Interfaces:**
- Consome: `readCentralDirectory`, `readSource`, `CentralDirectory.lookup`, `ZipEntry` (Tarefa 5); `PendingResource.zip`, `EpubContainer`, `FontObfuscation` (Tarefa 4); `readU16`, `readU32` (Tarefa 3); `DiagnosticSink`, `EpubDiagnosticCode.pathCaseMismatch`/`mimetypeIrregular` (Tarefa 1); do apoio de teste, `CountingByteSource`, `withLocalExtra`, `withDataDescriptor`, `withMethod`, `withFlagBits`, `patchLocalU16`, `patchCentralU32`, `withPrefix`, `ZipLayout`, `ZipWriter`.
- Produz: `final class ZipContainer implements EpubContainer { static Future<ZipContainer> open(EpubByteSource source, {required DiagnosticSink sink}); @visibleForTesting final CentralDirectory centralDirectory; }` — `open` fecha a fonte se falhar; `fetch`/`exists` depois de `close` lançam `StateError`.

- [ ] **Passo 1: Escrever o teste que falha**

Criar `test/container/zip_container_test.dart`. Os testes "extra do local
header que empurra os dados para além do fim", "falha da fonte no fetch" e
"abertura que falha fecha a fonte" são os itens 2, 3 e 1 do Foco de revisão:

```dart
// ZipContainer: fetch, leituras, mimetype e close (spec do contêiner §5).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/container/byte_source.dart';
import 'package:galley/src/container/container.dart';
import 'package:galley/src/container/zip/zip_container.dart';
import 'package:galley/src/diagnostics/diagnostic.dart';
import 'package:galley/src/diagnostics/exceptions.dart';

import 'support/zip_fixtures.dart';

Future<Uint8List> _read(PendingResource r) async {
  for (final _ in r.decode()) {}
  return r.bytes;
}

Future<ZipContainer> _open(Uint8List zip, {DiagnosticSink? sink}) =>
    ZipContainer.open(
      MemoryEpubByteSource(zip),
      sink: sink ?? DiagnosticSink(),
    );

void main() {
  final chapter = prose(40000);
  final image = noise(3000);
  final zip = epubZip({
    'META-INF/container.xml': utf8.encode('<container/>'),
    'OEBPS/Text/cap01.xhtml': chapter,
  });
  final mixed =
      (ZipWriter()
            ..add('mimetype', ascii.encode(epubMimetype), compress: false)
            ..add('OEBPS/Text/cap01.xhtml', chapter)
            ..add('OEBPS/Images/a.png', image, compress: false))
          .build();

  group('fetch', () {
    test('stored e deflate', () async {
      final c = await _open(mixed);
      final text = (await c.fetch('OEBPS/Text/cap01.xhtml'))!;
      expect(text.path, 'OEBPS/Text/cap01.xhtml');
      expect(text.size, chapter.length);
      expect(await _read(text), chapter);
      expect(await _read((await c.fetch('OEBPS/Images/a.png'))!), image);
      expect(c.paths, [
        'mimetype',
        'OEBPS/Text/cap01.xhtml',
        'OEBPS/Images/a.png',
      ]);
    });

    test('ausente devolve null', () async {
      final c = await _open(zip);
      expect(await c.fetch('OEBPS/nada.xhtml'), isNull);
      expect(await c.exists('OEBPS/nada.xhtml'), isFalse);
    });

    test('uma readRange por fetch, dentro do orçamento', () async {
      final counting = CountingByteSource(MemoryEpubByteSource(mixed));
      final c = await ZipContainer.open(counting, sink: DiagnosticSink());
      final entry = c.centralDirectory.lookup('OEBPS/Text/cap01.xhtml')!.entry;
      counting.reset();
      final r = (await c.fetch('OEBPS/Text/cap01.xhtml'))!;
      expect(counting.calls, 1);
      expect(
        counting.bytesRead,
        lessThanOrEqualTo(30 + entry.nameLength + entry.compressedSize + 1024),
      );
      expect(await _read(r), chapter);
      expect(counting.calls, 1, reason: 'decode não lê da fonte');
    });

    test('extra field grande no local header: duas leituras', () async {
      final big = withLocalExtra(mixed, 1, 5000);
      final counting = CountingByteSource(MemoryEpubByteSource(big));
      final c = await ZipContainer.open(counting, sink: DiagnosticSink());
      final entry = c.centralDirectory.lookup('OEBPS/Text/cap01.xhtml')!.entry;
      counting.reset();
      final r = (await c.fetch('OEBPS/Text/cap01.xhtml'))!;
      expect(counting.calls, 2);
      expect(counting.ranges.last.$2, entry.compressedSize);
      expect(await _read(r), chapter);
      expect(await _read((await c.fetch('OEBPS/Images/a.png'))!), image);
    });

    test(
      'extra do local header que empurra os dados para além do fim',
      () async {
        final bad = patchLocalU16(mixed, 2, 28, 60000);
        final c = await _open(bad);
        await expectLater(
          c.fetch('OEBPS/Images/a.png'),
          throwsA(
            isA<EpubContainerException>().having(
              (e) => e.href,
              'href',
              'OEBPS/Images/a.png',
            ),
          ),
        );
      },
    );

    test(
      'data descriptor: valem os tamanhos e o CRC do central directory',
      () async {
        final sink = DiagnosticSink(strict: true);
        final c = await _open(withDataDescriptor(mixed, 1), sink: sink);
        expect(
          await _read((await c.fetch('OEBPS/Text/cap01.xhtml'))!),
          chapter,
        );
        expect(sink.diagnostics, isEmpty);
      },
    );

    test('método 12 lança EpubContainerException(href)', () async {
      final c = await _open(withMethod(mixed, 1, 12));
      await expectLater(
        c.fetch('OEBPS/Text/cap01.xhtml'),
        throwsA(
          isA<EpubContainerException>()
              .having((e) => e.href, 'href', 'OEBPS/Text/cap01.xhtml')
              .having((e) => e.message, 'message', contains('12')),
        ),
      );
    });

    test('assinatura do local header errada', () async {
      final l = ZipLayout(mixed);
      final bad = Uint8List.fromList(mixed)..[l.local[2]] = 0;
      final c = await _open(bad);
      await expectLater(
        c.fetch('OEBPS/Images/a.png'),
        throwsA(isA<EpubContainerException>()),
      );
    });

    test(
      'entrada inválida lança EpubContainerException com o motivo',
      () async {
        final bad = patchCentralU32(mixed, 2, cdUncompressed, maxEntrySize + 1);
        final c = await _open(bad);
        expect(await c.exists('OEBPS/Images/a.png'), isTrue);
        await expectLater(
          c.fetch('OEBPS/Images/a.png'),
          throwsA(
            isA<EpubContainerException>().having(
              (e) => e.message,
              'message',
              contains('$maxEntrySize'),
            ),
          ),
        );
      },
    );

    test(
      'falha da fonte no fetch vira EpubContainerException com cause',
      () async {
        final inner = MemoryEpubByteSource(mixed);
        final c = await ZipContainer.open(inner, sink: DiagnosticSink());
        await inner.close(); // a fonte some por baixo do contêiner
        await expectLater(
          c.fetch('OEBPS/Images/a.png'),
          throwsA(
            isA<EpubContainerException>().having(
              (e) => e.cause,
              'cause',
              isStateError,
            ),
          ),
        );
      },
    );
  });

  test('bit 0 ligado lança EpubEncryptedException na abertura', () async {
    await expectLater(
      _open(withFlagBits(mixed, 2, 0x0001)),
      throwsA(
        isA<EpubEncryptedException>().having(
          (e) => e.scheme,
          'scheme',
          'zip-encryption',
        ),
      ),
    );
  });

  group('sem diferenciar maiúsculas', () {
    test('fetch acha e emite pathCaseMismatch; exists não emite', () async {
      final sink = DiagnosticSink();
      final c = await _open(mixed, sink: sink);
      expect(await c.exists('oebps/text/CAP01.xhtml'), isTrue);
      expect(sink.diagnostics, isEmpty);
      final r = (await c.fetch('oebps/text/CAP01.xhtml'))!;
      expect(r.path, 'OEBPS/Text/cap01.xhtml');
      expect(await _read(r), chapter);
      final d = sink.diagnostics.single;
      expect(d.code, EpubDiagnosticCode.pathCaseMismatch);
      expect(d.href, 'oebps/text/CAP01.xhtml');
      expect(d.details['actual'], 'OEBPS/Text/cap01.xhtml');
    });
  });

  group('mimetype', () {
    Future<List<EpubDiagnostic>> diagnosticsOf(Uint8List z) async {
      final sink = DiagnosticSink();
      await _open(z, sink: sink);
      return sink.diagnostics;
    }

    Uint8List build({
      bool include = true,
      bool first = true,
      bool compress = false,
      String content = epubMimetype,
    }) {
      final w = ZipWriter();
      void mimetype() =>
          w.add('mimetype', ascii.encode(content), compress: compress);
      if (include && first) mimetype();
      w.add('OEBPS/a.xhtml', prose(100));
      if (include && !first) mimetype();
      return w.build();
    }

    test('regular: nenhum diagnóstico', () async {
      expect(await diagnosticsOf(build()), isEmpty);
    });

    for (final (reason, z) in [
      ('missing', build(include: false)),
      ('notFirst', build(first: false)),
      ('compressed', build(compress: true)),
      ('content', build(content: 'application/zip')),
      ('unreadable', Uint8List.fromList(build())..[0] = 0),
    ]) {
      test('$reason: mimetypeIrregular info, nunca fatal', () async {
        final d = (await diagnosticsOf(z)).single;
        expect(d.code, EpubDiagnosticCode.mimetypeIrregular);
        expect(d.severity, EpubSeverity.info);
        expect(d.details['reason'], reason);
      });
    }

    test('com prefixo: só o diagnóstico do prefixo', () async {
      final ds = await diagnosticsOf(withPrefix(build(), 10));
      expect(ds.single.details['reason'], 'prefix');
    });

    test('strict: vira warning e lança', () async {
      await expectLater(
        _open(build(first: false), sink: DiagnosticSink(strict: true)),
        throwsA(isA<EpubContainerException>()),
      );
    });
  });

  group('close', () {
    test('fecha a fonte, é idempotente e bloqueia fetch', () async {
      final counting = CountingByteSource(MemoryEpubByteSource(zip));
      final c = await ZipContainer.open(counting, sink: DiagnosticSink());
      await c.close();
      await c.close();
      expect(counting.closed, isTrue);
      await expectLater(c.fetch('mimetype'), throwsStateError);
    });

    test('abertura que falha fecha a fonte', () async {
      final counting = CountingByteSource(
        MemoryEpubByteSource(Uint8List.sublistView(zip, 0, zip.length - 10)),
      );
      await expectLater(
        ZipContainer.open(counting, sink: DiagnosticSink()),
        throwsA(isA<EpubContainerException>()),
      );
      expect(counting.closed, isTrue);
    });
  });

  test('obfuscationOf é null sem encryption.xml', () async {
    final c = await _open(zip);
    expect(c.obfuscationOf('OEBPS/Text/cap01.xhtml'), isNull);
  });
}
```

- [ ] **Passo 2: Rodar e ver falhar**

Run: `flutter test test/container/zip_container_test.dart`
Expected: FAIL na compilação, com `Error when reading 'lib/src/container/zip/zip_container.dart'`.

- [ ] **Passo 3: Implementar**

Criar `lib/src/container/zip/zip_container.dart`:

```dart
/// Contêiner sobre um `.epub` (ZIP) lido por faixas (spec do contêiner §5).
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../../diagnostics/diagnostic.dart';
import '../../diagnostics/exceptions.dart';
import '../byte_source.dart';
import '../container.dart';
import 'binary.dart';
import 'central_directory.dart';

const int _localSignature = 0x04034b50;

final class ZipContainer implements EpubContainer {
  ZipContainer._(this._source, this._sink, this.centralDirectory);

  final EpubByteSource _source;
  final DiagnosticSink _sink;

  /// Central directory lido na abertura (testes e orçamento de leitura).
  @visibleForTesting
  final CentralDirectory centralDirectory;

  Future<void>? _closing;

  /// Lê o central directory e confere o `mimetype`. Exceção da fonte
  /// vira [EpubContainerException] com `cause`. Se a abertura falha, a fonte
  /// é fechada.
  static Future<ZipContainer> open(
    EpubByteSource source, {
    required DiagnosticSink sink,
  }) async {
    try {
      final cd = await readCentralDirectory(source, sink: sink);
      final container = ZipContainer._(source, sink, cd);
      await container._checkMimetype();
      return container;
    } on Object {
      try {
        await source.close();
      } on Object {
        // A falha original é a que importa.
      }
      rethrow;
    }
  }

  @override
  Iterable<String> get paths => centralDirectory.paths;

  @override
  Future<bool> exists(String path) async {
    _checkOpen();
    return centralDirectory.lookup(path) != null;
  }

  @override
  Future<PendingResource?> fetch(String path) async {
    _checkOpen();
    final hit = centralDirectory.lookup(path);
    if (hit == null) return null;
    final e = hit.entry;
    if (!hit.exact) {
      _sink.emit(
        EpubDiagnosticCode.pathCaseMismatch,
        href: path,
        message: 'caminho achado só sem diferenciar maiúsculas: ${e.name}',
        details: {'actual': e.name},
      );
    }
    final invalid = e.invalidReason;
    if (invalid != null) throw EpubContainerException(invalid, href: path);
    if (e.method != 0 && e.method != 8) {
      throw EpubContainerException(
        'método de compressão ${e.method} não suportado',
        href: path,
      );
    }

    final length = centralDirectory.length;
    final offset = e.localHeaderOffset;
    final first = await readSource(
      _source,
      offset,
      math.min(30 + e.nameLength + e.compressedSize + 1024, length - offset),
      href: path,
    );
    if (first.length < 30 || readU32(first, 0) != _localSignature) {
      throw EpubContainerException('local header inválido', href: path);
    }
    final dataStart = 30 + readU16(first, 26) + readU16(first, 28);
    final Uint8List data;
    if (dataStart + e.compressedSize <= first.length) {
      data = Uint8List.sublistView(
        first,
        dataStart,
        dataStart + e.compressedSize,
      );
    } else {
      if (offset + dataStart + e.compressedSize > length) {
        throw EpubContainerException(
          'dados da entrada além do fim do arquivo',
          href: path,
        );
      }
      data = await readSource(
        _source,
        offset + dataStart,
        e.compressedSize,
        href: path,
      );
    }
    return PendingResource.zip(
      path: e.name,
      size: e.uncompressedSize,
      method: e.method,
      data: data,
      crc32: e.crc32,
      sink: _sink,
    );
  }

  /// Sem `encryption.xml` lido ainda: nenhuma fonte ofuscada.
  @override
  FontObfuscation? obfuscationOf(String path) => null;

  @override
  Future<void> close() => _closing ??= _source.close();

  void _checkOpen() {
    if (_closing != null) throw StateError('ZipContainer fechado');
  }

  /// §5.2: primeira entrada (menor offset, e esse offset é o início do ZIP),
  /// stored, conteúdo exato. Nunca fatal.
  Future<void> _checkMimetype() async {
    final reason = await _mimetypeProblem();
    if (reason == null) return;
    _sink.emit(
      EpubDiagnosticCode.mimetypeIrregular,
      href: 'mimetype',
      message: switch (reason) {
        'missing' => 'entrada mimetype ausente',
        'notFirst' => 'mimetype não é a primeira entrada do ZIP',
        'compressed' => 'mimetype comprimido (deveria ser stored)',
        'content' => 'mimetype com conteúdo diferente de application/epub+zip',
        _ => 'mimetype ilegível',
      },
      details: {'reason': reason},
    );
  }

  Future<String?> _mimetypeProblem() async {
    final cd = centralDirectory;
    final hit = cd.lookup('mimetype');
    if (hit == null || !hit.exact) return 'missing';
    final entry = hit.entry;
    final first = cd.entries.reduce(
      (a, b) => b.localHeaderOffset < a.localHeaderOffset ? b : a,
    );
    if (!identical(first, entry) || entry.localHeaderOffset != cd.delta) {
      return 'notFirst';
    }
    if (entry.method != 0) return 'compressed';
    try {
      final pending = (await fetch('mimetype'))!;
      for (final _ in pending.decode()) {}
      final text = latin1.decode(pending.bytes);
      return text == 'application/epub+zip' ? null : 'content';
    } on EpubContainerException {
      return 'unreadable';
    }
  }
}
```

- [ ] **Passo 4: Rodar e ver passar**

Run: `flutter test test/container/zip_container_test.dart`
Expected: `All tests passed!` (23 testes).

- [ ] **Passo 5: Suíte do contêiner inteira**

Run: `flutter test test/container test/diagnostics`
Expected: `All tests passed!`.

- [ ] **Passo 6: Formatar e analisar**

Run: `dart format lib/src/container test/container && flutter analyze`
Expected: nada mudado e `No issues found!`.

- [ ] **Passo 7: Commit**

```bash
git add lib/src/container/zip/zip_container.dart test/container/zip_container_test.dart
git commit -m "feat(container): ZipContainer com fetch numa ida à fonte e mimetype

fetch com uma readRange (duas com extra grande no local header), data
descriptor pelo central directory, métodos 0 e 8, busca sem diferenciar
maiúsculas com pathCaseMismatch, os cinco casos de mimetype irregular e
fonte fechada quando a abertura falha."
```

---

### Tarefa 7: `encryption.xml`, `rights.xml` e DRM

Spec §6 (a tabela, na ordem dela). Integra no `ZipContainer.open` depois do
central directory e do `mimetype`: licença LCP, `rights.xml`,
`encryption.xml`.

**Arquivos:**
- Criar: `lib/src/container/encryption.dart`
- Modificar: `lib/src/container/zip/zip_container.dart` (substituir inteiro)
- Teste: `test/container/encryption_test.dart`

**Interfaces:**
- Consome: `normalizeEntryName`, `CentralDirectory.lookup` (Tarefa 5); `FontObfuscation` (Tarefa 4); `DiagnosticSink`, `EpubDiagnosticCode.fontObfuscationUnknown`, `EpubEncryptedException` (Tarefa 1); `package:xml` (`XmlDocument.parse`, `findAllElements(name, namespaceUri: '*')`, `findElements`, `getAttribute`, `namespaceUri`, `descendantElements`, `XmlException`).
- Produz: `const String idpfObfuscationAlgorithm = 'http://www.idpf.org/2008/embedding';`, `const String adobeObfuscationAlgorithm = 'http://ns.adobe.com/pdf/enc#RC';`, `const String lcpContentKeyType = 'http://readium.org/2014/01/lcp#EncryptedContentKey';`, `const String adeptNamespace = 'http://ns.adobe.com/adept';`.
- Produz: `bool isFontPath(String path)`, `String normalizeCipherReference(String uri)`.
- Produz: `final class EncryptedItem { const EncryptedItem({required String algorithm, required String uri, required bool lcpKey, required bool adeptKey}); }`.
- Produz: `List<EncryptedItem> parseEncryptionXml(String text)` (lança `XmlException`), `String rightsScheme(String text)`.
- Produz: `Map<String, FontObfuscation> resolveEncryption(List<EncryptedItem> items, {required String Function(String uri) resolve, required DiagnosticSink sink, required bool drmIsFatal})` — a Tarefa 9 usa com `drmIsFatal: false`.
- Produz: `ZipContainer.obfuscationOf` passa a responder pelo mapa lido na abertura.

- [ ] **Passo 1: Escrever o teste que falha**

Criar `test/container/encryption_test.dart`:

```dart
// encryption.xml, rights.xml, LCP e ofuscação de fontes (spec §6).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/container/byte_source.dart';
import 'package:galley/src/container/container.dart';
import 'package:galley/src/container/encryption.dart';
import 'package:galley/src/container/zip/zip_container.dart';
import 'package:galley/src/diagnostics/diagnostic.dart';
import 'package:galley/src/diagnostics/exceptions.dart';
import 'package:xml/xml.dart';

import 'support/zip_fixtures.dart';

const _aes = 'http://www.w3.org/2001/04/xmlenc#aes256-cbc';
const _font = 'OEBPS/Fonts/a.ttf';
const _text = 'OEBPS/Text/cap01.xhtml';

/// Um `EncryptedData` com o prefixo `enc:`.
String _data(String? uri, {String? algorithm = _aes, String keyInfo = ''}) =>
    '<enc:EncryptedData>'
    '${algorithm == null ? '' : '<enc:EncryptionMethod Algorithm="$algorithm"/>'}'
    '$keyInfo'
    '${uri == null ? '' : '<enc:CipherData><enc:CipherReference URI="$uri"/></enc:CipherData>'}'
    '</enc:EncryptedData>';

String _encryption(List<String> data) =>
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container" '
    'xmlns:enc="http://www.w3.org/2001/04/xmlenc#">${data.join()}</encryption>';

Uint8List _book(Map<String, String> meta, {Map<String, List<int>>? extra}) =>
    epubZip({
      'META-INF/container.xml': utf8.encode('<container/>'),
      for (final MapEntry(:key, :value) in meta.entries)
        key: utf8.encode(value),
      _text: prose(2000),
      _font: noise(3000),
      ...?extra,
    });

Future<ZipContainer> _open(Uint8List zip, {DiagnosticSink? sink}) =>
    ZipContainer.open(
      MemoryEpubByteSource(zip),
      sink: sink ?? DiagnosticSink(),
    );

Matcher _encrypted(String scheme) => throwsA(
  isA<EpubEncryptedException>()
      .having((e) => e.scheme, 'scheme', scheme)
      .having((e) => e.message, 'message', contains(scheme)),
);

void main() {
  group('arquivos de licença', () {
    test('META-INF/license.lcpl → lcp', () async {
      await expectLater(
        _open(_book({'META-INF/license.lcpl': '{}'})),
        _encrypted('lcp'),
      );
    });

    test('rights.xml com namespace do ADEPT → adobe-adept', () async {
      const rights =
          '<adept:rights xmlns:adept="http://ns.adobe.com/adept">'
          '<adept:licenseToken/></adept:rights>';
      await expectLater(
        _open(_book({'META-INF/rights.xml': rights})),
        _encrypted('adobe-adept'),
      );
    });

    test('rights.xml sem namespace conhecido → unknown:rights.xml', () async {
      await expectLater(
        _open(_book({'META-INF/rights.xml': '<rights/>'})),
        _encrypted('unknown:rights.xml'),
      );
    });

    test('rights.xml inválido → unknown:rights.xml', () async {
      await expectLater(
        _open(_book({'META-INF/rights.xml': '<rights'})),
        _encrypted('unknown:rights.xml'),
      );
    });

    test('licença LCP vence encryption.xml de fonte', () async {
      final meta = {
        'META-INF/license.lcpl': '{}',
        'META-INF/encryption.xml': _encryption([
          _data(_font, algorithm: idpfObfuscationAlgorithm),
        ]),
      };
      await expectLater(_open(_book(meta)), _encrypted('lcp'));
    });
  });

  group('encryption.xml', () {
    Future<ZipContainer> withEncryption(
      List<String> data, {
      DiagnosticSink? sink,
    }) => _open(
      _book({'META-INF/encryption.xml': _encryption(data)}),
      sink: sink,
    );

    test('XML inválido → unknown:encryption.xml-invalido com cause', () async {
      await expectLater(
        _open(_book({'META-INF/encryption.xml': '<encryption><enc:Encrypted'})),
        throwsA(
          isA<EpubEncryptedException>()
              .having(
                (e) => e.scheme,
                'scheme',
                'unknown:encryption.xml-invalido',
              )
              .having((e) => e.cause, 'cause', isA<XmlException>()),
        ),
      );
    });

    test('RetrievalMethod do LCP → lcp', () async {
      const keyInfo =
          '<ds:KeyInfo xmlns:ds="http://www.w3.org/2000/09/xmldsig#">'
          '<ds:RetrievalMethod URI="license.lcpl#/encryption/content_key" '
          'Type="http://readium.org/2014/01/lcp#EncryptedContentKey"/>'
          '</ds:KeyInfo>';
      await expectLater(
        withEncryption([_data(_text, keyInfo: keyInfo)]),
        _encrypted('lcp'),
      );
    });

    test('KeyInfo com namespace do ADEPT → adobe-adept', () async {
      const keyInfo =
          '<KeyInfo xmlns="http://www.w3.org/2000/09/xmldsig#">'
          '<resource xmlns="http://ns.adobe.com/adept">urn:uuid:1</resource>'
          '</KeyInfo>';
      await expectLater(
        withEncryption([_data(_text, keyInfo: keyInfo)]),
        _encrypted('adobe-adept'),
      );
    });

    test(
      'cifra sobre caminho que não é fonte → unknown:<primeiro URI>',
      () async {
        await expectLater(
          withEncryption([
            _data(_font, algorithm: idpfObfuscationAlgorithm),
            _data(_text, algorithm: 'urn:cifra:primeira'),
            _data('OEBPS/Text/cap02.xhtml', algorithm: 'urn:cifra:segunda'),
          ]),
          _encrypted('unknown:urn:cifra:primeira'),
        );
      },
    );

    test(
      'ofuscação IDPF sobre caminho que não é fonte → unknown:<uri>',
      () async {
        await expectLater(
          withEncryption([_data(_text, algorithm: idpfObfuscationAlgorithm)]),
          _encrypted('unknown:$idpfObfuscationAlgorithm'),
        );
      },
    );

    test(
      'ofuscação Adobe sobre caminho que não é fonte → unknown:<uri>',
      () async {
        await expectLater(
          withEncryption([_data(_text, algorithm: adobeObfuscationAlgorithm)]),
          _encrypted('unknown:$adobeObfuscationAlgorithm'),
        );
      },
    );

    test('IDPF sobre fonte → idpf', () async {
      final c = await withEncryption([
        _data(_font, algorithm: idpfObfuscationAlgorithm),
      ]);
      expect(c.obfuscationOf(_font), FontObfuscation.idpf);
      expect(c.obfuscationOf(_text), isNull);
    });

    test('Adobe sobre fonte → adobe', () async {
      final c = await withEncryption([
        _data(_font, algorithm: adobeObfuscationAlgorithm),
      ]);
      expect(c.obfuscationOf(_font), FontObfuscation.adobe);
    });

    test(
      'algoritmo desconhecido só sobre fontes → unknown + warning',
      () async {
        final sink = DiagnosticSink();
        final c = await withEncryption([
          _data(_font, algorithm: _aes),
        ], sink: sink);
        expect(c.obfuscationOf(_font), FontObfuscation.unknown);
        final d = sink.diagnostics.single;
        expect(d.code, EpubDiagnosticCode.fontObfuscationUnknown);
        expect(d.severity, EpubSeverity.warning);
        expect(d.href, _font);
        expect(d.details['algorithm'], _aes);
      },
    );

    test('EncryptionMethod ausente é tratado como algoritmo vazio', () async {
      final sink = DiagnosticSink();
      final c = await withEncryption([
        _data(_font, algorithm: null),
      ], sink: sink);
      expect(c.obfuscationOf(_font), FontObfuscation.unknown);
      expect(sink.diagnostics.single.details['algorithm'], '');
      await expectLater(
        withEncryption([_data(_text, algorithm: null)]),
        _encrypted('unknown:'),
      );
    });

    test('strict: fonte desconhecida lança', () async {
      await expectLater(
        withEncryption([_data(_font)], sink: DiagnosticSink(strict: true)),
        throwsA(isA<EpubContainerException>()),
      );
    });

    test('BOM UTF-8 antes da declaração XML não torna o XML inválido', () async {
      final xml =
          '\uFEFF${_encryption([_data(_font, algorithm: idpfObfuscationAlgorithm)])}';
      final c = await _open(_book({'META-INF/encryption.xml': xml}));
      expect(c.obfuscationOf(_font), FontObfuscation.idpf);
    });

    test('EncryptedData sem CipherReference é ignorado', () async {
      final c = await withEncryption([_data(null)]);
      expect(c.obfuscationOf(_text), isNull);
    });

    test('extensão de fonte em maiúsculas', () async {
      final zip = _book(
        {
          'META-INF/encryption.xml': _encryption([
            _data('OEBPS/Fonts/B.OTF', algorithm: idpfObfuscationAlgorithm),
          ]),
        },
        extra: {'OEBPS/Fonts/B.OTF': noise(100)},
      );
      final c = await _open(zip);
      expect(c.obfuscationOf('OEBPS/Fonts/B.OTF'), FontObfuscation.idpf);
    });

    test('%xx válido é decodificado; inválido fica cru', () async {
      final zip = _book(
        {
          'META-INF/encryption.xml': _encryption([
            _data(
              'OEBPS/Fonts/minha%20fonte.ttf',
              algorithm: idpfObfuscationAlgorithm,
            ),
            _data('OEBPS/Fonts/100%.ttf', algorithm: adobeObfuscationAlgorithm),
          ]),
        },
        extra: {
          'OEBPS/Fonts/minha fonte.ttf': noise(100),
          'OEBPS/Fonts/100%.ttf': noise(100),
        },
      );
      final c = await _open(zip);
      expect(
        c.obfuscationOf('OEBPS/Fonts/minha fonte.ttf'),
        FontObfuscation.idpf,
      );
      expect(c.obfuscationOf('OEBPS/Fonts/100%.ttf'), FontObfuscation.adobe);
    });

    test(
      'URI com / ou ./ inicial e caixa diferente casa pelo índice',
      () async {
        final c = await withEncryption([
          _data('/oebps/fonts/A.ttf', algorithm: idpfObfuscationAlgorithm),
        ]);
        expect(c.obfuscationOf(_font), FontObfuscation.idpf);
        expect(c.obfuscationOf('oebps/FONTS/a.TTF'), FontObfuscation.idpf);
      },
    );

    test('prefixo de namespace diferente e namespace padrão', () async {
      const xml =
          '<container:encryption '
          'xmlns:container="urn:oasis:names:tc:opendocument:xmlns:container">'
          '<x:EncryptedData xmlns:x="http://www.w3.org/2001/04/xmlenc#">'
          '<x:EncryptionMethod Algorithm="$idpfObfuscationAlgorithm"/>'
          '<x:CipherData><x:CipherReference URI="$_font"/></x:CipherData>'
          '</x:EncryptedData>'
          '<EncryptedData xmlns="http://www.w3.org/2001/04/xmlenc#">'
          '<EncryptionMethod Algorithm="$_aes"/>'
          '<CipherData><CipherReference URI="$_text"/></CipherData>'
          '</EncryptedData>'
          '</container:encryption>';
      await expectLater(
        _open(_book({'META-INF/encryption.xml': xml})),
        _encrypted('unknown:$_aes'),
      );
    });
  });

  group('isFontPath e normalizeCipherReference', () {
    test('extensões de fonte', () {
      for (final p in [
        'a.ttf',
        'a.OTF',
        'a.ttc',
        'a.otc',
        'a.woff',
        'a.WOFF2',
      ]) {
        expect(isFontPath(p), isTrue, reason: p);
      }
      for (final p in ['a.xhtml', 'a.ttf.bak', 'ttf', 'a.svg']) {
        expect(isFontPath(p), isFalse, reason: p);
      }
    });

    test('normalização', () {
      expect(normalizeCipherReference('./a%20b.ttf'), 'a b.ttf');
      expect(
        normalizeCipherReference(r'OEBPS\Fonts\a.ttf'),
        'OEBPS/Fonts/a.ttf',
      );
      expect(normalizeCipherReference('a%zz.ttf'), 'a%zz.ttf');
    });
  });
}
```

- [ ] **Passo 2: Rodar e ver falhar**

Run: `flutter test test/container/encryption_test.dart`
Expected: FAIL na compilação, com `Error when reading 'lib/src/container/encryption.dart'`.

- [ ] **Passo 3: Parse e tabela de §6**

Criar `lib/src/container/encryption.dart`:

```dart
/// `META-INF/encryption.xml`, `rights.xml` e detecção de DRM (spec do
/// contêiner §6).
library;

import 'package:xml/xml.dart';

import '../diagnostics/diagnostic.dart';
import '../diagnostics/exceptions.dart';
import 'container.dart';
import 'zip/central_directory.dart';

const String idpfObfuscationAlgorithm = 'http://www.idpf.org/2008/embedding';
const String adobeObfuscationAlgorithm = 'http://ns.adobe.com/pdf/enc#RC';
const String lcpContentKeyType =
    'http://readium.org/2014/01/lcp#EncryptedContentKey';
const String adeptNamespace = 'http://ns.adobe.com/adept';

const Set<String> _fontExtensions = {
  '.ttf',
  '.otf',
  '.ttc',
  '.otc',
  '.woff',
  '.woff2',
};

/// Extensão de fonte, sem diferenciar maiúsculas.
bool isFontPath(String path) {
  final lower = path.toLowerCase();
  final dot = lower.lastIndexOf('.');
  return dot >= 0 && _fontExtensions.contains(lower.substring(dot));
}

/// `CipherReference URI`: `%xx` decodificado (texto cru se inválido) e a
/// normalização de nome do central directory.
String normalizeCipherReference(String uri) {
  String decoded;
  try {
    decoded = Uri.decodeComponent(uri);
  } on ArgumentError {
    decoded = uri;
  }
  return normalizeEntryName(decoded);
}

/// Um `EncryptedData` com `CipherReference`.
final class EncryptedItem {
  const EncryptedItem({
    required this.algorithm,
    required this.uri,
    required this.lcpKey,
    required this.adeptKey,
  });

  /// `EncryptionMethod@Algorithm`; `''` se ausente.
  final String algorithm;

  /// `CipherReference@URI`, já normalizado.
  final String uri;

  /// `KeyInfo/RetrievalMethod` com o `Type` do LCP.
  final bool lcpKey;

  /// `KeyInfo` com elemento no namespace do ADEPT.
  final bool adeptKey;
}

/// Itens de `encryption.xml`, em ordem de documento. Lê por nome local, em
/// qualquer prefixo ou namespace. `EncryptedData` sem `CipherReference` é
/// ignorado. [XmlException] se o XML for inválido.
List<EncryptedItem> parseEncryptionXml(String text) {
  final doc = XmlDocument.parse(text);
  final items = <EncryptedItem>[];
  for (final data in doc.findAllElements('EncryptedData', namespaceUri: '*')) {
    final reference = data
        .findAllElements('CipherReference', namespaceUri: '*')
        .firstOrNull
        ?.getAttribute('URI');
    if (reference == null) continue;
    final method = data
        .findElements('EncryptionMethod', namespaceUri: '*')
        .firstOrNull;
    final keyInfos = data.findAllElements('KeyInfo', namespaceUri: '*');
    items.add(
      EncryptedItem(
        algorithm: method?.getAttribute('Algorithm') ?? '',
        uri: normalizeCipherReference(reference),
        lcpKey: keyInfos.any(
          (k) => k
              .findAllElements('RetrievalMethod', namespaceUri: '*')
              .any((r) => r.getAttribute('Type') == lcpContentKeyType),
        ),
        adeptKey: keyInfos.any(
          (k) =>
              k.namespaceUri == adeptNamespace ||
              k.descendantElements.any((e) => e.namespaceUri == adeptNamespace),
        ),
      ),
    );
  }
  return items;
}

/// Esquema de `rights.xml`: `adobe-adept` com o namespace do ADEPT, senão
/// `unknown:rights.xml` (inclusive XML inválido).
String rightsScheme(String text) {
  try {
    final doc = XmlDocument.parse(text);
    final adept = doc.descendantElements.any(
      (e) => e.namespaceUri == adeptNamespace,
    );
    return adept ? 'adobe-adept' : 'unknown:rights.xml';
  } on XmlException {
    return 'unknown:rights.xml';
  }
}

/// Aplica a tabela de §6 aos [items]. Com [drmIsFatal] (ZIP), LCP, ADEPT e
/// qualquer cifra sobre caminho que não é fonte lançam
/// [EpubEncryptedException]; sem ele (provider), só as fontes contam.
///
/// [resolve] leva o URI normalizado ao nome da entrada (mesmo índice de
/// `fetch`). Devolve a ofuscação por nome resolvido e emite
/// `fontObfuscationUnknown` para algoritmo desconhecido sobre fonte.
Map<String, FontObfuscation> resolveEncryption(
  List<EncryptedItem> items, {
  required String Function(String uri) resolve,
  required DiagnosticSink sink,
  required bool drmIsFatal,
}) {
  if (drmIsFatal) {
    if (items.any((i) => i.lcpKey)) {
      throw EpubEncryptedException(
        'conteúdo cifrado com Readium LCP (KeyInfo em encryption.xml): '
        'esquema lcp',
        scheme: 'lcp',
      );
    }
    if (items.any((i) => i.adeptKey)) {
      throw EpubEncryptedException(
        'conteúdo cifrado com Adobe ADEPT (KeyInfo em encryption.xml): '
        'esquema adobe-adept',
        scheme: 'adobe-adept',
      );
    }
    for (final item in items) {
      final path = resolve(item.uri);
      if (!isFontPath(path)) {
        throw EpubEncryptedException(
          'recurso cifrado com algoritmo "${item.algorithm}": '
          'esquema unknown:${item.algorithm}',
          scheme: 'unknown:${item.algorithm}',
          href: path,
        );
      }
    }
  }
  final result = <String, FontObfuscation>{};
  for (final item in items) {
    final path = resolve(item.uri);
    if (!isFontPath(path)) continue;
    final kind = switch (item.algorithm) {
      idpfObfuscationAlgorithm => FontObfuscation.idpf,
      adobeObfuscationAlgorithm => FontObfuscation.adobe,
      _ => FontObfuscation.unknown,
    };
    result[path] = kind;
    if (kind == FontObfuscation.unknown) {
      sink.emit(
        EpubDiagnosticCode.fontObfuscationUnknown,
        href: path,
        message: 'fonte com ofuscação não reconhecida: "${item.algorithm}"',
        details: {'algorithm': item.algorithm},
      );
    }
  }
  return result;
}
```

- [ ] **Passo 4: Integrar no `ZipContainer`**

Substituir `lib/src/container/zip/zip_container.dart` inteiro por (muda: imports
de `xml` e `encryption.dart`, o campo `_obfuscation`, `_checkEncryption()` no
`open`, `obfuscationOf` pelo mapa, `_checkEncryption` e `_readText`):

```dart
/// Contêiner sobre um `.epub` (ZIP) lido por faixas (spec do contêiner §5).
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:xml/xml.dart';

import '../../diagnostics/diagnostic.dart';
import '../../diagnostics/exceptions.dart';
import '../byte_source.dart';
import '../container.dart';
import '../encryption.dart';
import 'binary.dart';
import 'central_directory.dart';

const int _localSignature = 0x04034b50;

final class ZipContainer implements EpubContainer {
  ZipContainer._(this._source, this._sink, this.centralDirectory);

  final EpubByteSource _source;
  final DiagnosticSink _sink;

  /// Central directory lido na abertura (testes e orçamento de leitura).
  @visibleForTesting
  final CentralDirectory centralDirectory;

  final Map<String, FontObfuscation> _obfuscation = {};
  Future<void>? _closing;

  /// Lê o central directory, confere o `mimetype` e o DRM. Exceção da fonte
  /// vira [EpubContainerException] com `cause`. Se a abertura falha, a fonte
  /// é fechada.
  static Future<ZipContainer> open(
    EpubByteSource source, {
    required DiagnosticSink sink,
  }) async {
    try {
      final cd = await readCentralDirectory(source, sink: sink);
      final container = ZipContainer._(source, sink, cd);
      await container._checkMimetype();
      await container._checkEncryption();
      return container;
    } on Object {
      try {
        await source.close();
      } on Object {
        // A falha original é a que importa.
      }
      rethrow;
    }
  }

  @override
  Iterable<String> get paths => centralDirectory.paths;

  @override
  Future<bool> exists(String path) async {
    _checkOpen();
    return centralDirectory.lookup(path) != null;
  }

  @override
  Future<PendingResource?> fetch(String path) async {
    _checkOpen();
    final hit = centralDirectory.lookup(path);
    if (hit == null) return null;
    final e = hit.entry;
    if (!hit.exact) {
      _sink.emit(
        EpubDiagnosticCode.pathCaseMismatch,
        href: path,
        message: 'caminho achado só sem diferenciar maiúsculas: ${e.name}',
        details: {'actual': e.name},
      );
    }
    final invalid = e.invalidReason;
    if (invalid != null) throw EpubContainerException(invalid, href: path);
    if (e.method != 0 && e.method != 8) {
      throw EpubContainerException(
        'método de compressão ${e.method} não suportado',
        href: path,
      );
    }

    final length = centralDirectory.length;
    final offset = e.localHeaderOffset;
    final first = await readSource(
      _source,
      offset,
      math.min(30 + e.nameLength + e.compressedSize + 1024, length - offset),
      href: path,
    );
    if (first.length < 30 || readU32(first, 0) != _localSignature) {
      throw EpubContainerException('local header inválido', href: path);
    }
    final dataStart = 30 + readU16(first, 26) + readU16(first, 28);
    final Uint8List data;
    if (dataStart + e.compressedSize <= first.length) {
      data = Uint8List.sublistView(
        first,
        dataStart,
        dataStart + e.compressedSize,
      );
    } else {
      if (offset + dataStart + e.compressedSize > length) {
        throw EpubContainerException(
          'dados da entrada além do fim do arquivo',
          href: path,
        );
      }
      data = await readSource(
        _source,
        offset + dataStart,
        e.compressedSize,
        href: path,
      );
    }
    return PendingResource.zip(
      path: e.name,
      size: e.uncompressedSize,
      method: e.method,
      data: data,
      crc32: e.crc32,
      sink: _sink,
    );
  }

  @override
  FontObfuscation? obfuscationOf(String path) {
    final hit = centralDirectory.lookup(path);
    return _obfuscation[hit?.entry.name ?? path];
  }

  @override
  Future<void> close() => _closing ??= _source.close();

  /// §6, nesta ordem: licença LCP, `rights.xml`, `encryption.xml`.
  Future<void> _checkEncryption() async {
    if (centralDirectory.lookup('META-INF/license.lcpl') != null) {
      throw EpubEncryptedException(
        'livro protegido por Readium LCP (META-INF/license.lcpl): esquema lcp',
        scheme: 'lcp',
      );
    }
    if (centralDirectory.lookup('META-INF/rights.xml') != null) {
      final text = await _readText('META-INF/rights.xml');
      final scheme = text == null ? 'unknown:rights.xml' : rightsScheme(text);
      throw EpubEncryptedException(
        'livro com META-INF/rights.xml: esquema $scheme',
        scheme: scheme,
        href: 'META-INF/rights.xml',
      );
    }
    if (centralDirectory.lookup('META-INF/encryption.xml') == null) return;
    const invalid = 'unknown:encryption.xml-invalido';
    final text = await _readText('META-INF/encryption.xml');
    if (text == null) {
      throw EpubEncryptedException(
        'META-INF/encryption.xml ilegível: sem como provar que não há DRM '
        '(esquema $invalid)',
        scheme: invalid,
        href: 'META-INF/encryption.xml',
      );
    }
    final List<EncryptedItem> items;
    try {
      items = parseEncryptionXml(text);
    } on XmlException catch (e) {
      throw EpubEncryptedException(
        'META-INF/encryption.xml não é XML válido: sem como provar que não '
        'há DRM (esquema $invalid)',
        scheme: invalid,
        href: 'META-INF/encryption.xml',
        cause: e,
      );
    }
    _obfuscation.addAll(
      resolveEncryption(
        items,
        resolve: (uri) => centralDirectory.lookup(uri)?.entry.name ?? uri,
        sink: _sink,
        drmIsFatal: true,
      ),
    );
  }

  /// Texto UTF-8 de uma entrada; `null` se ausente ou ilegível.
  Future<String?> _readText(String path) async {
    try {
      final pending = await fetch(path);
      if (pending == null) return null;
      for (final _ in pending.decode()) {}
      return utf8.decode(pending.bytes, allowMalformed: true);
    } on EpubContainerException {
      return null;
    }
  }

  void _checkOpen() {
    if (_closing != null) throw StateError('ZipContainer fechado');
  }

  /// §5.2: primeira entrada (menor offset, e esse offset é o início do ZIP),
  /// stored, conteúdo exato. Nunca fatal.
  Future<void> _checkMimetype() async {
    final reason = await _mimetypeProblem();
    if (reason == null) return;
    _sink.emit(
      EpubDiagnosticCode.mimetypeIrregular,
      href: 'mimetype',
      message: switch (reason) {
        'missing' => 'entrada mimetype ausente',
        'notFirst' => 'mimetype não é a primeira entrada do ZIP',
        'compressed' => 'mimetype comprimido (deveria ser stored)',
        'content' => 'mimetype com conteúdo diferente de application/epub+zip',
        _ => 'mimetype ilegível',
      },
      details: {'reason': reason},
    );
  }

  Future<String?> _mimetypeProblem() async {
    final cd = centralDirectory;
    final hit = cd.lookup('mimetype');
    if (hit == null || !hit.exact) return 'missing';
    final entry = hit.entry;
    final first = cd.entries.reduce(
      (a, b) => b.localHeaderOffset < a.localHeaderOffset ? b : a,
    );
    if (!identical(first, entry) || entry.localHeaderOffset != cd.delta) {
      return 'notFirst';
    }
    if (entry.method != 0) return 'compressed';
    try {
      final pending = (await fetch('mimetype'))!;
      for (final _ in pending.decode()) {}
      final text = latin1.decode(pending.bytes);
      return text == 'application/epub+zip' ? null : 'content';
    } on EpubContainerException {
      return 'unreadable';
    }
  }
}
```

- [ ] **Passo 5: Rodar e ver passar**

Run: `flutter test test/container/encryption_test.dart test/container/zip_container_test.dart`
Expected: `All tests passed!` (24 + 23 testes).

- [ ] **Passo 6: Formatar e analisar**

Run: `dart format lib/src/container test/container && flutter analyze`
Expected: nada mudado e `No issues found!`.

- [ ] **Passo 7: Commit**

```bash
git add lib/src/container/encryption.dart lib/src/container/zip/zip_container.dart test/container/encryption_test.dart
git commit -m "feat(container): encryption.xml, rights.xml e detecção de DRM

LCP por licença e por RetrievalMethod, ADEPT por rights.xml e KeyInfo,
cifra sobre conteúdo como unknown:<algoritmo>, encryption.xml inválido
como unknown:encryption.xml-invalido, e o mapa de ofuscação das fontes
com fontObfuscationUnknown para algoritmo desconhecido (spec §6)."
```

---

### Tarefa 8: Desofuscação de fontes

Spec §6.1. Código e vetores do spike S6, copiados para `lib/` (o spike fica
intacto). A Camada B chama `deobfuscateFont` e `looksLikeFont`; aqui só as
funções e a prova sobre as fontes do corpus.

**Arquivos:**
- Criar: `lib/src/container/sha1.dart`
- Criar: `lib/src/container/font_obfuscation.dart`
- Teste: `test/container/font_obfuscation_test.dart`

**Interfaces:**
- Consome: `FontObfuscation` (Tarefa 4); `ZipContainer`, `obfuscationOf` (Tarefas 6 e 7); `FileEpubByteSource` (Tarefa 2); `noise` do apoio de teste; `package:xml` para ler o `dc:identifier` do OPF no teste.
- Produz: `Uint8List sha1(Uint8List data)`, `String sha1Hex(Uint8List data)`.
- Produz: `Uint8List? deobfuscateFont(Uint8List bytes, FontObfuscation kind, {required List<String> uniqueIdentifiers, required List<String> identifiers})` — `null` sem identificador utilizável; `ArgumentError` para `unknown`.
- Produz: `bool looksLikeFont(Uint8List bytes)`.

- [ ] **Passo 1: Escrever o teste que falha**

Criar `test/container/font_obfuscation_test.dart`. O grupo `corpus` abre
`fonte-ofuscada-idpf` e `fonte-ofuscada-adobe` em `strict`, lê o identificador
do OPF (`OEBPS/content.opf`, `unique-identifier="pub-id"`) e compara a fonte
desofuscada com `tool/corpus/assets/NotoSansOgham-Regular.ttf`:

```dart
// SHA-1, desofuscação IDPF/Adobe e looksLikeFont (spec do contêiner §6.1).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/container/container.dart';
import 'package:galley/src/container/font_obfuscation.dart';
import 'package:galley/src/container/sha1.dart';
import 'package:galley/src/container/zip/zip_container.dart';
import 'package:galley/src/diagnostics/diagnostic.dart';
import 'package:galley/src/io/file_byte_source.dart';
import 'package:xml/xml.dart';

import 'support/zip_fixtures.dart';

Uint8List _ascii(String s) => ascii.encode(s);

const _uuid = 'urn:uuid:b7e2f1a0-4c3d-4e5f-8a9b-0c1d2e3f4a5b';

/// Cabeçalho TrueType seguido de ruído: passa em looksLikeFont.
final Uint8List _font = Uint8List.fromList([0, 1, 0, 0, ...noise(4096)]);

Uint8List _idpf(Uint8List bytes, List<String> ids) => deobfuscateFont(
  bytes,
  FontObfuscation.idpf,
  uniqueIdentifiers: ids,
  identifiers: const [],
)!;

Uint8List? _adobe(Uint8List bytes, List<String> ids) => deobfuscateFont(
  bytes,
  FontObfuscation.adobe,
  uniqueIdentifiers: const [],
  identifiers: ids,
);

void main() {
  group('SHA-1', () {
    test('6 vetores conhecidos', () {
      expect(
        sha1Hex(_ascii('abc')),
        'a9993e364706816aba3e25717850c26c9cd0d89d',
      );
      expect(sha1Hex(Uint8List(0)), 'da39a3ee5e6b4b0d3255bfef95601890afd80709');
      expect(
        sha1Hex(_ascii('The quick brown fox jumps over the lazy dog')),
        '2fd4e1c67a2d28fced849ee1bb76e7391b93eb12',
      );
      // Fronteiras do padding: 55, 56 e 64 bytes.
      expect(
        sha1Hex(_ascii('a' * 55)),
        'c1c8bbdc22796e28c0e15163d20899b65621d65a',
      );
      expect(
        sha1Hex(_ascii('a' * 56)),
        'c2db330f6083854c99d4b5bfb6e8f29f201be699',
      );
      expect(
        sha1Hex(_ascii('a' * 64)),
        '0098ba824b5c16427bd7a1122a5a442a25ec644d',
      );
    });
  });

  group('IDPF', () {
    test('ida e volta; só os primeiros 1040 bytes mudam', () {
      final obfuscated = _idpf(_font, [_uuid]);
      expect(obfuscated.sublist(0, 1040), isNot(_font.sublist(0, 1040)));
      expect(obfuscated.sublist(1040), _font.sublist(1040));
      expect(looksLikeFont(obfuscated), isFalse);
      expect(_idpf(obfuscated, [_uuid]), _font);
    });

    test('chave é o SHA-1 dos identificadores sem espaço, CR, LF e TAB', () {
      final a = _idpf(_font, ['urn:uuid:abc', 'def']);
      final b = _idpf(_font, [' urn:uuid:abc\n', '\tdef\r ']);
      expect(a, b);
      final key = sha1(_ascii('urn:uuid:abcdef'));
      expect(a[0], _font[0] ^ key[0]);
      expect(a[20], _font[20] ^ key[0]);
    });

    test('lista vazia ou só whitespace → null', () {
      expect(
        deobfuscateFont(
          _font,
          FontObfuscation.idpf,
          uniqueIdentifiers: const [],
          identifiers: const [_uuid],
        ),
        isNull,
      );
      expect(
        deobfuscateFont(
          _font,
          FontObfuscation.idpf,
          uniqueIdentifiers: const [' \n'],
          identifiers: const [],
        ),
        isNull,
      );
    });

    test('fonte menor que 1040 bytes', () {
      final small = Uint8List.fromList([0, 1, 0, 0, 9, 9]);
      expect(_idpf(_idpf(small, [_uuid]), [_uuid]), small);
    });
  });

  group('Adobe', () {
    test('ida e volta; só os primeiros 1024 bytes mudam', () {
      final obfuscated = _adobe(_font, [_uuid])!;
      expect(obfuscated.sublist(1024), _font.sublist(1024));
      expect(obfuscated[0], _font[0] ^ 0xb7);
      expect(obfuscated[15], _font[15] ^ 0x5b);
      expect(_adobe(obfuscated, [_uuid]), _font);
    });

    test('UUID em qualquer posição; vale o primeiro utilizável', () {
      final expected = _adobe(_font, [_uuid]);
      expect(
        _adobe(_font, ['isbn:978-85-000', 'urn:uuid:curto', _uuid]),
        expected,
      );
      expect(
        _adobe(_font, [_uuid, 'urn:uuid:00000000-0000-0000-0000-000000000001']),
        expected,
      );
    });

    test('prefixo sem diferenciar maiúsculas e 32 hex sem prefixo', () {
      final expected = _adobe(_font, [_uuid]);
      expect(_adobe(_font, [_uuid.toUpperCase()]), expected);
      expect(_adobe(_font, ['b7e2f1a04c3d4e5f8a9b0c1d2e3f4a5b']), expected);
    });

    test('nenhum identificador utilizável → null', () {
      expect(_adobe(_font, const []), isNull);
      expect(_adobe(_font, ['isbn:978-85-000', 'urn:uuid:zz']), isNull);
    });
  });

  test('unknown lança ArgumentError', () {
    expect(
      () => deobfuscateFont(
        _font,
        FontObfuscation.unknown,
        uniqueIdentifiers: const [_uuid],
        identifiers: const [_uuid],
      ),
      throwsArgumentError,
    );
  });

  test('looksLikeFont reconhece os seis magics', () {
    for (final magic in [
      [0x00, 0x01, 0x00, 0x00],
      ...['OTTO', 'true', 'ttcf', 'wOFF', 'wOF2'].map(ascii.encode),
    ]) {
      expect(looksLikeFont(Uint8List.fromList([...magic, 0, 0])), isTrue);
    }
    expect(looksLikeFont(_ascii('<?xm')), isFalse);
    expect(looksLikeFont(Uint8List.fromList([0, 1, 0])), isFalse);
  });

  group('corpus', () {
    final original = File('tool/corpus/assets/NotoSansOgham-Regular.ttf')
        .readAsBytesSync();

    for (final (slug, kind) in [
      ('fonte-ofuscada-idpf', FontObfuscation.idpf),
      ('fonte-ofuscada-adobe', FontObfuscation.adobe),
    ]) {
      test(
        '$slug: desofuscada passa em looksLikeFont e é a fonte original',
        () async {
          final c = await ZipContainer.open(
            FileEpubByteSource('test/corpus/patologia/$slug/book.epub'),
            sink: DiagnosticSink(strict: true),
          );
          const fontPath = 'OEBPS/Fonts/NotoSansOgham-Regular.ttf';
          expect(c.obfuscationOf(fontPath), kind);

          final opf = (await c.fetch('OEBPS/content.opf'))!;
          for (final _ in opf.decode()) {}
          final doc = XmlDocument.parse(utf8.decode(opf.bytes));
          final uniqueId = doc.rootElement.getAttribute('unique-identifier');
          final ids = doc.findAllElements(
            'identifier',
            namespaceUri: 'http://purl.org/dc/elements/1.1/',
          );

          final font = (await c.fetch(fontPath))!;
          for (final _ in font.decode()) {}
          expect(looksLikeFont(font.bytes), isFalse);
          final restored = deobfuscateFont(
            font.bytes,
            kind,
            uniqueIdentifiers: [
              for (final e in ids)
                if (e.getAttribute('id') == uniqueId) e.innerText,
            ],
            identifiers: [for (final e in ids) e.innerText],
          )!;
          expect(looksLikeFont(restored), isTrue);
          expect(restored, original);
          await c.close();
        },
      );
    }
  });
}
```

- [ ] **Passo 2: Rodar e ver falhar**

Run: `flutter test test/container/font_obfuscation_test.dart`
Expected: FAIL na compilação, com `Error when reading 'lib/src/container/font_obfuscation.dart'`.

- [ ] **Passo 3: SHA-1**

Criar `lib/src/container/sha1.dart` (o do S6, com o comprimento em bits
gravado por `~/` em vez de `>> 32`):

```dart
/// SHA-1 próprio (FIPS 180-4), sem dependência (doc/11 §1). Vem do spike S6.
library;

import 'dart:typed_data';

/// Os 20 bytes do SHA-1 de [data], de uma vez (sem streaming).
Uint8List sha1(Uint8List data) {
  const mask = 0xFFFFFFFF;

  var h0 = 0x67452301;
  var h1 = 0xEFCDAB89;
  var h2 = 0x98BADCFE;
  var h3 = 0x10325476;
  var h4 = 0xC3D2E1F0;

  // Padding: 0x80, zeros até 56 mod 64, comprimento em bits big-endian.
  // O comprimento vai como dois u32 (setUint64 não existe no dart2js).
  final bitLength = data.length * 8;
  final paddedLength = ((data.length + 9 + 63) ~/ 64) * 64;
  final padded = Uint8List(paddedLength)..setRange(0, data.length, data);
  padded[data.length] = 0x80;
  final view = ByteData.sublistView(padded)
    ..setUint32(paddedLength - 8, bitLength ~/ 0x100000000, Endian.big)
    ..setUint32(paddedLength - 4, bitLength & mask, Endian.big);

  final w = Uint32List(80);

  int rotl(int x, int n) => ((x << n) | (x >>> (32 - n))) & mask;

  for (var chunk = 0; chunk < paddedLength; chunk += 64) {
    for (var i = 0; i < 16; i++) {
      w[i] = view.getUint32(chunk + i * 4, Endian.big);
    }
    for (var i = 16; i < 80; i++) {
      w[i] = rotl(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
    }

    var a = h0, b = h1, c = h2, d = h3, e = h4;
    for (var i = 0; i < 80; i++) {
      int f, k;
      if (i < 20) {
        f = (b & c) | ((~b & mask) & d);
        k = 0x5A827999;
      } else if (i < 40) {
        f = b ^ c ^ d;
        k = 0x6ED9EBA1;
      } else if (i < 60) {
        f = (b & c) | (b & d) | (c & d);
        k = 0x8F1BBCDC;
      } else {
        f = b ^ c ^ d;
        k = 0xCA62C1D6;
      }
      final temp = (rotl(a, 5) + f + e + k + w[i]) & mask;
      e = d;
      d = c;
      c = rotl(b, 30);
      b = a;
      a = temp;
    }

    h0 = (h0 + a) & mask;
    h1 = (h1 + b) & mask;
    h2 = (h2 + c) & mask;
    h3 = (h3 + d) & mask;
    h4 = (h4 + e) & mask;
  }

  final out = ByteData(20)
    ..setUint32(0, h0, Endian.big)
    ..setUint32(4, h1, Endian.big)
    ..setUint32(8, h2, Endian.big)
    ..setUint32(12, h3, Endian.big)
    ..setUint32(16, h4, Endian.big);
  return out.buffer.asUint8List();
}

/// SHA-1 em hexadecimal minúsculo.
String sha1Hex(Uint8List data) =>
    sha1(data).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
```

- [ ] **Passo 4: Desofuscação**

Criar `lib/src/container/font_obfuscation.dart`:

```dart
/// Desofuscação de fontes embutidas (doc/09 §4, spec do contêiner §6.1).
/// Código e vetores do spike S6. XOR é involutivo: ofuscar e desofuscar são
/// a mesma função.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'container.dart';
import 'sha1.dart';

final RegExp _idpfWhitespace = RegExp('[ \t\r\n]');
final RegExp _hex32 = RegExp(r'^[0-9a-fA-F]{32}$');

/// Desofusca [bytes] conforme [kind]. `null` se não houver identificador
/// utilizável para o algoritmo. [ArgumentError] para
/// [FontObfuscation.unknown].
///
/// - IDPF: XOR dos primeiros 1040 bytes com o SHA-1 da concatenação de
///   [uniqueIdentifiers] sem espaço, CR, LF e TAB.
/// - Adobe: XOR dos primeiros 1024 bytes com os 16 bytes do primeiro de
///   [identifiers] que for `urn:uuid:` (prefixo sem diferenciar maiúsculas)
///   ou 32 dígitos hex, sem hifens.
Uint8List? deobfuscateFont(
  Uint8List bytes,
  FontObfuscation kind, {
  required List<String> uniqueIdentifiers,
  required List<String> identifiers,
}) {
  switch (kind) {
    case FontObfuscation.idpf:
      final joined = uniqueIdentifiers.join().replaceAll(_idpfWhitespace, '');
      if (joined.isEmpty) return null;
      return _xorPrefix(bytes, sha1(utf8.encode(joined)), 1040);
    case FontObfuscation.adobe:
      for (final id in identifiers) {
        final key = _adobeKey(id);
        if (key != null) return _xorPrefix(bytes, key, 1024);
      }
      return null;
    case FontObfuscation.unknown:
      throw ArgumentError.value(kind, 'kind', 'ofuscação desconhecida');
  }
}

/// Magic de fonte conhecido: 00010000, OTTO, true, ttcf, wOFF, wOF2.
bool looksLikeFont(Uint8List bytes) {
  if (bytes.length < 4) return false;
  final magic = bytes[0] << 24 | bytes[1] << 16 | bytes[2] << 8 | bytes[3];
  return const {
    0x00010000, // TrueType
    0x4F54544F, // OTTO
    0x74727565, // true
    0x74746366, // ttcf
    0x774F4646, // wOFF
    0x774F4632, // wOF2
  }.contains(magic);
}

Uint8List? _adobeKey(String identifier) {
  var s = identifier.trim();
  if (s.toLowerCase().startsWith('urn:uuid:')) s = s.substring(9);
  final hex = s.replaceAll('-', '');
  if (!_hex32.hasMatch(hex)) return null;
  return Uint8List.fromList([
    for (var i = 0; i < 16; i++)
      int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
  ]);
}

Uint8List _xorPrefix(Uint8List bytes, Uint8List key, int prefixLength) {
  final out = Uint8List.fromList(bytes);
  final n = bytes.length < prefixLength ? bytes.length : prefixLength;
  for (var i = 0; i < n; i++) {
    out[i] ^= key[i % key.length];
  }
  return out;
}
```

- [ ] **Passo 5: Rodar e ver passar**

Run: `flutter test test/container/font_obfuscation_test.dart`
Expected: `All tests passed!` (13 testes).

- [ ] **Passo 6: Formatar e analisar**

Run: `dart format lib/src/container test/container && flutter analyze`
Expected: nada mudado e `No issues found!`.

- [ ] **Passo 7: Commit**

```bash
git add lib/src/container/sha1.dart lib/src/container/font_obfuscation.dart test/container/font_obfuscation_test.dart
git commit -m "feat(container): desofuscação de fontes IDPF e Adobe

SHA-1 e XOR do spike S6, chave Adobe pelo primeiro identificador UUID
utilizável e looksLikeFont pelos seis magics; as fontes ofuscadas do
corpus voltam byte a byte à original (spec §6.1)."
```

---

### Tarefa 9: `ProviderContainer`

Spec §6.2. O provider é a autoridade: sem `paths`, sem busca sem diferenciar
maiúsculas, sem CRC, sem `mimetype`, e DRM nunca fatal.

**Arquivos:**
- Criar: `lib/src/container/provider_container.dart`
- Teste: `test/container/provider_container_test.dart`

**Interfaces:**
- Consome: `EpubResourceProvider` (Tarefa 2); `EpubContainer`, `PendingResource.ready`, `maxEntrySize`, `FontObfuscation` (Tarefa 4); `parseEncryptionXml`, `resolveEncryption`, `idpfObfuscationAlgorithm`, `adobeObfuscationAlgorithm`, `lcpContentKeyType` (Tarefa 7); `DiagnosticSink`, `EpubDiagnosticCode.encryptionIgnored` (Tarefa 1).
- Produz: `final class ProviderContainer implements EpubContainer { static Future<ProviderContainer> open(EpubResourceProvider provider, {required DiagnosticSink sink}); }`.

- [ ] **Passo 1: Escrever o teste que falha**

Criar `test/container/provider_container_test.dart`:

```dart
// ProviderContainer (spec do contêiner §6.2).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/container/container.dart';
import 'package:galley/src/container/encryption.dart';
import 'package:galley/src/container/provider_container.dart';
import 'package:galley/src/container/resource_provider.dart';
import 'package:galley/src/diagnostics/diagnostic.dart';
import 'package:galley/src/diagnostics/exceptions.dart';

/// Provider em memória; [failing] lança FileSystemException em read.
final class _MapProvider implements EpubResourceProvider {
  _MapProvider(this.files, {this.failing = const {}});

  final Map<String, List<int>> files;
  final Set<String> failing;
  int closeCalls = 0;

  @override
  Future<bool> exists(String href) async => files.containsKey(href);

  @override
  Future<Uint8List> read(String href) async {
    if (failing.contains(href)) throw FileSystemException('sem acesso', href);
    return Uint8List.fromList(files[href]!);
  }

  @override
  Future<void> close() async => closeCalls++;
}

String _encryption(String algorithm, String uri, {String keyInfo = ''}) =>
    '<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container" '
    'xmlns:enc="http://www.w3.org/2001/04/xmlenc#"><enc:EncryptedData>'
    '<enc:EncryptionMethod Algorithm="$algorithm"/>$keyInfo'
    '<enc:CipherData><enc:CipherReference URI="$uri"/></enc:CipherData>'
    '</enc:EncryptedData></encryption>';

Future<Uint8List> _read(PendingResource r) async {
  expect(r.decode().length, 1);
  return r.bytes;
}

void main() {
  test('leitura: um passo, sem CRC; paths vazio', () async {
    final p = _MapProvider({'OEBPS/a.xhtml': utf8.encode('<p>oi</p>')});
    final sink = DiagnosticSink(strict: true);
    final c = await ProviderContainer.open(p, sink: sink);
    expect(c.paths, isEmpty);
    expect(await c.exists('OEBPS/a.xhtml'), isTrue);
    final r = (await c.fetch('OEBPS/a.xhtml'))!;
    expect(r.path, 'OEBPS/a.xhtml');
    expect(r.size, 9);
    expect(utf8.decode(await _read(r)), '<p>oi</p>');
    expect(sink.diagnostics, isEmpty);
  });

  test('ausente devolve null; sem busca sem diferenciar maiúsculas', () async {
    final c = await ProviderContainer.open(
      _MapProvider({
        'OEBPS/a.xhtml': [1],
      }),
      sink: DiagnosticSink(),
    );
    expect(await c.fetch('OEBPS/nada.xhtml'), isNull);
    expect(await c.fetch('oebps/A.xhtml'), isNull);
    expect(await c.exists('oebps/A.xhtml'), isFalse);
  });

  test(
    'exceção do provider vira EpubContainerException(href, cause)',
    () async {
      final c = await ProviderContainer.open(
        _MapProvider(
          {
            'a.xhtml': [1],
          },
          failing: {'a.xhtml'},
        ),
        sink: DiagnosticSink(),
      );
      await expectLater(
        c.fetch('a.xhtml'),
        throwsA(
          isA<EpubContainerException>()
              .having((e) => e.href, 'href', 'a.xhtml')
              .having((e) => e.cause, 'cause', isA<FileSystemException>()),
        ),
      );
    },
  );

  test('LCP e cifra sobre conteúdo nunca são fatais', () async {
    const lcp =
        '<ds:KeyInfo xmlns:ds="http://www.w3.org/2000/09/xmldsig#">'
        '<ds:RetrievalMethod Type="$lcpContentKeyType"/></ds:KeyInfo>';
    final p = _MapProvider({
      'META-INF/license.lcpl': utf8.encode('{}'),
      'META-INF/rights.xml': utf8.encode('<rights/>'),
      'META-INF/encryption.xml': utf8.encode(
        _encryption(
          'http://www.w3.org/2001/04/xmlenc#aes256-cbc',
          'OEBPS/a.xhtml',
          keyInfo: lcp,
        ),
      ),
      'OEBPS/a.xhtml': [1, 2, 3],
    });
    final sink = DiagnosticSink(strict: true);
    final c = await ProviderContainer.open(p, sink: sink);
    expect(await _read((await c.fetch('OEBPS/a.xhtml'))!), [1, 2, 3]);
    expect(c.obfuscationOf('OEBPS/a.xhtml'), isNull);
    expect(sink.diagnostics, isEmpty);
  });

  group('obfuscationOf', () {
    for (final (algorithm, kind) in [
      (idpfObfuscationAlgorithm, FontObfuscation.idpf),
      (adobeObfuscationAlgorithm, FontObfuscation.adobe),
    ]) {
      test(kind.name, () async {
        final c = await ProviderContainer.open(
          _MapProvider({
            'META-INF/encryption.xml': utf8.encode(
              _encryption(algorithm, 'OEBPS/Fonts/a.otf'),
            ),
          }),
          sink: DiagnosticSink(),
        );
        expect(c.obfuscationOf('OEBPS/Fonts/a.otf'), kind);
        expect(c.obfuscationOf('oebps/fonts/a.otf'), isNull);
      });
    }

    test('algoritmo desconhecido sobre fonte → unknown + warning', () async {
      final sink = DiagnosticSink();
      final c = await ProviderContainer.open(
        _MapProvider({
          'META-INF/encryption.xml': utf8.encode(
            _encryption('urn:x', 'Fonts/a.woff'),
          ),
        }),
        sink: sink,
      );
      expect(c.obfuscationOf('Fonts/a.woff'), FontObfuscation.unknown);
      expect(
        sink.diagnostics.single.code,
        EpubDiagnosticCode.fontObfuscationUnknown,
      );
    });
  });

  test(
    'encryption.xml inválido: encryptionIgnored e obfuscationOf null',
    () async {
      final sink = DiagnosticSink(strict: true);
      final c = await ProviderContainer.open(
        _MapProvider({'META-INF/encryption.xml': utf8.encode('<encryption')}),
        sink: sink,
      );
      final d = sink.diagnostics.single;
      expect(d.code, EpubDiagnosticCode.encryptionIgnored);
      expect(d.severity, EpubSeverity.info);
      expect(d.details['reason'], 'invalid-xml');
      expect(c.obfuscationOf('OEBPS/Fonts/a.otf'), isNull);
    },
  );

  test('encryption.xml ilegível pelo provider: encryptionIgnored', () async {
    final sink = DiagnosticSink();
    await ProviderContainer.open(
      _MapProvider(
        {
          'META-INF/encryption.xml': [1],
        },
        failing: {'META-INF/encryption.xml'},
      ),
      sink: sink,
    );
    expect(sink.diagnostics.single.details['reason'], 'unreadable');
  });

  test('close fecha o provider uma vez e bloqueia fetch', () async {
    final p = _MapProvider({});
    final c = await ProviderContainer.open(p, sink: DiagnosticSink());
    await c.close();
    await c.close();
    expect(p.closeCalls, 1);
    await expectLater(c.fetch('a'), throwsStateError);
  });
}
```

- [ ] **Passo 2: Rodar e ver falhar**

Run: `flutter test test/container/provider_container_test.dart`
Expected: FAIL na compilação, com `Error when reading 'lib/src/container/provider_container.dart'`.

- [ ] **Passo 3: Implementar**

Criar `lib/src/container/provider_container.dart`:

```dart
/// Contêiner sobre um [EpubResourceProvider] do app (spec do contêiner
/// §6.2). O provider é a autoridade: sem busca sem diferenciar maiúsculas,
/// sem CRC, sem `mimetype` e sem DRM fatal (ele já decifrou, doc/09 §4).
library;

import 'dart:convert';

import 'package:xml/xml.dart';

import '../diagnostics/diagnostic.dart';
import '../diagnostics/exceptions.dart';
import 'container.dart';
import 'encryption.dart';
import 'resource_provider.dart';

const String _encryptionPath = 'META-INF/encryption.xml';

final class ProviderContainer implements EpubContainer {
  ProviderContainer._(this._provider);

  final EpubResourceProvider _provider;
  final Map<String, FontObfuscation> _obfuscation = {};
  Future<void>? _closing;

  /// Lê só as entradas de ofuscação de fonte de `encryption.xml`, se houver.
  /// XML inválido ou ilegível emite `encryptionIgnored` e segue.
  static Future<ProviderContainer> open(
    EpubResourceProvider provider, {
    required DiagnosticSink sink,
  }) async {
    final container = ProviderContainer._(provider);
    final String text;
    try {
      if (!await provider.exists(_encryptionPath)) return container;
      text = utf8.decode(
        await provider.read(_encryptionPath),
        allowMalformed: true,
      );
    } on Object catch (e) {
      sink.emit(
        EpubDiagnosticCode.encryptionIgnored,
        href: _encryptionPath,
        message: 'encryption.xml ilegível pelo provider; ofuscação ignorada',
        details: {'reason': 'unreadable', 'exception': '$e'},
      );
      return container;
    }
    try {
      container._obfuscation.addAll(
        resolveEncryption(
          parseEncryptionXml(text),
          resolve: (uri) => uri,
          sink: sink,
          drmIsFatal: false,
        ),
      );
    } on XmlException catch (e) {
      sink.emit(
        EpubDiagnosticCode.encryptionIgnored,
        href: _encryptionPath,
        message: 'encryption.xml não é XML válido; ofuscação ignorada',
        details: {'reason': 'invalid-xml', 'exception': '$e'},
      );
    }
    return container;
  }

  /// O provider não lista seus recursos.
  @override
  Iterable<String> get paths => const [];

  @override
  Future<bool> exists(String path) async {
    _checkOpen();
    try {
      return await _provider.exists(path);
    } on Object catch (e) {
      throw EpubContainerException('provider falhou: $e', href: path, cause: e);
    }
  }

  @override
  Future<PendingResource?> fetch(String path) async {
    _checkOpen();
    try {
      if (!await _provider.exists(path)) return null;
      final bytes = await _provider.read(path);
      if (bytes.length > maxEntrySize) {
        throw EpubContainerException(
          'recurso acima de $maxEntrySize bytes',
          href: path,
        );
      }
      return PendingResource.ready(path: path, bytes: bytes);
    } on EpubException {
      rethrow;
    } on Object catch (e) {
      throw EpubContainerException('provider falhou: $e', href: path, cause: e);
    }
  }

  @override
  FontObfuscation? obfuscationOf(String path) => _obfuscation[path];

  @override
  Future<void> close() => _closing ??= _provider.close();

  void _checkOpen() {
    if (_closing != null) throw StateError('ProviderContainer fechado');
  }
}
```

- [ ] **Passo 4: Rodar e ver passar**

Run: `flutter test test/container/provider_container_test.dart`
Expected: `All tests passed!` (10 testes).

- [ ] **Passo 5: Formatar e analisar**

Run: `dart format lib/src/container test/container && flutter analyze`
Expected: nada mudado e `No issues found!`.

- [ ] **Passo 6: Commit**

```bash
git add lib/src/container/provider_container.dart test/container/provider_container_test.dart
git commit -m "feat(container): ProviderContainer

fetch por exists + read com exceção do provider embrulhada, um passo
sem CRC, e encryption.xml lido só para ofuscação de fontes; XML
inválido emite encryptionIgnored (spec §6.2)."
```

---

### Tarefa 10: Exports públicos e teste de corpus

Spec §3 (exports) e §9.1 (os 65 EPUBs, o orçamento de bytes lidos e a segunda
passada em `strict`).

**Arquivos:**
- Modificar: `lib/galley.dart` (substituir inteiro)
- Modificar: `test/container/inflate_web_test.dart` (substituir inteiro)
- Teste: `test/container/public_api_test.dart`
- Teste: `test/container/container_corpus_test.dart`

**Interfaces:**
- Consome: tudo das Tarefas 1–9; `CountingByteSource` e `tailReadSize`; a convenção do corpus (`test/corpus/README.md`: `exception.expected`, `diagnostics.expected`).
- Produz: `package:galley/galley.dart` exporta `EpubByteSource`, `MemoryEpubByteSource`, `FileEpubByteSource`, `EpubResourceProvider`, `EpubException`, `EpubContainerException`, `EpubEncryptedException`, `EpubDiagnostic`, `EpubDiagnosticCode`, `EpubSeverity`, e nada mais (`checkRange`, `ZipContainer`, `DiagnosticSink` ficam internos).

- [ ] **Passo 1: Escrever o teste de API que falha**

Criar `test/container/public_api_test.dart`. O segundo teste é o item 5 do
Foco de revisão:

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
Expected: FAIL na compilação, com `Type 'EpubByteSource' not found` (o
`lib/galley.dart` ainda não exporta nada).

- [ ] **Passo 3: Exports**

Substituir `lib/galley.dart` inteiro por:

```dart
/// Motor de renderização de EPUB nativo para Flutter.
///
/// Fase 1, sub-projeto 1 (contêiner): fonte de bytes, provider de recursos,
/// exceções e diagnósticos. Ver `doc/` para a arquitetura.
library;

export 'src/container/byte_source.dart'
    show EpubByteSource, MemoryEpubByteSource;
export 'src/container/resource_provider.dart' show EpubResourceProvider;
export 'src/diagnostics/diagnostic.dart'
    show EpubDiagnostic, EpubDiagnosticCode, EpubSeverity;
export 'src/diagnostics/exceptions.dart'
    show EpubContainerException, EpubEncryptedException, EpubException;
export 'src/io/file_byte_source.dart' show FileEpubByteSource;
```

- [ ] **Passo 4: Rodar e ver passar**

Run: `flutter test test/container/public_api_test.dart`
Expected: `All tests passed!` (2 testes).

- [ ] **Passo 5: O pacote inteiro no web**

Substituir `test/container/inflate_web_test.dart` inteiro por:

```dart
// Stub do inflate no web (P7, adiado para a 1.0.x). Só roda com
// `flutter test --platform chrome test/container/inflate_web_test.dart`; na
// VM, @TestOn pula o arquivo.
@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/galley.dart';
import 'package:galley/src/container/inflate/inflate.dart';
import 'package:galley/src/container/zip/zip_container.dart';

void main() {
  test('createInflater lança UnsupportedError citando P7 e 1.0.x', () {
    expect(
      () => createInflater((_) {}),
      throwsA(
        isA<UnsupportedError>().having(
          (e) => e.message,
          'message',
          allOf(contains('P7'), contains('1.0.x')),
        ),
      ),
    );
  });

  test(
    'o pacote compila no web; FileEpubByteSource lança UnsupportedError',
    () {
      expect(ZipContainer.open, isNotNull);
      expect(() => FileEpubByteSource('a.epub'), throwsUnsupportedError);
    },
  );
}
```

Se houver Chrome ou Chromium:
Run: `CHROME_EXECUTABLE=/usr/bin/chromium flutter test --platform chrome test/container/inflate_web_test.dart`
Expected: `All tests passed!` (2 testes). Sem navegador, pular (pendência da
Tarefa 12).

- [ ] **Passo 6: Teste de corpus**

Criar `test/container/container_corpus_test.dart`. É teste de aceitação sobre
o código das Tarefas 1–9: deve passar de primeira. Se falhar, o defeito é da
tarefa dona do comportamento (não afrouxe o teste):

```dart
// O contêiner sobre os 65 EPUBs do corpus (spec do contêiner §9.1).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/container/zip/central_directory.dart';
import 'package:galley/src/container/zip/zip_container.dart';
import 'package:galley/src/diagnostics/diagnostic.dart';
import 'package:galley/src/diagnostics/exceptions.dart';
import 'package:galley/src/io/file_byte_source.dart';

import 'support/zip_fixtures.dart';

/// Códigos que o contêiner emite (spec §9.1).
const containerCodes = {
  'mimetypeIrregular',
  'zipCrcMismatch',
  'zipDuplicateEntry',
  'pathCaseMismatch',
  'fontObfuscationUnknown',
};

/// Dos acima, os `warning` (lançam em strict).
const containerWarnings = {'zipCrcMismatch', 'fontObfuscationUnknown'};

/// Grupos que rodam com `strict: false` (doc/10 §5).
const relaxedGroups = {'patologia', 'faixa-b'};

/// Teto de uma ida da fonte por `fetch`: a primeira leitura e, com extra
/// field grande no local header, a segunda só com os dados.
int fetchBound(ZipEntry e, {required int calls}) =>
    30 +
    e.nameLength +
    e.compressedSize +
    1024 +
    (calls > 1 ? e.compressedSize : 0);

Future<void> _drainAll(ZipContainer c, CountingByteSource counting) async {
  for (final path in c.paths) {
    counting.reset();
    final r = (await c.fetch(path))!;
    final entry = c.centralDirectory.lookup(path)!.entry;
    expect(counting.calls, inInclusiveRange(1, 2), reason: path);
    expect(
      counting.bytesRead,
      lessThanOrEqualTo(fetchBound(entry, calls: counting.calls)),
      reason: 'fetch de $path leu demais',
    );
    for (final _ in r.decode()) {}
  }
}

List<String> _lines(File f) => f.existsSync()
    ? f.readAsLinesSync().where((l) => l.isNotEmpty).toList()
    : const [];

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

  test('corpus tem os 65 casos', () {
    expect(cases, hasLength(65));
  });

  for (final name in cases) {
    final dir = '${root.path}/$name';
    final group = name.split('/').first;
    final strict = !relaxedGroups.contains(group);
    final exception = _lines(File('$dir/exception.expected')).firstOrNull;
    final expectedCodes = _lines(File('$dir/diagnostics.expected'))
        .where(containerCodes.contains)
        .toSet();

    test('$name (strict: $strict)', () async {
      final counting = CountingByteSource(FileEpubByteSource('$dir/book.epub'));
      final sink = DiagnosticSink(strict: strict);
      final open = ZipContainer.open(counting, sink: sink);
      switch (exception) {
        case 'EpubContainerException':
          await expectLater(open, throwsA(isA<EpubContainerException>()));
          return;
        case 'EpubEncryptedException':
          await expectLater(open, throwsA(isA<EpubEncryptedException>()));
          return;
      }
      final c = await open;
      final cd = c.centralDirectory;
      int bound(String path) {
        final e = cd.lookup(path)?.entry;
        return e == null ? 0 : fetchBound(e, calls: 2);
      }

      expect(
        counting.bytesRead,
        lessThanOrEqualTo(
          tailReadSize +
              (cd.zip64 ? 56 : 0) +
              cd.cdSize +
              bound('mimetype') +
              bound('META-INF/encryption.xml') +
              bound('META-INF/rights.xml'),
        ),
        reason: 'a abertura leu demais',
      );

      await _drainAll(c, counting);
      final emitted = sink.diagnostics
          .map((d) => d.code.name)
          .where(containerCodes.contains)
          .toSet();
      expect(emitted, expectedCodes);
      await c.close();
    });

    if (group == 'patologia' && expectedCodes.any(containerWarnings.contains)) {
      test('$name (segunda passada, strict: true)', () async {
        final source = CountingByteSource(FileEpubByteSource('$dir/book.epub'));
        Future<void> run() async {
          final c = await ZipContainer.open(
            source,
            sink: DiagnosticSink(strict: true),
          );
          await _drainAll(c, source);
        }

        await expectLater(run(), throwsA(isA<EpubContainerException>()));
        await source.close();
      });
    }
  }
}
```

- [ ] **Passo 7: Rodar o corpus**

Run: `flutter test test/container/container_corpus_test.dart`
Expected: `All tests passed!` (68 testes: a contagem, os 65 casos e a segunda
passada de `patologia/crc-errado` e `patologia/ofuscacao-desconhecida`).

- [ ] **Passo 8: Suíte inteira, formatação e analyze**

Run: `dart format --output=none --set-exit-if-changed lib test tool example/lib example/integration_test && flutter analyze && flutter test`
Expected: nada a formatar, `No issues found!` e `All tests passed!`.

- [ ] **Passo 9: Commit**

```bash
git add lib/galley.dart test/container/public_api_test.dart test/container/inflate_web_test.dart test/container/container_corpus_test.dart
git commit -m "feat(container): exports públicos e teste de corpus do contêiner

Os 65 EPUBs abrem (ou lançam a exceção esperada), todo recurso é lido e
decodificado, os códigos do contêiner batem com diagnostics.expected, a
patologia com warning lança na segunda passada em strict, e nenhuma
leitura passa do orçamento de §9.1."
```

---

### Tarefa 11: Casos de desempenho

Spec §10. Três casos novos no harness, com `innerIterations` para ~5 ms por
amostra, medidos no scratchpad (ver "O que foi verificado").

**Arquivos:**
- Modificar: `test/perf/perf_test.dart` (substituir inteiro)

**Interfaces:**
- Consome: `PerfCase({required String id, void Function()? run, Future<void> Function()? runAsync, Future<void> Function()? setUp, int innerIterations = 1})`, `measureCase`, `writeResultIfAny` (`test/perf/support/perf_harness.dart`); `proseBytes` (`test/perf/support/perf_inputs.dart`); `ZipWriter`; `ZipContainer`, `MemoryEpubByteSource`, `DiagnosticSink`, `deobfuscateFont`, `FontObfuscation`.
- Produz: casos `zip.open.800`, `zip.fetch.inflate.1mb`, `font.deobfuscate.idpf` no `build/perf/result.json`.

- [ ] **Passo 1: Acrescentar os casos**

Substituir `test/perf/perf_test.dart` inteiro por (os quatro casos da Fase 0
não mudam):

```dart
// Casos de desempenho: primitivas da Fase 0 (spec do harness §2.4) e o
// contêiner da Fase 1 (spec do contêiner §10). Rodar com:
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
      },
      innerIterations: 10, // ≈ 5 ms por amostra
    ),
    PerfCase(
      id: 'zip.fetch.inflate.1mb',
      setUp: () async {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final results = <String, PerfCaseResult>{};

  for (final c in [..._phase0Cases(), ..._containerCases()]) {
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
Expected: `All tests passed!` e sete linhas `[perf] …`. As três novas com
caso entre ~3 000 e ~8 000 µs (no i5-11400H: 6 987, 4 812 e 5 720 µs). Se uma
delas ficar abaixo de 2 000 µs ou acima de 10 000 µs, ajustar o
`innerIterations` dela proporcionalmente e rodar de novo.

- [ ] **Passo 3: Comparar**

Run: `dart run tool/perf/compare.dart --baseline test/perf/baselines/amd-epyc-7763-64-core-processor.json`
Expected: os três casos novos como `novo, sem baseline` e `**Resultado: passou.**`.

- [ ] **Passo 4: Suíte normal pula o perf**

Run: `flutter test test/perf`
Expected: `All tests passed!` com os casos `perf` pulados.

- [ ] **Passo 5: Formatar e analisar**

Run: `dart format test/perf && flutter analyze`
Expected: nada mudado e `No issues found!`.

- [ ] **Passo 6: Commit**

```bash
git add test/perf/perf_test.dart
git commit -m "test: casos de desempenho do contêiner

zip.open.800 (central directory grande), zip.fetch.inflate.1mb (CRC e
fatias de 16 KiB, comparável ao zlib.inflate.1mb) e
font.deobfuscate.idpf (spec §10). Sem baseline até o perf-baseline
ser disparado depois do merge."
```

---

### Tarefa 12: Documentação

Spec §7. Cada troca abaixo é de um trecho que aparece **uma vez** no arquivo;
se não achar o trecho exato, pare e confira com `grep -n`.

**Arquivos:**
- Modificar: `doc/03-camada-a-ir.md` (§2.2 e §3.2)
- Modificar: `doc/07-api-publica.md` (§1)
- Modificar: `doc/08-concorrencia-cache.md` (§1 e §3)
- Modificar: `doc/09-erros-diagnosticos.md` (§1, §2, §3, §4 e §5)
- Modificar: `doc/11-empacotamento-versionamento.md` (§4)
- Modificar: `doc/14-pendencias.md` (Fase 1)
- Modificar: `test/corpus/corpus_test.dart` (`knownDiagnostics`)
- Modificar: `doc/specs/2026-09-25-container-design.md` (estado)
- Modificar: `CHANGELOG.md`

**Interfaces:** nenhuma.

- [ ] **Passo 1: `doc/03` §2.2 (leitor de ZIP)**

Em `doc/03-camada-a-ir.md`, trocar:

```markdown
Próprio, cerca de 300 linhas. Toda a arquitetura repousa sobre acesso aleatório
lazy, e nenhum pacote existente entrega essa forma.

- Lê o **end of central directory** e o **central directory** uma única vez na
  abertura, montando `Map<String, ZipEntry>` com offset, tamanho comprimido,
  tamanho original e método. Lê os últimos 64 KB do arquivo de uma vez para
  cobrir o comentário do EOCD sem segunda ida ao disco
- Suporta **ZIP64** para EOCD e central directory, porque arquivos acima de 4 GB
  são raros mas arquivos com mais de 65 535 entradas existem
- Infla uma entrada só quando pedida, direto para `Uint8List`
- **Nunca** carrega o arquivo inteiro em memória
- Suporta `stored` (método 0) e `deflate` (método 8); qualquer outro método
  levanta `EpubContainerException`
- Ignora o local file header exceto para o tamanho do nome e do extra field, que
  precisa pular para achar os dados; confia no central directory para tudo mais
- Valida CRC-32 só em modo `strict` ([09](09-erros-diagnosticos.md) §5); em
  produção, um CRC errado vira diagnóstico `zipCrcMismatch`
```

por:

```markdown
Próprio, em `lib/src/container/zip/`. Toda a arquitetura repousa sobre acesso
aleatório lazy, e nenhum pacote existente entrega essa forma. Detalhes em
[specs/2026-09-25-container-design.md](specs/2026-09-25-container-design.md) §5.

- Lê o fim do arquivo (os últimos 65 577 bytes: o maior comentário do EOCD, o
  EOCD e o locator ZIP64) numa leitura e o **central directory** inteiro
  noutra, uma única vez na abertura, montando o índice por nome (exato e sem
  diferenciar maiúsculas)
- Suporta **ZIP64** para EOCD e central directory, porque arquivos acima de 4 GB
  são raros mas arquivos com mais de 65 535 entradas existem; percorre o
  central directory pelo tamanho, não pela contagem
- **Prefixo** (EPUB colado depois de outro arquivo): todos os offsets recebem o
  deslocamento, com diagnóstico `mimetypeIrregular` (`reason: prefix`)
- **Nomes:** com o bit 11, UTF-8 tolerante; sem ele, UTF-8 se válido, senão
  CP437. `\` vira `/`, `/` e `./` iniciais caem; diretórios ficam fora do índice
- **Duplicatas:** vence a primeira entrada do central directory; as outras
  emitem `zipDuplicateEntry`
- `fetch` faz **uma** ida à fonte (local header e dados); `decode()` é `sync*`,
  infla em fatias de 16 KiB e tem um passo a cada 64 KiB de saída
- **Nunca** carrega o arquivo inteiro em memória (medido no teste de corpus)
- `maxEntrySize` (256 MiB descomprimidos): entrada maior, ou saída maior que a
  declarada, é ilegível; proteção contra zip bomb
- Suporta `stored` (método 0) e `deflate` (método 8); qualquer outro método
  levanta `EpubContainerException` daquela entrada
- Do local file header só usa o tamanho do nome e do extra field, que precisa
  pular para achar os dados; tamanhos e CRC vêm sempre do central directory,
  inclusive com data descriptor
- **CRC-32 sempre verificado** durante o `decode()`: em produção, um CRC errado
  (ou saída curta) vira diagnóstico `zipCrcMismatch`; em `strict`
  ([09](09-erros-diagnosticos.md) §5), exceção
```

- [ ] **Passo 2: `doc/03` §3.2 (diferença de caixa)**

Em `doc/03-camada-a-ir.md`, trocar:

```markdown
| Diferença de caixa entre manifest e ZIP | Segunda tentativa case-insensitive, com diagnóstico |
```

por:

```markdown
| Diferença de caixa entre manifest e ZIP | Segunda tentativa case-insensitive, com diagnóstico `pathCaseMismatch` |
```

- [ ] **Passo 3: `doc/07` §1**

Em `doc/07-api-publica.md`, trocar:

```markdown
  source: FileEpubByteSource(file),
```

por:

```markdown
  source: FileEpubByteSource(path),
```

- [ ] **Passo 4: `doc/08` §1 (prólogo assíncrono)**

Em `doc/08-concorrencia-cache.md`, trocar:

```markdown
implementações do mesmo `EpubByteSource`; a segunda é a padrão em plataformas com
`dart:io`.
```

por:

```markdown
implementações do mesmo `EpubByteSource`; a segunda é a padrão em plataformas com
`dart:io`.

**Prólogo assíncrono, corpo síncrono.** `readRange` devolve `Future`, e um
gerador `sync*` não espera. Por isso a tarefa que lê do contêiner tem duas
partes: um prólogo assíncrono com as idas à fonte (`EpubContainer.fetch`, uma
por entrada) e um corpo `sync*` que decodifica e processa
(`PendingResource.decode()` e o que vem depois), com os checkpoints de §3
([spec do contêiner](specs/2026-09-25-container-design.md) §4).
```

- [ ] **Passo 5: `doc/08` §3 (checkpoint do inflate)**

Em `doc/08-concorrencia-cache.md`, trocar:

```markdown
| Inflate de entrada | A cada 64 KB de saída |
```

por:

```markdown
| Inflate e CRC de entrada | A cada 64 KiB completos de saída e mais um ao terminar; no stored, o passo é o CRC de cada 64 KiB |
```

- [ ] **Passo 6: `doc/09` §1 (quinta condição fatal)**

Em `doc/09-erros-diagnosticos.md`, trocar:

```markdown
> ausente, OPF inválido e spine vazio. Uma quinta, DRM não suportado, é fatal por
> honestidade: não há nada legível para mostrar.
```

por:

```markdown
> ausente, OPF inválido e spine vazio. Uma quinta, DRM não suportado, é fatal por
> honestidade: não há nada legível para mostrar. Ela inclui `encryption.xml`
> ilegível (sem como provar que não há DRM) e ZIP com a criptografia do próprio
> formato (bit 0 da flag).
```

- [ ] **Passo 7: `doc/09` §2 (`EpubContainerException`)**

Em `doc/09-erros-diagnosticos.md`, trocar:

```markdown
| `EpubContainerException` | ZIP corrompido, método de compressão não suportado, `container.xml` ausente | **Sim**, em `open` | — |
```

por:

```markdown
| `EpubContainerException` | ZIP corrompido (EOCD ou central directory ilegível), `container.xml` ausente; depois de `open`, entrada ilegível (método não suportado, dados corrompidos, acima de `maxEntrySize`) | **Sim**, em `open`; depois dele, é falha de uma entrada | Entrada ilegível vira seção `placeholder` com `resourceUnreadable`; só é fatal quando é o `container.xml` ou o OPF |
```

- [ ] **Passo 8: `doc/09` §3 (códigos)**

Em `doc/09-erros-diagnosticos.md`, trocar:

```markdown
| `mimetypeIrregular` | info | `mimetype` não é a primeira entrada ou está comprimido |
| `zipCrcMismatch` | warning | CRC-32 da entrada não bate (só verificado em `strict`) |
```

por:

```markdown
| `mimetypeIrregular` | info | `mimetype` ausente, fora do primeiro lugar, comprimido, com conteúdo errado ou ilegível, ou ZIP com prefixo; o motivo em `details.reason` |
| `zipCrcMismatch` | warning | CRC-32 divergente (`reason: crc`) ou saída menor que a declarada (`reason: size`); sempre verificado |
| `zipDuplicateEntry` | info | Nome repetido no central directory; vale a primeira entrada |
| `pathCaseMismatch` | info | Caminho achado só sem diferenciar maiúsculas; o nome real em `details.actual` |
| `resourceUnreadable` | warning | Entrada ilegível convertida em placeholder; `details.reason` e `details.exception` |
| `encryptionIgnored` | info | `encryption.xml` inválido num livro servido por `EpubResourceProvider`; ofuscação ignorada |
```

- [ ] **Passo 9: `doc/09` §4 (detecção de DRM)**

Em `doc/09-erros-diagnosticos.md`, trocar:

```markdown
| **DRM real** (LCP, ACS, proprietário) | Qualquer outro algoritmo, ou algoritmo de fonte aplicado a conteúdo | `EpubEncryptedException`, fatal, com o esquema identificado na mensagem (`lcp`, `adobe-adept`, `unknown:<uri>`) |
```

por:

```markdown
| **DRM real** (LCP, ACS, proprietário) | `META-INF/license.lcpl` (LCP); `META-INF/rights.xml` (ADEPT pelo namespace `http://ns.adobe.com/adept`, senão desconhecido); `KeyInfo` com o `RetrievalMethod` do LCP ou com elemento do namespace do ADEPT; qualquer outro algoritmo, ou algoritmo de fonte aplicado a conteúdo; `encryption.xml` que não é XML válido; bit 0 da flag do ZIP | `EpubEncryptedException`, fatal, com o esquema identificado na mensagem (`lcp`, `adobe-adept`, `zip-encryption`, `unknown:<detalhe>`) |
```

- [ ] **Passo 10: `doc/09` §5 (strict)**

Em `doc/09-erros-diagnosticos.md`, trocar:

```markdown
- CRC-32 das entradas do ZIP é verificado
```

por:

```markdown
- CRC-32 divergente (sempre verificado) vira exceção
```

- [ ] **Passo 11: `doc/11` §4 (`lib/src/diagnostics/`)**

Em `doc/11-empacotamento-versionamento.md`, trocar:

```markdown
      container/                  # byte source, zip, inflate, opf, nav, ncx, encryption
```

por:

```markdown
      container/                  # byte source, zip, inflate, opf, nav, ncx, encryption
      diagnostics/                # EpubException, EpubDiagnostic, DiagnosticSink
```

- [ ] **Passo 12: `doc/11` §4 (`test/container/` e `test/diagnostics/`)**

Em `doc/11-empacotamento-versionamento.md`, trocar:

```markdown
  test/
    corpus/                       # os 40–50 arquivos + READMEs + diagnósticos esperados
```

por:

```markdown
  test/
    container/                    # ZIP, inflate, DRM, fontes e o contêiner sobre o corpus
    diagnostics/                  # exceções e DiagnosticSink
    corpus/                       # os 40–50 arquivos + READMEs + diagnósticos esperados
```

- [ ] **Passo 13: `doc/14` (pendências da Fase 1)**

Em `doc/14-pendencias.md`, trocar:

```markdown
| Tamanho do pacote no web (inflate, SHA-1, CSS), teto de 300 KB minificado | [13](13-riscos-spikes-fases.md) §1.2 | Fase 1 |
```

por:

```markdown
| Tamanho do pacote no web (inflate, SHA-1, CSS), teto de 300 KB minificado | [13](13-riscos-spikes-fases.md) §1.2 | Fase 1 |
| Chave NFC no índice de nomes do contêiner: nomes do ZIP e caminhos pedidos comparados em NFC | [Spec do contêiner](specs/2026-09-25-container-design.md) §1.2 | Sub-projeto 4 (IR de seção), quando a normalização existir |
| `tool/corpus/lib/hashes.dart` duplica o CRC-32 e o SHA-1 de `lib/src/container/`; unificar quando `tool/` puder importar o pacote | [Spec do contêiner](specs/2026-09-25-container-design.md) §7 | Antes da 1.0 |
| `test/container/inflate_web_test.dart` só roda com `--platform chrome`; entra no CI junto com o job web | [Spec do contêiner](specs/2026-09-25-container-design.md) §7 | Com o job web (1.0.x) |
| Regenerar os baselines por CPU com `zip.open.800`, `zip.fetch.inflate.1mb` e `font.deobfuscate.idpf` (disparar o `perf-baseline`); até lá aparecem como "novo, sem baseline" | [Spec do contêiner](specs/2026-09-25-container-design.md) §10 | Logo depois do merge da PR do contêiner |
```

- [ ] **Passo 14: `test/corpus/corpus_test.dart` (`knownDiagnostics`)**

Em `test/corpus/corpus_test.dart`, trocar:

```dart
  'fontObfuscationUnknown',
  'sectionTooLarge',
};
```

por:

```dart
  'fontObfuscationUnknown',
  'sectionTooLarge',
  'zipDuplicateEntry',
  'pathCaseMismatch',
  'resourceUnreadable',
  'encryptionIgnored',
};
```

- [ ] **Passo 15: Estado da spec**

Em `doc/specs/2026-09-25-container-design.md`, trocar:

```markdown
**Data:** 2026-09-25. **Estado:** aprovada (revisão delegada pelo dono do
repositório ao executor, com uma revisão independente cujos achados estão
incorporados). **Branch:** `fase1/container`.
```

por:

```markdown
**Data:** 2026-09-25. **Estado:** aprovada e implementada (plano em
`doc/plans/2026-09-25-container.md`; revisão delegada pelo dono do repositório
ao executor, com uma revisão independente cujos achados estão incorporados).
**Branch:** `fase1/container`.
```

- [ ] **Passo 16: `CHANGELOG.md`**

Em `CHANGELOG.md`, trocar:

```markdown
## Não lançado
```

por:

```markdown
## Não lançado

- Fase 1, sub-projeto 1 (contêiner): leitor de ZIP próprio com leitura por
  faixas, ZIP64, prefixo e limites contra arquivo hostil; inflate chunked com
  CRC-32 sempre verificado; detecção de DRM (LCP, ADEPT, criptografia do ZIP);
  desofuscação de fontes IDPF e Adobe; `FileEpubByteSource`,
  `MemoryEpubByteSource`, `EpubResourceProvider`, `EpubException` e
  `EpubDiagnostic` públicos.
```

- [ ] **Passo 17: Conferir**

Run: `flutter test test/corpus/corpus_test.dart && grep -c 'pathCaseMismatch' doc/09-erros-diagnosticos.md doc/03-camada-a-ir.md && grep -n 'FileEpubByteSource(file)' doc/07-api-publica.md; echo "restos: $?"`
Expected: `All tests passed!`, contagem ≥ 1 nos dois documentos e `restos: 1`.

- [ ] **Passo 18: Commit**

```bash
git add doc CHANGELOG.md test/corpus/corpus_test.dart
git commit -m "docs: contêiner nos documentos de arquitetura e pendências

CRC sempre verificado, fetch/decode e maxEntrySize (03), FileEpubByteSource
(07), prólogo assíncrono e checkpoint do inflate (08), fatalidade por
entrada, códigos novos e detecção de DRM (09), diretórios novos (11),
pendências do sub-projeto (14) e knownDiagnostics do corpus."
```

---

### Tarefa 13: PR e CI verde

**Arquivos:** nenhum novo; correções que o CI exigir vão no arquivo afetado,
com commit próprio.

**Interfaces:** nenhuma.

- [ ] **Passo 1: Verificação local completa**

Run: `dart format --output=none --set-exit-if-changed lib test tool example/lib example/integration_test && flutter analyze && (cd example && flutter analyze) && flutter test && git status --short`
Expected: nada a formatar, `No issues found!` duas vezes, `All tests passed!` e
`git status` vazio.

- [ ] **Passo 2: Push e PR**

O repositório é pessoal: a conta ativa do `gh` deve ser `EduardoSA8006`
(`gh auth status`; se não for, `gh auth switch --user EduardoSA8006`).

Escrever o corpo da PR num arquivo do scratchpad
(`/tmp/claude-1000/-home-eduardo8006-Documentos-projetos-galley/003640ed-5627-4a8b-81ed-13354cf11bdd/scratchpad/pr-container.md`),
no formato do `.github/pull_request_template.md`: **Resumo** (o que o
sub-projeto entrega, citando a spec e doc/09), **Commits** (a lista de
`git log --oneline main..HEAD`), **Verificação** (as cinco caixas do template
marcadas, mais "teste de corpus nos 65 EPUBs com orçamento de leitura" e,
se rodou, "`inflate_web_test` no Chrome") e **Pontos para revisar** (as
decisões 2, 4, 6, 8 e 9 da seção "Decisões onde a spec é ambígua" e os casos
novos de desempenho sem baseline).

```bash
git push -u origin fase1/container
gh pr create --repo EduardoSA8006/galley --base main --head fase1/container \
  --title "Fase 1, sub-projeto 1: contêiner (ZIP, inflate, DRM, fontes e diagnósticos)" \
  --body-file /tmp/claude-1000/-home-eduardo8006-Documentos-projetos-galley/003640ed-5627-4a8b-81ed-13354cf11bdd/scratchpad/pr-container.md
```

Expected: URL da PR.

- [ ] **Passo 3: Acompanhar o CI**

Run: `gh pr checks --watch --repo EduardoSA8006/galley`
Expected: `analyze`, `test (min)`, `test (stable)`, `engine-linux` e `perf`
verdes; no resumo do `perf`, os três casos novos como "novo, sem baseline".

Falha no `test (min)` ou `test (stable)` que não aparece localmente: rodar o
arquivo que falhou com `flutter test <arquivo>` na versão do job
(`FLUTTER_MIN` 3.47.0 ou o `stable` do log) e investigar a causa antes de
mexer (superpowers:systematic-debugging). Diferença de tempo no CI não é
motivo para afrouxar teste; o único teste com dependência de ambiente é o de
fontes do corpus, que lê arquivos versionados. O que for adiado vai para
`doc/14-pendencias.md`, com commit `docs: …`.

- [ ] **Passo 4: Depois do merge (pelo mantenedor)**

Disparar o `perf-baseline` para regenerar os baselines com os casos novos
(pendência registrada na Tarefa 12):

```bash
gh workflow run perf-baseline.yml --repo EduardoSA8006/galley --ref main
```

O resto do fluxo do baseline (baixar, conferir, PR) segue o
`doc/plans/2026-09-25-harness-ci.md`, Tarefa 10.

