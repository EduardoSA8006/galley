// O CSS sobre os 68 EPUBs do corpus (spec do CSS §14.1): códigos
// comparados com o diagnostics.expected, strict com segunda passada,
// afirmações estruturais em toda seção e as específicas por caso.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/container/zip/zip_container.dart';
import 'package:galley/src/css/cascade.dart';
import 'package:galley/src/css/computed_style.dart';
import 'package:galley/src/css/loader.dart';
import 'package:galley/src/css/properties.dart';
import 'package:galley/src/css/rule_index.dart';
import 'package:galley/src/diagnostics/diagnostic.dart';
import 'package:galley/src/diagnostics/exceptions.dart';
import 'package:galley/src/io/file_byte_source.dart';
import 'package:galley/src/publication/model.dart';
import 'package:galley/src/publication/read_publication.dart';
import 'package:galley/src/publication/xml_text.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

/// Códigos que só o CSS emite: o conjunto emitido é igual ao do
/// `.expected`.
const cssCodes = {
  'stylesheetIgnored',
  'stylesheetMediaIgnored',
  'cssRuleIgnored',
  'unsupportedLayout',
};

/// Códigos que o CSS reusa de outras camadas: se emitidos, precisam
/// constar do `.expected` (podem ser de outra camada).
const sharedCodes = {
  'resourceMissing',
  'resourceUnreadable',
  'encodingFallback',
};

/// Warnings só do CSS no `.expected`: o caso roda sem `strict` e ganha a
/// segunda passada (decisão 21 do plano, spec §14.1; `resourceMissing` do
/// `.expected` pode ser da Publicação, como em `regressoes/capa-ausente`).
const cssWarnings = {'unsupportedLayout', 'stylesheetIgnored'};

/// Grupos que rodam com `strict: false` (doc/10 §5).
const relaxedGroups = {'patologia', 'faixa-b'};

List<String> _lines(File f) => f.existsSync()
    ? f.readAsLinesSync().where((l) => l.isNotEmpty).toList()
    : const [];

final class _Section {
  _Section(this.path, this.document, this.sheets, this.styles);

  final String path;
  final Document document;
  final SectionSheets sheets;
  final SectionStyles styles;
}

/// Todas as seções XHTML do spine, com um cache de folhas e um sink do CSS
/// por livro.
Future<(List<_Section>, DiagnosticSink)> _run(
  String dir, {
  required bool strict,
}) async {
  final containerSink = DiagnosticSink(strict: strict);
  final container = await ZipContainer.open(
    FileEpubByteSource('$dir/book.epub'),
    sink: containerSink,
  );
  try {
    final publication = await readPublication(
      container,
      sink: DiagnosticSink(),
    );
    final cssSink = DiagnosticSink(strict: strict);
    final cache = StyleSheetCache();
    final sections = <_Section>[];
    for (final item in publication.spine) {
      final content = item.content;
      if (item.kind != SectionKind.xhtml || content.missing || content.remote) {
        continue;
      }
      final resource = await container.fetch(content.path);
      if (resource == null) continue;
      for (final _ in resource.decode()) {}
      final document = html.parse(
        decodeXml(
          resource.bytes,
          path: content.path,
          sink: DiagnosticSink(),
          htmlMeta: true,
        ),
      );
      final sheets = await loadSectionSheets(
        container,
        document,
        sectionPath: content.path,
        cache: cache,
        sink: cssSink,
        containerSink: containerSink,
      );
      final styles = computeStylesSync(
        document,
        sheets,
        sectionPath: content.path,
        sink: cssSink,
        recordOrigins: true,
      );
      sections.add(_Section(content.path, document, sheets, styles));
    }
    return (sections, cssSink);
  } finally {
    await container.close();
  }
}

/// Elementos de [document] em ordem, fora das subárvores de `template`.
List<Element> _elements(Document document) {
  final out = <Element>[];
  final root = document.documentElement;
  if (root == null) return out;
  final stack = <Element>[root];
  while (stack.isNotEmpty) {
    final e = stack.removeLast();
    out.add(e);
    if (e.localName == 'template') continue;
    final children = e.nodes.whereType<Element>().toList();
    for (var i = children.length - 1; i >= 0; i--) {
      stack.add(children[i]);
    }
  }
  return out;
}

bool _hasClass(Element e, String c) =>
    (e.attributes['class'] ?? '').split(' ').contains(c);

List<Element> _byClass(_Section s, String c) =>
    _elements(s.document).where((e) => _hasClass(e, c)).toList();

List<Element> _byTag(_Section s, String tag) =>
    _elements(s.document).where((e) => e.localName == tag).toList();

_Section _only(List<_Section> sections) => sections.single;

bool _fromBook(_Section s, Element e, CssProperty p) {
  final o = s.styles.originOf(e, p);
  return o == CssOrigin.author || o == CssOrigin.styleAttribute;
}

