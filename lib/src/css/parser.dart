/// Parser de folhas e de `style=""` (spec do CSS §5), pelo algoritmo do CSS
/// Syntax Level 3 no modelo atual ("consume a stylesheet's contents",
/// "consume a block's contents", "consume a qualified rule", "consume an
/// at-rule", "consume a declaration") sobre o [CssTokenizer].
///
/// Linear no tamanho do texto:
/// - cada token é pedido ao tokenizador uma vez; a tentativa de declaração
///   guarda os tokens dela num buffer e, quando falha, a releitura como
///   regra aninhada usa esse buffer. Como a tentativa para no ponto em que a
///   falha é certa (§5.3), ela nunca consome além do bloco `{}` que a fez
///   falhar e dos espaços e do `!important` depois dele: cada token é
///   examinado no máximo duas vezes;
/// - o prelúdio de cada regra e o valor de cada declaração são juntados uma
///   vez numa lista e entregues a `parseSelectorList`/`parseDeclaration`;
/// - blocos são consumidos com uma pilha de fechamentos (iterativo); a
///   recursão só existe por `@media` e bloco de regra, até 32 níveis;
/// - os diagnósticos são agregados por (código, motivo) por folha.
library;

import '../diagnostics/diagnostic.dart';
import 'properties.dart';
import 'selector.dart';
import 'tokenizer.dart';

/// Blocos abertos (`{`, `(`, `[`, função) antes do modo de salto (§5.4).
const int maxCssNesting = 32;

/// `@import` que vale: no nível de topo, em posição, com media que casa.
final class CssImport {
  const CssImport(this.href);

  /// Cru, como escrito na folha.
  final String href;

  @override
  String toString() => 'CssImport($href)';
}

final class StyleRule {
  StyleRule(List<Selector> selectors, List<Declaration> declarations)
    : selectors = List.unmodifiable(selectors),
      declarations = List.unmodifiable(declarations);

  /// Só os seletores suportados da lista, na ordem (§6.3).
  final List<Selector> selectors;

  /// Já expandidas e tipadas (§7), na ordem.
  final List<Declaration> declarations;
}

/// Diagnóstico de parse guardado na folha e reemitido pelo loader a cada
/// seção que a aplica (§9.6). No máximo um por (código, motivo) por folha.
final class CssIssue {
  CssIssue(
    this.code, {
    this.reason,
    required this.discarded,
    Map<String, Object?> details = const {},
  }) : details = Map.unmodifiable(details);

  /// `cssRuleIgnored`, `stylesheetIgnored` ou `stylesheetMediaIgnored`.
  final EpubDiagnosticCode code;

  /// §12.1; `null` em `stylesheetMediaIgnored`.
  final String? reason;

  /// Quantas regras, seletores, blocos ou `@import`.
  final int discarded;

  /// Amostra: `sample` (prelúdio ou seletor), `media`, `import` (href cru),
  /// `limit`.
  final Map<String, Object?> details;

  @override
  String toString() =>
      'CssIssue(${code.name}${reason == null ? '' : ', $reason'}, '
      '$discarded, $details)';
}

final class StyleSheet {
  StyleSheet({
    required List<CssImport> imports,
    required List<StyleRule> rules,
    required List<CssIssue> issues,
    required this.sourceLength,
  }) : imports = List.unmodifiable(imports),
       rules = List.unmodifiable(rules),
       issues = List.unmodifiable(issues);

  /// Só os que valem (em posição, media casada).
  final List<CssImport> imports;

  /// Fora das `@media` que não casam.
  final List<StyleRule> rules;
  final List<CssIssue> issues;

  /// Unidades de código do texto.
  final int sourceLength;
}

/// Folha inteira. Nunca lança.
StyleSheet parseStyleSheet(String text) =>
    (_Parser(text, attribute: false)..parseSheet()).sheet(text.length);

/// Conteúdo de `style=""`: as declarações e quantos itens foram descartados
/// por sintaxe (§10.5 soma e emite uma vez por seção). Nunca lança.
(List<Declaration>, int) parseStyleAttribute(String text) {
  final p = _Parser(text, attribute: true);
  final declarations = p.blockContents(0);
  return (List.unmodifiable(declarations), p.parseErrors);
}

