import 'dart:io';
import 'dart:typed_data';

import 'hashes.dart';

/// PNG RGB 8 bits, sem filtro, com um degradê simples para não comprimir a zero.
Uint8List png(int width, int height, {int seed = 0}) {
  final raw = BytesBuilder(copy: false);
  for (var y = 0; y < height; y++) {
    raw.addByte(0); // filtro None
    for (var x = 0; x < width; x++) {
      raw
        ..addByte((x * 255 ~/ (width == 1 ? 1 : width - 1) + seed) & 0xFF)
        ..addByte((y * 255 ~/ (height == 1 ? 1 : height - 1) + seed) & 0xFF)
        ..addByte(((x + y) ~/ 2 + seed) & 0xFF);
    }
  }
  final idat = ZLibCodec(level: 6).encode(raw.toBytes());

  final ihdr = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 2) // truecolor
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);

  final out = BytesBuilder(copy: false)
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  _chunk(out, 'IHDR', ihdr.buffer.asUint8List());
  _chunk(out, 'IDAT', idat);
  _chunk(out, 'IEND', const []);
  return out.toBytes();
}

void _chunk(BytesBuilder out, String type, List<int> data) {
  final typeBytes = type.codeUnits;
  final len = ByteData(4)..setUint32(0, data.length);
  final crc = ByteData(4)..setUint32(0, crc32([...typeBytes, ...data]));
  out
    ..add(len.buffer.asUint8List())
    ..add(typeBytes)
    ..add(data)
    ..add(crc.buffer.asUint8List());
}
