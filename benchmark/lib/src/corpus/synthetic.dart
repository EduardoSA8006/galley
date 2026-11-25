import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'epub_writer.dart';

/// Tamanho do livro sintético médio (50 MiB).
const int kSynthetic50MiB = 50 * 1024 * 1024;

/// Tamanho do livro sintético grande (300 MiB).
const int kSynthetic300MiB = 300 * 1024 * 1024;

const int _chunkBytes = 64 * 1024;
const String _imagePath = 'OEBPS/images/filler.png';
const String _identifier = 'urn:uuid:5e1d7a40-9b2c-4f63-8a15-7c0d4e9b21aa';

const List<String> _words = [
  'maré',
  'farol',
  'vento',
  'campo',
  'rio',
  'noite',
  'caminho',
  'pedra',
  'janela',
  'barco',
  'sombra',
  'cidade',
  'livro',
  'estrada',
  'lume',
  'fogo',
  'silêncio',
  'jardim',
  'montanha',
  'ponte',
  'chuva',
  'memória',
  'porto',
  'tempo',
  'canção',
  'areia',
  'horizonte',
  'nuvem',
  'raiz',
  'viagem',
];

/// Gera, em streaming, um EPUB válido de [targetBytes] bytes em [path].
///
/// Há [chapters] capítulos de texto de preenchimento determinístico
/// (deflate) e uma imagem *stored* de bytes pseudoaleatórios que completa o
/// tamanho pedido, que sai exato. A memória usada é constante (trechos de
/// 64 KiB escritos direto no arquivo). Lança [ArgumentError] se
/// [targetBytes] não comportar nem o texto dos capítulos.
Future<File> writeSyntheticBook(
  String path, {
  required int targetBytes,
  int chapters = 200,
}) async {
  final names = [for (var i = 1; i <= chapters; i++) 'OEBPS/text/ch$i.xhtml'];
  final bodies = [for (var i = 1; i <= chapters; i++) _chapter(i)];

  final opf = buildOpf(
    version: '3.0',
    title: 'Livro sintético',
    identifier: _identifier,
    language: 'pt-BR',
    items: [
      const OpfItem(
        'nav',
        'nav.xhtml',
        'application/xhtml+xml',
        properties: 'nav',
      ),
      const OpfItem('css', 'style.css', 'text/css'),
      const OpfItem('filler', 'images/filler.png', 'image/png'),
      for (var i = 1; i <= chapters; i++)
        OpfItem('c$i', 'text/ch$i.xhtml', 'application/xhtml+xml'),
    ],
    spineIds: [for (var i = 1; i <= chapters; i++) 'c$i'],
  );
  final nav = buildNavXhtml(
    language: 'pt-BR',
    title: 'Sumário',
    entries: [
      for (var i = 1; i <= chapters; i++) ('text/ch$i.xhtml', 'Capítulo $i'),
    ],
  );

  final file = File(path);
  final raf = file.openSync(mode: FileMode.write);
  try {
    final zip = ZipWriter(fileSink(raf));
    zip.addBytes(
      'mimetype',
      ascii.encode('application/epub+zip'),
      deflate: false,
    );
    zip.addBytes(
      'META-INF/container.xml',
      utf8.encode(containerXml('OEBPS/content.opf')),
    );
    zip.addBytes('OEBPS/content.opf', utf8.encode(opf));
    zip.addBytes('OEBPS/nav.xhtml', utf8.encode(nav));
    zip.addBytes('OEBPS/style.css', utf8.encode(_css));
    for (var i = 0; i < chapters; i++) {
      zip.addBytes(names[i], bodies[i]);
    }
    final imageSize =
        targetBytes -
        zip.offset -
        ZipWriter.localHeaderSize(_imagePath) -
        zip.centralDirectorySize([_imagePath]);
    if (imageSize < 8) {
      throw ArgumentError.value(
        targetBytes,
        'targetBytes',
        'pequeno demais para $chapters capítulos',
      );
    }
    zip.addStoredStream(_imagePath, imageSize, () => _noise(imageSize));
    zip.finish();
  } catch (_) {
    raf.closeSync();
    if (file.existsSync()) file.deleteSync();
    rethrow;
  }
  raf.closeSync();
  return file;
}

const String _css =
    'body { font-family: serif; line-height: 1.4; margin: 5%; }\n'
    'h1 { text-align: center; }\n'
    'p { margin: 0; text-indent: 1.2em; }\n';

/// Texto de preenchimento do capítulo [n]: 12 parágrafos de ~50 palavras.
Uint8List _chapter(int n) {
  var s = 0x2545F491 ^ (n * 0x9E3779B1 & 0xFFFFFFFF);
  int next() {
    s = (s * 1103515245 + 12345) & 0x7FFFFFFF;
    return s >> 8;
  }

  final b = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<!DOCTYPE html>')
    ..writeln(
      '<html xmlns="http://www.w3.org/1999/xhtml" lang="pt-BR" xml:lang="pt-BR">',
    )
    ..writeln('<head><meta charset="utf-8"/><title>Capítulo $n</title>')
    ..writeln('<link rel="stylesheet" type="text/css" href="../style.css"/>')
    ..writeln('</head><body>')
    ..writeln('<h1>Capítulo $n</h1>');
  for (var p = 0; p < 12; p++) {
    b.write('<p>');
    for (var w = 0; w < 50; w++) {
      if (w > 0) b.write(' ');
      b.write(_words[next() % _words.length]);
      if (w % 17 == 16) b.write(',');
    }
    b.writeln('.</p>');
  }
  b.writeln('</body></html>');
  return Uint8List.fromList(utf8.encode(b.toString()));
}

/// Produz [size] bytes pseudoaleatórios (xorshift32) em trechos de 64 KiB,
/// reaproveitando o mesmo buffer. Começa com a assinatura PNG.
Iterable<Uint8List> _noise(int size) sync* {
  final words = Uint32List(_chunkBytes ~/ 4);
  final buffer = words.buffer.asUint8List();
  var s = 0x1F123BB5;
  var remaining = size;
  var first = true;
  while (remaining > 0) {
    for (var i = 0; i < words.length; i++) {
      s ^= (s << 13) & 0xFFFFFFFF;
      s ^= s >> 17;
      s ^= (s << 5) & 0xFFFFFFFF;
      words[i] = s;
    }
    if (first) {
      buffer.setRange(0, 8, const [
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
      ]);
      first = false;
    }
    final n = remaining < _chunkBytes ? remaining : _chunkBytes;
    yield n == _chunkBytes ? buffer : Uint8List.sublistView(buffer, 0, n);
    remaining -= n;
  }
}
