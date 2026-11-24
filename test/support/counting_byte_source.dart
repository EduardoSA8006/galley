import 'dart:typed_data';

import 'package:galley/src/features/container/data/zip/byte_source.dart';

/// [ByteSource] que repassa as leituras a [_inner] e conta o que foi lido
/// (apenas uso em testes).
final class CountingByteSource implements ByteSource {
  /// Envolve [_inner].
  CountingByteSource(this._inner);

  final ByteSource _inner;
  int _bytesRead = 0;
  int _reads = 0;

  /// Total de bytes pedidos com sucesso até agora.
  int get bytesRead => _bytesRead;

  /// Número de chamadas de [read] bem-sucedidas.
  int get reads => _reads;

  @override
  int get length => _inner.length;

  @override
  Future<Uint8List> read(int offset, int length) async {
    final data = await _inner.read(offset, length);
    _bytesRead += data.length;
    _reads++;
    return data;
  }

  @override
  Future<void> close() => _inner.close();
}
