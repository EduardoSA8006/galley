// ComputedStyle (spec do CSS §3): valores iniciais de §7.1, igualdade por
// valor (a internação depende dela) e os campos derivados.
import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/css/computed_style.dart';

void main() {
  test('initial tem os valores iniciais de §7.1', () {
    const s = ComputedStyle.initial;
    expect(
      (s.display, s.whiteSpace, s.direction, s.verticalAlign, s.listStyleType),
      (
        CssDisplay.inline,
        CssWhiteSpace.normal,
        CssDirection.ltr,
        CssVerticalAlign.baseline,
        CssListStyleType.disc,
      ),
    );
    expect(
      (s.breakBefore, s.breakAfter, s.breakInside),
      (CssBreak.auto, CssBreak.auto, CssBreak.auto),
    );
    expect((s.width, s.height), (null, null));
    expect(
      (s.alignKeyword, s.textAlign),
      (CssAlignKeyword.start, CssTextAlign.start),
    );
    expect((s.underline, s.lineThrough), (false, false));
    expect(
      (s.fontStyle, s.weight, s.fontWeight),
      (CssFontStyle.normal, 400, CssFontWeight.normal),
    );
    expect(
      (s.fontVariant, s.textTransform, s.fontSizeStep),
      (CssFontVariant.normal, CssTextTransform.none, CssFontSizeStep.same),
    );
    expect(
      (s.margin, s.padding, s.textIndent),
      (EmEdges.zero, EmEdges.zero, 0.0),
    );
  });

  test('igualdade e hashCode por valor, campo a campo', () {
    const a = ComputedStyle(
      display: CssDisplay.block,
      width: CssLength(50, CssLengthUnit.percent),
      margin: EmEdges(1, 0, 1, 0),
    );
    // Valores de tempo de execução: b não é a mesma instância canônica de a.
    final fifty = double.parse('50');
    final b = ComputedStyle(
      display: CssDisplay.block,
      width: CssLength(fifty, CssLengthUnit.percent),
      margin: EmEdges(1, 0, 1, fifty - 50),
    );
    expect(identical(a, b), isFalse);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect({a: 1}[b], 1, reason: 'serve de chave do mapa de internação');
    expect(a == const ComputedStyle(display: CssDisplay.block), isFalse);
    expect(
      const ComputedStyle(underline: true) == ComputedStyle.initial,
      isFalse,
    );
    expect(
      const ComputedStyle(width: CssLength(1, CssLengthUnit.em)) ==
          const ComputedStyle(width: CssLength(1, CssLengthUnit.percent)),
      isFalse,
    );
  });

  test(
    'textAlign resolve left/right pela direção do elemento (CSS Text 3)',
    () {
      for (final (keyword, ltr, rtl) in [
        (CssAlignKeyword.left, CssTextAlign.start, CssTextAlign.end),
        (CssAlignKeyword.right, CssTextAlign.end, CssTextAlign.start),
        (CssAlignKeyword.start, CssTextAlign.start, CssTextAlign.start),
        (CssAlignKeyword.end, CssTextAlign.end, CssTextAlign.end),
        (CssAlignKeyword.center, CssTextAlign.center, CssTextAlign.center),
      ]) {
        expect(ComputedStyle(alignKeyword: keyword).textAlign, ltr);
        expect(
          ComputedStyle(
            alignKeyword: keyword,
            direction: CssDirection.rtl,
          ).textAlign,
          rtl,
        );
      }
    },
  );

  test('fontWeight é bold a partir de 600', () {
    expect(const ComputedStyle(weight: 599).fontWeight, CssFontWeight.normal);
    expect(const ComputedStyle(weight: 600).fontWeight, CssFontWeight.bold);
    expect(const ComputedStyle(weight: 1000).fontWeight, CssFontWeight.bold);
  });

  test('CssLength e EmEdges com igualdade por valor', () {
    expect(
      const CssLength(2, CssLengthUnit.em),
      const CssLength(2, CssLengthUnit.em),
    );
    expect(const EmEdges(1, 2, 3, 4), const EmEdges(1, 2, 3, 4));
    expect(const EmEdges(1, 2, 3, 4) == const EmEdges(4, 3, 2, 1), isFalse);
    expect(StyleClass.values, hasLength(3));
  });
}
