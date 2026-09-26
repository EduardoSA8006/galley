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

/// Elementos que o `package:html` nunca empilha em conteúdo HTML (inserir e
/// desempilhar, ou ignorar). Em SVG/MathML eles empilham sem `/>`.
const Set<String> _voidElements = {
  'area',
  'base',
  'basefont',
  'bgsound',
  'br',
  'col',
  'embed',
  'frame',
  'hr',
  'image',
  'img',
  'input',
  'isindex',
  'keygen',
  'link',
  'meta',
  'param',
  'source',
  'track',
  'wbr',
};

/// Elementos de formatação: entram na lista de formatação ativa, que o
/// parser reconstrói (clona) e percorre a cada tag e a cada texto.
const Set<String> _formatting = {
  'a',
  'b',
  'big',
  'code',
  'em',
  'font',
  'i',
  'nobr',
  's',
  'small',
  'strike',
  'strong',
  'tt',
  'u',
};

/// Fechamento implícito ("generate implied end tags").
const Set<String> _impliedEnd = {
  'dd',
  'dt',
  'li',
  'option',
  'optgroup',
  'p',
  'rb',
  'rp',
  'rt',
  'rtc',
};

/// Os de [_impliedEnd] que não são "special": o fechamento de um nome
/// qualquer (e o adoption agency) passa por eles; `li`, `p`, `dd` e `dt` o
/// barram.
const Set<String> _nonSpecialImplied = {
  'option',
  'optgroup',
  'rb',
  'rp',
  'rt',
  'rtc',
};

/// Fechamentos que desempilham tudo acima do elemento se ele está em escopo
/// (`endTagBlock`, `endTagP`, `endTagListItem`, cabeçalhos, applet/marquee/
/// object); aqui só por cima de [_impliedEnd].
const Set<String> _scopedEnd = {
  'address',
  'applet',
  'article',
  'aside',
  'blockquote',
  'button',
  'center',
  'dd',
  'details',
  'dir',
  'div',
  'dl',
  'dt',
  'fieldset',
  'figcaption',
  'figure',
  'footer',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'header',
  'hgroup',
  'li',
  'listing',
  'marquee',
  'menu',
  'nav',
  'object',
  'ol',
  'p',
  'pre',
  'section',
  'summary',
  'ul',
};

/// Por onde a abertura de `li`/`dd`/`dt` procura o item aberto (o parser
/// passa por não "special" e por `address`, `div` e `p`).
const Set<String> _listItemPassable = {
  'p',
  'option',
  'optgroup',
  'rb',
  'rp',
  'rt',
  'rtc',
};

/// RCDATA e RAWTEXT do `package:html` em conteúdo HTML (`noscript` inclusive:
/// ele parseia com scripting ligado).
const Set<String> _rawText = {
  'iframe',
  'noembed',
  'noframes',
  'noscript',
  'script',
  'style',
  'textarea',
  'title',
  'xmp',
};

/// Contextos em que o modo do parser pode divergir do modelo: conteúdo
/// estrangeiro (onde `script`/`style` não são RAWTEXT e `<![CDATA[` é
/// CDATA) e os modos que ignoram tags (`select`, `frameset`).
const Set<String> _ambiguousContext = {'frameset', 'math', 'select', 'svg'};

/// Tags que o modo "in table" não insere por foster parenting (`input` só
/// escapa com `type=hidden`, e fica de fora).
const Set<String> _notFostered = {
  'caption',
  'col',
  'colgroup',
  'form',
  'script',
  'style',
  'table',
  'tbody',
  'td',
  'template',
  'tfoot',
  'th',
  'thead',
  'tr',
};

/// Entrada opaca na pilha: nenhum fechamento a casa nem passa por ela.
const String _opaque = '';

bool _isLetter(int c) => (c | 0x20) >= 0x61 && (c | 0x20) <= 0x7A;

/// Whitespace do tokenizador (`\t`, `\n`, `\f`, `\r`, espaço).
bool _isSpace(int c) =>
    c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0C || c == 0x0D;

/// Fim do nome de tag: whitespace, `/` ou `>`.
bool _endsTagName(int c) => _isSpace(c) || c == 0x2F || c == 0x3E;

