import 'dart:typed_data';

import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

import '../../../core/diagnostics/diagnostic.dart';
import '../../../core/diagnostics/diagnostic_codes.dart';
import '../domain/document_tree.dart';
import '../domain/names.dart';
import '../domain/tree_builder.dart';

/// O que o [EventAdapter] faz quando a sequência de eventos não forma uma
/// árvore bem formada.
///
/// A política estrita ([StrictRepairPolicy]) não repara nada: lança
/// [XmlParserException], e quem chama decide o que fazer com o documento.
abstract base class RepairPolicy {
  /// Construtor para as subclasses.
  const RepairPolicy();

  /// Se o `parseEvents` valida o aninhamento das tags e a estrutura do
  /// documento (raiz única, declaração e doctype no lugar).
  bool get validating;

  /// Texto que não é só espaço em branco fora do elemento raiz.
  void textOutsideRoot(EventAdapter adapter, String text);

  /// Elemento depois do fechamento do elemento raiz.
  void extraRoot(EventAdapter adapter, XmlStartElementEvent event);

  /// Fechamento [name] sem elemento aberto ou diferente do aberto.
  void endTagMismatch(EventAdapter adapter, String name);

  /// Fim da entrada sem elemento raiz ou com elementos abertos.
  void endOfInput(EventAdapter adapter);
}

/// Política do caminho estrito: qualquer defeito estrutural lança
/// [XmlParserException].
final class StrictRepairPolicy extends RepairPolicy {
  /// Cria a política estrita.
  const StrictRepairPolicy();

  @override
  bool get validating => true;

  @override
  void textOutsideRoot(EventAdapter adapter, String text) =>
      throw XmlParserException('texto fora do elemento raiz');

  @override
  void extraRoot(EventAdapter adapter, XmlStartElementEvent event) =>
      throw XmlParserException('segundo elemento raiz <${event.name}>');

  @override
  void endTagMismatch(EventAdapter adapter, String name) =>
      throw XmlParserException('fechamento inesperado </$name>');

  @override
  void endOfInput(EventAdapter adapter) => throw XmlParserException(
    adapter.rootSeen
        ? 'fim do documento com elemento(s) aberto(s)'
        : 'documento sem elemento raiz',
  );
}

/// Converte os eventos do `parseEvents` do `package:xml` numa
/// [DocumentTree], com a própria pilha de namespaces.
///
/// - Nomes viram (namespace, nome local); declarações `xmlns`/`xmlns:p`
///   alimentam a pilha e não viram atributos. Os prefixos são resolvidos
///   depois de lidas todas as declarações do elemento.
/// - O texto passa por [normalizeLineEnds] (XML §2.11) antes da leitura.
/// - `epub:` e `xlink:` sem declaração caem em OPS e XLink; `xml:` é sempre o namespace XML;
///   outros prefixos sem declaração ficam em
///   [Namespaces.undeclaredPrefixUri], com o nome qualificado. Cada
///   prefixo sem declaração gera um `document.undeclaredPrefix`.
/// - Atributos sem prefixo ficam em [Namespaces.none]; com atributo
///   repetido, vale o primeiro (`document.duplicateAttribute`).
/// - Valores de atributo: TAB, LF e CR viram espaço (XML §3.3.3, sem
///   distinguir referências de caractere, já decodificadas pelo
///   `package:xml`). Caracteres proibidos no XML 1.0 (controles, surrogate
///   isolado, U+FFFE/U+FFFF) viram U+FFFD no texto e nos atributos, sem
///   mudar o comprimento.
/// - Declarações ilegais (`xmlns:p=""`, `xmlns:="…"`) são ignoradas, com
///   `document.invalidNamespaceDeclaration`.
/// - CDATA vira texto; comentários, PIs e doctype são descartados e
///   contados (`document.droppedNodes`), e o texto em volta deles é
///   fundido pelo montador. Espaço em branco fora da raiz é ignorado.
///
/// Cada instância lê um único documento.
final class EventAdapter {
  /// Cria o adaptador de um documento em [path] (local dos diagnósticos).
  EventAdapter({required this.path, this.policy = const StrictRepairPolicy()});