/// Atributo `media` de `<link>` e `<style>`: `null` casa; senão o texto é
/// tokenizado e vai a [mediaMatches].
bool mediaAttributeMatches(String? media) {
  if (media == null) return true;
  final tokenizer = CssTokenizer(media);
  final tokens = <CssToken>[];
  for (
    var t = tokenizer.next();
    t.type != CssTokenType.eof;
    t = tokenizer.next()
  ) {
    tokens.add(t);
  }
  return mediaMatches(tokens);
}

/// Lista de media queries (Media Queries 4 §3) sem avaliar característica
/// nenhuma: casa se alguma query de topo é `all`, `screen`, `only all`,
/// `only screen` ou `not <tipo>` com tipo que não é `all` nem `screen`.
/// Vírgula dentro de `(…)` ou de função não separa queries; lista vazia
/// casa; query malformada vale `not all`.
bool mediaMatches(List<CssToken> tokens) {
  var sawContent = false;
  var matched = false;
  var depth = 0;
  final words = <String>[];
  var broken = false;

  void endQuery() {
    if (!broken) matched = matched || _queryMatches(words);
    words.clear();
    broken = false;
  }

  for (final t in tokens) {
    switch (t.type) {
      case CssTokenType.function ||
          CssTokenType.leftParen ||
          CssTokenType.leftBracket ||
          CssTokenType.leftBrace:
        depth++;
        broken = true;
        sawContent = true;
      case CssTokenType.rightParen ||
          CssTokenType.rightBracket ||
          CssTokenType.rightBrace:
        if (depth > 0) {
          depth--;
        } else {
          broken = true;
        }
        sawContent = true;
      case CssTokenType.comma when depth == 0:
        sawContent = true;
        endQuery();
      case CssTokenType.whitespace:
        break;
      case CssTokenType.ident when depth == 0:
        sawContent = true;
        if (words.length < 3) {
          words.add(cssAsciiLower(t.value));
        } else {
          broken = true;
        }
      default:
        sawContent = true;
        if (depth == 0) broken = true;
    }
  }
  if (!sawContent) return true;
  endQuery();
  return matched;
}

const Set<String> _reservedMediaWords = {'only', 'not', 'and', 'or', 'layer'};

bool _queryMatches(List<String> w) {
  bool screenOrAll(String s) => s == 'all' || s == 'screen';
  return switch (w.length) {
    1 => screenOrAll(w[0]),
    2 =>
      (w[0] == 'only' && screenOrAll(w[1])) ||
          (w[0] == 'not' &&
              !screenOrAll(w[1]) &&
              !_reservedMediaWords.contains(w[1])),
    _ => false,
  };
}

/// At-rules reconhecidas: contam para a posição do `@import` (CSS Cascade 4
/// §2.2) e são descartadas em silêncio (§5.1).
/// Só as que o navegador reconhece: `@-moz-document`, `@document`,
/// `@viewport`, `@-ms-viewport` e `@-moz-keyframes` são desconhecidas no
/// Chromium e não tiram o `@import` seguinte de posição.
const Set<String> _knownAtRules = {
  'namespace', 'font-face', 'page', 'supports', 'layer', 'counter-style', //
  'font-feature-values', 'font-palette-values', 'property', 'container',
  'scope', 'starting-style', 'position-try', 'view-transition', 'keyframes',
  '-webkit-keyframes',
};

bool _isKnownAtRule(String name) => _knownAtRules.contains(name);

final class _IssueBuilder {
  _IssueBuilder(this.code, this.reason, this.details);

  final EpubDiagnosticCode code;
  final String? reason;
  final Map<String, Object?> details;
  int discarded = 1;
}

final class _Parser {
  _Parser(String text, {required this.attribute})
    : _tokenizer = CssTokenizer(text);

  final CssTokenizer _tokenizer;

  /// Em `style=""`: nada vira `CssIssue`; os descartes somam em
  /// [parseErrors].
  final bool attribute;
  int parseErrors = 0;

