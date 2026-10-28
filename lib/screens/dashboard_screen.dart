import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../models/shared_device_model.dart';
import '../services/anti_theft_service.dart';
import '../services/share_service.dart';
import '../services/tracking_service.dart';
import '../widgets/pulse_indicator.dart';
import 'package:geolocator/geolocator.dart';
import 'anti_theft_screen.dart';
import 'geofence_screen.dart';
import 'location_disabled_screen.dart';
import 'premium_screen.dart';
import 'settings_screen.dart';
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
      animation: trackingService,
      builder: (context, _) {
        final isActive = trackingService.active;
        final isStarting = trackingService.starting;

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          children: [
            // 1. Top Hero Card: Tracking Status & Timer
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isActive ? AppColors.success.withValues(alpha: 0.3) : AppColors.border,
                  width: isActive ? 1.5 : 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isActive
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
                            if (isActive)
                              const PulseIndicator(size: 10, color: AppColors.success)
                            else
                              Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  color: AppColors.textMuted,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            const SizedBox(width: 8),
                            Text(
                              'Tracking',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: isActive ? AppColors.textPrimary : AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          isActive ? 'Live location active' : 'Tap Start to begin trip',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isActive ? trackingService.formattedTimer : '00:00:00',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                            color: isActive ? AppColors.navyDark : AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Action button: Red "Stop" or Green "Start"
                  SizedBox(
                    height: 44,
                    child: ElevatedButton(
                      onPressed: isStarting
                          ? null
                          : () async {
                              try {
                                if (isActive) {
                                  await trackingService.stop();
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Row(
                                          children: [
                                            Icon(Icons.stop_circle_rounded, color: Colors.white, size: 20),
                                            SizedBox(width: 8),
                                            Text('Live tracking stopped'),
                                          ],
                                        ),
                                        backgroundColor: AppColors.danger,
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                  }
                                } else {
                                  final isEnabled = await Geolocator.isLocationServiceEnabled();
                                  if (!isEnabled) {
                                    if (context.mounted) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => const LocationDisabledScreen(),
                                          fullscreenDialog: true,
                                        ),
                                      );
                                    }
                                    return;
                                  }
                                  await trackingService.start();
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Row(
                                          children: [
                                            const Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 20),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                trackingService.isBackgroundPermissionGranted
                                                    ? 'Live tracking started'
                                                    : 'Tracking started. For bag/pocket route recording, allow "All the time" location in Settings.',
                                                style: const TextStyle(fontSize: 12),
                                              ),
                                            ),
                                          ],
                                        ),
                                        action: trackingService.isBackgroundPermissionGranted
                                            ? null
                                            : SnackBarAction(
                                                label: 'Settings',
                                                textColor: Colors.amberAccent,
                                                onPressed: () => Geolocator.openAppSettings(),
                                              ),
                                        backgroundColor: AppColors.success,
                                        duration: Duration(seconds: trackingService.isBackgroundPermissionGranted ? 2 : 4),
                                      ),
                                    );
                                  }
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  final isEnabled = await Geolocator.isLocationServiceEnabled();
                                  if (!isEnabled) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const LocationDisabledScreen(),
                                        fullscreenDialog: true,
                                      ),
                                    );
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('$e')),
                                    );
                                  }
                                }
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isActive ? AppColors.danger : AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        minimumSize: const Size(80, 44),
                      ),
                      child: isStarting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              isActive ? 'Stop' : 'Start',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),

            // Anti-Theft Security Shield Card
            AnimatedBuilder(
              animation: antiTheftService,
              builder: (context, _) {
                final isArmed = antiTheftService.isArmed;
                final isAlarm = antiTheftService.isAlarmActive;
                return Container(
                  margin: const EdgeInsets.only(top: 14),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: isAlarm ? AppColors.danger : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isAlarm
                          ? Colors.redAccent
                          : isArmed
                              ? const Color(0xFF10B981).withValues(alpha: 0.4)
                              : AppColors.border,
                      width: isArmed ? 1.5 : 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isAlarm
                            ? Colors.red.withValues(alpha: 0.3)
                            : isArmed
                                ? const Color(0xFF10B981).withValues(alpha: 0.08)
                                : Colors.black.withValues(alpha: 0.03),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AntiTheftScreen()),
                      );
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: isAlarm
                                ? Colors.white.withValues(alpha: 0.2)
                                : isArmed
                                    ? const Color(0xFFE6F9F0)
                                    : AppColors.tileBackground,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isAlarm
                                ? Icons.warning_rounded
                                : isArmed
                                    ? Icons.shield_rounded
                                    : Icons.shield_outlined,
                            color: isAlarm
                                ? Colors.white
                                : isArmed
                                    ? const Color(0xFF10B981)
                                    : AppColors.textSecondary,
                            size: 24,
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
                                      isAlarm
                                          ? 'THEFT ALARM'
                                          : isArmed
                                              ? 'Anti-Theft Armed'
                                              : 'Anti-Theft Disarmed',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: isAlarm ? Colors.white : AppColors.navyDark,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isAlarm
                                          ? Colors.white.withValues(alpha: 0.3)
                                          : isArmed
                                              ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                              : AppColors.border,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      isArmed ? 'PROTECTED' : 'OFF',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        color: isAlarm
                                            ? Colors.white
                                            : isArmed
                                                ? const Color(0xFF047857)
                                                : AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isAlarm
                                    ? 'Tap to silence siren or cut-off engine'
                                    : isArmed
                                        ? 'Guard active (${antiTheftService.movementThresholdMeters.toInt()}m limit)'
                                        : 'Tap to arm & lock parked location',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isAlarm ? Colors.white70 : AppColors.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isAlarm
                                ? Colors.white
                                : isArmed
                                    ? const Color(0xFFEF4444)
                                    : const Color(0xFF10B981),
                            foregroundColor: isAlarm ? AppColors.danger : Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            minimumSize: const Size(64, 36),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                          ),
                          onPressed: () {
                            if (isAlarm) {
                              antiTheftService.silenceAlarm();
                            } else if (isArmed) {
                              antiTheftService.disarmVehicle();
                            } else {
                              antiTheftService.armVehicle();
                            }
                          },
                          child: Text(
                            isAlarm
                                ? 'Silence'
                                : isArmed
                                    ? 'Disarm'
                                    : 'Arm',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 20),

            // 2. 6 Grid Features
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: 1.12,
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
                  icon: Icons.shield_rounded,
                  iconColor: const Color(0xFF10B981),
                  bgColor: const Color(0xFFE6F9F0),
                  title: 'Anti-Theft',
                  subtitle: 'Alarm & Siren',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AntiTheftScreen()),
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
                  icon: Icons.speed_rounded,
                  iconColor: const Color(0xFF0D9488),
                  bgColor: const Color(0xFFCCFBF1),
                  title: 'Speed & Safety',
                  subtitle: 'Alert limits',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    );
                  },
                ),
                _dashboardGridCard(
                  icon: Icons.radar_rounded,
                  iconColor: const Color(0xFFF59E0B),
                  bgColor: const Color(0xFFFEF3C7),
                  title: 'Geofence',
                  subtitle: 'Safety alerts',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const GeofenceScreen()),
                    );
                  },
                ),
              ],
            ),

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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSharedWithMeSection(BuildContext context) {
    final currentEmail = FirebaseAuth.instance.currentUser?.email;

    return StreamBuilder<List<SharedDeviceModel>>(
      stream: shareService.getSharedWithMeStream(),
      builder: (context, snapshot) {
        final devices = snapshot.data ?? [];

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
                const Text(
                  'Family & Live Sharing',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navyDark,
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
                const Spacer(),
                InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ShareScreen()),
                    );
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.share_location_rounded, size: 14, color: AppColors.primary),
                        SizedBox(width: 4),
                        Text(
                          'Share Hub',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
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
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: devices.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final dev = devices[index];
                  return _sharedDeviceCard(context, dev);
                },
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
