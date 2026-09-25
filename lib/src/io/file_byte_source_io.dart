import 'dart:io';
import 'dart:typed_data';

import '../container/byte_source.dart';

/// Fonte sobre um arquivo local, com um `RandomAccessFile` aberto na primeira
/// leitura.
///
/// O `RandomAccessFile` não aceita duas operações assíncronas ao mesmo tempo,
/// então as leituras entram numa fila e rodam uma de cada vez. Cada
/// [readRange] lê em laço até ter todos os bytes.
final class FileEpubByteSource implements EpubByteSource {
  /// Abre o arquivo na primeira chamada a [length] ou [readRange]; arquivo
  /// inexistente ou ilegível lança [FileSystemException] nesse momento.
  FileEpubByteSource(this.path);

  /// O worker (sub-projeto 5) usa para abrir um segundo handle no isolate.
  final String path;

  Future<RandomAccessFile>? _file;
  int? _size;
  Future<void> _tail = Future<void>.value();
  bool _closed = false;
  Future<void>? _closing;

  @override
  Future<int> get length => _enqueue(_sizeOf);

  @override
  Future<Uint8List> readRange(int offset, int length) => _enqueue((f) async {
    checkRange(offset, length, await _sizeOf(f));
    final out = Uint8List(length);
    await f.setPosition(offset);
    var read = 0;
    while (read < length) {
      final n = await f.readInto(out, read, length);
      if (n == 0) {
        throw FileSystemException(
          'fim de arquivo antes do esperado ($read de $length bytes)',
          path,
        );
      }
      read += n;
    }
    return out;
  });

  @override
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    await _tail;
    final file = _file;
    if (file == null) return;
    try {
      await (await file).close();
    } on FileSystemException {
      // Abertura falhou: não há handle para fechar.
    }
  }

  Future<int> _sizeOf(RandomAccessFile f) async => _size ??= await f.length();

  Future<T> _enqueue<T>(Future<T> Function(RandomAccessFile f) op) {
    if (_closed) {
      return Future.error(StateError('FileEpubByteSource fechada: $path'));
    }
    final result = _tail.then((_) async => op(await (_file ??= _open())));
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<RandomAccessFile> _open() => File(path).open();
}
