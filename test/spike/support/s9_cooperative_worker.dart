// Spike S9 — worker cooperativo da Camada A (doc/08 §1, §2 e §3; P10).
//
// Protótipo mínimo do que o `CooperativeEpubWorker` faria no web: a tarefa é
// um gerador `sync*` com um `yield` por checkpoint ("a cada bloco emitido",
// doc/08 §3), e um executor drena o iterador em fatias de até 4 ms no isolate
// principal, cedendo o event loop entre elas.
//
// Achado estrutural: o parse do pacote `html` (`HtmlParser.parse`) é uma
// chamada única e atômica sobre a string inteira. Não há como pôr `yield`
// dentro dele sem reescrever o tokenizer. Por isso o gerador tem dois
// estágios: (1) parse atômico, seguido de um `yield`; (2) caminhada no DOM com
// um `yield` por bloco. O executor mede o estágio 1 como uma fatia própria.
//
// Lógica pura, sem `dart:ui`, sem `dart:io`, sem `dart:isolate`: compila em VM,
// dart2js e dart2wasm.

import 'dart:async';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

/// Bloco emitido pela caminhada (esboço da IR da Camada A: só tag e texto).
class Block {
  const Block(this.tag, this.text);

  final String tag;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is Block && other.tag == tag && other.text == text;

  @override
  int get hashCode => Object.hash(tag, text);

  @override
  String toString() => '<$tag>${text.length}';
}

/// `Sink<Block>` que só acumula.
class BlockCollector implements Sink<Block> {
  final blocks = <Block>[];

  int get totalChars => blocks.fold(0, (sum, b) => sum + b.text.length);

  @override
  void add(Block data) => blocks.add(data);

  @override
  void close() {}
}

const blockTags = {
  'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li', 'pre', 'blockquote', 'td', //
};

final _whitespace = RegExp(r'\s+');

/// Parse atômico do pacote `html` (HTML5, tolerante; doc/03 §8). Não fatiável.
Document parseXhtml(String xhtml) => html.parse(xhtml);

/// Tarefa completa da Camada A para uma seção, como gerador `sync*`.
///
/// O primeiro `moveNext()` faz o parse inteiro (atômico); cada `moveNext()`
/// seguinte emite no máximo um bloco em [out].
Iterable<void> parseSectionSteps(String xhtml, Sink<Block> out) sync* {
  final doc = parseXhtml(xhtml);
  yield null; // checkpoint após o parse atômico
  yield* walkBlocksSteps(doc, out);
}

/// Estágio 2: caminhada iterativa (pilha explícita, sem recursão de `sync*`)
/// em ordem de documento, um `yield` por bloco emitido.
///
/// Um elemento de [blockTags] vira bloco quando não contém outro elemento de
/// [blockTags]; senão (`blockquote > p`, `li > p`, `td > p`) a caminhada desce
/// e os filhos viram blocos. O texto é normalizado com colapso de whitespace;
/// `pre` preserva o texto como está.
Iterable<void> walkBlocksSteps(Document doc, Sink<Block> out) sync* {
  final root = doc.body ?? doc.documentElement;
  if (root == null) return;
  final stack = <Element>[root];
  while (stack.isNotEmpty) {
    final el = stack.removeLast();
    final tag = el.localName ?? '';
    if (blockTags.contains(tag) && (tag == 'pre' || !_hasBlockDescendant(el))) {
      final raw = el.text;
      final text = tag == 'pre' ? raw : raw.replaceAll(_whitespace, ' ').trim();
      if (text.isNotEmpty) {
        out.add(Block(tag, text));
        yield null; // checkpoint "a cada bloco emitido" (doc/08 §3)
      }
      continue;
    }
    // `el.nodes`, não `el.children`: no pacote `html` 0.15.7, `children` é
    // uma `FilteredElementList` cujo `length` e `operator []` refazem
    // `nodes.whereType<Element>().toList()` a cada acesso. Indexar
    // `children[i]` num `section` com 5 mil filhos torna a caminhada O(n²)
    // (medido: 680 ms para 500 KB e 33 s para 3 MB na VM).
    final nodes = el.nodes;
    for (var i = nodes.length - 1; i >= 0; i--) {
      final n = nodes[i];
      if (n is Element) stack.add(n);
    }
  }
}

