/// Folha padrão (spec do CSS §8.1): a seção 15 (Rendering) do HTML recortada
/// às propriedades de §7.1. Mudar este texto muda a IR e exige bump de
/// `IR_SCHEMA_VERSION` (doc/08 §4.1), porque a folha padrão não entra na
/// lista de folhas da chave.
library;

import 'parser.dart';

/// `rp` não é escondido (o galley achata o ruby, doc/09 §3 `rubyFlattened`);
/// `noscript` fica visível (o galley não roda script); o recuo de lista usa
/// `padding-left`, físico (o HTML usa `padding-inline-start`). Nenhum
/// seletor tem combinador: o `circle`/`square` das listas aninhadas (HTML
/// §15.3.8) sai do nível de lista herdado, na cascata, sem que a folha
/// padrão suba pelos ancestrais de cada lista.
const String userAgentCss = '''
html, body, address, blockquote, center, div, figure, figcaption, footer,
header, hgroup, main, nav, section, article, aside, search, details, summary,
form, fieldset, legend, hr, p, pre, listing, xmp, plaintext,
h1, h2, h3, h4, h5, h6, dl, dt, dd, ol, ul, menu, dir,
table, caption, thead, tbody, tfoot, tr, td, th, colgroup, col { display: block }
li { display: list-item }
head, script, style, title, meta, link, base, template, area, param,
datalist, source, track, noembed, noframes { display: none }

pre, listing, xmp, plaintext { white-space: pre }
nobr { white-space: nowrap }

center, caption, th { text-align: center }

h1, h2, h3, h4, h5, h6, th { font-weight: bold }
b, strong { font-weight: bolder }
i, cite, em, var, dfn, address { font-style: italic }
u, ins { text-decoration: underline }
s, strike, del { text-decoration: line-through }

h1 { font-size: 2em }
h2 { font-size: 1.5em }
h3 { font-size: 1.17em }
h4 { font-size: 1em }
h5 { font-size: 0.83em }
h6 { font-size: 0.67em }
small, sub, sup { font-size: smaller }
big { font-size: larger }
sup { vertical-align: super }
sub { vertical-align: sub }

ul, menu, dir { list-style-type: disc }
ol { list-style-type: decimal }
ol[type="1"], li[type="1"] { list-style-type: decimal }
ol[type="a"], li[type="a"] { list-style-type: lower-alpha }
ol[type="A"], li[type="A"] { list-style-type: upper-alpha }
ol[type="i"], li[type="i"] { list-style-type: lower-roman }
ol[type="I"], li[type="I"] { list-style-type: upper-roman }
ul, ol, menu, dir { padding-left: 2.5em }
dd { margin-left: 2.5em }
blockquote { margin: 1em 2.5em }
''';

/// [userAgentCss] parseada uma vez (preguiçosa, como todo `final` de topo).
final StyleSheet userAgentSheet = parseStyleSheet(userAgentCss);
