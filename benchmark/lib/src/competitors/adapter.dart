/// Adaptador de um parser de EPUB para a comparação (`compare`).
///
/// Este arquivo e `measure.dart` não dependem de nenhum parser: o satélite
/// `benchmark/competitors/epubx_runner` os importa por caminho relativo (o
/// `epubx` exige `image ^3`, incompatível com `image ^4` do `epub_plus` e do
/// `epub_pro`, então vive em outro pacote e outro executável).
abstract interface class ParserAdapter {
  /// Nome do adaptador (`galley`, `epubx`, `epub_plus`, `epub_pro`).
  String get name;

  /// Abre o EPUB de [path] pelo caminho preguiçoso idiomático do pacote: lê
  /// o arquivo, decodifica o diretório do zip e faz o parse do OPF e da
  /// navegação, sem ler o conteúdo dos recursos (`EpubBook.open` no Galley,
  /// `EpubReader.openBook` nos concorrentes). Os recursos vêm depois, um a um.
  Future<void> open(String path);

  /// Abre [path] lendo o livro inteiro para a memória (`EpubReader.readBook`
  /// nos concorrentes). O Galley não tem equivalente: lança
  /// [UnsupportedError] e não é medido nessa métrica.
  Future<void> openEager(String path);

  /// Quantidade de itens do spine do livro aberto.
  int get spineLength;

  /// Soma dos bytes dos documentos do spine, em ordem, lendo cada um pela
  /// referência do livro aberto por [open] (`readContentAsBytes` nos
  /// concorrentes, `EpubBook.resource` no Galley): bytes crus, sem decodificar
  /// nem recodificar texto, então a soma é a mesma nos quatro.
  Future<int> readAllSpine();

  /// Tamanho em bytes do recurso em [hrefOrPath].
  ///
  /// Aceita o caminho completo no arquivo (`OEBPS/text/ch1.xhtml`); os
  /// concorrentes também aceitam o href relativo ao OPF. Lê só esse recurso
  /// pelo livro aberto por [open]. Lança se o recurso não existe.
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
