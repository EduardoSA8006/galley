import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

import '../../../core/diagnostics/diagnostic.dart';
import '../../../core/diagnostics/diagnostic_codes.dart';
import '../domain/names.dart';
import 'event_adapter.dart';

/// Política do modo tolerante: lê XHTML com defeitos e os "vícios de HTML"
/// mais comuns (spec §8.4 e §8.8), sem ser um construtor de árvore HTML5
/// completo. Cada reparo gera um diagnóstico no local (`caminho:linha`).
///
/// - Um `<` (ou outro caractere) que não inicia marcação volta ao texto
///   (`document.markupAsText`).
/// - Fechamentos comparam nomes sem diferença de maiúsculas. Um fechamento
///   sem abertura é descartado (`document.strayEndTag`); com abertura, fecha
///   os elementos acima dela (`document.unclosedElement` para cada um).
/// - Fechamentos implícitos do HTML: `p` ao abrir um bloco, `li` ao abrir
///   `li`, `dt`/`dd` ao abrir `dt`/`dd`, `tr` ao abrir `tr`, `td`/`th` ao
///   abrir `td`/`th`/`tr` e `option` ao abrir `option`, cada um até a
///   fronteira de escopo do HTML (por exemplo, `<table>` para `td`)
///   (`document.unclosedElement`).
/// - Elementos vazios do HTML são fechados na hora; fechamentos deles são
///   ignorados.
/// - `<script>`/`<style>`: conteúdo bruto até o fechamento; comentários,
///   CDATA, instruções de processamento e doctypes sem terminador viram
///   texto, e doctypes são descartados antes da leitura (ver
///   [prepareTolerantText]).
/// - Em `text/html` ([html]), nomes de elemento e de atributo sem prefixo
///   vão para minúsculas (fora de `<svg>`/`<math>`, que mantêm a caixa), e
///   os fechamentos implícitos válidos em HTML (fim de tag opcional) saem
///   com severidade info em vez de warning.
/// - Conteúdo fora de `<html>`/`<body>` vai para `html`/`body` virtuais;
///   uma raiz `svg` não é envolvida. Os fechamentos da raiz e do `<body>`
///   não fecham nada (o que vier depois continua no `<body>`); tudo fecha
///   no fim do documento, e o que não teve fechamento gera
///   `document.unclosedElement` (nós virtuais não contam).
/// - Sem nenhum conteúdo, [endOfInput] lança [XmlParserException], e quem
///   chama devolve o documento irrecuperável.
///
/// Uma instância por documento (guarda estado da leitura). Toda operação
/// é O(1) amortizado por evento, mesmo em entradas patológicas.
final class TolerantRepairPolicy extends RepairPolicy {
  /// Cria a política para ler um documento; [html] para `text/html`.
  TolerantRepairPolicy({this.html = false});

  /// Se o documento é `text/html`.
  final bool html;

  /// Elementos cujo fechamento é opcional no HTML.
  static const Set<String> optionalEndTags = {
    'html',
    'head',
    'body',
    'p',
    'li',
    'dt',
    'dd',
    'tr',
    'td',
    'th',
    'option',
    'optgroup',
    'thead',
    'tbody',
    'tfoot',
    'colgroup',
    'caption',
    'rb',
    'rt',
    'rtc',
    'rp',
  };

  /// Elementos vazios do HTML.
  static const Set<String> voidElements = {
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
    'source',
    'track',
    'wbr',
  };

  /// Blocos que fecham um `<p>` aberto.
  static const Set<String> paragraphClosers = {
    'p',
    'div',
    'ul',
    'ol',
    'table',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'pre',
    'blockquote',
    'section',
    'article',
    'aside',
    'header',
    'footer',
    'nav',
    'figure',
    'hr',
  };

  // Fronteiras de escopo (HTML "has an element in … scope", simplificado).
  static const List<String> _scope = [
    'html',
    'table',
    'td',
    'th',
    'caption',
    'marquee',
    'object',
    'applet',
    'template',
  ];
  static const List<String> _buttonScope = [..._scope, 'button'];
  static const List<String> _listScope = [..._scope, 'ul', 'ol'];
  static const List<String> _definitionScope = [..._scope, 'dl'];
  static const List<String> _tableScope = ['html', 'table', 'template'];

