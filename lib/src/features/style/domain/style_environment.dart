import 'package:meta/meta.dart';

/// Esquema de cor do tema do app (`prefers-color-scheme`).
enum ColorScheme {
  /// Claro.
  light,

  /// Escuro.
  dark,
}

/// Dados do ambiente para avaliar `@media` (spec §8.1): a mídia é sempre
/// `screen`; largura e altura da página em px lógicos; esquema de cor do
/// tema. O `em` das consultas é fixo em 16 px.
@immutable
final class StyleEnvironment {
  /// Cria o ambiente.
  const StyleEnvironment({
    required this.pageWidth,
    required this.pageHeight,
    this.colorScheme = ColorScheme.light,
  });

  /// Largura da página em px lógicos.
  final double pageWidth;

  /// Altura da página em px lógicos.
  final double pageHeight;

  /// Esquema de cor do tema.
  final ColorScheme colorScheme;

  @override
  bool operator ==(Object other) =>
      other is StyleEnvironment &&
      other.pageWidth == pageWidth &&
      other.pageHeight == pageHeight &&
      other.colorScheme == colorScheme;

  @override
  int get hashCode => Object.hash(pageWidth, pageHeight, colorScheme);

  @override
  String toString() =>
      'StyleEnvironment(${pageWidth}x$pageHeight, ${colorScheme.name})';
}

/// Comparação de um recurso de intervalo (`width`, `height`,
/// `aspect-ratio`) com um valor: `recurso <op> valor`.
enum MediaComparison {
  /// `<`.
  less,

  /// `<=` (e `max-`).
  lessOrEqual,

  /// `=` (e a forma simples `(width: v)`).
  equal,

  /// `>=` (e `min-`).
  greaterOrEqual,

  /// `>`.
  greater,
}

/// Condição de uma media query, com lógica de três valores (Media Queries
/// 4 §3): `null` é "desconhecido" (recurso desconhecido ou valor inválido)
/// e, no fim, conta como falso.
///
/// A profundidade da árvore é limitada pelo leitor (32 níveis de
/// parênteses), então a avaliação recursiva é limitada.
@immutable
sealed class MediaCondition {
  const MediaCondition();

  /// Valor no ambiente [env]; `null` = desconhecido.
  bool? evaluate(StyleEnvironment env);
}

/// Condição de valor fixo, ou desconhecida (`value == null`): recurso
/// desconhecido, valor inválido ou `<general-enclosed>`.
final class MediaConstant extends MediaCondition {
  /// Cria a constante.
  const MediaConstant(this.value);

  /// Condição desconhecida.
  static const MediaConstant unknown = MediaConstant(null);

  /// O valor fixo.
  final bool? value;

  @override
  bool? evaluate(StyleEnvironment env) => value;
}

/// `not <condição>`.
final class MediaNot extends MediaCondition {
  /// Cria a negação.
  const MediaNot(this.operand);

  /// Condição negada.
  final MediaCondition operand;

  @override
  bool? evaluate(StyleEnvironment env) {
    final v = operand.evaluate(env);
    return v == null ? null : !v;
  }
}

/// `a and b and ...`.
final class MediaAnd extends MediaCondition {
  /// Cria a conjunção.
  const MediaAnd(this.operands);

  /// As condições.
  final List<MediaCondition> operands;

  @override
  bool? evaluate(StyleEnvironment env) {
    var unknown = false;
    for (final c in operands) {
      final v = c.evaluate(env);
      if (v == false) return false;
      if (v == null) unknown = true;
    }
    return unknown ? null : true;
  }
}

/// `a or b or ...`.
final class MediaOr extends MediaCondition {
  /// Cria a disjunção.
  const MediaOr(this.operands);

  /// As condições.
  final List<MediaCondition> operands;

  @override
  bool? evaluate(StyleEnvironment env) {
    var unknown = false;
    for (final c in operands) {
      final v = c.evaluate(env);
      if (v == true) return true;
      if (v == null) unknown = true;
    }
    return unknown ? null : false;
  }
}

/// `width` ou `height` comparado a [px] (px lógicos; `em` já convertido).
/// [comparison] `null` é o contexto booleano (`(width)`: diferente de 0).
final class MediaSizeTest extends MediaCondition {
  /// Cria o teste; [height] escolhe a altura em vez da largura.
  const MediaSizeTest({
    required this.height,
    required this.comparison,
    this.px = 0,
  });

