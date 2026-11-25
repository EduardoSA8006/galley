import 'package:meta/meta.dart';

/// Política de uma preferência do leitor (spec §8.7).
enum PreferencePolicy {
  /// "Editora": a preferência não age; vale o livro.
  publisher,

  /// "Ajustar" (padrão): opera sobre o valor da editora, em geral só no
  /// texto corrido.
  adjust,

  /// "Forçar": substitui o valor da editora em tudo.
  force,
}

/// Valor escolhido pelo leitor com a sua [policy].
@immutable
final class Preference<T> {
  /// Cria a preferência.
  const Preference(this.value, {this.policy = PreferencePolicy.adjust});

  /// O valor (o significado depende da preferência e da política).
  final T value;

  /// Como o valor é aplicado.
  final PreferencePolicy policy;

  @override
  bool operator ==(Object other) =>
      other is Preference<T> && other.value == value && other.policy == policy;

  @override
  int get hashCode => Object.hash(value, policy);

  @override
  String toString() => 'Preference($value, $policy)';
}

/// Tema do leitor: cores ARGB (`0xAARRGGBB`) de fundo, texto e links.
@immutable
final class ReaderTheme {
  /// Cria o tema.
  const ReaderTheme({
    required this.background,
    required this.text,
    required this.link,
  });

  /// Cor do fundo da página.
  final int background;

  /// Cor do texto.
  final int text;

  /// Cor dos links.
  final int link;

  @override
  bool operator ==(Object other) =>
      other is ReaderTheme &&
      other.background == background &&
      other.text == text &&
      other.link == link;

  @override
  int get hashCode => Object.hash(background, text, link);
}

/// Alinhamento escolhido pelo leitor.
enum ReaderTextAlign {
  /// Início da linha.
  start,

  /// Fim da linha.
  end,

  /// À esquerda.
  left,

  /// À direita.
  right,

  /// Centralizado.
  center,

  /// Justificado.
  justify,
}

/// Preferências do leitor (spec §8.7). Cada uma é opcional: `null` = vale a
/// editora. Sem preferência alguma ([none]), o resultado é idêntico ao do
/// livro.
///
/// Só o modelo: a passada que aplica as preferências é feita no `restyle`.
/// Ela ignora valores numéricos não finitos (NaN, ±∞), fator de fonte e
/// entrelinha ≤ 0, e limita os demais a ±1e9 (ver `PreferencePass`).
@immutable
final class ReaderPreferences {
  /// Cria as preferências.
  const ReaderPreferences({
    this.fontFamily,
    this.preserveHeadingFonts = false,
    this.fontSize,
    this.lineHeight,
    this.paragraphSpacing,
    this.textIndent,
    this.textAlign,
    this.hyphenation,
    this.wordSpacing,
    this.letterSpacing,
    this.theme,
    this.genericFamilies = const {},
  });

  /// Nenhuma preferência: vale o livro.
  static const ReaderPreferences none = ReaderPreferences();

  /// Família da fonte (nome já registrado no Flutter).
  final Preference<String>? fontFamily;

  /// Se os títulos mantêm a fonte da editora quando [fontFamily] age.
  final bool preserveHeadingFonts;

  /// Tamanho da fonte: fator em "ajustar", px do texto corrido em "forçar".
  final Preference<double>? fontSize;

  /// Espaçamento entre linhas (multiplicador em "ajustar").
  final Preference<double>? lineHeight;

  /// Espaçamento entre parágrafos, em `em`.
  final Preference<double>? paragraphSpacing;

  /// Recuo da primeira linha, em `em`.
  final Preference<double>? textIndent;

  /// Alinhamento.
  final Preference<ReaderTextAlign>? textAlign;

  /// Hifenização ligada ou desligada.
  final Preference<bool>? hyphenation;

  /// Acréscimo relativo de espaço entre palavras.
  final Preference<double>? wordSpacing;

  /// Acréscimo relativo de espaço entre letras.
  final Preference<double>? letterSpacing;

  /// Tema de cores.
  final Preference<ReaderTheme>? theme;

  /// Mapeamento das famílias genéricas (`serif`, `monospace`...) para
  /// famílias registradas no app.
  final Map<String, String> genericFamilies;
}
