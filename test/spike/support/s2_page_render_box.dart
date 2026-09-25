// Spike S2 — seleção sobre `RenderBox` próprio (doc/05 §3; doc/04 §1.1, §2.1).
//
// Protótipo mínimo: uma seção de blocos, cada um com um `ui.Paragraph` já
// shapeado; páginas com fragmentos que pintam o **mesmo** `Paragraph` com
// `translate` e `clipRect` diferentes quando o bloco atravessa páginas; um
// `S2PageRenderBox` que pinta seleção (antes do texto), texto, hífen pendurado
// e alças, e converte entre ponto local e offset canônico da seção.
//
// A seleção é um par de offsets canônicos guardado fora do render box
// (`S2SelectionController`), como doc/05 §3.3 pede.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 's2_display_map.dart';

// ---------------------------------------------------------------------------
// Modelo: seção, blocos, páginas, fragmentos.

class S2BlockSpec {
  const S2BlockSpec(
    this.canonical, {
    this.uppercase = false,
    this.softHyphensBefore = const [],
    this.inlineImageSize = const Size(30, 20),
  });

  final String canonical;
  final bool uppercase;
  final List<int> softHyphensBefore;

  /// Cada U+FFFC do canônico vira um `addPlaceholder` deste tamanho (imagem
  /// inline, doc/03 §5 e spike S7).
  final Size inlineImageSize;
}

/// Bloco folha já shapeado. Geometria de linha lida uma vez após o `layout`.
class S2Block {
  S2Block._(
    this.index,
    this.textStart,
    this.canonical,
    this.text,
    this.paragraph,
  ) {
    final metrics = paragraph.computeLineMetrics();
    final n = metrics.length;
    lineTops = Float64List(n + 1);
    lineRights = Float64List(n);
    lineStarts = Int32List(n + 1);
    var y = 0.0;
    for (var i = 0; i < n; i++) {
      lineTops[i] = y;
      y += metrics[i].height;
      lineRights[i] = metrics[i].left + metrics[i].width;
    }
    lineTops[n] = y;
    // Início de cada linha (offset exibido). `getLineBoundary.end` inclui o
    // espaço final e coincide com o início da linha seguinte (sondado).
    var start = 0;
    for (var i = 0; i < n; i++) {
      lineStarts[i] = start;
      start = paragraph.getLineBoundary(ui.TextPosition(offset: start)).end;
    }
    lineStarts[n] = text.display.length;
  }

  final int index;

  /// Offset do primeiro caractere do bloco em `S2Section.canonicalText`.
  final int textStart;
  final String canonical;
  final DisplayText text;
  final ui.Paragraph paragraph;

  late final Float64List lineTops;
  late final Float64List lineRights;
  late final Int32List lineStarts;

  int get lineCount => lineRights.length;
  int get canonicalEnd => textStart + canonical.length;
  DisplayMap get map => text.map;

  /// A linha [line] termina num U+00AD onde houve quebra (hífen a pintar).
  bool endsWithSoftHyphen(int line) =>
      line < lineCount - 1 &&
      text.display.codeUnitAt(lineStarts[line + 1] - 1) == 0x00AD;
}

class S2Section {
  S2Section._(this.canonicalText, this.blocks, this.hyphen, this.columnWidth);

