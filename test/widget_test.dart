// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:gymcoach/app.dart';

void main() {
  testWidgets('renderiza la shell principal', (WidgetTester tester) async {
    await tester.pumpWidget(const GymCoachApp(showWelcome: false));

    expect(find.text('Inicio'), findsOneWidget);
    expect(find.text('Entrenamiento'), findsNWidgets(2));
    expect(find.text('Entrenamiento Diario'), findsOneWidget);
    expect(find.text('Ejercicios'), findsWidgets);
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Perfil'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
  });
}
