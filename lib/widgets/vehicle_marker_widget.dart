import 'dart:math';
import 'package:flutter/material.dart';
import '../models/vehicle_type.dart';

/// Top-down precision GPS navigation vehicle marker.
///
/// Firmly anchored onto the road asphalt (no floating/flying look).
/// Always aligns the FRONT of the vehicle in the direction of movement.
/// Features real-time smooth steering interpolation, road contact shadow,
/// forward projector headlights, and readable upright speed indicator.
class VehicleMarkerWidget extends StatefulWidget {
  final VehicleType vehicleType;
  final String? speedText;
  final bool isLive;
  final bool isMoving;
  final double heading; // in radians (0 = North, pi/2 = East, etc.)
  final double size;
  final bool showBadge;

  const VehicleMarkerWidget({
    super.key,
    required this.vehicleType,
    this.speedText,
    this.isLive = true,
    this.isMoving = false,
    this.heading = 0.0,
    this.size = 46.0,
    this.showBadge = true,
  });

  @override
  State<VehicleMarkerWidget> createState() => _VehicleMarkerWidgetState();
}

class _VehicleMarkerWidgetState extends State<VehicleMarkerWidget>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  late AnimationController _headingController;
  late Animation<double> _headingAnimation;
  double _currentHeading = 0.0;
  double _targetHeading = 0.0;

  @override
  void initState() {
    super.initState();
    _currentHeading = widget.heading;
    _targetHeading = widget.heading;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    );

    _headingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _headingAnimation = Tween<double>(
      begin: _currentHeading,
      end: _targetHeading,
    ).animate(
      CurvedAnimation(parent: _headingController, curve: Curves.easeOutCubic),
    )..addListener(() {
        if (mounted) setState(() {});
      });

    if (widget.isMoving || widget.isLive) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant VehicleMarkerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if ((widget.isMoving || widget.isLive) && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.isMoving && !widget.isLive && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.value = 0.0;
    }

    if (widget.heading != oldWidget.heading) {
      _animateToHeading(widget.heading);
    }
  }

  void _animateToHeading(double target) {
    // Shortest angular distance interpolation (prevents 360-degree spin across north boundary)
    double diff = (target - _currentHeading) % (2 * pi);
    if (diff > pi) diff -= 2 * pi;
    if (diff < -pi) diff += 2 * pi;

    if (diff.abs() < 0.005) return;

    final start = _headingController.isAnimating ? _headingAnimation.value : _currentHeading;
    _currentHeading = start;
    _targetHeading = start + diff;

    _headingAnimation = Tween<double>(
      begin: _currentHeading,
      end: _targetHeading,
    ).animate(
      CurvedAnimation(parent: _headingController, curve: Curves.easeOutCubic),
    );

    _headingController.forward(from: 0.0).then((_) {
      if (mounted) {
        _currentHeading = _targetHeading % (2 * pi);
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _headingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.vehicleType.color;
    final size = widget.size;

    final renderedHeading = _headingController.isAnimating
        ? _headingAnimation.value
        : _currentHeading;

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final pulse = _pulseAnimation.value;

        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // 1. Subtle resting radar ring when tracking is active but stopped
            if (widget.isLive && !widget.isMoving)
              Container(
                width: size * (0.95 + 0.1 * pulse),
                height: size * (0.95 + 0.1 * pulse),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.08 * (1.0 - pulse * 0.4)),
                  border: Border.all(
                    color: color.withValues(alpha: 0.28 * (1.0 - pulse * 0.5)),
                    width: 1.2,
                  ),
                ),
              ),

            // 2. Rotating Vehicle System (Aligned with travel heading: Front faces forward)
            Transform.rotate(
              angle: renderedHeading,
              child: SizedBox(
                width: size,
                height: size,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    // Forward Road Illumination Headlight Beams (only when moving)
                    if (widget.isMoving)
                      CustomPaint(
                        size: Size(size, size),
                        painter: _HeadlightBeamPainter(
                          color: color,
                          vehicleType: widget.vehicleType,
                        ),
                      ),

                    // Rotating Asphalt Contact Occlusion Shadow (Firmly anchors tires to the road)
                    CustomPaint(
                      size: Size(size, size),
                      painter: _AsphaltShadowPainter(
                        vehicleType: widget.vehicleType,
                      ),
                    ),

                    // True Top-Down Orthographic Navigation Vehicle Model
                    CustomPaint(
                      size: Size(size, size),
                      painter: _TopDownVehiclePainter(
                        vehicleType: widget.vehicleType,
                        color: color,
                        isMoving: widget.isMoving,
                        walkPhase: pulse,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 3. Compact Floating Status / Speed Pill (Always horizontal & right-side up)
            if (widget.showBadge && widget.isLive)
              Positioned(
                top: -18,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: const Color(0xEE0F172A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: widget.isMoving
                          ? const Color(0xFF10B981).withValues(alpha: 0.85)
                          : const Color(0xFFF59E0B).withValues(alpha: 0.85),
                      width: 1.0,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black38,
                        blurRadius: 4,
                        offset: Offset(0, 1.5),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 5.5,
                        height: 5.5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.isMoving
                              ? const Color(0xFF10B981)
                              : const Color(0xFFF59E0B),
                        ),
                      ),
                      const SizedBox(width: 4.5),
                      Text(
                        widget.isMoving
                            ? (widget.speedText ?? 'Moving')
                            : 'Stopped',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (widget.showBadge && widget.speedText != null && widget.speedText!.isNotEmpty)
              Positioned(
                top: -17,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xEE1E293B),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withValues(alpha: 0.6), width: 0.9),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 3,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Text(
                    widget.speedText!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9.0,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _AsphaltShadowPainter extends CustomPainter {
  final VehicleType vehicleType;
  _AsphaltShadowPainter({required this.vehicleType});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    switch (vehicleType) {
      case VehicleType.car:
        final w = size.width * 0.52;
        final h = size.height * 0.88;
        // Deep contact shadow under chassis & tires
        final contactRRect = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx, cy + 1.2), width: w * 0.95, height: h * 0.96),
          const Radius.circular(8),
        );
        canvas.drawRRect(
          contactRRect,
          Paint()
            ..color = Colors.black.withValues(alpha: 0.45)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5),
        );
        // Ambient soft dispersion shadow
        final ambientRRect = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx, cy + 2.0), width: w * 1.08, height: h * 1.05),
          const Radius.circular(10),
        );
        canvas.drawRRect(
          ambientRRect,
          Paint()
            ..color = Colors.black.withValues(alpha: 0.22)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0),
        );
        break;

      case VehicleType.bike:
      case VehicleType.scooty:
        final w = size.width * 0.36;
        final h = size.height * 0.82;
        final contactRRect = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx, cy + 1.0), width: w, height: h),
          const Radius.circular(6),
        );
        canvas.drawRRect(
          contactRRect,
          Paint()
            ..color = Colors.black.withValues(alpha: 0.42)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0),
        );
        break;

      case VehicleType.human:
        // Ground contact shadow under the walking child & sneakers
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(cx, cy + size.height * 0.08),
            width: size.width * 0.46,
            height: size.height * 0.40,
          ),
          Paint()
            ..color = Colors.black.withValues(alpha: 0.32)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0),
        );
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _AsphaltShadowPainter oldDelegate) =>
      oldDelegate.vehicleType != vehicleType;
}

