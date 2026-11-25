// ignore_for_file: implementation_imports

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:galley/galley.dart';
import 'package:galley/src/features/document/data/parse_document.dart';
import 'package:galley/src/features/document/domain/parsed_document.dart';

import '../bench.dart';
import '../corpus/handmade.dart';

/// Tamanho do XHTML sintético grande, textual (1 MiB: um capítulo longo de
/// romance).
const int kLargeXhtmlBytes = 1024 * 1024;

/// Tamanho do XHTML sintético denso em marcação.
const int kDenseXhtmlBytes = 256 * 1024;

/// Tamanho do documento malformado sintético.
const int _tolerantBytes = 256 * 1024;

/// Trechos de prosa que dão corpo ao texto do XHTML sintético.
const List<String> _prose = <String>[
  'A tipografia digital precisa equilibrar o tamanho da fonte, a largura da '
      'coluna e o espaçamento entre linhas para que a leitura longa seja '
      'confortável, mesmo em telas pequenas e com brilho variável ao longo '
      'do dia. Quando o leitor altera a fonte, todo o texto precisa fluir '
      'de novo, e a posição de leitura deve ser preservada com precisão. '
      'Um livro costuma ter centenas de milhares de caracteres, divididos '
      'em capítulos que o leitor abre um de cada vez, às vezes saltando '
      'direto para uma nota de rodapé e voltando em seguida ao ponto em que '
      'estava, sem perder o fio da narrativa nem a marcação que deixou.',
  'Havia uma casa no fim da rua, e dela se dizia que ninguém mais morava '
      'ali desde que a chuva de março derrubou o telhado da varanda. As '
      'crianças passavam correndo em frente ao portão enferrujado, desafiando '
      'umas às outras a tocar a maçaneta, e à noite, quando o vento descia '
      'do morro, a porta rangia como se alguém acabasse de entrar. Ninguém '
      'nunca confirmou nada, mas todos tinham uma história para contar sobre '
      'as luzes que acendiam sozinhas na janela do segundo andar.',
];

/// Gera um XHTML determinístico de pelo menos [targetBytes] bytes, com
/// tabelas, *ruby*, MathML, `style=`, `class`, `id` e `epub:type`.
Uint8List buildLargeXhtml(int targetBytes) {
  final b = StringBuffer()
    ..write(
      '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE html>\n'
      '<html xmlns="http://www.w3.org/1999/xhtml" '
      'xmlns:epub="http://www.idpf.org/2007/ops" '
      'xmlns:m="http://www.w3.org/1998/Math/MathML" lang="pt-BR">'
      '<head><title>Documento sintético</title>'
      '<style>p.texto{margin:0}</style></head><body>',
    );
  var i = 0;
  while (b.length < targetBytes) {
    b.write(
      '<section epub:type="chapter" id="s$i" class="cap c${i % 7}">'
      '<h2 id="h$i">Capítulo $i</h2>'
      '<p class="texto" '
      'style="margin:0 ${i % 5}em;color:#${(i * 37) % 900 + 100}">'
      'Um parágrafo com <em class="e">ênfase</em>, <a href="#s${i + 1}" '
      'epub:type="noteref">um link</a> &amp; texto &eacute;pico número $i, '
      'com <span style="font-weight:bold">negrito</span> e mais palavras '
      'para dar corpo ao texto corrido. ${_prose[i % 2]}</p>'
      '<p>${_prose[(i + 1) % 2]} ${_prose[i % 2]}</p>'
      '<p>${_prose[i % 2]} ${_prose[i % 2]} ${_prose[(i + 1) % 2]}</p>'
      '<p><ruby>漢<rt>かん</rt></ruby><ruby>字<rt>じ</rt></ruby> e kanji $i.</p>'
      '<table class="t"><thead><tr><th>A</th><th>B</th><th>C</th></tr></thead>'
      '<tbody><tr><td>${i * 3}</td><td>${i * 7}</td><td>${i * 11}</td></tr>'
      '<tr><td colspan="2">soma</td><td>${i * 21}</td></tr></tbody></table>'
      '<math xmlns="http://www.w3.org/1998/Math/MathML"><mfrac>'
      '<mi>x</mi><mn>$i</mn></mfrac></math>'
      '</section>',
    );
    i++;
  }
  b.write('</body></html>');
  return Uint8List.fromList(utf8.encode(b.toString()));
}

/// Gera um XHTML determinístico denso em marcação, de pelo menos
/// [targetBytes] bytes: muitos elementos aninhados com atributos (`class`,
/// `id`, `style`, `epub:type`, `data-*`), tabelas, *ruby* e MathML, com
/// pouquíssimo texto.
Uint8List buildDenseXhtml(int targetBytes) {
  final b = StringBuffer()
    ..write(
      '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE html>\n'
      '<html xmlns="http://www.w3.org/1999/xhtml" '
      'xmlns:epub="http://www.idpf.org/2007/ops" lang="pt-BR">'
      '<head><title>Denso</title></head><body>',
    );
  var i = 0;
  while (b.length < targetBytes) {
    b.write(
      '<div id="d$i" class="a${i % 5} b${i % 3}" epub:type="bodymatter" '
      'data-n="$i"><div class="l1"><div class="l2" style="margin:${i % 4}px">'
      '<span class="s" id="x$i" title="t$i">$i</span>'
      '<em class="e">a</em><b class="b">b</b><i>c</i><a href="#d$i" '
      'epub:type="noteref" class="n${i % 9}">d</a>'
      '<table class="t" id="t$i"><tr><td class="c" colspan="2">$i</td>'
      '<td class="c">${i * 3}</td></tr><tr><td>x</td><td>y</td><td>z</td></tr>'
      '</table>'
      '<ruby class="r">字<rt>じ</rt></ruby>'
      '<math xmlns="http://www.w3.org/1998/Math/MathML"><mrow><mi>x</mi>'
      '<mo>+</mo><mn>$i</mn></mrow></math>'
      '<img src="i$i.png" alt="" class="im" width="1" height="1"/><br/>'
      '</div></div></div>',
    );
    i++;
  }
  b.write('</body></html>');
  return Uint8List.fromList(utf8.encode(b.toString()));
}

