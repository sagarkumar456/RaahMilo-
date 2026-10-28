import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:trackmyphone/models/trip_model.dart';
import 'package:trackmyphone/services/road_routing_service.dart';
import 'package:trackmyphone/services/tracking_service.dart';
import 'package:trackmyphone/utils/trip_direction_helper.dart';

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

      final anchorTripPoint = TripPoint(
        latitude: pAnchor.latitude,
        longitude: pAnchor.longitude,
        speed: 0.0,
        accuracy: 15.0,
        timestamp: base,
      );

      // GPS jitter: 4 meters away, speed is 0.1 m/s (phone still on table)
      final pJitter = Position(
        latitude: 28.613965,
        longitude: 77.209040,
        timestamp: base.add(const Duration(seconds: 4)),
        accuracy: 18.0,
        altitude: 0.0,
        altitudeAccuracy: 0.0,
        heading: 0.0,
        headingAccuracy: 0.0,
        speed: 0.1,
        speedAccuracy: 0.0,
      );

      final isGenuine = TrackingService.isGenuineMovement(
        candidate: pJitter,
        lastPoint: anchorTripPoint,
        stationaryAnchor: pAnchor,
      );

      expect(isGenuine, false, reason: 'Stationary wander within desk anchor must be rejected');
    });

    test('Real Walking Movement: Accepts incremental displacement even if sensor reports speed 0.0', () {
      final base = DateTime(2026, 10, 20, 12, 5, 0);

      final pStart = Position(
        latitude: 28.610000,
        longitude: 77.210000,
        timestamp: base,
        accuracy: 12.0,
        altitude: 0.0,
        altitudeAccuracy: 0.0,
        heading: 0.0,
        headingAccuracy: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
      );

      final lastTripPt = TripPoint(
        latitude: pStart.latitude,
        longitude: pStart.longitude,
        speed: 0.0,
        accuracy: 12.0,
        timestamp: base,
      );

      // User walking: moved 8 meters in 4 seconds (~2.0 m/s), but raw sensor reports speed: 0.0
      final pWalking = Position(
        latitude: 28.610065,
        longitude: 77.210040,
        timestamp: base.add(const Duration(seconds: 4)),
        accuracy: 14.0,
        altitude: 0.0,
        altitudeAccuracy: 0.0,
        heading: 45.0,
        headingAccuracy: 0.0,
        speed: 0.0, // Sensor didn't calculate Doppler speed
        speedAccuracy: 0.0,
      );

      final isGenuine = TrackingService.isGenuineMovement(
        candidate: pWalking,
        lastPoint: lastTripPt,
        stationaryAnchor: pStart,
      );

      expect(isGenuine, true, reason: 'Genuine walking displacement must be captured as phone moves');
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

      final lastPt = TripPoint(
        latitude: 28.6100,
        longitude: 77.2100,
        speed: 5.0,
        accuracy: 10.0,
        timestamp: t1,
      );

      // Coordinate jump of 500 meters in 2 seconds = 250 m/s = 900 km/h (impossible ground vehicle speed)
      final pJump = Position(
        latitude: 28.6145,
        longitude: 77.2145,
        timestamp: t2,
        accuracy: 15.0,
        altitude: 0.0,
        altitudeAccuracy: 0.0,
        heading: 0.0,
        headingAccuracy: 0.0,
        speed: 250.0,
        speedAccuracy: 0.0,
      );

      final isGenuine = TrackingService.isGenuineMovement(
        candidate: pJump,
        lastPoint: lastPt,
      );

      expect(isGenuine, false, reason: 'Impossible physical speed jump must be rejected');
    });

    test('Gross Accuracy Filter: Discards cell-tower level inaccuracies (> 75m)', () {
      final base = DateTime(2026, 10, 20, 16, 0, 0);

      final lastPt = TripPoint(
        latitude: 28.6100,
        longitude: 77.2100,
        speed: 2.0,
        accuracy: 10.0,
        timestamp: base,
      );

      final pCellTower = Position(
        latitude: 28.6105,
        longitude: 77.2105,
        timestamp: base.add(const Duration(seconds: 3)),
        accuracy: 120.0, // Cell tower triangulation
        altitude: 0.0,
        altitudeAccuracy: 0.0,
        heading: 0.0,
        headingAccuracy: 0.0,
        speed: 1.5,
        speedAccuracy: 0.0,
      );

      final isGenuine = TrackingService.isGenuineMovement(
        candidate: pCellTower,
        lastPoint: lastPt,
      );

      expect(isGenuine, false, reason: 'Accuracy > 75m indicates cellular triangulation and must be rejected from path');
    });

    test('Stationary Anchor Crawl Prevention: Consecutive wander points around desk do NOT get accepted', () {
      final base = DateTime(2026, 10, 20, 17, 0, 0);

      final pAnchor = Position(
        latitude: 28.613939,
        longitude: 77.209021,
        timestamp: base,
        accuracy: 16.0,
        altitude: 0.0,
        altitudeAccuracy: 0.0,
        heading: 0.0,
        headingAccuracy: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
      );

      final anchorTripPt = TripPoint(
        latitude: pAnchor.latitude,
        longitude: pAnchor.longitude,
        speed: 0.0,
        accuracy: 16.0,
        timestamp: base,
      );

      // Wander 1: 3.2m North
      final wander1 = Position(
        latitude: 28.613968,
        longitude: 77.209021,
        timestamp: base.add(const Duration(seconds: 2)),
        accuracy: 18.0,
        altitude: 0.0,
        altitudeAccuracy: 0.0,
        heading: 0.0,
        headingAccuracy: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
      );

      // Wander 2: 4.5m East of original anchor
      final wander2 = Position(
        latitude: 28.613939,
        longitude: 77.209067,
        timestamp: base.add(const Duration(seconds: 4)),
        accuracy: 20.0,
        altitude: 0.0,
        altitudeAccuracy: 0.0,
        heading: 90.0,
        headingAccuracy: 0.0,
        speed: 0.1,
        speedAccuracy: 0.0,
      );

      // Wander 3: 3.8m South of original anchor
      final wander3 = Position(
        latitude: 28.613905,
        longitude: 77.209021,
        timestamp: base.add(const Duration(seconds: 6)),
        accuracy: 19.0,
        altitude: 0.0,
        altitudeAccuracy: 0.0,
        heading: 180.0,
        headingAccuracy: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
      );

      // All wander points must be rejected relative to the anchor
      expect(
        TrackingService.isGenuineMovement(
          candidate: wander1,
          lastPoint: anchorTripPt,
          stationaryAnchor: pAnchor,
          isStationary: true,
        ),
        false,
        reason: 'Wander 1 within anchor tolerance must be rejected',
      );

      expect(
        TrackingService.isGenuineMovement(
          candidate: wander2,
          lastPoint: anchorTripPt,
          stationaryAnchor: pAnchor,
          isStationary: true,
        ),
        false,
        reason: 'Wander 2 within anchor tolerance must be rejected',
      );

      expect(
        TrackingService.isGenuineMovement(
          candidate: wander3,
          lastPoint: anchorTripPt,
          stationaryAnchor: pAnchor,
          isStationary: true,
        ),
        false,
        reason: 'Wander 3 within anchor tolerance must be rejected',
      );
    });

    test('In-Motion Curves & Corners: 3m incremental steps around Point C are captured without straight lines', () {
      final base = DateTime(2026, 10, 20, 18, 0, 0);

      // User actively moving (isStationary: false)
      final pt1 = TripPoint(
        latitude: 28.610000,
        longitude: 77.210000,
        speed: 1.2,
        accuracy: 8.0,
        timestamp: base,
      );

      // Step around corner C (3.5m away)
      final pt2 = Position(
        latitude: 28.610031,
        longitude: 77.210000,
        timestamp: base.add(const Duration(seconds: 2)),
        accuracy: 9.0,
        altitude: 0.0,
        altitudeAccuracy: 0.0,
        heading: 90.0,
        headingAccuracy: 0.0,
        speed: 1.1,
        speedAccuracy: 0.0,
      );

      final isStepCaptured = TrackingService.isGenuineMovement(
        candidate: pt2,
        lastPoint: pt1,
        isStationary: false,
      );

      expect(isStepCaptured, true, reason: 'In-motion 3.5m corner step must be captured so curves are smooth');
    });

    test('GPS Ground Truth: RoadRoutingService preserves authentic GPS breadcrumbs without detours', () async {
      final pts = [
        ll.LatLng(28.6139, 77.2090),
        ll.LatLng(28.6142, 77.2093),
        ll.LatLng(28.6145, 77.2096),
      ];

      final result = await roadRoutingService.getRoadRoute(tripId: 'test_trip', points: pts);
      expect(result.length, pts.length);
      expect(result[0].latitude, pts[0].latitude);
      expect(result[1].latitude, pts[1].latitude);
      expect(result[2].latitude, pts[2].latitude);
    });

    test('One-way trip (e.g. 95m) is NOT falsely classified or split as a round-trip', () {
      final base = DateTime(2026, 10, 20, 10, 0, 0);
      final p1 = TripPoint(latitude: 28.6100, longitude: 77.2100, speed: 1.2, accuracy: 6.0, timestamp: base);
      final p2 = TripPoint(latitude: 28.6103, longitude: 77.2103, speed: 1.2, accuracy: 6.0, timestamp: base.add(const Duration(seconds: 30)));
      final p3 = TripPoint(latitude: 28.6106, longitude: 77.2106, speed: 1.1, accuracy: 6.0, timestamp: base.add(const Duration(seconds: 60)));
      final p4 = TripPoint(latitude: 28.6108, longitude: 77.2108, speed: 0.0, accuracy: 5.0, timestamp: base.add(const Duration(seconds: 90)));

      final trip = TripModel(
        id: 'oneway_95m',
        title: 'Walk to Store',
        ownerId: 'u1',
        viewerIds: [],
        startedAt: base,
        endedAt: base.add(const Duration(seconds: 90)),
        distanceMeters: 95.0,
        isActive: false,
        points: [p1, p2, p3, p4],
      );

      final segments = TripDirectionHelper.buildSegmentsForTrips([trip]);
      expect(segments.length, 1, reason: 'A 95m one-way walk must remain a single segment, never split into Outward/Return');
      expect(segments.first.isReturn, false);
      expect(segments.first.directionLabel, 'Trip 1 • Outward');
    });
  });
}
