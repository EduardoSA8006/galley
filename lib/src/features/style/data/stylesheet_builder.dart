import 'dart:typed_data';

import '../../../core/diagnostics/diagnostic.dart';
import '../../../core/diagnostics/diagnostic_codes.dart';
import '../../../core/diagnostics/diagnostic_sink.dart';
import '../../container/data/path/epub_path.dart';
import '../domain/css_value.dart';
import '../domain/properties.dart';
import '../domain/selector.dart';
import '../domain/style_environment.dart';
import '../domain/stylesheet.dart';
import 'css_blocks.dart';
import 'css_syntax.dart';
import 'css_tokenizer.dart';
import 'css_value_reader.dart';
import 'media_query_parser.dart';
import 'property_parser.dart';
import 'selector_parser.dart';

/// Monta a [StyleSheet] da folha [css], que está em [path] no zip.
///
/// Os seletores, as propriedades e as at-rules são interpretados aqui
/// (spec §8.9): `@media` vira condição das regras (avaliada no casamento);
/// `@supports` é avaliado já; `@import`/`@namespace` só valem antes da
/// primeira outra regra; `@page` sem seletor dá as margens; `@font-face`
/// recebe o nome interno [internalFontFamily] com [fontPrefix]; as demais
/// at-rules são ignoradas. Diagnósticos vão direto para [sink] (o limite é
/// do chamador), com `location` `'<path>:<linha>'`.
StyleSheet buildStyleSheet(
  String css, {
  required String path,
  required String fontPrefix,
  required DiagnosticSink sink,
}) {
  final parsed = parseCss(css, location: path, sink: sink);
  return _Builder(parsed, path, fontPrefix, sink).build();
}

final class _Builder {
  _Builder(this._parsed, this._path, this._fontPrefix, this._sink);

  final ParsedCss _parsed;
  final String _path;
  final String _fontPrefix;
  final DiagnosticSink _sink;

  final List<StyleRule> _rules = [];
  final List<FontFaceRule> _fontFaces = [];
  final List<(PageMargins, List<MediaQueryList>)> _pages = [];
  final List<ImportRef> _imports = [];

  String? _defaultNamespace;
  final Map<String, String> _prefixes = {};
  NamespaceMap _namespaces = NamespaceMap.empty;

  /// Se já passou alguma regra que não seja `@charset`/`@import`/
  /// `@namespace` no topo.
  bool _seenOther = false;
  int _order = 0;

  StyleSheet build() {
    _walk(_parsed.rules, const [], top: true);
    return StyleSheet(
      rules: List.unmodifiable(_rules),
      fontFaces: List.unmodifiable(_fontFaces),
      pages: List.unmodifiable(_pages),
      imports: List.unmodifiable(_imports),
    );
  }

  void _report(
    String code,
    DiagnosticSeverity severity,
    int offset,
    String message,
  ) {
    _sink.report(
      Diagnostic(
        severity: severity,
        code: code,
        message: message,
        location: '$_path:${_parsed.lineOf(offset)}',
      ),
    );
  }

  void _parseError(int offset, String message) => _report(
    DiagnosticCodes.cssParseError,
    DiagnosticSeverity.warning,
    offset,
    message,
  );

  /// Percorre [rules] com os `@media` [conditions] em volta. A recursão é
  /// limitada pelo aninhamento máximo do parser (32 níveis).
  void _walk(
    List<CssRule> rules,
    List<MediaQueryList> conditions, {
    required bool top,
  }) {
    for (final rule in rules) {
      switch (rule) {
        case QualifiedRule():
          if (top) _seenOther = true;
          _styleRule(rule, conditions);
        case AtRule(name: 'charset'):
          if (!top) _parseError(rule.offset, '@charset fora do topo');
        case AtRule(name: 'import' || 'namespace'):
          if (!top || _seenOther) {
            _parseError(
              rule.offset,
              '@${rule.name} depois de outras regras; ignorada',
            );
          } else if (rule.name == 'import') {
            _import(rule);
          } else {
            _namespace(rule);
          }
        case AtRule():
          if (top) _seenOther = true;
          _atRule(rule, conditions);
      }
    }
  }

