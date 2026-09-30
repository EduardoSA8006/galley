/// Seletores do subconjunto de doc/03 §6 (spec do CSS §6), pela gramática do
/// Selectors Level 4 §4 sobre os tokens do CSS Syntax.
///
/// Linear no tamanho do prelúdio:
/// - uma passada sobre os tokens, com a divisão por vírgula na mesma passada;
/// - passado o 32º composto (ou o 32º seletor simples de um composto), o
///   seletor deixa de ser montado mas o resto do item continua sendo
///   validado, sem guardar nada;
/// - argumentos de pseudo-classe funcional são saltados com uma pilha de
///   fechamentos; a lista de `:not()` e a do `of` do `:nth-child` são
///   validadas por um parser aninhado sobre o mesmo trecho, com no máximo
///   32 níveis, então cada token é visto no máximo duas vezes por nível (a
///   busca do `)` que fecha e o parser do nível);
/// - os hashes de ancestral saem do composto montado (no máximo 4);
/// - `:nth-child` lê o `double` do token e confere a faixa antes de virar
///   `int` (nunca `int.parse`).
library;

import 'tokenizer.dart';

const int maxCompoundsPerSelector = 32;
const int maxSimpleSelectorsPerCompound = 32;

/// Tipo, classe, `id`, nome e valor de atributo (spec do CSS §6.3, #34).
const int maxSelectorIdentifierLength = 256;

/// Maior argumento de `:nth-child(n)` que casa (spec do CSS §6.1).
const int maxNthChild = 1 << 30;

/// Semente do filtro de Bloom por tipo de identificador (spec do CSS §10.4).
const int bloomKindTag = 1;
const int bloomKindClass = 2;
const int bloomKindId = 3;

/// Hash de [lower] (já em minúsculas ASCII) para o filtro de Bloom; o
/// seletor e o elemento usam a mesma função.
int bloomHash(int kind, String lower) => Object.hash(kind, lower);

enum CssCombinator { descendant, child, adjacent }

/// `[a="v"]`: atributo com valor exatamente igual.
final class CssAttributeTest {
  const CssAttributeTest(this.name, this.nameAsWritten, this.value);

  /// Nome no DOM de um elemento HTML, em minúsculas ASCII (`epub:type` para
  /// `[epub|type=…]`).
  final String name;

  /// O nome como escrito, para elemento fora do namespace HTML.
  final String nameAsWritten;

  /// Comparado com diferença de caixa.
  final String value;
}

/// Um composto do subconjunto (≤ [maxSimpleSelectorsPerCompound] seletores
/// simples).
final class CompoundSelector {
  CompoundSelector({
    this.tag,
    this.tagAsWritten,
    this.id,
    List<String> classes = const [],
    List<CssAttributeTest> attributes = const [],
    this.firstChild = false,
    this.lastChild = false,
    this.nthChild,
    int? ids,
    int? pseudoClasses,
    this.impossible = false,
  }) : classes = List.unmodifiable(classes),
       attributes = List.unmodifiable(attributes),
       ids = ids ?? (id == null ? 0 : 1),
       pseudoClasses =
           pseudoClasses ??
           (firstChild ? 1 : 0) +
               (lastChild ? 1 : 0) +
               (nthChild == null ? 0 : 1);

  /// Minúsculas ASCII; `null` = universal ou ausente.
  final String? tag;

  /// Como escrito, para elemento fora do namespace HTML.
  final String? tagAsWritten;
  final String? id;
  final List<String> classes;
  final List<CssAttributeTest> attributes;
  final bool firstChild;
  final bool lastChild;

  /// n ≥ 1; 0 quando o argumento não pode casar (< 1 ou > [maxNthChild],
  /// ou dois `:nth-child` diferentes no composto).
  final int? nthChild;

  /// Quantos `#id` e quantas pseudo-classes o composto escreve, com
  /// repetição: a especificidade conta cada seletor simples (`#a#a` é
  /// (2,0,0); Selectors 4 §17).
  final int ids, pseudoClasses;

  /// O composto nunca casa (`#a#b`: dois `id` diferentes). É válido e fica
  /// no subconjunto, como no navegador.
  final bool impossible;
}

