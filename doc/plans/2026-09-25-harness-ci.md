# Harness de desempenho e CI — plano de implementação

> **Para agentes:** SUB-SKILL OBRIGATÓRIA: use superpowers:subagent-driven-development
> (recomendado) ou superpowers:executing-plans para executar tarefa por tarefa. Os
> passos usam checkbox (`- [ ]`).

**Objetivo:** fechar a Fase 0 com um harness de desempenho normalizado, um
comparador com gate de 20%, baseline versionado, CI no GitHub Actions e Flutter
mínimo 3.47.0.

**Arquitetura:** o modelo do JSON, a estatística, o comparador e a combinação do
baseline são Dart puro em `tool/perf/lib/`, testados na suíte normal. O harness
em `test/perf/support/` roda no `flutter_tester` (precisa de `dart:ui`), usa o
mesmo modelo para escrever `build/perf/result.json`, e só roda com a tag
`perf`. O CI chama os dois.

**Stack:** Flutter 3.47.0 (Dart 3.13.0), `flutter_test`, `package:html`,
`dart:ui`, `dart:io`, GitHub Actions (`actions/checkout@v7`,
`actions/upload-artifact@v7`, `subosito/flutter-action@v2`).

**Spec:** `doc/specs/2026-09-25-harness-ci-design.md`. Leia antes de começar.

## Restrições globais

- Flutter mínimo `>=3.47.0`; Dart `^3.13.0`. No CI, `FLUTTER_MIN: 3.47.0`.
- Nenhuma dependência nova em `pubspec.yaml` (nem de desenvolvimento).
- Gate: falha se `ratio_atual / ratio_baseline > 1,20`; aviso de melhora se `< 0,80`.
- Amostragem: 3 de aquecimento, 15 medidas; calibração e caso intercalados.
- Harness só roda com `flutter test --tags perf --run-skipped test/perf`; a
  suíte normal (`flutter test`) pula os casos `perf`.
- `result.json` em `build/perf/` (fora do git); baseline em `test/perf/baseline.json`.
- Texto em português brasileiro com acentuação; identificadores em inglês, como
  no resto do repositório.
- Shell com alias interativo: use `\mv -f`, `\cp -f`, `\rm -rf`.
- Nenhum arquivo de depuração versionado; rascunhos no scratchpad da sessão.
- Tudo na branch `fase0/harness-ci`.

## Foco de revisão

1. **`result.json` inexistente** (harness não rodou ou caiu): o comparador sai
   com código 1 e uma mensagem que nomeia o arquivo, sem stack trace. Teste na
   Tarefa 3.
2. **Suíte normal com os casos pulados**: `flutter test` não pode criar nem
   sobrescrever `build/perf/result.json` com um relatório vazio. Teste na
   Tarefa 5 (`writeResultIfAny` com mapa vazio).
3. **Caso rápido demais** (corpo quase vazio): a razão não pode sair 0, porque o
   modelo rejeita `ratio <= 0` e o baseline ficaria impossível de gerar. Teste
   na Tarefa 5.
4. **Combinar execuções incompatíveis** (Flutter diferente ou conjunto de casos
   diferente): `update_baseline` falha em vez de tirar mediana de coisas
   diferentes. Teste na Tarefa 4.
5. **Versão mínima divergente** entre `pubspec.yaml`, `example/pubspec.yaml` e
   os dois workflows: um teste lê os quatro e exige o mesmo valor. Teste na
   Tarefa 7.

---

### Tarefa 1: Flutter mínimo 3.47.0 e formatação

**Arquivos:**
- Modificar: `pubspec.yaml` (bloco `environment`)
- Modificar: `example/pubspec.yaml` (bloco `environment`)
- Modificar: `example/pubspec.lock` (gerado)
- Modificar: os 7 arquivos de `test/spike/` que o formatter aponta

**Interfaces:** nenhuma.

- [ ] **Passo 1: Trocar o `environment` da raiz**

Em `pubspec.yaml`, substituir:

```yaml
environment:
  sdk: ^3.12.1
  # Versão mínima fixada na Fase 0 (doc/11 §2). Revisar após os spikes.
  flutter: ">=3.44.0"
```

por:

```yaml
environment:
  sdk: ^3.13.0
  # Mínimo testado no CI (FLUTTER_MIN dos workflows); ver doc/11 §2.
  flutter: ">=3.47.0"
```

- [ ] **Passo 2: Trocar o `environment` do exemplo**

Em `example/pubspec.yaml`, substituir:

```yaml
environment:
  sdk: ^3.12.1
```

por:

```yaml
environment:
  sdk: ^3.13.0
  flutter: ">=3.47.0"
```

- [ ] **Passo 3: Resolver dependências**

Run: `flutter pub get && (cd example && flutter pub get)`
Expected: `Got dependencies!` nos dois.

- [ ] **Passo 4: Ver o que o formatter mudaria**

Run: `dart format --output=none --set-exit-if-changed lib test tool example/lib example/integration_test`
Expected: lista os arquivos que mudariam. Esperam-se os 7 de `test/spike/`
(`s5_line_metrics_stability_test.dart`, `s5_soft_hyphen_test.dart`,
`s6_font_deobfuscation_test.dart`, `s7_placeholder_and_decode_test.dart`,
`s8_anchored_pagination_test.dart`, `support/s6_font_obfuscation.dart`,
`support/s8_paginator.dart`); a subida da versão de linguagem pode acrescentar
outros. Anote a lista.

- [ ] **Passo 5: Formatar**

Run: `dart format lib test tool example/lib example/integration_test`
Expected: `Formatted N files (M changed)`.

- [ ] **Passo 6: Conferir que o diff é só formatação**

Run: `git diff --stat && git diff test/spike | grep '^[-+]' | grep -v '^[-+][-+]' | tr -d ' \t,' | sort | uniq -u | head -40`
Expected: o `--stat` lista só os pubspecs, o `example/pubspec.lock` e os
arquivos anotados no Passo 4. O segundo comando compara as linhas removidas e
acrescentadas sem espaço nem vírgula: a saída deve estar vazia ou mostrar só
linhas com `+`/`-` que diferem por quebra de linha. Se aparecer mudança de
token, pare e investigue.

- [ ] **Passo 7: Analyze e testes**

Run: `flutter analyze && (cd example && flutter analyze) && flutter test`
Expected: `No issues found!` duas vezes e `All tests passed!`.

- [ ] **Passo 8: Commit**

```bash
git add pubspec.yaml example/pubspec.yaml example/pubspec.lock test/spike
git commit -m "chore: Flutter mínimo 3.47.0 e formatação no Dart 3.13

O mínimo passa a ser a versão que o CI testa (FLUTTER_MIN). A subida do
sdk para ^3.13.0 acompanha o Dart da 3.47.0; os spikes S5–S8 são
reformatados pelo formatter do Dart 3.13, sem mudança de código."
```

---

### Tarefa 2: Modelo do relatório e mediana

**Arquivos:**
- Criar: `tool/perf/lib/stats.dart`
- Criar: `tool/perf/lib/perf_report.dart`
- Teste: `test/tool/perf_report_test.dart`

**Interfaces:**
- Produz: `double median(Iterable<double> values)` (lança `ArgumentError` se vazio).
- Produz: `const int perfSchemaVersion = 1`.
- Produz: `final class PerfFormatException implements Exception { PerfFormatException(String source, String message); final String source; final String message; }`.
- Produz: `final class PerfCaseResult { const PerfCaseResult({required double ratio, required double medianUs, required double calibrationUs, List<double> samples = const []}); }`.
- Produz: `final class PerfReport { const PerfReport({required String flutter, required String dart, required String os, required DateTime createdAt, required Map<String, PerfCaseResult> cases, String? sourceCommit, String? runner, int? runs}); factory PerfReport.parse(String text, {required String source}); String encode({bool includeSamples = true}); }`.

- [ ] **Passo 1: Escrever o teste que falha**

Criar `test/tool/perf_report_test.dart`:

```dart
// Modelo do JSON do harness de desempenho (spec §2.5 e §3.3).
import 'package:flutter_test/flutter_test.dart';

import '../../tool/perf/lib/perf_report.dart';
import '../../tool/perf/lib/stats.dart';

PerfReport _report() => PerfReport(
  flutter: '3.47.0',
  dart: '3.13.0',
  os: 'linux',
  createdAt: DateTime.utc(2026, 9, 25, 12),
  cases: const {
    'z.last': PerfCaseResult(
      ratio: 2.5,
      medianUs: 1000,
      calibrationUs: 400,
      samples: [2.4, 2.5, 2.6],
    ),
    'a.first': PerfCaseResult(ratio: 1.5, medianUs: 600, calibrationUs: 400),
  },
);

void main() {
  group('median', () {
    test('ímpar devolve o central', () {
      expect(median([3, 1, 2]), 2);
    });
    test('par devolve a média dos centrais', () {
      expect(median([4, 1, 3, 2]), 2.5);
    });
    test('vazio lança', () {
      expect(() => median(const []), throwsArgumentError);
    });
  });

  group('PerfReport', () {
    test('ida e volta preserva os campos', () {
      final back = PerfReport.parse(_report().encode(), source: 'mem');
      expect(back.flutter, '3.47.0');
      expect(back.dart, '3.13.0');
      expect(back.os, 'linux');
      expect(back.createdAt, DateTime.utc(2026, 9, 25, 12));
      expect(back.cases['z.last']!.ratio, 2.5);
      expect(back.cases['z.last']!.samples, [2.4, 2.5, 2.6]);
      expect(back.cases['a.first']!.calibrationUs, 400);
    });

    test('encode ordena os casos por id', () {
      final text = _report().encode();
      expect(text.indexOf('a.first'), lessThan(text.indexOf('z.last')));
    });

    test('encode sem amostras omite samples e mantém o resto', () {
      final text = _report().encode(includeSamples: false);
      expect(text, isNot(contains('samples')));
      expect(PerfReport.parse(text, source: 'mem').cases['z.last']!.samples, isEmpty);
    });

    test('campos do baseline fazem ida e volta', () {
      final base = PerfReport(
        flutter: '3.47.0',
        dart: '3.13.0',
        os: 'linux',
        createdAt: DateTime.utc(2026, 9, 25),
        cases: const {},
        sourceCommit: 'abc123',
        runner: 'ubuntu-24.04',
        runs: 3,
      );
      final back = PerfReport.parse(base.encode(), source: 'mem');
      expect(back.sourceCommit, 'abc123');
      expect(back.runner, 'ubuntu-24.04');
      expect(back.runs, 3);
    });

    test('números inteiros no JSON são aceitos', () {
      const text = '{"schema":1,"flutter":"x","dart":"y","os":"linux",'
          '"createdAt":"2026-09-25T00:00:00.000Z",'
          '"cases":{"c":{"ratio":2,"medianUs":36120,"calibrationUs":4874}}}';
      expect(PerfReport.parse(text, source: 'mem').cases['c']!.medianUs, 36120);
    });

    test('JSON inválido nomeia a origem', () {
      expect(
        () => PerfReport.parse('{', source: 'build/perf/result.json'),
        throwsA(
          isA<PerfFormatException>().having(
            (e) => e.toString(),
            'toString',
            contains('build/perf/result.json'),
          ),
        ),
      );
    });

    test('schema desconhecido é recusado', () {
      final text = _report().encode().replaceFirst('"schema": 1', '"schema": 2');
      expect(
        () => PerfReport.parse(text, source: 'mem'),
        throwsA(
          isA<PerfFormatException>().having(
            (e) => e.message,
            'message',
            contains('schema desconhecido'),
          ),
        ),
      );
    });

    test('ratio não positivo nomeia o campo', () {
      const text = '{"schema":1,"flutter":"x","dart":"y","os":"linux",'
          '"createdAt":"2026-09-25T00:00:00.000Z",'
          '"cases":{"c":{"ratio":0,"medianUs":1,"calibrationUs":1}}}';
      expect(
        () => PerfReport.parse(text, source: 'mem'),
        throwsA(
          isA<PerfFormatException>().having(
            (e) => e.message,
            'message',
            contains('cases.c.ratio'),
          ),
        ),
      );
    });

    test('campo obrigatório ausente nomeia o campo', () {
      const text = '{"schema":1,"dart":"y","os":"linux",'
          '"createdAt":"2026-09-25T00:00:00.000Z","cases":{}}';
      expect(
        () => PerfReport.parse(text, source: 'mem'),
        throwsA(
          isA<PerfFormatException>().having(
            (e) => e.message,
            'message',
            contains("'flutter'"),
          ),
        ),
      );
    });
  });
}
```

- [ ] **Passo 2: Rodar e ver falhar**

Run: `flutter test test/tool/perf_report_test.dart`
Expected: FAIL de compilação (`perf_report.dart` e `stats.dart` não existem).

- [ ] **Passo 3: Implementar `stats.dart`**

Criar `tool/perf/lib/stats.dart`:

```dart
/// Estatística mínima do harness de desempenho.
library;

/// Mediana de [values]. Com tamanho par, média dos dois centrais.
double median(Iterable<double> values) {
  final sorted = values.toList()..sort();
  if (sorted.isEmpty) {
    throw ArgumentError.value(values, 'values', 'mediana de lista vazia');
  }
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
}
```

- [ ] **Passo 4: Implementar `perf_report.dart`**

Criar `tool/perf/lib/perf_report.dart`:

```dart
/// Modelo do JSON do harness de desempenho: `build/perf/result.json` e
/// `test/perf/baseline.json` (doc/specs/2026-09-25-harness-ci-design.md §2.5).
library;

import 'dart:convert';

/// Versão do formato. Mudar o formato exige subir este número.
const int perfSchemaVersion = 1;

/// JSON do harness malformado ou de formato desconhecido.
final class PerfFormatException implements Exception {
  PerfFormatException(this.source, this.message);

  /// Arquivo (ou outra origem) de onde o JSON veio.
  final String source;
  final String message;

  @override
  String toString() => '$source: $message';
}

/// Medida de um caso.
final class PerfCaseResult {
  const PerfCaseResult({
    required this.ratio,
    required this.medianUs,
    required this.calibrationUs,
    this.samples = const [],
  });

  /// Mediana, por amostra, de tempo do caso ÷ tempo da calibração. É o que o
  /// gate compara.
  final double ratio;

  /// Mediana do tempo do caso, em µs, para leitura humana.
  final double medianUs;

  /// Mediana do tempo da calibração, em µs, para leitura humana.
  final double calibrationUs;

  /// Razão de cada amostra; vazio no baseline.
  final List<double> samples;
}

/// Um `result.json` ou um `baseline.json`.
final class PerfReport {
  const PerfReport({
    required this.flutter,
    required this.dart,
    required this.os,
    required this.createdAt,
    required this.cases,
    this.sourceCommit,
    this.runner,
    this.runs,
  });

  factory PerfReport.parse(String text, {required String source}) {
    final Object? root;
    try {
      root = jsonDecode(text);
    } on FormatException catch (e) {
      throw PerfFormatException(source, 'JSON inválido: ${e.message}');
    }
    final r = _Reader(source);
    final top = r.object(root, '(raiz)');
    final schema = r.integer(top, 'schema');
    if (schema != perfSchemaVersion) {
      throw PerfFormatException(
        source,
        'schema desconhecido: $schema (esperado $perfSchemaVersion)',
      );
    }
    final casesJson = r.object(top['cases'], 'cases');
    final cases = <String, PerfCaseResult>{};
    for (final MapEntry(:key, :value) in casesJson.entries) {
      final prefix = 'cases.$key';
      final c = r.object(value, prefix);
      final ratio = r.number(c, 'ratio', prefix);
      if (ratio <= 0) {
        throw PerfFormatException(
          source,
          "campo '$prefix.ratio' deve ser maior que zero, veio $ratio",
        );
      }
      cases[key] = PerfCaseResult(
        ratio: ratio,
        medianUs: r.number(c, 'medianUs', prefix),
        calibrationUs: r.number(c, 'calibrationUs', prefix),
        samples: r.numberList(c, 'samples', prefix),
      );
    }
    return PerfReport(
      flutter: r.string(top, 'flutter'),
      dart: r.string(top, 'dart'),
      os: r.string(top, 'os'),
      createdAt: r.date(top, 'createdAt'),
      cases: cases,
      sourceCommit: r.optionalString(top, 'sourceCommit'),
      runner: r.optionalString(top, 'runner'),
      runs: r.optionalInteger(top, 'runs'),
    );
  }

  final String flutter;
  final String dart;
  final String os;
  final DateTime createdAt;
  final Map<String, PerfCaseResult> cases;

  /// Commit de onde o baseline foi medido. Só no baseline.
  final String? sourceCommit;

  /// Runner do CI onde o baseline foi medido. Só no baseline.
  final String? runner;

  /// Número de execuções combinadas. Só no baseline.
  final int? runs;

  /// JSON indentado, casos em ordem de id, com `\n` final.
  String encode({bool includeSamples = true}) {
    final ids = cases.keys.toList()..sort();
    final json = <String, Object?>{
      'schema': perfSchemaVersion,
      'flutter': flutter,
      'dart': dart,
      'os': os,
      'createdAt': createdAt.toUtc().toIso8601String(),
      if (sourceCommit != null) 'sourceCommit': sourceCommit,
      if (runner != null) 'runner': runner,
      if (runs != null) 'runs': runs,
      'cases': {
        for (final id in ids)
          id: {
            'ratio': cases[id]!.ratio,
            'medianUs': cases[id]!.medianUs,
            'calibrationUs': cases[id]!.calibrationUs,
            if (includeSamples) 'samples': cases[id]!.samples,
          },
      },
    };
    return '${const JsonEncoder.withIndent('  ').convert(json)}\n';
  }
}

/// Leitura validada, com mensagens que nomeiam o campo.
final class _Reader {
  _Reader(this.source);

  final String source;

  Never _fail(String path, String what) =>
      throw PerfFormatException(source, "campo '$path' $what");

  String _path(String? prefix, String key) =>
      prefix == null ? key : '$prefix.$key';

  Map<String, Object?> object(Object? value, String path) =>
      value is Map<String, Object?> ? value : _fail(path, 'deve ser um objeto');

  String string(Map<String, Object?> m, String key) {
    final v = m[key];
    return v is String ? v : _fail(key, 'deve ser texto');
  }

  String? optionalString(Map<String, Object?> m, String key) {
    final v = m[key];
    if (v == null) return null;
    return v is String ? v : _fail(key, 'deve ser texto');
  }

  int integer(Map<String, Object?> m, String key) {
    final v = m[key];
    return v is int ? v : _fail(key, 'deve ser inteiro');
  }

  int? optionalInteger(Map<String, Object?> m, String key) {
    final v = m[key];
    if (v == null) return null;
    return v is int ? v : _fail(key, 'deve ser inteiro');
  }

  double number(Map<String, Object?> m, String key, String prefix) {
    final v = m[key];
    return v is num ? v.toDouble() : _fail(_path(prefix, key), 'deve ser número');
  }

  List<double> numberList(Map<String, Object?> m, String key, String prefix) {
    final v = m[key];
    if (v == null) return const [];
    if (v is! List<Object?>) _fail(_path(prefix, key), 'deve ser lista');
    return [
      for (final (i, e) in v.indexed)
        e is num ? e.toDouble() : _fail('${_path(prefix, key)}[$i]', 'deve ser número'),
    ];
  }

  DateTime date(Map<String, Object?> m, String key) {
    final s = string(m, key);
    return DateTime.tryParse(s) ?? _fail(key, 'deve ser data ISO 8601, veio "$s"');
  }
}
```

