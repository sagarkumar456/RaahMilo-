import 'dart:math';
import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../models/trip_model.dart';
import '../models/vehicle_type.dart';

class TripRouteThumbnail extends StatelessWidget {
  final List<TripPoint> points;
  final VehicleType? vehicleType;
  final double size;

  const TripRouteThumbnail({
    super.key,
    required this.points,
    this.vehicleType,
    this.size = 54,
  });

  @override
  Widget build(BuildContext context) {
    final vType = vehicleType ?? VehicleType.car;
    final themeColor = vType.color;
    final lightColor = vType.lightColor;

    if (points.length < 2) {
      // Beautiful distinct vehicle avatar thumbnail instead of identical fake curves
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: lightColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: themeColor.withValues(alpha: 0.35),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: themeColor.withValues(alpha: 0.08),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Vehicle icon centered
            Icon(
              vType.icon,
              size: size * 0.46,
              color: themeColor,
            ),
            // Bottom vehicle badge label
            Positioned(
              bottom: 3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: themeColor,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  vType.displayName,
                  style: const TextStyle(
                    fontSize: 7.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Has 2 or more points: draw actual recorded path
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: lightColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: themeColor.withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: themeColor.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Stack(
          children: [
            CustomPaint(
              size: Size(size, size),
              painter: _RouteThumbnailPainter(points, routeColor: themeColor),
            ),
            // Top-right tiny vehicle icon overlay
            Positioned(
              top: 3,
              right: 3,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                  border: Border.all(color: themeColor.withValues(alpha: 0.4), width: 0.6),
                ),
                child: Icon(
                  vType.icon,
                  size: 9,
                  color: themeColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteThumbnailPainter extends CustomPainter {
  final List<TripPoint> points;
  final Color routeColor;

  _RouteThumbnailPainter(this.points, {this.routeColor = AppColors.primary});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (var p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    final latSpan = (maxLat - minLat == 0) ? 0.001 : (maxLat - minLat);
    final lngSpan = (maxLng - minLng == 0) ? 0.001 : (maxLng - minLng);

    const pad = 8.0;
    final drawW = size.width - pad * 2;
    final drawH = size.height - pad * 2;

    final path = Path();
    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      final x = pad + ((p.longitude - minLng) / lngSpan) * drawW;
      final y = size.height - (pad + ((p.latitude - minLat) / latSpan) * drawH);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    // Outer glow/casing
    final casingPaint = Paint()
      ..color = routeColor.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, casingPaint);

    // Main route line
    final linePaint = Paint()
      ..color = routeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);

    // Direction arrow at midpoint of path
    final midIdx = points.length ~/ 2;
    final pFrom = points[midIdx > 0 ? midIdx - 1 : 0];
    final pTo = points[midIdx];
    final fx = pad + ((pFrom.longitude - minLng) / lngSpan) * drawW;
    final fy = size.height - (pad + ((pFrom.latitude - minLat) / latSpan) * drawH);
    final tx = pad + ((pTo.longitude - minLng) / lngSpan) * drawW;
    final ty = size.height - (pad + ((pTo.latitude - minLat) / latSpan) * drawH);

    final angle = atan2(ty - fy, tx - fx);
    if ((tx - fx).abs() > 1 || (ty - fy).abs() > 1) {
      final arrowPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      final arrowPath = Path();
      const arrowLen = 5.5;
      arrowPath.moveTo(tx, ty);
      arrowPath.lineTo(
        tx - arrowLen * cos(angle - 0.5),
        ty - arrowLen * sin(angle - 0.5),
      );
      arrowPath.lineTo(
        tx - arrowLen * cos(angle + 0.5),
        ty - arrowLen * sin(angle + 0.5),
      );
      arrowPath.close();
      canvas.drawPath(arrowPath, arrowPaint);
    }

    // Start point (Green circle with white border)
    final first = points.first;
    final startX = pad + ((first.longitude - minLng) / lngSpan) * drawW;
    final startY = size.height - (pad + ((first.latitude - minLat) / latSpan) * drawH);
    canvas.drawCircle(Offset(startX, startY), 4.0, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(startX, startY), 3.0, Paint()..color = AppColors.success);

    // End point (Red/Crimson circle with white border)
    final last = points.last;
    final endX = pad + ((last.longitude - minLng) / lngSpan) * drawW;
    final endY = size.height - (pad + ((last.latitude - minLat) / latSpan) * drawH);
    canvas.drawCircle(Offset(endX, endY), 4.0, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(endX, endY), 3.0, Paint()..color = AppColors.danger);
  }

  @override
  bool shouldRepaint(covariant _RouteThumbnailPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.routeColor != routeColor;
}
