import 'dart:typed_data';

import 'inflate.dart';

/// Mensagem do web; `inflate_web_test.dart` confere.
const String inflateUnsupportedMessage =
    'Inflate (deflate, método 8 do ZIP) ainda não existe no web: pendência '
    'P7, prevista para a 1.0.x. Entradas stored funcionam.';

ChunkedInflater createInflater(void Function(Uint8List chunk) onOutput) =>
    throw UnsupportedError(inflateUnsupportedMessage);
