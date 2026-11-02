import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../models/user_device_model.dart';
import '../services/device_manager_service.dart';
import 'pulse_indicator.dart';

class RemoteDeviceInfoCard extends StatelessWidget {
  final UserDeviceModel device;
  final VoidCallback onRecenter;
  final VoidCallback onDismiss;

  const RemoteDeviceInfoCard({
    super.key,
    required this.device,
    required this.onRecenter,
    required this.onDismiss,
  });

  void _ringDevice(BuildContext context) {
    deviceManagerService.ringRemoteDevice(device.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.notifications_active_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Loud alarm triggered on ${device.name}!',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasValidCoord = device.latitude != 0.0 || device.longitude != 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: device.isOnline
              ? AppColors.danger.withValues(alpha: 0.3)
              : AppColors.border,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Top Bar: Device Name, Status, Battery & Close
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: device.isOnline
                      ? AppColors.danger.withValues(alpha: 0.12)
                      : Colors.grey.shade100,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(
                    device.platform == 'iOS'
                        ? Icons.phone_iphone_rounded
                        : Icons.phone_android_rounded,
                    color: device.isOnline ? AppColors.danger : Colors.grey.shade700,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            device.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.navyDark,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.danger.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'REMOTE',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: AppColors.danger,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (device.isOnline) ...[
                          const PulseIndicator(size: 8, color: AppColors.success),
                          const SizedBox(width: 4),
                          const Text(
                            'Online Now',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.success,
                            ),
                          ),
                        ] else ...[
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade400,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Last active ${device.lastSeenFormatted}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                        if (device.batteryLevel >= 0) ...[
                          const Text(' • ', style: TextStyle(color: AppColors.textMuted)),
                          Icon(
                            device.batteryLevel > 20
                                ? Icons.battery_charging_full_rounded
                                : Icons.battery_alert_rounded,
                            size: 13,
                            color: device.batteryLevel > 20
                                ? AppColors.primary
                                : AppColors.danger,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '${device.batteryLevel}%',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: device.batteryLevel > 20
                                  ? AppColors.textPrimary
                                  : AppColors.danger,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                tooltip: 'Back to My Phone',
                onPressed: onDismiss,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 2. Address Box
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.tileBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border, width: 0.8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.location_on_rounded,
                  color: AppColors.danger,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.address.isNotEmpty
                            ? device.address
                            : (hasValidCoord
                                ? '${device.latitude.toStringAsFixed(5)}°, ${device.longitude.toStringAsFixed(5)}°'
                                : 'Locating device...'),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (hasValidCoord) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${device.latitude.toStringAsFixed(4)}°, ${device.longitude.toStringAsFixed(4)}°',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 3. Actions Row (Navigate, Ring Alarm, Share, Recenter)
          Row(
            children: [
              // Navigate Button (Primary)
              Expanded(
                flex: 3,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: hasValidCoord
                      ? () => deviceManagerService.openDirections(
                            device.latitude,
                            device.longitude,
                            label: device.name,
                          )
                      : null,
                  icon: const Icon(Icons.navigation_rounded, size: 18),
                  label: const Text(
                    'Directions',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Ring Lost Phone Alarm Button
              Expanded(
                flex: 3,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => _ringDevice(context),
                  icon: const Icon(Icons.notifications_active_rounded, size: 18),
                  label: const Text(
                    'Ring Siren',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Share Location Button
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: hasValidCoord
                    ? () => deviceManagerService.shareDeviceLocation(device)
                    : null,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.tileBackground,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Center(
                    child: Icon(Icons.share_rounded, color: AppColors.navyDark, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Recenter on Device
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onRecenter,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.tileBackground,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.my_location_rounded,
                      color: AppColors.primary,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
