import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/core/diagnostics/diagnostic.dart';
import 'package:galley/src/core/diagnostics/diagnostic_codes.dart';
import 'package:galley/src/core/diagnostics/diagnostic_sink.dart';
import 'package:galley/src/core/errors/galley_exception.dart';
import 'package:galley/src/features/container/domain/epub_book.dart';
import 'package:galley/src/features/document/data/parse_document.dart';
import 'package:galley/src/features/document/domain/document_tree.dart';
import 'package:galley/src/features/document/domain/parsed_document.dart';
import 'package:galley/src/features/style/data/book_style_context.dart';
import 'package:galley/src/features/style/data/style_document.dart';
import 'package:galley/src/features/style/domain/computed_style.dart';
import 'package:galley/src/features/style/domain/css_value.dart';
import 'package:galley/src/features/style/domain/properties.dart';
import 'package:galley/src/features/style/domain/reader_preferences.dart';
import 'package:galley/src/features/style/domain/restyle.dart';
import 'package:galley/src/features/style/domain/selector.dart';
import 'package:galley/src/features/style/domain/style_environment.dart';
import 'package:galley/src/features/style/domain/styled_document.dart';

import '../../support/epub_builder.dart';
import '../../support/style_fixture.dart';

const _xhtml = 'http://www.w3.org/1999/xhtml';
const _env = StyleEnvironment(pageWidth: 500, pageHeight: 800);

const _sharedCss = '''
@font-face { font-family: "Serifa Livro"; src: url(fonts/serifa.otf); }
body { font-family: "Serifa Livro", serif; font-size: 18px; }
p { margin: 0; text-indent: 1em; color: zzz; }
h1 { font-family: Georgia, serif; }
p.nota::before { content: "* "; }
''';

String _chapter(String title, String inline) =>
    '<html xmlns="$_xhtml"><head><title>$title</title>'
    '<link rel="stylesheet" href="style.css"/>'
    '<style>em { font-style: italic; } $inline</style></head>'
    '<body><h1>$title</h1><p class="nota">Texto <em>corrido</em>.</p>'
    '<p style="color: #102030">Outro parágrafo com '
    '<span style="font-weight: bold">peso</span>.</p></body></html>';

final Uint8List _epub = buildEpub({
  'OEBPS/content.opf': opf3(
    manifest:
        '<item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="c2" href="c2.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="css" href="style.css" media-type="text/css"/>',
    spine: '<itemref idref="c1"/><itemref idref="c2"/>',
  ),
  'OEBPS/c1.xhtml': _chapter('Um', 'h1 { color: #800000; }'),
  'OEBPS/c2.xhtml': _chapter('Dois', 'h1 { color: #008000; }'),
  'OEBPS/style.css': _sharedCss,
});

/// Livro, resolvedor pré-lido e documentos parseados.
final class _Fixture {
  _Fixture(this.resources, this.documents);

  final Map<String, Uint8List> resources;
  final List<ParsedDocument> documents;

  BookStyleContext context() =>
      BookStyleContext(resolve: (p) => resources[p], bookKey: 'livro-teste');
}

Future<_Fixture> _fixture() async {
  final book = await EpubBook.fromBytes(_epub);
  final resources = {'OEBPS/style.css': await book.resource('OEBPS/style.css')};
  final documents = [
    await parseDocument(book, 'OEBPS/c1.xhtml'),
    await parseDocument(book, 'OEBPS/c2.xhtml'),
  ];
  return _Fixture(resources, documents);
}

ReaderPreferences _all(PreferencePolicy policy) => ReaderPreferences(
  fontFamily: Preference('Literata', policy: policy),
  fontSize: Preference(1.5, policy: policy),
  lineHeight: Preference(2, policy: policy),
  paragraphSpacing: Preference(0.5, policy: policy),
  textIndent: Preference(2, policy: policy),
  textAlign: Preference(ReaderTextAlign.start, policy: policy),
  hyphenation: Preference(true, policy: policy),
  wordSpacing: Preference(0.25, policy: policy),
  letterSpacing: Preference(0.1, policy: policy),
  theme: Preference(
    const ReaderTheme(
      background: 0xFF101010,
      text: 0xFFEEEEEE,
      link: 0xFF80B0FF,
    ),
    policy: policy,
  ),
);

/// Compara os dois resultados elemento a elemento (e pseudo-elemento a
/// pseudo-elemento): igualdade por valor e `stableHash`.
void _expectSameStyles(DocumentTree tree, StyledDocument a, StyledDocument b) {
  for (var n = 0; n < tree.nodeCount; n++) {
    final ia = a.elementStyles[n];
    final ib = b.elementStyles[n];
    expect(ia < 0, ib < 0, reason: 'nó $n');
    if (ia < 0) continue;
    final sa = a.styles[ia];
    final sb = b.styles[ib];
    expect(sa, sb, reason: 'nó $n');
    expect(sa.stableHash, sb.stableHash, reason: 'nó $n');
    for (final kind in PseudoElement.values) {
      final pa = a.pseudoStyleOf(n, kind);
      final pb = b.pseudoStyleOf(n, kind);
      expect(pa == null, pb == null, reason: 'nó $n $kind');
      if (pa == null) continue;
      expect(a.styles[pa], b.styles[pb!], reason: 'nó $n $kind');
      expect(a.styles[pa].stableHash, b.styles[pb].stableHash);
      expect(a.generatedTextOf(n, kind), b.generatedTextOf(n, kind));
    }
  }
}

