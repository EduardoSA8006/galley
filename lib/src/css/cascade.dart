/// Cascata de uma seção (spec do CSS §10): caminhada, casamento pelo índice,
/// disputa por slot, herança, propagação de `text-decoration` e o
/// `ComputedStyle` internado de cada elemento.
///
/// Linear na seção:
/// - a caminhada visita cada nó uma vez (pilha explícita, sem recursão, sem
///   `children` indexado); cada [ElementInfo] é montado uma vez, quando ele
///   é visitado, e o custo de montá-lo entra na cessão antes do trabalho
///   seguinte (o total de irmãos sai de uma passada que só testa o tipo dos
///   nós);
/// - classes do elemento num `Set`: `class="a a a …"` não visita o balde `a`
///   N vezes;
/// - todo o trabalho das regras do livro paga orçamento (consulta a balde,
///   candidato — inclusive o rejeitado pelo Bloom —, seletor simples,
///   declaração), cada passo O(1): o casamento do livro custa O(2^22) por
///   seção, e o resto — folha padrão, dicas, `style=""` — é O(elementos +
///   texto dos atributos);
/// - a cascata não ordena: uma comparação por declaração casada, num vetor de
///   `CssProperty.values.length` slots zerado em O(1) por geração;
/// - internação e `style=""` são mapas: O(campos) e O(texto) uma vez por
///   texto;
/// - profundidade do DOM sem limite na caminhada, casamento só até
///   [maxCascadeDepth].
library;

import 'dart:typed_data';

import 'package:html/dom.dart';
import 'package:meta/meta.dart';

import '../diagnostics/diagnostic.dart';
import '../diagnostics/exceptions.dart';
import 'computed_style.dart';
import 'loader.dart';
import 'matcher.dart';
import 'parser.dart';
import 'properties.dart';
import 'rule_index.dart';
import 'tokenizer.dart';

/// A raiz `html` tem profundidade 1.
const int maxCascadeDepth = 256;

/// Passos das regras do livro por seção: o maior uso real no corpus é
/// 71 525 (`song-of-myself.xhtml`), ~58× abaixo; esgotado, custa ~0,25 s no
/// desktop (JIT).
const int cascadeBudget = 1 << 22;

/// Um `yield` a cada este número de passos de todo o trabalho.
const int cascadeYieldSteps = 4096;

/// Texto de um `style=""`, em unidades de código.
const int maxStyleAttributeLength = 8 * 1024;

/// Recebe o resultado de [computeStyles] (decisão da spec #20).
final class CascadeResult {
  SectionStyles? _styles;

  /// `StateError` antes de o gerador terminar.
  SectionStyles get styles =>
      _styles ??
      (throw StateError('computeStyles ainda não terminou de ser drenado'));
}

/// Resultado da cascata de uma seção.
final class SectionStyles {
  SectionStyles._(this._styles, this._origins, this.budgetExhausted);

  final Map<Element, ComputedStyle> _styles;
  final Map<Element, List<CssOrigin?>>? _origins;

  /// O orçamento de §10.6 acabou; o resto da seção teve só a folha padrão,
  /// as dicas de §8.2 e os `style=""`.
  final bool budgetExhausted;

  /// Estilo de [element], ou `null` se ele não é do documento processado.
  ComputedStyle? styleOf(Element element) => _styles[element];

  /// Elementos com estilo: todos os do documento fora da subárvore de
  /// `<template>`, inclusive os de `display: none` e os abaixo da
  /// profundidade de casamento.
  int get length => _styles.length;

  /// Origem da declaração que venceu [property] em [element]; `null` quando
  /// o valor veio de herança ou do inicial. Só com `recordOrigins: true`;
  /// senão lança `StateError` — é API de teste.
  CssOrigin? originOf(Element element, CssProperty property) {
    final origins = _origins;
    if (origins == null) {
      throw StateError('originOf exige computeStyles(recordOrigins: true)');
    }
    return origins[element]?[property.index];
  }
}

/// Cascata da seção (doc/08 §1): um `yield` a cada [cascadeYieldSteps]
/// passos (§10.6). Ao terminar, [into] recebe o resultado. Não muda o DOM.
/// [budget] existe para os testes das bordas do orçamento; [onYield], para os
/// da cessão: recebe o total de passos a cada `yield` e uma vez no fim.
Iterable<void> computeStyles(
  Document document,
  SectionSheets sheets, {
  required String sectionPath,
  required DiagnosticSink sink,
  required CascadeResult into,
  bool recordOrigins = false,
  int budget = cascadeBudget,
  @visibleForTesting void Function(int steps)? onYield,
}) sync* {
  final cascade = _Cascade(
    sheets,
    sectionPath,
    sink,
    recordOrigins,
    budget,
    onYield,
  );
  yield* cascade.run(document);
  onYield?.call(cascade._steps.total);
  into._styles = cascade.result();
}

