import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:epubx/epubx.dart' as lib;

// Os dois arquivos abaixo não têm dependências, então não puxam o `image ^4`
// para este pacote. O import é relativo (e este código fica em `bin/`, não em
// `lib/`) porque uma biblioteca carregada por `package:` não sai do seu
// pacote por caminho relativo.
// ignore: avoid_relative_lib_imports
import '../../../lib/src/competitors/adapter.dart';
// ignore: avoid_relative_lib_imports
import '../../../lib/src/competitors/measure.dart';

/// Adaptador do `epubx`: `EpubReader.readBook` sobre os bytes do arquivo (a
/// API idiomática lê o livro inteiro: HTML, CSS, imagens e fontes).
///
/// A lógica é a mesma dos adaptadores do `epub_plus` e do `epub_pro` (em
/// `benchmark/lib/src/competitors`); aqui os campos têm nomes em PascalCase.
final class EpubxAdapter implements ParserAdapter {
  lib.EpubBook? _book;

  @override
  String get name => 'epubx';

  lib.EpubBook get _open => _book ?? (throw StateError('livro não aberto'));

  @override
  Future<void> open(String path) async =>
      _book = await lib.EpubReader.readBook(await File(path).readAsBytes());

  @override
  int get spineLength => _open.Schema?.Package?.Spine?.Items?.length ?? 0;

  @override
  Future<int> readAllSpine() async {
    final package = _open.Schema?.Package;
    final manifest = package?.Manifest?.Items ?? const <lib.EpubManifestItem>[];
    final html =
        _open.Content?.Html ?? const <String, lib.EpubTextContentFile>{};
    var total = 0;
    for (final ref in package?.Spine?.Items ?? const <lib.EpubSpineItemRef>[]) {
      final item = manifest.firstWhere((m) => m.Id == ref.IdRef);
      final key = matchResourceKey(html.keys, item.Href ?? '');
      final text = key == null ? null : html[key]?.Content;
      if (text == null) throw StateError('sem conteúdo para ${item.Href}');
      total += utf8.encode(text).length;
    }
    return total;
  }

  @override
  Future<int> readOne(String hrefOrPath) async {
    final files =
        _open.Content?.AllFiles ?? const <String, lib.EpubContentFile>{};
    final key = matchResourceKey(files.keys, hrefOrPath);
    final file = key == null ? null : files[key];
    return switch (file) {
      lib.EpubTextContentFile(:final Content?) => utf8.encode(Content).length,
      lib.EpubByteContentFile(:final Content?) => Content.length,
      _ => throw StateError('recurso não encontrado: $hrefOrPath'),
    };
  }

  @override
  Future<void> close() async => _book = null;
}

/// Mede o `epubx` com o mesmo contrato do `bench_runner --adapter`:
/// `epubx_runner --measure <tipo> [--resource <caminho>] <livro>`, com tipo
/// `open`, `read-all` ou `read-one`; imprime `ns=`, `rss=` e `checksum=` (ver
/// `runAdapterMeasure`). Argumentos inválidos saem com 64; falha do parser,
/// com 70.
Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('measure', help: 'open, read-all ou read-one.')
    ..addOption('resource', help: 'Caminho do recurso (read-one).');
  final ArgResults parsed;
  try {
    parsed = parser.parse(args);
    if (parsed.option('measure') == null || parsed.rest.length != 1) {
      throw const FormatException('use --measure <tipo> <livro.epub>');
    }
  } on FormatException catch (e) {
    stderr.writeln('Argumentos inválidos: ${e.message}\n${parser.usage}');
    exit(64);
  }
  final code = await runAdapterMeasure(
    EpubxAdapter(),
    parsed.option('measure')!,
    parsed.rest.single,
    resource: parsed.option('resource'),
    out: stdout,
    err: stderr,
  );
  await stdout.flush();
  await stderr.flush();
  exit(code);
}
