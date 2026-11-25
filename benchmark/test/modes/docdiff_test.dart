// ignore_for_file: implementation_imports

import 'dart:convert';
import 'dart:typed_data';

import 'package:galley/galley.dart';
import 'package:galley/src/features/document/data/parse_document.dart';
import 'package:galley/src/features/document/domain/names.dart';
import 'package:galley/src/features/document/domain/parsed_document.dart';
import 'package:galley/src/features/document/domain/tree_builder.dart';
import 'package:galley_benchmark/src/corpus/handmade.dart';
import 'package:galley_benchmark/src/modes/docdiff.dart';
import 'package:test/test.dart';

import '../support/mini_epub.dart';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

const _xhtml = 'http://www.w3.org/1999/xhtml';

String _doc(String body) =>
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<html xmlns="$_xhtml" xmlns:epub="http://www.idpf.org/2007/ops">'
    '<head><title>t</title></head><body>$body</body></html>';

/// Montador falso: devolve sempre `<html><body><p>outro</p></body></html>`
/// como se fosse a leitura estrita.
ParsedDocument _fakeParser(
  Uint8List bytes, {
  required String path,
  String mediaType = 'application/xhtml+xml',
}) {
  final real = parseDocumentBytes(bytes, path: path, mediaType: mediaType);
  final b = TreeBuilder();
  final n = b.names;
  b
    ..startElement(n.intern(Namespaces.xhtml, 'html'))
    ..startElement(n.intern(Namespaces.xhtml, 'body'))
    ..startElement(n.intern(Namespaces.xhtml, 'p'))
    ..text('outro')
    ..endElement()
    ..endElement()
    ..endElement();
  return ParsedDocument(
    tree: b.build(),
    head: real.head,
    diagnostics: real.diagnostics,
    recovered: false,
  );
}

/// Leitura falsa que marca o documento como recuperado (e, com
/// [internalError], como defeito interno).
DocumentBytesParser _recoveredParser({String? internalError}) =>
    (bytes, {required path, mediaType = 'application/xhtml+xml'}) {
      final real = parseDocumentBytes(bytes, path: path, mediaType: mediaType);
      return ParsedDocument(
        tree: real.tree,
        head: real.head,
        diagnostics: real.diagnostics,
        recovered: true,
        internalError: internalError,
      );
    };

