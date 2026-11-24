import 'dart:async';

/// Contrato de um benchmark executado pelo `bench_runner`.
abstract interface class Bench {
  /// Identificador em kebab-case, ex.: `container/crc32-1mib`.
  String get id;

  /// Prepara os dados; não entra na medição.
  Future<void> setUp();

  /// Executa um ciclo de trabalho e devolve um checksum do resultado.
  ///
  /// Pode ser assíncrono (as APIs de zip e de abertura do livro são
  /// `Future`); o `bench_runner` aguarda o resultado. Uma exceção propaga e
  /// faz o runner sair com código 70.
  FutureOr<int> run();

  /// Libera os recursos criados em [setUp].
  Future<void> tearDown();
}
