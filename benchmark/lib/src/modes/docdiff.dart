// ignore_for_file: implementation_imports

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:galley/galley.dart';
import 'package:galley/src/features/container/data/text/decode_text.dart';
import 'package:galley/src/features/document/data/parse_document.dart';
import 'package:galley/src/features/document/domain/document_tree.dart';
import 'package:galley/src/features/document/domain/names.dart';
import 'package:galley/src/features/document/domain/parsed_document.dart';
import 'package:xml/xml.dart';

import '../bmf.dart' as bmf;
import '../corpus/fetcher.dart';
import '../corpus/manifest.dart';
import 'orchestration.dart' show exitMeasurementFailure;

/// Leitura de um documento: a assinatura de `parseDocumentBytes`, injetável
/// nos testes (montador falso) e no `wide`.
typedef DocumentBytesParser = ParsedDocument Function(
  Uint8List bytes, {
  required String path,
  String mediaType,
});

/// Media-types de documento lidos pelo `docdiff` e pelo `wide` (os mesmos
/// de `parseDocument`); outros itens do spine ficam de fora.
const Set<String> documentMediaTypes = {
  'application/xhtml+xml',
  'text/html',
  'image/svg+xml',
};

/// Quantas divergências o relatório lista (com o caminho e o evento).
const int docDiffListed = 10;

/// Resultado da comparação de um documento.
enum DocDiffKind {
  /// As duas sequências de eventos são iguais.
  match,

  /// As sequências diferem: bug do Galley.
  mismatch,

  /// O Galley leu o documento pelo modo tolerante; fora da comparação.
  tolerant,

  /// O Galley leu pelo caminho estrito, mas o DOM do `package:xml` lançou;
  /// fora da comparação (não é divergência).
  domUnparseable,
}

/// Resultado da comparação de um documento.
final class DocDiffOutcome {
  /// Cria o resultado.
  const DocDiffOutcome(
    this.path,
    this.kind, {
    this.index = -1,
    this.ours = '',
    this.dom = '',
  });

  /// Caminho do documento (`<livro>/<caminho no EPUB>`).
  final String path;

  /// Classe do resultado.
  final DocDiffKind kind;

  /// Índice do primeiro evento divergente (só em [DocDiffKind.mismatch]).
  final int index;

  /// Nosso evento nesse índice (`<fim>` se a nossa sequência acabou); no
  /// [DocDiffKind.domUnparseable], a mensagem do `package:xml`.
  final String ours;

  /// Evento do DOM nesse índice (`<fim>` se a do DOM acabou).
  final String dom;

  @override
  String toString() => switch (kind) {
    DocDiffKind.mismatch =>
      '$path: evento $index: nosso ${_clip(ours)} × DOM ${_clip(dom)}',
    DocDiffKind.domUnparseable => '$path: DOM falhou: ${_clip(ours)}',
    _ => '$path: ${kind.name}',
  };
}

String _clip(String s) => s.length <= 160 ? s : '${s.substring(0, 160)}…';

/// Acumula os resultados de uma execução do `docdiff`.
final class DocDiffReport {
  /// Documentos comparados ou excluídos (todas as classes).
  int total = 0;

  /// Documentos em que as sequências bateram.
  int matched = 0;

  /// Documentos lidos pelo modo tolerante (fora da comparação).
  int tolerant = 0;

  /// Divergências, em ordem.
  final List<DocDiffOutcome> mismatches = [];

  /// Documentos que o DOM do `package:xml` não leu (fora da comparação).
  final List<DocDiffOutcome> domUnparseable = [];

  /// Livros ou documentos que não puderam ser lidos (sem download, EPUB
  /// rejeitado, recurso ausente); só informativo.
  final List<String> notes = [];

  /// Acrescenta o resultado de um documento.
  void add(DocDiffOutcome outcome) {
    total++;
    switch (outcome.kind) {
      case DocDiffKind.match:
        matched++;
      case DocDiffKind.mismatch:
        mismatches.add(outcome);
      case DocDiffKind.tolerant:
        tolerant++;
      case DocDiffKind.domUnparseable:
        domUnparseable.add(outcome);
    }
  }

  /// 1 se houve divergência; 0 caso contrário.
  int get exitCode => mismatches.isEmpty ? 0 : 1;

  /// BMF: `docdiff/mismatch` → `count`.
  Map<String, Object> toBmf() => bmf.toBmf({
    'docdiff/mismatch': [
      bmf.Measure(
        slug: bmf.MeasureSlug.count,
        value: mismatches.length.toDouble(),
      ),
    ],
  });

