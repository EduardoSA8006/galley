import 'dart:io';

import 'package:galley_benchmark/src/bencher.dart';
import 'package:galley_benchmark/src/modes/size.dart';
import 'package:test/test.dart';

void main() {
  group('sizeDelta e sizeWithinBudget', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('galley-size-'));
    tearDown(() => dir.deleteSync(recursive: true));

    File apk(String name, int bytes) =>
        File('${dir.path}/$name')..writeAsBytesSync(List.filled(bytes, 1));

    test('delta é a diferença de bytes entre os APKs', () {
      expect(sizeDelta(apk('a', 1500), apk('b', 1000)), 500);
    });

    test('2.097.152 passa e 2.097.153 reprova', () {
      expect(sizeWithinBudget(2097152), isTrue);
      expect(sizeWithinBudget(2097153), isFalse);
      expect(sizeWithinBudget(0), isTrue);
    });

    test('o teto é parametrizável', () {
      expect(sizeWithinBudget(10, budget: 9), isFalse);
      expect(sizeWithinBudget(9, budget: 9), isTrue);
    });
  });

  test('sizeBmf grava size-bytes em size/galley-delta-arm64', () {
    expect(sizeBmf(1234), {
      'size/galley-delta-arm64': {
        'size-bytes': {'value': 1234.0},
      },
    });
  });

  group('bencherCommand', () {
    test('comando mínimo', () {
      expect(bencherCommand(testbed: 'local-dev', bmf: File('/tmp/x.json')), [
        'bencher',
        'run',
        '--project',
        'galley',
        '--testbed',
        'local-dev',
        '--adapter',
        'json',
        '--file',
        '/tmp/x.json',
      ]);
    });

    test('com branch e start point', () {
      expect(
        bencherCommand(
          testbed: 'github-ubuntu-nightly',
          bmf: File('out.json'),
          branch: 'baseline',
          startPoint: 'main',
        ),
        [
          'bencher',
          'run',
          '--project',
          'galley',
          '--testbed',
          'github-ubuntu-nightly',
          '--adapter',
          'json',
          '--file',
          'out.json',
          '--branch',
          'baseline',
          '--start-point',
          'main',
        ],
      );
    });
  });

  group('bencherRun', () {
    final bmf = File('/tmp/x.json');

    test('sem BENCHER_API_KEY pula com aviso e não executa nada', () async {
      var calls = 0;
      final r = await bencherRun(
        testbed: 'local-dev',
        bmf: bmf,
        environment: const {},
        runner: (cmd, env) async {
          calls++;
          return 0;
        },
      );
      expect(r.status, BencherStatus.skipped);
      expect(r.exitCode, 0);
      expect(calls, 0);
      expect(r.message, contains('BENCHER_API_KEY'));
    });

    test('chave vazia também pula', () async {
      final r = await bencherRun(
        testbed: 'local-dev',
        bmf: bmf,
        environment: const {'BENCHER_API_KEY': ''},
        runner: (cmd, env) async => fail('não deveria executar'),
      );
      expect(r.status, BencherStatus.skipped);
    });

    test('com a chave executa o comando exato; chave só no ambiente', () async {
      List<String>? seen;
      Map<String, String>? seenEnv;
      final r = await bencherRun(
        testbed: 'github-ubuntu-ab',
        bmf: bmf,
        branch: 'main',
        environment: const {'BENCHER_API_KEY': 's3cr3t'},
        runner: (cmd, env) async {
          seen = cmd;
          seenEnv = env;
          return 0;
        },
      );
      expect(r.status, BencherStatus.uploaded);
      expect(
        seen,
        bencherCommand(testbed: 'github-ubuntu-ab', bmf: bmf, branch: 'main'),
      );
      expect(seen!.join(' '), isNot(contains('s3cr3t')));
      expect(seenEnv!['BENCHER_API_KEY'], 's3cr3t');
    });

    test('código de saída diferente de 0 vira failed', () async {
      final r = await bencherRun(
        testbed: 'local-dev',
        bmf: bmf,
        environment: const {'BENCHER_API_KEY': 't'},
        runner: (cmd, env) async => 3,
      );
      expect(r.status, BencherStatus.failed);
      expect(r.exitCode, 3);
    });

    test('CLI ausente (ProcessException) vira failed com mensagem', () async {
      final r = await bencherRun(
        testbed: 'local-dev',
        bmf: bmf,
        environment: const {'BENCHER_API_KEY': 't'},
        runner: (cmd, env) async =>
            throw const ProcessException('bencher', [], 'not found'),
      );
      expect(r.status, BencherStatus.failed);
      expect(r.exitCode, isNot(0));
      expect(r.message, contains('bencher'));
    });
  });
}