  final List<CssToken> _replay = [];
  int _replayAt = 0;
  CssToken? _pushedBack;

  final List<CssImport> _imports = [];
  final List<StyleRule> _rules = [];
  final Map<String, _IssueBuilder> _issues = {};

  /// Uma regra de estilo válida ou at-rule reconhecida já apareceu: um
  /// `@import` depois dela está fora de posição.
  bool _rulesSeen = false;

  /// Prefixos declarados por `@namespace` em posição (CSS Namespaces 3 §3:
  /// depois de `@charset` e `@import`, antes de tudo o mais).
  final Set<String> _namespaces = {};
  bool _namespacesClosed = false;

  CssToken _next() {
    final back = _pushedBack;
    if (back != null) {
      _pushedBack = null;
      return back;
    }
    if (_replayAt < _replay.length) {
      final t = _replay[_replayAt++];
      if (_replayAt == _replay.length) {
        _replay.clear();
        _replayAt = 0;
      }
      return t;
    }
    return _tokenizer.next();
  }

  /// CSS Syntax "reconsume the current input token".
  void _reconsume(CssToken t) => _pushedBack = t;

  /// Devolve ao fluxo [tokens], que foram os últimos lidos, antes do que
  /// ainda estava para reler.
  void _unread(List<CssToken> tokens) {
    assert(_pushedBack == null, 'reconsumo pendente');
    final pending = _replay.sublist(_replayAt);
    _replay
      ..clear()
      ..addAll(tokens)
      ..addAll(pending);
    _replayAt = 0;
  }

  /// Agrega por (código, motivo, [key]): o primeiro guarda a amostra, os
  /// seguintes só somam [count] em `discarded`.
  void _issue(
    EpubDiagnosticCode code, {
    String? reason,
    String key = '',
    Map<String, Object?> details = const {},
    int count = 1,
  }) {
    if (attribute) {
      parseErrors += count;
      return;
    }
    final k = '${code.name}/$reason/$key';
    final existing = _issues[k];
    if (existing != null) {
      existing.discarded += count;
    } else {
      _issues[k] = _IssueBuilder(code, reason, details)..discarded = count;
    }
  }

  void _cssRule(String reason, String sample) => _issue(
    EpubDiagnosticCode.cssRuleIgnored,
    reason: reason,
    details: {'sample': sample},
  );

  void _nestingLimit() => _issue(
    EpubDiagnosticCode.stylesheetIgnored,
    reason: 'limit',
    details: {'limit': 'nesting'},
  );

  StyleSheet sheet(int sourceLength) => StyleSheet(
    imports: _imports,
    rules: _rules,
    issues: [
      for (final b in _issues.values)
        CssIssue(
          b.code,
          reason: b.reason,
          discarded: b.discarded,
          details: b.details,
        ),
    ],
    sourceLength: sourceLength,
  );

  void parseSheet() => _ruleList(topLevel: true, depth: 0);

  /// Resto de um bloco aberto por [opener], que fica em profundidade
  /// [depth] (ele incluso). Os tokens vão para [into] (se dado), com o
  /// fechamento. Um fechamento que não é o esperado é só um token (CSS
  /// Syntax §5.4.8). Devolve `false` se o aninhamento passou de
  /// [maxCssNesting]: daí em diante nada é guardado, mas o bloco é
  /// consumido até fechar (§5.4).
  bool _consumeBlock(CssToken opener, int depth, List<CssToken>? into) {
    var ok = depth <= maxCssNesting;
    if (!ok) _nestingLimit();
    var sink = ok ? into : null;
    final stack = <CssTokenType>[_closerOf(opener.type)];
    while (stack.isNotEmpty) {
      final t = _next();
      if (t.type == CssTokenType.eof) return ok;
      sink?.add(t);
      switch (t.type) {
        case CssTokenType.function ||
            CssTokenType.leftParen ||
            CssTokenType.leftBracket ||
            CssTokenType.leftBrace:
          stack.add(_closerOf(t.type));
          if (ok && depth + stack.length - 1 > maxCssNesting) {
            ok = false;
            sink = null;
            _nestingLimit();
          }
        case CssTokenType.rightParen ||
            CssTokenType.rightBracket ||
            CssTokenType.rightBrace:
          if (stack.last == t.type) stack.removeLast();
        default:
          break;
      }
    }
    return ok;
  }

