/// Gera os EPUBs sintéticos do corpus em `test/corpus/<grupo>/<slug>/`.
///
/// Uso: `dart run tool/corpus/generate.dart [--only <grupo|slug>]`
///
/// Sem `--only`, cada grupo sintético é apagado e regenerado por inteiro.
/// `test/corpus/reais/` nunca é tocado.
library;

import 'dart:io';
import 'dart:typed_data';

import 'lib/cases/conteudo.dart';
import 'lib/cases/escrita.dart';
import 'lib/cases/estrutura.dart';
import 'lib/cases/faixa_b.dart';
import 'lib/cases/patologia.dart';
import 'lib/cases/regressoes.dart';
import 'lib/corpus_case.dart';

void main(List<String> args) {
  final only = _flag(args, '--only');
  final toolDir = File.fromUri(Platform.script).parent;
  final repoRoot = toolDir.parent.parent;
  final corpusRoot = Directory('${repoRoot.path}/test/corpus');
  final font = File('${toolDir.path}/assets/NotoSansOgham-Regular.ttf').readAsBytesSync();

  final all = <CorpusCase>[
    ...regressoesCases(),
    ...estruturaCases(),
    ...conteudoCases(),
    ...faixaBCases(),
    ...escritaCases(),
    ...patologiaCases(Uint8List.fromList(font)),
  ];
  final selected = only == null
      ? all
      : all.where((c) => c.group == only || c.slug == only).toList();
  if (selected.isEmpty) {
    stderr.writeln('Nenhum caso casa com "$only".');
    exit(2);
  }

  if (only == null) {
    for (final group in selected.map((c) => c.group).toSet()) {
      final dir = Directory('${corpusRoot.path}/$group');
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  }

  final sw = Stopwatch()..start();
  var bytes = 0;
  for (final c in selected) {
    c.writeTo(corpusRoot);
    final size = File('${c.dirIn(corpusRoot).path}/book.epub').lengthSync();
    bytes += size;
    stdout.writeln('${c.group}/${c.slug}  ${(size / 1024).toStringAsFixed(1)} KB');
  }
  stdout.writeln('${selected.length} casos, ${(bytes / 1024 / 1024).toStringAsFixed(2)} MB, ${sw.elapsedMilliseconds} ms');
}

String? _flag(List<String> args, String name) {
  final i = args.indexOf(name);
  if (i < 0 || i + 1 >= args.length) return null;
  return args[i + 1];
}
