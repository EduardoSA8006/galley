/// Apoio dos testes do CSS: seções de texto, um contêiner que conta `fetch`
/// e um atalho para carregar as folhas de uma seção (spec do CSS §14).
library;

import 'dart:typed_data';

import 'package:galley/src/container/byte_source.dart';
import 'package:galley/src/container/container.dart';
import 'package:galley/src/container/provider_container.dart';
import 'package:galley/src/container/zip/zip_container.dart';
import 'package:galley/src/css/loader.dart';
import 'package:galley/src/diagnostics/diagnostic.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../../publication/support/epub_fixtures.dart';

export '../../publication/support/epub_fixtures.dart'
    show MapProvider, ZipWriter, epubFiles, epubZip, openZip;

/// Caminho da seção dos testes.
const String sectionPath = 'OEBPS/Text/cap01.xhtml';

/// XHTML de uma seção com [head] e [body].
String xhtml({String head = '', String body = ''}) =>
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<html xmlns="http://www.w3.org/1999/xhtml" '
    'xmlns:epub="http://www.idpf.org/2007/ops"><head><title>T</title>'
    '$head</head><body>$body</body></html>';

Document parseXhtml(String text) => html.parse(text);

/// Delega a [inner] e conta os `fetch` por caminho pedido.
final class CountingContainer implements EpubContainer {
  CountingContainer(this.inner);

  final EpubContainer inner;
  final Map<String, int> fetches = {};

  int get totalFetches => fetches.values.fold(0, (a, b) => a + b);

  @override
  Iterable<String> get paths => inner.paths;

  @override
  Future<bool> exists(String path) => inner.exists(path);

  @override
  Future<PendingResource?> fetch(String path) {
    fetches[path] = (fetches[path] ?? 0) + 1;
    return inner.fetch(path);
  }

  @override
  FontObfuscation? obfuscationOf(String path) => inner.obfuscationOf(path);

  @override
  Future<void> close() => inner.close();
}

/// Contêiner de [files] (por `ZipContainer`, ou `ProviderContainer` com
/// [provider]) aberto com [containerSink].
Future<CountingContainer> openCounting(
  Map<String, Object?> files, {
  required DiagnosticSink containerSink,
  bool provider = false,
}) async => CountingContainer(
  provider
      ? await ProviderContainer.open(MapProvider(files), sink: containerSink)
      : await openZip(files, sink: containerSink),
);

/// `ZipContainer` sobre os bytes de um ZIP montado no teste.
Future<ZipContainer> openZipBytes(Uint8List zip, DiagnosticSink sink) =>
    ZipContainer.open(MemoryEpubByteSource(zip), sink: sink);

/// `ProviderContainer` sobre um [MapProvider] montado no teste.
Future<ProviderContainer> openProvider(
  MapProvider provider,
  DiagnosticSink sink,
) => ProviderContainer.open(provider, sink: sink);

/// Resultado de [loadSheets].
final class Loaded {
  Loaded(this.sheets, this.sink, this.containerSink, this.container);

  final SectionSheets sheets;
  final DiagnosticSink sink;
  final DiagnosticSink containerSink;
  final CountingContainer container;

  /// `href` de cada folha aplicada, na ordem da cascata.
  List<String> get hrefs => [for (final s in sheets.sheets) s.href];

  /// Códigos emitidos no sink da seção, na ordem.
  List<String> get codes => [for (final d in sink.diagnostics) d.code.name];

  EpubDiagnostic only(EpubDiagnosticCode code) =>
      sink.diagnostics.singleWhere((d) => identical(d.code, code));
}

/// Carrega as folhas da seção [section] (texto XHTML em [sectionPath]) de um
/// EPUB com [files], com sinks não estritos (a menos de [strict]).
Future<Loaded> loadSheets(
  Map<String, Object?> files,
  String section, {
  bool provider = false,
  bool strict = false,
  bool containerStrict = false,
  StyleSheetCache? cache,
}) async {
  final containerSink = DiagnosticSink(strict: containerStrict);
  final container = await openCounting(
    {...files, sectionPath: section},
    containerSink: containerSink,
    provider: provider,
  );
  final sink = DiagnosticSink(strict: strict);
  try {
    final sheets = await loadSectionSheets(
      container,
      parseXhtml(section),
      sectionPath: sectionPath,
      cache: cache ?? StyleSheetCache(),
      sink: sink,
      containerSink: containerSink,
    );
    return Loaded(sheets, sink, containerSink, container);
  } finally {
    await container.close();
  }
}
