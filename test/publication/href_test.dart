// normalizeHref, splitFragment e decodePath (spec da Publicação §5.1, §5.2).
import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/publication/href.dart';

void main() {
  group('normalizeHref', () {
    final table = <(String, String, String?)>[
      ('OEBPS', 'Text/cap01.xhtml', 'OEBPS/Text/cap01.xhtml'),
      ('', 'cap01.xhtml', 'cap01.xhtml'),
      ('OEBPS/content', '../Text/cap01.xhtml', 'OEBPS/Text/cap01.xhtml'),
      ('OEBPS', '../../fora.xhtml', null),
      ('', '../fora.xhtml', null),
      ('OEBPS', r'Text\cap01.xhtml', 'OEBPS/Text/cap01.xhtml'),
      ('OEBPS/Text', '/Images/capa.png', 'Images/capa.png'),
      ('OEBPS', 'http://example.com/a.xhtml', null),
      ('OEBPS', 'mailto:a@b.c', null),
      ('OEBPS', 'data:image/png;base64,AAAA', null),
      ('OEBPS', r'C:\livro\a.xhtml', null),
      ('OEBPS', 'Text/cap01.xhtml?v=2#sec', 'OEBPS/Text/cap01.xhtml'),
      ('OEBPS', 'Text/cap01.xhtml#a?b', 'OEBPS/Text/cap01.xhtml'),
      ('OEBPS', 'Text//./cap01.xhtml', 'OEBPS/Text/cap01.xhtml'),
      ('OEBPS', 'Text/../cap01.xhtml', 'OEBPS/cap01.xhtml'),
      ('OEBPS', '', null),
      ('OEBPS', '#frag', null),
      ('OEBPS', '?q', null),
      ('OEBPS', 'Text/..', 'OEBPS'),
      ('', 'a/..', null),
      ('OEBPS', '  Text/cap01.xhtml  ', 'OEBPS/Text/cap01.xhtml'),
      ('OEBPS', 'Text/cap%20um.xhtml', 'OEBPS/Text/cap%20um.xhtml'),
      ('', 'a\u0000b', null),
      ('', '.. /x', null),
      ('', '.../x', null),
      ('', 'a./b', 'a./b'),
      ('', 'a/../C:/Windows/win.ini', null),
    ];
    for (final (base, raw, expected) in table) {
      test('"$raw" em "$base" → $expected', () {
        expect(normalizeHref(base, raw), expected);
      });
    }
  });

  group('splitFragment', () {
    test('separa no primeiro #', () {
      expect(splitFragment('a.xhtml#x#y'), ('a.xhtml', 'x#y'));
      expect(splitFragment('a.xhtml'), ('a.xhtml', null));
      expect(splitFragment('a.xhtml#'), ('a.xhtml', null));
      expect(splitFragment('#só'), ('', 'só'));
    });

    test('decodifica o fragmento de forma tolerante', () {
      expect(splitFragment('a.xhtml#se%C3%A7%C3%A3o'), ('a.xhtml', 'seção'));
      expect(splitFragment('a.xhtml#50%'), ('a.xhtml', '50%'));
      expect(splitFragment('a.xhtml#%E9'), ('a.xhtml', '%E9'));
    });

    test('decodifica IRI: literal não ASCII misturado com %xx', () {
      expect(splitFragment('a#seção%20um'), ('a', 'seção um'));
    });
  });

  group('decodePath', () {
    final table = <(String, String?)>[
      ('OEBPS/Text/cap%20um.xhtml', 'OEBPS/Text/cap um.xhtml'),
      ('OEBPS/Text/cap%C3%ADtulo%201.xhtml', 'OEBPS/Text/capítulo 1.xhtml'),
      ('OEBPS/%2e%2e/a.xhtml', 'a.xhtml'),
      ('%2e%2e/a.xhtml', null),
      ('OEBPS/%2E%2E/%2e%2e/a.xhtml', null),
      ('OEBPS/Text%5Ccap01.xhtml', 'OEBPS/Text/cap01.xhtml'),
      ('OEBPS/a%2Fb.xhtml', 'OEBPS/a%2Fb.xhtml'),
      ('OEBPS/caf%E9.xhtml', 'OEBPS/caf%E9.xhtml'),
      ('OEBPS/100%.xhtml', 'OEBPS/100%.xhtml'),
      ('OEBPS/%2e', 'OEBPS'),
      ('%2e', null),
      ('OEBPS/sem-escape.xhtml', 'OEBPS/sem-escape.xhtml'),
      // Colapso sempre reaplicado, mesmo sem `%xx` no texto.
      ('../x', null),
      (r'a\..\x', 'x'),
      // IRI: literal não ASCII (não precisa de %xx para decodificar).
      ('Text/capítulo%201.xhtml', 'Text/capítulo 1.xhtml'),
      // Overlong (codificação inválida de "..") continua cru.
      ('OEBPS/%C0%AE%C0%AE', 'OEBPS/%C0%AE%C0%AE'),
      // Segmento que decodifica para exatamente "." ou ".." fecha a raiz.
      ('.%2e', null),
      ('%2e.', null),
      ('%5c..%5c', null),
      // Só uma passada de decodificação: %2525 vira %25, não recursa.
      ('%252e%252e', '%2e%2e'),
      // Letra de drive revelada depois do decode/colapso.
      ('C%3a%5cx', null),
      (r'%5c%5c%3f%5cC%3a%5cx', null),
    ];
    for (final (input, expected) in table) {
      test('$input → $expected', () {
        expect(decodePath(input), expected);
      });
    }

    test('NUL nunca escapa cru do %xx decodificado', () {
      for (final input in ['..%00/x', 'a/..%00', '%00']) {
        final result = decodePath(input);
        expect(
          result == null || !result.contains('\u0000'),
          isTrue,
          reason: 'decodePath($input) = $result contém NUL',
        );
      }
    });

    test('normalizeHref + decodePath não produz ".." nem NUL via %00', () {
      final normalized = normalizeHref('', 'a/../..%00');
      expect(normalized, isNotNull);
      final result = decodePath(normalized!);
      if (result != null) {
        expect(result.split('/'), isNot(contains('..')));
        expect(result.contains('\u0000'), isFalse);
      }
    });
  });

  group('custo linear em entrada hostil', () {
    test('normalizeHref com 64 KiB de "../" termina em menos de 100 ms', () {
      final raw = '../' * (64 * 1024 ~/ 3);
      final stopwatch = Stopwatch()..start();
      final result = normalizeHref('OEBPS/a/b/c', raw);
      stopwatch.stop();
      expect(result, isNull);
      expect(stopwatch.elapsedMilliseconds, lessThan(100));
    });

    test('decodePath com 64 KiB de "%" termina em menos de 100 ms', () {
      final noisy = '%' * (64 * 1024);
      final raw = 'OEBPS/$noisy';
      final stopwatch = Stopwatch()..start();
      final result = decodePath(raw);
      stopwatch.stop();
      expect(result, raw);
      expect(stopwatch.elapsedMilliseconds, lessThan(100));
    });

    test('decodePath com prefixo válido longo e "%" solto no fim '
        'termina em menos de 100 ms', () {
      final raw = '%41' * 20000 + '%';
      final stopwatch = Stopwatch()..start();
      final result = decodePath(raw);
      stopwatch.stop();
      expect(result, 'A' * 20000 + '%');
      expect(stopwatch.elapsedMilliseconds, lessThan(100));
    });
  });

  group('auxiliares', () {
    test('hasScheme e isRemoteHref', () {
      expect(hasScheme('https://x/a.css'), isTrue);
      expect(hasScheme('Text/a.xhtml'), isFalse);
      expect(hasScheme('a:b'), isTrue);
      expect(isRemoteHref(' HTTP://x/a.mp3'), isTrue);
      expect(isRemoteHref('https://x/a.mp3'), isTrue);
      expect(isRemoteHref('ftp://x/a.mp3'), isFalse);
    });

    test('dirnameOf e basenameWithoutExtension', () {
      expect(dirnameOf('OEBPS/Text/a.xhtml'), 'OEBPS/Text');
      expect(dirnameOf('content.opf'), '');
      expect(basenameWithoutExtension('OEBPS/Text/cap02.xhtml'), 'cap02');
      expect(basenameWithoutExtension('a.b.html.xhtml'), 'a.b.html');
      expect(basenameWithoutExtension('OEBPS/.oculto'), '.oculto');
      expect(basenameWithoutExtension('LEIAME'), 'LEIAME');
    });
  });
}
