import 'package:flutter/material.dart';

enum VehicleType {
  car,
  human,
  scooty,
  bike;

  String get id => name;

  String get displayName {
    switch (this) {
      case VehicleType.car:
        return 'Car';
      case VehicleType.human:
        return 'Human';
      case VehicleType.scooty:
        return 'Scooty';
      case VehicleType.bike:
        return 'Bike';
    }
  }

  IconData get icon {
    switch (this) {
      case VehicleType.car:
        return Icons.directions_car_rounded;
      case VehicleType.human:
        return Icons.directions_walk_rounded;
      case VehicleType.scooty:
        return Icons.moped_rounded;
      case VehicleType.bike:
        return Icons.two_wheeler_rounded;
    }
  }

  Color get color {
    switch (this) {
      case VehicleType.car:
        return const Color(0xFF10B981); // Emerald Green
      case VehicleType.human:
        return const Color(0xFF0284C7); // Ocean Blue
      case VehicleType.scooty:
        return const Color(0xFFF59E0B); // Amber / Orange
      case VehicleType.bike:
        return const Color(0xFF8B5CF6); // Purple / Violet
    }
  }

  Color get lightColor {
    switch (this) {
      case VehicleType.car:
        return const Color(0xFFECFDF5);
      case VehicleType.human:
        return const Color(0xFFF0F9FF);
      case VehicleType.scooty:
        return const Color(0xFFFFFBEB);
      case VehicleType.bike:
        return const Color(0xFFF5F3FF);
    }
  }

  String get assetPath {
    switch (this) {
      case VehicleType.car:
        return 'assets/images/3d_car.png';
      case VehicleType.human:
        return 'assets/images/3d_human.png';
      case VehicleType.scooty:
        return 'assets/images/3d_scooty.png';
      case VehicleType.bike:
        return 'assets/images/3d_bike.png';
    }
  }

  static VehicleType fromString(String? val) {
    if (val == null) return VehicleType.car;
    switch (val.toLowerCase().trim()) {
      case 'car':
        return VehicleType.car;
      case 'human':
      case 'walk':
      case 'walking':
      case 'person':
        return VehicleType.human;
      case 'scooty':
      case 'scooter':
      case 'moped':
        return VehicleType.scooty;
      case 'bike':
      case 'motorcycle':
      case 'motorbike':
        return VehicleType.bike;
      default:
        return VehicleType.car;
    }
  }
}
