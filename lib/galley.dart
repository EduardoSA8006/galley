/// Motor de renderização de EPUB nativo para Flutter.
///
/// Fase 1, sub-projeto 1 (contêiner): fonte de bytes, provider de recursos,
/// exceções e diagnósticos. Ver `doc/` para a arquitetura.
library;

export 'src/container/byte_source.dart'
    show EpubByteSource, MemoryEpubByteSource;
export 'src/container/resource_provider.dart' show EpubResourceProvider;
export 'src/diagnostics/diagnostic.dart'
    show EpubDiagnostic, EpubDiagnosticCode, EpubSeverity;
export 'src/diagnostics/exceptions.dart'
    show EpubContainerException, EpubEncryptedException, EpubException;
export 'src/io/file_byte_source.dart' show FileEpubByteSource;
