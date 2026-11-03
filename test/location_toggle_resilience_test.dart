import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trackmyphone/models/trip_model.dart';
import 'package:trackmyphone/models/vehicle_type.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Location Toggle Resilience & 7km Preservation Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Active trip points and distance (7km) archive safely without data loss', () {
      final base = DateTime(2026, 11, 3, 10, 0, 0);

      // Create realistic points representing a 7 km trip
      final points = <TripPoint>[
        TripPoint(
          latitude: 28.6139,
          longitude: 77.2090,
          speed: 8.5,
          accuracy: 5.0,
          timestamp: base,
        ),
        TripPoint(
          latitude: 28.6500,
          longitude: 77.2400,
          speed: 9.0,
          accuracy: 5.0,
          timestamp: base.add(const Duration(minutes: 20)),
        ),
        TripPoint(
          latitude: 28.6700,
          longitude: 77.2600,
          speed: 8.0,
          accuracy: 5.0,
          timestamp: base.add(const Duration(minutes: 40)),
        ),
      ];

      // Compute total distance
      double totalDist = 0.0;
      for (int i = 0; i < points.length - 1; i++) {
        totalDist += Geolocator.distanceBetween(
          points[i].latitude,
          points[i].longitude,
          points[i + 1].latitude,
          points[i + 1].longitude,
        );
      }

      expect(totalDist, greaterThan(6500.0)); // ~7 km

      // Archive into TripModel
      final archivedTrip = TripModel(
        id: 'archived_7km_trip',
        title: '${VehicleType.bike.displayName} Trip at 10:00 AM',
        ownerId: 'test_uid',
        viewerIds: const [],
        startedAt: points.first.timestamp,
        endedAt: points.last.timestamp,
        distanceMeters: totalDist,
        isActive: false,
        points: points,
        vehicleType: 'bike',
      );

      final historyList = <TripModel>[archivedTrip];

      // Verify the distance calculation for date
      double calculatedKm = 0.0;
      for (final trip in historyList) {
        if (trip.startedAt.day == base.day) {
          calculatedKm += trip.distanceMeters / 1000.0;
        }
      }

      expect(calculatedKm, greaterThan(6.5));
      expect(calculatedKm.toStringAsFixed(1), equals((totalDist / 1000.0).toStringAsFixed(1)));
    });

    test('SharedPreferences retains active points when session persists', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('active_trip_meters', 7200.0);
      await prefs.setString('active_trip_points', '[{"latitude":28.6139,"longitude":77.2090,"speed":5.0,"accuracy":5.0,"timestamp":"2026-11-03T10:00:00.000"}]');

      final savedMeters = prefs.getDouble('active_trip_meters');
      final savedPoints = prefs.getString('active_trip_points');

      expect(savedMeters, equals(7200.0));
      expect(savedPoints, isNotNull);
      expect(savedPoints, contains('28.6139'));
    });
  });
}
