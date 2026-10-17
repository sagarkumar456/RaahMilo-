import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/geofence_model.dart';
import '../models/app_notification.dart';
import 'notification_service.dart';

class GeofenceService extends ChangeNotifier {
  static final GeofenceService _instance = GeofenceService._internal();
  factory GeofenceService() => _instance;

  GeofenceService._internal() {
    _initDefault();
  }

  final List<GeofenceModel> _geofences = [];
  List<GeofenceModel> get geofences => List.unmodifiable(_geofences);

  GeofenceModel? _currentGeofence;
  GeofenceModel? get currentGeofence => _currentGeofence;

  bool _isInside = true;
  bool get isInside => _isInside;

  double? _lastDistance;
  double? get lastDistance => _lastDistance;

  void _initDefault() {
    _currentGeofence = GeofenceModel(
      id: 'default_home',
      name: 'Home',
      latitude: 28.6139,
      longitude: 77.2090,
      radiusMeters: 500,
      notifyOnEntryExit: true,
      isActive: true,
    );
    _geofences.add(_currentGeofence!);
  }

  void saveGeofence({
    required String name,
    required double latitude,
    required double longitude,
    required double radiusMeters,
    required bool notifyOnEntryExit,
  }) {
    final updated = GeofenceModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name.isEmpty ? 'Safe Zone' : name,
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
      notifyOnEntryExit: notifyOnEntryExit,
      isActive: true,
    );

    _currentGeofence = updated;
    _geofences.removeWhere((g) => g.name == updated.name);
    _geofences.insert(0, updated);
    notifyListeners();
  }

  void checkLocation(Position position) {
    if (_currentGeofence == null || !_currentGeofence!.isActive) return;

    final distance = Geolocator.distanceBetween(
      _currentGeofence!.latitude,
      _currentGeofence!.longitude,
      position.latitude,
      position.longitude,
    );

    _lastDistance = distance;
    final nowInside = distance <= _currentGeofence!.radiusMeters;

    if (_currentGeofence!.notifyOnEntryExit) {
      if (_isInside && !nowInside) {
        // Transition: Left zone
        NotificationService().addNotification(
          title: 'Left ${_currentGeofence!.name}',
          subtitle: 'Your device left ${_currentGeofence!.name} area',
          type: NotificationType.leftZone,
        );
      } else if (!_isInside && nowInside) {
        // Transition: Arrived at zone
        NotificationService().addNotification(
          title: 'Arrived at ${_currentGeofence!.name}',
          subtitle: 'Your device arrived at ${_currentGeofence!.name}',
          type: NotificationType.arrivedZone,
        );
      }
    }

    _isInside = nowInside;
    notifyListeners();
  }
}
