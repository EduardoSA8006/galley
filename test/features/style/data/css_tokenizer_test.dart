import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/features/style/data/css_tokenizer.dart';

List<CssTokenType> types(String s) =>
    tokenizeCss(s).map((t) => t.type).toList();

CssToken one(String s) {
  final t = tokenizeCss(s);
  expect(t, hasLength(1), reason: s);
  return t.single;
}

void main() {
  group('tokenizeCss', () {
    test('regra simples', () {
      expect(types('a{color:red}'), [
        CssTokenType.ident,
        CssTokenType.leftBrace,
        CssTokenType.ident,
        CssTokenType.colon,
        CssTokenType.ident,
        CssTokenType.rightBrace,
      ]);
    });

    test('números', () {
      var t = one('12');
      expect((t.type, t.number, t.isInteger), (CssTokenType.number, 12, true));
      t = one('+.5e1');
      expect((t.number, t.isInteger), (5.0, false));
      t = one('10%');
      expect((t.type, t.number), (CssTokenType.percentage, 10));
      t = one('1e3px');
      expect((t.type, t.number, t.unit), (CssTokenType.dimension, 1000, 'px'));
      expect(one('1EM').unit, 'EM');
      t = one('-1.5em');
      expect((t.number, t.unit), (-1.5, 'em'));
    });

    test('strings e escapes', () {
      expect(one(r'"a\62 c"').value, 'abc');
      expect(one("'a\\\nb'").value, 'ab');
      expect(tokenizeCss('"ab\ncd"').first.type, CssTokenType.badString);
      final t = one(r'\31 0');
      expect((t.type, t.value), (CssTokenType.ident, '10'));
      expect(one(r'"\0"').value, '�');
      expect(one(r'"\110000"').value, '�');
      expect(one(r'"\D800"').value, '�');
    });

    test('url', () {
      final t = one('url( a.png )');
      expect((t.type, t.value), (CssTokenType.url, 'a.png'));
      expect(tokenizeCss('url(a b)').first.type, CssTokenType.badUrl);
      expect(types('url("a.png")'), [
        CssTokenType.function,
        CssTokenType.string,
        CssTokenType.rightParen,
      ]);
      expect(one('URL(x)').type, CssTokenType.url);
    });

    test('hash, cdo, cdc, comentário, NUL', () {
      expect(one('#id').isIdHash, isTrue);
      expect(one('#1a').isIdHash, isFalse);
      expect(types('<!-- -->'), [
        CssTokenType.cdo,
        CssTokenType.whitespace,
        CssTokenType.cdc,
      ]);
      expect(tokenizeCss('/* x'), isEmpty);
      final t = one('\u0000');
      expect((t.type, t.value), (CssTokenType.ident, '�'));
    });

    test('at-keyword, função e delim', () {
      expect(one('@media').value, 'media');
      expect(one('rgb(').type, CssTokenType.function);
      expect(one('@').type, CssTokenType.delim);
      expect(one('!').value, '!');
    });

    test('offsets valem no texto pré-processado', () {
      final src = 'a\r\nb';
      expect(preprocessCss(src), 'a\nb');
      final t = tokenizeCss(src);
      expect(t.map((e) => (e.start, e.end)), [(0, 1), (1, 2), (2, 3)]);
      expect(preprocessCss('a\fb\rc\u0000'), 'a\nb\nc�');
      expect(preprocessCss('x'), same('x'));
    });

    test('entradas de 1 MiB sem fim são lineares', () {
      const mib = 1024 * 1024;
      for (final src in [
        '"${'a' * mib}',
        '/*${'a' * mib}',
        r'\' * mib,
        'url(${'a' * mib}',
      ]) {
        final sw = Stopwatch()..start();
        tokenizeCss(src);
        expect(sw.elapsedMilliseconds, lessThan(2000));
      }
    });
  });
}
