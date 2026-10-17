import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import '../models/trip_model.dart';
import '../models/app_notification.dart';
import 'geofence_service.dart';
import 'notification_service.dart';

class TrackingService extends ChangeNotifier {
  static final TrackingService _instance = TrackingService._internal();
  factory TrackingService() => _instance;

  TrackingService._internal() {
    _initDefaultHistory();
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
    final now = DateTime.now();
    _historyTrips.addAll([
      TripModel(
        id: 'trip_1',
        title: 'Trip to Office',
        ownerId: 'default_user',
        viewerIds: [],
        startedAt: now.subtract(const Duration(days: 1, hours: 4)),
        endedAt: now.subtract(const Duration(days: 1, hours: 3, minutes: 28)),
        distanceMeters: 12400,
        isActive: false,
        points: _generateSamplePath(28.6139, 77.2090, 0.05, 0.04),
      ),
      TripModel(
        id: 'trip_2',
        title: 'Evening Ride',
        ownerId: 'default_user',
        viewerIds: [],
        startedAt: now.subtract(const Duration(days: 2, hours: 6)),
        endedAt: now.subtract(const Duration(days: 2, hours: 5, minutes: 15)),
        distanceMeters: 18600,
        isActive: false,
        points: _generateSamplePath(28.6250, 77.2180, -0.06, 0.05),
      ),
      TripModel(
        id: 'trip_3',
        title: 'Market Visit',
        ownerId: 'default_user',
        viewerIds: [],
        startedAt: now.subtract(const Duration(days: 3, hours: 8)),
        endedAt: now.subtract(const Duration(days: 3, hours: 7, minutes: 40)),
        distanceMeters: 8300,
        isActive: false,
        points: _generateSamplePath(28.6100, 77.2000, 0.03, -0.02),
      ),
      TripModel(
        id: 'trip_4',
        title: 'Morning Ride',
        ownerId: 'default_user',
        viewerIds: [],
        startedAt: now.subtract(const Duration(days: 4, hours: 10)),
        endedAt: now.subtract(const Duration(days: 4, hours: 9, minutes: 2)),
        distanceMeters: 25100,
        isActive: false,
        points: _generateSamplePath(28.6300, 77.2200, 0.08, 0.07),
      ),
      TripModel(
        id: 'trip_5',
        title: 'Family Trip',
        ownerId: 'default_user',
        viewerIds: [],
        startedAt: now.subtract(const Duration(days: 5, hours: 14)),
        endedAt: now.subtract(const Duration(days: 5, hours: 12, minutes: 45)),
        distanceMeters: 42700,
        isActive: false,
        points: _generateSamplePath(28.5900, 77.1800, -0.12, 0.10),
      ),
    ]);
  }

  static List<TripPoint> _generateSamplePath(double startLat, double startLng, double dLat, double dLng) {
    final List<TripPoint> pts = [];
    const count = 15;
    final now = DateTime.now();
    for (int i = 0; i < count; i++) {
      final fraction = i / (count - 1);
      final lat = startLat + dLat * fraction + (i % 2 == 0 ? 0.002 : -0.002);
      final lng = startLng + dLng * fraction + (i % 3 == 0 ? -0.001 : 0.002);
      pts.add(
        TripPoint(
          latitude: lat,
          longitude: lng,
          speed: 12.0 + (i % 4) * 5.0,
          accuracy: 4.5,
          timestamp: now.subtract(Duration(minutes: (count - i) * 2)),
        ),
      );
    }
    return pts;
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

      // Reliable background & foreground tracking configuration
      late LocationSettings locationSettings;
      if (defaultTargetPlatform == TargetPlatform.android) {
        locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 3,
          forceLocationManager: true,
          intervalDuration: const Duration(seconds: 2),
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: "TrackMyPhone is Active",
            notificationText: "Live GPS tracking in progress...",
            enableWakeLock: true,
            setOngoing: true,
            color: Colors.blue,
          ),
        );
      } else if (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        locationSettings = AppleSettings(
          accuracy: LocationAccuracy.high,
          activityType: ActivityType.fitness,
          distanceFilter: 3,
          pauseLocationUpdatesAutomatically: false,
          showBackgroundLocationIndicator: true,
        );
      } else {
        locationSettings = const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 3,
        );
      }

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

  Future<void> stop() async {
    _active = false;
    _timer?.cancel();
    _timer = null;
    await _positionSubscription?.cancel();
    _positionSubscription = null;

    final id = _tripId;
    _tripId = null;

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
