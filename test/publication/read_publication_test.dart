// readPublication sobre EPUBs montados e sobre ProviderContainer (spec da
// Publicação §5.3, §5.4, §6.4, §7.4, §7.5, §8.1 e §9).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/container/byte_source.dart';
import 'package:galley/src/container/container.dart';
import 'package:galley/src/container/provider_container.dart';
import 'package:galley/src/container/zip/zip_container.dart';
import 'package:galley/src/diagnostics/diagnostic.dart';
import 'package:galley/src/diagnostics/exceptions.dart';
import 'package:galley/src/publication/model.dart';
import 'package:galley/src/publication/read_publication.dart';

import 'support/epub_fixtures.dart';

/// Livro mínimo: dois capítulos, NAV e NCX; [files] substitui ou acrescenta
/// (valor `null` remove).
Map<String, Object?> _book([Map<String, Object?> files = const {}]) => {
  'OEBPS/content.opf': opfXml(
    items: [
      item('nav', 'nav.xhtml', properties: 'nav'),
      item('ncx', 'toc.ncx', mediaType: ncxType),
      item('c1', 'Text/c1.xhtml'),
      item('c2', 'Text/c2.xhtml'),
    ],
    itemrefs: [itemref('c1'), itemref('c2')],
    spineAttributes: ' toc="ncx"',
  ),
  'OEBPS/nav.xhtml': navXml(
    tocNav([('Um', 'Text/c1.xhtml'), ('Dois', 'Text/c2.xhtml')]),
  ),
  'OEBPS/toc.ncx': ncxXml([('Um (NCX)', 'Text/c1.xhtml')]),
  'OEBPS/Text/c1.xhtml': chapter,
  'OEBPS/Text/c2.xhtml': chapter,
  ...files,
};

Future<(EpubPublication, DiagnosticSink)> _read(
  Map<String, Object?> files, {
  bool strict = false,
}) async {
  final sink = DiagnosticSink(strict: strict);
  final container = await openZip(files, sink: sink);
  try {
    return (await readPublication(container, sink: sink), sink);
  } finally {
    await container.close();
  }
}

List<String> _codes(DiagnosticSink sink) => [
  for (final d in sink.diagnostics) d.code.name,
];

EpubDiagnostic _only(DiagnosticSink sink, EpubDiagnosticCode code) =>
    sink.diagnostics.singleWhere((d) => identical(d.code, code));