  void _atRule(AtRule rule, List<MediaQueryList> conditions) {
    switch (rule.name) {
      case 'media':
        final inner = rule.rules;
        if (inner == null) {
          _parseError(rule.offset, '@media sem bloco');
          return;
        }
        _walk(inner, [
          ...conditions,
          parseMediaQueryList(rule.prelude),
        ], top: false);
      case 'supports':
        final inner = rule.rules;
        if (inner == null) {
          _parseError(rule.offset, '@supports sem bloco');
          return;
        }
        if (_SupportsParser(rule.prelude, _namespaces, _path).evaluate()) {
          _walk(inner, conditions, top: false);
        }
      case 'page':
        if (rule.prelude.isNotEmpty) {
          _report(
            DiagnosticCodes.cssUnsupportedAtRule,
            DiagnosticSeverity.info,
            rule.offset,
            '@page com seletor não suportada; ignorada',
          );
          return;
        }
        _page(rule, conditions);
      case 'font-face':
        _fontFace(rule);
      default:
        _report(
          DiagnosticCodes.cssUnsupportedAtRule,
          DiagnosticSeverity.info,
          rule.offset,
          '@${rule.name} não suportada; ignorada',
        );
    }
  }

  // ---------------------------------------------------------------------
  // Regras de estilo.

  void _styleRule(QualifiedRule rule, List<MediaQueryList> conditions) {
    final selectors = parseSelectorList(rule.prelude, _namespaces);
    if (selectors == null) {
      _report(
        DiagnosticCodes.cssUnsupportedSelector,
        DiagnosticSeverity.info,
        rule.offset,
        'seletor não suportado ou malformado; regra descartada',
      );
      return;
    }
    final declarations = _declarations(rule.declarations);
    final conds = conditions.isEmpty
        ? const <MediaQueryList>[]
        : List<MediaQueryList>.unmodifiable(conditions);
    for (final selector in selectors) {
      _rules.add(
        StyleRule(
          selector: selector,
          declarations: declarations,
          order: _order++,
          conditions: conds,
        ),
      );
    }
  }

  List<Declaration> _declarations(List<RawDeclaration> raw) {
    final out = <Declaration>[];
    for (final d in raw) {
      final result = parseProperty(d.name, d.value, sheetPath: _path);
      switch (result) {
        case ParsedLonghands(:final values):
          for (final (id, value) in values) {
            out.add(Declaration(id, value, important: d.important));
          }
        case UnsupportedProperty():
          _report(
            DiagnosticCodes.cssUnsupportedProperty,
            DiagnosticSeverity.info,
            d.offset,
            'propriedade não suportada: ${d.name}',
          );
        case InvalidValue():
          _invalidValue(d);
        case IgnoredProperty():
          break;
      }
    }
    return List.unmodifiable(out);
  }

  void _invalidValue(RawDeclaration d) => _report(
    DiagnosticCodes.cssInvalidValue,
    DiagnosticSeverity.info,
    d.offset,
    'valor inválido para ${d.name}: '
    '${_parsed.source.substring(d.valueStart, d.valueEnd)}',
  );

  // ---------------------------------------------------------------------
  // @import e @namespace.

  /// Texto de uma string, `url(...)` ou `url("...")` em [tokens][i].
  static String? _urlOrString(List<CssToken> tokens, int i, int to) {
    final t = tokens[i];
    switch (t.type) {
      case CssTokenType.string || CssTokenType.url:
        return t.value;
      case CssTokenType.function when asciiLower(t.value) == 'url':
        final inner = [
          for (var j = i + 1; j < to; j++)
            if (tokens[j].type != CssTokenType.whitespace) tokens[j],
        ];
        if (inner.length == 2 &&
            inner[0].type == CssTokenType.string &&
            inner[1].type == CssTokenType.rightParen) {
          return inner[0].value;
        }
        return null;
      default:
        return null;
    }
  }

