/// Carregamento das folhas de uma seção (spec do CSS §9): coleta de `<link>`
/// e `<style>`, `@import` com limites, decodificação, cache e a lista de
/// folhas para a chave do cache (doc/08 §4.1). Assíncrono: é o prólogo de
/// doc/08 §1.
///
/// Linear na seção:
/// - uma caminhada sobre os nós, pilha explícita, sem `querySelectorAll`,
///   `getElementsByTagName` nem `children` indexado; a leitura do `<style>`
///   como dado de caractere é uma passada;
/// - cada folha é buscada, decodificada e parseada uma vez por publicação
///   (cache positivo e negativo);
/// - no máximo [maxSheetAttemptsPerSection] tentativas e
///   [maxSheetsPerSection] folhas por seção, seja qual for o número de
///   `<link>` e `@import`; a pilha de ciclo tem no máximo 27 entradas e é
///   conferida antes do `fetch`;
/// - [maxSectionStyleBytes] limita o que o parse recebe de uma seção (folhas
///   de arquivo e `<style>`), e [maxStyleSheetBytes] evita drenar uma
///   entrada enorme;
/// - a reemissão do cache custa O(`CssIssue` + 1) por folha aplicada.
library;

import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:html/dom.dart';
import 'package:meta/meta.dart';

import '../container/container.dart';
import '../container/fnv1a64.dart';
import '../diagnostics/diagnostic.dart';
import '../diagnostics/exceptions.dart';
import '../publication/href.dart';
import '../publication/xml_text.dart' show encodingSniffBytes;
import 'parser.dart';
import 'tokenizer.dart';

/// Por folha de arquivo, pelo `PendingResource.size`.
const int maxStyleSheetBytes = 1024 * 1024;

/// Soma, por seção, dos `PendingResource.size` das folhas de arquivo e das
/// unidades de código dos `<style>` (#13; revisão do plano, decisão 26).
const int maxSectionStyleBytes = 4 * 1024 * 1024;

/// Texto de um `<style>`, em unidades de código.
const int maxStyleElementLength = 1024 * 1024;

/// `<link>`, `<style>` e `@import` aplicados.
const int maxSheetsPerSection = 64;

/// `<link>` e `@import` tentados, achados ou não (#28).
const int maxSheetAttemptsPerSection = 256;

/// A folha de topo tem profundidade 0.
const int maxImportDepth = 8;

/// Unidades de código de fonte no cache (#15).
const int maxCachedStyleSource = 8 * 1024 * 1024;

const String _htmlNamespace = 'http://www.w3.org/1999/xhtml';

enum SheetSource { link, style, import }

/// Uma folha aplicada, para a chave do cache (doc/08 §4.1).
@immutable
final class SheetRef {
  /// Folha de arquivo (`<link>` ou `@import`).
  const SheetRef.file(
    this.source, {
    required String this.path,
    required String this.bytesHash,
  }) : text = null;

  /// `<style>`.
  const SheetRef.style(String this.text)
    : source = SheetSource.style,
      path = null,
      bytesHash = null;

  final SheetSource source;

  /// Arquivo: caminho real no contêiner (`PendingResource.path`).
  final String? path;

  /// Arquivo: FNV-1a 64 dos bytes crus, 16 hex.
  final String? bytesHash;

  /// `<style>`: o texto já lido como dado de caractere (§9.1).
  final String? text;

  @override
  bool operator ==(Object other) =>
      other is SheetRef &&
      other.source == source &&
      other.path == path &&
      other.bytesHash == bytesHash &&
      other.text == text;

  @override
  int get hashCode => Object.hash(source, path, bytesHash, text);

  @override
  String toString() => text == null
      ? 'SheetRef(${source.name}, $path, $bytesHash)'
      : 'SheetRef(style, ${text!.length} unidades)';
}

final class AppliedSheet {
  const AppliedSheet(this.ref, this.sheet, this.href);

  final SheetRef ref;
  final StyleSheet sheet;

  /// `href` dos diagnósticos desta folha: o caminho, ou a seção para
  /// `<style>`.
  final String href;
}

