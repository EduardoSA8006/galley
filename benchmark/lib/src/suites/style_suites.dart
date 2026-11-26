// ignore_for_file: implementation_imports

import 'dart:convert';
import 'dart:typed_data';

import 'package:galley/galley.dart';
import 'package:galley/src/features/document/data/parse_document.dart';
import 'package:galley/src/features/document/domain/parsed_document.dart';
import 'package:galley/src/features/style/data/book_style_context.dart';
import 'package:galley/src/features/style/data/stylesheet_builder.dart';
import 'package:galley/src/features/style/data/style_document.dart';
import 'package:galley/src/features/style/domain/matched_document.dart';
import 'package:galley/src/features/style/domain/reader_preferences.dart';
import 'package:galley/src/features/style/domain/restyle.dart';
import 'package:galley/src/features/style/domain/style_environment.dart';
import 'package:galley/src/features/style/domain/styled_document.dart';

import '../bench.dart';
import '../corpus/handmade.dart';
import 'document_suites.dart';

/// Tamanho da folha sintética grande do `style/parse-sheet-256kib`.
const int kLargeCssBytes = 256 * 1024;

/// Tamanho alvo da folha de editora sintética ([buildPublisherCss]).
const int kPublisherCssBytes = 40 * 1024;

/// Número de regras descendentes do `style/match-descendant-heavy`.
const int kDescendantRules = 2000;

/// Caminho da folha ligada pelo XHTML sintético, no zip.
const String _sheetPath = 'OEBPS/estilo.css';

/// `<link>` que o XHTML sintético usa para a folha de [_sheetPath].
const String _sheetLink = '<link rel="stylesheet" href="estilo.css"/>';

/// Ambiente de página dos benchmarks.
const StyleEnvironment _env = StyleEnvironment(pageWidth: 500, pageHeight: 800);

/// Preferências de troca de fonte, tamanho (1,2) e tema escuro.
const ReaderPreferences _literataDark = ReaderPreferences(
  fontFamily: Preference('Literata', policy: PreferencePolicy.force),
  fontSize: Preference(1.2),
  theme: Preference(
    ReaderTheme(background: 0xFF121212, text: 0xFFE0E0E0, link: 0xFF8AB4F8),
    policy: PreferencePolicy.force,
  ),
);

/// Cabeçalho fixo da folha de editora: reset, `@font-face`, `@page` e o
/// estilo-base do corpo, no tom das folhas do Gutenberg e dos livros privados.
const String _cssHead = r'''
@charset "utf-8";
@font-face { font-family: "Livro Serif"; font-weight: 400;
  src: url(../fonts/LivroSerif-Regular.otf) format("opentype"); }
@font-face { font-family: "Livro Serif"; font-style: italic;
  src: url("../fonts/LivroSerif-Italic.otf"); }
@font-face { font-family: "Livro Sans"; font-weight: 700;
  src: url(../fonts/LivroSans-Bold.otf); }
@page { margin: 5pt 1em; }
html, body { margin: 0; padding: 0; }
body { font-family: "Livro Serif", Georgia, serif; font-size: 100%;
  line-height: 1.4; orphans: 2; widows: 2; }
h1, h2, h3 { font-family: "Livro Sans", Arial, sans-serif; font-weight: bold;
  text-align: center; page-break-after: avoid; margin: 2em 0 1em; }
h2 { font-size: 1.4em; letter-spacing: 0.05em; text-transform: uppercase; }
p { margin: 0; text-indent: 1.5em; text-align: justify; hyphens: auto; }
p.texto { color: #222; line-height: 1.5 !important; }
p.texto:first-child { text-indent: 0; text-align: left !important; }
p.texto::first-letter { font-size: 2.2em; float: left; }
em.e, i { font-style: italic; }
a { color: #0645ad; text-decoration: none; }
a[href^="#"] { text-decoration: underline; }
table.t { border-collapse: collapse; width: 90% !important; margin: 1em auto; }
table.t th, table.t td { border: 1px solid #888; padding: 0.2em 0.4em; }
ruby rt { font-size: 0.5em; }
img { max-width: 100%; height: auto; }
''';