  /// Entidades HTML5 completas, nos dois caminhos. Instância `const` única:
  /// o `package:xml` guarda o parser compilado por mapeamento.
  static const XmlEntityMapping entities = XmlDefaultEntityMapping.html5();

  /// Caminho do documento no EPUB.
  final String path;

  /// Política para defeitos estruturais.
  final RepairPolicy policy;

  /// O montador da árvore.
  final TreeBuilder builder = TreeBuilder();

  /// Diagnósticos emitidos até aqui, em ordem.
  final List<Diagnostic> diagnostics = [];

  /// Se o elemento raiz já foi aberto.
  bool get rootSeen => _rootSeen;
  bool _rootSeen = false;

  // Pilha de declarações de prefixo: (prefixo, namespace), em paralelo.
  final List<String> _prefixes = [];
  final List<int> _prefixNamespaces = [];

  // Por elemento aberto: início das suas declarações em _prefixes, o
  // namespace padrão em vigor e o nome bruto (para conferir o fechamento).
  final List<int> _frames = [];
  final List<int> _defaults = [];
  final List<String> _openNames = [];

  /// Cache nome qualificado → id, conferido pelo namespace (o mesmo
  /// prefixo pode mudar de namespace conforme o escopo).
  final Map<String, int> _qualified = {};

  /// Ids dos atributos do elemento em curso, para achar repetições.
  final List<int> _attributeIds = [];

  /// Prefixos sem declaração já reportados; os conhecidos (`epub`,
  /// `xlink`) ficam à parte, um bit por id de namespace.
  Set<String>? _undeclared;
  int _wellKnownReported = 0;
  int _comments = 0;
  int _instructions = 0;
  int _doctypes = 0;

  /// Lê [text] inteiro e devolve a árvore.
  ///
  /// Defeitos estruturais vão para a [policy]; com a política estrita, a
  /// [XmlException] do `package:xml` ou da política propaga.
  DocumentTree run(String text) {
    final events = parseEvents(
      text.contains('\r') ? normalizeLineEnds(text) : text,
      entityMapping: entities,
      validateNesting: policy.validating,
      validateDocument: policy.validating,
    );
    for (final event in events) {
      switch (event) {
        case XmlTextEvent():
          _text(event.value);
        case XmlStartElementEvent():
          _start(event);
        case XmlEndElementEvent():
          _endTag(event.name);
        case XmlCDATAEvent():
          _text(event.value);
        case XmlCommentEvent():
          _comments++;
        case XmlProcessingEvent():
          _instructions++;
        case XmlDoctypeEvent():
          _doctypes++;
        case XmlDeclarationEvent():
          break;
      }
    }
    if (!_rootSeen || _openNames.isNotEmpty) policy.endOfInput(this);
    _reportDropped();
    return builder.build();
  }

  void _text(String value) {
    if (_openNames.isNotEmpty) {
      builder.text(_sanitize(value, attribute: false));
    } else if (!_isBlank(value)) {
      policy.textOutsideRoot(this, value);
    }
  }

  void _start(XmlStartElementEvent event) {
    if (_openNames.isEmpty) {
      if (_rootSeen) {
        policy.extraRoot(this, event);
        return;
      }
      _rootSeen = true;
    }
    final attributes = event.attributes;
    _frames.add(_prefixes.length);
    var defaultNamespace = _defaults.isEmpty ? Namespaces.none : _defaults.last;
    var declarations = 0;
    for (var i = 0; i < attributes.length; i++) {
      final attribute = attributes[i];
      final name = attribute.name;
      if (!_isDeclaration(name)) continue;
      declarations++;
      final value = attribute.value;
      if (name.length == 5) {
        defaultNamespace = value.isEmpty
            ? Namespaces.none
            : builder.names.internNamespace(value);
      } else if (name.length == 6 || value.isEmpty) {
        // `xmlns:="…"` e `xmlns:p=""` são ilegais (Namespaces in XML).
        diagnostics.add(
          Diagnostic(
            severity: DiagnosticSeverity.info,
            code: DiagnosticCodes.invalidNamespaceDeclaration,
            message: 'declaração "$name="$value"" ilegal; ignorada',
            location: path,
          ),
        );
      } else {
        _prefixes.add(name.substring(6));
        _prefixNamespaces.add(builder.names.internNamespace(value));
      }
    }
    _defaults.add(defaultNamespace);
    _openNames.add(event.name);

    builder.startElement(_resolve(event.name, defaultNamespace));
    if (attributes.length > declarations) {
      _attributes(event.name, attributes);
    }
    if (event.isSelfClosing) _close();
  }

