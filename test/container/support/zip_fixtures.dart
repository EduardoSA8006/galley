// ignore_for_file: avoid_relative_lib_imports — tool/ não é pacote; importar por caminho é intencional.
/// ZIPs de teste do contêiner: o `ZipWriter` do corpus e ajustes de bytes
/// para o que ele não cobre (spec do contêiner §9).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:galley/src/container/byte_source.dart';

import '../../../tool/corpus/lib/zip_writer.dart';

export '../../../tool/corpus/lib/zip_writer.dart' show ZipWriter;

/// Conteúdo do `mimetype` da OCF.
const String epubMimetype = 'application/epub+zip';

/// ZIP com `mimetype` stored na frente e as [files] dadas, em ordem.
Uint8List epubZip(
  Map<String, List<int>> files, {
  bool compress = true,
  bool zip64 = false,
}) {
  final w = ZipWriter(forceZip64: zip64)
    ..add('mimetype', ascii.encode(epubMimetype), compress: false);
  for (final MapEntry(key: name, value: data) in files.entries) {
    w.add(name, data, compress: compress);
  }
  return w.build();
}

/// [n] bytes de texto repetitivo (comprime bem, CRC conhecido pelo writer).
Uint8List prose(int n, {int seed = 1}) {
  final words = ['livro', 'página', 'capítulo', 'nota', 'verso', 'texto'];
  final out = BytesBuilder(copy: false);
  var i = seed;
  while (out.length < n) {
    out.add(utf8.encode('${words[i % words.length]}$i '));
    i = (i * 7 + 3) % 10007;
  }
  return Uint8List.sublistView(out.takeBytes(), 0, n);
}

/// [n] bytes pseudoaleatórios (não comprimem).
Uint8List noise(int n, {int seed = 7}) {
  var x = seed;
  return Uint8List.fromList(
    List<int>.generate(n, (_) {
      x = (x * 1103515245 + 12345) & 0x7FFFFFFF;
      return x >> 16 & 0xFF;
    }),
  );
}

/// Posições das estruturas de um ZIP sem comentário e sem ZIP64, como o
/// `ZipWriter` produz.
final class ZipLayout {
  ZipLayout(this.bytes) {
    eocd = bytes.length - 22;
    if (_u32(eocd) != 0x06054b50) {
      throw ArgumentError('ZipLayout: EOCD não está nos últimos 22 bytes');
    }
    cdSize = _u32(eocd + 12);
    cdOffset = _u32(eocd + 16);
    var p = cdOffset;
    while (p < cdOffset + cdSize) {
      central.add(p);
      local.add(_u32(p + 42));
      p += 46 + _u16(p + 28) + _u16(p + 30) + _u16(p + 32);
    }
  }

  final Uint8List bytes;
  late final int eocd;
  late final int cdSize;
  late final int cdOffset;

  /// Offset de cada entrada no central directory, em ordem.
  final List<int> central = [];

  /// Offset do local header de cada entrada, na ordem do central directory.
  final List<int> local = [];

  int _u16(int at) => bytes[at] | bytes[at + 1] << 8;
  int _u32(int at) =>
      ByteData.sublistView(bytes, at, at + 4).getUint32(0, Endian.little);

  int centralU16(int entry, int field) => _u16(central[entry] + field);
  int centralU32(int entry, int field) => _u32(central[entry] + field);
}

Uint8List _copy(Uint8List b) => Uint8List.fromList(b);

void _setU16(Uint8List b, int at, int v) =>
    ByteData.sublistView(b)..setUint16(at, v, Endian.little);

void _setU32(Uint8List b, int at, int v) =>
    ByteData.sublistView(b)..setUint32(at, v, Endian.little);

// Campos do central directory (offset dentro da entrada).
const cdFlags = 8;
const cdMethod = 10;
const cdCrc = 16;
const cdCompressed = 20;
const cdUncompressed = 24;
const cdLocalOffset = 42;

// Campos do local header.
const lhFlags = 6;
const lhMethod = 8;
const lhCrc = 14;
const lhCompressed = 18;
const lhUncompressed = 22;

/// Troca um campo u16 da entrada [entry] no central directory.
Uint8List patchCentralU16(Uint8List zip, int entry, int field, int value) {
  final out = _copy(zip);
  _setU16(out, ZipLayout(zip).central[entry] + field, value);
  return out;
}

/// Troca um campo u32 da entrada [entry] no central directory.
Uint8List patchCentralU32(Uint8List zip, int entry, int field, int value) {
  final out = _copy(zip);
  _setU32(out, ZipLayout(zip).central[entry] + field, value);
  return out;
}