List<String> _families(ComputedStyle s) => [
  for (final f in (s[PropertyId.fontFamily] as CssFontFamilies).families)
    f.name,
];

void main() {
  group('styleDocument num EPUB', () {
    test('folha compartilhada, <style>, style= e @font-face: nomes internos '
        'e diagnósticos da folha uma vez só', () async {
      final f = await _fixture();
      final context = f.context();
      final sink = CollectingDiagnosticSink();
      final internal = context.internalFamilyName('Serifa Livro');
      expect(internal, startsWith(context.fontPrefix));

      final results = [
        for (final doc in f.documents)
          styleDocument(context, doc, _env, ReaderPreferences.none, sink: sink),
      ];
      for (var i = 0; i < 2; i++) {
        final styled = results[i];
        final tree = f.documents[i].tree;
        expect(styled.internalError, isNull);
        // A tabela de @font-face sai com o nome interno do livro.
        final face = styled.fontFaces.single;
        expect(face.family, 'Serifa Livro');
        expect(face.internalFamily, internal);
        // O ComputedStyle troca a família do documento pelo nome interno.
        final p = elementsNamed(tree, 'p').first;
        expect(_families(styleOfElement(styled, p)), [internal, 'serif']);
        final h1 = elementsNamed(tree, 'h1').single;
        expect(_families(styleOfElement(styled, h1)), ['Georgia', 'serif']);
        // <style> do capítulo e style= chegam ao estilo.
        expect(
          styleOfElement(styled, h1)[PropertyId.color],
          CssColor(i == 0 ? 0xFF800000 : 0xFF008000),
        );
        final span = elementsNamed(tree, 'span').single;
        expect(
          styleOfElement(styled, span)[PropertyId.fontWeight],
          const CssNumber(700),
        );
        expect(
          styleOfElement(styled, elementsNamed(tree, 'p')[1])[PropertyId.color],
          const CssColor(0xFF102030),
        );
        expect(styled.generatedTextOf(p, PseudoElement.before), '* ');
      }
      final fromShared = sink.diagnostics
          .where((d) => d.location?.startsWith('OEBPS/style.css') ?? false)
          .toList();
      expect(fromShared, hasLength(1));
      expect(fromShared.single.code, DiagnosticCodes.cssInvalidValue);
    });

    for (final (name, prefs) in [
      ('none', ReaderPreferences.none),
      ('todas (ajustar)', _all(PreferencePolicy.adjust)),
      ('todas (forçar)', _all(PreferencePolicy.force)),
    ]) {
      test('restyle(matchDocument) == styleDocument: $name', () async {
        final f = await _fixture();
        for (final doc in f.documents) {
          final matched = matchDocument(f.context(), doc, _env);
          final viaRestyle = restyle(matched, prefs);
          final direct = styleDocument(f.context(), doc, _env, prefs);
          _expectSameStyles(doc.tree, viaRestyle, direct);
          expect(direct.pageBackground, viaRestyle.pageBackground);
        }
      });
    }

    test('Isolate.run: estilos iguais aos locais, sem erro', () async {
      final f = await _fixture();
      final resources = f.resources;
      final prefs = _all(PreferencePolicy.adjust);
      for (final doc in f.documents) {
        final local = styleDocument(f.context(), doc, _env, prefs);
        final remote = await Isolate.run(() {
          final context = BookStyleContext(
            resolve: (p) => resources[p],
            bookKey: 'livro-teste',
          );
          return styleDocument(context, doc, _env, prefs);
        });
        expect(remote.internalError, isNull);
        _expectSameStyles(doc.tree, local, remote);
        expect(
          remote.fontFaces.single.internalFamily,
          local.fontFaces.single.internalFamily,
        );
      }
    });
  });

  group('guardMatch (o catch-all de matchDocument)', () {
    test('exceção inesperada: só a folha padrão, internalError', () async {
      final f = await _fixture();
      final doc = f.documents.first;
      final sink = CollectingDiagnosticSink();
      final matched = guardMatch(
        doc,
        () => throw StateError('bug no casamento'),
        environment: _env,
        sink: sink,
      );
      expect(matched.internalError, 'StateError');
      final error = sink.diagnostics.single;
      expect(error.code, DiagnosticCodes.cssInternalError);
      expect(error.severity, DiagnosticSeverity.error);
      expect(error.location, doc.path);
      expect(error.message, contains('StateError'));
      expect(matched.fontFaces, isEmpty);

      // Os estilos são os da folha padrão sozinha.
      final styled = restyle(matched, ReaderPreferences.none);
      expect(styled.internalError, 'StateError');
      final tree = doc.tree;
      final p = elementsNamed(tree, 'p').first;
      final ps = styleOfElement(styled, p);
      expect(ps[PropertyId.marginTop], const CssLength(px: 16));
      expect(ps[PropertyId.color], isNot(const CssColor(0xFF102030)));
      final h1 = elementsNamed(tree, 'h1').single;
      expect(
        styleOfElement(styled, h1)[PropertyId.fontSize],
        const CssLength(px: 32),
      );
      final title = elementsNamed(tree, 'title').single;
      expect(
        styleOfElement(styled, title)[PropertyId.display],
        const CssKeyword(CssKeywords.none),
      );
    });

    test('GalleyException escapa', () async {
      final f = await _fixture();
      expect(
        () => guardMatch(
          f.documents.first,
          () => throw const BookClosedException(),
          environment: _env,
        ),
        throwsA(isA<BookClosedException>()),
      );
    });

    test(
      'matchDocument com resolvedor que lança erro comum: não lança',
      () async {
        final f = await _fixture();
        final context = BookStyleContext(
          resolve: (_) => throw StateError('resolvedor quebrado'),
          bookKey: 'livro',
        );
        final sink = CollectingDiagnosticSink();
        final matched = matchDocument(
          context,
          f.documents.first,
          _env,
          sink: sink,
        );
        expect(matched.internalError, 'StateError');
        expect(
          sink.diagnostics.map((d) => d.code),
          contains(DiagnosticCodes.cssInternalError),
        );
      },
    );

    test('sem exceção: devolve o resultado do corpo', () async {
      final f = await _fixture();
      final inner = matchDocument(f.context(), f.documents.first, _env);
      expect(inner.internalError, isNull);
      expect(
        guardMatch(f.documents.first, () => inner, environment: _env),
        same(inner),
      );
    });
  });

  group('guardRestyle (o catch-all de restyle)', () {
    test(
      'exceção inesperada: estilos da folha padrão, internalError',
      () async {
        final f = await _fixture();
        final doc = f.documents.first;
        final matched = matchDocument(f.context(), doc, _env);
        final sink = CollectingDiagnosticSink();
        final styled = guardRestyle(
          matched,
          () => throw StateError('bug no restyle'),
          sink: sink,
        );
        expect(styled.internalError, 'StateError');
        final error = sink.diagnostics.single;
        expect(error.code, DiagnosticCodes.cssInternalError);
        expect(error.severity, DiagnosticSeverity.error);
        expect(error.location, doc.path);
        expect(styled.fontFaces, isEmpty);
        final p = elementsNamed(doc.tree, 'p').first;
        final ps = styleOfElement(styled, p);
        expect(ps[PropertyId.marginTop], const CssLength(px: 16));
        expect(ps[PropertyId.textIndent], isNot(const CssLength(px: 18)));
        // Todo elemento tem estilo.
        for (var n = 0; n < doc.tree.nodeCount; n++) {
          expect(
            styled.elementStyles[n] >= 0,
            doc.tree.kindOf(n) == NodeKind.element,
          );
        }
      },
    );

    test('GalleyException escapa', () async {
      final f = await _fixture();
      final matched = matchDocument(f.context(), f.documents.first, _env);
      expect(
        () => guardRestyle(matched, () => throw const BookClosedException()),
        throwsA(isA<BookClosedException>()),
      );
    });

    test('sem exceção: devolve o resultado do corpo', () async {
      final f = await _fixture();
      final matched = matchDocument(f.context(), f.documents.first, _env);
      final inner = restyle(matched, ReaderPreferences.none);
      expect(guardRestyle(matched, () => inner), same(inner));
    });
  });

  group('isValidFor e o tamanho da página', () {
    test('font-size em vw/vh: outra página invalida o casamento', () {
      for (final css in ['p{font-size:5vw}', 'p{font-size:2vh}']) {
        final m = matchCss('<p>a</p>', css: css);
        expect(m.isValidFor(testEnvironment), isTrue, reason: css);
        expect(
          m.isValidFor(const StyleEnvironment(pageWidth: 600, pageHeight: 800)),
          isFalse,
          reason: css,
        );
        expect(
          m.isValidFor(const StyleEnvironment(pageWidth: 500, pageHeight: 900)),
          isFalse,
          reason: css,
        );
      }
    });

    test('sem vw/vh em font-size: outra página não invalida', () {
      final m = matchCss(
        '<p>a</p>',
        css: 'p{font-size:12px; margin-left:5vw; width:10vh}',
      );
      expect(
        m.isValidFor(const StyleEnvironment(pageWidth: 600, pageHeight: 900)),
        isTrue,
      );
    });

    test('font-size em vw no style=: também invalida', () {
      final m = matchCss('<p style="font-size:3vw">a</p>');
      expect(
        m.isValidFor(const StyleEnvironment(pageWidth: 600, pageHeight: 800)),
        isFalse,
      );
    });
  });
}