/// Seletor complexo do subconjunto.
final class Selector {
  Selector(List<CompoundSelector> compounds, List<CssCombinator> combinators)
    : assert(combinators.length == compounds.length - 1, 'combinadores'),
      compounds = List.unmodifiable(compounds),
      combinators = List.unmodifiable(combinators),
      specificity = _specificity(compounds),
      ancestorHashes = List.unmodifiable(
        _ancestorHashes(compounds, combinators),
      );

  /// Da esquerda para a direita, ≤ [maxCompoundsPerSelector].
  final List<CompoundSelector> compounds;

  /// `compounds.length - 1`; `combinators[i]` fica entre `compounds[i]` e
  /// `compounds[i + 1]`.
  final List<CssCombinator> combinators;

  /// `(a << 20) | (b << 10) | c`, cada componente saturado em 1023
  /// (Selectors 4 §17).
  final int specificity;

  /// Até 4 hashes ([bloomHash]) de identificadores que precisam estar num
  /// ancestral (spec do CSS §10.4).
  final List<int> ancestorHashes;

  CompoundSelector get rightmost => compounds.last;
}

int _specificity(List<CompoundSelector> compounds) {
  var a = 0, b = 0, c = 0;
  for (final k in compounds) {
    a += k.ids;
    b += k.classes.length + k.attributes.length + k.pseudoClasses;
    if (k.tag != null) c++;
  }
  int sat(int v) => v > 1023 ? 1023 : v;
  return (sat(a) << 20) | (sat(b) << 10) | sat(c);
}

/// Compostos com descendente ou `>` imediatamente à direita são ancestrais
/// do sujeito (um `+` no meio não muda o pai). Da direita para a esquerda;
/// em cada composto, `id`, depois classes, depois tipo.
List<int> _ancestorHashes(
  List<CompoundSelector> compounds,
  List<CssCombinator> combinators,
) {
  final out = <int>[];
  for (var i = compounds.length - 2; i >= 0 && out.length < 4; i--) {
    if (combinators[i] == CssCombinator.adjacent) continue;
    final k = compounds[i];
    final id = k.id;
    if (id != null && out.length < 4) {
      out.add(bloomHash(bloomKindId, cssAsciiLower(id)));
    }
    for (final c in k.classes) {
      if (out.length == 4) break;
      out.add(bloomHash(bloomKindClass, cssAsciiLower(c)));
    }
    final tag = k.tag;
    if (tag != null && out.length < 4) out.add(bloomHash(bloomKindTag, tag));
  }
  return out;
}

/// Resultado de [parseSelectorList].
sealed class SelectorListParse {}

/// A gramática aceitou a lista inteira. [selectors] tem só os do
/// subconjunto (pode ser vazia); os outros caíram.
final class SelectorList extends SelectorListParse {
  SelectorList(
    List<Selector> selectors,
    this.unsupported,
    this.unsupportedSample,
  ) : selectors = List.unmodifiable(selectors);

  final List<Selector> selectors;

  /// Quantos seletores da lista caíram por estar fora do subconjunto.
  final int unsupported;

  /// O primeiro que caiu, truncado em [maxSampleLength].
  final String? unsupportedSample;
}

/// Algum seletor da lista é inválido: a regra inteira cai (Selectors 4 §4.1:
/// a lista não é tolerante).
final class SelectorInvalid extends SelectorListParse {
  SelectorInvalid(this.sample);

  /// O prelúdio, truncado em [maxSampleLength].
  final String sample;
}

/// Pseudo-classes reconhecidas sem argumento (spec do CSS §6.3); as formas
/// antigas de pseudo-elemento com um `:` entram aqui.
const Set<String> _pseudoClasses = {
  'first-child', 'last-child', 'only-child', 'first-of-type', //
  'last-of-type', 'only-of-type', 'root', 'empty', 'link', 'visited',
  'any-link', 'local-link', 'target', 'target-within', 'scope', 'hover',
  'active', 'focus', 'focus-visible', 'focus-within', 'enabled', 'disabled',
  'checked', 'indeterminate', 'default', 'required', 'optional', 'valid',
  'invalid', 'in-range', 'out-of-range', 'read-only', 'read-write',
  'placeholder-shown', 'defined', 'fullscreen', 'playing', 'paused',
  'before', 'after', 'first-line', 'first-letter',
};

/// Pseudo-classes funcionais reconhecidas.
const Set<String> _functionalPseudoClasses = {
  'nth-child', 'nth-last-child', 'nth-of-type', 'nth-last-of-type', //
  'not', 'is', 'where', 'has', 'lang', 'dir',
};