class _HeadlightBeamPainter extends CustomPainter {
  final Color color;
  final VehicleType vehicleType;
  _HeadlightBeamPainter({required this.color, required this.vehicleType});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    if (vehicleType == VehicleType.car) {
      final w = size.width * 0.52;
      final h = size.height * 0.88;

      final beamTopY = cy - h * 1.05;
      final leftHLY = cy - h * 0.44;

      // Left headlight projector beam
      final leftBeam = Path()
        ..moveTo(cx - w * 0.30, leftHLY)
        ..lineTo(cx - w * 0.75, beamTopY)
        ..lineTo(cx - w * 0.08, beamTopY)
        ..close();

      final leftBeamPaint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Color(0xCCFEF08A),
            Color(0x55FEF08A),
            Color(0x00FEF08A),
          ],
        ).createShader(Rect.fromLTRB(cx - w * 0.75, beamTopY, cx - w * 0.08, leftHLY))
        ..style = PaintingStyle.fill;

      canvas.drawPath(leftBeam, leftBeamPaint);

      // Right headlight projector beam
      final rightBeam = Path()
        ..moveTo(cx + w * 0.30, leftHLY)
        ..lineTo(cx + w * 0.08, beamTopY)
        ..lineTo(cx + w * 0.75, beamTopY)
        ..close();

      final rightBeamPaint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Color(0xCCFEF08A),
            Color(0x55FEF08A),
            Color(0x00FEF08A),
          ],
        ).createShader(Rect.fromLTRB(cx + w * 0.08, beamTopY, cx + w * 0.75, leftHLY))
        ..style = PaintingStyle.fill;

      canvas.drawPath(rightBeam, rightBeamPaint);
    } else if (vehicleType == VehicleType.bike || vehicleType == VehicleType.scooty) {
      final h = size.height * 0.82;
      final beamTopY = cy - h * 0.95;
      final hlY = cy - h * 0.40;

      final beam = Path()
        ..moveTo(cx, hlY)
        ..lineTo(cx - size.width * 0.32, beamTopY)
        ..lineTo(cx + size.width * 0.32, beamTopY)
        ..close();

      final beamPaint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Color(0xDDFFFBEB),
            Color(0x55FEF08A),
            Color(0x00FEF08A),
          ],
        ).createShader(Rect.fromLTRB(cx - size.width * 0.32, beamTopY, cx + size.width * 0.32, hlY))
        ..style = PaintingStyle.fill;

      canvas.drawPath(beam, beamPaint);
    } else {
      // Human: forward directional cone
      final cone = Path()
        ..moveTo(cx, cy - size.height * 0.15)
        ..lineTo(cx - size.width * 0.28, cy - size.height * 0.70)
        ..lineTo(cx + size.width * 0.28, cy - size.height * 0.70)
        ..close();

      final conePaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            color.withValues(alpha: 0.55),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTRB(cx - size.width * 0.28, cy - size.height * 0.70, cx + size.width * 0.28, cy))
        ..style = PaintingStyle.fill;

      canvas.drawPath(cone, conePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _HeadlightBeamPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.vehicleType != vehicleType;
}

