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
