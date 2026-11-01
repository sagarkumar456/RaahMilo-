import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trackmyphone/screens/home_shell.dart';
import 'package:trackmyphone/screens/live_map_screen.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('LiveMapScreen mounts and renders without exceptions', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LiveMapScreen(isActiveTab: true),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(LiveMapScreen), findsOneWidget);
  });

  testWidgets('HomeShell switches to Map tab without exceptions', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: HomeShell(initialTab: 1),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(HomeShell), findsOneWidget);
  });
}