/// Drena [computeStyles] (testes e chamadores síncronos).
SectionStyles computeStylesSync(
  Document document,
  SectionSheets sheets, {
  required String sectionPath,
  required DiagnosticSink sink,
  bool recordOrigins = false,
  int budget = cascadeBudget,
}) {
  final into = CascadeResult();
  for (final _ in computeStyles(
    document,
    sheets,
    sectionPath: sectionPath,
    sink: sink,
    into: into,
    recordOrigins: recordOrigins,
    budget: budget,
  )) {}
  return into.styles;
}

/// Um nível da caminhada: os filhos do pai, montados um a um, e o estilo
/// do pai.
final class _Frame {
  _Frame(this.children, this.parentStyle);

  final ChildCursor children;
  final ComputedStyle parentStyle;
}

/// Camadas de origem e importância (CSS Cascade 4 §6.1; spec §10.5).
const int _layerUserAgent = 0;
const int _layerAuthor = 1;
const int _layerAuthorImportant = 2;
const int _layerUserAgentImportant = 3;

/// Especificidade (0,1,0) das dicas de §8.2 e `seq` depois das regras da
/// folha padrão.
const int _hintSpecificity = 1 << 10;
const int _hintSeq = 1 << 30;

final class _Cascade {
  _Cascade(
    SectionSheets sheets,
    this._section,
    this._sink,
    this._recordOrigins,
    int budget,
    this._onYield,
  ) : _steps = MatchSteps(budget),
      _book = RuleIndex([
        for (final s in sheets.sheets)
          for (final r in s.sheet.rules) (r, CssOrigin.author, s.href),
      ]);

  final String _section;
  final DiagnosticSink _sink;
  final bool _recordOrigins;
  final void Function(int steps)? _onYield;
  final MatchSteps _steps;
  final RuleIndex _book;
  final AncestorFilter _filter = AncestorFilter();

  final Map<Element, ComputedStyle> _styles = Map.identity();
  final Map<Element, List<CssOrigin?>> _originMap = Map.identity();
  final Map<ComputedStyle, ComputedStyle> _intern = {};
  final Map<String, (List<Declaration>, int)> _styleAttributes = {};

  bool _bookExhausted = false;
  bool _domDepthEmitted = false;
  bool _styleTooLargeEmitted = false;
  int _styleParseErrors = 0;
  final Set<String> _degradedEmitted = {};
  int _nextYield = cascadeYieldSteps;

  // Slots, um por CssProperty; válidos quando _gen[p] == _generation.
  static final int _n = CssProperty.values.length;
  final List<Declaration?> _winner = List.filled(_n, null);
  final Int32List _layer = Int32List(_n);
  final Int32List _attached = Int32List(_n);
  final Int32List _specificity = Int32List(_n);
  final Int32List _seq = Int32List(_n);
  final List<CssOrigin> _origin = List.filled(_n, CssOrigin.userAgent);
  final Int32List _gen = Int32List(_n);
  int _generation = 0;

  SectionStyles result() => SectionStyles._(
    _styles,
    _recordOrigins ? _originMap : null,
    _bookExhausted,
  );

  void _emit(
    EpubDiagnosticCode code,
    String href,
    String message,
    Map<String, Object?> details,
  ) => _sink.emit(
    code,
    href: href,
    message: message,
    details: details,
    onStrict: (m) => EpubSectionParseException(m, href: href),
  );

  /// `yield` a cada [cascadeYieldSteps] passos de todo o trabalho. A
  /// próxima janela começa no total de agora: depois de um salto grande (um
  /// elemento de `class` enorme, um `style=""` novo), uma cessão só, e não
  /// uma rajada de `yield` vazios.
  bool get _shouldYield {
    final total = _steps.total;
    if (total < _nextYield) return false;
    _nextYield = total + cascadeYieldSteps;
    _onYield?.call(total);
    return true;
  }

