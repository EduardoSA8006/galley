/// Normalização de `href` (spec da Publicação §5.1 e §5.2). Funções puras e
/// lineares no tamanho da entrada: um `split` e uma pilha de segmentos.
library;

import 'dart:convert';

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
/// vazio na raiz). `null` se tem esquema, tem caractere de controle literal
/// (`U+0000`–`U+001F`, `U+007F`) em qualquer lugar, sai da raiz, fica vazio,
/// ou (depois do colapso) tem `:` em algum segmento (o OCF proíbe `:` em
/// nomes; cobre esquema e letra de drive revelados) ou um segmento só de
/// pontos e espaços. Tira `?query` e `#fragmento`, troca `\` por `/` e
/// colapsa `.`, `..` e barras repetidas. Não decodifica `%xx`.
String? normalizeHref(String baseDir, String raw) {
  var s = raw.trim();
  if (_scheme.hasMatch(s)) return null;
  if (_hasControlChar(s)) return null;
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
/// decodificado de `%xx` de forma tolerante a IRI (fica cru se não
/// decodificar, ou se o decodificado contém caractere de controle).
(String, String?) splitFragment(String raw) {
  final hash = raw.indexOf('#');
  if (hash < 0) return (raw, null);
  final fragment = raw.substring(hash + 1);
  if (fragment.isEmpty) return (raw.substring(0, hash), null);
  final decoded = _tryDecode(fragment);
  return (
    raw.substring(0, hash),
    decoded == null || _hasControlChar(decoded) ? fragment : decoded,
  );
}

/// Decodifica `%xx` de [normalized] segmento a segmento (uma passada só; um
/// `%25` decodificado não é redecodificado) e reaplica os passos 3–6 de
/// [normalizeHref] ao resultado. Segmento que não decodifica, que
/// decodificado contém `/`, ou que decodificado contém caractere de
/// controle (`U+0000`–`U+001F`, `U+007F`), fica cru — fecha `%00` truncando
/// o caminho num provider ingênuo e `%2F` virando separador. `null` se o
/// resultado sai da raiz, fica vazio, ou tem `:` ou um segmento só de pontos
/// e espaços.
String? decodePath(String normalized) {
  final segments = normalized.split('/');
  for (var i = 0; i < segments.length; i++) {
    final segment = segments[i];
    if (!segment.contains('%')) continue;
    final decoded = _tryDecode(segment);
    if (decoded != null &&
        !decoded.contains('/') &&
        !_hasControlChar(decoded)) {
      segments[i] = decoded;
    }
  }
  return _collapse(segments.join('/').replaceAll(r'\', '/'));
}

/// Decodifica [s] com um decodificador próprio, linear e tolerante a IRI:
/// `%xx` vira o byte; `%` sem dois hex depois fica o byte do próprio `%`;
/// caractere literal (não ASCII inclusive) vira os bytes UTF-8 dele. No fim,
/// `utf8.decode` estrito (sem `allowMalformed`) — overlong e sequência
/// inválida lançam e o segmento fica cru.
String? _tryDecode(String s) {
  try {
    return utf8.decode(_percentDecodeBytes(s));
  } on FormatException {
    return null;
  }
}

int _hexDigit(int codeUnit) {
  if (codeUnit >= 0x30 && codeUnit <= 0x39) return codeUnit - 0x30;
  if (codeUnit >= 0x41 && codeUnit <= 0x46) return codeUnit - 0x41 + 10;
  if (codeUnit >= 0x61 && codeUnit <= 0x66) return codeUnit - 0x61 + 10;
  return -1;
}

List<int> _percentDecodeBytes(String s) {
  final bytes = <int>[];
  final len = s.length;
  var i = 0;
  while (i < len) {
    final code = s.codeUnitAt(i);
    if (code == 0x25 /* % */ ) {
      if (i + 2 < len) {
        final hi = _hexDigit(s.codeUnitAt(i + 1));
        final lo = _hexDigit(s.codeUnitAt(i + 2));
        if (hi >= 0 && lo >= 0) {
          bytes.add((hi << 4) | lo);
          i += 3;
          continue;
        }
      }
      bytes.add(0x25);
      i += 1;
      continue;
    }
    var j = i + 1;
    while (j < len && s.codeUnitAt(j) != 0x25) {
      j += 1;
    }
    bytes.addAll(utf8.encode(s.substring(i, j)));
    i = j;
  }
  return bytes;
}

bool _hasControlChar(String s) {
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c <= 0x1F || c == 0x7F) return true;
  }
  return false;
}

/// Colapsa `.`, `..` e barras repetidas; `null` se sai da raiz ou fica
/// vazio. Um `/` inicial não muda nada (a raiz é a do contêiner). Um
/// segmento com `:` (esquema, letra de drive, fluxo alternativo do NTFS), ou
/// que, tirados os pontos e espaços finais, fica vazio sem ser exatamente
/// `.` ou `..` (`".. "`, `"..."`, `". ."`), invalida o caminho inteiro: é o
/// que o Win32 enxergaria como outro arquivo ou como `.`/`..` ao gravar em
/// disco.
String? _collapse(String path) {
  final out = <String>[];
  for (final segment in path.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (out.isEmpty) return null;
      out.removeLast();
      continue;
    }
    if (segment.contains(':')) return null;
    if (_isDotsAndSpacesOnly(segment)) return null;
    out.add(segment);
  }
  return out.isEmpty ? null : out.join('/');
}

bool _isDotsAndSpacesOnly(String segment) {
  var end = segment.length;
  while (end > 0) {
    final c = segment.codeUnitAt(end - 1);
    if (c == 0x20 || c == 0x2e) {
      end -= 1;
    } else {
      break;
    }
  }
  return end == 0;
}
