import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../models/shared_device_model.dart';
import '../services/device_manager_service.dart';
import '../services/share_service.dart';
import '../services/tracking_service.dart';
import '../widgets/device_selector_sheet.dart';
import '../widgets/pulse_indicator.dart';
import 'geofence_screen.dart';
import 'location_disabled_screen.dart';
import 'notifications_screen.dart';
import 'premium_screen.dart';
import 'share_screen.dart';
import 'shared_device_map_screen.dart';
import 'shared_user_history_screen.dart';
import 'support_chat_screen.dart';

class DashboardScreen extends StatelessWidget {
  final ValueChanged<int> onNavigateTab;

  const DashboardScreen({
    super.key,
    required this.onNavigateTab,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([trackingService, deviceManagerService]),
      builder: (context, _) {
        final isActive = trackingService.active;
        final isStarting = trackingService.starting;
        final isGpsOn = trackingService.isLocationServiceEnabled && trackingService.hasLocationPermission;

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          children: [
            // 1. Top Hero Card: Tracking Status & Timer (Auto-tracked, always on)
            GestureDetector(
              onTap: isGpsOn
                  ? (!isActive
                      ? () => trackingService.checkLocationHealth(autoStart: true)
                      : null)
                  : () {
                      Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LocationDisabledScreen(),
                          fullscreenDialog: true,
                        ),
                      ).then((res) {
                        if (res == true) {
                          trackingService.checkLocationHealth(autoStart: true);
                        }
                      });
                    },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isGpsOn
                        ? AppColors.success.withValues(alpha: 0.3)
                        : AppColors.danger.withValues(alpha: 0.3),
                    width: isGpsOn ? 1.5 : 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isGpsOn
                          ? AppColors.success.withValues(alpha: 0.1)
                          : Colors.black.withValues(alpha: 0.04),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Pulse dot & texts
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (isGpsOn)
                                PulseIndicator(
                                  size: 10,
                                  color: isActive ? AppColors.success : AppColors.primary,
                                )
                              else
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                    color: AppColors.danger,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              const SizedBox(width: 8),
                              Text(
                                isGpsOn
                                    ? (isActive ? 'Tracking' : (isStarting ? 'Connecting GPS' : 'Tracking Ready'))
                                    : 'Location Off',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: isGpsOn ? AppColors.textPrimary : AppColors.danger,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            isGpsOn
                                ? (isActive
                                    ? 'Continuous live tracking active'
                                    : (isStarting ? 'Acquiring GPS signal...' : 'Live tracking ready • Always on'))
                                : 'Location off • Tap to enable in Settings',
                            style: TextStyle(
                              fontSize: 13,
                              color: isGpsOn ? AppColors.textSecondary : AppColors.danger,
                              fontWeight: isGpsOn ? FontWeight.normal : FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Auto-Tracking "ALWAYS ON" status badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isGpsOn
                            ? (isActive ? AppColors.successLight : AppColors.primary.withValues(alpha: 0.1))
                            : AppColors.dangerLight,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isGpsOn
                              ? (isActive
                                  ? AppColors.success.withValues(alpha: 0.4)
                                  : AppColors.primary.withValues(alpha: 0.4))
                              : AppColors.danger.withValues(alpha: 0.4),
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isGpsOn
                                ? (isActive ? Icons.shield_rounded : (isStarting ? Icons.sync_rounded : Icons.shield_outlined))
                                : Icons.location_off_rounded,
                            size: 16,
                            color: isGpsOn
                                ? (isActive ? AppColors.success : AppColors.primary)
                                : AppColors.danger,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isGpsOn
                                ? (isActive ? 'ALWAYS ON' : (isStarting ? 'STARTING' : 'ALWAYS ON'))
                                : 'LOCATION OFF',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                              color: isGpsOn
                                  ? (isActive ? AppColors.success : AppColors.primary)
                                  : AppColors.danger,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),

            // Today's Activity Stats Card (Distance, Speed, Mode)
            _buildTodayActivityCard(context),

            const SizedBox(height: 18),

            // 2. 6 Grid Features
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: 1.05,
              children: [
                _dashboardGridCard(
                  icon: Icons.navigation_rounded,
                  iconColor: AppColors.primary,
                  bgColor: AppColors.primaryLight,
                  title: 'Live Tracking',
                  subtitle: 'View on map',
                  onTap: () => onNavigateTab(1), // Map tab
                ),
                _dashboardGridCard(
                  icon: Icons.alt_route_rounded,
                  iconColor: const Color(0xFF8B5CF6),
                  bgColor: const Color(0xFFF3E8FF),
                  title: 'Trip History',
                  subtitle: 'Past routes',
                  onTap: () => onNavigateTab(2), // History tab
                ),
                _dashboardGridCard(
                  icon: Icons.radar_rounded,
                  iconColor: const Color(0xFF10B981),
                  bgColor: const Color(0xFFE6F9F0),
                  title: 'Geofence',
                  subtitle: 'Safe zones & alerts',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const GeofenceScreen()),
                    );
                  },
                ),
                _dashboardGridCard(
                  icon: Icons.support_agent_rounded,
                  iconColor: const Color(0xFF2563EB),
                  bgColor: const Color(0xFFEFF6FF),
                  title: 'AI Support',
                  subtitle: 'Chat & Helpdesk',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SupportChatScreen()),
                    );
                  },
                ),
                _dashboardGridCard(
                  icon: Icons.share_location_rounded,
                  iconColor: const Color(0xFF0D9488),
                  bgColor: const Color(0xFFCCFBF1),
                  title: 'Share Device',
                  subtitle: 'Live location',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ShareScreen()),
                    );
                  },
                ),
                _dashboardGridCard(
                  icon: Icons.notifications_active_rounded,
                  iconColor: const Color(0xFFF59E0B),
                  bgColor: const Color(0xFFFEF3C7),
                  title: 'Activity Alerts',
                  subtitle: 'Zone & trip log',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 24),

            // My Account Devices Section (Find My Phone / Multi-Device)
            _buildMyAccountDevicesSection(context),

            const SizedBox(height: 24),

            // Live Shared Devices Section (User A sharing with User B)
            _buildSharedWithMeSection(context),

            const SizedBox(height: 24),

            // 3. Upgrade to Premium Banner
            InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PremiumScreen()),
                );
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF7C3AED).withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.workspace_premium_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Upgrade to Premium',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Get advanced features',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: Colors.white70,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),

            if (trackingService.lastError != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.dangerLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        trackingService.lastError!,
                        style: const TextStyle(color: AppColors.danger, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  Widget _dashboardGridCard({
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border, width: 1.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: iconColor, size: 23),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTodayActivityCard(BuildContext context) {
    final pos = trackingService.current;
    final isActive = trackingService.active;
    final speed = (pos != null && isActive && pos.speed > 0.5)
        ? (pos.speed.clamp(0, 999) * 3.6).toStringAsFixed(0)
        : '0';
    final vehicle = trackingService.currentVehicle;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onNavigateTab(1),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.straighten_rounded, color: AppColors.primary, size: 14),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'DISTANCE',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      trackingService.todayDistanceFormatted,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(width: 1, height: 32, color: AppColors.border),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onNavigateTab(1),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.speed_rounded, color: Color(0xFF2563EB), size: 14),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'SPEED',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$speed km/h',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.navyDark,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(width: 1, height: 32, color: AppColors.border),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onNavigateTab(1),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: vehicle.color.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(vehicle.icon, color: vehicle.color, size: 14),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'MODE',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      vehicle.displayName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: vehicle.color,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyAccountDevicesSection(BuildContext context) {
    final devices = deviceManagerService.devices;
    final currentDeviceId = deviceManagerService.deviceId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.devices_other_rounded,
                color: AppColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'My Devices (Find My Phone)',
                style: TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navyDark,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => showDeviceSelectorSheet(context),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    devices.isNotEmpty ? '${devices.length} Linked' : 'Manage',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.primary, size: 18),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (devices.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.phone_android_rounded,
                      color: AppColors.primary,
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        deviceManagerService.deviceName.isNotEmpty
                            ? deviceManagerService.deviceName
                            : 'This Device',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Connected & Ready • Log into other phones to track them',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                  onPressed: () => showDeviceSelectorSheet(context),
                ),
              ],
            ),
          )
        else
          Column(
            children: devices.map((dev) {
              final isCurrent = dev.id == currentDeviceId;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isCurrent
                        ? AppColors.primary.withValues(alpha: 0.4)
                        : AppColors.border,
                    width: isCurrent ? 1.4 : 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: dev.isOnline
                                ? AppColors.primary.withValues(alpha: 0.12)
                                : Colors.grey.shade100,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            dev.platform == 'iOS'
                                ? Icons.phone_iphone_rounded
                                : Icons.phone_android_rounded,
                            color: dev.isOnline ? AppColors.primary : Colors.grey.shade600,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      dev.name,
                                      style: const TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.bold,
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
                                      color: isCurrent
                                          ? AppColors.navyDark
                                          : AppColors.danger.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      isCurrent ? 'THIS PHONE' : 'REMOTE',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        color: isCurrent ? Colors.white : AppColors.danger,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  if (dev.isOnline) ...[
                                    const PulseIndicator(size: 7, color: AppColors.success),
                                    const SizedBox(width: 4),
                                    const Text(
                                      'Live Online',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.success,
                                      ),
                                    ),
                                  ] else ...[
                                    Container(
                                      width: 7,
                                      height: 7,
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade400,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        'Last seen ${dev.lastSeenFormatted}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.grey.shade600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                  if (dev.batteryLevel >= 0) ...[
                                    const Text(' • ', style: TextStyle(color: AppColors.textMuted)),
                                    Icon(
                                      dev.batteryLevel > 20
                                          ? Icons.battery_charging_full_rounded
                                          : Icons.battery_alert_rounded,
                                      size: 13,
                                      color: dev.batteryLevel > 20
                                          ? AppColors.primary
                                          : AppColors.danger,
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      '${dev.batteryLevel}%',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: dev.batteryLevel > 20
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
                      ],
                    ),
                    if (dev.address.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_rounded,
                            size: 13,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              dev.address,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isCurrent ? AppColors.navyDark : AppColors.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              minimumSize: const Size(0, 36),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: () {
                              deviceManagerService.selectDevice(isCurrent ? null : dev.id);
                              onNavigateTab(1);
                            },
                            icon: const Icon(Icons.map_rounded, size: 16),
                            label: Text(
                              isCurrent ? 'View on Map' : 'Track Lost Phone',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.danger),
                            foregroundColor: AppColors.danger,
                            minimumSize: const Size(0, 36),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () {
                            deviceManagerService.ringRemoteDevice(dev.id);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Loud alarm triggered on ${dev.name}!'),
                                backgroundColor: AppColors.danger,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                          icon: const Icon(Icons.notifications_active_rounded, size: 16),
                          label: const Text(
                            'Ring',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildSharedWithMeSection(BuildContext context) {
    String? currentEmail;
    try {
      currentEmail = FirebaseAuth.instance.currentUser?.email;
    } catch (_) {}

    return StreamBuilder<List<SharedDeviceModel>>(
      stream: shareService.getSharedWithMeStream(),
      builder: (context, snapshot) {
        final devices = (snapshot.hasError || snapshot.data == null)
            ? <SharedDeviceModel>[]
            : snapshot.data!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.family_restroom_rounded,
                    color: Color(0xFF10B981),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Devices Shared With You',
                    style: TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navyDark,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                if (devices.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.success,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${devices.length} Live',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (devices.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.tileBackground,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.person_pin_circle_outlined,
                        color: AppColors.textSecondary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'No live devices shared yet',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            currentEmail != null && currentEmail.isNotEmpty
                                ? 'Friends can share to: $currentEmail'
                                : 'Sign in to see locations shared with you',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else
              Column(
                children: [
                  for (int i = 0; i < devices.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    _sharedDeviceCard(context, devices[i]),
                  ],
                ],
              ),
          ],
        );
      },
    );
  }

  Widget _sharedDeviceCard(BuildContext context, SharedDeviceModel dev) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SharedUserHistoryScreen(sharedDevice: dev),
          ),
        );
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: dev.isActive ? AppColors.primary.withValues(alpha: 0.35) : AppColors.border,
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.primaryLight,
                  child: Text(
                    dev.ownerName.isNotEmpty ? dev.ownerName[0].toUpperCase() : 'U',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
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
                              dev.ownerName,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (dev.isActive) ...[
                            const PulseIndicator(size: 8, color: AppColors.success),
                            const SizedBox(width: 4),
                            const Text(
                              'Live',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppColors.success,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dev.ownerEmail,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textMuted,
                  size: 22,
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Address chip with speed badge
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.tileBackground,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on_rounded, size: 16, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      dev.address,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${dev.speedKmh.toStringAsFixed(0)} km/h',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Action Buttons: Location History (Primary) + Live Map
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SharedUserHistoryScreen(sharedDevice: dev),
                        ),
                      );
                    },
                    icon: const Icon(Icons.history_rounded, size: 18),
                    label: const Text(
                      'Location History',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(40),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SharedDeviceMapScreen(initialDevice: dev),
                        ),
                      );
                    },
                    icon: const Icon(Icons.map_rounded, size: 16, color: AppColors.primary),
                    label: const Text(
                      'Live Map',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryDark,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(40),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      side: const BorderSide(color: AppColors.primary, width: 1.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