- [ ] **Passo 5: Rodar e ver passar**

Run: `flutter test test/tool/perf_report_test.dart`
Expected: `All tests passed!` (12 testes).

- [ ] **Passo 6: Format e analyze**

Run: `dart format tool/perf test/tool && flutter analyze`
Expected: `No issues found!`

- [ ] **Passo 7: Commit**

```bash
git add tool/perf/lib/stats.dart tool/perf/lib/perf_report.dart test/tool/perf_report_test.dart
git commit -m "feat(perf): modelo do result.json e do baseline, com validação"
```

---

### Tarefa 3: Comparador e CLI `compare`

**Arquivos:**
- Criar: `tool/perf/lib/compare.dart`
- Criar: `tool/perf/compare.dart`
- Teste: `test/tool/perf_compare_test.dart`

**Interfaces:**
- Consome: `PerfReport`, `PerfCaseResult`, `PerfFormatException` (Tarefa 2).
- Produz: `const double regressionThreshold = 1.20; const double improvementThreshold = 0.80;`
- Produz: `enum CaseStatus { ok, regression, improvement, newCase, missing }`.
- Produz: `final class CaseComparison { String id; CaseStatus status; double? baselineRatio; double? currentRatio; double? get change; }`.
- Produz: `final class PerfComparison { List<CaseComparison> cases; String currentFlutter; String? baselineFlutter; bool get hasBaseline; bool get flutterMismatch; bool get failed; String toMarkdown(); }`.
- Produz: `PerfComparison comparePerf({required PerfReport current, PerfReport? baseline})`.
- Produz (CLI): `dart run tool/perf/compare.dart [--result R] [--baseline B]`, padrões `build/perf/result.json` e `test/perf/baseline.json`; código de saída 1 em falha; acrescenta a tabela a `$GITHUB_STEP_SUMMARY` quando definido.

- [ ] **Passo 1: Escrever o teste que falha**

Criar `test/tool/perf_compare_test.dart`:

```dart
// Regras do gate de desempenho (spec §3.2) e CLI do comparador.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/perf/lib/compare.dart';
import '../../tool/perf/lib/perf_report.dart';

PerfReport _report(Map<String, double> ratios, {String flutter = '3.47.0'}) =>
    PerfReport(
      flutter: flutter,
      dart: '3.13.0',
      os: 'linux',
      createdAt: DateTime.utc(2026, 9, 25),
      cases: {
        for (final MapEntry(:key, :value) in ratios.entries)
          key: PerfCaseResult(ratio: value, medianUs: 1, calibrationUs: 1),
      },
    );

CaseStatus _status(double base, double current) => comparePerf(
  current: _report({'c': current}),
  baseline: _report({'c': base}),
).cases.single.status;

void main() {
  group('comparePerf', () {
    test('igual passa', () {
      expect(_status(2, 2), CaseStatus.ok);
    });

    test('acima de 1,20× é regressão e falha', () {
      final cmp = comparePerf(
        current: _report({'c': 1.25}),
        baseline: _report({'c': 1}),
      );
      expect(cmp.cases.single.status, CaseStatus.regression);
      expect(cmp.failed, isTrue);
    });

    test('exatamente 1,20× passa (limite estrito)', () {
      expect(_status(1, 1.2), CaseStatus.ok);
    });

    test('abaixo de 0,80× é melhora e não falha', () {
      final cmp = comparePerf(
        current: _report({'c': 0.75}),
        baseline: _report({'c': 1}),
      );
      expect(cmp.cases.single.status, CaseStatus.improvement);
      expect(cmp.failed, isFalse);
    });

    test('caso novo avisa e não falha', () {
      final cmp = comparePerf(
        current: _report({'a': 1, 'novo': 1}),
        baseline: _report({'a': 1}),
      );
      expect(
        cmp.cases.firstWhere((c) => c.id == 'novo').status,
        CaseStatus.newCase,
      );
      expect(cmp.failed, isFalse);
    });

    test('caso ausente do resultado falha', () {
      final cmp = comparePerf(
        current: _report({'a': 1}),
        baseline: _report({'a': 1, 'sumiu': 1}),
      );
      expect(
        cmp.cases.firstWhere((c) => c.id == 'sumiu').status,
        CaseStatus.missing,
      );
      expect(cmp.failed, isTrue);
    });

    test('sem baseline tudo é novo e nada falha', () {
      final cmp = comparePerf(current: _report({'a': 1, 'b': 2}));
      expect(cmp.hasBaseline, isFalse);
      expect(cmp.cases.map((c) => c.status), everyElement(CaseStatus.newCase));
      expect(cmp.failed, isFalse);
      expect(cmp.toMarkdown(), contains('Sem baseline'));
    });

    test('Flutter diferente avisa em destaque', () {
      final cmp = comparePerf(
        current: _report({'a': 1}, flutter: '3.47.5'),
        baseline: _report({'a': 1}),
      );
      expect(cmp.flutterMismatch, isTrue);
      expect(cmp.failed, isFalse);
      final md = cmp.toMarkdown();
      expect(md, contains('Flutter diferente'));
      expect(md, contains('3.47.5'));
      expect(md, contains('3.47.0'));
    });

    test('tabela mostra variação com vírgula e casos em ordem', () {
      final md = comparePerf(
        current: _report({'b': 1.25, 'a': 1}),
        baseline: _report({'b': 1, 'a': 1}),
      ).toMarkdown();
      expect(md, contains('+25,0%'));
      expect(md.indexOf('`a`'), lessThan(md.indexOf('`b`')));
      expect(md, contains('Resultado: falhou'));
    });
  });

  group('CLI', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('perf_compare_'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<ProcessResult> run(List<String> args, {String? summary}) =>
        Process.run(
          'dart',
          ['run', 'tool/perf/compare.dart', ...args],
          environment: {'GITHUB_STEP_SUMMARY': ?summary},
        );

    String write(String name, PerfReport report) {
      final f = File('${dir.path}/$name')..writeAsStringSync(report.encode());
      return f.path;
    }

    test('resultado inexistente sai com 1 e nomeia o arquivo', () async {
      final missing = '${dir.path}/nao-existe.json';
      final r = await run(['--result', missing, '--baseline', missing]);
      expect(r.exitCode, 1);
      expect(r.stderr as String, contains('nao-existe.json'));
      expect(r.stderr as String, isNot(contains('#0')));
    });

    test('regressão sai com 1 e escreve o resumo do job', () async {
      final summary = '${dir.path}/summary.md';
      final r = await run([
        '--result',
        write('r.json', _report({'c': 2})),
        '--baseline',
        write('b.json', _report({'c': 1})),
      ], summary: summary);
      expect(r.exitCode, 1);
      expect(File(summary).readAsStringSync(), contains('regressão'));
    });

    test('sem regressão sai com 0', () async {
      final r = await run([
        '--result',
        write('r.json', _report({'c': 1.1})),
        '--baseline',
        write('b.json', _report({'c': 1})),
      ]);
      expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    });
  });
}
```

Observação: `'GITHUB_STEP_SUMMARY': ?summary` é o elemento de mapa null-aware
(Dart 3.8+); com `summary` nulo a chave não entra. O processo filho herda o
ambiente do pai (`includeParentEnvironment` é `true` por padrão); se o pai
tiver `GITHUB_STEP_SUMMARY` (no CI tem), os testes sem `summary` escrevem no
resumo real do job, o que é inofensivo.

- [ ] **Passo 2: Rodar e ver falhar**

Run: `flutter test test/tool/perf_compare_test.dart`
Expected: FAIL de compilação (`compare.dart` não existe).

- [ ] **Passo 3: Implementar `tool/perf/lib/compare.dart`**

```dart
/// Regras do gate de desempenho (doc/specs/2026-09-25-harness-ci-design.md
/// §3.2): compara a razão de cada caso com a do baseline.
library;

import 'perf_report.dart';

/// Acima disto, regressão: o build falha. O limite é estrito.
const double regressionThreshold = 1.20;

/// Abaixo disto, melhora: aviso para atualizar o baseline.
const double improvementThreshold = 0.80;

enum CaseStatus { ok, regression, improvement, newCase, missing }

final class CaseComparison {
  const CaseComparison({
    required this.id,
    required this.status,
    this.baselineRatio,
    this.currentRatio,
  });

  final String id;
  final CaseStatus status;
  final double? baselineRatio;
  final double? currentRatio;

  /// `currentRatio / baselineRatio`, quando os dois existem.
  double? get change => switch ((baselineRatio, currentRatio)) {
    (final b?, final c?) => c / b,
    _ => null,
  };
}

final class PerfComparison {
  const PerfComparison({
    required this.cases,
    required this.currentFlutter,
    this.baselineFlutter,
  });

  final List<CaseComparison> cases;
  final String currentFlutter;

  /// `null` quando não há baseline.
  final String? baselineFlutter;

  bool get hasBaseline => baselineFlutter != null;

  bool get flutterMismatch => hasBaseline && baselineFlutter != currentFlutter;

  bool get failed => cases.any(
    (c) => c.status == CaseStatus.regression || c.status == CaseStatus.missing,
  );

  String toMarkdown() {
    final out = StringBuffer('## Desempenho\n\n');
    if (!hasBaseline) {
      out.writeln(
        '> **Sem baseline** (`test/perf/baseline.json`): todos os casos são '
        'novos e nada falha. Gere o baseline pelo workflow `perf-baseline`.\n',
      );
    } else if (flutterMismatch) {
      out.writeln(
        '> **AVISO: Flutter diferente.** Resultado em $currentFlutter, '
        'baseline em $baselineFlutter. A comparação vale pouco até o baseline '
        'ser regenerado nesta versão.\n',
      );
    }
    out
      ..writeln('| Caso | Baseline | Atual | Variação | Estado |')
      ..writeln('|---|---:|---:|---:|---|');
    for (final c in cases) {
      out.writeln(
        '| `${c.id}` | ${_ratio(c.baselineRatio)} | ${_ratio(c.currentRatio)} '
        '| ${_change(c.change)} | ${_label(c.status)} |',
      );
    }
    out
      ..writeln()
      ..writeln(
        failed
            ? '**Resultado: falhou** (regressão acima de '
                  '${_percent(regressionThreshold)} ou caso ausente).'
            : '**Resultado: passou.**',
      );
    return out.toString();
  }
}

PerfComparison comparePerf({required PerfReport current, PerfReport? baseline}) {
  final ids = {...current.cases.keys, ...?baseline?.cases.keys}.toList()..sort();
  return PerfComparison(
    currentFlutter: current.flutter,
    baselineFlutter: baseline?.flutter,
    cases: [
      for (final id in ids)
        _compareCase(id, baseline?.cases[id]?.ratio, current.cases[id]?.ratio),
    ],
  );
}

CaseComparison _compareCase(String id, double? base, double? current) {
  final status = switch ((base, current)) {
    (null, _) => CaseStatus.newCase,
    (_, null) => CaseStatus.missing,
    (final b?, final c?) when c / b > regressionThreshold => CaseStatus.regression,
    (final b?, final c?) when c / b < improvementThreshold =>
      CaseStatus.improvement,
    _ => CaseStatus.ok,
  };
  return CaseComparison(
    id: id,
    status: status,
    baselineRatio: base,
    currentRatio: current,
  );
}

String _ratio(double? v) => v == null ? '—' : v.toStringAsFixed(3);

String _change(double? v) {
  if (v == null) return '—';
  final pct = (v - 1) * 100;
  final sign = pct >= 0 ? '+' : '';
  return '$sign${pct.toStringAsFixed(1).replaceAll('.', ',')}%';
}

String _percent(double threshold) => '${((threshold - 1) * 100).round()}%';

String _label(CaseStatus s) => switch (s) {
  CaseStatus.ok => 'ok',
  CaseStatus.regression => '**regressão**',
  CaseStatus.improvement => 'melhora (atualizar o baseline?)',
  CaseStatus.newCase => 'novo, sem baseline',
  CaseStatus.missing => '**ausente do resultado**',
};
```

