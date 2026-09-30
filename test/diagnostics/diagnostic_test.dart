// Exceções e DiagnosticSink (spec do contêiner §8).
import 'package:flutter_test/flutter_test.dart';
import 'package:galley/src/diagnostics/diagnostic.dart';
import 'package:galley/src/diagnostics/exceptions.dart';

void main() {
  group('EpubException', () {
    test('toString com e sem href', () {
      expect(
        EpubContainerException('CRC divergente', href: 'a.xhtml').toString(),
        'EpubContainerException(a.xhtml): CRC divergente',
      );
      expect(
        EpubContainerException('EOCD não encontrado').toString(),
        'EpubContainerException: EOCD não encontrado',
      );
      expect(
        EpubEncryptedException('DRM lcp', scheme: 'lcp').toString(),
        'EpubEncryptedException: DRM lcp',
      );
    });

    test('guarda cause e scheme', () {
      const cause = FormatException('ruim');
      final e = EpubEncryptedException(
        'encryption.xml inválido',
        scheme: 'unknown:encryption.xml-invalido',
        cause: cause,
      );
      expect(e.cause, same(cause));
      expect(e.scheme, 'unknown:encryption.xml-invalido');
      expect(e, isA<EpubException>());
    });
  });

  group('EpubDiagnosticCode', () {
    test('sete códigos com a severidade padrão da spec', () {
      final codes = {
        EpubDiagnosticCode.mimetypeIrregular: EpubSeverity.info,
        EpubDiagnosticCode.zipCrcMismatch: EpubSeverity.warning,
        EpubDiagnosticCode.zipDuplicateEntry: EpubSeverity.info,
        EpubDiagnosticCode.pathCaseMismatch: EpubSeverity.info,
        EpubDiagnosticCode.fontObfuscationUnknown: EpubSeverity.warning,
        EpubDiagnosticCode.encryptionIgnored: EpubSeverity.info,
        EpubDiagnosticCode.resourceUnreadable: EpubSeverity.warning,
      };
      for (final MapEntry(key: code, value: severity) in codes.entries) {
        expect(code.defaultSeverity, severity, reason: code.name);
      }
      expect(codes.keys.map((c) => c.name).toSet(), {
        'mimetypeIrregular',
        'zipCrcMismatch',
        'zipDuplicateEntry',
        'pathCaseMismatch',
        'fontObfuscationUnknown',
        'encryptionIgnored',
        'resourceUnreadable',
      });
    });
  });

  group('códigos da Publicação', () {
    test('oito códigos com a severidade de doc/09 §3', () {
      final codes = {
        EpubDiagnosticCode.resourceMissing: EpubSeverity.warning,
        EpubDiagnosticCode.spineItemUnresolved: EpubSeverity.warning,
        EpubDiagnosticCode.unsupportedMediaType: EpubSeverity.warning,
        EpubDiagnosticCode.encodingFallback: EpubSeverity.info,
        EpubDiagnosticCode.tocReconciled: EpubSeverity.info,
        EpubDiagnosticCode.coverHeuristic: EpubSeverity.info,
        EpubDiagnosticCode.navIgnored: EpubSeverity.info,
        EpubDiagnosticCode.spineItemDuplicate: EpubSeverity.info,
      };
      for (final MapEntry(key: code, value: severity) in codes.entries) {
        expect(code.defaultSeverity, severity, reason: code.name);
        expect(code.toString(), code.name);
      }
      expect(codes.keys.map((c) => c.name).toSet(), {
        'resourceMissing',
        'spineItemUnresolved',
        'unsupportedMediaType',
        'encodingFallback',
        'tocReconciled',
        'coverHeuristic',
        'navIgnored',
        'spineItemDuplicate',
      });
    });

    test('EpubPackageException: toString, href e cause', () {
      const cause = FormatException('xml');
      final e = EpubPackageException(
        'OPF ausente',
        href: 'a.opf',
        cause: cause,
      );
      expect(e.toString(), 'EpubPackageException(a.opf): OPF ausente');
      expect(e.cause, same(cause));
      expect(e, isA<EpubException>());
    });

    test('strict: onStrict da Publicação lança EpubPackageException', () {
      final sink = DiagnosticSink(strict: true);
      expect(
        () => sink.emit(
          EpubDiagnosticCode.resourceMissing,
          href: 'OEBPS/a.xhtml',
          message: 'sem arquivo',
          onStrict: (m) => EpubPackageException(m, href: 'OEBPS/a.xhtml'),
        ),
        throwsA(
          isA<EpubPackageException>().having(
            (e) => e.message,
            'message',
            'resourceMissing: sem arquivo',
          ),
        ),
      );
    });
  });

  group('códigos e exceção do CSS', () {
    test(
      'quatro códigos com a severidade de doc/09 §3 e spec do CSS §12.1',
      () {
        final codes = {
          EpubDiagnosticCode.unsupportedLayout: EpubSeverity.warning,
          EpubDiagnosticCode.stylesheetIgnored: EpubSeverity.warning,
          EpubDiagnosticCode.stylesheetMediaIgnored: EpubSeverity.info,
          EpubDiagnosticCode.cssRuleIgnored: EpubSeverity.info,
        };
        for (final MapEntry(key: code, value: severity) in codes.entries) {
          expect(code.defaultSeverity, severity, reason: code.name);
          expect(code.toString(), code.name);
        }
        expect(codes.keys.map((c) => c.name).toSet(), {
          'unsupportedLayout',
          'stylesheetIgnored',
          'stylesheetMediaIgnored',
          'cssRuleIgnored',
        });
      },
    );

    test('EpubSectionParseException: toString, href e cause', () {
      const cause = FormatException('css');
      final e = EpubSectionParseException(
        'folha ilegível',
        href: 'OEBPS/Text/c.xhtml',
        cause: cause,
      );
      expect(
        e.toString(),
        'EpubSectionParseException(OEBPS/Text/c.xhtml): folha ilegível',
      );
      expect(e.cause, same(cause));
      expect(e, isA<EpubException>());
    });

    test(
      'strict: warning do CSS lança EpubSectionParseException; info não',
      () {
        final sink = DiagnosticSink(strict: true);
        EpubException onStrict(String m) =>
            EpubSectionParseException(m, href: 'c.xhtml');
        sink.emit(
          EpubDiagnosticCode.cssRuleIgnored,
          href: 'a.css',
          message: 'regra ignorada',
          onStrict: onStrict,
        );
        sink.emit(
          EpubDiagnosticCode.stylesheetMediaIgnored,
          href: 'a.css',
          message: 'print',
          onStrict: onStrict,
        );
        sink.emit(
          EpubDiagnosticCode.cssRuleIgnored,
          href: 'a.css',
          message: 'outra regra ignorada',
          onStrict: onStrict,
        );
        // Em strict o info continua info, registrado e somado, sem lançar.
        expect(sink.diagnostics, hasLength(2));
        final [rule, media] = sink.diagnostics;
        expect(rule.code, EpubDiagnosticCode.cssRuleIgnored);
        expect(rule.severity, EpubSeverity.info);
        expect(rule.details['count'], 2);
        expect(media.code, EpubDiagnosticCode.stylesheetMediaIgnored);
        expect(media.severity, EpubSeverity.info);
        expect(media.details['count'], 1);
        expect(sink.lastStrictException, isNull);
        expect(
          () => sink.emit(
            EpubDiagnosticCode.stylesheetIgnored,
            href: 'a.css',
            message: 'ciclo',
            onStrict: onStrict,
          ),
          throwsA(
            isA<EpubSectionParseException>().having(
              (e) => e.message,
              'message',
              'stylesheetIgnored: ciclo',
            ),
          ),
        );
        expect(sink.lastStrictException, isA<EpubSectionParseException>());
      },
    );
  });

  group('EpubDiagnostic', () {
    test('details é unmodifiable', () {
      final d = EpubDiagnostic(
        code: EpubDiagnosticCode.pathCaseMismatch,
        severity: EpubSeverity.info,
        message: 'caixa',
        details: {'actual': 'A.xhtml'},
      );
      expect(() => d.details['x'] = 1, throwsUnsupportedError);
    });
  });

  group('DiagnosticSink', () {
    test('primeira emissão tem count 1 e a severidade padrão', () {
      final sink = DiagnosticSink()
        ..emit(
          EpubDiagnosticCode.zipDuplicateEntry,
          href: 'a.xhtml',
          message: 'duplicada',
          details: {'index': 3},
        );
      final d = sink.diagnostics.single;
      expect(d.severity, EpubSeverity.info);
      expect(d.details, {'index': 3, 'count': 1});
    });

    test(
      'dedupe por (code, href): substitui na mesma posição e soma count',
      () {
        final sink = DiagnosticSink()
          ..emit(EpubDiagnosticCode.pathCaseMismatch, href: 'a', message: '1')
          ..emit(EpubDiagnosticCode.zipDuplicateEntry, href: 'a', message: '2')
          ..emit(
            EpubDiagnosticCode.pathCaseMismatch,
            href: 'a',
            message: '3',
            details: {'actual': 'A'},
          )
          ..emit(EpubDiagnosticCode.pathCaseMismatch, href: 'b', message: '4');
        final ds = sink.diagnostics;
        expect(ds.map((d) => d.message), ['3', '2', '4']);
        expect(ds[0].details, {'actual': 'A', 'count': 2});
        expect(ds[2].details['count'], 1);
      },
    );

    test('severity explícita vence a padrão', () {
      final sink = DiagnosticSink()
        ..emit(
          EpubDiagnosticCode.zipDuplicateEntry,
          message: 'x',
          severity: EpubSeverity.warning,
        );
      expect(sink.diagnostics.single.severity, EpubSeverity.warning);
    });

    test('fora de strict, warning não lança', () {
      final sink = DiagnosticSink()
        ..emit(EpubDiagnosticCode.zipCrcMismatch, href: 'a', message: 'crc');
      expect(sink.diagnostics.single.severity, EpubSeverity.warning);
    });

    test(
      'strict registra e depois lança EpubContainerException em warning',
      () {
        final sink = DiagnosticSink(strict: true);
        expect(
          () => sink.emit(
            EpubDiagnosticCode.zipCrcMismatch,
            href: 'a.xhtml',
            message: 'CRC divergente',
          ),
          throwsA(
            isA<EpubContainerException>()
                .having((e) => e.href, 'href', 'a.xhtml')
                .having(
                  (e) => e.message,
                  'message',
                  contains('zipCrcMismatch'),
                ),
          ),
        );
        expect(sink.diagnostics.single.code, EpubDiagnosticCode.zipCrcMismatch);
      },
    );

    test('strict usa onStrict quando informado', () {
      final sink = DiagnosticSink(strict: true);
      expect(
        () => sink.emit(
          EpubDiagnosticCode.fontObfuscationUnknown,
          message: 'fonte',
          onStrict: (m) => EpubEncryptedException(m, scheme: 'teste'),
        ),
        throwsA(
          isA<EpubEncryptedException>().having(
            (e) => e.message,
            'message',
            'fontObfuscationUnknown: fonte',
          ),
        ),
      );
    });

    test('lastStrictException é a instância lançada, e só em strict', () {
      final relaxed = DiagnosticSink()
        ..emit(EpubDiagnosticCode.zipCrcMismatch, href: 'a', message: 'crc');
      expect(relaxed.lastStrictException, isNull);

      final sink = DiagnosticSink(strict: true)
        ..emit(EpubDiagnosticCode.pathCaseMismatch, href: 'a', message: 'i');
      expect(sink.lastStrictException, isNull, reason: 'info não lança');
      Object? thrown;
      try {
        sink.emit(
          EpubDiagnosticCode.fontObfuscationUnknown,
          message: 'fonte',
          onStrict: (m) => EpubEncryptedException(m, scheme: 'teste'),
        );
      } on EpubException catch (e) {
        thrown = e;
      }
      expect(thrown, isNotNull);
      expect(identical(sink.lastStrictException, thrown), isTrue);
    });

    test('strict: info nunca lança', () {
      final sink = DiagnosticSink(strict: true)
        ..emit(EpubDiagnosticCode.zipDuplicateEntry, message: 'x')
        ..emit(EpubDiagnosticCode.pathCaseMismatch, message: 'y')
        ..emit(EpubDiagnosticCode.encryptionIgnored, message: 'z');
      expect(sink.diagnostics, hasLength(3));
    });

    test('strict promove mimetypeIrregular a warning e lança', () {
      final sink = DiagnosticSink(strict: true);
      expect(
        () => sink.emit(EpubDiagnosticCode.mimetypeIrregular, message: 'm'),
        throwsA(isA<EpubContainerException>()),
      );
      expect(sink.diagnostics.single.severity, EpubSeverity.warning);
      final relaxed = DiagnosticSink()
        ..emit(EpubDiagnosticCode.mimetypeIrregular, message: 'm');
      expect(relaxed.diagnostics.single.severity, EpubSeverity.info);
    });

    test('diagnostics devolvido não altera o sink', () {
      final sink = DiagnosticSink()
        ..emit(EpubDiagnosticCode.zipDuplicateEntry, message: 'x');
      expect(() => sink.diagnostics.clear(), throwsUnsupportedError);
    });
  });
}
