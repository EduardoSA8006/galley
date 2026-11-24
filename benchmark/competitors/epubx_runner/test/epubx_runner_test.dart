import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:test/test.dart';

// ignore: avoid_relative_lib_imports
import '../../../lib/src/competitors/measure.dart';
import '../bin/epubx_runner.dart';

const _opf = '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>T</dc:title>
<dc:identifier id="id">x</dc:identifier><dc:language>en</dc:language></metadata>
<manifest><item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
<item id="c1" href="text/c1.xhtml" media-type="application/xhtml+xml"/>
<item id="c2" href="text/c2.xhtml" media-type="application/xhtml+xml"/></manifest>
<spine toc="ncx"><itemref idref="c1"/><itemref idref="c2"/></spine></package>''';

void main() {
  late Directory tmp;
  late String book;
  const c1 = '<html><body><p>um</p></body></html>';
  const c2 = '<html><body><p>dois é três</p></body></html>';

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('epubx-runner-test-');
    final zip = Archive();
    void add(String name, String text) {
      final bytes = Utf8Encoder().convert(text);
      zip.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    add('mimetype', 'application/epub+zip');
    add(
      'META-INF/container.xml',
      '<?xml version="1.0"?><container version="1.0" '
          'xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles>'
          '<rootfile full-path="OEBPS/content.opf" '
          'media-type="application/oebps-package+xml"/></rootfiles></container>',
    );
    add('OEBPS/content.opf', _opf);
    add(
      'OEBPS/toc.ncx',
      '<?xml version="1.0"?><ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" '
          'version="2005-1"><head><meta name="dtb:uid" content="x"/></head>'
          '<docTitle><text>T</text></docTitle><navMap><navPoint id="n1" '
          'playOrder="1"><navLabel><text>1</text></navLabel>'
          '<content src="text/c1.xhtml"/></navPoint></navMap></ncx>',
    );
    add('OEBPS/text/c1.xhtml', c1);
    add('OEBPS/text/c2.xhtml', c2);
    book = '${tmp.path}/book.epub';
    File(book).writeAsBytesSync(ZipEncoder().encode(zip)!);
  });

  tearDownAll(() => tmp.deleteSync(recursive: true));

  test('abre, soma o spine e lê um recurso pelo caminho completo', () async {
    final adapter = EpubxAdapter();
    await adapter.open(book);
    expect(adapter.spineLength, 2);
    expect(
      await adapter.readAllSpine(),
      utf8.encode(c1).length + utf8.encode(c2).length,
    );
    expect(
      await adapter.readOne('OEBPS/text/c2.xhtml'),
      utf8.encode(c2).length,
    );
    await expectLater(adapter.readOne('OEBPS/nao.xhtml'), throwsStateError);
    await adapter.close();
  });

  test(
    'runAdapterMeasure imprime ns, rss e checksum; livro ausente falha',
    () async {
      final out = StringBuffer();
      final err = StringBuffer();
      expect(
        await runAdapterMeasure(
          EpubxAdapter(),
          'read-all',
          book,
          out: out,
          err: err,
        ),
        0,
      );
      expect(
        out.toString(),
        matches(RegExp(r'ns=\d+\nrss=\d+\nchecksum=\d+\n')),
      );
      expect(
        await runAdapterMeasure(
          EpubxAdapter(),
          'open',
          '${tmp.path}/nao-existe.epub',
          out: out,
          err: err,
        ),
        70,
      );
      expect(
        await runAdapterMeasure(
          EpubxAdapter(),
          'read-one',
          book,
          out: out,
          err: err,
        ),
        64,
      );
    },
  );
}
