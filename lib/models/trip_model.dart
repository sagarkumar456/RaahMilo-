import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

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

  factory TripPoint.fromMap(Map<String, dynamic> map) {
    return TripPoint(
      latitude: (map['lat'] as num?)?.toDouble() ?? 0.0,
      longitude: (map['lng'] as num?)?.toDouble() ?? 0.0,
      speed: (map['speed'] as num?)?.toDouble() ?? 0.0,
      accuracy: (map['accuracy'] as num?)?.toDouble() ?? 0.0,
      timestamp: (map['at'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
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
  });

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

  factory TripModel.fromFirestore(String id, Map<String, dynamic> data, [List<TripPoint> points = const []]) {
    return TripModel(
      id: id,
      title: data['title'] as String? ?? 'Trip to Destination',
      ownerId: data['ownerId'] as String? ?? '',
      viewerIds: List<String>.from(data['viewerIds'] ?? []),
      startedAt: (data['startedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endedAt: (data['endedAt'] as Timestamp?)?.toDate(),
      distanceMeters: (data['distanceMeters'] as num?)?.toDouble() ?? 0.0,
      isActive: data['active'] as bool? ?? false,
      points: points,
    );
  }
}