  Iterable<void> run(Document document) sync* {
    final truncated = _book.truncatedAt;
    if (truncated != null) {
      _emit(
        EpubDiagnosticCode.stylesheetIgnored,
        truncated,
        'teto de $maxRulesPerSection seletores por seção atingido',
        {'reason': 'limit', 'limit': 'rules'},
      );
    }
    final root = document.documentElement;
    if (root != null) {
      final frames = <_Frame>[
        _Frame(ChildCursor.root(root, _steps), ComputedStyle.initial),
      ];
      while (frames.isNotEmpty) {
        final frame = frames.last;
        // Monta o próximo irmão e soma o custo de montá-lo (doc/08 §3).
        final e = frame.children.next();
        if (e == null) {
          frames.removeLast();
          final parent = frame.children.parent;
          if (parent != null && parent.depth < maxCascadeDepth) {
            _filter.pop(parent);
          }
          continue;
        }
        if (_shouldYield) yield null;
        final ComputedStyle style;
        if (e.depth > maxCascadeDepth) {
          style = _deep(e, frame.parentStyle);
        } else {
          yield* _match(e);
          style = _resolve(e, frame.parentStyle);
        }
        _styles[e.element] = _intern.putIfAbsent(style, () => style);
        if (!e.isTemplate && e.element.nodes.isNotEmpty) {
          final children = ChildCursor(e, _steps);
          if (children.count > 0) {
            if (e.depth < maxCascadeDepth) _filter.push(e);
            frames.add(_Frame(children, style));
          }
        }
        if (_shouldYield) yield null;
      }
    }
    if (_styleParseErrors > 0) {
      _emit(
        EpubDiagnosticCode.cssRuleIgnored,
        _section,
        'declarações de style="" descartadas por sintaxe',
        {
          'reason': 'parse-error',
          'discarded': _styleParseErrors,
          'source': 'style-attribute',
        },
      );
    }
  }

  /// Estilo "herdado puro" abaixo de [maxCascadeDepth] (#17): herdadas
  /// copiadas, não herdadas no inicial, sem casar regras nem ler `style=""`.
  ComputedStyle _deep(ElementInfo e, ComputedStyle p) {
    if (!_domDepthEmitted) {
      _domDepthEmitted = true;
      _emit(
        EpubDiagnosticCode.stylesheetIgnored,
        _section,
        'elementos abaixo da profundidade $maxCascadeDepth sem casamento',
        {'reason': 'limit', 'limit': 'dom-depth'},
      );
    }
    if (_recordOrigins) _originMap[e.element] = List.filled(_n, null);
    return ComputedStyle(
      whiteSpace: p.whiteSpace,
      direction: p.direction,
      listStyleType: p.listStyleType,
      alignKeyword: p.alignKeyword,
      underline: p.underline,
      lineThrough: p.lineThrough,
      fontStyle: p.fontStyle,
      weight: p.weight,
      fontVariant: p.fontVariant,
      textTransform: p.textTransform,
      textIndent: p.textIndent,
    );
  }

  /// Casa o livro, a folha padrão, as dicas e o `style=""` de [e] nos slots.
  Iterable<void> _match(ElementInfo e) sync* {
    _generation++;
    if (!_bookExhausted && _book.length > 0) {
      _steps.bookMode = true;
      yield* _matchIndex(_book, e, book: true);
      _steps.bookMode = false;
      if (_steps.exhausted) {
        // O elemento em andamento recomeça sem o livro (#31), e o resto da
        // seção fica sem ele (#18).
        _bookExhausted = true;
        _generation++;
        _emit(
          EpubDiagnosticCode.stylesheetIgnored,
          _section,
          'orçamento da cascata esgotado',
          {'reason': 'budget'},
        );
      }
    }
    yield* _matchIndex(userAgentIndex, e, book: false);
    _hints(e);
    _styleAttribute(e);
  }

  /// Candidatos de [e] em [index]: o balde do `id`, um por classe, o do tipo
  /// e o universal (§10.3). Cada consulta custa um passo; no livro, para no
  /// primeiro passo além do orçamento. Cede entre candidatos sem criar um
  /// gerador por balde: [_candidates] devolve onde parou.
  Iterable<void> _matchIndex(
    RuleIndex index,
    ElementInfo e, {
    required bool book,
  }) sync* {
    final id = e.id;
    // As consultas são O(1) cada e O(classes do elemento) no total; o passo
    // de cada uma é contado ao percorrê-la.
    final buckets = [
      if (id != null) index.byId(id),
      for (final c in e.classes) index.byClass(c),
      index.byTag(e.lowerName),
      index.universal,
    ];
    for (final entries in buckets) {
      _steps.add(1);
      if (book && _steps.exhausted) return;
      // Cede também entre baldes vazios: 150 000 classes são 150 000
      // consultas.
      if (_shouldYield) yield null;
      var next = 0;
      while (next < entries.length) {
        next = _candidates(entries, next, e, book: book);
        if (book && _steps.exhausted) return;
        if (_shouldYield) yield null;
      }
    }
  }