/// Índice onde cortar [text] para o parse HTML5 não passar de [budget]
/// passos estimados, ou `null` se cabe inteiro.
///
/// O modelo segue o tokenizador do `package:html` (nome de tag até
/// whitespace, `/` ou `>`; atributos entre aspas; comentário até `-->`,
/// `--!>`, `<!-->` ou `<!--->`; DOCTYPE, `<?` e `</x` falso até o primeiro
/// `>`; RCDATA/RAWTEXT até o fechamento do próprio nome) e mantém uma pilha
/// que nunca fica menor que a do parser: um fechamento só desempilha pelo
/// que o parser também desempilharia (ver [_WorkModel.close]), e o que o
/// modelo não sabe classificar vira entrada opaca. O custo de cada tag é
/// `(profundidade + 1) × (formatação + 1)`, porque o parser percorre a pilha
/// e a lista de formatação ativa (e reconstrói os clones dela); cada texto
/// custa `1 + formatação × (profundidade + 1)`; nome de tag e DOCTYPE custam
/// `comprimento² / 256` (o tokenizador os monta concatenando caractere a
/// caractere); foster parenting custa os nós já criados (o parser procura a
/// tabela entre os irmãos). Cada índice de [text] é lido um número constante
/// de vezes e o resto do trabalho está no orçamento: linear.
int? htmlWorkCut(String text, {int budget = navParseBudget}) =>
    _WorkModel(text, budget).run();

final class _WorkModel {
  _WorkModel(this.text, this.budget) : n = text.length;

  final String text;
  final int budget;
  final int n;

  /// Nomes dos elementos abertos (ou [_opaque]).
  final List<String> stack = [];

  /// Índices de `table` e de `td`/`th`/`caption` em [stack].
  final List<int> tables = [];
  final List<int> cells = [];
  int work = 0;

  /// Elementos de formatação em [stack].
  int formatting = 0;

  /// `svg`/`math` em [stack].
  int foreign = 0;

  /// Elementos de [_ambiguousContext] em [stack].
  int ambiguous = 0;

  /// Nós criados até aqui (limite para os irmãos de uma tabela).
  int nodes = 0;
  int? cutAt;

  /// Texto corrente: início, e até onde já foi cobrado.
  int segment = 0;
  bool segmentCharged = false;
  int textScanned = 0;
  int whitespaceScanned = 0;
  bool fosterCharged = false;

  /// Próximas ocorrências já buscadas (cada busca só anda para a frente).
  int nextAmp = -1;
  int nextNul = -1;
  int nextDashDashGt = -1;
  int nextDashDashBangGt = -1;
  int nextCommentOpen = -1;
  int nextGt = -1;

  /// Terminou em `/>` fora de valor de atributo (preenchido por [tagEnd]).
  bool selfClosing = false;

  int get depthCost => (stack.length + 1) * (formatting + 1);

  /// Custo de um token de texto: o parser reconstrói a formatação ativa.
  int get textTokenCost => 1 + formatting * (stack.length + 1);

  /// Foster parenting possível: há `table` aberta sem célula acima dela.
  bool get fosterContext =>
      tables.isNotEmpty && (cells.isEmpty || cells.last < tables.last);

  int find(String pattern, int from) {
    final at = text.indexOf(pattern, from);
    return at < 0 ? n : at;
  }

  bool charge(int cost, int at) {
    work += cost;
    if (work <= budget) return true;
    cutAt = at;
    return false;
  }

  int? run() {
    var i = 0;
    while (true) {
      final lt = text.indexOf('<', i);
      if (!textUpTo(lt < 0 ? n : lt)) return cutAt;
      if (lt < 0 || lt + 1 >= n) return cutAt;
      final c = text.codeUnitAt(lt + 1);
      final int next;
      if (_isLetter(c)) {
        next = startTag(lt);
      } else if (c == 0x2F) {
        next = endTag(lt);
      } else if (c == 0x21) {
        next = markup(lt);
      } else if (c == 0x3F) {
        next = bogus(lt, lt + 2);
      } else {
        // `<` solto é texto, mas quebra o token de texto.
        if (!textUpTo(lt + 1) || !charge(3 * textTokenCost, lt)) return cutAt;
        i = lt + 1;
        continue;
      }
      if (next < 0) return cutAt;
      i = segment = next;
      segmentCharged = fosterCharged = false;
    }
  }

