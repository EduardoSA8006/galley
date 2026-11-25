import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/features/document/domain/document_tree.dart';
import 'package:galley/src/features/document/domain/names.dart';
import 'package:galley/src/features/document/domain/tree_builder.dart';

/// Monta `<html><body>` com [paragraphs] parágrafos com atributos e texto.
DocumentTree _paragraphs(int paragraphs) {
  final b = TreeBuilder();
  final n = b.names;
  final html = n.intern(Namespaces.xhtml, 'html');
  final body = n.intern(Namespaces.xhtml, 'body');
  final p = n.intern(Namespaces.xhtml, 'p');
  final cls = n.intern(Namespaces.none, 'class');
  b
    ..startElement(html)
    ..startElement(body);
  for (var i = 0; i < paragraphs; i++) {
    b
      ..startElement(p)
      ..attribute(cls, 'c$i')
      ..text('Parágrafo $i.')
      ..endElement();
  }
  b
    ..endElement()
    ..endElement();
  return b.build();
}

void main() {
  group('Namespaces', () {
    test('ids fixos e caminho inverso', () {
      const uris = {
        Namespaces.xhtml: 'http://www.w3.org/1999/xhtml',
        Namespaces.ops: 'http://www.idpf.org/2007/ops',
        Namespaces.svg: 'http://www.w3.org/2000/svg',
        Namespaces.mathml: 'http://www.w3.org/1998/Math/MathML',
        Namespaces.xml: 'http://www.w3.org/XML/1998/namespace',
        Namespaces.xlink: 'http://www.w3.org/1999/xlink',
        Namespaces.xmlns: 'http://www.w3.org/2000/xmlns/',
      };
      for (final MapEntry(key: id, value: uri) in uris.entries) {
        expect(Namespaces.idForUri(uri), id);
        expect(Namespaces.uriOf(id), uri);
      }
      expect(Namespaces.idForUri(null), Namespaces.none);
      expect(Namespaces.idForUri(''), Namespaces.none);
      expect(Namespaces.uriOf(Namespaces.none), isNull);
    });

    test('URI desconhecida recebe id >= 64 por documento', () {
      final names = NameTable();
      final a = names.internNamespace('urn:x-a');
      final b = names.internNamespace('urn:x-b');
      expect(a, greaterThanOrEqualTo(64));
      expect(b, greaterThanOrEqualTo(64));
      expect(a, isNot(b));
      expect(names.internNamespace('urn:x-a'), a);
      expect(names.namespaceUriOf(a), 'urn:x-a');
      expect(
        names.internNamespace(Namespaces.uriOf(Namespaces.svg)!),
        Namespaces.svg,
      );
    });
  });

  group('NameTable e TokenTable', () {
    test('o mesmo nome internado duas vezes devolve o mesmo id', () {
      final names = NameTable();
      final p1 = names.intern(Namespaces.xhtml, 'p');
      final p2 = names.intern(Namespaces.xhtml, 'p');
      final svgP = names.intern(Namespaces.svg, 'p');
      expect(p1, p2);
      expect(svgP, isNot(p1));
      expect(names.namespaceOf(svgP), Namespaces.svg);
      expect(names.localNameOf(p1), 'p');
      expect(names.lookup(Namespaces.xhtml, 'p'), p1);
      expect(names.lookup(Namespaces.xhtml, 'div'), isNull);
    });

    test('tokens', () {
      final tokens = TokenTable();
      final a = tokens.intern('chapter');
      expect(tokens.intern('chapter'), a);
      expect(tokens.tokenOf(a), 'chapter');
      expect(tokens.lookup('chapter'), a);
      expect(tokens.lookup('note'), isNull);
    });
  });

  group('TreeBuilder', () {
    test('<html><body><p>a</p>b</body></html>: percursos e texto', () {
      final b = TreeBuilder();
      final n = b.names;
      final html = n.intern(Namespaces.xhtml, 'html');
      final body = n.intern(Namespaces.xhtml, 'body');
      final p = n.intern(Namespaces.xhtml, 'p');
      b.startElement(html);
      expect(b.depth, 1);
      expect(b.openElementName, html);
      b
        ..startElement(body)
        ..startElement(p)
        ..text('a')
        ..endElement()
        ..text('b')
        ..endElement()
        ..endElement();
      expect(b.depth, 0);
      final t = b.build();

      expect(t.documentNode, 0);
      expect(t.kindOf(0), NodeKind.document);
      expect(t.parentOf(0), -1);
      expect(t.nodeCount, 6);

      final htmlN = t.childrenOf(0).single;
      expect(t.kindOf(htmlN), NodeKind.element);
      expect(t.localNameOf(htmlN), 'html');
      expect(t.namespaceOf(htmlN), Namespaces.xhtml);
      expect(t.nameOf(htmlN), html);

      final bodyN = t.childrenOf(htmlN).single;
      expect(t.parentOf(bodyN), htmlN);
      final kids = t.childrenOf(bodyN).toList();
      expect(kids, hasLength(2));
      final pN = kids[0];
      final bText = kids[1];
      expect(t.localNameOf(pN), 'p');
      expect(t.kindOf(bText), NodeKind.text);
      expect(t.textOf(bText), 'b');
      expect(t.nextSiblingOf(pN), bText);
      expect(t.previousSiblingOf(bText), pN);
      expect(t.previousSiblingOf(pN), -1);
      expect(t.nextSiblingOf(bText), -1);
      expect(t.parentOf(bText), bodyN);
      expect(t.firstChildOf(bodyN), pN);
      expect(t.firstChildOf(bText), -1);

      final aText = t.childrenOf(pN).single;
      expect(t.textOf(aText), 'a');
      expect(t.parentOf(aText), pN);
      expect(t.isVirtual(pN), isFalse);
    });

    test('textos seguidos geram um nó só', () {
      final b = TreeBuilder();
      b
        ..startElement(b.names.intern(Namespaces.xhtml, 'p'))
        ..text('a')
        ..text('b')
        ..endElement();
      final t = b.build();
      final p = t.firstChildOf(0);
      expect(t.childrenOf(p).length, 1);
      expect(t.textOf(t.firstChildOf(p)), 'ab');
    });

    test('elemento virtual preserva a flag', () {
      final b = TreeBuilder();
      final body = b.names.intern(Namespaces.xhtml, 'body');
      b
        ..startElement(body, virtual: true)
        ..startElement(b.names.intern(Namespaces.xhtml, 'p'))
        ..endElement()
        ..endElement();
      final t = b.build();
      final bodyN = t.firstChildOf(0);
      expect(t.isVirtual(bodyN), isTrue);
      expect(t.isVirtual(t.firstChildOf(bodyN)), isFalse);
    });

    test('atributos por (namespace, nome local)', () {
      final b = TreeBuilder();
      final n = b.names;
      final id = n.intern(Namespaces.none, 'id');
      final type = n.intern(Namespaces.ops, 'type');
      final lang = n.intern(Namespaces.xml, 'lang');
      b
        ..startElement(n.intern(Namespaces.xhtml, 'section'))
        ..attribute(id, 'c1')
        ..attribute(type, 'chapter')
        ..attribute(lang, 'pt-BR')
        ..startElement(n.intern(Namespaces.xhtml, 'p'))
        ..attribute(id, 'p1')
        ..text('x')
        ..endElement()
        ..endElement();
      final t = b.build();
      final section = t.firstChildOf(0);
      final p = t.firstChildOf(section);
      expect(t.attributeCountOf(section), 3);
      expect(t.attribute(section, Namespaces.none, 'id'), 'c1');
      expect(t.attribute(section, Namespaces.ops, 'type'), 'chapter');
      expect(t.attribute(section, Namespaces.none, 'type'), isNull);
      expect(t.attribute(section, Namespaces.xml, 'lang'), 'pt-BR');
      expect(t.attribute(section, Namespaces.none, 'nada'), isNull);
      expect(t.attributesOf(section).toList(), [
        (name: id, value: 'c1'),
        (name: type, value: 'chapter'),
        (name: lang, value: 'pt-BR'),
      ]);
      expect(t.attributeCountOf(p), 1);
      expect(t.attribute(p, Namespaces.none, 'id'), 'p1');
      expect(t.textOf(t.firstChildOf(p)), 'x');
    });

    test('atributo depois do primeiro filho lança StateError', () {
      final b = TreeBuilder();
      final p = b.names.intern(Namespaces.xhtml, 'p');
      b
        ..startElement(p)
        ..text('a');
      expect(
        () => b.attribute(b.names.intern(Namespaces.none, 'id'), 'x'),
        throwsStateError,
      );
    });

    test('10.000 níveis de aninhamento montam e percorrem sem estouro', () {
      const levels = 10000;
      final b = TreeBuilder();
      final div = b.names.intern(Namespaces.xhtml, 'div');
      for (var i = 0; i < levels; i++) {
        b.startElement(div);
      }
      b.text('fundo');
      for (var i = 0; i < levels; i++) {
        b.endElement();
      }
      final t = b.build();
      expect(t.nodeCount, levels + 2);

      // Percurso em pré-ordem iterativo, sem pilha.
      var visited = 0;
      var maxDepth = 0;
      var depth = 0;
      var node = t.documentNode;
      String? deepest;
      while (node != -1) {
        visited++;
        if (depth > maxDepth) maxDepth = depth;
        if (t.kindOf(node) == NodeKind.text) deepest = t.textOf(node);
        final child = t.firstChildOf(node);
        if (child != -1) {
          node = child;
          depth++;
          continue;
        }
        while (node != -1 && t.nextSiblingOf(node) == -1) {
          node = t.parentOf(node);
          depth--;
        }
        if (node != -1) node = t.nextSiblingOf(node);
      }
      expect(visited, levels + 2);
      expect(maxDepth, levels + 1);
      expect(deepest, 'fundo');
      for (var n = 0; n < t.nodeCount; n++) {
        expect(t.childrenOf(n).length, n == levels + 1 ? 0 : 1);
      }
    });

    test('retainedBytes > 0 e cresce com o tamanho', () {
      var previous = 0;
      for (final size in [1, 2, 8, 64, 512, 4096]) {
        final bytes = _paragraphs(size).retainedBytes;
        expect(bytes, greaterThan(previous), reason: 'size=$size');
        previous = bytes;
      }
    });

    test('build() com elemento aberto lança StateError', () {
      final b = TreeBuilder();
      b.startElement(b.names.intern(Namespaces.xhtml, 'html'));
      expect(b.build, throwsStateError);
    });

    test('endElement() sem elemento aberto lança StateError', () {
      expect(() => TreeBuilder().endElement(), throwsStateError);
    });

    test('tabelas de nomes e tokens acompanham a árvore', () {
      final b = TreeBuilder();
      final tok = b.tokens.intern('chapter');
      final t = b.build();
      expect(t.nodeCount, 1);
      expect(t.tokens.tokenOf(tok), 'chapter');
      expect(identical(t.names, b.names), isTrue);
    });
  });
}
