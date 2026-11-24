import 'dart:convert';
import 'dart:typed_data';

import 'zip_builder.dart';

/// Monta um EPUB (zip) em memória para os testes.
///
/// [files] mapeia caminho no zip para conteúdo: `String` (codificada em UTF-8)
/// ou `List<int>`. O `mimetype` vai armazenado (sem deflate); com
/// [mimetypeFirst] falso é gravado depois dos demais arquivos. Com
/// [includeContainer], gera `META-INF/container.xml` apontando para [opfPath].
Uint8List buildEpub(
  Map<String, Object> files, {
  bool includeMimetype = true,
  String mimetype = 'application/epub+zip',
  bool mimetypeFirst = true,
  bool includeContainer = true,
  String opfPath = 'OEBPS/content.opf',
}) {
  final zip = ZipBuilder();
  void addMimetype() =>
      zip.addFile('mimetype', utf8.encode(mimetype), deflate: false);

  if (includeMimetype && mimetypeFirst) addMimetype();
  if (includeContainer) {
    zip.addFile(
      'META-INF/container.xml',
      utf8.encode(
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<container version="1.0" '
        'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
        '<rootfiles><rootfile full-path="$opfPath" '
        'media-type="application/oebps-package+xml"/></rootfiles>'
        '</container>',
      ),
    );
  }
  files.forEach((name, content) {
    zip.addFile(
      name,
      content is String ? utf8.encode(content) : content as List<int>,
    );
  });
  if (includeMimetype && !mimetypeFirst) addMimetype();
  return zip.build();
}

/// Gera um documento OPF 3.0 válido.
///
/// [title] e [identifier] vão em `dc:title` e `dc:identifier id="bookid"`;
/// [manifest] são os `<item>` do manifest; [spine] os `<itemref>`;
/// [extraMetadata] é inserido ao fim de `<metadata>`; [spineAttrs] são
/// atributos extras do `<spine>` (ex.: `page-progression-direction="rtl"`).
String opf3({
  String title = 'T',
  String identifier = 'urn:uuid:12345678-1234-1234-1234-123456789abc',
  String manifest = '',
  String spine = '',
  String extraMetadata = '',
  String spineAttrs = '',
}) => _opf(
  '3.0',
  title,
  identifier,
  manifest,
  spine,
  extraMetadata,
  spineAttrs,
  '<meta property="dcterms:modified">2024-01-01T00:00:00Z</meta>',
);

/// Gera um documento OPF 2.0 válido; mesmos parâmetros de [opf3].
String opf2({
  String title = 'T',
  String identifier = 'urn:uuid:12345678-1234-1234-1234-123456789abc',
  String manifest = '',
  String spine = '',
  String extraMetadata = '',
  String spineAttrs = '',
}) => _opf(
  '2.0',
  title,
  identifier,
  manifest,
  spine,
  extraMetadata,
  spineAttrs,
  '',
);

String _opf(
  String version,
  String title,
  String identifier,
  String manifest,
  String spine,
  String extraMetadata,
  String spineAttrs,
  String versionMetadata,
) =>
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<package xmlns="http://www.idpf.org/2007/opf" '
    'xmlns:dc="http://purl.org/dc/elements/1.1/" version="$version" '
    'unique-identifier="bookid">'
    '<metadata>'
    '<dc:title>$title</dc:title>'
    '<dc:identifier id="bookid">$identifier</dc:identifier>'
    '<dc:language>pt-BR</dc:language>'
    '$versionMetadata$extraMetadata'
    '</metadata>'
    '<manifest>$manifest</manifest>'
    '<spine $spineAttrs>$spine</spine>'
    '</package>';