  void _import(AtRule rule) {
    final p = rule.prelude;
    if (p.isEmpty) {
      _parseError(rule.offset, '@import sem endereço');
      return;
    }
    // Fim do primeiro componente.
    var end = 1;
    if (p[0].type == CssTokenType.function) {
      final match = matchCssBlocks(p);
      end = match[0] < p.length ? match[0] + 1 : p.length;
    }
    final href = _urlOrString(p, 0, end);
    if (href == null) {
      _parseError(rule.offset, '@import sem endereço válido');
      return;
    }
    final rest = p.sublist(end);
    final media = rest.any((t) => t.type != CssTokenType.whitespace)
        ? parseMediaQueryList(rest)
        : null;
    final trimmed = href.trim();
    if (trimmed.isEmpty ||
        trimmed.startsWith('#') ||
        trimmed.startsWith('//')) {
      return;
    }
    final resolved = resolveHref(_path, trimmed);
    // Folhas externas (com esquema) ou fora do zip são descartadas.
    if (resolved == null || resolved.path.isEmpty) return;
    _imports.add(ImportRef(resolved.path, media: media));
  }

  void _namespace(AtRule rule) {
    final p = [
      for (final t in rule.prelude)
        if (t.type != CssTokenType.whitespace) t,
    ];
    String? prefix;
    var i = 0;
    if (p.isNotEmpty && p[0].type == CssTokenType.ident) {
      prefix = p[0].value;
      i = 1;
    }
    final uri = i < p.length ? _urlOrString(p, i, p.length) : null;
    final consumed = i < p.length && p[i].type == CssTokenType.function
        ? p.length
        : i + 1;
    if (uri == null || consumed != p.length) {
      _parseError(rule.offset, '@namespace malformada; ignorada');
      return;
    }
    if (prefix == null) {
      _defaultNamespace = uri;
    } else {
      _prefixes[prefix] = uri;
    }
    _namespaces = NamespaceMap(
      defaultUri: _defaultNamespace,
      prefixes: Map.unmodifiable(_prefixes),
    );
  }

  // ---------------------------------------------------------------------
  // @page.

  void _page(AtRule rule, List<MediaQueryList> conditions) {
    final decls = rule.declarations;
    if (decls == null) return;
    CssLengthSpec? top, right, bottom, left;
    var any = false;
    for (final d in decls) {
      if (d.name != 'margin' && !d.name.startsWith('margin-')) continue;
      final result = parseProperty(d.name, d.value, sheetPath: _path);
      if (result is! ParsedLonghands) {
        if (result is InvalidValue) _invalidValue(d);
        continue;
      }
      for (final (id, value) in result.values) {
        final length = value is CssLengthSpec ? value : null;
        switch (id) {
          case PropertyId.marginTop:
            top = length;
          case PropertyId.marginRight:
            right = length;
          case PropertyId.marginBottom:
            bottom = length;
          case PropertyId.marginLeft:
            left = length;
          default:
            continue;
        }
        any = true;
      }
    }
    if (!any) return;
    _pages.add((
      PageMargins(top: top, right: right, bottom: bottom, left: left),
      conditions.isEmpty
          ? const <MediaQueryList>[]
          : List<MediaQueryList>.unmodifiable(conditions),
    ));
  }

  // ---------------------------------------------------------------------
  // @font-face.

  void _fontFace(AtRule rule) {
    String? family;
    List<FontSource>? sources;
    var weight = (400, 400);
    var style = CssKeywords.normal;
    String? stretch;
    List<(int, int)>? ranges;
    for (final d in rule.declarations ?? const <RawDeclaration>[]) {
      switch (d.name) {
        case 'font-family':
          family = _familyName(d.value) ?? family;
        case 'src':
          sources = _sources(d.value);
        case 'font-weight':
          weight = _weightRange(d.value) ?? weight;
        case 'font-style':
          style = _fontStyle(d.value) ?? style;
        case 'font-stretch':
          stretch = _stretch(d) ?? stretch;
        case 'unicode-range':
          ranges =
              _unicodeRanges(
                _parsed.source.substring(d.valueStart, d.valueEnd),
              ) ??
              ranges;
      }
    }
    if (family == null) {
      _fontFaceInvalid(rule, '@font-face sem font-family; descartada');
      return;
    }
    if (sources == null || sources.isEmpty) {
      _fontFaceInvalid(
        rule,
        '@font-face "$family" sem fonte utilizável; descartada',
      );
      return;
    }
    _fontFaces.add(
      FontFaceRule(
        family: family,
        internalFamily: internalFontFamily(_fontPrefix, family),
        sources: List.unmodifiable(sources),
        weightMin: weight.$1,
        weightMax: weight.$2,
        style: style,
        stretch: stretch,
        unicodeRanges: List.unmodifiable(ranges ?? const [(0, 0x10FFFF)]),
      ),
    );
  }

