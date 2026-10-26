import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../models/stoppage_model.dart';

class StoppageMarkerWidget extends StatelessWidget {
  final StoppageModel stoppage;
  final VoidCallback onTap;
  final Color? customColor;
  final String? customLabel;
  final IconData? customIcon;

  const StoppageMarkerWidget({
    super.key,
    required this.stoppage,
    required this.onTap,
    this.customColor,
    this.customLabel,
    this.customIcon,
  });

  @override
  Widget build(BuildContext context) {
    if (stoppage.isEndStop) {
      return _buildEndStopMarker();
    }
    return _buildIntermediateStopMarker();
  }

  Widget _buildIntermediateStopMarker() {
    final stopColor = customColor ?? const Color(0xFFF59E0B);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Stoppage Duration Pill
            if (stoppage.formattedDuration.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                margin: const EdgeInsets.only(bottom: 2),
                decoration: BoxDecoration(
                  color: stopColor,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1)),
                  ],
                ),
                child: Text(
                  stoppage.formattedDuration,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
              ),

            // Circular Stop Pin with Stoppage Number
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: stopColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
                ],
              ),
              child: Center(
                child: Text(
                  '${stoppage.stopNumber}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEndStopMarker() {
    final endColor = customColor ?? const Color(0xFFDC2626);
    final labelText = customLabel ?? 'END STOP';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              margin: const EdgeInsets.only(bottom: 2),
              decoration: BoxDecoration(
                color: endColor,
                borderRadius: BorderRadius.circular(6),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1)),
                ],
              ),
              child: Text(
                labelText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.4,
                ),
              ),
            ),

            // Final Destination Pin
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: endColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(color: Colors.black38, blurRadius: 5, offset: Offset(0, 2)),
                ],
              ),
              child: Icon(
                customIcon ?? Icons.flag_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Start Origin Marker Widget
class StartOriginMarkerWidget extends StatelessWidget {
  final DateTime startedAt;
  final VoidCallback onTap;
  final Color? color;
  final String? label;
  final IconData? icon;

  const StartOriginMarkerWidget({
    super.key,
    required this.startedAt,
    required this.onTap,
    this.color,
    this.label,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final startColor = color ?? AppColors.success;
    final badgeLabel = label ?? 'START';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              margin: const EdgeInsets.only(bottom: 2),
              decoration: BoxDecoration(
                color: startColor,
                borderRadius: BorderRadius.circular(6),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1)),
                ],
              ),
              child: Text(
                badgeLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: startColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
                ],
              ),
              child: Icon(
                icon ?? Icons.trip_origin_rounded,
                color: Colors.white,
                size: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays an interactive stoppage details sheet
void showStoppageDetailsSheet(BuildContext context, StoppageModel stoppage) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 26),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: stoppage.isEndStop
                      ? const Color(0xFFDC2626).withValues(alpha: 0.12)
                      : const Color(0xFFF59E0B).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  stoppage.isEndStop ? Icons.flag_rounded : Icons.pause_circle_filled_rounded,
                  color: stoppage.isEndStop ? const Color(0xFFDC2626) : const Color(0xFFF59E0B),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stoppage.title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      stoppage.isEndStop
                          ? 'Final Destination Stoppage'
                          : 'Halted for ${stoppage.formattedDuration}',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: stoppage.isEndStop ? const Color(0xFFDC2626) : const Color(0xFFF59E0B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.tileBackground,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.access_time_rounded, size: 16, color: AppColors.textSecondary),
                    const SizedBox(width: 8),
                    Text(
                      stoppage.isEndStop ? 'Stop Time:' : 'Halt Duration:',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    const Spacer(),
                    Text(
                      stoppage.isEndStop ? stoppage.formattedTime : stoppage.formattedDuration,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                  ],
                ),
                const Divider(height: 14),
                Row(
                  children: [
                    const Icon(Icons.timeline_rounded, size: 16, color: AppColors.textSecondary),
                    const SizedBox(width: 8),
                    const Text('Time Details:', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    const Spacer(),
                    Text(
                      stoppage.formattedTime,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.navyDark),
                    ),
                  ],
                ),
                const Divider(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.location_on_rounded, size: 16, color: AppColors.primary),
                    const SizedBox(width: 8),
                    const Text('Coordinates:', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    const Spacer(),
                    Text(
                      '${stoppage.latitude.toStringAsFixed(5)}°, ${stoppage.longitude.toStringAsFixed(5)}°',
                      style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace', color: AppColors.textMuted),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
