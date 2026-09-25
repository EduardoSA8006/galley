/// Inflate chunked (deflate cru, método 8 do ZIP). Nativo em
/// `inflate_io.dart`; no web, `inflate_stub.dart` falha com mensagem clara
/// (P7, adiado para a 1.0.x).
library;

import 'dart:typed_data';

export 'inflate_stub.dart' if (dart.library.io) 'inflate_io.dart';

/// Recebe a entrada comprimida em pedaços e entrega a saída a quem o criou,
/// sincronamente, dentro de [add] e [close].
abstract interface class ChunkedInflater {
  /// FormatException se o stream for inválido. Exceção lançada pelo
  /// callback de saída atravessa [add] sem ser embrulhada.
  void add(Uint8List chunk);

  /// Stream truncado não lança: a saída só fica curta.
  void close();
}

/// Cria um inflater que entrega a saída a [onOutput].
typedef InflaterFactory = ChunkedInflater Function(
  void Function(Uint8List chunk) onOutput,
);