  /// Monta e shapeia os blocos. `canonicalText` junta os blocos com `\n`
  /// (separador de bloco, doc/05 §3.3).
  factory S2Section.layout(
    List<S2BlockSpec> specs, {
    required double columnWidth,
    double fontSize = 10,
  }) {
    ui.Paragraph shape(String s, [Size image = Size.zero]) {
      final b =
          ui.ParagraphBuilder(
            ui.ParagraphStyle(fontSize: fontSize, fontFamily: 'FlutterTest'),
          )..pushStyle(
            ui.TextStyle(
              fontSize: fontSize,
              fontFamily: 'FlutterTest',
              color: const ui.Color(0xFF000000),
            ),
          );
      // O placeholder ocupa um U+FFFC no texto do Paragraph: offsets
      // exibidos continuam alinhados com `s`.
      var from = 0;
      for (var i = s.indexOf('\uFFFC'); i >= 0; i = s.indexOf('\uFFFC', from)) {
        b
          ..addText(s.substring(from, i))
          ..addPlaceholder(
            image.width,
            image.height,
            ui.PlaceholderAlignment.middle,
          );
        from = i + 1;
      }
      b.addText(s.substring(from));
      return b.build()..layout(ui.ParagraphConstraints(width: columnWidth));
    }

    final blocks = <S2Block>[];
    final canonical = StringBuffer();
    for (var i = 0; i < specs.length; i++) {
      if (i > 0) canonical.write('\n');
      final spec = specs[i];
      final text = buildDisplayText(
        spec.canonical,
        uppercase: spec.uppercase,
        softHyphensBefore: spec.softHyphensBefore,
      );
      blocks.add(
        S2Block._(
          i,
          canonical.length,
          spec.canonical,
          text,
          shape(text.display, spec.inlineImageSize),
        ),
      );
      canonical.write(spec.canonical);
    }
    return S2Section._(canonical.toString(), blocks, shape('-'), columnWidth);
  }

  final String canonicalText;
  final List<S2Block> blocks;
  final double columnWidth;

  /// `"-"` pré-shapeado para o hífen pendurado (doc/04 §8, spike S5).
  final ui.Paragraph hyphen;

  /// Paginação gulosa por linha (sem órfã/viúva: isso é o S8). Um bloco que
  /// não cabe é cortado na fronteira de linha e continua na página seguinte
  /// com o mesmo `Paragraph` (doc/04 §2.1).
  List<S2Page> paginate({
    required double pageHeight,
    double blockSpacing = 10,
    EdgeInsets padding = const EdgeInsets.all(20),
  }) {
    final size = Size(
      padding.horizontal + columnWidth,
      padding.vertical + pageHeight,
    );
    final pages = <S2Page>[];
    var fragments = <S2Fragment>[];
    var y = 0.0;
    void flush() {
      pages.add(S2Page(this, fragments, size, padding));
      fragments = <S2Fragment>[];
      y = 0;
    }

    for (final block in blocks) {
      var line = 0;
      while (line < block.lineCount) {
        final gap = fragments.isEmpty ? 0.0 : blockSpacing;
        var last = line;
        while (last < block.lineCount &&
            y + gap + block.lineTops[last + 1] - block.lineTops[line] <=
                pageHeight) {
          last++;
        }
        if (last == line) {
          if (fragments.isEmpty) {
            last = line + 1; // linha maior que a página: entra mesmo assim
          } else {
            flush();
            continue;
          }
        }
        final top = y + gap;
        fragments.add(
          S2Fragment(
            block: block,
            firstLine: line,
            lastLine: last - 1,
            yOffset: padding.top + top,
            left: padding.left,
            pageWidth: size.width,
          ),
        );
        y = top + block.lineTops[last] - block.lineTops[line];
        line = last;
        if (line < block.lineCount) flush();
      }
    }
    if (fragments.isNotEmpty) flush();
    return pages;
  }

  void dispose() {
    for (final b in blocks) {
      b.paragraph.dispose();
    }
    hyphen.dispose();
  }
}

/// Fragmento de bloco numa página (doc/04 §2 `PageFragment`), com o que é
/// derivado dele para pintar e para seleção.
class S2Fragment {
  S2Fragment({
    required this.block,
    required this.firstLine,
    required this.lastLine,
    required this.yOffset,
    required this.left,
    required double pageWidth,
  }) : clipRect = Rect.fromLTRB(
         0,
         yOffset,
         pageWidth,
         yOffset + block.lineTops[lastLine + 1] - block.lineTops[firstLine],
       ),
       rect = Rect.fromLTWH(
         left,
         yOffset,
         block.paragraph.width,
         block.lineTops[lastLine + 1] - block.lineTops[firstLine],
       );

