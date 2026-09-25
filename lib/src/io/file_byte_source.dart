/// `FileEpubByteSource` por import condicional: `dart:io` no nativo, stub no
/// web.
library;

export 'file_byte_source_stub.dart'
    if (dart.library.io) 'file_byte_source_io.dart';
