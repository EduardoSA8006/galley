import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import 'manifest.dart';

/// Falha ao obter um livro do corpus: nenhuma fonte entregou o arquivo certo.
final class CorpusFetchException implements Exception {
  /// Cria a exceção para o livro [id] com a causa de cada tentativa.
  const CorpusFetchException(
    this.id,
    this.causes, {
    this.digestMismatch = false,
    this.retryAfter,
  });

  /// Identificador do livro.
  final String id;

  /// Causa de cada tentativa, na ordem (espelho, depois URL original).
  final List<String> causes;

  /// Se alguma fonte respondeu 200 com bytes de `sha256` diferente do
  /// esperado (a origem mudou o arquivo).
  final bool digestMismatch;

  /// Maior `Retry-After` pedido pelo servidor numa resposta 429/503 que o
  /// fetcher não esperou (por passar de `maxRetryAfter`).
  final Duration? retryAfter;

  @override
  String toString() => 'CorpusFetchException($id): ${causes.join('; ')}';
}

/// Falha de uma tentativa de download (interna).
final class _Failure implements Exception {
  _Failure(this.cause, {this.mismatch = false, this.retryAfter});

  final String cause;
  final bool mismatch;
  final Duration? retryAfter;
}

/// Obtém livros do corpus público com cache local e verificação de `sha256`.
///
/// Ordem: cache (`<cacheDir>/<sha256>.epub`) → `mirrorUrl` → `url`.
///
/// Os downloads têm prazos: [connectionTimeout] para conectar e
/// [requestTimeout] para a requisição inteira (cabeçalhos e corpo), então um
/// servidor que trava não prende a execução. Entre requisições de rede o
/// fetcher espera [pause] (gentileza com servidores) e honra `Retry-After`
/// de 429/503 até [maxRetryAfter] (uma nova tentativa); pedidos maiores
/// viram falha com [CorpusFetchException.retryAfter]. Chame [close] ao
/// terminar.
final class CorpusFetcher {
  /// Cria o fetcher que guarda os arquivos em [cacheDir].
  CorpusFetcher({
    required this.cacheDir,
    HttpClient? client,
    this.connectionTimeout = const Duration(seconds: 30),
    this.requestTimeout = const Duration(minutes: 5),
    this.pause = Duration.zero,
    this.maxRetryAfter = const Duration(minutes: 2),
  }) : _ownsClient = client == null,
       _client =
           client ??
           (HttpClient()
             ..userAgent = userAgent
             ..connectionTimeout = connectionTimeout);

  /// User-Agent genérico usado nas requisições.
  static const String userAgent =
      'galley-benchmark-corpus-fetcher/1 (+https://github.com/EduardoSA8006/galley)';

  /// Diretório do cache.
  final Directory cacheDir;

  /// Prazo para estabelecer a conexão.
  final Duration connectionTimeout;

  /// Prazo total de cada requisição, do envio ao último byte do corpo.
  final Duration requestTimeout;

  /// Pausa mínima entre o fim de uma requisição de rede e o começo da
  /// seguinte.
  final Duration pause;

  /// Maior `Retry-After` que o fetcher espera (uma vez) antes de repetir.
  final Duration maxRetryAfter;

  final HttpClient _client;
  final bool _ownsClient;
  DateTime? _lastRequestEnd;
  bool _swept = false;
  static int _tempCounter = 0;
  static const String _tempPrefix = 'download-';
  static const String _tempSuffix = '.part';

