/// Desofuscação de fontes embutidas (doc/09 §4, spec do contêiner §6.1).
/// Código e vetores do spike S6. XOR é involutivo: ofuscar e desofuscar são
/// a mesma função.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'container.dart';
import 'sha1.dart';

final RegExp _idpfWhitespace = RegExp('[ \t\r\n]');
final RegExp _hex32 = RegExp(r'^[0-9a-fA-F]{32}$');

/// Desofusca [bytes] conforme [kind]. `null` se não houver identificador
/// utilizável para o algoritmo. [ArgumentError] para
/// [FontObfuscation.unknown].
///
/// - IDPF: XOR dos primeiros 1040 bytes com o SHA-1 da concatenação de
///   [uniqueIdentifiers] sem espaço, CR, LF e TAB.
/// - Adobe: XOR dos primeiros 1024 bytes com os 16 bytes do primeiro de
///   [identifiers] que for `urn:uuid:` (prefixo sem diferenciar maiúsculas)
///   ou 32 dígitos hex, sem hifens.
Uint8List? deobfuscateFont(
  Uint8List bytes,
  FontObfuscation kind, {
  required List<String> uniqueIdentifiers,
  required List<String> identifiers,
}) {
  switch (kind) {
    case FontObfuscation.idpf:
      final joined = uniqueIdentifiers.join().replaceAll(_idpfWhitespace, '');
      if (joined.isEmpty) return null;
      return _xorPrefix(bytes, sha1(utf8.encode(joined)), 1040);
    case FontObfuscation.adobe:
      for (final id in identifiers) {
        final key = _adobeKey(id);
        if (key != null) return _xorPrefix(bytes, key, 1024);
      }
      return null;
    case FontObfuscation.unknown:
      throw ArgumentError.value(kind, 'kind', 'ofuscação desconhecida');
  }
}

/// Magic de fonte conhecido: 00010000, OTTO, true, ttcf, wOFF, wOF2.
bool looksLikeFont(Uint8List bytes) {
  if (bytes.length < 4) return false;
  final magic = bytes[0] << 24 | bytes[1] << 16 | bytes[2] << 8 | bytes[3];
  return const {
    0x00010000, // TrueType
    0x4F54544F, // OTTO
    0x74727565, // true
    0x74746366, // ttcf
    0x774F4646, // wOFF
    0x774F4632, // wOF2
  }.contains(magic);
}

Uint8List? _adobeKey(String identifier) {
  var s = identifier.trim();
  if (s.toLowerCase().startsWith('urn:uuid:')) s = s.substring(9);
  final hex = s.replaceAll('-', '');
  if (!_hex32.hasMatch(hex)) return null;
  return Uint8List.fromList([
    for (var i = 0; i < 16; i++)
      int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
  ]);
}

Uint8List _xorPrefix(Uint8List bytes, Uint8List key, int prefixLength) {
  final out = Uint8List.fromList(bytes);
  final n = bytes.length < prefixLength ? bytes.length : prefixLength;
  for (var i = 0; i < n; i++) {
    out[i] ^= key[i % key.length];
  }
  return out;
}
