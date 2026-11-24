import 'dart:math';

/// Mediana de [xs] (média dos dois centrais quando o tamanho é par).
///
/// Não altera a lista. Lança [ArgumentError] se [xs] for vazia.
double median(List<double> xs) {
  if (xs.isEmpty) throw ArgumentError.value(xs, 'xs', 'lista vazia');
  final sorted = List<double>.of(xs)..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
}

/// Percentil [p] (0 a 1) de [xs] pelo método do posto mais próximo.
///
/// Não altera a lista. Lança [ArgumentError] se [xs] for vazia ou se [p]
/// estiver fora de [0, 1].
double percentile(List<double> xs, double p) {
  if (xs.isEmpty) throw ArgumentError.value(xs, 'xs', 'lista vazia');
  if (p < 0 || p > 1) throw ArgumentError.value(p, 'p', 'deve estar em [0, 1]');
  final sorted = List<double>.of(xs)..sort();
  final rank = (p * sorted.length).ceil().clamp(1, sorted.length);
  return sorted[rank - 1];
}

/// Intervalo de confiança da razão das medianas.
typedef RatioInterval = ({double lower, double point, double upper});

/// Razão `mediana(head) / mediana(base)` com intervalo por percentis de um
/// bootstrap: em cada um dos [resamples] sorteios, [base] e [head] são
/// reamostradas com reposição (cada uma com o próprio tamanho) e a razão das
/// medianas é registrada. O intervalo cobre [confidence] (padrão 95%).
///
/// Determinístico para uma mesma [seed]. Lança [ArgumentError] se alguma
/// lista for vazia, se [resamples] < 1 ou se [confidence] não estiver em
/// (0, 1).
RatioInterval bootstrapMedianRatio(
  List<double> base,
  List<double> head, {
  int resamples = 10000,
  double confidence = 0.95,
  int seed = 42,
}) {
  if (base.isEmpty || head.isEmpty) {
    throw ArgumentError('base e head precisam de ao menos uma amostra');
  }
  if (resamples < 1) {
    throw ArgumentError.value(resamples, 'resamples', 'deve ser ≥ 1');
  }
  if (confidence <= 0 || confidence >= 1) {
    throw ArgumentError.value(confidence, 'confidence', 'deve estar em (0, 1)');
  }
  final rng = Random(seed);
  final b = List<double>.filled(base.length, 0);
  final h = List<double>.filled(head.length, 0);
  final ratios = List<double>.filled(resamples, 0);
  for (var i = 0; i < resamples; i++) {
    for (var j = 0; j < b.length; j++) {
      b[j] = base[rng.nextInt(base.length)];
    }
    for (var j = 0; j < h.length; j++) {
      h[j] = head[rng.nextInt(head.length)];
    }
    ratios[i] = median(h) / median(b);
  }
  ratios.sort();
  final tail = (1 - confidence) / 2;
  final lo = (tail * resamples).floor().clamp(0, resamples - 1);
  final hi = (((1 - tail) * resamples).ceil() - 1).clamp(0, resamples - 1);
  return (
    lower: ratios[lo],
    point: median(head) / median(base),
    upper: ratios[hi],
  );
}

/// Decisão do modo `ab` para um benchmark.
enum AbVerdict {
  /// O intervalo inteiro está acima de `1 + limite`: reprova.
  regressed,

  /// O intervalo inteiro está abaixo de `1 − limite`.
  improved,

  /// Sem evidência suficiente de mudança acima do limite.
  inconclusiveOrOk,

  /// Só existe no head (não reprova).
  added,

  /// Só existe na base (não reprova).
  removed,
}

/// Decide o veredito a partir do intervalo [ci] da razão head/base.
///
/// `regressed` se `ci.lower > 1 + threshold`; `improved` se
/// `ci.upper < 1 - threshold`; senão `inconclusiveOrOk`.
AbVerdict decideAb(RatioInterval ci, {double threshold = 0.05}) {
  if (ci.lower > 1 + threshold) return AbVerdict.regressed;
  if (ci.upper < 1 - threshold) return AbVerdict.improved;
  return AbVerdict.inconclusiveOrOk;
}
