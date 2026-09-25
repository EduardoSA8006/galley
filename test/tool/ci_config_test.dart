// A versão mínima do Flutter mora em quatro lugares; este teste impede que
// eles divirjam (spec §4 e §5).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _match(String path, RegExp pattern) {
  final m = pattern.firstMatch(File(path).readAsStringSync());
  expect(m, isNotNull, reason: '$path não tem ${pattern.pattern}');
  return m!.group(1)!;
}

void main() {
  test('mínimo do Flutter igual nos pubspecs e nos workflows', () {
    final pubspec = RegExp(r'flutter:\s*">=([0-9.]+)"');
    final workflow = RegExp(r'FLUTTER_MIN:\s*([0-9.]+)');
    final root = _match('pubspec.yaml', pubspec);
    expect(_match('example/pubspec.yaml', pubspec), root);
    expect(_match('.github/workflows/ci.yml', workflow), root);
    expect(_match('.github/workflows/perf-baseline.yml', workflow), root);
  });
}