  final S2Block block;
  final int firstLine, lastLine; // inclusivos
  final double yOffset; // topo do fragmento na página
  final double left;

  /// Clip de pintura: faixa vertical do fragmento na largura da página (o
  /// hífen pendurado cai na margem direita).
  final Rect clipRect;

  /// Coluna de texto do fragmento; é a área "dentro do fragmento".
  final Rect rect;

  int get blockIndex => block.index;
  ui.Paragraph get paragraph => block.paragraph;
  int get textStart => block.textStart;
  DisplayMap get displayMap => block.map;

  /// Translate aplicado ao pintar: a 1ª linha visível vai para [yOffset].
  Offset get translation => Offset(left, yOffset - block.lineTops[firstLine]);

  int get displayStart => block.lineStarts[firstLine];
  int get displayEnd => block.lineStarts[lastLine + 1];
  int get canonicalStart => textStart + displayMap.toCanonical(displayStart);
  int get canonicalEnd => textStart + displayMap.toCanonical(displayEnd);

  /// Linha visível mais próxima de `y` em coordenadas do parágrafo.
  int lineAtParagraphY(double y) {
    var lo = firstLine, hi = lastLine;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (block.lineTops[mid] <= y) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }
}

class S2Page {
  S2Page(this.section, this.fragments, this.size, this.padding);

  final S2Section section;
  final List<S2Fragment> fragments;
  final Size size;
  final EdgeInsets padding;

  int get canonicalStart => fragments.first.canonicalStart;
  int get canonicalEnd => fragments.last.canonicalEnd;
}

// ---------------------------------------------------------------------------
// Seleção (fora do render box).

class S2Selection {
  const S2Selection(this.base, this.extent);

  final int base, extent;

  int get start => math.min(base, extent);
  int get end => math.max(base, extent);

  @override
  bool operator ==(Object other) =>
      other is S2Selection && other.base == base && other.extent == extent;

  @override
  int get hashCode => Object.hash(base, extent);

  @override
  String toString() => 'S2Selection($base→$extent)';
}

class S2SelectionController extends ValueNotifier<S2Selection?> {
  S2SelectionController() : super(null);

  String textIn(S2Section section) {
    final s = value;
    return s == null ? '' : section.canonicalText.substring(s.start, s.end);
  }
}

/// Resultado de hit test de texto.
class S2TextHit {
  const S2TextHit({
    required this.caret,
    required this.char,
    required this.fragmentIndex,
    required this.insideFragment,
  });

  /// Posição de caret canônica (para arraste e alças).
  final int caret;

  /// Offset canônico do caractere sob o ponto (ou o mais próximo).
  final int char;
  final int fragmentIndex;
  final bool insideFragment;
}

enum S2Handle { start, end }

// ---------------------------------------------------------------------------
// Render box.

class S2PageRenderBox extends RenderBox {
  S2PageRenderBox({required this._page, this._selection});

  static const double handleRadius = 6;
  static const Color selectionColor = Color(0x663399FF);
  static const Color handleColor = Color(0xFF3399FF);

  S2Page _page;
  S2Page get page => _page;
  set page(S2Page value) {
    if (identical(value, _page)) return;
    _page = value;
    markNeedsLayout();
  }

  S2Selection? _selection;
  S2Selection? get selection => _selection;
  set selection(S2Selection? value) {
    if (value == _selection) return;
    _selection = value;
    markNeedsPaint(); // seleção é repaint, não relayout (doc/05 §1.1)
  }

  @override
  void performLayout() {
    size = constraints.constrain(_page.size);
  }

  @override
  bool hitTestSelf(Offset position) => true;

  // --- ponto → offset canônico (doc/05 §3.2) -------------------------------

