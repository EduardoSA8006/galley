// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:galley/src/core/diagnostics/diagnostic_sink.dart';
import 'package:galley/src/features/container/data/fonts/font_deobfuscator.dart';
import 'package:galley/src/features/container/data/parsers/nav_parser.dart';
import 'package:galley/src/features/container/data/parsers/ncx_parser.dart';
import 'package:galley/src/features/container/data/parsers/opf_parser.dart';
import 'package:galley/src/features/container/data/text/decode_text.dart';
import 'package:galley/src/features/container/data/zip/byte_source.dart';
import 'package:galley/src/features/container/data/zip/crc32.dart';
import 'package:galley/src/features/container/data/zip/zip_archive.dart';
import 'package:galley/src/features/container/domain/models/navigation.dart';

import '../bench.dart';
import '../corpus/epub_writer.dart';

/// Trabalho de um ciclo, já com a entrada pronta.
typedef _Work = FutureOr<int> Function();

/// Benchmark micro: [_prepare] monta a entrada (fora da medição) e devolve
/// o trabalho que `run` repete.
final class _MicroBench implements Bench {
  _MicroBench(this.id, this._prepare);

  @override
  final String id;

  final Future<_Work> Function() _prepare;
  _Work? _work;

  @override
  Future<void> setUp() async => _work = await _prepare();

  @override
  FutureOr<int> run() => _work!();

  @override
  Future<void> tearDown() async => _work = null;
}

/// Bytes pseudoaleatórios determinísticos.
Uint8List _randomBytes(int length, int seed) {
  final rnd = Random(seed);
  final out = Uint8List(length);
  for (var i = 0; i < length; i++) {
    out[i] = rnd.nextInt(256);
  }
  return out;
}

/// Texto compressível determinístico (palavras de um vocabulário pequeno).
Uint8List _compressibleText(int length, int seed) {
  final rnd = Random(seed);
  const words = [
    'leitor',
    'livro',
    'capítulo',
    'página',
    'fonte',
    'margem',
    'parágrafo',
    'tipografia',
  ];
  final b = StringBuffer();
  while (b.length < length) {
    b.write('${words[rnd.nextInt(words.length)]} ');
  }
  return Uint8List.fromList(utf8.encode(b.toString())).sublist(0, length);
}

List<(String, String)> _navEntries(int count) => [
  for (var i = 0; i < count; i++) ('text/ch$i.xhtml#s$i', 'Capítulo $i'),
];

int _countPoints(List<NavPoint> points) {
  var n = 0;
  for (final p in points) {
    n += 1 + _countPoints(p.children) + p.label.length;
  }
  return n;
}

/// Todos os benchmarks micro da etapa container.
List<Bench> containerMicroBenches() => <Bench>[
  _MicroBench('container/crc32-1mib', () async {
    final data = _randomBytes(1024 * 1024, 1);
    return () {
      var crc = 0;
      for (var i = 0; i < 6; i++) {
        crc = crc32(data, crc);
      }
      return crc;
    };
  }),
  _MicroBench('container/zip-central-dir-2000', () async {
    final chunks = <Uint8List>[];
    final writer = ZipWriter(chunks.add);
    for (var i = 0; i < 2000; i++) {
      writer.addBytes('OEBPS/text/chapter-$i.xhtml', [
        i & 0xFF,
      ], deflate: false);
    }
    writer.finish();
    final bytes = _concat(chunks);
    return () async {
      var sum = 0;
      for (var i = 0; i < 30; i++) {
        final archive = await ZipArchive.open(MemoryByteSource(bytes));
        sum += archive.entries.length + archive.entries.last.crc32;
        await archive.close();
      }
      return sum;
    };
  }),
  _MicroBench('container/inflate-1mib', () async {
    final chunks = <Uint8List>[];
    ZipWriter(chunks.add)
      ..addBytes('big.txt', _compressibleText(1024 * 1024, 2))
      ..finish();
    final archive = await ZipArchive.open(MemoryByteSource(_concat(chunks)));
    final entry = archive.entry('big.txt')!;
    return () async {
      var sum = 0;
      for (var i = 0; i < 3; i++) {
        final out = await archive.read(entry);
        sum += out.length + out[out.length ~/ 2];
      }
      return sum;
    };
  }),
  _MicroBench('container/opf-parse-large', () async {
    const count = 6000;
    final xml = buildOpf(
      version: '3.0',
      title: 'Livro grande',
      identifier: 'urn:uuid:6c1f0a52-3d4e-4b8a-9f27-0a1b2c3d4e5f',
      language: 'pt-BR',
      items: [
        for (var i = 0; i < count; i++)
          OpfItem('c$i', 'text/ch$i.xhtml', 'application/xhtml+xml'),
      ],
      spineIds: [for (var i = 0; i < count; i++) 'c$i'],
    );
    return () {
      final doc = parseOpf(
        xml,
        opfPath: 'OEBPS/content.opf',
        sink: const NullDiagnosticSink(),
      );
      return doc.manifest.length + doc.spine.items.length * 3;
    };
  }),
  _MicroBench('container/nav-parse-large', () async {
    final xhtml = buildNavXhtml(
      language: 'pt-BR',
      title: 'Sumário',
      entries: _navEntries(8000),
    );
    return () {
      final nav = parseNavDocument(
        xhtml,
        navPath: 'OEBPS/nav.xhtml',
        sink: const NullDiagnosticSink(),
      )!;
      return _countPoints(nav.toc);
    };
  }),
  _MicroBench('container/ncx-parse-large', () async {
    final xml = buildNcx(
      identifier: 'urn:uuid:6c1f0a52-3d4e-4b8a-9f27-0a1b2c3d4e5f',
      title: 'Sumário',
      entries: _navEntries(4000),
    );
    return () {
      final nav = parseNcx(
        xml,
        ncxPath: 'OEBPS/toc.ncx',
        sink: const NullDiagnosticSink(),
      )!;
      return _countPoints(nav.toc);
    };
  }),
  _MicroBench('container/deobfuscate-idpf', () async {
    final font = _randomBytes(256 * 1024, 3);
    return () {
      var sum = 0;
      for (var i = 0; i < 150; i++) {
        final out = deobfuscateIdpf(font, 'galley-hm-fonts-idpf-0001-$i');
        sum += out.length + out[0] + out[1039];
      }
      return sum;
    };
  }),
  _MicroBench('container/decode-text-utf16', () async {
    const units = 512 * 1024;
    final bytes = Uint8List(2 + units * 2)
      ..[0] = 0xFF
      ..[1] = 0xFE;
    final rnd = Random(4);
    for (var i = 0; i < units; i++) {
      // Letras latinas acentuadas (U+00C0..U+00FF) e ASCII, em LE.
      final unit = rnd.nextBool()
          ? 0x20 + rnd.nextInt(0x5F)
          : 0xC0 + rnd.nextInt(0x40);
      bytes[2 + i * 2] = unit & 0xFF;
      bytes[3 + i * 2] = unit >> 8;
    }
    return () {
      final text = decodeText(bytes);
      return text.length + text.codeUnitAt(text.length ~/ 2);
    };
  }),
];

Uint8List _concat(List<Uint8List> chunks) {
  final b = BytesBuilder(copy: false);
  chunks.forEach(b.add);
  return b.takeBytes();
}
