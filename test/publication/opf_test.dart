// parseOpf: leitura por nome local, metadados, manifest, spine e
// fatais (spec da Publicação §6).
import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/diagnostics/diagnostic.dart';
import 'package:galley/src/diagnostics/exceptions.dart';
import 'package:galley/src/publication/model.dart';
import 'package:galley/src/publication/opf.dart';

const _manifest =
    '<manifest><item id="c1" href="Text/c1.xhtml" '
    'media-type="application/xhtml+xml"/></manifest>';
const _spine = '<spine><itemref idref="c1"/></spine>';

String _opf({
  String metadata = '',
  String manifest = _manifest,
  String spine = _spine,
  String extra = '',
  String package =
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
      'unique-identifier="uid">',
}) =>
    '<?xml version="1.0"?>$package'
    '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/" '
    'xmlns:opf="http://www.idpf.org/2007/opf">$metadata</metadata>'
    '$manifest$spine$extra</package>';

OpfDocument _parse(String text, {DiagnosticSink? sink}) => parseOpf(
  text,
  opfPath: 'OEBPS/content.opf',
  sink: sink ?? DiagnosticSink(),
);

void main() {
  group('leitura por nome local', () {
    test('sem namespace nenhum', () {
      final opf = _parse(
        '<package version="2.0"><metadata><dc:title>Sem ns</dc:title>'
        '</metadata>$_manifest$_spine</package>',
      );
      expect(opf.metadata.title, 'Sem ns');
      expect(opf.version, '2.0');
      expect(opf.items.single.href, 'Text/c1.xhtml');
    });

    test('estrutura com prefixo opf:', () {
      final opf = _parse(
        '<opf:package xmlns:opf="http://www.idpf.org/2007/opf" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<opf:metadata><dc:title>Prefixado</dc:title>'
        '<dc:creator opf:role="trl">Tradutor</dc:creator></opf:metadata>'
        '<opf:manifest><opf:item id="c1" href="c1.xhtml" '
        'media-type="application/xhtml+xml"/></opf:manifest>'
        '<opf:spine><opf:itemref idref="c1"/></opf:spine></opf:package>',
      );
      expect(opf.metadata.title, 'Prefixado');
      expect(opf.metadata.contributors, ['Tradutor']);
      expect(opf.itemrefs.single.idref, 'c1');
    });

    test('dc: sem namespace declarado e dc:Title (OEB antigo)', () {
      final opf = _parse(
        '<package><metadata><dc-metadata><dc:Title>Antigo</dc:Title>'
        '<dc:Creator>Autor</dc:Creator></dc-metadata>'
        '<x-metadata><meta name="cover" content="capa"/></x-metadata>'
        '</metadata>$_manifest$_spine</package>',
      );
      expect(opf.metadata.title, 'Antigo');
      expect(opf.metadata.authors, ['Autor']);
      expect(opf.coverId, 'capa');
    });

    test('dc no namespace com outro prefixo', () {
      final opf = _parse(
        '<package><metadata xmlns:d="http://purl.org/dc/elements/1.1/">'
        '<d:title>Outro prefixo</d:title></metadata>$_manifest$_spine'
        '</package>',
      );
      expect(opf.metadata.title, 'Outro prefixo');
    });
  });

  group('títulos', () {
    test('vários dc:title sem refinamento: o primeiro; os outros em raw', () {
      final m = _parse(
        _opf(metadata: '<dc:title>Um</dc:title><dc:title>Dois</dc:title>'),
      ).metadata;
      expect(m.title, 'Um');
      expect(m.subtitle, isNull);
      expect(m.raw['title'], ['Dois']);
    });

    test('title-type main, subtitle e expanded', () {
      final m = _parse(
        _opf(
          metadata:
              '<dc:title id="t1">Completo</dc:title>'
              '<meta refines="#t1" property="title-type">expanded</meta>'
              '<dc:title id="t2">Sub</dc:title>'
              '<meta refines="#t2" property="title-type">subtitle</meta>'
              '<dc:title id="t3">Principal</dc:title>'
              '<meta refines="#t3" property="title-type">main</meta>',
        ),
      ).metadata;
      expect(m.title, 'Principal');
      expect(m.subtitle, 'Sub');
      expect(m.raw['title'], ['Completo']);
      expect(m.raw.containsKey('title-type'), isFalse);
    });

    test('sem main: o primeiro que não é subtitle nem expanded', () {
      final m = _parse(
        _opf(
          metadata:
              '<dc:title id="t1">Sub</dc:title>'
              '<meta refines="#t1" property="title-type">subtitle</meta>'
              '<dc:title id="t2">Título</dc:title>',
        ),
      ).metadata;
      expect(m.title, 'Título');
      expect(m.subtitle, 'Sub');
    });

    test('só subtitle: vira título, e não é também subtítulo', () {
      final m = _parse(
        _opf(
          metadata:
              '<dc:title id="t1">Só</dc:title>'
              '<meta refines="#t1" property="title-type">subtitle</meta>',
        ),
      ).metadata;
      expect(m.title, 'Só');
      expect(m.subtitle, isNull);
    });

    test('title-type duplicado no mesmo título: só o primeiro decide', () {
      final m = _parse(
        _opf(
          metadata:
              '<dc:title id="t1">Só</dc:title>'
              '<meta refines="#t1" property="title-type">main</meta>'
              '<meta refines="#t1" property="title-type">subtitle</meta>',
        ),
      ).metadata;
      expect(m.title, 'Só');
      expect(m.subtitle, isNull);
      expect(m.raw['title-type'], ['subtitle']);
    });
  });

  group('autores e colaboradores', () {
    test('creator sem papel é autor; contributor é colaborador', () {
      final m = _parse(
        _opf(
          metadata:
              '<dc:creator>Autora</dc:creator>'
              '<dc:contributor>Revisor</dc:contributor>'
              '<dc:creator opf:role="ill">Ilustrador</dc:creator>'
              '<dc:creator opf:role="aut">Coautor</dc:creator>',
        ),
      ).metadata;
      expect(m.authors, ['Autora', 'Coautor']);
      expect(m.contributors, ['Revisor', 'Ilustrador']);
    });

    test('role refinado, vários, algum aut', () {
      final m = _parse(
        _opf(
          metadata:
              '<dc:creator id="a">Herman</dc:creator>'
              '<meta property="role" refines="#a" scheme="marc:relators">'
              'ann</meta>'
              '<meta property="role" refines="#a">aut</meta>'
              '<dc:creator id="b">Artista</dc:creator>'
              '<meta property="role" refines="#b">art</meta>',
        ),
      ).metadata;
      expect(m.authors, ['Herman']);
      expect(m.contributors, ['Artista']);
      expect(m.raw.containsKey('role'), isFalse);
    });

    test('role refinando publisher fica em raw', () {
      final m = _parse(
        _opf(
          metadata:
              '<dc:publisher id="p">Editora</dc:publisher>'
              '<meta property="role" refines="#p">pbl</meta>',
        ),
      ).metadata;
      expect(m.publisher, 'Editora');
      expect(m.raw['role'], ['pbl']);
    });
  });

  group('série', () {
    test('collection-type series, com group-position', () {
      final m = _parse(
        _opf(
          metadata:
              '<meta property="belongs-to-collection" id="c">Saga</meta>'
              '<meta refines="#c" property="collection-type">series</meta>'
              '<meta refines="#c" property="group-position">2.5</meta>',
        ),
      ).metadata;
      expect(m.series, 'Saga');
      expect(m.seriesIndex, 2.5);
      expect(m.raw, isEmpty);
    });

    test('collection-type set vai para raw, com os refinamentos', () {
      final m = _parse(
        _opf(
          metadata:
              '<meta property="belongs-to-collection" id="c">Lista</meta>'
              '<meta refines="#c" property="collection-type">set</meta>'
              '<meta refines="#c" property="group-position">17</meta>',
        ),
      ).metadata;
      expect(m.series, isNull);
      expect(m.raw['belongs-to-collection'], ['Lista']);
      expect(m.raw['collection-type'], ['set']);
      expect(m.raw['group-position'], ['17']);
    });

    test('sem collection-type é série; o set antes é pulado', () {
      final m = _parse(
        _opf(
          metadata:
              '<meta property="belongs-to-collection" id="c1">Lista</meta>'
              '<meta refines="#c1" property="collection-type">set</meta>'
              '<meta property="belongs-to-collection">Série</meta>',
        ),
      ).metadata;
      expect(m.series, 'Série');
      expect(m.seriesIndex, isNull);
    });

    test('calibre:series na falta do EPUB3', () {
      final m = _parse(
        _opf(
          metadata:
              '<meta name="calibre:series" content="Discworld"/>'
              '<meta name="calibre:series_index" content="3"/>',
        ),
      ).metadata;
      expect(m.series, 'Discworld');
      expect(m.seriesIndex, 3.0);
      expect(m.raw, isEmpty);
    });

    test('com série EPUB3, calibre:series fica em raw', () {
      final m = _parse(
        _opf(
          metadata:
              '<meta property="belongs-to-collection">EPUB3</meta>'
              '<meta name="calibre:series" content="Calibre"/>',
        ),
      ).metadata;
      expect(m.series, 'EPUB3');
      expect(m.raw['calibre:series'], ['Calibre']);
    });

    test('seriesIndex não finito (NaN, Infinity, 1e400) fica null', () {
      for (final bad in ['NaN', 'Infinity', '-Infinity', '1e400']) {
        final m = _parse(
          _opf(
            metadata:
                '<meta property="belongs-to-collection" id="c">Saga</meta>'
                '<meta refines="#c" property="group-position">$bad</meta>',
          ),
        ).metadata;
        expect(m.series, 'Saga', reason: bad);
        expect(m.seriesIndex, isNull, reason: bad);
        expect(m.raw['group-position'], [bad], reason: bad);
      }
    });

    test('group-position duplicado: só o primeiro decide; o resto em raw', () {
      final m = _parse(
        _opf(
          metadata:
              '<meta property="belongs-to-collection" id="c">Saga</meta>'
              '<meta refines="#c" property="group-position">1</meta>'
              '<meta refines="#c" property="group-position">2</meta>',
        ),
      ).metadata;
      expect(m.series, 'Saga');
      expect(m.seriesIndex, 1.0);
      expect(m.raw['group-position'], ['2']);
    });

    test('calibre:series_index inválido: null, texto em raw', () {
      final m = _parse(
        _opf(
          metadata:
              '<meta name="calibre:series" content="Discworld"/>'
              '<meta name="calibre:series_index" content="NaN"/>',
        ),
      ).metadata;
      expect(m.series, 'Discworld');
      expect(m.seriesIndex, isNull);
      expect(m.raw['calibre:series_index'], ['NaN']);
    });
  });

  group('datas', () {
    test('completa, parcial e opf:event', () {
      final m = _parse(
        _opf(
          metadata:
              '<dc:date opf:event="creation">1990</dc:date>'
              '<dc:date opf:event="publication">2001-05</dc:date>'
              '<dc:date opf:event="modification">2010-01-02</dc:date>',
        ),
      ).metadata;
      expect(m.published, DateTime.utc(2001, 5));
      expect(m.modified, DateTime.utc(2010, 1, 2));
      expect(m.raw['date'], ['1990']);
    });

    test('sem publication: o primeiro que não é modification', () {
      final m = _parse(
        _opf(
          metadata:
              '<dc:date opf:event="modification">2010</dc:date>'
              '<dc:date>1851</dc:date>',
        ),
      ).metadata;
      expect(m.published, DateTime.utc(1851));
      expect(m.modified, DateTime.utc(2010));
    });

    test('dcterms:modified vence o dc:date de modification', () {
      final m = _parse(
        _opf(
          metadata:
              '<dc:date>2018-03-27T22:02:30Z</dc:date>'
              '<dc:date opf:event="modification">2010</dc:date>'
              '<meta property="dcterms:modified">2026-08-04T14:52:50Z</meta>',
        ),
      ).metadata;
      expect(m.published, DateTime.utc(2018, 3, 27, 22, 2, 30));
      expect(m.modified, DateTime.utc(2026, 8, 4, 14, 52, 50));
      expect(m.raw['date'], ['2010']);
    });

    test('inválida fica null e o texto vai para raw', () {
      final m = _parse(
        _opf(
          metadata:
              '<dc:date>por volta de 1900</dc:date>'
              '<meta property="dcterms:modified">2020-13</meta>',
        ),
      ).metadata;
      expect(m.published, isNull);
      expect(m.modified, isNull);
      expect(m.raw['date'], ['por volta de 1900']);
      expect(m.raw['dcterms:modified'], ['2020-13']);
    });

    test('parseEpubDate: casos parciais e inválidos', () {
      expect(parseEpubDate('2020'), DateTime.utc(2020));
      expect(parseEpubDate('2020-02'), DateTime.utc(2020, 2));
      expect(parseEpubDate('2020-02-29'), DateTime.utc(2020, 2, 29));
      expect(parseEpubDate('2021-02-29'), isNull);
      expect(parseEpubDate('2021-00'), isNull);
      expect(parseEpubDate('+275760-09-14'), isNull);
      expect(parseEpubDate('9' * 100), isNull);
      expect(parseEpubDate(''), isNull);
    });

    test(
      'parseEpubDate: com hora, offset e sempre UTC (rodada de correção 1)',
      () {
        // Válidos.
        expect(
          parseEpubDate('2018-03-27T22:02:30Z'),
          DateTime.utc(2018, 3, 27, 22, 2, 30),
        );
        expect(
          parseEpubDate('2020-01-01T10:00:00'),
          DateTime.utc(2020, 1, 1, 10),
        );
        expect(parseEpubDate('2020-01-01T10:00:00')!.isUtc, isTrue);
        expect(
          parseEpubDate('2020-01-01T01:00:00+05:00'),
          DateTime.utc(2019, 12, 31, 20),
        );
        expect(
          parseEpubDate('2020-01-01T23:00:00-05:00'),
          DateTime.utc(2020, 1, 2, 4),
        );
        expect(
          parseEpubDate('2020-01-01T00:00:00+14:00'),
          DateTime.utc(2019, 12, 31, 10),
        );

        // `DateTime.parse` normalizava estes; a gramática do EPUB recusa.
        expect(parseEpubDate('2021-02-29T10:00:00Z'), isNull);
        expect(parseEpubDate('2021-13-45T10:00:00Z'), isNull);
        expect(parseEpubDate('99999-99-99'), isNull);
        expect(parseEpubDate('2020-02-29T24:00:00Z'), isNull);
        expect(parseEpubDate('2020-01-01T10:00:00+99:99'), isNull);
        expect(parseEpubDate('2020-01-01T00:00:00+14:01'), isNull);
        expect(parseEpubDate('2020-04-31'), isNull);
      },
    );
  });

  group('demais campos e raw', () {
    test('primeiro de cada, subjects todos, raw só o não mapeado', () {
      final m = _parse(
        _opf(
          metadata:
              '<dc:identifier id="uid">urn:isbn:1</dc:identifier>'
              '<dc:title>T</dc:title>'
              '<dc:language>pt-BR</dc:language>'
              '<dc:language>en</dc:language>'
              '<dc:publisher>P</dc:publisher>'
              '<dc:description> D </dc:description>'
              '<dc:rights>R</dc:rights>'
              '<dc:subject>S1</dc:subject><dc:subject>S2</dc:subject>'
              '<dc:source>fonte</dc:source>'
              '<dc:title id="alt">Outro</dc:title>'
              '<meta property="file-as" refines="#alt">Outro, O</meta>'
              '<meta name="generator" content="Sigil"/>'
              '<meta property="schema:accessMode">textual</meta>'
              '<meta property="rendition:layout">reflowable</meta>'
              '<meta name="cover" content="img"/>'
              '<link rel="x" href="y"/>',
        ),
      ).metadata;
      expect(m.title, 'T');
      expect(m.language, 'pt-BR');
      expect(m.publisher, 'P');
      expect(m.description, 'D');
      expect(m.rights, 'R');
      expect(m.subjects, ['S1', 'S2']);
      expect(m.identifier, 'urn:isbn:1');
      expect(m.raw, {
        'language': ['en'],
        'source': ['fonte'],
        'title': ['Outro'],
        'file-as': ['Outro, O'],
        'generator': ['Sigil'],
        'schema:accessMode': ['textual'],
      });
    });

    test('listas e raw são não modificáveis', () {
      final m = _parse(_opf(metadata: '<dc:creator>A</dc:creator>')).metadata;
      expect(() => m.authors.add('B'), throwsUnsupportedError);
      expect(() => m.raw['x'] = [], throwsUnsupportedError);
    });

    test('texto vem só dos filhos diretos', () {
      final m = _parse(
        _opf(
          metadata:
              '<dc:title>Fora<dc:title>Dentro</dc:title></dc:title>'
              '<dc:description><![CDATA[<p>html</p>]]></dc:description>',
        ),
      ).metadata;
      expect(m.title, 'Fora');
      expect(m.raw['title'], ['Dentro']);
      expect(m.description, '<p>html</p>');
    });

    test('meta com content vazio some do raw; property com content e sem '
        'texto usa o content', () {
      final m = _parse(
        _opf(
          metadata:
              '<meta name="e" content=""/>'
              '<meta property="x" content="y"/>',
        ),
      ).metadata;
      expect(m.raw.containsKey('e'), isFalse);
      expect(m.raw['x'], ['y']);
    });
  });

  group('identificadores', () {
    test('todos em ordem, com trim; o único pelo unique-identifier', () {
      final opf = _parse(
        _opf(
          metadata:
              '<dc:identifier>  urn:isbn:9780000000001 </dc:identifier>'
              '<dc:identifier id="uid">urn:uuid:abc</dc:identifier>',
        ),
      );
      expect(opf.identifiers, ['urn:isbn:9780000000001', 'urn:uuid:abc']);
      expect(opf.uniqueIdentifiers, ['urn:uuid:abc']);
      expect(opf.metadata.identifier, 'urn:uuid:abc');
      expect(opf.metadata.raw['identifier'], ['urn:isbn:9780000000001']);
    });

    test('sem casamento com unique-identifier: o primeiro', () {
      final opf = _parse(
        _opf(
          metadata:
              '<dc:identifier id="x">primeiro</dc:identifier>'
              '<dc:identifier>segundo</dc:identifier>',
        ),
      );
      expect(opf.uniqueIdentifiers, ['primeiro']);
    });

    test('sem dc:identifier: listas vazias', () {
      final opf = _parse(_opf());
      expect(opf.identifiers, isEmpty);
      expect(opf.uniqueIdentifiers, isEmpty);
      expect(opf.metadata.identifier, isNull);
    });
  });

  group('manifest', () {
    test('item cru: href, media-type, properties e fallback', () {
      final opf = _parse(
        _opf(
          manifest:
              '<manifest><item id="c1" href="Text/c1.xhtml" '
              'media-type="application/xhtml+xml" properties="nav  scripted" '
              'fallback="c2"/></manifest>',
        ),
      );
      final item = opf.items.single;
      expect(item.href, 'Text/c1.xhtml');
      expect(item.mediaType, 'application/xhtml+xml');
      expect(item.properties, {'nav', 'scripted'});
      expect(item.fallback, 'c2');
    });

    test('id duplicado: vale o primeiro', () {
      final opf = _parse(
        _opf(
          manifest:
              '<manifest><item id="c1" href="a.xhtml" media-type="x"/>'
              '<item id="c1" href="b.xhtml" media-type="y"/></manifest>',
        ),
      );
      expect(opf.items.map((i) => i.href), ['a.xhtml']);
    });

    test('sem id ou sem href: descartado com resourceMissing', () {
      final sink = DiagnosticSink();
      final opf = _parse(
        _opf(
          manifest:
              '<manifest><item href="a.xhtml" media-type="x"/>'
              '<item id="b" media-type="y"/>'
              '<item id="c1" href="Text/c1.xhtml" media-type="z"/></manifest>',
        ),
        sink: sink,
      );
      expect(opf.items.map((i) => i.id), ['c1']);
      final d = sink.diagnostics.single;
      expect(d.code, EpubDiagnosticCode.resourceMissing);
      expect(d.href, isNull);
      expect(d.details, {'reason': 'no-href', 'id': 'b', 'count': 2});
    });

    test('resourceMissing em strict lança EpubPackageException', () {
      expect(
        () => _parse(
          _opf(
            manifest:
                '<manifest><item href="a.xhtml"/>'
                '<item id="c1" href="c1.xhtml"/></manifest>',
          ),
          sink: DiagnosticSink(strict: true),
        ),
        throwsA(
          isA<EpubPackageException>().having(
            (e) => e.message,
            'message',
            startsWith('resourceMissing: '),
          ),
        ),
      );
    });
  });

  group('spine', () {
    const manifest =
        '<manifest>'
        '<item id="a" href="a.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="b" href="b.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>'
        '</manifest>';

    test('idref sem item, repetido e linear', () {
      final sink = DiagnosticSink();
      final opf = _parse(
        _opf(
          manifest: manifest,
          spine:
              '<spine toc="ncx"><itemref idref="a"/><itemref idref="x"/>'
              '<itemref idref="b" linear="no"/><itemref idref="a"/></spine>',
        ),
        sink: sink,
      );
      expect(opf.itemrefs.map((r) => (r.idref, r.linear)), [
        ('a', true),
        ('b', false),
      ]);
      expect(opf.spineToc, 'ncx');
      final [unresolved, duplicate] = sink.diagnostics;
      expect(unresolved.code, EpubDiagnosticCode.spineItemUnresolved);
      expect(unresolved.severity, EpubSeverity.warning);
      expect(unresolved.href, 'OEBPS/content.opf');
      expect(unresolved.details, {'idref': 'x', 'count': 1});
      expect(duplicate.code, EpubDiagnosticCode.spineItemDuplicate);
      expect(duplicate.severity, EpubSeverity.info);
      expect(duplicate.href, 'OEBPS/content.opf');
      expect(duplicate.details, {'idref': 'a', 'count': 1});
    });

    test('spineItemUnresolved em strict lança EpubPackageException', () {
      expect(
        () => _parse(
          _opf(spine: '<spine><itemref idref="nada"/></spine>'),
          sink: DiagnosticSink(strict: true),
        ),
        throwsA(
          isA<EpubPackageException>()
              .having((e) => e.href, 'href', 'OEBPS/content.opf')
              .having(
                (e) => e.message,
                'message',
                startsWith('spineItemUnresolved: '),
              ),
        ),
      );
    });

    test('page-progression-direction', () {
      EpubReadingDirection of(String attr) =>
          _parse(_opf(spine: '<spine $attr><itemref idref="c1"/></spine>'))
              .direction;
      expect(of('page-progression-direction="rtl"'), EpubReadingDirection.rtl);
      expect(of('page-progression-direction="ltr"'), EpubReadingDirection.ltr);
      expect(
        of('page-progression-direction="default"'),
        EpubReadingDirection.auto,
      );
      expect(of(''), EpubReadingDirection.auto);
    });
  });

  group('layout e guide', () {
    test('rendition:layout global pre-paginated', () {
      expect(
        _parse(
          _opf(
            metadata: '<meta property="rendition:layout">pre-paginated</meta>',
          ),
        ).layout,
        EpubLayoutMode.prePaginated,
      );
      expect(_parse(_opf()).layout, EpubLayoutMode.reflowable);
      expect(
        _parse(
          _opf(
            metadata:
                '<meta refines="#x" property="rendition:layout">'
                'pre-paginated</meta>',
          ),
        ).layout,
        EpubLayoutMode.reflowable,
        reason: 'só o global conta',
      );
    });

    test('guide: reference com href, na ordem', () {
      final opf = _parse(
        _opf(
          extra:
              '<guide><reference type="cover" title="Capa" href="capa.xhtml"/>'
              '<reference type="toc" title="Sumário"/>'
              '<reference type="text" href="Text/c1.xhtml#i"/></guide>',
        ),
      );
      expect(opf.guide.map((r) => (r.type, r.title, r.href)), [
        ('cover', 'Capa', 'capa.xhtml'),
        ('text', '', 'Text/c1.xhtml#i'),
      ]);
    });
  });

  group('fatais', () {
    Matcher fatal(String text) => throwsA(
      isA<EpubPackageException>()
          .having((e) => e.href, 'href', 'OEBPS/content.opf')
          .having((e) => e.message, 'message', contains(text)),
    );

    test('XML inválido, com a XmlException em cause', () {
      expect(
        () => _parse('<package><metadata>'),
        throwsA(
          isA<EpubPackageException>().having(
            (e) => e.cause,
            'cause',
            isNotNull,
          ),
        ),
      );
    });

    test('raiz que não é package', () {
      expect(() => _parse('<pacote/>'), fatal('não <package>'));
    });

    test('sem manifest e sem spine', () {
      expect(() => _parse('<package>$_spine</package>'), fatal('<manifest>'));
      expect(() => _parse('<package>$_manifest</package>'), fatal('<spine>'));
    });
  });

  group('foco de revisão', () {
    test('OEB 1.2: DOCTYPE externo, dc 1.0 e dc-metadata', () {
      final opf = _parse(
        '<?xml version="1.0"?>\n'
        '<!DOCTYPE package PUBLIC "+//ISBN 0-9673008-1-9//DTD OEB 1.2 '
        'Package//EN" "http://openebook.org/dtds/oeb-1.2/oebpkg12.dtd">\n'
        '<package unique-identifier="id"><metadata><dc-metadata '
        'xmlns:dc="http://purl.org/dc/elements/1.0/">'
        '<dc:Title>Velho</dc:Title><dc:Identifier id="id">oeb:1</dc:Identifier>'
        '</dc-metadata></metadata><manifest><item id="a" href="a.html" '
        'media-type="text/x-oeb1-document"/></manifest>'
        '<spine><itemref idref="a"/></spine></package>',
      );
      expect(opf.metadata.title, 'Velho');
      expect(opf.uniqueIdentifiers, ['oeb:1']);
      expect(opf.items.single.mediaType, 'text/x-oeb1-document');
    });

    test('metadata aninhado 100 000 níveis: linear, sem estouro de pilha', () {
      final deep =
          '<package><metadata>${'<dc:title>t' * 100000}'
          '${'</dc:title>' * 100000}</metadata>$_manifest$_spine</package>';
      final sw = Stopwatch()..start();
      final m = _parse(deep).metadata;
      sw.stop();
      expect(m.title, 't');
      expect(m.raw['title'], hasLength(99999));
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('id repetido: refinamentos não ficam quadráticos; só o dono usa', () {
      final buffer = StringBuffer();
      for (var i = 0; i < 20000; i++) {
        buffer.write('<dc:creator id="a">Autor $i</dc:creator>');
      }
      for (var i = 0; i < 20000; i++) {
        buffer.write('<meta refines="#a" property="role">aut</meta>');
      }
      final sw = Stopwatch()..start();
      final m = _parse(_opf(metadata: buffer.toString())).metadata;
      sw.stop();
      expect(sw.elapsed, lessThan(const Duration(seconds: 1)));
      // Todos os 20 000 creators contam como autor (sem papel refinado,
      // o padrão é autor); só o dono do `id` "a" de fato consultou os
      // refinamentos, então nenhum deles some em `raw`.
      expect(m.authors, hasLength(20000));
      expect(m.contributors, isEmpty);
      expect(m.raw.containsKey('role'), isFalse);
    });
  });
}
