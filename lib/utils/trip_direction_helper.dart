import 'dart:math';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../models/trip_model.dart';
import 'path_arrows.dart';

/// Represents a distinct trip route segment (e.g., Jaane Ka / Outward vs Aane Ka / Return)
class TripRouteSegment {
  final String id;
  final String title;
  final String directionLabel; // 'Jaane Ka (Outward)', 'Aane Ka (Return)', etc.
  final Color primaryColor;
  final Color casingColor;
  final List<ll.LatLng> points;
  final DateTime startedAt;
  final DateTime? endedAt;
  final double distanceMeters;
  final bool isReturn;
  final int tripNumber;
  final ll.LatLng? turnaroundPoint;

  TripRouteSegment({
    required this.id,
    required this.title,
    required this.directionLabel,
    required this.primaryColor,
    required this.casingColor,
    required this.points,
    required this.startedAt,
    this.endedAt,
    required this.distanceMeters,
    this.isReturn = false,
    this.tripNumber = 1,
    this.turnaroundPoint,
  });

  String get formattedDistance {
    final km = distanceMeters / 1000.0;
    return '${km.toStringAsFixed(1)} km';
  }
}

class TripDirectionHelper {
  // Unified single green route color requested by user
  static const Color colorPathGreen = Color(0xFF10B981); // Emerald Green
  static const Color colorOutward = colorPathGreen;
  static const Color colorReturn = colorPathGreen;

  /// Returns the unified green color for all paths
  static Color getColorForTrip(int index, int totalTrips, {bool isReturn = false}) {
    return colorPathGreen;
  }

  /// Builds a friendly title indicating direction
  static String getDirectionTitle(int index, int totalTrips, {bool isReturn = false}) {
    if (isReturn) return 'Return Trip';
    if (totalTrips == 1) return 'Trip 1 • Route';
    if (totalTrips == 2) {
      return index == 0 ? 'Trip 1 • Outward' : 'Trip 2 • Return';
    }
    if (index == 0) return 'Trip 1 • Outward';
    if (index == totalTrips - 1) return 'Trip ${index + 1} • Return';
    return 'Trip ${index + 1}';
  }

  /// Offsets a polyline by [offsetMeters] perpendicularly to the local road direction.
  /// Positive offset shifts to the right of the heading, negative shifts to the left.
  /// This creates a dual-carriageway lane effect so Outward and Return paths do not overlap.
  static List<ll.LatLng> offsetPolyline(List<ll.LatLng> points, double offsetMeters) {
    if (points.length < 2 || offsetMeters.abs() < 0.1) return points;

    final List<ll.LatLng> shifted = [];
    const double metersPerDegreeLat = 111320.0;

    for (int i = 0; i < points.length; i++) {
      double bearing;
      if (i == 0) {
        bearing = calculateBearing(points[0], points[1]);
      } else if (i == points.length - 1) {
        bearing = calculateBearing(points[i - 1], points[i]);
      } else {
        final b1 = calculateBearing(points[i - 1], points[i]);
        final b2 = calculateBearing(points[i], points[i + 1]);
        bearing = atan2(sin(b1) + sin(b2), cos(b1) + cos(b2));
      }

      // Perpendicular angle (+90 degrees = right side)
      final perpAngle = bearing + (pi / 2.0);
      final currentPt = points[i];

      final dLat = (offsetMeters * cos(perpAngle)) / metersPerDegreeLat;
      final latRad = currentPt.latitude * (pi / 180.0);
      final metersPerDegreeLng = metersPerDegreeLat * max(0.1, cos(latRad));
      final dLng = (offsetMeters * sin(perpAngle)) / metersPerDegreeLng;

      shifted.add(ll.LatLng(currentPt.latitude + dLat, currentPt.longitude + dLng));
    }

    return shifted;
  }

