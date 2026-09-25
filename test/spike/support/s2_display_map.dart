// Spike S2 — `DisplayMap` de doc/04 §1.1 (Emenda 6).
//
// Texto exibido ≠ texto canônico quando há `text-transform` ou U+00AD
// inserido. O mapa converte offsets nas duas direções:
//
// - identidade: `DisplayMap.identity`, constante, nenhuma alocação e nenhuma
//   cópia de string;
// - com mudança: um `Uint32List` de "trechos não lineares", consultado por
//   busca binária. Entre dois trechos o mapa é linear com inclinação 1.
//
// Achado do spike: `String.toUpperCase()` da VM do Dart faz só o mapeamento
// simples de caixa (`'ß'.toUpperCase() == 'ß'`), enquanto o do JS faz o
// completo (`'SS'`). Por isso o uppercase aqui usa uma tabela própria de
// SpecialCasing; sem ela o texto exibido divergiria entre web e nativo.

import 'dart:typed_data';

abstract interface class DisplayMap {
  /// Offset (posição de caret) no texto exibido → offset no canônico do bloco.
  /// Dentro de um trecho expandido (o segundo `S` de `SS`) devolve o offset do
  /// caractere canônico de origem (`ß`). Dentro de um trecho inserido (U+00AD)
  /// devolve o offset canônico seguinte.
  int toCanonical(int displayOffset);

  /// Offset canônico → offset exibido. Um caractere canônico precedido de
  /// inserção mapeia para depois da inserção.
  int toDisplay(int canonicalOffset);

  bool get isIdentity;

  static const DisplayMap identity = _IdentityMap();
}

final class _IdentityMap implements DisplayMap {
  const _IdentityMap();

  @override
  int toCanonical(int displayOffset) => displayOffset;

  @override
  int toDisplay(int canonicalOffset) => canonicalOffset;

  @override
  bool get isIdentity => true;
}

/// Mapa por pontos de mudança. Cada trecho não linear ocupa 4 posições do
/// `Uint32List`: `(displayStart, canonicalStart, displayLength,
/// canonicalLength)`. Inserção de U+00AD: `(d, c, 1, 0)`. `ß → SS`:
/// `(d, c, 2, 1)`. Remoção: `(d, c, 0, n)`.
final class ChangePointMap implements DisplayMap {
  ChangePointMap._(this._entries) : _count = _entries.length ~/ 4;

  final Uint32List _entries;
  final int _count;

  int get changeCount => _count;

  @override
  bool get isIdentity => false;

  int _d(int i) => _entries[i * 4];
  int _c(int i) => _entries[i * 4 + 1];
  int _dl(int i) => _entries[i * 4 + 2];
  int _cl(int i) => _entries[i * 4 + 3];

  /// Último trecho cuja chave (display ou canônica) é ≤ [value]; −1 se nenhum.
  int _lastAtOrBefore(int value, int keyIndex) {
    var lo = 0, hi = _count - 1, found = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (_entries[mid * 4 + keyIndex] <= value) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return found;
  }

  @override
  int toCanonical(int displayOffset) {
    final i = _lastAtOrBefore(displayOffset, 0);
    if (i < 0) return displayOffset;
    final d = _d(i), c = _c(i), dl = _dl(i), cl = _cl(i);
    if (displayOffset < d + dl) return c;
    return c + cl + (displayOffset - d - dl);
  }

  @override
  int toDisplay(int canonicalOffset) {
    final i = _lastAtOrBefore(canonicalOffset, 1);
    if (i < 0) return canonicalOffset;
    final d = _d(i), c = _c(i), dl = _dl(i), cl = _cl(i);
    if (canonicalOffset < c + cl) return d;
    return d + dl + (canonicalOffset - c - cl);
  }
}

final class DisplayText {
  const DisplayText(this.display, this.map);

  /// Sem transformação: a mesma instância de `String`, mapa identidade.
  const DisplayText.identity(String canonical)
    : display = canonical,
      map = DisplayMap.identity;

  final String display;
  final DisplayMap map;
}

/// SpecialCasing (Unicode) para uppercase: só as entradas que expandem. Recorte
/// do spike; a Fase 2 gera a tabela inteira (~100 entradas) de
/// `SpecialCasing.txt` e `UnicodeData.txt`.
const Map<int, String> _upperSpecial = {
  0x00DF: 'SS', // ß
  0xFB00: 'FF', // ﬀ
  0xFB01: 'FI', // ﬁ
  0xFB02: 'FL', // ﬂ
  0x0149: 'ʼN', // ŉ
};

/// Monta o texto exibido de um bloco a partir do canônico.
///
/// [uppercase]: `text-transform: uppercase` no bloco inteiro.
/// [softHyphensBefore]: offsets canônicos antes dos quais inserir U+00AD
/// (hifenização da v1.2), em ordem crescente.
DisplayText buildDisplayText(
  String canonical, {
  bool uppercase = false,
  List<int> softHyphensBefore = const [],
}) {
  if (!uppercase && softHyphensBefore.isEmpty) {
    return DisplayText.identity(canonical);
  }
  final out = StringBuffer();
  final entries = <int>[];
  var d = 0;
  var shy = 0;
  var c = 0;
  while (c < canonical.length) {
    while (shy < softHyphensBefore.length && softHyphensBefore[shy] == c) {
      out.writeCharCode(0x00AD);
      entries.addAll([d, c, 1, 0]);
      d++;
      shy++;
    }
    final unit = canonical.codeUnitAt(c);
    final isPair =
        unit >= 0xD800 &&
        unit <= 0xDBFF &&
        c + 1 < canonical.length &&
        (canonical.codeUnitAt(c + 1) & 0xFC00) == 0xDC00;
    final width = isPair ? 2 : 1;
    final original = canonical.substring(c, c + width);
    var shown = original;
    if (uppercase) {
      final rune = original.runes.first;
      shown = _upperSpecial[rune] ?? original.toUpperCase();
    }
    if (shown.length != width) entries.addAll([d, c, shown.length, width]);
    out.write(shown);
    d += shown.length;
    c += width;
  }
  while (shy < softHyphensBefore.length && softHyphensBefore[shy] == c) {
    out.writeCharCode(0x00AD);
    entries.addAll([d, c, 1, 0]);
    d++;
    shy++;
  }
  final display = out.toString();
  if (entries.isEmpty) {
    // Uppercase que não mudou comprimento: offsets 1:1, mapa identidade.
    return DisplayText(display, DisplayMap.identity);
  }
  return DisplayText(display, ChangePointMap._(Uint32List.fromList(entries)));
}
