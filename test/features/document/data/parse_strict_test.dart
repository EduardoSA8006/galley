import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/core/diagnostics/diagnostic.dart';
import 'package:galley/src/core/diagnostics/diagnostic_codes.dart';
import 'package:galley/src/features/document/data/parse_document.dart';
import 'package:galley/src/features/document/domain/document_tree.dart';
import 'package:galley/src/features/document/domain/names.dart';
import 'package:galley/src/features/document/domain/parsed_document.dart';

const _xhtml = 'http://www.w3.org/1999/xhtml';
const _ops = 'http://www.idpf.org/2007/ops';
const _svg = 'http://www.w3.org/2000/svg';
const _xlink = 'http://www.w3.org/1999/xlink';

ParsedDocument _parse(String source) => parseDocumentBytes(
  Uint8List.fromList(utf8.encode(source)),
  path: 'OEBPS/ch1.xhtml',
);

/// Envolve [body] num documento XHTML com `xmlns:epub` declarado.
String _doc(String body) =>
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<html xmlns="$_xhtml" xmlns:epub="$_ops"><body>$body</body></html>';

/// O único elemento ([namespace], [localName]) da árvore.
int _single(DocumentTree tree, int namespace, String localName) {
  final found = tree.elementsNamed(namespace, localName);
  expect(found, hasLength(1), reason: '$localName em $namespace');
  return found.single;
}

List<String> _codes(ParsedDocument doc) => [
  for (final d in doc.diagnostics) d.code,
];

/// Serialização determinística da árvore, para comparar duas montagens.
String _dump(DocumentTree tree) {
  final out = StringBuffer();
  void visit(int n) {
    switch (tree.kindOf(n)) {
      case NodeKind.document:
        break;
      case NodeKind.element:
        out.write('<${tree.namespaceOf(n)}:${tree.localNameOf(n)}');
        for (final a in tree.attributesOf(n)) {
          out.write(
            ' ${tree.names.namespaceOf(a.name)}:'
            '${tree.names.localNameOf(a.name)}="${a.value}"',
          );
        }
        out.write('>');
      case NodeKind.text:
        out.write('[${tree.textOf(n)}]');
    }
    for (final c in tree.childrenOf(n)) {
      visit(c);
    }
    if (tree.kindOf(n) == NodeKind.element) out.write('</>');
  }

  visit(tree.documentNode);
  return out.toString();
}

