import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackmyphone/models/vehicle_type.dart';
import 'package:trackmyphone/widgets/vehicle_marker_widget.dart';

void main() {
  group('VehicleMarkerWidget - Smoke & Sanity Tests', () {
    testWidgets('Renders properly for all VehicleTypes without exceptions', (tester) async {
      for (final vType in VehicleType.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: VehicleMarkerWidget(
                  vehicleType: vType,
                  isLive: true,
                  isMoving: true,
                  speedText: '45 km/h',
                  heading: pi / 4,
                  size: 48.0,
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));

        // Expect widget and speed pill to render cleanly
        expect(find.byType(VehicleMarkerWidget), findsOneWidget);
        expect(find.text('45 km/h'), findsOneWidget);
        expect(find.byType(CustomPaint), findsWidgets);
      }
    });

    testWidgets('Displays Stopped badge when vehicle is not moving', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: VehicleMarkerWidget(
                vehicleType: VehicleType.car,
                isLive: true,
                isMoving: false,
                heading: 0.0,
                size: 48.0,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Stopped'), findsOneWidget);
    });

    testWidgets('Hides badge when showBadge is false', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: VehicleMarkerWidget(
                vehicleType: VehicleType.car,
                isLive: false,
                isMoving: false,
                showBadge: false,
                heading: 0.0,
                size: 48.0,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Stopped'), findsNothing);
      expect(find.text('Moving'), findsNothing);
    });
  });

  group('VehicleMarkerWidget - Functional & Heading Rotation Tests', () {
    testWidgets('Applies correct rotation angle for cardinal travel directions', (tester) async {
      // Test 90 degrees (East) = pi / 2 radians
      const targetAngle = pi / 2;

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: VehicleMarkerWidget(
                vehicleType: VehicleType.car,
                isLive: true,
                isMoving: true,
                heading: targetAngle,
                size: 48.0,
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 350));

      // Find Transform.rotate inside VehicleMarkerWidget
      final transformFinder = find.descendant(
        of: find.byType(VehicleMarkerWidget),
        matching: find.byType(Transform),
      );
      expect(transformFinder, findsOneWidget);

      final Transform transformWidget = tester.widget(transformFinder);
      // Rotation around Z axis by pi/2: matrix[0] = cos(pi/2) ~ 0, matrix[1] = sin(pi/2) ~ 1
      final matrix = transformWidget.transform;
      final angle = atan2(matrix.entry(1, 0), matrix.entry(0, 0));
      expect((angle - targetAngle).abs(), lessThan(0.01));
    });

    testWidgets('Smoothly animates heading when turning corner (0 to pi/2)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: VehicleMarkerWidget(
                vehicleType: VehicleType.car,
                isLive: true,
                isMoving: true,
                heading: 0.0,
                size: 48.0,
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 350));

      // Turn 90 degrees right (East)
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: VehicleMarkerWidget(
                vehicleType: VehicleType.car,
                isLive: true,
                isMoving: true,
                heading: pi / 2,
                size: 48.0,
              ),
            ),
          ),
        ),
      );

      // Halfway through animation (160ms)
      await tester.pump(const Duration(milliseconds: 160));

      final Transform midTransform = tester.widget(find.descendant(
        of: find.byType(VehicleMarkerWidget),
        matching: find.byType(Transform),
      ));
      final midMatrix = midTransform.transform;
      final midAngle = atan2(midMatrix.entry(1, 0), midMatrix.entry(0, 0));

      // Should be smoothly between 0 and pi/2
      expect(midAngle, greaterThan(0.05));
      expect(midAngle, lessThan(pi / 2));

      // Complete animation
      await tester.pump(const Duration(milliseconds: 200));

      final Transform endTransform = tester.widget(find.descendant(
        of: find.byType(VehicleMarkerWidget),
        matching: find.byType(Transform),
      ));
      final endMatrix = endTransform.transform;
      final endAngle = atan2(endMatrix.entry(1, 0), endMatrix.entry(0, 0));
      expect((endAngle - (pi / 2)).abs(), lessThan(0.01));
    });

    testWidgets('Interpolates shortest arc when crossing North threshold (-0.1 to +0.1 rad)', (tester) async {
      // Start slightly west of North (-0.1 rad ~ 354 deg)
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: VehicleMarkerWidget(
                vehicleType: VehicleType.car,
                isLive: true,
                isMoving: true,
                heading: -0.1,
                size: 48.0,
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 350));

      // Turn slightly east of North (+0.1 rad ~ 6 deg)
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: VehicleMarkerWidget(
                vehicleType: VehicleType.car,
                isLive: true,
                isMoving: true,
                heading: 0.1,
                size: 48.0,
              ),
            ),
          ),
        ),
      );

      // Pump 150ms - angle should not flip 360 degrees around South (should stay near 0)
      await tester.pump(const Duration(milliseconds: 150));

      final Transform transform = tester.widget(find.descendant(
        of: find.byType(VehicleMarkerWidget),
        matching: find.byType(Transform),
      ));
      final matrix = transform.transform;
      final angle = atan2(matrix.entry(1, 0), matrix.entry(0, 0));

      // Verify that it stays in the small arc between -0.1 and 0.1, never swinging past pi
      expect(angle.abs(), lessThan(0.2));
    });
  });
}
