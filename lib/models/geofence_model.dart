import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as ll;

class GeofenceModel {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final bool notifyOnEntryExit;
  final bool isActive;
  final DateTime? createdAt;

  GeofenceModel({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    this.notifyOnEntryExit = true,
    this.isActive = true,
    this.createdAt,
  });

  LatLng get center => LatLng(latitude, longitude);
  ll.LatLng get llCenter => ll.LatLng(latitude, longitude);

  GeofenceModel copyWith({
    String? id,
    String? name,
    double? latitude,
    double? longitude,
    double? radiusMeters,
    bool? notifyOnEntryExit,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return GeofenceModel(
      id: id ?? this.id,
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      radiusMeters: radiusMeters ?? this.radiusMeters,
      notifyOnEntryExit: notifyOnEntryExit ?? this.notifyOnEntryExit,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'latitude': latitude,
    'longitude': longitude,
    'radiusMeters': radiusMeters,
    'notifyOnEntryExit': notifyOnEntryExit,
    'isActive': isActive,
    'createdAt': createdAt?.toIso8601String(),
  };

  Map<String, dynamic> toJson() => toMap();

  factory GeofenceModel.fromMap(Map<String, dynamic> map) {
    return GeofenceModel(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? 'Safe Zone',
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0.0,
      radiusMeters: (map['radiusMeters'] as num?)?.toDouble() ?? 500.0,
      notifyOnEntryExit: map['notifyOnEntryExit'] as bool? ?? true,
      isActive: map['isActive'] as bool? ?? true,
      createdAt: map['createdAt'] != null ? DateTime.tryParse(map['createdAt']) : null,
    );
  }

  factory GeofenceModel.fromJson(Map<String, dynamic> json) => GeofenceModel.fromMap(json);
}
