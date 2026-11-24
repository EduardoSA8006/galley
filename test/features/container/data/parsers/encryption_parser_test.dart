import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/core/diagnostics/diagnostic_codes.dart';
import 'package:galley/src/core/diagnostics/diagnostic_sink.dart';
import 'package:galley/src/features/container/data/fonts/font_deobfuscator.dart';
import 'package:galley/src/features/container/data/parsers/encryption_parser.dart';

const _ns =
    'xmlns="urn:oasis:names:tc:opendocument:xmlns:container" '
    'xmlns:enc="http://www.w3.org/2001/04/xmlenc#"';

void main() {
  test('dois recursos com paths decodificados', () {
    final sink = CollectingDiagnosticSink();
    final r = parseEncryptionXml('''
<encryption $_ns>
  <enc:EncryptedData>
    <enc:EncryptionMethod Algorithm="$idpfObfuscation"/>
    <enc:CipherData><enc:CipherReference URI="OEBPS/fonts/My%20Font.otf"/></enc:CipherData>
  </enc:EncryptedData>
  <enc:EncryptedData>
    <enc:EncryptionMethod Algorithm="http://example.com/drm"/>
    <enc:CipherData><enc:CipherReference URI="/./OEBPS/a/../b.xhtml"/></enc:CipherData>
  </enc:EncryptedData>
</encryption>''', sink);
    expect(r.map((e) => e.path), ['OEBPS/fonts/My Font.otf', 'OEBPS/b.xhtml']);
    expect(r.map((e) => e.algorithm), [
      idpfObfuscation,
      'http://example.com/drm',
    ]);
    expect(sink.diagnostics, isEmpty);
  });

  test('entrada sem Algorithm ou URI é ignorada com aviso; resto mantido', () {
    final sink = CollectingDiagnosticSink();
    final r = parseEncryptionXml('''
<encryption $_ns>
  <enc:EncryptedData><enc:CipherData><enc:CipherReference URI="a"/></enc:CipherData></enc:EncryptedData>
  <enc:EncryptedData><enc:EncryptionMethod Algorithm="x"/></enc:EncryptedData>
  <enc:EncryptedData><enc:EncryptionMethod Algorithm="$adobeObfuscation"/>
    <enc:CipherData><enc:CipherReference URI="f.otf"/></enc:CipherData></enc:EncryptedData>
</encryption>''', sink);
    expect(r, hasLength(1));
    expect(r.single.path, 'f.otf');
    expect(
      sink.diagnostics.where(
        (d) => d.code == DiagnosticCodes.encryptionInvalid,
      ),
      hasLength(2),
    );
  });

  test('XML malformado devolve [] com encryption.invalid', () {
    final sink = CollectingDiagnosticSink();
    expect(parseEncryptionXml('<encryption', sink), isEmpty);
    expect(sink.diagnostics.single.code, 'encryption.invalid');
  });
}
