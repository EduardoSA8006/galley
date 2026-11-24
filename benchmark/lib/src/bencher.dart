/// Envia o BMF de [bmfPath] ao Bencher (`bencher run`) no testbed [testbed].
///
/// Ainda é um stub: a implementação real é da Task 10. Por ora avisa em
/// [log] e devolve 0.
Future<int> bencherRun({
  required String bmfPath,
  required String testbed,
  required StringSink log,
}) async {
  log.writeln('upload ao Bencher ainda não disponível (Task 10)');
  return 0;
}
