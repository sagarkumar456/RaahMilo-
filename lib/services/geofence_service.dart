import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_notification.dart';
import '../models/geofence_model.dart';
import 'notification_service.dart';

class GeofenceAlert {
  final String title;
  final String message;
  final bool isEntry;
  final GeofenceModel geofence;
  final DateTime timestamp;

  GeofenceAlert({
    required this.title,
    required this.message,
    required this.isEntry,
    required this.geofence,
    required this.timestamp,
  });
}

class GeofenceService extends ChangeNotifier {
  static final GeofenceService _instance = GeofenceService._internal();
  factory GeofenceService() => _instance;

  GeofenceService._internal() {
    _loadFromStorage();
  }

  static const String _storageKey = 'saved_geofences_list_v2';

  final List<GeofenceModel> _geofences = [];
  List<GeofenceModel> get geofences => List.unmodifiable(_geofences);

  GeofenceModel? _selectedGeofence;
  GeofenceModel? get selectedGeofence => _selectedGeofence;
  GeofenceModel? get currentGeofence => _selectedGeofence ?? (_geofences.isNotEmpty ? _geofences.first : null);

  // Tracks inside/outside state per geofence ID
  final Map<String, bool> _insideStates = {};
  // Tracks distance in meters per geofence ID
  final Map<String, double> _distances = {};

  final StreamController<GeofenceAlert> _alertStreamController = StreamController<GeofenceAlert>.broadcast();
  Stream<GeofenceAlert> get alertStream => _alertStreamController.stream;

  bool isInsideGeofence(String id) => _insideStates[id] ?? false;
  double? distanceToGeofence(String id) => _distances[id];

  bool get isInside => currentGeofence != null ? isInsideGeofence(currentGeofence!.id) : true;
  double? get lastDistance => currentGeofence != null ? distanceToGeofence(currentGeofence!.id) : null;

