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
/// - `<script>`/`<style>`: conteúdo bruto até o fechamento (ver
///   [escapeRawText]).
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
  /// Cria a política para ler um documento.
  TolerantRepairPolicy();

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

  @override
  bool get validating => false;

  @override
  bool get withLocation => true;

  @override
  int get defaultNamespace => Namespaces.xhtml;

  @override
  String prepare(String text) => escapeRawText(text);

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
  void onStart(EventAdapter adapter, XmlStartElementEvent event) {
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
      // Um segundo `<html>` ou `<body>` não abre nada.
      if (key == 'html') return;
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
    DiagnosticSeverity.warning,
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
    (_positions[key] ??= []).add(adapter.openDepth - 1);
    _openKeys.add(key);
    _virtual.add(virtual);
  }

  void _pop(EventAdapter adapter) {
    _positions[_openKeys.removeLast()]!.removeLast();
    _virtual.removeLast();
    adapter.closeElement();
  }

  String _key(String name) => _keys[name] ??= name.toLowerCase();

  static String _localPart(String key) => key.substring(key.indexOf(':') + 1);

  static bool _isBlank(String value) {
    for (var i = 0; i < value.length; i++) {
      final c = value.codeUnitAt(i);
      if (c != 0x20 && c != 0x09 && c != 0x0A && c != 0x0D) return false;
    }
    return true;
  }
}

/// [text] com o conteúdo de `<script>` e `<style>` tornado texto bruto: os
/// `<` entre a abertura e o fechamento correspondente (sem diferença de
/// maiúsculas; sem fechamento, até o fim) viram `&lt;`, que o
/// `package:xml` decodifica de volta. Seções CDATA dentro deles ficam como
/// estão. Comentários e CDATA fora deles são pulados. As quebras de linha
/// não mudam, então as linhas dos diagnósticos continuam valendo.
///
/// Um único passe linear; devolve o próprio [text] se não há o que trocar.
String escapeRawText(String text) {
  final length = text.length;
  StringBuffer? out;
  var copied = 0;
  var i = text.indexOf('<');
  while (i >= 0) {
    if (text.startsWith('<!--', i)) {
      i = _after(text, '-->', i + 4);
      continue;
    }
    if (text.startsWith('<![CDATA[', i)) {
      i = _after(text, ']]>', i + 9);
      continue;
    }
    final name = _rawTextName(text, i + 1);
    if (name == null) {
      i = i + 1 < length ? text.indexOf('<', i + 1) : -1;
      continue;
    }
    final tagEnd = _tagEnd(text, i + 1 + name.length);
    if (tagEnd < 0) break;
    if (text.codeUnitAt(tagEnd - 1) == 0x2F) {
      // `<script/>`: sem conteúdo.
      i = tagEnd + 1 < length ? text.indexOf('<', tagEnd + 1) : -1;
      continue;
    }
    var k = tagEnd + 1;
    while (true) {
      k = k < length ? text.indexOf('<', k) : -1;
      if (k < 0) break;
      if (text.startsWith('<![CDATA[', k)) {
        final end = text.indexOf(']]>', k + 9);
        k = end < 0 ? length : end + 3;
        continue;
      }
      if (_isClosingTag(text, k, name)) break;
      (out ??= StringBuffer())
        ..write(text.substring(copied, k))
        ..write('&lt;');
      copied = k + 1;
      k++;
    }
    // Continua depois do `<` do fechamento.
    i = k >= 0 && k + 1 < length ? text.indexOf('<', k + 1) : -1;
  }
  if (out == null) return text;
  out.write(text.substring(copied));
  return out.toString();
}

/// Próximo `<` depois de [terminator] (procurado a partir de [from]); −1
/// se não há.
int _after(String text, String terminator, int from) {
  final end = text.indexOf(terminator, from);
  if (end < 0) return -1;
  final next = end + terminator.length;
  return next < text.length ? text.indexOf('<', next) : -1;
}

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

/// Posição do `>` que fecha a tag a partir de [i], pulando valores entre
/// aspas; −1 se não há.
int _tagEnd(String text, int i) {
  var quote = 0;
  for (var j = i; j < text.length; j++) {
    final c = text.codeUnitAt(j);
    if (quote != 0) {
      if (c == quote) quote = 0;
    } else if (c == 0x22 || c == 0x27) {
      quote = c;
    } else if (c == 0x3E) {
      return j;
    }
  }
  return -1;
}
