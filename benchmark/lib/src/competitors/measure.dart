import '../peak_rss.dart';
import 'adapter.dart';

/// Código de saída quando a medição falha (EX_SOFTWARE).
const int exitMeasureFailure = 70;

/// Código de saída para argumentos inválidos (EX_USAGE).
const int exitMeasureUsage = 64;

/// Métricas aceitas por [runAdapterMeasure].
const List<String> measureKinds = [
  'open',
  'open-eager',
  'read-all',
  'read-one',
];

/// Mede [kind] com [adapter] em [path] e escreve `ns=`, `rss=` e `checksum=`
/// em [out].
///
/// O contrato é o mesmo do `bench_runner --adapter`, em cada processo:
/// - `open`: `ns` é o tempo de `open` (preguiçoso); `checksum` é
///   `spineLength`.
/// - `open-eager`: `ns` é o tempo de `openEager` (livro inteiro na memória);
///   `checksum` é `spineLength`.
/// - `read-all`: `ns` é `open` + `readAllSpine` (do arquivo aos bytes);
///   `checksum` é a soma dos bytes.
/// - `read-one`: `ns` é `open` + `readOne([resource])`; `checksum` é o
///   tamanho do recurso. Exige [resource].
///
/// `rss` é o pico (`peakRssBytes`, `VmHWM`) lido no fim. O tempo exclui o
/// `close`. Devolve 0, [exitMeasureUsage] ou [exitMeasureFailure] (exceção do
/// adaptador, com a mensagem em [err] dizendo a operação exata que falhou).
Future<int> runAdapterMeasure(
  ParserAdapter adapter,
  String kind,
  String path, {
  String? resource,
  required StringSink out,
  required StringSink err,
}) async {
  if (!measureKinds.contains(kind)) {
    err.writeln('Medida desconhecida: $kind (use ${measureKinds.join(', ')})');
    return exitMeasureUsage;
  }
  if (kind == 'read-one' && resource == null) {
    err.writeln('read-one exige --resource');
    return exitMeasureUsage;
  }
  final clock = Stopwatch()..start();
  int checksum;
  var phase = 'open';
  try {
    try {
      if (kind == 'open-eager') {
        phase = 'openEager';
        await adapter.openEager(path);
      } else {
        await adapter.open(path);
      }
      if (kind == 'open' || kind == 'open-eager') {
        checksum = adapter.spineLength;
      } else if (kind == 'read-all') {
        phase = 'readAllSpine';
        checksum = await adapter.readAllSpine();
      } else {
        phase = 'readOne($resource)';
        checksum = await adapter.readOne(resource!);
      }
      clock.stop();
    } finally {
      await adapter.close();
    }
  } on Object catch (e, st) {
    err.writeln('Falha em ${adapter.name} ($kind) na operação $phase: $e\n$st');
    return exitMeasureFailure;
  }
  final ns = (clock.elapsedTicks * 1e9 / clock.frequency).round();
  out
    ..writeln('ns=$ns')
    ..writeln('rss=${peakRssBytes()}')
    ..writeln('checksum=$checksum');
  return 0;
}