  /// Nome bruto → chave em minúsculas (cache).
  final Map<String, String> _keys = {};

  /// Por chave, as posições na pilha dos elementos abertos com esse nome,
  /// da mais externa para a mais interna.
  final Map<String, List<int>> _positions = {};

  /// Por elemento aberto, em paralelo à pilha do adaptador: a chave e se é
  /// virtual.
  final List<String> _openKeys = [];
  final List<bool> _virtual = [];

  /// Se a raiz ganhou `html`/`body` (raiz `html` ou virtual).
  bool _wrap = false;

  /// Posição do `<body>` na pilha (sempre 1), ou −1 se ainda não há.
  int _body = -1;

  /// Se o fechamento da raiz ou do `<body>` já apareceu.
  bool _ended = false;

  /// Se um `<html>` tardio já foi juntado ao `html` virtual.
  bool _merged = false;

  /// Posições na pilha dos `<svg>`/`<math>` abertos (pelo nome local, com
  /// ou sem prefixo): dentro deles, `text/html` não muda a caixa.
  final List<int> _foreign = [];

  @override
  bool get validating => false;

  @override
  bool get withLocation => true;

  @override
  int get defaultNamespace => Namespaces.xhtml;

  @override
  String prepare(EventAdapter adapter, String text) =>
      prepareTolerantText(text, onDoctype: adapter.countDoctype);

  @override
  void onText(EventAdapter adapter, String value) {
    final blank = _isBlank(value);
    if (adapter.openDepth == 0) {
      if (blank) return;
      _wrap = true;
      _openVirtual(adapter, 'html');
    }
    if (blank) {
      // Espaço depois do fechamento da raiz ou do `<body>` é descartado.
      if (_ended && adapter.openDepth == (_body >= 0 ? 2 : 1)) return;
    } else if (_wrap && adapter.openDepth == 1) {
      _openBody(adapter);
    }
    adapter.appendText(value);
  }

  @override
  void onStart(EventAdapter adapter, XmlStartElementEvent event) =>
      _start(adapter, html ? _lowercased(event) : event);

  void _start(EventAdapter adapter, XmlStartElementEvent event) {
    final key = _key(event.name);
    if (adapter.openDepth == 0) {
      if (key == 'html' || _localPart(key) == 'svg') {
        _wrap = key == 'html';
        _open(adapter, event, key);
        return;
      }
      _wrap = true;
      _openVirtual(adapter, 'html');
    }
    if (_wrap) {
      // Um `<html>` tardio junta-se ao virtual (uma vez); um segundo
      // `<html>` ou `<body>` não abre nada.
      if (key == 'html') {
        if (!_merged && _virtual[0]) {
          _merged = true;
          adapter.mergeIntoRoot(event);
        }
        return;
      }
      if (key == 'body') {
        if (_body >= 0) return;
        _closeAbove(adapter, 0);
        _open(adapter, event, key);
        if (adapter.openDepth == 2) _body = 1;
        return;
      }
      if (key != 'head' && adapter.openDepth == 1) _openBody(adapter);
    }
    _implicitCloses(adapter, key);
    _open(adapter, event, key);
  }

  @override
  void onEnd(EventAdapter adapter, String name) {
    final key = _key(name);
    if (voidElements.contains(key)) return;
    final stack = _positions[key];
    if (stack == null || stack.isEmpty) {
      adapter.report(
        DiagnosticCodes.strayEndTag,
        DiagnosticSeverity.warning,
        'fechamento </$name> sem abertura correspondente; descartado',
      );
      return;
    }
    final target = stack.last;
    if (target == 0 || target == _body) {
      _closeAbove(adapter, _body >= 0 ? _body : 0);
      _ended = true;
      return;
    }
    _closeAbove(adapter, target);
    _pop(adapter);
  }

  @override
  void onMarkupError(EventAdapter adapter, int offset) {
    final char = adapter.source[offset];
    adapter.report(
      DiagnosticCodes.markupAsText,
      DiagnosticSeverity.warning,
      '"$char" não inicia marcação válida; mantido como texto',
    );
    onText(adapter, char);
  }

  @override
  void textOutsideRoot(EventAdapter adapter, String text) {}

  @override
  void extraRoot(EventAdapter adapter, XmlStartElementEvent event) {}

  @override
  void endTagMismatch(EventAdapter adapter, String name) {}

