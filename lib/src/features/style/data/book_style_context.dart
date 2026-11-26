import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../../../core/diagnostics/diagnostic.dart';
import '../../../core/diagnostics/diagnostic_codes.dart';
import '../../../core/diagnostics/diagnostic_sink.dart';
import '../../../core/diagnostics/limited_diagnostic_sink.dart';
import '../../document/domain/document_head.dart';
import '../domain/style_environment.dart';
import '../domain/stylesheet.dart';
import 'css_decode.dart';
import 'media_query_parser.dart';
import 'stylesheet_builder.dart';

/// Lê os bytes do recurso em [path] (caminho no zip); `null` se ausente.
typedef ResourceResolver = Uint8List? Function(String path);

/// Profundidade máxima de `@import` (a folha raiz tem profundidade 0).
const int kMaxImportDepth = 8;

/// Máximo de `@import` seguidos a partir de uma folha raiz.
const int kMaxImportsPerRoot = 64;

/// Uma folha na ordem da cascata, com as media queries que precisam valer
/// para ela se aplicar (as do `<link>`/`<style>` e as dos `@import`, de
/// fora para dentro). Avaliadas no casamento, contra o `StyleEnvironment`.
@immutable
final class SheetEntry {
  /// Cria a entrada.
  const SheetEntry(this.sheet, this.conditions);

  /// A folha.
  final StyleSheet sheet;

  /// Condições `media`; todas precisam valer. Vazia = sempre.
  final List<MediaQueryList> conditions;
}

/// Contexto de estilo de um livro (spec §8.1, §8.2, §8.8): guarda as folhas
/// já lidas, a tabela de `@font-face` e o prefixo dos nomes internos de
/// fonte. Um por livro, no isolate que trabalha o livro; não é thread-safe.
///
/// As folhas ligadas ficam em cache pelo caminho (a ausência também); as de
/// `<style>` pelo diretório do documento e pelo texto exato, porque `url()`
/// é relativo ao documento. Os diagnósticos de cada folha saem uma vez por
/// livro, na primeira leitura, e todos passam por um limite de
/// [kDiagnosticReportLimit] por código no livro inteiro, com um resumo do
/// excedente ao fim de cada [sheetsFor].
final class BookStyleContext {
  /// Cria o contexto do livro [bookKey] (ex.: o identificador único), que
  /// lê os recursos por [resolve].
  BookStyleContext({required this._resolve, required String bookKey})
    : fontPrefix = 'gf${_fnv1a32Hex(bookKey)}-';

  final ResourceResolver _resolve;

  /// Prefixo dos nomes internos de fonte do livro: `gf` + FNV-1a de 32 bits
  /// da chave do livro (UTF-8) em 8 dígitos hexadecimais minúsculos + `-`.
  final String fontPrefix;

  /// Folhas ligadas ou importadas por caminho; `null` = ausente.
  final Map<String, StyleSheet?> _linked = {};

  /// Folhas de `<style>` por diretório do documento e texto.
  final Map<(String, String), StyleSheet> _inline = {};

  /// Expansão (com `@import`) de cada folha raiz já vista.
  final Map<Object, List<SheetEntry>> _expanded = {};

  final List<FontFaceRule> _fontFaces = [];

  /// Folhas cujas `@font-face` já entraram em [_fontFaces].
  final Set<StyleSheet> _fontSheets = Set.identity();
  late final List<FontFaceRule> _fontFacesView = UnmodifiableListView(
    _fontFaces,
  );

  final _BookLimiter _limiter = _BookLimiter();

  /// Nome interno da família [family] neste livro ([internalFontFamily]).
  String internalFamilyName(String family) =>
      internalFontFamily(fontPrefix, family);

  /// `@font-face` de todas as folhas usadas até agora, na ordem da cascata
  /// em que cada folha apareceu pela primeira vez (importadas antes de quem
  /// importa); visão viva, não modificável.
  List<FontFaceRule> get fontFaces => _fontFacesView;

  /// Quantas folhas estão no cache (ligadas, inclusive ausentes, e de
  /// `<style>`).
  @visibleForTesting
  int get cachedSheetCount => _linked.length + _inline.length;

  /// Folhas de [head] na ordem da cascata, para o documento em
  /// [documentPath]: cada `@import` expandido antes das regras de quem
  /// importa. Os diagnósticos novos vão para [sink].
  List<SheetEntry> sheetsFor(
    DocumentHead head, {
    required String documentPath,
    required DiagnosticSink sink,
  }) {
    _limiter.target = sink;
    try {
      final out = <SheetEntry>[];
      for (final ref in head.styleSheets) {
        final media = ref.media;
        final outer = media == null || media.trim().isEmpty
            ? const <MediaQueryList>[]
            : [parseMediaQueryText(media)];
        final List<SheetEntry> expanded;
        switch (ref) {
          case LinkedStyleSheet(:final path):
            expanded = _expanded[path] ??= _expand(path, _sheetAt(path));
          case InlineStyleSheet(:final css):
            final key = (_directoryOf(documentPath), css);
            expanded = _expanded[key] ??= _expand(
              documentPath,
              _inline[key] ??= _parse(css, documentPath),
            );
        }
        for (final entry in expanded) {
          out.add(
            outer.isEmpty
                ? entry
                : SheetEntry(entry.sheet, [...outer, ...entry.conditions]),
          );
        }
      }
      return out;
    } finally {
      _limiter.target = const NullDiagnosticSink();
    }
  }