  /// Resumo em texto: contagens, as primeiras [docDiffListed] divergências
  /// (caminho e primeiro evento divergente) e os documentos que o DOM não
  /// leu.
  String summary() {
    final b = StringBuffer()
      ..writeln('Diferencial de documentos (Galley × DOM do package:xml)')
      ..writeln('  documentos: $total')
      ..writeln('  bateram: $matched')
      ..writeln('  divergências: ${mismatches.length}')
      ..writeln('  modo tolerante (fora da comparação): $tolerant')
      ..writeln('  DOM não leu (fora da comparação): ${domUnparseable.length}');
    if (mismatches.isNotEmpty) {
      b.writeln('Divergências (primeiras $docDiffListed):');
      for (final m in mismatches.take(docDiffListed)) {
        b.writeln('  $m');
      }
    }
    if (domUnparseable.isNotEmpty) {
      b.writeln('DOM não leu (primeiros $docDiffListed):');
      for (final m in domUnparseable.take(docDiffListed)) {
        b.writeln('  $m');
      }
    }
    if (notes.isNotEmpty) {
      b.writeln('Fora da comparação:');
      for (final n in notes) {
        b.writeln('  $n');
      }
    }
    return b.toString();
  }
}

/// Compara a sequência de eventos da nossa árvore ([parse], por padrão
/// `parseDocumentBytes`) com a do DOM do `package:xml` para o documento
/// [bytes] em [path].
///
/// Documento lido pelo modo tolerante (`recovered`) não é comparado
/// ([DocDiffKind.tolerant]); se o DOM lança, [DocDiffKind.domUnparseable].
DocDiffOutcome compareDocument(
  String path,
  Uint8List bytes, {
  String mediaType = 'application/xhtml+xml',
  DocumentBytesParser parse = parseDocumentBytes,
}) {
  final parsed = parse(bytes, path: path, mediaType: mediaType);
  if (parsed.recovered) return DocDiffOutcome(path, DocDiffKind.tolerant);
  final XmlDocument dom;
  try {
    dom = XmlDocument.parse(
      _normalizeLineEnds(decodeText(bytes)),
      entityMapping: _entities,
    );
  } on XmlException catch (e) {
    return DocDiffOutcome(path, DocDiffKind.domUnparseable, ours: e.message);
  }
  final ours = treeEvents(parsed.tree);
  final theirs = domEvents(dom);
  final common = ours.length < theirs.length ? ours.length : theirs.length;
  for (var i = 0; i < common; i++) {
    if (ours[i] != theirs[i]) {
      return DocDiffOutcome(
        path,
        DocDiffKind.mismatch,
        index: i,
        ours: ours[i],
        dom: theirs[i],
      );
    }
  }
  if (ours.length != theirs.length) {
    return DocDiffOutcome(
      path,
      DocDiffKind.mismatch,
      index: common,
      ours: common < ours.length ? ours[common] : '<fim>',
      dom: common < theirs.length ? theirs[common] : '<fim>',
    );
  }
  return DocDiffOutcome(path, DocDiffKind.match);
}

/// Entidades HTML5 do `package:xml`, sem a variante linear do Galley: o
/// DOM serve de referência independente para ela.
final XmlEntityMapping _entities = XmlDefaultEntityMapping.html5();

/// Compara todos os documentos do spine de [book] (cada caminho uma vez),
/// acrescentando em [report] com caminhos `<key>/<caminho>`. Itens do spine
/// que não são documento ficam de fora; um recurso ilegível vira nota.
Future<void> diffBook(
  EpubBook book,
  String key,
  DocDiffReport report, {
  DocumentBytesParser parse = parseDocumentBytes,
}) async {
  final seen = <String>{};
  for (final spineItem in book.spine.items) {
    final item = spineItem.item;
    if (!documentMediaTypes.contains(item.mediaType)) continue;
    if (!seen.add(item.path)) continue;
    final Uint8List bytes;
    try {
      bytes = await book.resource(item.path);
    } on GalleyException catch (e) {
      report.notes.add('$key/${item.path}: ilegível (${e.runtimeType})');
      continue;
    }
    report.add(
      compareDocument(
        '$key/${item.path}',
        bytes,
        mediaType: item.mediaType,
        parse: parse,
      ),
    );
  }
}

