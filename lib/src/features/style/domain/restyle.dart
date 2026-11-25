import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../../../core/diagnostics/diagnostic.dart';
import '../../../core/diagnostics/diagnostic_codes.dart';
import '../../../core/diagnostics/diagnostic_sink.dart';
import '../../../core/errors/galley_exception.dart';
import '../../document/domain/document_tree.dart';
import '../../document/domain/names.dart';
import 'cascade.dart';
import 'computed_style.dart';
import 'css_value.dart';
import 'matched_document.dart';
import 'preference_pass.dart';
import 'properties.dart';
import 'reader_preferences.dart';
import 'selector.dart';
import 'style_environment.dart';
import 'styled_document.dart';
import 'text_run.dart';
import 'value_computer.dart';

/// Calcula os estilos do documento a partir do casamento guardado
/// [matched] (passos 4–5 da spec §8.1): valores calculados com herança,
/// internamento e conteúdo gerado.
///
/// A árvore é percorrida uma vez em ordem de documento, **sem recursão**
/// (pai antes do filho; uma pilha guarda os elementos abertos para fechar
/// `::after` depois dos descendentes). Um memo `(estilo do pai, conjunto,
/// tipo) → índice do estilo` evita recalcular o mesmo resultado, o que
/// cobre o atalho de irmãos da §8.6 e também primos e níveis repetidos; as
/// marcas de [MatchedDocument.flags] também entram na chave.
///
/// [preferences] são aplicadas pela [PreferencePass] (spec §8.5, §8.7):
/// cada estilo é calculado a partir do pai já ajustado e transformado em
/// seguida; o tamanho da fonte entra no próprio cálculo. Por isso a chave
/// do memo inclui também as marcas do pai (a fronteira do escopo), se o
/// elemento é o `body` (fundo do tema, margens com o espaçamento forçado)
/// e, quando a família da editora é mantida, essa família. Com ajustes de
/// texto corrido, guarda em paralelo o herdado da editora
/// ([PublisherSnapshot]) dos elementos de texto corrido, e o instantâneo do
/// pai também entra na chave. Sem preferências, o resultado é o do livro.
///
/// Só [GalleyException] escapa: um defeito interno (exceção inesperada)
/// vira os estilos da folha padrão, sem preferências, com
/// [StyledDocument.internalError] e `css.internalError` (error) em [sink]
/// (ver [guardRestyle]). O [StyledDocument.internalError] do casamento é
/// copiado para o resultado.
StyledDocument restyle(
  MatchedDocument matched,
  ReaderPreferences preferences, {
  DiagnosticSink? sink,
}) => guardRestyle(matched, () => _restyle(matched, preferences), sink: sink);

/// O catch-all de [restyle]: roda [body] e transforma qualquer exceção que
/// não seja [GalleyException] nos estilos de reserva do documento de
/// [matched]: a folha padrão sozinha (`userAgentMatch`), sem preferências,
/// com [StyledDocument.internalError] = tipo da exceção e
/// `css.internalError` em [sink]. Se até a reserva lançar, todo elemento
/// recebe os valores iniciais. Separado só para os testes exercitarem esse
/// caminho, que o cálculo real não alcança sem um bug.
@visibleForTesting
StyledDocument guardRestyle(
  MatchedDocument matched,
  StyledDocument Function() body, {
  DiagnosticSink? sink,
}) {
  try {
    return body();
  } on GalleyException {
    rethrow;
  } on Object catch (e) {
    final type = '${e.runtimeType}';
    (sink ?? const NullDiagnosticSink()).report(
      Diagnostic(
        severity: DiagnosticSeverity.error,
        code: DiagnosticCodes.cssInternalError,
        message:
            'erro inesperado no estilo ($type); '
            'usados só os estilos da folha padrão',
        location: matched.path,
      ),
    );
    return _fallback(matched, type);
  }
}

/// Estilos da folha padrão sozinha para a árvore de [matched], marcados
/// com [internalError]; valores iniciais em tudo se até isso lançar.
StyledDocument _fallback(MatchedDocument matched, String internalError) {
  try {
    final reserve = userAgentMatch(
      path: matched.path,
      documentLang: matched.documentLang,
      userAgentSheet: matched.userAgentSheet,
      tree: matched.tree,
      environment: StyleEnvironment(
        pageWidth: matched.pageWidth,
        pageHeight: matched.pageHeight,
      ),
      internalError: internalError,
    );
    return _restyle(reserve, ReaderPreferences.none);
  } on GalleyException {
    rethrow;
  } on Object {
    final tree = matched.tree;
    final nodeCount = tree.nodeCount;
    final elementStyles = Int32List(nodeCount);
    for (var n = 0; n < nodeCount; n++) {
      if (tree.kindOf(n) != NodeKind.element) elementStyles[n] = -1;
    }
    return StyledDocument(
      styles: List.unmodifiable([ComputedStyle(ValueComputer.initialValues)]),
      elementStyles: elementStyles,
      pseudoElements: Int32List(0),
      pseudoKinds: Uint8List(0),
      pseudoStyles: Int32List(0),
      generatedTexts: const [],
      fontFaces: const [],
      pageMargins: null,
      internalError: internalError,
    );
  }
}

