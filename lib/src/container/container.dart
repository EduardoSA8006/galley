/// Contêiner de recursos: a interface interna que a Publicação e a IR usam,
/// com duas implementações (`ZipContainer` e `ProviderContainer`).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../diagnostics/diagnostic.dart';
import '../diagnostics/exceptions.dart';
import 'inflate/inflate.dart';
import 'zip/crc32.dart';

/// Maior entrada aceita, descomprimida. Proteção contra zip bomb.
const int maxEntrySize = 256 * 1024 * 1024;

/// Teto dos arquivos de metadado do contêiner (`encryption.xml`,
/// `rights.xml`): os reais têm poucos KiB, e ler ou parsear um maior seria
/// só custo pago para um atacante.
const int maxMetadataSize = 4 * 1024 * 1024;

/// Um passo do `decode()` a cada 64 KiB completos de saída.
const int decodeStepBytes = 64 * 1024;

/// A entrada comprimida vai ao decoder em fatias de no máximo 16 KiB.
const int inflateSliceBytes = 16 * 1024;

enum FontObfuscation { idpf, adobe, unknown }

abstract interface class EpubContainer {
  /// Caminhos de arquivo presentes (sem diretórios), na ordem do contêiner.
  Iterable<String> get paths;

  /// Caminho existe: exato, senão sem diferenciar maiúsculas. Não emite
  /// diagnóstico (quem emite é [fetch]).
  Future<bool> exists(String path);

  /// Busca os bytes crus numa ida à fonte. `null` se ausente.
  /// [EpubContainerException] com `href: path` se a entrada não é legível.
  Future<PendingResource?> fetch(String path);

  /// Ofuscação de fonte declarada para o caminho (resolvido pelo mesmo
  /// índice de [fetch]).
  FontObfuscation? obfuscationOf(String path);

  /// Fecha a fonte: o contêiner é dono dela. Idempotente.
  Future<void> close();
}

/// Bytes crus de uma entrada, ainda por decodificar. [decode] é síncrono e
/// fatiável (doc/08 §3); [bytes] só existe depois dele.
final class PendingResource {
  /// Entrada de ZIP: [method] 0 (stored) ou 8 (deflate), [data] comprimido,
  /// [crc32] e [size] do central directory.
  PendingResource.zip({
    required this.path,
    required this.size,
    required int method,
    required this._data,
    required int crc32,
    required DiagnosticSink this._sink,
    this._inflaterFactory = createInflater,
  }) : assert(method == 0 || method == 8, 'método $method'),
       _method = method,
       _crc = crc32;

  /// Bytes já prontos (provider): um passo, sem CRC.
  PendingResource.ready({required this.path, required Uint8List bytes})
    : size = bytes.length,
      _method = null,
      _data = bytes,
      _crc = 0,
      _sink = null,
      _inflaterFactory = createInflater;

  /// Nome resolvido da entrada.
  final String path;

  /// Tamanho descomprimido declarado (≤ [maxEntrySize]).
  final int size;

  final int? _method;
  final Uint8List _data;
  final int _crc;
  final DiagnosticSink? _sink;
  final InflaterFactory _inflaterFactory;

  bool _started = false;
  Uint8List? _bytes;

  /// Bytes decodificados. [StateError] antes de [decode] ser drenado ou
  /// depois de uma exceção no decode.
  Uint8List get bytes =>
      _bytes ??
      (throw StateError(
        'bytes de $path indisponíveis: decode() não terminou ou falhou',
      ));

  /// Passos do decode: um a cada 64 KiB completos de saída e mais um ao
  /// terminar, depois do CRC. Cada chamada devolve um iterável novo; uma
  /// segunda drenagem lança [StateError] no primeiro passo.
  Iterable<void> decode() sync* {
    if (_started) {
      throw StateError('decode() de $path já foi iniciado');
    }
    _started = true;
    switch (_method) {
      case null:
        _bytes = _data;
        yield null;
      case 0:
        yield* _stored();
      default:
        yield* _inflate();
    }
  }

  Iterable<void> _stored() sync* {
    final data = _data;
    if (data.length > size) throw _overflow();
    final crc = Crc32();
    final whole = data.length - data.length % decodeStepBytes;
    for (var at = 0; at < whole; at += decodeStepBytes) {
      crc.add(data, at, at + decodeStepBytes);
      yield null;
    }
    crc.add(data, whole, data.length);
    _finish(data, crc.value);
    yield null;
  }

  Iterable<void> _inflate() sync* {
    final out = _Output(size);
    final crc = Crc32();
    final inflater = _inflaterFactory((chunk) {
      out.add(chunk); // lança _OutputOverflow antes de passar de size
      crc.add(chunk);
    });
    var steps = 0;
    final data = _data;
    for (var at = 0; at < data.length; at += inflateSliceBytes) {
      final end = math.min(at + inflateSliceBytes, data.length);
      _guard(() => inflater.add(Uint8List.sublistView(data, at, end)));
      while (steps < out.length ~/ decodeStepBytes) {
        steps++;
        yield null;
      }
    }
    _guard(inflater.close);
    while (steps < out.length ~/ decodeStepBytes) {
      steps++;
      yield null;
    }
    _finish(out.bytes, crc.value);
    yield null;
  }

  void _guard(void Function() step) {
    try {
      step();
    } on _OutputOverflow {
      throw _overflow();
    } on FormatException catch (e) {
      throw EpubContainerException(
        'stream deflate inválido',
        href: path,
        cause: e,
      );
    }
  }

  EpubContainerException _overflow() => EpubContainerException(
    'saída maior que o tamanho declarado ($size bytes)',
    href: path,
  );

  void _finish(Uint8List out, int actualCrc) {
    final sink = _sink!;
    if (out.length < size) {
      sink.emit(
        EpubDiagnosticCode.zipCrcMismatch,
        href: path,
        message: 'saída com ${out.length} de $size bytes declarados',
        details: {'reason': 'size', 'expected': size, 'actual': out.length},
      );
    } else if (actualCrc != _crc) {
      sink.emit(
        EpubDiagnosticCode.zipCrcMismatch,
        href: path,
        message: 'CRC-32 divergente',
        details: {'reason': 'crc', 'expected': _crc, 'actual': actualCrc},
      );
    }
    _bytes = out;
  }
}

final class _OutputOverflow implements Exception {
  const _OutputOverflow();
}

/// Saída do inflate que cresce por dobra até o tamanho declarado, sem
/// alocar de uma vez os 256 MiB que um cabeçalho mentiroso pediria.
final class _Output {
  _Output(this._limit) : _buffer = Uint8List(math.min(_limit, 64 * 1024));

  final int _limit;
  Uint8List _buffer;
  int length = 0;

  void add(Uint8List chunk) {
    final end = length + chunk.length;
    if (end > _limit) throw const _OutputOverflow();
    if (end > _buffer.length) {
      final grown = Uint8List(
        math.min(_limit, math.max(end, _buffer.length * 2)),
      )..setRange(0, length, _buffer);
      _buffer = grown;
    }
    _buffer.setRange(length, end, chunk);
    length = end;
  }

  Uint8List get bytes => Uint8List.sublistView(_buffer, 0, length);
}
