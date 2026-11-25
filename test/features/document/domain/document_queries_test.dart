import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/features/document/domain/document_tree.dart';
import 'package:galley/src/features/document/domain/names.dart';
import 'package:galley/src/features/document/domain/tree_builder.dart';

/// Monta `<body>` com três `<p>` e um `<span>`, com id/class/epub:type.
DocumentTree _sample() {
  final b = TreeBuilder();
  final n = b.names;
  final body = n.intern(Namespaces.xhtml, 'body');
  final p = n.intern(Namespaces.xhtml, 'p');
  final span = n.intern(Namespaces.xhtml, 'span');
  final id = n.intern(Namespaces.none, 'id');
  final cls = n.intern(Namespaces.none, 'class');
  final type = n.intern(Namespaces.ops, 'type');
  b.startElement(body); // 1
  b
    ..startElement(p) // 2
    ..attribute(id, 'n1')
    ..attribute(cls, ' a  b a ')
    ..attribute(type, 'noteref chapter')
    ..endElement();
  b
    ..startElement(span) // 3
    ..attribute(id, 'dup')
    ..attribute(cls, 'b')
    ..endElement();
  b
    ..startElement(p) // 4
    ..attribute(id, 'dup')
    ..attribute(cls, 'b c')
    ..endElement();
  b
    ..startElement(p) // 5
    ..attribute(id, '')
    ..attribute(cls, '')
    ..text('x')
    ..endElement();
  b.endElement();
  return b.build();
}

void main() {
  group('índices de consulta', () {
    final t = _sample();

    test('elementById acha o elemento certo', () {
      expect(t.elementById('n1'), 2);
      expect(t.idOf(2), 'n1');
    });

    test('id duplicado devolve o primeiro; id vazio é ignorado', () {
      expect(t.elementById('dup'), 3);
      expect(t.elementById(''), isNull);
      expect(t.idOf(5), isNull);
      expect(t.idOf(1), isNull);
    });

    test('classesOf separa por espaços e não repete', () {
      expect(t.classesOf(2).map(t.tokens.tokenOf), ['a', 'b']);
      expect(t.classesOf(5), isEmpty);
      expect(t.classesOf(1), isEmpty);
    });

    test('elementsWithClass vem na ordem do documento', () {
      expect(t.elementsWithClass('b'), [2, 3, 4]);
      expect(t.elementsWithClass('c'), [4]);
    });

    test('elementsNamed vem na ordem do documento', () {
      expect(t.elementsNamed(Namespaces.xhtml, 'p'), [2, 4, 5]);
      expect(t.elementsNamed(Namespaces.xhtml, 'span'), [3]);
    });

    test('epubTypesOf separa os tokens de epub:type', () {
      expect(t.epubTypesOf(2), ['noteref', 'chapter']);
      expect(t.epubTypesOf(3), isEmpty);
    });

    test('consultas por nomes inexistentes devolvem null ou []', () {
      expect(t.elementById('nao-existe'), isNull);
      expect(t.elementsWithClass('nao-existe'), isEmpty);
      expect(t.elementsNamed(Namespaces.xhtml, 'nao-existe'), isEmpty);
      expect(t.elementsNamed(Namespaces.svg, 'p'), isEmpty);
    });

    test('consultas não internam (tabelas congeladas seguem iguais)', () {
      final names = t.names.length;
      final tokens = t.tokens.length;
      t.elementsWithClass('zzz');
      t.elementsNamed(Namespaces.xhtml, 'zzz');
      expect(t.names.length, names);
      expect(t.tokens.length, tokens);
    });

    test('listas devolvidas são imutáveis', () {
      expect(() => t.elementsWithClass('b')[0] = 9, throwsUnsupportedError);
      expect(
        () => t.elementsNamed(Namespaces.xhtml, 'p')[0] = 9,
        throwsUnsupportedError,
      );
      expect(() => t.classesOf(2)[0] = 9, throwsUnsupportedError);
      expect(() => t.epubTypesOf(2).add('x'), throwsUnsupportedError);
    });

    test('documento sem id/class/epub:type funciona', () {
      final b = TreeBuilder();
      final body = b.names.intern(Namespaces.xhtml, 'body');
      b
        ..startElement(body)
        ..endElement();
      final tree = b.build();
      expect(tree.elementById('a'), isNull);
      expect(tree.classesOf(1), isEmpty);
      expect(tree.elementsNamed(Namespaces.xhtml, 'body'), [1]);
    });
  });
}
