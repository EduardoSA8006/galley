import 'dart:typed_data';

import 'computed_style.dart';
import 'selector.dart';
import 'stylesheet.dart';

/// Resultado do estilo de um documento (spec §8.6): uma tabela de estilos
/// distintos e arranjos tipados com o índice do estilo de cada elemento e
/// de cada pseudo-elemento presente. Transferível entre isolates sem cópia
/// profunda de objetos por elemento.
///
/// Os índices valem só dentro deste objeto; entre documentos (ou depois de
/// um `restyle`), compare estilos por valor ou por `stableHash`.
final class StyledDocument {
  /// Cria o resultado; use `restyle`.
  StyledDocument({
    required this.styles,
    required this.elementStyles,
    required Int32List pseudoElements,
    required Uint8List pseudoKinds,
    required Int32List pseudoStyles,
    required List<String?> generatedTexts,
    required this.fontFaces,
    required this.pageMargins,
    this.pageBackground,
  }) : assert(
         pseudoElements.length == pseudoKinds.length &&
             pseudoElements.length == pseudoStyles.length &&
             pseudoElements.length == generatedTexts.length,
         'arranjos de pseudo-elementos não paralelos',
       ),
       _pseudoElements = pseudoElements,
       _pseudoKinds = pseudoKinds,
       _pseudoStyles = pseudoStyles,
       _generatedTexts = generatedTexts;

  /// Estilos distintos do documento.
  final List<ComputedStyle> styles;

  /// Por nó da árvore: índice em [styles]; −1 para nós que não são
  /// elemento (o texto usa o estilo do pai).
  final Int32List elementStyles;

  // Pseudo-elementos com estilo, em ordem de documento e, no mesmo
  // elemento, por `PseudoElement.index` crescente (arranjos paralelos).
  final Int32List _pseudoElements;
  final Uint8List _pseudoKinds;
  final Int32List _pseudoStyles;
  final List<String?> _generatedTexts;

  /// `@font-face` do documento, com o nome interno de cada família, para o
  /// layout registrar sob demanda.
  final List<FontFaceRule> fontFaces;

  /// Margens do `@page` da editora (lados ausentes = não definidos). Os
  /// lados ficam como comprimentos especificados (`em` incluso), resolvidos
  /// pelo layout, que combina com a preferência de margens.
  final PageMargins? pageMargins;

  /// Cor ARGB do fundo da página, quando um tema a impõe; `null` = sem
  /// imposição (vale o fundo da editora nos elementos).
  final int? pageBackground;

  /// Índice em [styles] do pseudo-elemento [kind] de [element], ou `null`
  /// se ele não existe (sem regra, ou `::before`/`::after` sem `content`).
  int? pseudoStyleOf(int element, PseudoElement kind) {
    final i = _entryOf(element, kind);
    return i < 0 ? null : _pseudoStyles[i];
  }

  /// Texto gerado de `::before`/`::after` de [element] (strings, `attr()` e
  /// aspas; contadores ficam vazios até o SP8); `null` para os demais
  /// pseudo-elementos ou se ele não existe.
  String? generatedTextOf(int element, PseudoElement kind) {
    final i = _entryOf(element, kind);
    return i < 0 ? null : _generatedTexts[i];
  }

  int _entryOf(int element, PseudoElement kind) {
    final e = _pseudoElements;
    var lo = 0;
    var hi = e.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (e[mid] < element) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    for (var i = lo; i < e.length && e[i] == element; i++) {
      if (_pseudoKinds[i] == kind.index) return i;
    }
    return -1;
  }

  /// Quantidade de estilos distintos.
  int get distinctStyleCount => styles.length;

  /// Bytes retidos (estimativa): arranjos, estilos e textos gerados. Os
  /// valores dentro dos estilos são em geral compartilhados com as folhas.
  int get retainedBytes {
    var bytes =
        64 +
        elementStyles.lengthInBytes +
        _pseudoElements.lengthInBytes +
        _pseudoKinds.lengthInBytes +
        _pseudoStyles.lengthInBytes +
        _generatedTexts.length * 8 +
        fontFaces.length * 8 +
        styles.length * 8;
    for (final s in styles) {
      bytes += s.retainedBytes;
    }
    for (final t in _generatedTexts) {
      if (t != null) bytes += 16 + t.length * 2;
    }
    return bytes;
  }
}
