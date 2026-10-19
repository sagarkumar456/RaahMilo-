import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'vehicle_type.dart';

class TripPoint {
  final double latitude;
  final double longitude;
  final double speed;
  final double accuracy;
  final DateTime timestamp;

  TripPoint({
    required this.latitude,
    required this.longitude,
    required this.speed,
    required this.accuracy,
    required this.timestamp,
  });

  LatLng toLatLng() => LatLng(latitude, longitude);

  Map<String, dynamic> toMap() => {
    'lat': latitude,
    'lng': longitude,
    'speed': speed,
    'accuracy': accuracy,
    'at': Timestamp.fromDate(timestamp),
  };

  Map<String, dynamic> toJson() => {
    'lat': latitude,
    'lng': longitude,
    'speed': speed,
    'accuracy': accuracy,
    'timestamp': timestamp.toIso8601String(),
  };

  factory TripPoint.fromMap(Map<String, dynamic> map) {
    DateTime ts;
    final atVal = map['at'] ?? map['timestamp'];
    if (atVal is Timestamp) {
      ts = atVal.toDate();
    } else if (atVal is String) {
      ts = DateTime.tryParse(atVal) ?? DateTime.now();
    } else if (atVal is int) {
      ts = DateTime.fromMillisecondsSinceEpoch(atVal);
    } else {
      ts = DateTime.now();
    }

    return TripPoint(
      latitude: (map['lat'] as num?)?.toDouble() ?? 0.0,
      longitude: (map['lng'] as num?)?.toDouble() ?? 0.0,
      speed: (map['speed'] as num?)?.toDouble() ?? 0.0,
      accuracy: (map['accuracy'] as num?)?.toDouble() ?? 0.0,
      timestamp: ts,
    );
  }

  factory TripPoint.fromJson(Map<String, dynamic> json) => TripPoint.fromMap(json);
}

class TripModel {
  final String id;
  final String title;
  final String ownerId;
  final List<String> viewerIds;
  final DateTime startedAt;
  final DateTime? endedAt;
  final double distanceMeters;
  final bool isActive;
  final List<TripPoint> points;
  final String vehicleType; // 'car', 'human', 'scooty', 'bike'

  TripModel({
    required this.id,
    required this.title,
    required this.ownerId,
    required this.viewerIds,
    required this.startedAt,
    this.endedAt,
    required this.distanceMeters,
    required this.isActive,
    this.points = const [],
    this.vehicleType = 'car',
  });

  VehicleType get vehicleTypeEnum => VehicleType.fromString(vehicleType);

  String get formattedDistance {
    final km = distanceMeters / 1000.0;
    return '${km.toStringAsFixed(1)} km';
  }

  String get formattedDuration {
    final end = endedAt ?? DateTime.now();
    final diff = end.difference(startedAt);
    if (diff.inHours > 0) {
      return '${diff.inHours} hr ${diff.inMinutes % 60} min';
    }
    return '${diff.inMinutes} min';
  }

  String get formattedDate {
    return DateFormat('dd MMM yyyy • hh:mm a').format(startedAt);
  }

  String get formattedTimeRange {
    final startStr = DateFormat('hh:mm a').format(startedAt);
    final endStr = endedAt != null ? DateFormat('hh:mm a').format(endedAt!) : 'Live';
    return '${DateFormat('dd MMM yyyy').format(startedAt)} • $startStr - $endStr';
  }

  double get avgSpeedKmh {
    final end = endedAt ?? DateTime.now();
    final diffHours = end.difference(startedAt).inSeconds / 3600.0;
    if (diffHours <= 0) return 0.0;
    return (distanceMeters / 1000.0) / diffHours;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'ownerId': ownerId,
    'viewerIds': viewerIds,
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt?.toIso8601String(),
    'distanceMeters': distanceMeters,
    'active': isActive,
    'points': points.map((p) => p.toJson()).toList(),
    'vehicleType': vehicleType,
  };

  factory TripModel.fromJson(Map<String, dynamic> json) {
    final rawPoints = json['points'] as List<dynamic>? ?? [];
    return TripModel(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Trip to Destination',
      ownerId: json['ownerId'] as String? ?? '',
      viewerIds: List<String>.from(json['viewerIds'] ?? []),
      startedAt: json['startedAt'] != null
          ? DateTime.tryParse(json['startedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      endedAt: json['endedAt'] != null
          ? DateTime.tryParse(json['endedAt'].toString())
          : null,
      distanceMeters: (json['distanceMeters'] as num?)?.toDouble() ?? 0.0,
      isActive: json['active'] as bool? ?? (json['isActive'] as bool? ?? false),
      points: rawPoints
          .map((p) => TripPoint.fromJson(p as Map<String, dynamic>))
          .toList(),
      vehicleType: json['vehicleType'] as String? ?? 'car',
    );
  }

  factory TripModel.fromFirestore(String id, Map<String, dynamic> data, [List<TripPoint> points = const []]) {
    DateTime started;
    final sVal = data['startedAt'];
    if (sVal is Timestamp) {
      started = sVal.toDate();
    } else if (sVal is String) {
      started = DateTime.tryParse(sVal) ?? DateTime.now();
    } else {
      started = DateTime.now();
    }

    DateTime? ended;
    final eVal = data['endedAt'];
    if (eVal is Timestamp) {
      ended = eVal.toDate();
    } else if (eVal is String) {
      ended = DateTime.tryParse(eVal);
    }

    return TripModel(
      id: id,
      title: data['title'] as String? ?? 'Trip to Destination',
      ownerId: data['ownerId'] as String? ?? '',
      viewerIds: List<String>.from(data['viewerIds'] ?? []),
      startedAt: started,
      endedAt: ended,
      distanceMeters: (data['distanceMeters'] as num?)?.toDouble() ?? 0.0,
      isActive: data['active'] as bool? ?? false,
      points: points,
      vehicleType: data['vehicleType'] as String? ?? 'car',
    );
  }

  TripModel copyWith({
    String? id,
    String? title,
    String? ownerId,
    List<String>? viewerIds,
    DateTime? startedAt,
    DateTime? endedAt,
    double? distanceMeters,
    bool? isActive,
    List<TripPoint>? points,
    String? vehicleType,
  }) {
    return TripModel(
      id: id ?? this.id,
      title: title ?? this.title,
      ownerId: ownerId ?? this.ownerId,
      viewerIds: viewerIds ?? this.viewerIds,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      isActive: isActive ?? this.isActive,
      points: points ?? this.points,
      vehicleType: vehicleType ?? this.vehicleType,
    );
  }
}
