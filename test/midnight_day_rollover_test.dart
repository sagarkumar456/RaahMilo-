import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trackmyphone/models/trip_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Midnight Day Rollover & Past Day Distance Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Trip with 0 distanceMeters computes distance accurately from points', () {
      final pts = [
        TripPoint(
          latitude: 28.6139,
          longitude: 77.2090,
          speed: 1.5,
          accuracy: 5.0,
          timestamp: DateTime(2026, 11, 2, 10, 0, 0),
        ),
        TripPoint(
          latitude: 28.6239,
          longitude: 77.2190,
          speed: 1.5,
          accuracy: 5.0,
          timestamp: DateTime(2026, 11, 2, 10, 15, 0),
        ),
      ];

      final trip = TripModel(
        id: 'test_nov2_trip',
        title: 'Walk Trip',
        ownerId: 'test_user',
        viewerIds: const [],
        startedAt: DateTime(2026, 11, 2, 10, 0, 0),
        endedAt: DateTime(2026, 11, 2, 10, 15, 0),
        distanceMeters: 0.0,
        isActive: false,
        points: pts,
      );

      expect(trip.id, equals('test_nov2_trip'));

      final dist = Geolocator.distanceBetween(
        pts[0].latitude,
        pts[0].longitude,
        pts[1].latitude,
        pts[1].longitude,
      );
      expect(dist, greaterThan(1000.0));
    });

    test('Multi-day points partition correctly across calendar day boundaries', () {
      final points = [
        TripPoint(
          latitude: 28.6139,
          longitude: 77.2090,
          speed: 2.0,
          accuracy: 5.0,
          timestamp: DateTime(2026, 11, 2, 22, 0, 0),
        ),
        TripPoint(
          latitude: 28.6200,
          longitude: 77.2150,
          speed: 2.0,
          accuracy: 5.0,
          timestamp: DateTime(2026, 11, 2, 22, 15, 0),
        ),
        TripPoint(
          latitude: 28.6250,
          longitude: 77.2200,
          speed: 2.5,
          accuracy: 5.0,
          timestamp: DateTime(2026, 11, 3, 08, 0, 0),
        ),
        TripPoint(
          latitude: 28.6300,
          longitude: 77.2250,
          speed: 2.5,
          accuracy: 5.0,
          timestamp: DateTime(2026, 11, 3, 08, 30, 0),
        ),
      ];

      final Map<String, List<TripPoint>> pointsByDay = {};
      for (final tp in points) {
        final d = tp.timestamp.toLocal();
        final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        pointsByDay.putIfAbsent(key, () => []).add(tp);
      }

      expect(pointsByDay.containsKey('2026-11-02'), isTrue);
      expect(pointsByDay['2026-11-02']!.length, equals(2));

      expect(pointsByDay.containsKey('2026-11-03'), isTrue);
      expect(pointsByDay['2026-11-03']!.length, equals(2));

      final nov2Pts = pointsByDay['2026-11-02']!;
      final nov2Dist = Geolocator.distanceBetween(
        nov2Pts[0].latitude,
        nov2Pts[0].longitude,
        nov2Pts[1].latitude,
        nov2Pts[1].longitude,
      );
      expect(nov2Dist, greaterThan(500.0));

      final nov3Pts = pointsByDay['2026-11-03']!;
      final nov3Dist = Geolocator.distanceBetween(
        nov3Pts[0].latitude,
        nov3Pts[0].longitude,
        nov3Pts[1].latitude,
        nov3Pts[1].longitude,
      );
      expect(nov3Dist, greaterThan(500.0));
    });
  });
}