- [ ] **Passo 4: Implementar a CLI `tool/perf/compare.dart`**

```dart
// Compara build/perf/result.json com test/perf/baseline.json.
//
//   dart run tool/perf/compare.dart [--result R] [--baseline B]
//
// Sai com 1 em regressão, caso ausente ou arquivo ilegível. Com
// GITHUB_STEP_SUMMARY definido, acrescenta a tabela ao resumo do job.
import 'dart:io';

import 'lib/compare.dart';
import 'lib/perf_report.dart';

const _usage =
    'uso: dart run tool/perf/compare.dart [--result R] [--baseline B]';

void main(List<String> args) {
  var resultPath = 'build/perf/result.json';
  var baselinePath = 'test/perf/baseline.json';
  for (var i = 0; i < args.length; i++) {
    final hasValue = i + 1 < args.length;
    switch (args[i]) {
      case '--result' when hasValue:
        resultPath = args[++i];
      case '--baseline' when hasValue:
        baselinePath = args[++i];
      default:
        stderr.writeln(_usage);
        exitCode = 64;
        return;
    }
  }

  try {
    final current = PerfReport.parse(
      File(resultPath).readAsStringSync(),
      source: resultPath,
    );
    final baselineFile = File(baselinePath);
    final baseline = baselineFile.existsSync()
        ? PerfReport.parse(baselineFile.readAsStringSync(), source: baselinePath)
        : null;
    final comparison = comparePerf(current: current, baseline: baseline);
    final markdown = comparison.toMarkdown();
    stdout.write(markdown);
    final summary = Platform.environment['GITHUB_STEP_SUMMARY'];
    if (summary != null && summary.isNotEmpty) {
      File(summary).writeAsStringSync('$markdown\n', mode: FileMode.append);
    }
    exitCode = comparison.failed ? 1 : 0;
  } on PerfFormatException catch (e) {
    stderr.writeln(e);
    exitCode = 1;
  } on FileSystemException catch (e) {
    stderr.writeln('Não consegui ler ${e.path}: ${e.message}');
    exitCode = 1;
  }
}
```

- [ ] **Passo 5: Rodar e ver passar**

Run: `flutter test test/tool/perf_compare_test.dart`
Expected: `All tests passed!` (12 testes). Os três da CLI levam alguns segundos
cada (`dart run`).

- [ ] **Passo 6: Format e analyze**

Run: `dart format tool/perf test/tool && flutter analyze`
Expected: `No issues found!`

- [ ] **Passo 7: Commit**

```bash
git add tool/perf/lib/compare.dart tool/perf/compare.dart test/tool/perf_compare_test.dart
git commit -m "feat(perf): comparador com gate de 20% sobre a razão normalizada"
```

---

### Tarefa 4: Combinação do baseline e CLI `update_baseline`

**Arquivos:**
- Criar: `tool/perf/lib/baseline.dart`
- Criar: `tool/perf/update_baseline.dart`
- Teste: `test/tool/perf_baseline_test.dart`

**Interfaces:**
- Consome: `PerfReport`, `PerfCaseResult`, `PerfFormatException` (Tarefa 2); `median` (Tarefa 2).
- Produz: `PerfReport combineBaseline(List<PerfReport> runs, {String? sourceCommit, String? runner, DateTime? createdAt})` — lança `ArgumentError` se `runs` vazio, com Flutter diferente ou com conjuntos de casos diferentes.
- Produz (CLI): `dart run tool/perf/update_baseline.dart [--out F] [--commit SHA] [--runner NOME] r1.json [r2.json ...]`, padrão `--out test/perf/baseline.json`.

- [ ] **Passo 1: Escrever o teste que falha**

Criar `test/tool/perf_baseline_test.dart`:

```dart
// Combinação de execuções do harness num baseline (spec §3.3).
import 'package:flutter_test/flutter_test.dart';

import '../../tool/perf/lib/baseline.dart';
import '../../tool/perf/lib/perf_report.dart';

PerfReport _run(Map<String, double> ratios, {String flutter = '3.47.0'}) =>
    PerfReport(
      flutter: flutter,
      dart: '3.13.0',
      os: 'linux',
      createdAt: DateTime.utc(2026, 9, 25),
      cases: {
        for (final MapEntry(:key, :value) in ratios.entries)
          key: PerfCaseResult(
            ratio: value,
            medianUs: value * 100,
            calibrationUs: 100,
            samples: [value],
          ),
      },
    );

void main() {
  test('mediana por caso, sem amostras, com metadados', () {
    final base = combineBaseline(
      [
        _run({'a': 1, 'b': 10}),
        _run({'a': 3, 'b': 30}),
        _run({'a': 2, 'b': 20}),
      ],
      sourceCommit: 'abc123',
      runner: 'ubuntu-24.04',
      createdAt: DateTime.utc(2026, 9, 26),
    );
    expect(base.cases['a']!.ratio, 2);
    expect(base.cases['b']!.ratio, 20);
    expect(base.cases['b']!.medianUs, 2000);
    expect(base.cases['a']!.samples, isEmpty);
    expect(base.runs, 3);
    expect(base.sourceCommit, 'abc123');
    expect(base.runner, 'ubuntu-24.04');
    expect(base.createdAt, DateTime.utc(2026, 9, 26));
    expect(base.flutter, '3.47.0');
  });

  test('uma execução só vira baseline dela mesma', () {
    expect(combineBaseline([_run({'a': 1.5})]).cases['a']!.ratio, 1.5);
  });

  test('nenhuma execução lança', () {
    expect(() => combineBaseline(const []), throwsArgumentError);
  });

  test('Flutter diferente entre execuções lança', () {
    expect(
      () => combineBaseline([
        _run({'a': 1}),
        _run({'a': 1}, flutter: '3.47.5'),
      ]),
      throwsA(
        isA<ArgumentError>().having(
          (e) => '${e.message}',
          'message',
          contains('3.47.5'),
        ),
      ),
    );
  });

  test('casos diferentes entre execuções lança e nomeia o caso', () {
    expect(
      () => combineBaseline([
        _run({'a': 1}),
        _run({'a': 1, 'extra': 1}),
      ]),
      throwsA(
        isA<ArgumentError>().having(
          (e) => '${e.message}',
          'message',
          contains('extra'),
        ),
      ),
    );
  });
}
```

- [ ] **Passo 2: Rodar e ver falhar**

Run: `flutter test test/tool/perf_baseline_test.dart`
Expected: FAIL de compilação (`baseline.dart` não existe).

- [ ] **Passo 3: Implementar `tool/perf/lib/baseline.dart`**

```dart
/// Combina execuções do harness num baseline
/// (doc/specs/2026-09-25-harness-ci-design.md §3.3).
library;

import 'perf_report.dart';
import 'stats.dart';

/// Mediana, caso a caso, de [runs]. Execuções de Flutter diferente ou com
/// conjuntos de casos diferentes não se combinam.
PerfReport combineBaseline(
  List<PerfReport> runs, {
  String? sourceCommit,
  String? runner,
  DateTime? createdAt,
}) {
  if (runs.isEmpty) {
    throw ArgumentError.value(runs, 'runs', 'nenhuma execução para combinar');
  }
  final first = runs.first;
  final ids = first.cases.keys.toSet();
  for (final r in runs.skip(1)) {
    if (r.flutter != first.flutter) {
      throw ArgumentError(
        'execuções com Flutter diferente: ${first.flutter} e ${r.flutter}',
      );
    }
    final other = r.cases.keys.toSet();
    final diff = ids.difference(other).union(other.difference(ids));
    if (diff.isNotEmpty) {
      throw ArgumentError(
        'execuções com casos diferentes: ${(diff.toList()..sort()).join(', ')}',
      );
    }
  }
  double med(String id, double Function(PerfCaseResult) field) =>
      median(runs.map((r) => field(r.cases[id]!)));
  return PerfReport(
    flutter: first.flutter,
    dart: first.dart,
    os: first.os,
    createdAt: (createdAt ?? DateTime.now()).toUtc(),
    sourceCommit: sourceCommit,
    runner: runner,
    runs: runs.length,
    cases: {
      for (final id in ids)
        id: PerfCaseResult(
          ratio: med(id, (c) => c.ratio),
          medianUs: med(id, (c) => c.medianUs),
          calibrationUs: med(id, (c) => c.calibrationUs),
        ),
    },
  );
}
```

