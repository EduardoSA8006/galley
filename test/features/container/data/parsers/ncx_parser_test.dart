import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/core/diagnostics/diagnostic_codes.dart';
import 'package:galley/src/core/diagnostics/diagnostic_sink.dart';
import 'package:galley/src/features/container/data/parsers/ncx_parser.dart';

String _ncx(String inner) =>
    '<?xml version="1.0"?><ncx xmlns="http://www.daisy.org/z3986/2005/ncx/">'
    '$inner</ncx>';

String _point(
  String id,
  int order,
  String label,
  String src, [
  String c = '',
]) =>
    '<navPoint id="$id" playOrder="$order"><navLabel><text>$label</text>'
    '</navLabel><content src="$src"/>$c</navPoint>';

void main() {
  test('navPoints aninhados ordenados por playOrder por nível', () {
    final sink = CollectingDiagnosticSink();
    final nav = parseNcx(
      _ncx(
        '<navMap>'
        '${_point('b', 3, 'B', 'b.xhtml')}'
        '${_point('a', 1, 'A', 'text/a%201.xhtml#f', _point('a2', 5, 'A2', 'a2.xhtml') + _point('a1', 2, 'A1', 'a1.xhtml'))}'
        '</navMap>',
      ),
      ncxPath: 'OEBPS/toc.ncx',
      sink: sink,
    )!;
    expect(nav.toc.map((p) => p.label), ['A', 'B']);
    expect(nav.toc[0].path, 'OEBPS/text/a 1.xhtml');
    expect(nav.toc[0].fragment, 'f');
    expect(nav.toc[0].children.map((p) => p.label), ['A1', 'A2']);
    expect(sink.diagnostics, isEmpty);
  });

  test('sem playOrder em todos mantém a ordem do documento', () {
    final nav = parseNcx(
      _ncx(
        '<navMap>'
        '<navPoint playOrder="2"><navLabel><text>B</text></navLabel>'
        '<content src="b.xhtml"/></navPoint>'
        '<navPoint><navLabel><text>A</text></navLabel>'
        '<content src="a.xhtml"/></navPoint></navMap>',
      ),
      ncxPath: 'toc.ncx',
      sink: CollectingDiagnosticSink(),
    )!;
    expect(nav.toc.map((p) => p.label), ['B', 'A']);
  });

  test('pageList', () {
    final nav = parseNcx(
      _ncx(
        '<navMap/><pageList><pageTarget type="normal" value="1">'
        '<navLabel><text>1</text></navLabel><content src="p.xhtml#p1"/>'
        '</pageTarget></pageList>',
      ),
      ncxPath: 'OEBPS/toc.ncx',
      sink: CollectingDiagnosticSink(),
    )!;
    expect(nav.pageList.single.label, '1');
    expect(nav.pageList.single.path, 'OEBPS/p.xhtml');
    expect(nav.pageList.single.fragment, 'p1');
  });

  test('NCX sem namespace é aceito', () {
    final nav = parseNcx(
      '<ncx><navMap><navPoint><navLabel><text>X</text></navLabel>'
      '<content src="x.xhtml"/></navPoint></navMap></ncx>',
      ncxPath: 'toc.ncx',
      sink: CollectingDiagnosticSink(),
    )!;
    expect(nav.toc.single.label, 'X');
  });

  test('NCX inválido devolve null e ncx.invalid', () {
    final sink = CollectingDiagnosticSink();
    expect(parseNcx('<ncx><navMap>', ncxPath: 't.ncx', sink: sink), isNull);
    expect(sink.diagnostics.single.code, DiagnosticCodes.ncxInvalid);
  });
}