  /// Testa `entries[from…]` até o fim, até o orçamento do livro acabar ou até
  /// a hora de ceder; devolve o índice do próximo candidato.
  int _candidates(
    List<RuleEntry> entries,
    int from,
    ElementInfo e, {
    required bool book,
  }) {
    for (var k = from; k < entries.length; k++) {
      final entry = entries[k];
      _steps.add(1);
      if (book && _steps.exhausted) return k + 1;
      if (_candidateMatches(entry, e)) {
        final declarations = entry.declarations;
        for (var i = 0; i < declarations.length; i++) {
          _steps.add(1);
          if (book && _steps.exhausted) return k + 1;
          final d = declarations[i];
          _apply(
            d,
            layer: entry.origin == CssOrigin.userAgent
                ? (d.important ? _layerUserAgentImportant : _layerUserAgent)
                : (d.important ? _layerAuthorImportant : _layerAuthor),
            attached: 0,
            specificity: entry.selector.specificity,
            seq: entry.seqBase + i,
            origin: entry.origin,
          );
        }
      }
      if (book && _steps.exhausted) return k + 1;
      if (_steps.total >= _nextYield) return k + 1;
    }
    return entries.length;
  }

  bool _candidateMatches(RuleEntry entry, ElementInfo e) {
    for (final h in entry.selector.ancestorHashes) {
      if (!_filter.mayContain(h)) return false;
    }
    return matchSelector(entry.selector, e, _steps);
  }

  /// Dicas de apresentação de §8.2 e o tipo das listas aninhadas, da origem
  /// da folha padrão.
  void _hints(ElementInfo e) {
    if (!e.isHtml) return;
    final attributes = e.element.attributes;
    final hidden = attributes['hidden'];
    // `hidden="until-found"` (sem caixa ASCII) não esconde (HTML §15.3.1).
    if (hidden != null && !cssAsciiEquals(hidden, 'until-found')) {
      _steps.add(1);
      _apply(
        const Declaration(
          CssProperty.display,
          CssKeywordValue(CssDisplay.none),
        ),
        layer: _layerUserAgent,
        attached: 0,
        specificity: _hintSpecificity,
        seq: _hintSeq,
        origin: CssOrigin.userAgent,
      );
    }
    // Listas aninhadas do HTML §15.3.8: `:is(dir, menu, ol, ul) :is(dir,
    // menu, ul)` é `circle`, (0,0,2), e com duas listas acima é `square`,
    // (0,0,3). Pelo nível herdado, sem subir pelos ancestrais.
    final level = e.listDepth;
    if (level > 0 && e.isList && e.lowerName != 'ol') {
      _steps.add(1);
      _apply(
        Declaration(
          CssProperty.listStyleType,
          CssKeywordValue(
            level == 1 ? CssListStyleType.circle : CssListStyleType.square,
          ),
        ),
        layer: _layerUserAgent,
        attached: 0,
        specificity: level == 1 ? 2 : 3,
        seq: _hintSeq + 2,
        origin: CssOrigin.userAgent,
      );
    }
    final dir = attributes['dir'];
    final direction = dir == null
        ? null
        : cssAsciiEquals(dir, 'rtl')
        ? CssDirection.rtl
        : cssAsciiEquals(dir, 'ltr')
        ? CssDirection.ltr
        : null;
    if (direction != null) {
      _steps.add(1);
      _apply(
        Declaration(CssProperty.direction, CssKeywordValue(direction)),
        layer: _layerUserAgent,
        attached: 0,
        specificity: _hintSpecificity,
        seq: _hintSeq + 1,
        origin: CssOrigin.userAgent,
      );
    }
  }