- [ ] **Passo 4: Implementar a CLI `tool/perf/update_baseline.dart`**

```dart
// Combina um ou mais result.json num baseline candidato.
//
//   dart run tool/perf/update_baseline.dart [--out F] [--commit SHA]
//       [--runner NOME] result1.json [result2.json ...]
//
// Atualizar test/perf/baseline.json é commit deliberado (doc/10 §4.2); o CI
// gera o candidato pelo workflow perf-baseline.
import 'dart:io';

import 'lib/baseline.dart';
import 'lib/perf_report.dart';

const _usage =
    'uso: dart run tool/perf/update_baseline.dart [--out F] [--commit SHA] '
    '[--runner NOME] result1.json [result2.json ...]';

void main(List<String> args) {
  var out = 'test/perf/baseline.json';
  String? commit;
  String? runner;
  final inputs = <String>[];
  for (var i = 0; i < args.length; i++) {
    final hasValue = i + 1 < args.length;
    switch (args[i]) {
      case '--out' when hasValue:
        out = args[++i];
      case '--commit' when hasValue:
        commit = args[++i];
      case '--runner' when hasValue:
        runner = args[++i];
      case final a when a.startsWith('--'):
        stderr.writeln(_usage);
        exitCode = 64;
        return;
      case final path:
        inputs.add(path);
    }
  }
  if (inputs.isEmpty) {
    stderr.writeln(_usage);
    exitCode = 64;
    return;
  }

  try {
    final runs = [
      for (final p in inputs)
        PerfReport.parse(File(p).readAsStringSync(), source: p),
    ];
    final baseline = combineBaseline(
      runs,
      sourceCommit: commit,
      runner: runner,
    );
    File(out)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(baseline.encode(includeSamples: false));
    stdout.writeln(
      'baseline com ${baseline.cases.length} casos de ${runs.length} '
      'execuções escrito em $out',
    );
  } on PerfFormatException catch (e) {
    stderr.writeln(e);
    exitCode = 1;
  } on ArgumentError catch (e) {
    stderr.writeln(e.message);
    exitCode = 1;
  } on FileSystemException catch (e) {
    stderr.writeln('Não consegui ler ${e.path}: ${e.message}');
    exitCode = 1;
  }
}
```

- [ ] **Passo 5: Rodar e ver passar**

Run: `flutter test test/tool/perf_baseline_test.dart`
Expected: `All tests passed!` (5 testes).

- [ ] **Passo 6: Conferir a CLI à mão**

Run: `dart run tool/perf/update_baseline.dart; echo "saída $?"`
Expected: a linha de uso e `saída 64`.

- [ ] **Passo 7: Format e analyze**

Run: `dart format tool/perf test/tool && flutter analyze`
Expected: `No issues found!`

- [ ] **Passo 8: Commit**

```bash
git add tool/perf/lib/baseline.dart tool/perf/update_baseline.dart test/tool/perf_baseline_test.dart
git commit -m "feat(perf): combinação de execuções em baseline candidato"
```

---

### Tarefa 5: Harness

**Arquivos:**
- Criar: `test/perf/support/perf_harness.dart`
- Criar: `dart_test.yaml`
- Teste: `test/perf/perf_harness_test.dart`

**Interfaces:**
- Consome: `PerfReport`, `PerfCaseResult` (Tarefa 2); `median` (Tarefa 2).
- Produz: `const int warmupSamples = 3; const int measuredSamples = 15; const String defaultResultPath = 'build/perf/result.json';`
- Produz: `final class PerfCase { PerfCase({required String id, void Function()? run, Future<void> Function()? runAsync, Future<void> Function()? setUp, int innerIterations = 1}); }` — lança `ArgumentError` se `run` e `runAsync` forem ambos nulos ou ambos presentes.
- Produz: `void calibrationWorkload()` e `int get calibrationSink`.
- Produz: `Future<PerfCaseResult> measureCase(PerfCase c, {int warmup = warmupSamples, int samples = measuredSamples, void Function() calibration = calibrationWorkload})`.
- Produz: `Future<String> detectFlutterVersion({Map<String, String>? environment, Future<ProcessResult> Function(String, List<String>)? runProcess})`.
- Produz: `Future<bool> writeResultIfAny(Map<String, PerfCaseResult> cases, {String path = defaultResultPath, Map<String, String>? environment})` — não escreve nada e devolve `false` com mapa vazio.

- [ ] **Passo 1: Escrever o teste que falha**

Criar `test/perf/perf_harness_test.dart` (sem tag: roda na suíte normal):

```dart
// Mecânica do harness de desempenho (spec §2): amostragem, normalização,
// versão do Flutter e escrita do resultado.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/perf/lib/perf_report.dart';
import 'support/perf_harness.dart';

void _busyWait(int micros) {
  final sw = Stopwatch()..start();
  while (sw.elapsedMicroseconds < micros) {}
}

void main() {
  group('PerfCase', () {
    test('exige exatamente um corpo', () {
      expect(() => PerfCase(id: 'x'), throwsArgumentError);
      expect(
        () => PerfCase(id: 'x', run: () {}, runAsync: () async {}),
        throwsArgumentError,
      );
      expect(PerfCase(id: 'x', run: () {}).id, 'x');
    });
  });

  group('measureCase', () {
    test('intercala calibração e caso, descarta o aquecimento', () async {
      var setUps = 0;
      var calibrations = 0;
      var bodies = 0;
      final result = await measureCase(
        PerfCase(
          id: 'conta',
          setUp: () async => setUps++,
          run: () => bodies++,
          innerIterations: 2,
        ),
        warmup: 3,
        samples: 5,
        calibration: () => calibrations++,
      );
      expect(setUps, 1);
      expect(calibrations, 8);
      expect(bodies, 16);
      expect(result.samples, hasLength(5));
    });

    test('corpo quase vazio ainda dá razão positiva', () async {
      final result = await measureCase(
        PerfCase(id: 'vazio', run: () {}),
        warmup: 1,
        samples: 5,
      );
      expect(result.ratio, greaterThan(0));
    });

    test('razão acompanha o custo relativo', () async {
      final result = await measureCase(
        PerfCase(id: 'dobro', run: () => _busyWait(2000)),
        warmup: 1,
        samples: 7,
        calibration: () => _busyWait(1000),
      );
      expect(result.ratio, inInclusiveRange(1.5, 2.5));
      expect(result.medianUs, inInclusiveRange(1800, 4000));
    });

    test('corpo assíncrono é aguardado', () async {
      final result = await measureCase(
        PerfCase(
          id: 'async',
          runAsync: () => Future<void>.delayed(const Duration(milliseconds: 2)),
        ),
        warmup: 0,
        samples: 3,
        calibration: () {},
      );
      expect(result.medianUs, greaterThanOrEqualTo(2000));
    });
  });

  test('calibração faz trabalho observável', () {
    final before = calibrationSink;
    calibrationWorkload();
    expect(calibrationSink, isNot(before));
  });

  group('detectFlutterVersion', () {
    test('FLUTTER_VERSION tem precedência', () async {
      final v = await detectFlutterVersion(
        environment: {'FLUTTER_VERSION': '3.47.0'},
        runProcess: (_, _) => throw StateError('não deveria rodar'),
      );
      expect(v, '3.47.0');
    });

    test('lê frameworkVersion mesmo com banner antes do JSON', () async {
      final v = await detectFlutterVersion(
        environment: const {},
        runProcess: (_, _) async => ProcessResult(
          0,
          0,
          'Downloading Dart SDK...\n{"frameworkVersion": "3.47.5"}\n',
          '',
        ),
      );
      expect(v, '3.47.5');
    });

    test('processo que falha vira unknown', () async {
      expect(
        await detectFlutterVersion(
          environment: const {},
          runProcess: (_, _) => throw const ProcessException('flutter', []),
        ),
        'unknown',
      );
      expect(
        await detectFlutterVersion(
          environment: const {},
          runProcess: (_, _) async => ProcessResult(0, 1, '', 'erro'),
        ),
        'unknown',
      );
    });
  });

  group('writeResultIfAny', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('perf_harness_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('mapa vazio não cria arquivo', () async {
      final path = '${dir.path}/perf/result.json';
      expect(await writeResultIfAny(const {}, path: path), isFalse);
      expect(File(path).existsSync(), isFalse);
    });

    test('escreve um result.json legível', () async {
      final path = '${dir.path}/perf/result.json';
      final wrote = await writeResultIfAny(
        const {
          'c': PerfCaseResult(
            ratio: 2,
            medianUs: 200,
            calibrationUs: 100,
            samples: [2],
          ),
        },
        path: path,
        environment: {'FLUTTER_VERSION': '3.47.0'},
      );
      expect(wrote, isTrue);
      final back = PerfReport.parse(File(path).readAsStringSync(), source: path);
      expect(back.flutter, '3.47.0');
      expect(back.os, Platform.operatingSystem);
      expect(back.cases['c']!.samples, [2]);
    });
  });
}
```

- [ ] **Passo 2: Rodar e ver falhar**

Run: `flutter test test/perf/perf_harness_test.dart`
Expected: FAIL de compilação (`perf_harness.dart` não existe).

- [ ] **Passo 3: Implementar `test/perf/support/perf_harness.dart`**

