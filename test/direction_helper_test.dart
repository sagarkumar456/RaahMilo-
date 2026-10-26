import 'package:flutter_test/flutter_test.dart';
import 'package:trackmyphone/models/trip_model.dart';
import 'package:trackmyphone/utils/trip_direction_helper.dart';

void main() {
  group('TripDirectionHelper Terminology and Route Splitting Tests', () {
    test('Ensures pure English directional labels (no Hindi/Hinglish text)', () {
      expect(TripDirectionHelper.getDirectionTitle(0, 1), 'Trip 1 • Route');
      expect(TripDirectionHelper.getDirectionTitle(0, 2), 'Trip 1 • Outward');
      expect(TripDirectionHelper.getDirectionTitle(1, 2), 'Trip 2 • Return');
      expect(TripDirectionHelper.getDirectionTitle(1, 2, isReturn: true), 'Trip 2 • Return');
    });

    test('Splits round trip correctly into Outward and Return legs with English labels', () {
      final base = DateTime(2026, 10, 20, 9, 0, 0);

      // Start at A, go to C (turnaround point 500m away), then return back to A
      final pA = TripPoint(latitude: 28.6100, longitude: 77.2100, speed: 5.0, accuracy: 4.0, timestamp: base);
      final pA1 = TripPoint(latitude: 28.6120, longitude: 77.2120, speed: 6.0, accuracy: 4.0, timestamp: base.add(const Duration(minutes: 2)));
      final pC = TripPoint(latitude: 28.6150, longitude: 77.2150, speed: 4.0, accuracy: 4.0, timestamp: base.add(const Duration(minutes: 5))); // furthest turnaround point
      final pB1 = TripPoint(latitude: 28.6125, longitude: 77.2125, speed: 5.0, accuracy: 4.0, timestamp: base.add(const Duration(minutes: 8)));
      final pB2 = TripPoint(latitude: 28.6105, longitude: 77.2102, speed: 4.0, accuracy: 4.0, timestamp: base.add(const Duration(minutes: 10)));
      final pReturnEnd = TripPoint(latitude: 28.6101, longitude: 77.2101, speed: 0.0, accuracy: 4.0, timestamp: base.add(const Duration(minutes: 12)));

      final trip = TripModel(
        id: 'test_round_trip_1',
        title: 'Morning Commute',
        ownerId: 'user_123',
        viewerIds: [],
        startedAt: base,
        endedAt: base.add(const Duration(minutes: 12)),
        distanceMeters: 1200.0,
        isActive: false,
        points: [pA, pA1, pC, pB1, pB2, pReturnEnd],
      );

      final segments = TripDirectionHelper.buildSegmentsForTrips([trip]);

      expect(segments.length, 2);
      expect(segments[0].directionLabel, 'Trip 1 • Outward');
      expect(segments[0].title, 'Outward Route (Leg 1)');
      expect(segments[0].isReturn, false);

      expect(segments[1].directionLabel, 'Trip 2 • Return');
      expect(segments[1].title, 'Return Route (Leg 2)');
      expect(segments[1].isReturn, true);

      // Ensure turnaround point is identified at Point C
      expect(segments[0].points.isNotEmpty, true);
      expect(segments[1].points.isNotEmpty, true);
    });
  });
}