  void _fontFaceInvalid(AtRule rule, String message) => _report(
    DiagnosticCodes.cssFontFaceInvalid,
    DiagnosticSeverity.warning,
    rule.offset,
    message,
  );

  static const Set<String> _notFamilyNames = {
    'serif',
    'sans-serif',
    'monospace',
    'cursive',
    'fantasy',
    'system-ui',
    'inherit',
    'initial',
    'unset',
    'default',
  };

  /// Uma família só: string, ou idents separados por espaço.
  static String? _familyName(List<CssToken> value) {
    if (value.length == 1 && value.single.type == CssTokenType.string) {
      final name = value.single.value.trim();
      return name.isEmpty ? null : name;
    }
    final words = <String>[];
    for (final t in value) {
      if (t.type == CssTokenType.whitespace) continue;
      if (t.type != CssTokenType.ident) return null;
      words.add(t.value);
    }
    if (words.isEmpty) return null;
    if (words.length == 1 && _notFamilyNames.contains(asciiLower(words[0]))) {
      return null;
    }
    return words.join(' ');
  }

  /// Lista de `src`; itens inválidos ou externos ficam de fora.
  List<FontSource> _sources(List<CssToken> value) {
    final r = CssValueReader(value, _path);
    final comps = r.components;
    final out = <FontSource>[];
    if (comps == null) return out;
    var i = 0;
    while (i < comps.length) {
      var end = i;
      while (end < comps.length && !r.isComma(comps[end])) {
        end++;
      }
      final source = _source(r, comps.sublist(i, end));
      if (source != null) out.add(source);
      i = end + 1;
    }
    return out;
  }

  static FontSource? _source(CssValueReader r, List<CssComponent> group) {
    if (group.isEmpty) return null;
    final first = group.first;
    if (r.functionLower(first) == 'local') {
      final inner = r
          .inner(first)
          .where((t) => t.type != CssTokenType.rightParen);
      final name = _familyName(inner.toList()) ?? _localIdents(inner);
      return name == null ? null : FontLocalSource(name);
    }
    final path = r.url(first);
    if (path == null) return null;
    String? format;
    for (final c in group.skip(1)) {
      if (r.functionLower(c) != 'format') continue;
      for (final t in r.inner(c)) {
        if (t.type == CssTokenType.string || t.type == CssTokenType.ident) {
          format = asciiLower(t.value);
          break;
        }
      }
      break;
    }
    return FontUrlSource(path, format);
  }

  /// `local(Serif)` (genérica como nome de fonte local é válida).
  static String? _localIdents(Iterable<CssToken> inner) {
    final words = <String>[];
    for (final t in inner) {
      if (t.type != CssTokenType.ident) return null;
      words.add(t.value);
    }
    return words.isEmpty ? null : words.join(' ');
  }

  /// `font-weight` do descritor: um ou dois valores (intervalo).
  (int, int)? _weightRange(List<CssToken> value) {
    final r = CssValueReader(value, _path);
    final comps = r.components;
    if (comps == null || comps.isEmpty || comps.length > 2) return null;
    final weights = <int>[];
    for (final c in comps) {
      final n = r.number(c);
      if (n != null) {
        if (n < 1 || n > 1000) return null;
        weights.add(n.round());
        continue;
      }
      switch (r.keyword(c)) {
        case CssKeywords.normal:
          weights.add(400);
        case CssKeywords.bold:
          weights.add(700);
        default:
          return null;
      }
    }
    final a = weights.first;
    final b = weights.last;
    return a <= b ? (a, b) : (b, a);
  }

