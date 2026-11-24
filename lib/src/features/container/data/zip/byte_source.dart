import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:galley/src/core/errors/galley_exception.dart';

/// Fonte de bytes de acesso aleatório usada pelo leitor de zip.
abstract interface class ByteSource {
  /// Tamanho total da fonte, em bytes.
  int get length;

  /// Lê [length] bytes a partir de [offset].
  ///
  /// Lança [CorruptArchiveException] se a faixa ultrapassar o fim da fonte.
  Future<Uint8List> read(int offset, int length);

  /// Libera os recursos da fonte.
  Future<void> close();
}

CorruptArchiveException _outOfRange(int offset, int length, int total) =>
    CorruptArchiveException(
      'Leitura fora dos limites: offset $offset, tamanho $length, '
      'total $total.',
    );

bool _invalidRange(int offset, int length, int total) =>
    offset < 0 || length < 0 || offset + length > total;

/// [ByteSource] sobre bytes já em memória.
final class MemoryByteSource implements ByteSource {
  /// Cria a fonte sobre [bytes] (sem copiar).
  MemoryByteSource(this._bytes);

  final Uint8List _bytes;

  @override
  int get length => _bytes.length;

  @override
  Future<Uint8List> read(int offset, int length) async {
    if (_invalidRange(offset, length, _bytes.length)) {
      throw _outOfRange(offset, length, _bytes.length);
    }
    return Uint8List.sublistView(_bytes, offset, offset + length);
  }

  @override
  Future<void> close() async {}
}

/// [ByteSource] sobre um arquivo, lido sob demanda via [RandomAccessFile].
final class FileByteSource implements ByteSource {
  FileByteSource._(this._file, this.length);

  /// Abre o arquivo em [path] para leitura.
  static Future<FileByteSource> open(String path) async {
    final file = await File(path).open();
    try {
      return FileByteSource._(file, await file.length());
    } catch (_) {
      await file.close();
      rethrow;
    }
  }

  final RandomAccessFile _file;

  // `RandomAccessFile` não aceita operações simultâneas: as leituras são
  // encadeadas nesta fila.
  Future<void> _queue = Future<void>.value();

  @override
  final int length;

  @override
  Future<Uint8List> read(int offset, int length) {
    if (_invalidRange(offset, length, this.length)) {
      return Future<Uint8List>.error(_outOfRange(offset, length, this.length));
    }
    final result = _queue.then((_) async {
      await _file.setPosition(offset);
      final data = await _file.read(length);
      if (data.length != length) {
        throw _outOfRange(offset, length, this.length);
      }
      return data;
    });
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  @override
  Future<void> close() async {
    await _queue;
    await _file.close();
  }
}