  void _styleAttribute(ElementInfo e) {
    final text = e.element.attributes['style'];
    if (text == null) return;
    if (text.length > maxStyleAttributeLength) {
      if (!_styleTooLargeEmitted) {
        _styleTooLargeEmitted = true;
        _emit(
          EpubDiagnosticCode.stylesheetIgnored,
          _section,
          'style="" acima de $maxStyleAttributeLength unidades de código',
          {'reason': 'too-large', 'source': 'style-attribute'},
        );
      }
      return;
    }
    final (declarations, errors) = _styleAttributes.putIfAbsent(text, () {
      // O parse de um texto novo entra na cessão pelo tamanho (§10.6): ~10 µs
      // por KiB contra ~60 ns de um passo, então um passo a cada 2 unidades.
      // Só a cessão: o `style=""` não está em modo livro nem paga orçamento.
      _steps.add(text.length ~/ 2);
      return parseStyleAttribute(text);
    });
    _styleParseErrors += errors;
    for (var i = 0; i < declarations.length; i++) {
      _steps.add(1);
      final d = declarations[i];
      _apply(
        d,
        layer: d.important ? _layerAuthorImportant : _layerAuthor,
        attached: 1,
        specificity: 0,
        seq: i,
        origin: CssOrigin.styleAttribute,
      );
    }
  }

  /// A declaração disputa o slot pela chave `(camada, anexado,
  /// especificidade, seq)`, campo a campo (sem `<<`: no dart2js os
  /// operadores de bits truncam em 32 bits); a maior vence.
  void _apply(
    Declaration d, {
    required int layer,
    required int attached,
    required int specificity,
    required int seq,
    required CssOrigin origin,
  }) {
    final p = d.property.index;
    if (_gen[p] == _generation) {
      final l = _layer[p], a = _attached[p], s = _specificity[p];
      final wins = layer != l
          ? layer > l
          : attached != a
          ? attached > a
          : specificity != s
          ? specificity > s
          : seq > _seq[p];
      if (!wins) return;
    }
    _gen[p] = _generation;
    _winner[p] = d;
    _layer[p] = layer;
    _attached[p] = attached;
    _specificity[p] = specificity;
    _seq[p] = seq;
    _origin[p] = origin;
  }

  CssValue? _value(CssProperty p) =>
      _gen[p.index] == _generation ? _winner[p.index]!.value : null;

  /// Valor de uma propriedade de palavra: sem vencedor, herda ou inicial;
  /// `inherit`/`initial`/`unset` pela regra do CSS Cascade 4 §7.3.
  T _keyword<T extends Enum>(CssProperty p, T parent, T initial) {
    final v = _value(p);
    return switch (v) {
      null => p.inherited ? parent : initial,
      CssWideKeyword(keyword: CssWide.inherit) => parent,
      CssWideKeyword(keyword: CssWide.initial) => initial,
      CssWideKeyword() => p.inherited ? parent : initial,
      CssKeywordValue(:final value) => value as T,
      _ => p.inherited ? parent : initial,
    };
  }

  double _em(CssProperty p, double parent, double initial) {
    final v = _value(p);
    return switch (v) {
      CssEmValue(:final em) => em,
      CssWideKeyword(keyword: CssWide.inherit) => parent,
      CssWideKeyword(keyword: CssWide.unset) when p.inherited => parent,
      null when p.inherited => parent,
      _ => initial,
    };
  }

  CssLength? _length(CssProperty p, CssLength? parent) {
    final v = _value(p);
    return switch (v) {
      CssLengthValue(:final length) => length,
      CssWideKeyword(keyword: CssWide.inherit) => parent,
      _ => null,
    };
  }