  @override
  void endOfInput(EventAdapter adapter) {
    if (!adapter.rootSeen) {
      throw XmlParserException('documento sem conteúdo');
    }
    while (adapter.openDepth > 0) {
      final index = adapter.openDepth - 1;
      final closedByTag = _ended && (index == 0 || index == _body);
      if (!_virtual[index] && !closedByTag) _reportUnclosed(adapter, index);
      _pop(adapter);
    }
  }

  void _implicitCloses(EventAdapter adapter, String key) {
    switch (key) {
      case 'li':
        _closeInScope(adapter, const ['li'], _listScope);
      case 'dt' || 'dd':
        _closeInScope(adapter, const ['dt', 'dd'], _definitionScope);
      case 'tr':
        _closeInScope(adapter, const ['td', 'th'], _tableScope);
        _closeInScope(adapter, const ['tr'], _tableScope);
      case 'td' || 'th':
        _closeInScope(adapter, const ['td', 'th'], _tableScope);
      case 'option':
        if (_openKeys.isNotEmpty && _openKeys.last == 'option') {
          _reportUnclosed(adapter, _openKeys.length - 1);
          _pop(adapter);
        }
    }
    if (paragraphClosers.contains(key)) {
      _closeInScope(adapter, const ['p'], _buttonScope);
    }
  }

  /// Fecha o elemento mais interno entre [targets], com tudo acima dele, se
  /// nenhuma fronteira de [boundaries] estiver mais para dentro.
  void _closeInScope(
    EventAdapter adapter,
    List<String> targets,
    List<String> boundaries,
  ) {
    final target = _innermost(targets);
    if (target < 0 || target < _innermost(boundaries)) return;
    _closeAbove(adapter, target);
    _reportUnclosed(adapter, target);
    _pop(adapter);
  }

  /// Posição mais interna de um elemento aberto com chave em [keys]; −1 se
  /// nenhum.
  int _innermost(List<String> keys) {
    var result = -1;
    for (final key in keys) {
      final stack = _positions[key];
      if (stack != null && stack.isNotEmpty && stack.last > result) {
        result = stack.last;
      }
    }
    return result;
  }

  /// Fecha os elementos acima da posição [index], cada um com
  /// `document.unclosedElement` (exceto os virtuais).
  void _closeAbove(EventAdapter adapter, int index) {
    while (adapter.openDepth > index + 1) {
      final top = adapter.openDepth - 1;
      if (!_virtual[top]) _reportUnclosed(adapter, top);
      _pop(adapter);
    }
  }

  void _reportUnclosed(EventAdapter adapter, int index) => adapter.report(
    DiagnosticCodes.unclosedElement,
    html && optionalEndTags.contains(_openKeys[index])
        ? DiagnosticSeverity.info
        : DiagnosticSeverity.warning,
    'elemento <${adapter.openNameAt(index)}> sem fechamento; '
    'fechado implicitamente',
  );

  void _open(EventAdapter adapter, XmlStartElementEvent event, String key) {
    adapter.openElement(event);
    if (event.isSelfClosing) return;
    if (voidElements.contains(key)) {
      adapter.closeElement();
      return;
    }
    _push(adapter, key, virtual: false);
  }

  void _openVirtual(EventAdapter adapter, String localName) {
    adapter.openVirtual(localName);
    _push(adapter, localName, virtual: true);
  }

  void _openBody(EventAdapter adapter) {
    _openVirtual(adapter, 'body');
    _body = 1;
  }

  void _push(EventAdapter adapter, String key, {required bool virtual}) {
    final index = adapter.openDepth - 1;
    if (_isForeign(key)) _foreign.add(index);
    (_positions[key] ??= []).add(index);
    _openKeys.add(key);
    _virtual.add(virtual);
  }

  void _pop(EventAdapter adapter) {
    if (_foreign.isNotEmpty && _foreign.last == _openKeys.length - 1) {
      _foreign.removeLast();
    }
    _positions[_openKeys.removeLast()]!.removeLast();
    _virtual.removeLast();
    adapter.closeElement();
  }

  String _key(String name) => _keys[name] ??= name.toLowerCase();

