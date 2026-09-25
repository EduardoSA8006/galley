import 'dart:io';
import 'dart:typed_data';

/// Um caso do corpus: um EPUB, uma linha de README e o que se espera dele.
class CorpusCase {
  const CorpusCase({
    required this.group,
    required this.slug,
    required this.readme,
    required this.build,
    this.diagnostics = const [],
    this.exception,
  });

  /// Pasta do grupo em `test/corpus/` (`regressoes`, `faixa-b`...).
  final String group;
  final String slug;

  /// Uma linha: o que o caso testa. A origem "sintético" é acrescentada.
  final String readme;

  /// Códigos de `EpubDiagnostic` esperados (doc/09 §3), em ordem alfabética.
  final List<String> diagnostics;

  /// Exceção fatal esperada em `open` (doc/09 §2), ou `null`.
  final String? exception;

  final Uint8List Function() build;

  Directory dirIn(Directory corpusRoot) =>
      Directory('${corpusRoot.path}/$group/$slug');

  void writeTo(Directory corpusRoot) {
    final dir = dirIn(corpusRoot)..createSync(recursive: true);
    File('${dir.path}/book.epub').writeAsBytesSync(build());
    File('${dir.path}/README.md')
        .writeAsStringSync('$readme Origem: sintético.\n');
    final diag = File('${dir.path}/diagnostics.expected');
    if (diagnostics.isNotEmpty) {
      diag.writeAsStringSync('${([...diagnostics]..sort()).join('\n')}\n');
    } else if (diag.existsSync()) {
      diag.deleteSync();
    }
    final exc = File('${dir.path}/exception.expected');
    if (exception != null) {
      exc.writeAsStringSync('$exception\n');
    } else if (exc.existsSync()) {
      exc.deleteSync();
    }
  }
}