/// Um bloco de regras variadas, deterministicamente derivado de [i]:
/// classe, id, descendente, filho, adjacente, atributo, `@media` e, de vez
/// em quando, `!important` em `line-height`, `text-align` e `width`.
void _writeRuleBlock(StringBuffer b, int i) {
  final c = i % 7;
  final hex = 0x100 + (i * 37) % 0xE00;
  b
    ..write(
      '.k$i { margin: 0 ${i % 5}em; color: #${hex.toRadixString(16)}; }\n',
    )
    ..write(
      'section.c$c > p.texto + p { text-indent: 1.${i % 9}em; '
      'line-height: 1.${3 + i % 5}; }\n',
    )
    ..write(
      'section.cap h2, div.l$i h3 { font-size: ${100 + i % 60}%; '
      'margin: ${i % 4}em 0 ${1 + i % 3}em; }\n',
    )
    ..write(
      'table.t td:nth-child(${i % 3 + 1}) { text-align: right; '
      'padding: 0.${i % 9}em; }\n',
    )
    ..write(
      'p.texto em.e a, section.c$c span.s$i { color: #${hex.toRadixString(16)}; '
      'font-weight: ${i.isEven ? 'bold' : 'normal'}; }\n',
    )
    ..write('#s$i p { margin-top: ${i % 6}px; }\n')
    ..write(
      '@media (min-width: ${300 + i % 400}px) { .c$c p { '
      'text-indent: ${i % 3}em; } }\n',
    );
  if (i % 17 == 0) {
    b.write(
      'section.c$c p { line-height: 1.${3 + i % 4} !important; '
      'text-align: ${i.isEven ? 'justify' : 'left'} !important; }\n',
    );
  }
  if (i % 23 == 0) {
    b.write('div.l$i img { width: ${50 + i % 50}% !important; }\n');
  }
}

/// Folha de editora determinística de ~[kPublisherCssBytes] (40 KiB),
/// misturando o estilo do Gutenberg e o dos livros privados (ver
/// [_writeRuleBlock]); casa com o XHTML de [buildLargeXhtml].
String buildPublisherCss() => buildLargeCss(kPublisherCssBytes);

/// Folha determinística de pelo menos [targetBytes] bytes: o cabeçalho de
/// [buildPublisherCss] seguido de blocos de regras variadas.
String buildLargeCss(int targetBytes) {
  final b = StringBuffer(_cssHead);
  var i = 0;
  while (b.length < targetBytes) {
    _writeRuleBlock(b, i++);
  }
  return b.toString();
}

/// Folha com [count] regras descendentes distintas (3 níveis, com
/// pseudo-classes), todas sobre o vocabulário de [buildLargeXhtml].
String buildDescendantCss(int count) {
  const outer = <String>[
    'body',
    'section',
    '.cap',
    '.c0',
    '.c1',
    '.c2',
    '.c3',
    '.c4',
    '.c5',
    '.c6',
  ];
  const middle = <String>['p', 'table', '.t', 'tbody', 'tr', 'h2'];
  const inner = <String>[
    'em',
    'a',
    'span',
    'td',
    'th',
    '.e',
    '.texto',
    'ruby',
    'rt',
  ];
  const suffix = <String>[
    '',
    ':first-child',
    ':last-child',
    ':nth-child(2)',
    ':only-child',
  ];
  final b = StringBuffer();
  for (var i = 0; i < count; i++) {
    var n = i;
    final o = outer[n % outer.length];
    n ~/= outer.length;
    final m = middle[n % middle.length];
    n ~/= middle.length;
    final t = inner[n % inner.length];
    n ~/= inner.length;
    final s = suffix[n % suffix.length];
    b.write(
      '$o $m $t$s { color: #${(0x100 + i % 0xE00).toRadixString(16)}; }\n',
    );
  }
  return b.toString();
}

/// Soma que depende do estilo calculado; falha se o estilo caiu no
/// reserva por defeito interno (o benchmark mediria outra coisa).
int _styledChecksum(StyledDocument s) {
  if (s.internalError != null) {
    throw StateError('erro interno no estilo: ${s.internalError}');
  }
  return s.distinctStyleCount * 31 + s.retainedBytes;
}

int _matchedChecksum(MatchedDocument m) {
  if (m.internalError != null) {
    throw StateError('erro interno no casamento: ${m.internalError}');
  }
  return m.retainedBytes;
}

BookStyleContext _contextFor(Map<String, Uint8List> resources, String key) =>
    BookStyleContext(resolve: (p) => resources[p], bookKey: key);