  /// Emite em [sink], para cada código que passou do limite, o total exato
  /// de ocorrências omitidas no livro desde o último [flush]. Opcional: o
  /// orquestrador chama no fim do livro. Sem nada omitido, não emite nada.
  void flush({required DiagnosticSink sink}) => _limiter.flush(sink);

  /// Folha em [path], lida na primeira vez; `null` se ausente.
  StyleSheet? _sheetAt(String path) {
    if (_linked.containsKey(path)) return _linked[path];
    final bytes = _resolve(path);
    if (bytes == null) {
      _limiter.report(
        Diagnostic(
          severity: DiagnosticSeverity.warning,
          code: DiagnosticCodes.cssMissingStyleSheet,
          message: 'folha de estilo ausente: $path',
          location: path,
        ),
      );
      return _linked[path] = null;
    }
    return _linked[path] = _parse(decodeCss(bytes), path);
  }

  StyleSheet _parse(String css, String path) {
    final sheet = buildStyleSheet(
      css,
      path: path,
      fontPrefix: fontPrefix,
      sink: _limiter,
    );
    return sheet;
  }

  /// Expande os `@import` da folha raiz [root] (em [rootPath]). A recursão
  /// é limitada a [kMaxImportDepth] níveis.
  List<SheetEntry> _expand(String rootPath, StyleSheet? root) {
    final out = <SheetEntry>[];
    if (root == null) return List.unmodifiable(out);
    final stack = <String>[rootPath];
    var imports = 0;

    void walk(StyleSheet sheet, List<MediaQueryList> conds, int depth) {
      for (final ref in sheet.imports) {
        final importer = stack.last;
        if (stack.contains(ref.path)) {
          _importDiagnostic(
            DiagnosticCodes.cssImportCycle,
            importer,
            'ciclo de @import em ${ref.path}; pulado',
          );
          continue;
        }
        if (depth + 1 > kMaxImportDepth) {
          _importDiagnostic(
            DiagnosticCodes.cssImportLimit,
            importer,
            '@import de ${ref.path} além de $kMaxImportDepth níveis; pulado',
          );
          continue;
        }
        if (imports >= kMaxImportsPerRoot) {
          _importDiagnostic(
            DiagnosticCodes.cssImportLimit,
            importer,
            '@import de ${ref.path} além de $kMaxImportsPerRoot por folha '
            'raiz; pulado',
          );
          continue;
        }
        imports++;
        final imported = _sheetAt(ref.path);
        if (imported == null) continue;
        final media = ref.media;
        stack.add(ref.path);
        walk(
          imported,
          media == null ? conds : List.unmodifiable([...conds, media]),
          depth + 1,
        );
        stack.removeLast();
      }
      out.add(SheetEntry(sheet, conds));
      if (_fontSheets.add(sheet)) _fontFaces.addAll(sheet.fontFaces);
    }

    walk(root, const [], 0);
    return List.unmodifiable(out);
  }

  void _importDiagnostic(String code, String importer, String message) =>
      _limiter.report(
        Diagnostic(
          severity: DiagnosticSeverity.warning,
          code: code,
          message: message,
          location: importer,
        ),
      );

  static String _directoryOf(String path) {
    final slash = path.lastIndexOf('/');
    return slash < 0 ? '' : path.substring(0, slash);
  }
}

/// FNV-1a de 32 bits dos bytes UTF-8 de [text], em 8 dígitos hex.
String _fnv1a32Hex(String text) {
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(text)) {
    hash = ((hash ^ byte) * 0x01000193) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

/// Limite de [kDiagnosticReportLimit] diagnósticos por código no livro
/// inteiro, repassando ao sink da chamada em curso ([target]). Na primeira
/// ocorrência além do limite sai um único aviso por código no livro; depois
/// o código fica em silêncio. [flush] emite o total omitido.
final class _BookLimiter implements DiagnosticSink {
  DiagnosticSink target = const NullDiagnosticSink();

  /// Ocorrências por código no livro inteiro.
  final Map<String, int> _counts = {};

  /// Omitidos ainda não totalizados por [flush], com o primeiro omitido.
  final Map<String, (int, Diagnostic)> _omitted = {};

  @override
  void report(Diagnostic diagnostic) {
    final code = diagnostic.code;
    final count = (_counts[code] ?? 0) + 1;
    _counts[code] = count;
    if (count <= kDiagnosticReportLimit) {
      target.report(diagnostic);
      return;
    }
    if (count == kDiagnosticReportLimit + 1) {
      target.report(
        Diagnostic(
          severity: diagnostic.severity,
          code: code,
          message:
              'limite de $kDiagnosticReportLimit ocorrências de $code '
              'atingido; demais diagnósticos deste código serão omitidos '
              'neste livro',
          location: diagnostic.location,
        ),
      );
    }
    final previous = _omitted[code];
    _omitted[code] = previous == null
        ? (1, diagnostic)
        : (previous.$1 + 1, previous.$2);
  }

  void flush(DiagnosticSink sink) {
    for (final MapEntry(key: code, value: (n, first)) in _omitted.entries) {
      sink.report(
        Diagnostic(
          severity: first.severity,
          code: code,
          message:
              '$n ocorrência(s) de $code omitida(s) neste livro '
              '(total ${_counts[code]})',
          location: first.location,
        ),
      );
    }
    _omitted.clear();
  }
}
