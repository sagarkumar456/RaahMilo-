import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_notification.dart';
import 'api_service.dart';
import 'auth_service.dart';
import 'geocoding_service.dart';
import 'notification_service.dart';
import 'tracking_service.dart';

class AntiTheftEvent {
  final String id;
  final String title;
  final String description;
  final DateTime timestamp;
  final String type; // 'ARM', 'DISARM', 'ALARM', 'ENGINE'
  final bool isAlert;

  AntiTheftEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.timestamp,
    required this.type,
    this.isAlert = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'timestamp': timestamp.toIso8601String(),
        'type': type,
        'isAlert': isAlert,
      };

  factory AntiTheftEvent.fromJson(Map<String, dynamic> json) => AntiTheftEvent(
        id: json['id'] ?? '',
        title: json['title'] ?? '',
        description: json['description'] ?? '',
        timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
        type: json['type'] ?? 'ARM',
        isAlert: json['isAlert'] ?? false,
      );
}

class AntiTheftService extends ChangeNotifier {
  static final AntiTheftService _instance = AntiTheftService._internal();
  factory AntiTheftService() => _instance;

  AntiTheftService._internal() {
    _loadState();
  }

  bool _isArmed = false;
  bool get isArmed => _isArmed;

  bool _isAlarmActive = false;
  bool get isAlarmActive => _isAlarmActive;

  bool _isEngineCutoff = false;
  bool get isEngineCutoff => _isEngineCutoff;

  double? _parkedLat;
  double? get parkedLat => _parkedLat;

  double? _parkedLng;
  double? get parkedLng => _parkedLng;

  String _parkedAddress = 'Unknown location';
  String get parkedAddress => _parkedAddress;

  DateTime? _armedAt;
  DateTime? get armedAt => _armedAt;

  String _sensitivity = 'Medium'; // High (8m), Medium (15m), Low (30m)
  String get sensitivity => _sensitivity;

  bool _loudSiren = true;
  bool get loudSiren => _loudSiren;

  bool _autoArmOnParking = false;
  bool get autoArmOnParking => _autoArmOnParking;

  Timer? _sirenTimer;
  StreamSubscription<Position>? _positionSub;

  final List<AntiTheftEvent> _events = [];
  List<AntiTheftEvent> get events => List.unmodifiable(_events);

  double get movementThresholdMeters {
    switch (_sensitivity) {
      case 'High':
        return 8.0;
      case 'Low':
        return 30.0;
      case 'Medium':
      default:
        return 15.0;
    }
  }

  Future<void> _loadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isArmed = prefs.getBool('antitheft_armed') ?? false;
      _isEngineCutoff = prefs.getBool('antitheft_engine_cutoff') ?? false;
      _sensitivity = prefs.getString('antitheft_sensitivity') ?? 'Medium';
      _loudSiren = prefs.getBool('antitheft_loud_siren') ?? true;
      _autoArmOnParking = prefs.getBool('antitheft_auto_arm') ?? false;

      final lat = prefs.getDouble('antitheft_parked_lat');
      final lng = prefs.getDouble('antitheft_parked_lng');
      if (lat != null && lng != null) {
        _parkedLat = lat;
        _parkedLng = lng;
        _parkedAddress = prefs.getString('antitheft_parked_addr') ?? 'Parked Location';
      }

      final armedTimeStr = prefs.getString('antitheft_armed_at');
      if (armedTimeStr != null) {
        _armedAt = DateTime.tryParse(armedTimeStr);
      }