  /// Encerra o cliente HTTP (se foi criado aqui); pode ser chamado de novo.
  void close() {
    if (_ownsClient) _client.close(force: true);
  }

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
    var mismatch = false;
    Duration? retryAfter;
    for (final uri in [?e.mirrorUrl, e.url]) {
      try {
        await _download(uri, target, expected: e.sha256);
        return target;
      } on _Failure catch (f) {
        causes.add('$uri: ${f.cause}');
        mismatch = mismatch || f.mismatch;
        final r = f.retryAfter;
        if (r != null && (retryAfter == null || r > retryAfter)) retryAfter = r;
      }
    }
    throw CorpusFetchException(
      e.id,
      causes,
      digestMismatch: mismatch,
      retryAfter: retryAfter,
    );
  }

  /// Baixa [uri] sem `sha256` esperado, grava em `<cacheDir>/<sha256>.epub` e
  /// devolve o arquivo e o `sha256` calculado (para fixar um livro novo).
  ///
  /// Lança [CorpusFetchException] (com o [id]) se o download falhar.
  Future<({File file, String sha256})> pin(
    Uri uri, {
    required String id,
  }) async {
    await cacheDir.create(recursive: true);
    try {
      final sha = await _download(uri, null, expected: null);
      return (file: File('${cacheDir.path}/$sha.epub'), sha256: sha);
    } on _Failure catch (f) {
      throw CorpusFetchException(
        id,
        ['$uri: ${f.cause}'],
        digestMismatch: f.mismatch,
        retryAfter: f.retryAfter,
      );
    }
  }

  /// Baixa [uri] para [target] (sem verificar `sha256`; para arquivos que não
  /// são livros, como o catálogo) e devolve o `sha256`. [timeout] substitui
  /// o [requestTimeout] (arquivos grandes).
  Future<String> downloadTo(
    Uri uri,
    File target, {
    required String id,
    Duration? timeout,
  }) async {
    await target.parent.create(recursive: true);
    try {
      return await _download(uri, target, expected: null, timeout: timeout);
    } on _Failure catch (f) {
      throw CorpusFetchException(id, [
        '$uri: ${f.cause}',
      ], retryAfter: f.retryAfter);
    }
  }

  /// Baixa [uri] para [target] via arquivo temporário e devolve o `sha256`;
  /// lança [_Failure] com a causa. Aplica pausa, prazo e `Retry-After`.
  Future<String> _download(
    Uri uri,
    File? target, {
    required String? expected,
    Duration? timeout,
  }) async {
    var attempt = 0;
    while (true) {
      attempt++;
      try {
        return await _attempt(uri, target, expected, timeout ?? requestTimeout);
      } on _Failure catch (f) {
        final wait = f.retryAfter;
        if (attempt == 1 && wait != null && wait <= maxRetryAfter) {
          await Future<void>.delayed(wait);
          continue;
        }
        rethrow;
      }
    }
  }

  Future<String> _attempt(
    Uri uri,
    File? target,
    String? expected,
    Duration timeout,
  ) async {
    final last = _lastRequestEnd;
    if (last != null) {
      final wait = pause - DateTime.now().difference(last);
      if (!wait.isNegative) await Future<void>.delayed(wait);
    }
    await _sweepStaleTemps();
    final dir = target?.parent ?? cacheDir;
    final partial = File(
      '${dir.path}/$_tempPrefix${pid}_${_tempCounter++}$_tempSuffix',
    );
    HttpClientRequest? request;
    try {
      return await Future<String>(() async {
        request = await _client.getUrl(uri);
        final response = await request!.close();
        if (response.statusCode != HttpStatus.ok) {
          await response.drain<void>();
          Duration? retry;
          if (response.statusCode == HttpStatus.tooManyRequests ||
              response.statusCode == HttpStatus.serviceUnavailable) {
            retry = _parseRetryAfter(
              response.headers.value(HttpHeaders.retryAfterHeader),
            );
          }
          throw _Failure(
            'HTTP ${response.statusCode}'
            '${retry == null ? '' : ' (Retry-After ${retry.inSeconds} s)'}',
            retryAfter: retry,
          );
        }
        await response.pipe(partial.openWrite());
        final actual = await _digest(partial);
        if (expected != null && actual != expected) {
          throw _Failure(
            'sha256 mismatch (esperado $expected, obtido $actual)',
            mismatch: true,
          );
        }
        await partial.rename(target?.path ?? '${cacheDir.path}/$actual.epub');
        return actual;
      }).timeout(timeout);
    } on TimeoutException {
      try {
        request?.abort();
      } on Object {
        // Já concluída ou fechada.
      }
      throw _Failure('tempo esgotado (${timeout.inMilliseconds} ms)');
    } on _Failure {
      rethrow;
    } on Object catch (error) {
      throw _Failure(error.toString());
    } finally {
      _lastRequestEnd = DateTime.now();
      if (partial.existsSync()) {
        try {
          await partial.delete();
        } on Object {
          // Será sobrescrito na próxima tentativa.
        }
      }
    }
  }

  /// Apaga `*.part` de execuções interrompidas (com mais de 2 h) do cache;
  /// roda uma vez por fetcher.
  Future<void> _sweepStaleTemps() async {
    if (_swept) return;
    _swept = true;
    try {
      final limit = DateTime.now().subtract(const Duration(hours: 2));
      await for (final e in cacheDir.list()) {
        if (e is File &&
            e.path.endsWith(_tempSuffix) &&
            (await e.lastModified()).isBefore(limit)) {
          await e.delete();
        }
      }
    } on Object {
      // Limpeza é só higiene.
    }
  }

  /// `Retry-After` em segundos ou como data HTTP; `null` se ausente ou
  /// inválido. Datas no passado viram zero.
  static Duration? _parseRetryAfter(String? value) {
    if (value == null) return null;
    final seconds = int.tryParse(value.trim());
    if (seconds != null) return Duration(seconds: seconds < 0 ? 0 : seconds);
    try {
      final wait = HttpDate.parse(value.trim()).difference(DateTime.now());
      return wait.isNegative ? Duration.zero : wait;
    } on Object {
      return null;
    }
  }

  static Future<String> _digest(File file) async =>
      (await crypto.sha256.bind(file.openRead()).single).toString();
}
