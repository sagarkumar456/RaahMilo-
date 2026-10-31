import 'package:flutter_map/flutter_map.dart';

/// Centralized map tile server configurations for RaahMilo.
/// 100% Free, zero API key required, zero watermarks.
class AppMapTiles {
  /// CartoDB Voyager: Ultra-fast CDN edge-cached tiles (100% free, zero watermarks, sub-20ms response)
  static const String streetUrl =
      'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png';

  /// OpenStreetMap standard fallback
  static const String streetFallbackUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

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
        fallbackUrl: streetFallbackUrl,
        userAgentPackageName: userAgentPackage,
        tileProvider: NetworkTileProvider(silenceExceptions: true),
        maxZoom: 19.0,
        maxNativeZoom: 19,
        minZoom: 3.0,
        keepBuffer: 8,
        panBuffer: 2,
        evictErrorTileStrategy: EvictErrorTileStrategy.dispose,
        tileDisplay: const TileDisplay.fadeIn(duration: Duration(milliseconds: 50)),
        tileUpdateTransformer: TileUpdateTransformers.ignoreTapEvents,
      );
    }
    return TileLayer(
      urlTemplate: streetUrl,
      fallbackUrl: streetFallbackUrl,
      subdomains: const ['a', 'b', 'c', 'd'],
      userAgentPackageName: userAgentPackage,
      tileProvider: NetworkTileProvider(silenceExceptions: true),
      maxZoom: 19.0,
      maxNativeZoom: 19,
      minZoom: 3.0,
      keepBuffer: 8,
      panBuffer: 2,
      evictErrorTileStrategy: EvictErrorTileStrategy.dispose,
      tileDisplay: const TileDisplay.fadeIn(duration: Duration(milliseconds: 50)),
      tileUpdateTransformer: TileUpdateTransformers.ignoreTapEvents,
    );
  }
}