  /// Fragmento que contém `y`; fora de todos, o mais próximo verticalmente.
  int _fragmentIndexAt(double y) {
    final fragments = _page.fragments;
    var best = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < fragments.length; i++) {
      final r = fragments[i].rect;
      if (y >= r.top && y < r.bottom) return i;
      final d = y < r.top ? r.top - y : y - r.bottom;
      if (d < bestDistance) {
        bestDistance = d;
        best = i;
      }
    }
    return best;
  }

  S2TextHit? hitAt(Offset local) {
    final fragments = _page.fragments;
    if (fragments.isEmpty) return null;
    final fi = _fragmentIndexAt(local.dy);
    final f = fragments[fi];
    final block = f.block;
    final map = f.displayMap;
    final inside = f.rect.contains(local);
    // Desfaz o translate e prende y na faixa visível do fragmento.
    final p = local - f.translation;
    final line = f.lineAtParagraphY(p.dy);
    final lineMid = (block.lineTops[line] + block.lineTops[line + 1]) / 2;
    final int caretDisplay;
    final int charDisplay;
    if (local.dx < f.rect.left) {
      caretDisplay = block.lineStarts[line];
      charDisplay = caretDisplay;
    } else if (local.dx >= f.rect.right) {
      caretDisplay = block.lineStarts[line + 1];
      charDisplay = math.max(block.lineStarts[line], caretDisplay - 1);
    } else {
      final q = Offset(p.dx, lineMid);
      caretDisplay = f.paragraph.getPositionForOffset(q).offset;
      final glyph = f.paragraph.getClosestGlyphInfoForOffset(q);
      charDisplay = glyph?.graphemeClusterCodeUnitRange.start ?? caretDisplay;
    }
    return S2TextHit(
      caret: f.textStart + map.toCanonical(caretDisplay),
      char: f.textStart + map.toCanonical(charDisplay),
      fragmentIndex: fi,
      insideFragment: inside,
    );
  }

  /// Caret canônico no ponto. Nunca "morto": fora de fragmento resolve para a
  /// linha mais próxima; margem esquerda/direita → início/fim dessa linha.
  int? canonicalOffsetAt(Offset local) => hitAt(local)?.caret;

  // --- offset canônico → retângulos (caminho inverso) ----------------------

  /// Retângulos (coordenadas da página) do range canônico `[start, end)`,
  /// por fragmento, clipados à coluna do fragmento ([S2Fragment.rect]):
  /// verticalmente, para não vazar linhas do mesmo `Paragraph` que estão em
  /// outra página; horizontalmente, porque `getBoxesForRange` devolve o espaço
  /// final de uma linha cheia **além** da largura do parágrafo (achado do
  /// spike: caixa de 0–210 numa coluna de 200). Retângulos de largura zero
  /// (U+00AD, espaço final que transborda) são descartados.
  List<Rect> rectsFor(int startCanonical, int endCanonical) {
    final out = <Rect>[];
    for (final f in _page.fragments) {
      final cs = math.max(startCanonical, f.canonicalStart);
      final ce = math.min(endCanonical, f.canonicalEnd);
      if (cs >= ce) continue;
      final ds = math.max(
        f.displayMap.toDisplay(cs - f.textStart),
        f.displayStart,
      );
      final de = math.min(
        f.displayMap.toDisplay(ce - f.textStart),
        f.displayEnd,
      );
      if (ds >= de) continue;
      final t = f.translation;
      for (final box in f.paragraph.getBoxesForRange(ds, de)) {
        final r = box.toRect().shift(t).intersect(f.rect);
        if (r.width > 0 && r.height > 0) out.add(r);
      }
    }
    return out;
  }

  /// Sub-ranges canônicos de `[start, end)` que esta página cobre, um por
  /// fragmento.
  List<(int, int)> coveredRanges(int startCanonical, int endCanonical) => [
    for (final f in _page.fragments)
      if (math.max(startCanonical, f.canonicalStart) <
          math.min(endCanonical, f.canonicalEnd))
        (
          math.max(startCanonical, f.canonicalStart),
          math.min(endCanonical, f.canonicalEnd),
        ),
  ];

  /// Palavra em torno do caractere canônico, via `getWordBoundary` do
  /// `Paragraph` exibido e mapeada de volta.
  (int, int) wordAt(int canonical) {
    for (final f in _page.fragments) {
      final b = f.block;
      if (canonical < b.textStart || canonical >= b.canonicalEnd) continue;
      final d = b.map.toDisplay(canonical - b.textStart);
      final r = b.paragraph.getWordBoundary(ui.TextPosition(offset: d));
      return (
        b.textStart + b.map.toCanonical(r.start),
        b.textStart + b.map.toCanonical(r.end),
      );
    }
    return (canonical, canonical);
  }

  // --- alças ---------------------------------------------------------------

  /// Pontos de ancoragem das alças (base do retângulo), ou `null` quando a
  /// extremidade não está nesta página.
  (Offset?, Offset?) handleAnchors(S2Selection s) {
    if (s.start == s.end || _page.fragments.isEmpty) return (null, null);
    final rects = rectsFor(s.start, s.end);
    if (rects.isEmpty) return (null, null);
    final startHere =
        s.start >= _page.canonicalStart && s.start < _page.canonicalEnd;
    final endHere = s.end > _page.canonicalStart && s.end <= _page.canonicalEnd;
    return (
      startHere ? rects.first.bottomLeft : null,
      endHere ? rects.last.bottomRight : null,
    );
  }

  static Offset handleCenter(Offset anchor) =>
      anchor + const Offset(0, handleRadius);

  /// Alça sob o ponto, com área de toque de 2× o raio.
  S2Handle? handleAt(Offset local) {
    final s = _selection;
    if (s == null) return null;
    final (a, b) = handleAnchors(s);
    const slop = handleRadius * 2;
    if (b != null && (handleCenter(b) - local).distance <= slop) {
      return S2Handle.end;
    }
    if (a != null && (handleCenter(a) - local).distance <= slop) {
      return S2Handle.start;
    }
    return null;
  }

  // --- pintura (doc/05 §1: seleção antes do texto, alças por cima) ---------

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    final s = _selection;
    if (s != null && s.start < s.end) {
      final paint = Paint()..color = selectionColor;
      for (final r in rectsFor(s.start, s.end)) {
        canvas.drawRect(r, paint);
      }
    }
    final hyphen = _page.section.hyphen;
    for (final f in _page.fragments) {
      canvas.save();
      canvas.clipRect(f.clipRect);
      canvas.drawParagraph(f.paragraph, f.translation);
      for (var line = f.firstLine; line <= f.lastLine; line++) {
        if (!f.block.endsWithSoftHyphen(line)) continue;
        canvas.drawParagraph(
          hyphen,
          f.translation +
              Offset(f.block.lineRights[line], f.block.lineTops[line]),
        );
      }
      canvas.restore();
    }
    if (s != null) {
      final (a, b) = handleAnchors(s);
      final paint = Paint()..color = handleColor;
      if (a != null) canvas.drawCircle(handleCenter(a), handleRadius, paint);
      if (b != null) canvas.drawCircle(handleCenter(b), handleRadius, paint);
    }
    canvas.restore();
  }
}

