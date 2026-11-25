import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/features/document/data/parse_document.dart';

import '../../support/synthetic_xhtml.dart';

/// Teto da razão `tree.retainedBytes / bytes do XHTML`.
///
/// Medido na primeira execução: 3,584 (512 KiB de XHTML sintético); o teto
/// é o medido × 1,25, arredondado para 4,48. O contador `retainedBytes`
/// conta os arranjos tipados da árvore, o texto e os valores de atributo a
/// 2 bytes por caractere (UTF-16) e exclui as tabelas de nomes e de tokens (definição documentada em
/// `DocumentTree.retainedBytes`).
const double _maxRetainedRatio = 4.48;

void main() {
  test('a árvore retém no máximo K vezes os bytes do XHTML', () {
    final bytes = syntheticXhtml(512 * 1024);
    final document = parseDocumentBytes(bytes, path: 'OEBPS/memoria.xhtml');
    expect(document.recovered, isFalse);
    final ratio = document.tree.retainedBytes / bytes.length;
    expect(ratio, lessThanOrEqualTo(_maxRetainedRatio));
  });
}
