import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

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

/// Computes contrasting chevron color so arrows are always crisp inside the route line
Color getContrastingChevronColor(Color? routeColor) {
  if (routeColor == null) return Colors.white;
  final luminance = routeColor.computeLuminance();
  // If route is very light (e.g. bright yellow), use deep slate, otherwise crisp white
  return luminance > 0.68 ? const Color(0xFF0F172A) : Colors.white;
}

/// Generates standard embedded navigation chevron arrows directly INSIDE the route path.
/// Zero chip containers, zero drop shadows — looks like Google Maps & Uber route arrows.
List<Marker> buildDirectionalArrowMarkers(
  List<ll.LatLng> points, {
  Color? routeColor,
  Color? arrowColor,
  double minDistanceMeters = 8.0,
}) {
  if (points.length < 2) return [];

  final List<Marker> markers = [];
  final Color chevronColor = arrowColor ?? getContrastingChevronColor(routeColor);

  // Calculate total path distance to adjust spacing
  double totalDistance = 0.0;
  for (int i = 0; i < points.length - 1; i++) {
    totalDistance += approximateDistanceMeters(points[i], points[i + 1]);
  }

  // Spacing: short trips every ~35m, medium every ~65m, long every ~120m
  final double targetSpacing = totalDistance < 500
      ? 35.0
      : totalDistance < 2500
          ? 65.0
          : 120.0;

  double accumulatedDist = 0.0;

  for (int i = 0; i < points.length - 1; i++) {
    final from = points[i];
    final to = points[i + 1];
    final segmentDist = approximateDistanceMeters(from, to);

    accumulatedDist += segmentDist;

    if (accumulatedDist >= targetSpacing && segmentDist >= minDistanceMeters) {
      accumulatedDist = 0.0;

      final midLat = (from.latitude + to.latitude) / 2.0;
      final midLng = (from.longitude + to.longitude) / 2.0;
      final bearing = calculateBearing(from, to);

      markers.add(
        Marker(
          point: ll.LatLng(midLat, midLng),
          width: 14,
          height: 14,
          alignment: Alignment.center,
          child: Transform.rotate(
            angle: bearing,
            child: CustomPaint(
              size: const Size(14, 14),
              painter: EmbeddedChevronPainter(
                color: chevronColor,
                strokeWidth: 2.3,
              ),
            ),
          ),
        ),
      );
    }
  }

  // Fallback: If no arrow triggered but path exists, add at midpoint
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
        width: 14,
        height: 14,
        alignment: Alignment.center,
        child: Transform.rotate(
          angle: bearing,
          child: CustomPaint(
            size: const Size(14, 14),
            painter: EmbeddedChevronPainter(
              color: chevronColor,
              strokeWidth: 2.3,
            ),
          ),
        ),
      ),
    );
  }

  return markers;
}

/// Standard navigation chevron painter that renders flush inside the polyline.
class EmbeddedChevronPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  const EmbeddedChevronPainter({
    required this.color,
    this.strokeWidth = 2.3,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    final w = size.width;
    final h = size.height;

    // Centered chevron pointing forward (UP / 0 radians)
    path.moveTo(w * 0.18, h * 0.70);
    path.lineTo(w * 0.50, h * 0.30);
    path.lineTo(w * 0.82, h * 0.70);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant EmbeddedChevronPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}
