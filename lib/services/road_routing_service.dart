import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:shared_preferences/shared_preferences.dart';

/// RoadRoutingService manages route coordinates for saved trips.
/// In GPS tracking applications, the phone's genuine recorded GPS breadcrumbs
/// represent true ground reality. Overriding them with external car routing algorithms
/// (such as OSRM driving) causes fake detour paths on walking/alley paths where
/// the user never moved.
/// Preserving the authentic GPS path guarantees 100% fidelity and consistency
/// with the live tracking view.
class RoadRoutingService {
  static final RoadRoutingService _instance = RoadRoutingService._internal();
  factory RoadRoutingService() => _instance;
  RoadRoutingService._internal() {
    clearCache();
  }

  final Map<String, List<ll.LatLng>> _memoryCache = {};
  final Map<String, double> _distanceCache = {};

  /// Returns the authentic GPS points recorded by the device.
  Future<List<ll.LatLng>> getRoadRoute({
    required String tripId,
    required List<ll.LatLng> points,
  }) async {
    return points;
  }

  double? getRoadDistanceMeters(String tripId) => _distanceCache[tripId];

  /// Clears any legacy OSRM routes stored in SharedPreferences
  Future<void> clearCache() async {
    _memoryCache.clear();
    _distanceCache.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith('road_route_') || k.startsWith('road_dist_')).toList();
      for (final k in keys) {
        await prefs.remove(k);
      }
    } catch (_) {}
  }
}

final roadRoutingService = RoadRoutingService();

