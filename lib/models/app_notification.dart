import 'package:flutter/material.dart';

enum NotificationType {
  leftZone,
  arrivedZone,
  speedAlert,
  lowBattery,
  trackingStarted,
  trackingStopped,
  general,
  antiTheftArmed,
  antiTheftDisarmed,
  theftAlarmTriggered,
  supportTicket,
}

class AppNotification {
  final String id;
  final String title;
  final String subtitle;
  final String timeText;
  final DateTime timestamp;
  final NotificationType type;
  bool isRead;

  AppNotification({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.timeText,
    required this.timestamp,
    required this.type,
    this.isRead = false,
  });

  IconData get icon {
    switch (type) {
      case NotificationType.leftZone:
        return Icons.location_on_rounded;
      case NotificationType.arrivedZone:
        return Icons.navigation_rounded;
      case NotificationType.speedAlert:
        return Icons.warning_amber_rounded;
      case NotificationType.lowBattery:
        return Icons.battery_alert_rounded;
      case NotificationType.trackingStarted:
        return Icons.play_circle_fill_rounded;
      case NotificationType.trackingStopped:
        return Icons.stop_circle_rounded;
      case NotificationType.antiTheftArmed:
        return Icons.security_rounded;
      case NotificationType.antiTheftDisarmed:
        return Icons.lock_open_rounded;
      case NotificationType.theftAlarmTriggered:
        return Icons.notification_important_rounded;
      case NotificationType.supportTicket:
        return Icons.support_agent_rounded;
      case NotificationType.general:
        return Icons.notifications_rounded;
    }
  }

  Color get iconColor {
    switch (type) {
      case NotificationType.leftZone:
        return const Color(0xFFEF4444); // Red
      case NotificationType.arrivedZone:
        return const Color(0xFF10B981); // Green
      case NotificationType.speedAlert:
        return const Color(0xFFEF4444); // Red
      case NotificationType.lowBattery:
        return const Color(0xFFF59E0B); // Amber
      case NotificationType.trackingStarted:
        return const Color(0xFF10B981); // Green
      case NotificationType.trackingStopped:
        return const Color(0xFFEF4444); // Red
      case NotificationType.antiTheftArmed:
        return const Color(0xFF10B981); // Emerald
      case NotificationType.antiTheftDisarmed:
        return const Color(0xFF64748B); // Slate
      case NotificationType.theftAlarmTriggered:
        return const Color(0xFFDC2626); // Bright Crimson
      case NotificationType.supportTicket:
        return const Color(0xFF2563EB); // Blue
      case NotificationType.general:
        return const Color(0xFF10B981); // Green
    }
  }

  Color get iconBgColor {
    return iconColor.withValues(alpha: 0.12);
  }
}