/// Formas antigas de pseudo-elemento com um `:` (Selectors 4 §3.6.1): são
/// pseudo-elementos, e nada pode vir depois delas no composto.
const Set<String> _legacyPseudoElements = {
  'before',
  'after',
  'first-line',
  'first-letter',
};

/// Pseudo-elementos reconhecidos (com `::`).
const Set<String> _pseudoElements = {
  'before', 'after', 'first-line', 'first-letter', 'marker', 'selection', //
  'placeholder', 'backdrop', 'cue', 'file-selector-button',
};

/// Destino de um item da lista.
enum _Fate { supported, unsupported, invalid }

/// [prelude]: os tokens entre o fim da regra anterior e o `{`, com os
/// blocos balanceados pelo parser. [namespaces]: os prefixos declarados por
/// `@namespace` na folha; um prefixo que não está nele torna o seletor
/// inválido (CSS Namespaces 3 §5; Selectors 4 §5.2).
SelectorListParse parseSelectorList(
  List<CssToken> prelude, {
  Set<String> namespaces = const {},
}) => _SelectorParser(prelude, namespaces, 0, prelude.length, 0).parseList();

final class _SelectorParser {
  _SelectorParser(
    this._t,
    this._namespaces,
    this._i,
    this._end,
    this._depth, {
    this._noPseudoElements = false,
  });

  final List<CssToken> _t;
  final Set<String> _namespaces;
  int _i;

  /// Fim (exclusivo) dos tokens desta lista: o `)` de um `:not()` ou de um
  /// `of`, ou o fim do prelúdio.
  final int _end;

  /// Listas aninhadas (`:not(:not(…))`, `of`): no máximo [_maxDepth].
  final int _depth;

  /// Dentro de `:not()`: pseudo-elemento torna a lista inválida (é
  /// `<complex-real-selector-list>`; o `of` do `:nth-child` aceita, como no
  /// Chromium).
  final bool _noPseudoElements;
  static const int _maxDepth = 32;

  CssTokenType _typeAt(int at) => at < _end ? _t[at].type : CssTokenType.eof;

  bool _delimAt(int at, String c) =>
      _typeAt(at) == CssTokenType.delim && _t[at].value == c;

  bool _skipWhitespace() {
    final start = _i;
    while (_typeAt(_i) == CssTokenType.whitespace) {
      _i++;
    }
    return _i > start;
  }

  bool get _atItemEnd {
    final type = _typeAt(_i);
    return type == CssTokenType.eof || type == CssTokenType.comma;
  }

  SelectorListParse parseList() {
    final first = _i;
    final selectors = <Selector>[];
    var unsupported = 0;
    String? sample;
    while (true) {
      _skipWhitespace();
      final start = _i;
      final (fate, selector) = _complex();
      if (fate == _Fate.invalid) {
        return SelectorInvalid(cssSample(_t, first, _end));
      }
      if (fate == _Fate.supported) {
        selectors.add(selector!);
      } else {
        unsupported++;
        sample ??= cssSample(_t, start, _i);
      }
      if (_typeAt(_i) == CssTokenType.eof) break;
      _i++; // vírgula
    }
    return SelectorList(selectors, unsupported, sample);
  }

  /// Um seletor complexo até a vírgula de topo ou o fim.
  (_Fate, Selector?) _complex() {
    if (_atItemEnd) return (_Fate.invalid, null);
    final compounds = <CompoundSelector>[];
    final combinators = <CssCombinator>[];
    var supported = true;
    var count = 0;
    while (true) {
      count++;
      final building = supported && count <= maxCompoundsPerSelector;
      final (fate, compound) = _compound(build: building);
      if (fate == _Fate.invalid) return (_Fate.invalid, null);
      if (fate == _Fate.unsupported || count > maxCompoundsPerSelector) {
        supported = false;
      }
      if (supported) compounds.add(compound!);
      final sawSpace = _skipWhitespace();
      if (_atItemEnd) break;
      // Nada combina depois de um pseudo-elemento (Selectors 4 §3.6).
      if (_endedWithPseudoElement) return (_Fate.invalid, null);
      CssCombinator? combinator;
      var explicit = true;
      if (_delimAt(_i, '>')) {
        combinator = CssCombinator.child;
      } else if (_delimAt(_i, '+')) {
        combinator = CssCombinator.adjacent;
      } else if (_delimAt(_i, '~')) {
        supported = false; // irmão geral: válido, fora do subconjunto
      } else if (sawSpace) {
        combinator = CssCombinator.descendant;
        explicit = false;
      } else {
        return (_Fate.invalid, null);
      }
      if (explicit) {
        _i++;
        _skipWhitespace();
        if (_atItemEnd) return (_Fate.invalid, null);
      }
      if (supported) combinators.add(combinator!);
    }
    if (!supported) return (_Fate.unsupported, null);
    return (_Fate.supported, Selector(compounds, combinators));
  }

