// Spike S8 — paginação ancorada (doc/04 §2.2, §3.1; doc/10 Invariante 8).
//
// Lógica pura, sem dart:ui. Um bloco é uma lista de alturas de linha já
// medidas; a paginação só decide onde as fronteiras de página caem.
//
// A ideia central: as regras de quebra (órfã, viúva, heading, breakBefore) são
// expressas como uma única função `isLegalBreak(t)` sobre a fronteira entre a
// linha global t-1 e a linha global t. Paginar para frente e para trás usa a
// mesma função, o que garante que "as regras espelham" (doc/04 §3.1) por
// construção e não por duplicação de código.

import 'dart:math';

enum SpikeBlockKind { paragraph, heading, sceneBreak }

class SpikeBlock {
  const SpikeBlock({
    required this.kind,
    required this.lineHeights,
    this.breakBefore = false,
  });

  final SpikeBlockKind kind;
  final List<double> lineHeights;
  final bool breakBefore;

  int get lineCount => lineHeights.length;
}

/// Posição de retomada: primeira linha de uma página.
class SpikeCursor {
  const SpikeCursor(this.block, this.line);

  final int block;
  final int line;

  @override
  bool operator ==(Object other) =>
      other is SpikeCursor && other.block == block && other.line == line;

  @override
  int get hashCode => Object.hash(block, line);

  @override
  String toString() => '($block,$line)';
}

/// Página como intervalo de linhas globais [firstLine, endLine).
class SpikePage {
  const SpikePage(this.firstLine, this.endLine, this.height);

  final int firstLine;
  final int endLine;
  final double height;

  int get lineCount => endLine - firstLine;

  @override
  String toString() => '[$firstLine,$endLine) h=$height';
}

class SpikePagination {
  const SpikePagination(this.pages, this.anchorLine, this.anchorPageIndex);

  final List<SpikePage> pages;

  /// Linha global onde a página ancorada começa (após snap, ver [snapAnchor]).
  final int anchorLine;

  /// Índice da página que começa em [anchorLine].
  final int anchorPageIndex;
}

class SpikePaginator {
  SpikePaginator(this.blocks, {required this.pageHeight, this.spacing = 12.0})
    : _lineBlock = <int>[],
      _lineIndex = <int>[],
      _lineHeight = <double>[],
      _blockStart = List<int>.filled(blocks.length + 1, 0) {
    var g = 0;
    for (var b = 0; b < blocks.length; b++) {
      _blockStart[b] = g;
      for (var l = 0; l < blocks[b].lineCount; l++) {
        _lineBlock.add(b);
        _lineIndex.add(l);
        _lineHeight.add(blocks[b].lineHeights[l]);
        g++;
      }
    }
    _blockStart[blocks.length] = g;
    _maxLineHeight = _lineHeight.isEmpty ? 0 : _lineHeight.reduce(max);
  }

  final List<SpikeBlock> blocks;
  final double pageHeight;

  /// Espaço entre blocos. Conta na altura da página quando há um bloco acima,
  /// nunca no topo da página.
  final double spacing;

  final List<int> _lineBlock;
  final List<int> _lineIndex;
  final List<double> _lineHeight;
  final List<int> _blockStart;
  late final double _maxLineHeight;

  int get totalLines => _lineBlock.length;

  /// Regras de órfã/viúva/heading desligadas em coluna com menos de 3 linhas
  /// (doc/04 §2.2, `viewportTooSmall`).
  bool get typographyRulesEnabled => pageHeight >= 3 * _maxLineHeight;

  int lineOf(SpikeCursor c) => _blockStart[c.block] + c.line;

  SpikeCursor cursorOf(int globalLine) =>
      SpikeCursor(_lineBlock[globalLine], _lineIndex[globalLine]);

  bool _isBlockStart(int t) => _lineIndex[t] == 0;

  bool _isBlockEnd(int t) =>
      _lineIndex[t] == blocks[_lineBlock[t]].lineCount - 1;

  bool _isParagraph(int t) =>
      blocks[_lineBlock[t]].kind == SpikeBlockKind.paragraph;

  bool _isHeading(int t) =>
      blocks[_lineBlock[t]].kind == SpikeBlockKind.heading;

  /// Quebra forçada antes da linha [t] (`break-before: page`, Classe 1).
  bool isForcedBreak(int t) =>
      t > 0 &&
      t < totalLines &&
      _isBlockStart(t) &&
      blocks[_lineBlock[t]].breakBefore;