void main() {
  group('compareDocument', () {
    test('documentos idênticos: bate, sem divergência', () {
      final report = DocDiffReport()
        ..add(compareDocument('a.xhtml', _bytes(_doc('<p>um</p>'))))
        ..add(compareDocument('b.xhtml', _bytes(_doc('<p>dois</p>'))));

      expect(report.total, 2);
      expect(report.matched, 2);
      expect(report.mismatches, isEmpty);
      expect(report.exitCode, 0);
    });

    test('árvore divergente (montador falso): 1 divergência com o evento', () {
      final report = DocDiffReport()
        ..add(
          compareDocument(
            'livro/cap1.xhtml',
            _bytes(_doc('<p>um</p>')),
            parse: _fakeParser,
          ),
        );

      expect(report.mismatches, hasLength(1));
      final m = report.mismatches.single;
      expect(m.path, 'livro/cap1.xhtml');
      // html bate; o primeiro evento divergente é a entrada no <body> × <head>.
      expect(m.index, 1);
      expect(m.ours, contains('body'));
      expect(m.dom, contains('head'));
      expect(report.exitCode, 1);
      final bmf = report.toBmf();
      expect((bmf['docdiff/mismatch']! as Map)['count'], {'value': 1.0});
      final summary = report.summary();
      expect(summary, contains('livro/cap1.xhtml'));
      expect(summary, contains('evento 1'));
    });

    test('documento malformado: tolerante, fora da comparação', () {
      final report = DocDiffReport()
        ..add(compareDocument('m.xhtml', _bytes(_doc('<p>aberto</div>'))));

      expect(report.total, 1);
      expect(report.tolerant, 1);
      expect(report.matched, 0);
      expect(report.mismatches, isEmpty);
      expect(report.exitCode, 0);
      expect((report.toBmf()['docdiff/mismatch']! as Map)['count'], {
        'value': 0.0,
      });
    });

    test('diferenças intencionais normalizadas no lado do DOM', () {
      final cases = <String, String>{
        'crlf': _doc('<p>a\r\nb\rc</p>'),
        'atributo com TAB/LF': _doc('<p title="a\tb\nc">x</p>'),
        'caractere proibido': _doc('<p title="a&#1;b">x&#1;y</p>'),
        'epub: sem declaração':
            '<html xmlns="$_xhtml"><body>'
            '<section epub:type="chapter">x</section></body></html>',
        'xlink: sem declaração':
            '<html xmlns="$_xhtml"><body>'
            '<svg xmlns="http://www.w3.org/2000/svg"><a xlink:href="#x"/>'
            '</svg></body></html>',
        'outro prefixo sem declaração':
            '<html xmlns="$_xhtml"><body>'
            '<foo:bar foo:baz="1">x</foo:bar></body></html>',
        'atributo repetido': _doc('<p class="a" class="b">x</p>'),
        'comentário e CDATA no meio do texto': _doc(
          '<p>a<!-- c -->b<![CDATA[<c>]]>d<?pi x?>e</p>',
        ),
        'entidades HTML5': _doc('<p>&nbsp;&eacute;&amp;&#x263A;</p>'),
        'xml:lang': _doc('<p xml:lang="pt">x</p>'),
      };
      for (final MapEntry(key: name, value: text) in cases.entries) {
        final outcome = compareDocument('$name.xhtml', _bytes(text));
        expect(outcome.kind, DocDiffKind.match, reason: '$name: $outcome');
      }
    });

    test('internalError: falha própria, exit 1, fora do tolerante', () {
      final report = DocDiffReport()
        ..add(
          compareDocument(
            'livro/cap1.xhtml',
            _bytes(_doc('<p>um</p>')),
            parse: _recoveredParser(internalError: 'RangeError'),
          ),
        );

      expect(report.internalErrors, hasLength(1));
      expect(report.internalErrors.single.kind, DocDiffKind.internalError);
      expect(report.tolerant, 0);
      expect(report.exitCode, 1);
      expect((report.toBmf()['docdiff/internal-error']! as Map)['count'], {
        'value': 1.0,
      });
      final summary = report.summary();
      expect(summary, contains('RangeError'));
      expect(summary, contains('livro/cap1.xhtml'));
    });

    test('XHTML tolerante que o DOM lê: contado à parte, não reprova', () {
      final report = DocDiffReport()
        ..add(
          compareDocument(
            'livro/cap1.xhtml',
            _bytes(_doc('<p>um</p>')),
            parse: _recoveredParser(),
          ),
        );

      expect(report.tolerantDomParsed, hasLength(1));
      expect(report.tolerant, 0);
      expect(report.exitCode, 0);
      expect((report.toBmf()['docdiff/tolerant-dom-parsed']! as Map)['count'], {
        'value': 1.0,
      });
      expect(report.summary(), contains('livro/cap1.xhtml'));
    });

    test('text/html vai ao modo tolerante e fica fora', () {
      final outcome = compareDocument(
        'h.html',
        _bytes(_doc('<p>x</p>')),
        mediaType: 'text/html',
      );
      // Bem formado, mas text/html vai direto ao tolerante: não conta como
      // "tolerante que o DOM lê".
      expect(outcome.kind, DocDiffKind.tolerant);
    });
  });

  test('diffBook: livros escritos à mão sem divergência', () async {
    final books = await buildHandmadeCorpus();
    final report = DocDiffReport();
    for (final MapEntry(key: key, value: bytes) in books.entries) {
      final book = await EpubBook.fromBytes(bytes);
      try {
        await diffBook(book, key, report);
      } finally {
        await book.close();
      }
    }
    expect(report.mismatches, isEmpty, reason: report.summary());
    expect(report.matched, greaterThan(0));
  });

  test('diffBook: capítulo malformado conta como tolerante', () async {
    final book = await EpubBook.fromBytes(
      buildMiniEpub([_doc('<p>ok</p>'), _doc('<p>aberto</div>')]),
    );
    final report = DocDiffReport();
    try {
      await diffBook(book, 'mini', report);
    } finally {
      await book.close();
    }
    expect(report.total, 2);
    expect(report.matched, 1);
    expect(report.tolerant, 1);
    expect(report.summary(), contains('tolerante'));
  });
}
