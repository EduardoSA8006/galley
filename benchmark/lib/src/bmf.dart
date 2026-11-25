/// Slugs fixos das métricas (medidas) do formato BMF.
abstract final class MeasureSlug {
  /// Instruções de CPU no espaço do usuário.
  static const instructions = 'instructions';

  /// Tempo de relógio em nanossegundos.
  static const wallTimeNs = 'wall-time-ns';

  /// Pico de memória residente em bytes.
  static const peakRssBytes = 'peak-rss-bytes';

  /// Bytes lidos do arquivo.
  static const bytesRead = 'bytes-read';

  /// Tamanho em bytes.
  static const sizeBytes = 'size-bytes';

  /// Contagem de itens (ex.: livros por classe no modo `wide`).
  static const count = 'count';
}

/// Uma medida de um benchmark, com intervalo opcional.
final class Measure {
  /// Cria uma medida.
  const Measure({
    required this.slug,
    required this.value,
    this.lower,
    this.upper,
  });

  /// Identificador da métrica (ver [MeasureSlug]).
  final String slug;

  /// Valor central.
  final double value;

  /// Limite inferior, se houver.
  final double? lower;

  /// Limite superior, se houver.
  final double? upper;
}

/// Converte medidas para o Bencher Metric Format:
/// `{ "<bench>": { "<slug>": {"value": v, "lower_value": l?, "upper_value": u?} } }`.
Map<String, Object> toBmf(Map<String, List<Measure>> byBenchmark) => {
  for (final entry in byBenchmark.entries)
    entry.key: {
      for (final m in entry.value)
        m.slug: <String, double>{
          'value': m.value,
          'lower_value': ?m.lower,
          'upper_value': ?m.upper,
        },
    },
};