/// Executa o modo `docdiff` sobre os livros do manifesto público
/// [manifestPath] (cache em [cacheDir]): imprime o resumo em [log] e grava
/// o BMF em [outPath] e o relatório em [reportPath] (se dados).
///
/// Devolve 1 se houver divergência, [exitMeasurementFailure] se nenhum
/// documento foi comparado (corpus inteiro indisponível) e 0 caso
/// contrário.
Future<int> runDocDiffMode({
  required String manifestPath,
  required Directory cacheDir,
  String? outPath,
  String? reportPath,
  StringSink? log,
}) async {
  final sink = log ?? stderr;
  final report = DocDiffReport();
  final fetcher = CorpusFetcher(cacheDir: cacheDir);
  try {
    for (final entry in loadManifest(manifestPath)) {
      final File file;
      try {
        file = await fetcher.fetch(entry);
      } on CorpusFetchException catch (e) {
        report.notes.add('${entry.id}: não baixou (${e.causes.join('; ')})');
        continue;
      }
      final EpubBook book;
      try {
        book = await EpubBook.open(file.path);
      } on GalleyException catch (e) {
        report.notes.add('${entry.id}: EPUB rejeitado (${e.runtimeType})');
        continue;
      }
      try {
        sink.writeln('comparando ${entry.id}');
        await diffBook(book, entry.id, report);
      } finally {
        await book.close();
      }
    }
  } finally {
    fetcher.close();
  }
  final summary = report.summary();
  sink.write(summary);
  if (outPath != null) {
    await File(outPath).writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(report.toBmf())}\n',
    );
  }
  if (reportPath != null) {
    await File(reportPath).writeAsString('```\n$summary```\n');
  }
  if (report.total == 0) {
    sink.writeln('Nenhum documento comparado.');
    return exitMeasurementFailure;
  }
  return report.exitCode;
}

// ---------------------------------------------------------------------------
// Sequências de eventos
//
// Os dois lados viram a mesma sequência: `<{uri}local attrs>` ao entrar num
// elemento (atributos ordenados por URI e nome local, sem `xmlns*`),
// `#text "…"` para o texto (fundido entre eventos de elemento, CDATA como
// texto, comentários e PIs ignorados, texto vazio omitido) e `</{uri}local>`
// ao sair. Strings e valores vão em JSON, para o relatório mostrar
// caracteres invisíveis.
// ---------------------------------------------------------------------------

final class _Events {
  final List<String> events = [];
  final StringBuffer _text = StringBuffer();

  void text(String value) => _text.write(value);

  void enter(String name, List<(String, String, String)> attributes) {
    _flush();
    attributes.sort((a, b) {
      final c = a.$1.compareTo(b.$1);
      return c != 0 ? c : a.$2.compareTo(b.$2);
    });
    final b = StringBuffer('<$name');
    for (final (uri, local, value) in attributes) {
      b.write(' {$uri}$local=${jsonEncode(value)}');
    }
    b.write('>');
    events.add(b.toString());
  }

  void exit(String name) {
    _flush();
    events.add('</$name>');
  }

  void _flush() {
    if (_text.isEmpty) return;
    events.add('#text ${jsonEncode(_text.toString())}');
    _text.clear();
  }
}

/// Sequência de eventos da nossa árvore, a partir dos filhos do nó do
/// documento (iterativa).
List<String> treeEvents(DocumentTree tree) {
  final out = _Events();
  final names = tree.names;
  String nameOf(int element) =>
      '{${names.namespaceUriOf(tree.namespaceOf(element)) ?? ''}}'
      '${tree.localNameOf(element)}';

  var n = tree.firstChildOf(tree.documentNode);
  while (n != -1) {
    if (tree.kindOf(n) == NodeKind.text) {
      out.text(tree.textOf(n));
    } else {
      out.enter(nameOf(n), [
        for (final a in tree.attributesOf(n))
          (
            names.namespaceUriOf(names.namespaceOf(a.name)) ?? '',
            names.localNameOf(a.name),
            a.value,
          ),
      ]);
      final child = tree.firstChildOf(n);
      if (child != -1) {
        n = child;
        continue;
      }
      out.exit(nameOf(n));
    }
    // Sobe até achar um irmão seguinte, fechando os elementos no caminho.
    while (n != -1 && tree.nextSiblingOf(n) == -1) {
      n = tree.parentOf(n);
      if (n == tree.documentNode) {
        n = -1;
      } else {
        out.exit(nameOf(n));
      }
    }
    if (n != -1) n = tree.nextSiblingOf(n);
  }
  out._flush();
  return out.events;
}

