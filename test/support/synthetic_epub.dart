import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:galley/src/features/container/data/zip/crc32.dart';

const int _chunk = 64 * 1024;
const String _imagePath = 'OEBPS/images/filler.bin';

/// Grava em [file], em streaming, um EPUB válido de exatamente [targetBytes]
/// bytes (apenas uso em testes).
///
/// Há [chapters] capítulos pequenos e uma imagem armazenada (sem compressão)
/// que completa o tamanho. Nada é montado em memória além de um trecho de
/// 64 KiB. O arquivo não usa zip64, então [targetBytes] deve ser < 4 GiB.
Future<void> writeSyntheticEpubTo(
  File file, {
  required int targetBytes,
  int chapters = 200,
}) async {
  final sink = file.openSync(mode: FileMode.write);
  final central = BytesBuilder(copy: false);
  var offset = 0;
  var count = 0;

  void u16(BytesBuilder b, int v) => b.add([v & 0xFF, (v >> 8) & 0xFF]);
  void u32(BytesBuilder b, int v) =>
      b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);

  int localSize(String name) => 30 + utf8.encode(name).length;
  int centralSize(String name) => 46 + utf8.encode(name).length;

  void header(String name, int crc, int size, int entryOffset) {
    final n = utf8.encode(name);
    final h = BytesBuilder(copy: false);
    u32(h, 0x04034b50);
    u16(h, 20);
    u16(h, 0x800);
    u16(h, 0);
    u16(h, 0);
    u16(h, 0x21);
    u32(h, crc);
    u32(h, size);
    u32(h, size);
    u16(h, n.length);
    u16(h, 0);
    h.add(n);
    sink.writeFromSync(h.takeBytes());
    offset += 30 + n.length;

    final c = central;
    u32(c, 0x02014b50);
    u16(c, 20);
    u16(c, 20);
    u16(c, 0x800);
    u16(c, 0);
    u16(c, 0);
    u16(c, 0x21);
    u32(c, crc);
    u32(c, size);
    u32(c, size);
    u16(c, n.length);
    u16(c, 0);
    u16(c, 0);
    u16(c, 0);
    u16(c, 0);
    u32(c, 0);
    u32(c, entryOffset);
    c.add(n);
    count++;
  }

  void addBytes(String name, List<int> data) {
    header(name, crc32(data), data.length, offset);
    sink.writeFromSync(data);
    offset += data.length;
  }

  try {
    addBytes('mimetype', ascii.encode('application/epub+zip'));
    addBytes(
      'META-INF/container.xml',
      utf8.encode(
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<container version="1.0" '
        'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
        '<rootfiles><rootfile full-path="OEBPS/content.opf" '
        'media-type="application/oebps-package+xml"/></rootfiles></container>',
      ),
    );
    final manifest = StringBuffer(
      '<item id="nav" href="nav.xhtml" '
      'media-type="application/xhtml+xml" properties="nav"/>'
      '<item id="img" href="images/filler.bin" '
      'media-type="application/octet-stream"/>',
    );
    final spine = StringBuffer();
    final toc = StringBuffer();
    for (var i = 1; i <= chapters; i++) {
      manifest.write(
        '<item id="c$i" href="ch$i.xhtml" media-type="application/xhtml+xml"/>',
      );
      spine.write('<itemref idref="c$i"/>');
      toc.write('<li><a href="ch$i.xhtml">Capítulo $i</a></li>');
    }
    addBytes(
      'OEBPS/content.opf',
      utf8.encode(
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<package xmlns="http://www.idpf.org/2007/opf" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" version="3.0" '
        'unique-identifier="bookid"><metadata>'
        '<dc:title>Sintético</dc:title>'
        '<dc:identifier id="bookid">urn:uuid:5e1d7a40-9b2c-4f63-8a15-7c0d4e9b21aa</dc:identifier>'
        '<dc:language>pt-BR</dc:language>'
        '<meta property="dcterms:modified">2024-01-01T00:00:00Z</meta>'
        '</metadata><manifest>$manifest</manifest>'
        '<spine>$spine</spine></package>',
      ),
    );
    addBytes(
      'OEBPS/nav.xhtml',
      utf8.encode(
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<html xmlns="http://www.w3.org/1999/xhtml" '
        'xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Sumário</title>'
        '</head><body><nav epub:type="toc"><ol>$toc</ol></nav></body></html>',
      ),
    );
    for (var i = 1; i <= chapters; i++) {
      addBytes(
        'OEBPS/ch$i.xhtml',
        utf8.encode(
          '<?xml version="1.0" encoding="UTF-8"?>'
          '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>$i</title>'
          '</head><body><h1>Capítulo $i</h1><p>${'texto ' * 40}</p></body></html>',
        ),
      );
    }

    // A imagem completa o tamanho: local + dados + diretório central
    // (incluindo a própria entrada) + EOCD de 22 bytes.
    final imageSize =
        targetBytes -
        offset -
        localSize(_imagePath) -
        (central.length + centralSize(_imagePath)) -
        22;
    if (imageSize < 1) {
      throw ArgumentError.value(targetBytes, 'targetBytes', 'pequeno demais');
    }
    final chunk = Uint8List(_chunk);
    for (var i = 0; i < chunk.length; i++) {
      chunk[i] = (i * 31 + 7) & 0xFF;
    }
    var crc = 0;
    for (var left = imageSize; left > 0; left -= _chunk) {
      final n = left < _chunk ? left : _chunk;
      crc = crc32(
        n == _chunk ? chunk : Uint8List.sublistView(chunk, 0, n),
        crc,
      );
    }
    header(_imagePath, crc, imageSize, offset);
    for (var left = imageSize; left > 0; left -= _chunk) {
      final n = left < _chunk ? left : _chunk;
      sink.writeFromSync(
        n == _chunk ? chunk : Uint8List.sublistView(chunk, 0, n),
      );
    }
    offset += imageSize;

    final cdOffset = offset;
    final cd = central.takeBytes();
    sink.writeFromSync(cd);
    final e = BytesBuilder(copy: false);
    u32(e, 0x06054b50);
    u16(e, 0);
    u16(e, 0);
    u16(e, count);
    u16(e, count);
    u32(e, cd.length);
    u32(e, cdOffset);
    u16(e, 0);
    sink.writeFromSync(e.takeBytes());
  } finally {
    sink.closeSync();
  }
}
