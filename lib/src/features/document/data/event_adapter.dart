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
/// - `epub:` sem declaração cai em OPS; `xml:` é sempre o namespace XML;
///   outros prefixos sem declaração ficam em
///   [Namespaces.undeclaredPrefixUri], com o nome qualificado. Cada
///   prefixo sem declaração gera um `document.undeclaredPrefix`.
/// - Atributos sem prefixo ficam em [Namespaces.none]; com atributo
///   repetido, vale o primeiro (`document.duplicateAttribute`).
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

  /// Prefixos sem declaração já reportados (fora `epub`, à parte).
  Set<String>? _undeclared;
  bool _epubReported = false;
  int _comments = 0;
  int _instructions = 0;
  int _doctypes = 0;

  /// Lê [text] inteiro e devolve a árvore.
  ///
  /// Defeitos estruturais vão para a [policy]; com a política estrita, a
  /// [XmlException] do `package:xml` ou da política propaga.
  DocumentTree run(String text) {
    final events = parseEvents(
      text,
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
      builder.text(value);
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
      final namespace = value.isEmpty
          ? Namespaces.none
          : builder.names.internNamespace(value);
      if (name.length == 5) {
        defaultNamespace = namespace;
      } else {
        _prefixes.add(name.substring(6));
        _prefixNamespaces.add(namespace);
      }
    }
    _defaults.add(defaultNamespace);
    _openNames.add(event.name);

    builder.startElement(_resolve(event.name, defaultNamespace));
    if (attributes.length > declarations) _attributes(attributes);
    if (event.isSelfClosing) _close();
  }

  void _attributes(List<XmlEventAttribute> attributes) {
    final ids = _attributeIds..clear();
    for (var i = 0; i < attributes.length; i++) {
      final attribute = attributes[i];
      final name = attribute.name;
      if (_isDeclaration(name)) continue;
      final id = _resolve(name, Namespaces.none);
      if (ids.contains(id)) {
        diagnostics.add(
          Diagnostic(
            severity: DiagnosticSeverity.info,
            code: DiagnosticCodes.duplicateAttribute,
            message: 'atributo "$name" repetido; vale o primeiro',
            location: path,
          ),
        );
        continue;
      }
      ids.add(id);
      builder.attribute(id, attribute.value);
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
    if (colon == 4 && qualified.startsWith('epub')) {
      if (!_epubReported) {
        _epubReported = true;
        _reportUndeclared(
          'prefixo "epub" sem declaração; usado o namespace OPS',
        );
      }
      return Namespaces.ops;
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
}
