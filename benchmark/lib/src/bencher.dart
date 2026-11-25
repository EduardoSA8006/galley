import 'dart:io';

/// Projeto do Galley no Bencher.
const String bencherProject = 'galley';

/// Variável de ambiente com a chave de API do Bencher (lida pela própria
/// CLI). É a autenticação atual do Bencher: os antigos tokens
/// (`BENCHER_API_TOKEN`, `--token`) estão obsoletos e não podem mais ser
/// criados.
const String bencherKeyVariable = 'BENCHER_API_KEY';

/// Testbed da contagem de instruções (Valgrind), no PR e no noturno.
///
/// PR e noturno usam o mesmo testbed por tipo de medida: o histórico do
/// Bencher é indexado por branch × testbed, e só assim o `--start-point main`
/// do PR traz os pontos da `main`.
const String testbedValgrind = 'github-ubuntu-valgrind';

/// Testbed do A/B de tempo de parede, no PR e no noturno.
const String testbedAb = 'github-ubuntu-ab';

/// Testbed das medidas só do noturno (compare, size e wide).
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

/// Tamanho máximo do nome de branch enviado ao Bencher.
const int maxBencherBranchLength = 64;

final RegExp _branchUnsafe = RegExp(r'[^A-Za-z0-9._/-]');
final RegExp _branchLeading = RegExp(r'^[-.]+');

/// Normaliza [raw] (nome de branch do git) para um branch do Bencher.
///
/// Troca cada caractere fora de `[A-Za-z0-9._/-]` por `-`, remove hífens e
/// pontos iniciais (o nome nunca vira uma opção da CLI) e corta em
/// [maxBencherBranchLength] caracteres. Vazio, ou `HEAD` (checkout
/// destacado), vira `main`.
String sanitizeBencherBranch(String raw) {
  if (raw.trim() == 'HEAD') return 'main';
  var name = raw
      .replaceAll(_branchUnsafe, '-')
      .replaceFirst(_branchLeading, '');
  if (name.length > maxBencherBranchLength) {
    name = name.substring(0, maxBencherBranchLength);
  }
  return name.isEmpty ? 'main' : name;
}

/// Monta o comando `bencher run` do BMF [bmf] no testbed [testbed].
///
/// [branch], [startPoint] e [hash] (o commit medido) são opcionais. A chave
/// nunca entra na linha de comando: a CLI a lê de `BENCHER_API_KEY`.
List<String> bencherCommand({
  required String testbed,
  required File bmf,
  String? branch,
  String? startPoint,
  String? hash,
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
  if (hash != null) ...['--hash', hash],
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

/// Envia o BMF [bmf] ao Bencher (`bencher run`) no testbed [testbed], com
/// [branch], [startPoint] e o commit [hash] opcionais.
///
/// Sem `BENCHER_API_KEY` em [environment] (padrão: o ambiente do processo)
/// não executa nada e devolve [BencherStatus.skipped] com um aviso. [runner]
/// permite injetar a execução do processo nos testes.
Future<BencherOutcome> bencherRun({
  required String testbed,
  required File bmf,
  String? branch,
  String? startPoint,
  String? hash,
  Map<String, String>? environment,
  BencherProcessRunner? runner,
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
    hash: hash,
  );
  try {
    final code = await (runner ?? _defaultRunner)(command, {
      ...env,
      bencherKeyVariable: key,
    });
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
