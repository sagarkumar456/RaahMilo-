import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/trip_model.dart';
import '../models/app_notification.dart';
import 'geocoding_service.dart';
import 'geofence_service.dart';
import 'notification_service.dart';
import 'share_service.dart';

class TrackingService extends ChangeNotifier {
  static final TrackingService _instance = TrackingService._internal();
  factory TrackingService() => _instance;

  TrackingService._internal() {
    _initDefaultHistory();
    restoreActiveSession();
  }

  StreamSubscription<Position>? _positionSubscription;
  Timer? _timer;

  final List<LatLng> _points = [];
  List<LatLng> get points => List.unmodifiable(_points);

  Position? _current;
  Position? get current => _current;

  String? _tripId;
  String? get tripId => _tripId;

  bool _active = false;
  bool get active => _active;

  bool _starting = false;
  bool get starting => _starting;

  double _meters = 0.0;
  double get meters => _meters;

  DateTime? _began;
  DateTime? get began => _began;

  Duration _elapsed = Duration.zero;
  Duration get elapsed => _elapsed;

  String? _lastError;
  String? get lastError => _lastError;

  final List<TripModel> _historyTrips = [];
  List<TripModel> get historyTrips => List.unmodifiable(_historyTrips);

  String get formattedTimer {
    final hours = _elapsed.inHours.toString().padLeft(2, '0');
    final minutes = (_elapsed.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  void _initDefaultHistory() {
    // History contains only genuine trips recorded on the device
  }

  void setCurrentPosition(Position p) {
    _current = p;
    geocodingService.updateFromPosition(p.latitude, p.longitude);
    notifyListeners();
  }

  Future<Position?> initCurrentLocation() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        return null;
      }
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        _current = last;
        geocodingService.updateFromPosition(last.latitude, last.longitude);
        notifyListeners();
      }
      final current = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 6),
        ),
      );
      _current = current;
      geocodingService.updateFromPosition(current.latitude, current.longitude);
      notifyListeners();
      return current;
    } catch (_) {
      return _current;
    }
  }

  Future<void> start() async {
    if (_active || _starting) return;
    _starting = true;
    _lastError = null;
    notifyListeners();

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Enable location services in your phone settings.');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Location permission is required for live tracking.');
      }

      _began = DateTime.now();
      _meters = 0.0;
      _points.clear();
      _elapsed = Duration.zero;

      // Start elapsed timer
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_began != null) {
          _elapsed = DateTime.now().difference(_began!);
          notifyListeners();
        }
      });

      // Save initial trip to Firestore if available
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest_tracker';
        final ref = await FirebaseFirestore.instance.collection('trips').add({
          'title': 'Trip at ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}',
          'ownerId': uid,
          'viewerIds': <String>[],
          'startedAt': FieldValue.serverTimestamp(),
          'endedAt': null,
          'active': true,
          'distanceMeters': 0.0,
          'latest': null,
        });
        _tripId = ref.id;
      } catch (e) {
        // Fallback for demo / offline
        _tripId = 'local_${DateTime.now().millisecondsSinceEpoch}';
      }

      _active = true;
      notifyListeners();

      // Persist tracking session
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_tracking_active', true);
        await prefs.setString('active_trip_id', _tripId!);
        await prefs.setString('active_trip_began', _began!.toIso8601String());
        await prefs.setDouble('active_trip_meters', _meters);
      } catch (_) {}

      // Reliable background & foreground tracking configuration
      final locationSettings = _createLocationSettings();

      // Initial fix
      try {
        final initialPos = await Geolocator.getCurrentPosition(
          locationSettings: locationSettings,
        );
        _onPosition(initialPos);
      } catch (_) {}

      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (p) => _onPosition(p),
        onError: (Object e) {
          _lastError = e.toString();
          notifyListeners();
        },
      );

      // Add Notification
      NotificationService().addNotification(
        title: 'Tracking Started',
        subtitle: 'Live tracking has started',
        type: NotificationType.trackingStarted,
      );
    } catch (e) {
      _lastError = '$e';
      if (_tripId != null && _active) {
        await stop();
      }
      rethrow;
    } finally {
      _starting = false;
      notifyListeners();
    }
  }

  Future<void> _onPosition(Position p) async {
    if (!_active || _tripId == null) return;
    if (p.accuracy > 100) return; // Discard bad fixes

    final old = _current;
    if (old != null) {
      final step = Geolocator.distanceBetween(
        old.latitude,
        old.longitude,
        p.latitude,
        p.longitude,
      );
      if (step < 2) return;
      if (step > 500 && p.timestamp.difference(old.timestamp).inSeconds < 10) return;
      _meters += step;
    }

    _current = p;
    _points.add(LatLng(p.latitude, p.longitude));

    // Update reverse geocoded address
    geocodingService.updateFromPosition(p.latitude, p.longitude);

    // Check geofences
    GeofenceService().checkLocation(p);

    // Speed alert check (> 80 km/h)
    final speedKmh = (p.speed.clamp(0, 999) * 3.6);
    if (speedKmh > 80) {
      NotificationService().addNotification(
        title: 'Speed Alert',
        subtitle: 'Speed crossed ${speedKmh.toStringAsFixed(0)} km/h',
        type: NotificationType.speedAlert,
      );
    }

    // Keep persisted meters updated in SharedPreferences
    SharedPreferences.getInstance().then((prefs) {
      prefs.setDouble('active_trip_meters', _meters);
    }).catchError((_) {});

    // Update live shared locations with viewer accounts
    shareService.updateMySharedLocations(
      lat: p.latitude,
      lng: p.longitude,
      speed: p.speed,
      address: geocodingService.fullAddress,
    );

    notifyListeners();

    // Sync to Firestore
    final id = _tripId!;
    if (!id.startsWith('local_')) {
      try {
        final ref = FirebaseFirestore.instance.collection('trips').doc(id);
        await ref.collection('points').add({
          'lat': p.latitude,
          'lng': p.longitude,
          'accuracy': p.accuracy,
          'speed': p.speed,
          'at': Timestamp.fromDate(p.timestamp),
        });
        await ref.update({
          'latest': {
            'lat': p.latitude,
            'lng': p.longitude,
            'speed': p.speed,
            'accuracy': p.accuracy,
            'at': Timestamp.fromDate(p.timestamp),
          },
          'distanceMeters': _meters,
        });
      } catch (e) {
        _lastError = 'Cloud sync error: $e';
        notifyListeners();
      }
    }
  }

  LocationSettings _createLocationSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
        forceLocationManager: true,
        intervalDuration: const Duration(seconds: 2),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: "RaahMilo is Active",
          notificationText: "Live GPS tracking in progress...",
          enableWakeLock: true,
          setOngoing: true,
          color: Color(0xFF10B981),
        ),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.fitness,
        distanceFilter: 3,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    } else {
      return const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
      );
    }
  }

  Future<void> restoreActiveSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isActive = prefs.getBool('is_tracking_active') ?? false;
      if (!isActive) return;

      final savedTripId = prefs.getString('active_trip_id');
      final beganStr = prefs.getString('active_trip_began');
      final savedMeters = prefs.getDouble('active_trip_meters') ?? 0.0;

      if (savedTripId == null || beganStr == null) return;

      _tripId = savedTripId;
      _began = DateTime.tryParse(beganStr) ?? DateTime.now();
      _meters = savedMeters;
      _active = true;
      _elapsed = DateTime.now().difference(_began!);

      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_began != null) {
          _elapsed = DateTime.now().difference(_began!);
          notifyListeners();
        }
      });

      final locationSettings = _createLocationSettings();
      await _positionSubscription?.cancel();
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (p) => _onPosition(p),
        onError: (Object e) {
          _lastError = e.toString();
          notifyListeners();
        },
      );

      try {
        final currentPos = await Geolocator.getCurrentPosition(
          locationSettings: locationSettings,
        );
        _onPosition(currentPos);
      } catch (_) {}

      notifyListeners();
    } catch (e) {
      debugPrint('Error restoring tracking session: $e');
    }
  }

  Future<void> stop() async {
    _active = false;
    _timer?.cancel();
    _timer = null;
    await _positionSubscription?.cancel();
    _positionSubscription = null;

    final id = _tripId;
    _tripId = null;

    // Clear persisted active session from SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('is_tracking_active');
      await prefs.remove('active_trip_id');
      await prefs.remove('active_trip_began');
      await prefs.remove('active_trip_meters');
    } catch (_) {}

    if (id != null && !id.startsWith('local_')) {
      try {
        await FirebaseFirestore.instance.collection('trips').doc(id).update({
          'active': false,
          'endedAt': FieldValue.serverTimestamp(),
          'distanceMeters': _meters,
        });
      } catch (_) {}
    }

    // Save to local history
    if (_began != null && _points.isNotEmpty) {
      final now = DateTime.now();
      _historyTrips.insert(
        0,
        TripModel(
          id: id ?? DateTime.now().millisecondsSinceEpoch.toString(),
          title: 'Trip at ${DateFormat('hh:mm a').format(_began!)}',
          ownerId: FirebaseAuth.instance.currentUser?.uid ?? 'user',
          viewerIds: [],
          startedAt: _began!,
          endedAt: now,
          distanceMeters: _meters,
          isActive: false,
          points: _points.map((pt) => TripPoint(
            latitude: pt.latitude,
            longitude: pt.longitude,
            speed: _current?.speed ?? 0.0,
            accuracy: _current?.accuracy ?? 5.0,
            timestamp: now,
          )).toList(),
        ),
      );
    }

    // Add Notification for stopped tracking
    NotificationService().addNotification(
      title: 'Tracking Stopped',
      subtitle: 'Live tracking session has ended',
      type: NotificationType.trackingStopped,
    );

    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _positionSubscription?.cancel();
    super.dispose();
  }
}

final trackingService = TrackingService();
