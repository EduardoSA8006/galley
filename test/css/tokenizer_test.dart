// CssTokenizer: cada regra do CSS Syntax Level 3 §4 que o parser usa (spec
// do CSS §4). As expectativas vêm do algoritmo do padrão, não do código.
import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/css/tokenizer.dart';

List<CssToken> _all(String css) {
  final t = CssTokenizer(css);
  return [for (var k = t.next(); k.type != CssTokenType.eof; k = t.next()) k];
}

List<String> _show(String css) => [for (final t in _all(css)) '$t'];

void main() {
  group('tipos de token (§4.3.1)', () {
    test('pontuação e blocos', () {
      expect(_show(':;,[](){}'), [
        'colon',
        'semicolon',
        'comma',
        'leftBracket',
        'rightBracket',
        'leftParen',
        'rightParen',
        'leftBrace',
        'rightBrace',
      ]);
    });

    test('identificadores: -a, --x, não ASCII, _', () {
      expect(_show('a -a --x ção _b'), [
        'ident(a)',
        'whitespace',
        'ident(-a)',
        'whitespace',
        'ident(--x)',
        'whitespace',
        'ident(ção)',
        'whitespace',
        'ident(_b)',
      ]);
    });

    test('- sozinho é delim; -1 é número; --> é cdc', () {
      expect(_show('- -1 -->'), [
        'delim(-)',
        'whitespace',
        'number(-1 int)',
        'whitespace',
        'cdc',
      ]);
    });

    test('função, at-keyword e hash', () {
      expect(_show('rgb( @media @-x #id #1a #-b'), [
        'function(rgb)',
        'whitespace',
        'at(media)',
        'whitespace',
        'at(-x)',
        'whitespace',
        'hash-id(id)',
        'whitespace',
        'hash(1a)',
        'whitespace',
        'hash-id(-b)',
      ]);
    });

    test('@ e # sem nome são delim', () {
      expect(_show('@ # @1'), [
        'delim(@)',
        'whitespace',
        'delim(#)',
        'whitespace',
        'delim(@)',
        'number(1 int)',
      ]);
    });

    test('<!-- e --> viram cdo e cdc', () {
      expect(_show('<!-- a -->'), [
        'cdo',
        'whitespace',
        'ident(a)',
        'whitespace',
        'cdc',
      ]);
      expect(_show('<!-'), ['delim(<)', 'delim(!)', 'delim(-)']);
    });

    test('!important são dois tokens', () {
      expect(_show('!important'), ['delim(!)', 'ident(important)']);
    });
  });

  group('comentários (§4.3.2)', () {
    test('somem, inclusive entre tokens colados', () {
      expect(_show('a/* x */b'), ['ident(a)', 'ident(b)']);
      expect(_show('a/**/ /**/b'), ['ident(a)', 'whitespace', 'ident(b)']);
    });

    test('sem fim consome até o fim do texto', () {
      expect(_show('a /* nunca fecha'), ['ident(a)', 'whitespace']);
    });
  });

  group('strings (§4.3.5)', () {
    test('com } e ; dentro, aspas simples e duplas', () {
      expect(_show('"a;}" \'b"c\''), [
        'string(a;})',
        'whitespace',
        'string(b"c)',
      ]);
    });

    test('\\ + LF é continuação; \\ + CRLF também', () {
      expect(_show('"a\\\nb"'), ['string(ab)']);
      expect(_show('"a\\\r\nb"'), ['string(ab)']);
    });

    test('LF literal fecha como badString e não é consumido', () {
      expect(_show('"a\nb'), ['badString', 'whitespace', 'ident(b)']);
      expect(_all('"a\nb').first.value, 'a');
    });

    test('CR e FF também são quebra de linha', () {
      expect(_all('"a\rb').first.type, CssTokenType.badString);
      expect(_all('"a\fb').first.type, CssTokenType.badString);
    });

    test('fim do texto fecha a string; \\ no fim some', () {
      expect(_show('"abc'), ['string(abc)']);
      expect(_show('"abc\\'), ['string(abc)']);
    });
  });

  group('escapes (§4.3.7)', () {
    test('hex curto com espaço depois; 6 dígitos sem espaço', () {
      expect(_show(r'\41 x'), ['ident(Ax)']);
      expect(_show(r'\000041x'), ['ident(Ax)']);
      // O sétimo dígito já não é do escape.
      expect(_show(r'\0000411'), ['ident(A1)']);
    });

    test('CRLF depois do hex conta como um espaço só', () {
      expect(_show('\\41\r\nx'), ['ident(Ax)']);
    });

    test('0, surrogate e acima de U+10FFFF viram U+FFFD', () {
      expect(_all(r'\0').single.value, '\uFFFD');
      expect(_all(r'\D800').single.value, '\uFFFD');
      expect(_all(r'\110000').single.value, '\uFFFD');
      expect(_all(r'\10FFFF').single.value, String.fromCharCode(0x10FFFF));
    });

    test('outro caractere vira ele mesmo', () {
      expect(_show(r'a\.b'), ['ident(a.b)']);
      expect(_show(r'\\'), [r'ident(\)']);
    });

    test('\\ no fim do texto vira U+FFFD num ident', () {
      expect(_all('a\\').single.value, 'a\uFFFD');
      expect(_all('\\').single.value, '\uFFFD');
    });

    test('\\ seguido de LF não é escape: delim', () {
      expect(_show('\\\n'), [r'delim(\)', 'whitespace']);
    });

    test('escape em string e em hash', () {
      expect(_show(r'"\22"'), ['string(")']);
      expect(_show(r'#\31 a'), ['hash-id(1a)']);
      expect(_all(r'#\31 a').single.isIdHash, isTrue);
    });
  });

  group('url (§4.3.4, §4.3.6)', () {
    test('sem aspas, com espaço nas pontas, sem diferença de caixa', () {
      expect(_show('url(a.png) url(  b.png  ) URL(c)'), [
        'url(a.png)',
        'whitespace',
        'url(b.png)',
        'whitespace',
        'url(c)',
      ]);
    });

    test('com aspas vira function url e string', () {
      expect(_show('url("a.png")'), [
        'function(url)',
        'string(a.png)',
        'rightParen',
      ]);
      expect(_show("url(  'a')"), [
        'function(url)',
        'whitespace',
        'string(a)',
        'rightParen',
      ]);
    });

    test('espaço no meio, aspas, ( e não imprimível viram badUrl', () {
      expect(_show('url(a b) x'), ['badUrl', 'whitespace', 'ident(x)']);
      expect(_show('url(a"b) x'), ['badUrl', 'whitespace', 'ident(x)']);
      expect(_show('url(a(b) x'), ['badUrl', 'whitespace', 'ident(x)']);
      expect(_show('url(a\u0001b) x'), ['badUrl', 'whitespace', 'ident(x)']);
    });

    test('escape dentro de url e nos restos de badUrl', () {
      expect(_show(r'url(a\)b)'), ['url(a)b)']);
      expect(_show(r'url(a b\)c) x'), ['badUrl', 'whitespace', 'ident(x)']);
    });

    test('url sem fim termina no fim do texto', () {
      expect(_show('url(abc'), ['url(abc)']);
    });
  });

  group('números (§4.3.3, §4.3.12)', () {
    test('.5, 1e3, +3, -0 e expoente com sinal', () {
      final t = _all('.5 1e3 +3 -0 2E-2');
      expect(
        t.where((k) => k.type != CssTokenType.whitespace).map((k) => k.number),
        [0.5, 1000, 3, 0, 0.02],
      );
      expect(t[0].isInteger, isFalse);
      expect(t[2].isInteger, isFalse);
      expect(t[4].isInteger, isTrue);
      expect(t[4].value, '+3');
      expect(t[6].number.isNegative, isTrue, reason: '-0 é -0.0');
    });

    test('1e sem dígito é dimensão de unidade e', () {
      expect(_show('1e'), ['dimension(1 e)']);
    });

    test('dimensão com unidade em minúsculas ASCII e percentagem', () {
      expect(_show('10PX 50% 2n-1'), [
        'dimension(10 px)',
        'whitespace',
        'percentage(50)',
        'whitespace',
        'dimension(2 n-1)',
      ]);
    });

    test('+ e . sem dígito são delim', () {
      expect(_show('+ .a'), ['delim(+)', 'whitespace', 'delim(.)', 'ident(a)']);
    });

    test('literal de 64 caracteres vale; de 65 é NaN', () {
      final ok = _all('1' * maxNumericLiteralLength).single;
      expect(ok.number.isFinite, isTrue);
      final long = _all('1' * (maxNumericLiteralLength + 1)).single;
      expect(long.type, CssTokenType.number);
      expect(long.number.isNaN, isTrue);
    });

    test('literal de 100 dígitos é NaN, sem exceção', () {
      expect(_all('9' * 100).single.number.isNaN, isTrue);
    });
  });

  group('pré-processamento (§3.3)', () {
    test('CR, CRLF e FF contam como LF (espaço)', () {
      expect(_show('a\rb\r\nc\fd'), [
        'ident(a)',
        'whitespace',
        'ident(b)',
        'whitespace',
        'ident(c)',
        'whitespace',
        'ident(d)',
      ]);
    });

    test('U+0000 e surrogate solto viram U+FFFD no valor', () {
      expect(_all('a\u0000b').single.value, 'a\uFFFDb');
      expect(_all('a\uD800b').single.value, 'a\uFFFDb');
      expect(_all('"\u0000"').single.value, '\uFFFD');
    });

    test('par de surrogates fica inteiro (não ASCII de identificador)', () {
      expect(_all('a😀b').single.value, 'a😀b');
    });
  });

  group('amostras', () {
    test('cssSample: 64 unidades sem cortar um par de surrogates', () {
      final t = _all('${'a' * 63}😀');
      expect(cssSample(t), 'a' * 63);
      expect(truncateSample('b' * 70), 'b' * maxSampleLength);
    });
  });

  group('hostis (spec do CSS §14.3): linear, sem exceção', () {
    void linear(String name, String css, void Function(List<CssToken>) check) {
      test(name, () {
        final sw = Stopwatch()..start();
        final tokens = _all(css);
        sw.stop();
        check(tokens);
        expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
      });
    }

    const mib = 1024 * 1024;
    linear('comentário sem fim de 1 MiB', '/*${'a' * mib}', (t) {
      expect(t, isEmpty);
    });
    linear('string sem fim de 1 MiB', '"${'a' * mib}', (t) {
      expect(t.single.value.length, mib);
    });
    linear('url( sem fim de 1 MiB', 'url(${'a' * mib}', (t) {
      expect(t.single.type, CssTokenType.url);
    });
    linear(r'\ repetido 500 000 vezes', r'\\' * 500000, (t) {
      expect(t.single.value.length, 500000);
    });
    linear(r'\FFFFFFFF repetido 100 000 vezes', r'\FFFFFFFF' * 100000, (t) {
      expect(t.single.type, CssTokenType.ident);
    });
    linear('literal numérico de 1 MiB', '1' * mib, (t) {
      expect(t.single.number.isNaN, isTrue);
    });
    linear('{, ( e [ repetidos 500 000 vezes', '{([' * 500000, (t) {
      expect(t, hasLength(1500000));
    });
  });
}
