import 'dart:io';

import 'package:galley_benchmark/src/modes/orchestration.dart';
import 'package:test/test.dart';

void main() {
  group('Shard.parse', () {
    test('aceita i/n com 1 ≤ i ≤ n', () {
      final s = Shard.parse('2/4');
      expect(s.index, 2);
      expect(s.count, 4);
      expect(Shard.parse('1/1').count, 1);
    });
    test('rejeita formatos e faixas inválidos', () {
      for (final bad in [
        '',
        '1',
        '0/4',
        '5/4',
        '1/0',
        'a/b',
        '-1/2',
        '1/2/3',
      ]) {
        expect(() => Shard.parse(bad), throwsFormatException, reason: bad);
      }
    });
  });

  group('Shard.select', () {
    const ids = ['e', 'a', 'd', 'b', 'c'];
    test('reparte os ids ordenados em rodízio', () {
      expect(const Shard(1, 2).select(ids), ['a', 'c', 'e']);
      expect(const Shard(2, 2).select(ids), ['b', 'd']);
    });
    test('as fatias cobrem tudo sem repetir', () {
      final all = [for (var i = 1; i <= 3; i++) ...Shard(i, 3).select(ids)]
        ..sort();
      expect(all, [...ids]..sort());
    });
    test('1/1 devolve todos, ordenados', () {
      expect(Shard.all.select(ids), ['a', 'b', 'c', 'd', 'e']);
    });
    test('fatia além da quantidade de ids fica vazia', () {
      expect(const Shard(3, 3).select(['a', 'b']), isEmpty);
    });
  });

  group('CLI --shard', () {
    for (final mode in ['instructions', 'ab']) {
      test('$mode: --shard inválido sai com 64', () async {
        final r = await Process.run(Platform.resolvedExecutable, [
          'run',
          'tool/bench.dart',
          mode,
          '--base',
          'HEAD',
          '--head',
          'HEAD',
          '--shard',
          '3/2',
        ]);
        expect(r.exitCode, 64, reason: '${r.stderr}');
        expect('${r.stderr}', contains('shard'));
      });
    }
  });
}