  void _attributes(String element, List<XmlEventAttribute> attributes) {
    final ids = _attributeIds..clear();
    var duplicates = 0;
    for (var i = 0; i < attributes.length; i++) {
      final attribute = attributes[i];
      final name = attribute.name;
      if (_isDeclaration(name)) continue;
      final id = _resolve(name, Namespaces.none);
      if (ids.contains(id)) {
        duplicates++;
        continue;
      }
      ids.add(id);
      builder.attribute(id, _sanitize(attribute.value, attribute: true));
    }
    if (duplicates > 0) {
      diagnostics.add(
        Diagnostic(
          severity: DiagnosticSeverity.info,
          code: DiagnosticCodes.duplicateAttribute,
          message:
              '$duplicates atributo(s) repetido(s) em <$element>; '
              'vale o primeiro',
          location: path,
        ),
      );
    }
  }

  void _endTag(String name) {
    if (_openNames.isEmpty || _openNames.last != name) {
      policy.endTagMismatch(this, name);
      return;
    }
    _close();
  }

  /// Fecha o elemento aberto mais interno e o seu escopo de namespaces.
  void _close() {
    builder.endElement();
    final frame = _frames.removeLast();
    if (_prefixes.length > frame) {
      _prefixes.length = frame;
      _prefixNamespaces.length = frame;
    }
    _defaults.removeLast();
    _openNames.removeLast();
  }

  /// Id do nome [qualified]; sem prefixo, vai para [unprefixed].
  int _resolve(String qualified, int unprefixed) {
    final colon = qualified.indexOf(':');
    if (colon <= 0) return builder.names.intern(unprefixed, qualified);
    final namespace = _prefixNamespace(qualified, colon);
    final cached = _qualified[qualified];
    if (cached != null && builder.names.namespaceOf(cached) == namespace) {
      return cached;
    }
    final local = namespace == _undeclaredNamespace
        ? qualified
        : qualified.substring(colon + 1);
    final id = builder.names.intern(namespace, local);
    _qualified[qualified] = id;
    return id;
  }

  int _undeclaredNamespace = -1;

  /// Namespace do prefixo `qualified[0, colon)`, pela pilha de
  /// declarações (sem alocar no caso comum).
  int _prefixNamespace(String qualified, int colon) {
    for (var i = _prefixes.length - 1; i >= 0; i--) {
      final prefix = _prefixes[i];
      if (prefix.length == colon && qualified.startsWith(prefix)) {
        return _prefixNamespaces[i];
      }
    }
    if (colon == 3 && qualified.startsWith('xml')) return Namespaces.xml;
    final wellKnown = colon == 4 && qualified.startsWith('epub')
        ? Namespaces.ops
        : colon == 5 && qualified.startsWith('xlink')
        ? Namespaces.xlink
        : -1;
    if (wellKnown >= 0) {
      if (_wellKnownReported & (1 << wellKnown) == 0) {
        _wellKnownReported |= 1 << wellKnown;
        _reportUndeclared(
          'prefixo "${qualified.substring(0, colon)}" sem declaração; '
          'usado ${Namespaces.uriOf(wellKnown)}',
        );
      }
      return wellKnown;
    }
    final prefix = qualified.substring(0, colon);
    if ((_undeclared ??= {}).add(prefix)) {
      _reportUndeclared('prefixo "$prefix" sem declaração');
    }
    if (_undeclaredNamespace < 0) {
      _undeclaredNamespace = builder.names.internNamespace(
        Namespaces.undeclaredPrefixUri,
      );
    }
    return _undeclaredNamespace;
  }

