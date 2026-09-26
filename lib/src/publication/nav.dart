/// NAV do EPUB3 com `package:html` (spec da Publicação §7.2; doc/03 §8).
///
/// Linear no tamanho do NAV:
/// - antes do parse, [htmlWorkCut] corta o texto onde o trabalho estimado do
///   parser HTML5 passaria de [navParseBudget] (o parser percorre a pilha de
///   elementos abertos em várias tags, e aninhamento hostil o deixaria
///   quadrático: 4 000 níveis de `<ol><li>` custam 1,3 s, 50 000 custam
///   6 min);
/// - a caminhada itera `nodes` com pilha explícita, nunca indexa `children`;
/// - cada nó é visitado no máximo uma vez pela busca dos `nav`, uma pela
///   busca da lista do `nav`, uma pela varredura do `li` dono e uma pelo
///   título: nenhuma delas desce em `ol`/`ul` (a lista aninhada é do `li`
///   filho) nem em `nav` aninhado;
/// - a recursão por nível de lista para em [maxNavDepth].
library;

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

/// Profundidade máxima de entradas (spec §7.2).
const int maxNavDepth = 64;

/// Máximo de entradas por `nav` (spec §7.2).
const int maxNavEntries = 100000;

/// Teto do trabalho estimado do parser HTML5 no NAV (~0,7 s no pior caso
/// medido; um NAV real de 100 000 entradas usa ~3 milhões).
const int navParseBudget = 1 << 24;

/// Entrada crua de NAV ou NCX: o `href` como está no documento.
final class NavEntry {
  NavEntry({
    required this.title,
    this.href,
    this.type,
    List<NavEntry> children = const [],
  }) : children = List.unmodifiable(children);

  /// Texto com whitespace colapsado; `''` se não houver.
  final String title;

  /// Cru; `null` em entrada sem alvo.
  final String? href;

  /// `epub:type` do `a` (só em landmarks).
  final String? type;
  final List<NavEntry> children;

  @override
  String toString() => 'NavEntry($title, $href)';
}

/// O que o NAV fornece.
final class NavDocument {
  NavDocument({
    required List<NavEntry> toc,
    required List<NavEntry> pageList,
    required List<NavEntry> landmarks,
    required this.truncated,
  }) : toc = List.unmodifiable(toc),
       pageList = List.unmodifiable(pageList),
       landmarks = List.unmodifiable(landmarks);

  final List<NavEntry> toc;
  final List<NavEntry> pageList;
  final List<NavEntry> landmarks;

  /// Algum limite de §7.2 (ou o [navParseBudget]) foi atingido; a parte lida
  /// está nas listas.
  final bool truncated;
}

/// Lê os `nav` de `toc`, `page-list` e `landmarks` (o primeiro de cada tipo).
NavDocument parseNav(String text) {
  final cut = htmlWorkCut(text);
  final document = html.parse(cut == null ? text : text.substring(0, cut));
  Element? toc;
  Element? pageList;
  Element? landmarks;
  final stack = <Node>[document];
  while (stack.isNotEmpty) {
    final node = stack.removeLast();
    if (node is Element && node.localName == 'nav') {
      final types = _tokens(node.attributes['epub:type']);
      if (toc == null && types.contains('toc')) toc = node;
      if (pageList == null && types.contains('page-list')) pageList = node;
      if (landmarks == null && types.contains('landmarks')) landmarks = node;
    }
    _pushChildren(stack, node);
  }
  final reader = _Reader();
  return NavDocument(
    toc: _navEntries(toc, reader.reset(), landmark: false),
    pageList: _navEntries(pageList, reader.reset(), landmark: false),
    landmarks: _navEntries(landmarks, reader.reset(), landmark: true),
    truncated: cut != null || reader.truncatedAny,
  );
}

/// Filhos de [node] na pilha, em ordem reversa (sai em ordem de documento).
void _pushChildren(List<Node> stack, Node node) {
  final children = node.nodes;
  for (var i = children.length - 1; i >= 0; i--) {
    stack.add(children[i]);
  }
}

Set<String> _tokens(String? value) => value == null
    ? const {}
    : value.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toSet();

bool _isList(Node node) =>
    node is Element && (node.localName == 'ol' || node.localName == 'ul');

/// Contagem de entradas de um `nav`.
final class _Reader {
  int count = 0;
  bool truncated = false;
  bool truncatedAny = false;

  _Reader reset() {
    count = 0;
    truncated = false;
    return this;
  }

  void truncate() {
    truncated = true;
    truncatedAny = true;
  }
}

List<NavEntry> _navEntries(
  Element? nav,
  _Reader reader, {
  required bool landmark,
}) {
  if (nav == null) return const [];
  // A primeira lista do nav, sem descer em nav aninhado.
  final stack = <Node>[];
  _pushChildren(stack, nav);
  while (stack.isNotEmpty) {
    final node = stack.removeLast();
    if (_isList(node)) {
      return _list(node as Element, 1, reader, landmark: landmark);
    }
    if (node is Element && node.localName == 'nav') continue;
    _pushChildren(stack, node);
  }
  return const [];
}