  /// Cobra o texto de [segment] até [end]: o início (dois tokens: espaços e
  /// resto), foster parenting se houver não whitespace, e cada `&` ou NUL
  /// (que partem o texto em até três tokens).
  bool textUpTo(int end) {
    if (end <= segment) return true;
    if (!segmentCharged) {
      segmentCharged = true;
      nodes += 1 + formatting;
      if (!charge(2 * textTokenCost, segment)) return false;
    }
    if (!fosterCharged && fosterContext) {
      var k = whitespaceScanned > segment ? whitespaceScanned : segment;
      while (k < end && _isSpace(text.codeUnitAt(k))) {
        k++;
      }
      whitespaceScanned = k;
      if (k < end) {
        fosterCharged = true;
        nodes++;
        if (!charge(nodes * (formatting + 1), k)) return false;
      }
    }
    var from = textScanned > segment ? textScanned : segment;
    while (true) {
      if (nextAmp < from) nextAmp = find('&', from);
      if (nextNul < from) nextNul = find('\u0000', from);
      final at = nextAmp < nextNul ? nextAmp : nextNul;
      if (at >= end) break;
      if (!charge(3 * textTokenCost, at)) return false;
      from = at + 1;
    }
    textScanned = end;
    return true;
  }

  /// Nome de tag em minúsculas ASCII (como o tokenizador; `toLowerCase`
  /// mapearia, por exemplo, o sinal de Kelvin para `k`).
  String tagName(int start, int end) {
    final units = text.codeUnits.sublist(start, end);
    for (var k = 0; k < units.length; k++) {
      final u = units[k];
      if (u >= 0x41 && u <= 0x5A) units[k] = u + 0x20;
    }
    return String.fromCharCodes(units);
  }

  /// Fim do nome que começa em [start]: o índice do terminador, ou [n].
  int nameEnd(int start) {
    var p = start;
    while (p < n && !_endsTagName(text.codeUnitAt(p))) {
      p++;
    }
    return p;
  }

  int nameCost(int length) => length * length >> 8;

  int startTag(int lt) {
    final p = nameEnd(lt + 1);
    final length = p - lt - 1;
    if (p >= n) {
      charge(nameCost(length), lt);
      return -1;
    }
    final gt = tagEnd(p);
    if (gt < 0) {
      charge(nameCost(length), lt);
      return -1;
    }
    final name = tagName(lt + 1, p);
    // `isindex` vira form, hr, label, um texto de 50 caracteres, input e hr:
    // oito tokens e seis nós a partir de nove bytes.
    var cost = name == 'isindex'
        ? 8 * depthCost + 128 + nameCost(length)
        : depthCost + nameCost(length);
    if (fosterContext && !_notFostered.contains(name)) {
      cost += (nodes + 1) * (formatting + 1);
    }
    if (!charge(cost, lt)) return -1;
    nodes += 1 + formatting;
    if (_voidElements.contains(name) && (foreign == 0 || selfClosing)) {
      return gt + 1;
    }
    if (name == 'plaintext') {
      if (ambiguous > 0) {
        open(_opaque);
        return opaqueRegion(gt + 1, n) < 0 ? -1 : n;
      }
      open(name);
      segment = gt + 1;
      segmentCharged = fosterCharged = false;
      textUpTo(n);
      return -1;
    }
    if (_rawText.contains(name)) {
      final close = rawTextEnd(name, gt + 1);
      if (ambiguous > 0) {
        open(_opaque);
        return opaqueRegion(gt + 1, close);
      }
      // `<!--` no script abre os estados de escape, e um `</script>` pode
      // não fechar: opaco.
      if (name == 'script') {
        if (nextCommentOpen < gt + 1) nextCommentOpen = find('<!--', gt + 1);
        open(nextCommentOpen < close ? _opaque : name);
      } else {
        open(name);
      }
      return close;
    }
    open(name);
    return gt + 1;
  }

  int endTag(int lt) {
    if (lt + 2 >= n) return -1;
    final c = text.codeUnitAt(lt + 2);
    if (c == 0x3E) return charge(1, lt) ? lt + 3 : -1;
    if (!_isLetter(c)) return bogus(lt, lt + 2);
    final p = nameEnd(lt + 2);
    final length = p - lt - 2;
    if (p >= n) {
      charge(nameCost(length), lt);
      return -1;
    }
    final gt = tagEnd(p);
    if (gt < 0) {
      charge(nameCost(length), lt);
      return -1;
    }
    final name = tagName(lt + 2, p);
    var cost = depthCost * _endTagWeight(name) + nameCost(length);
    // `</br>` vira `<br>` e `</p>` sem p abre um p: inserções.
    if ((name == 'br' || name == 'p') && fosterContext) {
      cost += (nodes + 1) * (formatting + 1);
      nodes++;
    }
    if (!charge(cost, lt)) return -1;
    close(name);
    return gt + 1;
  }

