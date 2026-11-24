import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/core/diagnostics/diagnostic_codes.dart';
import 'package:galley/src/core/diagnostics/diagnostic_sink.dart';
import 'package:galley/src/features/container/data/parsers/opf_metadata_parser.dart';
import 'package:galley/src/features/container/domain/models/epub_metadata.dart';
import 'package:xml/xml.dart';

import '../../../../support/epub_builder.dart';

XmlElement _package(String opf) => XmlDocument.parse(opf).rootElement;

XmlElement _metadataOf(XmlElement package) =>
    package.findElements('metadata').first;

EpubMetadata _parse(
  String opf,
  CollectingDiagnosticSink sink, {
  EpubVersion version = EpubVersion.epub3,
}) {
  final pkg = _package(opf);
  return parseOpfMetadata(
    _metadataOf(pkg),
    version: version,
    uniqueIdentifierId: pkg.getAttribute('unique-identifier'),
    sink: sink,
  );
}

List<String> _codes(CollectingDiagnosticSink s) =>
    s.diagnostics.map((d) => d.code).toList();

void main() {
  group('parseOpfMetadata EPUB 3', () {
    test('título main vem primeiro, mesmo declarado depois do subtitle', () {
      final sink = CollectingDiagnosticSink();
      final opf = _opfWith(
        '<dc:title id="t1">Subtítulo</dc:title>'
        '<dc:title id="t2">  O   Principal </dc:title>'
        '<meta refines="#t1" property="title-type">subtitle</meta>'
        '<meta refines="#t2" property="title-type">main</meta>',
        includeBaseTitle: false,
      );
      final m = _parse(opf, sink);
      expect(m.title, 'O Principal');
      expect(m.titles, ['O Principal', 'Subtítulo']);
    });

    test('display-seq ordena títulos sem main', () {
      final sink = CollectingDiagnosticSink();
      final opf = _opfWith(
        '<dc:title id="a">B</dc:title><dc:title id="b">A</dc:title>'
        '<meta refines="#a" property="display-seq">2</meta>'
        '<meta refines="#b" property="display-seq">1</meta>',
        includeBaseTitle: false,
      );
      expect(_parse(opf, sink).titles, ['A', 'B']);
    });

    test('criador com refines file-as e role', () {
      final sink = CollectingDiagnosticSink();
      final opf = _opfWith(
        '<dc:creator id="c1">Yukiya Murasaki</dc:creator>'
        '<meta refines="#c1" property="file-as">Murasaki, Yukiya</meta>'
        '<meta refines="#c1" property="role" scheme="marc:relators">aut</meta>'
        '<meta refines="#zzz" property="role">xxx</meta>',
      );
      final m = _parse(opf, sink);
      expect(m.creators, hasLength(1));
      expect(m.creators.single.name, 'Yukiya Murasaki');
      expect(m.creators.single.fileAs, 'Murasaki, Yukiya');
      expect(m.creators.single.role, 'aut');
      expect(_codes(sink), isEmpty);
    });

    test('uniqueIdentifier correto entre dois identificadores', () {
      final sink = CollectingDiagnosticSink();
      final opf = _opfWith(
        '<dc:identifier id="other">urn:isbn:111</dc:identifier>',
      );
      final m = _parse(opf, sink);
      expect(m.identifiers, hasLength(2));
      expect(
        m.uniqueIdentifier,
        'urn:uuid:12345678-1234-1234-1234-123456789abc',
      );
      expect(m.identifiers.last.id, 'other');
      expect(_codes(sink), isEmpty);
    });

    test('uniqueIdentifier ausente usa o primeiro e reporta', () {
      final sink = CollectingDiagnosticSink();
      final pkg = _package(_opfWith(''));
      final m = parseOpfMetadata(
        _metadataOf(pkg),
        version: EpubVersion.epub3,
        uniqueIdentifierId: 'naoexiste',
        sink: sink,
      );
      expect(
        m.uniqueIdentifier,
        'urn:uuid:12345678-1234-1234-1234-123456789abc',
      );
      expect(_codes(sink), [DiagnosticCodes.opfUniqueIdentifierMissing]);
    });

    test(
      'modified lido e demais metas vão para otherMeta (primeiro vence)',
      () {
        final sink = CollectingDiagnosticSink();
        final opf = _opfWith(
          '<meta property="schema:x">um</meta>'
          '<meta property="schema:x">dois</meta>',
        );
        final m = _parse(opf, sink);
        expect(m.modified, '2024-01-01T00:00:00Z');
        expect(m.otherMeta['schema:x'], 'um');
        expect(m.otherMeta.containsKey('dcterms:modified'), isFalse);
      },
    );

    test('campos simples: publisher, description, subjects, date, rights', () {
      final sink = CollectingDiagnosticSink();
      final opf = _opfWith(
        '<dc:publisher>Ed</dc:publisher><dc:description>D</dc:description>'
        '<dc:subject>a</dc:subject><dc:subject>b</dc:subject>'
        '<dc:date>2020-05-01</dc:date><dc:rights>R</dc:rights>'
        '<dc:contributor id="k">Fulano</dc:contributor>'
        '<meta refines="#k" property="role">trl</meta>',
      );
      final m = _parse(opf, sink);
      expect(m.publisher, 'Ed');
      expect(m.description, 'D');
      expect(m.subjects, ['a', 'b']);
      expect(m.date, '2020-05-01');
      expect(m.rights, 'R');
      expect(m.languages, ['pt-BR']);
      expect(m.contributors.single.role, 'trl');
    });

    test('coleções são imutáveis', () {
      final m = _parse(_opfWith(''), CollectingDiagnosticSink());
      expect(() => m.titles.add('x'), throwsUnsupportedError);
      expect(() => m.otherMeta['a'] = 'b', throwsUnsupportedError);
      expect(() => m.creators.clear(), throwsUnsupportedError);
    });
  });

  group('parseOpfMetadata EPUB 2', () {
    test('opf:file-as, opf:role e opf:scheme como atributos', () {
      final sink = CollectingDiagnosticSink();
      final opf = _opf2With(
        '<dc:creator opf:file-as="Autor, A" opf:role="aut">A Autor</dc:creator>'
        '<dc:identifier opf:scheme="ISBN">978</dc:identifier>',
      );
      final m = _parse(opf, sink, version: EpubVersion.epub2);
      expect(m.creators.single.fileAs, 'Autor, A');
      expect(m.creators.single.role, 'aut');
      expect(m.creators.single.name, 'A Autor');
      expect(m.identifiers.last.scheme, 'ISBN');
    });

    test('meta name/content vai para otherMeta', () {
      final sink = CollectingDiagnosticSink();
      final opf = _opf2With('<meta name="cover" content="img"/>');
      final m = _parse(opf, sink, version: EpubVersion.epub2);
      expect(m.otherMeta['cover'], 'img');
    });

    test('meta sem namespace e prefixo opf: em elementos OPF', () {
      final sink = CollectingDiagnosticSink();
      const opf =
          '<package xmlns:opf="http://www.idpf.org/2007/opf" '
          'xmlns:dc="http://purl.org/dc/elements/1.1/" version="2.0" '
          'unique-identifier="bookid">'
          '<opf:metadata><dc:title>T</dc:title>'
          '<dc:identifier id="bookid">x</dc:identifier>'
          '<opf:meta name="cover" content="c"/></opf:metadata></package>';
      final pkg = _package(opf);
      final m = parseOpfMetadata(
        pkg.findElements('metadata', namespace: '*').first,
        version: EpubVersion.epub2,
        uniqueIdentifierId: 'bookid',
        sink: sink,
      );
      expect(m.otherMeta['cover'], 'c');
      expect(m.uniqueIdentifier, 'x');
    });
  });

  group('namespace e título', () {
    test('prefixo dcx: com namespace DC é reconhecido', () {
      final sink = CollectingDiagnosticSink();
      const opf =
          '<package xmlns="http://www.idpf.org/2007/opf" '
          'xmlns:dcx="http://purl.org/dc/elements/1.1/" version="3.0" '
          'unique-identifier="b"><metadata>'
          '<dcx:title>Via dcx</dcx:title>'
          '<dcx:identifier id="b">i</dcx:identifier>'
          '</metadata></package>';
      final m = _parse(opf, sink);
      expect(m.title, 'Via dcx');
      expect(m.uniqueIdentifier, 'i');
    });

    test('sem título: title nulo + opf.titleMissing', () {
      final sink = CollectingDiagnosticSink();
      const opf =
          '<package xmlns="http://www.idpf.org/2007/opf" '
          'xmlns:dc="http://purl.org/dc/elements/1.1/" version="3.0" '
          'unique-identifier="b"><metadata>'
          '<dc:identifier id="b">i</dc:identifier></metadata></package>';
      final m = _parse(opf, sink);
      expect(m.title, isNull);
      expect(_codes(sink), [DiagnosticCodes.opfTitleMissing]);
    });
  });

  group('parseEpubVersion', () {
    XmlElement pkg(String attrs, {String manifest = ''}) => _package(
      '<package xmlns="http://www.idpf.org/2007/opf" $attrs>'
      '<metadata/><manifest>$manifest</manifest></package>',
    );

    test('"3.0" -> epub3', () {
      final sink = CollectingDiagnosticSink();
      expect(parseEpubVersion(pkg('version="3.0"'), sink), EpubVersion.epub3);
      expect(_codes(sink), isEmpty);
    });

    test('"2.0.1" -> epub2', () {
      final sink = CollectingDiagnosticSink();
      expect(parseEpubVersion(pkg('version="2.0.1"'), sink), EpubVersion.epub2);
      expect(_codes(sink), isEmpty);
    });

    test('ausente sem nav -> epub2 + opf.versionInvalid', () {
      final sink = CollectingDiagnosticSink();
      expect(parseEpubVersion(pkg(''), sink), EpubVersion.epub2);
      expect(_codes(sink), [DiagnosticCodes.opfVersionInvalid]);
    });

    test('inválida com item nav -> epub3 + opf.versionInvalid', () {
      final sink = CollectingDiagnosticSink();
      final p = pkg(
        'version="abc"',
        manifest:
            '<item id="n" href="nav.xhtml" properties="scripted nav" '
            'media-type="application/xhtml+xml"/>',
      );
      expect(parseEpubVersion(p, sink), EpubVersion.epub3);
      expect(_codes(sink), [DiagnosticCodes.opfVersionInvalid]);
    });
  });
}

String _opfWith(String extra, {bool includeBaseTitle = true}) {
  final base = opf3(extraMetadata: extra);
  return includeBaseTitle
      ? base
      : base.replaceFirst('<dc:title>T</dc:title>', '');
}

String _opf2With(String extra) => opf2(extraMetadata: extra).replaceFirst(
  'xmlns:dc=',
  'xmlns:opf="http://www.idpf.org/2007/opf" xmlns:dc=',
);