/// Livro de um capítulo grande (1 MiB) que liga [css] e o contexto
/// aquecido: o casamento roda uma vez para a folha entrar no cache, como
/// num capítulo N de um livro aberto.
({ParsedDocument document, BookStyleContext context}) _warmChapter(
  String css,
  String key,
) {
  final document = parseDocumentBytes(
    buildLargeXhtml(kLargeXhtmlBytes, head: _sheetLink),
    path: 'OEBPS/grande.xhtml',
  );
  final context = _contextFor({
    _sheetPath: Uint8List.fromList(utf8.encode(css)),
  }, key);
  _matchedChecksum(matchDocument(context, document, _env));
  return (document: document, context: context);
}

/// Repetições do estilo do spine por livro, para o ciclo cair em 10–50 ms
/// (calibradas em ~35 ms nativos).
const Map<String, int> _spineRepeats = {
  'typography': 76,
  'publisher-css': 98,
  'tables': 113,
  'notes': 117,
  'images': 200,
  'cjk': 113,
  'rtl-bidi': 150,
  'fonts-idpf': 310,
  'fonts-adobe': 360,
  'epub2-ncx': 175,
};

Future<Map<String, Uint8List>>? _corpus;

/// Documentos do spine de `hm/<name>` já parseados e o contexto de estilo
/// do livro (folhas lidas do manifest) aquecido.
Future<({List<ParsedDocument> documents, BookStyleContext context})>
_spineStyleInput(String name) async {
  final corpus = await (_corpus ??= buildHandmadeCorpus());
  final book = await EpubBook.fromBytes(corpus['hm/$name']!);
  try {
    final resources = <String, Uint8List>{
      for (final item in book.manifest.values)
        if (item.mediaType == 'text/css')
          item.path: await book.resource(item.path),
    };
    final documents = <ParsedDocument>[
      for (final item in book.spine.items)
        parseDocumentBytes(
          await book.resource(item.item.path),
          path: item.item.path,
          mediaType: item.item.mediaType,
        ),
    ];
    final context = _contextFor(resources, 'hm/$name');
    for (final d in documents) {
      _matchedChecksum(matchDocument(context, d, _env));
    }
    return (documents: documents, context: context);
  } finally {
    await book.close();
  }
}

/// Benchmarks de estilo: leitura de folha, estilo completo e `restyle` de um
/// capítulo de 1 MiB (lado a lado: a meta é `restyle` ≥ 5× mais rápido),
/// casamento de regras descendentes e o spine dos livros `hm/*`.
List<Bench> styleBenches() => <Bench>[
  PreparedBench('style/parse-sheet-256kib', () async {
    final css = buildLargeCss(kLargeCssBytes);
    return () {
      final sheet = buildStyleSheet(
        css,
        path: 'OEBPS/grande.css',
        fontPrefix: 'gf0-',
        sink: const NullDiagnosticSink(),
      );
      return sheet.rules.length * 31 + sheet.fontFaces.length;
    };
  }),
  // Estilo completo do capítulo N: casamento + `restyle`, folha já lida.
  PreparedBench('style/full-large-1mib', () async {
    final (:document, :context) = _warmChapter(
      buildPublisherCss(),
      'style/full-large',
    );
    return () {
      final matched = matchDocument(context, document, _env);
      return _matchedChecksum(matched) +
          _styledChecksum(restyle(matched, _literataDark));
    };
  }),
  // Só a troca de preferências sobre o casamento guardado: uma passada com
  // Literata/tamanho 1,2/tema escuro.
  PreparedBench('style/restyle-large-1mib', () async {
    final (:document, :context) = _warmChapter(
      buildPublisherCss(),
      'style/restyle-large',
    );
    final matched = matchDocument(context, document, _env);
    _matchedChecksum(matched);
    return () => _styledChecksum(restyle(matched, _literataDark));
  }),
  PreparedBench('style/match-descendant-heavy', () async {
    final (:document, :context) = _warmChapter(
      buildDescendantCss(kDescendantRules),
      'style/descendant-heavy',
    );
    return () => _matchedChecksum(matchDocument(context, document, _env));
  }),
  for (final name in kHandmadeSpineBooks)
    PreparedBench('style/spine-hm-$name', () async {
      final input = await _spineStyleInput(name);
      final repeats = _spineRepeats[name]!;
      return () {
        var sum = 0;
        for (var r = 0; r < repeats; r++) {
          for (final d in input.documents) {
            sum += _styledChecksum(
              styleDocument(input.context, d, _env, ReaderPreferences.none),
            );
          }
        }
        return sum;
      };
    }),
];