  /// Percursos da pilha que o fechamento custa ao parser, em múltiplos de
  /// [depthCost] (medido no `package:html`): `</h1>`–`</h6>` testam o escopo
  /// de cada cabeçalho duas vezes; `</p>` sem p abre e fecha um;
  /// `</body>`/`</html>` testam o escopo do body; em SVG/MathML o fechamento
  /// ainda compara cada nome em minúsculas antes.
  int _endTagWeight(String name) {
    var weight = 1;
    if (name.length == 2 &&
        name.codeUnitAt(0) == 0x68 &&
        name.codeUnitAt(1) >= 0x31 &&
        name.codeUnitAt(1) <= 0x36) {
      weight = 12;
    } else if (name == 'p' || name == 'body' || name == 'html') {
      weight = 2;
    }
    return foreign > 0 ? 2 * weight : weight;
  }

  /// `<!`: comentário, DOCTYPE, CDATA (só em conteúdo estrangeiro) ou
  /// comentário falso.
  int markup(int lt) {
    if (text.startsWith('--', lt + 2)) {
      if (!charge(1, lt)) return -1;
      nodes++;
      if (nextDashDashGt < lt + 2) nextDashDashGt = find('-->', lt + 2);
      if (nextDashDashBangGt < lt + 4) {
        nextDashDashBangGt = find('--!>', lt + 4);
      }
      final a = nextDashDashGt + 2;
      final b = nextDashDashBangGt + 3;
      final end = a < b ? a : b;
      return end >= n ? -1 : end + 1;
    }
    if (_startsWithDoctype(lt + 2)) {
      final gt = find('>', lt + 2);
      if (!charge(nameCost(gt - lt), lt)) return -1;
      return gt >= n ? -1 : gt + 1;
    }
    if (foreign > 0 && text.startsWith('[CDATA[', lt + 2)) {
      if (!charge(1, lt)) return -1;
      final close = find(']]>', lt + 9);
      if (opaqueRegion(lt + 9, close) < 0) return -1;
      return close >= n ? -1 : close + 3;
    }
    return bogus(lt, lt + 2);
  }

  bool _startsWithDoctype(int at) {
    const doctype = 'doctype';
    if (at + doctype.length > n) return false;
    for (var k = 0; k < doctype.length; k++) {
      if (text.codeUnitAt(at + k) | 0x20 != doctype.codeUnitAt(k)) {
        return false;
      }
    }
    return true;
  }

  /// Comentário falso até o primeiro `>`.
  int bogus(int lt, int from) {
    if (!charge(1, lt)) return -1;
    nodes++;
    final gt = find('>', from);
    return gt >= n ? -1 : gt + 1;
  }

  /// Onde o parser pode ou não ver tags: cada `<` empilha uma entrada opaca,
  /// nenhum fechamento é visto, e o custo é o do pior token que ali pode
  /// começar (o fechamento de cabeçalho em SVG, e um nome ou DOCTYPE até o
  /// próximo `>`). Devolve [to], ou -1 se cortou.
  int opaqueRegion(int from, int to) {
    var k = from;
    while (true) {
      final lt = text.indexOf('<', k);
      if (lt < 0 || lt >= to) return to;
      if (nextGt < lt) nextGt = find('>', lt);
      if (!charge(depthCost * 24 + nameCost(nextGt - lt), lt)) return -1;
      nodes++;
      open(_opaque);
      k = lt + 1;
    }
  }

  /// Índice do `<` do fechamento `</name` seguido de whitespace, `/` ou `>`
  /// (sem distinção de caixa ASCII), ou [n].
  int rawTextEnd(String name, int from) {
    var k = from;
    while (true) {
      final lt = text.indexOf('</', k);
      if (lt < 0) return n;
      final e = lt + 2 + name.length;
      if (e < n && _endsTagName(text.codeUnitAt(e))) {
        var same = true;
        for (var j = 0; j < name.length; j++) {
          if (text.codeUnitAt(lt + 2 + j) | 0x20 != name.codeUnitAt(j)) {
            same = false;
            break;
          }
        }
        if (same) return lt;
      }
      k = lt + 2;
    }
  }

