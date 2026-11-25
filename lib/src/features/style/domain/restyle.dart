import 'dart:typed_data';

import '../../document/domain/document_tree.dart';
import '../../document/domain/names.dart';
import 'computed_style.dart';
import 'css_value.dart';
import 'matched_document.dart';
import 'properties.dart';
import 'reader_preferences.dart';
import 'selector.dart';
import 'styled_document.dart';
import 'value_computer.dart';

/// Calcula os estilos do documento a partir do casamento guardado
/// [matched] (passos 4–5 da spec §8.1): valores calculados com herança,
/// internamento e conteúdo gerado.
///
/// A árvore é percorrida uma vez em ordem de documento, **sem recursão**
/// (pai antes do filho; uma pilha guarda os elementos abertos para fechar
/// `::after` depois dos descendentes). Um memo `(estilo do pai, conjunto,
/// tipo) → índice do estilo` evita recalcular o mesmo resultado, o que
/// cobre o atalho de irmãos da §8.6 e também primos e níveis repetidos.
///
/// [preferences] ainda não age: a passada de preferências chega numa etapa
/// seguinte; o resultado é o do livro.
StyledDocument restyle(MatchedDocument matched, ReaderPreferences preferences) {
  final tree = matched.tree;
  final nodeCount = tree.nodeCount;
  final computer = ValueComputer(
    internalFamilies: bookFamilyNames(matched.fontFaces),
    pageWidth: matched.pageWidth,
    pageHeight: matched.pageHeight,
  );
  final interner = StyleInterner();
  final styles = interner.styles;
  final elementStyles = Int32List(nodeCount)..fillRange(0, nodeCount, -1);
  final setCount = matched.sets.length;
  final memo = <int, int>{};

  int styleFor(int parentStyle, int set, int kind, {required bool isRoot}) {
    // kind: 0 = elemento, 1 + PseudoElement.index para pseudo-elementos.
    final key = ((parentStyle + 1) * setCount + set) * 5 + kind;
    final known = memo[key];
    if (known != null) return known;
    final values = computer.compute(
      matched.sets[set],
      parent: parentStyle < 0 ? null : styles[parentStyle],
      isRoot: isRoot,
      pseudo: kind == 0 ? null : PseudoElement.values[kind - 1],
    );
    return memo[key] = interner.indexOf(values);
  }

  final pseudoIn = matched.pseudoElements;
  final pseudoKindsIn = matched.pseudoKinds;
  final pseudoSetsIn = matched.pseudoSets;
  var cursor = 0;
  final pseudoElements = <int>[];
  final pseudoKinds = <int>[];
  final pseudoStyles = <int>[];
  final generated = <String?>[];

  final quotes = _QuoteState();
  // Elementos abertos e, paralelo, a entrada de `::after` pendente (−1).
  final open = <int>[];
  final pendingAfter = <int>[];

  void close() {
    final element = open.removeLast();
    final after = pendingAfter.removeLast();
    if (after >= 0) {
      generated[after] = _generatedText(
        tree,
        element,
        styles[pseudoStyles[after]],
        quotes,
      );
    }
  }

  var rootSeen = false;
  for (var n = 0; n < nodeCount; n++) {
    if (tree.kindOf(n) != NodeKind.element) continue;
    final parent = tree.parentOf(n);
    while (open.isNotEmpty && open.last != parent) {
      close();
    }
    final parentStyle = parent >= 0 ? elementStyles[parent] : -1;
    final isRoot = parentStyle < 0;
    final style = styleFor(
      parentStyle,
      matched.elementSets[n],
      0,
      isRoot: isRoot,
    );
    elementStyles[n] = style;
    if (isRoot && !rootSeen) {
      rootSeen = true;
      computer.rootFontSize =
          (styles[style][PropertyId.fontSize] as CssLength).px;
    }

    var after = -1;
    while (cursor < pseudoIn.length && pseudoIn[cursor] < n) {
      cursor++;
    }
    for (; cursor < pseudoIn.length && pseudoIn[cursor] == n; cursor++) {
      final kind = PseudoElement.values[pseudoKindsIn[cursor]];
      final index = styleFor(
        style,
        pseudoSetsIn[cursor],
        kind.index + 1,
        isRoot: false,
      );
      final isBeforeOrAfter =
          kind == PseudoElement.before || kind == PseudoElement.after;
      if (isBeforeOrAfter && styles[index][PropertyId.content] is! CssContent) {
        continue; // `content: none`/`normal`: o pseudo-elemento não existe.
      }
      pseudoElements.add(n);
      pseudoKinds.add(kind.index);
      pseudoStyles.add(index);
      switch (kind) {
        case PseudoElement.before:
          generated.add(_generatedText(tree, n, styles[index], quotes));
        case PseudoElement.after:
          after = generated.length;
          generated.add(''); // preenchido ao fechar o elemento
        case PseudoElement.firstLetter || PseudoElement.firstLine:
          generated.add(null);
      }
    }
    open.add(n);
    pendingAfter.add(after);
  }
  while (open.isNotEmpty) {
    close();
  }

  return StyledDocument(
    styles: List.unmodifiable(styles),
    elementStyles: elementStyles,
    pseudoElements: Int32List.fromList(pseudoElements),
    pseudoKinds: Uint8List.fromList(pseudoKinds),
    pseudoStyles: Int32List.fromList(pseudoStyles),
    generatedTexts: List.unmodifiable(generated),
    fontFaces: matched.fontFaces,
    pageMargins: matched.pageMargins,
  );
}

/// Profundidade das aspas, em ordem de documento (CSS Generated Content).
final class _QuoteState {
  int depth = 0;
}

/// Texto de `content` do pseudo-elemento com estilo [style] em [element]:
/// strings, `attr()` (vazio se o atributo faltar), aspas pela profundidade
/// e contadores vazios (SP8).
String _generatedText(
  DocumentTree tree,
  int element,
  ComputedStyle style,
  _QuoteState quotes,
) {
  final content = style[PropertyId.content];
  if (content is! CssContent) return '';
  final q = style[PropertyId.quotes];
  final pairs = q is CssQuotes ? q.pairs : const <(String, String)>[];
  final out = StringBuffer();
  for (final item in content.items) {
    switch (item) {
      case ContentText(:final text):
        out.write(text);
      case ContentAttr(:final name):
        out.write(tree.attribute(element, Namespaces.none, name) ?? '');
      case ContentCounter():
        break;
      case ContentQuote(:final kind):
        switch (kind) {
          case QuoteKind.open:
            if (pairs.isNotEmpty) {
              out.write(pairs[_level(quotes.depth, pairs.length)].$1);
            }
            quotes.depth++;
          case QuoteKind.close:
            if (quotes.depth == 0) break;
            quotes.depth--;
            if (pairs.isNotEmpty) {
              out.write(pairs[_level(quotes.depth, pairs.length)].$2);
            }
          case QuoteKind.noOpen:
            quotes.depth++;
          case QuoteKind.noClose:
            if (quotes.depth > 0) quotes.depth--;
        }
    }
  }
  return out.toString();
}

int _level(int depth, int count) => depth < count ? depth : count - 1;