StyledDocument _restyle(
  MatchedDocument matched,
  ReaderPreferences preferences,
) {
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
  final pass = PreferencePass(preferences, matched);
  final active = pass.isActive;
  final familyTable = matched.familyTable;
  final familyCount = familyTable.length + 1;
  // Instantâneos da editora dos elementos de texto corrido (ver
  // [PublisherSnapshot]), internados; por nó, o índice (−1 = nenhum).
  final tracks = pass.tracksPublisher;
  final snapshots = <PublisherSnapshot>[];
  final snapshotIndex = <PublisherSnapshot, int>{};
  final elementSnapshots = tracks
      ? (Int32List(nodeCount)..fillRange(0, nodeCount, -1))
      : null;
  // Com instantâneos, o resultado depende também do instantâneo do pai: o
  // memo passa a ser (chave, instantâneo do pai) → (estilo, instantâneo).
  final trackedMemo = <(int, int), (int, int)>{};
  var lastSnapshot = -1;

  int styleFor(
    int parentStyle,
    int set,
    int kind,
    int flags, {
    required bool isRoot,
    int parentFlags = 0,
    bool isBody = false,
    int family = -1,
    int parentSnapshot = -1,
  }) {
    // kind: 0 = elemento, 1 + PseudoElement.index para pseudo-elementos.
    // As marcas de texto corrido entram na chave: elementos com marcas
    // diferentes nunca compartilham o cálculo (a passada de preferências
    // depende delas).
    var key =
        (((parentStyle + 1) * setCount + set) * 5 + kind) * ElementFlags.limit +
        flags;
    if (active) {
      // Escopo do pai (texto corrido, título), `body` e família mantida.
      final scope =
          parentFlags & (ElementFlags.inTextRun | ElementFlags.heading);
      key =
          ((key * 8 + scope) * 2 + (isBody ? 1 : 0)) * familyCount + family + 1;
    }
    if (tracks) {
      final known = trackedMemo[(key, parentSnapshot)];
      if (known != null) {
        lastSnapshot = known.$2;
        return known.$1;
      }
    } else {
      final known = memo[key];
      if (known != null) return known;
    }
    final cascaded = matched.sets[set];
    final values = computer.compute(
      cascaded,
      parent: parentStyle < 0 ? null : styles[parentStyle],
      isRoot: isRoot,
      pseudo: kind == 0 ? null : PseudoElement.values[kind - 1],
      fontScale: pass.fontScale,
    );
    PublisherSnapshot? own;
    if (active) {
      own = pass.apply(
        values,
        cascaded,
        flags: flags,
        parentFlags: parentFlags,
        isRoot: isRoot,
        isBody: isBody,
        isPseudo: kind != 0,
        publisherFamily: family < 0 ? null : familyTable[family],
        parentPublisher: parentSnapshot < 0 ? null : snapshots[parentSnapshot],
      );
    }
    final style = interner.indexOf(values);
    if (!tracks) return memo[key] = style;
    var snapshot = -1;
    if (own != null) {
      snapshot = snapshotIndex[own] ??= snapshots.length;
      if (snapshot == snapshots.length) snapshots.add(own);
    }
    trackedMemo[(key, parentSnapshot)] = (style, snapshot);
    lastSnapshot = snapshot;
    return style;
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
    final flags = matched.flags[n];
    final style = styleFor(
      parentStyle,
      matched.elementSets[n],
      0,
      flags,
      isRoot: isRoot,
      parentFlags: isRoot ? 0 : matched.flags[parent],
      isBody:
          pass.dependsOnBody &&
          tree.namespaceOf(n) == Namespaces.xhtml &&
          tree.localNameOf(n) == 'body',
      family: pass.keepsPublisherFamily(flags)
          ? matched.publisherFamilies[n]
          : -1,
      parentSnapshot: elementSnapshots == null || isRoot
          ? -1
          : elementSnapshots[parent],
    );
    if (elementSnapshots != null) elementSnapshots[n] = lastSnapshot;
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
        flags,
        isRoot: false,
        parentFlags: flags,
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
    pageBackground: pass.theme?.background,
    internalError: matched.internalError,
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