/// Sequência de eventos do DOM do `package:xml`, só do elemento raiz
/// (iterativa).
///
/// O DOM não aplica as regras que o Galley aplica de propósito; para não
/// virarem divergência, este lado as reproduz:
/// - CRLF e CR isolado → LF: feito na entrada, antes do parse (XML §2.11),
///   como o Galley faz.
/// - Valores de atributo: TAB, LF e CR → espaço (XML §3.3.3; o Galley não
///   distingue referências de caractere).
/// - Caracteres proibidos no XML 1.0 (controles, surrogate isolado,
///   U+FFFE/U+FFFF) → U+FFFD, no texto e nos atributos.
/// - Prefixos sem declaração: o DOM não os resolve (URI nula). Como o
///   Galley, `xml:` vai ao namespace XML, `epub:` e `xlink:` a OPS e XLink,
///   e os demais a [Namespaces.undeclaredPrefixUri] com o nome qualificado
///   como nome local. Uma declaração `xmlns:p=""` (ilegal) é ignorada.
/// - Atributos sem prefixo ficam sem namespace (o DOM daria o padrão).
/// - Atributo repetido: vale o primeiro (o DOM guarda todos).
List<String> domEvents(XmlDocument document) {
  final out = _Events();
  final stack = <(XmlElement, Iterator<XmlNode>)>[];

  void enter(XmlElement e) {
    final attributes = <(String, String, String)>[];
    final seen = <String>{};
    for (final a in e.attributes) {
      final qualified = a.name.qualified;
      if (qualified == 'xmlns' || qualified.startsWith('xmlns:')) continue;
      final (uri, local) = a.name.prefix == null
          ? ('', qualified)
          : _resolvePrefixed(e, a.name.prefix!, a.name.local, qualified);
      if (!seen.add('{$uri}$local')) continue;
      attributes.add((uri, local, _sanitize(a.value, attribute: true)));
    }
    out.enter(_elementName(e), attributes);
    stack.add((e, e.children.iterator));
  }

  enter(document.rootElement);
  while (stack.isNotEmpty) {
    final (element, children) = stack.last;
    if (!children.moveNext()) {
      stack.removeLast();
      out.exit(_elementName(element));
      continue;
    }
    switch (children.current) {
      case final XmlElement child:
        enter(child);
      case final XmlText t:
        out.text(_sanitize(t.value, attribute: false));
      case final XmlCDATA c:
        out.text(_sanitize(c.value, attribute: false));
      default:
        break; // comentários e PIs
    }
  }
  out._flush();
  return out.events;
}

String _elementName(XmlElement e) {
  final name = e.name;
  if (name.prefix == null) return '{${name.namespaceUri ?? ''}}${name.local}';
  final (uri, local) = _resolvePrefixed(
    e,
    name.prefix!,
    name.local,
    name.qualified,
  );
  return '{$uri}$local';
}

/// (URI, nome local) de um nome com [prefix] no escopo de [element].
(String, String) _resolvePrefixed(
  XmlElement element,
  String prefix,
  String local,
  String qualified,
) {
  final declaration = 'xmlns:$prefix';
  for (XmlNode? n = element; n is XmlElement; n = n.parent) {
    final value = n.getAttribute(declaration);
    if (value != null && value.isNotEmpty) return (value, local);
  }
  return switch (prefix) {
    'xml' => ('http://www.w3.org/XML/1998/namespace', local),
    'epub' => ('http://www.idpf.org/2007/ops', local),
    'xlink' => ('http://www.w3.org/1999/xlink', local),
    _ => (Namespaces.undeclaredPrefixUri, qualified),
  };
}

String _normalizeLineEnds(String text) =>
    text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

/// Caracteres proibidos → U+FFFD; num atributo, também TAB/LF/CR → espaço.
String _sanitize(String value, {required bool attribute}) {
  final b = StringBuffer();
  for (final r in value.runes) {
    if (r == 0x09 || r == 0x0A || r == 0x0D) {
      b.writeCharCode(attribute ? 0x20 : r);
    } else if (r < 0x20 ||
        (r >= 0xD800 && r <= 0xDFFF) ||
        r == 0xFFFE ||
        r == 0xFFFF) {
      b.writeCharCode(0xFFFD);
    } else {
      b.writeCharCode(r);
    }
  }
  return b.toString();
}