/// Folhas de uma seção, na ordem da cascata (importadas antes de quem
/// importa; a mesma folha importada duas vezes aparece duas vezes). No
/// máximo [maxSheetsPerSection].
final class SectionSheets {
  SectionSheets(List<AppliedSheet> sheets) : sheets = List.unmodifiable(sheets);

  static final SectionSheets empty = SectionSheets(const []);

  final List<AppliedSheet> sheets;

  /// A lista ordenada de [SheetRef] (§9.7).
  List<SheetRef> get cacheKey =>
      List.unmodifiable([for (final s in sheets) s.ref]);
}

/// Entrada do [StyleSheetCache]: positiva ([_Parsed]) ou negativa.
sealed class _Entry {
  const _Entry();

  /// Unidades de código de fonte que a entrada ocupa; negativa conta 0.
  int get weight => 0;
}

final class _Parsed extends _Entry {
  const _Parsed(
    this.sheet,
    this.realPath,
    this.bytesHash,
    this.size,
    this.decodeDiagnostics,
  );

  final StyleSheet sheet;
  final String realPath;
  final String bytesHash;
  final int size;

  /// O que `decodeCss` emitiu (o `encodingFallback`), para reemitir.
  final List<EpubDiagnostic> decodeDiagnostics;

  @override
  int get weight => sheet.sourceLength;
}

/// Nenhum arquivo neste caminho.
final class _Missing extends _Entry {
  const _Missing();
}

final class _TooLarge extends _Entry {
  const _TooLarge(this.realPath, this.size);

  final String realPath;
  final int size;
}

final class _Unreadable extends _Entry {
  const _Unreadable(this.exception);

  final String exception;
}

/// Passaria do teto de bytes da seção; nunca vai para o cache.
final class _OverBudget extends _Entry {
  const _OverBudget(this.realPath);

  final String realPath;
}

/// Folhas parseadas, e as faltas, reaproveitadas entre as seções de uma
/// publicação (os capítulos repetem a folha). LRU pelo tamanho do fonte.
final class StyleSheetCache {
  StyleSheetCache({this.maxSource = maxCachedStyleSource});

  final int maxSource;

  /// Chave `('file', caminho pedido)` ou `('style', texto)`.
  final LinkedHashMap<(String, String), Object> _entries = LinkedHashMap();
  int _total = 0;

  /// Entradas guardadas (testes).
  @visibleForTesting
  int get length => _entries.length;

  /// Unidades de código de fonte guardadas (testes).
  @visibleForTesting
  int get sourceUnits => _total;

  Object? _get((String, String) key) {
    final value = _entries.remove(key);
    if (value != null) _entries[key] = value; // mais recente no fim
    return value;
  }

  void _put((String, String) key, Object value, int weight) {
    if (weight > maxSource) return; // maior que o teto: não entra
    final old = _entries.remove(key);
    if (old != null) _total -= _weightOf(old);
    _entries[key] = value;
    _total += weight;
    while (_total > maxSource) {
      final oldest = _entries.keys.first;
      _total -= _weightOf(_entries.remove(oldest)!);
    }
  }

  static int _weightOf(Object value) => switch (value) {
    final _Entry e => e.weight,
    final StyleSheet s => s.sourceLength,
    _ => 0,
  };

  _Entry? _file(String path) => _get(('file', path)) as _Entry?;

  void _putFile(String path, _Entry entry) =>
      _put(('file', path), entry, entry.weight);

  StyleSheet? _style(String text) => _get(('style', text)) as StyleSheet?;

  void _putStyle(String text, StyleSheet sheet) =>
      _put(('style', text), sheet, sheet.sourceLength);
}