void main() {
  group('namespaces', () {
    test('xmlns e xmlns:epub: elemento XHTML e epub:type em OPS', () {
      final doc = _parse(_doc('<section epub:type="chapter">x</section>'));
      final tree = doc.tree;
      final section = _single(tree, Namespaces.xhtml, 'section');
      expect(tree.attribute(section, Namespaces.ops, 'type'), 'chapter');
      expect(tree.epubTypesOf(section), ['chapter']);
      expect(_codes(doc), isNot(contains(DiagnosticCodes.undeclaredPrefix)));
      expect(doc.recovered, isFalse);
    });

    test('declarações xmlns não viram atributos', () {
      final tree = _parse(_doc('')).tree;
      final html = _single(tree, Namespaces.xhtml, 'html');
      expect(tree.attributeCountOf(html), 0);
    });

    test('epub: sem declaração cai em OPS, com undeclaredPrefix', () {
      final doc = _parse(
        '<html xmlns="$_xhtml"><body>'
        '<section epub:type="chapter">x</section>'
        '<aside epub:type="footnote"/></body></html>',
      );
      final section = _single(doc.tree, Namespaces.xhtml, 'section');
      expect(doc.tree.attribute(section, Namespaces.ops, 'type'), 'chapter');
      final undeclared = doc.diagnostics
          .where((d) => d.code == DiagnosticCodes.undeclaredPrefix)
          .toList();
      expect(undeclared, hasLength(1), reason: 'uma vez por prefixo');
      expect(undeclared.single.severity, DiagnosticSeverity.info);
      expect(undeclared.single.message, contains('epub'));
      expect(undeclared.single.location, 'OEBPS/ch1.xhtml');
    });

    test('declaração depois do atributo prefixado ainda vale', () {
      final doc = _parse(
        '<html xmlns="$_xhtml"><body>'
        '<p epub:type="note" xmlns:epub="$_ops">x</p></body></html>',
      );
      final p = _single(doc.tree, Namespaces.xhtml, 'p');
      expect(doc.tree.attribute(p, Namespaces.ops, 'type'), 'note');
      expect(_codes(doc), isNot(contains(DiagnosticCodes.undeclaredPrefix)));
    });

    test('<html:p> com xmlns:html ligado ao XHTML vira p XHTML', () {
      final tree = _parse(
        '<html:html xmlns:html="$_xhtml"><html:body>'
        '<html:p>x</html:p></html:body></html:html>',
      ).tree;
      final p = _single(tree, Namespaces.xhtml, 'p');
      expect(tree.localNameOf(p), 'p');
      expect(tree.namespaceOf(p), Namespaces.xhtml);
    });

    test('svg:image com xlink:href', () {
      final tree = _parse(
        _doc(
          '<svg:svg xmlns:svg="$_svg" xmlns:xlink="$_xlink">'
          '<svg:image xlink:href="a.png"/></svg:svg>',
        ),
      ).tree;
      final image = _single(tree, Namespaces.svg, 'image');
      expect(tree.attribute(image, Namespaces.xlink, 'href'), 'a.png');
    });

    test('xmlns padrão do SVG em elemento aninhado', () {
      final tree = _parse(_doc('<svg xmlns="$_svg"><image/></svg><p/>')).tree;
      _single(tree, Namespaces.svg, 'image');
      _single(tree, Namespaces.xhtml, 'p');
    });

    test('redeclaração vale só no escopo do elemento', () {
      final tree = _parse(
        '<r xmlns:a="urn:um"><x xmlns:a="urn:dois"><a:e/></x><a:e/></r>',
      ).tree;
      final um = tree.names.namespaceIdOf('urn:um');
      final dois = tree.names.namespaceIdOf('urn:dois');
      expect(tree.elementsNamed(dois!, 'e'), hasLength(1));
      expect(tree.elementsNamed(um!, 'e'), hasLength(1));
      expect(
        tree.elementsNamed(dois, 'e').single,
        lessThan(tree.elementsNamed(um, 'e').single),
      );
    });

    test('xml:lang acessível por Namespaces.xml', () {
      final tree = _parse('<html xmlns="$_xhtml" xml:lang="ja"><body/></html>')
          .tree;
      final html = _single(tree, Namespaces.xhtml, 'html');
      expect(tree.attribute(html, Namespaces.xml, 'lang'), 'ja');
    });

    test('atributo sem prefixo fica em Namespaces.none', () {
      final tree = _parse(_doc('<p class="a" id="x"/>')).tree;
      final p = _single(tree, Namespaces.xhtml, 'p');
      expect(tree.attribute(p, Namespaces.none, 'class'), 'a');
      expect(tree.attribute(p, Namespaces.xhtml, 'class'), isNull);
      expect(tree.elementById('x'), p);
    });

    test('prefixo desconhecido sem declaração mantém o nome com prefixo', () {
      final doc = _parse(_doc('<foo:bar foo:baz="1"/>'));
      final tree = doc.tree;
      final ns = tree.names.namespaceIdOf(Namespaces.undeclaredPrefixUri);
      expect(ns, isNotNull);
      final el = _single(tree, ns!, 'foo:bar');
      expect(tree.attribute(el, ns, 'foo:baz'), '1');
      expect(_codes(doc), contains(DiagnosticCodes.undeclaredPrefix));
    });

    test('documento sem xmlns: XHTML implícito, com impliedNamespace', () {
      final doc = _parse('<html><body><x xmlns=""><y/></x></body></html>');
      final tree = doc.tree;
      _single(tree, Namespaces.xhtml, 'html');
      _single(tree, Namespaces.xhtml, 'body');
      // `xmlns=""` explícito continua valendo.
      _single(tree, Namespaces.none, 'x');
      _single(tree, Namespaces.none, 'y');
      final d = doc.diagnostics.singleWhere(
        (d) => d.code == DiagnosticCodes.impliedNamespace,
      );
      expect(d.severity, DiagnosticSeverity.info);
      expect(d.message, contains(_xhtml));
      expect(doc.recovered, isFalse);
    });

    test('raiz svg sem xmlns: SVG implícito', () {
      final doc = _parse('<svg><g><rect/></g></svg>');
      _single(doc.tree, Namespaces.svg, 'svg');
      _single(doc.tree, Namespaces.svg, 'rect');
      expect(_codes(doc), contains(DiagnosticCodes.impliedNamespace));
    });

    test('raiz com xmlns (mesmo "") não gera impliedNamespace', () {
      for (final source in ['<html xmlns="$_xhtml"/>', '<r xmlns=""/>']) {
        expect(
          _codes(_parse(source)),
          isNot(contains(DiagnosticCodes.impliedNamespace)),
          reason: source,
        );
      }
      _single(_parse('<r xmlns=""/>').tree, Namespaces.none, 'r');
    });
  });

  group('texto', () {
    test('&nbsp; vira U+00A0', () {
      final tree = _parse(_doc('<p>a&nbsp;b</p>')).tree;
      final p = _single(tree, Namespaces.xhtml, 'p');
      expect(tree.textOf(tree.firstChildOf(p)), 'a b');
    });

    test('entidade HTML5 em atributo', () {
      final tree = _parse(_doc('<p title="&eacute;&amp;"/>')).tree;
      final p = _single(tree, Namespaces.xhtml, 'p');
      expect(tree.attribute(p, Namespaces.none, 'title'), 'é&');
    });

    test('CDATA é fundido com o texto vizinho', () {
      final tree = _parse(_doc('<p>a<![CDATA[<b>]]>c</p>')).tree;
      final p = _single(tree, Namespaces.xhtml, 'p');
      expect(tree.childrenOf(p), hasLength(1));
      expect(tree.textOf(tree.firstChildOf(p)), 'a<b>c');
    });

    test('a<!-- c -->b vira um único nó de texto e conta o descarte', () {
      final doc = _parse(_doc('<p>a<!-- c -->b</p>'));
      final tree = doc.tree;
      final p = _single(tree, Namespaces.xhtml, 'p');
      expect(tree.childrenOf(p), hasLength(1));
      expect(tree.textOf(tree.firstChildOf(p)), 'ab');
      final dropped = doc.diagnostics.singleWhere(
        (d) => d.code == DiagnosticCodes.droppedNodes,
      );
      expect(dropped.severity, DiagnosticSeverity.info);
      expect(dropped.location, 'OEBPS/ch1.xhtml');
    });

    test('doctype, PIs e comentários são contados; a declaração XML não', () {
      final doc = _parse(
        '<?xml version="1.0"?><!DOCTYPE html><!-- topo -->'
        '<html xmlns="$_xhtml"><?pi x?><body><!-- a --><!-- b --></body>'
        '</html>',
      );
      final dropped = doc.diagnostics.singleWhere(
        (d) => d.code == DiagnosticCodes.droppedNodes,
      );
      expect(dropped.message, contains('3 comentário'));
      expect(dropped.message, contains('1 instrução'));
      expect(dropped.message, contains('1 doctype'));
      final body = _single(doc.tree, Namespaces.xhtml, 'body');
      expect(doc.tree.firstChildOf(body), -1);
    });

    test('sem descartes, sem droppedNodes', () {
      final doc = _parse(_doc('<p>a</p>'));
      expect(_codes(doc), isNot(contains(DiagnosticCodes.droppedNodes)));
    });

    test('espaços e quebras de linha entre elementos são preservados', () {
      final tree = _parse(
        '<html xmlns="$_xhtml">\n<body>\n  <p>a</p>\n  <p>b</p>\n</body>\n'
        '</html>\n',
      ).tree;
      final body = _single(tree, Namespaces.xhtml, 'body');
      final kids = tree.childrenOf(body).toList();
      expect(kids.map(tree.kindOf), [
        NodeKind.text,
        NodeKind.element,
        NodeKind.text,
        NodeKind.element,
        NodeKind.text,
      ]);
      expect(tree.textOf(kids[0]), '\n  ');
      expect(tree.textOf(kids[2]), '\n  ');
      expect(tree.textOf(kids[4]), '\n');
      final html = _single(tree, Namespaces.xhtml, 'html');
      expect(tree.textOf(tree.firstChildOf(html)), '\n');
    });

    test('espaço fora da raiz não vira nó', () {
      final tree = _parse('<?xml version="1.0"?>\n<!DOCTYPE html>\n<html/>\n')
          .tree;
      expect(tree.childrenOf(tree.documentNode), hasLength(1));
    });
  });

  group('atributos', () {
    test('atributo duplicado: o primeiro vence, com duplicateAttribute', () {
      final doc = _parse(_doc('<p class="a" class="b"/>'));
      final p = _single(doc.tree, Namespaces.xhtml, 'p');
      expect(doc.tree.attributeCountOf(p), 1);
      expect(doc.tree.attribute(p, Namespaces.none, 'class'), 'a');
      final dup = doc.diagnostics.singleWhere(
        (d) => d.code == DiagnosticCodes.duplicateAttribute,
      );
      expect(dup.severity, DiagnosticSeverity.info);
    });
  });

  group('entrada', () {
    test('bytes com BOM UTF-16 geram a mesma árvore que os UTF-8', () {
      final source = _doc('<p class="c">Olá &amp; ルビ<br/></p>\n');
      final utf8Tree = _parse(source).tree;
      for (final littleEndian in [true, false]) {
        final bytes = BytesBuilder()
          ..add(littleEndian ? [0xFF, 0xFE] : [0xFE, 0xFF]);
        for (final unit in source.codeUnits) {
          bytes.add(
            littleEndian ? [unit & 0xFF, unit >> 8] : [unit >> 8, unit & 0xFF],
          );
        }
        final tree = parseDocumentBytes(
          bytes.toBytes(),
          path: 'OEBPS/ch1.xhtml',
        ).tree;
        expect(_dump(tree), _dump(utf8Tree), reason: 'LE=$littleEndian');
      }
    });

    test('encoding="ISO-8859-1" em bytes latin1 dá o mesmo texto', () {
      const text = 'Olá, ação é çÇ ñ ÿ';
      final source =
          '<?xml version="1.0" encoding="ISO-8859-1"?>'
          '<html xmlns="$_xhtml"><body><p title="$text">$text</p></body>'
          '</html>';
      final bytes = Uint8List.fromList(latin1.encode(source));
      final doc = parseDocumentBytes(bytes, path: 'OEBPS/ch1.xhtml');
      expect(doc.recovered, isFalse);
      final p = _single(doc.tree, Namespaces.xhtml, 'p');
      expect(doc.tree.textOf(doc.tree.firstChildOf(p)), text);
      expect(doc.tree.attribute(p, Namespaces.none, 'title'), text);
    });

    test('documento só com <!DOCTYPE html>: irrecuperável', () {
      for (final source in ['<!DOCTYPE html>', '<!DOCTYPE html>\n  ']) {
        final doc = _parse(source);
        expect(doc.recovered, isTrue, reason: source);
        expect(_codes(doc), [DiagnosticCodes.unparseable], reason: source);
        final body = _single(doc.tree, Namespaces.xhtml, 'body');
        expect(doc.tree.firstChildOf(body), -1);
      }
    });

    test('documento sintético de 2 MB monta sem erro', () {
      final source = syntheticDocument(2 * 1024 * 1024);
      expect(source.length, greaterThanOrEqualTo(2 * 1024 * 1024));
      final doc = _parse(source);
      expect(doc.recovered, isFalse);
      expect(
        doc.diagnostics.where((d) => d.severity != DiagnosticSeverity.info),
        isEmpty,
      );
      expect(doc.tree.elementsNamed(Namespaces.xhtml, 'p').length, 1000);
      expect(doc.tree.elementsNamed(Namespaces.mathml, 'mi'), isNotEmpty);
    });
  });

  group('correções da revisão', () {
    test('CRLF, CR isolado e mistura viram LF no texto', () {
      for (final source in ['a\r\nb', 'a\rb', 'a\nb']) {
        final tree = _parse('<r>$source</r>').tree;
        final r = _single(tree, Namespaces.xhtml, 'r');
        expect(tree.textOf(tree.firstChildOf(r)), 'a\nb', reason: source);
      }
      final tree = _parse('<r>a\r\n\r\rb\n\r\nc</r>').tree;
      final r = _single(tree, Namespaces.xhtml, 'r');
      expect(tree.textOf(tree.firstChildOf(r)), 'a\n\n\nb\n\nc');
    });

    test('&#13; (referência) continua CR no texto', () {
      final tree = _parse('<r>a&#13;b</r>').tree;
      final r = _single(tree, Namespaces.xhtml, 'r');
      expect(tree.textOf(tree.firstChildOf(r)), 'a\rb');
    });

    test('valores de atributo: TAB, LF e CR viram espaço', () {
      final tree = _parse('<r t="a\tb\nc\r\nd\re"/>').tree;
      final r = _single(tree, Namespaces.xhtml, 'r');
      expect(tree.attribute(r, Namespaces.none, 't'), 'a b c d e');
    });

    test('caracteres proibidos viram U+FFFD no texto e nos atributos', () {
      final tree = _parse(
        '<r t="x&#0;y\u0001">a&#0;b\uD800c\u0008d\uDC00e\uFFFF'
        '\u{1F600}</r>',
      ).tree;
      final r = _single(tree, Namespaces.xhtml, 'r');
      expect(tree.attribute(r, Namespaces.none, 't'), 'x\uFFFDy\uFFFD');
      expect(
        tree.textOf(tree.firstChildOf(r)),
        'a\uFFFDb\uFFFDc\uFFFDd\uFFFDe\uFFFD\u{1F600}',
      );
    });

    test('xlink: sem declaração cai em XLink, com undeclaredPrefix', () {
      final doc = _parse(
        '<svg xmlns="$_svg"><image xlink:href="a.png"/></svg>',
      );
      final image = _single(doc.tree, Namespaces.svg, 'image');
      expect(doc.tree.attribute(image, Namespaces.xlink, 'href'), 'a.png');
      final d = doc.diagnostics.singleWhere(
        (d) => d.code == DiagnosticCodes.undeclaredPrefix,
      );
      expect(d.message, contains('xlink'));
    });

    test('xmlns:p="" e xmlns:="u" são ignorados com diagnóstico', () {
      final doc = _parse(
        '<r xmlns:a="urn:a"><x xmlns:a="" xmlns:="urn:b"><a:e/></x></r>',
      );
      final a = doc.tree.names.namespaceIdOf('urn:a');
      expect(doc.tree.elementsNamed(a!, 'e'), hasLength(1));
      expect(doc.tree.names.namespaceIdOf('urn:b'), isNull);
      final invalid = doc.diagnostics
          .where((d) => d.code == DiagnosticCodes.invalidNamespaceDeclaration)
          .toList();
      expect(invalid, hasLength(2));
      expect(invalid.first.severity, DiagnosticSeverity.info);
      final x = _single(doc.tree, Namespaces.xhtml, 'x');
      expect(doc.tree.attributeCountOf(x), 0);
    });

    test('xmlns="" reinicia o namespace padrão dentro do XHTML', () {
      final tree = _parse(
        '<html xmlns="$_xhtml"><body><x xmlns=""><y/></x><p/></body></html>',
      ).tree;
      _single(tree, Namespaces.none, 'x');
      _single(tree, Namespaces.none, 'y');
      _single(tree, Namespaces.xhtml, 'p');
    });

    test('duplicateAttribute: um diagnóstico por elemento, com contagem', () {
      final doc = _parse('<r><p a="1" a="2" b="1" b="2" a="3"/><q c="1"/></r>');
      final dup = doc.diagnostics
          .where((d) => d.code == DiagnosticCodes.duplicateAttribute)
          .toList();
      expect(dup, hasLength(1));
      expect(dup.single.message, contains('3'));
      final p = _single(doc.tree, Namespaces.xhtml, 'p');
      expect(doc.tree.attributeCountOf(p), 2);
      expect(doc.tree.attribute(p, Namespaces.none, 'a'), '1');
    });
  });

  group('linearidade (revisão final)', () {
    test('um <p> com 160k atributos distintos: tempo linear', () {
      // Antes: List.contains por atributo, O(k²) (160k levavam 8 s).
      final attrs = StringBuffer();
      for (var i = 0; i < 160000; i++) {
        attrs.write(' a$i="v"');
      }
      final source = _doc('<p$attrs a0="w"/>');
      expect(source.length, greaterThan(1024 * 1024));
      final watch = Stopwatch()..start();
      final doc = _parse(source);
      watch.stop();
      expect(watch.elapsed, lessThan(const Duration(seconds: 10)));
      final p = _single(doc.tree, Namespaces.xhtml, 'p');
      expect(doc.tree.attributeCountOf(p), 160000);
      expect(doc.tree.attribute(p, Namespaces.none, 'a0'), 'v');
    });

    test('80k xmlns:pN na raiz + 80k <p0:q/>: tempo linear', () {
      // Antes: cada nome com prefixo varria a pilha inteira de prefixos
      // (40k + 40k levavam 5,8 s; aqui, ~4× isso).
      final declarations = StringBuffer();
      for (var i = 0; i < 80000; i++) {
        declarations.write(' xmlns:p$i="urn:$i"');
      }
      final source =
          '<html xmlns="$_xhtml"$declarations><body>'
          '${'<p0:q/>' * 80000}</body></html>';
      expect(source.length, greaterThan(1024 * 1024));
      final watch = Stopwatch()..start();
      final doc = _parse(source);
      watch.stop();
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      expect(doc.recovered, isFalse);
      final ns = doc.tree.names.namespaceIdOf('urn:0');
      expect(doc.tree.elementsNamed(ns!, 'q'), hasLength(80000));
    });

    test('120k níveis, cada um declarando um prefixo e usando p0:', () {
      // Antes: O(profundidade²) (40k níveis levavam 1,7 s).
      final open = StringBuffer();
      for (var i = 0; i < 120000; i++) {
        open.write('<p0:d xmlns:p${i + 1}="urn:${i + 1}">');
      }
      final source =
          '<html xmlns="$_xhtml" xmlns:p0="urn:0"><body>$open'
          '${'</p0:d>' * 120000}</body></html>';
      expect(source.length, greaterThan(1024 * 1024));
      final watch = Stopwatch()..start();
      final doc = _parse(source);
      watch.stop();
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      expect(doc.recovered, isFalse);
      final ns = doc.tree.names.namespaceIdOf('urn:0');
      expect(doc.tree.elementsNamed(ns!, 'd'), hasLength(120000));
    });

    test(
      'prefixo redeclarado em escopo interno e restaurado no fechamento',
      () {
        final doc = _parse(
          '<r xmlns:a="urn:1"><x xmlns:a="urn:2"><a:e/></x><a:e/></r>',
        );
        final one = doc.tree.names.namespaceIdOf('urn:1')!;
        final two = doc.tree.names.namespaceIdOf('urn:2')!;
        expect(doc.tree.elementsNamed(one, 'e'), hasLength(1));
        expect(doc.tree.elementsNamed(two, 'e'), hasLength(1));
      },
    );
  });

  group('ParsedDocument', () {
    test('head sem dados, diagnósticos não modificáveis', () {
      final doc = _parse(_doc('<p/>'));
      expect(doc.head.styleSheets, isEmpty);
      expect(
        () => doc.diagnostics.add(
          const Diagnostic(
            severity: DiagnosticSeverity.info,
            code: 'x',
            message: 'x',
          ),
        ),
        throwsUnsupportedError,
      );
    });

    test('sem conteúdo: html/body virtuais e document.unparseable', () {
      // Os demais malformados passam pelo modo tolerante (recovery_test).
      for (final source in [
        '',
        ' \n\t ',
        '<?xml version="1.0"?><!-- nada -->',
      ]) {
        final doc = _parse(source);
        final tree = doc.tree;
        final html = _single(tree, Namespaces.xhtml, 'html');
        final body = _single(tree, Namespaces.xhtml, 'body');
        expect(tree.isVirtual(html), isTrue);
        expect(tree.isVirtual(body), isTrue);
        expect(tree.firstChildOf(body), -1);
        expect(tree.nodeCount, 3, reason: source);
        expect(doc.recovered, isTrue);
        final error = doc.diagnostics.single;
        expect(error.code, DiagnosticCodes.unparseable);
        expect(error.severity, DiagnosticSeverity.error);
        expect(error.location, 'OEBPS/ch1.xhtml');
      }
    });
  });
}

