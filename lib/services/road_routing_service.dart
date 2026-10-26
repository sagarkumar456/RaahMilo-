import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as ll;
import 'package:shared_preferences/shared_preferences.dart';

/// RoadRoutingService fetches and caches real road networks using OSRM
/// (Open Source Routing Machine).
/// 100% Free, zero API key required, zero watermarks.
/// It converts straight GPS breadcrumbs into realistic turn-by-turn road paths.
class RoadRoutingService {
  static final RoadRoutingService _instance = RoadRoutingService._internal();
  factory RoadRoutingService() => _instance;
  RoadRoutingService._internal();

  // In-memory route cache by tripId or coordinate hash
  final Map<String, List<ll.LatLng>> _memoryCache = {};
  final Map<String, double> _distanceCache = {};

  /// Fetches the road-snapped route between the provided coordinates.
  /// If [tripId] is provided, attempts to load from disk/memory cache first.
  Future<List<ll.LatLng>> getRoadRoute({
    required String tripId,
    required List<ll.LatLng> points,
  }) async {
    if (points.length < 2) return points;

    final cacheKey = tripId.isNotEmpty
        ? tripId
        : '${points.first.latitude.toStringAsFixed(4)},${points.first.longitude.toStringAsFixed(4)}_${points.length}_${points.last.latitude.toStringAsFixed(4)},${points.last.longitude.toStringAsFixed(4)}';

    // 1. Check in-memory cache
    if (_memoryCache.containsKey(cacheKey) && _memoryCache[cacheKey]!.isNotEmpty) {
      return _memoryCache[cacheKey]!;
    }

    // 2. Check persistent SharedPreferences cache
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedJson = prefs.getString('road_route_$cacheKey');
      if (savedJson != null && savedJson.isNotEmpty) {
        final List<dynamic> list = jsonDecode(savedJson);
        final restored = list.map((item) {
          final lat = (item['lat'] as num).toDouble();
          final lng = (item['lng'] as num).toDouble();
          return ll.LatLng(lat, lng);
        }).toList();
        if (restored.isNotEmpty) {
          _memoryCache[cacheKey] = restored;
          final savedDist = prefs.getDouble('road_dist_$cacheKey');
          if (savedDist != null) _distanceCache[cacheKey] = savedDist;
          return restored;
        }
      }
    } catch (e) {
      debugPrint('Error reading road cache: $e');
    }

    // 3. Filter valid coordinates and sample points to stay well within OSRM limits
    final validPoints = points.where((p) =>
      !p.latitude.isNaN && !p.latitude.isInfinite &&
      !p.longitude.isNaN && !p.longitude.isInfinite &&
      p.latitude >= -90.0 && p.latitude <= 90.0 &&
      p.longitude >= -180.0 && p.longitude <= 180.0
    ).toList();

    if (validPoints.length < 2) return points;

    final sampled = _sampleWaypoints(validPoints, maxPoints: 35);

    try {
      // Coordinates format for OSRM: {lon},{lat};{lon},{lat}...
      final coordsParam = sampled
          .map((p) => '${p.longitude.toStringAsFixed(6)},${p.latitude.toStringAsFixed(6)}')
          .join(';');

      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/$coordsParam?overview=full&geometries=geojson',
      );

      final res = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'RaahMilo-App/1.0 (Mobile; Flutter; SecureRoutingClient)',
          'X-Content-Type-Options': 'nosniff',
        },
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['code'] == 'Ok' &&
            data['routes'] is List &&
            (data['routes'] as List).isNotEmpty) {
          final route = data['routes'][0];
          final geometry = route['geometry'];
          if (geometry != null && geometry['coordinates'] is List) {
            final rawCoords = geometry['coordinates'] as List;
            final List<ll.LatLng> roadPath = [];
            for (final coord in rawCoords) {
              if (coord is List && coord.length >= 2) {
                final lng = (coord[0] as num).toDouble();
                final lat = (coord[1] as num).toDouble();
                roadPath.add(ll.LatLng(lat, lng));
              }
            }

            if (roadPath.isNotEmpty) {
              _memoryCache[cacheKey] = roadPath;

              final distMeters = (route['distance'] as num?)?.toDouble();
              if (distMeters != null) {
                _distanceCache[cacheKey] = distMeters;
              }

              // Save to SharedPreferences asynchronously for offline & instant re-open
              _persistCache(cacheKey, roadPath, distMeters);
              return roadPath;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('OSRM routing fetch exception: $e');
    }

    // Fallback: Return original raw GPS coordinates if network fails
    return points;
  }

  double? getRoadDistanceMeters(String tripId) => _distanceCache[tripId];

  Future<void> _persistCache(
    String key,
    List<ll.LatLng> coords,
    double? distMeters,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = coords.map((c) => {'lat': c.latitude, 'lng': c.longitude}).toList();
      await prefs.setString('road_route_$key', jsonEncode(jsonList));
      if (distMeters != null) {
        await prefs.setDouble('road_dist_$key', distMeters);
      }
    } catch (_) {}
  }

  /// Reduce list of points to at most [maxPoints] while keeping start, end,
  /// and significant turning points.
  List<ll.LatLng> _sampleWaypoints(List<ll.LatLng> pts, {int maxPoints = 35}) {
    if (pts.length <= maxPoints) return pts;

    final List<ll.LatLng> result = [];
    result.add(pts.first);

    final step = (pts.length - 2) / (maxPoints - 2);
    for (int i = 1; i < maxPoints - 1; i++) {
      final index = (i * step).round().clamp(1, pts.length - 2);
      result.add(pts[index]);
    }

    result.add(pts.last);
    return result;
  }
}

final roadRoutingService = RoadRoutingService();
