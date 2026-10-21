import 'package:flutter_map/flutter_map.dart';

/// Centralized map tile server configurations for RaahMilo.
/// 100% Free, zero API key required, zero watermarks.
class AppMapTiles {
  /// OpenStreetMap: Free open-source map with zero API key and zero watermarks
  static const String streetUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// Esri World Street Map: Clean fallback layer, zero API key required
  static const String streetFallbackUrl =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}';

  /// ArcGIS World Imagery for satellite view
  static const String satelliteUrl =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';

  /// User Agent matching the Android applicationId
  static const String userAgentPackage = 'com.trackmyphone.gps';

  /// Factory helper that produces a clean TileLayer with zero watermarks & zero API keys
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
      fallbackUrl: streetFallbackUrl,
      userAgentPackageName: userAgentPackage,
      maxZoom: 19.0,
    );
  }
}
