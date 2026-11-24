import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/features/container/data/fonts/font_deobfuscator.dart';

void main() {
  final font = Uint8List.fromList(List.generate(2000, (i) => i % 251));
  const uuid = 'urn:uuid:12345678-1234-1234-1234-123456789abc';

  test('idpf: involutivo, ignora espaços e preserva além de 1040', () {
    final once = deobfuscateIdpf(font, ' urn:uuid:abc \n');
    expect(once, isNot(font));
    expect(deobfuscateIdpf(once, 'urn:uuid:abc'), font);
    expect(deobfuscateIdpf(font, 'id').sublist(1040), font.sublist(1040));
    expect(
      deobfuscateIdpf(font, 'id').sublist(0, 1040),
      isNot(font.sublist(0, 1040)),
    );
  });

  test('idpf: não muta a entrada e aceita dados curtos', () {
    final copy = Uint8List.fromList(font);
    deobfuscateIdpf(font, 'id');
    expect(font, copy);
    final short = Uint8List.fromList([1, 2, 3]);
    expect(deobfuscateIdpf(short, 'id'), hasLength(3));
  });

  test('adobe: chave do UUID, fronteira em 1024 e involução', () {
    final out = deobfuscateAdobe(font, uuid);
    expect(out.sublist(1024), font.sublist(1024));
    expect(out[0], font[0] ^ 0x12);
    expect(out[1], font[1] ^ 0x34);
    expect(out[16], font[16] ^ 0x12);
    expect(out[1023], isNot(font[1023] ^ 0));
    expect(deobfuscateAdobe(out, uuid), font);
  });

  test('adobe: UUID inválido lança FormatException', () {
    expect(() => deobfuscateAdobe(font, 'not-a-uuid'), throwsFormatException);
    expect(
      () => deobfuscateAdobe(
        font,
        'urn:uuid:zz345678-1234-1234-1234-123456789abc',
      ),
      throwsFormatException,
    );
  });
}