/// Bytes de uma folha para texto (§9.4): BOM; senão `@charset "…";` na
/// forma exata do CSS Syntax §3.2 nos primeiros [encodingSniffBytes];
/// senão UTF-8. UTF-8 inválido e UTF-16 com número ímpar de bytes caem
/// para Latin-1 com `encodingFallback`.
String decodeCss(
  Uint8List bytes, {
  required String path,
  required DiagnosticSink sink,
}) {
  final n = bytes.length;
  if (n >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
    return _decodeUtf8(Uint8List.sublistView(bytes, 3), 'utf-8', path, sink);
  }
  if (n >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _decodeUtf16(Uint8List.sublistView(bytes, 2), true, path, sink);
  }
  if (n >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _decodeUtf16(Uint8List.sublistView(bytes, 2), false, path, sink);
  }
  final label = _charsetLabel(bytes);
  if (label != null &&
      const {
        'iso-8859-1',
        'latin1',
        'windows-1252',
        'us-ascii',
      }.contains(label)) {
    return latin1.decode(bytes);
  }
  // utf-16, utf-16le e utf-16be declarados sem BOM contam como UTF-8 (o
  // `@charset` foi lido como ASCII); rótulo desconhecido também.
  return _decodeUtf8(bytes, label, path, sink);
}

/// `@charset "` (40 63 68 61 72 73 65 74 20 22), rótulo ASCII sem `"`, e
/// `";` dentro dos primeiros [encodingSniffBytes] bytes; em minúsculas.
String? _charsetLabel(Uint8List bytes) {
  const prefix = [0x40, 0x63, 0x68, 0x61, 0x72, 0x73, 0x65, 0x74, 0x20, 0x22];
  final end = bytes.length < encodingSniffBytes
      ? bytes.length
      : encodingSniffBytes;
  if (end < prefix.length + 2) return null;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) return null;
  }
  for (var i = prefix.length; i + 1 < end; i++) {
    final b = bytes[i];
    if (b == 0x22) {
      if (bytes[i + 1] != 0x3B) return null;
      return cssAsciiLower(ascii.decode(bytes.sublist(prefix.length, i)));
    }
    if (b > 0x7F) return null;
  }
  return null;
}

String _decodeUtf8(
  Uint8List bytes,
  String? declared,
  String path,
  DiagnosticSink sink,
) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return _fallback(bytes, declared, path, sink);
  }
}

String _decodeUtf16(
  Uint8List bytes,
  bool little,
  String path,
  DiagnosticSink sink,
) {
  final declared = little ? 'utf-16le' : 'utf-16be';
  if (bytes.length.isOdd) return _fallback(bytes, declared, path, sink);
  final units = Uint16List(bytes.length ~/ 2);
  for (var i = 0; i < units.length; i++) {
    final a = bytes[2 * i];
    final b = bytes[2 * i + 1];
    units[i] = little ? a | b << 8 : a << 8 | b;
  }
  return String.fromCharCodes(units);
}

String _fallback(
  Uint8List bytes,
  String? declared,
  String path,
  DiagnosticSink sink,
) {
  sink.emit(
    EpubDiagnosticCode.encodingFallback,
    href: path,
    message:
        'bytes inválidos em ${declared ?? 'utf-8'}; decodificado como latin1',
    details: {'declared': declared, 'used': 'latin1'},
    onStrict: (m) => EpubSectionParseException(m, href: path),
  );
  return latin1.decode(bytes);
}

/// O texto de um `<style>` como dado de caractere do XML (#22), numa
/// passada: `<![CDATA[ … ]]>` literal sem os marcadores (sem fim: até o fim
/// do texto); fora dele, `&lt;`, `&gt;`, `&amp;`, `&quot;`, `&apos;`,
/// `&#N;` e `&#xH;` decodificados (fora de faixa, surrogate e `&#0;` →
/// U+FFFD); outra entidade fica literal. `<!-- -->` fica no texto, para o
/// tokenizador do CSS (§7.5).
String xmlCharacterData(String s) {
  final n = s.length;
  StringBuffer? out;
  var start = 0; // começo do trecho cru pendente
  var i = 0;
  void flush(int at, String replacement, int next) {
    (out ??= StringBuffer())
      ..write(s.substring(start, at))
      ..write(replacement);
    start = next;
  }

  while (i < n) {
    final c = s.codeUnitAt(i);
    if (c == 0x3C && s.startsWith('<![CDATA[', i)) {
      final end = s.indexOf(']]>', i + 9);
      final content = end < 0 ? s.substring(i + 9) : s.substring(i + 9, end);
      final next = end < 0 ? n : end + 3;
      flush(i, content, next);
      i = next;
      continue;
    }
    if (c != 0x26) {
      i++;
      continue;
    }
    final (replacement, next) = _entity(s, i);
    if (replacement == null) {
      i++;
    } else {
      flush(i, replacement, next);
      i = next;
    }
  }
  final b = out;
  if (b == null) return s;
  b.write(s.substring(start));
  return b.toString();
}

