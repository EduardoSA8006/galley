import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/galley.dart';
import 'package:galley/src/features/container/data/fonts/font_deobfuscator.dart';

import '../../support/epub_builder.dart';
import '../../support/zip_builder.dart';

const _uuid = 'urn:uuid:12345678-1234-1234-1234-123456789abc';
const _cases = 2000;
const _perCase = Duration(seconds: 2);

String _xhtml(String body) =>
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>t</title></head>'
    '<body>$body</body></html>';

/// EPUB válido que exercita muitos caminhos: deflate + stored, nav + NCX,
/// fonte ofuscada IDPF com encryption.xml, capa e 3 itens de spine.
Uint8List _base({required bool zip64}) {
  final font = Uint8List.fromList([for (var i = 0; i < 2000; i++) i % 251]);
  final obfuscated = deobfuscateIdpf(font, _uuid);
  final files = <String, Object>{
    'META-INF/encryption.xml':
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container" '
        'xmlns:enc="http://www.w3.org/2001/04/xmlenc#">'
        '<enc:EncryptedData>'
        '<enc:EncryptionMethod Algorithm="http://www.idpf.org/2008/embedding"/>'
        '<enc:CipherData><enc:CipherReference URI="OEBPS/f.otf"/>'
        '</enc:CipherData></enc:EncryptedData></encryption>',
    'OEBPS/content.opf': opf3(
      manifest:
          '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" '
          'properties="nav"/>'
          '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>'
          '<item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>'
          '<item id="c2" href="c2.xhtml" media-type="application/xhtml+xml"/>'
          '<item id="c3" href="c3.xhtml" media-type="application/xhtml+xml"/>'
          '<item id="cover" href="cover.png" media-type="image/png" '
          'properties="cover-image"/>'
          '<item id="f" href="f.otf" media-type="font/otf"/>',
      spine: '<itemref idref="c1"/><itemref idref="c2"/><itemref idref="c3"/>',
      spineAttrs: 'toc="ncx"',
    ),
    'OEBPS/nav.xhtml': _xhtml(
      '<nav xmlns:epub="http://www.idpf.org/2007/ops" epub:type="toc"><ol>'
      '<li><a href="c1.xhtml">Um</a></li><li><a href="c2.xhtml">Dois</a></li>'
      '</ol></nav>',
    ),
    'OEBPS/toc.ncx':
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">'
        '<navMap><navPoint id="n1" playOrder="1"><navLabel><text>Um</text>'
        '</navLabel><content src="c1.xhtml"/></navPoint></navMap></ncx>',
    'OEBPS/c1.xhtml': _xhtml('<p>${'Olá mundo. ' * 40}</p>'),
    'OEBPS/c2.xhtml': _xhtml('<p>${'Segundo capítulo. ' * 40}</p>'),
    'OEBPS/c3.xhtml': _xhtml('<p>Terceiro</p>'),
    'OEBPS/cover.png': List<int>.generate(300, (i) => (i * 7) % 256),
    'OEBPS/f.otf': obfuscated,
  };
  if (!zip64) return buildEpub(files);
  final zip = ZipBuilder()
    ..addFile('mimetype', utf8.encode('application/epub+zip'), deflate: false)
    ..addFile(
      'META-INF/container.xml',
      utf8.encode(
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<container version="1.0" '
        'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
        '<rootfiles><rootfile full-path="OEBPS/content.opf" '
        'media-type="application/oebps-package+xml"/></rootfiles></container>',
      ),
    );
  files.forEach((n, c) {
    zip.addFile(n, c is String ? utf8.encode(c) : c as List<int>);
  });
  return zip.build(zip64: true);
}

int _find(Uint8List b, List<int> sig, {bool last = false}) {
  var found = -1;
  for (var i = 0; i + sig.length <= b.length; i++) {
    var ok = true;
    for (var j = 0; j < sig.length; j++) {
      if (b[i + j] != sig[j]) {
        ok = false;
        break;
      }
    }
    if (ok) {
      found = i;
      if (!last) return i;
    }
  }
  return found;
}

const _eocd = [0x50, 0x4b, 0x05, 0x06];
const _cdh = [0x50, 0x4b, 0x01, 0x02];

Uint8List _mutate(Uint8List base, Random rnd) {
  switch (rnd.nextInt(5)) {
    case 0:
      return Uint8List.sublistView(base, 0, rnd.nextInt(base.length));
    case 1:
      final out = Uint8List.fromList(base);
      for (var n = 1 + rnd.nextInt(16); n > 0; n--) {
        out[rnd.nextInt(out.length)] = rnd.nextInt(256);
      }
      return out;
    case 2:
      final out = Uint8List.fromList(base);
      final cd = _find(out, _cdh);
      final end = _find(out, _eocd, last: true);
      if (cd < 0 || end <= cd) return out;
      final start = cd + rnd.nextInt(end - cd);
      final stop = min(end, start + 1 + rnd.nextInt(64));
      out.fillRange(start, stop, 0);
      return out;
    case 3:
      final end = _find(base, _eocd, last: true);
      return Uint8List.fromList([...base, ...base.sublist(max(0, end))]);
    default:
      // Mutação concentrada no diretório central e no EOCD.
      final out = Uint8List.fromList(base);
      final cd = max(0, _find(out, _cdh));
      for (var n = 1 + rnd.nextInt(8); n > 0; n--) {
        out[cd + rnd.nextInt(out.length - cd)] = rnd.nextInt(256);
      }
      return out;
  }
}

/// Abre e lê tudo; devolve `null` se OK ou se só houve [GalleyException].
Future<String?> _exercise(Uint8List bytes) async {
  EpubBook? book;
  try {
    book = await EpubBook.fromBytes(bytes);
    for (final item in book.manifest.values.toList()) {
      try {
        await book.resource(item.path);
      } on GalleyException {
        // esperado
      }
    }
  } on GalleyException {
    // esperado
  } catch (e, s) {
    return 'exceção inesperada ${e.runtimeType}: $e\n$s';
  } finally {
    try {
      await book?.close();
    } on GalleyException {
      // esperado
    } catch (e, s) {
      // ignore: control_flow_in_finally
      return 'close() lançou ${e.runtimeType}: $e\n$s';
    }
  }
  return null;
}

void main() {
  test('bases válidas abrem sem diagnósticos de erro', () async {
    for (final z in [false, true]) {
      final book = await EpubBook.fromBytes(_base(zip64: z));
      expect(book.manifest, hasLength(7), reason: 'zip64=$z');
      expect(book.spine.items, hasLength(3));
      await book.close();
    }
  });

  test('fuzz: $_cases variações só lançam GalleyException', () async {
    final rnd = Random(42);
    final bases = [_base(zip64: false), _base(zip64: true)];
    final failures = <String>[];
    for (var i = 0; i < _cases; i++) {
      final base = bases[i % 2];
      final bytes = _mutate(base, rnd);
      final sw = Stopwatch()..start();
      String? problem;
      try {
        problem = await _exercise(bytes).timeout(_perCase);
      } on TimeoutException {
        problem = 'timeout > ${_perCase.inSeconds}s';
      }
      if (problem == null && sw.elapsed > _perCase) {
        problem = 'demorou ${sw.elapsed}';
      }
      if (problem != null) {
        failures.add('caso $i (semente 42, base ${i % 2}): $problem');
      }
    }
    expect(failures, isEmpty, reason: failures.take(10).join('\n---\n'));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
