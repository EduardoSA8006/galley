/// Fonte de bytes do `.epub` (doc/03 §2.1, Emenda 8).
library;

import 'dart:typed_data';

/// Acesso aleatório ao arquivo. Implementável pelo app (HTTP com `Range`,
/// armazenamento próprio).
abstract interface class EpubByteSource {
  /// Tamanho total em bytes.
  Future<int> get length;

  /// Exatamente [length] bytes a partir de [offset]. O resultado pode ser uma
  /// view: quem chama não altera o conteúdo.
  ///
  /// [RangeError] se `offset < 0`, `length < 0` ou `offset + length` passa do
  /// tamanho. [StateError] depois de [close].
  Future<Uint8List> readRange(int offset, int length);

  /// Idempotente.
  Future<void> close();
}

/// Fonte sobre bytes já em memória (web e testes).
final class MemoryEpubByteSource implements EpubByteSource {
  MemoryEpubByteSource(Uint8List bytes) : _bytes = bytes;

  final Uint8List _bytes;
  bool _closed = false;

  @override
  Future<int> get length async {
    _checkOpen();
    return _bytes.length;
  }

  @override
  Future<Uint8List> readRange(int offset, int length) async {
    _checkOpen();
    checkRange(offset, length, _bytes.length);
    return Uint8List.sublistView(_bytes, offset, offset + length);
  }

  @override
  Future<void> close() async => _closed = true;

  void _checkOpen() {
    if (_closed) throw StateError('MemoryEpubByteSource fechada');
  }
}

/// Validação comum de `readRange`.
void checkRange(int offset, int length, int size) {
  if (offset < 0) throw RangeError.value(offset, 'offset', 'negativo');
  if (length < 0) throw RangeError.value(length, 'length', 'negativo');
  if (offset + length > size) {
    throw RangeError(
      'faixa $offset+$length passa do fim da fonte ($size bytes)',
    );
  }
}
