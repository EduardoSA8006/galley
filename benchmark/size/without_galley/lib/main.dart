import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';

/// App mínimo do modo `size`: idêntico ao de `with_galley`, exceto pela
/// dependência no `galley` e pela linha marcada com `GALLEY`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final bytes = (await rootBundle.load('assets/empty.epub')).buffer
      .asUint8List();
  var result = '';
  try {
    result = '${bytes.length}'; // GALLEY
  } on Object catch (e) {
    result = '$e';
  }
  runApp(Directionality(textDirection: TextDirection.ltr, child: Text(result)));
}
