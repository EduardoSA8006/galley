// A Publicação sobre os 68 EPUBs do corpus (spec da Publicação §10.1).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/container/zip/zip_container.dart';
import 'package:galley/src/diagnostics/diagnostic.dart';
import 'package:galley/src/diagnostics/exceptions.dart';
import 'package:galley/src/io/file_byte_source.dart';
import 'package:galley/src/publication/model.dart';
import 'package:galley/src/publication/read_publication.dart';

/// Códigos que a Publicação emite e que o corpus compara (spec §10.1).
const publicationCodes = {
  'resourceMissing',
  'spineItemUnresolved',
  'spineItemDuplicate',
  'unsupportedMediaType',
  'tocReconciled',
  'coverHeuristic',
  'navIgnored',
  'resourceUnreadable',
};

/// Dos acima, os `warning`: o caso roda sem `strict` e ganha a segunda
/// passada.
const publicationWarnings = {
  'resourceMissing',
  'spineItemUnresolved',
  'unsupportedMediaType',
  'resourceUnreadable',
};

/// Grupos que rodam com `strict: false` (doc/10 §5).
const relaxedGroups = {'patologia', 'faixa-b'};

List<String> _lines(File f) => f.existsSync()
    ? f.readAsLinesSync().where((l) => l.isNotEmpty).toList()
    : const [];

int _depth(List<NavPoint> points) {
  var max = 0;
  for (final p in points) {
    final d = 1 + _depth(p.children);
    if (d > max) max = d;
  }
  return max;
}

/// Asserções específicas de §10.1, por caso.
final Map<String, void Function(EpubPublication)> _specific = {
  'estrutura/opf-em-subpasta': (p) {
    expect(p.opfPath, 'OEBPS/content/content.opf');
    expect(p.manifest.values.where((i) => i.missing), isEmpty);
    expect(p.spine.map((s) => s.item.path), [
      'OEBPS/Text/cap01.xhtml',
      'OEBPS/Text/cap02.xhtml',
      'OEBPS/Text/cap03.xhtml',
    ]);
  },
  'regressoes/href-barra-invertida': (p) {
    final item = p.manifest['OEBPS_Text_cap01_xhtml']!;
    expect(item.path, 'OEBPS/Text/cap01.xhtml');
    expect(item.missing, isFalse);
  },
  'regressoes/href-url-encoded': (p) {
    final item = p.manifest['cap1']!;
    expect(item.path, 'OEBPS/Text/capítulo 1.xhtml');
    expect(item.missing, isFalse);
  },
  'estrutura/nav-ncx-divergentes': (p) {
    expect(p.toc.map((e) => e.title), [
      'Capítulo 1',
      'Capítulo 2',
      'Capítulo 3',
      'Capítulo 4',
    ]);
    expect(p.toc.where((e) => e.synthesized), isEmpty);
    expect(p.navPath, 'OEBPS/nav.xhtml');
  },
  'regressoes/ncx-incompleto-orfaos': (p) {
    expect(p.navPath, isNull);
    expect(p.ncxPath, 'OEBPS/toc.ncx');
    expect(p.toc.map((e) => e.target!.path), [
      for (var i = 1; i <= 6; i++) 'OEBPS/Text/cap0$i.xhtml',
    ]);
    expect(
      [
        for (var i = 0; i < p.toc.length; i++)
          if (p.toc[i].synthesized) i,
      ],
      [1, 3, 5],
    );
    expect(p.toc[1].title, 'cap02');
  },
  'estrutura/linear-no': (p) {
    final notas = p.toc.singleWhere((e) => e.title == 'Notas');
    expect(notas.synthesized, isFalse);
    expect(p.toc.where((e) => e.synthesized), isEmpty);
    final spineNotas = p.spine.singleWhere((s) => s.idref == 'notas');
    expect(spineNotas.linear, isFalse);
  },
  'estrutura/page-list-tres-fontes': (p) {
    expect(p.pageList.map((e) => e.title), [
      for (var i = 1; i <= 12; i++) '$i',
    ]);
    expect(p.pageList.map((e) => e.target!.fragment), [
      for (var i = 1; i <= 12; i++) 'pg$i',
    ]);
    expect(p.pageList.map((e) => e.target!.path).toSet(), {
      'OEBPS/Text/cap01.xhtml',
    });
    // Do NAV: com toc e page-list no NAV, o NCX nem é lido.
    expect(p.navPath, 'OEBPS/nav.xhtml');
    expect(p.ncxPath, isNull);
  },
  'estrutura/toc-6-niveis': (p) => expect(_depth(p.toc), 6),
  'estrutura/spine-800-itens': (p) => expect(p.spine, hasLength(800)),
  'regressoes/spine-so-imagem': (p) {
    expect(p.spine[1].kind, SectionKind.image);
    expect(p.spine[1].content.path, 'OEBPS/Images/pagina.png');
  },
  'regressoes/capa-ausente': (p) => expect(p.coverPath, isNull),
  'reais/moby-dick-en': (p) {
    expect(p.metadata.authors, ['Herman Melville']);
    expect(p.metadata.title, 'Moby Dick');
    expect(p.metadata.subtitle, 'Or, The Whale');
    expect(p.metadata.series, isNull);
  },
};

