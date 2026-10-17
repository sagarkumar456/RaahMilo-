import 'package:flutter/material.dart';
import '../models/app_notification.dart';

class NotificationService extends ChangeNotifier {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;

  NotificationService._internal() {
    _initDefaults();
  }

  final List<AppNotification> _notifications = [];
  List<AppNotification> get notifications => List.unmodifiable(_notifications);

  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  List<AppNotification> get todayNotifications {
    final now = DateTime.now();
    return _notifications.where((n) {
      final diff = now.difference(n.timestamp);
      return diff.inHours < 24 && n.timestamp.day == now.day;
    }).toList();
  }

  List<AppNotification> get yesterdayNotifications {
    final now = DateTime.now();
    return _notifications.where((n) {
      final diff = now.difference(n.timestamp);
      return diff.inHours >= 24 || n.timestamp.day != now.day;
    }).toList();
  }

  void _initDefaults() {
    final now = DateTime.now();
    _notifications.addAll([
      AppNotification(
        id: '1',
        title: 'Left Home',
        subtitle: 'Your device left Home area',
        timeText: '10:15 AM',
        timestamp: now.subtract(const Duration(minutes: 45)),
        type: NotificationType.leftZone,
        isRead: false,
      ),
      AppNotification(
        id: '2',
        title: 'Arrived at Office',
        subtitle: 'Your device arrived at Office',
        timeText: '09:05 AM',
        timestamp: now.subtract(const Duration(hours: 2)),
        type: NotificationType.arrivedZone,
        isRead: false,
      ),
      AppNotification(
        id: '3',
        title: 'Speed Alert',
        subtitle: 'Speed crossed 80 km/h',
        timeText: '08:42 AM',
        timestamp: now.subtract(const Duration(hours: 3)),
        type: NotificationType.speedAlert,
        isRead: false,
      ),
      AppNotification(
        id: '4',
        title: 'Low Battery',
        subtitle: 'Device battery is 15%',
        timeText: '06:20 AM',
        timestamp: now.subtract(const Duration(hours: 5)),
        type: NotificationType.lowBattery,
        isRead: false,
      ),
      AppNotification(
        id: '5',
        title: 'Entered Market',
        subtitle: 'Your device entered Market area',
        timeText: '05:30 PM',
        timestamp: now.subtract(const Duration(days: 1, hours: 2)),
        type: NotificationType.arrivedZone,
        isRead: true,
      ),
      AppNotification(
        id: '6',
        title: 'Tracking Started',
        subtitle: 'Live tracking has started',
        timeText: '07:15 AM',
        timestamp: now.subtract(const Duration(days: 1, hours: 8)),
        type: NotificationType.trackingStarted,
        isRead: true,
      ),
    ]);
  }

  void addNotification({
    required String title,
    required String subtitle,
    required NotificationType type,
  }) {
    final now = DateTime.now();
    final hour = now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
    final minute = now.minute.toString().padLeft(2, '0');
    final ampm = now.hour >= 12 ? 'PM' : 'AM';
    final timeStr = '$hour:$minute $ampm';

    _notifications.insert(
      0,
      AppNotification(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
        subtitle: subtitle,
        timeText: timeStr,
        timestamp: now,
        type: type,
        isRead: false,
      ),
    );
    notifyListeners();
  }

  void markAllRead() {
    for (var n in _notifications) {
      n.isRead = true;
    }
    notifyListeners();
  }

  void markAsRead(String id) {
    final item = _notifications.firstWhere((n) => n.id == id, orElse: () => _notifications.first);
    item.isRead = true;
    notifyListeners();
  }
}
