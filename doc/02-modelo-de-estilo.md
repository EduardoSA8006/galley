# 02 — Modelo de estilo

**Decisão 2: perfil uniforme na v1, com o enum de fidelidade já na API.
Emenda 5: precedência exata do perfil `uniform`.**

## 1. O conflito

A pergunta "quem ganha, o CSS do publisher ou a preferência do usuário?" está mal
posta. Considere um romance típico:

```css
body { font-family: "Charis SIL"; font-size: 11pt; color: #1a1a1a }
p { text-indent: 1.5em; margin: 0; text-align: justify }
h1 { text-align: center; font-variant: small-caps }
blockquote { font-size: 0.9em }
code { font-family: monospace }
.verso { margin-left: 2em; font-style: italic }
```

O usuário escolhe Literata, 18px, alinhado à esquerda, fundo sépia.

- Se o **publisher** ganha: o seletor de fonte não faz nada, e um livro com
  `color: #fff` fica invisível no fundo sépia.
- Se o **usuário** ganha: o `h1` centralizado desalinha, o `blockquote` para de
  ser menor, o `code` perde monoespaçado e a poesia perde o recuo.

Nenhuma das duas respostas serve.

## 2. Classificar por propriedade, não por origem

### Classe 1 — Semântica de estrutura

`display`, `float`, `list-style`, tudo de `table`, `vertical-align`, quebras,
dimensões intrínsecas de imagem, `page-progression-direction`, `direction`/`dir`,
`lang`.

**O usuário nunca sobrepõe.** Mexer aqui é perda de conteúdo, o que viola o
contrato de fidelidade.

### Classe 2 — Tipografia relativa

`font-style`, `font-weight`, `font-variant`, `text-transform`, `text-indent`,
tamanhos e margens em `em`/`%`/`rem`, alinhamento de elementos estruturais.

Regra geral: **preserve o relativo, ancore o absoluto.**

```
tamanhoFinal = (valorDoPublisher / rootDoPublisher) * rootDoUsuario
```

`11pt` e `0.9em` viram múltiplos do root do publisher, depois multiplicam pelo
root do usuário. O `blockquote` continua 10% menor que o corpo, e o corpo obedece
aos 18px escolhidos. Controle e hierarquia ao mesmo tempo.

O **quanto** da Classe 2 é honrado depende do perfil de fidelidade (§3.1). A
classificação em si não muda.

### Classe 3 — Aparência global

Cor de texto, cor de fundo, família base, tamanho base, entrelinha base,
alinhamento do corpo, margens da página.

**O usuário manda sempre.** O CSS do publisher aqui é descartado.

Cor não é negociável: honrar `color` do publisher garante texto ilegível em tema
escuro ou sépia numa fração grande do acervo real.

## 3. Tipografia própria do motor

Perfil uniforme **não** significa achatar. Se você remove o CSS do editor e não
põe nada no lugar, o resultado é pior que ter honrado o CSS. O motor passa a ser
dono da própria tipografia, por regra semântica derivada da tag:

| Elemento | Regra do motor |
|---|---|
| `p` corpo | Recuo conforme `EpubStyle.indent`; **sem recuo** no primeiro parágrafo após heading, após quebra de cena (`hr`) e após imagem em bloco |
| `code`, `pre`, `kbd`, `samp` | Família monoespaçada da cadeia de fallback, tamanho 0.9× do corpo; `pre` sem quebra automática, com rolagem horizontal do bloco quando excede a largura |
| `h1`–`h6` | Escala tipográfica calculada do tamanho base: `1.8 / 1.55 / 1.35 / 1.2 / 1.1 / 1.0`, peso bold, alinhamento próprio (start, exceto quando o publisher centraliza), margem superior 1.5× e inferior 0.5× da entrelinha |
| `blockquote` | Recuo de 1.5em nas duas margens, tamanho 0.95× |
| Versos (`.verse`, `<p>` em `<div epub:type="z3998:verse">`, `<pre>` com `epub:type` de poesia) | Recuo pendente, sem justificação, whitespace preservado |
| `figcaption` | 0.85× do corpo, centralizado |
| `sup`, `sub` | 0.7×, deslocamento de baseline via `ui.TextStyle` com `fontFeatures`/offset; nunca altera a altura da linha |
| `li` | Marcador conforme `Block.marker` (disco, círculo, quadrado, decimal, alfa, romano), recuo 1.5em por nível |
| `td`, `th` | `th` em bold; padding interno 0.4em |
| `hr` | Quebra de cena: espaço de uma entrelinha; nunca uma linha visível a menos que o `EpubStyle` peça |
| `small` | 0.85× |
| Ênfase, negrito, itálico, sublinhado, riscado, small-caps | Vêm do documento (inline e semânticos) |

Isso substitui a tipografia do editor por uma **sua, boa e consistente**.

### 3.1 Precedência no perfil `uniform` (Emenda 5)

A regra do motor é a **base**. Sobre ela, do CSS do publisher:

