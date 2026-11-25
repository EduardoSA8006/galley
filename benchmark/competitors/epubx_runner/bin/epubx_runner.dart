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

/// Adaptador do `epubx`.
///
/// `open` usa `EpubReader.openBook` (leitura preguiçosa: `EpubBookRef`) e os
/// recursos saem de `EpubContentFileRef.readContentAsBytes`; `openEager` usa
/// `EpubReader.readBook`. A lógica é a mesma dos adaptadores do `epub_plus` e
/// do `epub_pro` (em `benchmark/lib/src/competitors`); aqui os campos têm
/// nomes em PascalCase.
final class EpubxAdapter implements ParserAdapter {
  lib.EpubBookRef? _ref;
  lib.EpubBook? _eager;

  @override
  String get name => 'epubx';

  lib.EpubBookRef get _open => _ref ?? (throw StateError('livro não aberto'));

  @override
  Future<void> open(String path) async =>
      _ref = await lib.EpubReader.openBook(await File(path).readAsBytes());

  @override
  Future<void> openEager(String path) async =>
      _eager = await lib.EpubReader.readBook(await File(path).readAsBytes());

  @override
  int get spineLength =>
      (_ref?.Schema ?? _eager?.Schema)?.Package?.Spine?.Items?.length ?? 0;

  @override
  Future<int> readAllSpine() async {
    final package = _open.Schema?.Package;
    final hrefById = {
      for (final m
          in package?.Manifest?.Items ?? const <lib.EpubManifestItem>[])
        m.Id: m.Href,
    };
    final html = _open.Content?.Html ?? {};
    var total = 0;
    for (final ref in package?.Spine?.Items ?? const <lib.EpubSpineItemRef>[]) {
      final href = hrefById[ref.IdRef] ?? '';
      final file = html[href] ?? html[matchResourceKey(html.keys, href)];
      if (file == null) throw StateError('sem referência para $href');
      total += (await file.readContentAsBytes()).length;
    }
    return total;
  }

  @override
  Future<int> readOne(String hrefOrPath) async {
    final files = _open.Content?.AllFiles ?? {};
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
