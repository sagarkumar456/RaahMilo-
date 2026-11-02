import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackmyphone/models/user_device_model.dart';
import 'package:trackmyphone/services/device_manager_service.dart';
import 'package:trackmyphone/widgets/device_selector_sheet.dart';
import 'package:trackmyphone/widgets/lost_device_marker_widget.dart';
import 'package:trackmyphone/widgets/remote_device_info_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Multi-Device Tracking & Find My Phone Tests', () {
    test('UserDeviceModel parses and serializes correctly', () {
      final now = DateTime.now();
      final device = UserDeviceModel(
        id: 'dev_phone_abc_123',
        ownerUid: 'usr_test_123',
        name: 'Vivo V29 5G',
        model: 'Vivo V2310',
        platform: 'Android',
        latitude: 28.6139,
        longitude: 77.2090,
        speedKmh: 24.5,
        heading: 180.0,
        address: 'Connaught Place, New Delhi',
        batteryLevel: 85,
        isOnline: true,
        isTrackingActive: true,
        ringAlert: false,
        lastSeen: now,
        createdAt: now.subtract(const Duration(days: 2)),
      );

      final map = device.toMap();
      expect(map['id'], 'dev_phone_abc_123');
      expect(map['ownerUid'], 'usr_test_123');
      expect(map['name'], 'Vivo V29 5G');
      expect(map['model'], 'Vivo V2310');
      expect(map['latitude'], 28.6139);
      expect(map['longitude'], 77.2090);
      expect(map['batteryLevel'], 85);
      expect(map['isOnline'], true);

      final restored = UserDeviceModel.fromMap(map, 'dev_phone_abc_123');
      expect(restored.id, 'dev_phone_abc_123');
      expect(restored.name, 'Vivo V29 5G');
      expect(restored.model, 'Vivo V2310');
      expect(restored.latitude, 28.6139);
      expect(restored.longitude, 77.2090);
      expect(restored.batteryLevel, 85);
      expect(restored.isOnline, true);
    });

    test('UserDeviceModel computes offline status for stale devices', () {
      final staleDate = DateTime.now().subtract(const Duration(minutes: 25));
      final map = {
        'id': 'dev_lost_xyz',
        'ownerUid': 'usr_test',
        'name': 'Samsung Galaxy S23',
        'model': 'SM-S901B',
        'platform': 'Android',
        'latitude': 28.7041,
        'longitude': 77.1025,
        'batteryLevel': 42,
        'isOnline': true, // flag in DB was true, but timestamp is 25m old
        'lastSeen': staleDate.toIso8601String(),
        'createdAt': staleDate.toIso8601String(),
      };

      final device = UserDeviceModel.fromMap(map, 'dev_lost_xyz');
      // Freshness check: older than 10 mins should be computed as offline
      expect(device.isOnline, false);
      expect(device.isLostOrInactive, true);
      expect(device.lastSeenFormatted, '25m ago');
    });

    test('Finder Mode toggle updates state without errors', () async {
      final service = DeviceManagerService();
      expect(service.isFinderMode, isA<bool>());

      await service.setFinderMode(true);
      expect(service.isFinderMode, true);

      await service.setFinderMode(false);
      expect(service.isFinderMode, false);
    });

    test('Device switching correctly toggles isViewingCurrentDevice', () async {
      final service = DeviceManagerService();
      await service.selectDevice(null);
      expect(service.isViewingCurrentDevice, true);

      await service.selectDevice('dev_remote_lost_phone_999');
      expect(service.isViewingCurrentDevice, false);
      expect(service.selectedDeviceId, 'dev_remote_lost_phone_999');

      await service.selectDevice(null);
      expect(service.isViewingCurrentDevice, true);
    });

    testWidgets('LostDeviceMarkerWidget renders with radar pulse and label', (tester) async {
      final device = UserDeviceModel(
        id: 'dev_test_lost',
        ownerUid: 'usr_test',
        name: 'My Lost Phone',
        latitude: 28.6139,
        longitude: 77.2090,
        batteryLevel: 65,
        isOnline: true,
        lastSeen: DateTime.now(),
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LostDeviceMarkerWidget(device: device),
          ),
        ),
      );

      expect(find.text('My Lost Phone'), findsOneWidget);
      expect(find.byIcon(Icons.phone_android_rounded), findsOneWidget);
    });

    testWidgets('RemoteDeviceInfoCard renders with 4 quick action buttons', (tester) async {
      final device = UserDeviceModel(
        id: 'dev_remote_123',
        ownerUid: 'usr_test',
        name: 'Samsung Galaxy S23 (Lost)',
        model: 'SM-S901B',
        platform: 'Android',
        latitude: 28.6139,
        longitude: 77.2090,
        address: 'Connaught Place, New Delhi',
        batteryLevel: 78,
        isOnline: true,
        lastSeen: DateTime.now(),
        createdAt: DateTime.now(),
      );

      bool recenterCalled = false;
      bool dismissCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RemoteDeviceInfoCard(
              device: device,
              onRecenter: () => recenterCalled = true,
              onDismiss: () => dismissCalled = true,
            ),
          ),
        ),
      );

      expect(find.text('Samsung Galaxy S23 (Lost)'), findsOneWidget);
      expect(find.text('REMOTE'), findsOneWidget);
      expect(find.text('Online Now'), findsOneWidget);
      expect(find.text('78%'), findsOneWidget);
      expect(find.text('Connaught Place, New Delhi'), findsOneWidget);

      // Verify action buttons
      expect(find.text('Directions'), findsOneWidget);
      expect(find.text('Ring Siren'), findsOneWidget);
      expect(find.byIcon(Icons.share_rounded), findsOneWidget);
      expect(find.byIcon(Icons.my_location_rounded), findsOneWidget);

      // Tap recenter
      await tester.tap(find.byIcon(Icons.my_location_rounded));
      expect(recenterCalled, true);

      // Tap dismiss (close button)
      await tester.tap(find.byIcon(Icons.close_rounded));
      expect(dismissCalled, true);
    });

    testWidgets('DeviceSelectorSheet mounts and renders without errors', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DeviceSelectorSheet(),
          ),
        ),
      );

      expect(find.text('My Account Devices'), findsOneWidget);
      expect(find.text('Lost Phone Finder Mode'), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);
    });
  });
}