/// Troca um campo u16 do local header da entrada [entry].
Uint8List patchLocalU16(Uint8List zip, int entry, int field, int value) {
  final out = _copy(zip);
  _setU16(out, ZipLayout(zip).local[entry] + field, value);
  return out;
}

/// Método de compressão nos dois cabeçalhos.
Uint8List withMethod(Uint8List zip, int entry, int method) => patchLocalU16(
  patchCentralU16(zip, entry, cdMethod, method),
  entry,
  lhMethod,
  method,
);

/// Liga [bits] na flag dos dois cabeçalhos.
Uint8List withFlagBits(Uint8List zip, int entry, int bits) {
  final l = ZipLayout(zip);
  final out = _copy(zip);
  _setU16(out, l.central[entry] + cdFlags, l.centralU16(entry, cdFlags) | bits);
  final lf =
      out[l.local[entry] + lhFlags] | out[l.local[entry] + lhFlags + 1] << 8;
  _setU16(out, l.local[entry] + lhFlags, lf | bits);
  return out;
}

/// Desliga [bits] na flag dos dois cabeçalhos.
Uint8List withoutFlagBits(Uint8List zip, int entry, int bits) {
  final l = ZipLayout(zip);
  final out = _copy(zip);
  _setU16(
    out,
    l.central[entry] + cdFlags,
    l.centralU16(entry, cdFlags) & ~bits,
  );
  final lf =
      out[l.local[entry] + lhFlags] | out[l.local[entry] + lhFlags + 1] << 8;
  _setU16(out, l.local[entry] + lhFlags, lf & ~bits);
  return out;
}

/// Data descriptor (bit 3) com CRC e tamanhos do local header zerados; o
/// descriptor em si não é gravado (o leitor usa o central directory).
Uint8List withDataDescriptor(Uint8List zip, int entry) {
  final out = withFlagBits(zip, entry, 0x0008);
  final at = ZipLayout(out).local[entry];
  _setU32(out, at + lhCrc, 0);
  _setU32(out, at + lhCompressed, 0);
  _setU32(out, at + lhUncompressed, 0);
  return out;
}

/// Troca os bytes do nome da entrada [entry] (mesmo tamanho) nos dois
/// cabeçalhos.
Uint8List withRawName(Uint8List zip, int entry, List<int> name) {
  final l = ZipLayout(zip);
  if (l.centralU16(entry, 28) != name.length) {
    throw ArgumentError('withRawName: o nome novo precisa ter o mesmo tamanho');
  }
  return _copy(zip)
    ..setRange(l.central[entry] + 46, l.central[entry] + 46 + name.length, name)
    ..setRange(l.local[entry] + 30, l.local[entry] + 30 + name.length, name);
}

/// Comentário no EOCD.
Uint8List withComment(Uint8List zip, List<int> comment) {
  final out = Uint8List.fromList([...zip, ...comment]);
  _setU16(out, zip.length - 2, comment.length);
  return out;
}

/// Comentário que contém uma assinatura de EOCD falsa (sem comentário que
/// feche no fim do arquivo).
Uint8List withFakeEocdInComment(Uint8List zip) => withComment(zip, [
  ...ascii.encode('antes '),
  0x50, 0x4b, 0x05, 0x06, // assinatura do EOCD
  ...List<int>.filled(18, 0x41),
  ...ascii.encode(' depois'),
]);

/// Disco do EOCD e disco do central directory.
Uint8List withEocdDisks(Uint8List zip, {int disk = 0, int cdDisk = 0}) {
  final out = _copy(zip);
  final eocd = ZipLayout(zip).eocd;
  _setU16(out, eocd + 4, disk);
  _setU16(out, eocd + 6, cdDisk);
  return out;
}

/// Contagem de entradas do EOCD (as duas).
Uint8List withEocdCount(Uint8List zip, int count) {
  final out = _copy(zip);
  final eocd = ZipLayout(zip).eocd;
  _setU16(out, eocd + 8, count);
  _setU16(out, eocd + 10, count);
  return out;
}

/// Offset do central directory no EOCD.
Uint8List withEocdCdOffset(Uint8List zip, int cdOffset) {
  final out = _copy(zip);
  _setU32(out, ZipLayout(zip).eocd + 16, cdOffset);
  return out;
}