| Honrado | Não honrado (o motor decide) |
|---|---|
| `font-style`, `font-weight`, `font-variant`, `text-transform` (todos inline e de bloco) | `text-indent`, `margin`, `padding` |
| `vertical-align` para sup/sub | `line-height` |
| `text-align` em `h1`–`h6`, `figcaption`, `th`, `td` e em elementos com `epub:type` de título ou dedicatória | `text-align` em `p` e `div` genéricos |
| `font-size` **relativo** (`em`, `%`, `rem`, palavras-chave `smaller`/`larger`), com **clamp em `[0.75, 1.6]`** do tamanho do corpo | `font-size` absoluto (`pt`, `px`) |
| `display: none` (Classe 1), `list-style-type`, `page-break-*`/`break-*` | `font-family`, `color`, `background` |

Por que o clamp: CSS de editora contém `font-size: 0.5em` em notas e `3em` em
capitulares. Sem teto e piso, o perfil uniforme deixa de ser uniforme.

Por que `text-align` em `p` é do motor: é a preferência mais visível do usuário
(`EpubStyle.textAlign`) e é Classe 3 na prática, mesmo quando o publisher a
declara em `p`.

Por que `text-indent` é do motor: conflita frontalmente com `EpubStyle.indent`, e
a convenção editorial ("sem recuo depois de heading") é aplicada pelo motor a
partir da estrutura, não do CSS.

No perfil `faithful` (v2.0), a coluna "não honrado" passa a ser honrada, exceto
Classe 3.

## 4. Perfis de fidelidade

```dart
enum EpubFidelity {
  /// A tipografia do motor substitui a do publisher (§3).
  /// Previsível entre livros, imune a CSS ruim, mais rápido.
  uniform,

  /// Preserva a Classe 2 do publisher, incluindo capitular,
  /// small-caps e float com contorno.
  /// NÃO IMPLEMENTADO na v1.0 — lança EpubUnsupportedException
  /// na construção de EpubLayoutEngine ou EpubReader.
  faithful,
}
```

Os dois valores existem desde a v1.0 por causa da Emenda 2
([01-decisoes.md](01-decisoes.md)): adicionar valor a enum público depois
quebraria `switch` exaustivo no código dos consumidores.

Implementar `faithful` exige float com contorno de texto, `::first-letter` e
`font-variant: small-caps` de verdade. Cada um é um subsistema de layout, e é por
isso que fica para depois da 1.1.

## 5. `EpubStyle`

```dart
@immutable
final class EpubStyle {
  // Classe 3 — o usuário manda
  final String family;
  final List<String> fallbackChain;
  final double fontSize;          // px lógicos, o "root do usuário"
  final double lineHeight;        // múltiplo do fontSize
  final double letterSpacing;
  final double wordSpacing;
  final EpubTextAlign textAlign;  // start, justify, center
  final Color textColor;
  final Color backgroundColor;
  final Color linkColor;
  final Color selectionColor;
  final EdgeInsets pageMargins;
  final double paragraphSpacing;  // múltiplo do lineHeight
  final EpubIndentStyle indent;   // firstLine, none, spacing
  final bool showSceneBreakRule;  // pinta o hr como linha em vez de espaço

  // Política
  final EpubFidelity fidelity;
  final double maxTextScale;      // teto para MediaQuery.textScaler
  final bool hyphenate;           // ver P1 em 01-decisoes.md; sem efeito na 1.0

  const EpubStyle.light();
  const EpubStyle.dark();
  const EpubStyle.sepia();
  EpubStyle copyWith({ ... });

  /// Hash de layout (§5.2). Não inclui cores.
  int get layoutHash;
}
```

`final class` para que campos possam ser adicionados sem quebrar quem implementa
ou estende ([11](11-empacotamento-versionamento.md) §3.3).

### 5.1 `fallbackChain` não é opcional

Um leitor precisa lidar com livros em escritas que a fonte escolhida não cobre.
Sem cadeia de fallback, um livro em japonês, árabe ou grego antigo abre com
caixas vazias. A cadeia deve conter, no mínimo: a fonte escolhida, uma serifada
ampla, uma monoespaçada, e as fontes de sistema para CJK e árabe.

O `lang` da seção e do bloco ([03](03-camada-a-ir.md) §4) é passado ao
`ui.TextStyle.locale`. É isso que resolve a unificação Han: com `locale: ja` o
motor de texto escolhe os glifos japoneses da fonte de fallback, com `zh-Hans` os
chineses simplificados. Sem `locale`, o resultado depende da ordem das fontes do
sistema, e está errado para um dos dois idiomas.

### 5.2 Hash de estilo

A Camada C é invalidada por um hash que cobre exatamente:

```
family | fallbackChain | fontSize | lineHeight | letterSpacing | wordSpacing
| textAlign | pageMargins | paragraphSpacing | indent | fidelity
| textScale efetivo | locale | hyphenate | showSceneBreakRule
```

Cor **não** entra no hash: mudar cor só repinta, não relayouta. Essa distinção é
o que faz troca de tema custar menos de 50 ms.

Cores são passadas ao `ui.Paragraph` mesmo assim, porque o `ui.TextStyle`
precisa delas para pintar. A consequência é que trocar cor **reconstrói** os
`Paragraph`s (barato, o shaping é o que custa) mas **não repagina**, porque as
métricas de linha são idênticas. A implementação deve verificar isso com um
teste: mesma `LineBox` para duas cores diferentes.

### 5.3 Escala de texto do sistema

`MediaQuery.textScaler` multiplica `fontSize`, limitado por `maxTextScale`. Entra
no hash como "textScale efetivo". Ver [05](05-render-selecao-a11y.md) §4.3.
