// Stub do inflate no web (P7, adiado para a 1.0.x). Só roda com
// `flutter test --platform chrome test/container/inflate_web_test.dart`; na
// VM, @TestOn pula o arquivo.
@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/container/inflate/inflate.dart';

void main() {
  test('createInflater lança UnsupportedError citando P7 e 1.0.x', () {
    expect(
      () => createInflater((_) {}),
      throwsA(
        isA<UnsupportedError>().having(
          (e) => e.message,
          'message',
          allOf(contains('P7'), contains('1.0.x')),
        ),
      ),
    );
  });
}
