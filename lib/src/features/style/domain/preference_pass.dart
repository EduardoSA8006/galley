import 'package:meta/meta.dart';

import 'css_value.dart';
import 'matched_document.dart';
import 'properties.dart';
import 'reader_preferences.dart';
import 'text_run.dart';

/// Passada de preferências do leitor sobre os valores calculados (spec
/// §8.5, §8.7). Não é origem da cascata: transforma o valor calculado da
/// editora depois da herança, então vale mesmo contra `!important`.
///
/// **Regra da fronteira.** O valor de cada elemento é calculado a partir
/// do pai **já ajustado** e depois transformado. Uma propriedade herdada só
/// é transformada onde o valor nasce: o elemento a declara (sem
/// `inherit`/`unset`), é a raiz, ou entra no escopo da preferência (o pai
/// não é texto corrido / título e ele é). Um valor só herdado nunca é
/// transformado de novo, e na saída do escopo segue como está.
///
/// O tamanho da fonte não passa por aqui: o fator ([fontScale]) entra no
/// cálculo do `font-size` (`ValueComputer.compute`), para que `em` e as
/// demais unidades relativas já usem o tamanho ajustado.
final class PreferencePass {
  /// Prepara a passada de [preferences] para o documento [matched]. As
  /// preferências com política "editora" são ignoradas.
  factory PreferencePass(
    ReaderPreferences preferences,
    MatchedDocument matched,
  ) {
    Preference<T>? active<T>(Preference<T>? p) =>
        p == null || p.policy == PreferencePolicy.publisher ? null : p;

    final size = active(preferences.fontSize);
    var scale = 1.0;
    if (size != null) {
      scale = size.policy == PreferencePolicy.force
          ? (matched.bodyFontSize > 0 ? size.value / matched.bodyFontSize : 1)
          : size.value;
      if (!scale.isFinite || scale <= 0) scale = 1;
    }
    return PreferencePass._(
      fontScale: scale,
      family: active(preferences.fontFamily),
      preserveHeadingFonts: preferences.preserveHeadingFonts,
      lineHeight: active(preferences.lineHeight),
      paragraphSpacing: active(preferences.paragraphSpacing),
      textIndent: active(preferences.textIndent),
      textAlign: active(preferences.textAlign),
      hyphenation: active(preferences.hyphenation),
      wordSpacing: active(preferences.wordSpacing),
      letterSpacing: active(preferences.letterSpacing),
      theme: active(preferences.theme)?.value,
      genericFamilies: preferences.genericFamilies,
    );
  }

  PreferencePass._({
    required this.fontScale,
    required Preference<String>? family,
    required this._preserveHeadingFonts,
    required this._lineHeight,
    required this._paragraphSpacing,
    required this._textIndent,
    required this._textAlign,
    required this._hyphenation,
    required this._wordSpacing,
    required this._letterSpacing,
    required this.theme,
    required this._genericFamilies,
  }) : _family = family,
       _familyValue = family == null
           ? null
           : CssFontFamilies(List.unmodifiable([FontFamilyName(family.value)]));

  /// Fator do tamanho da fonte (1 = editora): o valor em "ajustar";
  /// `alvo / tamanho do corpo da editora` em "forçar".
  final double fontScale;

  /// Tema ativo (as duas políticas agem igual), ou `null`.
  final ReaderTheme? theme;

  final Preference<String>? _family;
  final CssFontFamilies? _familyValue;
  final bool _preserveHeadingFonts;
  final Preference<double>? _lineHeight;
  final Preference<double>? _paragraphSpacing;
  final Preference<double>? _textIndent;
  final Preference<ReaderTextAlign>? _textAlign;
  final Preference<bool>? _hyphenation;
  final Preference<double>? _wordSpacing;
  final Preference<double>? _letterSpacing;
  final Map<String, String> _genericFamilies;

  /// Se alguma preferência age (sem nenhuma, o resultado é o do livro).
  bool get isActive =>
      fontScale != 1 ||
      _family != null ||
      _lineHeight != null ||
      _paragraphSpacing != null ||
      _textIndent != null ||
      _textAlign != null ||
      _hyphenation != null ||
      _wordSpacing != null ||
      _letterSpacing != null ||
      theme != null ||
      _genericFamilies.isNotEmpty;

