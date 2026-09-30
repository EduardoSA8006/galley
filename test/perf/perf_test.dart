// Casos de desempenho: primitivas da Fase 0 (spec do harness §2.4), o
// contêiner (spec do contêiner §10), a Publicação (spec da Publicação §11) e
// o CSS (spec do CSS §15) da Fase 1. Rodar com:
//
//   flutter test --tags perf --run-skipped test/perf
//
// e comparar com `dart run tool/perf/compare.dart`.
// ignore_for_file: avoid_relative_lib_imports — tool/ não é pacote; importar por caminho é intencional.
@Tags(['perf'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/container/byte_source.dart';
import 'package:galley/src/container/container.dart';
import 'package:galley/src/container/font_obfuscation.dart';
import 'package:galley/src/container/zip/zip_container.dart';
import 'package:galley/src/css/cascade.dart';
import 'package:galley/src/css/loader.dart';
import 'package:galley/src/css/parser.dart';
import 'package:galley/src/diagnostics/diagnostic.dart';
import 'package:galley/src/publication/read_publication.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../../tool/corpus/lib/png.dart';
import '../../tool/corpus/lib/zip_writer.dart';
import '../../tool/perf/lib/perf_report.dart';
import 'support/perf_harness.dart';
import 'support/perf_inputs.dart';

int _sink = 0;

List<PerfCase> _phase0Cases() {
  late String xhtml;
  late List<String> paragraphs;
  late Uint8List deflated;
  late Uint8List pngBytes;
  return [
    PerfCase(
      id: 'html.parse.500kb',
      setUp: () async => xhtml = xhtmlOfLength(500 * 1024),
      run: () => _sink += html.parse(xhtml).body!.nodes.length,
    ),
    PerfCase(
      id: 'paragraph.shape.1000',
      setUp: () async => paragraphs = paragraphsOfWords(1000, 40),
      run: () {
        for (final text in paragraphs) {
          final builder =
              ui.ParagraphBuilder(
                  ui.ParagraphStyle(fontFamily: 'FlutterTest', fontSize: 16),
                )
                ..pushStyle(
                  ui.TextStyle(fontFamily: 'FlutterTest', fontSize: 16),
                )
                ..addText(text);
          final p = builder.build()
            ..layout(const ui.ParagraphConstraints(width: 320));
          _sink += p.height.toInt();
          p.dispose();
        }
      },
    ),
    PerfCase(
      id: 'zlib.inflate.1mb',
      setUp: () async => deflated = deflateRaw(proseBytes(1024 * 1024)),
      run: () => _sink += ZLibDecoder(raw: true).convert(deflated).length,
      innerIterations: 6, // ≈ 5 ms por amostra, como a calibração
    ),
    PerfCase(
      id: 'image.decode.target',
      setUp: () async => pngBytes = png(1200, 1600, seed: 5),
      runAsync: () async {
        final codec = await ui.instantiateImageCodec(
          pngBytes,
          targetWidth: 300,
        );
        final frame = await codec.getNextFrame();
        _sink += frame.image.width;
        frame.image.dispose();
        codec.dispose();
      },
    ),
  ];
}

List<PerfCase> _containerCases() {
  late Uint8List spine800;
  late ZipContainer inflateContainer;
  late Uint8List font;
  return [
    PerfCase(
      id: 'zip.open.800',
      setUp: () async =>
          spine800 = File('test/corpus/estrutura/spine-800-itens/book.epub')
              .readAsBytesSync(),
      runAsync: () async {
        final c = await ZipContainer.open(
          MemoryEpubByteSource(spine800),
          sink: DiagnosticSink(),
        );
        _sink += c.paths.length;
        await c.close();
      },
      innerIterations: 10, // ≈ 5 ms por amostra
    ),
    PerfCase(
      id: 'zip.fetch.inflate.1mb',
      setUp: () async {
        // Contêiner reusado entre amostras de propósito (o harness não tem teardown).
        final zip =
            (ZipWriter()
                  ..add(
                    'mimetype',
                    ascii.encode('application/epub+zip'),
                    compress: false,
                  )
                  ..add('OEBPS/Text/grande.xhtml', proseBytes(1024 * 1024)))
                .build();
        inflateContainer = await ZipContainer.open(
          MemoryEpubByteSource(zip),
          sink: DiagnosticSink(),
        );
      },
      runAsync: () async {
        final r = (await inflateContainer.fetch('OEBPS/Text/grande.xhtml'))!;
        for (final _ in r.decode()) {}
        _sink += r.bytes.length;
      },
    ),
    PerfCase(
      id: 'font.deobfuscate.idpf',
      setUp: () async => font = proseBytes(64 * 1024),
      run: () => _sink += deobfuscateFont(
        font,
        FontObfuscation.idpf,
        uniqueIdentifiers: const [
          'urn:uuid:b7e2f1a0-4c3d-4e5f-8a9b-0c1d2e3f4a5b',
        ],
        identifiers: const [],
      )!.length,
      innerIterations: 400, // ≈ 5 ms por amostra
    ),
  ];
}

List<PerfCase> _publicationCases() {
  late ZipContainer spine800;
  return [
    PerfCase(
      id: 'publication.read.800',
      // Contêiner aberto uma vez e reusado: o caso mede só a Publicação.
      setUp: () async => spine800 = await ZipContainer.open(
        MemoryEpubByteSource(
          File('test/corpus/estrutura/spine-800-itens/book.epub')
              .readAsBytesSync(),
        ),
        sink: DiagnosticSink(),
      ),
      runAsync: () async {
        final p = await readPublication(spine800, sink: DiagnosticSink());
        _sink += p.spine.length;
      },
      // Uma leitura já passa de 5 ms (≈ 27 ms no i5-11400H).
    ),
  ];
}

List<PerfCase> _cssCases() {
  const book = 'test/corpus/reais/leaves-of-grass-en/book.epub';
  const section = 'epub/text/song-of-myself.xhtml';
  late List<String> sheets;
  late Document document;
  late SectionSheets sectionSheets;

  Future<String> read(ZipContainer c, String path) async {
    final r = (await c.fetch(path))!;
    for (final _ in r.decode()) {}
    return utf8.decode(r.bytes);
  }

  Future<ZipContainer> open() => ZipContainer.open(
    MemoryEpubByteSource(File(book).readAsBytesSync()),
    sink: DiagnosticSink(),
  );

  return [
    PerfCase(
      id: 'css.parse',
      setUp: () async {
        final c = await open();
        sheets = [
          for (final name in ['core', 'se', 'local'])
            await read(c, 'epub/css/$name.css'),
        ];
        await c.close();
      },
      run: () {
        for (final text in sheets) {
          _sink += parseStyleSheet(text).rules.length;
        }
      },
      innerIterations: 11, // ≈ 5,8 ms por amostra (0,53 ms as três folhas)
    ),
    PerfCase(
      id: 'css.cascade',
      // O Document e as SectionSheets são montados uma vez: o caso mede só a
      // cascata, que não muda o DOM.
      setUp: () async {
        final c = await open();
        document = html.parse(await read(c, section));
        sectionSheets = await loadSectionSheets(
          c,
          document,
          sectionPath: section,
          cache: StyleSheetCache(),
          sink: DiagnosticSink(),
          containerSink: DiagnosticSink(),
        );
        await c.close();
        // Sem as duas folhas da seção, o caso mediria uma cascata vazia.
        if (sectionSheets.sheets.length != 2) {
          throw StateError(
            'css.cascade: esperadas 2 folhas, vieram '
            '${sectionSheets.sheets.length}',
          );
        }
      },
      run: () => _sink += computeStylesSync(
        document,
        sectionSheets,
        sectionPath: section,
        sink: DiagnosticSink(),
      ).length,
      // Uma cascata já passa de 5 ms (≈ 6,2 ms no i5-11400H, medido em
      // 2026-09-30, 2 816 elementos).
    ),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final results = <String, PerfCaseResult>{};

  for (final c in [
    ..._phase0Cases(),
    ..._containerCases(),
    ..._publicationCases(),
    ..._cssCases(),
  ]) {
    test(c.id, () async {
      final r = await measureCase(c);
      results[c.id] = r;
      print(
        '[perf] ${c.id}: razão ${r.ratio.toStringAsFixed(3)}, '
        'caso ${r.medianUs.round()} µs, calibração ${r.calibrationUs.round()} µs',
      );
    }, timeout: const Timeout(Duration(minutes: 5)));
  }

  tearDownAll(() async {
    if (await writeResultIfAny(results)) {
      print(
        '[perf] $defaultResultPath escrito (${results.length} casos, sink $_sink)',
      );
    }
  });
}