```dart
/// Harness de desempenho da Fase 0 (doc/specs/2026-09-25-harness-ci-design.md
/// §2). Mede cada caso intercalado com uma calibração fixa e registra a
/// mediana das razões, que é o que o gate compara.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../tool/perf/lib/perf_report.dart';
import '../../../tool/perf/lib/stats.dart';

const int warmupSamples = 3;
const int measuredSamples = 15;
const String defaultResultPath = 'build/perf/result.json';

/// Um caso medido. Exatamente um de [run] e [runAsync].
final class PerfCase {
  PerfCase({
    required this.id,
    this.run,
    this.runAsync,
    this.setUp,
    this.innerIterations = 1,
  }) {
    if ((run == null) == (runAsync == null)) {
      throw ArgumentError('PerfCase "$id": informe exatamente um de run e runAsync');
    }
  }

  /// Chave estável do baseline.
  final String id;
  final void Function()? run;
  final Future<void> Function()? runAsync;

  /// Preparação fora do tempo, uma vez antes das amostras.
  final Future<void> Function()? setUp;

  /// Repetições do corpo por amostra.
  final int innerIterations;
}

/// Repetições da carga de calibração; ajustado para ~5 ms no desktop de
/// desenvolvimento (spec §2.3).
const int _calibrationRounds = 4;

final Uint8List _calibrationBuffer = Uint8List.fromList(
  List<int>.generate(64 * 1024, (i) => (i * 31) & 0xff),
);

int _sink = 0;

/// Acumulador da calibração, para o trabalho não ser eliminado.
int get calibrationSink => _sink;

/// Carga fixa em Dart puro: FNV-1a 32 sobre 64 KB, `StringBuffer`, `Map` e
/// `sort`, repetidos [_calibrationRounds] vezes.
void calibrationWorkload() {
  var h = 0x811c9dc5;
  for (var round = 0; round < _calibrationRounds; round++) {
    for (final b in _calibrationBuffer) {
      h = ((h ^ b) * 0x01000193) & 0xffffffff;
    }
    final sb = StringBuffer();
    for (var i = 0; i < 2000; i++) {
      sb
        ..write('w')
        ..write(i)
        ..write(' ');
    }
    h ^= sb.length;
    final m = <String, int>{};
    for (var i = 0; i < 2000; i++) {
      m['k$i'] = i;
    }
    for (var i = 0; i < 2000; i++) {
      h ^= m['k${(i * 7) % 2000}']!;
    }
    final list = List<int>.generate(5000, (i) => (i * 2654435761 + round) & 0xffff)
      ..sort();
    h ^= list[2500];
  }
  _sink ^= h | 1;
}

double _micros(Stopwatch sw) => sw.elapsedTicks * 1e6 / sw.frequency;

/// Mede [c]: [warmup] amostras descartadas e [samples] medidas, cada uma
/// com a calibração e em seguida o caso.
Future<PerfCaseResult> measureCase(
  PerfCase c, {
  int warmup = warmupSamples,
  int samples = measuredSamples,
  void Function() calibration = calibrationWorkload,
}) async {
  await c.setUp?.call();
  final ratios = <double>[];
  final caseUs = <double>[];
  final calibrationUs = <double>[];
  final sw = Stopwatch();
  for (var i = 0; i < warmup + samples; i++) {
    sw
      ..reset()
      ..start();
    calibration();
    sw.stop();
    final cal = _micros(sw);

    sw
      ..reset()
      ..start();
    for (var k = 0; k < c.innerIterations; k++) {
      final run = c.run;
      if (run != null) {
        run();
      } else {
        await c.runAsync!();
      }
    }
    sw.stop();
    final t = _micros(sw);

    if (i < warmup) continue;
    // Piso de 1 tick nos dois lados: a razão nunca é 0 nem infinita.
    final tick = 1e6 / sw.frequency;
    ratios.add((t < tick ? tick : t) / (cal < tick ? tick : cal));
    caseUs.add(t);
    calibrationUs.add(cal);
  }
  return PerfCaseResult(
    ratio: median(ratios),
    medianUs: median(caseUs),
    calibrationUs: median(calibrationUs),
    samples: ratios,
  );
}

/// `FLUTTER_VERSION` quando definida; senão `frameworkVersion` de
/// `flutter --version --machine`; senão `"unknown"`.
Future<String> detectFlutterVersion({
  Map<String, String>? environment,
  Future<ProcessResult> Function(String, List<String>)? runProcess,
}) async {
  final fromEnv = (environment ?? Platform.environment)['FLUTTER_VERSION'];
  if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
  try {
    final r = await (runProcess ?? Process.run)('flutter', [
      '--version',
      '--machine',
    ]);
    if (r.exitCode != 0) return 'unknown';
    final out = r.stdout as String;
    final start = out.indexOf('{');
    if (start < 0) return 'unknown';
    final json = jsonDecode(out.substring(start));
    if (json is Map<String, Object?> && json['frameworkVersion'] is String) {
      return json['frameworkVersion']! as String;
    }
  } on Object {
    // Sem flutter no PATH ou saída inesperada: versão desconhecida.
  }
  return 'unknown';
}

/// Escreve o `result.json` se houver ao menos um caso medido. A suíte normal
/// pula os casos `perf`, e um relatório vazio não pode sobrescrever o último.
Future<bool> writeResultIfAny(
  Map<String, PerfCaseResult> cases, {
  String path = defaultResultPath,
  Map<String, String>? environment,
}) async {
  if (cases.isEmpty) return false;
  final report = PerfReport(
    flutter: await detectFlutterVersion(environment: environment),
    dart: Platform.version.split(' ').first,
    os: Platform.operatingSystem,
    createdAt: DateTime.now().toUtc(),
    cases: cases,
  );
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(report.encode());
  return true;
}
```

- [ ] **Passo 4: Criar `dart_test.yaml` na raiz**

```yaml
# Casos de desempenho ficam fora da suíte normal. Verificado no Flutter
# 3.47.5: exclude_tags conflita com --tags; skip por tag com --run-skipped
# funciona (doc/specs/2026-09-25-harness-ci-design.md §2.1).
tags:
  perf:
    skip: "harness de desempenho: flutter test --tags perf --run-skipped test/perf"
```

- [ ] **Passo 5: Rodar e ver passar**

Run: `flutter test test/perf/perf_harness_test.dart`
Expected: `All tests passed!` (11 testes).

- [ ] **Passo 6: Format e analyze**

Run: `dart format test/perf && flutter analyze`
Expected: `No issues found!`

- [ ] **Passo 7: Commit**

```bash
git add test/perf/support/perf_harness.dart test/perf/perf_harness_test.dart dart_test.yaml
git commit -m "feat(perf): harness com calibração intercalada e tag perf fora da suíte normal"
```

---

### Tarefa 6: Casos da Fase 0

**Arquivos:**
- Criar: `test/perf/support/perf_inputs.dart`
- Criar: `test/perf/perf_test.dart`
- Possivelmente modificar: `test/perf/support/perf_harness.dart` (só a constante `_calibrationRounds`)

**Interfaces:**
- Consome: `PerfCase`, `measureCase`, `writeResultIfAny` (Tarefa 5); `Prose` de `tool/corpus/lib/text.dart` (`Prose({String lang = 'pt', int seed = 1})`, `String sentence()`, `String paragraph()`); `Uint8List png(int width, int height, {int seed = 0})` de `tool/corpus/lib/png.dart`.
- Produz: `String xhtmlOfLength(int chars, {int seed = 9})`, `List<String> paragraphsOfWords(int count, int words, {int seed = 11})`, `Uint8List proseBytes(int length, {int seed = 13})`, `Uint8List deflateRaw(Uint8List data)`.

- [ ] **Passo 1: Criar as entradas determinísticas**

Criar `test/perf/support/perf_inputs.dart`:

```dart
/// Entradas determinísticas dos casos de desempenho, a partir dos geradores
/// do corpus (tool/corpus).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../tool/corpus/lib/text.dart';

/// Documento XHTML com cerca de [chars] caracteres de `<p>` de prosa.
String xhtmlOfLength(int chars, {int seed = 9}) {
  final prose = Prose(seed: seed);
  final body = StringBuffer();
  while (body.length < chars) {
    body
      ..write('<p>')
      ..write(prose.paragraph())
      ..write('</p>\n');
  }
  return '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<html xmlns="http://www.w3.org/1999/xhtml" lang="pt-BR">'
      '<head><title>perf</title></head><body>\n$body</body></html>\n';
}

/// [count] parágrafos de exatamente [words] palavras cada.
List<String> paragraphsOfWords(int count, int words, {int seed = 11}) {
  final prose = Prose(seed: seed);
  return List.generate(count, (_) {
    final out = <String>[];
    while (out.length < words) {
      out.addAll(prose.sentence().split(' '));
    }
    return out.take(words).join(' ');
  });
}

/// [length] bytes UTF-8 de prosa.
Uint8List proseBytes(int length, {int seed = 13}) {
  final prose = Prose(seed: seed);
  final out = BytesBuilder(copy: false);
  while (out.length < length) {
    out.add(utf8.encode('${prose.paragraph()}\n'));
  }
  return Uint8List.sublistView(out.takeBytes(), 0, length);
}

/// Deflate cru, como numa entrada de ZIP.
Uint8List deflateRaw(Uint8List data) =>
    Uint8List.fromList(ZLibEncoder(raw: true).convert(data));
```

- [ ] **Passo 2: Criar os casos**

Criar `test/perf/perf_test.dart`:

```dart
// Casos de desempenho da Fase 0: só primitivas das quais o motor vai
// depender (spec §2.4). Rodar com:
//
//   flutter test --tags perf --run-skipped test/perf
//
// e comparar com `dart run tool/perf/compare.dart`.
@Tags(['perf'])
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;

import '../../tool/corpus/lib/png.dart';
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
      run: () => _sink ^= html.parse(xhtml).body!.nodes.length,
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
                ..pushStyle(ui.TextStyle(fontFamily: 'FlutterTest', fontSize: 16))
                ..addText(text);
          final p = builder.build()
            ..layout(const ui.ParagraphConstraints(width: 320));
          _sink ^= p.height.toInt();
          p.dispose();
        }
      },
    ),
    PerfCase(
      id: 'zlib.inflate.1mb',
      setUp: () async => deflated = deflateRaw(proseBytes(1024 * 1024)),
      run: () => _sink ^= ZLibDecoder(raw: true).convert(deflated).length,
    ),
    PerfCase(
      id: 'image.decode.target',
      setUp: () async => pngBytes = png(1200, 1600, seed: 5),
      runAsync: () async {
        final codec = await ui.instantiateImageCodec(pngBytes, targetWidth: 300);
        final frame = await codec.getNextFrame();
        _sink ^= frame.image.width;
        frame.image.dispose();
        codec.dispose();
      },
    ),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final results = <String, PerfCaseResult>{};

  for (final c in _phase0Cases()) {
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
      print('[perf] $defaultResultPath escrito (${results.length} casos, sink $_sink)');
    }
  });
}
```

- [ ] **Passo 3: Suíte normal pula os casos e não escreve resultado**

Run: `\rm -rf build/perf && flutter test test/perf && ls build/perf 2>&1`
Expected: `All tests passed!` com `~4` pulados (os 11 do harness passam) e
`ls: não é possível acessar 'build/perf'`.

- [ ] **Passo 4: Rodar o harness**

Run: `flutter test --tags perf --run-skipped test/perf 2>&1 | grep '\[perf\]'`
Expected: 4 linhas de caso e a linha `build/perf/result.json escrito (4 casos, …)`.

- [ ] **Passo 5: Calibrar a carga de calibração**

Nas linhas do Passo 4, a calibração deve ficar entre 3000 e 8000 µs. Se ficar
fora, ajustar `_calibrationRounds` em `test/perf/support/perf_harness.dart`
proporcionalmente (ex.: 1500 µs com 4 rodadas → 12 rodadas) e repetir o
Passo 4.

- [ ] **Passo 6: Medir o ruído local**

```bash
SP=/tmp/claude-1000/-home-eduardo8006-Documentos-projetos-galley/003640ed-5627-4a8b-81ed-13354cf11bdd/scratchpad/perf-ruido
\rm -rf $SP && mkdir -p $SP
for i in 1 2 3 4 5; do
  flutter test --tags perf --run-skipped test/perf >/dev/null && \cp -f build/perf/result.json $SP/r$i.json
done
dart run tool/perf/update_baseline.dart --out $SP/base.json $SP/r1.json $SP/r2.json $SP/r3.json
for i in 4 5; do dart run tool/perf/compare.dart --result $SP/r$i.json --baseline $SP/base.json; done
```

Expected: as duas comparações passam, com todas as variações dentro de ±20%.
Se algum caso passar de ±15%, subir `measuredSamples` para 25 na Tarefa 5
(constante em `perf_harness.dart`), repetir e registrar o motivo na mensagem de
commit. Anote as variações: elas vão para doc/10 na Tarefa 8.

- [ ] **Passo 7: Comparador sem baseline**

Run: `dart run tool/perf/compare.dart; echo "saída $?"`
Expected: tabela com `Sem baseline`, os 4 casos como `novo, sem baseline` e
`saída 0`.

- [ ] **Passo 8: Format, analyze e suíte completa**

Run: `dart format test/perf && flutter analyze && flutter test`
Expected: `No issues found!` e `All tests passed!`.

- [ ] **Passo 9: Commit**

```bash
git add test/perf/support/perf_inputs.dart test/perf/perf_test.dart test/perf/support/perf_harness.dart
git commit -m "feat(perf): casos da Fase 0 (html, shaping, inflate, decodificação)"
```

---

### Tarefa 7: Workflows do GitHub Actions

**Arquivos:**
- Criar: `.github/workflows/ci.yml`
- Criar: `.github/workflows/perf-baseline.yml`
- Teste: `test/tool/ci_config_test.dart`

**Interfaces:**
- Consome: `tool/perf/compare.dart` e `tool/perf/update_baseline.dart` (Tarefas 3 e 4); comando do harness (Tarefa 6).
- Produz: jobs `analyze`, `test` (matriz `min`/`stable`), `engine-linux`, `perf`; workflow manual `perf-baseline` com artefato `perf-baseline`.

- [ ] **Passo 1: Escrever o teste que falha**

Criar `test/tool/ci_config_test.dart`:

```dart
// A versão mínima do Flutter mora em quatro lugares; este teste impede que
// eles divirjam (spec §4 e §5).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _match(String path, RegExp pattern) {
  final m = pattern.firstMatch(File(path).readAsStringSync());
  expect(m, isNotNull, reason: '$path não tem ${pattern.pattern}');
  return m!.group(1)!;
}

void main() {
  test('mínimo do Flutter igual nos pubspecs e nos workflows', () {
    final pubspec = RegExp(r'flutter:\s*">=([0-9.]+)"');
    final workflow = RegExp(r'FLUTTER_MIN:\s*([0-9.]+)');
    final root = _match('pubspec.yaml', pubspec);
    expect(root, '3.47.0');
    expect(_match('example/pubspec.yaml', pubspec), root);
    expect(_match('.github/workflows/ci.yml', workflow), root);
    expect(_match('.github/workflows/perf-baseline.yml', workflow), root);
  });
}
```

- [ ] **Passo 2: Rodar e ver falhar**

Run: `flutter test test/tool/ci_config_test.dart`
Expected: FAIL (`PathNotFoundException` para `.github/workflows/ci.yml`).

- [ ] **Passo 3: Criar `.github/workflows/ci.yml`**

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

env:
  # Mínimo declarado em pubspec.yaml; test/tool/ci_config_test.dart confere.
  FLUTTER_MIN: 3.47.0