/// Afirmações estruturais de §14.1, em toda seção.
void _structural(_Section s) {
  final elements = _elements(s.document);
  expect(s.styles.length, elements.length, reason: s.path);
  for (final e in elements) {
    final style = s.styles.styleOf(e)!;
    final where = '${s.path} <${e.localName}>';
    switch (e.localName) {
      case 'head' || 'script' || 'style' || 'title':
        expect(style.display, CssDisplay.none, reason: where);
      case 'em' || 'i':
        if (!_fromBook(s, e, CssProperty.fontStyle)) {
          expect(style.fontStyle, CssFontStyle.italic, reason: where);
        }
      case 'b' || 'strong':
        if (!_fromBook(s, e, CssProperty.fontWeight)) {
          expect(style.fontWeight, CssFontWeight.bold, reason: where);
        }
    }
    for (final v in [
      style.margin.top,
      style.margin.right,
      style.margin.bottom,
      style.margin.left,
      style.padding.top,
      style.padding.right,
      style.padding.bottom,
      style.padding.left,
    ]) {
      expect(v, inInclusiveRange(0, 8), reason: where);
    }
    expect(style.textIndent, inInclusiveRange(-4, 8), reason: where);
    for (final l in [style.width, style.height]) {
      if (l != null) expect(l.value, inInclusiveRange(0, 100), reason: where);
    }
    expect(style.weight, inInclusiveRange(1, 1000), reason: where);
  }
}

ComputedStyle _style(_Section s, Element e) => s.styles.styleOf(e)!;

void _layout(DiagnosticSink sink, String property) {
  final d = sink.diagnostics.singleWhere(
    (d) => identical(d.code, EpubDiagnosticCode.unsupportedLayout),
  );
  expect(d.details['property'], property);
}

/// Afirmações específicas de §14.1, por caso.
final Map<String, void Function(List<_Section>, DiagnosticSink)> _specific = {
  'conteudo/display-none-com-texto': (sections, _) {
    final s = _only(sections);
    final hidden = [
      ..._byClass(s, 'oculto'),
      ..._byTag(s, 'p').where(
        (p) =>
            p.attributes.containsKey('style') ||
            p.attributes.containsKey('hidden'),
      ),
    ];
    expect(hidden, hasLength(4));
    for (final e in hidden) {
      expect(_style(s, e).display, CssDisplay.none, reason: e.outerHtml);
    }
    final visible = _byTag(s, 'p').where((p) => p.text.startsWith('Visível'));
    expect(visible, hasLength(2));
    for (final e in visible) {
      expect(_style(s, e).display, CssDisplay.block);
    }
  },
  'conteudo/text-transform-uppercase': (sections, _) {
    final s = _only(sections);
    final up = _byClass(s, 'up');
    expect(up.map((e) => e.localName), ['h1', 'p', 'span']);
    for (final e in up) {
      expect(_style(s, e).textTransform, CssTextTransform.uppercase);
    }
    expect(
      _style(s, _byClass(s, 'cap').single).textTransform,
      CssTextTransform.capitalize,
    );
    expect(
      _style(s, _byClass(s, 'low').single).textTransform,
      CssTextTransform.lowercase,
    );
  },
  'conteudo/lista-5-niveis': (sections, _) {
    final s = _only(sections);
    final expected = [
      CssListStyleType.disc,
      CssListStyleType.circle,
      CssListStyleType.square,
      CssListStyleType.disc,
      CssListStyleType.none,
    ];
    for (var level = 1; level <= 5; level++) {
      final ul = _byClass(s, 'l$level').single;
      for (final li in ul.nodes.whereType<Element>()) {
        expect(
          _style(s, li).listStyleType,
          expected[level - 1],
          reason: 'l$level',
        );
      }
    }
  },
  'regressoes/text-align-inline-span': (sections, _) {
    final s = _only(sections);
    final spans = _byTag(s, 'span');
    expect(spans, hasLength(2));
    for (final e in spans) {
      expect(
        (_style(s, e).display, _style(s, e).textAlign),
        (CssDisplay.inline, CssTextAlign.center),
      );
    }
  },
  'faixa-b/float-com-contorno': (_, sink) => _layout(sink, 'float'),
  'faixa-b/columns': (_, sink) => _layout(sink, 'columns'),
  'faixa-b/writing-mode-vertical': (_, sink) => _layout(sink, 'writing-mode'),
  'reais/moby-dick-en': (sections, _) {
    final s = sections.singleWhere(
      (x) => x.path.endsWith('epub/text/chapter-1.xhtml'),
    );
    final h2 = _byTag(s, 'h2').single;
    final h = _style(s, h2);
    expect(
      (h.fontVariant, h.textAlign, h.breakAfter),
      (CssFontVariant.smallCaps, CssTextAlign.center, CssBreak.avoid),
    );
    final hgroup = _byTag(s, 'hgroup').single;
    final title = hgroup.nodes.whereType<Element>().last;
    expect(_style(s, title).textIndent, 0, reason: 'hgroup > p');
    final after = hgroup.parent!.nodes.whereType<Element>().toList();
    final i = after.indexOf(hgroup);
    expect(_style(s, after[i + 1]).textIndent, 0, reason: 'hgroup + p');
    expect(_style(s, after[i + 2]).textIndent, 1);
  },
  'conteudo/css-import-cadeia': (sections, _) {
    final s = _only(sections);
    expect(
      _style(
        s,
        _byClass(s, 'do-listas').single.nodes.whereType<Element>().single,
      ).listStyleType,
      CssListStyleType.square,
    );
    expect(_style(s, _byClass(s, 'do-tipo').single).weight, 700);
    expect(
      _style(s, _byClass(s, 'sobrescrita').single).fontStyle,
      CssFontStyle.normal,
    );
    expect(_style(s, _byClass(s, 'da-repetida').single).underline, isTrue);
    expect(
      _style(s, _byClass(s, 'do-main').single).textTransform,
      CssTextTransform.uppercase,
    );
    expect(s.sheets.cacheKey.map((r) => r.path), [
      'OEBPS/Styles/extra/listas.css',
      'OEBPS/Styles/base/tipo grafia.css',
      'OEBPS/Styles/repetida.css',
      'OEBPS/Styles/repetida.css',
      'OEBPS/Styles/main.css',
    ]);
  },
  'conteudo/css-media-misto': (sections, _) {
    final s = _only(sections);
    ComputedStyle of(String c) => _style(s, _byClass(s, c).single);
    expect(of('so-impressao').display, CssDisplay.block);
    expect(of('da-tela').weight, 700);
    expect(of('largo').weight, 400);
    expect(of('tela-media').fontStyle, CssFontStyle.italic);
    expect(of('impressa').display, CssDisplay.block);
    expect(of('retrato').display, CssDisplay.block);
    expect(of('do-x').display, CssDisplay.block);
    expect(of('nao-impressa').textTransform, CssTextTransform.uppercase);
  },
  'regressoes/css-latin1': (sections, sink) {
    final s = _only(sections);
    // Só a folha sem @charset cai no latin1, uma vez (o cache não reemite).
    final fallbacks = [
      for (final d in sink.diagnostics)
        if (d.code == EpubDiagnosticCode.encodingFallback) d,
    ];
    expect(fallbacks, hasLength(1));
    expect(fallbacks.single.href, endsWith('sem-charset.css'));
    expect(fallbacks.single.details['count'], 1);
    expect(
      _style(s, _byClass(s, 'citação').single).fontStyle,
      CssFontStyle.italic,
    );
    expect(_style(s, _byClass(s, 'lição').single).weight, 700);
  },
};

