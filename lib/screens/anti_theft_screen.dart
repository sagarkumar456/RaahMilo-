import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../core/app_colors.dart';
import '../services/anti_theft_service.dart';
import 'support_chat_screen.dart';

class AntiTheftScreen extends StatefulWidget {
  const AntiTheftScreen({super.key});

  @override
  State<AntiTheftScreen> createState() => _AntiTheftScreenState();
}

class _AntiTheftScreenState extends State<AntiTheftScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _isLoadingAction = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _toggleArm(bool willArm) async {
    setState(() => _isLoadingAction = true);
    try {
      if (willArm) {
        await antiTheftService.armVehicle();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.shield_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Vehicle Armed! Anti-theft movement guard is ACTIVE.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } else {
        await antiTheftService.disarmVehicle();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.lock_open_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Vehicle Disarmed. Security guard paused.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              backgroundColor: Color(0xFF64748B),
            ),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingAction = false);
      }
    }
  }

  Future<void> _toggleSirenAlarm() async {
    if (antiTheftService.isAlarmActive) {
      await antiTheftService.silenceAlarm();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Siren Alarm silenced')),
        );
      }
    } else {
      await antiTheftService.triggerTheftAlarm(reason: 'Manual Panic Alarm Triggered');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🚨 LOUD SIREN ALARM ACTIVATED! Alert sent to Support Team'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  void _showTestAlarmDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.danger),
            SizedBox(width: 8),
            Text('Simulate Theft Alarm?'),
          ],
        ),
        content: const Text(
          'This will simulate vehicle displacement, trigger audible alert sound, vibrate phone, and send a security alert.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              antiTheftService.simulateTheftMovement();
            },
            child: const Text('Trigger Test Alarm'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: antiTheftService,
      builder: (context, _) {
        final isArmed = antiTheftService.isArmed;
        final isAlarm = antiTheftService.isAlarmActive;
        final isCutoff = antiTheftService.isEngineCutoff;
        final parkedLat = antiTheftService.parkedLat ?? 28.6139;
        final parkedLng = antiTheftService.parkedLng ?? 77.2090;

        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          appBar: AppBar(
            title: const Text('Anti-Theft Protection'),
            actions: [
              IconButton(
                tooltip: 'Simulate Alarm',
                icon: const Icon(Icons.bug_report_outlined),
                onPressed: _showTestAlarmDialog,
              ),
              IconButton(
                tooltip: 'Help & AI Support',
                icon: const Icon(Icons.support_agent_rounded),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SupportChatScreen()),
                  );
                },
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            children: [
              // 1. Critical Alarm Warning Banner if Alarm Active
              if (isAlarm) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.danger,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.danger.withValues(alpha: 0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.warning_rounded, color: Colors.white, size: 28),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '🚨 SIREN ALARM ACTIVE: THEFT DETECTED!',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: AppColors.danger,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: _toggleSirenAlarm,
                              icon: const Icon(Icons.volume_off_rounded, size: 18),
                              label: const Text('Silence Siren'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.black,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: () => antiTheftService.toggleEngineCutoff(!isCutoff),
                              icon: Icon(isCutoff ? Icons.power_settings_new_rounded : Icons.lock_rounded, size: 18),
                              label: Text(isCutoff ? 'Restore' : 'Cutoff Engine'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // 2. Shield Display Card
              Container(
                padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isAlarm
                        ? [const Color(0xFFDC2626), const Color(0xFF991B1B)]
                        : isArmed
                            ? [const Color(0xFF0F172A), const Color(0xFF1E293B)]
                            : [Colors.white, Colors.white],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isAlarm
                        ? Colors.redAccent
                        : isArmed
                            ? const Color(0xFF10B981).withValues(alpha: 0.4)
                            : AppColors.border,
                    width: isArmed ? 2 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isAlarm
                          ? Colors.red.withValues(alpha: 0.3)
                          : isArmed
                              ? const Color(0xFF10B981).withValues(alpha: 0.15)
                              : Colors.black.withValues(alpha: 0.04),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Animated Shield Icon
                    ScaleTransition(
                      scale: isAlarm ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isAlarm
                              ? Colors.white.withValues(alpha: 0.2)
                              : isArmed
                                  ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                  : AppColors.tileBackground,
                        ),
                        child: Center(
                          child: Icon(
                            isAlarm
                                ? Icons.notification_important_rounded
                                : isArmed
                                    ? Icons.shield_rounded
                                    : Icons.shield_outlined,
                            size: 54,
                            color: isAlarm
                                ? Colors.white
                                : isArmed
                                    ? const Color(0xFF10B981)
                                    : AppColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isAlarm
                          ? '🚨 ALARM TRIGGERED'
                          : isArmed
                              ? 'ARMED & PROTECTED'
                              : 'VEHICLE DISARMED',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                        color: (isArmed || isAlarm) ? Colors.white : AppColors.navyDark,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isAlarm
                          ? 'Unauthorized displacement detected!'
                          : isArmed
                              ? 'Movement threshold: ${antiTheftService.movementThresholdMeters.toInt()}m'
                              : 'Tap below to lock and protect vehicle',
                      style: TextStyle(
                        fontSize: 13,
                        color: (isArmed || isAlarm) ? Colors.white70 : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 22),

                    // Big Arm/Disarm Action Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isArmed ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        onPressed: _isLoadingAction ? null : () => _toggleArm(!isArmed),
                        icon: _isLoadingAction
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Icon(isArmed ? Icons.lock_open_rounded : Icons.lock_rounded),
                        label: Text(
                          _isLoadingAction
                              ? 'Updating API...'
                              : isArmed
                                  ? 'Disarm Vehicle'
                                  : 'Arm Vehicle Now',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 3. Quick Action Row: Siren Panic & Remote Engine Cutoff
              Row(
                children: [
                  Expanded(
                    child: _securityQuickActionTile(
                      icon: isAlarm ? Icons.volume_off_rounded : Icons.campaign_rounded,
                      iconColor: isAlarm ? Colors.white : AppColors.danger,
                      bgColor: isAlarm ? AppColors.danger : AppColors.dangerLight,
                      title: isAlarm ? 'Silence' : 'Panic Siren',
                      subtitle: isAlarm ? 'Stop alarm' : 'Sound siren',
                      onTap: _toggleSirenAlarm,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _securityQuickActionTile(
                      icon: isCutoff ? Icons.power_settings_new_rounded : Icons.lock_person_rounded,
                      iconColor: isCutoff ? Colors.white : const Color(0xFF6366F1),
                      bgColor: isCutoff ? const Color(0xFF4F46E5) : const Color(0xFFEEF2FF),
                      title: isCutoff ? 'Immobilized' : 'Cut-off Engine',
                      subtitle: isCutoff ? 'Tap to restore' : 'Remote cutoff',
                      onTap: () => antiTheftService.toggleEngineCutoff(!isCutoff),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // 4. Parked Location & Security Perimeter Map
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(Icons.local_parking_rounded, color: AppColors.primary, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Parked Anchor Location',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.navyDark),
                                ),
                                Text(
                                  antiTheftService.parkedAddress,
                                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isArmed ? const Color(0xFFE6F9F0) : AppColors.tileBackground,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              isArmed ? 'Locked' : 'Unlocked',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isArmed ? AppColors.success : AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                      child: SizedBox(
                        height: 150,
                        child: FlutterMap(
                          options: MapOptions(
                            initialCenter: ll.LatLng(parkedLat, parkedLng),
                            initialZoom: 16.5,
                            interactionOptions: const InteractionOptions(
                              flags: InteractiveFlag.none,
                            ),
                          ),
                          children: [
                            TileLayer(
                              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.trackmyphone.app',
                            ),
                            CircleLayer(
                              circles: [
                                CircleMarker(
                                  point: ll.LatLng(parkedLat, parkedLng),
                                  radius: antiTheftService.movementThresholdMeters,
                                  useRadiusInMeter: true,
                                  color: (isAlarm ? Colors.red : const Color(0xFF10B981)).withValues(alpha: 0.25),
                                  borderColor: isAlarm ? Colors.red : const Color(0xFF10B981),
                                  borderStrokeWidth: 2,
                                ),
                              ],
                            ),
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: ll.LatLng(parkedLat, parkedLng),
                                  width: 36,
                                  height: 36,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: isArmed ? const Color(0xFF10B981) : AppColors.primary,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 2),
                                    ),
                                    child: const Icon(Icons.directions_car_rounded, color: Colors.white, size: 20),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 5. Sensitivity & Preferences
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Anti-Theft Sensitivity',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.navyDark),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: ['High', 'Medium', 'Low'].map((level) {
                        final isSelected = antiTheftService.sensitivity == level;
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: ChoiceChip(
                              label: Center(
                                child: Text(
                                  level == 'High'
                                      ? 'High (8m)'
                                      : level == 'Medium'
                                          ? 'Med (15m)'
                                          : 'Low (30m)',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    color: isSelected ? Colors.white : AppColors.navyDark,
                                  ),
                                ),
                              ),
                              selected: isSelected,
                              selectedColor: AppColors.primary,
                              backgroundColor: AppColors.tileBackground,
                              showCheckmark: false,
                              onSelected: (_) => antiTheftService.setSensitivity(level),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const Divider(height: 24),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Loud Siren & Haptics', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: const Text('Audible siren alert on theft detection', style: TextStyle(fontSize: 11)),
                      value: antiTheftService.loudSiren,
                      activeColor: AppColors.primary,
                      onChanged: antiTheftService.setLoudSiren,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Auto-Arm on Parking', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: const Text('Arm vehicle automatically when stationary', style: TextStyle(fontSize: 11)),
                      value: antiTheftService.autoArmOnParking,
                      activeColor: AppColors.primary,
                      onChanged: antiTheftService.setAutoArmOnParking,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 6. Security Event History Log
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Recent Security Logs',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.navyDark),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'API Synced',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF2563EB)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (antiTheftService.events.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: Text(
                            'No security events recorded yet',
                            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                          ),
                        ),
                      )
                    else
                      ...antiTheftService.events.take(5).map((ev) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                margin: const EdgeInsets.only(top: 2),
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: ev.isAlert ? AppColors.danger : AppColors.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      ev.title,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: ev.isAlert ? AppColors.danger : AppColors.navyDark,
                                      ),
                                    ),
                                    Text(
                                      ev.description,
                                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '${ev.timestamp.hour.toString().padLeft(2, '0')}:${ev.timestamp.minute.toString().padLeft(2, '0')}',
                                style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Widget _securityQuickActionTile({
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.navyDark),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
