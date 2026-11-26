import 'dart:typed_data';

import '../../document/domain/document_tree.dart';
import '../../document/domain/names.dart';
import 'computed_style.dart';
import 'css_value.dart';
import 'matched_document.dart';
import 'properties.dart';
import 'stylesheet.dart';
import 'value_computer.dart';

/// Marcas por elemento guardadas no casamento ([MatchedDocument.flags]),
/// para a passada de preferências (spec §8.7).
abstract final class ElementFlags {
  /// Raiz de texto corrido: bloco com texto direto, fora de títulos,
  /// tabelas e `pre`, com tamanho a até ±15% do corpo. Só elementos XHTML.
  static const int textRunRoot = 1;

  /// A raiz de texto corrido e os seus descendentes em linha (um bloco
  /// interno é classificado por si mesmo).
  static const int inTextRun = 2;

  /// `h1`–`h6` e descendentes.
  static const int heading = 4;

  /// `a`/`area` com `href` e descendentes.
  static const int link = 8;

  /// A família da editora é monoespaçada.
  static const int monospace = 16;

  /// `display` calculado da editora é `list-item` (F10: o espaçamento entre
  /// parágrafos pula itens de lista, que continuam texto corrido para os
  /// demais ajustes).
  static const int listItem = 32;

  /// Maior valor possível das marcas somadas, mais um.
  static const int limit = 64;
}

/// Classificação do documento: marcas por nó, tamanho do corpo e família
/// da editora por elemento.
typedef TextRunMarks = ({
  Uint8List flags,
  double bodyFontSize,
  Int32List publisherFamilies,
  List<CssFontFamilies> familyTable,
});

/// Classifica os elementos de [tree] pelos valores calculados da editora
/// (sem preferências) da cascata [sets]/[elementSets] (spec §8.7).
///
/// Duas passadas em ordem de documento, **sem recursão**: a primeira
/// calcula os estilos da editora (com memo `(estilo do pai, conjunto)`) e
/// acha o primeiro `body` XHTML; a segunda marca. Sem `body` (item SVG do
/// spine, por exemplo), a referência é o tamanho da raiz.
TextRunMarks classifyTextRuns({
  required DocumentTree tree,
  required List<CascadedValues> sets,
  required Int32List elementSets,
  required List<FontFaceRule> fontFaces,
  required double pageWidth,
  required double pageHeight,
}) {
  final nodeCount = tree.nodeCount;
  final families = bookFamilyNames(fontFaces);
  // Nome interno → família original (minúsculas), para reconhecer uma
  // monoespaçada embutida pelo nome que a editora deu.
  final originalOf = {for (final e in families.entries) e.value: e.key};
  final computer = ValueComputer(
    internalFamilies: families,
    pageWidth: pageWidth,
    pageHeight: pageHeight,
  );
  final interner = StyleInterner();
  final styles = interner.styles;
  final styleOf = Int32List(nodeCount)..fillRange(0, nodeCount, -1);
  final memo = <int, int>{};
  final setCount = sets.length;

  var body = -1;
  var root = -1;
  for (var n = 0; n < nodeCount; n++) {
    if (tree.kindOf(n) != NodeKind.element) continue;
    final parent = tree.parentOf(n);
    final parentStyle = parent >= 0 ? styleOf[parent] : -1;
    final set = elementSets[n];
    final key = (parentStyle + 1) * setCount + set;
    var style = memo[key];
    if (style == null) {
      final isRoot = parentStyle < 0;
      style = interner.indexOf(
        computer.compute(
          sets[set],
          parent: isRoot ? null : styles[parentStyle],
          isRoot: isRoot,
        ),
      );
      memo[key] = style;
      if (isRoot && root < 0) {
        computer.rootFontSize = _fontSize(styles[style]);
      }
    }
    styleOf[n] = style;
    if (root < 0) root = n;
    if (body < 0 &&
        tree.namespaceOf(n) == Namespaces.xhtml &&
        tree.localNameOf(n) == 'body') {
      body = n;
    }
  }
  final reference = body >= 0 ? body : root;
  final bodyFontSize = reference >= 0
      ? _fontSize(styles[styleOf[reference]])
      : kInitialFontSize;

  final flags = Uint8List(nodeCount);
  // Por nó: dentro (ou é) de `pre`/`table` XHTML.
  final blocked = Uint8List(nodeCount);
  final publisherFamilies = Int32List(nodeCount)..fillRange(0, nodeCount, -1);
  final familyTable = <CssFontFamilies>[];
  final familyIndex = <CssFontFamilies, int>{};
  final familyMono = <bool>[];
  final hrefName = tree.names.lookup(Namespaces.none, 'href');

  // Texto "direto" de cada elemento: o dos filhos de texto mais o dos
  // descendentes em linha (sem atravessar outro bloco, `inline-block`,
  // tabela etc.), para `<p><span>x</span></p>` contar. Passada reversa:
  // em pré-ordem os filhos vêm depois do pai, então cada elemento já tem o
  // valor final quando é visitado e o repassa ao pai.
  final hasText = Uint8List(nodeCount);
  for (var n = nodeCount - 1; n >= 0; n--) {
    if (tree.kindOf(n) != NodeKind.element) continue;
    if (hasText[n] == 0 && _hasDirectText(tree, n)) hasText[n] = 1;
    // SVG/MathML embutidos são conteúdo substituído: o texto deles não
    // sobe para o bloco XHTML.
    if (hasText[n] == 0 || tree.namespaceOf(n) != Namespaces.xhtml) continue;
    final parent = tree.parentOf(n);
    if (parent < 0 || tree.kindOf(parent) != NodeKind.element) continue;
    final display = (styles[styleOf[n]][PropertyId.display] as CssKeyword).id;
    if (_inlineLevel.contains(display)) hasText[parent] = 1;
  }

  for (var n = 0; n < nodeCount; n++) {
    if (tree.kindOf(n) != NodeKind.element) continue;
    final style = styles[styleOf[n]];
    final parent = tree.parentOf(n);
    final isElementParent =
        parent >= 0 && tree.kindOf(parent) == NodeKind.element;
    final display = (style[PropertyId.display] as CssKeyword).id;
    // Título e link passam a todos os descendentes; o texto corrido só aos
    // descendentes em linha (`em`, `span`, `a`...): um bloco interno (`pre`,
    // tabela, título, epígrafe menor) é classificado por si mesmo.
    var f = isElementParent
        ? flags[parent] &
              (_inlineLevel.contains(display)
                  ? ElementFlags.inTextRun |
                        ElementFlags.heading |
                        ElementFlags.link
                  : ElementFlags.heading | ElementFlags.link)
        : 0;
    var inBlocked = isElementParent && blocked[parent] != 0;

    final xhtml = tree.namespaceOf(n) == Namespaces.xhtml;
    final name = xhtml ? tree.localNameOf(n) : '';
    if (xhtml) {
      if (name == 'pre' || name == 'table') inBlocked = true;
      if (_headings.contains(name)) f |= ElementFlags.heading;
      if ((name == 'a' || name == 'area') &&
          hrefName != null &&
          tree.attributeById(n, hrefName) != null) {
        f |= ElementFlags.link;
      }
    }

    if (display == CssKeywords.listItem) f |= ElementFlags.listItem;

    final family = style[PropertyId.fontFamily] as CssFontFamilies;
    var fi = familyIndex[family];
    if (fi == null) {
      fi = familyTable.length;
      familyTable.add(family);
      familyMono.add(_isMonospace(family, originalOf));
      familyIndex[family] = fi;
    }
    publisherFamilies[n] = fi;
    if (familyMono[fi]) f |= ElementFlags.monospace;

    if (xhtml &&
        !inBlocked &&
        (display == CssKeywords.block ||
            display == CssKeywords.listItem ||
            display == CssKeywords.flowRoot) &&
        !_excluded.contains(name) &&
        (_fontSize(style) - bodyFontSize).abs() <=
            _sizeTolerance * bodyFontSize + 1e-9 &&
        hasText[n] != 0) {
      f |= ElementFlags.textRunRoot | ElementFlags.inTextRun;
    }

    flags[n] = f;
    if (inBlocked) blocked[n] = 1;
  }

  return (
    flags: flags,
    bodyFontSize: bodyFontSize,
    publisherFamilies: publisherFamilies,
    familyTable: List.unmodifiable(familyTable),
  );
}