      if (_isArmed) {
        _startLocationGuard();
      }
      notifyListeners();
    } catch (_) {}
  }

  void _addEvent({
    required String title,
    required String description,
    required String type,
    bool isAlert = false,
  }) {
    final event = AntiTheftEvent(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      description: description,
      timestamp: DateTime.now(),
      type: type,
      isAlert: isAlert,
    );
    _events.insert(0, event);
    if (_events.length > 30) {
      _events.removeLast();
    }
    notifyListeners();
  }

  /// Arm Vehicle Security
  Future<void> armVehicle({double? forcedLat, double? forcedLng}) async {
    try {
      if (forcedLat != null && forcedLng != null) {
        _parkedLat = forcedLat;
        _parkedLng = forcedLng;
      } else if (trackingService.current != null) {
        _parkedLat = trackingService.current!.latitude;
        _parkedLng = trackingService.current!.longitude;
      } else {
        try {
          final lastKnown = await Geolocator.getLastKnownPosition();
          if (lastKnown != null) {
            _parkedLat = lastKnown.latitude;
            _parkedLng = lastKnown.longitude;
          } else {
            final fresh = await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.high,
                timeLimit: Duration(seconds: 4),
              ),
            );
            _parkedLat = fresh.latitude;
            _parkedLng = fresh.longitude;
          }
        } catch (_) {
          _parkedLat ??= 28.6139;
          _parkedLng ??= 77.2090;
        }
      }

      _isArmed = true;
      _armedAt = DateTime.now();

      // Resolve address
      if (_parkedLat != null && _parkedLng != null) {
        geocodingService.getAddress(_parkedLat!, _parkedLng!).then((addr) {
          _parkedAddress = addr;
          notifyListeners();
        });
      }

      // Persist
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('antitheft_armed', true);
      if (_parkedLat != null) await prefs.setDouble('antitheft_parked_lat', _parkedLat!);
      if (_parkedLng != null) await prefs.setDouble('antitheft_parked_lng', _parkedLng!);
      await prefs.setString('antitheft_armed_at', _armedAt!.toIso8601String());

      // 1. Call API
      final uid = authService.uid.isNotEmpty ? authService.uid : 'device_01';
      await apiService.armVehicle(
        vehicleId: uid,
        lat: _parkedLat ?? 0.0,
        lng: _parkedLng ?? 0.0,
      );

      // 2. Notification
      NotificationService().addNotification(
        title: 'Vehicle Armed & Protected',
        subtitle: 'Anti-Theft active at ${_parkedAddress.isNotEmpty ? _parkedAddress : "Parked position"}',
        type: NotificationType.antiTheftArmed,
      );

      _addEvent(
        title: 'Anti-Theft Armed',
        description: 'Guard active with $sensitivity sensitivity threshold (${movementThresholdMeters.toInt()}m)',
        type: 'ARM',
      );

      HapticFeedback.mediumImpact();
      _startLocationGuard();
      notifyListeners();
    } catch (e) {
      _isArmed = true;
      _armedAt = DateTime.now();
      notifyListeners();
    }
  }

  /// Disarm Vehicle Security
  Future<void> disarmVehicle() async {
    _isArmed = false;
    _armedAt = null;
    silenceAlarm();
    _stopLocationGuard();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('antitheft_armed', false);
    await prefs.remove('antitheft_armed_at');

    // Call API
    final uid = authService.uid.isNotEmpty ? authService.uid : 'device_01';
    await apiService.disarmVehicle(vehicleId: uid);

    NotificationService().addNotification(
      title: 'Vehicle Disarmed',
      subtitle: 'Anti-Theft protection has been deactivated',
      type: NotificationType.antiTheftDisarmed,
    );

    _addEvent(
      title: 'Anti-Theft Disarmed',
      description: 'Vehicle security turned off by authorized user',
      type: 'DISARM',
    );

    HapticFeedback.lightImpact();
    notifyListeners();
  }

  /// Trigger Anti-Theft Siren & Alarm
  Future<void> triggerTheftAlarm({required String reason, double? lat, double? lng}) async {
    if (_isAlarmActive) return;
    _isAlarmActive = true;

    final curLat = lat ?? _parkedLat ?? 28.6139;
    final curLng = lng ?? _parkedLng ?? 77.2090;

    _addEvent(
      title: '🚨 THEFT ALARM TRIGGERED',
      description: '$reason at coordinate (${curLat.toStringAsFixed(4)}, ${curLng.toStringAsFixed(4)})',
      type: 'ALARM',
      isAlert: true,
    );

    // Call Alarm API
    final uid = authService.uid.isNotEmpty ? authService.uid : 'device_01';
    await apiService.triggerTheftAlarm(
      vehicleId: uid,
      reason: reason,
      lat: curLat,
      lng: curLng,
    );

    // Dispatch automatic alert to skdas1641999@gmail.com
    await apiService.sendSupportIssueAlert(
      userEmail: authService.email.isNotEmpty ? authService.email : 'user@raahmilo.com',
      userUid: uid,
      issueDescription: 'CRITICAL SECURITY ALERT: Theft Alarm triggered! $reason at lat: $curLat, lng: $curLng',
      priority: 'CRITICAL',
      telemetry: {
        'alarmReason': reason,
        'latitude': curLat,
        'longitude': curLng,
        'isArmed': _isArmed,
        'engineCutoff': _isEngineCutoff,
        'time': DateTime.now().toIso8601String(),
      },
    );

    // Add high priority notification
    NotificationService().addNotification(
      title: '🚨 SECURITY ALARM: Vehicle Moved!',
      subtitle: '$reason! Tap to view live location & sound siren.',
      type: NotificationType.theftAlarmTriggered,
    );

    _startSirenPulsing();
    notifyListeners();
  }

  /// Silence Alarm
  Future<void> silenceAlarm() async {
    _isAlarmActive = false;
    _sirenTimer?.cancel();
    _sirenTimer = null;

    final uid = authService.uid.isNotEmpty ? authService.uid : 'device_01';
    await apiService.silenceTheftAlarm(vehicleId: uid);

    _addEvent(
      title: 'Alarm Silenced',
      description: 'Theft siren deactivated by user command',
      type: 'ALARM',
    );

    notifyListeners();
  }

  /// Toggle Engine Cutoff / Immobilizer
  Future<void> toggleEngineCutoff(bool cutoff) async {
    _isEngineCutoff = cutoff;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('antitheft_engine_cutoff', cutoff);

    final uid = authService.uid.isNotEmpty ? authService.uid : 'device_01';
    await apiService.setEngineCutoff(vehicleId: uid, cutoff: cutoff);

    _addEvent(
      title: cutoff ? '🔒 Engine Immobilized' : '🔓 Engine Enabled',
      description: cutoff
          ? 'Remote fuel/ignition cut-off engaged'
          : 'Normal vehicle ignition restored',
      type: 'ENGINE',
      isAlert: cutoff,
    );

    HapticFeedback.heavyImpact();
    notifyListeners();
  }

  void setSensitivity(String level) {
    if (_sensitivity == level) return;
    _sensitivity = level;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('antitheft_sensitivity', level);
    });
    notifyListeners();
  }

  void setLoudSiren(bool enabled) {
    _loudSiren = enabled;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool('antitheft_loud_siren', enabled);
    });
    notifyListeners();
  }

  void setAutoArmOnParking(bool enabled) {
    _autoArmOnParking = enabled;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool('antitheft_auto_arm', enabled);
    });
    notifyListeners();
  }

  void _startSirenPulsing() {
    _sirenTimer?.cancel();
    if (!_loudSiren) return;

    // Play immediate audible alert sound and haptics
    SystemSound.play(SystemSoundType.alert);
    HapticFeedback.heavyImpact();

    _sirenTimer = Timer.periodic(const Duration(milliseconds: 450), (timer) {
      if (!_isAlarmActive) {
        timer.cancel();
        return;
      }
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.heavyImpact();
    });
  }

  void _startLocationGuard() {
    _positionSub?.cancel();
    try {
      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 1, // Sensitive to real-world movement
        ),
      ).listen((pos) {
        checkPositionForTheft(pos);
      });
    } catch (_) {}
  }

  void _stopLocationGuard() {
    _positionSub?.cancel();
    _positionSub = null;
  }

  /// Instant motion simulation for testing alarm & siren
  Future<void> simulateTheftMovement() async {
    if (!_isArmed) {
      await armVehicle();
    }
    // Simulate displacement by 38 meters
    final testLat = (_parkedLat ?? 28.6139) + 0.00035;
    final testLng = (_parkedLng ?? 77.2090) + 0.00035;
    await triggerTheftAlarm(
      reason: 'TEST MOTION: Vehicle displacement 38m detected outside safety perimeter',
      lat: testLat,
      lng: testLng,
    );
  }

  /// Check if displacement exceeds security limit
  void checkPositionForTheft(Position pos) {
    if (!_isArmed || _parkedLat == null || _parkedLng == null) return;

    final dist = Geolocator.distanceBetween(
      _parkedLat!,
      _parkedLng!,
      pos.latitude,
      pos.longitude,
    );

    if (dist > movementThresholdMeters || (pos.speed * 3.6 > 4.0)) {
      triggerTheftAlarm(
        reason: 'Unauthorized displacement: ${dist.toStringAsFixed(1)}m from parked spot',
        lat: pos.latitude,
        lng: pos.longitude,
      );
    }
  }

  @override
  void dispose() {
    _sirenTimer?.cancel();
    _positionSub?.cancel();
    super.dispose();
  }
}

final antiTheftService = AntiTheftService();
