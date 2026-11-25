import 'dart:typed_data';

import '../../document/domain/document_tree.dart';
import 'css_value.dart';
import 'style_environment.dart';
import 'stylesheet.dart';

/// Resultado da cascata da editora para um elemento (ou pseudo-elemento):
/// o valor vencedor de cada propriedade declarada, antes da herança e da
/// passada de preferências (spec §8.5, §8.6).
///
/// Internado dentro de um [MatchedDocument]: elementos com as mesmas
/// declarações vencedoras apontam para o mesmo objeto.
final class CascadedValues {
  /// Cria o conjunto; [properties] em ordem crescente, [values] paralelo.
  CascadedValues(this.properties, this.values)
    : assert(properties.length == values.length, 'arranjos não paralelos');

  /// Conjunto sem nenhuma declaração.
  static final CascadedValues empty = CascadedValues(Int32List(0), const []);

  /// Ids de `PropertyId` declarados, em ordem crescente.
  final Int32List properties;

  /// Valor vencedor de cada item de [properties].
  final List<CssValue> values;

  /// Valor vencedor de [property], ou `null` se não foi declarada.
  CssValue? valueOf(int property) {
    final i = _indexOf(property);
    return i < 0 ? null : values[i];
  }

  /// Se [property] foi declarada.
  bool declares(int property) => _indexOf(property) >= 0;

  int _indexOf(int property) {
    final p = properties;
    var lo = 0;
    var hi = p.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final v = p[mid];
      if (v == property) return mid;
      if (v < property) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return -1;
  }

  /// Bytes retidos: o arranjo, as referências e os cabeçalhos (os valores
  /// em si são compartilhados com as folhas).
  int get retainedBytes => 32 + properties.lengthInBytes + values.length * 8;
}

/// O casamento guardado de um documento (spec §8.6): a cascata da editora
/// por elemento e pseudo-elemento, autocontida para o `restyle` refazer só
/// a passada de preferências.
final class MatchedDocument {
  /// Cria o resultado; use `matchDocument`.
  MatchedDocument({
    required this.tree,
    required this.sets,
    required this.elementSets,
    required this.pseudoElements,
    required this.pseudoKinds,
    required this.pseudoSets,
    required this.fontFaces,
    required this.pageMargins,
    required this.pageWidth,
    required this.pageHeight,
    required this._mediaQueries,
    required this._mediaResults,
  });

  /// A árvore do documento.
  final DocumentTree tree;

  /// Conjuntos distintos de valores em cascata.
  final List<CascadedValues> sets;

  /// Por nó da árvore: índice em [sets]; −1 para nós que não são elemento.
  final Int32List elementSets;

  /// Elementos com pseudo-elemento casado, em ordem de documento (um item
  /// por pseudo-elemento; paralelo a [pseudoKinds] e [pseudoSets]).
  final Int32List pseudoElements;

  /// Índice de `PseudoElement` de cada item; dentro do mesmo elemento, em
  /// ordem crescente.
  final Uint8List pseudoKinds;

  /// Índice em [sets] de cada item.
  final Int32List pseudoSets;

  /// `@font-face` das folhas que se aplicam ao documento, na ordem da
  /// cascata.
  final List<FontFaceRule> fontFaces;

  /// Margens do `@page`: por lado, a do último `@page` com condições
  /// verdadeiras que a declara; `null` se nenhum declara margem.
  final PageMargins? pageMargins;

  /// Largura da página do ambiente do casamento, em px: base de `vw` onde o
  /// valor calculado precisa ser absoluto (`font-size`).
  final double pageWidth;

  /// Altura da página do ambiente do casamento, em px: base de `vh` onde o
  /// valor calculado precisa ser absoluto (`font-size`).
  final double pageHeight;

  final List<MediaQueryList> _mediaQueries;
  final List<bool> _mediaResults;

  /// `true` se todas as media queries avaliadas no casamento dão o mesmo
  /// resultado em [env]: o casamento continua valendo e só a passada de
  /// preferências precisa ser refeita.
  bool isValidFor(StyleEnvironment env) {
    for (var i = 0; i < _mediaQueries.length; i++) {
      if (_mediaQueries[i].evaluate(env) != _mediaResults[i]) return false;
    }
    return true;
  }

  /// Bytes retidos: a árvore, os arranjos e os conjuntos (estimativa).
  int get retainedBytes {
    var bytes =
        tree.retainedBytes +
        elementSets.lengthInBytes +
        pseudoElements.lengthInBytes +
        pseudoKinds.lengthInBytes +
        pseudoSets.lengthInBytes +
        sets.length * 8 +
        fontFaces.length * 8 +
        _mediaQueries.length * 9;
    for (final s in sets) {
      bytes += s.retainedBytes;
    }
    return bytes;
  }
}

/// Avalia e registra as media queries usadas no casamento, para
/// [MatchedDocument.isValidFor]. Cada lista é avaliada uma vez (por
/// identidade).
final class MediaChecks {
  /// Cria o registro para o ambiente [environment].
  MediaChecks(this.environment);

  /// O ambiente do casamento.
  final StyleEnvironment environment;

  final Map<MediaQueryList, int> _seen = Map.identity();

  /// Listas avaliadas, em ordem.
  final List<MediaQueryList> queries = [];

  /// Resultado de cada item de [queries].
  final List<bool> results = [];

  /// Resultado de [list] no ambiente, registrado.
  bool evaluate(MediaQueryList list) {
    final known = _seen[list];
    if (known != null) return results[known];
    final value = list.evaluate(environment);
    _seen[list] = queries.length;
    queries.add(list);
    results.add(value);
    return value;
  }

  /// Se todas as [conditions] valem (para na primeira falsa: as seguintes
  /// só importam enquanto ela for falsa, e ela já está registrada).
  bool all(List<MediaQueryList> conditions) {
    for (final c in conditions) {
      if (!evaluate(c)) return false;
    }
    return true;
  }
}
