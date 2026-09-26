// Exports públicos do contêiner (spec §3) e a regra do import condicional.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/galley.dart';

void main() {
  test('lib/galley.dart exporta os tipos da spec §3', () async {
    final EpubByteSource memory = MemoryEpubByteSource(Uint8List(4));
    expect(await memory.length, 4);
    expect(FileEpubByteSource('x.epub').path, 'x.epub');
    const EpubResourceProvider? provider = null;
    expect(provider, isNull);
    final EpubException e = EpubContainerException('m', href: 'a');
    expect(e, isA<Exception>());
    expect(EpubEncryptedException('m', scheme: 'lcp').scheme, 'lcp');
    final d = EpubDiagnostic(
      code: EpubDiagnosticCode.zipCrcMismatch,
      severity: EpubSeverity.warning,
      message: 'm',
    );
    expect(d.code.name, 'zipCrcMismatch');
  });

  test('dart:io só é importado por arquivos *_io.dart de lib/', () {
    final offenders = [
      for (final f in Directory(
        'lib',
      ).listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.dart') &&
            !f.path.endsWith('_io.dart') &&
            f.readAsStringSync().contains("import 'dart:io'"))
          f.path,
    ];
    expect(offenders, isEmpty, reason: 'quebraria a compilação para o web');
  });
}
