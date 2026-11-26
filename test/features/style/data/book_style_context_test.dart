import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/core/diagnostics/diagnostic.dart';
import 'package:galley/src/core/diagnostics/diagnostic_codes.dart';
import 'package:galley/src/core/diagnostics/diagnostic_sink.dart';
import 'package:galley/src/features/document/domain/document_head.dart';
import 'package:galley/src/features/style/data/book_style_context.dart';
import 'package:galley/src/features/style/domain/selector.dart';
import 'package:galley/src/features/style/domain/style_environment.dart';
import 'package:galley/src/features/style/domain/stylesheet.dart';

const env = StyleEnvironment(pageWidth: 600, pageHeight: 800);

/// Resolvedor de mapa que conta as chamadas por caminho.
final class MapResolver {
  MapResolver(Map<String, String> files)
    : bytes = {
        for (final e in files.entries)
          e.key: Uint8List.fromList(utf8.encode(e.value)),
      };

  final Map<String, Uint8List> bytes;
  final Map<String, int> calls = {};

  Uint8List? call(String path) {
    calls[path] = (calls[path] ?? 0) + 1;
    return bytes[path];
  }
}

DocumentHead linkHead(String path, {String? media}) => DocumentHead(
  styleSheets: [LinkedStyleSheet(path: path, media: media)],
);

late CollectingDiagnosticSink sink;

List<Diagnostic> withCode(String code) =>
    sink.diagnostics.where((d) => d.code == code).toList();

/// Nome do tipo do seletor mais à direita da primeira regra.
String? firstType(StyleSheet sheet) {
  final compound = sheet.rules.first.selector.compounds.last;
  for (final s in compound.simples) {
    if (s is TypeSelector) return s.localName;
  }
  return null;
}

bool applies(SheetEntry e) => e.conditions.every((c) => c.evaluate(env));

