import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/core/diagnostics/diagnostic_sink.dart';
import 'package:galley/src/features/style/data/css_syntax.dart';
import 'package:galley/src/features/style/data/media_query_parser.dart';
import 'package:galley/src/features/style/domain/style_environment.dart';

const light = StyleEnvironment(pageWidth: 600, pageHeight: 800);
const dark = StyleEnvironment(
  pageWidth: 600,
  pageHeight: 800,
  colorScheme: ColorScheme.dark,
);

bool matches(String text, [StyleEnvironment env = light]) =>
    parseMediaQueryText(text).evaluate(env);

void main() {
  group('verdadeiras no ambiente 600×800 claro', () {
    for (final q in [
      'screen',
      'all',
      'only screen and (min-width: 500px)',
      'screen, print',
      '(400px <= width <= 700px)',
      '(orientation: portrait)',
      '(prefers-color-scheme)',
      '(min-width: 30em)',
      'SCREEN',
      'Screen AND (MIN-WIDTH: 500PX)',
      '',
      'not print',
      '(width >= 600px)',
      '(600px = width)',
      '(width < 601px)',
      '(800px >= height)',
      '(max-aspect-ratio: 1/1)',
      '(aspect-ratio: 3/4)',
      '(aspect-ratio: 6 / 8)',
      '(width) and (height)',
      '(orientation)',
      '(prefers-color-scheme: light)',
      '((min-width: 1px) and (min-height: 1px))',
      '(max-width: 1px) or (min-width: 1px)',
      'not (max-width: 1px)',
      '(min-width: 0)',
      '(max-width: 6.25in)',
      'print, (foo: 1), screen',
    ]) {
      test('"$q"', () => expect(matches(q), isTrue));
    }
  });

  group('falsas no ambiente 600×800 claro', () {
    for (final q in [
      'print',
      'amzn-kf8',
      'amazon-kf8',
      'amzn-mobi',
      'speech',
      'aural',
      'tv',
      'handheld',
      'projection',
      'braille',
      'embossed',
      'tty',
      'not screen',
      'not all',
      '(max-width: 599px)',
      '(min-aspect-ratio: 1/1)',
      '(foo: 1)',
      'not (foo: 1)',
      '(prefers-color-scheme: dark)',
      '(orientation: landscape)',
      '(min-width: 601px)',
      '(width > 600px)',
      '(min-width: abc)',
      '(min-orientation: portrait)',
      'screen and',
      'screen foo',
      'only (width)',
      'screen and (width) or (height)',
      '(width) and (height) or (width)',
      'not',
      'and',
      'foo',
      '(width: 600)',
      'unknownfn(1)',
      ')',
    ]) {
      test('"$q"', () => expect(matches(q), isFalse));
    }
  });

  test('prefers-color-scheme: dark verdadeira no ambiente escuro', () {
    expect(matches('(prefers-color-scheme: dark)', dark), isTrue);
    expect(matches('(prefers-color-scheme: light)', dark), isFalse);
    expect(matches('(prefers-color-scheme)', dark), isTrue);
  });

  test('orientation: portrait quando altura == largura', () {
    const square = StyleEnvironment(pageWidth: 500, pageHeight: 500);
    expect(matches('(orientation: portrait)', square), isTrue);
    expect(matches('(orientation: landscape)', square), isFalse);
  });

  test('paisagem', () {
    const wide = StyleEnvironment(pageWidth: 900, pageHeight: 500);
    expect(matches('(orientation: landscape)', wide), isTrue);
    expect(matches('(min-aspect-ratio: 16/9)', wide), isTrue);
  });

  test('parseMediaQueryList a partir dos tokens do prelúdio', () {
    final at =
        parseCss(
              '@media only screen and (max-width: 700px) {}',
              location: 'a.css',
              sink: const NullDiagnosticSink(),
            ).rules.single
            as AtRule;
    expect(parseMediaQueryList(at.prelude).evaluate(light), isTrue);
  });

  test('100.000 "(" é falso, linear e sem estouro de pilha', () {
    final sw = Stopwatch()..start();
    expect(matches('${'(' * 100000}width'), isFalse);
    expect(matches('${'(' * 100000}width${')' * 100000}'), isFalse);
    expect(matches('${'(' * 32}width${')' * 32}'), isTrue);
    expect(matches('${'(' * 33}width${')' * 33}'), isFalse);
    expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
  });
}