  /// Se o resultado depende de o elemento ser o `body` (o tema pinta o
  /// fundo da raiz e do `body`; o espaçamento entre parágrafos em "forçar"
  /// poupa as margens da raiz e do `body`).
  bool get dependsOnBody =>
      theme != null || _paragraphSpacing?.policy == PreferencePolicy.force;

  /// Se o elemento de marcas [flags] fica com a família calculada da
  /// editora (monoespaçada em "ajustar", ou título com
  /// `preserveHeadingFonts`): aí o resultado depende dessa família.
  bool keepsPublisherFamily(int flags) {
    final family = _family;
    if (family == null || family.policy == PreferencePolicy.force) {
      return false;
    }
    return flags & ElementFlags.monospace != 0 ||
        (_preserveHeadingFonts && flags & ElementFlags.heading != 0);
  }

  /// Se a passada guarda, em paralelo, o valor herdado da editora das
  /// propriedades que ajusta no texto corrido ([PublisherSnapshot]): só
  /// com alguma delas em "ajustar".
  bool get tracksPublisher =>
      _adjusts(_lineHeight) ||
      _adjusts(_textIndent) ||
      _adjusts(_textAlign) ||
      _adjusts(_hyphenation) ||
      _adjusts(_wordSpacing) ||
      _adjusts(_letterSpacing);

