import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
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
    initCurrentLocation();
    try {
      FirebaseAuth.instance.authStateChanges().listen((user) {
        if (user != null) {
          syncFirestoreHistory();
        }
      });
    } catch (_) {}
  }

  StreamSubscription<Position>? _positionSubscription;
  Timer? _timer;

  final List<LatLng> _points = [];
  List<LatLng> get points => List.unmodifiable(_points);

  final List<TripPoint> _tripPoints = [];
  List<TripPoint> get tripPoints => List.unmodifiable(_tripPoints);

  Position? _current;
  Position? get current => _current;

  Position? _stationaryAnchor;
  Position? get stationaryAnchor => _stationaryAnchor;

  bool _isStationary = true;
  bool get isStationary => _isStationary;
  bool get isMoving => !_isStationary && _active;

  int _stationaryFixCount = 0;

  String? _tripId;
  String? get tripId => _tripId;

  bool _active = false;
  bool get active => _active;

  bool _starting = false;
  bool get starting => _starting;

  bool _isBackgroundPermissionGranted = true;
  bool get isBackgroundPermissionGranted => _isBackgroundPermissionGranted;

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
    GeofenceService().checkLocation(p);
    notifyListeners();
  }

  Future<Position?> initCurrentLocation({bool forceRefresh = false}) async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        return null;
      }

      final isEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isEnabled) {
        return null;
      }

      // Step 1: Immediate warm start with last known location if we have none yet
      if (_current == null && !forceRefresh) {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null && _current == null) {
          _current = last;
          geocodingService.updateFromPosition(last.latitude, last.longitude);
          notifyListeners();
        }
      }

      // Step 2: Fresh position using Google Play Services Fused Location
      Position? current;
      try {
        current = await Geolocator.getCurrentPosition(
          locationSettings: defaultTargetPlatform == TargetPlatform.android
              ? AndroidSettings(
                  accuracy: LocationAccuracy.high,
                  timeLimit: const Duration(seconds: 10),
                )
              : const LocationSettings(
                  accuracy: LocationAccuracy.high,
                  timeLimit: Duration(seconds: 10),
                ),
        );
      } catch (_) {
        // Fallback for indoors (where satellite GPS might timeout): use network/Wi-Fi fusion
        try {
          current = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 5),
            ),
          );
        } catch (_) {}
      }

      if (current != null) {
        _current = current;
        geocodingService.updateFromPosition(current.latitude, current.longitude);
        GeofenceService().checkLocation(current);
        notifyListeners();
        return current;
      }
      return _current;
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
      _isBackgroundPermissionGranted = (permission == LocationPermission.always);

      _began = DateTime.now();
      _meters = 0.0;
      _points.clear();
      _tripPoints.clear();
      _stationaryAnchor = null;
      _isStationary = true;
      _stationaryFixCount = 0;
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

  /// Evaluates whether a new candidate position [candidate] represents genuine physical movement
  /// rather than stationary GPS jitter or outlier sensor telemetry.
  /// Accommodates in-bag/in-pocket GPS signal attenuation (up to 250m accuracy) while
  /// rejecting gross cellular tower triangulation (> 250m).
  static bool isGenuineMovement({
    required Position candidate,
    required TripPoint lastPoint,
    Position? stationaryAnchor,
    bool isStationary = true,
  }) {
    // 1. Reject gross noise (cellular tower triangulation: > 250m)
    // Note: Phones inside bags, pockets, backpacks, or glove compartments experience satellite signal
    // attenuation where accuracy typically ranges between 35m - 220m.
    if (candidate.accuracy > 250.0) return false;

    // 2. Physical displacement from last registered point
    final step = Geolocator.distanceBetween(
      lastPoint.latitude,
      lastPoint.longitude,
      candidate.latitude,
      candidate.longitude,
    );

    // 3. Teleportation / Outlier Jump Filter (> 55 m/s = 198 km/h over large jump)
    final timeDiffSec = candidate.timestamp.difference(lastPoint.timestamp).inSeconds.abs();
    final calcSpeed = timeDiffSec > 0 ? (step / timeDiffSec) : candidate.speed;
    if (timeDiffSec >= 1 && calcSpeed > 55.0 && step > 150.0) {
      return false;
    }

    // 4. Stationary Drift Filter:
    // When the phone is stationary or has an active stationary anchor,
    // prevent indoor/desk satellite wander from creating spiderweb movements.
    final anchor = stationaryAnchor;
    if (isStationary && anchor != null) {
      final distFromAnchor = Geolocator.distanceBetween(
        anchor.latitude,
        anchor.longitude,
        candidate.latitude,
        candidate.longitude,
      );

      // Adaptive anchor radius based on sensor accuracy:
      // High-accuracy outdoor fixes (accuracy <= 10m) have tight 7.5m tolerance.
      // Indoor / in-bag fixes scale up to 20m tolerance to absorb indoor bounce.
      final anchorTolerance = math.max(7.5, math.min(20.0, candidate.accuracy * 0.55));

      // Inside anchor bubble: reject satellite drift unless speed indicates clear breakout motion
      // Lowered to 0.7 m/s so normal walking pace (2.5 - 4 km/h) with phone inside a bag/pocket breaks out cleanly.
      if (distFromAnchor < anchorTolerance) {
        if (candidate.speed >= 0.7 && distFromAnchor >= 4.0) {
          return true; // Steady walking breakout motion with phone in bag
        }
        if (calcSpeed >= 0.7 && distFromAnchor >= 4.5) {
          return true; // Steady walking breakout
        }
        return false; // Stationary satellite jitter! Anchor remains locked.
      }

      // Moving beyond anchor bubble: check outlier speed relative to anchor
      final anchorTimeDiffSec = candidate.timestamp.difference(anchor.timestamp).inSeconds.abs();
      final anchorSpeed = anchorTimeDiffSec > 0 ? (distFromAnchor / anchorTimeDiffSec) : candidate.speed;
      if (anchorTimeDiffSec >= 1 && anchorSpeed > 55.0 && distFromAnchor > 150.0) {
        return false;
      }

      // Genuine breakout movement from stationary state!
      return true;
    }

    // 5. In-Motion Movement Evaluation (phone is actively moving):
    // Discard sub-noise sensor jitter (< 1.8m) to avoid crowding points,
    // but capture all turns, bends, and corner waypoints faithfully.
    if (step < 1.8) return false;

    // Discard gross cellular tower triangulation fixes while moving (> 250m)
    if (candidate.accuracy > 250.0) return false;

    return true;
  }

  Future<void> _onPosition(Position p) async {
    if (!_active || _tripId == null) return;

    _current = p;
    geocodingService.updateFromPosition(p.latitude, p.longitude);
    GeofenceService().checkLocation(p);

    // Reject coarse cell-tower triangulation fixes (> 250m) from movement path.
    // In-bag or pocket positioning typically maintains 30m - 220m accuracy.
    if (p.accuracy > 250.0) {
      notifyListeners();
      return;
    }

    final bool isFirstPoint = _tripPoints.isEmpty;
    if (isFirstPoint) {
      _stationaryAnchor = p;
      _isStationary = true;
      _stationaryFixCount = 0;
      _points.add(LatLng(p.latitude, p.longitude));
      _tripPoints.add(TripPoint(
        latitude: p.latitude,
        longitude: p.longitude,
        speed: p.speed,
        accuracy: p.accuracy,
        timestamp: p.timestamp,
      ));
      _saveActiveTripState();
      notifyListeners();
      return;
    }

    final lastPoint = _tripPoints.last;
    final genuine = isGenuineMovement(
      candidate: p,
      lastPoint: lastPoint,
      stationaryAnchor: _stationaryAnchor,
      isStationary: _isStationary,
    );

    if (!genuine) {
      // Not genuine movement.
      // If we were in moving state, detect if device has now come to a complete stop
      if (!_isStationary) {
        final step = Geolocator.distanceBetween(
          lastPoint.latitude,
          lastPoint.longitude,
          p.latitude,
          p.longitude,
        );
        if (step < 6.0 && p.speed < 0.6) {
          _stationaryFixCount++;
          if (_stationaryFixCount >= 3) {
            // Stopped at traffic light, cafe, or destination
            _isStationary = true;
            _stationaryAnchor = p;
            _stationaryFixCount = 0;
          }
        } else {
          _stationaryFixCount = 0;
        }
      }
      notifyListeners();
      return;
    }

    final step = Geolocator.distanceBetween(
      lastPoint.latitude,
      lastPoint.longitude,
      p.latitude,
      p.longitude,
    );

    // If device was stationary, transition to moving state and unlock anchor
    if (_isStationary) {
      _isStationary = false;
      _stationaryAnchor = null;
      _stationaryFixCount = 0;
    }

    // True genuine movement! Accumulate real distance
    _meters += step;
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
        distanceFilter: 0, // 0 ensures Android delivers regular time-based updates even when phone is in bag/pocket with screen off
        forceLocationManager: false, // Google Play Services Fused Location
        intervalDuration: const Duration(seconds: 3), // 3-second consistent stream
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: "RaahMilo Tracking Active",
          notificationText: "Live GPS route recording in progress...",
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
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    } else {
      return const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
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

      // If app was terminated for more than 4 hours, auto-finalize the old trip into history if real movement was made
      if (now.difference(lastPointTime).inHours >= 4) {
        debugPrint('Auto-saving stale trip into history: $savedTripId');
        if (restoredTripPoints.length >= 2 && savedMeters >= 15.0) {
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
          _historyTrips.removeWhere((t) => t.id.startsWith('sample_'));
          await _saveLocalHistory();
        }

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
    } else if (finalPoints.isNotEmpty && _current != null && !_isStationary) {
      final lastPt = finalPoints.last;
      final endDist = Geolocator.distanceBetween(
        lastPt.latitude,
        lastPt.longitude,
        _current!.latitude,
        _current!.longitude,
      );
      // Only append destination point if it passes genuine physical movement criteria,
      // has high sensor accuracy (<= 25m), and represents a plausible final step (<= 25m).
      if (endDist >= 2.5 &&
          endDist <= 25.0 &&
          _current!.accuracy <= 25.0 &&
          isGenuineMovement(
            candidate: _current!,
            lastPoint: lastPt,
            stationaryAnchor: _stationaryAnchor,
            isStationary: _isStationary,
          )) {
        final destPt = TripPoint(
          latitude: _current!.latitude,
          longitude: _current!.longitude,
          speed: _current!.speed,
          accuracy: _current!.accuracy,
          timestamp: now,
        );
        finalPoints.add(destPt);
        _points.add(LatLng(_current!.latitude, _current!.longitude));
      }
    }

    if (_points.isEmpty && finalPoints.isNotEmpty) {
      for (final tp in finalPoints) {
        _points.add(LatLng(tp.latitude, tp.longitude));
      }
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

    // Save to local history permanently only if phone actually moved
    if (finalPoints.length >= 2 && totalDistance >= 6.0) {
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
    }

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
      }

      // Permanently remove all mock/sample trips
      _historyTrips.removeWhere((t) => t.id.startsWith('sample_'));
      _historyTrips.sort((a, b) => b.startedAt.compareTo(a.startedAt));
      await _saveLocalHistory();
      notifyListeners();

      await syncFirestoreHistory();
    } catch (e) {
      debugPrint('Error loading history: $e');
    }
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
