/// Bytes de `container.xml`, OPF, NCX e NAV para texto (spec da Publicação
/// §4). A detecção completa de encoding (Shift-JIS e outros) é da IR.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../diagnostics/diagnostic.dart';
import '../diagnostics/exceptions.dart';

/// Bytes do começo lidos como ASCII para achar a declaração.
const int encodingSniffBytes = 1024;

final RegExp _xmlDeclaration = RegExp(
  r'''^\s*<\?xml\s[^>]*?encoding\s*=\s*["']([^"']*)["']''',
);
final RegExp _metaCharset = RegExp(
  r'''<meta\s[^>]*?charset\s*=\s*["']?\s*([A-Za-z0-9_.:\-]+)''',
  caseSensitive: false,
);

enum _Encoding { utf8, latin1, utf16le, utf16be }

/// Decodifica [bytes] de [path]: BOM, senão a declaração `encoding` (e, com
/// [htmlMeta], o `<meta charset>` do NAV) nos primeiros
/// [encodingSniffBytes] bytes, senão UTF-8. UTF-8 inválido e UTF-16 com
/// número ímpar de bytes caem para Latin-1 com `encodingFallback`.
String decodeXml(
  Uint8List bytes, {
  required String path,
  required DiagnosticSink sink,
  bool htmlMeta = false,
}) {
  final n = bytes.length;
  if (n >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
    return _decode(
      Uint8List.sublistView(bytes, 3),
      _Encoding.utf8,
      'utf-8',
      path,
      sink,
    );
  }
  if (n >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _decode(
      Uint8List.sublistView(bytes, 2),
      _Encoding.utf16le,
      'utf-16le',
      path,
      sink,
    );
  }
  if (n >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _decode(
      Uint8List.sublistView(bytes, 2),
      _Encoding.utf16be,
      'utf-16be',
      path,
      sink,
    );
  }
  final declared = _declaredEncoding(bytes, htmlMeta: htmlMeta);
  return _decode(bytes, _encodingOf(declared), declared, path, sink);
}

/// Rótulo declarado, em minúsculas; `null` se não há declaração. Os bytes 0
/// são pulados, para uma declaração em UTF-16 sem BOM ser legível.
String? _declaredEncoding(Uint8List bytes, {required bool htmlMeta}) {
  final end = bytes.length < encodingSniffBytes
      ? bytes.length
      : encodingSniffBytes;
  final ascii = StringBuffer();
  for (var i = 0; i < end; i++) {
    final b = bytes[i];
    if (b != 0) ascii.writeCharCode(b < 0x80 ? b : 0x3F);
  }
  final head = ascii.toString();
  final xml = _xmlDeclaration.firstMatch(head);
  if (xml != null) return xml.group(1)!.trim().toLowerCase();
  if (htmlMeta) {
    final meta = _metaCharset.firstMatch(head);
    if (meta != null) return meta.group(1)!.trim().toLowerCase();
  }
  return null;
}

_Encoding _encodingOf(String? label) => switch (label) {
  'iso-8859-1' || 'latin1' || 'windows-1252' || 'us-ascii' => _Encoding.latin1,
  'utf-16' || 'utf-16le' => _Encoding.utf16le,
  'utf-16be' => _Encoding.utf16be,
  _ => _Encoding.utf8,
};

String _decode(
  Uint8List bytes,
  _Encoding encoding,
  String? declared,
  String path,
  DiagnosticSink sink,
) {
  switch (encoding) {
    case _Encoding.latin1:
      return latin1.decode(bytes);
    case _Encoding.utf8:
      try {
        return utf8.decode(bytes);
      } on FormatException {
        return _fallback(bytes, declared, path, sink);
      }
    case _Encoding.utf16le:
    case _Encoding.utf16be:
      if (bytes.length.isOdd) return _fallback(bytes, declared, path, sink);
      final little = encoding == _Encoding.utf16le;
      final units = Uint16List(bytes.length ~/ 2);
      for (var i = 0; i < units.length; i++) {
        final a = bytes[2 * i];
        final b = bytes[2 * i + 1];
        units[i] = little ? a | b << 8 : a << 8 | b;
      }
      return String.fromCharCodes(units);
  }
}

String _fallback(
  Uint8List bytes,
  String? declared,
  String path,
  DiagnosticSink sink,
) {
  sink.emit(
    EpubDiagnosticCode.encodingFallback,
    href: path,
    message:
        'bytes inválidos em ${declared ?? 'utf-8'}; decodificado como latin1',
    details: {'declared': declared, 'used': 'latin1'},
    onStrict: (m) => EpubPackageException(m, href: path),
  );
  return latin1.decode(bytes);
}