class S2PageView extends LeafRenderObjectWidget {
  const S2PageView({super.key, required this.page, this.selection});

  final S2Page page;
  final S2Selection? selection;

  @override
  S2PageRenderBox createRenderObject(BuildContext context) =>
      S2PageRenderBox(page: page, selection: selection);

  @override
  void updateRenderObject(BuildContext context, S2PageRenderBox renderObject) {
    renderObject
      ..page = page
      ..selection = selection;
  }
}

// ---------------------------------------------------------------------------
// Gestos: long press seleciona palavra e arrasta para estender; arraste em
// alça move a extremidade correspondente.

/// Pan que só entra na arena quando o toque começa sobre uma alça; fora das
/// alças, o long press (e, no leitor real, a virada de página) fica livre.
///
/// `DragStartBehavior.down`: com o padrão (`start`), `onStart` recebe a
/// posição onde o pan foi aceito, 36 px (kPanSlop) depois do toque na alça, e
/// a alça "pula" esse trecho.
class _HandlePanRecognizer extends PanGestureRecognizer {
  _HandlePanRecognizer({super.debugOwner, required this.hitsHandle}) {
    dragStartBehavior = DragStartBehavior.down;
  }

  bool Function(Offset local) hitsHandle;

  @override
  bool isPointerAllowed(PointerEvent event) =>
      hitsHandle(event.localPosition) && super.isPointerAllowed(event);
}

