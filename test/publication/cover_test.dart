// findCover: os três passos de pacote (spec da Publicação §8.2).
import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/diagnostics/diagnostic.dart';
import 'package:galley/src/publication/cover.dart';
import 'package:galley/src/publication/model.dart';
import 'package:galley/src/publication/opf.dart';

OpfDocument _opf({String? coverId}) => parseOpf(
  '<package><metadata>'
  '${coverId == null ? '' : '<meta name="cover" content="$coverId"/>'}'
  '</metadata><manifest><item id="c1" href="c1.xhtml" '
  'media-type="application/xhtml+xml"/></manifest>'
  '<spine><itemref idref="c1"/></spine></package>',
  opfPath: 'content.opf',
  sink: DiagnosticSink(),
);

ManifestItem _item(
  String id,
  String path, {
  String mediaType = 'image/jpeg',
  Set<String> properties = const {},
  bool missing = false,
  bool remote = false,
}) => ManifestItem(
  id: id,
  path: path,
  mediaType: mediaType,
  properties: properties,
  missing: missing,
  remote: remote,
);

Map<String, ManifestItem> _manifest(List<ManifestItem> items) => {
  for (final i in items) i.id: i,
};

void main() {
  test('1: properties cover-image', () {
    final sink = DiagnosticSink();
    final manifest = _manifest([
      _item('capa-velha', 'Images/cover.jpg'),
      _item('img', 'Images/frente.jpg', properties: {'cover-image'}),
    ]);
    expect(
      findCover(_opf(coverId: 'capa-velha'), manifest, sink: sink),
      'Images/frente.jpg',
    );
    expect(sink.diagnostics, isEmpty);
  });

  test('2: meta name="cover", sem diagnóstico', () {
    final sink = DiagnosticSink();
    final manifest = _manifest([
      _item('cover-a', 'Images/cover-a.jpg'),
      _item('frente', 'Images/frente.png', mediaType: 'image/png'),
    ]);
    expect(
      findCover(_opf(coverId: 'frente'), manifest, sink: sink),
      'Images/frente.png',
    );
    expect(sink.diagnostics, isEmpty);
  });

  test('3: imagem com "cover" no id ou no caminho, com coverHeuristic', () {
    final sink = DiagnosticSink(strict: true);
    final manifest = _manifest([
      _item(
        'texto-cover',
        'Text/cover.xhtml',
        mediaType: 'application/xhtml+xml',
      ),
      _item('i1', 'Images/MyCOVER.JPG'),
    ]);
    expect(findCover(_opf(), manifest, sink: sink), 'Images/MyCOVER.JPG');
    final d = sink.diagnostics.single;
    expect(d.code, EpubDiagnosticCode.coverHeuristic);
    expect(d.severity, EpubSeverity.info);
    expect(d.href, 'Images/MyCOVER.JPG');
  });

  test('missing e remote são pulados em todos os passos', () {
    final sink = DiagnosticSink();
    final manifest = _manifest([
      _item(
        'a',
        'Images/cover.png',
        properties: {'cover-image'},
        missing: true,
      ),
      _item(
        'b',
        'https://x/cover.jpg',
        properties: {'cover-image'},
        remote: true,
      ),
      _item('cover', 'Images/c.jpg', missing: true),
      _item('capa', 'Images/cover2.jpg'),
    ]);
    expect(
      findCover(_opf(coverId: 'cover'), manifest, sink: sink),
      'Images/cover2.jpg',
    );
    expect(sink.diagnostics.single.code, EpubDiagnosticCode.coverHeuristic);
  });

  test('nenhum: null', () {
    final sink = DiagnosticSink();
    expect(
      findCover(
        _opf(coverId: 'nao-existe'),
        _manifest([_item('i', 'Images/foto.jpg')]),
        sink: sink,
      ),
      isNull,
    );
    expect(sink.diagnostics, isEmpty);
  });
}
