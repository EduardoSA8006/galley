import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/core/diagnostics/diagnostic.dart';
import 'package:galley/src/core/diagnostics/diagnostic_codes.dart';
import 'package:galley/src/features/document/data/parse_document.dart';
import 'package:galley/src/features/document/domain/document_tree.dart';
import 'package:galley/src/features/document/domain/names.dart';
import 'package:galley/src/features/document/domain/parsed_document.dart';

const _path = 'OEBPS/ch1.xhtml';
const _xhtml = 'http://www.w3.org/1999/xhtml';

ParsedDocument _parse(String source, {String? mediaType}) => parseDocumentBytes(
  Uint8List.fromList(utf8.encode(source)),
  path: _path,
  mediaType: mediaType ?? 'application/xhtml+xml',
);

/// Envolve [body] num XHTML com `<html>` e `<body>` reais.
String _doc(String body) => '<html xmlns="$_xhtml"><body>$body</body></html>';

/// Forma compacta da árvore: `nome[filhos]`, `*` nos nós virtuais e texto
/// entre aspas.
String _dump(DocumentTree tree) {
  final out = StringBuffer();
  void visit(int n) {
    if (tree.kindOf(n) == NodeKind.text) {
      out.write('"${tree.textOf(n)}"');
      return;
    }
    out.write(tree.localNameOf(n));
    if (tree.isVirtual(n)) out.write('*');
    final children = tree.childrenOf(n).toList();
    if (children.isEmpty) return;
    out.write('[');
    children.forEach(visit);
    out.write(']');
  }

  tree.childrenOf(tree.documentNode).forEach(visit);
  return out.toString();
}

List<String> _codes(ParsedDocument doc) => [
  for (final d in doc.diagnostics) d.code,
];

int _count(ParsedDocument doc, String code) =>
    _codes(doc).where((c) => c == code).length;

