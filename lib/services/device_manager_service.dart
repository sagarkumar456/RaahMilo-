import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_device_model.dart';
import 'alert_sound_service.dart';
import 'auth_service.dart';

class DeviceManagerService extends ChangeNotifier {
  static final DeviceManagerService _instance = DeviceManagerService._internal();
  factory DeviceManagerService() => _instance;

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

  static const MethodChannel _nativeChannel = MethodChannel('com.trackmyphone.gps/alert_sound');
  static const String _keyDeviceId = 'user_device_unique_id';
  static const String _keyDeviceName = 'user_device_custom_name';
  static const String _keyFinderMode = 'user_device_finder_mode';
  static const String _keySelectedDeviceId = 'user_selected_device_id';

  String _deviceId = '';
  String _deviceName = '';
  String _deviceModel = 'Android Device';
  int _batteryLevel = -1;
  bool _isFinderMode = false;
  String? _selectedDeviceId;
  List<UserDeviceModel> _devices = [];

  StreamSubscription<QuerySnapshot>? _devicesSubscription;
  StreamSubscription<DocumentSnapshot>? _myDeviceSubscription;
  DateTime? _lastLocationUploadTime;

  String get deviceId => _deviceId;
  String get deviceName => _deviceName.isNotEmpty ? _deviceName : _deviceModel;
  String get deviceModel => _deviceModel;
  int get batteryLevel => _batteryLevel;
  bool get isFinderMode => _isFinderMode;
  String? get selectedDeviceId => _selectedDeviceId;
  List<UserDeviceModel> get devices => List.unmodifiable(_devices);

  bool get isViewingCurrentDevice =>
      _selectedDeviceId == null || _selectedDeviceId == _deviceId;

  UserDeviceModel? get selectedDevice {
    if (isViewingCurrentDevice) {
      return currentDeviceModel;
    }
    try {
      return _devices.firstWhere((d) => d.id == _selectedDeviceId);
    } catch (_) {
      return null;
    }
  }

  UserDeviceModel? get currentDeviceModel {
    try {
      return _devices.firstWhere((d) => d.id == _deviceId);
    } catch (_) {
      return null;
    }
  }

  DeviceManagerService._internal() {
    _init();
  }

  Future<void> _init() async {
    await _loadLocalConfig();
    _fetchNativeDeviceInfo();
    _setupAuthListener();
  }

  Future<void> _loadLocalConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var id = prefs.getString(_keyDeviceId);
      if (id == null || id.isEmpty) {
        final randomPart = Random().nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
        id = 'dev_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}_$randomPart';
        await prefs.setString(_keyDeviceId, id);
      }
      _deviceId = id;
      _deviceName = prefs.getString(_keyDeviceName) ?? '';
      _isFinderMode = prefs.getBool(_keyFinderMode) ?? false;
      _selectedDeviceId = prefs.getString(_keySelectedDeviceId);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _fetchNativeDeviceInfo() async {
    try {
      final model = await _nativeChannel.invokeMethod<String>('getDeviceModel');
      if (model != null && model.isNotEmpty) {
        _deviceModel = model;
        if (_deviceName.isEmpty) {
          _deviceName = model;
        }
      }
    } catch (_) {}

    try {
      final bat = await _nativeChannel.invokeMethod<int>('getBatteryLevel');
      if (bat != null && bat >= 0) {
        _batteryLevel = bat;
      }
    } catch (_) {}

    notifyListeners();
  }

  void _setupAuthListener() {
    authService.addListener(() {
      _syncForCurrentAccount();
    });
    _syncForCurrentAccount();
  }

  void _syncForCurrentAccount() {
    final uid = authService.uid;
    _devicesSubscription?.cancel();
    _myDeviceSubscription?.cancel();

    if (uid.isEmpty) {
      _devices = [];
      notifyListeners();
      return;
    }

    // 1. Listen to all devices registered under this user account
    try {
      _devicesSubscription = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('devices')
          .snapshots()
          .listen(
        (snapshot) {
          _devices = snapshot.docs
              .map((doc) => UserDeviceModel.fromSnapshot(doc))
              .toList();

          // Sort current device first, then newest active
          _devices.sort((a, b) {
            if (a.id == _deviceId) return -1;
            if (b.id == _deviceId) return 1;
            return b.lastSeen.compareTo(a.lastSeen);
          });

          notifyListeners();
        },
        onError: (_) {},
      );
    } catch (_) {}

    // 2. Listen to this device's document for remote ring alerts
    try {
      if (_deviceId.isNotEmpty) {
        _myDeviceSubscription = FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('devices')
            .doc(_deviceId)
            .snapshots()
            .listen((doc) {
          if (doc.exists) {
            final data = doc.data();
            if (data != null && data['ringAlert'] == true) {
              _triggerLoudAlarmAndReset();
            }
          }
        });
      }
    } catch (_) {}

    // 3. Register or update current device on login
    registerCurrentDevice();
  }