const Map<String, String> _xmlEntities = {
  'lt;': '<',
  'gt;': '>',
  'amp;': '&',
  'quot;': '"',
  'apos;': "'",
};

/// Referência em `s[at]` (`&`): o texto e o índice depois dela, ou
/// `(null, at)` se não é uma das do XML.
(String?, int) _entity(String s, int at) {
  for (final MapEntry(key: name, value: text) in _xmlEntities.entries) {
    if (s.startsWith(name, at + 1)) return (text, at + 1 + name.length);
  }
  if (!s.startsWith('#', at + 1)) return (null, at);
  var i = at + 2;
  final hex = i < s.length && s.codeUnitAt(i) == 0x78; // só `x` minúsculo
  if (hex) i++;
  var value = 0;
  var digits = 0;
  while (i < s.length) {
    final c = s.codeUnitAt(i);
    final d = c >= 0x30 && c <= 0x39
        ? c - 0x30
        : hex && c >= 0x61 && c <= 0x66
        ? c - 0x61 + 10
        : hex && c >= 0x41 && c <= 0x46
        ? c - 0x41 + 10
        : -1;
    if (d < 0) break;
    if (value <= 0x10FFFF) value = value * (hex ? 16 : 10) + d;
    digits++;
    i++;
  }
  if (digits == 0 || i >= s.length || s.codeUnitAt(i) != 0x3B) {
    return (null, at);
  }
  final valid =
      value != 0 && value <= 0x10FFFF && !(value >= 0xD800 && value <= 0xDFFF);
  return (String.fromCharCode(valid ? value : 0xFFFD), i + 1);
}

/// Tokens por espaço ASCII, em minúsculas ASCII (`rel`).
Set<String> _asciiTokens(String value) {
  final out = <String>{};
  var start = -1;
  for (var i = 0; i <= value.length; i++) {
    final c = i < value.length ? value.codeUnitAt(i) : 0x20;
    final space = c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0C || c == 0x0D;
    if (space) {
      if (start >= 0) out.add(cssAsciiLower(value.substring(start, i)));
      start = -1;
    } else if (start < 0) {
      start = i;
    }
  }
  return out;
}

/// `type` ausente, vazio ou `text/css` (sem caixa, antes de `;`).
bool _isCssType(String? type) {
  if (type == null) return true;
  final semicolon = type.indexOf(';');
  final essence = cssAsciiLower(
    (semicolon < 0 ? type : type.substring(0, semicolon)).trim(),
  );
  return essence.isEmpty || essence == 'text/css';
}

sealed class _Found {
  const _Found();
}

final class _FoundLink extends _Found {
  const _FoundLink(this.href);

  final String href;
}

final class _FoundStyle extends _Found {
  const _FoundStyle(this.text);

  final String text;
}

/// Junta as folhas de [document] (a seção em [sectionPath]). Não fecha o
/// contêiner. Nunca lança por causa do CSS; a exceção de `strict` do [sink]
/// ou do [containerSink] propaga como está.
///
/// [sink]: o sink da seção, onde o CSS emite. [containerSink]: o sink com
/// que [container] foi aberto; só serve para reconhecer, por identidade, a
/// exceção de `strict` que o contêiner lança no `fetch`/`decode()` (§9.3).
Future<SectionSheets> loadSectionSheets(
  EpubContainer container,
  Document document, {
  required String sectionPath,
  required StyleSheetCache cache,
  required DiagnosticSink sink,
  required DiagnosticSink containerSink,
}) async {
  final loader = _Loader(container, sectionPath, cache, sink, containerSink);
  for (final found in loader.collect(document)) {
    switch (found) {
      case _FoundLink(:final href):
        await loader.attempt(
          href,
          base: dirnameOf(sectionPath),
          depth: 0,
          stack: const [],
          from: sectionPath,
          source: SheetSource.link,
        );
      case _FoundStyle(:final text):
        await loader.style(text);
    }
  }
  return SectionSheets(loader.sheets);
}

