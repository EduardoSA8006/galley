// parseNcx: navMap, pageList, playOrder e limites (spec da Publicação §7.3).
import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/publication/nav.dart';
import 'package:galley/src/publication/ncx.dart';
import 'package:xml/xml.dart';

String _ncx(String body) =>
    '<?xml version="1.0"?>'
    '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">'
    '<head/><docTitle><text>Livro</text></docTitle>$body</ncx>';

String _point(String label, String? src, {String children = '', int? order}) =>
    '<navPoint id="p"${order == null ? '' : ' playOrder="$order"'}>'
    '<navLabel><text>$label</text></navLabel>'
    '${src == null ? '' : '<content src="$src"/>'}$children</navPoint>';

int _depth(List<NavEntry> entries) {
  var max = 0;
  for (final e in entries) {
    final d = 1 + _depth(e.children);
    if (d > max) max = d;
  }
  return max;
}

void main() {
  test('navMap aninhado', () {
    final ncx = parseNcx(
      _ncx(
        '<navMap>${_point('Um', 'c1.xhtml', children: _point('Um.um', 'c1.xhtml#s1'))}'
        '${_point('Dois', 'c2.xhtml')}</navMap>',
      ),
    );
    expect(ncx.toc.map((e) => (e.title, e.href)), [
      ('Um', 'c1.xhtml'),
      ('Dois', 'c2.xhtml'),
    ]);
    expect(ncx.toc.first.children.single.href, 'c1.xhtml#s1');
    expect(ncx.truncated, isFalse);
  });

  test('pageList com pageTarget', () {
    final ncx = parseNcx(
      _ncx(
        '<navMap/><pageList>'
        '<pageTarget type="normal" value="1"><navLabel><text>1</text>'
        '</navLabel><content src="c1.xhtml#pg1"/></pageTarget>'
        '<pageTarget type="normal" value="2"><navLabel><text>2</text>'
        '</navLabel><content src="c1.xhtml#pg2"/></pageTarget></pageList>',
      ),
    );
    expect(ncx.pageList.map((e) => (e.title, e.href)), [
      ('1', 'c1.xhtml#pg1'),
      ('2', 'c1.xhtml#pg2'),
    ]);
  });

  test('playOrder fora de ordem é ignorado: vale a ordem do documento', () {
    final ncx = parseNcx(
      _ncx(
        '<navMap>${_point('B', 'b.xhtml', order: 2)}'
        '${_point('A', 'a.xhtml', order: 1)}</navMap>',
      ),
    );
    expect(ncx.toc.map((e) => e.title), ['B', 'A']);
  });

  test('navPoint sem content não tem alvo; rótulo colapsado', () {
    final ncx = parseNcx(
      _ncx('<navMap>${_point('  Parte\n  I ', null)}</navMap>'),
    );
    expect(ncx.toc.single.title, 'Parte I');
    expect(ncx.toc.single.href, isNull);
  });

  test('sem namespace e com prefixo', () {
    final ncx = parseNcx(
      '<n:ncx xmlns:n="http://www.daisy.org/z3986/2005/ncx/"><n:navMap>'
      '<n:navPoint><n:navLabel><n:text>X</n:text></n:navLabel>'
      '<n:content src="x.xhtml"/></n:navPoint></n:navMap></n:ncx>',
    );
    expect(ncx.toc.single.href, 'x.xhtml');
    expect(
      parseNcx('<ncx><navMap>${_point('Y', 'y.xhtml')}</navMap></ncx>')
          .toc
          .single
          .title,
      'Y',
    );
  });

  test('XML inválido lança XmlException', () {
    expect(() => parseNcx('<ncx><navMap>'), throwsA(isA<XmlException>()));
  });

  test('limites: profundidade 64 e 100 000 entradas', () {
    var nested = '';
    for (var i = 0; i < 70; i++) {
      nested = _point('N$i', 'n.xhtml', children: nested);
    }
    final deep = parseNcx(_ncx('<navMap>$nested</navMap>'));
    expect(_depth(deep.toc), maxNavDepth);
    expect(deep.truncated, isTrue);

    final many = parseNcx(
      _ncx('<navMap>${_point('x', 'x.xhtml') * (maxNavEntries + 1)}</navMap>'),
    );
    expect(many.toc, hasLength(maxNavEntries));
    expect(many.truncated, isTrue);
  });

  test('64 níveis exatos: sem corte, profundidade 64', () {
    var nested = '';
    for (var i = 0; i < 64; i++) {
      nested = _point('N$i', 'n.xhtml', children: nested);
    }
    final deep = parseNcx(_ncx('<navMap>$nested</navMap>'));
    expect(_depth(deep.toc), maxNavDepth);
    expect(deep.truncated, isFalse);
  });

  test('65 níveis: corte, profundidade continua 64', () {
    var nested = '';
    for (var i = 0; i < 65; i++) {
      nested = _point('N$i', 'n.xhtml', children: nested);
    }
    final deep = parseNcx(_ncx('<navMap>$nested</navMap>'));
    expect(_depth(deep.toc), maxNavDepth);
    expect(deep.truncated, isTrue);
  });

  test('exatamente maxNavEntries no navMap: sem corte', () {
    final ncx = parseNcx(
      _ncx('<navMap>${_point('x', 'x.xhtml') * maxNavEntries}</navMap>'),
    );
    expect(ncx.toc, hasLength(maxNavEntries));
    expect(ncx.truncated, isFalse);
  });

  test('limite do pageList: 100 001 pageTarget corta', () {
    String target(String label) =>
        '<pageTarget><navLabel><text>$label</text></navLabel>'
        '<content src="c.xhtml"/></pageTarget>';
    final ncx = parseNcx(
      _ncx(
        '<navMap/><pageList>${target('p') * (maxNavEntries + 1)}</pageList>',
      ),
    );
    expect(ncx.pageList, hasLength(maxNavEntries));
    expect(ncx.truncated, isTrue);
  });

  group('foco de revisão', () {
    test('DOCTYPE do NCX 2005-1 (EPUB2)', () {
      final ncx = parseNcx(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN" '
        '"http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">\n'
        '${_ncx('<navMap>${_point('A', 'a.xhtml')}</navMap>').substring('<?xml version="1.0"?>'.length)}',
      );
      expect(ncx.toc.single.href, 'a.xhtml');
    });

    test('100 000 níveis de navPoint: sem estouro de pilha, truncated', () {
      final deep =
          '<ncx><navMap>'
          '${'<navPoint><navLabel><text>t</text></navLabel>' * 100000}'
          '${'</navPoint>' * 100000}</navMap></ncx>';
      final sw = Stopwatch()..start();
      final ncx = parseNcx(deep);
      sw.stop();
      expect(_depth(ncx.toc), maxNavDepth);
      expect(ncx.truncated, isTrue);
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
    });
  });
}