  /// O último composto lido terminou num pseudo-elemento.
  bool _endedWithPseudoElement = false;

  /// Um composto. Com [build] falso só valida.
  (_Fate, CompoundSelector?) _compound({required bool build}) {
    var supported = true;
    var simple = 0;
    String? tag;
    String? tagAsWritten;
    String? id;
    var ids = 0, pseudoClasses = 0;
    var impossible = false;
    final classes = <String>[];
    final attributes = <CssAttributeTest>[];
    var firstChild = false, lastChild = false;
    int? nthChild;
    var any = false;
    // O pseudo-elemento do composto; depois dele só vale `::marker` depois
    // de `::before`/`::after` (CSS Pseudo 4 §3.1).
    String? pseudoElement;
    _endedWithPseudoElement = false;

    bool tooLong(String s) => s.length > maxSelectorIdentifierLength;

    // Seletor de tipo (Selectors 4 §5.1), com namespace opcional (§5.2).
    final type = _typeAt(_i);
    final star = _delimAt(_i, '*');
    if (type == CssTokenType.ident || star) {
      if (_delimAt(_i + 1, '|') &&
          (_typeAt(_i + 2) == CssTokenType.ident || _delimAt(_i + 2, '*'))) {
        // svg|rect, *|p: prefixo não declarado é inválido.
        if (!star && !_namespaces.contains(_t[_i].value)) {
          return (_Fate.invalid, null);
        }
        supported = false;
        _i += 3;
      } else {
        if (!star) {
          tagAsWritten = _t[_i].value;
          tag = cssAsciiLower(tagAsWritten);
          if (tooLong(tag)) supported = false;
        }
        _i++;
      }
      simple++;
      any = true;
    } else if (_delimAt(_i, '|') &&
        (_typeAt(_i + 1) == CssTokenType.ident || _delimAt(_i + 1, '*'))) {
      supported = false; // |p
      _i += 2;
      simple++;
      any = true;
    }

    while (true) {
      final t = _typeAt(_i);
      final startsSimple =
          t == CssTokenType.hash ||
          t == CssTokenType.leftBracket ||
          t == CssTokenType.colon ||
          _delimAt(_i, '.');
      if (!startsSimple) break;
      if (pseudoElement != null &&
          !(t == CssTokenType.colon &&
              _typeAt(_i + 1) == CssTokenType.colon &&
              _typeAt(_i + 2) == CssTokenType.ident &&
              cssAsciiLower(_t[_i + 2].value) == 'marker' &&
              (pseudoElement == 'before' || pseudoElement == 'after'))) {
        return (_Fate.invalid, null);
      }
      if (t == CssTokenType.hash) {
        if (!_t[_i].isIdHash) return (_Fate.invalid, null);
        final value = _t[_i].value;
        if (tooLong(value)) supported = false;
        if (id != null && id != value) impossible = true; // #a#b nunca casa
        id = value;
        ids++;
        _i++;
      } else if (_delimAt(_i, '.')) {
        if (_typeAt(_i + 1) != CssTokenType.ident) {
          return (_Fate.invalid, null);
        }
        final value = _t[_i + 1].value;
        if (tooLong(value)) supported = false;
        if (build && supported && simple < maxSimpleSelectorsPerCompound) {
          classes.add(value);
        }
        _i += 2;
      } else if (t == CssTokenType.leftBracket) {
        final attribute = _attribute();
        if (attribute == null) return (_Fate.invalid, null);
        final (fate, test) = attribute;
        if (fate == _Fate.unsupported) supported = false;
        if (build && supported && test != null) attributes.add(test);
      } else {
        if (_typeAt(_i + 1) == CssTokenType.colon) {
          _i += 2;
          final name = _pseudoElement();
          if (name == null || _noPseudoElements) return (_Fate.invalid, null);
          pseudoElement = name;
          supported = false;
        } else {
          _i++;
          final pseudo = _pseudoClass();
          switch (pseudo) {
            case _Pseudo.invalid:
              return (_Fate.invalid, null);
            case _Pseudo.legacyElement:
              if (_noPseudoElements) return (_Fate.invalid, null);
              pseudoElement = _pseudoName;
              supported = false;
            case _Pseudo.unsupported:
              supported = false;
            case _Pseudo.firstChild:
              firstChild = true;
              pseudoClasses++;
            case _Pseudo.lastChild:
              lastChild = true;
              pseudoClasses++;
            case _Pseudo.nthChild:
              // Dois :nth-child diferentes nunca casam.
              final n = nthChild;
              nthChild = n == null || n == _nthValue ? _nthValue : 0;
              pseudoClasses++;
          }
        }
      }
      simple++;
      any = true;
    }
    _endedWithPseudoElement = pseudoElement != null;
    if (!any) return (_Fate.invalid, null);
    if (simple > maxSimpleSelectorsPerCompound) supported = false;
    if (!supported) return (_Fate.unsupported, null);
    if (!build) return (_Fate.supported, null);
    return (
      _Fate.supported,
      CompoundSelector(
        tag: tag,
        tagAsWritten: tagAsWritten,
        id: id,
        classes: classes,
        attributes: attributes,
        firstChild: firstChild,
        lastChild: lastChild,
        nthChild: nthChild,
        ids: ids,
        pseudoClasses: pseudoClasses,
        impossible: impossible,
      ),
    );
  }

