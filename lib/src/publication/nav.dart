/// NAV do EPUB3 com `package:html` (spec da Publicação §7.2; doc/03 §8).
///
/// Linear no tamanho do NAV:
/// - antes do parse, [htmlWorkCut] re-serializa o texto como HTML canônico
///   (sem comentários, texto cru, SVG/MathML nem atributos que o NAV não lê)
///   e o corta onde o trabalho estimado do parser HTML5 passaria de
///   [navParseBudget] (o parser percorre a pilha de elementos abertos e a
///   lista de formatação ativa em várias tags, e aninhamento hostil o
///   deixaria quadrático: 4 000 níveis de `<ol><li>` custam 1,3 s, 50 000
///   custam 6 min);
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

/// Teto do trabalho estimado do parser HTML5 no NAV (~1 s no pior caso
/// medido com 4 MiB; um NAV plano de 100 000 entradas usa ~5 milhões).
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
  final work = htmlWorkCut(text);
  final Document document;
  try {
    document = html.parse(work.text);
  } on FormatException {
    // Rede de segurança. A única FormatException conhecida do package:html
    // (0.15.7) é o int.parse da referência numérica fora de faixa, que o
    // texto canônico já não tem; se outra versão lançar outra, o NAV conta
    // como inutilizável: sem entradas, e o leitor segue para o NCX
    // (navIgnored no-toc). Outros erros continuam sendo bug e propagam.
    return NavDocument(
      toc: const [],
      pageList: const [],
      landmarks: const [],
      truncated: false,
    );
  }
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
    truncated: work.cut != null || reader.truncatedAny,
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
  final out = <NavEntry>[];
  for (final node in list.nodes) {
    if (node is! Element || node.localName != 'li') continue;
    // Só descarta (e marca) se a lista além do limite tem alguma entrada.
    if (depth > maxNavDepth) {
      reader.truncate();
      break;
    }
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

/// Elementos que o `package:html` nunca empilha (inserir e desempilhar, ou
/// ignorar).
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

/// Elementos de texto cru (RCDATA, RAWTEXT, `plaintext`): saem do texto
/// canônico com o conteúdo.
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

/// Os atributos que [parseNav] lê; os outros saem do texto canônico.
const Set<String> _keptAttributes = {'alt', 'epub:type', 'href', 'title'};

/// Nome de tag acima disso vira um nome neutro ([_WorkModel.canonicalName]).
const int _maxTagNameLength = 32;

bool _isLetter(int c) => (c | 0x20) >= 0x61 && (c | 0x20) <= 0x7A;

bool _isUpper(int c) => c >= 0x41 && c <= 0x5A;

/// Whitespace do tokenizador (`\t`, `\n`, `\f`, `\r`, espaço).
bool _isSpace(int c) =>
    c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0C || c == 0x0D;

/// Fim do nome de tag: whitespace, `/` ou `>`.
bool _endsTagName(int c) => _isSpace(c) || c == 0x2F || c == 0x3E;

/// O texto que vai ao parser HTML5 ([parseNav]) e onde o original foi
/// cortado (`null` se coube inteiro).
typedef HtmlWork = ({String text, int? cut});

/// Tokeniza [text] e o re-serializa como um HTML canônico, o único texto que
/// o `html.parse` recebe, numa passada linear:
/// - comentários, DOCTYPE, `<?…>` e `<!…>` saem; CDATA vira texto escapado;
///   os elementos de texto cru ([_rawText] e `plaintext`) e as subárvores
///   `svg` e `math` saem com o conteúdo;
/// - tags só com os atributos que [parseNav] lê, entre aspas duplas; nome de
///   tag longo vira nome neutro, igual na abertura e no fechamento; `<x/>` de
///   elemento não vazio vira `<x></x>` (o HTML5 ignora a barra);
/// - no texto, `<` que não abre tag vira `&lt;`, e a referência numérica
///   acima de U+10FFFF vira `&#xFFFD;` (o tokenizador faz `int.parse` dos
///   dígitos e lançaria `FormatException` acima de 2^63);
/// - entre dois textos que no original não eram contíguos entra `<!---->`,
///   para o fim de um não continuar a referência do outro.
///
/// Nesse texto o tokenizador do `package:html` fica sempre nos estados de
/// dados e de tag, então o que ele vê é exatamente o que foi escrito. Sobre
/// esses tokens, uma pilha que nunca fica menor que a do parser estima o
/// trabalho da construção da árvore, e o texto é cortado onde ele passaria
/// de [budget]; `cut` é esse índice em [text].
///
/// Custo (em passos): tag `(profundidade + 1) × (formatação + 1)`, porque o
/// parser percorre a pilha e a lista de formatação ativa (e reconstrói os
/// clones dela); cada token de texto `1 + formatação × (profundidade + 1)`;
/// foster parenting, os nós já criados (o parser procura a tabela entre os
/// irmãos); `</h1>`–`</h6>` doze percursos, `</p>`/`</body>`/`</html>` dois;
/// `isindex` oito tags e seis nós. Um fechamento só desempilha pelo que o
/// parser também desempilharia (ver [_WorkModel.close]).
HtmlWork htmlWorkCut(String text, {int budget = navParseBudget}) =>
    _WorkModel(text, budget).run();

final class _WorkModel {
  _WorkModel(this.text, this.budget) : n = text.length;

  final String text;
  final int budget;
  final int n;
  final StringBuffer out = StringBuffer();

  /// Nomes dos elementos abertos.
  final List<String> stack = [];

  /// Índices de `table` e de `td`/`th`/`caption` em [stack].
  final List<int> tables = [];
  final List<int> cells = [];
  int work = 0;

  /// Elementos de formatação em [stack].
  int formatting = 0;

  /// Nós criados até aqui (limite para os irmãos de uma tabela).
  int nodes = 0;
  int? cutAt;

  /// A última coisa escrita foi texto, que terminava em [textEnd] no
  /// original; [fosterCharged] vale para esse texto.
  bool inText = false;
  int textEnd = -1;
  bool fosterCharged = false;

  /// Próximas ocorrências já buscadas (cada busca só anda para a frente).
  int nextAmp = -1;
  int nextNul = -1;
  int nextLt = -1;
  int nextDashDashGt = -1;
  int nextDashDashBangGt = -1;

  /// Preenchidos por [tagEnd]: terminou em `/>` fora de valor de atributo, e
  /// os atributos mantidos (nome, início e fim do valor; início -1 sem
  /// valor).
  bool selfClosing = false;
  final List<String> attrNames = [];
  final List<int> attrValues = [];

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

  HtmlWork run() {
    var i = 0;
    var from = 0;
    while (true) {
      final lt = find('<', from);
      if (lt >= n) {
        emitText(i, n);
        return result();
      }
      final c = lt + 1 < n ? text.codeUnitAt(lt + 1) : 0;
      final opens =
          _isLetter(c) || c == 0x21 || c == 0x3F || (c == 0x2F && lt + 2 < n);
      if (!opens) {
        // `<` solto: texto (vira `&lt;` em [emitText]).
        from = lt + 1;
        continue;
      }
      if (!emitText(i, lt)) return result();
      final int next;
      if (_isLetter(c)) {
        next = startTag(lt);
      } else if (c == 0x2F) {
        next = endTag(lt);
      } else if (c == 0x21) {
        next = markup(lt);
      } else {
        next = skipPast('>', lt + 2);
      }
      if (next < 0) return result();
      i = from = next;
    }
  }

  HtmlWork result() => (text: out.toString(), cut: cutAt);

  /// Escreve o texto [from, [to) do original (sem tag dentro, mas com `<`
  /// solto), cobrando os tokens; com [cdata], todo `&` e `<` sai escapado.
  bool emitText(int from, int to, {bool cdata = false}) {
    if (from >= to) return true;
    if (inText && from != textEnd) {
      if (!charge(1, from)) return false;
      nodes++;
      out.write('<!---->');
      inText = false;
    }
    if (!inText) {
      inText = true;
      fosterCharged = false;
      nodes += 1 + formatting;
      if (!charge(2 * textTokenCost, from)) return false;
    }
    textEnd = to;
    if (!fosterCharged && fosterContext) {
      var k = from;
      while (k < to && _isSpace(text.codeUnitAt(k))) {
        k++;
      }
      if (k < to) {
        fosterCharged = true;
        nodes++;
        if (!charge(nodes * (formatting + 1), k)) {
          out.write(text.substring(from, k));
          return false;
        }
      }
    }
    var copied = from;
    var k = from;
    while (true) {
      if (nextAmp < k) nextAmp = find('&', k);
      if (nextNul < k) nextNul = find('\u0000', k);
      if (nextLt < k) nextLt = find('<', k);
      var at = nextAmp < nextNul ? nextAmp : nextNul;
      if (nextLt < at) at = nextLt;
      if (at >= to) break;
      out.write(text.substring(copied, at));
      if (!charge(3 * textTokenCost, at)) return false;
      final c = text.codeUnitAt(at);
      copied = k = at + 1;
      if (c == 0x3C) {
        out.write('&lt;');
      } else if (c == 0x26) {
        if (cdata) {
          out.write('&amp;');
        } else {
          final e = badReferenceEnd(at, to);
          if (e < 0) {
            out.write('&');
          } else {
            out.write('&#xFFFD;');
            copied = k = e;
          }
        }
      } else {
        out.write('\u0000');
      }
    }
    out.write(text.substring(copied, to));
    return true;
  }

  /// Fim (depois do `;`, se houver) da referência numérica que começa no `&`
  /// em [at] se o valor passa de U+10FFFF, ou -1. O tokenizador consome
  /// todos os dígitos e faz `int.parse` deles, que lança acima de 2^63; acima
  /// de U+10FFFF ele já daria U+FFFD. Zeros à esquerda não contam.
  int badReferenceEnd(int at, int to) {
    if (at + 2 >= to || text.codeUnitAt(at + 1) != 0x23) return -1;
    var p = at + 2;
    final hex = text.codeUnitAt(p) | 0x20 == 0x78;
    if (hex) p++;
    final start = p;
    var value = 0;
    while (p < to) {
      final c = text.codeUnitAt(p);
      final int digit;
      if (c >= 0x30 && c <= 0x39) {
        digit = c - 0x30;
      } else if (hex && (c | 0x20) >= 0x61 && (c | 0x20) <= 0x66) {
        digit = (c | 0x20) - 0x61 + 10;
      } else {
        break;
      }
      if (value <= 0x10FFFF) value = value * (hex ? 16 : 10) + digit;
      p++;
    }
    if (p == start || value <= 0x10FFFF) return -1;
    return p < to && text.codeUnitAt(p) == 0x3B ? p + 1 : p;
  }

  /// Nome canônico: minúsculas ASCII (como o tokenizador; `toLowerCase`
  /// mapearia, por exemplo, o sinal de Kelvin para `k`); acima de
  /// [_maxTagNameLength], `x-` e um hash do nome, para que abertura e
  /// fechamento do mesmo nome continuem iguais.
  String canonicalName(int start, int end) {
    if (end - start > _maxTagNameLength) {
      var hash = 0x811C9DC5;
      for (var k = start; k < end; k++) {
        var c = text.codeUnitAt(k);
        if (_isUpper(c)) c += 0x20;
        hash = ((hash ^ c) * 0x01000193) & 0xFFFFFFFF;
      }
      return 'x-${hash.toRadixString(16)}';
    }
    var k = start;
    while (k < end && !_isUpper(text.codeUnitAt(k))) {
      k++;
    }
    if (k == end) return text.substring(start, end);
    final units = text.codeUnits.sublist(start, end);
    for (var j = k - start; j < units.length; j++) {
      if (_isUpper(units[j])) units[j] += 0x20;
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

  /// Tag de abertura: índice depois dela, ou -1 (fim do texto ou corte).
  int startTag(int lt) {
    final p = nameEnd(lt + 1);
    if (p >= n) return -1;
    final gt = tagEnd(p);
    if (gt < 0) return -1;
    final name = canonicalName(lt + 1, p);
    if (_rawText.contains(name)) {
      if (selfClosing) return gt + 1;
      final close = rawTextEnd(name, gt + 1);
      if (close >= n) return -1;
      return skipEndTag(close);
    }
    if (name == 'plaintext') return -1;
    if (name == 'svg' || name == 'math') {
      return selfClosing ? gt + 1 : skipForeign(gt + 1);
    }
    // `isindex` vira form, hr, label, um texto de 50 caracteres, input e hr:
    // oito tokens e seis nós a partir de nove bytes.
    var cost = name == 'isindex' ? 8 * depthCost + 128 : depthCost;
    if (fosterContext && !_notFostered.contains(name)) {
      cost += (nodes + 1) * (formatting + 1);
    }
    final isVoid = _voidElements.contains(name);
    final closeToo = selfClosing && !isVoid;
    if (closeToo) {
      cost += (stack.length + 2) * (formatting + 2) * _endTagWeight(name);
    }
    if (!charge(cost, lt)) return -1;
    nodes += 1 + formatting;
    inText = false;
    out
      ..write('<')
      ..write(name);
    writeAttributes();
    out.write('>');
    if (isVoid) return gt + 1;
    open(name);
    if (closeToo) {
      out
        ..write('</')
        ..write(name)
        ..write('>');
      close(name);
    }
    return gt + 1;
  }

  void writeAttributes() {
    for (var a = 0; a < attrNames.length; a++) {
      out
        ..write(' ')
        ..write(attrNames[a])
        ..write('="');
      final start = attrValues[2 * a];
      final end = attrValues[2 * a + 1];
      var copied = start;
      for (var k = start; k < end; k++) {
        final c = text.codeUnitAt(k);
        if (c == 0x22) {
          out
            ..write(text.substring(copied, k))
            ..write('&quot;');
          copied = k + 1;
        } else if (c == 0x26) {
          final e = badReferenceEnd(k, end);
          if (e >= 0) {
            out
              ..write(text.substring(copied, k))
              ..write('&#xFFFD;');
            copied = e;
            k = e - 1;
          }
        }
      }
      if (start < end) out.write(text.substring(copied, end));
      out.write('"');
    }
  }

  int endTag(int lt) {
    final c = text.codeUnitAt(lt + 2);
    if (c == 0x3E) return lt + 3; // `</>` é ignorado
    if (!_isLetter(c)) return skipPast('>', lt + 2);
    final p = nameEnd(lt + 2);
    if (p >= n) return -1;
    final gt = tagEnd(p);
    if (gt < 0) return -1;
    final name = canonicalName(lt + 2, p);
    var cost = depthCost * _endTagWeight(name);
    // `</br>` vira `<br>` e `</p>` sem p abre um p: inserções.
    if ((name == 'br' || name == 'p') && fosterContext) {
      cost += (nodes + 1) * (formatting + 1);
      nodes++;
    }
    if (!charge(cost, lt)) return -1;
    inText = false;
    out
      ..write('</')
      ..write(name)
      ..write('>');
    close(name);
    return gt + 1;
  }

  /// Fechamento do elemento de texto cru em [lt]: índice depois dele.
  int skipEndTag(int lt) {
    final p = nameEnd(lt + 2);
    if (p >= n) return -1;
    final gt = tagEnd(p);
    return gt < 0 ? -1 : gt + 1;
  }

  /// Percursos da pilha que o fechamento custa ao parser, em múltiplos de
  /// [depthCost] (medido no `package:html`): `</h1>`–`</h6>` testam o escopo
  /// de cada cabeçalho duas vezes; `</p>` sem p abre e fecha um;
  /// `</body>`/`</html>` testam o escopo do body.
  int _endTagWeight(String name) {
    if (name.length == 2 &&
        name.codeUnitAt(0) == 0x68 &&
        name.codeUnitAt(1) >= 0x31 &&
        name.codeUnitAt(1) <= 0x36) {
      return 12;
    }
    return name == 'p' || name == 'body' || name == 'html' ? 2 : 1;
  }

  /// `<!`: comentário e DOCTYPE saem; CDATA vira texto escapado.
  int markup(int lt) {
    if (text.startsWith('--', lt + 2)) return skipComment(lt);
    if (text.startsWith('[CDATA[', lt + 2)) {
      final close = find(']]>', lt + 9);
      if (!emitText(lt + 9, close, cdata: true)) return -1;
      return close >= n ? -1 : close + 3;
    }
    return skipPast('>', lt + 2);
  }

  /// Comentário: termina em `<!-->`, `<!--->`, no primeiro `-->` ou `--!>`.
  int skipComment(int lt) {
    if (nextDashDashGt < lt + 2) nextDashDashGt = find('-->', lt + 2);
    if (nextDashDashBangGt < lt + 4) {
      nextDashDashBangGt = find('--!>', lt + 4);
    }
    final a = nextDashDashGt + 2;
    final b = nextDashDashBangGt + 3;
    final end = a < b ? a : b;
    return end >= n ? -1 : end + 1;
  }

  /// Depois do próximo [pattern] a partir de [from], ou -1.
  int skipPast(String pattern, int from) {
    final at = find(pattern, from);
    return at >= n ? -1 : at + pattern.length;
  }

  /// Subárvore `svg`/`math` a partir de [from]: índice depois do fechamento
  /// que a encerra, ou -1. Dentro dela não há texto cru; CDATA vai até
  /// `]]>`.
  int skipForeign(int from) {
    var depth = 1;
    var k = from;
    while (true) {
      final lt = find('<', k);
      if (lt + 1 >= n) return -1;
      final c = text.codeUnitAt(lt + 1);
      if (c == 0x21) {
        if (text.startsWith('--', lt + 2)) {
          k = skipComment(lt);
        } else if (text.startsWith('[CDATA[', lt + 2)) {
          k = skipPast(']]>', lt + 9);
        } else {
          k = skipPast('>', lt + 2);
        }
      } else if (c == 0x3F) {
        k = skipPast('>', lt + 2);
      } else if (_isLetter(c) || (c == 0x2F && lt + 2 < n)) {
        final closing = c == 0x2F;
        final start = closing ? lt + 2 : lt + 1;
        if (closing && !_isLetter(text.codeUnitAt(start))) {
          k = text.codeUnitAt(start) == 0x3E ? start + 1 : skipPast('>', start);
        } else {
          final p = nameEnd(start);
          if (p >= n) return -1;
          final gt = tagEnd(p);
          if (gt < 0) return -1;
          final length = p - start;
          final foreign =
              length == 3 &&
                  (text.codeUnitAt(start) | 0x20) == 0x73 &&
                  (text.codeUnitAt(start + 1) | 0x20) == 0x76 &&
                  (text.codeUnitAt(start + 2) | 0x20) == 0x67 ||
              length == 4 &&
                  (text.codeUnitAt(start) | 0x20) == 0x6D &&
                  (text.codeUnitAt(start + 1) | 0x20) == 0x61 &&
                  (text.codeUnitAt(start + 2) | 0x20) == 0x74 &&
                  (text.codeUnitAt(start + 3) | 0x20) == 0x68;
          if (foreign && closing) {
            depth--;
            if (depth == 0) return gt + 1;
          } else if (foreign && !selfClosing) {
            depth++;
          }
          k = gt + 1;
        }
      } else {
        k = lt + 1;
      }
      if (k < 0) return -1;
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
  /// Guarda em [attrNames]/[attrValues] a primeira ocorrência de cada nome de
  /// [_keptAttributes].
  int tagEnd(int p) {
    selfClosing = false;
    attrNames.clear();
    attrValues.clear();
    const beforeName = 0;
    const attrName = 1;
    const afterName = 2;
    const beforeValue = 3;
    const unquoted = 4;
    const afterQuoted = 5;
    const selfClosingStart = 6;
    var nameStart = -1;
    var kept = false;
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
            nameStart = q;
          }
        case attrName:
          if (c == 0x3E || c == 0x3D || c == 0x2F || _isSpace(c)) {
            kept = keepAttribute(nameStart, q);
          }
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
            nameStart = q;
          }
        case beforeValue:
          if (c == 0x3E) return q;
          if (c == 0x22 || c == 0x27) {
            final quote = text.indexOf(c == 0x22 ? '"' : "'", q + 1);
            if (quote < 0) return -1;
            if (kept) setValue(q + 1, quote);
            kept = false;
            q = quote;
            state = afterQuoted;
          } else if (!_isSpace(c)) {
            state = unquoted;
            nameStart = q;
          }
        case unquoted:
          if (c == 0x3E || _isSpace(c)) {
            if (kept) setValue(nameStart, q);
            kept = false;
          }
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

  /// Registra o atributo [start, [end) se for de [_keptAttributes] e ainda
  /// não visto (o primeiro vale), com valor vazio até [tagEnd] achar o
  /// valor. Devolve se o valor que vier é dele.
  bool keepAttribute(int start, int end) {
    if (end - start > 9) return false;
    final name = canonicalName(start, end);
    if (!_keptAttributes.contains(name) || attrNames.contains(name)) {
      return false;
    }
    attrNames.add(name);
    attrValues.addAll([-1, -1]);
    return true;
  }

  void setValue(int start, int end) {
    attrValues[attrValues.length - 2] = start;
    attrValues[attrValues.length - 1] = end;
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
        if (stack.isNotEmpty && stack.last == 'option') {
          popTo(stack.length - 1);
        }
    }
    if (_formatting.contains(name)) formatting++;
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
      if (_formatting.contains(stack.removeLast())) formatting--;
    }
    while (tables.isNotEmpty && tables.last >= k) {
      tables.removeLast();
    }
    while (cells.isNotEmpty && cells.last >= k) {
      cells.removeLast();
    }
  }
}
