# S5 — soft hyphen, justificação e métricas de linha

**Data:** 2026-09-09. **Flutter:** 3.44.1 stable.
**Onde:** `test/spike/s5_soft_hyphen_test.dart` e
`test/spike/s5_line_metrics_stability_test.dart` (flutter_tester, fonte
FlutterTest, 1 glifo = fontSize px); `example/integration_test/spike_s5_hyphen_pixels_test.dart`
(engine Linux, Noto Serif e Liberation Serif do sistema).

## 5.1 O `ui.Paragraph` quebra no U+00AD? **Sim.**

`Paralele` + U+00AD + `pipedo` em coluna de 85 px (fontSize 10): 2 linhas; a 1ª
linha cobre `[0, 9)`, isto é, termina exatamente depois do soft hyphen, e a 2ª
começa em `pipedo`. Sem o U+00AD, a mesma palavra em 85 px quebra por caractere
em `[0, 8)`. O soft hyphen é tratado como oportunidade de quebra (é o comportamento
de SkParagraph/ICU).

## 5.2 O hífen é pintado na quebra? **Não.**

| Medida | FlutterTest | Noto Serif | Liberation Serif |
|---|---|---|---|
| Largura de `Paralele` sozinho | 80.0 | 154.84 | 128.81 |
| Largura de `Paralele-` | 90.0 | 167.24 | 142.13 |
| Largura da 1ª linha com U+00AD na quebra | **80.0** | **154.84** | **128.81** |
| Caixa do U+00AD na posição de quebra | 0 px | — | — |
| Pixels escuros à direita da última letra (sem SHY / SHY na quebra / `-` literal) | — | 0 / **0** / 30 | 0 / **0** / 30 |

A largura da 1ª linha é idêntica à da metade sozinha e nenhum pixel é pintado
depois da última letra. O motor usa o U+00AD **só** como ponto de quebra; o
hífen visível é problema do consumidor.

**Contradiz** doc/01 Emenda 11 ("que o `ui.Paragraph` já quebra e pinta
corretamente"), doc/04 §8 item 2 ("pinta o hífen só na quebra", "nenhum código
de layout novo") e doc/12 v1.2 ("custo de layout zero"). O que precisa mudar:

- A hifenização (v1.2) exige um passo de **pintura** do motor. Opções, em ordem
  de preferência:
  1. Após `layout`, para cada linha cuja fronteira cai num U+00AD (detectável
     por `getLineBoundary`: o `end` da linha é o índice logo após um U+00AD),
     `drawParagraph` de um `"-"` pré-shapeado no mesmo estilo em
     `(line.left + line.width, baseline)`. Sem relayout. O hífen invade a
     margem direita em ~0.3em (*hanging hyphen*); em `justify` a linha já ocupa a
     coluna, então o hífen fica na margem, como em composição tipográfica
     tradicional.
  2. `layout(width − larguraDoHífen)` e pintar como em 1: nada invade a margem,
     mas todas as linhas perdem ~0.3em.
  3. Substituir por `-` literal e relayoutar até estabilizar: exato, mas 2 a 3
     shapings por parágrafo e `DisplayMap` mais complexo.
- O `DisplayMap` (doc/04 §1.1) não muda em nenhuma opção: o U+00AD continua sendo
  um caractere inserido no texto exibido.

## 5.3 U+00AD sem quebra tem largura zero? **Sim.**

`getBoxesForRange` sobre o U+00AD em coluna larga: 1 caixa de largura 0.
`longestLine` com e sem U+00AD: 140.0 nos dois casos. **Sustenta** doc/03 §5
(manter U+00AD do fonte não altera o layout quando não quebra).

## 5.4 `TextAlign.justify`

Texto de 6 linhas em coluna de 125 px: linhas 0–4 com `width` = 125.0, última
linha 70.0 (`hardBreak = true`). A última linha **não** é justificada.

Parâmetros disponíveis: `ui.ParagraphStyle(textAlign, textDirection, maxLines,
fontFamily, fontSize, height, textHeightBehavior, fontWeight, fontStyle,
strutStyle, ellipsis, locale)`; `ui.TextStyle(letterSpacing, wordSpacing)` como
`double` **fixos**. Não existe espaçamento máximo entre palavras, alinhamento por
linha, nem callback de quebra. **Sustenta** a Emenda 11: a "opção 3" da v0.2 é
inimplementável sobre `ui.Paragraph`.

## 5.5 Custo de shaping com U+00AD

Parágrafo de 2000 caracteres @360 px, 200 `build + layout`, mediana de 3 rodadas
intercaladas, flutter_tester (serve para a razão, não para o absoluto):

| Variante | µs por layout |
|---|---|
| Sem soft hyphen | 165 |
| Com 299 soft hyphens (um a cada 6 letras) | 175 |
| Razão | **1.06×** |

Inserir U+00AD é praticamente gratuito em shaping. **Sustenta** doc/12 v1.2
quanto a shaping; o custo real da hifenização é a pintura de 5.2.

## 5.6 Cor não altera métricas

120 linhas, dois parágrafos iguais exceto `color`, `background` e
`decorationColor`: `computeLineMetrics()` idêntico campo a campo (`width`,
`height`, `baseline`, `ascent`, `descent`, `left`, `hardBreak`,
`unscaledAscent`). **Sustenta** doc/02 §5.2 (trocar tema repinta, não
repagina).

## 5.8 `StrutStyle` não altera a altura da linha (achado lateral)

| Configuração | flutter_tester (fontSize 10) | Engine Linux, Noto Serif 20 |
|---|---|---|
| Sem nada | 10.0 | 27.0 |
| `StrutStyle(fontFamily, fontSize, height: 1.5/2.0, forceStrutHeight: true)` | **10.0** | **27.0** |
| `StrutStyle(fontFamily, fontSize, leading: 0.5, forceStrutHeight: true)` | 10.0 | — |
| `ParagraphStyle(height: 1.5/2.0)` | 15.0 | 40.0 |
| `TextStyle(height: 1.5)` | 15.0 | — |

`ui.StrutStyle` não teve efeito em nenhum dos dois ambientes, com ou sem
`forceStrutHeight`, com `fontFamily` que resolve. Pode ser erro de uso (a
Fase 2 deve reexaminar), mas a documentação não deve depender disso.

**Contradiz** doc/04 §1 ("Recebe também um `StrutStyle` derivado de `fontSize ×
lineHeight`"). O que precisa mudar: a entrelinha fixa vem de
`ParagraphStyle.height` (e `TextStyle.height` nos spans), que funciona nos dois
ambientes e produz exatamente `fontSize × lineHeight`. O objetivo de doc/04 §1
(linhas com `sup`/`sub`/fallback não ficarem mais altas) precisa ser verificado
na Fase 2 com `height` + `TextHeightBehavior`, não com strut.