void main() {
  final root = Directory('test/corpus');
  final cases =
      root
          .listSync()
          .whereType<Directory>()
          .expand((group) => group.listSync().whereType<Directory>())
          .map(
            (d) => d.path.substring(root.path.length + 1).replaceAll(r'\', '/'),
          )
          .toList()
        ..sort();

  test('corpus tem os 68 casos e as asserções específicas existem', () {
    expect(cases, hasLength(68));
    expect(cases, containsAll(_specific.keys));
  });

  for (final name in cases) {
    final dir = '${root.path}/$name';
    final group = name.split('/').first;
    if (File('$dir/exception.expected').existsSync()) continue;
    final expectedAll = _lines(File('$dir/diagnostics.expected')).toSet();
    final expected = expectedAll.where(cssCodes.contains).toSet();
    final hasWarning = expected.any(cssWarnings.contains);
    final strict = !relaxedGroups.contains(group) && !hasWarning;

    test('$name (strict: $strict)', () async {
      final (sections, sink) = await _run(dir, strict: strict);
      final emitted = sink.diagnostics.map((d) => d.code.name).toSet();
      expect(emitted.where(cssCodes.contains).toSet(), expected);
      for (final code in emitted.where(sharedCodes.contains)) {
        expect(expectedAll, contains(code));
      }
      sections.forEach(_structural);
      _specific[name]?.call(sections, sink);
    }, timeout: const Timeout(Duration(minutes: 2)));

    if (hasWarning) {
      test('$name (segunda passada, strict: true)', () async {
        await expectLater(
          _run(dir, strict: true),
          throwsA(
            isA<EpubSectionParseException>().having(
              (e) => cssWarnings.any(
                (c) => expected.contains(c) && e.message.startsWith('$c: '),
              ),
              'mensagem com o código',
              isTrue,
            ),
          ),
        );
      });
    }
  }
}
