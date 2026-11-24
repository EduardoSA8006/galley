import 'dart:convert';
import 'dart:typed_data';

import '../crypto/sha1.dart';

/// Algoritmo de ofuscação de fontes da IDPF.
const String idpfObfuscation = 'http://www.idpf.org/2008/embedding';

/// Algoritmo de ofuscação de fontes da Adobe.
const String adobeObfuscation = 'http://ns.adobe.com/pdf/enc#RC';

const int _idpfLength = 1040;
const int _adobeLength = 1024;

/// Desofusca (ou ofusca; a operação é involutiva) uma fonte IDPF.
///
/// A chave é o SHA-1 do identificador único sem espaços em branco (U+0020,
/// U+0009, U+000D, U+000A); os primeiros 1040 bytes recebem XOR com a chave
/// de 20 bytes ciclada. Devolve uma cópia; [data] não é alterada.
Uint8List deobfuscateIdpf(Uint8List data, String uniqueIdentifier) {
  final cleaned = uniqueIdentifier.replaceAll(RegExp('[ \t\r\n]'), '');
  final key = sha1(utf8.encode(cleaned));
  return _xorPrefix(data, key, _idpfLength);
}

/// Desofusca (ou ofusca) uma fonte Adobe.
///
/// A chave são os 16 bytes do UUID de [uniqueIdentifier] (aceita o prefixo
/// `urn:uuid:` e hifens); os primeiros 1024 bytes recebem XOR com a chave
/// ciclada. Lança [FormatException] se o UUID for inválido. Devolve uma
/// cópia; [data] não é alterada.
Uint8List deobfuscateAdobe(Uint8List data, String uniqueIdentifier) {
  final hex = uniqueIdentifier
      .trim()
      .replaceFirst(RegExp('^urn:uuid:', caseSensitive: false), '')
      .replaceAll('-', '');
  if (!RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(hex)) {
    throw FormatException(
      'UUID inválido para ofuscação Adobe',
      uniqueIdentifier,
    );
  }
  final key = Uint8List.fromList([
    for (var i = 0; i < 32; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ]);
  return _xorPrefix(data, key, _adobeLength);
}

Uint8List _xorPrefix(Uint8List data, Uint8List key, int limit) {
  final out = Uint8List.fromList(data);
  final n = out.length < limit ? out.length : limit;
  for (var i = 0; i < n; i++) {
    out[i] ^= key[i % key.length];
  }
  return out;
}
