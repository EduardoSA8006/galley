import 'dart:typed_data';

final Uint32List _table = _buildTable();

Uint32List _buildTable() {
  final table = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    table[n] = c;
  }
  return table;
}

/// Calcula o CRC-32 (polinômio `0xEDB88320`) de [bytes].
///
/// O parâmetro [crc] permite o cálculo incremental: passe o resultado anterior
/// para continuar a soma sobre o próximo trecho. O resultado é sem sinal, de
/// 32 bits.
int crc32(List<int> bytes, [int crc = 0]) =>
    bytes is Uint8List ? _crc32Bytes(bytes, crc) : _crc32List(bytes, crc);

/// Laço quente (leitura do ZIP): com o tipo exato, o AOT lê os bytes e o
/// comprimento direto, sem chamadas pela tabela de despacho de `List<int>`
/// a cada byte. O tamanho e a tabela ficam em variáveis locais.
///
/// Sobre `List<int>`, o laço fazia duas chamadas indiretas por byte (`length`
/// e `[]`): ~2× mais lento e sensível ao layout do executável AOT. Em AMD
/// Zen 3/Zen 5 (runners do CI), só deslocar o código (código morto em outra
/// função) mudava o tempo em 5–8%, e o gate `ab` reprovava sem mudança no
/// container. Este laço varia ≤ 1% com o mesmo deslocamento.
int _crc32Bytes(Uint8List bytes, int crc) {
  final table = _table;
  final n = bytes.length;
  var c = (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  for (var i = 0; i < n; i++) {
    c = table[(c ^ bytes[i]) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}

/// Caminho genérico, para listas que não são `Uint8List` (testes, escrita).
int _crc32List(List<int> bytes, int crc) {
  final table = _table;
  var c = (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  for (var i = 0; i < bytes.length; i++) {
    c = table[(c ^ bytes[i]) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}
