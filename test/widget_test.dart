import 'package:flutter_test/flutter_test.dart';
import 'package:trackmyphone/main.dart';

void main() {
  testWidgets('RaahMiloApp initial build test', (WidgetTester tester) async {
    await tester.pumpWidget(const RaahMiloApp());
    expect(find.text('RaahMilo'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });
}
