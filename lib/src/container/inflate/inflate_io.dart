import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'inflate.dart';

/// `ZLibDecoder(raw: true)` em modo chunked.
ChunkedInflater createInflater(void Function(Uint8List chunk) onOutput) =>
    _IoInflater(onOutput);

final class _IoInflater implements ChunkedInflater {
  _IoInflater(void Function(Uint8List chunk) onOutput)
    : _sink = ZLibDecoder(raw: true).startChunkedConversion(_Output(onOutput));

  final ByteConversionSink _sink;

  @override
  void add(Uint8List chunk) => _sink.add(chunk);

  @override
  void close() => _sink.close();
}

final class _Output implements Sink<List<int>> {
  _Output(this._onOutput);

  final void Function(Uint8List chunk) _onOutput;

  @override
  void add(List<int> data) =>
      _onOutput(data is Uint8List ? data : Uint8List.fromList(data));

  @override
  void close() {}
}
