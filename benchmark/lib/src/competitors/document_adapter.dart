// ignore_for_file: implementation_imports

import 'dart:io';
import 'dart:typed_data';

import 'package:galley/galley.dart';
import 'package:galley/src/features/container/data/text/decode_text.dart';
import 'package:galley/src/features/document/data/parse_document.dart';
import 'package:galley/src/features/document/domain/document_tree.dart';
import 'package:xml/xml.dart';

import '../peak_rss.dart';
import 'measure.dart' show exitMeasureFailure, exitMeasureUsage;

/// Parser de documentos XHTML para a comparação informativa (`compare`).
///
/// Mede só o parse: os bytes dos documentos já estão na memória.
abstract interface class DocumentParser {
  /// Nome do parser (`galley-document` ou `xml-dom`).
  String get name;

  /// Faz o parse de todos os [documents] e mantém as árvores vivas até o
  /// fim (o pico de memória precisa contá-las). Devolve o total de
  /// elementos, que é o checksum (igual nos dois parsers em documentos bem
  /// formados).
  int parseAll(List<Uint8List> documents);
}

/// `parseDocumentBytes` do Galley.
final class GalleyDocumentParser implements DocumentParser {
  @override
  String get name => 'galley-document';

  @override
  int parseAll(List<Uint8List> documents) {
    final trees = <DocumentTree>[
      for (var i = 0; i < documents.length; i++)
        parseDocumentBytes(documents[i], path: 'doc$i.xhtml').tree,
    ];
    var elements = 0;
    for (final tree in trees) {
      for (var n = 0; n < tree.nodeCount; n++) {
        if (tree.kindOf(n) == NodeKind.element) elements++;
      }
    }
    return elements;
  }
}

/// DOM do `package:xml` (`XmlDocument.parse`) com as entidades HTML5, a
/// partir do mesmo texto decodificado.
final class XmlDomParser implements DocumentParser {
  @override
  String get name => 'xml-dom';

  @override
  int parseAll(List<Uint8List> documents) {
    final trees = <XmlDocument>[
      for (final bytes in documents)
        XmlDocument.parse(
          decodeText(bytes),
          entityMapping: XmlDefaultEntityMapping.html5(),
        ),
    ];
    var elements = 0;
    for (final tree in trees) {
      elements += tree.descendantElements.length;
    }
    return elements;
  }
}

/// Carrega os documentos de [path]: num `.epub`, os documentos do spine (em
/// ordem); em qualquer outro arquivo, o próprio arquivo.
Future<List<Uint8List>> loadDocuments(String path) async {
  if (!path.endsWith('.epub')) return [File(path).readAsBytesSync()];
  final book = await EpubBook.fromBytes(File(path).readAsBytesSync());
  try {
    return [
      for (final item in book.spine.items) await book.resource(item.item.path),
    ];
  } finally {
    await book.close();
  }
}

/// Mede o parse de [path] com [parser] e escreve `ns=`, `rss=` e
/// `checksum=` em [out], no mesmo formato do `runAdapterMeasure`.
///
/// O tempo cobre só o parse (a leitura do arquivo fica de fora); `rss` é o
/// pico (`VmHWM`) lido no fim. Devolve 0 ou [exitMeasureFailure].
Future<int> runDocumentMeasure(
  DocumentParser parser,
  String kind,
  String path, {
  required StringSink out,
  required StringSink err,
}) async {
  if (kind != 'parse') {
    err.writeln('Medida desconhecida: $kind (use parse)');
    return exitMeasureUsage;
  }
  try {
    final documents = await loadDocuments(path);
    final clock = Stopwatch()..start();
    final checksum = parser.parseAll(documents);
    clock.stop();
    final ns = (clock.elapsedTicks * 1e9 / clock.frequency).round();
    out
      ..writeln('ns=$ns')
      ..writeln('rss=${peakRssBytes()}')
      ..writeln('checksum=$checksum');
    return 0;
  } on Object catch (e, st) {
    err.writeln('Falha em ${parser.name} (parse): $e\n$st');
    return exitMeasureFailure;
  }
}
