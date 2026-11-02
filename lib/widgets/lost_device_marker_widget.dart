import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../models/user_device_model.dart';
import 'pulse_indicator.dart';

class LostDeviceMarkerWidget extends StatelessWidget {
  final UserDeviceModel device;
  final VoidCallback? onTap;

  const LostDeviceMarkerWidget({
    super.key,
    required this.device,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // 1. Radar Pulse Circle (Glowing Red/Emerald)
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (device.isOnline ? AppColors.danger : Colors.grey)
                  .withValues(alpha: 0.22),
            ),
          ),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (device.isOnline ? AppColors.danger : Colors.grey)
                  .withValues(alpha: 0.35),
            ),
          ),

          // 2. Center Phone Avatar
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: device.isOnline ? AppColors.danger : AppColors.navyDark,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Center(
              child: Icon(
                Icons.phone_android_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),

          // 3. Online / Offline Dot Indicator
          Positioned(
            right: 12,
            top: 12,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: device.isOnline ? AppColors.success : Colors.grey.shade400,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ),

          // 4. Floating Device Label Pill
          Positioned(
            bottom: -22,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.navyDark.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (device.isOnline)
                    const PulseIndicator(size: 6, color: AppColors.success)
                  else
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.grey,
                        shape: BoxShape.circle,
                      ),
                    ),
                  const SizedBox(width: 4),
                  Text(
                    device.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