  /// [event] com os nomes sem prefixo em minúsculas (`text/html`). Dentro
  /// de `<svg>`/`<math>` nada muda; no próprio `<svg>`/`<math>`, só o nome
  /// do elemento.
  XmlStartElementEvent _lowercased(XmlStartElementEvent event) {
    if (_foreign.isNotEmpty) return event;
    final name = _lowerUnprefixed(event.name);
    final foreignRoot = _isForeign(_key(name));
    List<XmlEventAttribute>? attributes;
    if (!foreignRoot) {
      final original = event.attributes;
      for (var i = 0; i < original.length; i++) {
        final attribute = original[i];
        final lower = _lowerUnprefixed(attribute.name);
        if (identical(lower, attribute.name) && attributes == null) continue;
        attributes ??= original.sublist(0, i);
        attributes.add(
          identical(lower, attribute.name)
              ? attribute
              : XmlEventAttribute(
                  lower,
                  attribute.value,
                  attribute.attributeType,
                ),
        );
      }
    }
    if (identical(name, event.name) && attributes == null) return event;
    return XmlStartElementEvent(
      name,
      attributes ?? event.attributes,
      event.isSelfClosing,
    );
  }

  /// [name] em minúsculas se não tem prefixo; o próprio [name] se já está
  /// em minúsculas ou tem prefixo.
  String _lowerUnprefixed(String name) {
    if (name.contains(':')) return name;
    final key = _key(name);
    return key == name ? name : key;
  }

  static String _localPart(String key) => key.substring(key.indexOf(':') + 1);

  /// Se [key] é `svg` ou `math`, com ou sem prefixo. O namespace ainda não
  /// está resolvido quando se decide a caixa (as declarações do próprio
  /// elemento entram na abertura); o nome local basta para não mexer.
  static bool _isForeign(String key) {
    final local = _localPart(key);
    return local == 'svg' || local == 'math';
  }

  static bool _isBlank(String value) {
    for (var i = 0; i < value.length; i++) {
      final c = value.codeUnitAt(i);
      if (c != 0x20 && c != 0x09 && c != 0x0A && c != 0x0D) return false;
    }
    return true;
  }
}

/// Prepara [text] para a leitura tolerante, num único passe linear que
/// acompanha as tags como o `package:xml` as lê (valores de atributo entre
/// aspas incluídos):
///
/// - Conteúdo de `<script>`/`<style>` vira texto bruto: os `<` entre a
///   abertura e o fechamento correspondente (sem diferença de maiúsculas;
///   sem fechamento, até o fim) viram `&lt;`, que o `package:xml`
///   decodifica de volta. Seções CDATA terminadas dentro deles ficam como
///   estão.
/// - O `<` de um comentário, CDATA ou instrução de processamento sem
///   terminador à frente vira `&lt;` (texto). Sem isso, o `package:xml`
///   varreria até o fim a cada tentativa, em tempo quadrático.
/// - Um `<!DOCTYPE …>` é trocado por espaços (mantendo as quebras de
///   linha) e contado em [onDoctype]; sem terminador, vira texto.
///
/// As quebras de linha não mudam, então as linhas dos diagnósticos
/// continuam valendo. Devolve o próprio [text] se não há o que trocar.
String prepareTolerantText(String text, {void Function()? onDoctype}) =>
    _Preparer(text, onDoctype).run();

final class _Preparer {
  _Preparer(this.text, this.onDoctype)
    : length = text.length,
      _commentEnd = _Finder(text, '-->'),
      _cdataEnd = _Finder(text, ']]>'),
      _processingEnd = _Finder(text, '?>'),
      _greaterThan = _Finder(text, '>'),
      _bracketOpen = _Finder(text, '['),
      _bracketClose = _Finder(text, ']'),
      _doubleQuote = _Finder(text, '"'),
      _singleQuote = _Finder(text, "'"),
      _lessThan = _Finder(text, '<');

  final String text;
  final int length;
  final void Function()? onDoctype;
  final _Finder _commentEnd;
  final _Finder _cdataEnd;
  final _Finder _processingEnd;
  final _Finder _greaterThan;
  final _Finder _bracketOpen;
  final _Finder _bracketClose;
  final _Finder _doubleQuote;
  final _Finder _singleQuote;
  final _Finder _lessThan;

  /// O que interrompe a leitura de um doctype antes do subconjunto interno.
  late final List<_Finder> _doctypeStops = [
    _greaterThan,
    _bracketOpen,
    _doubleQuote,
    _singleQuote,
    _lessThan,
  ];

