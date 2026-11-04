import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/trip_model.dart';
import '../models/vehicle_type.dart';
import '../models/app_notification.dart';
import 'auth_service.dart';
import 'device_manager_service.dart';
import 'geocoding_service.dart';
import 'geofence_service.dart';
import 'notification_service.dart';
import 'share_service.dart';

class TrackingService extends ChangeNotifier {
  static final TrackingService _instance = TrackingService._internal();
  factory TrackingService() => _instance;

  String? _lastUserUid;

  @override
  void notifyListeners() {
    final binding = WidgetsBinding.instance;
    final phase = binding.schedulerPhase;
    if (phase == SchedulerPhase.idle || phase == SchedulerPhase.postFrameCallbacks) {
      super.notifyListeners();
    } else {
      binding.addPostFrameCallback((_) {
        super.notifyListeners();
      });
    }
  }

  TrackingService._internal() {
    _lastUserUid = authService.uid.isNotEmpty ? authService.uid : null;
    loadHistory();
    restoreActiveSession();
    _restoreSelectedVehicle();
    initCurrentLocation();
    _setupAuthListener();
    _initLocationHealthMonitoring();
  }

  void _setupAuthListener() {
    try {
      FirebaseAuth.instance.authStateChanges().listen((user) {
        _handleAuthChange(user?.uid);
      });
    } catch (_) {}

    try {
      authService.addListener(() {
        final currentUid = authService.uid;
        _handleAuthChange(currentUid.isNotEmpty ? currentUid : null);
      });
    } catch (_) {}
  }

  Future<void> _handleAuthChange(String? newUid) async {
    // If the UID hasn't changed, no need to reset
    if (newUid == _lastUserUid) {
      if (newUid != null && newUid.isNotEmpty) {
        syncFirestoreHistory();
      }
      return;
    }

    final oldUid = _lastUserUid;
    _lastUserUid = newUid;

    // Only wipe and isolate if switching between two different user accounts
    if (oldUid != null && oldUid.isNotEmpty && oldUid != newUid) {
      await _saveLocalHistoryForUser(oldUid);
      _historyTrips.clear();
      if (_active) {
        await stop();
      }
      _points.clear();
      _tripPoints.clear();
      _meters = 0.0;
      _tripId = null;
      _began = null;
      notifyListeners();
    }

    // If a user is now logged in, load their scoped trips and sync from cloud
    if (newUid != null && newUid.isNotEmpty) {
      await loadHistory();
      await restoreActiveSession();
      await syncFirestoreHistory();
    }
  }

