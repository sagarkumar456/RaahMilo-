import 'package:flutter_map/flutter_map.dart';

/// Centralized map tile server configurations for RaahMilo.
/// Uses ultra-fast CartoDB Voyager CDN as primary layer with OpenStreetMap as automatic fallback.
/// This prevents blank/grey screens caused by carrier-level blocking or OSM rate limits.
class AppMapTiles {
  /// CartoDB Voyager: High-performance Cloudflare CDN tiles, modern Google-Maps style aesthetic
  static const String streetUrl =
      'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png';

  /// OpenStreetMap standard fallback
  static const String osmFallbackUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// ArcGIS World Imagery for satellite view
  static const String satelliteUrl =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';

  /// User Agent matching the Android applicationId
  static const String userAgentPackage = 'com.trackmyphone.gps';

  /// Factory helper that produces a reliable TileLayer with fallback
  static TileLayer buildTileLayer({bool isSatellite = false}) {
    if (isSatellite) {
      return TileLayer(
        urlTemplate: satelliteUrl,
        fallbackUrl: streetUrl,
        userAgentPackageName: userAgentPackage,
        maxZoom: 19.0,
      );
    }
    return TileLayer(
      urlTemplate: streetUrl,
      fallbackUrl: osmFallbackUrl,
      userAgentPackageName: userAgentPackage,
      maxZoom: 20.0,
    );
  }
}
