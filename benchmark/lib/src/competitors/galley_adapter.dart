import 'package:galley/galley.dart';

import 'adapter.dart';

/// Adaptador do Galley: `EpubBook.open` (contêiner e pacote; os recursos são
/// lidos sob demanda com `EpubBook.resource`).
final class GalleyAdapter implements ParserAdapter {
  EpubBook? _book;

  @override
  String get name => 'galley';

  EpubBook get _open => _book ?? (throw StateError('livro não aberto'));

  @override
  Future<void> open(String path) async => _book = await EpubBook.open(path);

  @override
  Future<void> openEager(String path) async =>
      throw UnsupportedError('o Galley não tem leitura integral (eager)');

  @override
  int get spineLength => _open.spine.items.length;

  @override
  Future<int> readAllSpine() async {
    var total = 0;
    for (final item in _open.spine.items) {
      total += (await _open.resource(item.item.path)).length;
    }
    return total;
  }

  @override
  Future<int> readOne(String hrefOrPath) async =>
      (await _open.resource(hrefOrPath)).length;

  @override
  Future<void> close() async {
    final book = _book;
    _book = null;
    await book?.close();
  }
}
