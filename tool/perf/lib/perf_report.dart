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
    return v is num
        ? v.toDouble()
        : _fail(_path(prefix, key), 'deve ser número');
  }

  List<double> numberList(Map<String, Object?> m, String key, String prefix) {
    final v = m[key];
    if (v == null) return const [];
    if (v is! List<Object?>) _fail(_path(prefix, key), 'deve ser lista');
    return [
      for (final (i, e) in v.indexed)
        e is num
            ? e.toDouble()
            : _fail('${_path(prefix, key)}[$i]', 'deve ser número'),
    ];
  }

  DateTime date(Map<String, Object?> m, String key) {
    final s = string(m, key);
    return DateTime.tryParse(s) ??
        _fail(key, 'deve ser data ISO 8601, veio "$s"');
  }
}