  static CssTokenType _closerOf(CssTokenType opener) => switch (opener) {
    CssTokenType.leftBracket => CssTokenType.rightBracket,
    CssTokenType.leftBrace => CssTokenType.rightBrace,
    _ => CssTokenType.rightParen,
  };

  static bool _opensBlock(CssTokenType type) =>
      type == CssTokenType.function ||
      type == CssTokenType.leftParen ||
      type == CssTokenType.leftBracket;

  /// "Consume a stylesheet's contents" ([topLevel]) ou o bloco de um
  /// `@media` que casa (a mesma lista de regras, sem o topo: `cdo`/`cdc`
  /// começam regra e `}` fecha o bloco).
  void _ruleList({required bool topLevel, required int depth}) {
    while (true) {
      final t = _next();
      switch (t.type) {
        case CssTokenType.eof:
          return;
        case CssTokenType.whitespace:
          continue;
        case CssTokenType.cdo || CssTokenType.cdc when topLevel:
          continue;
        case CssTokenType.rightBrace when !topLevel:
          return;
        case CssTokenType.atKeyword:
          _atRule(t, topLevel: topLevel, depth: depth);
        default:
          _qualifiedRule(t, topLevel: topLevel, depth: depth);
      }
    }
  }

  /// "Consume a qualified rule" numa lista de regras. No topo, `;` e `}`
  /// fazem parte do prelúdio.
  void _qualifiedRule(
    CssToken first, {
    required bool topLevel,
    required int depth,
  }) {
    final prelude = <CssToken>[];
    var poisoned = false;
    var t = first;
    while (true) {
      switch (t.type) {
        case CssTokenType.eof:
          _cssRule('parse-error', cssSample(prelude));
          return;
        case CssTokenType.rightBrace when !topLevel:
          _reconsume(t);
          _cssRule('parse-error', cssSample(prelude));
          return;
        case CssTokenType.leftBrace:
          _styleRule(prelude, poisoned: poisoned, depth: depth + 1);
          return;
        default:
          prelude.add(t);
          if (_opensBlock(t.type) && !_consumeBlock(t, depth + 1, prelude)) {
            poisoned = true;
          }
      }
      t = _next();
    }
  }

  /// O `{` de uma regra de estilo já foi lido; o bloco fica em [depth].
  void _styleRule(
    List<CssToken> prelude, {
    required bool poisoned,
    required int depth,
  }) {
    if (depth > maxCssNesting || poisoned) {
      // A regra cai: o prelúdio já registrou o limite, ou o salto do bloco
      // registra agora.
      _consumeBlock(const CssToken(CssTokenType.leftBrace), depth, null);
      return;
    }
    switch (parseSelectorList(prelude, namespaces: _namespaces)) {
      case SelectorInvalid(:final sample):
        _cssRule('parse-error', sample);
        _consumeBlock(const CssToken(CssTokenType.leftBrace), depth, null);
      case SelectorList(:final selectors, :final unsupported) && final list:
        // Só uma regra válida fecha os @namespace (`p!{}` não fecha).
        _rulesSeen = true;
        _namespacesClosed = true;
        if (unsupported > 0) {
          _issue(
            EpubDiagnosticCode.cssRuleIgnored,
            reason: 'unsupported-selector',
            details: {'sample': list.unsupportedSample},
            count: unsupported,
          );
        }
        if (selectors.isEmpty) {
          _consumeBlock(const CssToken(CssTokenType.leftBrace), depth, null);
          return;
        }
        _rules.add(StyleRule(selectors, blockContents(depth)));
    }
  }

