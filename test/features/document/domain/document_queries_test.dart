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

    group('casos de borda', () {
      /// `<body>` com um `<p>` com os atributos dados (nome, valor, ns).
      DocumentTree one(List<(String, String, int)> attrs) {
        final b = TreeBuilder();
        final body = b.names.intern(Namespaces.xhtml, 'body');
        final p = b.names.intern(Namespaces.xhtml, 'p');
        b
          ..startElement(body)
          ..startElement(p);
        for (final (name, value, ns) in attrs) {
          b.attribute(b.names.intern(ns, name), value);
        }
        b
          ..endElement()
          ..endElement();
        return b.build();
      }

      test('TAB, LF, CR e FF separam; NBSP não separa', () {
        final tree = one([('class', 'a\tb\nc\rd\fe\u00A0f', Namespaces.none)]);
        expect(tree.classesOf(2).map(tree.tokens.tokenOf), [
          'a',
          'b',
          'c',
          'd',
          'e\u00A0f',
        ]);
      });

      test('atributos repetidos no mesmo elemento: vale o primeiro', () {
        final tree = one([
          ('id', 'x', Namespaces.none),
          ('id', 'y', Namespaces.none),
          ('class', 'a', Namespaces.none),
          ('class', 'b', Namespaces.none),
          ('type', 'noteref', Namespaces.ops),
          ('type', 'chapter', Namespaces.ops),
        ]);
        expect(tree.elementById('x'), 2);
        expect(tree.elementById('y'), isNull);
        expect(tree.classesOf(2).map(tree.tokens.tokenOf), ['a']);
        expect(tree.epubTypesOf(2), ['noteref']);
      });

      test('type sem prefixo é ignorado por epubTypesOf', () {
        final tree = one([('type', 'noteref', Namespaces.none)]);
        expect(tree.epubTypesOf(2), isEmpty);
      });

      test('token de epub:type não aparece em elementsWithClass', () {
        final tree = one([('type', 'noteref', Namespaces.ops)]);
        expect(tree.elementsWithClass('noteref'), isEmpty);
      });

      test('epub:type esparso: só alguns elementos, busca binária', () {
        final b = TreeBuilder();
        final n = b.names;
        final div = n.intern(Namespaces.xhtml, 'div');
        final type = n.intern(Namespaces.ops, 'type');
        b.startElement(div);
        for (var i = 0; i < 20; i++) {
          b.startElement(div);
          if (i.isOdd) b.attribute(type, 't$i u');
          b.endElement();
        }
        b.endElement();
        final tree = b.build();
        for (var i = 0; i < 20; i++) {
          expect(tree.epubTypesOf(i + 2), i.isOdd ? ['t$i', 'u'] : isEmpty);
        }
        expect(tree.epubTypesOf(1), isEmpty);
      });

      test('aninhamento profundo: ordem do documento (pré-ordem)', () {
        final b = TreeBuilder();
        final div = b.names.intern(Namespaces.xhtml, 'div');
        final cls = b.names.intern(Namespaces.none, 'class');
        void open() => b
          ..startElement(div)
          ..attribute(cls, 'k');
        open(); // 1
        open(); // 2
        open(); // 3
        b.endElement();
        open(); // 4
        b
          ..endElement()
          ..endElement();
        open(); // 5
        b
          ..endElement()
          ..endElement();
        final tree = b.build();
        expect(tree.elementsWithClass('k'), [1, 2, 3, 4, 5]);
        expect(tree.elementsNamed(Namespaces.xhtml, 'div'), [1, 2, 3, 4, 5]);
      });

      test('tokens internados direto no builder antes do build', () {
        final b = TreeBuilder();
        b.tokens
          ..intern('x')
          ..intern('y')
          ..intern('chapter');
        final p = b.names.intern(Namespaces.xhtml, 'p');
        final cls = b.names.intern(Namespaces.none, 'class');
        b
          ..startElement(p)
          ..attribute(cls, 'novo chapter novo')
          ..endElement();
        final tree = b.build();
        expect(tree.classesOf(1).map(tree.tokens.tokenOf), ['novo', 'chapter']);
        expect(tree.elementsWithClass('chapter'), [1]);
        expect(tree.elementsWithClass('x'), isEmpty);
      });

      test('class com 100 mil tokens distintos monta em tempo linear', () {
        const count = 100000;
        final value = List.generate(count, (i) => 't$i t$i').join(' ');
        final watch = Stopwatch()..start();
        final tree = one([('class', value, Namespaces.none)]);
        watch.stop();
        expect(tree.classesOf(2), hasLength(count));
        expect(tree.elementsWithClass('t99999'), [2]);
        expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      });
    });
  });
}
