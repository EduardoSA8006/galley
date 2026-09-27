// parseContainerXml (spec da Publicação §9.1).
import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/diagnostics/exceptions.dart';
import 'package:galley/src/publication/container_xml.dart';

String _container(String rootfiles) =>
    '<?xml version="1.0"?>'
    '<container version="1.0" '
    'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
    '<rootfiles>$rootfiles</rootfiles></container>';

Matcher _containerError(String text) => throwsA(
  isA<EpubContainerException>()
      .having((e) => e.href, 'href', 'META-INF/container.xml')
      .having((e) => e.message, 'message', contains(text)),
);

void main() {
  test('rootfile do OPF', () {
    expect(
      parseContainerXml(
        _container(
          '<rootfile full-path="OEBPS/content.opf" '
          'media-type="application/oebps-package+xml"/>',
        ),
      ),
      ['OEBPS/content.opf'],
    );
  });

  test('outras renditions: só os de OPF, em ordem', () {
    expect(
      parseContainerXml(
        _container(
          '<rootfile full-path="livro.pdf" media-type="application/pdf"/>'
          '<rootfile full-path="a/um.opf" '
          'media-type="application/oebps-package+xml"/>'
          '<rootfile full-path=" b/dois.opf " '
          'media-type=" Application/OEBPS-Package+XML "/>',
        ),
      ),
      ['a/um.opf', 'b/dois.opf'],
    );
  });

  test('sem namespace e com prefixo também servem', () {
    expect(
      parseContainerXml(
        '<container><rootfiles><rootfile full-path="c.opf" '
        'media-type="application/oebps-package+xml"/></rootfiles></container>',
      ),
      ['c.opf'],
    );
    expect(
      parseContainerXml(
        '<o:container xmlns:o="urn:x"><o:rootfile o:full-path="d.opf" '
        'o:media-type="application/oebps-package+xml"/></o:container>',
      ),
      ['d.opf'],
    );
  });

  test('media-type errado', () {
    expect(
      () => parseContainerXml(
        _container(
          '<rootfile full-path="OEBPS/content.opf" media-type="text/xml"/>',
        ),
      ),
      _containerError('sem rootfile'),
    );
  });

  test('full-path vazio ou ausente', () {
    expect(
      () => parseContainerXml(
        _container(
          '<rootfile full-path=" " '
          'media-type="application/oebps-package+xml"/>'
          '<rootfile media-type="application/oebps-package+xml"/>',
        ),
      ),
      _containerError('full-path vazio'),
    );
  });

  test('XML inválido guarda a XmlException em cause', () {
    expect(
      () => parseContainerXml('<container><rootfiles>'),
      throwsA(
        isA<EpubContainerException>()
            .having((e) => e.href, 'href', 'META-INF/container.xml')
            .having((e) => e.cause, 'cause', isNotNull),
      ),
    );
  });
}
