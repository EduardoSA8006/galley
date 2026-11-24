import 'dart:io';

import 'package:epub_pro/epub_pro.dart' as lib;

import 'adapter.dart';

/// Adaptador do `epub_pro`.
///
/// `open` usa `EpubReader.openBook` (leitura preguiçosa: `EpubBookRef`) e os
/// recursos saem de `EpubContentFileRef.readContentAsBytes`; `openEager` usa
/// `EpubReader.readBook`.
///
/// A lógica é a mesma dos adaptadores do `epub_plus` e do `epubx`: as três
/// bibliotecas são da mesma família, mas os tipos são distintos e não
/// compartilham interface.
final class EpubProAdapter implements ParserAdapter {
  lib.EpubBookRef? _ref;
  lib.EpubBook? _eager;

  @override
  String get name => 'epub_pro';

  lib.EpubBookRef get _open => _ref ?? (throw StateError('livro não aberto'));

  @override
  Future<void> open(String path) async =>
      _ref = await lib.EpubReader.openBook(await File(path).readAsBytes());

  @override
  Future<void> openEager(String path) async =>
      _eager = await lib.EpubReader.readBook(await File(path).readAsBytes());

  @override
  int get spineLength =>
      (_ref?.schema ?? _eager?.schema)?.package?.spine?.items.length ?? 0;

  @override
  Future<int> readAllSpine() async {
    final package = _open.schema?.package;
    final hrefById = {
      for (final m
          in package?.manifest?.items ?? const <lib.EpubManifestItem>[])
        m.id: m.href,
    };
    final html = _open.content?.html ?? const {};
    var total = 0;
    for (final ref in package?.spine?.items ?? const <lib.EpubSpineItemRef>[]) {
      final href = hrefById[ref.idRef] ?? '';
      final file = html[href] ?? html[matchResourceKey(html.keys, href)];
      if (file == null) throw StateError('sem referência para $href');
      total += (await file.readContentAsBytes()).length;
    }
    return total;
  }

  @override
  Future<int> readOne(String hrefOrPath) async {
    final files = _open.content?.allFiles ?? const {};
    final key = matchResourceKey(files.keys, hrefOrPath);
    final file = key == null ? null : files[key];
    if (file == null) throw StateError('recurso não encontrado: $hrefOrPath');
    return (await file.readContentAsBytes()).length;
  }

  @override
  Future<void> close() async {
    _ref = null;
    _eager = null;
  }
}
