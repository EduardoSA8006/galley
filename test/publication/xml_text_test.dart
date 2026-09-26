// decodeXml: BOM, declaração, <meta charset> e fallback (spec da Publicação §4).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/diagnostics/diagnostic.dart';
import 'package:galley/src/publication/xml_text.dart';

Uint8List _bytes(List<int> b) => Uint8List.fromList(b);

Uint8List _utf16(String s, {required bool little}) {
  final out = <int>[];
  for (final u in s.codeUnits) {
    out.addAll(little ? [u & 0xFF, u >> 8] : [u >> 8, u & 0xFF]);
  }
  return _bytes(out);
}

String _decode(Uint8List bytes, DiagnosticSink sink, {bool htmlMeta = false}) =>
    decodeXml(bytes, path: 'OEBPS/a.opf', sink: sink, htmlMeta: htmlMeta);

void main() {
  const text = '<?xml version="1.0"?><a>çé</a>';

  test('BOM UTF-8 sai do texto e vence a declaração Latin-1', () {
    final sink = DiagnosticSink();
    final bytes = _bytes([
      0xEF,
      0xBB,
      0xBF,
      ...utf8.encode('<?xml version="1.0" encoding="ISO-8859-1"?><a>çé</a>'),
    ]);
    expect(
      _decode(bytes, sink),
      '<?xml version="1.0" encoding="ISO-8859-1"?><a>çé</a>',
    );
    expect(sink.diagnostics, isEmpty);
  });

  test('BOM UTF-16 LE e BE', () {
    final sink = DiagnosticSink();
    expect(
      _decode(_bytes([0xFF, 0xFE, ..._utf16(text, little: true)]), sink),
      text,
    );
    expect(
      _decode(_bytes([0xFE, 0xFF, ..._utf16(text, little: false)]), sink),
      text,
    );
    expect(sink.diagnostics, isEmpty);
  });

  test('declaração Latin-1 (e seus sinônimos) sem BOM', () {
    for (final label in ['ISO-8859-1', 'latin1', 'windows-1252', 'US-ASCII']) {
      final sink = DiagnosticSink();
      final bytes = _bytes([
        ...ascii.encode('<?xml version="1.0" encoding="$label"?><a>'),
        0xE7,
        0xE9,
        ...ascii.encode('</a>'),
      ]);
      expect(
        _decode(bytes, sink),
        '<?xml version="1.0" encoding="$label"?><a>çé</a>',
        reason: label,
      );
      expect(sink.diagnostics, isEmpty, reason: label);
    }
  });

  test("declaração com aspas simples e 'utf8'", () {
    final sink = DiagnosticSink();
    const source = "<?xml version='1.0' encoding='utf8'?><a>çé</a>";
    expect(_decode(_bytes(utf8.encode(source)), sink), source);
  });

  test('utf-16 declarado sem BOM vira UTF-16 LE', () {
    const source = '<?xml version="1.0" encoding="utf-16"?><a>çé</a>';
    final sink = DiagnosticSink();
    expect(_decode(_utf16(source, little: true), sink), source);
  });

  test('rótulo desconhecido vira UTF-8', () {
    const source = '<?xml version="1.0" encoding="Shift_JIS"?><a>çé</a>';
    final sink = DiagnosticSink();
    expect(_decode(_bytes(utf8.encode(source)), sink), source);
    expect(sink.diagnostics, isEmpty);
  });

  test('<meta charset> só com htmlMeta (NAV)', () {
    final bytes = _bytes([
      ...ascii.encode('<html><head><meta charset="iso-8859-1"/></head>'),
      0xE9,
      ...ascii.encode('</html>'),
    ]);
    final nav = DiagnosticSink();
    expect(_decode(bytes, nav, htmlMeta: true), endsWith('é</html>'));
    expect(nav.diagnostics, isEmpty);
    final opf = DiagnosticSink();
    expect(_decode(bytes, opf), endsWith('é</html>'));
    expect(
      opf.diagnostics.single.code,
      EpubDiagnosticCode.encodingFallback,
      reason: 'fora do NAV, o meta não conta: UTF-8 inválido',
    );
  });

  test('UTF-8 inválido cai para Latin-1 com encodingFallback', () {
    final sink = DiagnosticSink(strict: true);
    final bytes = _bytes([
      ...ascii.encode('<?xml version="1.0" encoding="UTF-8"?><a>'),
      0xE9,
      ...ascii.encode('</a>'),
    ]);
    expect(_decode(bytes, sink), endsWith('<a>é</a>'));
    final d = sink.diagnostics.single;
    expect(d.code, EpubDiagnosticCode.encodingFallback);
    expect(d.severity, EpubSeverity.info);
    expect(d.href, 'OEBPS/a.opf');
    expect(d.details, {'declared': 'utf-8', 'used': 'latin1', 'count': 1});
  });

  test('sem declaração, UTF-8 inválido: declared null', () {
    final sink = DiagnosticSink();
    expect(_decode(_bytes([0x3C, 0x61, 0x3E, 0xE9]), sink), '<a>é');
    expect(sink.diagnostics.single.details['declared'], isNull);
  });

  test('UTF-16 com número ímpar de bytes cai para Latin-1', () {
    final sink = DiagnosticSink();
    final bytes = _bytes([0xFF, 0xFE, 0x3C, 0x00, 0x61]);
    expect(_decode(bytes, sink), '<\u0000a');
    expect(sink.diagnostics.single.details, {
      'declared': 'utf-16le',
      'used': 'latin1',
      'count': 1,
    });
  });

  test('declaração depois dos primeiros 1 024 bytes não conta', () {
    final sink = DiagnosticSink();
    final bytes = _bytes([
      ...List<int>.filled(encodingSniffBytes, 0x20),
      ...ascii.encode('<?xml version="1.0" encoding="latin1"?><a>'),
      0xE9,
    ]);
    _decode(bytes, sink);
    expect(sink.diagnostics.single.code, EpubDiagnosticCode.encodingFallback);
  });
}