  /// "Consume an at-rule" numa lista de regras.
  void _atRule(CssToken at, {required bool topLevel, required int depth}) {
    final name = cssAsciiLower(at.value);
    final prelude = <CssToken>[];
    var poisoned = false;
    var hasBlock = false;
    loop:
    while (true) {
      final t = _next();
      switch (t.type) {
        case CssTokenType.eof || CssTokenType.semicolon:
          break loop;
        case CssTokenType.rightBrace when !topLevel:
          _reconsume(t);
          break loop;
        case CssTokenType.leftBrace:
          hasBlock = true;
          break loop;
        default:
          prelude.add(t);
          if (_opensBlock(t.type) && !_consumeBlock(t, depth + 1, prelude)) {
            poisoned = true;
          }
      }
    }
    void skipBlock() {
      if (hasBlock) {
        _consumeBlock(const CssToken(CssTokenType.leftBrace), depth + 1, null);
      }
    }

    if (poisoned) {
      skipBlock();
      return;
    }
    switch (name) {
      case 'charset':
        skipBlock();
      case 'import':
        if (hasBlock) {
          skipBlock();
          _cssRule('parse-error', cssSample(prelude));
        } else {
          _import(prelude, topLevel: topLevel);
        }
      case 'media':
        if (!hasBlock) return;
        _rulesSeen = true;
        _namespacesClosed = true;
        if (!mediaMatches(prelude)) {
          skipBlock();
          _issue(
            EpubDiagnosticCode.stylesheetMediaIgnored,
            key: 'media',
            details: {'media': cssSample(prelude)},
          );
        } else if (depth + 1 > maxCssNesting) {
          skipBlock(); // o salto registra o limite
        } else {
          _ruleList(topLevel: false, depth: depth + 1);
        }
      case 'namespace':
        skipBlock();
        _rulesSeen = true;
        if (!hasBlock && topLevel && !_namespacesClosed) _namespace(prelude);
      default:
        skipBlock();
        if (_isKnownAtRule(name) && (hasBlock || name != 'layer')) {
          _rulesSeen = true;
          _namespacesClosed = true;
        }
    }
  }

  /// `@namespace prefixo url;` guarda o prefixo; o namespace padrão (sem
  /// prefixo) é ignorado.
  void _namespace(List<CssToken> prelude) {
    final words = [
      for (final t in prelude)
        if (t.type != CssTokenType.whitespace) t,
    ];
    if (words.length < 2 || words[0].type != CssTokenType.ident) return;
    final uri = words[1];
    if (uri.type == CssTokenType.string ||
        uri.type == CssTokenType.url ||
        (uri.type == CssTokenType.function &&
            cssAsciiEquals(uri.value, 'url'))) {
      _namespaces.add(words[0].value);
    }
  }

  /// Href de `@import`: `<string>`, `url(…)` sem aspas ou `url(<string>)`.
  /// Devolve o href e o índice depois dele; `null` se o prelúdio não
  /// começa assim.
  static (String, int)? _importHref(List<CssToken> prelude) {
    var i = 0;
    while (i < prelude.length && prelude[i].type == CssTokenType.whitespace) {
      i++;
    }
    if (i >= prelude.length) return null;
    final t = prelude[i];
    if (t.type == CssTokenType.string || t.type == CssTokenType.url) {
      return (t.value, i + 1);
    }
    if (t.type != CssTokenType.function || !cssAsciiEquals(t.value, 'url')) {
      return null;
    }
    var j = i + 1;
    while (j < prelude.length && prelude[j].type == CssTokenType.whitespace) {
      j++;
    }
    if (j >= prelude.length || prelude[j].type != CssTokenType.string) {
      return null;
    }
    final href = prelude[j].value;
    j++;
    while (j < prelude.length && prelude[j].type == CssTokenType.whitespace) {
      j++;
    }
    if (j >= prelude.length || prelude[j].type != CssTokenType.rightParen) {
      return null;
    }
    return (href, j + 1);
  }