  /// `[…]` a partir do `[` (Selectors 4 §6). `null` = inválido; senão o
  /// destino e o teste (só `[a=v]` está no subconjunto).
  (_Fate, CssAttributeTest?)? _attribute() {
    _i++; // [
    _skipWhitespace();
    String name;
    var supported = true;
    if (_typeAt(_i) == CssTokenType.ident) {
      if (_delimAt(_i + 1, '|') && _typeAt(_i + 2) == CssTokenType.ident) {
        // epub|type → epub:type, se `@namespace epub` foi declarado.
        if (!_namespaces.contains(_t[_i].value)) return null;
        name = '${_t[_i].value}:${_t[_i + 2].value}';
        _i += 3;
      } else {
        name = _t[_i].value;
        _i++;
      }
    } else if (_delimAt(_i, '*') &&
        _delimAt(_i + 1, '|') &&
        _typeAt(_i + 2) == CssTokenType.ident) {
      supported = false; // [*|a]
      name = _t[_i + 2].value;
      _i += 3;
    } else if (_delimAt(_i, '|') && _typeAt(_i + 1) == CssTokenType.ident) {
      name = _t[_i + 1].value; // [|a]: sem prefixo
      _i += 2;
    } else {
      return null;
    }
    if (name.length > maxSelectorIdentifierLength) supported = false;
    _skipWhitespace();
    if (_typeAt(_i) == CssTokenType.rightBracket) {
      _i++;
      return (_Fate.unsupported, null); // presença
    }
    if (_delimAt(_i, '=')) {
      _i++;
    } else if (_typeAt(_i) == CssTokenType.delim &&
        const {'~', '|', '^', r'$', '*'}.contains(_t[_i].value) &&
        _delimAt(_i + 1, '=')) {
      supported = false;
      _i += 2;
    } else {
      return null;
    }
    _skipWhitespace();
    final valueType = _typeAt(_i);
    if (valueType != CssTokenType.ident && valueType != CssTokenType.string) {
      return null;
    }
    final value = _t[_i].value;
    if (value.length > maxSelectorIdentifierLength) supported = false;
    _i++;
    _skipWhitespace();
    if (_typeAt(_i) == CssTokenType.ident) {
      final flag = cssAsciiLower(_t[_i].value);
      if (flag != 'i' && flag != 's') return null;
      supported = false;
      _i++;
      _skipWhitespace();
    }
    if (_typeAt(_i) != CssTokenType.rightBracket) return null;
    _i++;
    if (!supported) return (_Fate.unsupported, null);
    return (
      _Fate.supported,
      CssAttributeTest(cssAsciiLower(name), name, value),
    );
  }

  /// Argumento de `:nth-child(n)` no subconjunto, lido por [_pseudoClass].
  int _nthValue = 0;