  /// Transforma [values] (calculados da editora a partir do pai já
  /// ajustado) no lugar.
  ///
  /// [set] são as declarações vencedoras do elemento; [flags] e
  /// [parentFlags], as marcas dele e do pai (`ElementFlags`; num
  /// pseudo-elemento, as do elemento nas duas). [publisherFamily] é a
  /// família calculada da editora do elemento, usada quando
  /// [keepsPublisherFamily]; num pseudo-elemento, `null` (fica a calculada).
  ///
  /// [parentPublisher] é o instantâneo da editora do pai quando o pai está
  /// no texto corrido (com [tracksPublisher]). Um elemento que sai do
  /// escopo (bloco interno: `pre`, tabela, título, epígrafe menor) herda
  /// dele, nas propriedades que não declara, o valor da editora e não o
  /// ajustado. Devolve o instantâneo do próprio elemento quando ele está no
  /// texto corrido (para os filhos), senão `null`.
  PublisherSnapshot? apply(
    List<CssValue> values,
    CascadedValues set, {
    required int flags,
    required int parentFlags,
    required bool isRoot,
    required bool isBody,
    required bool isPseudo,
    CssFontFamilies? publisherFamily,
    PublisherSnapshot? parentPublisher,
  }) {
    final inRun = _inRun(flags);
    final enteringRun = inRun && (isRoot || !_inRun(parentFlags));
    final heading = flags & ElementFlags.heading != 0;
    final enteringHeading =
        heading && (isRoot || parentFlags & ElementFlags.heading == 0);
    bool runBorn(int p) => inRun && (enteringRun || _declares(set, p));
    bool headingBorn(int p) =>
        heading && !inRun && (enteringHeading || _declares(set, p));

    final fs = (values[PropertyId.fontSize] as CssLength).px;

    // `line-height` declarado em unidade absoluta acompanha o fator.
    if (fontScale != 1) {
      final spec = set.valueOf(PropertyId.lineHeight);
      final lh = values[PropertyId.lineHeight];
      if (spec is CssLengthSpec && spec.px != 0 && lh is CssLength) {
        final px = lh.px + spec.px * (fontScale - 1);
        values[PropertyId.lineHeight] = CssLength(
          px: px < 0 ? 0 : px,
          percent: lh.percent,
          vw: lh.vw,
          vh: lh.vh,
        );
      }
    }

    // Saída do texto corrido: o herdado volta a ser o da editora.
    const tracked = PublisherSnapshot.properties;
    if (!inRun && parentPublisher != null) {
      for (var k = 0; k < tracked.length; k++) {
        if (!_declares(set, tracked[k])) {
          values[tracked[k]] = parentPublisher.values[k];
        }
      }
    }
    PublisherSnapshot? own;
    if (inRun && tracksPublisher) {
      own = PublisherSnapshot([
        for (var k = 0; k < tracked.length; k++)
          parentPublisher == null || _declares(set, tracked[k])
              ? values[tracked[k]]
              : parentPublisher.values[k],
      ]);
    }

    final lineHeight = _lineHeight;
    if (lineHeight != null) {
      const p = PropertyId.lineHeight;
      final m = lineHeight.value;
      if (lineHeight.policy == PreferencePolicy.force) {
        values[p] = CssNumber(m);
      } else if (runBorn(p)) {
        values[p] = _multiplyLineHeight(values[p], m);
      } else if (headingBorn(p)) {
        values[p] = _multiplyLineHeight(values[p], 1 + (m - 1) / 2);
      }
    }

    final display = (values[PropertyId.display] as CssKeyword).id;
    final isBlock =
        !isPseudo &&
        (display == CssKeywords.block || display == CssKeywords.listItem);
    final isRunRoot = !isPseudo && flags & ElementFlags.textRunRoot != 0;

    final spacing = _paragraphSpacing;
    if (spacing != null &&
        (spacing.policy == PreferencePolicy.force
            // A raiz e o `body` não são parágrafos: as margens deles são as
            // bordas da página.
            ? isBlock && !isRoot && !isBody
            : isRunRoot && flags & ElementFlags.listItem == 0)) {
      values[PropertyId.marginTop] = const CssLength();
      values[PropertyId.marginBottom] = CssLength(px: spacing.value * fs);
    }

    final indent = _textIndent;
    if (indent != null &&
        (indent.policy == PreferencePolicy.force ? isBlock : isRunRoot)) {
      values[PropertyId.textIndent] = CssLength(px: indent.value * fs);
    }

    final align = _textAlign;
    if (align != null) {
      const p = PropertyId.textAlign;
      if (align.policy == PreferencePolicy.force) {
        values[p] = CssKeyword(_alignKeyword(align.value));
      } else if (runBorn(p) && _alignsToStart(values)) {
        values[p] = CssKeyword(_alignKeyword(align.value));
      }
    }

    final hyphenation = _hyphenation;
    if (hyphenation != null &&
        (hyphenation.policy == PreferencePolicy.force ||
            runBorn(PropertyId.hyphens))) {
      values[PropertyId.hyphens] = CssKeyword(
        hyphenation.value ? CssKeywords.auto : CssKeywords.manual,
      );
    }

    for (final (pref, p) in [
      (_wordSpacing, PropertyId.wordSpacing),
      (_letterSpacing, PropertyId.letterSpacing),
    ]) {
      if (pref == null) continue;
      final extra = pref.value * fs;
      if (pref.policy == PreferencePolicy.force) {
        values[p] = CssLength(px: extra);
      } else if (runBorn(p)) {
        final old = values[p];
        values[p] = old is CssLength
            ? CssLength(
                px: old.px + extra,
                percent: old.percent,
                vw: old.vw,
                vh: old.vh,
              )
            : CssLength(px: extra);
      }
    }

    final familyValue = _familyValue;
    if (familyValue != null) {
      if (!keepsPublisherFamily(flags)) {
        values[PropertyId.fontFamily] = familyValue;
      } else if (publisherFamily != null) {
        values[PropertyId.fontFamily] = publisherFamily;
      }
    }
    if (_genericFamilies.isNotEmpty) {
      values[PropertyId.fontFamily] = _mapGenerics(
        values[PropertyId.fontFamily] as CssFontFamilies,
      );
    }

    final theme = this.theme;
    if (theme != null) {
      values[PropertyId.color] = CssColor(
        flags & ElementFlags.link != 0 ? theme.link : theme.text,
      );
      values[PropertyId.backgroundColor] = CssColor(
        isRoot || isBody ? theme.background : 0,
      );
      for (final p in _currentColorProperties) {
        values[p] = const CssKeyword(CssKeywords.currentcolor);
      }
    }
    return own;
  }

