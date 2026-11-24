import 'dart:convert';
import 'dart:io';

import 'package:galley_benchmark/src/modes/instructions.dart';
import 'package:galley_benchmark/src/modes/orchestration.dart';
import 'package:test/test.dart';

/// Saída real do cachegrind (`--cache-sim=no`) sobre o `bench_runner`.
const _cachegrindStderr = '''
==1866608== Cachegrind, a high-precision tracing profiler
==1866608== Copyright (C) 2002-2024, and GNU GPL'd, by Nicholas Nethercote et al.
==1866608== Using Valgrind-3.24.0 and LibVEX; rerun with -h for copyright info
==1866608== Command: /tmp/runner --bench container/crc32-1mib --iterations 4
==1866608==
==1866608== I refs:        968,757,243
''';

/// Saída real de `perf stat -x, -e instructions:u`.
const _perfStderr = '5365604,,instructions:u,2164171,100,00,,\n';

InstructionCount _count(int perIteration, {int checksum = 7}) =>
    InstructionCount(
      lowIterations: 1,
      highIterations: 2,
      low: 1000,
      high: 1000 + perIteration,
      checksum: checksum,
    );

void main() {
  group('compareInstructions', () {
    final rows = {
      for (final r in compareInstructions(
        {'a': 1000000, 'b': 1000000, 'c': 1000000, 'gone': 5},
        {'a': 1004000, 'b': 1006000, 'c': 970000, 'new': 9},
      ))
        r.benchId: r,
    };

    test('+0,4% fica ok', () {
      expect(rows['a']!.status, GateStatus.ok);
      expect(rows['a']!.ratio, closeTo(1.004, 1e-12));
    });
    test('+0,6% reprova', () {
      expect(rows['b']!.status, GateStatus.regressed);
    });
    test('−3% é melhoria', () {
      expect(rows['c']!.status, GateStatus.improved);
    });
    test('só no head é added, sem base nem razão', () {
      expect(rows['new']!.status, GateStatus.added);
      expect(rows['new']!.base, isNull);
      expect(rows['new']!.ratio, isNull);
      expect(rows['new']!.head, 9);
    });
    test('só na base é removed', () {
      expect(rows['gone']!.status, GateStatus.removed);
      expect(rows['gone']!.head, isNull);
    });
    test('exatamente +0,5% não reprova', () {
      final r = compareInstructions({'x': 1000000}, {'x': 1005000}).single;
      expect(r.status, GateStatus.ok);
    });
  });

  group('parsers', () {
    test('cachegrind: I refs do stderr', () {
      expect(parseCachegrindInstructions(_cachegrindStderr), 968757243);
    });
    test('cachegrind sem I refs lança FormatException', () {
      expect(
        () => parseCachegrindInstructions('==1== erro qualquer\n'),
        throwsFormatException,
      );
    });
    test('perf: CSV de instructions:u', () {
      expect(parsePerfInstructions(_perfStderr), 5365604);
    });
    test('perf: ignora linhas do programa antes do CSV', () {
      expect(parsePerfInstructions('aviso do programa\n$_perfStderr'), 5365604);
    });
    test('perf: CPU híbrida soma cpu_core e cpu_atom', () {
      expect(
        parsePerfInstructions(
          '1000,,cpu_core/instructions:u/,5,100,00,,\n'
          '234,,cpu_atom/instructions:u/,5,100,00,,\n',
        ),
        1234,
      );
    });
    test('perf: CPU híbrida com <not counted> num tipo de núcleo', () {
      expect(
        parsePerfInstructions(
          '1000,,cpu_core/instructions:u/,5,100,00,,\n'
          '<not counted>,,cpu_atom/instructions:u/,0,0,,\n',
        ),
        1000,
      );
    });
    test('perf: <not supported> lança FormatException', () {
      expect(
        () => parsePerfInstructions('<not supported>,,instructions:u,0,100,,'),
        throwsFormatException,
      );
    });
  });

  group('InstructionCount', () {
    test('por iteração = (I(n2) − I(n1)) / (n2 − n1)', () {
      const c = InstructionCount(
        lowIterations: 1,
        highIterations: 4,
        low: 1000,
        high: 7000,
        checksum: 1,
      );
      expect(c.perIteration, 2000);
    });
  });

  group('CounterUnavailable', () {
    final exe = File('/nao/existe/runner');
    test('valgrind ausente do PATH', () async {
      await expectLater(
        countInstructions(
          exe,
          'harness/noop',
          Counter.valgrind,
          environment: const {'PATH': ''},
        ),
        throwsA(
          isA<CounterUnavailable>().having(
            (e) => e.message,
            'message',
            contains(
              'instale valgrind (ex.: sudo apt-get install -y valgrind)',
            ),
          ),
        ),
      );
    });
    test('perf ausente do PATH', () async {
      await expectLater(
        countInstructions(
          exe,
          'harness/noop',
          Counter.perf,
          environment: const {'PATH': ''},
        ),
        throwsA(isA<CounterUnavailable>()),
      );
    });
    test('mensagem do perf bloqueado', () {
      expect(
        CounterUnavailable.perfBlocked(3).message,
        'perf_event_paranoid=3; rode: sudo sysctl '
        'kernel.perf_event_paranoid=1 ou use --counter valgrind',
      );
    });
  });

  group('perf/valgrind falsos no PATH', () {
    late Directory bin;
    setUp(() async => bin = await Directory.systemTemp.createTemp('fakebin-'));
    tearDown(() async => bin.delete(recursive: true));

    Map<String, String> env() => {'PATH': '${bin.path}:/usr/bin:/bin'};

    void fake(String name, String body) {
      final f = File('${bin.path}/$name')
        ..writeAsStringSync('#!/bin/sh\n$body\n');
      Process.runSync('chmod', ['+x', f.path]);
    }

    Future<CountedRun> run(Counter c, {Duration? timeout}) => runCounted(
      File('/bin/true'),
      'x/y',
      1,
      c,
      environment: env(),
      timeout: timeout ?? const Duration(seconds: 30),
    );

    test('perf híbrido: soma as linhas', () async {
      fake(
        'perf',
        "echo checksum=5\n"
            "echo '10,,cpu_core/instructions:u/,1,100,,' >&2\n"
            "echo '7,,cpu_atom/instructions:u/,1,100,,' >&2",
      );
      final r = await run(Counter.perf);
      expect(r.instructions, 17);
      expect(r.checksum, 5);
    });

    test('perf <not supported>: mensagem própria, sem paranoid', () async {
      fake(
        'perf',
        "echo checksum=5\n"
            "echo '<not supported>,,instructions:u,0,100,,' >&2",
      );
      await expectLater(
        run(Counter.perf),
        throwsA(
          isA<CounterUnavailable>().having(
            (e) => e.message,
            'message',
            'contador de instruções indisponível nesta máquina/VM; '
                'use --counter valgrind',
          ),
        ),
      );
    });

    test('perf sem permissão: mensagem do perf_event_paranoid', () async {
      fake(
        'perf',
        "echo 'Error: Access to performance monitoring and observability "
            "operations is limited. perf_event_paranoid setting is 4' >&2\n"
            'exit 255',
      );
      await expectLater(
        run(Counter.perf),
        throwsA(
          isA<CounterUnavailable>().having(
            (e) => e.message,
            'message',
            startsWith('perf_event_paranoid='),
          ),
        ),
      );
    });

    test('timeout mata o processo e os filhos e cita o benchmark', () async {
      final pidFile = '${bin.path}/pid';
      fake('valgrind', 'sleep 60 &\necho \$! > $pidFile\nwait');
      await expectLater(
        run(Counter.valgrind, timeout: const Duration(seconds: 2)),
        throwsA(
          isA<MeasurementFailure>().having(
            (e) => e.message,
            'message',
            allOf(contains('x/y'), contains('tempo esgotado')),
          ),
        ),
      );
      final pid = File(pidFile).readAsStringSync().trim();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(Directory('/proc/$pid').existsSync(), isFalse);
    });
  });

  test(
    'CLI: ProcessException (git ausente) sai com 70 sem stack trace',
    () async {
      final bin = await Directory.systemTemp.createTemp('fakebin-');
      addTearDown(() => bin.delete(recursive: true));
      final f = File('${bin.path}/valgrind')..writeAsStringSync('#!/bin/sh\n');
      Process.runSync('chmod', ['+x', f.path]);
      final r = await Process.run(
        Platform.resolvedExecutable,
        [
          'run',
          'tool/bench.dart',
          'instructions',
          '--base',
          'HEAD',
          '--head',
          'HEAD',
        ],
        environment: {'PATH': bin.path},
      );
      expect(r.exitCode, 70, reason: '${r.stdout}\n${r.stderr}');
      expect(r.stderr as String, contains('git'));
      expect(r.stderr as String, isNot(contains('#0 ')));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  group('evaluateGate', () {
    test('checksums divergentes saem com 2 e listam o benchmark', () {
      final r = evaluateGate(
        base: {'a': _count(100, checksum: 1), 'b': _count(100)},
        head: {'a': _count(100, checksum: 2), 'b': _count(100)},
      );
      expect(r.exitCode, 2);
      expect(r.checksumMismatches, ['a']);
      expect(renderReport(r), contains('a'));
    });
    test('regressão sai com 1', () {
      final r = evaluateGate(
        base: {'a': _count(1000)},
        head: {'a': _count(1010)},
      );
      expect(r.exitCode, 1);
      expect(r.rows.single.status, GateStatus.regressed);
    });
    test('added e removed não reprovam', () {
      final r = evaluateGate(
        base: {'old': _count(10)},
        head: {'new': _count(10)},
      );
      expect(r.exitCode, 0);
    });
    test('BMF só com os valores do head', () {
      final r = evaluateGate(
        base: {'old': _count(10), 'a': _count(10)},
        head: {'a': _count(12)},
      );
      expect(jsonDecode(jsonEncode(r.toBmf())), {
        'a': {
          'instructions': {'value': 12.0},
        },
      });
    });
  });

  group('CLI instructions (integração)', tags: ['slow'], () {
    late Directory tmp;
    setUp(() async => tmp = await Directory.systemTemp.createTemp('instr-it-'));
    tearDown(() async => tmp.delete(recursive: true));

    Future<ProcessResult> cli(List<String> extra) =>
        Process.run(Platform.resolvedExecutable, [
          'run',
          'tool/bench.dart',
          'instructions',
          '--head',
          'HEAD',
          '--counter',
          'valgrind',
          '--bench',
          'container/deobfuscate-idpf',
          '--bench',
          'container/decode-text-utf16',
          '--out',
          '${tmp.path}/bmf.json',
          '--report',
          '${tmp.path}/report.md',
          ...extra,
        ]);

    test('HEAD × HEAD: todos ok e variação < 0,01%', () async {
      final r = await cli(['--base', 'HEAD']);
      expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
      final bmf = jsonDecode(
        File('${tmp.path}/bmf.json').readAsStringSync(),
      ) as Map<String, Object?>;
      expect(bmf.keys, {
        'container/deobfuscate-idpf',
        'container/decode-text-utf16',
      });
      final report = File('${tmp.path}/report.md').readAsStringSync();
      final row = RegExp(
        r'^\| `([^`]+)` \| (\d+) \| (\d+) \| [^|]+ \| (\w+) \|$',
        multiLine: true,
      );
      final matches = row.allMatches(report).toList();
      expect(matches, hasLength(2), reason: report);
      for (final m in matches) {
        expect(m[4], 'ok', reason: m[0]);
        final base = int.parse(m[2]!);
        final head = int.parse(m[3]!);
        expect((head - base).abs() / base, lessThan(0.0001), reason: m[0]);
      }
    }, timeout: const Timeout(Duration(minutes: 15)));

    test('base sem benchmark/ marca tudo como added e sai com 0', () async {
      final r = await cli(['--base', 'd4ef38a']);
      expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
      final report = File('${tmp.path}/report.md').readAsStringSync();
      expect(report, contains('não tem `benchmark/`'));
      expect('| added |'.allMatches(report), hasLength(2), reason: report);
    }, timeout: const Timeout(Duration(minutes: 15)));
  });

  group('parseThreshold', () {
    test('aceita valores entre 0 (exclusive) e 1', () {
      expect(parseThreshold('0.005'), 0.005);
      expect(parseThreshold('0.10'), 0.1);
      expect(parseThreshold('1'), 1.0);
    });
    test('rejeita fora de (0, 1] e texto inválido', () {
      for (final bad in ['0', '-0.1', '1.5', 'abc', '', 'NaN']) {
        expect(() => parseThreshold(bad), throwsFormatException, reason: bad);
      }
    });
    test('o padrão é 0,5%', () {
      expect(defaultThreshold, 0.005);
    });
  });
}
