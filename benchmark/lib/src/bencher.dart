import 'dart:io';

/// Projeto do Galley no Bencher.
const String bencherProject = 'galley';

/// Variável de ambiente com a chave de API do Bencher (lida pela própria
/// CLI). É a autenticação atual do Bencher: os antigos tokens
/// (`BENCHER_API_TOKEN`, `--token`) estão obsoletos e não podem mais ser
/// criados.
const String bencherKeyVariable = 'BENCHER_API_KEY';

/// Testbed do job de PR com contagem de instruções (Valgrind).
const String testbedValgrind = 'github-ubuntu-valgrind';

/// Testbed do job de PR com A/B de tempo de parede.
const String testbedAb = 'github-ubuntu-ab';

/// Testbed do job noturno (compare, size, instruções e A/B longo).
const String testbedNightly = 'github-ubuntu-nightly';

/// Testbed das medições manuais da máquina do mantenedor.
const String testbedLocal = 'local-dev';

/// Resultado de um envio ao Bencher.
enum BencherStatus {
  /// O `bencher run` terminou com sucesso.
  uploaded,

  /// Não havia chave: nada foi executado (não é falha).
  skipped,

  /// A CLI falhou, não está instalada ou saiu com código diferente de 0.
  failed,
}

/// Desfecho de [bencherRun].
final class BencherOutcome {
  /// Cria o desfecho.
  const BencherOutcome(this.status, this.exitCode, this.message);

  /// Como terminou.
  final BencherStatus status;

  /// Código de saída a repassar ao chamador (0 se enviado ou pulado).
  final int exitCode;

  /// Explicação legível (aviso de salto ou motivo da falha).
  final String message;
}

/// Executa [command] com [environment] e devolve o código de saída.
typedef BencherProcessRunner = Future<int> Function(
  List<String> command,
  Map<String, String> environment,
);

/// Monta o comando `bencher run` do BMF [bmf] no testbed [testbed].
///
/// [branch] e [startPoint] são opcionais. A chave nunca entra na linha de
/// comando: a CLI a lê de `BENCHER_API_KEY`.
List<String> bencherCommand({
  required String testbed,
  required File bmf,
  String? branch,
  String? startPoint,
}) => [
  'bencher',
  'run',
  '--project',
  bencherProject,
  '--testbed',
  testbed,
  '--adapter',
  'json',
  '--file',
  bmf.path,
  if (branch != null) ...['--branch', branch],
  if (startPoint != null) ...['--start-point', startPoint],
];

Future<int> _defaultRunner(
  List<String> command,
  Map<String, String> environment,
) async {
  final p = await Process.start(
    command.first,
    command.sublist(1),
    environment: environment,
    mode: ProcessStartMode.inheritStdio,
  );
  return p.exitCode;
}

/// Envia o BMF [bmf] ao Bencher (`bencher run`) no testbed [testbed].
///
/// Sem `BENCHER_API_KEY` em [environment] (padrão: o ambiente do processo)
/// não executa nada e devolve [BencherStatus.skipped] com um aviso. [runner]
/// permite injetar a execução do processo nos testes.
Future<BencherOutcome> bencherRun({
  required String testbed,
  required File bmf,
  String? branch,
  String? startPoint,
  Map<String, String>? environment,
  BencherProcessRunner runner = _defaultRunner,
}) async {
  final env = environment ?? Platform.environment;
  final key = env[bencherKeyVariable];
  if (key == null || key.isEmpty) {
    return const BencherOutcome(
      BencherStatus.skipped,
      0,
      'upload ao Bencher pulado: $bencherKeyVariable não está definido',
    );
  }
  final command = bencherCommand(
    testbed: testbed,
    bmf: bmf,
    branch: branch,
    startPoint: startPoint,
  );
  try {
    final code = await runner(command, {...env, bencherKeyVariable: key});
    return code == 0
        ? const BencherOutcome(BencherStatus.uploaded, 0, 'enviado ao Bencher')
        : BencherOutcome(
            BencherStatus.failed,
            code,
            'bencher run saiu com código $code',
          );
  } on ProcessException catch (e) {
    return BencherOutcome(
      BencherStatus.failed,
      1,
      'não foi possível executar a CLI bencher: ${e.message}',
    );
  }
}
