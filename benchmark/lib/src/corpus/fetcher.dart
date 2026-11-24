import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import 'manifest.dart';

/// Falha ao obter um livro do corpus: nenhuma fonte entregou o arquivo certo.
final class CorpusFetchException implements Exception {
  /// Cria a exceção para o livro [id] com a causa de cada tentativa.
  const CorpusFetchException(this.id, this.causes);

  /// Identificador do livro.
  final String id;

  /// Causa de cada tentativa, na ordem (espelho, depois URL original).
  final List<String> causes;

  @override
  String toString() => 'CorpusFetchException($id): ${causes.join('; ')}';
}

/// Obtém livros do corpus público com cache local e verificação de `sha256`.
///
/// Ordem: cache (`<cacheDir>/<sha256>.epub`) → `mirrorUrl` → `url`.
final class CorpusFetcher {
  /// Cria o fetcher que guarda os arquivos em [cacheDir].
  CorpusFetcher({required this.cacheDir, HttpClient? client})
    : _client = client ?? (HttpClient()..userAgent = userAgent);

  /// User-Agent genérico usado nas requisições.
  static const String userAgent =
      'galley-benchmark-corpus-fetcher/1 (+https://github.com/EduardoSA8006/galley)';

  /// Diretório do cache.
  final Directory cacheDir;

  final HttpClient _client;

  /// Devolve o arquivo local de [e], baixando-o se preciso.
  ///
  /// Lança [CorpusFetchException] se nenhuma fonte entregar bytes com o
  /// `sha256` esperado.
  Future<File> fetch(CorpusEntry e) async {
    final target = File('${cacheDir.path}/${e.sha256}.epub');
    if (target.existsSync()) {
      if (await _digest(target) == e.sha256) return target;
      await target.delete();
    }
    await cacheDir.create(recursive: true);

    final causes = <String>[];
    for (final uri in [?e.mirrorUrl, e.url]) {
      final cause = await _download(uri, target, e.sha256);
      if (cause == null) return target;
      causes.add('$uri: $cause');
    }
    throw CorpusFetchException(e.id, causes);
  }

  /// Baixa [uri] para [target] via arquivo temporário; devolve `null` em caso
  /// de sucesso ou a causa da falha.
  Future<String?> _download(Uri uri, File target, String expected) async {
    final partial = File('${target.path}.part');
    try {
      final request = await _client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return 'HTTP ${response.statusCode}';
      }
      await response.pipe(partial.openWrite());
      final actual = await _digest(partial);
      if (actual != expected) {
        await partial.delete();
        return 'sha256 mismatch (esperado $expected, obtido $actual)';
      }
      await partial.rename(target.path);
      return null;
    } on Object catch (error) {
      if (partial.existsSync()) await partial.delete();
      return error.toString();
    }
  }

  static Future<String> _digest(File file) async =>
      (await crypto.sha256.bind(file.openRead()).single).toString();
}
