import 'package:flutter_test/flutter_test.dart';
import 'package:galley_example/main.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('abre o EPUB embutido e mostra título e capítulos', (
    tester,
  ) async {
    await tester.pumpWidget(const GalleyExampleApp());
    await tester.pumpAndSettle();
    expect(find.textContaining('Livro de Exemplo do Galley'), findsOneWidget);
    expect(find.textContaining('3 capítulos'), findsOneWidget);
  });
}
