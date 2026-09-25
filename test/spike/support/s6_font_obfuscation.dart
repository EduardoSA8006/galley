// Spike S6 — ofuscação de fontes embutidas (doc/09 §4).
//
// Dois algoritmos aparecem em `META-INF/encryption.xml` aplicados a fontes:
//
// - IDPF (http://www.idpf.org/2008/embedding): chave = SHA-1 (20 bytes) dos
//   unique-identifiers concatenados, sem espaço, CR, LF e TAB; XOR dos
//   primeiros 1040 bytes do arquivo com a chave repetida.
// - Adobe (http://ns.adobe.com/pdf/enc#RC): chave = 16 bytes do UUID do
//   identifier (sem "urn:uuid:" e sem hifens, hex → bytes); XOR dos primeiros
//   1024 bytes.
//
// XOR é involutivo: ofuscar e desofuscar são a mesma função.

import 'dart:convert';
import 'dart:typed_data';

import 'sha1.dart';

const idpfAlgorithm = 'http://www.idpf.org/2008/embedding';
const adobeAlgorithm = 'http://ns.adobe.com/pdf/enc#RC';

/// Chave IDPF a partir dos identifiers únicos do OPF.
Uint8List idpfKey(Iterable<String> uniqueIdentifiers) {
  final joined = uniqueIdentifiers.join().replaceAll(RegExp(r'[ \t\r\n]'), '');
  return sha1(Uint8List.fromList(utf8.encode(joined)));
}

/// Chave Adobe a partir do identifier `urn:uuid:xxxxxxxx-xxxx-...`.
Uint8List adobeKey(String identifier) {
  var hex = identifier.trim();
  if (hex.startsWith('urn:uuid:')) hex = hex.substring('urn:uuid:'.length);
  hex = hex.replaceAll('-', '');
  if (hex.length != 32) {
    throw ArgumentError.value(identifier, 'identifier', 'não é um UUID');
  }
  final key = Uint8List(16);
  for (var i = 0; i < 16; i++) {
    key[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return key;
}

/// Aplica XOR dos primeiros [prefixLength] bytes com [key] repetida.
/// Devolve uma cópia; não altera [bytes].
Uint8List xorPrefix(Uint8List bytes, Uint8List key, int prefixLength) {
  final out = Uint8List.fromList(bytes);
  final n = bytes.length < prefixLength ? bytes.length : prefixLength;
  for (var i = 0; i < n; i++) {
    out[i] ^= key[i % key.length];
  }
  return out;
}

Uint8List idpfObfuscate(Uint8List font, Iterable<String> uniqueIdentifiers) =>
    xorPrefix(font, idpfKey(uniqueIdentifiers), 1040);

Uint8List idpfDeobfuscate(Uint8List font, Iterable<String> uniqueIdentifiers) =>
    idpfObfuscate(font, uniqueIdentifiers);

Uint8List adobeObfuscate(Uint8List font, String identifier) =>
    xorPrefix(font, adobeKey(identifier), 1024);

Uint8List adobeDeobfuscate(Uint8List font, String identifier) =>
    adobeObfuscate(font, identifier);