  int? _fontStyle(List<CssToken> value) {
    final r = CssValueReader(value, _path);
    final comps = r.components;
    if (comps == null || comps.isEmpty) return null;
    final id = r.keyword(comps.first);
    return switch (id) {
      CssKeywords.normal || CssKeywords.italic when comps.length == 1 => id,
      // `oblique` aceita ângulos depois.
      CssKeywords.oblique => id,
      _ => null,
    };
  }

  static const Set<String> _stretchKeywords = {
    'normal',
    'ultra-condensed',
    'extra-condensed',
    'condensed',
    'semi-condensed',
    'semi-expanded',
    'expanded',
    'extra-expanded',
    'ultra-expanded',
  };

  /// `font-stretch`: palavra-chave ou porcentagem(ns), como escrito.
  String? _stretch(RawDeclaration d) {
    final parts = [
      for (final t in d.value)
        if (t.type != CssTokenType.whitespace) t,
    ];
    if (parts.isEmpty || parts.length > 2) return null;
    for (final t in parts) {
      final ok =
          (t.type == CssTokenType.ident &&
              _stretchKeywords.contains(asciiLower(t.value))) ||
          (t.type == CssTokenType.percentage && t.number >= 0);
      if (!ok) return null;
    }
    return asciiLower(_parsed.source.substring(d.valueStart, d.valueEnd));
  }
}

/// Faixas de `unicode-range` lidas do texto cru [raw] (o tokenizador não
/// preserva `U+0000-00FF`); entradas inválidas ficam de fora, e `null` se
/// nenhuma valer.
List<(int, int)>? _unicodeRanges(String raw) {
  final text = raw.replaceAll(RegExp(r'/\*.*?(\*/|$)', dotAll: true), '');
  final out = <(int, int)>[];
  for (final part in text.split(',')) {
    final range = _unicodeRange(part.trim());
    if (range != null) out.add(range);
  }
  return out.isEmpty ? null : out;
}

const int _maxCodePoint = 0x10FFFF;

(int, int)? _unicodeRange(String s) {
  if (s.length < 3 || (s[0] != 'u' && s[0] != 'U') || s[1] != '+') {
    return null;
  }
  final body = s.substring(2);
  final dash = body.indexOf('-');
  int? start;
  int? end;
  if (dash >= 0) {
    start = _hexValue(body.substring(0, dash));
    end = _hexValue(body.substring(dash + 1));
  } else {
    final q = body.indexOf('?');
    final digits = q < 0 ? body : body.substring(0, q);
    final wild = q < 0 ? '' : body.substring(q);
    if (wild.split('').any((c) => c != '?')) return null;
    if (digits.length + wild.length > 6) return null;
    if (digits.isEmpty) {
      start = 0;
      end = wild.isEmpty ? null : int.parse('F' * wild.length, radix: 16);
    } else {
      start = _hexValue(digits + '0' * wild.length);
      end = _hexValue(digits + 'F' * wild.length);
    }
  }
  if (start == null || end == null || start > _maxCodePoint || start > end) {
    return null;
  }
  return (start, end > _maxCodePoint ? _maxCodePoint : end);
}

/// Valor de 1 a 6 dígitos hexadecimais, ou `null`.
int? _hexValue(String s) {
  if (s.isEmpty || s.length > 6) return null;
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i) | 0x20;
    final digit = (c >= 0x30 && c <= 0x39) || (c >= 0x61 && c <= 0x66);
    if (!digit) return null;
  }
  return int.parse(s, radix: 16);
}

/// Consulta inválida em `@supports`.
final class _Malformed implements Exception {
  const _Malformed();
}

/// Parênteses além do limite em `@supports`.
final class _TooDeep implements Exception {
  const _TooDeep();
}

const _malformed = _Malformed();