  StringBuffer? _out;
  int _copied = 0;

  String run() {
    var i = _next(0);
    while (i >= 0) {
      i = _next(_step(i));
    }
    final out = _out;
    if (out == null) return text;
    out.write(text.substring(_copied));
    return out.toString();
  }

  int _next(int from) => from < length ? text.indexOf('<', from) : -1;

  /// Trata a marcação que começa no `<` em [i]; devolve de onde seguir.
  int _step(int i) {
    if (text.startsWith('<!--', i)) {
      final end = _commentEnd.find(i + 4);
      return end < 0 ? _escape(i) : end + 3;
    }
    if (text.startsWith('<![CDATA[', i)) {
      final end = _cdataEnd.find(i + 9);
      return end < 0 ? _escape(i) : end + 3;
    }
    if (text.startsWith('<!', i) && _matchesName(text, i + 2, 'doctype')) {
      final end = _doctypeEnd(i + 9);
      if (end < 0) return _escape(i);
      _blank(i, end + 1);
      onDoctype?.call();
      return end + 1;
    }
    if (text.startsWith('<?', i)) {
      final end = _processingEnd.find(i + 2);
      return end < 0 ? _escape(i) : end + 2;
    }
    if (i + 1 < length && _isNameStart(text.codeUnitAt(i + 1))) {
      final end = _startTagEnd(i + 1);
      if (end < 0) return i + 1;
      final name = _rawTextName(text, i + 1);
      if (name == null || text.codeUnitAt(end - 1) == 0x2F) return end + 1;
      return _rawText(end + 1, name);
    }
    return i + 1;
  }

  /// Escapa os `<` do conteúdo bruto a partir de [from] até o fechamento
  /// de [name]; devolve a posição depois do `<` do fechamento (ou o fim).
  int _rawText(int from, String name) {
    var k = from;
    while (true) {
      k = _next(k);
      if (k < 0) return length;
      if (text.startsWith('<![CDATA[', k)) {
        final end = _cdataEnd.find(k + 9);
        if (end >= 0) {
          k = end + 3;
          continue;
        }
      } else if (_isClosingTag(text, k, name)) {
        return k + 1;
      }
      k = _escape(k);
    }
  }

  /// Fim (`>`) do doctype cujo nome começa depois de [from]; −1 se não
  /// há.
  ///
  /// Antes do subconjunto interno, literais entre aspas são pulados, e um
  /// `<` (fora ou dentro deles) desiste: os identificadores externos não
  /// têm `<`, e assim cada tentativa fica antes do próximo `<`. Com `[`, o
  /// fim é o primeiro `>` depois do `]` seguinte (aspas dentro do
  /// subconjunto não são consideradas: um `]` dentro de um valor de
  /// entidade é raro, e pular aspas ali poderia ficar quadrático).
  int _doctypeEnd(int from) {
    var k = from;
    while (true) {
      final stop = _firstOf(k);
      if (stop < 0) return -1;
      switch (text.codeUnitAt(stop)) {
        case 0x3E:
          return stop;
        case 0x5B:
          final close = _bracketClose.find(stop + 1);
          return close < 0 ? -1 : _greaterThan.find(close + 1);
        case final quote && (0x22 || 0x27):
          final close = (quote == 0x22 ? _doubleQuote : _singleQuote).find(
            stop + 1,
          );
          final less = _lessThan.find(stop + 1);
          if (close < 0 || (less >= 0 && less < close)) return -1;
          k = close + 1;
        default: // `<`
          return -1;
      }
    }
  }

  /// Primeira posição a partir de [from] de `>`, `[`, aspa ou `<`; −1 se
  /// nenhum.
  int _firstOf(int from) {
    var best = -1;
    for (final finder in _doctypeStops) {
      final at = finder.find(from);
      if (at >= 0 && (best < 0 || at < best)) best = at;
    }
    return best;
  }

