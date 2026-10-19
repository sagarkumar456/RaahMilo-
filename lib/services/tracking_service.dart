import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/trip_model.dart';
import '../models/vehicle_type.dart';
import '../models/app_notification.dart';
import 'anti_theft_service.dart';
import 'auth_service.dart';
import 'geocoding_service.dart';
import 'geofence_service.dart';
import 'notification_service.dart';
import 'share_service.dart';

class TrackingService extends ChangeNotifier {
  static final TrackingService _instance = TrackingService._internal();
  factory TrackingService() => _instance;

  TrackingService._internal() {
    loadHistory();
    restoreActiveSession();
    _restoreSelectedVehicle();
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        syncFirestoreHistory();
      }
    });
  }

  StreamSubscription<Position>? _positionSubscription;
  Timer? _timer;

  final List<LatLng> _points = [];
  List<LatLng> get points => List.unmodifiable(_points);

  final List<TripPoint> _tripPoints = [];
  List<TripPoint> get tripPoints => List.unmodifiable(_tripPoints);

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

  VehicleType _currentVehicle = VehicleType.car;
  VehicleType get currentVehicle => _currentVehicle;

  void setVehicleType(VehicleType type) {
    if (_currentVehicle == type) return;
    _currentVehicle = type;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('selected_vehicle_type', type.name);
    });
    notifyListeners();
  }

  Future<void> _restoreSelectedVehicle() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('selected_vehicle_type');
      if (saved != null) {
        _currentVehicle = VehicleType.fromString(saved);
        notifyListeners();
      }
    } catch (_) {}
  }

  double getDistanceForDate(DateTime date, {VehicleType? vehicleFilter}) {
    double totalMeters = 0.0;
    for (final trip in _historyTrips) {
      if (trip.startedAt.year == date.year &&
          trip.startedAt.month == date.month &&
          trip.startedAt.day == date.day) {
        if (vehicleFilter == null || trip.vehicleTypeEnum == vehicleFilter) {
          totalMeters += trip.distanceMeters;
        }
      }
    }
    final now = DateTime.now();
    if (_active &&
        date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      if (vehicleFilter == null || _currentVehicle == vehicleFilter) {
        totalMeters += _meters;
      }
    }
    return totalMeters / 1000.0;
  }

  List<TripModel> getTripsForDate(DateTime date, {VehicleType? vehicleFilter}) {
    final list = _historyTrips.where((trip) {
      final matchesDate = trip.startedAt.year == date.year &&
          trip.startedAt.month == date.month &&
          trip.startedAt.day == date.day;
      if (!matchesDate) return false;
      if (vehicleFilter != null && trip.vehicleTypeEnum != vehicleFilter) {
        return false;
      }
      return true;
    }).toList();
    list.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return list;
  }

  String get formattedTimer {
    final hours = _elapsed.inHours.toString().padLeft(2, '0');
    final minutes = (_elapsed.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
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
      _tripPoints.clear();
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
        final uid = authService.uid;
        final ref = await FirebaseFirestore.instance.collection('trips').add({
          'title': '${_currentVehicle.displayName} Trip at ${DateFormat('hh:mm a').format(_began!)}',
          'ownerId': uid,
          'viewerIds': <String>[],
          'startedAt': FieldValue.serverTimestamp(),
          'endedAt': null,
          'active': true,
          'distanceMeters': 0.0,
          'latest': null,
          'vehicleType': _currentVehicle.name,
        });
        _tripId = ref.id;
      } catch (e) {
        _tripId = 'local_${DateTime.now().millisecondsSinceEpoch}';
      }

      _active = true;
      notifyListeners();

      // Persist tracking session to SharedPreferences
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('is_tracking_active', true);
        await prefs.setString('active_trip_id', _tripId!);
        await prefs.setString('active_trip_began', _began!.toIso8601String());
        await prefs.setDouble('active_trip_meters', 0.0);
        await prefs.remove('active_trip_points');
      } catch (_) {}

      // Reliable background & foreground tracking configuration
      final locationSettings = _createLocationSettings();

      // Initial fix
      try {
        final initialPos = await Geolocator.getCurrentPosition(
          locationSettings: locationSettings,
        );
        await _onPosition(initialPos);
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
    _tripPoints.add(TripPoint(
      latitude: p.latitude,
      longitude: p.longitude,
      speed: p.speed,
      accuracy: p.accuracy,
      timestamp: p.timestamp,
    ));

    // Update reverse geocoded address
    geocodingService.updateFromPosition(p.latitude, p.longitude);

    // Check geofences
    GeofenceService().checkLocation(p);

    // Check Anti-Theft unauthorized movement
    antiTheftService.checkPositionForTheft(p);

    // Speed alert check (> 80 km/h)
    final speedKmh = (p.speed.clamp(0, 999) * 3.6);
    if (speedKmh > 80) {
      NotificationService().addNotification(
        title: 'Speed Alert',
        subtitle: 'Speed crossed ${speedKmh.toStringAsFixed(0)} km/h',
        type: NotificationType.speedAlert,
      );
    }

    // Persist active points & meters asynchronously to SharedPreferences
    _saveActiveTripState();

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

  Future<void> _saveActiveTripState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('active_trip_meters', _meters);
      final jsonList = _tripPoints.map((tp) => tp.toJson()).toList();
      await prefs.setString('active_trip_points', jsonEncode(jsonList));
    } catch (_) {}
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
      final savedPointsJson = prefs.getString('active_trip_points');

      if (savedTripId == null || beganStr == null) return;

      final beganDate = DateTime.tryParse(beganStr) ?? DateTime.now();

      // Restore saved points from SharedPreferences
      final List<TripPoint> restoredTripPoints = [];
      final List<LatLng> restoredPoints = [];

      if (savedPointsJson != null && savedPointsJson.isNotEmpty) {
        try {
          final List<dynamic> list = jsonDecode(savedPointsJson);
          for (final item in list) {
            if (item is Map<String, dynamic>) {
              final tp = TripPoint.fromJson(item);
              restoredTripPoints.add(tp);
              restoredPoints.add(LatLng(tp.latitude, tp.longitude));
            }
          }
        } catch (e) {
          debugPrint('Error restoring saved active points: $e');
        }
      }

      final now = DateTime.now();
      final lastPointTime = restoredTripPoints.isNotEmpty
          ? restoredTripPoints.last.timestamp
          : beganDate;

      // If app was terminated for more than 4 hours, auto-finalize the old trip into history
      if (now.difference(lastPointTime).inHours >= 4) {
        debugPrint('Auto-saving stale trip into history: $savedTripId');
        final staleTrip = TripModel(
          id: savedTripId,
          title: 'Trip at ${DateFormat('hh:mm a').format(beganDate)}',
          ownerId: authService.uid,
          viewerIds: [],
          startedAt: beganDate,
          endedAt: lastPointTime,
          distanceMeters: savedMeters,
          isActive: false,
          points: restoredTripPoints,
        );
        _historyTrips.insert(0, staleTrip);
        await _saveLocalHistory();

        await prefs.remove('is_tracking_active');
        await prefs.remove('active_trip_id');
        await prefs.remove('active_trip_began');
        await prefs.remove('active_trip_meters');
        await prefs.remove('active_trip_points');

        if (!savedTripId.startsWith('local_')) {
          try {
            await FirebaseFirestore.instance.collection('trips').doc(savedTripId).update({
              'active': false,
              'endedAt': Timestamp.fromDate(lastPointTime),
              'distanceMeters': savedMeters,
            });
          } catch (_) {}
        }

        notifyListeners();
        return;
      }

      // Resume active tracking session seamlessly with complete route preserved
      _tripId = savedTripId;
      _began = beganDate;
      _meters = savedMeters;
      _active = true;
      _elapsed = now.difference(_began!);

      _points.clear();
      _points.addAll(restoredPoints);

      _tripPoints.clear();
      _tripPoints.addAll(restoredTripPoints);

      if (_tripPoints.isNotEmpty) {
        final last = _tripPoints.last;
        _current = Position(
          latitude: last.latitude,
          longitude: last.longitude,
          timestamp: last.timestamp,
          accuracy: last.accuracy,
          altitude: 0.0,
          altitudeAccuracy: 0.0,
          heading: 0.0,
          headingAccuracy: 0.0,
          speed: last.speed,
          speedAccuracy: 0.0,
        );
        geocodingService.updateFromPosition(last.latitude, last.longitude);
      }

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
    final beganTime = _began ?? DateTime.now();
    final now = DateTime.now();
    final totalDistance = _meters;
    final finalPoints = List<TripPoint>.from(_tripPoints);

    // If _tripPoints was empty but we have recorded points or current position
    if (finalPoints.isEmpty && _points.isNotEmpty) {
      for (final pt in _points) {
        finalPoints.add(TripPoint(
          latitude: pt.latitude,
          longitude: pt.longitude,
          speed: _current?.speed ?? 0.0,
          accuracy: _current?.accuracy ?? 5.0,
          timestamp: now,
        ));
      }
    } else if (finalPoints.isEmpty && _current != null) {
      finalPoints.add(TripPoint(
        latitude: _current!.latitude,
        longitude: _current!.longitude,
        speed: _current!.speed,
        accuracy: _current!.accuracy,
        timestamp: now,
      ));
    }

    _tripId = null;

    // Clear persisted active session from SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('is_tracking_active');
      await prefs.remove('active_trip_id');
      await prefs.remove('active_trip_began');
      await prefs.remove('active_trip_meters');
      await prefs.remove('active_trip_points');
    } catch (_) {}

    if (id != null && !id.startsWith('local_')) {
      try {
        await FirebaseFirestore.instance.collection('trips').doc(id).update({
          'active': false,
          'endedAt': FieldValue.serverTimestamp(),
          'distanceMeters': totalDistance,
        });
      } catch (_) {}
    }

    // Save to local history permanently
    final completedTrip = TripModel(
      id: id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: '${_currentVehicle.displayName} Trip at ${DateFormat('hh:mm a').format(beganTime)}',
      ownerId: authService.uid,
      viewerIds: [],
      startedAt: beganTime,
      endedAt: now,
      distanceMeters: totalDistance,
      isActive: false,
      points: finalPoints,
      vehicleType: _currentVehicle.name,
    );

    _historyTrips.insert(0, completedTrip);
    await _saveLocalHistory();

    // Add Notification for stopped tracking
    NotificationService().addNotification(
      title: 'Tracking Stopped',
      subtitle: 'Live tracking session has ended',
      type: NotificationType.trackingStopped,
    );

    notifyListeners();
  }

  Future<void> loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('saved_history_trips');
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List<dynamic> list = jsonDecode(jsonStr);
        final loaded = list
            .map((item) => TripModel.fromJson(item as Map<String, dynamic>))
            .toList();

        final existingIds = _historyTrips.map((t) => t.id).toSet();
        for (final trip in loaded) {
          if (!existingIds.contains(trip.id)) {
            _historyTrips.add(trip);
            existingIds.add(trip.id);
          }
        }
        _historyTrips.sort((a, b) => b.startedAt.compareTo(a.startedAt));
        notifyListeners();
      }

      // If no trips exist locally, seed realistic sample trips for calendar & filter demo
      if (_historyTrips.isEmpty) {
        _historyTrips.addAll(_createSampleTrips());
        await _saveLocalHistory();
        notifyListeners();
      }

      await syncFirestoreHistory();
    } catch (e) {
      debugPrint('Error loading history: $e');
    }
  }

  List<TripModel> _createSampleTrips() {
    final now = DateTime.now();
    return [
      TripModel(
        id: 'sample_1',
        title: 'Car Drive to Market',
        ownerId: authService.uid,
        viewerIds: [],
        startedAt: DateTime(now.year, now.month, now.day, 10, 30),
        endedAt: DateTime(now.year, now.month, now.day, 11, 15),
        distanceMeters: 6400,
        isActive: false,
        vehicleType: 'car',
        points: [
          TripPoint(latitude: 28.6250, longitude: 77.2050, speed: 18.0, accuracy: 4.0, timestamp: DateTime(now.year, now.month, now.day, 10, 30)),
          TripPoint(latitude: 28.6200, longitude: 77.2080, speed: 22.0, accuracy: 4.0, timestamp: DateTime(now.year, now.month, now.day, 10, 42)),
          TripPoint(latitude: 28.6139, longitude: 77.2090, speed: 25.0, accuracy: 4.0, timestamp: DateTime(now.year, now.month, now.day, 10, 58)),
          TripPoint(latitude: 28.6080, longitude: 77.2140, speed: 20.0, accuracy: 4.0, timestamp: DateTime(now.year, now.month, now.day, 11, 15)),
        ],
      ),
      TripModel(
        id: 'sample_2',
        title: 'Bike Ride across City',
        ownerId: authService.uid,
        viewerIds: [],
        startedAt: DateTime(now.year, now.month, now.day - 1, 9, 15),
        endedAt: DateTime(now.year, now.month, now.day - 1, 10, 5),
        distanceMeters: 14800,
        isActive: false,
        vehicleType: 'bike',
        points: [
          TripPoint(latitude: 28.5800, longitude: 77.2200, speed: 35.0, accuracy: 5.0, timestamp: DateTime(now.year, now.month, now.day - 1, 9, 15)),
          TripPoint(latitude: 28.5900, longitude: 77.2350, speed: 42.0, accuracy: 4.0, timestamp: DateTime(now.year, now.month, now.day - 1, 9, 30)),
          TripPoint(latitude: 28.6050, longitude: 77.2450, speed: 38.0, accuracy: 4.0, timestamp: DateTime(now.year, now.month, now.day - 1, 9, 48)),
          TripPoint(latitude: 28.6180, longitude: 77.2500, speed: 30.0, accuracy: 4.0, timestamp: DateTime(now.year, now.month, now.day - 1, 10, 5)),
        ],
      ),
      TripModel(
        id: 'sample_3',
        title: 'Scooty Commute to Office',
        ownerId: authService.uid,
        viewerIds: [],
        startedAt: DateTime(now.year, now.month, now.day - 2, 17, 30),
        endedAt: DateTime(now.year, now.month, now.day - 2, 18, 5),
        distanceMeters: 8400,
        isActive: false,
        vehicleType: 'scooty',
        points: [
          TripPoint(latitude: 28.6100, longitude: 77.1900, speed: 25.0, accuracy: 4.0, timestamp: DateTime(now.year, now.month, now.day - 2, 17, 30)),
          TripPoint(latitude: 28.6150, longitude: 77.2000, speed: 28.0, accuracy: 4.0, timestamp: DateTime(now.year, now.month, now.day - 2, 17, 45)),
          TripPoint(latitude: 28.6220, longitude: 77.2100, speed: 22.0, accuracy: 4.0, timestamp: DateTime(now.year, now.month, now.day - 2, 18, 5)),
        ],
      ),
      TripModel(
        id: 'sample_4',
        title: 'Morning Walk at Park',
        ownerId: authService.uid,
        viewerIds: [],
        startedAt: DateTime(now.year, now.month, now.day - 3, 6, 30),
        endedAt: DateTime(now.year, now.month, now.day - 3, 7, 20),
        distanceMeters: 3200,
        isActive: false,
        vehicleType: 'human',
        points: [
          TripPoint(latitude: 28.6320, longitude: 77.2180, speed: 4.5, accuracy: 3.0, timestamp: DateTime(now.year, now.month, now.day - 3, 6, 30)),
          TripPoint(latitude: 28.6340, longitude: 77.2200, speed: 5.0, accuracy: 3.0, timestamp: DateTime(now.year, now.month, now.day - 3, 6, 55)),
          TripPoint(latitude: 28.6310, longitude: 77.2220, speed: 4.2, accuracy: 3.0, timestamp: DateTime(now.year, now.month, now.day - 3, 7, 20)),
        ],
      ),
      TripModel(
        id: 'sample_5',
        title: 'Highway Car Trip',
        ownerId: authService.uid,
        viewerIds: [],
        startedAt: DateTime(now.year, now.month, now.day - 4, 14, 0),
        endedAt: DateTime(now.year, now.month, now.day - 4, 14, 45),
        distanceMeters: 21500,
        isActive: false,
        vehicleType: 'car',
        points: [
          TripPoint(latitude: 28.5500, longitude: 77.1800, speed: 55.0, accuracy: 4.0, timestamp: DateTime(now.year, now.month, now.day - 4, 14, 0)),
          TripPoint(latitude: 28.5800, longitude: 77.2000, speed: 65.0, accuracy: 4.0, timestamp: DateTime(now.year, now.month, now.day - 4, 14, 20)),
          TripPoint(latitude: 28.6100, longitude: 77.2250, speed: 50.0, accuracy: 4.0, timestamp: DateTime(now.year, now.month, now.day - 4, 14, 45)),
        ],
      ),
      TripModel(
        id: 'sample_6',
        title: 'Evening Bike Ride',
        ownerId: authService.uid,
        viewerIds: [],
        startedAt: DateTime(now.year, now.month, now.day - 5, 18, 15),
        endedAt: DateTime(now.year, now.month, now.day - 5, 18, 55),
        distanceMeters: 11200,
        isActive: false,
        vehicleType: 'bike',
        points: [
          TripPoint(latitude: 28.6000, longitude: 77.2100, speed: 40.0, accuracy: 4.0, timestamp: DateTime(now.year, now.month, now.day - 5, 18, 15)),
          TripPoint(latitude: 28.6150, longitude: 77.2250, speed: 42.0, accuracy: 4.0, timestamp: DateTime(now.year, now.month, now.day - 5, 18, 35)),
          TripPoint(latitude: 28.6300, longitude: 77.2400, speed: 38.0, accuracy: 4.0, timestamp: DateTime(now.year, now.month, now.day - 5, 18, 55)),
        ],
      ),
      TripModel(
        id: 'sample_7',
        title: 'Scooty Shopping Run',
        ownerId: authService.uid,
        viewerIds: [],
        startedAt: DateTime(now.year, now.month, now.day - 6, 11, 0),
        endedAt: DateTime(now.year, now.month, now.day - 6, 11, 35),
        distanceMeters: 6700,
        isActive: false,
        vehicleType: 'scooty',
        points: [
          TripPoint(latitude: 28.6200, longitude: 77.2000, speed: 28.0, accuracy: 4.0, timestamp: DateTime(now.year, now.month, now.day - 6, 11, 0)),
          TripPoint(latitude: 28.6300, longitude: 77.2150, speed: 25.0, accuracy: 4.0, timestamp: DateTime(now.year, now.month, now.day - 6, 11, 35)),
        ],
      ),
      TripModel(
        id: 'sample_8',
        title: 'Evening Walk Jog',
        ownerId: authService.uid,
        viewerIds: [],
        startedAt: DateTime(now.year, now.month, now.day - 7, 19, 0),
        endedAt: DateTime(now.year, now.month, now.day - 7, 19, 40),
        distanceMeters: 4500,
        isActive: false,
        vehicleType: 'human',
        points: [
          TripPoint(latitude: 28.6100, longitude: 77.2100, speed: 7.5, accuracy: 3.0, timestamp: DateTime(now.year, now.month, now.day - 7, 19, 0)),
          TripPoint(latitude: 28.6180, longitude: 77.2150, speed: 8.0, accuracy: 3.0, timestamp: DateTime(now.year, now.month, now.day - 7, 19, 40)),
        ],
      ),
    ];
  }

  Future<void> syncFirestoreHistory() async {
    try {
      final uid = authService.uid;
      if (uid.isEmpty) return;

      final snapshot = await FirebaseFirestore.instance
          .collection('trips')
          .where('ownerId', isEqualTo: uid)
          .get();

      final existingIds = _historyTrips.map((t) => t.id).toSet();
      bool changed = false;

      final docs = snapshot.docs.where((d) => d.data()['active'] != true).toList();

      for (final doc in docs) {
        if (!existingIds.contains(doc.id)) {
          final firestoreTrip = TripModel.fromFirestore(doc.id, doc.data());
          _historyTrips.add(firestoreTrip);
          existingIds.add(doc.id);
          changed = true;
        }
      }

      if (changed) {
        _historyTrips.sort((a, b) => b.startedAt.compareTo(a.startedAt));
        await _saveLocalHistory();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Firestore history sync: $e');
    }
  }

  Future<void> _saveLocalHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _historyTrips.map((t) => t.toJson()).toList();
      await prefs.setString('saved_history_trips', jsonEncode(jsonList));
    } catch (e) {
      debugPrint('Error saving local history: $e');
    }
  }

  Future<void> deleteTrip(String tripId) async {
    _historyTrips.removeWhere((t) => t.id == tripId);
    await _saveLocalHistory();
    try {
      if (!tripId.startsWith('local_')) {
        await FirebaseFirestore.instance.collection('trips').doc(tripId).delete();
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> clearAllUserData() async {
    if (_active) {
      await stop();
    }
    _points.clear();
    _tripPoints.clear();
    _historyTrips.clear();
    _meters = 0.0;
    _tripId = null;
    _began = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('saved_history_trips');
      await prefs.remove('is_tracking_active');
      await prefs.remove('active_trip_id');
      await prefs.remove('active_trip_began');
      await prefs.remove('active_trip_meters');
      await prefs.remove('active_trip_points');
    } catch (_) {}
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