  CssFontFamilies _mapGenerics(CssFontFamilies value) {
    List<FontFamilyName>? out;
    final families = value.families;
    for (var i = 0; i < families.length; i++) {
      final f = families[i];
      if (!f.generic) continue;
      final mapped = _genericFamilies[f.name];
      if (mapped == null) continue;
      out ??= List.of(families);
      out[i] = FontFamilyName(mapped);
    }
    return out == null ? value : CssFontFamilies(List.unmodifiable(out));
  }
}

/// Valores da editora (sem os ajustes de texto corrido) das propriedades
/// herdadas que a passada ajusta, guardados em paralelo para os blocos que
/// saem do texto corrido herdarem o da editora (spec §8.7). Igualdade por
/// valor, para internar.
@immutable
final class PublisherSnapshot {
  /// Cria o instantâneo; [values] paralelo a [properties].
  PublisherSnapshot(List<CssValue> values)
    : assert(values.length == properties.length, 'um valor por propriedade'),
      values = List.unmodifiable(values);

  /// Propriedades guardadas.
  static const List<int> properties = [
    PropertyId.lineHeight,
    PropertyId.textAlign,
    PropertyId.hyphens,
    PropertyId.wordSpacing,
    PropertyId.letterSpacing,
    PropertyId.textIndent,
  ];

  /// Valor da editora de cada item de [properties].
  final List<CssValue> values;

  @override
  bool operator ==(Object other) =>
      other is PublisherSnapshot && listEquals(other.values, values);

  @override
  int get hashCode => Object.hashAll(values);
}

bool _adjusts(Preference<Object?>? p) =>
    p != null && p.policy == PreferencePolicy.adjust;

/// Texto corrido para as preferências: dentro de uma raiz de texto corrido
/// e fora de títulos.
bool _inRun(int flags) =>
    flags & ElementFlags.inTextRun != 0 && flags & ElementFlags.heading == 0;

/// Se [set] declara [p] com um valor próprio (`inherit`/`unset` só
/// repetem o herdado, que já foi transformado).
bool _declares(CascadedValues set, int p) {
  final v = set.valueOf(p);
  if (v == null) return false;
  return !(v is CssKeyword &&
      (v.id == CssKeywords.inherit || v.id == CssKeywords.unset));
}

/// `line-height` calculado [value] multiplicado por [m]: número × m,
/// comprimento × m, `normal` → `1,2 × m`.
CssValue _multiplyLineHeight(CssValue value, double m) => switch (value) {
  CssNumber(:final value) => CssNumber(value * m),
  CssLength(:final px, :final percent, :final vw, :final vh) => CssLength(
    px: px * m,
    percent: percent * m,
    vw: vw * m,
    vh: vh * m,
  ),
  CssKeyword(id: CssKeywords.normal) => CssNumber(1.2 * m),
  _ => value,
};

/// Se o alinhamento calculado é o do início da linha (`start`, `left` em
/// LTR, `right` em RTL) ou justificado; centralizado e fim ficam.
bool _alignsToStart(List<CssValue> values) {
  final align = values[PropertyId.textAlign];
  if (align is! CssKeyword) return false;
  final direction = values[PropertyId.direction];
  final rtl = direction is CssKeyword && direction.id == CssKeywords.rtl;
  return switch (align.id) {
    CssKeywords.start || CssKeywords.justify => true,
    CssKeywords.left => !rtl,
    CssKeywords.right => rtl,
    _ => false,
  };
}

int _alignKeyword(ReaderTextAlign align) => switch (align) {
  ReaderTextAlign.start => CssKeywords.start,
  ReaderTextAlign.end => CssKeywords.end,
  ReaderTextAlign.left => CssKeywords.left,
  ReaderTextAlign.right => CssKeywords.right,
  ReaderTextAlign.center => CssKeywords.center,
  ReaderTextAlign.justify => CssKeywords.justify,
};

/// Cores que o tema faz seguir a cor do texto.
const List<int> _currentColorProperties = [
  PropertyId.borderTopColor,
  PropertyId.borderRightColor,
  PropertyId.borderBottomColor,
  PropertyId.borderLeftColor,
  PropertyId.textDecorationColor,
  PropertyId.textEmphasisColor,
];