  /// Se testa a altura (senão, a largura).
  final bool height;

  /// Comparação, ou `null` no contexto booleano.
  final MediaComparison? comparison;

  /// Valor comparado, em px.
  final double px;

  @override
  bool? evaluate(StyleEnvironment env) {
    final v = height ? env.pageHeight : env.pageWidth;
    final c = comparison;
    if (c == null) return v != 0;
    return _compare(v.compareTo(px), c);
  }
}

/// `aspect-ratio` (largura/altura) comparado a [numerator]/[denominator].
/// [comparison] `null` é o contexto booleano.
final class MediaAspectRatioTest extends MediaCondition {
  /// Cria o teste.
  const MediaAspectRatioTest({
    required this.comparison,
    this.numerator = 1,
    this.denominator = 1,
  });

  /// Comparação, ou `null` no contexto booleano.
  final MediaComparison? comparison;

  /// Numerador (positivo).
  final double numerator;

  /// Denominador (positivo).
  final double denominator;

  @override
  bool? evaluate(StyleEnvironment env) {
    final c = comparison;
    if (c == null) return env.pageWidth != 0 && env.pageHeight != 0;
    // largura/altura ? n/d  ⇔  largura·d ? n·altura (ambos positivos).
    final lhs = env.pageWidth * denominator;
    final rhs = numerator * env.pageHeight;
    return _compare(lhs.compareTo(rhs), c);
  }
}

/// `orientation`: retrato quando a altura ≥ largura. [portrait] `null` é o
/// contexto booleano (sempre verdadeiro).
final class MediaOrientationTest extends MediaCondition {
  /// Cria o teste.
  const MediaOrientationTest(this.portrait);

  /// `portrait` (verdadeiro), `landscape` (falso) ou contexto booleano.
  final bool? portrait;

  @override
  bool? evaluate(StyleEnvironment env) {
    final p = portrait;
    if (p == null) return true;
    return (env.pageHeight >= env.pageWidth) == p;
  }
}

/// `prefers-color-scheme`; [scheme] `null` é o contexto booleano (sempre
/// verdadeiro).
final class MediaColorSchemeTest extends MediaCondition {
  /// Cria o teste.
  const MediaColorSchemeTest(this.scheme);

  /// Esquema exigido, ou `null`.
  final ColorScheme? scheme;

  @override
  bool? evaluate(StyleEnvironment env) {
    final s = scheme;
    return s == null || env.colorScheme == s;
  }
}

bool _compare(int order, MediaComparison c) => switch (c) {
  MediaComparison.less => order < 0,
  MediaComparison.lessOrEqual => order <= 0,
  MediaComparison.equal => order == 0,
  MediaComparison.greaterOrEqual => order >= 0,
  MediaComparison.greater => order > 0,
};

/// Uma media query: `[not|only]? tipo [and condição]?` ou só a condição.
@immutable
final class MediaQuery {
  /// Cria a consulta.
  const MediaQuery({
    this.negated = false,
    this.typeMatches = true,
    this.condition,
  });

  /// Consulta malformada: nunca casa, nem com `not` (vira `not all`).
  static const MediaQuery never = MediaQuery(typeMatches: false);

  /// Se começa com `not`.
  final bool negated;

  /// Se o tipo de mídia casa (`all`/`screen`, ou ausente).
  final bool typeMatches;

  /// Condição, se houver.
  final MediaCondition? condition;

  /// Se a consulta vale em [env]; desconhecido conta como falso.
  bool evaluate(StyleEnvironment env) {
    bool? v = typeMatches;
    final c = condition;
    if (v && c != null) v = c.evaluate(env);
    if (v == null) return false;
    return negated ? !v : v;
  }
}

/// Lista de media queries separadas por vírgula (`@media`, atributo
/// `media`, `@import`): vale se alguma valer; lista vazia vale sempre.
///
/// Não depende do ambiente na leitura: é avaliada no casamento, por isso a
/// folha pode ser guardada por livro.
@immutable
final class MediaQueryList {
  /// Cria a lista.
  const MediaQueryList(this.queries);

  /// Lista vazia (sempre verdadeira).
  static const MediaQueryList all = MediaQueryList([]);

  /// As consultas.
  final List<MediaQuery> queries;

  /// Se a lista vale em [env].
  bool evaluate(StyleEnvironment env) {
    if (queries.isEmpty) return true;
    for (final q in queries) {
      if (q.evaluate(env)) return true;
    }
    return false;
  }
}