/// Documento XHTML sintético com pelo menos [minChars] caracteres: tabelas,
/// *ruby*, MathML, `style=` e `epub:type`, com 1000 parágrafos.
String syntheticDocument(int minChars) {
  const head =
      '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE html>\n'
      '<html xmlns="$_xhtml" xmlns:epub="$_ops" xml:lang="pt-BR">\n'
      '<head><title>Sintético</title></head>\n<body>\n';
  const tail = '</body>\n</html>\n';
  final unit = StringBuffer();
  var i = 0;
  // Bloco que se repete até atingir o tamanho, com 1000 <p> no total.
  String block(int k) =>
      '<section epub:type="chapter" id="s$k" class="cap c${k % 7}">\n'
      '<h2 style="margin: 1em 0">Capítulo $k</h2>\n'
      '<p class="texto">Texto &amp; <ruby>漢<rt>かん</rt>字<rt>じ</rt></ruby> '
      'com <em>ênfase</em>&nbsp;e <a href="#s$k">link</a>.</p>\n'
      '<table><tr><td>a$k</td><td style="color: red">b</td></tr></table>\n'
      '<math xmlns="http://www.w3.org/1998/Math/MathML"><mi>x</mi>'
      '<mo>=</mo><mn>$k</mn></math>\n'
      '<!-- comentário -->\n'
      '</section>\n';
  final body = StringBuffer();
  while (i < 1000) {
    body.write(block(i++));
  }
  // Completa o tamanho com texto dentro de um div (sem novos <p>).
  final filler = 'Lorem ipsum dolor sit amet, consectetur adipiscing. ' * 20;
  while (head.length + body.length + tail.length < minChars) {
    body.write('<div class="f">$filler</div>\n');
  }
  unit
    ..write(head)
    ..write(body)
    ..write(tail);
  return unit.toString();
}