/// Gera um documento malformado determinístico de pelo menos [targetBytes]
/// bytes: `<br>` e `<p>` sem fechamento, atributos sem aspas, `&` solto,
/// tags cruzadas e fechamentos sobrando (tudo isso força o modo tolerante).
Uint8List buildMalformedXhtml(int targetBytes) {
  final b = StringBuffer()
    ..write('<html><head><title>Malformado</title></head><body>');
  var i = 0;
  while (b.length < targetBytes) {
    b.write(
      '<div class=bloco id=b$i><p>Texto $i & mais texto<br>'
      '<b>negrito <i>cruzado</b> itálico</i>'
      '<p>segundo parágrafo sem fechar<ul><li>um<li>dois</ul></span>'
      '<table><tr><td>${i * 3}<td>${i * 5}</table></div>',
    );
    i++;
  }
  return Uint8List.fromList(utf8.encode(b.toString()));
}

/// Soma que depende da árvore montada e dos diagnósticos.
int _checksum(ParsedDocument d) =>
    d.tree.nodeCount * 31 + d.tree.retainedBytes + d.diagnostics.length;

/// Benchmark de documento: [_prepare] monta a entrada (fora da medição) e
/// devolve o trabalho que `run` repete.
final class _DocBench implements Bench {
  _DocBench(this.id, this._prepare);

  @override
  final String id;

  final Future<FutureOr<int> Function()> Function() _prepare;
  FutureOr<int> Function()? _work;

  @override
  Future<void> setUp() async => _work = await _prepare();

  @override
  FutureOr<int> run() => _work!();

  @override
  Future<void> tearDown() async => _work = null;
}

/// Livros `hm/*` bem formados (os `malformed-*` ficam de fora).
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

/// Repetições do parse do spine por livro, para o ciclo cair em 10–50 ms.
const Map<String, int> _spineRepeats = {
  'typography': 300,
  'publisher-css': 290,
  'tables': 320,
  'notes': 320,
  'images': 600,
  'cjk': 400,
  'rtl-bidi': 380,
  'fonts-idpf': 1100,
  'fonts-adobe': 1000,
  'epub2-ncx': 550,
};

/// Repetições de consultas por `run` do `query-id-class`.
const int _queryRepeats = 100000;

Future<Map<String, Uint8List>>? _corpus;

Future<List<(Uint8List, String)>> _spineDocuments(String name) async {
  final corpus = await (_corpus ??= buildHandmadeCorpus());
  final book = await EpubBook.fromBytes(corpus['hm/$name']!);
  try {
    return [
      for (final item in book.spine.items)
        (await book.resource(item.item.path), item.item.mediaType),
    ];
  } finally {
    await book.close();
  }
}

/// Benchmarks de documento: construção da árvore, consultas, modo
/// tolerante, transferência entre isolates e parse do spine dos livros
/// `hm/*`.
List<Bench> documentBenches() => <Bench>[
  _DocBench('document/build-large-1mib', () async {
    final bytes = buildLargeXhtml(kLargeXhtmlBytes);
    return () =>
        _checksum(parseDocumentBytes(bytes, path: 'OEBPS/grande.xhtml'));
  }),
  _DocBench('document/build-dense-256kib', () async {
    final bytes = buildDenseXhtml(kDenseXhtmlBytes);
    return () =>
        _checksum(parseDocumentBytes(bytes, path: 'OEBPS/denso.xhtml'));
  }),
  _DocBench('document/query-id-class', () async {
    final document = parseDocumentBytes(
      buildLargeXhtml(kLargeXhtmlBytes),
      path: 'OEBPS/grande.xhtml',
    );
    final tree = document.tree;
    return () {
      var sum = 0;
      for (var i = 0; i < _queryRepeats; i++) {
        sum += tree.elementById('s${i * 13 % 400}') ?? 0;
        sum += tree.elementsWithClass('c${i % 7}').length;
        sum += tree.elementsWithClass('texto').length;
      }
      return sum;
    };
  }),
  _DocBench('document/build-tolerant', () async {
    final bytes = buildMalformedXhtml(_tolerantBytes);
    return () {
      final d = parseDocumentBytes(bytes, path: 'OEBPS/ruim.xhtml');
      if (!d.recovered) throw StateError('o documento deveria ser tolerante');
      return _checksum(d);
    };
  }),
  // Mede parse + spawn + transferência (não só o envio); a diferença para
  // `document/build-large-1mib` estima o custo da transferência.
  _DocBench('document/transfer-large', () async {
    final bytes = buildLargeXhtml(kLargeXhtmlBytes);
    return () async {
      final document = await Isolate.run(
        () => parseDocumentBytes(bytes, path: 'OEBPS/grande.xhtml'),
      );
      return _checksum(document);
    };
  }),
  for (final name in _books)
    _DocBench('document/parse-spine-hm-$name', () async {
      final documents = await _spineDocuments(name);
      final repeats = _spineRepeats[name]!;
      return () {
        var sum = 0;
        for (var r = 0; r < repeats; r++) {
          for (final (bytes, mediaType) in documents) {
            sum += _checksum(
              parseDocumentBytes(
                bytes,
                path: 'OEBPS/doc.xhtml',
                mediaType: mediaType,
              ),
            );
          }
        }
        return sum;
      };
    }),
];