/// Tira os últimos [cut] bytes do central directory e ajusta o `cdSize`:
/// a última entrada passa a atravessar o fim.
Uint8List withTruncatedCentralDirectory(Uint8List zip, int cut) {
  final l = ZipLayout(zip);
  final cdEnd = l.cdOffset + l.cdSize;
  final out = Uint8List.fromList([
    ...zip.sublist(0, cdEnd - cut),
    ...zip.sublist(cdEnd),
  ]);
  _setU32(out, out.length - 22 + 12, l.cdSize - cut);
  return out;
}

/// Assinatura errada na entrada [entry] do central directory.
Uint8List withBadCentralSignature(Uint8List zip, int entry) =>
    patchCentralU32(zip, entry, 0, 0x02014b51);

/// Bytes arbitrários antes do ZIP; os offsets internos não mudam.
Uint8List withPrefix(Uint8List zip, int length) =>
    Uint8List.fromList([...noise(length, seed: 99), ...zip]);

/// Extra field de [extraLength] bytes no local header da entrada [entry],
/// com offsets e EOCD ajustados.
Uint8List withLocalExtra(Uint8List zip, int entry, int extraLength) {
  final l = ZipLayout(zip);
  final at = l.local[entry];
  final nameLength = zip[at + 26] | zip[at + 27] << 8;
  final oldExtra = zip[at + 28] | zip[at + 29] << 8;
  final insertAt = at + 30 + nameLength + oldExtra;
  final extra = Uint8List(extraLength);
  // Um bloco 0xCAFE com o resto do espaço.
  _setU16(extra, 0, 0xCAFE);
  _setU16(extra, 2, extraLength - 4);
  final out = Uint8List.fromList([
    ...zip.sublist(0, insertAt),
    ...extra,
    ...zip.sublist(insertAt),
  ]);
  _setU16(out, at + 28, oldExtra + extraLength);
  // O central directory inteiro fica depois do ponto de inserção.
  _setU32(out, out.length - 22 + 16, l.cdOffset + extraLength);
  for (var i = 0; i < l.central.length; i++) {
    if (l.local[i] > at) {
      _setU32(
        out,
        l.central[i] + extraLength + cdLocalOffset,
        l.local[i] + extraLength,
      );
    }
  }
  return out;
}

/// Fonte que conta chamadas e bytes lidos.
final class CountingByteSource implements EpubByteSource {
  CountingByteSource(this.inner);

  final EpubByteSource inner;
  int calls = 0;
  int bytesRead = 0;
  bool closed = false;

  /// Faixas pedidas, em ordem.
  final List<(int, int)> ranges = [];

  void reset() {
    calls = 0;
    bytesRead = 0;
    ranges.clear();
  }

  @override
  Future<int> get length => inner.length;

  @override
  Future<Uint8List> readRange(int offset, int length) {
    calls++;
    bytesRead += length;
    ranges.add((offset, length));
    return inner.readRange(offset, length);
  }

  @override
  Future<void> close() {
    closed = true;
    return inner.close();
  }
}

/// Fonte cuja leitura sempre falha com [error].
final class FailingByteSource implements EpubByteSource {
  FailingByteSource(this.error, {this.size = 1000});

  final Object error;
  final int size;
  bool closed = false;

  @override
  Future<int> get length async => size;

  @override
  Future<Uint8List> readRange(int offset, int length) async => throw error;

  @override
  Future<void> close() async => closed = true;
}

/// Num ZIP gerado com `forceZip64`, grava [lo]/[hi] no campo [field] do
/// extra 0x0001 da entrada [entry] do central directory (0: tamanho
/// original, 1: comprimido, 2: offset).
Uint8List withZip64ExtraValue(
  Uint8List zip,
  int entry,
  int field, {
  required int lo,
  required int hi,
}) {
  final out = _copy(zip);
  final data = ByteData.sublistView(out);
  final locator = out.length - 22 - 20;
  final eocd64 = data.getUint32(locator + 8, Endian.little);
  var p = data.getUint32(eocd64 + 48, Endian.little);
  for (var i = 0; i < entry; i++) {
    p +=
        46 +
        data.getUint16(p + 28, Endian.little) +
        data.getUint16(p + 30, Endian.little) +
        data.getUint16(p + 32, Endian.little);
  }
  final at = p + 46 + data.getUint16(p + 28, Endian.little) + 4 + field * 8;
  data
    ..setUint32(at, lo, Endian.little)
    ..setUint32(at + 4, hi, Endian.little);
  return out;
}

/// Total de discos no locator ZIP64.
Uint8List withZip64TotalDisks(Uint8List zip, int disks) {
  final out = _copy(zip);
  _setU32(out, out.length - 22 - 20 + 16, disks);
  return out;
}
