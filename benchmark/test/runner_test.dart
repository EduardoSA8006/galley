import 'dart:io';

import 'package:test/test.dart';

Future<ProcessResult> _run(List<String> args) => Process.run(
  Platform.resolvedExecutable,
  ['run', 'bin/bench_runner.dart', ...args],
);

void main() {
  test('harness/noop imprime checksum=0 e sai com 0', () async {
    final r = await _run(['--bench', 'harness/noop', '--iterations', '3']);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect((r.stdout as String).trim(), 'checksum=0');
  });

  test('id desconhecido sai com 64 e escreve no stderr', () async {
    final r = await _run(['--bench', 'nao/existe', '--iterations', '1']);
    expect(r.exitCode, 64);
    expect(r.stderr as String, contains('nao/existe'));
  });

  test('--list imprime um id por linha', () async {
    final r = await _run(['--list']);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    final ids = (r.stdout as String).trim().split('\n');
    expect(ids, containsAll(['harness/noop', 'container/crc32-1mib']));
  });

  test('sem --bench nem --list sai com 64', () async {
    final r = await _run(['--iterations', '1']);
    expect(r.exitCode, 64);
  });

  test('--timing imprime ns= e checksum=', () async {
    final r = await _run([
      '--bench',
      'harness/noop',
      '--iterations',
      '3',
      '--timing',
    ]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    final lines = (r.stdout as String).trim().split('\n');
    expect(lines.first, matches(RegExp(r'^ns=\d+$')));
    expect(lines.last, 'checksum=0');
  });

  test('--timing com 1 iteração sai com 64', () async {
    final r = await _run([
      '--bench',
      'harness/noop',
      '--iterations',
      '1',
      '--timing',
    ]);
    expect(r.exitCode, 64);
    expect(r.stderr as String, contains('--timing'));
  });
}
