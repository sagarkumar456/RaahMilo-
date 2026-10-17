import 'package:google_maps_flutter/google_maps_flutter.dart';

class GeofenceModel {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final bool notifyOnEntryExit;
  final bool isActive;

  GeofenceModel({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    this.notifyOnEntryExit = true,
    this.isActive = true,
  });

  LatLng get center => LatLng(latitude, longitude);

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'latitude': latitude,
    'longitude': longitude,
    'radiusMeters': radiusMeters,
    'notifyOnEntryExit': notifyOnEntryExit,
    'isActive': isActive,
  };

  factory GeofenceModel.fromMap(Map<String, dynamic> map) {
    return GeofenceModel(
      id: map['id'] ?? '',
      name: map['name'] ?? 'Safe Zone',
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0.0,
      radiusMeters: (map['radiusMeters'] as num?)?.toDouble() ?? 500.0,
      notifyOnEntryExit: map['notifyOnEntryExit'] ?? true,
      isActive: map['isActive'] ?? true,
    );
  }
}
