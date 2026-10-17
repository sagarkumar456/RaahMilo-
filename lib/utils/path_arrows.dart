import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../core/app_colors.dart';

/// Helper to calculate geographic bearing (heading in radians) from one LatLng to another
double calculateBearing(ll.LatLng from, ll.LatLng to) {
  final dLng = (to.longitude - from.longitude) * (pi / 180.0);
  final lat1 = from.latitude * (pi / 180.0);
  final lat2 = to.latitude * (pi / 180.0);

  final y = sin(dLng) * cos(lat2);
  final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng);

  return atan2(y, x); // 0 = North, pi/2 = East, pi = South, -pi/2 = West
}

/// Approximate distance between two LatLng in meters
double approximateDistanceMeters(ll.LatLng from, ll.LatLng to) {
  final latMid = (from.latitude + to.latitude) / 2.0 * (pi / 180.0);
  final dx = (to.longitude - from.longitude) * (pi / 180.0) * 6371000.0 * cos(latMid);
  final dy = (to.latitude - from.latitude) * (pi / 180.0) * 6371000.0;
  return sqrt(dx * dx + dy * dy);
}

/// Generates directional arrow markers along a polyline path to show the movement direction
List<Marker> buildDirectionalArrowMarkers(
  List<ll.LatLng> points, {
  Color arrowColor = AppColors.primary,
  double minDistanceMeters = 25.0, // Minimum distance before placing an arrow
}) {
  if (points.length < 2) return [];

  final List<Marker> markers = [];
  double accumulatedDist = 0.0;

  // Determine an adaptive spacing so the map doesn't get overcrowded
  // For short trips (< 500m): arrow every ~35m
  // For medium trips (1km - 5km): arrow every ~100m
  // For long trips (> 5km): arrow every ~250m
  double totalDistance = 0.0;
  for (int i = 0; i < points.length - 1; i++) {
    totalDistance += approximateDistanceMeters(points[i], points[i + 1]);
  }

  final double targetSpacing = totalDistance < 600
      ? 40.0
      : totalDistance < 3000
          ? 90.0
          : 180.0;

  for (int i = 0; i < points.length - 1; i++) {
    final from = points[i];
    final to = points[i + 1];
    final segmentDist = approximateDistanceMeters(from, to);

    accumulatedDist += segmentDist;

    // Check if we reached the distance threshold for an arrow
    if (accumulatedDist >= targetSpacing && segmentDist >= 6.0) {
      accumulatedDist = 0.0;

      final midLat = (from.latitude + to.latitude) / 2.0;
      final midLng = (from.longitude + to.longitude) / 2.0;
      final bearing = calculateBearing(from, to);

      markers.add(
        Marker(
          point: ll.LatLng(midLat, midLng),
          width: 22,
          height: 22,
          alignment: Alignment.center,
          child: Transform.rotate(
            angle: bearing,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: arrowColor.withValues(alpha: 0.3), width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 4,
                    offset: const Offset(0, 1.5),
                  ),
                ],
              ),
              child: Center(
                child: Icon(
                  Icons.navigation_rounded,
                  size: 12,
                  color: arrowColor,
                ),
              ),
            ),
          ),
        ),
      );
    }
  }

  // If path is long enough but accumulated distance didn't trigger, add at least one midpoint arrow
  if (markers.isEmpty && points.length >= 2) {
    final midIndex = points.length ~/ 2;
    final from = points[midIndex > 0 ? midIndex - 1 : 0];
    final to = points[midIndex > 0 ? midIndex : 1];
    final bearing = calculateBearing(from, to);

    markers.add(
      Marker(
        point: ll.LatLng(
          (from.latitude + to.latitude) / 2.0,
          (from.longitude + to.longitude) / 2.0,
        ),
        width: 22,
        height: 22,
        alignment: Alignment.center,
        child: Transform.rotate(
          angle: bearing,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: arrowColor.withValues(alpha: 0.3), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 4,
                  offset: const Offset(0, 1.5),
                ),
              ],
            ),
            child: Center(
              child: Icon(
                Icons.navigation_rounded,
                size: 12,
                color: arrowColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  return markers;
}