  /// Converts day trips into separated segments.
  /// If there's 1 single trip that loops back (round trip), it splits into Jaane Ka and Aane Ka.
  /// If there are multiple trips, it assigns each its outward/return characteristics.
  static List<TripRouteSegment> buildSegmentsForTrips(
    List<TripModel> dayTrips, {
    Map<String, List<ll.LatLng>>? snappedRoutes,
  }) {
    if (dayTrips.isEmpty) return [];

    // Sort chronologically (earliest trip first)
    final sortedTrips = List<TripModel>.from(dayTrips)
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));

    final List<TripRouteSegment> segments = [];

    // Case 1: Single trip on this day - check if it has a turnaround (round trip)
    if (sortedTrips.length == 1) {
      final trip = sortedTrips.first;
      final rawCoords = trip.points.map((p) => ll.LatLng(p.latitude, p.longitude)).toList();
      final routeCoords = (snappedRoutes != null && snappedRoutes.containsKey(trip.id))
          ? snappedRoutes[trip.id]!
          : rawCoords;

      final split = _detectAndSplitRoundTrip(trip, routeCoords);
      if (split != null) {
        return split;
      }

      // Single one-way trip
      segments.add(
        TripRouteSegment(
          id: trip.id,
          title: trip.title.isNotEmpty ? trip.title : 'Trip 1',
          directionLabel: 'Trip 1 • Outward',
          primaryColor: colorOutward,
          casingColor: colorOutward.withValues(alpha: 0.25),
          points: routeCoords,
          startedAt: trip.startedAt,
          endedAt: trip.endedAt,
          distanceMeters: trip.distanceMeters,
          isReturn: false,
          tripNumber: 1,
        ),
      );
      return segments;
    }

    // Case 2: Multiple trips on this day (e.g., Morning Jaane Ka + Evening Aane Ka)
    for (int i = 0; i < sortedTrips.length; i++) {
      final trip = sortedTrips[i];
      final isReturn = (i > 0 && i == sortedTrips.length - 1);
      final rawCoords = trip.points.map((p) => ll.LatLng(p.latitude, p.longitude)).toList();
      final routeCoords = (snappedRoutes != null && snappedRoutes.containsKey(trip.id))
          ? snappedRoutes[trip.id]!
          : rawCoords;

      final color = getColorForTrip(i, sortedTrips.length, isReturn: isReturn);
      final label = getDirectionTitle(i, sortedTrips.length, isReturn: isReturn);

      // Apply lateral offset when there are 2 overlapping trips
      // Trip 1 shifted slightly left (+2.5m), Trip 2 shifted slightly right (-2.5m)
      List<ll.LatLng> displayCoords = routeCoords;
      if (sortedTrips.length == 2) {
        final offset = i == 0 ? 2.5 : -2.5;
        displayCoords = offsetPolyline(routeCoords, offset);
      }

      segments.add(
        TripRouteSegment(
          id: trip.id,
          title: trip.title.isNotEmpty ? trip.title : 'Trip ${i + 1}',
          directionLabel: label,
          primaryColor: color,
          casingColor: color.withValues(alpha: 0.25),
          points: displayCoords,
          startedAt: trip.startedAt,
          endedAt: trip.endedAt,
          distanceMeters: trip.distanceMeters,
          isReturn: isReturn,
          tripNumber: i + 1,
        ),
      );
    }

    return segments;
  }

  /// Detects if a single continuous trip is a round trip (went somewhere and came back)
  static List<TripRouteSegment>? _detectAndSplitRoundTrip(
    TripModel trip,
    List<ll.LatLng> coords,
  ) {
    if (coords.length < 8) return null;

    final start = coords.first;
    final end = coords.last;

    // Find the point furthest away from the start
    double maxDistFromStart = 0.0;
    int maxIdx = -1;

    for (int i = 0; i < coords.length; i++) {
      final d = approximateDistanceMeters(start, coords[i]);
      if (d > maxDistFromStart) {
        maxDistFromStart = d;
        maxIdx = i;
      }
    }

    final endDistFromStart = approximateDistanceMeters(start, end);

    // If max distance is > 500m, the turnaround is between 25% and 80% through the trip,
    // and the trip returned back to within 45% of start distance, it's a round trip!
    final minIndex = (coords.length * 0.25).floor();
    final maxIndex = (coords.length * 0.80).floor();

    if (maxDistFromStart > 500 &&
        maxIdx >= minIndex &&
        maxIdx <= maxIndex &&
        endDistFromStart < (maxDistFromStart * 0.45)) {
      
      final outwardPts = coords.sublist(0, maxIdx + 1);
      final returnPts = coords.sublist(maxIdx);

      // Shift slightly to create dual lanes
      final shiftedOutward = offsetPolyline(outwardPts, 2.5);
      final shiftedReturn = offsetPolyline(returnPts, -2.5);

      final turnaroundPt = coords[maxIdx];

      return [
        TripRouteSegment(
          id: '${trip.id}_outward',
          title: 'Outward Route (Leg 1)',
          directionLabel: 'Trip 1 • Outward',
          primaryColor: colorOutward,
          casingColor: colorOutward.withValues(alpha: 0.25),
          points: shiftedOutward,
          startedAt: trip.startedAt,
          endedAt: trip.startedAt.add(
            Duration(minutes: ((trip.endedAt ?? DateTime.now()).difference(trip.startedAt).inMinutes ~/ 2)),
          ),
          distanceMeters: trip.distanceMeters / 2,
          isReturn: false,
          tripNumber: 1,
          turnaroundPoint: turnaroundPt,
        ),
        TripRouteSegment(
          id: '${trip.id}_return',
          title: 'Return Route (Leg 2)',
          directionLabel: 'Trip 2 • Return',
          primaryColor: colorReturn,
          casingColor: colorReturn.withValues(alpha: 0.25),
          points: shiftedReturn,
          startedAt: trip.startedAt.add(
            Duration(minutes: ((trip.endedAt ?? DateTime.now()).difference(trip.startedAt).inMinutes ~/ 2)),
          ),
          endedAt: trip.endedAt,
          distanceMeters: trip.distanceMeters / 2,
          isReturn: true,
          tripNumber: 2,
          turnaroundPoint: turnaroundPt,
        ),
      ];
    }

    return null;
  }
}