  /// `@import` (§5.2): posição do CSS Cascade 4 §2.2, `layer`/`supports()`
  /// ignorados, media que não casa ignorada.
  void _import(List<CssToken> prelude, {required bool topLevel}) {
    final parsed = _importHref(prelude);
    if (parsed == null) {
      _cssRule('parse-error', cssSample(prelude));
      return;
    }
    final (href, after) = parsed;
    if (!topLevel || _rulesSeen) {
      _lateImport(href);
      return;
    }
    var i = after;
    while (i < prelude.length && prelude[i].type == CssTokenType.whitespace) {
      i++;
    }
    if (i < prelude.length) {
      final t = prelude[i];
      final word = cssAsciiLower(t.value);
      if ((t.type == CssTokenType.ident && word == 'layer') ||
          (t.type == CssTokenType.function &&
              (word == 'layer' || word == 'supports'))) {
        _issue(
          EpubDiagnosticCode.stylesheetIgnored,
          reason: 'unsupported-import',
          details: {'import': href},
        );
        return;
      }
    }
    final media = prelude.sublist(after);
    if (!mediaMatches(media)) {
      _issue(
        EpubDiagnosticCode.stylesheetMediaIgnored,
        key: 'import',
        details: {'media': cssSample(media), 'import': href},
      );
      return;
    }
    _imports.add(CssImport(href));
  }

  void _lateImport(String href) => _issue(
    EpubDiagnosticCode.stylesheetIgnored,
    reason: 'late-import',
    details: {'import': href},
  );

  /// "Consume a block's contents" dentro de um bloco de regra de estilo (em
  /// [depth]) e em `style=""` (em 0): até `}` ou o fim.
  List<Declaration> blockContents(int depth) {
    final declarations = <Declaration>[];
    while (true) {
      final t = _next();
      switch (t.type) {
        case CssTokenType.whitespace || CssTokenType.semicolon:
          continue;
        case CssTokenType.rightBrace || CssTokenType.eof:
          return declarations;
        case CssTokenType.atKeyword:
          _nestedAtRule(t, depth);
        default:
          _declaration(t, depth, declarations);
      }
    }
  }

  /// At-rule dentro de um bloco de estilo: com bloco, descartada com
  /// `nested-rule`; `@import`, `late-import`; outra sem bloco, em silêncio.
  void _nestedAtRule(CssToken at, int depth) {
    final prelude = <CssToken>[];
    loop:
    while (true) {
      final t = _next();
      switch (t.type) {
        case CssTokenType.eof || CssTokenType.semicolon:
          break loop;
        case CssTokenType.rightBrace:
          _reconsume(t);
          break loop;
        case CssTokenType.leftBrace:
          _consumeBlock(t, depth + 1, null);
          _cssRule(
            'nested-rule',
            truncateSample('@${at.value} ${cssSample(prelude)}'.trim()),
          );
          return;
        default:
          prelude.add(t);
          if (_opensBlock(t.type)) _consumeBlock(t, depth + 1, prelude);
      }
    }
    if (!cssAsciiEquals(at.value, 'import')) return;
    final parsed = _importHref(prelude);
    if (parsed == null) {
      _cssRule('parse-error', cssSample(prelude));
    } else {
      _lateImport(parsed.$1);
    }
  }

