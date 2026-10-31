import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackmyphone/models/trip_model.dart';
import 'package:trackmyphone/models/vehicle_type.dart';
import 'package:trackmyphone/widgets/trip_route_painter.dart';

void main() {
  group('TripRouteThumbnail & Vehicle Customization Tests', () {
    testWidgets('Renders distinct vehicle avatar icon and badge when points are empty', (tester) async {
      for (final type in [VehicleType.car, VehicleType.bike, VehicleType.scooty, VehicleType.human]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TripRouteThumbnail(
                points: const [],
                vehicleType: type,
                size: 54,
              ),
            ),
          ),
        );

        // Expect vehicle icon to be present
        expect(find.byIcon(type.icon), findsOneWidget);
        // Expect display name text to be present
        expect(find.text(type.displayName), findsOneWidget);
      }
    });

    testWidgets('Renders CustomPaint route thumbnail when points are provided', (tester) async {
      final List<TripPoint> samplePoints = [
        TripPoint(latitude: 28.6139, longitude: 77.2090, speed: 10.0, accuracy: 5.0, timestamp: DateTime.now()),
        TripPoint(latitude: 28.6145, longitude: 77.2098, speed: 12.0, accuracy: 5.0, timestamp: DateTime.now()),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TripRouteThumbnail(
              points: samplePoints,
              vehicleType: VehicleType.car,
              size: 54,
            ),
          ),
        ),
      );

      expect(
        find.byWidgetPredicate((w) => w is CustomPaint && w.painter is CustomPainter),
        findsWidgets,
      );
      expect(find.byIcon(VehicleType.car.icon), findsOneWidget);
    });

    test('TripModel formats date and time using local timezone correctly', () {
      // 2026-10-31 18:30:00 UTC corresponds to 2026-11-01 00:00:00 in IST (UTC+5:30)
      final utcStarted = DateTime.utc(2026, 10, 31, 18, 30);
      final trip = TripModel(
        id: 'test_utc',
        title: 'Late Night Ride',
        ownerId: 'u1',
        viewerIds: const [],
        startedAt: utcStarted,
        endedAt: utcStarted.add(const Duration(minutes: 45)),
        distanceMeters: 4500,
        isActive: false,
        vehicleType: 'bike',
      );

      final localStarted = utcStarted.toLocal();
      // Formatted date and time range should reflect localStarted
      expect(trip.formattedDate.contains(localStarted.day.toString().padLeft(2, '0')), isTrue);
      expect(trip.formattedTimeRange.contains(localStarted.day.toString().padLeft(2, '0')), isTrue);
    });
  });
}
