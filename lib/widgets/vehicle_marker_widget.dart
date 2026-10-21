import 'dart:math';
import 'package:flutter/material.dart';
import '../models/vehicle_type.dart';

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
    this.size = 42.0,
    this.showBadge = true,
  });

  @override
  State<VehicleMarkerWidget> createState() => _VehicleMarkerWidgetState();
}

class _VehicleMarkerWidgetState extends State<VehicleMarkerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    );

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
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.vehicleType.color;
    final size = widget.size;
    final isFacingLeft = sin(widget.heading) < -0.15;

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final pulse = _pulseAnimation.value;

        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // 1. Navigation Directional Beam (Points in forward travel direction)
            if (widget.isMoving)
              Transform.rotate(
                angle: widget.heading,
                child: CustomPaint(
                  size: Size(size * 1.5, size * 1.5),
                  painter: _DirectionBeamPainter(color: color),
                ),
              )
            else if (widget.isLive)
              // Subtle resting radar ring when tracking is active but stopped
              Container(
                width: size * (0.95 + 0.1 * pulse),
                height: size * (0.95 + 0.1 * pulse),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.08 * (1.0 - pulse * 0.4)),
                  border: Border.all(
                    color: color.withValues(alpha: 0.25 * (1.0 - pulse * 0.5)),
                    width: 1.2,
                  ),
                ),
              ),

            // 2. Realistic Ground Asphalt Contact Shadow (Firmly anchors vehicle onto the road, prevents floating/flying look)
            Positioned(
              bottom: 4,
              child: Container(
                width: size * 0.76,
                height: 8,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.all(Radius.elliptical(size * 0.76, 8)),
                  boxShadow: [
                    // Deep contact shadow directly under tires
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.55),
                      blurRadius: 3,
                      spreadRadius: 0.5,
                      offset: const Offset(0, 1),
                    ),
                    // Ambient road occlusion shadow
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 7,
                      spreadRadius: 2,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),

            // 3. 3D Vehicle Model (Firmly grounded on the road, no flying bounce)
            Transform.scale(
              scaleX: isFacingLeft ? -1.0 : 1.0, // Orients vehicle along movement direction
              child: SizedBox(
                width: size,
                height: size,
                child: Image.asset(
                  widget.vehicleType.assetPath,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Center(
                      child: Icon(
                        widget.vehicleType.icon,
                        color: color,
                        size: size * 0.75,
                      ),
                    );
                  },
                ),
              ),
            ),

            // 4. Compact Floating Status / Speed Pill
            if (widget.showBadge && widget.isLive)
              Positioned(
                top: -17,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xEE0F172A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: widget.isMoving
                          ? const Color(0xFF10B981).withValues(alpha: 0.8)
                          : const Color(0xFFF59E0B).withValues(alpha: 0.8),
                      width: 1.0,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black38,
                        blurRadius: 4,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.isMoving
                              ? const Color(0xFF10B981)
                              : const Color(0xFFF59E0B),
                        ),
                      ),
                      const SizedBox(width: 4),
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
                top: -16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: const Color(0xDD1E293B),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withValues(alpha: 0.5), width: 0.8),
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

class _DirectionBeamPainter extends CustomPainter {
  final Color color;
  _DirectionBeamPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: 0.6),
          color.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: size.width / 2))
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(center.dx, center.dy - size.height * 0.5);
    path.lineTo(center.dx + size.width * 0.24, center.dy);
    path.lineTo(center.dx, center.dy - size.height * 0.08);
    path.lineTo(center.dx - size.width * 0.24, center.dy);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _DirectionBeamPainter oldDelegate) => oldDelegate.color != color;
}
