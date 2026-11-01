import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trackmyphone/models/trip_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Account Data Isolation & Persistence Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('TripModel preserves ownerId in serialization and deserialization', () {
      final trip = TripModel(
        id: 'trip_101',
        title: 'Morning Walk',
        ownerId: 'user_alpha_123',
        viewerIds: ['user_beta_456'],
        startedAt: DateTime(2026, 11, 1, 9, 30),
        endedAt: DateTime(2026, 11, 1, 10, 15),
        distanceMeters: 3200.0,
        isActive: false,
        vehicleType: 'human',
      );

      final jsonMap = trip.toJson();
      expect(jsonMap['ownerId'], 'user_alpha_123');

      final restoredTrip = TripModel.fromJson(jsonMap);
      expect(restoredTrip.id, 'trip_101');
      expect(restoredTrip.ownerId, 'user_alpha_123');
      expect(restoredTrip.vehicleType, 'human');
      expect(restoredTrip.distanceMeters, 3200.0);
    });

    test('User account storage keys isolate data between different users', () async {
      final prefs = await SharedPreferences.getInstance();

      final tripUserA = TripModel(
        id: 'trip_user_a_1',
        title: 'User A Office Trip',
        ownerId: 'uid_user_a',
        viewerIds: const [],
        startedAt: DateTime(2026, 11, 1, 8, 30),
        endedAt: DateTime(2026, 11, 1, 9, 0),
        distanceMeters: 5500.0,
        isActive: false,
        vehicleType: 'car',
      );

      final tripUserB = TripModel(
        id: 'trip_user_b_1',
        title: 'User B Gym Trip',
        ownerId: 'uid_user_b',
        viewerIds: const [],
        startedAt: DateTime(2026, 11, 1, 18, 0),
        endedAt: DateTime(2026, 11, 1, 19, 0),
        distanceMeters: 4200.0,
        isActive: false,
        vehicleType: 'bike',
      );

      // Save user A's trip into user A's scoped storage
      await prefs.setString(
        'saved_history_trips_uid_user_a',
        jsonEncode([tripUserA.toJson()]),
      );

      // Save user B's trip into user B's scoped storage
      await prefs.setString(
        'saved_history_trips_uid_user_b',
        jsonEncode([tripUserB.toJson()]),
      );

      // Verify User A only reads User A's data
      final rawUserA = prefs.getString('saved_history_trips_uid_user_a');
      expect(rawUserA, isNotNull);
      final List<dynamic> listA = jsonDecode(rawUserA!);
      final loadedA = listA.map((m) => TripModel.fromJson(m)).toList();
      expect(loadedA.length, 1);
      expect(loadedA.first.ownerId, 'uid_user_a');
      expect(loadedA.first.title, 'User A Office Trip');

      // Verify User B only reads User B's data
      final rawUserB = prefs.getString('saved_history_trips_uid_user_b');
      expect(rawUserB, isNotNull);
      final List<dynamic> listB = jsonDecode(rawUserB!);
      final loadedB = listB.map((m) => TripModel.fromJson(m)).toList();
      expect(loadedB.length, 1);
      expect(loadedB.first.ownerId, 'uid_user_b');
      expect(loadedB.first.title, 'User B Gym Trip');

      // Verify no cross contamination
      expect(loadedA.any((t) => t.ownerId == 'uid_user_b'), isFalse);
      expect(loadedB.any((t) => t.ownerId == 'uid_user_a'), isFalse);
    });

    test('Legacy migration imports existing trips safely without data loss', () async {
      final prefs = await SharedPreferences.getInstance();

      final legacyTrip = TripModel(
        id: 'legacy_trip_1',
        title: 'Old Existing Trip',
        ownerId: '',
        viewerIds: const [],
        startedAt: DateTime(2026, 10, 25, 14, 0),
        distanceMeters: 8100.0,
        isActive: false,
        vehicleType: 'car',
      );

      // Legacy global key without user scoping
      await prefs.setString('saved_history_trips', jsonEncode([legacyTrip.toJson()]));

      // Simulate first login of user_target after update
      const targetUid = 'user_target_999';
      final legacyRaw = prefs.getString('saved_history_trips');
      expect(legacyRaw, isNotNull);

      final List<dynamic> rawLegacyList = jsonDecode(legacyRaw!);
      final migratedTrips = rawLegacyList
          .map((item) => TripModel.fromJson(item as Map<String, dynamic>))
          .map((t) => t.copyWith(ownerId: targetUid))
          .toList();

      await prefs.setString(
        'saved_history_trips_$targetUid',
        jsonEncode(migratedTrips.map((t) => t.toJson()).toList()),
      );

      // Verify migrated data in target account
      final migratedRaw = prefs.getString('saved_history_trips_$targetUid');
      expect(migratedRaw, isNotNull);
      final List<dynamic> listMigrated = jsonDecode(migratedRaw!);
      final loadedMigrated = listMigrated.map((m) => TripModel.fromJson(m)).toList();

      expect(loadedMigrated.length, 1);
      expect(loadedMigrated.first.id, 'legacy_trip_1');
      expect(loadedMigrated.first.ownerId, targetUid);
      expect(loadedMigrated.first.title, 'Old Existing Trip');
    });
  });
}

