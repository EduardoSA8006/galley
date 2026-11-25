/// Ids fixos dos namespaces conhecidos.
///
/// Namespaces fora desta lista recebem ids a partir de [firstCustom],
/// atribuídos por documento através de [NameTable.internNamespace].
abstract final class Namespaces {
  /// Sem namespace (atributos sem prefixo, por exemplo).
  static const int none = 0;

  /// XHTML (`http://www.w3.org/1999/xhtml`).
  static const int xhtml = 1;

  /// OPS, o namespace do prefixo `epub:` (`http://www.idpf.org/2007/ops`).
  static const int ops = 2;

  /// SVG (`http://www.w3.org/2000/svg`).
  static const int svg = 3;

  /// MathML (`http://www.w3.org/1998/Math/MathML`).
  static const int mathml = 4;

  /// XML, o namespace do prefixo `xml:`
  /// (`http://www.w3.org/XML/1998/namespace`).
  static const int xml = 5;

  /// XLink (`http://www.w3.org/1999/xlink`).
  static const int xlink = 6;

  /// Declarações de namespace (`http://www.w3.org/2000/xmlns/`).
  static const int xmlns = 7;

  /// Primeiro id dado a uma URI desconhecida.
  static const int firstCustom = 64;

  static const List<String?> _uris = [
    null,
    'http://www.w3.org/1999/xhtml',
    'http://www.idpf.org/2007/ops',
    'http://www.w3.org/2000/svg',
    'http://www.w3.org/1998/Math/MathML',
    'http://www.w3.org/XML/1998/namespace',
    'http://www.w3.org/1999/xlink',
    'http://www.w3.org/2000/xmlns/',
  ];

  /// Id fixo da [uri]: [none] para `null` ou vazia, −1 se a URI não for
  /// conhecida (nesse caso, use [NameTable.internNamespace]).
  static int idForUri(String? uri) {
    if (uri == null || uri.isEmpty) return none;
    for (var i = 1; i < _uris.length; i++) {
      if (_uris[i] == uri) return i;
    }
    return -1;
  }

  /// URI de um id fixo; `null` para [none] e para ids que não são fixos.
  static String? uriOf(int id) =>
      id > none && id < _uris.length ? _uris[id] : null;
}

/// Tabela de nomes internados de um documento.
///
/// Cada par (namespace, nome local) recebe um id `int` denso, a partir de 0,
/// compartilhado entre nomes de elemento e de atributo. Também atribui ids
/// (a partir de [Namespaces.firstCustom]) às URIs de namespace desconhecidas.
final class NameTable {
  /// Cria uma tabela vazia.
  NameTable();

  final List<int> _namespaces = [];
  final List<String> _localNames = [];
  final Map<int, Map<String, int>> _byNamespace = {};
  final List<String> _customUris = [];
  final Map<String, int> _customIds = {};

  /// Quantidade de nomes internados.
  int get length => _localNames.length;

  /// Id de (namespace, [localName]), criando-o se ainda não existir.
  int intern(int namespace, String localName) {
    final byLocal = _byNamespace[namespace] ??= <String, int>{};
    final existing = byLocal[localName];
    if (existing != null) return existing;
    final id = _localNames.length;
    _namespaces.add(namespace);
    _localNames.add(localName);
    byLocal[localName] = id;
    return id;
  }

  /// Id de (namespace, [localName]) se já internado; `null` caso contrário.
  int? lookup(int namespace, String localName) =>
      _byNamespace[namespace]?[localName];

  /// Namespace do nome [nameId].
  int namespaceOf(int nameId) => _namespaces[nameId];

  /// Nome local do nome [nameId].
  String localNameOf(int nameId) => _localNames[nameId];

  /// Id da [uri]: o fixo de [Namespaces] quando conhecida, ou um id
  /// por documento a partir de [Namespaces.firstCustom].
  int internNamespace(String uri) {
    final fixed = Namespaces.idForUri(uri);
    if (fixed >= 0) return fixed;
    return _customIds.putIfAbsent(uri, () {
      _customUris.add(uri);
      return Namespaces.firstCustom + _customUris.length - 1;
    });
  }

  /// URI do namespace [id], fixo ou por documento; `null` para
  /// [Namespaces.none] e para ids desconhecidos.
  String? namespaceUriOf(int id) {
    if (id < Namespaces.firstCustom) return Namespaces.uriOf(id);
    final i = id - Namespaces.firstCustom;
    return i < _customUris.length ? _customUris[i] : null;
  }
}

/// Tabela de tokens internados (os tokens de `class` e de `epub:type`).
final class TokenTable {
  /// Cria uma tabela vazia.
  TokenTable();

  final List<String> _tokens = [];
  final Map<String, int> _ids = {};

  /// Quantidade de tokens internados.
  int get length => _tokens.length;

  /// Id do [token], criando-o se ainda não existir.
  int intern(String token) => _ids.putIfAbsent(token, () {
    _tokens.add(token);
    return _tokens.length - 1;
  });

  /// Token do [id].
  String tokenOf(int id) => _tokens[id];

  /// Id do [token] se já internado; `null` caso contrário.
  int? lookup(String token) => _ids[token];
}
