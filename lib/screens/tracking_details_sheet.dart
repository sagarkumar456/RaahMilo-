import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../core/app_colors.dart';
import '../services/geocoding_service.dart';

class TrackingDetailsSheet extends StatelessWidget {
  final Position? position;

  const TrackingDetailsSheet({super.key, required this.position});

  @override
  Widget build(BuildContext context) {
    final lat = position != null ? position!.latitude.toStringAsFixed(4) : '28.6139';
    final lng = position != null ? position!.longitude.toStringAsFixed(4) : '77.2090';
    final speed = position != null ? (position!.speed.clamp(0, 999) * 3.6).toStringAsFixed(0) : '52';
    final alt = position != null ? position!.altitude.toStringAsFixed(0) : '216';
    final acc = position != null ? position!.accuracy.toStringAsFixed(1) : '5.0';

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header: Title and Close button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Tracking Details',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navyDark,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _metricTile(
              icon: Icons.navigation_rounded,
              title: 'Current Area',
              value: geocodingService.currentTitle,
            ),
            const Divider(color: AppColors.border, height: 20),
            _metricTile(
              icon: Icons.location_on_rounded,
              title: 'Latitude',
              value: lat,
            ),
            const Divider(color: AppColors.border, height: 20),
            _metricTile(
              icon: Icons.place_rounded,
              title: 'Longitude',
              value: lng,
            ),
            const Divider(color: AppColors.border, height: 20),
            _metricTile(
              icon: Icons.speed_rounded,
              title: 'Speed',
              value: '$speed km/h',
            ),
            const Divider(color: AppColors.border, height: 20),
            _metricTile(
              icon: Icons.terrain_rounded,
              title: 'Altitude',
              value: '$alt m',
            ),
            const Divider(color: AppColors.border, height: 20),
            _metricTile(
              icon: Icons.gps_fixed_rounded,
              title: 'Accuracy',
              value: '$acc m',
            ),
            const Divider(color: AppColors.border, height: 20),
            _metricTile(
              icon: Icons.access_time_rounded,
              title: 'Last Update',
              value: 'Just now',
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _metricTile({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, color: AppColors.textSecondary, size: 22),
        const SizedBox(width: 16),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
