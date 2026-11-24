/// Adaptador de um parser de EPUB para a comparação (`compare`).
///
/// Este arquivo e `measure.dart` não dependem de nenhum parser: o satélite
/// `benchmark/competitors/epubx_runner` os importa por caminho relativo (o
/// `epubx` exige `image ^3`, incompatível com `image ^4` do `epub_plus` e do
/// `epub_pro`, então vive em outro pacote e outro executável).
abstract interface class ParserAdapter {
  /// Nome do adaptador (`galley`, `epubx`, `epub_plus`, `epub_pro`).
  String get name;

  /// Abre o EPUB de [path] com a API idiomática do pacote.
  ///
  /// Os parsers concorrentes leem o livro inteiro aqui (`readBook`); o Galley
  /// só abre o contêiner e o pacote (leitura preguiçosa).
  Future<void> open(String path);

  /// Quantidade de itens do spine do livro aberto.
  int get spineLength;

  /// Soma dos bytes dos documentos do spine, em ordem.
  ///
  /// Os concorrentes só expõem o texto já decodificado; os bytes são os do
  /// UTF-8 desse texto (iguais aos do arquivo quando o parser não normaliza).
  Future<int> readAllSpine();

  /// Tamanho em bytes do recurso em [hrefOrPath].
  ///
  /// Aceita o caminho completo no arquivo (`OEBPS/text/ch1.xhtml`) ou o href
  /// relativo ao OPF (`text/ch1.xhtml`). Lança se o recurso não existe.
  Future<int> readOne(String hrefOrPath);

  /// Libera os recursos do livro aberto.
  Future<void> close();
}

/// Procura em [keys] a chave que corresponde a [hrefOrPath]: igual a ela ou
/// terminada por ela depois de uma `/` (a chave é um href relativo ao OPF e
/// [hrefOrPath] pode ser o caminho completo no arquivo).
///
/// Devolve `null` se nenhuma corresponde.
String? matchResourceKey(Iterable<String> keys, String hrefOrPath) {
  for (final key in keys) {
    if (key == hrefOrPath || hrefOrPath.endsWith('/$key')) return key;
  }
  return null;
}
