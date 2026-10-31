import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trackmyphone/models/app_notification.dart';
import 'package:trackmyphone/services/geofence_service.dart';
import 'package:trackmyphone/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('Geofence Safe Zone Functional & Alert Tests', () {
    test('Creating a safe zone correctly calculates inside state and distance', () async {
      final geofenceService = GeofenceService();

      // Create a test safe zone around Delhi Connaught Place
      await geofenceService.saveGeofence(
        id: 'test_zone_cp',
        name: 'CP Office',
        latitude: 28.6315,
        longitude: 77.2167,
        radiusMeters: 500,
        notifyOnEntryExit: true,
      );

      final zone = geofenceService.geofences.firstWhere((g) => g.id == 'test_zone_cp');
      expect(zone.name, 'CP Office');
      expect(zone.radiusMeters, 500);

      // Check position exactly at the center (distance = 0m, should be inside)
      geofenceService.checkLocationLatLng(28.6315, 77.2167);
      expect(geofenceService.isInsideGeofence('test_zone_cp'), isTrue);
      expect(geofenceService.distanceToGeofence('test_zone_cp')! < 1.0, isTrue);

      // Check position ~2 km away (should be outside)
      // 0.02 deg latitude is approx 2.2 km
      geofenceService.checkLocationLatLng(28.6515, 77.2167);
      expect(geofenceService.isInsideGeofence('test_zone_cp'), isFalse);
      expect(geofenceService.distanceToGeofence('test_zone_cp')! > 1000.0, isTrue);
    });

    test('Simulate Exit and Simulate Entry fire real alerts and notifications', () async {
      final geofenceService = GeofenceService();
      final notificationService = NotificationService();

      await geofenceService.saveGeofence(
        id: 'test_home_zone',
        name: 'My Home',
        latitude: 28.6139,
        longitude: 77.2090,
        radiusMeters: 300,
        notifyOnEntryExit: true,
      );

      GeofenceAlert? lastAlert;
      final sub = geofenceService.alertStream.listen((alert) {
        lastAlert = alert;
      });

      // 1. Simulate Exit
      geofenceService.simulateExit('test_home_zone');
      await Future.delayed(const Duration(milliseconds: 10));
      expect(geofenceService.isInsideGeofence('test_home_zone'), isFalse);
      expect(lastAlert, isNotNull);
      expect(lastAlert!.isEntry, isFalse);
      expect(lastAlert!.title, 'Left My Home');

      // Verify NotificationService received the notification
      final exitNotif = notificationService.notifications.firstWhere(
        (n) => n.title == 'Left My Home',
      );
      expect(exitNotif.type, NotificationType.leftZone);

      // 2. Simulate Entry
      geofenceService.simulateEntry('test_home_zone');
      await Future.delayed(const Duration(milliseconds: 10));
      expect(geofenceService.isInsideGeofence('test_home_zone'), isTrue);
      expect(lastAlert!.isEntry, isTrue);
      expect(lastAlert!.title, 'Arrived at My Home');

      final entryNotif = notificationService.notifications.firstWhere(
        (n) => n.title == 'Arrived at My Home',
      );
      expect(entryNotif.type, NotificationType.arrivedZone);

      await sub.cancel();
    });

    test('Deactivated geofence does not fire alerts', () async {
      final geofenceService = GeofenceService();

      await geofenceService.saveGeofence(
        id: 'inactive_zone',
        name: 'Inactive Gym',
        latitude: 28.6139,
        longitude: 77.2090,
        radiusMeters: 400,
        notifyOnEntryExit: true,
      );

      // Deactivate
      await geofenceService.toggleGeofenceActive('inactive_zone', false);

      GeofenceAlert? triggered;
      final sub = geofenceService.alertStream.listen((alert) {
        if (alert.geofence.id == 'inactive_zone') {
          triggered = alert;
        }
      });

      // Move outside then inside
      geofenceService.checkLocationLatLng(28.7000, 77.2090);
      geofenceService.checkLocationLatLng(28.6139, 77.2090);

      expect(triggered, isNull);
      await sub.cancel();
    });
  });
}
