import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/core/diagnostics/diagnostic.dart';
import 'package:galley/src/core/diagnostics/diagnostic_codes.dart';
import 'package:galley/src/core/diagnostics/diagnostic_sink.dart';
import 'package:galley/src/core/errors/galley_exception.dart';
import 'package:galley/src/features/container/data/parsers/opf_parser.dart';
import 'package:galley/src/features/container/domain/models/epub_metadata.dart';
import 'package:galley/src/features/container/domain/models/opf_document.dart';
import 'package:galley/src/features/container/domain/models/rendition.dart';
import 'package:galley/src/features/container/domain/models/spine.dart';

import '../../../../support/epub_builder.dart';

OpfDocument _parse(
  String xml,
  CollectingDiagnosticSink sink, {
  String opfPath = 'OEBPS/content.opf',
}) => parseOpf(xml, opfPath: opfPath, sink: sink);

List<String> _codes(CollectingDiagnosticSink s) =>
    s.diagnostics.map((d) => d.code).toList();

const _ch1 =
    '<item id="c1" href="ch1.xhtml" media-type="application/xhtml+xml"/>';

void main() {
  late CollectingDiagnosticSink sink;
  setUp(() => sink = CollectingDiagnosticSink());

  group('manifest', () {
    test('resolve href percent-encoded relativo ao OPF', () {
      final doc = _parse(
        opf3(
          manifest:
              '<item id="a" href="Text/cap%C3%ADtulo%201.xhtml" '
              'media-type="application/xhtml+xml" properties=" scripted  svg "/>'
              '<item id="b" href="../x.css" media-type="text/css" '
              'fallback="a"/>',
          spine: '<itemref idref="a"/>',
        ),
        sink,
      );
      expect(doc.version, EpubVersion.epub3);
      expect(doc.manifest['a']!.path, 'OEBPS/Text/capítulo 1.xhtml');
      expect(doc.manifest['a']!.properties, {'scripted', 'svg'});
      expect(doc.manifest['b']!.path, 'x.css');
      expect(doc.manifest['b']!.fallbackId, 'a');
      expect(_codes(sink), isEmpty);
    });

    test('item sem id/href/media-type ou href irresolvível é ignorado', () {
      final doc = _parse(
        opf3(
          manifest:
              '$_ch1'
              '<item href="a.xhtml" media-type="text/css"/>'
              '<item id="n" media-type="text/css"/>'
              '<item id="m" href="a.css"/>'
              '<item id="h" href="http://x.org/a.css" media-type="text/css"/>',
          spine: '<itemref idref="c1"/>',
        ),
        sink,
      );
      expect(doc.manifest.keys, ['c1']);
      expect(
        _codes(sink).where((c) => c == DiagnosticCodes.opfManifestItemInvalid),
        hasLength(4),
      );
    });

    test('id duplicado: o primeiro vence', () {
      final doc = _parse(
        opf3(
          manifest:
              '$_ch1<item id="c1" href="outro.xhtml" '
              'media-type="application/xhtml+xml"/>',
          spine: '<itemref idref="c1"/>',
        ),
        sink,
      );
      expect(doc.manifest['c1']!.path, 'OEBPS/ch1.xhtml');
      expect(_codes(sink), [DiagnosticCodes.opfDuplicateId]);
    });
  });

  group('spine', () {
    test('idref inexistente é pulado; linear="no"; direção rtl', () {
      final doc = _parse(
        opf3(
          manifest:
              '$_ch1<item id="c2" href="ch2.xhtml" '
              'media-type="application/xhtml+xml"/>',
          spine:
              '<itemref idref="c1"/><itemref idref="zz"/>'
              '<itemref idref="c2" linear="no" properties="page-spread-left"/>',
          spineAttrs: 'page-progression-direction="rtl"',
        ),
        sink,
      );
      expect(doc.spine.items.map((i) => i.item.id), ['c1', 'c2']);
      expect(doc.spine.items[0].linear, isTrue);
      expect(doc.spine.items[1].linear, isFalse);
      expect(doc.spine.items[1].properties, {'page-spread-left'});
      expect(doc.spine.direction, PageProgressionDirection.rtl);
      expect(_codes(sink), [DiagnosticCodes.opfSpineRefMissing]);
    });

    test('direção ausente é unspecified; ltr é reconhecido', () {
      expect(
        _parse(
          opf3(manifest: _ch1, spine: '<itemref idref="c1"/>'),
          sink,
        ).spine.direction,
        PageProgressionDirection.unspecified,
      );
      expect(
        _parse(
          opf3(
            manifest: _ch1,
            spine: '<itemref idref="c1"/>',
            spineAttrs: 'page-progression-direction="ltr"',
          ),
          sink,
        ).spine.direction,
        PageProgressionDirection.ltr,
      );
    });

    test('spine vazio gera opf.spineEmpty (error) sem exceção', () {
      _parse(opf3(manifest: _ch1), sink);
      final d = sink.diagnostics.singleWhere(
        (d) => d.code == DiagnosticCodes.opfSpineEmpty,
      );
      expect(d.severity, DiagnosticSeverity.error);
    });

    test('item nav pode estar no spine', () {
      final doc = _parse(
        opf3(
          manifest:
              '<item id="nav" href="nav.xhtml" '
              'media-type="application/xhtml+xml" properties="nav"/>',
          spine: '<itemref idref="nav"/>',
        ),
        sink,
      );
      expect(doc.spine.items, hasLength(1));
      expect(doc.navItem!.id, 'nav');
    });
  });

  group('rendition', () {
    test('padrões', () {
      final r = _parse(
        opf3(manifest: _ch1, spine: '<itemref idref="c1"/>'),
        sink,
      ).rendition;
      expect(r.layout, RenditionLayout.reflowable);
      expect(r.orientation, RenditionOrientation.auto);
      expect(r.spread, RenditionSpread.auto);
    });

    test('pre-paginated + spread portrait → both', () {
      final r = _parse(
        opf3(
          manifest: _ch1,
          spine: '<itemref idref="c1"/>',
          extraMetadata:
              '<meta property="rendition:layout">pre-paginated</meta>'
              '<meta property="rendition:spread">portrait</meta>'
              '<meta property="rendition:orientation">landscape</meta>',
        ),
        sink,
      ).rendition;
      expect(r.layout, RenditionLayout.prePaginated);
      expect(r.spread, RenditionSpread.both);
      expect(r.orientation, RenditionOrientation.landscape);
      expect(_codes(sink), isEmpty);
    });

    test('valor desconhecido → padrão + diagnóstico', () {
      final r = _parse(
        opf3(
          manifest: _ch1,
          spine: '<itemref idref="c1"/>',
          extraMetadata: '<meta property="rendition:layout">bogus</meta>',
        ),
        sink,
      ).rendition;
      expect(r.layout, RenditionLayout.reflowable);
      expect(_codes(sink), [DiagnosticCodes.opfRenditionValueInvalid]);
    });
  });

  group('capa', () {
    const img =
        '<item id="img" href="cover.jpg" media-type="image/jpeg" '
        'properties="cover-image"/>';

    test('por property cover-image', () {
      final doc = _parse(
        opf3(manifest: '$_ch1$img', spine: '<itemref idref="c1"/>'),
        sink,
      );
      expect(doc.cover!.path, 'OEBPS/cover.jpg');
    });

    test('por meta name=cover (EPUB 2)', () {
      final doc = _parse(
        opf2(
          manifest: '$_ch1<item id="cv" href="c.png" media-type="image/png"/>',
          spine: '<itemref idref="c1"/>',
          extraMetadata: '<meta name="cover" content="cv"/>',
        ),
        sink,
      );
      expect(doc.version, EpubVersion.epub2);
      expect(doc.cover!.id, 'cv');
    });

    test('por guide apontando para imagem; XHTML é ignorado', () {
      String withGuide(String href) =>
          opf2(
            manifest:
                '$_ch1<item id="cv" href="c.png" media-type="image/png"/>',
            spine: '<itemref idref="c1"/>',
          ).replaceFirst(
            '</package>',
            '<guide><reference type="cover" href="$href"/></guide></package>',
          );
      expect(_parse(withGuide('c.png'), sink).cover!.id, 'cv');
      expect(_parse(withGuide('ch1.xhtml#x'), sink).cover, isNull);
    });

    test('cover-image tem prioridade sobre meta cover', () {
      final doc = _parse(
        opf3(
          manifest:
              '$_ch1$img<item id="o" href="o.png" media-type="image/png"/>',
          spine: '<itemref idref="c1"/>',
          extraMetadata: '<meta name="cover" content="o"/>',
        ),
        sink,
      );
      expect(doc.cover!.id, 'img');
    });
  });

  group('nav e ncx', () {
    test('ncxItem por spine@toc', () {
      final doc = _parse(
        opf2(
          manifest:
              '$_ch1<item id="n1" href="a.ncx" '
              'media-type="application/x-dtbncx+xml"/>'
              '<item id="n2" href="b.ncx" '
              'media-type="application/x-dtbncx+xml"/>',
          spine: '<itemref idref="c1"/>',
          spineAttrs: 'toc="n2"',
        ),
        sink,
      );
      expect(doc.ncxItem!.id, 'n2');
      expect(doc.navItem, isNull);
    });

    test('ncxItem cai no primeiro item NCX sem spine@toc', () {
      final doc = _parse(
        opf2(
          manifest:
              '$_ch1<item id="n1" href="a.ncx" '
              'media-type="application/x-dtbncx+xml"/>',
          spine: '<itemref idref="c1"/>',
        ),
        sink,
      );
      expect(doc.ncxItem!.id, 'n1');
    });
  });

  group('robustez', () {
    test('XML quebrado → MissingPackageDocumentException', () {
      expect(
        () => _parse('<package', sink),
        throwsA(isA<MissingPackageDocumentException>()),
      );
    });

    test('raiz que não é package → MissingPackageDocumentException', () {
      expect(
        () => _parse('<html/>', sink),
        throwsA(isA<MissingPackageDocumentException>()),
      );
    });

    test('sem metadata/manifest/spine: vazio + diagnósticos, sem exceção', () {
      final doc = _parse(
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0"/>',
        sink,
      );
      expect(doc.manifest, isEmpty);
      expect(doc.spine.items, isEmpty);
      expect(
        _codes(sink),
        containsAll([
          DiagnosticCodes.opfTitleMissing,
          DiagnosticCodes.opfSpineEmpty,
        ]),
      );
    });
  });
}
