/// Folha de editora realista (apenas uso em testes): reset, `@font-face`,
/// `@page`, `@media`, seletores de classe, descendentes, atributos e
/// pseudo-elementos, `!important`, atalhos e unidades variadas, no estilo
/// das folhas de EPUB comerciais. Casa com o XHTML de `syntheticXhtml`.
const String kPublisherCss = r'''
@charset "utf-8";
@namespace epub "http://www.idpf.org/2007/ops";
@font-face {
  font-family: "Livro Serif";
  font-style: normal;
  font-weight: 400;
  src: url(../fonts/LivroSerif-Regular.otf) format("opentype");
}
@font-face {
  font-family: "Livro Serif";
  font-style: italic;
  src: url("../fonts/LivroSerif-Italic.otf");
}
@page { margin: 5pt 1em; }
html, body { margin: 0; padding: 0; }
body {
  font-family: "Livro Serif", Georgia, serif;
  font-size: 100%;
  line-height: 1.4;
  orphans: 2;
  widows: 2;
  text-rendering: optimizeLegibility;
}
h1, h2, h3 {
  font-family: "Helvetica Neue", Arial, sans-serif;
  font-weight: bold;
  text-align: center;
  page-break-after: avoid;
  margin: 2em 0 1em;
}
h2 { font-size: 1.4em; letter-spacing: 0.05em; text-transform: uppercase; }
p { margin: 0; text-indent: 1.5em; text-align: justify; hyphens: auto; }
p.texto { color: #222; }
p.texto:first-child { text-indent: 0; }
p.texto::first-letter { font-size: 2.2em; float: left; }
h2 + p { text-indent: 0 !important; }
section.c0 p, section.c3 p { word-spacing: 0.1em; }
section[epub|type~="chapter"] > h2 { border-bottom: 1px solid #999; }
em, i { font-style: italic; }
a { color: #004080; text-decoration: none; }
a[href^="#"]::after { content: " \2192"; }
ruby rt { font-size: 50%; }
table { border-collapse: collapse; margin: 1em auto; width: 80%; }
td { border: 1px solid #ccc; padding: 0.25em 0.5em; text-align: right; }
.c1 h2 { color: rgb(80, 20, 20); }
.c2 { background-color: #fafafa; }
.c4 em { font-weight: 600; }
.c5 > p:last-child { margin-bottom: 1em; }
.c6 td:nth-child(2n) { background: #eee; }
@media amzn-kf8 { p { text-indent: 0; } }
@media screen and (min-width: 600px) { body { margin: 0 5%; } }
@media (prefers-color-scheme: dark) { a { color: #80b0ff; } }
.vertical { writing-mode: vertical-rl; -webkit-writing-mode: vertical-rl; }
''';