void main() {
  final root = Directory('test/corpus');
  final cases =
      root
          .listSync()
          .whereType<Directory>()
          .expand((group) => group.listSync().whereType<Directory>())
          .map(
            (d) => d.path.substring(root.path.length + 1).replaceAll(r'\', '/'),
          )
          .toList()
        ..sort();

  test('corpus tem os 68 casos e as asserções específicas existem', () {
    expect(cases, hasLength(68));
    expect(cases, containsAll(_specific.keys));
  });

  for (final name in cases) {
    final dir = '${root.path}/$name';
    final group = name.split('/').first;
    final exception = _lines(File('$dir/exception.expected')).firstOrNull;
    if (exception == 'EpubContainerException' ||
        exception == 'EpubEncryptedException') {
      continue; // falham no contêiner (spec §10.1)
    }
    final expectedAll = _lines(File('$dir/diagnostics.expected')).toSet();
    final expected = expectedAll.where(publicationCodes.contains).toSet();
    final hasWarning = expected.any(publicationWarnings.contains);
    final strict = !relaxedGroups.contains(group) && !hasWarning;

    test('$name (strict: $strict)', () async {
      final sink = DiagnosticSink(strict: strict);
      final container = await ZipContainer.open(
        FileEpubByteSource('$dir/book.epub'),
        sink: sink,
      );
      try {
        final read = readPublication(container, sink: sink);
        if (exception == 'EpubPackageException') {
          await expectLater(read, throwsA(isA<EpubPackageException>()));
          return;
        }
        final publication = await read;
        final emitted = sink.diagnostics.map((d) => d.code.name).toSet();
        expect(emitted.where(publicationCodes.contains).toSet(), expected);
        if (emitted.contains('encodingFallback')) {
          expect(expectedAll, contains('encodingFallback'));
        }
        for (final item in publication.manifest.values) {
          if (item.missing || item.remote) continue;
          expect(
            await container.exists(item.path),
            isTrue,
            reason: 'item ${item.id} (${item.path})',
          );
        }
        _specific[name]?.call(publication);
      } finally {
        await container.close();
      }
    });

    if (hasWarning) {
      test('$name (segunda passada, strict: true)', () async {
        final sink = DiagnosticSink(strict: true);
        final container = await ZipContainer.open(
          FileEpubByteSource('$dir/book.epub'),
          sink: sink,
        );
        try {
          await expectLater(
            readPublication(container, sink: sink),
            throwsA(
              isA<EpubPackageException>().having(
                (e) => publicationWarnings.any(
                  (c) => expected.contains(c) && e.message.startsWith('$c: '),
                ),
                'mensagem com o código',
                isTrue,
              ),
            ),
          );
        } finally {
          await container.close();
        }
      });
    }
  }
}