  /// Nome da forma antiga de pseudo-elemento lida por [_pseudoClass].
  String _pseudoName = '';

  /// Depois de `:`.
  _Pseudo _pseudoClass() {
    final type = _typeAt(_i);
    if (type == CssTokenType.ident) {
      final name = cssAsciiLower(_t[_i].value);
      _i++;
      if (!_pseudoClasses.contains(name)) return _Pseudo.invalid;
      if (_legacyPseudoElements.contains(name)) {
        _pseudoName = name;
        return _Pseudo.legacyElement;
      }
      if (name == 'first-child') return _Pseudo.firstChild;
      if (name == 'last-child') return _Pseudo.lastChild;
      return _Pseudo.unsupported;
    }
    if (type != CssTokenType.function) return _Pseudo.invalid;
    final name = cssAsciiLower(_t[_i].value);
    _i++;
    if (!_functionalPseudoClasses.contains(name)) return _Pseudo.invalid;
    final start = _i;
    final end = _closeOf(start);
    if (end < 0) return _Pseudo.invalid;
    _i = end + 1;
    switch (name) {
      // Lista de seletores não tolerante: vazia ou inválida derruba.
      case 'not':
        return _isSelectorList(start, end, noPseudoElements: true)
            ? _Pseudo.unsupported
            : _Pseudo.invalid;
      // Lista tolerante (Selectors 4 §4.2): qualquer conteúdo vale.
      case 'is' || 'where':
        return _Pseudo.unsupported;
      // Argumento obrigatório, não validado a fundo.
      case 'has' || 'lang' || 'dir':
        return _hasContent(start, end) ? _Pseudo.unsupported : _Pseudo.invalid;
    }
    final allowOf = name == 'nth-child' || name == 'nth-last-child';
    final anb = _anPlusB(start, end, allowOf: allowOf);
    if (anb == null) return _Pseudo.invalid;
    if (name != 'nth-child' || !anb.integerOnly) return _Pseudo.unsupported;
    final n = anb.b;
    _nthValue = n >= 1 && n <= maxNthChild ? n.toInt() : 0;
    return _Pseudo.nthChild;
  }

  /// Depois de `::`: o nome do pseudo-elemento, ou `null` se inválido.
  String? _pseudoElement() {
    final type = _typeAt(_i);
    if (type == CssTokenType.ident) {
      final name = cssAsciiLower(_t[_i].value);
      _i++;
      return _pseudoElements.contains(name) ? name : null;
    }
    if (type == CssTokenType.function && cssAsciiLower(_t[_i].value) == 'cue') {
      final end = _closeOf(_i + 1);
      if (end < 0) return null;
      _i = end + 1;
      return 'cue';
    }
    return null;
  }

  /// Os tokens `[start, end)` são uma lista de seletores válida (uma lista
  /// aninhada, até [_maxDepth] níveis; cada nível percorre os seus tokens).
  bool _isSelectorList(int start, int end, {bool noPseudoElements = false}) {
    if (_depth >= _maxDepth) return false;
    final inner = _SelectorParser(
      _t,
      _namespaces,
      start,
      end,
      _depth + 1,
      noPseudoElements: noPseudoElements,
    );
    return inner.parseList() is! SelectorInvalid;
  }

  bool _hasContent(int start, int end) {
    for (var i = start; i < end; i++) {
      if (_t[i].type != CssTokenType.whitespace) return true;
    }
    return false;
  }

  /// Índice do `)` que fecha a função cujo primeiro token de argumento está
  /// em [start]; -1 se não fecha. Um fechamento que não é o do topo da pilha
  /// é só um token (CSS Syntax §5.4.8).
  int _closeOf(int start) {
    final stack = <CssTokenType>[CssTokenType.rightParen];
    for (var i = start; i < _end; i++) {
      final type = _t[i].type;
      switch (type) {
        case CssTokenType.function || CssTokenType.leftParen:
          stack.add(CssTokenType.rightParen);
        case CssTokenType.leftBracket:
          stack.add(CssTokenType.rightBracket);
        case CssTokenType.leftBrace:
          stack.add(CssTokenType.rightBrace);
        case CssTokenType.rightParen ||
            CssTokenType.rightBracket ||
            CssTokenType.rightBrace:
          if (stack.last == type) {
            stack.removeLast();
            if (stack.isEmpty) return i;
          }
        default:
          break;
      }
    }
    return -1;
  }

