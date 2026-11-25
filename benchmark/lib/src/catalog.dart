import 'bench.dart';
import 'suites/container_macro.dart';
import 'suites/container_micro.dart';
import 'suites/document_suites.dart';
import 'suites/style_suites.dart';

/// Benchmark vazio, usado para descontar a partida do processo.
final class NoopBench implements Bench {
  /// Cria o benchmark vazio.
  const NoopBench();

  @override
  String get id => 'harness/noop';

  @override
  Future<void> setUp() async {}

  @override
  int run() => 0;

  @override
  Future<void> tearDown() async {}
}

/// Catálogo de todos os benchmarks disponíveis.
final class Catalog {
  Catalog._();

  /// Todos os benchmarks registrados.
  static List<Bench> all() => <Bench>[
    const NoopBench(),
    ...containerMicroBenches(),
    ...containerMacroBenches(),
    ...documentBenches(),
    ...styleBenches(),
  ];

  /// Devolve o benchmark de [id]; lança [ArgumentError] se não existir.
  static Bench byId(String id) {
    for (final bench in all()) {
      if (bench.id == id) return bench;
    }
    throw ArgumentError.value(id, 'id', 'benchmark desconhecido');
  }
}