class _TopDownVehiclePainter extends CustomPainter {
  final VehicleType vehicleType;
  final Color color;
  final bool isMoving;
  final double walkPhase;

  _TopDownVehiclePainter({
    required this.vehicleType,
    required this.color,
    required this.isMoving,
    this.walkPhase = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    switch (vehicleType) {
      case VehicleType.car:
        _drawCar(canvas, size, color, isMoving);
        break;
      case VehicleType.bike:
        _drawBike(canvas, size, color, isMoving);
        break;
      case VehicleType.scooty:
        _drawScooty(canvas, size, color, isMoving);
        break;
      case VehicleType.human:
        _drawHuman(canvas, size, color, isMoving, walkPhase);
        break;
    }
  }

  void _drawCar(Canvas canvas, Size size, Color color, bool isMoving) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final w = size.width * 0.52;
    final h = size.height * 0.88;

    // 1. Four low-profile rubber tires
    final tirePaint = Paint()..color = const Color(0xFF1E293B)..style = PaintingStyle.fill;
    final rimPaint = Paint()..color = const Color(0xFF64748B)..style = PaintingStyle.fill;

    final tires = [
      Offset(cx - w * 0.46, cy - h * 0.27), // Front-Left
      Offset(cx + w * 0.46, cy - h * 0.27), // Front-Right
      Offset(cx - w * 0.47, cy + h * 0.25), // Rear-Left
      Offset(cx + w * 0.47, cy + h * 0.25), // Rear-Right
    ];

    for (final t in tires) {
      final tRect = Rect.fromCenter(center: t, width: w * 0.13, height: h * 0.17);
      canvas.drawRRect(RRect.fromRectAndRadius(tRect, const Radius.circular(2.5)), tirePaint);
      final rimRect = Rect.fromCenter(center: t, width: w * 0.06, height: h * 0.09);
      canvas.drawRRect(RRect.fromRectAndRadius(rimRect, const Radius.circular(1.5)), rimPaint);
    }

    // 2. Aerodynamic Body Chassis (Front points straight UP towards North)
    final bodyPath = Path();
    bodyPath.moveTo(cx, cy - h * 0.49);
    // Front right curve & bumper
    bodyPath.quadraticBezierTo(cx + w * 0.28, cy - h * 0.49, cx + w * 0.38, cy - h * 0.44);
    bodyPath.quadraticBezierTo(cx + w * 0.45, cy - h * 0.35, cx + w * 0.46, cy - h * 0.22);
    // Right waistline (slight tuck)
    bodyPath.quadraticBezierTo(cx + w * 0.41, cy - h * 0.02, cx + w * 0.48, cy + h * 0.18);
    // Rear right haunch
    bodyPath.quadraticBezierTo(cx + w * 0.49, cy + h * 0.36, cx + w * 0.41, cy + h * 0.47);
    // Rear bumper
    bodyPath.quadraticBezierTo(cx + w * 0.20, cy + h * 0.49, cx, cy + h * 0.49);
    // Rear left bumper
    bodyPath.quadraticBezierTo(cx - w * 0.20, cy + h * 0.49, cx - w * 0.41, cy + h * 0.47);
    // Rear left haunch
    bodyPath.quadraticBezierTo(cx - w * 0.49, cy + h * 0.36, cx - w * 0.48, cy + h * 0.18);
    // Left waistline
    bodyPath.quadraticBezierTo(cx - w * 0.41, cy - h * 0.02, cx - w * 0.46, cy - h * 0.22);
    // Front left curve & bumper
    bodyPath.quadraticBezierTo(cx - w * 0.45, cy - h * 0.35, cx - w * 0.38, cy - h * 0.44);
    bodyPath.quadraticBezierTo(cx - w * 0.28, cy - h * 0.49, cx, cy - h * 0.49);
    bodyPath.close();

    // Metallic body gradient
    final bodyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          _adjustColor(color, -0.22),
          color,
          _adjustColor(color, 0.20),
          color,
          _adjustColor(color, -0.22),
        ],
        stops: const [0.0, 0.32, 0.50, 0.68, 1.0],
      ).createShader(Rect.fromCenter(center: Offset(cx, cy), width: w, height: h))
      ..style = PaintingStyle.fill;
    canvas.drawPath(bodyPath, bodyPaint);

    // Chassis fine perimeter border
    final borderPaint = Paint()
      ..color = _adjustColor(color, -0.38)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawPath(bodyPath, borderPaint);

    // 3. Side Mirrors
    final mirrorPaint = Paint()..color = _adjustColor(color, -0.10)..style = PaintingStyle.fill;
    final leftMirror = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx - w * 0.52, cy - h * 0.16), width: w * 0.10, height: h * 0.09),
      const Radius.circular(2),
    );
    final rightMirror = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx + w * 0.52, cy - h * 0.16), width: w * 0.10, height: h * 0.09),
      const Radius.circular(2),
    );
    canvas.drawRRect(leftMirror, mirrorPaint);
    canvas.drawRRect(rightMirror, mirrorPaint);

    // 4. Hood character crease lines
    final creasePaint = Paint()
      ..color = _adjustColor(color, -0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;
    canvas.drawLine(Offset(cx - w * 0.15, cy - h * 0.42), Offset(cx - w * 0.22, cy - h * 0.24), creasePaint);
    canvas.drawLine(Offset(cx + w * 0.15, cy - h * 0.42), Offset(cx + w * 0.22, cy - h * 0.24), creasePaint);

    // 5. Front Windshield (Deep obsidian tinted curved glass)
    final windshieldPath = Path();
    windshieldPath.moveTo(cx - w * 0.30, cy - h * 0.21);
    windshieldPath.quadraticBezierTo(cx, cy - h * 0.23, cx + w * 0.30, cy - h * 0.21);
    windshieldPath.lineTo(cx + w * 0.27, cy - h * 0.05);
    windshieldPath.quadraticBezierTo(cx, cy - h * 0.06, cx - w * 0.27, cy - h * 0.05);
    windshieldPath.close();

    final glassPaint = Paint()..color = const Color(0xFF0F172A)..style = PaintingStyle.fill;
    canvas.drawPath(windshieldPath, glassPaint);

    // Windshield diagonal reflection glare
    final glarePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.32)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(cx - w * 0.18, cy - h * 0.20), Offset(cx - w * 0.06, cy - h * 0.07), glarePaint);

    // 6. Panoramic Sunroof / Cabin Roof
    final roofRect = Rect.fromLTRB(cx - w * 0.25, cy - h * 0.04, cx + w * 0.25, cy + h * 0.17);
    final roofRRect = RRect.fromRectAndRadius(roofRect, const Radius.circular(3));
    final roofPaint = Paint()..color = const Color(0xFF1E293B)..style = PaintingStyle.fill;
    canvas.drawRRect(roofRRect, roofPaint);

    // Roof glass highlight
    final roofGlassRect = Rect.fromLTRB(cx - w * 0.20, cy - h * 0.02, cx + w * 0.20, cy + h * 0.14);
    canvas.drawRRect(
      RRect.fromRectAndRadius(roofGlassRect, const Radius.circular(2)),
      Paint()..color = const Color(0xFF0B132B),
    );

    // Shark-fin antenna
    final finPath = Path()
      ..moveTo(cx, cy + h * 0.11)
      ..lineTo(cx - w * 0.04, cy + h * 0.16)
      ..lineTo(cx + w * 0.04, cy + h * 0.16)
      ..close();
    canvas.drawPath(finPath, Paint()..color = _adjustColor(color, -0.15));

    // 7. Rear Windshield
    final rearGlassPath = Path();
    rearGlassPath.moveTo(cx - w * 0.26, cy + h * 0.18);
    rearGlassPath.quadraticBezierTo(cx, cy + h * 0.17, cx + w * 0.26, cy + h * 0.18);
    rearGlassPath.lineTo(cx + w * 0.29, cy + h * 0.32);
    rearGlassPath.quadraticBezierTo(cx, cy + h * 0.33, cx - w * 0.29, cy + h * 0.32);
    rearGlassPath.close();
    canvas.drawPath(rearGlassPath, glassPaint);

    // 8. High-intensity LED Headlights (White/Ice-Blue)
    final hlPaint = Paint()..color = const Color(0xFFF8FAFC)..style = PaintingStyle.fill;
    final hlGlowPaint = Paint()
      ..color = const Color(0xFF38BDF8).withValues(alpha: 0.8)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);

    // Left headlight
    final leftHLRect = Rect.fromCenter(center: Offset(cx - w * 0.30, cy - h * 0.44), width: w * 0.14, height: h * 0.06);
    canvas.drawOval(leftHLRect, hlGlowPaint);
    canvas.drawOval(leftHLRect, hlPaint);

    // Right headlight
    final rightHLRect = Rect.fromCenter(center: Offset(cx + w * 0.30, cy - h * 0.44), width: w * 0.14, height: h * 0.06);
    canvas.drawOval(rightHLRect, hlGlowPaint);
    canvas.drawOval(rightHLRect, hlPaint);

    // 9. Rear LED Taillights (Vibrant Ruby Red)
    final tlPaint = Paint()..color = const Color(0xFFEF4444)..style = PaintingStyle.fill;
    final tlGlowPaint = Paint()
      ..color = const Color(0xFFDC2626).withValues(alpha: 0.8)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);

    final leftTLRect = Rect.fromCenter(center: Offset(cx - w * 0.34, cy + h * 0.46), width: w * 0.14, height: h * 0.04);
    canvas.drawRRect(RRect.fromRectAndRadius(leftTLRect, const Radius.circular(1.5)), tlGlowPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(leftTLRect, const Radius.circular(1.5)), tlPaint);

    final rightTLRect = Rect.fromCenter(center: Offset(cx + w * 0.34, cy + h * 0.46), width: w * 0.14, height: h * 0.04);
    canvas.drawRRect(RRect.fromRectAndRadius(rightTLRect, const Radius.circular(1.5)), tlGlowPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(rightTLRect, const Radius.circular(1.5)), tlPaint);
  }

  void _drawBike(Canvas canvas, Size size, Color color, bool isMoving) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final w = size.width * 0.42;
    final h = size.height * 0.86;

    // 1. Front and Rear Wheels
    final tirePaint = Paint()..color = const Color(0xFF1E293B)..style = PaintingStyle.fill;
    final rimPaint = Paint()..color = const Color(0xFF64748B)..style = PaintingStyle.fill;

    // Front tire
    final fTireRect = Rect.fromCenter(center: Offset(cx, cy - h * 0.36), width: w * 0.18, height: h * 0.22);
    canvas.drawRRect(RRect.fromRectAndRadius(fTireRect, const Radius.circular(3)), tirePaint);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, cy - h * 0.36), width: w * 0.08, height: h * 0.12), const Radius.circular(1.5)), rimPaint);

    // Rear tire
    final rTireRect = Rect.fromCenter(center: Offset(cx, cy + h * 0.34), width: w * 0.20, height: h * 0.22);
    canvas.drawRRect(RRect.fromRectAndRadius(rTireRect, const Radius.circular(3)), tirePaint);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, cy + h * 0.34), width: w * 0.09, height: h * 0.12), const Radius.circular(1.5)), rimPaint);

    // 2. Wide Handlebars & Grips
    final barPaint = Paint()..color = const Color(0xFF334155)..strokeWidth = 2.4..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(cx - w * 0.46, cy - h * 0.22), Offset(cx + w * 0.46, cy - h * 0.22), barPaint);

    // Rubber Grips
    final gripPaint = Paint()..color = const Color(0xFF0F172A)..strokeWidth = 3.6..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(cx - w * 0.46, cy - h * 0.22), Offset(cx - w * 0.34, cy - h * 0.22), gripPaint);
    canvas.drawLine(Offset(cx + w * 0.34, cy - h * 0.22), Offset(cx + w * 0.46, cy - h * 0.22), gripPaint);

    // Mirrors
    canvas.drawCircle(Offset(cx - w * 0.44, cy - h * 0.27), 2.2, Paint()..color = const Color(0xFF94A3B8));
    canvas.drawCircle(Offset(cx + w * 0.44, cy - h * 0.27), 2.2, Paint()..color = const Color(0xFF94A3B8));

    // 3. Sculpted Fuel Tank
    final tankPath = Path();
    tankPath.moveTo(cx, cy - h * 0.24);
    tankPath.quadraticBezierTo(cx + w * 0.32, cy - h * 0.16, cx + w * 0.24, cy + h * 0.02);
    tankPath.quadraticBezierTo(cx, cy + h * 0.05, cx - w * 0.24, cy + h * 0.02);
    tankPath.quadraticBezierTo(cx - w * 0.32, cy - h * 0.16, cx, cy - h * 0.24);
    tankPath.close();

    final tankPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [_adjustColor(color, -0.2), color, _adjustColor(color, 0.2), color, _adjustColor(color, -0.2)],
      ).createShader(Rect.fromCenter(center: Offset(cx, cy - h * 0.1), width: w * 0.6, height: h * 0.3))
      ..style = PaintingStyle.fill;
    canvas.drawPath(tankPath, tankPaint);

    // Chrome gas cap
    canvas.drawCircle(Offset(cx, cy - h * 0.14), 2.5, Paint()..color = const Color(0xFFE2E8F0));

    // 4. Dual Rider & Pillion Seat
    final seatPath = Path();
    seatPath.moveTo(cx - w * 0.18, cy + h * 0.03);
    seatPath.lineTo(cx + w * 0.18, cy + h * 0.03);
    seatPath.quadraticBezierTo(cx + w * 0.22, cy + h * 0.18, cx + w * 0.12, cy + h * 0.30);
    seatPath.lineTo(cx, cy + h * 0.33);
    seatPath.lineTo(cx - w * 0.12, cy + h * 0.30);
    seatPath.quadraticBezierTo(cx - w * 0.22, cy + h * 0.18, cx - w * 0.18, cy + h * 0.03);
    seatPath.close();
    canvas.drawPath(seatPath, Paint()..color = const Color(0xFF0F172A));

    // 5. Headlight & Taillight
    final hlPaint = Paint()..color = const Color(0xFFF8FAFC);
    canvas.drawCircle(Offset(cx, cy - h * 0.44), 3.2, Paint()..color = const Color(0xFF38BDF8)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5));
    canvas.drawCircle(Offset(cx, cy - h * 0.44), 2.4, hlPaint);

    // Tail LED
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, cy + h * 0.42), width: w * 0.16, height: h * 0.04), const Radius.circular(1.5)),
      Paint()..color = const Color(0xFFEF4444),
    );
  }

  void _drawScooty(Canvas canvas, Size size, Color color, bool isMoving) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final w = size.width * 0.42;
    final h = size.height * 0.84;

    // 1. Front and Rear Wheels
    final tirePaint = Paint()..color = const Color(0xFF1E293B)..style = PaintingStyle.fill;
    final fTireRect = Rect.fromCenter(center: Offset(cx, cy - h * 0.34), width: w * 0.17, height: h * 0.20);
    canvas.drawRRect(RRect.fromRectAndRadius(fTireRect, const Radius.circular(3)), tirePaint);
    final rTireRect = Rect.fromCenter(center: Offset(cx, cy + h * 0.32), width: w * 0.19, height: h * 0.20);
    canvas.drawRRect(RRect.fromRectAndRadius(rTireRect, const Radius.circular(3)), tirePaint);

    // 2. Handlebars & Retro Round Mirrors
    final barPaint = Paint()..color = const Color(0xFF475569)..strokeWidth = 2.2..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(cx - w * 0.44, cy - h * 0.20), Offset(cx + w * 0.44, cy - h * 0.20), barPaint);
    canvas.drawCircle(Offset(cx - w * 0.42, cy - h * 0.25), 2.4, Paint()..color = const Color(0xFFCBD5E1));
    canvas.drawCircle(Offset(cx + w * 0.42, cy - h * 0.25), 2.4, Paint()..color = const Color(0xFFCBD5E1));

    // 3. Front Apron Shield
    final apronPath = Path();
    apronPath.moveTo(cx, cy - h * 0.28);
    apronPath.quadraticBezierTo(cx + w * 0.34, cy - h * 0.24, cx + w * 0.30, cy - h * 0.08);
    apronPath.lineTo(cx + w * 0.18, cy - h * 0.03);
    apronPath.lineTo(cx - w * 0.18, cy - h * 0.03);
    apronPath.lineTo(cx - w * 0.30, cy - h * 0.08);
    apronPath.quadraticBezierTo(cx - w * 0.34, cy - h * 0.24, cx, cy - h * 0.28);
    apronPath.close();

    final bodyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [_adjustColor(color, -0.15), color, _adjustColor(color, 0.2), color, _adjustColor(color, -0.15)],
      ).createShader(Rect.fromCenter(center: Offset(cx, cy), width: w, height: h))
      ..style = PaintingStyle.fill;
    canvas.drawPath(apronPath, bodyPaint);

    // 4. Floorboard with Ribs
    final floorRect = Rect.fromLTRB(cx - w * 0.20, cy - h * 0.03, cx + w * 0.20, cy + h * 0.10);
    canvas.drawRRect(RRect.fromRectAndRadius(floorRect, const Radius.circular(2)), Paint()..color = const Color(0xFF334155));

    // 5. Contoured Scooter Seat
    final seatRect = Rect.fromLTRB(cx - w * 0.23, cy + h * 0.09, cx + w * 0.23, cy + h * 0.32);
    canvas.drawRRect(RRect.fromRectAndRadius(seatRect, const Radius.circular(6)), Paint()..color = const Color(0xFF0F172A));

    // 6. Round Chrome Headlight
    canvas.drawCircle(Offset(cx, cy - h * 0.27), 3.5, Paint()..color = const Color(0xFFE2E8F0));
    canvas.drawCircle(Offset(cx, cy - h * 0.27), 2.5, Paint()..color = const Color(0xFFFEF08A));

    // 7. Taillight
    canvas.drawOval(Rect.fromCenter(center: Offset(cx, cy + h * 0.36), width: w * 0.18, height: h * 0.05), Paint()..color = const Color(0xFFEF4444));
  }

  void _drawHuman(Canvas canvas, Size size, Color color, bool isMoving, double walkPhase) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final w = size.width;
    final h = size.height;

    // Smooth pendulum swing (-1.0 to +1.0) for natural walking strides
    final stride = isMoving ? sin((walkPhase - 0.5) * pi) : 0.0;

    // 1. Walking Dust / Step Puffs behind trailing foot (when moving)
    if (isMoving && stride.abs() > 0.3) {
      final trailingFootX = stride > 0 ? (cx - w * 0.14) : (cx + w * 0.14);
      final puffAlpha = (0.28 * stride.abs()).clamp(0.0, 0.28);
      canvas.drawCircle(
        Offset(trailingFootX, cy + h * 0.30),
        2.5 + stride.abs() * 1.5,
        Paint()..color = Colors.white.withValues(alpha: puffAlpha),
      );
    }

    // 2. Cute Sneakers (Feet) - oscillate with stride
    // Left Foot (stride forward = -Y, backward = +Y)
    final lFootY = cy + h * 0.18 - stride * (h * 0.13);
    final lFootCenter = Offset(cx - w * 0.14, lFootY);
    _drawSneaker(canvas, lFootCenter, w * 0.15, h * 0.21);

    // Right Foot (opposite swing)
    final rFootY = cy + h * 0.18 + stride * (h * 0.13);
    final rFootCenter = Offset(cx + w * 0.14, rFootY);
    _drawSneaker(canvas, rFootCenter, w * 0.15, h * 0.21);

    // 3. Torso / Shirt (Rounded T-shirt)
    final torsoRect = Rect.fromCenter(
      center: Offset(cx, cy + h * 0.03),
      width: w * 0.40,
      height: h * 0.28,
    );
    final torsoRRect = RRect.fromRectAndRadius(torsoRect, const Radius.circular(7));

    // Shirt gradient
    final shirtPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          _adjustColor(color, 0.15),
          color,
          _adjustColor(color, -0.12),
        ],
      ).createShader(torsoRect)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(torsoRRect, shirtPaint);

    // Subtle shirt border for crisp definition
    canvas.drawRRect(
      torsoRRect,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9,
    );

    // 4. Cute School Backpack / Bag on back
    final bagRect = Rect.fromCenter(
      center: Offset(cx, cy + h * 0.09),
      width: w * 0.32,
      height: h * 0.21,
    );
    final bagRRect = RRect.fromRectAndRadius(bagRect, const Radius.circular(5.5));

    // Vibrant school backpack color (amber / golden orange)
    const bagColor = Color(0xFFF59E0B);
    final bagPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFFFBBF24),
          bagColor,
          const Color(0xFFD97706),
        ],
      ).createShader(bagRect)
      ..style = PaintingStyle.fill;

    // Drop shadow under backpack onto torso
    canvas.drawRRect(
      bagRRect.shift(const Offset(0, 1.2)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );
    canvas.drawRRect(bagRRect, bagPaint);

    // Backpack front zipper pocket line
    final zipPaint = Paint()
      ..color = const Color(0xFF92400E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawLine(
      Offset(cx - w * 0.10, cy + h * 0.11),
      Offset(cx + w * 0.10, cy + h * 0.11),
      zipPaint,
    );
    // Silver zipper pull tab
    canvas.drawCircle(Offset(cx, cy + h * 0.11), 1.2, Paint()..color = const Color(0xFFE2E8F0));

    // Two backpack straps looping over shoulders
    final strapPaint = Paint()
      ..color = const Color(0xFF334155)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx - w * 0.09, cy + h * 0.04), Offset(cx - w * 0.09, cy - h * 0.04), strapPaint);
    canvas.drawLine(Offset(cx + w * 0.09, cy + h * 0.04), Offset(cx + w * 0.09, cy - h * 0.04), strapPaint);

    // Backpack top handle
    canvas.drawArc(
      Rect.fromCenter(center: Offset(cx, cy - h * 0.02), width: w * 0.10, height: h * 0.07),
      pi,
      pi,
      false,
      Paint()
        ..color = const Color(0xFF92400E)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // 5. Swinging Arms & Peach Hands (Swing opposite to feet)
    // Left Arm (swings with +stride)
    final lArmSwing = stride * (h * 0.10);
    final lShoulder = Offset(cx - w * 0.19, cy - h * 0.01);
    final lHandCenter = Offset(cx - w * 0.22, cy + h * 0.07 + lArmSwing);
    _drawArmAndHand(canvas, lShoulder, lHandCenter, color);

    // Right Arm (swings with -stride)
    final rArmSwing = -stride * (h * 0.10);
    final rShoulder = Offset(cx + w * 0.19, cy - h * 0.01);
    final rHandCenter = Offset(cx + w * 0.22, cy + h * 0.07 + rArmSwing);
    _drawArmAndHand(canvas, rShoulder, rHandCenter, color);

    // 6. Child Head, Skin & Ears
    const skinTone = Color(0xFFFFD2A6);
    final headCenter = Offset(cx, cy - h * 0.10);
    final headRadius = w * 0.17;

    // Cute ears
    canvas.drawCircle(Offset(cx - w * 0.17, cy - h * 0.10), 2.8, Paint()..color = skinTone);
    canvas.drawCircle(Offset(cx - w * 0.17, cy - h * 0.10), 1.4, Paint()..color = const Color(0xFFFCA5A5));
    canvas.drawCircle(Offset(cx + w * 0.17, cy - h * 0.10), 2.8, Paint()..color = skinTone);
    canvas.drawCircle(Offset(cx + w * 0.17, cy - h * 0.10), 1.4, Paint()..color = const Color(0xFFFCA5A5));

    // Head base
    canvas.drawCircle(headCenter, headRadius, Paint()..color = skinTone);

    // 7. Child's Baseball Cap (Visor pointing straight UP in travel heading)
    const capColor = Color(0xFF1D4ED8); // Royal cobalt cap

    // Cap crown dome (sitting on back half of head)
    final crownPath = Path();
    crownPath.addArc(
      Rect.fromCircle(center: headCenter, radius: headRadius - 0.5),
      -0.15 * pi,
      1.3 * pi,
    );
    crownPath.close();
    canvas.drawPath(
      crownPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF3B82F6),
            capColor,
            const Color(0xFF1E40AF),
          ],
        ).createShader(Rect.fromCircle(center: headCenter, radius: headRadius))
        ..style = PaintingStyle.fill,
    );

    // White button on cap crown
    canvas.drawCircle(Offset(cx, cy - h * 0.09), 1.8, Paint()..color = Colors.white);

    // Forward Cap Visor / Bill (Curves forward UP in travel heading)
    final visorPath = Path();
    visorPath.moveTo(cx - w * 0.15, cy - h * 0.12);
    visorPath.quadraticBezierTo(
      cx,
      cy - h * 0.28, // Forward tip of visor pointing UP
      cx + w * 0.15,
      cy - h * 0.12,
    );
    visorPath.quadraticBezierTo(
      cx,
      cy - h * 0.17,
      cx - w * 0.15,
      cy - h * 0.12,
    );
    visorPath.close();

    // Visor fill
    canvas.drawPath(
      visorPath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF60A5FA),
            Color(0xFF2563EB),
            Color(0xFF1D4ED8),
          ],
        ).createShader(Rect.fromLTRB(cx - w * 0.15, cy - h * 0.28, cx + w * 0.15, cy - h * 0.12))
        ..style = PaintingStyle.fill,
    );

    // Crisp white trim along visor front lip
    final visorLip = Path();
    visorLip.moveTo(cx - w * 0.15, cy - h * 0.12);
    visorLip.quadraticBezierTo(
      cx,
      cy - h * 0.28,
      cx + w * 0.15,
      cy - h * 0.12,
    );
    canvas.drawPath(
      visorLip,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawSneaker(Canvas canvas, Offset center, double width, double height) {
    final shoeRect = Rect.fromCenter(center: center, width: width, height: height);
    final shoeRRect = RRect.fromRectAndRadius(shoeRect, const Radius.circular(3.5));

    // Sneaker body (Dark stylish slate)
    canvas.drawRRect(shoeRRect, Paint()..color = const Color(0xFF1E293B));

    // White rubber toe bumper in front (-Y)
    final toeRect = Rect.fromCenter(
      center: Offset(center.dx, center.dy - height * 0.32),
      width: width * 0.88,
      height: height * 0.28,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(toeRect, const Radius.circular(2.5)),
      Paint()..color = Colors.white,
    );

    // Sneaker white sole border
    canvas.drawRRect(
      shoeRRect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9,
    );

    // Cute laces cross stitches
    final lacesPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;
    canvas.drawLine(
      Offset(center.dx - width * 0.24, center.dy),
      Offset(center.dx + width * 0.24, center.dy),
      lacesPaint,
    );
    canvas.drawLine(
      Offset(center.dx - width * 0.24, center.dy + height * 0.18),
      Offset(center.dx + width * 0.24, center.dy + height * 0.18),
      lacesPaint,
    );
  }

  void _drawArmAndHand(Canvas canvas, Offset shoulder, Offset hand, Color sleeveColor) {
    // Sleeve
    final sleevePaint = Paint()
      ..color = sleeveColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(shoulder, Offset((shoulder.dx + hand.dx) / 2, (shoulder.dy + hand.dy) / 2), sleevePaint);

    // Bare forearm
    final armPaint = Paint()
      ..color = const Color(0xFFFFD2A6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset((shoulder.dx + hand.dx) / 2, (shoulder.dy + hand.dy) / 2), hand, armPaint);

    // Peach Hand
    canvas.drawCircle(hand, 2.7, Paint()..color = const Color(0xFFFFD2A6));
    canvas.drawCircle(
      hand,
      2.7,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6,
    );
  }

  Color _adjustColor(Color c, double amount) {
    final hsl = HSLColor.fromColor(c);
    final newLightness = (hsl.lightness + amount).clamp(0.0, 1.0);
    return hsl.withLightness(newLightness).toColor();
  }

  @override
  bool shouldRepaint(covariant _TopDownVehiclePainter oldDelegate) =>
      oldDelegate.vehicleType != vehicleType ||
      oldDelegate.color != color ||
      oldDelegate.isMoving != isMoving ||
      (vehicleType == VehicleType.human && oldDelegate.walkPhase != walkPhase);
}