  ComputedStyle _resolve(ElementInfo e, ComputedStyle p) {
    if (_recordOrigins) {
      _originMap[e.element] = [
        for (final prop in CssProperty.values)
          _gen[prop.index] == _generation ? _origin[prop.index] : null,
      ];
    }
    final direction = _keyword(
      CssProperty.direction,
      p.direction,
      CssDirection.ltr,
    );
    final decoration = _value(CssProperty.textDecoration);
    final ownUnderline =
        decoration is CssDecorationValue && decoration.underline;
    final ownLineThrough =
        decoration is CssDecorationValue && decoration.lineThrough;
    final style = ComputedStyle(
      display: _keyword(CssProperty.display, p.display, CssDisplay.inline),
      whiteSpace: _keyword(
        CssProperty.whiteSpace,
        p.whiteSpace,
        CssWhiteSpace.normal,
      ),
      direction: direction,
      verticalAlign: _keyword(
        CssProperty.verticalAlign,
        p.verticalAlign,
        CssVerticalAlign.baseline,
      ),
      listStyleType: _listStyleType(e, p),
      breakBefore: _keyword(
        CssProperty.breakBefore,
        p.breakBefore,
        CssBreak.auto,
      ),
      breakAfter: _keyword(CssProperty.breakAfter, p.breakAfter, CssBreak.auto),
      breakInside: _keyword(
        CssProperty.breakInside,
        p.breakInside,
        CssBreak.auto,
      ),
      width: _length(CssProperty.width, p.width),
      height: _length(CssProperty.height, p.height),
      alignKeyword: _keyword(
        CssProperty.textAlign,
        p.alignKeyword,
        CssAlignKeyword.start,
      ),
      // Propagação, não herança (CSS Text Decoration 3 §2.1): nada do que o
      // elemento declara tira a linha que vem de cima.
      underline: p.underline || ownUnderline,
      lineThrough: p.lineThrough || ownLineThrough,
      fontStyle: _keyword(
        CssProperty.fontStyle,
        p.fontStyle,
        CssFontStyle.normal,
      ),
      weight: _weight(p.weight),
      fontVariant: _keyword(
        CssProperty.fontVariant,
        p.fontVariant,
        CssFontVariant.normal,
      ),
      textTransform: _keyword(
        CssProperty.textTransform,
        p.textTransform,
        CssTextTransform.none,
      ),
      fontSizeStep: switch (_value(CssProperty.fontSize)) {
        CssFontSizeValue(:final step) => step,
        _ => CssFontSizeStep.same,
      },
      margin: EmEdges(
        _em(CssProperty.marginTop, p.margin.top, 0),
        _em(CssProperty.marginRight, p.margin.right, 0),
        _em(CssProperty.marginBottom, p.margin.bottom, 0),
        _em(CssProperty.marginLeft, p.margin.left, 0),
      ),
      padding: EmEdges(
        _em(CssProperty.paddingTop, p.padding.top, 0),
        _em(CssProperty.paddingRight, p.padding.right, 0),
        _em(CssProperty.paddingBottom, p.padding.bottom, 0),
        _em(CssProperty.paddingLeft, p.padding.left, 0),
      ),
      textIndent: _em(CssProperty.textIndent, p.textIndent, 0),
    );
    _degraded();
    return style;
  }

  /// `bolder`/`lighter` pela tabela do CSS Fonts 4 §2.2 sobre o peso do pai.
  double _weight(double parent) {
    final v = _value(CssProperty.fontWeight);
    return switch (v) {
      CssWeightValue(:final absolute?) => absolute,
      CssWeightValue(bolder: true) =>
        parent < 350
            ? 400
            : parent < 550
            ? 700
            : parent < 900
            ? 900
            : parent,
      CssWeightValue() =>
        parent < 100
            ? parent
            : parent < 550
            ? 100
            : parent < 750
            ? 400
            : 700,
      CssWideKeyword(keyword: CssWide.initial) => 400,
      _ => parent, // sem vencedor, inherit e unset: herda
    };
  }

  /// Tipo desconhecido resolve no elemento onde a declaração vale (#8).
  CssListStyleType _listStyleType(ElementInfo e, ComputedStyle p) {
    if (_value(CssProperty.listStyleType) is CssUnknownListStyle) {
      final ol =
          e.isHtml &&
          (e.lowerName == 'ol' ||
              (e.lowerName == 'li' &&
                  e.parent != null &&
                  e.parent!.isHtml &&
                  e.parent!.lowerName == 'ol'));
      return ol ? CssListStyleType.decimal : CssListStyleType.disc;
    }
    return _keyword(
      CssProperty.listStyleType,
      p.listStyleType,
      CssListStyleType.disc,
    );
  }

  /// `unsupportedLayout` quando o vencedor degrada, uma vez por (seção,
  /// propriedade) (§10.7).
  void _degraded() {
    for (final (prop, name) in const [
      (CssProperty.float, 'float'),
      (CssProperty.position, 'position'),
      (CssProperty.columnCount, 'columns'),
      (CssProperty.columnWidth, 'columns'),
      (CssProperty.writingMode, 'writing-mode'),
    ]) {
      final v = _value(prop);
      if (v is CssDegradedValue && v.degrades && _degradedEmitted.add(name)) {
        _emit(
          EpubDiagnosticCode.unsupportedLayout,
          _section,
          '$name: ${v.keyword} degradado para o fluxo normal',
          {'property': name, 'value': v.keyword},
        );
      }
    }
  }
}
