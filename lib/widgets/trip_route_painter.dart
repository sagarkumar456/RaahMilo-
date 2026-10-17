import 'dart:math';
import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../models/trip_model.dart';

class TripRouteThumbnail extends StatelessWidget {
  final List<TripPoint> points;
  final double size;

  const TripRouteThumbnail({
    super.key,
    required this.points,
    this.size = 54,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.tileBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CustomPaint(
          painter: _RouteThumbnailPainter(points),
        ),
      ),
    );
  }
}

class _RouteThumbnailPainter extends CustomPainter {
  final List<TripPoint> points;

  _RouteThumbnailPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFFEFF4FA);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    if (points.isEmpty) {
      final p1 = Offset(size.width * 0.2, size.height * 0.7);
      final p2 = Offset(size.width * 0.5, size.height * 0.3);
      final p3 = Offset(size.width * 0.8, size.height * 0.6);

      final path = Path()
        ..moveTo(p1.dx, p1.dy)
        ..quadraticBezierTo(p2.dx, p2.dy, p3.dx, p3.dy);

      final linePaint = Paint()
        ..color = AppColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;

      canvas.drawPath(path, linePaint);
      canvas.drawCircle(p1, 3.5, Paint()..color = AppColors.success);
      canvas.drawCircle(p3, 3.5, Paint()..color = AppColors.danger);
      return;
    }

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

    final linePaint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, linePaint);

    // Direction arrow at midpoint of path
    if (points.length >= 2) {
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
        const arrowLen = 6.0;
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
    }

    // Start point (Green)
    final first = points.first;
    final startX = pad + ((first.longitude - minLng) / lngSpan) * drawW;
    final startY = size.height - (pad + ((first.latitude - minLat) / latSpan) * drawH);
    canvas.drawCircle(Offset(startX, startY), 3.5, Paint()..color = AppColors.success);

    // End point (Red)
    final last = points.last;
    final endX = pad + ((last.longitude - minLng) / lngSpan) * drawW;
    final endY = size.height - (pad + ((last.latitude - minLat) / latSpan) * drawH);
    canvas.drawCircle(Offset(endX, endY), 3.5, Paint()..color = AppColors.danger);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
