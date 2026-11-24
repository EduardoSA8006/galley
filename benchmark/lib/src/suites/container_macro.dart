import 'dart:async';
import 'dart:typed_data';

import 'package:galley/galley.dart';

import '../bench.dart';
import '../corpus/handmade.dart';

/// Ciclos de abertura por `run`, para o ciclo cair em 10–50 ms.
const int _opensPerRun = 80;

/// O livro EPUB 2 é menor e precisa de mais aberturas por `run`.
const int _opensPerRunSmall = 160;

/// Corpus escrito à mão, montado uma vez por processo.
Future<Map<String, Uint8List>>? _corpus;

/// Macro: abre o livro e, com [readSpine], lê todos os itens do spine.
final class _MacroBench implements Bench {
  _MacroBench(this._name, {required this.readSpine, required this.repeats});

  final String _name;
  final bool readSpine;
  final int repeats;
  Uint8List? _bytes;

  @override
  String get id => 'container/open-${readSpine ? 'read-spine-' : ''}$_name';

  @override
  Future<void> setUp() async {
    final corpus = await (_corpus ??= buildHandmadeCorpus());
    _bytes = corpus['hm/$_name']!;
  }

  @override
  Future<int> run() async {
    var sum = 0;
    for (var i = 0; i < repeats; i++) {
      final book = await EpubBook.fromBytes(_bytes!);
      try {
        sum +=
            book.manifest.length +
            book.spine.items.length +
            book.metadata.titles.length +
            book.diagnostics.length;
        if (readSpine) {
          for (final item in book.spine.items) {
            sum += (await book.resource(item.item.path)).length;
          }
        }
      } finally {
        await book.close();
      }
    }
    return sum;
  }

  @override
  Future<void> tearDown() async => _bytes = null;
}

/// Livros `hm/*` bem formados usados nos benchmarks macro.
const List<String> _books = <String>[
  'typography',
  'publisher-css',
  'tables',
  'notes',
  'images',
  'cjk',
  'rtl-bidi',
  'fonts-idpf',
  'fonts-adobe',
  'epub2-ncx',
];

/// Benchmarks macro: abrir cada livro, e abrir + ler o spine inteiro.
List<Bench> containerMacroBenches() => <Bench>[
  for (final name in _books) ...[
    _MacroBench(
      name,
      readSpine: false,
      repeats: name == 'epub2-ncx' ? _opensPerRunSmall : _opensPerRun,
    ),
    _MacroBench(
      name,
      readSpine: true,
      repeats: name == 'epub2-ncx' ? _opensPerRunSmall : _opensPerRun,
    ),
  ],
];