  Future<void> registerCurrentDevice({
    double? latitude,
    double? longitude,
    double? speedKmh,
    double? heading,
    String? address,
    bool? isTrackingActive,
  }) async {
    final uid = authService.uid;
    if (uid.isEmpty || _deviceId.isEmpty) return;

    try {
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('devices')
          .doc(_deviceId);

      final data = <String, dynamic>{
        'id': _deviceId,
        'ownerUid': uid,
        'name': _deviceName.isNotEmpty ? _deviceName : _deviceModel,
        'model': _deviceModel,
        'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'iOS' : 'Android',
        'isOnline': true,
        'batteryLevel': _batteryLevel,
        'lastSeen': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (latitude != null) data['latitude'] = latitude;
      if (longitude != null) data['longitude'] = longitude;
      if (speedKmh != null) data['speedKmh'] = speedKmh;
      if (heading != null) data['heading'] = heading;
      if (address != null && address.isNotEmpty) data['address'] = address;
      if (isTrackingActive != null) data['isTrackingActive'] = isTrackingActive;

      // Ensure createdAt is only set once
      data['createdAt'] = FieldValue.serverTimestamp();

      await docRef.set(data, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Broadcasts GPS coordinates to Firestore under this device's document.
  /// Skips update if finder mode is active so this phone doesn't override anything!
  Future<void> updateCurrentDeviceLocation({
    required double lat,
    required double lng,
    required double speedKmh,
    required double heading,
    required String address,
    required bool isTrackingActive,
  }) async {
    // If finder mode is enabled, do NOT broadcast this phone's location
    if (_isFinderMode) return;

    final uid = authService.uid;
    if (uid.isEmpty || _deviceId.isEmpty) return;

    // Throttle location upload: maximum once every 3.5 seconds
    final now = DateTime.now();
    if (_lastLocationUploadTime != null &&
        now.difference(_lastLocationUploadTime!).inMilliseconds < 3500) {
      return;
    }
    _lastLocationUploadTime = now;

    // Refresh native battery in background occasionally
    _fetchNativeDeviceInfo();

    try {
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('devices')
          .doc(_deviceId);

      await docRef.set({
        'id': _deviceId,
        'ownerUid': uid,
        'name': _deviceName.isNotEmpty ? _deviceName : _deviceModel,
        'model': _deviceModel,
        'latitude': lat,
        'longitude': lng,
        'speedKmh': speedKmh,
        'heading': heading,
        'address': address,
        'batteryLevel': _batteryLevel,
        'isOnline': true,
        'isTrackingActive': isTrackingActive,
        'lastSeen': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> setFinderMode(bool enable) async {
    _isFinderMode = enable;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyFinderMode, enable);
    } catch (_) {}
    notifyListeners();
  }

  Future<void> selectDevice(String? deviceId) async {
    _selectedDeviceId = (deviceId == null || deviceId == _deviceId) ? null : deviceId;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_selectedDeviceId != null) {
        await prefs.setString(_keySelectedDeviceId, _selectedDeviceId!);
      } else {
        await prefs.remove(_keySelectedDeviceId);
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> renameDevice(String targetDeviceId, String newName) async {
    final cleanName = newName.trim();
    if (cleanName.isEmpty) return;

    final uid = authService.uid;
    if (targetDeviceId == _deviceId) {
      _deviceName = cleanName;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyDeviceName, cleanName);
      } catch (_) {}
      notifyListeners();
    }

    if (uid.isNotEmpty) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('devices')
            .doc(targetDeviceId)
            .update({'name': cleanName});
      } catch (_) {}
    }
  }

  Future<void> removeDevice(String targetDeviceId) async {
    final uid = authService.uid;
    if (uid.isEmpty) return;

    if (_selectedDeviceId == targetDeviceId) {
      await selectDevice(null);
    }

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('devices')
          .doc(targetDeviceId)
          .delete();
    } catch (_) {}
  }

  /// Sends a remote siren / ring signal to the specified device
  Future<void> ringRemoteDevice(String targetDeviceId) async {
    final uid = authService.uid;
    if (uid.isEmpty) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('devices')
          .doc(targetDeviceId)
          .update({'ringAlert': true});
    } catch (_) {}
  }

  Future<void> _triggerLoudAlarmAndReset() async {
    // Play loud siren and vibrate
    await AlertSoundService.playAlertSound(type: 'alarm');

    // Reset ringAlert flag in Firestore so it doesn't loop forever
    final uid = authService.uid;
    if (uid.isNotEmpty && _deviceId.isNotEmpty) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('devices')
            .doc(_deviceId)
            .update({'ringAlert': false});
      } catch (_) {}
    }
  }

  /// Opens Google Maps with direct turn-by-turn navigation / pin to the lost phone
  Future<void> openDirections(double lat, double lng, {String label = 'Lost Phone Location'}) async {
    try {
      await _nativeChannel.invokeMethod('openMap', {
        'lat': lat,
        'lng': lng,
        'label': label,
      });
    } catch (_) {}
  }

  /// Shares device location with coordinates & Google Maps link
  Future<void> shareDeviceLocation(UserDeviceModel device) async {
    final mapsUrl = 'https://maps.google.com/?q=${device.latitude},${device.longitude}';
    final text = '🚨 *Find My Phone Alert: ${device.name}*\n'
        '📍 Status: ${device.isOnline ? "Online (Live)" : "Last Seen: " + device.lastSeenFormatted}\n'
        '🏠 Location: ${device.address.isNotEmpty ? device.address : "Unknown"}\n'
        '🌐 Coordinates: ${device.latitude.toStringAsFixed(5)}, ${device.longitude.toStringAsFixed(5)}\n'
        '🔋 Battery: ${device.batteryLevel >= 0 ? "${device.batteryLevel}%" : "N/A"}\n'
        '🗺️ Open in Google Maps: $mapsUrl';

    try {
      await SharePlus.instance.share(
        ShareParams(
          text: text,
          subject: 'Location of ${device.name}',
        ),
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _devicesSubscription?.cancel();
    _myDeviceSubscription?.cancel();
    super.dispose();
  }
}

final deviceManagerService = DeviceManagerService();
