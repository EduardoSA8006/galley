// Fnv1a64 (spec do CSS §9.7): vetores de referência do FNV e add fatiado.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/container/fnv1a64.dart';

String _hex(String s) => (Fnv1a64()..add(utf8.encode(s))).hex;

void main() {
  test('vetores de referência', () {
    expect(_hex(''), 'cbf29ce484222325');
    expect(_hex('a'), 'af63dc4c8601ec8c');
    expect(_hex('foobar'), '85944171f73967e8');
  });

  test('add fatiado dá a mesma saída', () {
    final bytes = utf8.encode('foobar');
    final h = Fnv1a64()
      ..add(bytes, 0, 2)
      ..add(bytes, 2, 2)
      ..add(bytes, 2);
    expect(h.hex, '85944171f73967e8');
  });

  test('bytes acima de 255 contam só o byte baixo', () {
    expect((Fnv1a64()..add([0x161])).hex, _hex('a'));
  });

  test('faixa inválida lança RangeError (erro de programação)', () {
    expect(() => Fnv1a64().add([1, 2], 1, 3), throwsRangeError);
  });

  test('1 MiB em tempo linear', () {
    final sw = Stopwatch()..start();
    final h = Fnv1a64()..add(List<int>.filled(1024 * 1024, 7));
    sw.stop();
    expect(h.hex, hasLength(16));
    expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
  });
}
