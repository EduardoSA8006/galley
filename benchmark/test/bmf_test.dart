import 'dart:convert';

import 'package:galley_benchmark/src/bmf.dart';
import 'package:test/test.dart';

void main() {
  test('toBmf gera o formato BMF com limites', () {
    final out = toBmf({
      'container/crc32-1mib': [
        const Measure(slug: 'instructions', value: 10, lower: 9, upper: 11),
      ],
    });
    expect(jsonDecode(jsonEncode(out)), {
      'container/crc32-1mib': {
        'instructions': {
          'value': 10.0,
          'lower_value': 9.0,
          'upper_value': 11.0,
        },
      },
    });
  });

  test('toBmf omite as chaves nulas', () {
    final out = toBmf({
      'harness/noop': [
        const Measure(slug: 'wall-time-ns', value: 5),
        const Measure(slug: 'size-bytes', value: 7, lower: 6),
      ],
    });
    final json = jsonDecode(jsonEncode(out)) as Map<String, Object?>;
    final noop = json['harness/noop']! as Map<String, Object?>;
    expect(noop['wall-time-ns'], {'value': 5.0});
    expect(noop['size-bytes'], {'value': 7.0, 'lower_value': 6.0});
  });
}