  void _reportUndeclared(String message) => diagnostics.add(
    Diagnostic(
      severity: DiagnosticSeverity.info,
      code: DiagnosticCodes.undeclaredPrefix,
      message: message,
      location: path,
    ),
  );

  void _reportDropped() {
    if (_comments + _instructions + _doctypes == 0) return;
    diagnostics.add(
      Diagnostic(
        severity: DiagnosticSeverity.info,
        code: DiagnosticCodes.droppedNodes,
        message:
            'descartados: $_comments comentário(s), $_instructions '
            'instrução(ões) de processamento, $_doctypes doctype(s)',
        location: path,
      ),
    );
  }

  /// `xmlns` ou `xmlns:p`.
  static bool _isDeclaration(String name) =>
      name.startsWith('xmlns') &&
      (name.length == 5 || name.codeUnitAt(5) == 0x3A);

  static bool _isBlank(String value) {
    for (var i = 0; i < value.length; i++) {
      final c = value.codeUnitAt(i);
      if (c != 0x20 && c != 0x09 && c != 0x0A && c != 0x0D) return false;
    }
    return true;
  }

  /// [value] sem caracteres proibidos no XML 1.0 (trocados por U+FFFD) e,
  /// se [attribute], com TAB, LF e CR trocados por espaço. Devolve o próprio
  /// [value] quando não há o que trocar (o caso comum, num laço curto).
  static String _sanitize(String value, {required bool attribute}) {
    final length = value.length;
    if (attribute) {
      for (var i = 0; i < length; i++) {
        final c = value.codeUnitAt(i);
        if (c < 0x20 || c >= 0xD800) return _sanitizeFrom(value, i, true);
      }
    } else {
      for (var i = 0; i < length; i++) {
        final c = value.codeUnitAt(i);
        if (c >= 0x20 ? c >= 0xD800 : c != 0x0A && c != 0x09 && c != 0x0D) {
          return _sanitizeFrom(value, i, false);
        }
      }
    }
    return value;
  }

  /// Caminho lento de [_sanitize], a partir do índice [from].
  static String _sanitizeFrom(String value, int from, bool attribute) {
    final length = value.length;
    final out = Uint16List(length);
    for (var j = 0; j < from; j++) {
      out[j] = value.codeUnitAt(j);
    }
    var changed = false;
    for (var i = from; i < length; i++) {
      final c = value.codeUnitAt(i);
      var unit = c;
      if (c < 0x20) {
        if (c == 0x09 || c == 0x0A || c == 0x0D) {
          if (attribute) unit = 0x20;
        } else {
          unit = 0xFFFD;
        }
      } else if (c >= 0xD800) {
        if (c <= 0xDBFF &&
            i + 1 < length &&
            (value.codeUnitAt(i + 1) & 0xFC00) == 0xDC00) {
          // Par de surrogates válido: copia os dois.
          out[i] = c;
          out[++i] = value.codeUnitAt(i);
          continue;
        }
        if (c <= 0xDFFF || c >= 0xFFFE) unit = 0xFFFD;
      }
      if (unit != c) changed = true;
      out[i] = unit;
    }
    return changed ? String.fromCharCodes(out) : value;
  }
}

/// [text] com CRLF e CR isolado trocados por LF (XML 1.0 §2.11).
String normalizeLineEnds(String text) {
  final length = text.length;
  final out = Uint16List(length);
  var n = 0;
  for (var i = 0; i < length; i++) {
    final c = text.codeUnitAt(i);
    if (c == 0x0D) {
      out[n++] = 0x0A;
      if (i + 1 < length && text.codeUnitAt(i + 1) == 0x0A) i++;
    } else {
      out[n++] = c;
    }
  }
  return String.fromCharCodes(out, 0, n);
}