  /// A fronteira entre a linha t-1 (fim de uma página) e a linha t (início da
  /// seguinte) é aceitável?
  bool isLegalBreak(int t) {
    if (t <= 0 || t >= totalLines) return true;
    if (isForcedBreak(t)) return true;
    if (!typographyRulesEnabled) return true;

    final above = t - 1;
    final sameBlock = _lineBlock[above] == _lineBlock[t];

    // Órfã: primeira linha de um parágrafo sozinha no fim da página.
    if (sameBlock && _isParagraph(above) && _isBlockStart(above)) return false;

    // Viúva: última linha de um parágrafo sozinha no início da página.
    if (sameBlock && _isParagraph(t) && _isBlockEnd(t)) return false;

    // Heading no fim da página: precisa de pelo menos 2 linhas do bloco
    // seguinte na mesma página, ou o bloco seguinte inteiro se ele tiver 1.
    if (_isHeading(above)) return false;
    // A página acima termina com heading + 1 linha de um bloco que continua.
    // Para parágrafos coincide com a regra de órfã; vale também para blocos
    // de outros tipos (heading de dois níveis, verso).
    if (sameBlock &&
        _isBlockStart(above) &&
        above - 1 >= 0 &&
        _isHeading(above - 1)) {
      return false;
    }
    return true;
  }

  double _heightOf(int first, int end) {
    var h = 0.0;
    for (var t = first; t < end; t++) {
      if (t > first && _isBlockStart(t)) h += spacing;
      h += _lineHeight[t];
    }
    return h;
  }

  /// Ajusta o âncora para a fronteira legal mais próxima antes dele, para que a
  /// página anterior não termine com órfã ou heading e a ancorada não comece
  /// com viúva.
  int snapAnchor(int anchor) {
    var t = anchor.clamp(0, totalLines);
    while (t > 0 && !isLegalBreak(t)) {
      t--;
    }
    return t;
  }

  /// Páginas de [start] até o fim, preenchendo de cima para baixo.
  List<SpikePage> paginateForward(int start) {
    final pages = <SpikePage>[];
    var s = start;
    while (s < totalLines) {
      var t = s;
      var h = 0.0;
      while (t < totalLines) {
        if (t > s && isForcedBreak(t)) break;
        final add = (t > s && _isBlockStart(t) ? spacing : 0) + _lineHeight[t];
        if (t > s && h + add > pageHeight) break;
        h += add;
        t++;
      }
      // Recua a fronteira até ficar legal, mantendo ao menos uma linha.
      while (t > s + 1 && !isLegalBreak(t)) {
        t--;
      }
      pages.add(SpikePage(s, t, _heightOf(s, t)));
      s = t;
    }
    return pages;
  }

  /// Páginas do início até [end] (exclusivo), preenchendo de baixo para cima.
  /// Devolvidas em ordem de leitura.
  List<SpikePage> paginateBackward(int end) {
    final pages = <SpikePage>[];
    var e = end;
    while (e > 0) {
      var t = e;
      var h = 0.0;
      while (t > 0) {
        if (t < e && isForcedBreak(t)) break;
        final u = t - 1;
        // Ao acrescentar u acima de t, aparece o spacing entre blocos se t
        // começa um bloco.
        final add = _lineHeight[u] + (t < e && _isBlockStart(t) ? spacing : 0);
        if (t < e && h + add > pageHeight) break;
        h += add;
        t--;
      }
      // Avança a fronteira (empurra linhas para a página de cima) até ficar
      // legal, mantendo ao menos uma linha nesta página.
      while (t < e - 1 && !isLegalBreak(t)) {
        t++;
      }
      pages.add(SpikePage(t, e, _heightOf(t, e)));
      e = t;
    }
    pages.sort((a, b) => a.firstLine.compareTo(b.firstLine));
    return pages;
  }

  /// Paginação ancorada: para trás até o início, para frente até o fim.
  SpikePagination paginateAnchored(SpikeCursor anchor) {
    final snapped = snapAnchor(lineOf(anchor));
    final before = paginateBackward(snapped);
    final after = paginateForward(snapped);
    return SpikePagination([...before, ...after], snapped, before.length);
  }

  /// Verifica as regras tipográficas em cada fronteira de página. Devolve as
  /// fronteiras ilegais (vazio = tudo certo). Fronteiras onde a página tem uma
  /// única linha são toleradas, porque não há como quebrar melhor.
  List<int> illegalBreaks(List<SpikePage> pages) {
    final bad = <int>[];
    for (var i = 1; i < pages.length; i++) {
      final t = pages[i].firstLine;
      if (!isLegalBreak(t) &&
          pages[i - 1].lineCount > 1 &&
          pages[i].lineCount > 1) {
        bad.add(t);
      }
    }
    return bad;
  }
}
