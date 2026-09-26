/// EPUBs de teste da Publicação: `container.xml`, OPF, NAV e NCX de texto,
/// montados com o `ZipWriter` do corpus ou servidos por um provider em
/// memória (spec da Publicação §10).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:galley/src/container/byte_source.dart';
import 'package:galley/src/container/resource_provider.dart';
import 'package:galley/src/container/zip/zip_container.dart';
import 'package:galley/src/diagnostics/diagnostic.dart';

import '../../container/support/zip_fixtures.dart';

export '../../container/support/zip_fixtures.dart' show ZipWriter, epubZip;

const String xhtmlType = 'application/xhtml+xml';
const String ncxType = 'application/x-dtbncx+xml';

String containerXml([List<String> fullPaths = const ['OEBPS/content.opf']]) =>
    '<?xml version="1.0"?><container version="1.0" '
    'xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles>'
    '${[for (final p in fullPaths) '<rootfile full-path="$p" media-type="application/oebps-package+xml"/>'].join()}'
    '</rootfiles></container>';

/// `<item>` do manifest.
String item(
  String id,
  String href, {
  String mediaType = xhtmlType,
  String? properties,
  String? fallback,
}) =>
    '<item id="$id" href="$href" media-type="$mediaType"'
    '${properties == null ? '' : ' properties="$properties"'}'
    '${fallback == null ? '' : ' fallback="$fallback"'}/>';

/// `<itemref>` do spine.
String itemref(String idref, {bool linear = true}) =>
    '<itemref idref="$idref"${linear ? '' : ' linear="no"'}/>';

String opfXml({
  String metadata =
      '<dc:identifier id="uid">urn:uuid:teste</dc:identifier>'
      '<dc:title>Teste</dc:title>',
  required List<String> items,
  required List<String> itemrefs,
  String spineAttributes = '',
  String extra = '',
}) =>
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
    'unique-identifier="uid"><metadata '
    'xmlns:dc="http://purl.org/dc/elements/1.1/">$metadata</metadata>'
    '<manifest>${items.join()}</manifest>'
    '<spine$spineAttributes>${itemrefs.join()}</spine>$extra</package>';

/// NAV com os `nav` dados.
String navXml(String navs) =>
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<html xmlns="http://www.w3.org/1999/xhtml" '
    'xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Nav</title>'
    '</head><body>$navs</body></html>';

/// `nav` de `toc` com uma lista de `(título, href)`.
String tocNav(List<(String, String)> entries, {String type = 'toc'}) =>
    '<nav epub:type="$type"><ol>'
    '${[for (final (t, h) in entries) '<li><a href="$h">$t</a></li>'].join()}'
    '</ol></nav>';

String ncxXml(List<(String, String)> entries, {String pageList = ''}) =>
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">'
    '<head/><docTitle><text>T</text></docTitle><navMap>'
    '${[for (final (t, h) in entries) '<navPoint><navLabel><text>$t</text></navLabel><content src="$h"/></navPoint>'].join()}'
    '</navMap>$pageList</ncx>';

const String chapter =
    '<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml">'
    '<body><p>texto</p></body></html>';

/// [files] com `container.xml` padrão (a menos que dado, ou `null` para
/// omitir); valores `String` (UTF-8) ou `List<int>`.
Map<String, List<int>> epubFiles(Map<String, Object?> files) {
  final all = <String, Object?>{
    'META-INF/container.xml': containerXml(),
    ...files,
  };
  return {
    for (final MapEntry(:key, :value) in all.entries)
      if (value != null)
        key: value is String ? utf8.encode(value) : value as List<int>,
  };
}

Future<ZipContainer> openZip(
  Map<String, Object?> files, {
  required DiagnosticSink sink,
}) => ZipContainer.open(
  MemoryEpubByteSource(epubZip(epubFiles(files))),
  sink: sink,
);

/// Provider em memória. [failingRead] lança em `read`; [failingExists]
/// lança em `exists`; [readThrows] lança o objeto dado em `read`.
final class MapProvider implements EpubResourceProvider {
  MapProvider(
    Map<String, Object?> files, {
    this.failingRead = const {},
    this.failingExists = const {},
    this.readThrows = const {},
  }) : files = epubFiles(files);

  final Map<String, List<int>> files;
  final Set<String> failingRead;
  final Set<String> failingExists;
  final Map<String, Object> readThrows;
  bool closed = false;

  @override
  Future<bool> exists(String href) async {
    if (failingExists.contains(href)) {
      throw FileSystemException('exists falhou', href);
    }
    return files.containsKey(href);
  }

  @override
  Future<Uint8List> read(String href) async {
    final thrown = readThrows[href];
    if (thrown != null) throw thrown;
    if (failingRead.contains(href)) {
      throw FileSystemException('read falhou', href);
    }
    return Uint8List.fromList(files[href]!);
  }

  @override
  Future<void> close() async => closed = true;
}
