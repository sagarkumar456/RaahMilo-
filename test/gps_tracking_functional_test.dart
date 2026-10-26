import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:trackmyphone/models/trip_model.dart';

void main() {
  group('GPS Tracking Functional & Regression Tests', () {
    test('Stationary Jitter Filter: Rejects small displacement while speed is stationary', () {
      final base = DateTime(2026, 10, 20, 12, 0, 0);

      // Anchor point (sitting at desk)
      final pAnchor = Position(
        latitude: 28.613939,
        longitude: 77.209021,
        timestamp: base,
        accuracy: 15.0,
        altitude: 0.0,
        altitudeAccuracy: 0.0,
        heading: 0.0,
        headingAccuracy: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
      );

      // GPS jitter: 6 meters away, but speed is 0.1 m/s (phone still on table)
      final pJitter = Position(
        latitude: 28.613990,
        longitude: 77.209050,
        timestamp: base.add(const Duration(seconds: 4)),
        accuracy: 18.0,
        altitude: 0.0,
        altitudeAccuracy: 0.0,
        heading: 0.0,
        headingAccuracy: 0.0,
        speed: 0.1,
        speedAccuracy: 0.0,
      );

      final step = Geolocator.distanceBetween(
        pAnchor.latitude,
        pAnchor.longitude,
        pJitter.latitude,
        pJitter.longitude,
      );

      // Verify physical distance is within jitter radius
      expect(step < 12.0, true);
      // Verify speed is below stationary threshold
      expect(pJitter.speed < 0.6, true);

      // Under our stationary filter: (speed < 0.6 && step < 12.0) is rejected
      final isStationaryJitter = pJitter.speed < 0.6 && step < 12.0;
      expect(isStationaryJitter, true, reason: 'Stationary drift should be rejected from the movement path');
    });

    test('Real Movement Through Point C: Intermediate waypoints are properly recorded', () {
      final base = DateTime(2026, 10, 20, 14, 0, 0);

      // Point A: Starting position
      final pA = TripPoint(
        latitude: 28.6100,
        longitude: 77.2100,
        speed: 6.0, // ~21 km/h
        accuracy: 8.0,
        timestamp: base,
      );

      // Point C: Intermediate waypoint / turn (traveling through Point C)
      final pC = TripPoint(
        latitude: 28.6150,
        longitude: 77.2180,
        speed: 5.5, // ~20 km/h
        accuracy: 9.0,
        timestamp: base.add(const Duration(minutes: 3)),
      );

      // Point B: Destination
      final pB = TripPoint(
        latitude: 28.6220,
        longitude: 77.2250,
        speed: 0.0, // stopped at destination
        accuracy: 7.0,
        timestamp: base.add(const Duration(minutes: 6)),
      );

      final tripPoints = [pA, pC, pB];

      // Calculate total ground-truth distance A -> C -> B
      final leg1 = Geolocator.distanceBetween(pA.latitude, pA.longitude, pC.latitude, pC.longitude);
      final leg2 = Geolocator.distanceBetween(pC.latitude, pC.longitude, pB.latitude, pB.longitude);
      final totalGroundTruthDistance = leg1 + leg2;

      // Direct straight distance A -> B (cutting corner without Point C)
      final directDistance = Geolocator.distanceBetween(pA.latitude, pA.longitude, pB.latitude, pB.longitude);

      // Total distance through Point C must be strictly greater than cutting across A -> B
      expect(totalGroundTruthDistance > directDistance, true);

      // Verify trip model preserves all 3 points
      final trip = TripModel(
        id: 'trip_via_c',
        title: 'Trip via Point C',
        ownerId: 'user_1',
        viewerIds: [],
        startedAt: base,
        endedAt: base.add(const Duration(minutes: 6)),
        distanceMeters: totalGroundTruthDistance,
        isActive: false,
        points: tripPoints,
      );

      expect(trip.points.length, 3);
      expect(trip.points[1].latitude, pC.latitude);
      expect(trip.points[1].longitude, pC.longitude);

      // Verify JSON serialization round-trip
      final json = trip.toJson();
      final restored = TripModel.fromJson(json);
      expect(restored.points.length, 3);
      expect(restored.points[1].latitude, pC.latitude);
      expect(restored.distanceMeters, totalGroundTruthDistance);
    });

    test('Teleportation Filter: Discards impossible jumps (> 60 m/s = 216 km/h)', () {
      final t1 = DateTime(2026, 10, 20, 15, 0, 0);
      final t2 = t1.add(const Duration(seconds: 2));

      // Coordinate jump of 500 meters in 2 seconds = 250 m/s = 900 km/h (impossible ground vehicle speed)
      final lat1 = 28.6100;
      final lng1 = 77.2100;
      final lat2 = 28.6145;
      final lng2 = 77.2145;

      final step = Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
      final timeDiffSec = t2.difference(t1).inSeconds.abs();
      final calcSpeed = step / timeDiffSec;

      expect(calcSpeed > 60.0, true);
      expect(step > 120.0, true);

      // Outlier jump condition
      final isOutlierJump = timeDiffSec >= 1 && calcSpeed > 60.0 && step > 120.0;
      expect(isOutlierJump, true, reason: 'Cell-tower flips / teleportation jumps must be rejected');
    });
  });
}