  void selectGeofence(GeofenceModel? g) {
    _selectedGeofence = g;
    notifyListeners();
  }

  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_storageKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List decoded = jsonDecode(jsonStr);
        _geofences.clear();
        for (final item in decoded) {
          _geofences.add(GeofenceModel.fromMap(Map<String, dynamic>.from(item)));
        }
      }

      if (_geofences.isEmpty) {
        _initDefault();
      } else {
        _selectedGeofence = _geofences.first;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading geofences: $e');
      if (_geofences.isEmpty) {
        _initDefault();
      }
    }
  }

  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _geofences.map((g) => g.toMap()).toList();
      await prefs.setString(_storageKey, jsonEncode(list));
    } catch (e) {
      debugPrint('Error saving geofences: $e');
    }
  }

  void _initDefault() {
    final defaultHome = GeofenceModel(
      id: 'default_home',
      name: 'Home Zone',
      latitude: 28.6139,
      longitude: 77.2090,
      radiusMeters: 500,
      notifyOnEntryExit: true,
      isActive: true,
      createdAt: DateTime.now(),
    );
    _geofences.add(defaultHome);
    _selectedGeofence = defaultHome;
    _insideStates[defaultHome.id] = true;
    _distances[defaultHome.id] = 0.0;
    _saveToStorage();
  }

  Future<void> saveGeofence({
    required String name,
    required double latitude,
    required double longitude,
    required double radiusMeters,
    required bool notifyOnEntryExit,
    String? id,
  }) async {
    final geofenceId = id ?? DateTime.now().millisecondsSinceEpoch.toString();
    final newGeofence = GeofenceModel(
      id: geofenceId,
      name: name.trim().isEmpty ? 'Safe Zone' : name.trim(),
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
      notifyOnEntryExit: notifyOnEntryExit,
      isActive: true,
      createdAt: DateTime.now(),
    );

    final existingIndex = _geofences.indexWhere((g) => g.id == geofenceId);
    if (existingIndex >= 0) {
      _geofences[existingIndex] = newGeofence;
    } else {
      _geofences.insert(0, newGeofence);
    }

    _selectedGeofence = newGeofence;

    // Immediately evaluate state if we have current coordinates
    _evaluateSingleGeofence(newGeofence);

    await _saveToStorage();
    notifyListeners();
  }

  Future<void> toggleGeofenceActive(String id, bool active) async {
    final idx = _geofences.indexWhere((g) => g.id == id);
    if (idx >= 0) {
      _geofences[idx] = _geofences[idx].copyWith(isActive: active);
      await _saveToStorage();
      notifyListeners();
    }
  }

  Future<void> deleteGeofence(String id) async {
    _geofences.removeWhere((g) => g.id == id);
    _insideStates.remove(id);
    _distances.remove(id);
    if (_selectedGeofence?.id == id) {
      _selectedGeofence = _geofences.isNotEmpty ? _geofences.first : null;
    }
    await _saveToStorage();
    notifyListeners();
  }

  void _evaluateSingleGeofence(GeofenceModel g) {
    // If we have any last calculated distance, keep it, otherwise set neutral baseline
    if (!_insideStates.containsKey(g.id)) {
      _insideStates[g.id] = true; // default neutral until real GPS checks
    }
  }

  /// Simulates device moving outside the specified geofence boundary.
  /// Sets prior state as inside to ensure an authentic exit transition and alert.
  void simulateExit(String geofenceId) {
    final idx = _geofences.indexWhere((g) => g.id == geofenceId);
    if (idx == -1) return;
    final g = _geofences[idx];
    _insideStates[geofenceId] = true;
    final offsetMeters = g.radiusMeters + 250.0;
    final dLat = offsetMeters / 111320.0;
    checkLocationLatLng(g.latitude + dLat, g.longitude);
  }

  /// Simulates device moving inside the specified geofence boundary (to its center).
  /// Sets prior state as outside to ensure an authentic entry transition and alert.
  void simulateEntry(String geofenceId) {
    final idx = _geofences.indexWhere((g) => g.id == geofenceId);
    if (idx == -1) return;
    final g = _geofences[idx];
    _insideStates[geofenceId] = false;
    checkLocationLatLng(g.latitude, g.longitude);
  }

  /// Re-evaluates geofences with the device's real coordinates.
  void resetToRealPosition(double lat, double lng) {
    checkLocationLatLng(lat, lng);
  }

  void checkLocation(Position position) {
    checkLocationLatLng(position.latitude, position.longitude);
  }

  void checkLocationLatLng(double lat, double lng) {
    if (_geofences.isEmpty) return;

    bool hasChanged = false;

    for (final geofence in _geofences) {
      if (!geofence.isActive) continue;

      final distance = Geolocator.distanceBetween(
        geofence.latitude,
        geofence.longitude,
        lat,
        lng,
      );

      _distances[geofence.id] = distance;
      final nowInside = distance <= geofence.radiusMeters;
      final wasInside = _insideStates[geofence.id];

      // First fix for this geofence: record baseline without firing false alert
      if (wasInside == null) {
        _insideStates[geofence.id] = nowInside;
        hasChanged = true;
        continue;
      }

      if (geofence.notifyOnEntryExit) {
        if (wasInside && !nowInside) {
          // Transition: User EXITED geofence
          _insideStates[geofence.id] = false;
          hasChanged = true;

          final title = 'Left ${geofence.name}';
          final message = 'Your device exited ${geofence.name} zone (${distance.toInt()}m from center)';

          NotificationService().addNotification(
            title: title,
            subtitle: message,
            type: NotificationType.leftZone,
          );

          _alertStreamController.add(GeofenceAlert(
            title: title,
            message: message,
            isEntry: false,
            geofence: geofence,
            timestamp: DateTime.now(),
          ));
        } else if (!wasInside && nowInside) {
          // Transition: User ENTERED geofence
          _insideStates[geofence.id] = true;
          hasChanged = true;

          final title = 'Arrived at ${geofence.name}';
          final message = 'Your device entered ${geofence.name} safe zone';

          NotificationService().addNotification(
            title: title,
            subtitle: message,
            type: NotificationType.arrivedZone,
          );

          _alertStreamController.add(GeofenceAlert(
            title: title,
            message: message,
            isEntry: true,
            geofence: geofence,
            timestamp: DateTime.now(),
          ));
        }
      } else {
        if (wasInside != nowInside) {
          _insideStates[geofence.id] = nowInside;
          hasChanged = true;
        }
      }
    }

    if (hasChanged) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _alertStreamController.close();
    super.dispose();
  }
}