  /// Índice do `>` da tag cujo nome termina em [p] (atributos como no
  /// tokenizador, valores entre aspas inteiros), ou -1 no fim do texto.
  int tagEnd(int p) {
    selfClosing = false;
    const beforeName = 0;
    const attrName = 1;
    const afterName = 2;
    const beforeValue = 3;
    const unquoted = 4;
    const afterQuoted = 5;
    const selfClosingStart = 6;
    final first = text.codeUnitAt(p);
    if (first == 0x3E) return p;
    var state = first == 0x2F ? selfClosingStart : beforeName;
    var q = p + 1;
    while (q < n) {
      final c = text.codeUnitAt(q);
      switch (state) {
        case beforeName:
          if (c == 0x3E) return q;
          if (c == 0x2F) {
            state = selfClosingStart;
          } else if (!_isSpace(c)) {
            state = attrName;
          }
        case attrName:
          if (c == 0x3E) return q;
          if (c == 0x3D) {
            state = beforeValue;
          } else if (c == 0x2F) {
            state = selfClosingStart;
          } else if (_isSpace(c)) {
            state = afterName;
          }
        case afterName:
          if (c == 0x3E) return q;
          if (c == 0x3D) {
            state = beforeValue;
          } else if (c == 0x2F) {
            state = selfClosingStart;
          } else if (!_isSpace(c)) {
            state = attrName;
          }
        case beforeValue:
          if (c == 0x3E) return q;
          if (c == 0x22 || c == 0x27) {
            final quote = text.indexOf(c == 0x22 ? '"' : "'", q + 1);
            if (quote < 0) return -1;
            q = quote;
            state = afterQuoted;
          } else if (!_isSpace(c)) {
            state = unquoted;
          }
        case unquoted:
          if (c == 0x3E) return q;
          if (_isSpace(c)) state = beforeName;
        case afterQuoted:
          if (c == 0x3E) return q;
          if (c == 0x2F) {
            state = selfClosingStart;
          } else {
            state = beforeName;
            if (!_isSpace(c)) continue;
          }
        default: // selfClosingStart
          if (c == 0x3E) {
            selfClosing = true;
            return q;
          }
          state = beforeName;
          continue;
      }
      q++;
    }
    return -1;
  }

  /// Abertura: o que o parser fecha antes de inserir, depois empilha.
  void open(String name) {
    switch (name) {
      case 'li':
        closeListItem(const {'li'});
        closeP();
      case 'dd' || 'dt':
        closeListItem(const {'dd', 'dt'});
        closeP();
      case 'p':
        closeP();
      case 'option' || 'optgroup':
        // Em SVG/MathML `option` é elemento estrangeiro e não fecha nada.
        if (foreign == 0 && stack.isNotEmpty && stack.last == 'option') {
          popTo(stack.length - 1);
        }
    }
    if (_formatting.contains(name)) formatting++;
    if (name == 'svg' || name == 'math') foreign++;
    if (_ambiguousContext.contains(name)) ambiguous++;
    if (name == 'table') tables.add(stack.length);
    if (name == 'td' || name == 'th' || name == 'caption') {
      cells.add(stack.length);
    }
    stack.add(name);
  }

  /// `li` fecha o `li` aberto (`dd`/`dt` fecham `dd`/`dt`) por cima de
  /// [_listItemPassable].
  void closeListItem(Set<String> targets) {
    for (var k = stack.length - 1; k >= 0; k--) {
      final e = stack[k];
      if (targets.contains(e)) {
        popTo(k);
        return;
      }
      if (!_listItemPassable.contains(e)) return;
    }
  }

  /// "Close a p element" por cima de [_impliedEnd].
  void closeP() {
    for (var k = stack.length - 1; k >= 0; k--) {
      final e = stack[k];
      if (e == 'p') {
        popTo(k);
        return;
      }
      if (!_impliedEnd.contains(e)) return;
    }
  }

  /// Fechamento: desempilha até [name] só se ele está no topo ou abaixo de
  /// elementos que o parser também fecharia no caminho — [_impliedEnd] para
  /// os fechamentos com escopo, [_nonSpecialImplied] para os outros (o
  /// parser ignora o fechamento ao encontrar um "special"). `</body>` e
  /// `</html>` só mudam o modo; `</head>` fecha o head no topo.
  void close(String name) {
    if (name == 'body' || name == 'html' || name == 'br') return;
    if (name == 'head') {
      if (stack.isNotEmpty && stack.last == 'head') popTo(stack.length - 1);
      return;
    }
    final passable = _scopedEnd.contains(name)
        ? _impliedEnd
        : _nonSpecialImplied;
    for (var k = stack.length - 1; k >= 0; k--) {
      final e = stack[k];
      if (e == name) {
        popTo(k);
        return;
      }
      if (!passable.contains(e)) return;
    }
  }

  void popTo(int k) {
    while (stack.length > k) {
      final e = stack.removeLast();
      if (_formatting.contains(e)) formatting--;
      if (e == 'svg' || e == 'math') foreign--;
      if (_ambiguousContext.contains(e)) ambiguous--;
    }
    while (tables.isNotEmpty && tables.last >= k) {
      tables.removeLast();
    }
    while (cells.isNotEmpty && cells.last >= k) {
      cells.removeLast();
    }
  }
}
