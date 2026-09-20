import 'package:cineshow/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('exibe a home do CINESHOW', (tester) async {
    await tester.pumpWidget(const CineShowApp());

    expect(find.text('CINESHOW'), findsOneWidget);
    expect(find.text('Assistir agora'), findsOneWidget);
    expect(find.text('Continue assistindo'), findsOneWidget);
  });
}
