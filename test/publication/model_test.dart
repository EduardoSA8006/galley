// Modelo da Publicação: imutabilidade, NavTarget e SectionKind (spec §3, §6.4).
import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/publication/metadata.dart';
import 'package:galley/src/publication/model.dart';

void main() {
  test('sectionKindOf', () {
    expect(sectionKindOf('application/xhtml+xml'), SectionKind.xhtml);
    expect(sectionKindOf('text/html'), SectionKind.xhtml);
    expect(sectionKindOf('text/x-oeb1-document'), SectionKind.xhtml);
    expect(sectionKindOf('image/png'), SectionKind.image);
    expect(sectionKindOf('image/svg+xml'), SectionKind.image);
    expect(sectionKindOf('application/pdf'), SectionKind.unsupported);
    expect(sectionKindOf(''), SectionKind.unsupported);
  });

  test('SpineItem.kind vem do content', () {
    final pdf = ManifestItem(
      id: 'p',
      path: 'a.pdf',
      mediaType: 'application/pdf',
    );
    final png = ManifestItem(id: 'i', path: 'a.png', mediaType: 'image/png');
    final s = SpineItem(idref: 'p', item: pdf, content: png, linear: true);
    expect(pdf.kind, SectionKind.unsupported);
    expect(s.kind, SectionKind.image);
  });

  test('NavTarget tem igualdade de valor', () {
    final built = NavTarget('a.xhtml', ['x'].single);
    expect(built, const NavTarget('a.xhtml', 'x'));
    expect(built.hashCode, const NavTarget('a.xhtml', 'x').hashCode);
    expect({built, const NavTarget('a.xhtml', 'x')}, hasLength(1));
    expect(const NavTarget('a.xhtml'), isNot(const NavTarget('a.xhtml', 'x')));
    expect(built.toString(), 'a.xhtml#x');
  });

  test('coleções do modelo são não modificáveis', () {
    final item = ManifestItem(
      id: 'c',
      path: 'c.xhtml',
      mediaType: 'application/xhtml+xml',
      properties: {'nav'},
    );
    expect(() => item.properties.add('x'), throwsUnsupportedError);
    final point = NavPoint(
      title: 't',
      children: [NavPoint(title: 'f')],
    );
    expect(() => point.children.clear(), throwsUnsupportedError);
    final spine = [
      SpineItem(idref: 'c', item: item, content: item, linear: true),
    ];
    final p = EpubPublication(
      opfPath: 'content.opf',
      version: '3.0',
      metadata: EpubMetadata(),
      manifest: {'c': item},
      spine: spine,
      toc: [point],
      landmarks: const [],
      pageList: const [],
      coverPath: null,
      navPath: null,
      ncxPath: null,
      direction: EpubReadingDirection.auto,
      layout: EpubLayoutMode.reflowable,
      uniqueIdentifiers: const ['u'],
      identifiers: const ['u'],
    );
    spine.clear();
    expect(p.spine, hasLength(1), reason: 'cópia, não view');
    expect(() => p.manifest['x'] = item, throwsUnsupportedError);
    expect(() => p.toc.add(point), throwsUnsupportedError);
    expect(() => p.identifiers.add('v'), throwsUnsupportedError);
  });

  test('EpubMetadata: listas e raw não modificáveis, inclusive os valores', () {
    final m = EpubMetadata(
      authors: ['A'],
      subjects: ['S'],
      raw: {
        'source': ['x'],
      },
    );
    expect(() => m.authors.add('B'), throwsUnsupportedError);
    expect(() => m.subjects.clear(), throwsUnsupportedError);
    expect(() => m.raw['y'] = [], throwsUnsupportedError);
    expect(() => m.raw['source']!.add('z'), throwsUnsupportedError);
    expect(EpubMetadata().title, isNull);
  });
}
