import 'dart:io';

import 'package:galley_benchmark/src/corpus/synthetic.dart';
import 'package:test/test.dart';

Future<ProcessResult> _run(List<String> args) => Process.run(
  Platform.resolvedExecutable,
  ['run', 'bin/bench_runner.dart', ...args],
);

/// Compila o `bench_runner` em AOT dentro de [dir] e devolve o caminho.
Future<String> _compile(Directory dir) async {
  final exe = '${dir.path}/runner';
  final c = await Process.run(Platform.resolvedExecutable, [
    'compile',
    'exe',
    'bin/bench_runner.dart',
    '-o',
    exe,
  ]);
  expect(c.exitCode, 0, reason: '${c.stderr}');
  return exe;
}

int _rss(String out) =>
    int.parse(RegExp(r'^rss=(\d+)$', multiLine: true).firstMatch(out)![1]!);

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

  test('--measure-open imprime ns=, rss= e checksum= de um EPUB', () async {
    final dir = Directory.systemTemp.createTempSync('galley-open-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final book = await writeSyntheticBook(
      '${dir.path}/livro.epub',
      targetBytes: 200 * 1024,
      chapters: 3,
    );
    final exe = await _compile(dir);
    final r = await Process.run(exe, ['--measure-open', book.path]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    final out = r.stdout as String;
    expect(out, matches(RegExp(r'^ns=\d+$', multiLine: true)));
    expect(out, matches(RegExp(r'^checksum=\d+$', multiLine: true)));
    // Pequeno: o pico do pai (o processo de teste, em JIT) não pode vazar.
    expect(_rss(out), inExclusiveRange(0, 100 * 1024 * 1024));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('--measure-open com arquivo inexistente sai com 70', () async {
    final r = await _run(['--measure-open', '/nao/existe.epub']);
    expect(r.exitCode, 70);
  });

  test('--adapter e --doc-adapter juntos saem com 64', () async {
    final r = await _run([
      '--adapter',
      'galley',
      '--doc-adapter',
      'xml-dom',
      '--measure',
      'parse',
      'x.epub',
    ]);
    expect(r.exitCode, 64);
    expect(r.stderr as String, contains('não podem ser usados juntos'));
  });

  test('rss= não herda o pico de um pai grande', () async {
    final dir = Directory.systemTemp.createTempSync('galley-parent-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final book = await writeSyntheticBook(
      '${dir.path}/livro.epub',
      targetBytes: 200 * 1024,
      chapters: 3,
    );
    final exe = await _compile(dir);
    // Pai de ~400 MB de RSS: toca as páginas, depois libera e lança o runner.
    final r = await Process.run('python3', [
      '-c',
      'import subprocess,sys\n'
          'b=bytearray(400*1024*1024)\n'
          'for i in range(0,len(b),4096): b[i]=1\n'
          'del b\n'
          'sys.stdout.write(subprocess.run([sys.argv[1],"--measure-open",'
          'sys.argv[2]],capture_output=True,text=True).stdout)',
      exe,
      book.path,
    ]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    final rss = int.parse(
      RegExp(
        r'^rss=(\d+)$',
        multiLine: true,
      ).firstMatch(r.stdout as String)![1]!,
    );
    expect(rss, lessThan(100 * 1024 * 1024));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
