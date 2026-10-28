import 'package:flutter_test/flutter_test.dart';
import 'package:trackmyphone/models/stoppage_model.dart';
import 'package:trackmyphone/models/trip_model.dart';

void main() {
  group('StoppageModel & extractStoppages tests', () {
    test('Detects intermediate halt and guarantees end stoppage', () {
      final base = DateTime(2026, 10, 19, 10, 0, 0);

      // 1. Starting movement (moving at 20 km/h)
      final p1 = TripPoint(latitude: 28.6100, longitude: 77.2100, speed: 5.5, accuracy: 4.0, timestamp: base);
      final p2 = TripPoint(latitude: 28.6130, longitude: 77.2120, speed: 6.0, accuracy: 4.0, timestamp: base.add(const Duration(minutes: 2)));

      // 2. Halting for 5 minutes at shop/signal (speed ~0, distance < 10m)
      final p3 = TripPoint(latitude: 28.6150, longitude: 77.2140, speed: 0.1, accuracy: 3.0, timestamp: base.add(const Duration(minutes: 3)));
      final p4 = TripPoint(latitude: 28.61505, longitude: 77.21405, speed: 0.0, accuracy: 3.0, timestamp: base.add(const Duration(minutes: 5)));
      final p5 = TripPoint(latitude: 28.61502, longitude: 77.21402, speed: 0.0, accuracy: 3.0, timestamp: base.add(const Duration(minutes: 8)));

      // 3. Movement resumes
      final p6 = TripPoint(latitude: 28.6180, longitude: 77.2170, speed: 7.0, accuracy: 4.0, timestamp: base.add(const Duration(minutes: 10)));
      final p7 = TripPoint(latitude: 28.6220, longitude: 77.2200, speed: 6.5, accuracy: 4.0, timestamp: base.add(const Duration(minutes: 13)));

      // 4. Trip ends (Final stop)
      final p8 = TripPoint(latitude: 28.6250, longitude: 77.2230, speed: 0.0, accuracy: 3.0, timestamp: base.add(const Duration(minutes: 15)));

      final points = [p1, p2, p3, p4, p5, p6, p7, p8];

      final stoppages = extractStoppages(points);

      expect(stoppages.isNotEmpty, true);

      // Verify intermediate stoppage
      final intermediate = stoppages.where((s) => !s.isEndStop).toList();
      expect(intermediate.length, 1);
      expect(intermediate.first.stopNumber, 1);
      // Stoppage started at p3 (min 3) and vehicle departed at p6 (min 10) = 7 minutes
      expect(intermediate.first.duration.inMinutes, 7);
      expect(intermediate.first.formattedDuration, '7 mins');
      expect(intermediate.first.arrivedAt, p3.timestamp);
      expect(intermediate.first.departedAt, p6.timestamp);

      // Verify End Stoppage ("na end stopage banana hai")
      final endStops = stoppages.where((s) => s.isEndStop).toList();
      expect(endStops.length, 1);
      expect(endStops.first.isEndStop, true);
      expect(endStops.first.title, 'Trip Destination');
      expect(endStops.first.latitude, p8.latitude);
      expect(endStops.first.longitude, p8.longitude);
    });

    test('Detects halt during stationary GPS throttle when only 1 ping logged before departure', () {
      final base = DateTime(2026, 10, 19, 14, 0, 0);

      // Moving point
      final p1 = TripPoint(latitude: 28.6100, longitude: 77.2100, speed: 6.0, accuracy: 3.0, timestamp: base);

      // Stops at red light / store for 3 minutes (single point logged because stationary filter throttled)
      final p2 = TripPoint(latitude: 28.6120, longitude: 77.2120, speed: 0.1, accuracy: 3.0, timestamp: base.add(const Duration(minutes: 1)));

      // Movement resumes 3 minutes later
      final p3 = TripPoint(latitude: 28.6140, longitude: 77.2140, speed: 5.5, accuracy: 3.0, timestamp: base.add(const Duration(minutes: 4)));

      // Trip ends
      final p4 = TripPoint(latitude: 28.6160, longitude: 77.2160, speed: 0.0, accuracy: 3.0, timestamp: base.add(const Duration(minutes: 6)));

      final stoppages = extractStoppages([p1, p2, p3, p4]);

      final intermediate = stoppages.where((s) => !s.isEndStop).toList();
      expect(intermediate.length, 1);
      expect(intermediate.first.duration.inMinutes, 3);
      expect(intermediate.first.arrivedAt, p2.timestamp);
      expect(intermediate.first.departedAt, p3.timestamp);
    });
  });
}
