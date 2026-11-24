import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:galley/galley.dart';

void main() => runApp(const GalleyExampleApp());

/// Aplicativo de exemplo: abre o EPUB embutido e mostra título e capítulos.
class GalleyExampleApp extends StatelessWidget {
  /// Cria o aplicativo.
  const GalleyExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Galley Example',
    theme: ThemeData(colorSchemeSeed: Colors.indigo),
    home: const _BookInfoPage(),
  );
}

class _BookInfoPage extends StatefulWidget {
  const _BookInfoPage();

  @override
  State<_BookInfoPage> createState() => _BookInfoPageState();
}

class _BookInfoPageState extends State<_BookInfoPage> {
  late final Future<({String? title, int chapters})> _info = _load();

  Future<({String? title, int chapters})> _load() async {
    final data = await rootBundle.load('assets/sample.epub');
    final book = await EpubBook.fromBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    try {
      return (title: book.metadata.title, chapters: book.spine.items.length);
    } finally {
      await book.close();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Galley')),
    body: Center(
      child: FutureBuilder(
        future: _info,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Text('Erro: ${snapshot.error}');
          final info = snapshot.data;
          if (info == null) return const CircularProgressIndicator();
          return Text(
            '${info.title ?? 'Sem título'}\n${info.chapters} capítulos',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          );
        },
      ),
    ),
  );
}