/// Avaliador de `@supports` (CSS Conditional 3, mais `selector()`):
/// verdadeiro sse a condição vale para o motor. Malformada,
/// `<general-enclosed>` ou além de [kMaxConditionDepth] níveis → falsa.
/// Linear, com recursão limitada a essa profundidade.
final class _SupportsParser {
  _SupportsParser(this.t, this.namespaces, this.path)
    : match = matchCssBlocks(t);

  final List<CssToken> t;
  final NamespaceMap namespaces;
  final String path;
  final Int32List match;

  bool evaluate() {
    try {
      final (v, end) = _condition(0, t.length, 0);
      return _ws(end, t.length) >= t.length && v;
    } on _Malformed {
      return false;
    } on _TooDeep {
      return false;
    }
  }

  int _ws(int i, int to) {
    while (i < to && t[i].type == CssTokenType.whitespace) {
      i++;
    }
    return i;
  }

  String? _ident(int i, int to) =>
      i < to && t[i].type == CssTokenType.ident ? asciiLower(t[i].value) : null;

  int _close(int i, int to) {
    final m = match[i];
    return m < to ? m : to;
  }

  int _after(int i, int to) {
    final m = match[i];
    return m < to ? m + 1 : to;
  }

  (bool, int) _condition(int i, int to, int depth) {
    i = _ws(i, to);
    if (_ident(i, to) == 'not') {
      final (v, end) = _inParens(_ws(i + 1, to), to, depth);
      return (!v, end);
    }
    var (value, end) = _inParens(i, to, depth);
    String? kind;
    while (true) {
      final j = _ws(end, to);
      final word = _ident(j, to);
      if (word != 'and' && word != 'or') break;
      if (kind != null && kind != word) throw _malformed;
      kind = word;
      final (v, e) = _inParens(_ws(j + 1, to), to, depth);
      value = word == 'and' ? value && v : value || v;
      end = e;
    }
    return (value, end);
  }

  (bool, int) _inParens(int i, int to, int depth) {
    if (i >= to) throw _malformed;
    final token = t[i];
    if (token.type == CssTokenType.function) {
      final next = _after(i, to);
      if (asciiLower(token.value) != 'selector') return (false, next);
      final inner = _trimmed(i + 1, _close(i, to));
      final list = parseSelectorList(inner, namespaces);
      return (list != null && list.length == 1, next);
    }
    if (token.type != CssTokenType.leftParen) throw _malformed;
    if (depth + 1 > kMaxConditionDepth) throw const _TooDeep();
    final close = _close(i, to);
    final next = _after(i, to);
    final from = _ws(i + 1, close);
    if (from < close && t[from].type == CssTokenType.ident) {
      final colon = _ws(from + 1, close);
      if (colon < close && t[colon].type == CssTokenType.colon) {
        return (_declaration(from, colon, close), next);
      }
    }
    try {
      final (v, end) = _condition(from, close, depth + 1);
      if (_ws(end, close) == close) return (v, next);
    } on _Malformed {
      // `<general-enclosed>`: falso.
    }
    return (false, next);
  }

  List<CssToken> _trimmed(int from, int to) {
    while (from < to && t[from].type == CssTokenType.whitespace) {
      from++;
    }
    while (to > from && t[to - 1].type == CssTokenType.whitespace) {
      to--;
    }
    return t.sublist(from, to);
  }

  /// `(nome: valor)`: verdadeiro sse a propriedade lê o valor.
  bool _declaration(int name, int colon, int close) {
    var value = _trimmed(colon + 1, close);
    // `!important` é aceito e ignorado.
    if (value.length >= 2 &&
        value.last.type == CssTokenType.ident &&
        asciiLower(value.last.value) == 'important') {
      var b = value.length - 2;
      while (b >= 0 && value[b].type == CssTokenType.whitespace) {
        b--;
      }
      if (b >= 0 &&
          value[b].type == CssTokenType.delim &&
          value[b].value == '!') {
        value = value.sublist(0, b);
        while (value.isNotEmpty && value.last.type == CssTokenType.whitespace) {
          value = value.sublist(0, value.length - 1);
        }
      }
    }
    if (value.isEmpty) return false;
    return parseProperty(t[name].value, value, sheetPath: path)
        is ParsedLonghands;
  }
}
