import 'dart:convert';

/// Caminho resolvido dentro do zip, com o fragmento (sem `#`) se houver.
typedef ResolvedHref = ({String path, String? fragment});

final RegExp _scheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*:');

/// Resolve [href] relativo ao arquivo [baseFilePath] (caminho na raiz do zip).
///
/// Devolve `null` para hrefs com esquema (`http:`, `mailto:`...) ou que
/// escapam da raiz. Separa o `#fragmento`, descarta a `?query` e aplica
/// percent-decoding (UTF-8) em seguida; sequências malformadas mantêm o texto
/// cru. Uma `/` inicial é tratada como relativa à raiz do zip. [href] vazio
/// (ou só fragmento) aponta para o próprio [baseFilePath]. O resultado nunca
/// começa com `/`.
ResolvedHref? resolveHref(String baseFilePath, String href) {
  if (_scheme.hasMatch(href)) return null;

  String? fragment;
  var rest = href;
  final hash = rest.indexOf('#');
  if (hash >= 0) {
    fragment = _decode(rest.substring(hash + 1));
    rest = rest.substring(0, hash);
  }
  final query = rest.indexOf('?');
  if (query >= 0) rest = rest.substring(0, query);

  if (rest.isEmpty) return (path: baseFilePath, fragment: fragment);

  rest = _decode(rest);
  final segments = <String>[];
  if (!rest.startsWith('/')) {
    final slash = baseFilePath.lastIndexOf('/');
    if (slash >= 0) {
      segments.addAll(baseFilePath.substring(0, slash).split('/'));
    }
  }
  for (final part in rest.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (segments.isEmpty) return null;
      segments.removeLast();
    } else {
      segments.add(part);
    }
  }
  return (path: segments.join('/'), fragment: fragment);
}

final RegExp _hexPair = RegExp(r'^[0-9a-fA-F]{2}$');

String _decode(String s) {
  if (!s.contains('%')) return s;
  final out = <int>[];
  final runes = s.runes.toList();
  for (var i = 0; i < runes.length; i++) {
    if (runes[i] != 0x25) {
      out.addAll(utf8.encode(String.fromCharCode(runes[i])));
      continue;
    }
    if (i + 2 >= runes.length) return s;
    final pair = String.fromCharCodes(runes.sublist(i + 1, i + 3));
    if (!_hexPair.hasMatch(pair)) return s;
    out.add(int.parse(pair, radix: 16));
    i += 2;
  }
  try {
    return utf8.decode(out);
  } on FormatException {
    return s;
  }
}
