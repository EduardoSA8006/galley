// loadSectionSheets, decodeCss e StyleSheetCache (spec do CSS §9): coleta,
// caminhos, leitura, codificação, @import com tetos, cache e a chave.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/css/loader.dart';
import 'package:galley/src/diagnostics/diagnostic.dart';
import 'package:galley/src/diagnostics/exceptions.dart';
import 'package:html/dom.dart';

import '../container/support/zip_fixtures.dart' show ZipLayout;
import 'support/css_fixtures.dart';

String _link(
  String href, {
  String rel = 'stylesheet',
  String? type,
  String? media,
}) =>
    '<link rel="$rel" href="$href"'
    '${type == null ? '' : ' type="$type"'}'
    '${media == null ? '' : ' media="$media"'}/>';

String _links(List<String> hrefs) => hrefs.map(_link).join();

/// Uma regra reconhecível por folha: `.nome { display: block }`.
String _rule(String name) => '.$name { display: block }';

/// Classe da primeira regra de cada folha aplicada.
List<String> _names(Loaded l) => [
  for (final s in l.sheets.sheets)
    if (s.sheet.rules.isNotEmpty)
      s.sheet.rules.first.selectors.first.rightmost.classes.first,
];

void main() {
  group('coleta (§9.1)', () {
    test(
      '<link>: rel com vários tokens, alternate, type e href vazio',
      () async {
        final l = await loadSheets(
          {
            'OEBPS/Styles/a.css': _rule('a'),
            'OEBPS/Styles/b.css': _rule('b'),
            'OEBPS/Styles/c.css': _rule('c'),
            'OEBPS/Styles/d.css': _rule('d'),
            'OEBPS/Styles/e.css': _rule('e'),
          },
          xhtml(
            head:
                _link('../Styles/a.css', rel: 'icon StyleSheet') +
                _link('../Styles/b.css', rel: 'alternate stylesheet') +
                _link('../Styles/c.css', type: 'text/css; charset=utf-8') +
                _link('../Styles/d.css', type: 'text/less') +
                _link('  ') +
                _link('../Styles/e.css', rel: 'preload'),
          ),
        );
        expect(_names(l), ['a', 'c']);
        expect(l.sink.diagnostics, isEmpty);
      },
    );

    test(
      '<link> com media que não casa: stylesheetMediaIgnored, sem fetch',
      () async {
        final l = await loadSheets({
          'OEBPS/Styles/p.css': _rule('p'),
        }, xhtml(head: _link('../Styles/p.css', media: 'print')));
        expect(l.sheets.sheets, isEmpty);
        final d = l.only(EpubDiagnosticCode.stylesheetMediaIgnored);
        expect(d.href, 'OEBPS/Styles/p.css');
        expect(d.severity, EpubSeverity.info);
        expect(d.details['media'], 'print');
        expect(l.container.totalFetches, 0);
      },
    );

    test('<style> em head, body e SVG, em ordem de documento', () async {
      final l = await loadSheets(
        {'OEBPS/Styles/l.css': _rule('l')},
        xhtml(
          head: '<style>${_rule('h')}</style>${_link('../Styles/l.css')}',
          body:
              '<p>x</p><style type="text/css">${_rule('b')}</style>'
              '<svg xmlns="http://www.w3.org/2000/svg"><style>'
              '${_rule('s')}</style></svg>',
        ),
      );
      expect(_names(l), ['h', 'l', 'b', 's']);
      expect(l.sheets.cacheKey.map((r) => r.source), [
        SheetSource.style,
        SheetSource.link,
        SheetSource.style,
        SheetSource.style,
      ]);
    });

    test('<style> e <link> dentro de <template> não contam', () async {
      final l = await loadSheets(
        {'OEBPS/Styles/t.css': _rule('t')},
        xhtml(
          body:
              '<template><style>${_rule('x')}</style>'
              '${_link('../Styles/t.css')}</template>',
        ),
      );
      expect(l.sheets.sheets, isEmpty);
      expect(l.container.totalFetches, 0);
    });

    test('<style type>: só vazio ou text/css exato, sem caixa', () async {
      final l = await loadSheets(
        const {},
        xhtml(
          head:
              '<style type="">${_rule('v')}</style>'
              '<style type="TEXT/CSS">${_rule('m')}</style>'
              '<style type="text/css; charset=utf-8">${_rule('p')}</style>'
              '<style type=" text/css ">${_rule('e')}</style>',
        ),
      );
      expect(_names(l), ['v', 'm']);
      expect(l.sink.diagnostics, isEmpty);
    });

    test('<link type>: parâmetro e espaço em volta ainda valem', () async {
      final l = await loadSheets(
        {'OEBPS/Styles/p.css': _rule('p'), 'OEBPS/Styles/e.css': _rule('e')},
        xhtml(
          head:
              _link('../Styles/p.css', type: 'text/css; charset=utf-8') +
              _link('../Styles/e.css', type: ' TEXT/CSS '),
        ),
      );
      expect(_names(l), ['p', 'e']);
    });

    test('<style> com media e type', () async {
      final l = await loadSheets(
        const {},
        xhtml(
          head:
              '<style media="print">${_rule('p')}</style>'
              '<style type="text/less">${_rule('l')}</style>'
              '<style media="not print">${_rule('n')}</style>',
        ),
      );
      expect(_names(l), ['n']);
      expect(
        l.only(EpubDiagnosticCode.stylesheetMediaIgnored).href,
        sectionPath,
      );
    });
  });

  group('<style> como dado de caractere do XML (#22)', () {
    Future<String> styleText(String raw) async {
      final l = await loadSheets(const {}, xhtml(head: '<style>$raw</style>'));
      return l.sheets.cacheKey.single.text!;
    }

    test('entidades predefinidas e numéricas', () async {
      expect(
        await styleText('div &gt; p &amp; &lt;&quot;&apos;'),
        'div > p & <"\'',
      );
      expect(await styleText('&#x2014;&#8212;'), '——');
    });

    test(
      '&#0;, surrogate e fora de faixa viram U+FFFD; sem ; fica literal',
      () async {
        expect(
          await styleText('&#0;&#xD800;&#x110000;&#99999999999999;'),
          '�' * 4,
        );
        expect(
          await styleText('&#65 &#X41; &nbsp; &foo;'),
          '&#65 &#X41; &nbsp; &foo;',
        );
      },
    );

    test('CDATA literal sem os marcadores; sem fim vai até o fim', () async {
      expect(await styleText('a<![CDATA[ &gt; ]]>b'), 'a &gt; b');
      expect(await styleText('a<![CDATA[ &gt;'), 'a &gt;');
    });

    test('<!-- --> fica para o tokenizador (cdo/cdc)', () async {
      final l = await loadSheets(
        const {},
        xhtml(head: '<style><!-- ${_rule('c')} --></style>'),
      );
      expect(_names(l), ['c']);
    });

    test('div &gt; p vira seletor de filho', () async {
      final l = await loadSheets(
        const {},
        xhtml(head: '<style>div &gt; p { display: none }</style>'),
      );
      expect(
        l.sheets.sheets.single.sheet.rules.single.selectors.single.combinators,
        hasLength(1),
      );
    });

    test('xmlCharacterData em 1 MiB de entidades: linear', () {
      final sw = Stopwatch()..start();
      expect(xmlCharacterData('&amp;' * 200000), '&' * 200000);
      expect(xmlCharacterData('&#${'1' * 1000000};'), '�');
      sw.stop();
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
    });
  });

  group('<style> acima do teto (§9.1)', () {
    test('1 Mi unidades valem; + 1 é too-large', () async {
      final ok = '/*${'x' * (maxStyleElementLength - 4)}*/';
      expect(ok.length, maxStyleElementLength);
      final l1 = await loadSheets(const {}, xhtml(head: '<style>$ok</style>'));
      expect(l1.sheets.sheets, hasLength(1));
      final l2 = await loadSheets(const {}, xhtml(head: '<style>$ok </style>'));
      expect(l2.sheets.sheets, isEmpty);
      final d = l2.only(EpubDiagnosticCode.stylesheetIgnored);
      expect((d.href, d.details['reason']), (sectionPath, 'too-large'));
    });
  });

  group('caminhos (§9.2)', () {
    test('remoto, data:, .. além da raiz: resourceMissing sem fetch', () async {
      final l = await loadSheets(
        const {},
        xhtml(
          head: _links([
            'https://x.org/a.css',
            'data:text/css,p{}',
            '../../../x.css',
          ]),
        ),
      );
      expect(l.codes, ['resourceMissing', 'resourceMissing']);
      expect(l.sink.diagnostics[0].href, 'https://x.org/a.css');
      expect(l.sink.diagnostics[0].details['reason'], 'remote');
      expect(l.sink.diagnostics[1].href, sectionPath);
      expect(l.sink.diagnostics[1].details['reason'], 'refused');
      expect(l.sink.diagnostics[1].details['count'], 2);
      expect(l.container.totalFetches, 0);
    });

    test('%20 decodificado; %2e%2e não atravessa; ausente', () async {
      final l = await loadSheets(
        {
          'OEBPS/Styles/tipo grafia.css': _rule('t'),
          'OEBPS/Styles/%2e%2e/x.css': _rule('x'),
        },
        xhtml(
          head: _links([
            '../Styles/tipo%20grafia.css',
            '../Styles/%2e%2e/x.css',
            '../Styles/nada.css',
          ]),
        ),
      );
      expect(_names(l), ['t', 'x']);
      expect(l.hrefs, [
        'OEBPS/Styles/tipo grafia.css',
        'OEBPS/Styles/%2e%2e/x.css',
      ]);
      final missing = l.only(EpubDiagnosticCode.resourceMissing);
      expect(missing.href, 'OEBPS/Styles/nada.css');
      expect(missing.details['from'], sectionPath);
    });
  });

  group('leitura (§9.3)', () {
    test('1 MiB vale; 1 MiB + 1 é too-large sem drenar o decode()', () async {
      // CRC errado nos dois: só a folha drenada emite zipCrcMismatch.
      Uint8List zip(int size) {
        final css = utf8.encode('/*${'x' * (size - 4)}*/');
        final w = ZipWriter()
          ..add(
            'mimetype',
            ascii.encode('application/epub+zip'),
            compress: false,
          )
          ..add('META-INF/container.xml', utf8.encode('<container/>'))
          ..add('OEBPS/Styles/g.css', css, crcOverride: 1)
          ..add(
            sectionPath,
            utf8.encode(xhtml(head: _link('../Styles/g.css'))),
          );
        return w.build();
      }

      for (final (size, applied, crc) in [
        (maxStyleSheetBytes, 1, true),
        (maxStyleSheetBytes + 1, 0, false),
      ]) {
        final containerSink = DiagnosticSink();
        final container = CountingContainer(
          await openZipBytes(zip(size), containerSink),
        );
        final sink = DiagnosticSink();
        final sheets = await loadSectionSheets(
          container,
          parseXhtml(xhtml(head: _link('../Styles/g.css'))),
          sectionPath: sectionPath,
          cache: StyleSheetCache(),
          sink: sink,
          containerSink: containerSink,
        );
        expect(sheets.sheets, hasLength(applied), reason: '$size');
        expect(
          containerSink.diagnostics.any(
            (d) => identical(d.code, EpubDiagnosticCode.zipCrcMismatch),
          ),
          crc,
          reason: '$size',
        );
        if (applied == 0) {
          expect(sink.diagnostics.single.details['reason'], 'too-large');
        }
        await container.close();
      }
    });

    test(
      '4 MiB por seção pelo PendingResource.size; + 1 byte é limit bytes',
      () async {
        final mib = '/*${'x' * (maxStyleSheetBytes - 4)}*/';
        final files = {
          for (var i = 0; i < 4; i++) 'OEBPS/Styles/m$i.css': mib,
          'OEBPS/Styles/um.css': ' ',
        };
        final four = await loadSheets(
          files,
          xhtml(
            head: _links([for (var i = 0; i < 4; i++) '../Styles/m$i.css']),
          ),
        );
        expect(four.sheets.sheets, hasLength(4));
        expect(four.sink.diagnostics, isEmpty);
        final over = await loadSheets(
          files,
          xhtml(
            head: _links([
              for (var i = 0; i < 4; i++) '../Styles/m$i.css',
              '../Styles/um.css',
            ]),
          ),
        );
        expect(over.sheets.sheets, hasLength(4));
        final d = over.only(EpubDiagnosticCode.stylesheetIgnored);
        expect((d.href, d.details['limit']), ('OEBPS/Styles/um.css', 'bytes'));
      },
    );

    test('o texto de <style> conta no teto de 4 MiB da seção', () async {
      final mi = '/*${'x' * (maxStyleElementLength - 4)}*/';
      final four = List.filled(4, '<style>$mi</style>').join();
      final ok = await loadSheets(const {}, xhtml(head: four));
      expect(ok.sheets.sheets, hasLength(4));
      expect(ok.sink.diagnostics, isEmpty);
      final over = await loadSheets(
        const {},
        xhtml(head: '$four<style>${_rule('a')}</style>'),
      );
      expect(over.sheets.sheets, hasLength(4));
      final d = over.only(EpubDiagnosticCode.stylesheetIgnored);
      expect((d.href, d.details['limit']), (sectionPath, 'bytes'));
    });

    test('fetch que lança: resourceUnreadable, e a folha é pulada', () async {
      final containerSink = DiagnosticSink();
      final provider = MapProvider(
        {'OEBPS/Styles/r.css': _rule('r'), sectionPath: ''},
        failingRead: {'OEBPS/Styles/r.css'},
      );
      final container = CountingContainer(
        await openProvider(provider, containerSink),
      );
      final sink = DiagnosticSink();
      final sheets = await loadSectionSheets(
        container,
        parseXhtml(xhtml(head: _link('../Styles/r.css'))),
        sectionPath: sectionPath,
        cache: StyleSheetCache(),
        sink: sink,
        containerSink: containerSink,
      );
      expect(sheets.sheets, isEmpty);
      final d = sink.diagnostics.single;
      expect(d.code, EpubDiagnosticCode.resourceUnreadable);
      expect(d.details['reason'], 'unreadable');
      expect(d.details['exception'], contains('read falhou'));
    });
  });

  group('ilegível (§9.3)', () {
    test('resourceUnreadable tem o href do candidato que falhou', () async {
      final containerSink = DiagnosticSink();
      // O decodificado (r x.css) não existe; o normalizado falha na leitura.
      final provider = MapProvider(
        {'OEBPS/Styles/r%20x.css': _rule('r'), sectionPath: ''},
        failingRead: {'OEBPS/Styles/r%20x.css'},
      );
      final container = CountingContainer(
        await openProvider(provider, containerSink),
      );
      final sink = DiagnosticSink();
      final sheets = await loadSectionSheets(
        container,
        parseXhtml(xhtml(head: _link('../Styles/r%20x.css'))),
        sectionPath: sectionPath,
        cache: StyleSheetCache(),
        sink: sink,
        containerSink: containerSink,
      );
      expect(sheets.sheets, isEmpty);
      expect(container.fetches.keys, [
        'OEBPS/Styles/r x.css',
        'OEBPS/Styles/r%20x.css',
      ]);
      final d = sink.diagnostics.single;
      expect(d.code, EpubDiagnosticCode.resourceUnreadable);
      expect(d.href, 'OEBPS/Styles/r%20x.css');
    });

    test('decode() que lança sem strict (deflate inválido)', () async {
      final w = ZipWriter()
        ..add('mimetype', ascii.encode('application/epub+zip'), compress: false)
        ..add('META-INF/container.xml', utf8.encode('<container/>'))
        ..add('OEBPS/Styles/d.css', utf8.encode(_rule('d') * 20));
      final zip = w.build();
      // BFINAL = 1 e BTYPE = 11 (reservado) no primeiro byte do payload.
      final at = ZipLayout(zip).local[2] + 30 + 'OEBPS/Styles/d.css'.length;
      zip[at] = 0xFF;
      final containerSink = DiagnosticSink();
      final container = await openZipBytes(zip, containerSink);
      final sink = DiagnosticSink();
      final sheets = await loadSectionSheets(
        container,
        parseXhtml(xhtml(head: _link('../Styles/d.css'))),
        sectionPath: sectionPath,
        cache: StyleSheetCache(),
        sink: sink,
        containerSink: containerSink,
      );
      expect(sheets.sheets, isEmpty);
      final d = sink.diagnostics.single;
      expect(d.code, EpubDiagnosticCode.resourceUnreadable);
      expect(d.href, 'OEBPS/Styles/d.css');
      expect(d.details['reason'], 'unreadable');
      await container.close();
    });
  });

  group('strict (§9, §12.3)', () {
    test('a exceção do sink do contêiner propaga por identidade', () async {
      final containerSink = DiagnosticSink(strict: true);
      final w = ZipWriter()
        ..add('mimetype', ascii.encode('application/epub+zip'), compress: false)
        ..add('META-INF/container.xml', utf8.encode('<container/>'))
        ..add('OEBPS/Styles/c.css', utf8.encode(_rule('c')), crcOverride: 7);
      final container = await openZipBytes(w.build(), containerSink);
      final sink = DiagnosticSink(strict: true);
      await expectLater(
        loadSectionSheets(
          container,
          parseXhtml(xhtml(head: _link('../Styles/c.css'))),
          sectionPath: sectionPath,
          cache: StyleSheetCache(),
          sink: sink,
          containerSink: containerSink,
        ),
        throwsA(
          allOf(
            isA<EpubContainerException>(),
            predicate(
              (Object e) => identical(e, containerSink.lastStrictException),
            ),
          ),
        ),
      );
      expect(sink.diagnostics, isEmpty, reason: 'não vira resourceUnreadable');
      await container.close();
    });

    test(
      'warning do CSS lança EpubSectionParseException pelo sink da seção',
      () async {
        await expectLater(
          loadSheets(
            const {},
            xhtml(head: _link('../Styles/nada.css')),
            strict: true,
          ),
          throwsA(
            isA<EpubSectionParseException>()
                .having(
                  (e) => e.message,
                  'message',
                  startsWith('resourceMissing: '),
                )
                .having((e) => e.href, 'href', 'OEBPS/Styles/nada.css'),
          ),
        );
      },
    );

    test('info não lança em strict', () async {
      final l = await loadSheets(
        {'OEBPS/Styles/a.css': '@media print { p { } } :foo { }'},
        xhtml(head: _link('../Styles/a.css')),
        strict: true,
      );
      expect(l.codes, ['stylesheetMediaIgnored', 'cssRuleIgnored']);
    });
  });

  group('decodeCss (§9.4)', () {
    String decode(List<int> bytes, [DiagnosticSink? sink]) => decodeCss(
      Uint8List.fromList(bytes),
      path: 'a.css',
      sink: sink ?? DiagnosticSink(),
    );

    test('BOM UTF-8, UTF-16 LE e BE, e o BOM sai', () {
      expect(decode([0xEF, 0xBB, 0xBF, ...utf8.encode('ção')]), 'ção');
      expect(decode([0xFF, 0xFE, 0x61, 0x00, 0xE7, 0x00]), 'aç');
      expect(decode([0xFE, 0xFF, 0x00, 0x61, 0x00, 0xE7]), 'aç');
    });

    test('@charset Latin-1 na forma exata', () {
      expect(
        decode([...ascii.encode('@charset "ISO-8859-1"; .'), 0xE7, 0xE3]),
        '@charset "ISO-8859-1"; .çã',
      );
      expect(
        decode([...ascii.encode('@charset "windows-1252";'), 0xE9]),
        endsWith('é'),
      );
    });

    test("@charset 'x', sem espaço ou depois de outro byte não conta", () {
      for (final head in [
        "@charset 'iso-8859-1';",
        '@charset  "iso-8859-1";',
        '@charset"iso-8859-1";',
        ' @charset "iso-8859-1";',
        '@CHARSET "iso-8859-1";',
      ]) {
        final sink = DiagnosticSink();
        final text = decode([...ascii.encode(head), 0xE7], sink);
        expect(text, endsWith('ç'), reason: head);
        expect(
          sink.diagnostics.single.code,
          EpubDiagnosticCode.encodingFallback,
        );
      }
    });

    test('@charset "utf-16" sem BOM vale como UTF-8', () {
      final sink = DiagnosticSink();
      expect(
        decode(utf8.encode('@charset "utf-16"; ç'), sink),
        '@charset "utf-16"; ç',
      );
      expect(sink.diagnostics, isEmpty);
    });

    test('UTF-8 inválido cai para Latin-1 com encodingFallback', () {
      final sink = DiagnosticSink();
      expect(decode([0x2E, 0xE7, 0xE3], sink), '.çã');
      final d = sink.diagnostics.single;
      expect(d.code, EpubDiagnosticCode.encodingFallback);
      expect(d.details['declared'], isNull);
      expect(d.details['used'], 'latin1');
    });

    test('UTF-16 com número ímpar de bytes cai para Latin-1', () {
      final sink = DiagnosticSink();
      decode([0xFF, 0xFE, 0x61], sink);
      expect(sink.diagnostics.single.details['declared'], 'utf-16le');
    });

    test('rótulo depois do byte 1 024 não conta', () {
      final sink = DiagnosticSink();
      decode([...ascii.encode('@charset "${'x' * 1020}latin1";'), 0xE7], sink);
      expect(sink.diagnostics, hasLength(1));
    });
  });

  group('@import (§9.5)', () {
    test(
      'relativo à folha que importa; em <style>, relativo à seção',
      () async {
        final l = await loadSheets(
          {
            'OEBPS/Styles/main.css': '@import "base/b.css"; ${_rule('main')}',
            'OEBPS/Styles/base/b.css':
                '@import "../extra/e.css"; ${_rule('b')}',
            'OEBPS/Styles/extra/e.css': _rule('e'),
            'OEBPS/Text/s.css': _rule('s'),
          },
          xhtml(
            head:
                '${_link('../Styles/main.css')}'
                '<style>@import "s.css"; ${_rule('st')}</style>',
          ),
        );
        expect(_names(l), ['e', 'b', 'main', 's', 'st']);
        expect(l.sheets.cacheKey.map((r) => r.source), [
          SheetSource.import,
          SheetSource.import,
          SheetSource.link,
          SheetSource.import,
          SheetSource.style,
        ]);
        expect(l.sink.diagnostics, isEmpty);
      },
    );

    test('a mesma folha importada duas vezes aplica duas vezes', () async {
      final l = await loadSheets({
        'OEBPS/Styles/a.css': '@import "x.css"; @import "x.css"; ${_rule('a')}',
        'OEBPS/Styles/x.css': _rule('x'),
      }, xhtml(head: _link('../Styles/a.css')));
      expect(_names(l), ['x', 'x', 'a']);
      expect(l.container.fetches['OEBPS/Styles/x.css'], 1);
    });

    test('ciclo a → b → a: cycle antes do fetch', () async {
      final l = await loadSheets({
        'OEBPS/Styles/a.css': '@import "b.css"; ${_rule('a')}',
        'OEBPS/Styles/b.css': '@import "A.css"; ${_rule('b')}',
      }, xhtml(head: _link('../Styles/a.css')));
      expect(_names(l), ['b', 'a']);
      final d = l.only(EpubDiagnosticCode.stylesheetIgnored);
      expect(d.details['reason'], 'cycle');
      expect(d.details['from'], 'OEBPS/Styles/b.css');
      expect(l.container.totalFetches, 2);
    });

    test('profundidade 8 vale; 9 é depth, sem fetch', () async {
      Map<String, Object?> chain(int levels) => {
        for (var i = 0; i < levels; i++)
          'OEBPS/Styles/c$i.css': '@import "c${i + 1}.css"; ${_rule('c$i')}',
        'OEBPS/Styles/c$levels.css': _rule('c$levels'),
      };
      final ok = await loadSheets(
        chain(8),
        xhtml(head: _link('../Styles/c0.css')),
      );
      expect(ok.sheets.sheets, hasLength(9));
      expect(ok.sink.diagnostics, isEmpty);
      final deep = await loadSheets(
        chain(9),
        xhtml(head: _link('../Styles/c0.css')),
      );
      expect(deep.sheets.sheets, hasLength(9));
      final d = deep.only(EpubDiagnosticCode.stylesheetIgnored);
      expect((d.href, d.details['reason']), ('OEBPS/Styles/c9.css', 'depth'));
      expect(
        deep.container.fetches.containsKey('OEBPS/Styles/c9.css'),
        isFalse,
      );
    });

    test('@import com layer: unsupported-import com o href da folha', () async {
      final l = await loadSheets({
        'OEBPS/Styles/a.css': '@import "x.css" layer(base); ${_rule('a')}',
        'OEBPS/Styles/x.css': _rule('x'),
      }, xhtml(head: _link('../Styles/a.css')));
      expect(_names(l), ['a']);
      final d = l.only(EpubDiagnosticCode.stylesheetIgnored);
      expect(d.href, 'OEBPS/Styles/a.css');
      expect(d.details['reason'], 'unsupported-import');
      expect(d.details['import'], 'x.css');
    });

    test('@import com media que não casa: href é a folha importada', () async {
      final l = await loadSheets({
        'OEBPS/Styles/a.css': '@import url(sub/x.css) print; ${_rule('a')}',
      }, xhtml(head: _link('../Styles/a.css')));
      final d = l.only(EpubDiagnosticCode.stylesheetMediaIgnored);
      expect(d.href, 'OEBPS/Styles/sub/x.css');
      expect(l.container.totalFetches, 1);
    });
  });

  group('tetos (§9.5)', () {
    test('64 folhas contando <link> e <style>; a 65ª é limit sheets', () async {
      final files = {
        for (var i = 0; i < 40; i++) 'OEBPS/Styles/f$i.css': _rule('f$i'),
      };
      final l = await loadSheets(
        files,
        xhtml(
          head:
              _links([for (var i = 0; i < 40; i++) '../Styles/f$i.css']) +
              List.generate(25, (i) => '<style>${_rule('s$i')}</style>').join(),
        ),
      );
      expect(l.sheets.sheets, hasLength(maxSheetsPerSection));
      expect(_names(l).last, 's23');
      final d = l.only(EpubDiagnosticCode.stylesheetIgnored);
      expect((d.href, d.details['limit']), (sectionPath, 'sheets'));
    });

    test(
      'cadeia de 8 @import a partir da 60ª folha: a reserva segura em 64',
      () async {
        final files = <String, Object?>{
          for (var i = 0; i < 59; i++) 'OEBPS/Styles/f$i.css': _rule('f$i'),
          for (var i = 0; i < 8; i++)
            'OEBPS/Styles/c$i.css': '@import "c${i + 1}.css"; ${_rule('c$i')}',
          'OEBPS/Styles/c8.css': _rule('c8'),
        };
        final l = await loadSheets(
          files,
          xhtml(
            head: _links([
              for (var i = 0; i < 59; i++) '../Styles/f$i.css',
              '../Styles/c0.css',
            ]),
          ),
        );
        expect(l.sheets.sheets, hasLength(maxSheetsPerSection));
        expect(l.sheets.cacheKey, hasLength(maxSheetsPerSection));
        // c0…c4 couberam; c5 bateu no teto com as vagas de c0…c4 em andamento.
        expect(_names(l).skip(59), ['c4', 'c3', 'c2', 'c1', 'c0']);
        final d = l.only(EpubDiagnosticCode.stylesheetIgnored);
        expect((d.href, d.details['limit']), ('OEBPS/Styles/c5.css', 'sheets'));
      },
    );

    test('256 tentativas; a 257ª é limit attempts, uma vez', () async {
      final l = await loadSheets({
        'OEBPS/Styles/a.css': '@import "nada.css";\n' * 300,
      }, xhtml(head: _link('../Styles/a.css')));
      final limit = l.sink.diagnostics.where(
        (d) => identical(d.code, EpubDiagnosticCode.stylesheetIgnored),
      );
      expect(limit.single.details['limit'], 'attempts');
      expect(l.only(EpubDiagnosticCode.resourceMissing).details['count'], 255);
      expect(l.container.fetches['OEBPS/Styles/nada.css'], 1);
    });
  });

  group('cache (§9.6)', () {
    test(
      'mesma folha em duas seções: um fetch, os mesmos diagnósticos do CSS',
      () async {
        final containerSink = DiagnosticSink();
        final container = await openCounting({
          // Latin-1 inválido em UTF-8, uma regra inválida e a caixa trocada.
          'OEBPS/Styles/Main.css': [
            ...ascii.encode(':foo { } .a { display: block } /*'),
            0xE7,
            ...ascii.encode('*/'),
          ],
        }, containerSink: containerSink);
        final cache = StyleSheetCache();
        final sinks = <DiagnosticSink>[];
        for (final section in ['OEBPS/Text/c1.xhtml', 'OEBPS/Text/c2.xhtml']) {
          final sink = DiagnosticSink();
          sinks.add(sink);
          final sheets = await loadSectionSheets(
            container,
            parseXhtml(xhtml(head: _link('../Styles/main.css'))),
            sectionPath: section,
            cache: cache,
            sink: sink,
            containerSink: containerSink,
          );
          expect(sheets.sheets.single.href, 'OEBPS/Styles/Main.css');
        }
        expect(container.totalFetches, 1);
        for (final sink in sinks) {
          expect(
            [for (final d in sink.diagnostics) '${d.code.name} ${d.href}'],
            [
              'encodingFallback OEBPS/Styles/Main.css',
              'cssRuleIgnored OEBPS/Styles/Main.css',
            ],
          );
        }
        expect(containerSink.diagnostics.map((d) => d.code), [
          EpubDiagnosticCode.pathCaseMismatch,
        ]);
        await container.close();
      },
    );

    test(
      'entradas negativas: um fetch por publicação, diagnóstico por seção',
      () async {
        final containerSink = DiagnosticSink();
        // Um provider que falha na leitura de bad.css.
        final failing = CountingContainer(
          await openProvider(
            MapProvider(
              {
                'OEBPS/Styles/big.css': ' ' * (maxStyleSheetBytes + 1),
                'OEBPS/Styles/bad.css': _rule('x'),
              },
              failingRead: {'OEBPS/Styles/bad.css'},
            ),
            containerSink,
          ),
        );
        final cache = StyleSheetCache();
        for (var i = 0; i < 3; i++) {
          final sink = DiagnosticSink();
          await loadSectionSheets(
            failing,
            parseXhtml(
              xhtml(
                head: _links([
                  '../Styles/nada.css',
                  '../Styles/big.css',
                  '../Styles/bad.css',
                ]),
              ),
            ),
            sectionPath: 'OEBPS/Text/c$i.xhtml',
            cache: cache,
            sink: sink,
            containerSink: containerSink,
          );
          expect(
            [for (final d in sink.diagnostics) d.code.name],
            ['resourceMissing', 'stylesheetIgnored', 'resourceUnreadable'],
          );
        }
        expect(failing.fetches, {
          'OEBPS/Styles/nada.css': 1,
          'OEBPS/Styles/big.css': 1,
          'OEBPS/Styles/bad.css': 1,
        });
        await failing.close();
      },
    );

    test(
      'borda exata do cache: peso igual ao teto entra; um a mais, não',
      () async {
        // O peso é a chave (o caminho pedido) mais o fonte, e o caminho
        // real da entrada positiva (§9.6).
        const igual = 'OEBPS/Styles/igual.css'; // 22 unidades
        const mais = 'OEBPS/Styles/mais.css'; // 21 unidades
        final cache = StyleSheetCache(maxSource: 2 * 22 + 40);
        final containerSink = DiagnosticSink();
        final container = await openCounting({
          igual: '/*${'a' * 36}*/', // 40 unidades: pesa 84, o teto
          mais: '/*${'b' * 39}*/', // 43 unidades: pesa 85
        }, containerSink: containerSink);
        for (var i = 0; i < 2; i++) {
          for (final name in ['igual', 'mais']) {
            await loadSectionSheets(
              container,
              parseXhtml(xhtml(head: _link('../Styles/$name.css'))),
              sectionPath: sectionPath,
              cache: cache,
              sink: DiagnosticSink(),
              containerSink: containerSink,
            );
          }
        }
        expect(container.fetches['OEBPS/Styles/igual.css'], 1);
        expect(container.fetches['OEBPS/Styles/mais.css'], 2);
        await container.close();
      },
    );

    test(
      'LRU pelo tamanho do fonte; folha maior que o teto não entra',
      () async {
        // Cada folha pesa 2 × 18 (chave e caminho real) + 40 = 76.
        final cache = StyleSheetCache(maxSource: 200);
        final files = {
          'OEBPS/Styles/a.css': '/*${'a' * 36}*/', // 40 unidades
          'OEBPS/Styles/b.css': '/*${'b' * 36}*/',
          'OEBPS/Styles/c.css': '/*${'c' * 36}*/',
          'OEBPS/Styles/g.css': '/*${'g' * 200}*/',
        };
        final containerSink = DiagnosticSink();
        final container = await openCounting(
          files,
          containerSink: containerSink,
        );
        Future<void> load(String name) => loadSectionSheets(
          container,
          parseXhtml(xhtml(head: _link('../Styles/$name.css'))),
          sectionPath: sectionPath,
          cache: cache,
          sink: DiagnosticSink(),
          containerSink: containerSink,
        );
        await load('a');
        await load('b');
        expect(cache.sourceUnits, 152);
        await load('a'); // a fica mais recente
        await load('c'); // 228 > 200: sai b, o mais antigo
        expect(cache.sourceUnits, 152);
        await load('a');
        await load('b');
        expect(container.fetches['OEBPS/Styles/a.css'], 1);
        expect(container.fetches['OEBPS/Styles/b.css'], 2);
        await load('g');
        await load('g');
        expect(container.fetches['OEBPS/Styles/g.css'], 2);
        await container.close();
      },
    );
  });

  group('chave (§9.7)', () {
    test(
      'cacheKey com caminho real e hash dos bytes crus; <style> com texto',
      () async {
        final l = await loadSheets({
          'OEBPS/Styles/a.css': 'a',
        }, xhtml(head: '${_link('../Styles/a.css')}<style>p{}</style>'));
        expect(l.sheets.cacheKey, [
          const SheetRef.file(
            SheetSource.link,
            path: 'OEBPS/Styles/a.css',
            bytesHash: 'af63dc4c8601ec8c',
          ),
          const SheetRef.style('p{}'),
        ]);
        expect(
          () => l.sheets.cacheKey.add(const SheetRef.style('x')),
          throwsUnsupportedError,
        );
      },
    );
  });

  group('foco de revisão', () {
    test('href com ?query e #fragmento carrega a folha', () async {
      final l = await loadSheets({
        'OEBPS/Styles/a.css': _rule('a'),
        'OEBPS/Styles/b.css': _rule('b'),
      }, xhtml(head: _links(['../Styles/a.css?v=3', '../Styles/b.css#x'])));
      expect(_names(l), ['a', 'b']);
      expect(l.sink.diagnostics, isEmpty);
    });

    test('@import do Google Fonts: sem fetch, resourceMissing remote, o resto '
        'da folha vale; em strict, lança', () async {
      final files = {
        'OEBPS/Styles/a.css':
            '@import url(https://fonts.googleapis.com/css?family=Lora); '
            '${_rule('a')}',
      };
      final section = xhtml(head: _link('../Styles/a.css'));
      final l = await loadSheets(files, section);
      expect(_names(l), ['a']);
      final d = l.only(EpubDiagnosticCode.resourceMissing);
      expect(d.href, 'https://fonts.googleapis.com/css?family=Lora');
      expect(d.details['reason'], 'remote');
      expect(l.container.totalFetches, 1);
      await expectLater(
        loadSheets(files, section, strict: true),
        throwsA(isA<EpubSectionParseException>()),
      );
    });

    test('valores de atributo em maiúsculas: REL, TYPE e media', () async {
      final l = await loadSheets(
        {'OEBPS/Styles/a.css': _rule('a')},
        xhtml(
          head:
              '<LINK REL="StyleSheet" TYPE="TEXT/CSS" MEDIA="SCREEN" '
              'HREF="../Styles/a.css"/><STYLE TYPE="Text/Css">${_rule('s')}'
              '</STYLE>',
        ),
      );
      expect(_names(l), ['a', 's']);
    });

    test('o idioma /*<![CDATA[*/ … /*]]>*/ do XHTML', () async {
      final l = await loadSheets(
        const {},
        xhtml(head: '<style>/*<![CDATA[*/ ${_rule('c')} /*]]>*/</style>'),
      );
      expect(_names(l), ['c']);
      expect(l.sheets.sheets.single.sheet.issues, isEmpty);
    });
  });

  group('hostis (§14.3): linear', () {
    void linear(String name, Future<void> Function() body) {
      test(name, () async {
        final sw = Stopwatch()..start();
        await body();
        sw.stop();
        expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
      });
    }

    linear(
      '@import em leque: cada folha importa a seguinte duas vezes',
      () async {
        final l = await loadSheets({
          for (var i = 0; i < 20; i++)
            'OEBPS/Styles/f$i.css':
                '@import "f${i + 1}.css"; @import "f${i + 1}.css";',
          'OEBPS/Styles/f20.css': '',
        }, xhtml(head: _link('../Styles/f0.css')));
        expect(l.sheets.sheets, hasLength(maxSheetsPerSection));
        expect(l.container.totalFetches, lessThanOrEqualTo(21));
      },
    );

    linear('250 000 @import de um ausente e de um acima de 1 MiB', () async {
      // Cinco <style> de 750 000 unidades (o teto é por <style>), cada um com
      // 50 000 @import: todos são tentados, e só 256 tentativas contam.
      for (final target in ['n.css', 'b.css']) {
        final l = await loadSheets(
          {'OEBPS/Text/b.css': ' ' * (maxStyleSheetBytes + 1)},
          xhtml(
            head: List.filled(
              5,
              '<style>${'@import"$target";' * 50000}</style>',
            ).join(),
          ),
        );
        final limit = l.sink.diagnostics.where(
          (d) => d.details['limit'] == 'attempts',
        );
        expect(limit, hasLength(1), reason: target);
        expect(l.container.fetches['OEBPS/Text/$target'], 1, reason: target);
        expect(l.sheets.sheets, hasLength(5), reason: target);
      }
    });

    linear('faltas distintas de caminho longo: o cache fica no teto', () async {
      const maxSource = 256 * 1024;
      final cache = StyleSheetCache(maxSource: maxSource);
      final containerSink = DiagnosticSink();
      final container = await openCounting(
        const {},
        containerSink: containerSink,
      );
      final long = 'x' * 4096;
      var peak = 0;
      for (var s = 0; s < 20; s++) {
        final sink = DiagnosticSink();
        await loadSectionSheets(
          container,
          parseXhtml(
            xhtml(
              head: _links([
                for (var i = 0; i < maxSheetAttemptsPerSection; i++)
                  '../Styles/$long-$s-$i.css',
              ]),
            ),
          ),
          sectionPath: sectionPath,
          cache: cache,
          sink: sink,
          containerSink: containerSink,
        );
        expect(sink.diagnostics.map((d) => d.code).toSet(), {
          EpubDiagnosticCode.resourceMissing,
        });
        if (cache.sourceUnits > peak) peak = cache.sourceUnits;
        expect(cache.sourceUnits, lessThanOrEqualTo(maxSource));
      }
      // Cada falta pesa a chave (> 4 KiB): cabem menos de 64 de uma vez.
      expect(peak, greaterThan(maxSource - 8192));
      expect(cache.length, lessThan(maxSource ~/ 4096));
      await container.close();
    });

    linear('folha vazia ligada por 100 000 <link>', () async {
      final containerSink = DiagnosticSink();
      final container = await openCounting({
        'OEBPS/Styles/v.css': '',
      }, containerSink: containerSink);
      final document = parseXhtml(xhtml());
      final head = document.head!;
      for (var i = 0; i < 100000; i++) {
        head.append(
          Element.tag('link')
            ..attributes['rel'] = 'stylesheet'
            ..attributes['href'] = '../Styles/v.css',
        );
      }
      final sink = DiagnosticSink();
      final sheets = await loadSectionSheets(
        container,
        document,
        sectionPath: sectionPath,
        cache: StyleSheetCache(),
        sink: sink,
        containerSink: containerSink,
      );
      expect(sheets.cacheKey, hasLength(maxSheetsPerSection));
      expect(container.totalFetches, 1);
      await container.close();
    });
  });
}