class S2SelectablePage extends StatefulWidget {
  const S2SelectablePage({
    super.key,
    required this.page,
    required this.controller,
  });

  final S2Page page;
  final S2SelectionController controller;

  @override
  State<S2SelectablePage> createState() => _S2SelectablePageState();
}

class _S2SelectablePageState extends State<S2SelectablePage> {
  final _boxKey = GlobalKey();
  (int, int)? _anchorWord;
  int? _dragBase;
  Offset _dragDelta = Offset.zero;

  S2PageRenderBox get _box =>
      _boxKey.currentContext!.findRenderObject()! as S2PageRenderBox;

  S2SelectionController get _c => widget.controller;

  void _onLongPressStart(LongPressStartDetails d) {
    final hit = _box.hitAt(d.localPosition);
    if (hit == null) return;
    final word = _box.wordAt(hit.char);
    _anchorWord = word;
    _c.value = S2Selection(word.$1, word.$2);
  }

  void _onLongPressMove(LongPressMoveUpdateDetails d) {
    final word = _anchorWord;
    final caret = _box.canonicalOffsetAt(d.localPosition);
    if (word == null || caret == null) return;
    _c.value = caret < word.$1
        ? S2Selection(word.$2, caret)
        : S2Selection(word.$1, math.max(caret, word.$2));
  }

  bool _hitsHandle(Offset local) => _box.handleAt(local) != null;

  void _onPanStart(DragStartDetails d) {
    final s = _c.value;
    final handle = _box.handleAt(d.localPosition);
    if (s == null || handle == null) return;
    final (a, b) = _box.handleAnchors(s);
    final anchor = handle == S2Handle.start ? a! : b!;
    // O dedo está sobre a alça, abaixo do texto: o ponto de texto é o da
    // ancoragem (1 px acima da base do retângulo), transportado pelo arraste.
    _dragDelta = anchor - const Offset(0, 1) - d.localPosition;
    _dragBase = handle == S2Handle.start ? s.end : s.start;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final base = _dragBase;
    if (base == null) return;
    final caret = _box.canonicalOffsetAt(d.localPosition + _dragDelta);
    if (caret == null) return;
    _c.value = S2Selection(base, caret);
  }

  void _onPanEnd(DragEndDetails d) => _dragBase = null;

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      gestures: {
        LongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
              () => LongPressGestureRecognizer(debugOwner: this),
              (r) => r
                ..onLongPressStart = _onLongPressStart
                ..onLongPressMoveUpdate = _onLongPressMove,
            ),
        _HandlePanRecognizer:
            GestureRecognizerFactoryWithHandlers<_HandlePanRecognizer>(
              () => _HandlePanRecognizer(
                debugOwner: this,
                hitsHandle: _hitsHandle,
              ),
              (r) => r
                ..hitsHandle = _hitsHandle
                ..onStart = _onPanStart
                ..onUpdate = _onPanUpdate
                ..onEnd = _onPanEnd,
            ),
      },
      child: ValueListenableBuilder<S2Selection?>(
        valueListenable: _c,
        builder: (context, selection, _) =>
            S2PageView(key: _boxKey, page: widget.page, selection: selection),
      ),
    );
  }
}