void main() {
  group('livro bem formado', () {
    test('modelo completo, sem diagnóstico, strict', () async {
      final (p, sink) = await _read(_book(), strict: true);
      expect(sink.diagnostics, isEmpty);
      expect(p.opfPath, 'OEBPS/content.opf');
      expect(p.version, '3.0');
      expect(p.metadata.title, 'Teste');
      expect(p.uniqueIdentifiers, ['urn:uuid:teste']);
      expect(p.identifiers, ['urn:uuid:teste']);
      expect(p.manifest.keys, ['nav', 'ncx', 'c1', 'c2']);
      expect(p.spine.map((s) => s.item.path), [
        'OEBPS/Text/c1.xhtml',
        'OEBPS/Text/c2.xhtml',
      ]);
      expect(p.spine.first.kind, SectionKind.xhtml);
      expect(p.toc.map((e) => (e.title, e.target)), [
        ('Um', const NavTarget('OEBPS/Text/c1.xhtml')),
        ('Dois', const NavTarget('OEBPS/Text/c2.xhtml')),
      ]);
      expect(p.navPath, 'OEBPS/nav.xhtml');
      // Sem page-list no NAV, o NCX é lido (e não tem page-list).
      expect(p.ncxPath, 'OEBPS/toc.ncx');
      expect(p.pageList, isEmpty);
      expect(p.direction, EpubReadingDirection.auto);
      expect(p.layout, EpubLayoutMode.reflowable);
      expect(p.coverPath, isNull);
    });

    test('coleções não modificáveis e o contêiner continua aberto', () async {
      final sink = DiagnosticSink();
      final container = await openZip(_book(), sink: sink);
      final p = await readPublication(container, sink: sink);
      expect(() => p.spine.clear(), throwsUnsupportedError);
      expect(() => p.manifest.clear(), throwsUnsupportedError);
      expect(
        () => p.toc.first.children.add(p.toc.first),
        throwsUnsupportedError,
      );
      expect(await container.exists('OEBPS/Text/c1.xhtml'), isTrue);
      await container.close();
    });
  });

  group('caminhos do manifest (§5.3)', () {
    test('tentativa dupla: decodificado, cru e nenhum', () async {
      final (p, sink) = await _read(
        _book({
          'OEBPS/content.opf': opfXml(
            items: [
              item('dec', 'Text/cap%C3%ADtulo%201.xhtml'),
              item('cru', 'Text/100%25.xhtml'),
              item('nada', 'Text/n%C3%A3o.xhtml'),
            ],
            itemrefs: [itemref('dec'), itemref('cru'), itemref('nada')],
          ),
          'OEBPS/Text/capítulo 1.xhtml': chapter,
          'OEBPS/Text/100%25.xhtml': chapter,
        }),
      );
      expect(p.manifest['dec']!.path, 'OEBPS/Text/capítulo 1.xhtml');
      expect(p.manifest['dec']!.missing, isFalse);
      expect(p.manifest['cru']!.path, 'OEBPS/Text/100%25.xhtml');
      expect(p.manifest['cru']!.missing, isFalse);
      expect(p.manifest['nada']!.path, 'OEBPS/Text/não.xhtml');
      expect(p.manifest['nada']!.missing, isTrue);
      final d = _only(sink, EpubDiagnosticCode.resourceMissing);
      expect(d.href, 'OEBPS/Text/não.xhtml');
      expect(d.details, {'id': 'nada', 'count': 1});
      expect(p.spine, hasLength(3), reason: 'item missing fica no spine');
    });

    test('%2e%2e não atravessa a raiz: vale a forma crua', () async {
      final (p, sink) = await _read(
        _book({
          'OEBPS/content.opf': opfXml(
            items: [
              item('c1', 'Text/c1.xhtml'),
              item('fora', '%2e%2e/%2e%2e/segredo.xhtml'),
            ],
            itemrefs: [itemref('c1')],
          ),
          'segredo.xhtml': chapter,
        }),
      );
      final fora = p.manifest['fora']!;
      expect(fora.path, 'OEBPS/%2e%2e/%2e%2e/segredo.xhtml');
      expect(fora.missing, isTrue);
      expect(_codes(sink), ['resourceMissing', 'tocReconciled']);
    });

    test('href recusado: path cru, resourceMissing sem href', () async {
      final (p, sink) = await _read(
        _book({
          'OEBPS/content.opf': opfXml(
            items: [
              item('c1', 'Text/c1.xhtml'),
              item('fora', '../../fora.xhtml'),
              item('mail', 'mailto:x@y.z'),
            ],
            itemrefs: [itemref('c1')],
          ),
        }),
      );
      expect(p.manifest['fora']!.path, '../../fora.xhtml');
      expect(p.manifest['fora']!.missing, isTrue);
      expect(p.manifest['mail']!.missing, isTrue);
      final d = _only(sink, EpubDiagnosticCode.resourceMissing);
      expect(d.href, isNull);
      expect(d.details, {'id': 'mail', 'raw': 'mailto:x@y.z', 'count': 2});
    });

    test('remote: sem diagnóstico, nunca missing', () async {
      final (p, sink) = await _read(
        _book({
          'OEBPS/content.opf': opfXml(
            items: [
              item('c1', 'Text/c1.xhtml'),
              item('audio', 'https://ex.com/a.mp3', mediaType: 'audio/mpeg'),
            ],
            itemrefs: [itemref('c1')],
          ),
        }),
      );
      final audio = p.manifest['audio']!;
      expect(audio.remote, isTrue);
      expect(audio.missing, isFalse);
      expect(audio.path, 'https://ex.com/a.mp3');
      expect(_codes(sink), ['tocReconciled'], reason: 'sem NAV no OPF');
    });

    test('item que é o próprio OPF ou um diretório é missing', () async {
      final (p, sink) = await _read(
        _book({
          'OEBPS/content.opf': opfXml(
            items: [
              item('c1', 'Text/c1.xhtml'),
              item(
                'opf',
                'content.opf',
                mediaType: 'application/oebps-package+xml',
              ),
              item('dir', 'Text/'),
            ],
            itemrefs: [itemref('c1')],
          ),
        }),
      );
      expect(p.manifest['opf']!.missing, isTrue);
      expect(p.manifest['dir']!.missing, isTrue);
      expect(
        sink.diagnostics
            .where((d) => identical(d.code, EpubDiagnosticCode.resourceMissing))
            .map((d) => (d.href, d.details['reason'])),
        [('OEBPS/content.opf', 'opf'), ('OEBPS/Text', 'directory')],
      );
    });

    test('media-type em minúsculas e sem parâmetros', () async {
      final (p, _) = await _read(
        _book({
          'OEBPS/content.opf': opfXml(
            items: [
              item(
                'c1',
                'Text/c1.xhtml',
                mediaType: ' Application/XHTML+XML; charset=utf-8',
              ),
            ],
            itemrefs: [itemref('c1')],
          ),
        }),
      );
      expect(p.manifest['c1']!.mediaType, 'application/xhtml+xml');
      expect(p.spine.single.kind, SectionKind.xhtml);
    });

    test('item que é o próprio OPF com outra caixa é missing', () async {
      final (p, sink) = await _read(
        _book({
          'OEBPS/content.opf': opfXml(
            items: [
              item('c1', 'Text/c1.xhtml'),
              item(
                'opf',
                'CONTENT.OPF',
                mediaType: 'application/oebps-package+xml',
              ),
            ],
            itemrefs: [itemref('c1')],
          ),
        }),
      );
      final opf = p.manifest['opf']!;
      expect(opf.missing, isTrue);
      expect(opf.path, 'OEBPS/CONTENT.OPF', reason: 'o path guardado fica');
      final d = _only(sink, EpubDiagnosticCode.resourceMissing);
      expect((d.href, d.details['reason']), ('OEBPS/CONTENT.OPF', 'opf'));
    });
  });

  group('spine e fallback (§6.3, §6.4)', () {
    test('fallback em cadeia até o primeiro XHTML existente', () async {
      final (p, sink) = await _read(
        _book({
          'OEBPS/content.opf': opfXml(
            items: [
              item('pdf', 'a.pdf', mediaType: 'application/pdf', fallback: 'x'),
              item('x', 'x.xhtml', fallback: 'img'),
              item('img', 'i.png', mediaType: 'image/png'),
            ],
            itemrefs: [itemref('pdf')],
          ),
          'OEBPS/a.pdf': [1, 2, 3],
          'OEBPS/i.png': [1, 2, 3],
        }),
      );
      final s = p.spine.single;
      expect(s.item.id, 'pdf');
      expect(s.content.id, 'img', reason: 'x.xhtml é missing: pula');
      expect(s.kind, SectionKind.image);
      expect(_codes(sink), ['resourceMissing', 'tocReconciled']);
    });

    test(
      'fallback em ciclo: content é o próprio item, unsupportedMediaType',
      () async {
        final (p, sink) = await _read(
          _book({
            'OEBPS/content.opf': opfXml(
              items: [
                item('a', 'a.pdf', mediaType: 'application/pdf', fallback: 'b'),
                item(
                  'b',
                  'b.epub',
                  mediaType: 'application/epub+zip',
                  fallback: 'a',
                ),
              ],
              itemrefs: [itemref('a')],
            ),
            'OEBPS/a.pdf': [1],
            'OEBPS/b.epub': [1],
          }),
        );
        expect(p.spine.single.content.id, 'a');
        expect(p.spine.single.kind, SectionKind.unsupported);
        final d = _only(sink, EpubDiagnosticCode.unsupportedMediaType);
        expect(d.href, 'OEBPS/a.pdf');
        expect(d.details['mediaType'], 'application/pdf');
      },
    );

    test('cadeia de fallback para em 16 passos', () async {
      final items = [
        for (var i = 0; i < 20; i++)
          item(
            'f$i',
            'f$i.bin',
            mediaType: 'application/octet-stream',
            fallback: 'f${i + 1}',
          ),
        item('f20', 'f20.xhtml'),
      ];
      final (p, sink) = await _read(
        _book({
          'OEBPS/content.opf': opfXml(items: items, itemrefs: [itemref('f0')]),
          for (var i = 0; i < 20; i++) 'OEBPS/f$i.bin': [0],
          'OEBPS/f20.xhtml': chapter,
        }),
      );
      expect(p.spine.single.content.id, 'f0');
      expect(_codes(sink), ['unsupportedMediaType', 'tocReconciled']);
    });

    test(
      'mesmo caminho por dois ids: spineItemDuplicate, vale o primeiro',
      () async {
        final (p, sink) = await _read(
          _book({
            'OEBPS/content.opf': opfXml(
              items: [item('a', 'Text/c1.xhtml'), item('b', 'Text/./c1.xhtml')],
              itemrefs: [itemref('a'), itemref('b')],
            ),
          }),
        );
        expect(p.spine.map((s) => s.idref), ['a']);
        final d = _only(sink, EpubDiagnosticCode.spineItemDuplicate);
        expect(d.href, 'OEBPS/content.opf');
        expect(d.details['idref'], 'b');
      },
    );

    test('spine vazio depois de descartar idrefs sem item é fatal', () async {
      await expectLater(
        _read(
          _book({
            'OEBPS/content.opf': opfXml(
              items: [item('c1', 'Text/c1.xhtml')],
              itemrefs: [itemref('x'), itemref('y')],
            ),
          }),
        ),
        throwsA(
          isA<EpubPackageException>()
              .having((e) => e.href, 'href', 'OEBPS/content.opf')
              .having((e) => e.message, 'message', 'spine vazio'),
        ),
      );
    });

    test('mesmo arquivo com outra caixa: spineItemDuplicate', () async {
      final (p, sink) = await _read(
        _book({
          'OEBPS/content.opf': opfXml(
            items: [item('a', 'Text/c1.xhtml'), item('b', 'TEXT/C1.XHTML')],
            itemrefs: [itemref('a'), itemref('b')],
          ),
        }),
      );
      expect(p.manifest['b']!.path, 'OEBPS/TEXT/C1.XHTML');
      expect(p.manifest['b']!.missing, isFalse);
      expect(p.spine.map((s) => s.idref), ['a']);
      expect(
        _only(sink, EpubDiagnosticCode.spineItemDuplicate).details['idref'],
        'b',
      );
    });

    test('alvo casa com o item do spine, não com o de outra caixa', () async {
      // O manifest traz primeiro a grafia que o spine descarta; o alvo
      // exato dela vai para o item que ficou no spine, e ninguém é órfão.
      final (p, sink) = await _read(
        _book({
          'OEBPS/content.opf': opfXml(
            items: [
              item('nav', 'nav.xhtml', properties: 'nav'),
              item('b', 'TEXT/C1.XHTML'),
              item('a', 'Text/c1.xhtml'),
            ],
            itemrefs: [itemref('a'), itemref('b')],
          ),
          'OEBPS/nav.xhtml': navXml(tocNav([('Um', 'TEXT/C1.XHTML')])),
        }),
      );
      expect(p.spine.map((s) => s.idref), ['a']);
      expect(p.toc.single.target, const NavTarget('OEBPS/Text/c1.xhtml'));
      expect(_codes(sink), ['spineItemDuplicate']);
    });

    test('remoto nunca é content: fallback pula a imagem remota', () async {
      final (p, sink) = await _read(
        _book({
          'OEBPS/content.opf': opfXml(
            items: [
              item('pdf', 'a.pdf', mediaType: 'application/pdf', fallback: 'r'),
              item(
                'r',
                'https://ex.com/capa.png',
                mediaType: 'image/png',
                fallback: 'c1',
              ),
              item('c1', 'Text/c1.xhtml'),
            ],
            itemrefs: [itemref('pdf')],
          ),
          'OEBPS/a.pdf': [1],
        }),
      );
      expect(p.spine.single.content.id, 'c1');
      expect(_codes(sink), isNot(contains('unsupportedMediaType')));
    });

    test('XHTML remoto no spine vai ao fallback local', () async {
      final (p, _) = await _read(
        _book({
          'OEBPS/content.opf': opfXml(
            items: [
              item('r', 'https://ex.com/c.xhtml', fallback: 'c1'),
              item('c1', 'Text/c1.xhtml'),
            ],
            itemrefs: [itemref('r')],
          ),
        }),
      );
      final s = p.spine.single;
      expect(s.item.id, 'r');
      expect(s.item.remote, isTrue);
      expect(s.content.id, 'c1');
    });

    test('borda da cadeia de fallback: 16 passos resolvem, 17 não', () async {
      Future<String> contentWithUnsupported(int unsupported) async {
        final items = [
          for (var i = 0; i < unsupported; i++)
            item(
              'f$i',
              'f$i.bin',
              mediaType: 'application/pdf',
              fallback: 'f${i + 1}',
            ),
          item('f$unsupported', 'f$unsupported.xhtml'),
        ];
        final (p, _) = await _read(
          _book({
            'OEBPS/content.opf': opfXml(
              items: items,
              itemrefs: [itemref('f0')],
            ),
            for (var i = 0; i < unsupported; i++) 'OEBPS/f$i.bin': [0],
            'OEBPS/f$unsupported.xhtml': chapter,
          }),
        );
        return p.spine.single.content.id;
      }

      expect(await contentWithUnsupported(16), 'f16', reason: '16 passos');
      expect(await contentWithUnsupported(17), 'f0', reason: '17 passos');
    });
  });

  group('NAV e NCX (§7)', () {
    test('NAV quebrado (missing) → NCX', () async {
      final (p, sink) = await _read(_book({'OEBPS/nav.xhtml': null}));
      expect(p.navPath, isNull);
      expect(p.ncxPath, 'OEBPS/toc.ncx');
      expect(p.toc.first.title, 'Um (NCX)');
      expect(p.toc.first.synthesized, isFalse);
      final ignored = _only(sink, EpubDiagnosticCode.navIgnored);
      expect(ignored.href, 'OEBPS/nav.xhtml');
      expect(ignored.details['reason'], 'missing');
      expect(_codes(sink), ['resourceMissing', 'navIgnored', 'tocReconciled']);
    });

    test(
      'NAV sem nav de toc: no-toc, NCX dá o TOC, NAV dá landmarks',
      () async {
        final (p, sink) = await _read(
          _book({
            'OEBPS/nav.xhtml': navXml(
              tocNav([('Início', 'Text/c1.xhtml')], type: 'landmarks'),
            ),
          }),
        );
        expect(p.toc.map((e) => e.title), ['Um (NCX)', 'c2']);
        expect(
          p.landmarks.single.target,
          const NavTarget('OEBPS/Text/c1.xhtml'),
        );
        expect(p.navPath, 'OEBPS/nav.xhtml');
        expect(
          _only(sink, EpubDiagnosticCode.navIgnored).details['reason'],
          'no-toc',
        );
      },
    );

    test(
      'NAV sem entradas vai ao NCX; referência numérica enorme não lança',
      () async {
        // O parseNav devolve um NAV sem entradas quando o package:html lança
        // FormatException; o texto vazio chega ao mesmo NAV sem entradas.
        final (empty, emptySink) = await _read(_book({'OEBPS/nav.xhtml': ''}));
        expect(empty.navPath, 'OEBPS/nav.xhtml');
        expect(empty.ncxPath, 'OEBPS/toc.ncx');
        expect(empty.toc.first.title, 'Um (NCX)');
        expect(
          _only(emptySink, EpubDiagnosticCode.navIgnored).details['reason'],
          'no-toc',
        );

        // A referência que fazia o tokenizador lançar FormatException
        // (int.parse acima de 2^63) vira U+FFFD no texto canônico.
        final (big, bigSink) = await _read(
          _book({
            'OEBPS/nav.xhtml': navXml(
              tocNav([
                ('&#99999999999999999999999;', 'Text/c1.xhtml'),
                ('Dois', 'Text/c2.xhtml'),
              ]),
            ),
          }),
        );
        expect(big.toc.map((e) => e.title), ['\u{FFFD}', 'Dois']);
        expect(bigSink.diagnostics, isEmpty);
      },
    );

    test('NCX com XML inválido: invalid; sem TOC, tudo sintetizado', () async {
      final (p, sink) = await _read(
        _book({'OEBPS/nav.xhtml': null, 'OEBPS/toc.ncx': '<ncx><navMap>'}),
      );
      expect(p.ncxPath, isNull);
      expect(p.toc.map((e) => (e.title, e.synthesized)), [
        ('c1', true),
        ('c2', true),
      ]);
      final reasons = [
        for (final d in sink.diagnostics)
          if (identical(d.code, EpubDiagnosticCode.navIgnored))
            (d.href, d.details['reason']),
      ];
      expect(reasons, [
        ('OEBPS/nav.xhtml', 'missing'),
        ('OEBPS/toc.ncx', 'invalid'),
      ]);
    });

    test('sem NAV nem NCX no manifest', () async {
      final (p, sink) = await _read(
        _book({
          'OEBPS/content.opf': opfXml(
            items: [item('c1', 'Text/c1.xhtml')],
            itemrefs: [itemref('c1')],
          ),
        }),
      );
      expect(p.navPath, isNull);
      expect(p.ncxPath, isNull);
      expect(p.toc.single.synthesized, isTrue);
      expect(_codes(sink), ['tocReconciled']);
    });

    test('NAV em diretório diferente do OPF e #frag do próprio NAV', () async {
      final (p, _) = await _read(
        _book({
          'OEBPS/content.opf': opfXml(
            items: [
              item('nav', 'nav/toc.xhtml', properties: 'nav'),
              item('c1', 'Text/c1.xhtml'),
            ],
            itemrefs: [itemref('c1')],
          ),
          'OEBPS/nav/toc.xhtml': navXml(
            tocNav([('Um', '../Text/c1.xhtml#s1'), ('Aqui', '#topo')]),
          ),
        }),
      );
      expect(p.toc.map((e) => e.target), [
        const NavTarget('OEBPS/Text/c1.xhtml', 's1'),
        const NavTarget('OEBPS/nav/toc.xhtml', 'topo'),
      ]);
    });

    test(
      'alvos: maiúsculas, %xx, externo, fora da raiz, sem casamento',
      () async {
        final (p, sink) = await _read(
          _book({
            'OEBPS/content.opf': opfXml(
              items: [
                item('nav', 'nav.xhtml', properties: 'nav'),
                item('c1', 'Text/Cap%C3%ADtulo.xhtml'),
              ],
              itemrefs: [itemref('c1')],
            ),
            'OEBPS/Text/Capítulo.xhtml': chapter,
            'OEBPS/nav.xhtml': navXml(
              tocNav([
                ('Caixa', 'TEXT/CAP%C3%8DTULO.XHTML#a%20b'),
                ('Externo', 'https://ex.com/x.html'),
                ('Fora', '../../x.xhtml'),
                ('', 'Text/outro.xhtml'),
              ]),
            ),
          }),
        );
        expect(p.toc.map((e) => (e.title, e.target)), [
          ('Caixa', const NavTarget('OEBPS/Text/Capítulo.xhtml', 'a b')),
          ('Externo', null),
          ('Fora', null),
          ('outro', const NavTarget('OEBPS/Text/outro.xhtml')),
        ]);
        expect(sink.diagnostics, isEmpty);
      },
    );

    test('page-list: NAV; senão NCX', () async {
      const ncxPages =
          '<pageList><pageTarget><navLabel><text>7</text></navLabel>'
          '<content src="Text/c1.xhtml#p7"/></pageTarget></pageList>';
      final fromNcx = (await _read(
        _book({
          'OEBPS/toc.ncx': ncxXml([
            ('Um', 'Text/c1.xhtml'),
          ], pageList: ncxPages),
        }),
      )).$1;
      expect(fromNcx.pageList.single.title, '7');
      expect(
        fromNcx.pageList.single.target,
        const NavTarget('OEBPS/Text/c1.xhtml', 'p7'),
      );

      final fromNav = (await _read(
        _book({
          'OEBPS/nav.xhtml': navXml(
            tocNav([('Um', 'Text/c1.xhtml'), ('Dois', 'Text/c2.xhtml')]) +
                tocNav([('1', 'Text/c1.xhtml#p1')], type: 'page-list'),
          ),
          'OEBPS/toc.ncx': ncxXml([
            ('Um', 'Text/c1.xhtml'),
          ], pageList: ncxPages),
        }),
      )).$1;
      expect(fromNav.pageList.single.title, '1');
      expect(fromNav.ncxPath, isNull);
    });

    test('landmarks: guide do OPF quando o NAV não tem', () async {
      final (p, _) = await _read(
        _book({
          'OEBPS/content.opf': opfXml(
            items: [
              item('nav', 'nav.xhtml', properties: 'nav'),
              item('c1', 'Text/c1.xhtml'),
            ],
            itemrefs: [itemref('c1')],
            extra:
                '<guide><reference type="text" title="Começo" '
                'href="Text/c1.xhtml#i"/></guide>',
          ),
        }),
      );
      expect(p.landmarks.single.type, 'text');
      expect(p.landmarks.single.title, 'Começo');
      expect(
        p.landmarks.single.target,
        const NavTarget('OEBPS/Text/c1.xhtml', 'i'),
      );
    });

    test('NAV truncado: navIgnored truncated, a parte lida é usada', () async {
      var nested = '';
      for (var i = 0; i < 70; i++) {
        nested = '<ol><li><a href="Text/c1.xhtml#n$i">N$i</a>$nested</li></ol>';
      }
      final (p, sink) = await _read(
        _book({
          'OEBPS/nav.xhtml': navXml('<nav epub:type="toc">$nested</nav>'),
        }),
      );
      expect(p.toc.first.title, 'N69');
      expect(
        _only(sink, EpubDiagnosticCode.navIgnored).details['reason'],
        'truncated',
      );
    });

    test('NAV acima do teto: too-large, sem drenar', () async {
      final big = navXml(
        '<nav epub:type="toc"><ol><li><a href="Text/c1.xhtml">x</a></li></ol>'
        '</nav><p>${'a' * maxPackageDocumentSize}</p>',
      );
      final (p, sink) = await _read(_book({'OEBPS/nav.xhtml': big}));
      expect(p.navPath, isNull);
      expect(p.toc.first.title, 'Um (NCX)');
      expect(
        _only(sink, EpubDiagnosticCode.navIgnored).details['reason'],
        'too-large',
      );
    });

    test('guide com href só de fragmento: sem alvo', () async {
      final (p, _) = await _read(
        _book({
          'OEBPS/content.opf': opfXml(
            items: [
              item('nav', 'nav.xhtml', properties: 'nav'),
              item('c1', 'Text/c1.xhtml'),
            ],
            itemrefs: [itemref('c1')],
            extra:
                '<guide><reference type="toc" title="Aqui" href="#x"/>'
                '<reference type="text" title="Começo" '
                'href="Text/c1.xhtml"/></guide>',
          ),
        }),
      );
      expect(p.landmarks.map((l) => (l.title, l.target)), [
        ('Aqui', null),
        ('Começo', const NavTarget('OEBPS/Text/c1.xhtml')),
      ]);
    });

    test('NCX acima do teto: too-large, TOC sintetizado', () async {
      final (p, sink) = await _read(
        _book({
          'OEBPS/nav.xhtml': null,
          'OEBPS/toc.ncx': ncxXml([
            ('Um', 'Text/c1.xhtml'),
          ]).replaceFirst('<head/>', '<head/>${' ' * maxPackageDocumentSize}'),
        }),
      );
      expect(p.ncxPath, isNull);
      expect(p.toc.every((e) => e.synthesized), isTrue);
      expect(
        [
          for (final d in sink.diagnostics)
            if (identical(d.code, EpubDiagnosticCode.navIgnored))
              (d.href, d.details['reason']),
        ],
        [('OEBPS/nav.xhtml', 'missing'), ('OEBPS/toc.ncx', 'too-large')],
      );
    });

    test('NAV remoto: navIgnored missing, NCX dá o TOC', () async {
      final (p, sink) = await _read(
        _book({
          'OEBPS/content.opf': opfXml(
            items: [
              item('nav', 'https://ex.com/nav.xhtml', properties: 'nav'),
              item('ncx', 'toc.ncx', mediaType: ncxType),
              item('c1', 'Text/c1.xhtml'),
            ],
            itemrefs: [itemref('c1')],
            spineAttributes: ' toc="ncx"',
          ),
        }),
      );
      expect(p.navPath, isNull);
      expect(p.ncxPath, 'OEBPS/toc.ncx');
      expect(p.toc.single.title, 'Um (NCX)');
      final d = _only(sink, EpubDiagnosticCode.navIgnored);
      expect(
        (d.href, d.details['reason']),
        ('https://ex.com/nav.xhtml', 'missing'),
      );
    });
  });

  group('fatais (§9.1)', () {
    test('container.xml ausente', () async {
      await expectLater(
        _read(_book({'META-INF/container.xml': null})),
        throwsA(
          isA<EpubContainerException>().having(
            (e) => e.href,
            'href',
            'META-INF/container.xml',
          ),
        ),
      );
    });

    test('rootfile inexistente seguido de válido', () async {
      final (p, _) = await _read(
        _book({
          'META-INF/container.xml': containerXml([
            'nao/existe.opf',
            'OEBPS/content.opf',
          ]),
        }),
      );
      expect(p.opfPath, 'OEBPS/content.opf');
    });

    test(
      'nenhum rootfile existe: OPF ausente com o primeiro full-path',
      () async {
        await expectLater(
          _read(
            _book({
              'META-INF/container.xml': containerXml(['a.opf', 'b.opf']),
            }),
          ),
          throwsA(
            isA<EpubPackageException>()
                .having((e) => e.href, 'href', 'a.opf')
                .having((e) => e.message, 'message', 'OPF ausente'),
          ),
        );
      },
    );

    test('full-path com outra caixa: opfPath é o nome real', () async {
      final (p, sink) = await _read(
        _book({
          'META-INF/container.xml': containerXml(['oebps/CONTENT.opf']),
        }),
      );
      expect(p.opfPath, 'OEBPS/content.opf');
      expect(p.spine.first.item.path, 'OEBPS/Text/c1.xhtml');
      expect(_codes(sink), ['pathCaseMismatch']);
    });

    test('OPF acima do teto e OPF inválido', () async {
      await expectLater(
        _read(
          _book({
            'OEBPS/content.opf':
                '<package>${' ' * maxPackageDocumentSize}</package>',
          }),
        ),
        throwsA(
          isA<EpubPackageException>().having(
            (e) => e.message,
            'message',
            contains('teto'),
          ),
        ),
      );
      await expectLater(
        _read(_book({'OEBPS/content.opf': '<package><manifest>'})),
        throwsA(
          isA<EpubPackageException>().having(
            (e) => e.href,
            'href',
            'OEBPS/content.opf',
          ),
        ),
      );
    });

    test('ofuscação sobre conteúdo é EpubEncryptedException', () async {
      String encryption(String uri) =>
          '<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container" '
          'xmlns:enc="http://www.w3.org/2001/04/xmlenc#"><enc:EncryptedData>'
          '<enc:EncryptionMethod Algorithm="http://www.idpf.org/2008/embedding"/>'
          '<enc:CipherData><enc:CipherReference URI="$uri"/></enc:CipherData>'
          '</enc:EncryptedData></encryption>';
      Map<String, Object?> withFont(String mediaType) => _book({
        'META-INF/encryption.xml': encryption('OEBPS/Fonts/f.ttf'),
        'OEBPS/content.opf': opfXml(
          items: [
            item('c1', 'Text/c1.xhtml'),
            item('f', 'Fonts/f.ttf', mediaType: mediaType),
          ],
          itemrefs: [itemref('c1')],
        ),
        'OEBPS/Fonts/f.ttf': Uint8List(2000),
      });
      await expectLater(
        _read(withFont(xhtmlType)),
        throwsA(
          isA<EpubEncryptedException>()
              .having(
                (e) => e.scheme,
                'scheme',
                'unknown:obfuscation-on-content',
              )
              .having((e) => e.href, 'href', 'OEBPS/Fonts/f.ttf'),
        ),
      );
      for (final type in [
        'font/ttf',
        'application/vnd.ms-opentype',
        'application/x-font-ttf',
        'application/font-woff',
        'application/octet-stream',
      ]) {
        final (p, _) = await _read(withFont(type));
        expect(p.manifest['f']!.missing, isFalse, reason: type);
      }
    });
  });

  group('strict (§9.1)', () {
    test('warning da Publicação lança EpubPackageException', () async {
      await expectLater(
        _read(_book({'OEBPS/Text/c2.xhtml': null}), strict: true),
        throwsA(
          isA<EpubPackageException>()
              .having((e) => e.href, 'href', 'OEBPS/Text/c2.xhtml')
              .having(
                (e) => e.message,
                'message',
                startsWith('resourceMissing: '),
              ),
        ),
      );
    });

    test(
      'exceção do sink na leitura do NAV propaga (não vira unreadable)',
      () async {
        final files = epubFiles(_book());
        final w = ZipWriter()
          ..add(
            'mimetype',
            ascii.encode('application/epub+zip'),
            compress: false,
          );
        for (final MapEntry(:key, :value) in files.entries) {
          w.add(key, value, crcOverride: key == 'OEBPS/nav.xhtml' ? 1 : null);
        }
        final zip = w.build();
        Future<EpubPublication> run(DiagnosticSink sink) async {
          final c = await ZipContainer.open(
            MemoryEpubByteSource(zip),
            sink: sink,
          );
          return readPublication(c, sink: sink);
        }

        final strict = DiagnosticSink(strict: true);
        await expectLater(
          run(strict),
          throwsA(
            isA<EpubContainerException>()
                .having(
                  (e) => e.message,
                  'message',
                  startsWith('zipCrcMismatch: '),
                )
                .having(
                  (e) => identical(e, strict.lastStrictException),
                  'é a lançada pelo sink',
                  isTrue,
                ),
          ),
        );
        final relaxed = DiagnosticSink();
        final p = await run(relaxed);
        expect(
          p.navPath,
          'OEBPS/nav.xhtml',
          reason: 'fora de strict, só diagnóstico',
        );
        expect(_codes(relaxed), ['zipCrcMismatch']);
      },
    );

    test('exceção de terceiro com a mensagem de um warning registrado é falha '
        'do fetch, não do sink', () async {
      final sink = DiagnosticSink(strict: true);
      // Sink reaproveitado: um warning já registrado, cuja exceção quem
      // o usou antes capturou.
      expect(
        () => sink.emit(
          EpubDiagnosticCode.resourceMissing,
          href: 'x',
          message: 'x',
        ),
        throwsA(isA<EpubContainerException>()),
      );
      final impostor = EpubContainerException(
        'resourceMissing: x',
        href: 'OEBPS/nav.xhtml',
      );
      final container = await ProviderContainer.open(
        MapProvider(_book(), readThrows: {'OEBPS/nav.xhtml': impostor}),
        sink: sink,
      );
      await expectLater(
        readPublication(container, sink: sink),
        throwsA(
          isA<EpubPackageException>()
              .having(
                (e) => e.message,
                'message',
                startsWith('resourceUnreadable: '),
              )
              .having((e) => e.href, 'href', 'OEBPS/nav.xhtml')
              .having((e) => e.cause, 'cause', same(impostor)),
        ),
      );
    });
  });

  group('ProviderContainer', () {
    Future<(EpubPublication, DiagnosticSink)> readProvider(
      MapProvider provider,
    ) async {
      final sink = DiagnosticSink();
      final container = await ProviderContainer.open(provider, sink: sink);
      return (await readPublication(container, sink: sink), sink);
    }

    test('lê o livro sem ZIP', () async {
      final (p, sink) = await readProvider(MapProvider(_book()));
      expect(p.toc.map((e) => e.title), ['Um', 'Dois']);
      expect(sink.diagnostics, isEmpty);
    });

    test('exists que lança: missing e resourceUnreadable', () async {
      final (p, sink) = await readProvider(
        MapProvider(_book(), failingExists: {'OEBPS/Text/c2.xhtml'}),
      );
      expect(p.manifest['c2']!.missing, isTrue);
      final d = _only(sink, EpubDiagnosticCode.resourceUnreadable);
      expect(d.href, 'OEBPS/Text/c2.xhtml');
      expect(d.details['reason'], 'exists');
      expect(d.details['exception'], contains('exists falhou'));
    });

    test('read do NAV que lança: unreadable e NCX', () async {
      final (p, sink) = await readProvider(
        MapProvider(_book(), failingRead: {'OEBPS/nav.xhtml'}),
      );
      expect(p.toc.first.title, 'Um (NCX)');
      expect(_codes(sink), [
        'resourceUnreadable',
        'navIgnored',
        'tocReconciled',
      ]);
      expect(
        _only(sink, EpubDiagnosticCode.navIgnored).details['reason'],
        'unreadable',
      );
    });

    test(
      'read do container.xml que lança: a EpubContainerException propaga',
      () async {
        final sink = DiagnosticSink();
        final container = await ProviderContainer.open(
          MapProvider(_book(), failingRead: {'META-INF/container.xml'}),
          sink: sink,
        );
        await expectLater(
          readPublication(container, sink: sink),
          throwsA(
            isA<EpubContainerException>()
                .having((e) => e.href, 'href', 'META-INF/container.xml')
                .having((e) => e.cause, 'cause', isNotNull),
          ),
        );
      },
    );

    test('read do OPF que lança: a EpubContainerException propaga', () async {
      final sink = DiagnosticSink();
      final container = await ProviderContainer.open(
        MapProvider(_book(), failingRead: {'OEBPS/content.opf'}),
        sink: sink,
      );
      await expectLater(
        readPublication(container, sink: sink),
        throwsA(
          isA<EpubContainerException>().having(
            (e) => e.href,
            'href',
            'OEBPS/content.opf',
          ),
        ),
      );
    });

    test('readPublication não fecha o contêiner', () async {
      final provider = MapProvider(_book());
      final EpubContainer container = await ProviderContainer.open(
        provider,
        sink: DiagnosticSink(),
      );
      await readPublication(container, sink: DiagnosticSink());
      expect(provider.closed, isFalse);
      await container.close();
      expect(provider.closed, isTrue);
    });

    test('read do NCX que lança: unreadable, TOC sintetizado', () async {
      final (p, sink) = await readProvider(
        MapProvider(
          _book({'OEBPS/nav.xhtml': null}),
          failingRead: {'OEBPS/toc.ncx'},
        ),
      );
      expect(p.ncxPath, isNull);
      expect(p.toc.every((e) => e.synthesized), isTrue);
      final unreadable = _only(sink, EpubDiagnosticCode.resourceUnreadable);
      expect(unreadable.href, 'OEBPS/toc.ncx');
      expect(unreadable.details['exception'], contains('read falhou'));
      expect(
        [
          for (final d in sink.diagnostics)
            if (identical(d.code, EpubDiagnosticCode.navIgnored))
              (d.href, d.details['reason']),
        ],
        [('OEBPS/nav.xhtml', 'missing'), ('OEBPS/toc.ncx', 'unreadable')],
      );
    });

    test('caminho fatal também não fecha o contêiner', () async {
      final provider = MapProvider(
        _book({
          'OEBPS/content.opf': opfXml(
            items: [item('c1', 'Text/c1.xhtml')],
            itemrefs: [itemref('x')],
          ),
        }),
      );
      final container = await ProviderContainer.open(
        provider,
        sink: DiagnosticSink(),
      );
      await expectLater(
        readPublication(container, sink: DiagnosticSink()),
        throwsA(isA<EpubPackageException>()),
      );
      expect(provider.closed, isFalse);
      expect(await container.exists('OEBPS/Text/c1.xhtml'), isTrue);
      await container.close();
      expect(provider.closed, isTrue);
    });
  });

  group('foco de revisão', () {
    test('OPF na raiz do contêiner', () async {
      final (p, sink) = await _read({
        'META-INF/container.xml': containerXml(['content.opf']),
        'content.opf': opfXml(
          items: [
            item('nav', 'nav.xhtml', properties: 'nav'),
            item('c1', 'c1.xhtml'),
          ],
          itemrefs: [itemref('c1')],
        ),
        'nav.xhtml': navXml(tocNav([('Um', 'c1.xhtml')])),
        'c1.xhtml': chapter,
      });
      expect(p.opfPath, 'content.opf');
      expect(p.spine.single.item.path, 'c1.xhtml');
      expect(p.toc.single.target, const NavTarget('c1.xhtml'));
      expect(sink.diagnostics, isEmpty);
    });

    test('OPF em UTF-16 LE com BOM', () async {
      final opf = opfXml(
        metadata:
            '<dc:identifier id="uid">u</dc:identifier>'
            '<dc:title>Título em UTF-16</dc:title>',
        items: [item('c1', 'Text/c1.xhtml')],
        itemrefs: [itemref('c1')],
      ).replaceFirst('encoding="UTF-8"', 'encoding="UTF-16"');
      final bytes = <int>[0xFF, 0xFE];
      for (final u in opf.codeUnits) {
        bytes.addAll([u & 0xFF, u >> 8]);
      }
      final (p, sink) = await _read(_book({'OEBPS/content.opf': bytes}));
      expect(p.metadata.title, 'Título em UTF-16');
      expect(p.spine.single.kind, SectionKind.xhtml);
      expect(_codes(sink), ['tocReconciled']);
    });

    test('OEB 1.2: text/x-oeb1-document é seção xhtml', () async {
      final (p, sink) = await _read(
        _book({
          'OEBPS/content.opf': opfXml(
            items: [
              item('a', 'Text/c1.xhtml', mediaType: 'text/x-oeb1-document'),
            ],
            itemrefs: [itemref('a')],
          ),
        }),
      );
      expect(p.spine.single.kind, SectionKind.xhtml);
      expect(_codes(sink), isNot(contains('unsupportedMediaType')));
    });
  });
}
