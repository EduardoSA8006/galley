import '../epub_builder.dart';
import '../text.dart';

/// Semente estável por slug (FNV-1a), para o gerador ser reprodutível.
int seedFor(String slug) {
  var h = 0x811C9DC5;
  for (final c in slug.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

Prose proseFor(String slug, {String lang = 'pt'}) =>
    Prose(lang: lang, seed: seedFor(slug));

/// Livro comum: N capítulos com `<h1>` e prosa, spine e TOC coerentes.
EpubBuilder standardBook(
  String slug, {
  String title = 'Livro de teste',
  int chapters = 3,
  String lang = 'pt-BR',
  int wordsPerChapter = 300,
}) {
  final b = EpubBuilder(slug: slug, title: title, language: lang);
  final prose = proseFor(slug, lang: lang.startsWith('en') ? 'en' : 'pt');
  for (var i = 1; i <= chapters; i++) {
    final r = b.addChapter(
      'cap${i.toString().padLeft(2, '0')}.xhtml',
      xhtml(
        title: 'Capítulo $i',
        lang: lang,
        body:
            '<h1 id="c$i">Capítulo $i</h1>\n${prose.paragraphsForWords(wordsPerChapter)}',
      ),
    );
    b.chapterInSpineAndToc(r, 'Capítulo $i');
  }
  return b;
}

/// Livro de um capítulo com corpo arbitrário, para casos de conteúdo.
EpubBuilder singleChapterBook(
  String slug,
  String body, {
  String title = 'Livro de teste',
  String lang = 'pt-BR',
  String? css,
  String? dir,
  String? head,
}) {
  final b = EpubBuilder(slug: slug, title: title, language: lang);
  final r = b.addChapter(
    'cap01.xhtml',
    xhtml(title: title, lang: lang, body: body, css: css, dir: dir, head: head),
  );
  b.chapterInSpineAndToc(r, title);
  return b;
}
