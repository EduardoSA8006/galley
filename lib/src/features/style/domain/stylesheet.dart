import 'package:meta/meta.dart';

import 'css_value.dart';
import 'selector.dart';
import 'style_environment.dart';

/// Nome interno da família [family] do livro, para não misturar famílias
/// de mesmo nome entre livros no engine de fontes (spec §8.8).
///
/// [fontPrefix] é o prefixo do livro (hex em minúsculas, ex. `gf1a2b-`).
/// Fonte única deste cálculo: o casamento das famílias usa a mesma função.
String internalFontFamily(String fontPrefix, String family) =>
    (fontPrefix + family).toLowerCase();

/// Declaração interpretada: uma longhand com seu valor.
@immutable
final class Declaration {
  /// Cria a declaração.
  const Declaration(this.property, this.value, {this.important = false});

  /// Id da propriedade (`PropertyId`).
  final int property;

  /// Valor pré-interpretado.
  final CssValue value;

  /// Se veio com `!important`.
  final bool important;

  @override
  bool operator ==(Object other) =>
      other is Declaration &&
      other.property == property &&
      other.value == value &&
      other.important == important;

  @override
  int get hashCode => Object.hash(property, value, important);

  @override
  String toString() =>
      'Declaration($property, $value${important ? ', !important' : ''})';
}

/// Regra de estilo com um único seletor: `p, q {…}` vira duas regras que
/// compartilham a lista de declarações.
@immutable
final class StyleRule {
  /// Cria a regra.
  const StyleRule({
    required this.selector,
    required this.declarations,
    required this.order,
    this.conditions = const [],
  });

  /// O seletor.
  final Selector selector;

  /// Declarações, na ordem do texto.
  final List<Declaration> declarations;

  /// Posição na folha (cresce na ordem do texto), para a cascata.
  final int order;

  /// `@media` em volta, do mais externo ao mais interno; todos precisam
  /// valer no ambiente.
  final List<MediaQueryList> conditions;
}

/// Fonte de um `@font-face`.
@immutable
sealed class FontSource {
  const FontSource();
}

/// `url(...)`, resolvida no zip pela folha.
final class FontUrlSource extends FontSource {
  /// Cria a fonte.
  const FontUrlSource(this.path, this.format);

  /// Caminho no zip.
  final String path;

  /// Primeiro formato de `format(...)`, em minúsculas, se houver.
  final String? format;

  @override
  bool operator ==(Object other) =>
      other is FontUrlSource && other.path == path && other.format == format;

  @override
  int get hashCode => Object.hash(FontUrlSource, path, format);

  @override
  String toString() => 'FontUrlSource($path, $format)';
}

/// `local(...)`: fonte instalada no sistema.
final class FontLocalSource extends FontSource {
  /// Cria a fonte.
  const FontLocalSource(this.name);

  /// Nome da fonte, como escrito.
  final String name;

  @override
  bool operator ==(Object other) =>
      other is FontLocalSource && other.name == name;

  @override
  int get hashCode => Object.hash(FontLocalSource, name);

  @override
  String toString() => 'FontLocalSource($name)';
}

/// Uma regra `@font-face` válida.
@immutable
final class FontFaceRule {
  /// Cria a regra.
  const FontFaceRule({
    required this.family,
    required this.internalFamily,
    required this.sources,
    this.weightMin = 400,
    this.weightMax = 400,
    this.style = CssKeywords.normal,
    this.stretch,
    this.unicodeRanges = const [(0, 0x10FFFF)],
  });

  /// Família como escrita na folha.
  final String family;

  /// Nome interno por livro ([internalFontFamily]).
  final String internalFamily;

  /// Fontes utilizáveis, em ordem de preferência (nunca vazia).
  final List<FontSource> sources;

  /// Menor peso coberto (1–1000).
  final int weightMin;

  /// Maior peso coberto (1–1000).
  final int weightMax;

  /// Estilo: id de `CssKeywords` (`normal`, `italic` ou `oblique`).
  final int style;

  /// `font-stretch` em minúsculas como escrito (`condensed`, `75%`...), ou
  /// `null` se ausente ou inválido.
  final String? stretch;

  /// Faixas de code points `(início, fim)` inclusivas; sem `unicode-range`,
  /// todo o Unicode.
  final List<(int, int)> unicodeRanges;
}

/// Margens de um `@page` sem seletor; `null` = não declarada (ou `auto`).
@immutable
final class PageMargins {
  /// Cria as margens.
  const PageMargins({this.top, this.right, this.bottom, this.left});

  /// Margem de cima.
  final CssLengthSpec? top;

  /// Margem da direita.
  final CssLengthSpec? right;

  /// Margem de baixo.
  final CssLengthSpec? bottom;

  /// Margem da esquerda.
  final CssLengthSpec? left;

  @override
  bool operator ==(Object other) =>
      other is PageMargins &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom &&
      other.left == left;

  @override
  int get hashCode => Object.hash(top, right, bottom, left);

  @override
  String toString() => 'PageMargins($top, $right, $bottom, $left)';
}

/// `@import`: folha a ler antes das regras desta.
@immutable
final class ImportRef {
  /// Cria a referência.
  const ImportRef(this.path, {this.media});

  /// Caminho no zip, resolvido pela folha que importa.
  final String path;

  /// Media queries do `@import`; `null` se não houver.
  final MediaQueryList? media;
}

/// Folha de estilo interpretada.
///
/// Não depende do ambiente (os `@media` são avaliados no casamento; o
/// `@supports` já foi resolvido na montagem), por isso pode ser guardada
/// por livro.
@immutable
final class StyleSheet {
  /// Cria a folha.
  const StyleSheet({
    this.rules = const [],
    this.fontFaces = const [],
    this.pages = const [],
    this.imports = const [],
  });

  /// Folha vazia.
  static final StyleSheet empty = const StyleSheet();

  /// Regras de estilo, em ordem.
  final List<StyleRule> rules;

  /// `@font-face` válidos, em ordem.
  final List<FontFaceRule> fontFaces;

  /// Margens de cada `@page` sem seletor, com os `@media` em volta.
  final List<(PageMargins, List<MediaQueryList>)> pages;

  /// `@import`s, em ordem.
  final List<ImportRef> imports;
}
