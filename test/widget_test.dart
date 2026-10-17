import 'package:flutter_test/flutter_test.dart';
import 'package:trackmyphone/main.dart';

void main() {
  testWidgets('TrackMyPhoneApp initial build test', (WidgetTester tester) async {
    await tester.pumpWidget(const TrackMyPhoneApp());
    expect(find.text('TrackMyPhone'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });
}
