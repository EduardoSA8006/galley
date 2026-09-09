# S7 — placeholder inline e decode de imagem com tamanho-alvo

**Data:** 2026-09-09. **Flutter:** 3.44.1 stable, flutter_tester
(`test/spike/s7_placeholder_and_decode_test.dart`).

## 7.1 `addPlaceholder(PlaceholderAlignment.baseline)`

Placeholder de 20×40 entre `antes ` (6 code units) e ` depois`, fontSize 10:

- `getBoxesForPlaceholders()` → 1 caixa: `LTRB(60.0, 0.5, 80.0, 40.5)`.
- `getBoxesForRange(6, 7)` → a **mesma** caixa. O placeholder ocupa exatamente
  um code unit (U+FFFC) no texto do parágrafo; o caractere seguinte começa em
  `x = 80.0`, onde o placeholder termina.
- Altura da linha: sem placeholder 10.0; placeholder de 5 px 10.0 (não cresce);
  placeholder de 40 px **43.0** (cresce para acomodar 40 acima da baseline mais
  o descent de 2.5 + arredondamento).

**Sustenta** doc/03 §5 (U+FFFC no `canonicalText` mapeia 1:1 no placeholder e
em `getBoxesForRange`) e doc/04 §10 (limitar imagem inline a `2 × lineHeight`,
senão a linha estoura e a imagem vira bloco).

## 7.2 `instantiateImageCodec(targetWidth:)`

PNG de 2000×2000 gerado no teste (18.5 KB comprimido), 5 decodes, mediana:

| | Dimensão | Memória (w×h×4) | Tempo de decode |
|---|---|---|---|
| Sem alvo | 2000×2000 | 15.26 MB | 21.3 ms |
| `targetWidth: 360` | 360×360 | 0.49 MB | 19.4 ms |
| Razão | — | **30.9×** menos | 0.91× (igual, dentro do ruído) |

O ganho é de **memória retida**, não de tempo: o decoder ainda processa o PNG
inteiro e reduz na saída. **Sustenta** doc/05 §6 (decodificar em tamanho-alvo,
cache por bytes decodificados). Nota para a doc: `targetWidth` não reduz o pico
transitório do decode, então decodificar fora do caminho crítico continua
necessário.

## 7.3 APIs confirmadas por chamada real

| API | Resultado |
|---|---|
| `Paragraph.getClosestGlyphInfoForOffset(Offset(25, 5))` | `TextRange(2, 3)` |
| `Paragraph.getWordBoundary(TextPosition(6))` | `TextRange(4, 11)` (`palavra`) |
| `Paragraph.getLineBoundary(TextPosition(6))` | `TextRange(0, 17)` |
| `Paragraph.dispose()` | existe e roda |
| `Paragraph.getBoxesForPlaceholders()` | ver 7.1 |
| `ui.TextStyle(locale: Locale('ja','JP'))` | aceito |
| `ui.ParagraphStyle(locale:, strutStyle:)` | aceito; strut sem efeito na altura (ver RESULTADO-S5 §5.8) |
| `ui.ParagraphStyle(height: 1.5)` | altura da linha 15.0 para fontSize 10 |
| `SemanticsFlag.isHeader` | existe |
| Nível de heading | `SemanticsConfiguration.headingLevel` (`int`, setter em `semantics.dart:6397`, assert `0..6`). Doc do setter: "only used for web semantics, ignored on other platforms" — em Android/iOS o nível não é exposto, só `isHeader` |

**Sustenta** doc/05 §3.1 e §4.3 quanto aos nomes. Nota para doc/05 §4.3: o
nível numérico do heading só chega ao leitor de tela no web; TalkBack e
VoiceOver recebem apenas `isHeader`.
