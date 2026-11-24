import 'dart:convert';
import 'dart:io';

import 'package:epub_pro/epub_pro.dart' as lib;

import 'adapter.dart';

/// Adaptador do `epub_pro`: `EpubReader.readBook` sobre os bytes do arquivo
/// (a API idiomática lê o livro inteiro: HTML, CSS, imagens e fontes).
///
/// A lógica é a mesma dos adaptadores do `epub_plus` e do `epubx`: as três
/// bibliotecas são da mesma família, mas os tipos são distintos e não
/// compartilham interface.
final class EpubProAdapter implements ParserAdapter {
  lib.EpubBook? _book;

  @override
  String get name => 'epub_pro';

  lib.EpubBook get _open => _book ?? (throw StateError('livro não aberto'));

  @override
  Future<void> open(String path) async =>
      _book = await lib.EpubReader.readBook(await File(path).readAsBytes());

  @override
  int get spineLength => _open.schema?.package?.spine?.items.length ?? 0;

  Map<String, lib.EpubTextContentFile> get _html =>
      _open.content?.html ?? const {};

  @override
  Future<int> readAllSpine() async {
    final package = _open.schema?.package;
    final manifest = package?.manifest?.items ?? const <lib.EpubManifestItem>[];
    var total = 0;
    for (final ref in package?.spine?.items ?? const <lib.EpubSpineItemRef>[]) {
      final item = manifest.firstWhere((m) => m.id == ref.idRef);
      final key = matchResourceKey(_html.keys, item.href ?? '');
      final text = key == null ? null : _html[key]?.content;
      if (text == null) throw StateError('sem conteúdo para ${item.href}');
      total += utf8.encode(text).length;
    }
    return total;
  }

  @override
  Future<int> readOne(String hrefOrPath) async {
    final content = _open.content;
    final key = matchResourceKey(content?.allFiles.keys ?? [], hrefOrPath);
    final file = key == null ? null : content!.allFiles[key];
    return switch (file) {
      lib.EpubTextContentFile(:final content?) => utf8.encode(content).length,
      lib.EpubByteContentFile(:final content?) => content.length,
      _ => throw StateError('recurso não encontrado: $hrefOrPath'),
    };
  }

  @override
  Future<void> close() async => _book = null;
}
