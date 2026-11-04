import 'package:cloud_firestore/cloud_firestore.dart';

class UserDeviceModel {
  final String id;
  final String ownerUid;
  final String name;
  final String model;
  final String platform;
  final double latitude;
  final double longitude;
  final double speedKmh;
  final double heading;
  final String address;
  final int batteryLevel;
  final bool isOnline;
  final bool isTrackingActive;
  final bool ringAlert;
  final DateTime lastSeen;
  final DateTime createdAt;

  const UserDeviceModel({
    required this.id,
    required this.ownerUid,
    required this.name,
    this.model = 'Android Device',
    this.platform = 'Android',
    this.latitude = 0.0,
    this.longitude = 0.0,
    this.speedKmh = 0.0,
    this.heading = 0.0,
    this.address = '',
    this.batteryLevel = -1,
    this.isOnline = true,
    this.isTrackingActive = true,
    this.ringAlert = false,
    required this.lastSeen,
    required this.createdAt,
  });

  bool get isLostOrInactive {
    final diff = DateTime.now().difference(lastSeen);
    return diff.inMinutes > 15;
  }

  String get lastSeenFormatted {
    final now = DateTime.now();
    final diff = now.difference(lastSeen);

    if (diff.inSeconds < 45) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'ownerUid': ownerUid,
      'name': name,
      'model': model,
      'platform': platform,
      'latitude': latitude,
      'longitude': longitude,
      'speedKmh': speedKmh,
      'heading': heading,
      'address': address,
      'batteryLevel': batteryLevel,
      'isOnline': isOnline,
      'isTrackingActive': isTrackingActive,
      'ringAlert': ringAlert,
      'lastSeen': Timestamp.fromDate(lastSeen),
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  factory UserDeviceModel.fromMap(Map<String, dynamic> map, String docId) {
    DateTime parseTime(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) {
        return DateTime.tryParse(val) ?? DateTime.now();
      }
      if (val is int) {
        return DateTime.fromMillisecondsSinceEpoch(val);
      }
      if (val is DateTime) {
        return val;
      }
      return DateTime.now();
    }

    final lastSeenDate = parseTime(map['lastSeen'] ?? map['updatedAt']);
    final diff = DateTime.now().difference(lastSeenDate);
    // Auto-compute online status based on freshness (< 10 minutes)
    final computedOnline = map['isOnline'] == true && diff.inMinutes < 10;

    return UserDeviceModel(
      id: docId,
      ownerUid: (map['ownerUid'] as String?) ?? '',
      name: (map['name'] as String?)?.isNotEmpty == true
          ? (map['name'] as String)
          : (map['model'] as String?) ?? 'Phone',
      model: (map['model'] as String?) ?? 'Android Device',
      platform: (map['platform'] as String?) ?? 'Android',
      latitude: ((map['latitude'] as num?) ?? 0.0).toDouble(),
      longitude: ((map['longitude'] as num?) ?? 0.0).toDouble(),
      speedKmh: ((map['speedKmh'] as num?) ?? 0.0).toDouble(),
      heading: ((map['heading'] as num?) ?? 0.0).toDouble(),
      address: (map['address'] as String?) ?? '',
      batteryLevel: (map['batteryLevel'] as num?)?.toInt() ?? -1,
      isOnline: computedOnline,
      isTrackingActive: map['isTrackingActive'] != false,
      ringAlert: map['ringAlert'] == true,
      lastSeen: lastSeenDate,
      createdAt: parseTime(map['createdAt']),
    );
  }

  factory UserDeviceModel.fromSnapshot(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    return UserDeviceModel.fromMap(data, doc.id);
  }

  UserDeviceModel copyWith({
    String? name,
    String? model,
    double? latitude,
    double? longitude,
    double? speedKmh,
    double? heading,
    String? address,
    int? batteryLevel,
    bool? isOnline,
    bool? isTrackingActive,
    bool? ringAlert,
    DateTime? lastSeen,
  }) {
    return UserDeviceModel(
      id: id,
      ownerUid: ownerUid,
      name: name ?? this.name,
      model: model ?? this.model,
      platform: platform,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      speedKmh: speedKmh ?? this.speedKmh,
      heading: heading ?? this.heading,
      address: address ?? this.address,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      isOnline: isOnline ?? this.isOnline,
      isTrackingActive: isTrackingActive ?? this.isTrackingActive,
      ringAlert: ringAlert ?? this.ringAlert,
      lastSeen: lastSeen ?? this.lastSeen,
      createdAt: createdAt,
    );
  }
}

