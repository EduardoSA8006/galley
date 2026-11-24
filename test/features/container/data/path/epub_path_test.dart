import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/features/container/data/path/epub_path.dart';

void main() {
  group('resolveHref', () {
    test('percent-decoding e fragmento', () {
      expect(
        resolveHref('OEBPS/content.opf', 'Text/Cap%C3%ADtulo%201.xhtml#p2'),
        (path: 'OEBPS/Text/Capítulo 1.xhtml', fragment: 'p2'),
      );
    });

    test('resolve .. relativo ao diretório', () {
      expect(resolveHref('OEBPS/Text/c1.xhtml', '../Images/a.png'), (
        path: 'OEBPS/Images/a.png',
        fragment: null,
      ));
    });

    test('href vazio com fragmento aponta para o mesmo arquivo', () {
      expect(resolveHref('OEBPS/Text/c1.xhtml', '#n1'), (
        path: 'OEBPS/Text/c1.xhtml',
        fragment: 'n1',
      ));
    });

    test('escapar da raiz devolve null', () {
      expect(resolveHref('content.opf', '../../x'), isNull);
      expect(resolveHref('a/b.xhtml', '../../x'), isNull);
    });

    test('esquemas devolvem null', () {
      expect(resolveHref('content.opf', 'https://e.com/a'), isNull);
      expect(resolveHref('content.opf', 'mailto:a@b.c'), isNull);
    });

    test('remove query', () {
      expect(resolveHref('OEBPS/c.xhtml', 'a.png?v=1#x'), (
        path: 'OEBPS/a.png',
        fragment: 'x',
      ));
    });

    test('normaliza ponto e barras duplicadas', () {
      expect(resolveHref('OEBPS/c.xhtml', './a//b/./c.png'), (
        path: 'OEBPS/a/b/c.png',
        fragment: null,
      ));
    });

    test('barra inicial é relativa à raiz do zip', () {
      expect(resolveHref('OEBPS/Text/c.xhtml', '/OEBPS/a.png'), (
        path: 'OEBPS/a.png',
        fragment: null,
      ));
    });

    test('percent malformado mantém o texto cru', () {
      expect(resolveHref('c.xhtml', 'a%ZZ.png'), (
        path: 'a%ZZ.png',
        fragment: null,
      ));
      expect(resolveHref('c.xhtml', '50%'), (path: '50%', fragment: null));
      expect(resolveHref('c.xhtml', 'x.xhtml#a%'), (
        path: 'x.xhtml',
        fragment: 'a%',
      ));
    });

    test('percent que gera UTF-8 inválido mantém o texto cru', () {
      expect(resolveHref('c.xhtml', 'a%FF.png'), (
        path: 'a%FF.png',
        fragment: null,
      ));
    });

    test('href vazio sem fragmento aponta para o mesmo arquivo', () {
      expect(resolveHref('OEBPS/c.xhtml', ''), (
        path: 'OEBPS/c.xhtml',
        fragment: null,
      ));
    });

    test('fragmento é percent-decodificado', () {
      expect(resolveHref('c.xhtml', '#a%20b'), (
        path: 'c.xhtml',
        fragment: 'a b',
      ));
    });
  });
}