  /// Fim (`>`) da tag de abertura cujo nome começa em [j], como a
  /// gramática do `package:xml` a lê (atributos separados por espaço, com
  /// valor entre aspas, sem aspas ou sem valor); −1 se não é uma tag.
  int _startTagEnd(int j) {
    var k = _skipName(j);
    while (true) {
      final spaced = k < length && _isSpace(text.codeUnitAt(k));
      k = _skipSpace(k);
      if (k >= length) return -1;
      final c = text.codeUnitAt(k);
      if (c == 0x3E) return k;
      if (c == 0x2F) {
        return k + 1 < length && text.codeUnitAt(k + 1) == 0x3E ? k + 1 : -1;
      }
      if (!spaced || !_isNameStart(c)) return -1;
      k = _skipName(k);
      final equals = _skipSpace(k);
      if (equals >= length || text.codeUnitAt(equals) != 0x3D) continue;
      k = _skipSpace(equals + 1);
      if (k >= length) return -1;
      final q = text.codeUnitAt(k);
      if (q == 0x22 || q == 0x27) {
        final end = (q == 0x22 ? _doubleQuote : _singleQuote).find(k + 1);
        if (end < 0) return -1;
        k = end + 1;
      } else if (_isNameChar(q)) {
        k = _skipName(k);
      } else {
        return -1;
      }
    }
  }

  int _skipName(int k) {
    while (k < length && _isNameChar(text.codeUnitAt(k))) {
      k++;
    }
    return k;
  }

  int _skipSpace(int k) {
    while (k < length && _isSpace(text.codeUnitAt(k))) {
      k++;
    }
    return k;
  }

  /// Troca o `<` em [i] por `&lt;`; devolve a posição seguinte.
  int _escape(int i) {
    _replace(i, i + 1, '&lt;');
    return i + 1;
  }

  /// Troca `text[from, to)` por espaços, mantendo as quebras de linha.
  void _blank(int from, int to) {
    final units = <int>[
      for (var k = from; k < to; k++) text.codeUnitAt(k) == 0x0A ? 0x0A : 0x20,
    ];
    _replace(from, to, String.fromCharCodes(units));
  }

  void _replace(int from, int to, String replacement) {
    (_out ??= StringBuffer())
      ..write(text.substring(_copied, from))
      ..write(replacement);
    _copied = to;
  }
}

/// `indexOf` de [pattern] com memória do último resultado: com consultas
/// em ordem crescente, cada trecho do texto é varrido no máximo uma vez.
final class _Finder {
  _Finder(this.text, this.pattern);

  final String text;
  final String pattern;
  int _from = 0;
  int _result = -2;

  /// Posição da primeira ocorrência a partir de [from], ou −1.
  int find(int from) {
    if (_result != -2 && from >= _from && (_result < 0 || from <= _result)) {
      return _result;
    }
    _from = from;
    _result = from <= text.length ? text.indexOf(pattern, from) : -1;
    return _result;
  }
}

bool _isSpace(int c) => c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;

/// Primeiro caractere de nome XML (aproximado: letras ASCII, `_`, `:` e
/// tudo a partir de U+00C0).
bool _isNameStart(int c) =>
    (c | 0x20) >= 0x61 && (c | 0x20) <= 0x7A ||
    c == 0x5F ||
    c == 0x3A ||
    c >= 0xC0;

bool _isNameChar(int c) =>
    _isNameStart(c) ||
    (c >= 0x30 && c <= 0x39) ||
    c == 0x2D ||
    c == 0x2E ||
    c == 0xB7;

/// `script` ou `style` se começam em [i] (sem diferença de maiúsculas) e
/// terminam num delimitador de tag; senão `null`.
String? _rawTextName(String text, int i) {
  for (final name in const ['script', 'style']) {
    if (_matchesName(text, i, name)) return name;
  }
  return null;
}

/// Se [name] (minúsculo) está em [i], sem diferença de maiúsculas, seguido
/// de espaço, `>`, `/` ou do fim.
bool _matchesName(String text, int i, String name) {
  final end = i + name.length;
  if (end > text.length) return false;
  for (var j = 0; j < name.length; j++) {
    if (text.codeUnitAt(i + j) | 0x20 != name.codeUnitAt(j)) return false;
  }
  if (end == text.length) return true;
  final c = text.codeUnitAt(end);
  return c == 0x3E || c == 0x2F || c == 0x20 || (c >= 0x09 && c <= 0x0D);
}

bool _isClosingTag(String text, int i, String name) =>
    i + 1 < text.length &&
    text.codeUnitAt(i + 1) == 0x2F &&
    _matchesName(text, i + 2, name);
