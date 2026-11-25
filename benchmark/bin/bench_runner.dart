import 'dart:io';

import 'package:args/args.dart';
import 'package:galley_benchmark/src/bench.dart';
import 'package:galley_benchmark/src/catalog.dart';
import 'package:galley_benchmark/src/competitors/css_adapter.dart';
import 'package:galley_benchmark/src/competitors/document_adapter.dart';
import 'package:galley_benchmark/src/competitors/epub_plus_adapter.dart';
import 'package:galley_benchmark/src/competitors/epub_pro_adapter.dart';
import 'package:galley_benchmark/src/competitors/galley_adapter.dart';
import 'package:galley_benchmark/src/competitors/measure.dart';
import 'package:galley_benchmark/src/runner.dart';

/// Executa um benchmark: `--bench <id> --iterations <n>`.
///
/// Com `--measure-open <caminho>`, abre o EPUB, lê o spine e imprime `ns=`,
/// `rss=` (`VmHWM`, ver `peakRssBytes`) e `checksum=` (ver `measureOpen`).
///
/// Com `--adapter` (`galley`, `epub_plus` ou `epub_pro`), `--measure`
/// (`open`, `open-eager`, `read-all` ou `read-one`), `--resource` (só no
/// `read-one`) e o caminho do livro, mede o parser escolhido (ver
/// `runAdapterMeasure`) e imprime `ns=`, `rss=` e `checksum=`. O `epubx` tem
/// executável próprio (`benchmark/competitors/epubx_runner`).
///
/// Com `--doc-adapter` (`galley-document` ou `xml-dom`), `--measure parse` e o
/// caminho de um `.epub` (documentos do spine) ou de um `.xhtml`, mede só o
/// parse dos documentos (ver `runDocumentMeasure`); é a comparação
/// informativa do parse do Galley contra o DOM do `package:xml`.
///
/// Com `--css-adapter` (`galley-css` ou `csslib`), `--measure parse` e o
/// caminho de um `.epub` (todas as folhas `text/css` do manifest) ou de um
/// `.css`, mede só a leitura das folhas (ver `runCssMeasure`); é a
/// comparação informativa do Galley contra o `package:csslib`.
///
/// Imprime a linha `checksum=<int>`; com `--timing`, imprime antes a linha
/// `ns=<int>` (tempo de relógio das iterações 2 a n, sem `setUp`). Com `--list`, imprime os
/// ids do catálogo, um por linha, e sai com 0. Id desconhecido ou argumentos
/// inválidos saem com código 64; exceção em `setUp`/`run` sai com 70 (ver
/// `runBench`).
Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addFlag('list', negatable: false, help: 'Lista os ids do catálogo.')
    ..addOption('bench', help: 'Id do benchmark.')
    ..addOption(
      'measure-open',
      help:
          'Abre o EPUB do caminho, lê o spine e imprime ns=, rss= e checksum=.',
    )
    ..addOption(
      'adapter',
      allowed: ['galley', 'epub_plus', 'epub_pro'],
      help: 'Parser a medir (com --measure).',
    )
    ..addOption(
      'doc-adapter',
      allowed: ['galley-document', 'xml-dom'],
      help: 'Parser de documento a medir (com --measure parse).',
    )
    ..addOption(
      'css-adapter',
      allowed: ['galley-css', 'csslib'],
      help: 'Leitor de CSS a medir (com --measure parse).',
    )
    ..addOption(
      'measure',
      allowed: [...measureKinds, 'parse'],
      help: 'Medida do adaptador.',
    )
    ..addOption('resource', help: 'Caminho do recurso (--measure read-one).')
    ..addFlag(
      'timing',
      negatable: false,
      help: 'Imprime ns=<tempo das iterações 2..n> (exige --iterations ≥ 2).',
    )
    ..addOption('iterations', defaultsTo: '1', help: 'Número de ciclos.');
  final ArgResults parsed;
  final int iterations;
  try {
    parsed = parser.parse(args);
    iterations = int.parse(parsed.option('iterations')!);
    if (iterations < 1) throw const FormatException('iterations < 1');
    if (parsed.flag('timing') && iterations < 2) {
      throw const FormatException('--timing exige --iterations ≥ 2');
    }
    if (!parsed.flag('list') &&
        parsed.option('bench') == null &&
        parsed.option('measure-open') == null &&
        parsed.option('adapter') == null &&
        parsed.option('doc-adapter') == null &&
        parsed.option('css-adapter') == null) {
      throw const FormatException(
        '--bench, --measure-open, --adapter, --doc-adapter ou --css-adapter '
        'é obrigatório',
      );
    }
    final adapterFlags = [
      'adapter',
      'doc-adapter',
      'css-adapter',
    ].where((o) => parsed.option(o) != null).length;
    if (adapterFlags > 1) {
      throw const FormatException(
        '--adapter, --doc-adapter e --css-adapter não podem ser usados juntos',
      );
    }
    if ((parsed.option('adapter') != null ||
            parsed.option('doc-adapter') != null ||
            parsed.option('css-adapter') != null) &&
        (parsed.option('measure') == null || parsed.rest.length != 1)) {
      throw const FormatException(
        '--adapter exige --measure e o caminho do livro',
      );
    }
  } on FormatException catch (e) {
    stderr.writeln('Argumentos inválidos: ${e.message}\n${parser.usage}');
    await _exit(64);
  }
  if (parsed.flag('list')) {
    for (final bench in Catalog.all()) {
      stdout.writeln(bench.id);
    }
    await _exit(0);
  }
  final cssAdapterName = parsed.option('css-adapter');
  if (cssAdapterName != null) {
    await _exit(
      await runCssMeasure(
        cssAdapterName == 'csslib' ? CsslibParser() : GalleyCssParser(),
        parsed.option('measure')!,
        parsed.rest.single,
        out: stdout,
        err: stderr,
      ),
    );
  }
  final docAdapterName = parsed.option('doc-adapter');
  if (docAdapterName != null) {
    await _exit(
      await runDocumentMeasure(
        docAdapterName == 'xml-dom' ? XmlDomParser() : GalleyDocumentParser(),
        parsed.option('measure')!,
        parsed.rest.single,
        out: stdout,
        err: stderr,
      ),
    );
  }
  final adapterName = parsed.option('adapter');
  if (adapterName != null) {
    await _exit(
      await runAdapterMeasure(
        switch (adapterName) {
          'galley' => GalleyAdapter(),
          'epub_plus' => EpubPlusAdapter(),
          _ => EpubProAdapter(),
        },
        parsed.option('measure')!,
        parsed.rest.single,
        resource: parsed.option('resource'),
        out: stdout,
        err: stderr,
      ),
    );
  }
  final openPath = parsed.option('measure-open');
  if (openPath != null) {
    await _exit(
      await measureOpen(openPath, stdoutSink: stdout, stderrSink: stderr),
    );
  }
  final id = parsed.option('bench')!;
  final Bench bench;
  try {
    bench = Catalog.byId(id);
  } on ArgumentError {
    stderr.writeln('Benchmark desconhecido: $id');
    await _exit(64);
  }
  final code = await runBench(
    bench,
    iterations,
    stdoutSink: stdout,
    stderrSink: stderr,
    timing: parsed.flag('timing'),
  );
  await _exit(code);
}

/// Esvazia stdout e stderr antes de sair, para não perder mensagens quando a
/// saída vai para um pipe.
Future<Never> _exit(int code) async {
  await stdout.flush();
  await stderr.flush();
  exit(code);
}