void main() {
  setUp(() => sink = CollectingDiagnosticSink());

  test('folha ligada é lida uma vez por livro; diagnósticos só na 1ª', () {
    final r = MapResolver({'OEBPS/css/s.css': 'p { colr: red }'});
    final ctx = BookStyleContext(resolve: r.call, bookKey: 'livro');
    final head = linkHead('OEBPS/css/s.css');
    final a = ctx.sheetsFor(head, documentPath: 'OEBPS/a.xhtml', sink: sink);
    final first = sink.diagnostics.length;
    expect(first, greaterThan(0));
    final sink2 = CollectingDiagnosticSink();
    final b = ctx.sheetsFor(head, documentPath: 'OEBPS/b.xhtml', sink: sink2);
    expect(r.calls['OEBPS/css/s.css'], 1);
    expect(sink2.diagnostics, isEmpty);
    expect(identical(a.single.sheet, b.single.sheet), isTrue);
    expect(ctx.cachedSheetCount, 1);
  });

  test('ciclo de @import: 1 css.importCycle, regras de b antes das de a', () {
    final r = MapResolver({
      'css/a.css': '@import "b.css"; a {}',
      'css/b.css': '@import url(a.css); b {}',
    });
    final ctx = BookStyleContext(resolve: r.call, bookKey: 'k');
    final entries = ctx.sheetsFor(
      linkHead('css/a.css'),
      documentPath: 'd.xhtml',
      sink: sink,
    );
    expect(withCode(DiagnosticCodes.cssImportCycle), hasLength(1));
    expect(
      withCode(DiagnosticCodes.cssImportCycle).single.severity,
      DiagnosticSeverity.warning,
    );
    expect(entries.map((e) => firstType(e.sheet)), ['b', 'a']);
    // Segundo documento: nada de novo.
    final sink2 = CollectingDiagnosticSink();
    ctx.sheetsFor(linkHead('css/a.css'), documentPath: 'e.xhtml', sink: sink2);
    expect(sink2.diagnostics, isEmpty);
  });

  test('profundidade: a0 → … → a10 lê a0–a8; a9 dá css.importLimit', () {
    final files = <String, String>{
      for (var i = 0; i <= 10; i++)
        'a$i.css': '${i < 10 ? '@import "a${i + 1}.css"; ' : ''}a$i {}',
    };
    final r = MapResolver(files);
    final ctx = BookStyleContext(resolve: r.call, bookKey: 'k');
    final entries = ctx.sheetsFor(
      linkHead('a0.css'),
      documentPath: 'd.xhtml',
      sink: sink,
    );
    expect(entries.map((e) => firstType(e.sheet)), [
      for (var i = 8; i >= 0; i--) 'a$i',
    ]);
    expect(withCode(DiagnosticCodes.cssImportLimit), hasLength(1));
    expect(r.calls.containsKey('a9.css'), isFalse);
  });

  test('mais de 64 importações por folha raiz dá css.importLimit', () {
    final files = <String, String>{
      'root.css': [for (var i = 0; i < 70; i++) '@import "i$i.css";'].join(),
      for (var i = 0; i < 70; i++) 'i$i.css': 'x {}',
    };
    final ctx = BookStyleContext(
      resolve: MapResolver(files).call,
      bookKey: 'k',
    );
    final entries = ctx.sheetsFor(
      linkHead('root.css'),
      documentPath: 'd.xhtml',
      sink: sink,
    );
    expect(entries, hasLength(65));
    expect(withCode(DiagnosticCodes.cssImportLimit), isNotEmpty);
  });

  test('@import com print e <link media=print> têm condição falsa', () {
    final r = MapResolver({
      'a.css': '@import url(x.css) print; a {}',
      'x.css': 'x {}',
      'p.css': 'p {}',
    });
    final ctx = BookStyleContext(resolve: r.call, bookKey: 'k');
    final entries = ctx.sheetsFor(
      DocumentHead(
        styleSheets: [
          const LinkedStyleSheet(path: 'a.css'),
          const LinkedStyleSheet(path: 'p.css', media: 'print'),
          const InlineStyleSheet(css: 's {}', media: 'screen'),
        ],
      ),
      documentPath: 'd.xhtml',
      sink: sink,
    );
    expect(entries.map((e) => firstType(e.sheet)), ['x', 'a', 'p', 's']);
    expect(entries.map(applies), [false, true, false, true]);
  });

  test('@import com media sob <link media> junta as duas condições', () {
    final r = MapResolver({
      'a.css': '@import url(x.css) (min-width: 100px);',
      'x.css': 'x {}',
    });
    final ctx = BookStyleContext(resolve: r.call, bookKey: 'k');
    final entries = ctx.sheetsFor(
      linkHead('a.css', media: 'screen'),
      documentPath: 'd.xhtml',
      sink: sink,
    );
    expect(entries.first.conditions, hasLength(2));
    expect(entries.last.conditions, hasLength(1));
  });

  test('folha ausente: css.missingStyleSheet uma vez para dois documentos', () {
    final r = MapResolver({});
    final ctx = BookStyleContext(resolve: r.call, bookKey: 'k');
    final head = linkHead('OEBPS/nada.css');
    expect(
      ctx.sheetsFor(head, documentPath: 'OEBPS/a.xhtml', sink: sink),
      isEmpty,
    );
    expect(
      ctx.sheetsFor(head, documentPath: 'OEBPS/b.xhtml', sink: sink),
      isEmpty,
    );
    final missing = withCode(DiagnosticCodes.cssMissingStyleSheet);
    expect(missing, hasLength(1));
    expect(missing.single.severity, DiagnosticSeverity.warning);
    expect(r.calls['OEBPS/nada.css'], 1);
  });

  test('<style> em cache pelo diretório do documento e pelo texto', () {
    final ctx = BookStyleContext(resolve: MapResolver({}).call, bookKey: 'k');
    const head = DocumentHead(styleSheets: [InlineStyleSheet(css: 'p {}')]);
    ctx.sheetsFor(head, documentPath: 'OEBPS/a.xhtml', sink: sink);
    ctx.sheetsFor(head, documentPath: 'OEBPS/b.xhtml', sink: sink);
    expect(ctx.cachedSheetCount, 1);
    ctx.sheetsFor(head, documentPath: 'OEBPS/x/c.xhtml', sink: sink);
    expect(ctx.cachedSheetCount, 2);
  });

  test('@import do <style> é relativo ao documento', () {
    final r = MapResolver({'OEBPS/css/i.css': 'i {}'});
    final ctx = BookStyleContext(resolve: r.call, bookKey: 'k');
    final entries = ctx.sheetsFor(
      const DocumentHead(
        styleSheets: [InlineStyleSheet(css: '@import "css/i.css"; s {}')],
      ),
      documentPath: 'OEBPS/a.xhtml',
      sink: sink,
    );
    expect(entries.map((e) => firstType(e.sheet)), ['i', 's']);
  });

  test('prefixo e nomes internos de fonte por livro', () {
    final a = BookStyleContext(resolve: MapResolver({}).call, bookKey: 'a');
    final b = BookStyleContext(resolve: MapResolver({}).call, bookKey: 'b');
    // FNV-1a 32 de "a" = 0xe40c292c.
    expect(a.fontPrefix, 'gfe40c292c-');
    expect(RegExp(r'^gf[0-9a-f]{8}-$').hasMatch(b.fontPrefix), isTrue);
    expect(a.internalFamilyName('Body'), isNot(b.internalFamilyName('Body')));
    expect(a.internalFamilyName('Body'), a.internalFamilyName('body'));
    expect(
      a.internalFamilyName('Body'),
      internalFontFamily(a.fontPrefix, 'Body'),
    );
  });

  test('@font-face do livro com o nome interno, também das importadas', () {
    final r = MapResolver({
      'css/a.css':
          '@import "f.css"; @font-face { font-family: Body; src: url(b.otf) }',
      'css/f.css': '@font-face { font-family: "Title"; src: url(t.otf) }',
    });
    final ctx = BookStyleContext(resolve: r.call, bookKey: 'k');
    ctx.sheetsFor(linkHead('css/a.css'), documentPath: 'd.xhtml', sink: sink);
    ctx.sheetsFor(linkHead('css/a.css'), documentPath: 'e.xhtml', sink: sink);
    expect(ctx.fontFaces.map((f) => f.family), ['Title', 'Body']);
    expect(ctx.fontFaces.map((f) => f.internalFamily), [
      ctx.internalFamilyName('Title'),
      ctx.internalFamilyName('Body'),
    ]);
  });

  test('folha UTF-16 com BOM é lida', () {
    final units = '@charset "utf-16"; p { color: red }'.codeUnits;
    final bytes = Uint8List(2 + units.length * 2)
      ..[0] = 0xFF
      ..[1] = 0xFE;
    for (var i = 0; i < units.length; i++) {
      bytes[2 + i * 2] = units[i] & 0xFF;
      bytes[3 + i * 2] = units[i] >> 8;
    }
    final ctx = BookStyleContext(
      resolve: (p) => p == 'u.css' ? bytes : null,
      bookKey: 'k',
    );
    final entries = ctx.sheetsFor(
      linkHead('u.css'),
      documentPath: 'd.xhtml',
      sink: sink,
    );
    expect(firstType(entries.single.sheet), 'p');
    expect(entries.single.sheet.rules.single.declarations, isNotEmpty);
  });

  test('limite por código no livro: N chamadas dão 20 + 1 aviso', () {
    final ctx = BookStyleContext(resolve: MapResolver({}).call, bookKey: 'k');
    // Cada capítulo tem um <style> próprio com 3 propriedades fora do escopo.
    for (var i = 0; i < 30; i++) {
      ctx.sheetsFor(
        DocumentHead(
          styleSheets: [InlineStyleSheet(css: 'p { a$i: 1; b$i: 1; c$i: 1 }')],
        ),
        documentPath: 'c$i.xhtml',
        sink: sink,
      );
    }
    final unsupported = withCode(DiagnosticCodes.cssUnsupportedProperty);
    expect(unsupported, hasLength(21));
    expect(unsupported.last.message, contains('serão omitidos neste livro'));
    expect(
      unsupported.where((d) => d.message.contains('omitid')),
      hasLength(1),
    );
  });

  test('flush emite o total exato omitido por código', () {
    final ctx = BookStyleContext(resolve: MapResolver({}).call, bookKey: 'k');
    for (var i = 0; i < 10; i++) {
      ctx.sheetsFor(
        DocumentHead(
          styleSheets: [InlineStyleSheet(css: 'p { a$i: 1; b$i: 1; c$i: 1 }')],
        ),
        documentPath: 'c$i.xhtml',
        sink: sink,
      );
    }
    final end = CollectingDiagnosticSink();
    ctx.flush(sink: end);
    // 30 ocorrências, 20 repassadas: 10 omitidas.
    expect(end.diagnostics, hasLength(1));
    final summary = end.diagnostics.single;
    expect(summary.code, DiagnosticCodes.cssUnsupportedProperty);
    expect(summary.message, contains('10 ocorrência(s)'));
    expect(summary.message, contains('total 30'));
    // Sem nada novo, flush não repete.
    final again = CollectingDiagnosticSink();
    ctx.flush(sink: again);
    expect(again.diagnostics, isEmpty);
  });

  test('flush sem excedente não emite nada', () {
    final ctx = BookStyleContext(resolve: MapResolver({}).call, bookKey: 'k');
    ctx.sheetsFor(
      const DocumentHead(styleSheets: [InlineStyleSheet(css: 'p { zz: 1 }')]),
      documentPath: 'c.xhtml',
      sink: sink,
    );
    final end = CollectingDiagnosticSink();
    ctx.flush(sink: end);
    expect(end.diagnostics, isEmpty);
  });
}