final class _Loader {
  _Loader(
    this._container,
    this._section,
    this._cache,
    this._sink,
    this._containerSink,
  );

  final EpubContainer _container;
  final String _section;
  final StyleSheetCache _cache;
  final DiagnosticSink _sink;
  final DiagnosticSink _containerSink;

  final List<AppliedSheet> sheets = [];

  /// Folhas anexadas e em andamento (#36).
  int _reserved = 0;
  int _attempts = 0;
  int _bytes = 0;
  final Set<String> _limitsEmitted = {};

  void _emit(
    EpubDiagnosticCode code,
    String href,
    String message, [
    Map<String, Object?> details = const {},
  ]) => _sink.emit(
    code,
    href: href,
    message: message,
    details: details,
    onStrict: (m) => EpubSectionParseException(m, href: href),
  );

  /// Cada tipo de `limit` sai uma vez por seção.
  void _limit(String kind, String href, String from) {
    if (!_limitsEmitted.add(kind)) return;
    final what = switch (kind) {
      'sheets' => '$maxSheetsPerSection folhas',
      'attempts' => '$maxSheetAttemptsPerSection tentativas',
      _ => '$maxSectionStyleBytes bytes de CSS',
    };
    _emit(
      EpubDiagnosticCode.stylesheetIgnored,
      href,
      'teto de $what por seção atingido',
      {'reason': 'limit', 'limit': kind, 'from': from},
    );
  }

  /// Caminho de um `href` para diagnóstico sem busca: a URL remota, a forma
  /// decodificada (ou a normalizada), ou [fallback] se é recusado.
  static String _hrefForDiagnostic(String raw, String base, String fallback) {
    if (isRemoteHref(raw)) return raw.trim();
    final normalized = normalizeHref(base, raw);
    if (normalized == null) return fallback;
    return decodePath(normalized) ?? normalized;
  }

