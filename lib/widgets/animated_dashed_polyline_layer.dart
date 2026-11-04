import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

/// Configuration for an animated dashed road polyline.
class RoutePolylineStyle {
  final List<ll.LatLng> points;
  final Color routeColor;
  final Color? casingColor;
  final double strokeWidth;
  final double casingWidth;
  final double dashWidth;
  final double dashLength;
  final double gapLength;
  final bool isMoving;

  const RoutePolylineStyle({
    required this.points,
    required this.routeColor,
    this.casingColor,
    this.strokeWidth = 6.2,
    this.casingWidth = 12.0,
    this.dashWidth = 2.8,
    this.dashLength = 13.0,
    this.gapLength = 8.5,
    this.isMoving = false,
  });
}

/// A hardware-accelerated FlutterMap layer that renders routes as sleek
/// navigation roads with embedded white dashes. When the vehicle is moving,
/// the dashes animate along the polyline towards the car; when stopped,
/// the dashes immediately freeze in place.
class AnimatedDashedPolylineLayer extends StatefulWidget {
  final List<RoutePolylineStyle> routes;

  const AnimatedDashedPolylineLayer({
    super.key,
    required this.routes,
  });

  @override
  State<AnimatedDashedPolylineLayer> createState() =>
      _AnimatedDashedPolylineLayerState();
}

class _AnimatedDashedPolylineLayerState
    extends State<AnimatedDashedPolylineLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
    );

    if (_hasMovingRoute(widget.routes)) {
      _controller.repeat();
    }
  }

  bool _hasMovingRoute(List<RoutePolylineStyle> routes) {
    for (final r in routes) {
      if (r.isMoving && r.points.length >= 2) return true;
    }
    return false;
  }

  @override
  void didUpdateWidget(covariant AnimatedDashedPolylineLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final isAnyMoving = _hasMovingRoute(widget.routes);
    if (isAnyMoving && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!isAnyMoving && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.routes.isEmpty) {
      return const SizedBox.shrink();
    }

    final camera = MapCamera.of(context);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return MobileLayerTransformer(
          child: CustomPaint(
            painter: _AnimatedDashedPolylinePainter(
              camera: camera,
              routes: widget.routes,
              phase: _controller.value,
            ),
            size: Size(camera.size.x, camera.size.y),
          ),
        );
      },
    );
  }
}

class _AnimatedDashedPolylinePainter extends CustomPainter {
  final MapCamera camera;
  final List<RoutePolylineStyle> routes;
  final double phase;

  _AnimatedDashedPolylinePainter({
    required this.camera,
    required this.routes,
    required this.phase,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final viewportRect = Rect.fromLTWH(-40, -40, size.width + 80, size.height + 80);

    for (final route in routes) {
      final pts = route.points;
      if (pts.length < 2) continue;

      // 1. Convert LatLng to camera canvas offsets with micro-distance deduplication (at least 2.5px)
      final offsets = <Offset>[];
      for (int i = 0; i < pts.length; i++) {
        final off = camera.getOffsetFromOrigin(pts[i]);
        if (offsets.isEmpty ||
            (off - offsets.last).distanceSquared >= 6.25) {
          offsets.add(off);
        }
      }

      if (offsets.length < 2) continue;

      // 2. Build continuous route path
      final basePath = Path();
      basePath.moveTo(offsets[0].dx, offsets[0].dy);
      for (int i = 1; i < offsets.length; i++) {
        basePath.lineTo(offsets[i].dx, offsets[i].dy);
      }

      // 3. Draw Outer Casing / Translucent Halo
      final casingPaint = Paint()
        ..color = route.casingColor ?? route.routeColor.withValues(alpha: 0.18)
        ..strokeWidth = route.casingWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      canvas.drawPath(basePath, casingPaint);

      // 4. Draw Vibrant Road Body
      final routePaint = Paint()
        ..color = route.routeColor
        ..strokeWidth = route.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      canvas.drawPath(basePath, routePaint);

      // 5. Draw Dashes: ONLY animate when vehicle is actively moving!
      // For stationary or completed history trips, skip heavy per-frame extractPath to keep UI at 60 FPS
      if (!route.isMoving) continue;

      final dashLength = route.dashLength;
      final gapLength = route.gapLength;
      final patternLength = dashLength + gapLength;
      final phaseOffset = phase * patternLength;

      final dashPaint = Paint()
        ..color = Colors.white
        ..strokeWidth = route.dashWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      final dashPath = Path();
      int dashesExtracted = 0;

      for (final metric in basePath.computeMetrics()) {
        final totalLength = metric.length;
        if (totalLength <= 0) continue;

        double current = -patternLength + phaseOffset;
        while (current < totalLength && dashesExtracted < 80) {
          final dashStart = current;
          final dashEnd = current + dashLength;

          if (dashEnd > 0 && dashStart < totalLength) {
            final startClamp = math.max(0.0, dashStart);
            final endClamp = math.min(totalLength, dashEnd);
            if (endClamp > startClamp) {
              final tangent = metric.getTangentForOffset(startClamp);
              if (tangent == null || viewportRect.contains(tangent.position)) {
                dashPath.addPath(
                  metric.extractPath(startClamp, endClamp),
                  Offset.zero,
                );
                dashesExtracted++;
              }
            }
          }
          current += patternLength;
        }
      }

      canvas.drawPath(dashPath, dashPaint);
    }
  }

  @override
  bool shouldRepaint(_AnimatedDashedPolylinePainter oldDelegate) {
    final hasMoving = routes.any((r) => r.isMoving && r.points.length >= 2);
    if (hasMoving && oldDelegate.phase != phase) {
      return true;
    }
    if (oldDelegate.camera != camera ||
        oldDelegate.routes.length != routes.length) {
      return true;
    }
    for (int i = 0; i < routes.length; i++) {
      if (routes[i].isMoving != oldDelegate.routes[i].isMoving ||
          routes[i].points.length != oldDelegate.routes[i].points.length ||
          routes[i].routeColor != oldDelegate.routes[i].routeColor) {
        return true;
      }
    }
    return false;
  }
}

