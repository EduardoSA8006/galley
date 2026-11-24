import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

/// Variável de ambiente com o diretório do corpus privado (EPUBs do
/// mantenedor que nunca saem da máquina).
const String privateCorpusVariable = 'GALLEY_PRIVATE_CORPUS';

/// Aviso quando não há corpus privado para medir.
const String privateCorpusMissingWarning =
    '$privateCorpusVariable ausente ou inválida: corpus privado não medido.';

/// Identificador anônimo de [f]: os 12 primeiros hexadecimais do `sha256` do
/// conteúdo.
///
/// Só o conteúdo entra no cálculo (nome e caminho não), então o id é estável
/// e é o único jeito de um livro privado aparecer em relatórios e no BMF.
String anonymousId(File f) {
  final output = _DigestSink();
  final input = crypto.sha256.startChunkedConversion(output);
  final raf = f.openSync();
  try {
    final buffer = List<int>.filled(1 << 20, 0);
    while (true) {
      final n = raf.readIntoSync(buffer);
      if (n == 0) break;
      input.add(n == buffer.length ? buffer : buffer.sublist(0, n));
    }
  } finally {
    raf.closeSync();
  }
  input.close();
  return output.value.toString().substring(0, 12);
}

final class _DigestSink implements Sink<crypto.Digest> {
  late crypto.Digest value;

  @override
  void add(crypto.Digest data) => value = data;

  @override
  void close() {}
}

/// Lista os `.epub` (recursivamente) do diretório em [privateCorpusVariable].
///
/// Variável ausente ou diretório inexistente devolvem uma lista vazia e
/// chamam [onWarning] (padrão: stderr) com [privateCorpusMissingWarning], que
/// não cita o caminho. [environment] padrão: o do processo.
Future<List<File>> listPrivateCorpus({
  Map<String, String>? environment,
  void Function(String)? onWarning,
}) async {
  void warn(String m) => (onWarning ?? stderr.writeln)(m);
  final path = (environment ?? Platform.environment)[privateCorpusVariable];
  if (path == null || path.isEmpty || !Directory(path).existsSync()) {
    warn(privateCorpusMissingWarning);
    return const [];
  }
  final files = [
    await for (final e in Directory(path).list(recursive: true))
      if (e is File && e.path.toLowerCase().endsWith('.epub')) e,
  ]..sort((a, b) => a.path.compareTo(b.path));
  return files;
}