  /// §9.1: `<link>` e `<style>` em ordem de documento, sem descer em
  /// `<template>`.
  List<_Found> collect(Document document) {
    final out = <_Found>[];
    final stack = <Node>[...document.nodes.reversed];
    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      if (node is! Element) continue;
      final html = node.namespaceUri == _htmlNamespace;
      final name = node.localName;
      if (html && name == 'template') continue; // conteúdo inerte
      if (html && name == 'link') {
        final found = _link(node);
        if (found != null) out.add(found);
      } else if (name == 'style') {
        final found = _style(node);
        if (found != null) out.add(found);
        continue; // o texto do <style> não tem elemento
      }
      final children = node.nodes;
      for (var i = children.length - 1; i >= 0; i--) {
        stack.add(children[i]);
      }
    }
    return out;
  }

  _FoundLink? _link(Element link) {
    final attributes = link.attributes;
    final rel = _asciiTokens(attributes['rel'] ?? '');
    if (!rel.contains('stylesheet') || rel.contains('alternate')) return null;
    if (!_isCssType(attributes['type'])) return null;
    final href = (attributes['href'] ?? '').trim();
    if (href.isEmpty) return null;
    final media = attributes['media'];
    if (!mediaAttributeMatches(media)) {
      _emit(
        EpubDiagnosticCode.stylesheetMediaIgnored,
        _hrefForDiagnostic(href, dirnameOf(_section), _section),
        'folha com media que não casa',
        {'media': truncateSample(media!)},
      );
      return null;
    }
    return _FoundLink(href);
  }

  _FoundStyle? _style(Element style) {
    final attributes = style.attributes;
    if (!_isCssType(attributes['type'])) return null;
    final media = attributes['media'];
    if (!mediaAttributeMatches(media)) {
      _emit(
        EpubDiagnosticCode.stylesheetMediaIgnored,
        _section,
        '<style> com media que não casa',
        {'media': truncateSample(media!)},
      );
      return null;
    }
    final raw = StringBuffer();
    for (final child in style.nodes) {
      if (child is Text) raw.write(child.data);
    }
    if (raw.length > maxStyleElementLength) {
      _emit(
        EpubDiagnosticCode.stylesheetIgnored,
        _section,
        '<style> acima de $maxStyleElementLength unidades de código',
        {'reason': 'too-large', 'length': raw.length},
      );
      return null;
    }
    return _FoundStyle(xmlCharacterData(raw.toString()));
  }

  /// Um `<style>`: reserva uma vaga, conta o texto no teto de bytes da seção
  /// e aplica, com profundidade 0.
  Future<void> style(String text) async {
    if (_reserved == maxSheetsPerSection) {
      _limit('sheets', _section, _section);
      return;
    }
    if (_bytes + text.length > maxSectionStyleBytes) {
      _limit('bytes', _section, _section);
      return;
    }
    _bytes += text.length;
    _reserved++;
    var sheet = _cache._style(text);
    if (sheet == null) {
      sheet = parseStyleSheet(text);
      _cache._putStyle(text, sheet);
    }
    await _apply(
      sheet,
      SheetRef.style(text),
      href: _section,
      base: dirnameOf(_section),
      depth: 0,
      stack: const [],
      decodeDiagnostics: const [],
    );
  }

  /// `tentar` de §9.5, para `<link>` e `@import`.
  Future<void> attempt(
    String raw, {
    required String base,
    required int depth,
    required List<String> stack,
    required String from,
    required SheetSource source,
  }) async {
    if (_attempts == maxSheetAttemptsPerSection) {
      _limit('attempts', _section, from);
      return;
    }
    _attempts++;
    if (isRemoteHref(raw)) {
      _emit(
        EpubDiagnosticCode.resourceMissing,
        raw.trim(),
        'folha remota não é buscada',
        {'reason': 'remote'},
      );
      return;
    }
    final normalized = normalizeHref(base, raw);
    if (normalized == null) {
      _emit(
        EpubDiagnosticCode.resourceMissing,
        from,
        'href de folha recusado',
        {'reason': 'refused', 'raw': truncateSample(raw)},
      );
      return;
    }
    final decoded = decodePath(normalized);
    final candidates = decoded != null && decoded != normalized
        ? [decoded, normalized]
        : [normalized];
    final preferred = candidates.first;
    if (depth > maxImportDepth) {
      _emit(
        EpubDiagnosticCode.stylesheetIgnored,
        preferred,
        '@import além da profundidade $maxImportDepth',
        {'reason': 'depth', 'from': from},
      );
      return;
    }
    if (candidates.any((c) => stack.contains(cssAsciiLower(c)))) {
      _emit(
        EpubDiagnosticCode.stylesheetIgnored,
        preferred,
        '@import em ciclo',
        {'reason': 'cycle', 'from': from},
      );
      return;
    }
    if (_reserved == maxSheetsPerSection) {
      _limit('sheets', preferred, from);
      return;
    }
    _reserved++; // a vaga é desta folha, antes do fetch e da recursão
    final entry = await _read(candidates);
    switch (entry) {
      case _Parsed():
        _bytes += entry.size;
        await _apply(
          entry.sheet,
          SheetRef.file(
            source,
            path: entry.realPath,
            bytesHash: entry.bytesHash,
          ),
          href: entry.realPath,
          base: dirnameOf(entry.realPath),
          depth: depth,
          stack: [
            ...stack,
            for (final c in candidates) cssAsciiLower(c),
            cssAsciiLower(entry.realPath),
          ],
          decodeDiagnostics: entry.decodeDiagnostics,
        );
      case _Missing():
        _reserved--;
        _emit(
          EpubDiagnosticCode.resourceMissing,
          preferred,
          'folha ausente no contêiner',
          {'from': from},
        );
      case _TooLarge(:final realPath, :final size):
        _reserved--;
        _emit(
          EpubDiagnosticCode.stylesheetIgnored,
          realPath,
          'folha acima de $maxStyleSheetBytes bytes',
          {'reason': 'too-large', 'size': size, 'from': from},
        );
      case _Unreadable(:final exception):
        _reserved--;
        _emit(
          EpubDiagnosticCode.resourceUnreadable,
          preferred,
          'folha ilegível',
          {'reason': 'unreadable', 'exception': exception},
        );
      case _OverBudget(:final realPath):
        _reserved--;
        _limit('bytes', realPath, from);
    }
  }

  /// Cache, senão `fetch` de cada candidato na ordem (§9.3, §9.6).
  Future<_Entry> _read(List<String> candidates) async {
    for (final c in candidates) {
      final cached = _cache._file(c);
      if (cached is _Missing) continue;
      if (cached is _Parsed) {
        return _bytes + cached.size > maxSectionStyleBytes
            ? _OverBudget(cached.realPath)
            : cached;
      }
      if (cached != null) return cached;
      final PendingResource? resource;
      try {
        resource = await _container.fetch(c);
      } on EpubException catch (e) {
        if (_isStrict(e)) rethrow;
        return _unreadable(c, e);
      }
      if (resource == null) {
        _cache._putFile(c, const _Missing());
        continue;
      }
      if (resource.size > maxStyleSheetBytes) {
        final entry = _TooLarge(resource.path, resource.size);
        _cache._putFile(c, entry);
        return entry;
      }
      if (_bytes + resource.size > maxSectionStyleBytes) {
        return _OverBudget(resource.path); // antes do decode(), sem cache
      }
      try {
        for (final _ in resource.decode()) {}
      } on EpubException catch (e) {
        if (_isStrict(e)) rethrow;
        return _unreadable(c, e);
      }
      final bytes = resource.bytes;
      final decodeSink = DiagnosticSink();
      final text = decodeCss(bytes, path: resource.path, sink: decodeSink);
      final entry = _Parsed(
        parseStyleSheet(text),
        resource.path,
        (Fnv1a64()..add(bytes)).hex,
        resource.size,
        decodeSink.diagnostics,
      );
      _cache._putFile(c, entry);
      return entry;
    }
    return const _Missing();
  }

  /// A exceção do `strict` de um dos dois sinks, reconhecida por
  /// identidade (§9.3), propaga como está.
  bool _isStrict(EpubException e) =>
      identical(e, _containerSink.lastStrictException) ||
      identical(e, _sink.lastStrictException);

  /// Outra `EpubException` do contêiner vira entrada ilegível.
  _Entry _unreadable(String path, EpubException e) {
    final entry = _Unreadable('$e');
    _cache._putFile(path, entry);
    return entry;
  }

  /// `aplicar` de §9.5: reemite o que o CSS guardou, segue os `@import` e
  /// anexa a folha (ocupando a vaga reservada).
  Future<void> _apply(
    StyleSheet sheet,
    SheetRef ref, {
    required String href,
    required String base,
    required int depth,
    required List<String> stack,
    required List<EpubDiagnostic> decodeDiagnostics,
  }) async {
    for (final d in decodeDiagnostics) {
      _emit(d.code, d.href ?? href, d.message, {
        for (final MapEntry(:key, :value) in d.details.entries)
          if (key != 'count') key: value,
      });
    }
    for (final issue in sheet.issues) {
      final import = issue.details['import'];
      final issueHref =
          identical(issue.code, EpubDiagnosticCode.stylesheetMediaIgnored) &&
              import is String
          ? _hrefForDiagnostic(import, base, href)
          : href;
      _emit(
        issue.code,
        issueHref,
        issue.reason == null
            ? 'CSS com media que não casa'
            : 'CSS ignorado: ${issue.reason}',
        {
          if (issue.reason != null) 'reason': issue.reason,
          'discarded': issue.discarded,
          ...issue.details,
        },
      );
    }
    for (final import in sheet.imports) {
      await attempt(
        import.href,
        base: base,
        depth: depth + 1,
        stack: stack,
        from: href,
        source: SheetSource.import,
      );
    }
    sheets.add(AppliedSheet(ref, sheet, href));
  }
}
