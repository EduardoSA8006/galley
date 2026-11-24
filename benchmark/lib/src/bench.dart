/// Contrato de um benchmark executado pelo `bench_runner`.
abstract interface class Bench {
  /// Identificador em kebab-case, ex.: `container/crc32-1mib`.
  String get id;

  /// Prepara os dados; não entra na medição.
  Future<void> setUp();

  /// Executa um ciclo de trabalho e devolve um checksum do resultado.
  int run();

  /// Libera os recursos criados em [setUp].
  Future<void> tearDown();
}
