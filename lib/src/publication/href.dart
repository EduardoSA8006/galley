/// Normalização de `href` (spec da Publicação §5.1 e §5.2). Funções puras e
/// lineares no tamanho da entrada: um `split` e uma pilha de segmentos.
library;

final RegExp _scheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*:');

/// `href` com esquema (`http:`, `mailto:`, `data:`, `C:`…).
bool hasScheme(String raw) => _scheme.hasMatch(raw.trim());

/// Esquema `http:` ou `https:` (recurso remoto do EPUB3).
bool isRemoteHref(String raw) {
  final lower = raw.trim().toLowerCase();
  return lower.startsWith('http:') || lower.startsWith('https:');
}

/// Diretório de [path] (sem `/` final; `''` na raiz).
String dirnameOf(String path) {
  final slash = path.lastIndexOf('/');
  return slash < 0 ? '' : path.substring(0, slash);
}

/// Nome do arquivo de [path], sem a última extensão.
String basenameWithoutExtension(String path) {
  final name = path.substring(path.lastIndexOf('/') + 1);
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}

/// Caminho de [raw] relativo à raiz do contêiner, resolvido contra
/// [baseDir] (diretório do documento que contém o `href`, sem `/` final;
/// vazio na raiz). `null` se tem esquema, sai da raiz ou fica vazio. Tira
/// `?query` e `#fragmento`, troca `\` por `/` e colapsa `.`, `..` e barras
/// repetidas. Não decodifica `%xx`.
String? normalizeHref(String baseDir, String raw) {
  var s = raw.trim();
  if (_scheme.hasMatch(s)) return null;
  final hash = s.indexOf('#');
  if (hash >= 0) s = s.substring(0, hash);
  final query = s.indexOf('?');
  if (query >= 0) s = s.substring(0, query);
  s = s.replaceAll(r'\', '/');
  if (s.isEmpty) return null;
  final joined = s.startsWith('/') || baseDir.isEmpty ? s : '$baseDir/$s';
  return _collapse(joined);
}

/// Separa no primeiro `#`. Fragmento vazio → `null`; o fragmento é
/// decodificado de `%xx` (fica cru se não decodificar).
(String, String?) splitFragment(String raw) {
  final hash = raw.indexOf('#');
  if (hash < 0) return (raw, null);
  final fragment = raw.substring(hash + 1);
  return (
    raw.substring(0, hash),
    fragment.isEmpty ? null : _tryDecode(fragment) ?? fragment,
  );
}

/// Decodifica `%xx` de [normalized] segmento a segmento e reaplica os passos
/// 3–6 de [normalizeHref]. Segmento que não decodifica, ou que decodificado
/// contém `/`, fica cru. `null` se o resultado sai da raiz ou fica vazio.
String? decodePath(String normalized) {
  if (!normalized.contains('%')) return normalized;
  final segments = normalized.split('/');
  for (var i = 0; i < segments.length; i++) {
    final segment = segments[i];
    if (!segment.contains('%')) continue;
    final decoded = _tryDecode(segment);
    if (decoded != null && !decoded.contains('/')) segments[i] = decoded;
  }
  return _collapse(segments.join('/').replaceAll(r'\', '/'));
}

String? _tryDecode(String s) {
  try {
    return Uri.decodeComponent(s);
  } on ArgumentError {
    return null;
  } on FormatException {
    return null;
  }
}

/// Colapsa `.`, `..` e barras repetidas; `null` se sai da raiz ou fica
/// vazio. Um `/` inicial não muda nada (a raiz é a do contêiner).
String? _collapse(String path) {
  final out = <String>[];
  for (final segment in path.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (out.isEmpty) return null;
      out.removeLast();
    } else {
      out.add(segment);
    }
  }
  return out.isEmpty ? null : out.join('/');
}
