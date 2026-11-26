import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/core/diagnostics/diagnostic_codes.dart';
import 'package:galley/src/features/document/data/parse_document.dart';
import 'package:galley/src/features/document/domain/parsed_document.dart';
import 'package:xml/xml.dart';

ParsedDocument _parse(String source) => parseDocumentBytes(
  Uint8List.fromList(utf8.encode(source)),
  path: 'OEBPS/ch1.xhtml',
);

void main() {
  test('documentos comuns, malformados e vazios: internalError nulo', () {
    for (final source in [
      '<html xmlns="http://www.w3.org/1999/xhtml"><body/></html>',
      '<p>aberto</div>',
      '',
    ]) {
      final doc = _parse(source);
      expect(doc.internalError, isNull, reason: source);
      expect(doc.path, 'OEBPS/ch1.xhtml', reason: source);
    }
  });

  // Forçar um defeito interno pelo parse real exigiria um bug conhecido;
  // `guardParse` é o próprio catch-all de `parseDocumentBytes`, isolado
  // para ser exercitado com um corpo que lança.
  group('guardParse (o catch-all de parseDocumentBytes)', () {
    test('exceção inesperada: irrecuperável com internalError', () {
      final doc = guardParse(
        'OEBPS/ch1.xhtml',
        () => throw StateError('bug no montador'),
      );
      expect(doc.internalError, 'StateError');
      expect(doc.path, 'OEBPS/ch1.xhtml');
      expect(doc.recovered, isTrue);
      final error = doc.diagnostics.single;
      expect(error.code, DiagnosticCodes.unparseable);
      expect(error.message, contains('erro inesperado (StateError)'));
    });

    test('XmlException: irrecuperável sem internalError', () {
      final doc = guardParse(
        'OEBPS/ch1.xhtml',
        () => throw XmlParserException('ruim'),
      );
      expect(doc.internalError, isNull);
      expect(doc.recovered, isTrue);
      expect(doc.diagnostics.single.code, DiagnosticCodes.unparseable);
    });

    test('sem exceção: devolve o resultado do corpo', () {
      final inner = _parse('<html><body/></html>');
      expect(guardParse('x', () => inner), same(inner));
    });
  });
}
