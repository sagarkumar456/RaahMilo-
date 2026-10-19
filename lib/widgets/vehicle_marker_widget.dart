import 'package:flutter/material.dart';
import '../models/vehicle_type.dart';

class VehicleMarkerWidget extends StatelessWidget {
  final VehicleType vehicleType;
  final String? speedText;
  final bool isLive;
  final double size;

  const VehicleMarkerWidget({
    super.key,
    required this.vehicleType,
    this.speedText,
    this.isLive = true,
    this.size = 58.0,
  });

  @override
  Widget build(BuildContext context) {
    final color = vehicleType.color;

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        // 1. Radar Pulse Glow when live tracking
        if (isLive)
          Container(
            width: size + 20,
            height: size + 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.18),
              border: Border.all(
                color: color.withValues(alpha: 0.35),
                width: 1.5,
              ),
            ),
          ),

        // 2. Realistic Navigation Ground Shadow
        Positioned(
          bottom: 2,
          child: Container(
            width: size * 0.72,
            height: 14,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.all(Radius.elliptical(size * 0.72, 14)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
        ),

        // 3. Navigation Base Disc (Gives grounding & theme accent on map)
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.88),
            border: Border.all(color: color, width: 2.2),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.35),
                blurRadius: 12,
                spreadRadius: 1,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipOval(
            child: Padding(
              padding: const EdgeInsets.all(4.0),
              child: Image.asset(
                vehicleType.assetPath,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Center(
                    child: Icon(
                      vehicleType.icon,
                      color: color,
                      size: size * 0.55,
                    ),
                  );
                },
              ),
            ),
          ),
        ),

        // 4. Floating Mini Speed & Mode Pill
        if (speedText != null && speedText!.isNotEmpty)
          Positioned(
            top: -22,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withValues(alpha: 0.8), width: 1.2),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black38,
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(vehicleType.icon, color: Colors.white, size: 11),
                  const SizedBox(width: 4),
                  Text(
                    speedText!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
