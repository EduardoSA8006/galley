import 'dart:math';

import 'package:galley_benchmark/src/modes/stats.dart';
import 'package:test/test.dart';

/// [n] amostras de média [mean] com ruído gaussiano relativo [noise].
List<double> _samples(Random rng, int n, double mean, double noise) => [
  for (var i = 0; i < n; i++)
    mean *
        (1 +
            noise *
                sqrt(-2 * log(1 - rng.nextDouble())) *
                cos(2 * pi * rng.nextDouble())),
];

void main() {
  group('median', () {
    test('ímpar, par e sem alterar a lista', () {
      final xs = [3.0, 1.0, 2.0];
      expect(median(xs), 2.0);
      expect(xs, [3.0, 1.0, 2.0]);
      expect(median([4.0, 1.0, 3.0, 2.0]), 2.5);
      expect(median([5.0]), 5.0);
    });
    test('lista vazia lança ArgumentError', () {
      expect(() => median([]), throwsArgumentError);
    });
  });

  group('bootstrapMedianRatio + decideAb', () {
    const n = 15;
    late Random rng;
    setUp(() => rng = Random(7));

    AbVerdict verdict(double headMean, double headNoise) {
      final base = _samples(rng, n, 1000, 0.02);
      final head = _samples(rng, n, 1000 * headMean, headNoise);
      return decideAb(bootstrapMedianRatio(base, head));
    }

    test('duas amostras independentes da mesma distribuição: IC contém 1', () {
      final a = _samples(rng, n, 1000, 0.02);
      final b = _samples(rng, n, 1000, 0.02);
      final ci = bootstrapMedianRatio(a, b);
      expect(ci.lower, lessThanOrEqualTo(1.0));
      expect(ci.upper, greaterThanOrEqualTo(1.0));
      expect(decideAb(ci), AbVerdict.inconclusiveOrOk);
    });

    test('head 10% mais lento com ruído de 2% reprova', () {
      expect(verdict(1.10, 0.02), AbVerdict.regressed);
    });

    test('head 3% mais lento com ruído de 5% não reprova', () {
      final base = _samples(rng, n, 1000, 0.05);
      final head = _samples(rng, n, 1030, 0.05);
      expect(
        decideAb(bootstrapMedianRatio(base, head)),
        AbVerdict.inconclusiveOrOk,
      );
    });

    test('head 10% mais rápido é melhoria', () {
      expect(verdict(0.90, 0.02), AbVerdict.improved);
    });

    test('mesma seed dá o mesmo IC; seed diferente, outro', () {
      final base = _samples(rng, n, 1000, 0.03);
      final head = _samples(rng, n, 1050, 0.03);
      final a = bootstrapMedianRatio(base, head);
      final b = bootstrapMedianRatio(base, head);
      expect((a.lower, a.point, a.upper), (b.lower, b.point, b.upper));
      final c = bootstrapMedianRatio(base, head, seed: 1);
      expect(c.lower == a.lower && c.upper == a.upper, isFalse);
    });

    test('lower ≤ point ≤ upper e point = mediana(head)/mediana(base)', () {
      final base = _samples(rng, n, 1000, 0.03);
      final head = _samples(rng, n, 1100, 0.03);
      final ci = bootstrapMedianRatio(base, head);
      expect(ci.point, closeTo(median(head) / median(base), 1e-12));
      expect(ci.lower, lessThanOrEqualTo(ci.point));
      expect(ci.upper, greaterThanOrEqualTo(ci.point));
    });

    test('listas vazias lançam ArgumentError', () {
      expect(() => bootstrapMedianRatio([], [1.0]), throwsArgumentError);
      expect(() => bootstrapMedianRatio([1.0], []), throwsArgumentError);
    });
  });

  group('decideAb', () {
    test('fronteiras: lower exatamente 1,05 não reprova', () {
      expect(
        decideAb((lower: 1.05, point: 1.1, upper: 1.2)),
        AbVerdict.inconclusiveOrOk,
      );
      expect(
        decideAb((lower: 1.0501, point: 1.1, upper: 1.2)),
        AbVerdict.regressed,
      );
      expect(
        decideAb((lower: 0.8, point: 0.9, upper: 0.95)),
        AbVerdict.inconclusiveOrOk,
      );
      expect(
        decideAb((lower: 0.8, point: 0.9, upper: 0.9499)),
        AbVerdict.improved,
      );
    });
  });
}