jobs:
  analyze:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v7
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: ${{ env.FLUTTER_MIN }}
          cache: true
      - run: flutter pub get
      - name: Formatação
        run: dart format --output=none --set-exit-if-changed lib test tool example/lib example/integration_test
      - run: flutter analyze
      - name: Analyze do exemplo
        run: flutter analyze
        working-directory: example

  test:
    runs-on: ubuntu-24.04
    strategy:
      fail-fast: false
      matrix:
        flutter: [min, stable]
    name: test (${{ matrix.flutter }})
    steps:
      - uses: actions/checkout@v7
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          # Vazio = último release do canal.
          flutter-version: ${{ matrix.flutter == 'min' && env.FLUTTER_MIN || '' }}
          cache: true
      - run: flutter --version
      - run: flutter test

  engine-linux:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v7
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: ${{ env.FLUTTER_MIN }}
          cache: true
      - name: Dependências do desktop Linux
        run: |
          sudo apt-get update
          sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev xvfb
      - name: Testes na engine real (um arquivo por invocação)
        working-directory: example
        run: |
          for f in integration_test/*_test.dart; do
            echo "::group::$f"
            xvfb-run -a flutter test "$f" -d linux
            echo "::endgroup::"
          done

  perf:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v7
      - id: flutter
        uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: ${{ env.FLUTTER_MIN }}
          cache: true
      - name: Harness
        run: flutter test --tags perf --run-skipped test/perf
        env:
          FLUTTER_VERSION: ${{ steps.flutter.outputs.VERSION }}
      - name: Comparar com o baseline
        run: dart run tool/perf/compare.dart
      - uses: actions/upload-artifact@v7
        if: always()
        with:
          name: perf-result
          path: build/perf/result.json
          if-no-files-found: warn
```

- [ ] **Passo 4: Criar `.github/workflows/perf-baseline.yml`**

```yaml
name: Baseline de desempenho

# Gera um baseline candidato no runner do CI. Atualizar
# test/perf/baseline.json é commit deliberado (doc/10 §4.2): baixe o
# artefato perf-baseline e commite com a justificativa.
on:
  workflow_dispatch:

env:
  # Mínimo declarado em pubspec.yaml; test/tool/ci_config_test.dart confere.
  FLUTTER_MIN: 3.47.0

jobs:
  baseline:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v7
      - id: flutter
        uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: ${{ env.FLUTTER_MIN }}
          cache: true
      - name: Harness, três execuções
        env:
          FLUTTER_VERSION: ${{ steps.flutter.outputs.VERSION }}
        run: |
          for i in 1 2 3; do
            flutter test --tags perf --run-skipped test/perf
            cp build/perf/result.json "build/perf/result-$i.json"
          done
      - name: Combinar
        run: >
          dart run tool/perf/update_baseline.dart
          --out build/perf/baseline.json
          --commit "$GITHUB_SHA"
          --runner ubuntu-24.04
          build/perf/result-1.json build/perf/result-2.json build/perf/result-3.json
      - name: Conferir o candidato contra a última execução
        run: dart run tool/perf/compare.dart --result build/perf/result-3.json --baseline build/perf/baseline.json
      - uses: actions/upload-artifact@v7
        with:
          name: perf-baseline
          path: build/perf/baseline.json
          if-no-files-found: error
```

- [ ] **Passo 5: Rodar o teste e ver passar**

Run: `flutter test test/tool/ci_config_test.dart`
Expected: `All tests passed!`

- [ ] **Passo 6: Validar os workflows com actionlint**

```bash
SP=/tmp/claude-1000/-home-eduardo8006-Documentos-projetos-galley/003640ed-5627-4a8b-81ed-13354cf11bdd/scratchpad/actionlint
mkdir -p $SP && gh release download -R rhysd/actionlint -p '*_linux_amd64.tar.gz' -D $SP --clobber
tar -xzf $SP/*_linux_amd64.tar.gz -C $SP actionlint
$SP/actionlint .github/workflows/*.yml && echo OK
```

Expected: `OK`, sem apontamentos. Corrija o que ele apontar e rode de novo.

- [ ] **Passo 7: Commit**

```bash
git add .github/workflows/ci.yml .github/workflows/perf-baseline.yml test/tool/ci_config_test.dart
git commit -m "ci: analyze, testes em 3.47.0 e stable, engine real no Linux e gate de desempenho"
```

---

### Tarefa 8: Documentação

**Arquivos:**
- Modificar: `doc/10-testes.md` (§4.2)
- Modificar: `doc/11-empacotamento-versionamento.md` (§2)
- Modificar: `doc/13-riscos-spikes-fases.md` (estado do §1 e linha da Fase 0 no §2)
- Modificar: `doc/14-pendencias.md`
- Modificar: `spike/README.md`
- Modificar: `doc/specs/2026-09-25-harness-ci-design.md` (linha de estado)

**Interfaces:** nenhuma.

- [ ] **Passo 1: doc/10 §4.2**

Substituir o corpo do §4.2 ("Registrado na Fase 0 e versionado no repositório…
nunca automático.") por:

```markdown
Registrado na Fase 0 e versionado em `test/perf/baseline.json`. Atualizar o
baseline é um commit deliberado, revisado, com justificativa — nunca
automático.

**Como se mede.** O harness (`test/perf/support/perf_harness.dart`) roda no
`flutter_tester`, em JIT, com `flutter test --tags perf --run-skipped
test/perf`; a suíte normal pula os casos. Cada caso tem 3 amostras de
aquecimento e 15 medidas, e cada amostra mede uma **carga de calibração** fixa
em Dart puro e, em seguida, o caso. A métrica é a mediana das razões caso ÷
calibração: comparar razões, e não milissegundos, cancela a maior parte da
diferença entre runners. Por ser JIT no `flutter_tester`, o número detecta
regressão, mas não verifica o orçamento absoluto do §4.1.

**O gate.** `dart run tool/perf/compare.dart` compara `build/perf/result.json`
com o baseline: razão atual ÷ razão do baseline acima de 1,20 falha o build;
abaixo de 0,80 avisa que o baseline pode ser atualizado; caso novo avisa; caso
que sumiu falha; Flutter diferente do baseline avisa em destaque.

**Onde nasce o baseline.** No runner do CI, nunca na máquina de quem
desenvolve: o workflow manual `perf-baseline` roda o harness três vezes,
combina as medianas com `tool/perf/update_baseline.dart` e publica o candidato
como artefato, que é baixado e commitado.

**Ruído medido** (Fase 0, <máquina e data do Passo 6 da Tarefa 6>): variação
máxima de <X>% entre execuções locais, abaixo do limite de 20%.
```

Trocar `<máquina e data…>` e `<X>` pelos valores anotados na Tarefa 6, Passo 6
(ex.: "desktop Linux de desenvolvimento, 2026-09-25" e "6,4"). Não deixar os
marcadores no texto.

- [ ] **Passo 2: doc/11 §2**

Depois do parágrafo que começa com "Todas as seis: Android, iOS, macOS,
Windows, Linux, web.", acrescentar:

```markdown
Versão mínima: **Flutter 3.47.0** (Dart 3.13.0). É a versão que o CI testa,
junto com o `stable` mais recente. Subir o mínimo é commit deliberado: muda
`pubspec.yaml`, `example/pubspec.yaml` e o `FLUTTER_MIN` dos dois workflows,
que `test/tool/ci_config_test.dart` mantém iguais.
```

- [ ] **Passo 3: doc/13**

No parágrafo "**Estado em 2026-09-25:**", trocar o trecho "sem mudar o mínimo
declarado no `pubspec.yaml` (3.44)" por "e o mínimo foi fixado em 3.47.0, a
versão testada no CI ([11](11-empacotamento-versionamento.md) §2)", e
acrescentar ao fim do parágrafo: "Harness de medição, baseline e CI em
`test/perf/`, `tool/perf/` e `.github/workflows/` ([10](10-testes.md) §4.2).
Com isso a Fase 0 está concluída, exceto o S3."

- [ ] **Passo 4: spike/README.md**

Depois do parágrafo "Na engine real, rode **um arquivo por invocação**…",
acrescentar a frase: "O job `engine-linux` do CI segue a mesma regra, com um
`flutter test` por arquivo sob `xvfb-run`."

- [ ] **Passo 5: doc/14**

1. Remover da tabela "Infraestrutura, medição e CI" a linha "Reformatar os
   spikes S5–S8 no formatter do Dart 3.13…".
2. Em **Concluídas**, acrescentar:

```markdown
| Reformatar os spikes S5–S8 no formatter do Dart 3.13 | 2026-09-25 | <hash curto do commit da Tarefa 1> |
```

   Obter o hash com `git log --format=%h -1 --grep='Flutter mínimo 3.47.0'`.
3. Acrescentar em "Infraestrutura, medição e CI" qualquer pendência nova
   surgida nas Tarefas 1–7 (por exemplo, se `measuredSamples` teve de subir,
   ou se o ruído local ficou perto do limite), com origem "Implementação do
   harness (2026-09-25)".

- [ ] **Passo 6: Estado da spec**

Em `doc/specs/2026-09-25-harness-ci-design.md`, trocar "**Estado:** aprovado em
conversa, aguardando revisão da spec escrita." por "**Estado:** aprovada e
implementada (plano em `doc/plans/2026-09-25-harness-ci.md`)."

- [ ] **Passo 7: Conferir links e marcadores**

Run: `grep -n '<máquina\|<X>\|<hash' doc/10-testes.md doc/14-pendencias.md; echo "marcadores: $?"`
Expected: `marcadores: 1` (nenhum encontrado).

- [ ] **Passo 8: Commit**

```bash
git add doc spike/README.md
git commit -m "docs: harness, gate de desempenho e Flutter mínimo 3.47.0; Fase 0 concluída exceto S3"
```

---

### Tarefa 9: PR e CI verde

**Arquivos:** nenhum novo; correções que o CI exigir vão no arquivo afetado.

**Interfaces:** nenhuma.

- [ ] **Passo 1: Verificação local completa**

Run: `dart format --output=none --set-exit-if-changed lib test tool example/lib example/integration_test && flutter analyze && (cd example && flutter analyze) && flutter test && git status --short`
Expected: nada a formatar, `No issues found!` duas vezes, `All tests passed!` e
`git status` vazio.

- [ ] **Passo 2: Push e PR**

```bash
git push -u origin fase0/harness-ci
gh pr create --repo EduardoSA8006/galley --base main --head fase0/harness-ci \
  --title "Fase 0: harness de desempenho, CI e Flutter mínimo 3.47.0" \
  --body-file <arquivo no scratchpad com resumo, commits, verificação e pontos para revisar>
```

O corpo da PR segue o formato da PR #1: resumo, commits, verificação, pontos
para revisar (limite de 20%, ruído medido, `stable` na matriz deixando a PR
vermelha).

- [ ] **Passo 3: Acompanhar o CI**

Run: `gh pr checks --watch --repo EduardoSA8006/galley`
Expected: `analyze`, `test (min)`, `test (stable)`, `engine-linux` e `perf`
verdes; `perf` com o resumo "Sem baseline".

Se `engine-linux` falhar por dependência do sistema ou de GL no xvfb, acrescente
o pacote que o log indicar (ex.: `libgl1-mesa-dri`, `mesa-utils`) à linha do
`apt-get install` em `ci.yml`, commite com `ci: <pacote> para a engine Linux no
xvfb`, faça push e acompanhe de novo. Qualquer outra falha: investigar a causa
antes de mexer (superpowers:systematic-debugging), e registrar em
`doc/14-pendencias.md` o que for adiado.

---

### Tarefa 10: Baseline inicial (depois do merge)

Só depois que a PR da Tarefa 9 for mesclada pelo mantenedor.

**Arquivos:**
- Criar: `test/perf/baseline.json`

**Interfaces:**
- Consome: workflow `perf-baseline` (Tarefa 7).

- [ ] **Passo 1: Sincronizar a main**

Run: `git switch main && git pull --ff-only && git switch -c fase0/perf-baseline`

- [ ] **Passo 2: Gerar o candidato no CI**

```bash
gh workflow run perf-baseline.yml --repo EduardoSA8006/galley --ref main
sleep 5
RUN=$(gh run list --repo EduardoSA8006/galley --workflow perf-baseline.yml --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch "$RUN" --repo EduardoSA8006/galley --exit-status
```

Expected: execução verde.

- [ ] **Passo 3: Baixar e conferir**

```bash
SP=/tmp/claude-1000/-home-eduardo8006-Documentos-projetos-galley/003640ed-5627-4a8b-81ed-13354cf11bdd/scratchpad/baseline
\rm -rf $SP && gh run download "$RUN" --repo EduardoSA8006/galley -n perf-baseline -D $SP
cat $SP/baseline.json
```

Expected: `flutter` igual a `3.47.0`, `runs` igual a 3, `runner`
`ubuntu-24.04`, `sourceCommit` igual ao SHA da main, os 4 casos.

- [ ] **Passo 4: Commit e PR**

```bash
\cp -f $SP/baseline.json test/perf/baseline.json
git add test/perf/baseline.json
git commit -m "perf: baseline inicial da Fase 0

Gerado pelo workflow perf-baseline no ubuntu-24.04 com Flutter 3.47.0,
mediana de três execuções, a partir do commit <sha curto>."
git push -u origin fase0/perf-baseline
gh pr create --repo EduardoSA8006/galley --base main --head fase0/perf-baseline \
  --title "perf: baseline inicial da Fase 0" \
  --body "Baseline gerado pelo workflow perf-baseline (run $RUN), mediana de três execuções no ubuntu-24.04 com Flutter 3.47.0. A partir do merge, o job perf passa a ser bloqueante com o limite de 20%."
gh pr checks --watch --repo EduardoSA8006/galley
```

Trocar `<sha curto>` pelo `sourceCommit` do arquivo (7 primeiros caracteres).
Expected: CI verde, e o resumo do job `perf` com os 4 casos em `ok`.