  /// Uma tentativa de declaração a partir de [first] (§5.3, decisão #35):
  /// para no ponto em que a falha já é certa, com o mesmo resultado do
  /// "consume a declaration" do CSS Syntax.
  void _declaration(CssToken first, int depth, List<Declaration> out) {
    final buffer = <CssToken>[first];
    if (first.type != CssTokenType.ident) {
      _fail(buffer, depth);
      return;
    }
    var t = _next();
    buffer.add(t);
    while (t.type == CssTokenType.whitespace) {
      t = _next();
      buffer.add(t);
    }
    if (t.type != CssTokenType.colon) {
      _fail(buffer, depth);
      return;
    }
    final valueStart = buffer.length;
    final custom = first.value.startsWith('--');
    var content = false; // algum token de topo que não é espaço
    var bad = false;
    var poisoned = false;
    value:
    while (true) {
      t = _next();
      switch (t.type) {
        case CssTokenType.eof || CssTokenType.semicolon:
          break value;
        case CssTokenType.rightBrace:
          _reconsume(t);
          break value;
        case CssTokenType.leftBrace:
          buffer.add(t);
          if (!_consumeBlock(t, depth + 1, buffer)) poisoned = true;
          if (custom) continue;
          // Um `{}` depois de conteúdo: falha ao fechar o bloco.
          if (content) {
            _fail(buffer, depth);
            return;
          }
          // Um `{}` no começo só vale como o valor inteiro (com
          // `!important`, que o CSS Syntax tira antes de conferir).
          if (!_onlyImportantFollows(buffer)) {
            _fail(buffer, depth);
            return;
          }
          return; // sintaxe válida; `{}` não é valor de nenhuma propriedade
        case CssTokenType.whitespace:
          buffer.add(t);
        case CssTokenType.badString || CssTokenType.badUrl:
          buffer.add(t);
          bad = true;
          content = true;
        default:
          buffer.add(t);
          content = true;
          if (_opensBlock(t.type) && !_consumeBlock(t, depth + 1, buffer)) {
            poisoned = true;
          }
      }
    }
    if (poisoned || custom) return;
    if (bad) {
      _cssRule('parse-error', cssSample(buffer));
      return;
    }
    // `!important` no fim: `delim !` e `ident important`, espaço no meio.
    var end = buffer.length;
    while (end > valueStart &&
        buffer[end - 1].type == CssTokenType.whitespace) {
      end--;
    }
    var important = false;
    if (end - valueStart >= 2 &&
        buffer[end - 1].type == CssTokenType.ident &&
        cssAsciiEquals(buffer[end - 1].value, 'important')) {
      var bang = end - 2;
      while (bang > valueStart &&
          buffer[bang].type == CssTokenType.whitespace) {
        bang--;
      }
      if (buffer[bang].type == CssTokenType.delim &&
          buffer[bang].value == '!') {
        important = true;
        end = bang;
      }
    }
    out.addAll(
      parseDeclaration(
        cssAsciiLower(first.value),
        buffer.sublist(valueStart, end),
        important: important,
      ),
    );
  }

  /// Depois de um `{}` no começo do valor: lê espaços e um `!important`
  /// opcional (tudo vai para [buffer]) e diz se o valor termina ali (`;`,
  /// `}` ou fim). O primeiro token que sobra também fica no [buffer].
  bool _onlyImportantFollows(List<CssToken> buffer) {
    var stage = 0; // 0: antes do `!`; 1: depois do `!`; 2: depois de important
    while (true) {
      final t = _next();
      final end =
          t.type == CssTokenType.semicolon ||
          t.type == CssTokenType.rightBrace ||
          t.type == CssTokenType.eof;
      if (end && stage != 1) {
        if (t.type == CssTokenType.rightBrace) _reconsume(t);
        return true;
      }
      // O que sobra (inclusive o `;` ou o `}` depois de um `!` solto) volta
      // ao fluxo com o buffer.
      if (t.type != CssTokenType.eof) buffer.add(t);
      if (end) return false;
      if (t.type == CssTokenType.whitespace) continue;
      if (stage == 0 && t.type == CssTokenType.delim && t.value == '!') {
        stage = 1;
      } else if (stage == 1 &&
          t.type == CssTokenType.ident &&
          cssAsciiEquals(t.value, 'important')) {
        stage = 2;
      } else {
        return false;
      }
    }
  }

  /// A tentativa falhou: os tokens dela são relidos como regra qualificada
  /// aninhada, que para no `;` (CSS Syntax "consume a block's contents").
  /// Com prelúdio e bloco, é descartada com `nested-rule`; ao chegar ao `;`
  /// ou ao `}` sem bloco, é lixo (`parse-error`).
  void _fail(List<CssToken> buffer, int depth) {
    _unread(buffer);
    final prelude = <CssToken>[];
    while (true) {
      final t = _next();
      switch (t.type) {
        case CssTokenType.eof || CssTokenType.semicolon:
          _cssRule('parse-error', cssSample(prelude));
          return;
        case CssTokenType.rightBrace:
          _reconsume(t);
          _cssRule('parse-error', cssSample(prelude));
          return;
        case CssTokenType.leftBrace:
          _consumeBlock(t, depth + 1, null);
          _cssRule('nested-rule', cssSample(prelude));
          return;
        default:
          prelude.add(t);
          if (_opensBlock(t.type)) _consumeBlock(t, depth + 1, prelude);
      }
    }
  }
}