  Future<void> onUserSignOut() async {
    final uid = authService.uid;
    if (uid.isNotEmpty) {
      await _saveLocalHistoryForUser(uid);
    }
    _historyTrips.clear();
    _points.clear();
    _tripPoints.clear();
    _meters = 0.0;
    _tripId = null;
    _began = null;
    _lastUserUid = null;
    notifyListeners();
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

  bool _isLocationServiceEnabled = true;
  bool get isLocationServiceEnabled => _isLocationServiceEnabled;

  bool _hasLocationPermission = true;
  bool get hasLocationPermission => _hasLocationPermission;

  bool get isGpsReady => _isLocationServiceEnabled && _hasLocationPermission;

  StreamSubscription<ServiceStatus>? _serviceStatusSubscription;

  void cancelLocationHealthMonitoring() {
    _serviceStatusSubscription?.cancel();
    _serviceStatusSubscription = null;
  }

  void _initLocationHealthMonitoring() {
    cancelLocationHealthMonitoring();
    try {
      _serviceStatusSubscription = Geolocator.getServiceStatusStream().listen((status) {
        final enabled = (status == ServiceStatus.enabled);
        if (_isLocationServiceEnabled != enabled) {
          _isLocationServiceEnabled = enabled;
          notifyListeners();
        }
        if (enabled) {
          checkLocationHealth(autoStart: true);
        }
      });
    } catch (_) {}
  }

  Future<bool> checkLocationHealth({bool autoStart = true}) async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      final perm = await Geolocator.checkPermission();
      final hasPerm = (perm == LocationPermission.always || perm == LocationPermission.whileInUse);

      bool changed = false;
      if (_isLocationServiceEnabled != enabled) {
        _isLocationServiceEnabled = enabled;
        changed = true;
      }
      if (_hasLocationPermission != hasPerm) {
        _hasLocationPermission = hasPerm;
        changed = true;
      }

      if (changed) {
        notifyListeners();
      }

      if (enabled && hasPerm) {
        if (!_active && !_starting && autoStart) {
          // Attempt to restore any active session from SharedPreferences first
          await restoreActiveSession();
          if (!_active) {
            await start(preserveExistingPoints: true);
          }
        } else if (_active && _positionSubscription == null) {
          // Reconnect GPS position stream without wiping points or meters!
          _reconnectPositionStream();
        }
        return true;
      } else {
        return false;
      }
    } catch (_) {
      return false;
    }
  }

  void _reconnectPositionStream() {
    if (!_active) return;
    try {
      _positionSubscription?.cancel();
      final locationSettings = _createLocationSettings();
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (p) => _onPosition(p),
        onError: (Object e) {
          _lastError = e.toString();
          debugPrint('Position stream error: $e');
          _positionSubscription?.cancel();
          _positionSubscription = null;
          notifyListeners();
        },
      );
      Geolocator.getCurrentPosition().then((p) {
        if (_active) _onPosition(p);
      }).catchError((_) {});
    } catch (e) {
      debugPrint('Error reconnecting position stream: $e');
    }
  }

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

  DateTime? _lastSpeedAlertTime;

  final List<TripModel> _historyTrips = [];
  List<TripModel> get historyTrips {
    final list = List<TripModel>.from(_historyTrips);
    if (_active && _tripPoints.length >= 2) {
      final activeTrip = TripModel(
        id: _tripId ?? 'live_active',
        title: '${_currentVehicle.displayName} Trip • In Progress (Live)',
        ownerId: authService.uid,
        viewerIds: [],
        startedAt: (_began ?? DateTime.now()).toLocal(),
        endedAt: null,
        distanceMeters: currentTripDistanceMeters,
        isActive: true,
        points: List<TripPoint>.from(_tripPoints),
        vehicleType: _currentVehicle.name,
      );
      list.insert(0, activeTrip);
    }
    return List.unmodifiable(list);
  }

  double get currentTripDistanceMeters {
    double m = _meters;
    if (_tripPoints.length >= 2) {
      double ptsDist = 0.0;
      for (int i = 0; i < _tripPoints.length - 1; i++) {
        ptsDist += Geolocator.distanceBetween(
          _tripPoints[i].latitude,
          _tripPoints[i].longitude,
          _tripPoints[i + 1].latitude,
          _tripPoints[i + 1].longitude,
        );
      }
      if (ptsDist > m) {
        m = ptsDist;
        _meters = ptsDist;
      }
    }
    return m;
  }

  VehicleType _currentVehicle = VehicleType.car;
  VehicleType get currentVehicle => _currentVehicle;

  void setVehicleType(VehicleType type) {
    if (_currentVehicle == type) return;
    _currentVehicle = type;
    final uid = authService.uid;
    final key = uid.isNotEmpty ? 'selected_vehicle_type_$uid' : 'selected_vehicle_type';
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(key, type.name);
    });
    notifyListeners();
  }

  Future<void> _restoreSelectedVehicle() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = authService.uid;
      final key = uid.isNotEmpty ? 'selected_vehicle_type_$uid' : 'selected_vehicle_type';
      final saved = prefs.getString(key) ?? prefs.getString('selected_vehicle_type');
      if (saved != null) {
        _currentVehicle = VehicleType.fromString(saved);
        notifyListeners();
      }
    } catch (_) {}
  }

  double get todayDistanceMeters => getDistanceForDate(DateTime.now()) * 1000.0;
  double get todayDistanceKm => getDistanceForDate(DateTime.now());

  String get todayDistanceFormatted {
    final km = todayDistanceKm;
    if (km <= 0.0) return '0 km';
    if (km < 1.0) {
      return '${km.toStringAsFixed(2)} km';
    }
    return '${km.toStringAsFixed(1)} km';
  }

  double getDistanceForDate(DateTime date, {VehicleType? vehicleFilter}) {
    double totalMeters = 0.0;
    int historyCountForDate = 0;

    for (final trip in _historyTrips) {
      final tripDate = trip.startedAt.toLocal();
      if (tripDate.year == date.year &&
          tripDate.month == date.month &&
          tripDate.day == date.day) {
        if (vehicleFilter == null || trip.vehicleTypeEnum == vehicleFilter) {
          double dist = trip.distanceMeters;
          // Fallback: If trip.distanceMeters was 0, compute from breadcrumbs
          if (dist <= 0.0 && trip.points.length >= 2) {
            for (int i = 0; i < trip.points.length - 1; i++) {
              dist += Geolocator.distanceBetween(
                trip.points[i].latitude,
                trip.points[i].longitude,
                trip.points[i + 1].latitude,
                trip.points[i + 1].longitude,
              );
            }
          }
          totalMeters += dist;
          if (dist > 0.0) historyCountForDate++;

          // If trip has empty points and 0 distance, trigger background point fetch
          if (trip.points.isEmpty && dist <= 0.0 && !trip.id.startsWith('local_')) {
            unawaited(ensureTripPointsLoaded(trip));
          }
        }
      }
    }

    final now = DateTime.now();
    final isToday = date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;

    if (vehicleFilter == null || _currentVehicle == vehicleFilter) {
      if (isToday) {
        // Today's active tracking meters
        double currentMeters = _meters;
        // Check today's points in _tripPoints
        final todayPoints = _tripPoints.where((tp) {
          final pt = tp.timestamp.toLocal();
          return pt.year == now.year && pt.month == now.month && pt.day == now.day;
        }).toList();

        if (todayPoints.length >= 2) {
          double pointsDist = 0.0;
          for (int i = 0; i < todayPoints.length - 1; i++) {
            pointsDist += Geolocator.distanceBetween(
              todayPoints[i].latitude,
              todayPoints[i].longitude,
              todayPoints[i + 1].latitude,
              todayPoints[i + 1].longitude,
            );
          }
          if (pointsDist > currentMeters) {
            currentMeters = pointsDist;
            _meters = pointsDist;
          }
        }
        final activeAlreadyInHistory = _historyTrips.any((t) => t.id == _tripId && t.isActive);
        if (!activeAlreadyInHistory) {
          totalMeters += currentMeters;
        }
      } else {
        // Past day (e.g. yesterday 2 Nov): If there are unfinalized points in _tripPoints for this date
        // and no history trip was saved yet, calculate directly from those points!
        if (totalMeters <= 0.0) {
          final pastDatePoints = _tripPoints.where((tp) {
            final pt = tp.timestamp.toLocal();
            return pt.year == date.year && pt.month == date.month && pt.day == date.day;
          }).toList();

          if (pastDatePoints.length >= 2) {
            double pastDist = 0.0;
            for (int i = 0; i < pastDatePoints.length - 1; i++) {
              pastDist += Geolocator.distanceBetween(
                pastDatePoints[i].latitude,
                pastDatePoints[i].longitude,
                pastDatePoints[i + 1].latitude,
                pastDatePoints[i + 1].longitude,
              );
            }
            totalMeters += pastDist;
          }
        }
      }
    }
    return totalMeters / 1000.0;
  }

  List<TripModel> getTripsForDate(DateTime date, {VehicleType? vehicleFilter}) {
    final list = _historyTrips.where((trip) {
      final tripDate = trip.startedAt.toLocal();
      final matchesDate = tripDate.year == date.year &&
          tripDate.month == date.month &&
          tripDate.day == date.day;
      if (!matchesDate) return false;
      if (vehicleFilter != null && trip.vehicleTypeEnum != vehicleFilter) {
        return false;
      }
      return true;
    }).toList();

    final now = DateTime.now();
    final isToday = date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;

    if (vehicleFilter == null || _currentVehicle == vehicleFilter) {
      if (isToday) {
        // If viewing today, include any live or recorded points from today
        final todayPoints = _tripPoints.where((tp) {
          final pt = tp.timestamp.toLocal();
          return pt.year == now.year && pt.month == now.month && pt.day == now.day;
        }).toList();

        final hasTodayPoints = todayPoints.length >= 2 || _tripPoints.length >= 2;
        final alreadyHasActive = list.any((t) => t.isActive || t.id == _tripId);

        if (hasTodayPoints && !alreadyHasActive) {
          final pts = todayPoints.isNotEmpty ? todayPoints : List<TripPoint>.from(_tripPoints);
          double activeDist = _meters;
          if (pts.length >= 2) {
            double computed = 0.0;
            for (int i = 0; i < pts.length - 1; i++) {
              computed += Geolocator.distanceBetween(
                pts[i].latitude,
                pts[i].longitude,
                pts[i + 1].latitude,
                pts[i + 1].longitude,
              );
            }
            if (computed > activeDist) activeDist = computed;
          }

          final activeTrip = TripModel(
            id: _tripId ?? 'live_active',
            title: '${_currentVehicle.displayName} Trip • ${_active ? "In Progress (Live)" : "Today"}',
            ownerId: authService.uid,
            viewerIds: [],
            startedAt: pts.isNotEmpty ? pts.first.timestamp.toLocal() : (_began ?? now).toLocal(),
            endedAt: _active ? null : (pts.isNotEmpty ? pts.last.timestamp.toLocal() : now.toLocal()),
            distanceMeters: activeDist,
            isActive: _active,
            points: pts,
            vehicleType: _currentVehicle.name,
          );
          list.insert(0, activeTrip);
        }
      } else {
        // Past day: If there are unfinalized points in _tripPoints and no trip in history for this date
        if (list.isEmpty) {
          final pastDatePoints = _tripPoints.where((tp) {
            final pt = tp.timestamp.toLocal();
            return pt.year == date.year && pt.month == date.month && pt.day == date.day;
          }).toList();

          if (pastDatePoints.length >= 2) {
            double pastDist = 0.0;
            for (int i = 0; i < pastDatePoints.length - 1; i++) {
              pastDist += Geolocator.distanceBetween(
                pastDatePoints[i].latitude,
                pastDatePoints[i].longitude,
                pastDatePoints[i + 1].latitude,
                pastDatePoints[i + 1].longitude,
              );
            }
            final pastTrip = TripModel(
              id: 'trip_${date.year}_${date.month}_${date.day}_unfinalized',
              title: '${_currentVehicle.displayName} Trip at ${DateFormat('hh:mm a').format(pastDatePoints.first.timestamp.toLocal())}',
              ownerId: authService.uid,
              viewerIds: [],
              startedAt: pastDatePoints.first.timestamp.toLocal(),
              endedAt: pastDatePoints.last.timestamp.toLocal(),
              distanceMeters: pastDist,
              isActive: false,
              points: pastDatePoints,
              vehicleType: _currentVehicle.name,
            );
            list.add(pastTrip);
          }
        }
      }
    }

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

    deviceManagerService.updateCurrentDeviceLocation(
      lat: p.latitude,
      lng: p.longitude,
      speedKmh: p.speed.clamp(0, 999) * 3.6,
      heading: p.heading,
      address: geocodingService.fullAddress,
      isTrackingActive: _active,
    );
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
          deviceManagerService.registerCurrentDevice(
            latitude: last.latitude,
            longitude: last.longitude,
            address: geocodingService.fullAddress,
            isTrackingActive: _active,
          );
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
        deviceManagerService.registerCurrentDevice(
          latitude: current.latitude,
          longitude: current.longitude,
          speedKmh: current.speed.clamp(0, 999) * 3.6,
          heading: current.heading,
          address: geocodingService.fullAddress,
          isTrackingActive: _active,
        );
        notifyListeners();
        return current;
      }
      return _current;
    } catch (_) {
      return _current;
    }
  }

  Future<void> start({bool preserveExistingPoints = false}) async {
    if (_active || _starting) return;
    _starting = true;
    _lastError = null;
    notifyListeners();

    try {
      final isServiceEnabled = await Geolocator.isLocationServiceEnabled();
      _isLocationServiceEnabled = isServiceEnabled;
      if (!isServiceEnabled) {
        _lastError = 'Location services disabled in device settings.';
        _starting = false;
        notifyListeners();
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      final hasPerm = (permission == LocationPermission.always || permission == LocationPermission.whileInUse);
      _hasLocationPermission = hasPerm;
      if (!hasPerm) {
        _lastError = 'Location permission is required for live tracking.';
        _starting = false;
        notifyListeners();
        return;
      }
      _isBackgroundPermissionGranted = (permission == LocationPermission.always);

      // Pre-check SharedPreferences: If in-memory _tripPoints is empty, load any unfinalized session from disk
      if (_tripPoints.isEmpty) {
        try {
          final prefs = await SharedPreferences.getInstance();
          final savedPointsJson = prefs.getString('active_trip_points');
          if (savedPointsJson != null && savedPointsJson.isNotEmpty) {
            final List<dynamic> list = jsonDecode(savedPointsJson);
            for (final item in list) {
              if (item is Map<String, dynamic>) {
                final tp = TripPoint.fromJson(item);
                _tripPoints.add(tp);
                _points.add(LatLng(tp.latitude, tp.longitude));
              }
            }
            final savedM = prefs.getDouble('active_trip_meters') ?? 0.0;
            if (savedM > _meters) _meters = savedM;
            final beganStr = prefs.getString('active_trip_began');
            if (beganStr != null) _began = DateTime.tryParse(beganStr);
            final savedId = prefs.getString('active_trip_id');
            if (savedId != null && savedId.isNotEmpty) _tripId = savedId;
          }
        } catch (_) {}
      }

      // SAFETY: Group all unfinalized points by calendar day.
      // Auto-archive any points from past calendar days (e.g. 2 Nov) permanently into _historyTrips!
      final now = DateTime.now();
      final Map<String, List<TripPoint>> pointsByDay = {};
      for (final tp in _tripPoints) {
        final d = tp.timestamp.toLocal();
        final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        pointsByDay.putIfAbsent(key, () => []).add(tp);
      }

      final todayKey = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      // Finalize past days
      for (final entry in pointsByDay.entries) {
        if (entry.key != todayKey) {
          final pastPoints = entry.value;
          if (pastPoints.length >= 2) {
            double pastDist = 0.0;
            for (int i = 0; i < pastPoints.length - 1; i++) {
              pastDist += Geolocator.distanceBetween(
                pastPoints[i].latitude,
                pastPoints[i].longitude,
                pastPoints[i + 1].latitude,
                pastPoints[i + 1].longitude,
              );
            }
            if (pastDist >= 5.0) {
              final pastDate = pastPoints.first.timestamp.toLocal();
              final existingIndex = _historyTrips.indexWhere((t) {
                final td = t.startedAt.toLocal();
                return td.year == pastDate.year && td.month == pastDate.month && td.day == pastDate.day;
              });
              if (existingIndex == -1) {
                final pastTrip = TripModel(
                  id: 'trip_${pastDate.year}_${pastDate.month}_${pastDate.day}_${pastPoints.first.timestamp.millisecondsSinceEpoch}',
                  title: '${_currentVehicle.displayName} Trip • ${DateFormat('d MMM yyyy').format(pastDate)}',
                  ownerId: authService.uid,
                  viewerIds: const [],
                  startedAt: pastPoints.first.timestamp,
                  endedAt: pastPoints.last.timestamp,
                  distanceMeters: pastDist,
                  isActive: false,
                  points: pastPoints,
                  vehicleType: _currentVehicle.name,
                );
                _historyTrips.insert(0, pastTrip);
              } else if (_historyTrips[existingIndex].distanceMeters <= 0.0 || _historyTrips[existingIndex].points.isEmpty) {
                _historyTrips[existingIndex] = _historyTrips[existingIndex].copyWith(
                  distanceMeters: pastDist > 0 ? pastDist : _historyTrips[existingIndex].distanceMeters,
                  points: pastPoints,
                  endedAt: pastPoints.last.timestamp,
                );
              }
            }
          }
        }
      }
      _historyTrips.removeWhere((t) => t.id.startsWith('sample_'));
      _historyTrips.sort((a, b) => b.startedAt.compareTo(a.startedAt));
      await _saveLocalHistory();

      // Today's points handling: retain today's recorded points and distance
      final todayPoints = pointsByDay[todayKey] ?? [];
      if (!preserveExistingPoints && todayPoints.isEmpty) {
        _began = DateTime.now();
        _meters = 0.0;
        _points.clear();
        _tripPoints.clear();
        _stationaryAnchor = null;
        _isStationary = true;
        _stationaryFixCount = 0;
        _elapsed = Duration.zero;
      } else {
        _tripPoints.clear();
        _tripPoints.addAll(todayPoints);
        _points.clear();
        _points.addAll(todayPoints.map((tp) => LatLng(tp.latitude, tp.longitude)));
        _began ??= todayPoints.isNotEmpty ? todayPoints.first.timestamp : now;
        double todayDist = 0.0;
        for (int i = 0; i < todayPoints.length - 1; i++) {
          todayDist += Geolocator.distanceBetween(
            todayPoints[i].latitude,
            todayPoints[i].longitude,
            todayPoints[i + 1].latitude,
            todayPoints[i + 1].longitude,
          );
        }
        if (todayDist > _meters) _meters = todayDist;
      }

      // Start elapsed timer
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_began != null) {
          _elapsed = DateTime.now().difference(_began!);
          notifyListeners();
        }
      });

      // Synchronously generate a permanent Firestore document ID
      final uid = authService.uid;
      DocumentReference<Map<String, dynamic>>? docRef;
      if (uid.isNotEmpty) {
        docRef = FirebaseFirestore.instance.collection('trips').doc();
      }
      _tripId = docRef?.id ?? 'trip_${DateTime.now().millisecondsSinceEpoch}';

      _active = true;
      _starting = false;
      notifyListeners();

      // Async Firestore trip creation with SetOptions(merge: true) so it never fails on network delay
      if (docRef != null) {
        docRef.set({
          'title': '${_currentVehicle.displayName} Trip at ${DateFormat('hh:mm a').format(_began!)}',
          'ownerId': uid,
          'viewerIds': <String>[],
          'startedAt': FieldValue.serverTimestamp(),
          'endedAt': null,
          'active': true,
          'distanceMeters': _meters,
          'latest': null,
          'vehicleType': _currentVehicle.name,
        }, SetOptions(merge: true)).catchError((e) {
          debugPrint('Firestore trip creation notice: $e');
        });
      }

      // Persist tracking session to SharedPreferences immediately with valid trip ID
      _persistInitialActiveSession();

      // Seed with last known or current position immediately if available
      if (_current != null) {
        _onPosition(_current!);
      } else {
        Geolocator.getLastKnownPosition().then((last) {
          if (last != null && _tripPoints.isEmpty && _active) {
            _onPosition(last);
          }
        }).catchError((_) {});
      }

      // Reliable background & foreground tracking configuration
      _positionSubscription?.cancel();
      try {
        final locationSettings = _createLocationSettings();
        _positionSubscription = Geolocator.getPositionStream(
          locationSettings: locationSettings,
        ).listen(
          (p) => _onPosition(p),
          onError: (Object e) {
            _lastError = e.toString();
            debugPrint('Position stream error: $e');
            _positionSubscription?.cancel();
            _positionSubscription = null;
            notifyListeners();
          },
        );
      } catch (streamError) {
        debugPrint('AndroidSettings failed ($streamError), falling back to standard LocationSettings');
        try {
          _positionSubscription = Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 0,
            ),
          ).listen(
            (p) => _onPosition(p),
            onError: (Object e) {
              _lastError = e.toString();
              debugPrint('Standard position stream error: $e');
              _positionSubscription?.cancel();
              _positionSubscription = null;
              notifyListeners();
            },
          );
        } catch (fallbackError) {
          debugPrint('Standard stream also failed: $fallbackError');
        }
      }

      // Async non-blocking fresh fix attempt with short timeout
      Geolocator.getCurrentPosition(
        locationSettings: defaultTargetPlatform == TargetPlatform.android
            ? AndroidSettings(
                accuracy: LocationAccuracy.high,
                timeLimit: const Duration(seconds: 5),
              )
            : const LocationSettings(
                accuracy: LocationAccuracy.high,
                timeLimit: Duration(seconds: 5),
              ),
      ).then((p) {
        if (_active) _onPosition(p);
      }).catchError((_) {});

      // Add Notification
      NotificationService().addNotification(
        title: 'Tracking Started',
        subtitle: 'Live tracking has started',
        type: NotificationType.trackingStarted,
      );
    } catch (e) {
      _lastError = '$e';
      debugPrint('Error starting tracking: $e');
    } finally {
      _starting = false;
      notifyListeners();
    }
  }

  Future<void> _persistInitialActiveSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_tracking_active', true);
      await prefs.setString('active_trip_user_id', authService.uid);
      if (_tripId != null) await prefs.setString('active_trip_id', _tripId!);
      if (_began != null) await prefs.setString('active_trip_began', _began!.toIso8601String());
      await prefs.setDouble('active_trip_meters', _meters);
      final jsonList = _tripPoints.map((tp) => tp.toJson()).toList();
      await prefs.setString('active_trip_points', jsonEncode(jsonList));
    } catch (_) {}
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
      // High-accuracy outdoor fixes (accuracy <= 10m) have tight 6.5m tolerance.
      // Indoor / in-bag fixes scale up to 12.0m tolerance (reduced from 20m) so real movement breaks out quickly.
      final anchorTolerance = math.max(6.5, math.min(12.0, candidate.accuracy * 0.45));

      // Inside anchor bubble: reject satellite drift completely while stationary
      if (distFromAnchor < anchorTolerance) {
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
    // Discard sub-noise sensor jitter (< 1.6m), but capture all turns, bends, and corner waypoints faithfully.
    if (step < 1.6) return false;

    // Discard gross cellular tower triangulation fixes while moving (> 250m)
    if (candidate.accuracy > 250.0) return false;

    return true;
  }

  Future<void> _onPosition(Position p) async {
    if (!_active || _tripId == null) return;

    _current = p;
    geocodingService.updateFromPosition(p.latitude, p.longitude);
    GeofenceService().checkLocation(p);

    deviceManagerService.updateCurrentDeviceLocation(
      lat: p.latitude,
      lng: p.longitude,
      speedKmh: p.speed.clamp(0, 999) * 3.6,
      heading: p.heading,
      address: geocodingService.fullAddress,
      isTrackingActive: _active,
    );

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

    // Day boundary rollover: If recorded points belong to a previous calendar day,
    // automatically finalize yesterday's trip into history and start fresh for today
    final nowLocal = p.timestamp.toLocal();
    final firstPointLocal = _tripPoints.first.timestamp.toLocal();
    if (firstPointLocal.year != nowLocal.year ||
        firstPointLocal.month != nowLocal.month ||
        firstPointLocal.day != nowLocal.day) {
      await _rolloverPastDayTrips(nowLocal);
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

    // Speed alert check (> 80 km/h with 5-minute debounce cooldown)
    final speedKmh = (p.speed.clamp(0, 999) * 3.6);
    if (speedKmh > 80 &&
        (_lastSpeedAlertTime == null ||
            DateTime.now().difference(_lastSpeedAlertTime!).inMinutes >= 5)) {
      _lastSpeedAlertTime = DateTime.now();
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

    // Sync to Firestore asynchronously without blocking local tracking
    final id = _tripId;
    if (id != null && !id.startsWith('local_') && authService.uid.isNotEmpty) {
      try {
        final ref = FirebaseFirestore.instance.collection('trips').doc(id);
        ref.collection('points').add({
          'lat': p.latitude,
          'lng': p.longitude,
          'accuracy': p.accuracy,
          'speed': p.speed,
          'at': Timestamp.fromDate(p.timestamp),
        }).catchError((_) {});
        ref.set({
          'latest': {
            'lat': p.latitude,
            'lng': p.longitude,
            'speed': p.speed,
            'accuracy': p.accuracy,
            'at': Timestamp.fromDate(p.timestamp),
          },
          'distanceMeters': _meters,
        }, SetOptions(merge: true)).catchError((_) {});
      } catch (e) {
        debugPrint('Cloud sync notice: $e');
      }
    }
  }

  Future<void> _saveActiveTripState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_tracking_active', _active);
      await prefs.setString('active_trip_user_id', authService.uid);
      if (_tripId != null) await prefs.setString('active_trip_id', _tripId!);
      if (_began != null) await prefs.setString('active_trip_began', _began!.toIso8601String());
      await prefs.setDouble('active_trip_meters', _meters);
      final jsonList = _tripPoints.map((tp) => tp.toJson()).toList();
      await prefs.setString('active_trip_points', jsonEncode(jsonList));
    } catch (_) {}
  }

  Future<void> _rolloverPastDayTrips(DateTime nowLocal) async {
    try {
      final Map<String, List<TripPoint>> pointsByDay = {};
      for (final tp in _tripPoints) {
        final d = tp.timestamp.toLocal();
        final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        pointsByDay.putIfAbsent(key, () => []).add(tp);
      }

      final todayKey = '${nowLocal.year}-${nowLocal.month.toString().padLeft(2, '0')}-${nowLocal.day.toString().padLeft(2, '0')}';

      for (final entry in pointsByDay.entries) {
        if (entry.key != todayKey) {
          final pastPoints = entry.value;
          if (pastPoints.length >= 2) {
            double pastDist = 0.0;
            for (int i = 0; i < pastPoints.length - 1; i++) {
              pastDist += Geolocator.distanceBetween(
                pastPoints[i].latitude,
                pastPoints[i].longitude,
                pastPoints[i + 1].latitude,
                pastPoints[i + 1].longitude,
              );
            }
            final pastDate = pastPoints.first.timestamp.toLocal();
            final existingIndex = _historyTrips.indexWhere((t) {
              final td = t.startedAt.toLocal();
              return td.year == pastDate.year && td.month == pastDate.month && td.day == pastDate.day;
            });
            if (existingIndex == -1) {
              final finalizedTrip = TripModel(
                id: 'trip_${pastDate.year}_${pastDate.month}_${pastDate.day}_${pastPoints.first.timestamp.millisecondsSinceEpoch}',
                title: '${_currentVehicle.displayName} Trip • ${DateFormat('d MMM yyyy').format(pastDate)}',
                ownerId: authService.uid,
                viewerIds: const [],
                startedAt: pastPoints.first.timestamp,
                endedAt: pastPoints.last.timestamp,
                distanceMeters: pastDist,
                isActive: false,
                points: pastPoints,
                vehicleType: _currentVehicle.name,
              );
              _historyTrips.insert(0, finalizedTrip);
              _historyTrips.removeWhere((t) => t.id.startsWith('sample_'));
              await _saveLocalHistory();
            } else if (_historyTrips[existingIndex].distanceMeters <= 0.0 || _historyTrips[existingIndex].points.isEmpty) {
              _historyTrips[existingIndex] = _historyTrips[existingIndex].copyWith(
                distanceMeters: pastDist > 0 ? pastDist : _historyTrips[existingIndex].distanceMeters,
                points: pastPoints,
                endedAt: pastPoints.last.timestamp,
              );
              await _saveLocalHistory();
            }

            // Update old Firestore trip doc if it matched previous tripId
            if (_tripId != null && !_tripId!.startsWith('local_')) {
              try {
                FirebaseFirestore.instance.collection('trips').doc(_tripId).set({
                  'active': false,
                  'endedAt': Timestamp.fromDate(pastPoints.last.timestamp),
                  'distanceMeters': pastDist,
                }, SetOptions(merge: true)).catchError((_) {});
              } catch (_) {}
            }
          }
        }
      }

      // Retain only today's points
      final todayPoints = pointsByDay[todayKey] ?? [];
      _tripPoints.clear();
      _tripPoints.addAll(todayPoints);
      _points.clear();
      _points.addAll(todayPoints.map((tp) => LatLng(tp.latitude, tp.longitude)));

      double todayMeters = 0.0;
      for (int i = 0; i < todayPoints.length - 1; i++) {
        todayMeters += Geolocator.distanceBetween(
          todayPoints[i].latitude,
          todayPoints[i].longitude,
          todayPoints[i + 1].latitude,
          todayPoints[i + 1].longitude,
        );
      }
      _meters = todayMeters;
      _began = todayPoints.isNotEmpty ? todayPoints.first.timestamp : nowLocal;
      _tripId = 'trip_${nowLocal.millisecondsSinceEpoch}';

      await _saveActiveTripState();
      notifyListeners();
    } catch (e) {
      debugPrint('Error during day rollover: $e');
    }
  }

  LocationSettings _createLocationSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0, // 0 ensures Android delivers regular time-based updates even when phone is in bag/pocket with screen off
        forceLocationManager: false, // Google Play Services Fused Location
        intervalDuration: const Duration(seconds: 3), // 3-second consistent stream
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: "RaahMilo Tracking Active",
          notificationText: "Live GPS route recording in progress...",
          enableWakeLock: true,
          setOngoing: true,
          color: Color(0xFF10B981),
          notificationIcon: AndroidResource(name: 'ic_launcher'),
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
      final uid = authService.uid;
      if (uid.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      final activeUserId = prefs.getString('active_trip_user_id');
      if (activeUserId != null && activeUserId.isNotEmpty && activeUserId != uid) {
        // Active tracking session belongs to another account, do not restore for current user
        return;
      }

      final savedTripId = prefs.getString('active_trip_id');
      final beganStr = prefs.getString('active_trip_began');
      final savedMeters = prefs.getDouble('active_trip_meters') ?? 0.0;
      final savedPointsJson = prefs.getString('active_trip_points');

      final beganDate = beganStr != null ? (DateTime.tryParse(beganStr) ?? DateTime.now()) : DateTime.now();

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

      // Compute total effective distance from restored points as fallback
      double restoredComputedDist = 0.0;
      if (restoredTripPoints.length >= 2) {
        for (int i = 0; i < restoredTripPoints.length - 1; i++) {
          restoredComputedDist += Geolocator.distanceBetween(
            restoredTripPoints[i].latitude,
            restoredTripPoints[i].longitude,
            restoredTripPoints[i + 1].latitude,
            restoredTripPoints[i + 1].longitude,
          );
        }
      }
      final effectiveMeters = savedMeters > restoredComputedDist ? savedMeters : restoredComputedDist;

      // Group restored points by local calendar day (YYYY-MM-DD)
      final Map<String, List<TripPoint>> pointsByDay = {};
      for (final tp in restoredTripPoints) {
        final d = tp.timestamp.toLocal();
        final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        pointsByDay.putIfAbsent(key, () => []).add(tp);
      }

      final todayKey = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      // Auto-finalize any past day points into _historyTrips immediately!
      for (final entry in pointsByDay.entries) {
        if (entry.key != todayKey) {
          final pastPoints = entry.value;
          if (pastPoints.length >= 2) {
            double pastDist = 0.0;
            for (int i = 0; i < pastPoints.length - 1; i++) {
              pastDist += Geolocator.distanceBetween(
                pastPoints[i].latitude,
                pastPoints[i].longitude,
                pastPoints[i + 1].latitude,
                pastPoints[i + 1].longitude,
              );
            }
            if (pastDist >= 5.0) {
              final pastDate = pastPoints.first.timestamp.toLocal();
              final existingIndex = _historyTrips.indexWhere((t) {
                final td = t.startedAt.toLocal();
                return td.year == pastDate.year && td.month == pastDate.month && td.day == pastDate.day;
              });
              final pastTrip = existingIndex == -1
                  ? TripModel(
                      id: 'trip_${pastDate.year}_${pastDate.month}_${pastDate.day}_${pastPoints.first.timestamp.millisecondsSinceEpoch}',
                      title: '${_currentVehicle.displayName} Trip • ${DateFormat('d MMM yyyy').format(pastDate)}',
                      ownerId: uid,
                      viewerIds: const [],
                      startedAt: pastPoints.first.timestamp,
                      endedAt: pastPoints.last.timestamp,
                      distanceMeters: pastDist,
                      isActive: false,
                      points: pastPoints,
                      vehicleType: _currentVehicle.name,
                    )
                  : _historyTrips[existingIndex].copyWith(
                      distanceMeters: pastDist > 0 ? pastDist : _historyTrips[existingIndex].distanceMeters,
                      points: pastPoints,
                      endedAt: pastPoints.last.timestamp,
                    );

              if (existingIndex == -1) {
                _historyTrips.insert(0, pastTrip);
                _historyTrips.removeWhere((t) => t.id.startsWith('sample_'));
              } else {
                _historyTrips[existingIndex] = pastTrip;
              }
              await _saveLocalHistory();

              if (savedTripId != null && !savedTripId.startsWith('local_')) {
                try {
                  FirebaseFirestore.instance.collection('trips').doc(pastTrip.id).set({
                    'title': pastTrip.title,
                    'ownerId': authService.uid,
                    'viewerIds': const [],
                    'active': false,
                    'startedAt': Timestamp.fromDate(pastTrip.startedAt),
                    'endedAt': Timestamp.fromDate(pastTrip.endedAt!),
                    'distanceMeters': pastDist,
                    'vehicleType': _currentVehicle.name,
                  }, SetOptions(merge: true)).catchError((_) {});
                } catch (_) {}
              }
            }
          }
        }
      }

      final isActive = prefs.getBool('is_tracking_active') ?? false;
      final todayPoints = pointsByDay[todayKey] ?? [];
      final todayRestoredPoints = todayPoints.map((tp) => LatLng(tp.latitude, tp.longitude)).toList();

      final lastPointTime = restoredTripPoints.isNotEmpty
          ? restoredTripPoints.last.timestamp
          : beganDate;

      // If app was terminated for more than 4 hours, auto-finalize the old trip into history if real movement was made
      if (now.difference(lastPointTime).inHours >= 4 && !isActive) {
        debugPrint('Auto-saving stale trip into history: $savedTripId');
        if (todayPoints.length >= 2) {
          double todayDist = 0.0;
          for (int i = 0; i < todayPoints.length - 1; i++) {
            todayDist += Geolocator.distanceBetween(
              todayPoints[i].latitude,
              todayPoints[i].longitude,
              todayPoints[i + 1].latitude,
              todayPoints[i + 1].longitude,
            );
          }
          if (todayDist >= 6.0) {
            final staleTripId = savedTripId ?? 'stale_${todayPoints.first.timestamp.millisecondsSinceEpoch}';
            final staleTrip = TripModel(
              id: staleTripId,
              title: '${_currentVehicle.displayName} Trip at ${DateFormat('hh:mm a').format(todayPoints.first.timestamp)}',
              ownerId: authService.uid,
              viewerIds: const [],
              startedAt: todayPoints.first.timestamp,
              endedAt: todayPoints.last.timestamp,
              distanceMeters: todayDist,
              isActive: false,
              points: todayPoints,
              vehicleType: _currentVehicle.name,
            );
            _historyTrips.insert(0, staleTrip);
            _historyTrips.removeWhere((t) => t.id.startsWith('sample_'));
            await _saveLocalHistory();
          }
        }

        await prefs.remove('is_tracking_active');
        await prefs.remove('active_trip_id');
        await prefs.remove('active_trip_began');
        await prefs.remove('active_trip_meters');
        await prefs.remove('active_trip_points');
        notifyListeners();
        return;
      }

      // Resume active tracking session seamlessly with today's route
      double todayDist = 0.0;
      for (int i = 0; i < todayPoints.length - 1; i++) {
        todayDist += Geolocator.distanceBetween(
          todayPoints[i].latitude,
          todayPoints[i].longitude,
          todayPoints[i + 1].latitude,
          todayPoints[i + 1].longitude,
        );
      }

      final isFromToday = beganDate.day == now.day && beganDate.month == now.month && beganDate.year == now.year;
      _tripId = (isFromToday && savedTripId != null && savedTripId.isNotEmpty)
          ? savedTripId
          : 'trip_${now.millisecondsSinceEpoch}';
      _began = isFromToday ? beganDate : (todayPoints.isNotEmpty ? todayPoints.first.timestamp : now);
      _meters = todayDist > 0 ? todayDist : (isFromToday ? effectiveMeters : 0.0);
      _active = true;
      _elapsed = now.difference(_began!);

      _points.clear();
      _points.addAll(todayRestoredPoints);

      _tripPoints.clear();
      _tripPoints.addAll(todayPoints);

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
      await prefs.remove('active_trip_user_id');
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
          'points': finalPoints.map((p) => p.toJson()).toList(),
          'vehicleType': _currentVehicle.name,
        });
      } catch (_) {}
    }

    double computedDist = totalDistance;
    if (computedDist <= 0.0 && finalPoints.length >= 2) {
      for (int i = 0; i < finalPoints.length - 1; i++) {
        computedDist += Geolocator.distanceBetween(
          finalPoints[i].latitude,
          finalPoints[i].longitude,
          finalPoints[i + 1].latitude,
          finalPoints[i + 1].longitude,
        );
      }
    }

    // Save to local history permanently only if phone actually moved
    if (finalPoints.length >= 2 && computedDist >= 6.0) {
      final completedTrip = TripModel(
        id: id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        title: '${_currentVehicle.displayName} Trip at ${DateFormat('hh:mm a').format(beganTime)}',
        ownerId: authService.uid,
        viewerIds: [],
        startedAt: beganTime,
        endedAt: now,
        distanceMeters: computedDist,
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

  String _getHistoryStorageKey(String uid) => 'saved_history_trips_$uid';

  Future<void> loadHistory() async {
    try {
      final uid = authService.uid;
      if (uid.isEmpty) {
        _historyTrips.clear();
        notifyListeners();
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final userKey = _getHistoryStorageKey(uid);
      String? jsonStr = prefs.getString(userKey);

      // Legacy migration: If user-specific storage is empty, check legacy global storage
      if (jsonStr == null || jsonStr.isEmpty) {
        final legacyJsonStr = prefs.getString('saved_history_trips');
        if (legacyJsonStr != null && legacyJsonStr.isNotEmpty) {
          try {
            final List<dynamic> legacyList = jsonDecode(legacyJsonStr);
            final userLegacyTrips = <TripModel>[];
            for (final item in legacyList) {
              if (item is Map<String, dynamic>) {
                final trip = TripModel.fromJson(item);
                // Claim trips matching current UID, empty ownerId, or demo/guest
                if (trip.ownerId == uid ||
                    trip.ownerId.isEmpty ||
                    trip.ownerId.startsWith('demo_') ||
                    trip.ownerId == 'guest') {
                  userLegacyTrips.add(trip.copyWith(ownerId: uid));
                }
              }
            }
            if (userLegacyTrips.isNotEmpty) {
              jsonStr = jsonEncode(userLegacyTrips.map((t) => t.toJson()).toList());
              await prefs.setString(userKey, jsonStr);
            }
          } catch (e) {
            debugPrint('Legacy history migration notice: $e');
          }
        }
      }

      _historyTrips.clear();

      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List<dynamic> list = jsonDecode(jsonStr);
        final loaded = list
            .whereType<Map<String, dynamic>>()
            .map((item) => TripModel.fromJson(item))
            .where((t) => t.ownerId == uid || t.ownerId.isEmpty)
            .map((t) => t.ownerId.isEmpty ? t.copyWith(ownerId: uid) : t)
            .toList();

        final existingIds = <String>{};
        for (final trip in loaded) {
          if (!existingIds.contains(trip.id)) {
            double dist = trip.distanceMeters;
            if (dist <= 0.0 && trip.points.length >= 2) {
              for (int i = 0; i < trip.points.length - 1; i++) {
                dist += Geolocator.distanceBetween(
                  trip.points[i].latitude,
                  trip.points[i].longitude,
                  trip.points[i + 1].latitude,
                  trip.points[i + 1].longitude,
                );
              }
            }
            _historyTrips.add(trip.copyWith(distanceMeters: dist > 0 ? dist : trip.distanceMeters));
            existingIds.add(trip.id);
          }
        }
      }

      // Check active_trip_points in SharedPreferences for any past days (e.g. 2 Nov) not yet archived
      final activeSavedPoints = prefs.getString('active_trip_points');
      if (activeSavedPoints != null && activeSavedPoints.isNotEmpty) {
        try {
          final List<dynamic> list = jsonDecode(activeSavedPoints);
          final List<TripPoint> unarchived = [];
          for (final item in list) {
            if (item is Map<String, dynamic>) {
              unarchived.add(TripPoint.fromJson(item));
            }
          }
          final now = DateTime.now();
          final todayKey = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
          final Map<String, List<TripPoint>> byDay = {};
          for (final p in unarchived) {
            final d = p.timestamp.toLocal();
            final k = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
            byDay.putIfAbsent(k, () => []).add(p);
          }
          for (final entry in byDay.entries) {
            if (entry.key != todayKey && entry.value.length >= 2) {
              final pts = entry.value;
              double dist = 0.0;
              for (int i = 0; i < pts.length - 1; i++) {
                dist += Geolocator.distanceBetween(
                  pts[i].latitude,
                  pts[i].longitude,
                  pts[i + 1].latitude,
                  pts[i + 1].longitude,
                );
              }
              if (dist >= 5.0) {
                final pastDate = pts.first.timestamp.toLocal();
                final existingIdx = _historyTrips.indexWhere((t) {
                  final td = t.startedAt.toLocal();
                  return td.year == pastDate.year && td.month == pastDate.month && td.day == pastDate.day;
                });
                if (existingIdx == -1) {
                  final recTrip = TripModel(
                    id: 'trip_${pastDate.year}_${pastDate.month}_${pastDate.day}_${pts.first.timestamp.millisecondsSinceEpoch}',
                    title: '${_currentVehicle.displayName} Trip • ${DateFormat('d MMM yyyy').format(pastDate)}',
                    ownerId: uid,
                    viewerIds: const [],
                    startedAt: pts.first.timestamp,
                    endedAt: pts.last.timestamp,
                    distanceMeters: dist,
                    isActive: false,
                    points: pts,
                    vehicleType: _currentVehicle.name,
                  );
                  _historyTrips.insert(0, recTrip);
                } else if (_historyTrips[existingIdx].distanceMeters <= 0.0 || _historyTrips[existingIdx].points.isEmpty) {
                  _historyTrips[existingIdx] = _historyTrips[existingIdx].copyWith(
                    distanceMeters: dist > 0 ? dist : _historyTrips[existingIdx].distanceMeters,
                    points: pts,
                  );
                }
              }
            }
          }
        } catch (_) {}
      }

      // Permanently remove all mock/sample trips
      _historyTrips.removeWhere((t) => t.id.startsWith('sample_'));
      _historyTrips.sort((a, b) => b.startedAt.compareTo(a.startedAt));
      await _saveLocalHistory();
      notifyListeners();

      // Sync cloud trips in background without delaying login or app load
      unawaited(syncFirestoreHistory());
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
          .get()
          .timeout(const Duration(seconds: 6));

      final existingIds = _historyTrips.map((t) => t.id).toSet();
      bool changed = false;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final isActive = data['active'] == true;
        if (isActive) {
          // If the trip is marked active in Firestore, but is NOT our currently running local session (_tripId):
          // It is an unclosed session from earlier today (e.g. before location toggle) or from a past day!
          if (doc.id != _tripId) {
            double dist = (data['distanceMeters'] as num?)?.toDouble() ?? 0.0;
            List<TripPoint> pts = [];
            if (data['points'] is List) {
              pts = (data['points'] as List)
                  .map((p) => TripPoint.fromMap(Map<String, dynamic>.from(p)))
                  .toList();
            }

            final firestoreTrip = TripModel.fromFirestore(doc.id, data).copyWith(
              isActive: false,
              ownerId: uid,
              distanceMeters: dist,
              points: pts,
            );
            if (!existingIds.contains(doc.id)) {
              _historyTrips.add(firestoreTrip);
              existingIds.add(doc.id);
              changed = true;
            } else {
              final idx = _historyTrips.indexWhere((t) => t.id == doc.id);
              if (idx != -1 && _historyTrips[idx].points.isEmpty && pts.isNotEmpty) {
                _historyTrips[idx] = _historyTrips[idx].copyWith(
                  points: pts,
                  distanceMeters: dist > 0 ? dist : _historyTrips[idx].distanceMeters,
                );
                changed = true;
              }
            }
            doc.reference.update({'active': false}).catchError((_) {});

            // If points were not embedded or distance is 0, fetch points subcollection in background
            if (pts.isEmpty || dist <= 0.0) {
              unawaited(ensureTripPointsLoaded(firestoreTrip));
            }
          }
          continue;
        }

        if (!existingIds.contains(doc.id)) {
          final firestoreTrip = TripModel.fromFirestore(doc.id, data);
          if (firestoreTrip.ownerId == uid || firestoreTrip.ownerId.isEmpty) {
            final t = firestoreTrip.copyWith(ownerId: uid);
            _historyTrips.add(t);
            existingIds.add(doc.id);
            changed = true;
            if (t.points.isEmpty || t.distanceMeters <= 0.0) {
              unawaited(ensureTripPointsLoaded(t));
            }
          }
        } else {
          // If already in memory but points were empty or distance was 0, backfill
          final idx = _historyTrips.indexWhere((t) => t.id == doc.id);
          if (idx != -1 && (_historyTrips[idx].points.isEmpty || _historyTrips[idx].distanceMeters <= 0.0)) {
            if (data['points'] is List && (data['points'] as List).isNotEmpty) {
              final pts = (data['points'] as List)
                  .map((p) => TripPoint.fromMap(Map<String, dynamic>.from(p)))
                  .toList();
              if (pts.isNotEmpty) {
                double dist = _historyTrips[idx].distanceMeters;
                if (dist <= 0.0 && pts.length >= 2) {
                  for (int i = 0; i < pts.length - 1; i++) {
                    dist += Geolocator.distanceBetween(
                      pts[i].latitude,
                      pts[i].longitude,
                      pts[i + 1].latitude,
                      pts[i + 1].longitude,
                    );
                  }
                }
                _historyTrips[idx] = _historyTrips[idx].copyWith(
                  points: pts,
                  distanceMeters: dist > 0 ? dist : _historyTrips[idx].distanceMeters,
                );
                changed = true;
              }
            } else {
              unawaited(ensureTripPointsLoaded(_historyTrips[idx]));
            }
          }
        }
      }

      // Remove any contaminated trips that don't belong to this account
      final beforeCount = _historyTrips.length;
      _historyTrips.removeWhere((t) => t.ownerId.isNotEmpty && t.ownerId != uid);
      if (_historyTrips.length != beforeCount) {
        changed = true;
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

  /// Ensures that route points are loaded for a trip, querying Firestore if points are missing locally.
  Future<List<TripPoint>> ensureTripPointsLoaded(TripModel trip) async {
    if (trip.points.isNotEmpty) return trip.points;
    if (trip.id.startsWith('local_')) return const [];

    try {
      final docRef = FirebaseFirestore.instance.collection('trips').doc(trip.id);
      final docSnap = await docRef.get();
      if (docSnap.exists) {
        final data = docSnap.data();
        if (data != null && data['points'] is List && (data['points'] as List).isNotEmpty) {
          final pts = (data['points'] as List)
              .map((p) => TripPoint.fromMap(Map<String, dynamic>.from(p)))
              .toList();
          _updateTripPointsInMemory(trip.id, pts);
          return pts;
        }
      }

      // Query points subcollection (with fallback if orderBy('at') encounters indexing issue)
      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await docRef.collection('points').orderBy('at').limit(3000).get();
      } catch (err) {
        debugPrint('ensureTripPointsLoaded: orderBy error ($err), retrying without order...');
        snap = await docRef.collection('points').limit(3000).get();
      }
      if (snap.docs.isNotEmpty) {
        final pts = snap.docs.map((d) => TripPoint.fromMap(d.data())).toList();
        pts.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        if (pts.isNotEmpty) {
          double dist = trip.distanceMeters;
          if (dist <= 0.0 && pts.length >= 2) {
            for (int i = 0; i < pts.length - 1; i++) {
              dist += Geolocator.distanceBetween(
                pts[i].latitude,
                pts[i].longitude,
                pts[i + 1].latitude,
                pts[i + 1].longitude,
              );
            }
          }
          _updateTripPointsInMemory(trip.id, pts, updatedDistance: dist > 0 ? dist : null);
          // Backfill into document for immediate future access
          docRef.update({
            'points': pts.map((p) => p.toJson()).toList(),
            if (dist > 0) 'distanceMeters': dist,
          }).catchError((_) {});
          return pts;
        }
      }
    } catch (e) {
      debugPrint('ensureTripPointsLoaded error for ${trip.id}: $e');
    }
    return const [];
  }

  void _updateTripPointsInMemory(String tripId, List<TripPoint> pts, {double? updatedDistance}) {
    final idx = _historyTrips.indexWhere((t) => t.id == tripId);
    if (idx != -1) {
      _historyTrips[idx] = _historyTrips[idx].copyWith(
        points: pts,
        distanceMeters: updatedDistance ?? _historyTrips[idx].distanceMeters,
      );
      _saveLocalHistory();
      notifyListeners();
    }
  }

  /// Ensures that route points are fully loaded for all trips on [date]
  Future<void> ensurePointsLoadedForDate(DateTime date) async {
    final trips = getTripsForDate(date);
    bool anyLoaded = false;
    for (final trip in trips) {
      if (trip.points.isEmpty && !trip.id.startsWith('local_')) {
        final pts = await ensureTripPointsLoaded(trip);
        if (pts.isNotEmpty) anyLoaded = true;
      }
    }
    if (anyLoaded) {
      notifyListeners();
    }
  }

  Future<void> _saveLocalHistory() async {
    final uid = authService.uid;
    if (uid.isEmpty) return;
    await _saveLocalHistoryForUser(uid);
  }

  Future<void> _saveLocalHistoryForUser(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Only persist trips belonging to this specific user account
      final userTrips = _historyTrips
          .where((t) => t.ownerId == uid || t.ownerId.isEmpty)
          .map((t) => t.ownerId.isEmpty ? t.copyWith(ownerId: uid) : t)
          .toList();
      final jsonList = userTrips.map((t) => t.toJson()).toList();
      await prefs.setString(_getHistoryStorageKey(uid), jsonEncode(jsonList));
    } catch (e) {
      debugPrint('Error saving local history for $uid: $e');
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
    final uid = authService.uid;
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
      if (uid.isNotEmpty) {
        await prefs.remove(_getHistoryStorageKey(uid));
      }
      await prefs.remove('saved_history_trips');
      await prefs.remove('is_tracking_active');
      await prefs.remove('active_trip_user_id');
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