  /// Microsintaxe An+B do CSS Syntax §6.2 sobre os tokens `[start, end)`,
  /// com `of <seletores>` opcional (Selectors 4 §14.4). `null` = inválido.
  _AnB? _anPlusB(int start, int end, {required bool allowOf}) {
    var i = start;
    bool ws() {
      final s = i;
      while (i < end && _t[i].type == CssTokenType.whitespace) {
        i++;
      }
      return i > s;
    }

    CssToken? at() => i < end ? _t[i] : null;
    bool isInt(CssToken? t) =>
        t != null && t.type == CssTokenType.number && t.isInteger;
    bool signed(CssToken t) =>
        t.value.startsWith('+') || t.value.startsWith('-');
    bool dashDigits(String s, int from) {
      if (s.length <= from) return false;
      for (var k = from; k < s.length; k++) {
        final c = s.codeUnitAt(k);
        if (c < 0x30 || c > 0x39) return false;
      }
      return true;
    }

    // Depois de "n" (ou "-n", "+n", "<n-dimension>"): nada, <signed-integer>
    // ou ['+' | '-'] <signless-integer>.
    bool afterN() {
      ws();
      final t = at();
      if (t == null || _isOfStart(i, end)) return true;
      if (isInt(t) && signed(t)) {
        i++;
        return true;
      }
      if (t.type == CssTokenType.delim && (t.value == '+' || t.value == '-')) {
        i++;
        ws();
        final u = at();
        if (!isInt(u) || signed(u!)) return false;
        i++;
        return true;
      }
      return false;
    }

    // Depois de "n-" (ou "-n-", "<ndash-dimension>"): <signless-integer>.
    bool afterNDash() {
      ws();
      final u = at();
      if (!isInt(u) || signed(u!)) return false;
      i++;
      return true;
    }

    ws();
    final t = at();
    if (t == null) return null;
    var integerOnly = false;
    var b = 0.0;
    var ok = false;
    switch (t.type) {
      case CssTokenType.number:
        if (!t.isInteger) return null;
        i++;
        integerOnly = true;
        b = t.number;
        ok = true;
      case CssTokenType.ident:
        final v = cssAsciiLower(t.value);
        i++;
        if (v == 'odd' || v == 'even') {
          ok = true;
        } else if (v == 'n' || v == '-n') {
          ok = afterN();
        } else if (v == 'n-' || v == '-n-') {
          ok = afterNDash();
        } else if (v.startsWith('n-')) {
          ok = dashDigits(v, 2);
        } else if (v.startsWith('-n-')) {
          ok = dashDigits(v, 3);
        }
      case CssTokenType.delim when t.value == '+':
        // '+'? seguido direto (sem espaço) de n, n- ou n-<dígitos>.
        final u = i + 1 < end ? _t[i + 1] : null;
        if (u == null || u.type != CssTokenType.ident) return null;
        final v = cssAsciiLower(u.value);
        i += 2;
        if (v == 'n') {
          ok = afterN();
        } else if (v == 'n-') {
          ok = afterNDash();
        } else if (v.startsWith('n-')) {
          ok = dashDigits(v, 2);
        }
      case CssTokenType.dimension:
        if (!t.isInteger) return null;
        i++;
        final u = t.unit;
        if (u == 'n') {
          ok = afterN();
        } else if (u == 'n-') {
          ok = afterNDash();
        } else if (u.startsWith('n-')) {
          ok = dashDigits(u, 2);
        }
      default:
        return null;
    }
    if (!ok) return null;
    ws();
    if (i == end) return _AnB(integerOnly: integerOnly, b: b);
    if (!allowOf || !_isOfStart(i, end)) return null;
    // `of <seletores>`: fora do subconjunto, mas a lista tem de ser válida.
    i++;
    if (!_isSelectorList(i, end)) return null;
    return _AnB(integerOnly: false, b: b);
  }

  bool _isOfStart(int i, int end) =>
      i < end &&
      _t[i].type == CssTokenType.ident &&
      cssAsciiLower(_t[i].value) == 'of';
}

enum _Pseudo {
  invalid,
  unsupported,
  legacyElement,
  firstChild,
  lastChild,
  nthChild,
}

final class _AnB {
  const _AnB({required this.integerOnly, required this.b});

  /// Só um `<integer>`: a forma do subconjunto.
  final bool integerOnly;
  final double b;
}
