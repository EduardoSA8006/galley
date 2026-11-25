import 'package:galley_benchmark/src/corpus/pg_wide.dart';
import 'package:test/test.dart';

void main() {
  test('parseCsv: aspas, vírgulas, aspas duplas e quebras de linha', () {
    final rows = parseCsv('a,b,c\r\n1,"x, y","diz ""oi""\nlinha 2"\n2,,z\n');
    expect(rows, [
      ['a', 'b', 'c'],
      ['1', 'x, y', 'diz "oi"\nlinha 2'],
      ['2', '', 'z'],
    ]);
  });

  test('catalogTextBooks: só Text, ordenado, sem duplicatas', () {
    const csv =
        'Text#,Type,Issued,Title,Language,Authors,Subjects,LoCC,Bookshelves\n'
        '30,Text,2000-01-01,"B, o livro",en,"X, Y",,,\n'
        '10,Text,2000-01-01,A,en,,,,\n'
        '20,Sound,2000-01-01,Som,en,,,,\n'
        '10,Text,2000-01-01,A,en,,,,\n';
    expect(catalogTextBooks(csv), [10, 30]);
  });

  test('pickBookNumbers é determinístico para a mesma semente', () {
    final all = List.generate(1000, (i) => i + 1);
    final a = pickBookNumbers(all, count: 50, seed: 2026);
    final b = pickBookNumbers(all.reversed.toList(), count: 50, seed: 2026);
    expect(a, hasLength(50));
    expect(a.toSet(), hasLength(50));
    expect(b, a);
    expect(pickBookNumbers(all, count: 50, seed: 7), isNot(a));
  });

  test('pgEpubUrl aponta para o espelho oficial', () {
    expect(
      pgEpubUrl(84).toString(),
      'https://gutenberg.pglaf.org/cache/epub/84/pg84.epub',
    );
  });
}
