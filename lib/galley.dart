/// Leitor de EPUB nativo em Dart/Flutter, sem WebView.
library;

export 'src/core/diagnostics/diagnostic.dart'
    show Diagnostic, DiagnosticSeverity;
export 'src/core/diagnostics/diagnostic_sink.dart'
    show CollectingDiagnosticSink, DiagnosticSink, NullDiagnosticSink;
export 'src/core/errors/galley_exception.dart';
export 'src/core/diagnostics/diagnostic_codes.dart' show DiagnosticCodes;
export 'src/features/container/data/zip/zip_limits.dart' show ZipLimits;
export 'src/features/container/domain/epub_book.dart' show EpubBook;
export 'src/features/container/domain/models/epub_metadata.dart'
    show EpubContributor, EpubIdentifier, EpubMetadata, EpubVersion;
export 'src/features/container/domain/models/manifest.dart' show ManifestItem;
export 'src/features/container/domain/models/navigation.dart'
    show EpubNavigation, NavPoint;
export 'src/features/container/domain/models/rendition.dart'
    show EpubRendition, RenditionLayout, RenditionOrientation, RenditionSpread;
export 'src/features/container/domain/models/spine.dart'
    show EpubSpine, PageProgressionDirection, SpineItem;
