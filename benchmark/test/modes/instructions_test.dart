import 'dart:convert';
import 'dart:io';

import 'package:galley_benchmark/src/modes/instructions.dart';
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
}
