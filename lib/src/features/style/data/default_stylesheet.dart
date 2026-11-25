import '../../../core/diagnostics/diagnostic_sink.dart';
import '../domain/stylesheet.dart';
import 'stylesheet_builder.dart';

/// Texto da folha padrão (origem do agente, spec §8.9).
///
/// Baseada na seção "Rendering" da especificação HTML (WHATWG), reduzida ao
/// que o motor suporta: propriedades lógicas viram as físicas do modo
/// horizontal, `:is()` é expandido e `:dir()` vira o atributo `dir`. As
/// regras de HTML valem só para elementos XHTML (namespace padrão, como nos
/// navegadores); SVG e MathML embutidos recebem o mínimo para ficarem em
/// linha e esconderem o que não é desenhado.
///
/// Diferenças deliberadas: `h1`–`h6` têm sempre os tamanhos de nível
/// (sem a redução de `h1` dentro de `section`/`article`, removida da
/// especificação) e `:link` casa `a`/`area` com `href`.
const String kDefaultStyleSheetCss = r'''
@namespace url(http://www.w3.org/1999/xhtml);
@namespace svg url(http://www.w3.org/2000/svg);
@namespace m url(http://www.w3.org/1998/Math/MathML);

/* Ocultos */
[hidden], area, base, basefont, datalist, head, link, meta, noembed,
noframes, param, rp, script, style, template, title { display: none; }

/* Blocos */
html, body { display: block; }
address, blockquote, center, dialog, div, figure, figcaption, footer, form,
header, hr, legend, listing, main, p, plaintext, pre, search, xmp,
article, aside, h1, h2, h3, h4, h5, h6, hgroup, nav, section,
details, summary, fieldset { display: block; }
body { margin: 8px; }
blockquote, figure, listing, p, plaintext, pre, xmp {
  margin-top: 1em; margin-bottom: 1em;
}
blockquote, figure { margin-left: 40px; margin-right: 40px; }
address { font-style: italic; }
listing, plaintext, pre, xmp { font-family: monospace; white-space: pre; }
center { text-align: center; }
dialog:not([open]) { display: none; }
fieldset { margin-left: 2px; margin-right: 2px; border: 2px groove;
  padding: 0.35em 0.75em 0.625em; }

/* Títulos */
h1 { margin-top: 0.67em; margin-bottom: 0.67em; font-size: 2em; }
h2 { margin-top: 0.83em; margin-bottom: 0.83em; font-size: 1.5em; }
h3 { margin-top: 1em; margin-bottom: 1em; font-size: 1.17em; }
h4 { margin-top: 1.33em; margin-bottom: 1.33em; font-size: 1em; }
h5 { margin-top: 1.67em; margin-bottom: 1.67em; font-size: 0.83em; }
h6 { margin-top: 2.33em; margin-bottom: 2.33em; font-size: 0.67em; }
h1, h2, h3, h4, h5, h6 { font-weight: bold; }

/* Listas */
dir, dd, dl, dt, menu, ol, ul { display: block; }
li { display: list-item; }
dir, dl, menu, ol, ul { margin-top: 1em; margin-bottom: 1em; }
dir dir, dir dl, dir menu, dir ol, dir ul, dl dir, dl dl, dl menu, dl ol,
dl ul, menu dir, menu dl, menu menu, menu ol, menu ul, ol dir, ol dl,
ol menu, ol ol, ol ul, ul dir, ul dl, ul menu, ul ol, ul ul {
  margin-top: 0; margin-bottom: 0;
}
dd { margin-left: 40px; }
dir, menu, ol, ul { padding-left: 40px; }
ol, ul, menu { counter-reset: list-item; }
ol { list-style-type: decimal; }
dir, menu, ul { list-style-type: disc; }
dir dir, dir menu, dir ul, menu dir, menu menu, menu ul, ol dir, ol menu,
ol ul, ul dir, ul menu, ul ul { list-style-type: circle; }
dir dir dir, dir dir menu, dir dir ul, dir menu dir, dir menu menu,
dir menu ul, dir ol dir, dir ol menu, dir ol ul, dir ul dir, dir ul menu,
dir ul ul, menu dir dir, menu dir menu, menu dir ul, menu menu dir,
menu menu menu, menu menu ul, menu ol dir, menu ol menu, menu ol ul,
menu ul dir, menu ul menu, menu ul ul, ol dir dir, ol dir menu, ol dir ul,
ol menu dir, ol menu menu, ol menu ul, ol ol dir, ol ol menu, ol ol ul,
ol ul dir, ol ul menu, ol ul ul, ul dir dir, ul dir menu, ul dir ul,
ul menu dir, ul menu menu, ul menu ul, ul ol dir, ul ol menu, ul ol ul,
ul ul dir, ul ul menu, ul ul ul { list-style-type: square; }

/* Tabelas */
table { display: table; box-sizing: border-box; border-spacing: 2px;
  border-collapse: separate; text-indent: initial; }
caption { display: table-caption; text-align: center; }
colgroup { display: table-column-group; }
col { display: table-column; }
thead { display: table-header-group; }
tbody { display: table-row-group; }
tfoot { display: table-footer-group; }
tr { display: table-row; }
td, th { display: table-cell; padding: 1px; }
th { font-weight: bold; text-align: center; }
thead, tbody, tfoot, table > tr { vertical-align: middle; }
tr, td, th { vertical-align: inherit; }
thead, tbody, tfoot, tr { border-color: inherit; }

/* Ruby */
ruby { display: ruby; }
rt { display: ruby-text; }

/* Texto */
cite, dfn, em, i, var { font-style: italic; }
b, strong { font-weight: bolder; }
code, kbd, samp, tt { font-family: monospace; }
big { font-size: larger; }
small { font-size: smaller; }
sub { vertical-align: sub; }
sup { vertical-align: super; }
sub, sup { line-height: normal; font-size: smaller; }
:link { color: #0000EE; text-decoration: underline; }
mark { background-color: yellow; color: black; }
abbr[title], acronym[title] { text-decoration: dotted underline; }
ins, u { text-decoration: underline; }
del, s, strike { text-decoration: line-through; }
q::before { content: open-quote; }
q::after { content: close-quote; }
nobr { white-space: nowrap; }
nobr wbr { white-space: normal; }

/* Direção */
[dir=ltr i], bdi[dir=ltr i] { direction: ltr; }
[dir=rtl i], bdi[dir=rtl i] { direction: rtl; }
address, blockquote, center, div, figure, figcaption, footer, form, header,
hr, legend, listing, main, p, plaintext, pre, summary, xmp, article, aside,
h1, h2, h3, h4, h5, h6, hgroup, nav, section, table, caption, colgroup, col,
thead, tbody, tfoot, tr, td, th, dir, dd, dl, dt, menu, ol, ul, li, bdi,
output, [dir=ltr i], [dir=rtl i], [dir=auto i] { unicode-bidi: isolate; }
bdo, bdo[dir] { unicode-bidi: isolate-override; }
pre[dir=auto i] { unicode-bidi: plaintext; }

/* Separador e mídia */
hr { color: gray; border-style: inset; border-width: 1px;
  margin: 0.5em auto; overflow: hidden; }
iframe { border: 2px inset; }
video { object-fit: contain; }

/* SVG e MathML embutidos */
svg|svg, m|math { display: inline; }
svg|svg:not(:root) { overflow: hidden; }
svg|title, svg|desc, svg|metadata, svg|style, svg|script { display: none; }
m|math[display=block i] { display: block; text-align: center; }
m|annotation, m|annotation-xml { display: none; }
''';

/// A folha padrão interpretada, lida uma vez por isolate (na primeira
/// consulta) e compartilhada por todos os livros.
StyleSheet get defaultStyleSheet => _defaultStyleSheet;

final StyleSheet _defaultStyleSheet = buildStyleSheet(
  kDefaultStyleSheetCss,
  path: '',
  fontPrefix: '',
  sink: const NullDiagnosticSink(),
);
