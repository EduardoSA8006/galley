import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/features/document/data/parse_document.dart';
import 'package:galley/src/features/style/data/book_style_context.dart';
import 'package:galley/src/features/style/data/style_document.dart';
import 'package:galley/src/features/style/domain/reader_preferences.dart';
import 'package:galley/src/features/style/domain/restyle.dart';
import 'package:galley/src/features/style/domain/style_environment.dart';

import '../../support/publisher_css.dart';
import '../../support/synthetic_xhtml.dart';

// Tetos calibrados na primeira medição (XHTML sintético de 1 MiB de
// `syntheticXhtml` com `kPublisherCss` ligada, sem preferências): o medido
// × 1,25, congelado. Uma regressão que passe do teto precisa de motivo e de
// nova calibração registrada aqui.

/// Teto de estilos distintos no capítulo. Medido: 36; teto 36 × 1,25 = 45.
const int kMaxDistinctStyles = 45;

/// Teto da razão `StyledDocument.retainedBytes / bytes do XHTML`. Medido:
/// 0,4557; teto 0,4557 × 1,25 ≈ 0,57.
const double kMaxStyledRatio = 0.57;

/// Teto da razão `MatchedDocument.retainedBytes / bytes do XHTML` (inclui a
/// árvore do SP3, ≈ 3,6 dos bytes do XHTML). Medido: 4,2387; teto
/// 4,2387 × 1,25 ≈ 5,30.
const double kMaxMatchedRatio = 5.30;

void main() {
  test('tetos de memória do estilo no XHTML sintético de 1 MiB', () {
    final bytes = syntheticXhtml(
      1024 * 1024,
      head: '<link rel="stylesheet" href="estilo.css"/>',
    );
    final document = parseDocumentBytes(bytes, path: 'OEBPS/memoria.xhtml');
    expect(document.recovered, isFalse);
    final css = Uint8List.fromList(utf8.encode(kPublisherCss));
    final context = BookStyleContext(
      resolve: (p) => p == 'OEBPS/estilo.css' ? css : null,
      bookKey: 'memoria',
    );
    const env = StyleEnvironment(pageWidth: 500, pageHeight: 800);
    final matched = matchDocument(context, document, env);
    final styled = restyle(matched, ReaderPreferences.none);
    expect(styled.internalError, isNull);
    final styledRatio = styled.retainedBytes / bytes.length;
    final matchedRatio = matched.retainedBytes / bytes.length;
    // ignore: avoid_print
    print(
      'MEDIDO distinct=${styled.distinctStyleCount} '
      'styled=$styledRatio matched=$matchedRatio',
    );
    expect(styled.distinctStyleCount, lessThanOrEqualTo(kMaxDistinctStyles));
    expect(styledRatio, lessThanOrEqualTo(kMaxStyledRatio));
    expect(matchedRatio, lessThanOrEqualTo(kMaxMatchedRatio));
  });
}
