// Sanidade estrutural do corpus. Não parseia EPUB: só garante que cada caso
// tem os arquivos da convenção (test/corpus/README.md) e que o ZIP tem a
// forma esperada. O parser real entra na Fase 1.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Códigos de doc/09 §3. Um `diagnostics.expected` só pode citar estes.
const knownDiagnostics = {
  'unsupportedLayout',
  'unsupportedMath',
  'unsupportedMediaType',
  'rubyFlattened',
  'resourceMissing',
  'spineItemUnresolved',
  'encodingFallback',
  'unknownEntity',
  'imageWithoutAlt',
  'imageWithoutIntrinsicSize',
  'imageDecodeFailed',
  'inlineImagePromoted',
  'svgUnrasterized',
  'anchorNotFound',
  'locatorRepaired',
  'tocReconciled',
  'coverHeuristic',
  'cacheMiss',
  'mimetypeIrregular',
  'zipCrcMismatch',
  'indivisibleBlock',
  'tableOverflow',
  'viewportTooSmall',
  'fontObfuscationUnknown',
  'sectionTooLarge',
  'zipDuplicateEntry',
  'pathCaseMismatch',
  'resourceUnreadable',
  'encryptionIgnored',
  'navIgnored',
  'spineItemDuplicate',
};

/// Exceções fatais de doc/09 §2.
const fatalExceptions = {
  'EpubContainerException',
  'EpubPackageException',
  'EpubEncryptedException',
};

/// Casos em que o ZIP é deliberadamente inválido e o EOCD não existe.
const truncatedCases = {'patologia/arquivo-truncado'};

void main() {
  final root = Directory('test/corpus');
  final cases =
      root
          .listSync()
          .whereType<Directory>()
          .expand((group) => group.listSync().whereType<Directory>())
          .map(
            (d) => d.path.substring(root.path.length + 1).replaceAll(r'\', '/'),
          )
          .toList()
        ..sort();

  test('corpus tem os grupos da convenção e casos suficientes', () {
    final groups = cases.map((c) => c.split('/').first).toSet();
    expect(
      groups,
      containsAll([
        'regressoes',
        'estrutura',
        'conteudo',
        'faixa-b',
        'escrita',
        'patologia',
        'reais',
      ]),
    );
    expect(
      cases.length,
      greaterThanOrEqualTo(40),
      reason: 'doc/10 §1.1 pede 40 a 50 arquivos',
    );
  });

  for (final name in cases) {
    group(name, () {
      final dir = Directory('${root.path}/$name');
      final epub = File('${dir.path}/book.epub');
      final readme = File('${dir.path}/README.md');

      test('tem book.epub e README.md de uma linha', () {
        expect(epub.existsSync(), isTrue);
        expect(epub.lengthSync(), greaterThan(0));
        expect(readme.existsSync(), isTrue);
        final lines = readme
            .readAsLinesSync()
            .where((l) => l.trim().isNotEmpty)
            .toList();
        expect(
          lines,
          hasLength(1),
          reason: 'README deve ter exatamente uma linha',
        );
        if (name.startsWith('reais/')) {
          expect(
            lines.single,
            contains('https://'),
            reason: 'EPUB real precisa da URL de origem',
          );
        }
      });

      test(
        'ZIP começa com PK\\x03\\x04 e ${truncatedCases.contains(name) ? 'não ' : ''}tem EOCD',
        () {
          final bytes = epub.readAsBytesSync();
          expect(bytes.sublist(0, 4), equals([0x50, 0x4B, 0x03, 0x04]));
          final hasEocd = _hasEocd(bytes);
          expect(hasEocd, truncatedCases.contains(name) ? isFalse : isTrue);
        },
      );

      test('arquivos .expected são bem formados', () {
        final diag = File('${dir.path}/diagnostics.expected');
        if (diag.existsSync()) {
          final codes = diag
              .readAsLinesSync()
              .where((l) => l.isNotEmpty)
              .toList();
          expect(codes, isNotEmpty);
          expect(
            codes,
            equals([...codes]..sort()),
            reason: 'códigos em ordem alfabética',
          );
          expect(codes.toSet().length, codes.length, reason: 'sem duplicatas');
          for (final c in codes) {
            expect(
              knownDiagnostics,
              contains(c),
              reason: '"$c" não está em doc/09 §3',
            );
          }
        }
        final exc = File('${dir.path}/exception.expected');
        if (exc.existsSync()) {
          final lines = exc
              .readAsLinesSync()
              .where((l) => l.isNotEmpty)
              .toList();
          expect(lines, hasLength(1));
          expect(fatalExceptions, contains(lines.single));
          expect(
            diag.existsSync(),
            isFalse,
            reason: 'caso fatal não tem diagnósticos',
          );
        }
      });
    });
  }
}

/// Procura a assinatura do EOCD (`PK\x05\x06`) nos últimos 64 KB + 22 bytes.
bool _hasEocd(Uint8List bytes) {
  final start = bytes.length > 65557 ? bytes.length - 65557 : 0;
  for (var i = bytes.length - 22; i >= start; i--) {
    if (bytes[i] == 0x50 &&
        bytes[i + 1] == 0x4B &&
        bytes[i + 2] == 0x05 &&
        bytes[i + 3] == 0x06) {
      return true;
    }
  }
  return false;
}