/// `display` que deixa o texto do elemento contar como texto direto do
/// bloco que o contém.
const Set<int> _inlineLevel = {
  CssKeywords.inline,
  CssKeywords.contents,
  CssKeywords.ruby,
  CssKeywords.rubyBase,
  CssKeywords.rubyText,
  CssKeywords.rubyBaseContainer,
  CssKeywords.rubyTextContainer,
};

/// Desvio máximo do tamanho do texto corrido sobre o do corpo (±15%).
const double _sizeTolerance = 0.15;

const Set<String> _headings = {'h1', 'h2', 'h3', 'h4', 'h5', 'h6'};

/// Elementos XHTML que nunca são raiz de texto corrido.
const Set<String> _excluded = {
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'td',
  'th',
  'caption',
  'pre',
  'figcaption',
};

/// Nomes (minúsculas) tratados como monoespaçados além do genérico.
const Set<String> _monospaceNames = {
  'monospaced',
  'courier',
  'courier new',
  'consolas',
  'menlo',
  'monaco',
  'lucida console',
};

double _fontSize(ComputedStyle style) =>
    (style[PropertyId.fontSize] as CssLength).px;

bool _isMonospace(CssFontFamilies value, Map<String, String> originalOf) {
  for (final f in value.families) {
    if (f.generic) {
      if (f.name == 'monospace') return true;
      continue;
    }
    final lower = originalOf[f.name] ?? f.name.toLowerCase();
    if (_monospaceNames.contains(lower)) return true;
  }
  return false;
}

/// Se [element] tem um filho de texto com algum caractere que não seja
/// espaço ASCII (espaço, tab, LF, CR, FF); U+00A0 conta como texto.
bool _hasDirectText(DocumentTree tree, int element) {
  final text = tree.text;
  for (var c = tree.firstChildOf(element); c != -1; c = tree.nextSiblingOf(c)) {
    if (tree.kindOf(c) != NodeKind.text) continue;
    final end = tree.textEndOf(c);
    for (var i = tree.textStartOf(c); i < end; i++) {
      switch (text.codeUnitAt(i)) {
        case 0x20 || 0x09 || 0x0A || 0x0D || 0x0C:
          continue;
        default:
          return true;
      }
    }
  }
  return false;
}
