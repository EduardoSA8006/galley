import 'dart:convert';
import 'dart:io';

import 'package:galley_benchmark/src/modes/ab.dart';
import 'package:galley_benchmark/src/modes/orchestration.dart';
import 'package:galley_benchmark/src/modes/stats.dart';
import 'package:test/test.dart';

AbSamples _s(double ns, {int checksum = 7, double spread = 0}) => AbSamples(
  iterations: 5,
  checksum: checksum,
  nsPerIteration: [for (var i = -2; i <= 2; i++) ns + i * spread],
);

void main() {
  group('parseTimedRun', () {
    test('lê ns e checksum', () {
      final r = parseTimedRun('ns=123456\nchecksum=-9\n');
      expect(r.ns, 123456);
      expect(r.checksum, -9);
    });
    test('saída sem ns lança FormatException', () {
      expect(() => parseTimedRun('checksum=1\n'), throwsFormatException);
      expect(() => parseTimedRun('ns=5\n'), throwsFormatException);
    });
  });

  group('calibrateIterations', () {
    test('~200 ms por amostra: k = 1 + 200ms / ns por iteração', () {
      expect(calibrateIterations(2e6), 101); // 2 ms -> 100 medidas
      expect(calibrateIterations(50e6), 5); // 50 ms -> 4 medidas
    });
    test('iteração maior que o alvo usa k = 2 (1 medida)', () {
      expect(calibrateIterations(900e6), 2);
    });
    test('iteração minúscula é limitada', () {
      expect(calibrateIterations(1), maxAbIterations);
      expect(calibrateIterations(0), maxAbIterations);
    });
  });

  group('evaluateAb', () {
    final result = evaluateAb(
      base: {
        'fast': _s(1000, spread: 10),
        'slow': _s(1000, spread: 10),
        'same': _s(1000, spread: 10),
        'gone': _s(5),
        'sum': _s(1000, checksum: 1),
      },
      head: {
        'fast': _s(800, spread: 10),
        'slow': _s(1300, spread: 10),
        'same': _s(1000, spread: 10),
        'new': _s(9),
        'sum': _s(1000, checksum: 2),
      },
    );
    final rows = {for (final r in result.rows) r.benchId: r};

    test('classifica cada benchmark', () {
      expect(rows['fast']!.verdict, AbVerdict.improved);
      expect(rows['slow']!.verdict, AbVerdict.regressed);
      expect(rows['same']!.verdict, AbVerdict.inconclusiveOrOk);
      expect(rows['gone']!.verdict, AbVerdict.removed);
      expect(rows['new']!.verdict, AbVerdict.added);
      expect(rows['new']!.ci, isNull);
    });
    test('checksums divergentes saem em checksumMismatches', () {
      expect(result.checksumMismatches, ['sum']);
    });
    test('exitCode: 2 com checksum divergente, 1 com regressão, 0 sem', () {
      expect(result.exitCode, 2);
      final noSum = evaluateAb(
        base: {'a': _s(1000, spread: 10)},
        head: {'a': _s(1300, spread: 10)},
      );
      expect(noSum.exitCode, 1);
      final ok = evaluateAb(
        base: {'a': _s(1000, spread: 10)},
        head: {'a': _s(1000, spread: 10), 'b': _s(3)},
      );
      expect(ok.exitCode, 0);
    });
    test('BMF: wall-time-ns do head com limites absolutos; sem removed', () {
      final json =
          jsonDecode(jsonEncode(result.toBmf())) as Map<String, Object?>;
      expect(json.keys, containsAll(['fast', 'slow', 'same', 'new', 'sum']));
      expect(json.containsKey('gone'), isFalse);
      final slow = (json['slow']! as Map)['wall-time-ns']! as Map;
      expect(slow['value'], 1300);
      expect(slow['lower_value'], lessThan(1300));
      expect(slow['upper_value'], greaterThan(1300));
      expect(
        slow['lower_value'],
        closeTo(1000 * rows['slow']!.ci!.lower, 1e-6),
      );
      final added = (json['new']! as Map)['wall-time-ns']! as Map;
      expect(added['value'], 9);
      expect(added.containsKey('lower_value'), isFalse);
    });
  });

  test('relatório: tabela com razão, IC e status', () {
    final r = evaluateAb(
      base: {'a/b': _s(1000, spread: 10)},
      head: {'a/b': _s(1300, spread: 10)},
      notes: const ['nota de teste'],
    );
    final md = renderAbReport(r, rounds: 15);
    expect(md, contains('# Comparação de tempo (A/B)'));
    expect(md, contains('15 rodadas'));
    expect(md, contains('> nota de teste'));
    expect(md, contains('`a/b`'));
    expect(md, contains('regressed'));
    expect(md, contains('+30,0%'));
  });

  test('BMF: lower_value ≤ value ≤ upper_value mesmo se o IC não envolve o ponto', () {
    // Mediana do head acima do IC (IC todo abaixo do ponto): o limite superior
    // é ajustado para o valor.
    const row = AbRow(
      benchId: 'x',
      base: 1000,
      head: 1100,
      ci: (lower: 0.9, point: 1.1, upper: 1.05),
      verdict: AbVerdict.inconclusiveOrOk,
    );
    final m =
        (AbResult(
                  rows: const [row],
                  checksumMismatches: const [],
                  notes: const [],
                  threshold: 0.05,
                ).toBmf()['x']!
                as Map)['wall-time-ns']!
            as Map;
    expect(m['lower_value'], lessThanOrEqualTo(m['value'] as num));
    expect(m['upper_value'], greaterThanOrEqualTo(m['value'] as num));
  });

  group('baseSupportsTiming', () {
    late Directory tmp;
    setUp(() async => tmp = await Directory.systemTemp.createTemp('ab-fake-'));
    tearDown(() => tmp.delete(recursive: true));

    File fake(String body) {
      final f = File('${tmp.path}/runner')
        ..writeAsStringSync('#!/bin/sh\n$body\n');
      Process.runSync('chmod', ['+x', f.path]);
      return f;
    }

    test('exit 0 -> aceita', () async {
      expect(await baseSupportsTiming(fake('echo ns=1'), tmp), isTrue);
    });
    test('exit 64 citando --timing -> não aceita (tudo added)', () async {
      final exe = fake(
        'echo \'Could not find an option "--timing"\' >&2; exit 64',
      );
      expect(await baseSupportsTiming(exe, tmp), isFalse);
    });
    test('exit 64 sem citar --timing -> falha (70)', () async {
      final exe = fake('echo outro >&2; exit 64');
      await expectLater(
        baseSupportsTiming(exe, tmp),
        throwsA(isA<MeasurementFailure>()),
      );
    });
    test('queda (exit 70) -> falha, não "sem suporte"', () async {
      await expectLater(
        baseSupportsTiming(fake('echo boom >&2; exit 70'), tmp),
        throwsA(isA<MeasurementFailure>()),
      );
    });
    test('travamento estoura o timeout e vira falha', () async {
      await expectLater(
        baseSupportsTiming(
          fake('sleep 30'),
          tmp,
          timeout: const Duration(seconds: 1),
        ),
        throwsA(isA<MeasurementFailure>()),
      );
    });
  });

  group('CLI ab', () {
    Future<ProcessResult> cli(List<String> args) => Process.run(
      Platform.resolvedExecutable,
      ['run', 'tool/bench.dart', 'ab', ...args],
    );
    test('--rounds 2 sai com 64', () async {
      final r = await cli([
        '--base',
        'HEAD',
        '--head',
        'HEAD',
        '--rounds',
        '2',
      ]);
      expect(r.exitCode, 64, reason: '${r.stderr}');
    });
    test('sem --base sai com 64', () async {
      final r = await cli(['--head', 'HEAD']);
      expect(r.exitCode, 64, reason: '${r.stderr}');
    });
  });
}