List<NavEntry> _list(
  Element list,
  int depth,
  _Reader reader, {
  required bool landmark,
}) {
  if (depth > maxNavDepth) {
    reader.truncate();
    return const [];
  }
  final out = <NavEntry>[];
  for (final node in list.nodes) {
    if (node is! Element || node.localName != 'li') continue;
    if (reader.count >= maxNavEntries) {
      reader.truncate();
      break;
    }
    reader.count++;
    final (label, sublist) = _scanItem(node);
    final children = sublist == null
        ? const <NavEntry>[]
        : _list(sublist, depth + 1, reader, landmark: landmark);
    out.add(
      NavEntry(
        title: label == null ? '' : _title(label),
        href: label?.localName == 'a' ? label!.attributes['href'] : null,
        type: landmark ? label?.attributes['epub:type']?.trim() : null,
        children: children,
      ),
    );
  }
  return out;
}

/// O primeiro `a`/`span` e a primeira lista descendentes de [li], sem descer
/// em listas nem em `nav`.
(Element?, Element?) _scanItem(Element li) {
  Element? label;
  Element? sublist;
  final stack = <Node>[];
  _pushChildren(stack, li);
  while (stack.isNotEmpty && (label == null || sublist == null)) {
    final node = stack.removeLast();
    if (node is! Element) continue;
    if (_isList(node)) {
      sublist ??= node;
      continue;
    }
    if (node.localName == 'nav') continue;
    if (label == null && (node.localName == 'a' || node.localName == 'span')) {
      label = node;
    }
    _pushChildren(stack, node);
  }
  return (label, sublist);
}

/// Whitespace do HTML (U+00A0 não entra: é conteúdo).
final RegExp _whitespace = RegExp(r'[ \t\n\r\f]+');

/// Texto dos descendentes de [label] (sem descer em listas), colapsado;
/// vazio → `alt` do primeiro `img`; vazio → atributo `title`; vazio → `''`.
String _title(Element label) {
  final text = StringBuffer();
  String? alt;
  final stack = <Node>[];
  _pushChildren(stack, label);
  while (stack.isNotEmpty) {
    final node = stack.removeLast();
    if (node is Text) {
      text.write(node.data);
      continue;
    }
    if (node is! Element || _isList(node)) continue;
    if (alt == null && node.localName == 'img') alt = node.attributes['alt'];
    _pushChildren(stack, node);
  }
  for (final candidate in [
    text.toString(),
    alt ?? '',
    label.attributes['title'] ?? '',
  ]) {
    final collapsed = candidate.replaceAll(_whitespace, ' ').trim();
    if (collapsed.isNotEmpty) return collapsed;
  }
  return '';
}

const Set<String> _voidElements = {
  'area',
  'base',
  'br',
  'col',
  'embed',
  'hr',
  'img',
  'input',
  'link',
  'meta',
  'param',
  'source',
  'track',
  'wbr',
};

bool _isLetter(int c) => (c | 0x20) >= 0x61 && (c | 0x20) <= 0x7A;

bool _isNameChar(int c) =>
    _isLetter(c) ||
    (c >= 0x30 && c <= 0x39) ||
    c == 0x2D ||
    c == 0x3A ||
    c == 0x5F ||
    c == 0x2E;

/// Índice onde cortar [text] para o parse HTML5 não passar de [budget]
/// passos estimados, ou `null` se cabe inteiro.
///
/// Estimativa: uma pilha de nomes de tag. Abertura empilha (menos elementos
/// vazios e `/>`); fechamento desempilha até o nome, se ele está na pilha;
/// cada tag soma a profundidade corrente, e a busca do fechamento soma o que
/// percorre. Aninhamento real custa `profundidade × tags`, e o corte cai
/// antes de a conta passar do orçamento. Um índice de [text] é lido uma vez,
/// e o resto do trabalho está no orçamento: linear.
int? htmlWorkCut(String text, {int budget = navParseBudget}) {
  final stack = <String>[];
  final n = text.length;
  var work = 0;
  var i = 0;
  while (i < n) {
    final lt = text.indexOf('<', i);
    if (lt < 0 || lt + 1 >= n) return null;
    final c = text.codeUnitAt(lt + 1);
    if (c == 0x21) {
      // <!-- comentário -->, <!DOCTYPE>, <![CDATA[ ]]>
      final comment = text.startsWith('<!--', lt);
      final end = comment
          ? text.indexOf('-->', lt + 4)
          : text.indexOf('>', lt + 2);
      if (end < 0) return null;
      i = end + (comment ? 3 : 1);
      continue;
    }
    final closing = c == 0x2F;
    final start = closing ? lt + 2 : lt + 1;
    if (start >= n || !_isLetter(text.codeUnitAt(start))) {
      i = lt + 1;
      continue;
    }
    var p = start + 1;
    while (p < n && _isNameChar(text.codeUnitAt(p))) {
      p++;
    }
    final gt = text.indexOf('>', p);
    if (gt < 0) return null;
    work += stack.length + 1;
    if (work > budget) return lt;
    final name = text.substring(start, p).toLowerCase();
    if (closing) {
      final at = stack.lastIndexOf(name);
      work += at < 0 ? stack.length : stack.length - at;
      if (at >= 0) stack.length = at;
    } else if (text.codeUnitAt(gt - 1) != 0x2F &&
        !_voidElements.contains(name)) {
      stack.add(name);
    }
    i = gt + 1;
  }
  return null;
}