void main() {
  group('entrada no modo tolerante', () {
    test('documento bem formado não passa pelo modo tolerante', () {
      final doc = _parse(_doc('<p>a</p>'));
      expect(doc.recovered, isFalse);
      expect(_dump(doc.tree), 'html[body[p["a"]]]');
      expect(_codes(doc), isNot(contains(DiagnosticCodes.recovered)));
    });

    test('malformado emite document.recovered (warning) com a linha', () {
      final doc = _parse(
        '<html xmlns="$_xhtml">\n<body>\n<p>a < b</p>\n</body></html>',
      );
      expect(doc.recovered, isTrue);
      final recovered = doc.diagnostics
          .where((d) => d.code == DiagnosticCodes.recovered)
          .toList();
      expect(recovered, hasLength(1));
      expect(recovered.single.severity, DiagnosticSeverity.warning);
      expect(recovered.single.location, '$_path:3');
    });

    test('text/html bem formado: recovered sem document.recovered', () {
      final doc = _parse(
        '<html><head><title>T</title></head><body><p>x</p></body></html>',
        mediaType: 'text/html',
      );
      expect(doc.recovered, isTrue);
      expect(_codes(doc), isNot(contains(DiagnosticCodes.recovered)));
      expect(_codes(doc), isNot(contains(DiagnosticCodes.unclosedElement)));
      expect(_dump(doc.tree), 'html[head[title["T"]]body[p["x"]]]');
      // Sem xmlns, o HTML cai no namespace XHTML (e o <head> é lido).
      expect(doc.tree.elementsNamed(Namespaces.xhtml, 'p'), hasLength(1));
      expect(doc.head.title, 'T');
    });
  });

  group('regras de recuperação', () {
    test('<p>a<p>b: dois p irmãos', () {
      final doc = _parse(_doc('<p>a<p>b'));
      expect(_dump(doc.tree), 'html[body[p["a"]p["b"]]]');
      expect(_codes(doc), contains(DiagnosticCodes.unclosedElement));
    });

    test('bloco fecha o p aberto', () {
      final doc = _parse(_doc('<p>a<div>b</div>'));
      expect(_dump(doc.tree), 'html[body[p["a"]div["b"]]]');
    });

    test('<ul><li>a<li>b</ul>', () {
      final doc = _parse(_doc('<ul><li>a<li>b</ul>'));
      expect(_dump(doc.tree), 'html[body[ul[li["a"]li["b"]]]]');
      expect(_codes(doc), contains(DiagnosticCodes.unclosedElement));
    });

    test('li aninhado numa lista interna não fecha o li de fora', () {
      final doc = _parse(_doc('<ul><li>a<ul><li>b</ul></ul>'));
      expect(_dump(doc.tree), 'html[body[ul[li["a"ul[li["b"]]]]]]');
    });

    test('dt/dd fecham dt/dd', () {
      final doc = _parse(_doc('<dl><dt>a<dd>b<dt>c</dl>'));
      expect(_dump(doc.tree), 'html[body[dl[dt["a"]dd["b"]dt["c"]]]]');
    });

    test('<table><tr><td>1<td>2<tr><td>3</table>', () {
      final doc = _parse(_doc('<table><tr><td>1<td>2<tr><td>3</table>'));
      expect(
        _dump(doc.tree),
        'html[body[table[tr[td["1"]td["2"]]tr[td["3"]]]]]',
      );
      expect(_codes(doc), contains(DiagnosticCodes.unclosedElement));
    });

    test('option fecha option', () {
      final doc = _parse(_doc('<select><option>a<option>b</select>'));
      expect(_dump(doc.tree), 'html[body[select[option["a"]option["b"]]]]');
    });

    test('<P>x</p>: fechamento ignora maiúsculas', () {
      final doc = _parse(_doc('<P>x</p>'));
      expect(_dump(doc.tree), 'html[body[P["x"]]]');
      expect(_codes(doc), isNot(contains(DiagnosticCodes.strayEndTag)));
      expect(_codes(doc), isNot(contains(DiagnosticCodes.unclosedElement)));
    });

    test('a < b no texto: o < volta ao texto', () {
      final doc = _parse(_doc('<p>a < b</p>'));
      expect(_dump(doc.tree), 'html[body[p["a < b"]]]');
      expect(_codes(doc), contains(DiagnosticCodes.markupAsText));
      expect(doc.recovered, isTrue);
    });

    test('<br> sem barra é vazio; </br> é ignorado', () {
      final doc = _parse(_doc('<p>a<br>b<img src="x.png"></img>c</p>'));
      expect(_dump(doc.tree), 'html[body[p["a"br"b"img"c"]]]');
      expect(_codes(doc), isNot(contains(DiagnosticCodes.strayEndTag)));
    });

    test('<script>/<style>: conteúdo bruto até o fechamento', () {
      final doc = _parse(
        _doc(
          '<script>if (a<b && c<d) {}</script>'
          '<STYLE>p > a::before { content: "<p>" }</style><p>x</p>',
        ),
      );
      final tree = doc.tree;
      final script = tree.elementsNamed(Namespaces.xhtml, 'script').single;
      expect(tree.textOf(tree.firstChildOf(script)), 'if (a<b && c<d) {}');
      final style = tree.elementsNamed(Namespaces.xhtml, 'STYLE').single;
      expect(
        tree.textOf(tree.firstChildOf(style)),
        'p > a::before { content: "<p>" }',
      );
      expect(tree.elementsNamed(Namespaces.xhtml, 'p'), hasLength(1));
    });

    test('<style> com CDATA mantém o conteúdo da seção', () {
      final doc = _parse(
        '<html xmlns="$_xhtml"><head><style><![CDATA[a<b{}]]></style>'
        '</head><body><p>a < b</p></body></html>',
      );
      final tree = doc.tree;
      final style = tree.elementsNamed(Namespaces.xhtml, 'style').single;
      expect(tree.textOf(tree.firstChildOf(style)), 'a<b{}');
    });

    test('atributo duplicado: vale o primeiro', () {
      final doc = _parse(_doc('<p id="1" id="2">a<p>b'));
      final tree = doc.tree;
      final p = tree.elementsNamed(Namespaces.xhtml, 'p').first;
      expect(tree.attribute(p, Namespaces.none, 'id'), '1');
      expect(_codes(doc), contains(DiagnosticCodes.duplicateAttribute));
    });

    test('</div> solto é descartado', () {
      final doc = _parse(_doc('<p>a</p></div><p>b</p>'));
      expect(_dump(doc.tree), 'html[body[p["a"]p["b"]]]');
      expect(_count(doc, DiagnosticCodes.strayEndTag), 1);
      final stray = doc.diagnostics.firstWhere(
        (d) => d.code == DiagnosticCodes.strayEndTag,
      );
      expect(stray.location, '$_path:1');
    });

    test('fechamento fecha até o correspondente', () {
      final doc = _parse(_doc('<div><span><b>x</div><p>y</p>'));
      expect(_dump(doc.tree), 'html[body[div[span[b["x"]]]p["y"]]]');
      expect(_count(doc, DiagnosticCodes.unclosedElement), 2);
    });

    test('<div><span> sem fechar: fecha tudo no fim', () {
      final doc = _parse('<div><span>x');
      expect(_dump(doc.tree), 'html*[body*[div[span["x"]]]]');
      // Os virtuais não contam; div e span sim.
      expect(_count(doc, DiagnosticCodes.unclosedElement), 2);
      expect(doc.recovered, isTrue);
    });

    test('texto antes de <html> vai para dentro do body virtual', () {
      final doc = _parse(
        'oi<html xmlns="$_xhtml"><body><p>x</p></body></html>',
      );
      expect(_dump(doc.tree), 'html*[body*["oi"p["x"]]]');
      expect(doc.tree.elementsNamed(Namespaces.xhtml, 'p'), hasLength(1));
    });

    test('elemento solto na raiz ganha html e body virtuais', () {
      final doc = _parse('<p>a</p><p>b</p>');
      expect(_dump(doc.tree), 'html*[body*[p["a"]p["b"]]]');
    });

    test('conteúdo depois de </body> fica no body', () {
      final doc = _parse('${_doc('<p>a</p>')}\n<p>b</p>\n');
      expect(_dump(doc.tree), 'html[body[p["a"]p["b"]]]');
    });

    test('raiz svg não é envolvida', () {
      final doc = _parse(
        '<svg xmlns="http://www.w3.org/2000/svg"><g><rect/></svg>',
        mediaType: 'image/svg+xml',
      );
      expect(_dump(doc.tree), 'svg[g[rect]]');
    });

    test("'' e '   ' caem no caminho irrecuperável", () {
      for (final source in ['', '   ', '<!-- só comentário -->']) {
        final doc = _parse(source);
        expect(_dump(doc.tree), 'html*[body*]', reason: source);
        expect(_codes(doc), [DiagnosticCodes.unparseable], reason: source);
        expect(doc.recovered, isTrue);
      }
      final html = _parse('', mediaType: 'text/html');
      expect(_codes(html), [DiagnosticCodes.unparseable]);
    });
  });

  group('robustez', () {
    test('muitos < no texto: termina, tudo vira texto', () {
      final source = _doc('<p>${'<' * 50000}</p>');
      final watch = Stopwatch()..start();
      final doc = _parse(source);
      watch.stop();
      expect(watch.elapsed, lessThan(const Duration(seconds: 20)));
      final p = doc.tree.elementsNamed(Namespaces.xhtml, 'p').single;
      expect(doc.tree.textOf(doc.tree.firstChildOf(p)), '<' * 50000);
      // Limite por código: 20 ocorrências + 1 resumo.
      expect(_count(doc, DiagnosticCodes.markupAsText), 21);
    });

    test('100k <div> sem fechar: tempo linear', () {
      final source = '<div>' * 100000;
      final watch = Stopwatch()..start();
      final doc = _parse(source);
      watch.stop();
      expect(watch.elapsed, lessThan(const Duration(seconds: 20)));
      expect(
        doc.tree.elementsNamed(Namespaces.xhtml, 'div'),
        hasLength(100000),
      );
      expect(_count(doc, DiagnosticCodes.unclosedElement), 21);
      expect(
        doc.diagnostics.last.message,
        contains('100000'),
        reason: 'o resumo traz o total',
      );
    });

    test('100k </span> soltos dentro de 100k <div>: tempo linear', () {
      final source = '${'<div>' * 100000}${'</span>' * 100000}';
      final watch = Stopwatch()..start();
      final doc = _parse(source);
      watch.stop();
      expect(watch.elapsed, lessThan(const Duration(seconds: 20)));
      expect(_count(doc, DiagnosticCodes.strayEndTag), 21);
    });

    test('100k <p> irmãos implícitos: tempo linear', () {
      final source = _doc('<p>x' * 100000);
      final watch = Stopwatch()..start();
      final doc = _parse(source);
      watch.stop();
      expect(watch.elapsed, lessThan(const Duration(seconds: 20)));
      expect(doc.tree.elementsNamed(Namespaces.xhtml, 'p'), hasLength(100000));
    });

    test('entrada com bytes estranhos não lança', () {
      final doc = parseDocumentBytes(
        Uint8List.fromList([0x3C, 0x00, 0xFF, 0x3C, 0x2F, 0x3E, 0x26, 0x3C]),
        path: _path,
      );
      expect(doc.tree.elementsNamed(Namespaces.xhtml, 'body'), hasLength(1));
    });
  });

  group('correções da revisão', () {
    for (final (label, unit) in [
      ('<!DOCTYPE x [', '<!DOCTYPE x ['),
      ('<!DOCTYPE x', '<!DOCTYPE x '),
      ('<![CDATA[', '<![CDATA['),
      ('<!--', '<!--'),
      ('<?x ', '<?x '),
    ]) {
      test('~100 KB de "$label" sem terminador: tempo linear', () {
        final source = _doc('<p>${unit * (100000 ~/ unit.length)}</p>');
        final watch = Stopwatch()..start();
        final doc = _parse(source);
        watch.stop();
        expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
        expect(doc.tree.elementsNamed(Namespaces.xhtml, 'p'), hasLength(1));
      });
    }

    test('comentário sem fim vira texto e o resto do documento segue', () {
      final doc = _parse(_doc('<p>a <!-- b</p><p>c</p>'));
      expect(_dump(doc.tree), 'html[body[p["a <!-- b"]p["c"]]]');
    });

    test('doctype no modo tolerante é descartado e contado', () {
      final doc = _parse(
        '<!DOCTYPE html>\n<html><body><p>a<p>b</body></html>',
        mediaType: 'text/html',
      );
      expect(_dump(doc.tree), 'html[body[p["a"]p["b"]]]');
      final dropped = doc.diagnostics.singleWhere(
        (d) => d.code == DiagnosticCodes.droppedNodes,
      );
      expect(dropped.message, contains('1 doctype'));
    });

    test('text/html: nomes de elemento e atributo em minúsculas', () {
      final doc = _parse(
        '<HTML LANG="pt"><HEAD><TITLE>T</TITLE></HEAD>'
        '<BODY><P CLASS="a">x</P></BODY></HTML>',
        mediaType: 'text/html',
      );
      expect(_dump(doc.tree), 'html[head[title["T"]]body[p["x"]]]');
      expect(doc.head.title, 'T');
      expect(doc.head.lang, 'pt');
      final p = doc.tree.elementsNamed(Namespaces.xhtml, 'p').single;
      expect(doc.tree.attribute(p, Namespaces.none, 'class'), 'a');
    });

    test('text/html: SVG dentro do HTML mantém a caixa', () {
      final doc = _parse(
        '<html><body><svg xmlns="http://www.w3.org/2000/svg" '
        'viewBox="0 0 1 1"><foreignObject/></svg></body></html>',
        mediaType: 'text/html',
      );
      final tree = doc.tree;
      final svg = tree.elementsNamed(
        tree.names.namespaceIdOf('http://www.w3.org/2000/svg')!,
        'svg',
      );
      expect(tree.attribute(svg.single, Namespaces.none, 'viewBox'), '0 0 1 1');
      expect(_dump(tree), 'html[body[svg[foreignObject]]]');
    });

    test('XHTML recuperado mantém a caixa dos nomes', () {
      final doc = _parse(_doc('<P CLASS="a">x'));
      expect(_dump(doc.tree), 'html[body[P["x"]]]');
    });

    test(
      '<html> depois de texto: atributos e prefixos vão ao html virtual',
      () {
        final doc = _parse(
          'oi<html xmlns="$_xhtml" xmlns:ex="urn:ex" lang="pt">'
          '<body><p ex:a="1">x</p></body></html>',
        );
        final tree = doc.tree;
        final html = tree.elementsNamed(Namespaces.xhtml, 'html').single;
        expect(tree.isVirtual(html), isTrue);
        expect(tree.attribute(html, Namespaces.none, 'lang'), 'pt');
        expect(doc.head.lang, 'pt');
        final ex = tree.names.namespaceIdOf('urn:ex');
        expect(ex, isNotNull);
        final p = tree.elementsNamed(Namespaces.xhtml, 'p').single;
        expect(tree.attribute(p, ex!, 'a'), '1');
        expect(_codes(doc), isNot(contains(DiagnosticCodes.undeclaredPrefix)));
      },
    );

    test('<script> dentro de valor de atributo não abre texto bruto', () {
      final doc = _parse(_doc('<p title="<script>">a</p><p>b < c</p>'));
      final tree = doc.tree;
      final ps = tree.elementsNamed(Namespaces.xhtml, 'p');
      expect(ps, hasLength(2));
      expect(tree.attribute(ps.first, Namespaces.none, 'title'), '<script>');
      expect(_dump(tree), 'html[body[p["a"]p["b < c"]]]');
    });

    test('text/html: fechamentos implícitos válidos são info', () {
      final doc = _parse(
        '<html><body><ul><li>a<li>b</ul><p>x<p>y',
        mediaType: 'text/html',
      );
      final unclosed = doc.diagnostics
          .where((d) => d.code == DiagnosticCodes.unclosedElement)
          .toList();
      expect(unclosed, isNotEmpty);
      expect(
        unclosed.map((d) => d.severity),
        everyElement(DiagnosticSeverity.info),
      );
    });

    test('text/html: fechamento trocado continua warning', () {
      final doc = _parse(
        '<html><body><div><span>a</div></body></html>',
        mediaType: 'text/html',
      );
      final unclosed = doc.diagnostics.singleWhere(
        (d) => d.code == DiagnosticCodes.unclosedElement,
      );
      expect(unclosed.severity, DiagnosticSeverity.warning);
    });

    test('XHTML: fechamentos implícitos continuam warning', () {
      final doc = _parse(_doc('<p>a<p>b'));
      final unclosed = doc.diagnostics.firstWhere(
        (d) => d.code == DiagnosticCodes.unclosedElement,
      );
      expect(unclosed.severity, DiagnosticSeverity.warning);
    });
  });
}
