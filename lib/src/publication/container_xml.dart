/// `META-INF/container.xml` (spec da Publicação §9.1).
library;

import 'package:xml/xml.dart';

import '../diagnostics/exceptions.dart';

const String containerXmlPath = 'META-INF/container.xml';
const String opfMediaType = 'application/oebps-package+xml';

/// Os `full-path` dos `rootfile` com `media-type`
/// `application/oebps-package+xml` e `full-path` não vazio, em ordem de
/// documento (crus: quem resolve é o orquestrador). Uma passada pelos
/// descendentes (iterativa no `package:xml`), linear.
///
/// [EpubContainerException] (`href: META-INF/container.xml`) se o XML é
/// inválido ou se não sobra nenhum `rootfile`.
List<String> parseContainerXml(String text) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(text);
  } on XmlException catch (e) {
    throw EpubContainerException(
      'container.xml não é XML válido: ${e.message}',
      href: containerXmlPath,
      cause: e,
    );
  }
  final paths = <String>[];
  var sawPackageRootfile = false;
  for (final rootfile in document.findAllElements(
    'rootfile',
    namespaceUri: '*',
  )) {
    final mediaType = rootfile.getAttribute('media-type', namespaceUri: '*');
    if (mediaType?.trim().toLowerCase() != opfMediaType) continue;
    sawPackageRootfile = true;
    final fullPath = rootfile.getAttribute('full-path', namespaceUri: '*');
    if (fullPath != null && fullPath.trim().isNotEmpty) {
      paths.add(fullPath.trim());
    }
  }
  if (paths.isEmpty) {
    throw EpubContainerException(
      sawPackageRootfile
          ? 'container.xml só tem rootfile com full-path vazio'
          : 'container.xml sem rootfile de media-type $opfMediaType',
      href: containerXmlPath,
    );
  }
  return paths;
}
