import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/core/diagnostics/diagnostic.dart';
import 'package:galley/src/core/diagnostics/diagnostic_codes.dart';
import 'package:galley/src/core/diagnostics/diagnostic_sink.dart';
import 'package:galley/src/features/container/data/parsers/container_xml_parser.dart';
import 'package:xml/xml.dart';

import '../../../../support/epub_builder.dart';

String container(String rootfiles) =>
    '<?xml version="1.0"?><container version="1.0" '
    'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
    '<rootfiles>$rootfiles</rootfiles></container>';

void main() {
  group('parseContainerXml', () {
    test('um rootfile', () {
      final sink = CollectingDiagnosticSink();
      final xml = container(
        '<rootfile full-path="OEBPS/content.opf" '
        'media-type="application/oebps-package+xml"/>',
      );
      expect(parseContainerXml(xml, sink), ['OEBPS/content.opf']);
      expect(sink.diagnostics, isEmpty);
    });

    test('vários rootfiles em ordem, com multipleRenditions (info)', () {
      final sink = CollectingDiagnosticSink();
      final xml = container(
        '<rootfile full-path="OEBPS/a.opf" '
        'media-type="application/oebps-package+xml"/>'
        '<rootfile full-path="OEBPS/b.opf" '
        'media-type="application/oebps-package+xml"/>',
      );
      expect(parseContainerXml(xml, sink), ['OEBPS/a.opf', 'OEBPS/b.opf']);
      expect(
        sink.diagnostics.single.code,
        DiagnosticCodes.containerMultipleRenditions,
      );
      expect(sink.diagnostics.single.severity, DiagnosticSeverity.info);
    });

    test('ignora media-type diferente e full-path ausente', () {
      final sink = CollectingDiagnosticSink();
      final xml = container(
        '<rootfile full-path="x.pdf" media-type="application/pdf"/>'
        '<rootfile media-type="application/oebps-package+xml"/>',
      );
      expect(parseContainerXml(xml, sink), isEmpty);
    });

    test('XML inválido devolve vazio e xmlInvalid (error)', () {
      final sink = CollectingDiagnosticSink();
      expect(parseContainerXml('<nope', sink), isEmpty);
      expect(sink.diagnostics.single.code, DiagnosticCodes.containerXmlInvalid);
      expect(sink.diagnostics.single.severity, DiagnosticSeverity.error);
    });
  });

  group('helpers de teste', () {
    test('opf3 e opf2 são XML válido com namespaces e bookid', () {
      for (final opf in [opf3(), opf2(title: 'Título')]) {
        final doc = XmlDocument.parse(opf);
        final root = doc.rootElement;
        expect(root.name.local, 'package');
        expect(root.getAttribute('unique-identifier'), 'bookid');
        expect(root.getAttribute('xmlns'), 'http://www.idpf.org/2007/opf');
        expect(
          root.getAttribute('xmlns:dc'),
          'http://purl.org/dc/elements/1.1/',
        );
        expect(
          doc.findAllElements('dc:identifier').single.getAttribute('id'),
          'bookid',
        );
      }
      expect(opf3(), contains('version="3.0"'));
      expect(opf2(), contains('version="2.0"'));
    });

    test('buildEpub gera zip com mimetype primeiro e container', () {
      final bytes = buildEpub({'OEBPS/a.txt': 'oi'});
      expect(bytes.sublist(0, 4), [0x50, 0x4B, 0x03, 0x04]);
      final text = String.fromCharCodes(bytes);
      expect(
        text.indexOf('mimetype'),
        lessThan(text.indexOf('META-INF/container.xml')),
      );
      expect(text, contains('application/epub+zip'));
    });
  });
}