bool _hasBlockDescendant(Element el) {
  for (final n in el.nodes) {
    if (n is Element &&
        (blockTags.contains(n.localName) || _hasBlockDescendant(n))) {
      return true;
    }
  }
  return false;
}

/// Drena o iterador de uma vez (o que o `IsolateEpubWorker` faria).
int drain(Iterator<void> work) {
  var steps = 0;
  while (work.moveNext()) {
    steps++;
  }
  return steps;
}

/// Drena o iterador de uma vez medindo cada passo (µs). Só para achar o
/// custo de um passo específico; o `Stopwatch` por passo não entra nos
/// tempos de parede.
List<int> drainTimed(Iterator<void> work) {
  final times = <int>[];
  final sw = Stopwatch();
  while (true) {
    sw
      ..reset()
      ..start();
    if (!work.moveNext()) break;
    times.add(sw.elapsedMicroseconds);
  }
  return times;
}

/// Uma fatia executada pelo [CooperativeRunner].
class Slice {
  const Slice(this.firstStep, this.steps, this.micros);

  /// Índice (0-based) do primeiro `moveNext()` desta fatia. O passo 0 é o
  /// parse atômico; o passo `i ≥ 1` emite o bloco `i - 1`.
  final int firstStep;
  final int steps;
  final int micros;

  bool containsStep(int step) => step >= firstStep && step < firstStep + steps;
}

class CooperativeReport {
  CooperativeReport(this.slices, this.wallMicros, this.gapMicros);

  final List<Slice> slices;

  /// Do primeiro `moveNext()` até o iterador acabar, incluindo as cessões.
  final int wallMicros;

  /// Duração de cada cessão (`await Future.delayed(Duration.zero)`), medida
  /// do fim de uma fatia ao início da seguinte.
  final List<int> gapMicros;

  int get steps => slices.fold(0, (s, x) => s + x.steps);
  int get busyMicros => slices.fold(0, (s, x) => s + x.micros);

  /// Fatias do estágio 2 (excluindo a que contém o passo 0, o parse).
  Iterable<Slice> get walkSlices => slices.where((s) => !s.containsStep(0));

  Slice sliceOfStep(int step) => slices.firstWhere((s) => s.containsStep(step));
}

/// Executor cooperativo: fatias limitadas por `Stopwatch` a [budget], cedendo
/// o event loop entre elas.
///
/// Diferença em relação a doc/08 §2: lá a cessão é
/// `SchedulerBinding.scheduleTask(_, Priority.idle)`. Aqui não há binding (é
/// um teste de lógica pura, e no `--platform chrome` fora de widget test não
/// há `SchedulerBinding`), então a cessão é um `Timer` de zero
/// (`Future.delayed(Duration.zero)`), que é o fallback que a Emenda 9 já
/// prevê (`Timer.run`). O custo da cessão é medido em [CooperativeReport.gapMicros].
///
/// O orçamento é verificado **depois** de cada passo, como no `_slice` de
/// doc/08 §2: uma fatia só passa de [budget] pelo tamanho do último passo.
class CooperativeRunner {
  CooperativeRunner({this.budget = const Duration(microseconds: 4000)});

  final Duration budget;

  Future<CooperativeReport> run(Iterator<void> work) async {
    final budgetMicros = budget.inMicroseconds;
    final slices = <Slice>[];
    final gaps = <int>[];
    final wall = Stopwatch()..start();
    final slice = Stopwatch();
    var step = 0;
    var more = true;
    var lastEnd = -1;
    while (more) {
      if (lastEnd >= 0) gaps.add(wall.elapsedMicroseconds - lastEnd);
      final first = step;
      slice
        ..reset()
        ..start();
      do {
        more = work.moveNext();
        if (more) step++;
      } while (more && slice.elapsedMicroseconds < budgetMicros);
      slice.stop();
      if (step > first || slices.isEmpty) {
        slices.add(Slice(first, step - first, slice.elapsedMicroseconds));
      }
      lastEnd = wall.elapsedMicroseconds;
      if (more) await Future<void>.delayed(Duration.zero);
    }
    wall.stop();
    return CooperativeReport(slices, wall.elapsedMicroseconds, gaps);
  }
}
