import 'dart:typed_data';

import '../container/byte_source.dart';

/// Web: não há sistema de arquivos. Use [MemoryEpubByteSource] ou uma fonte
/// própria.
final class FileEpubByteSource implements EpubByteSource {
  FileEpubByteSource(this.path) {
    throw UnsupportedError(
      'FileEpubByteSource precisa de dart:io; no web, use '
      'MemoryEpubByteSource ou uma EpubByteSource própria.',
    );
  }

  final String path;

  @override
  Future<int> get length => throw UnimplementedError();

  @override
  Future<Uint8List> readRange(int offset, int length) =>
      throw UnimplementedError();

  @override
  Future<void> close() => throw UnimplementedError();
}
