/// Diagnósticos (doc/09 §3) e o coletor usado por todas as camadas.
library;

import 'exceptions.dart';

enum EpubSeverity { info, warning }

/// Classe com constantes, não enum: cresce sem quebrar consumidores
/// (doc/11 §3.3). Compare por identidade ou por [name].
final class EpubDiagnosticCode {
  const EpubDiagnosticCode._(this.name, this.defaultSeverity);

  final String name;
  final EpubSeverity defaultSeverity;

  /// `mimetype` ausente, fora do lugar, comprimido, com conteúdo errado,
  /// ilegível, ou ZIP com prefixo. `details.reason` diz qual.
  static const mimetypeIrregular = EpubDiagnosticCode._(
    'mimetypeIrregular',
    EpubSeverity.info,
  );

  /// CRC-32 divergente (`reason: 'crc'`) ou saída menor que a declarada
  /// (`reason: 'size'`).
  static const zipCrcMismatch = EpubDiagnosticCode._(
    'zipCrcMismatch',
    EpubSeverity.warning,
  );

  /// Nome repetido no central directory; vale a primeira entrada.
  static const zipDuplicateEntry = EpubDiagnosticCode._(
    'zipDuplicateEntry',
    EpubSeverity.info,
  );

  /// Caminho achado só sem diferenciar maiúsculas; `details.actual`.
  static const pathCaseMismatch = EpubDiagnosticCode._(
    'pathCaseMismatch',
    EpubSeverity.info,
  );

  /// Fonte com ofuscação não reconhecida ou sem chave utilizável.
  static const fontObfuscationUnknown = EpubDiagnosticCode._(
    'fontObfuscationUnknown',
    EpubSeverity.warning,
  );

  /// `encryption.xml` inválido num livro servido por provider.
  static const encryptionIgnored = EpubDiagnosticCode._(
    'encryptionIgnored',
    EpubSeverity.info,
  );

  /// Entrada ilegível convertida em placeholder (sub-projetos 2 e 4).
  static const resourceUnreadable = EpubDiagnosticCode._(
    'resourceUnreadable',
    EpubSeverity.warning,
  );

  @override
  String toString() => name;
}

/// Diagnóstico imutável; [details] é unmodifiable.
final class EpubDiagnostic {
  EpubDiagnostic({
    required this.code,
    required this.severity,
    required this.message,
    this.href,
    this.charOffset,
    Map<String, Object?> details = const {},
  }) : details = Map.unmodifiable(details);

  final EpubDiagnosticCode code;
  final EpubSeverity severity;
  final String? href;
  final int? charOffset;
  final String message;
  final Map<String, Object?> details;

  @override
  String toString() =>
      'EpubDiagnostic(${code.name}, ${severity.name}'
      '${href == null ? '' : ', $href'}): $message';
}

/// Coletor de diagnósticos de um documento. Deduplica por `(code, href)` e,
/// em [strict], transforma `warning` em exceção (doc/09 §5).
final class DiagnosticSink {
  DiagnosticSink({this.strict = false});

  final bool strict;

  final List<EpubDiagnostic> _items = [];
  final Map<(String, String?), int> _index = {};

  /// Em ordem de primeira emissão.
  List<EpubDiagnostic> get diagnostics => List.unmodifiable(_items);

  /// Registra um diagnóstico. A repetição de `(code, href)` substitui a
  /// instância anterior, na mesma posição, com `details['count']` somado.
  ///
  /// Em [strict], `mimetypeIrregular` sobe para `warning`, e todo `warning` é
  /// registrado e depois lançado como a exceção de [onStrict] (padrão:
  /// [EpubContainerException] com [href]), com o nome do código na mensagem.
  void emit(
    EpubDiagnosticCode code, {
    required String message,
    String? href,
    Map<String, Object?> details = const {},
    EpubSeverity? severity,
    EpubException Function(String message)? onStrict,
  }) {
    var effective = severity ?? code.defaultSeverity;
    if (strict && identical(code, EpubDiagnosticCode.mimetypeIrregular)) {
      effective = EpubSeverity.warning;
    }
    final key = (code.name, href);
    final at = _index[key];
    final previous = at == null ? 0 : (_items[at].details['count']! as int);
    final diagnostic = EpubDiagnostic(
      code: code,
      severity: effective,
      href: href,
      message: message,
      details: {...details, 'count': previous + 1},
    );
    if (at == null) {
      _index[key] = _items.length;
      _items.add(diagnostic);
    } else {
      _items[at] = diagnostic;
    }
    if (strict && effective == EpubSeverity.warning) {
      final text = '${code.name}: $message';
      throw (onStrict ?? (m) => EpubContainerException(m, href: href))(text);
    }
  }
}
