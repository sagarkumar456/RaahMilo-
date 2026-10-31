import 'package:flutter_map/flutter_map.dart';

/// Centralized map tile server configurations for RaahMilo.
/// 100% Free, zero API key required, zero watermarks.
class AppMapTiles {
  /// OpenStreetMap standard tile server (clean, free, zero watermarks, zero API key required)
  static const String streetUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// ArcGIS World Imagery for satellite view (free, zero API key required)
  static const String satelliteUrl =
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';

  /// Android application package for OpenStreetMap compliance
  static const String userAgentPackage = 'com.trackmyphone.gps';

  /// Factory helper that produces a clean TileLayer with zero watermarks & zero API keys.
  /// Note: fallbackUrl is omitted intentionally so Flutter's MapNetworkImageProvider
  /// can fully utilize high-speed RAM image caching for instantaneous panning.
  static TileLayer buildTileLayer({bool isSatellite = false}) {
    if (isSatellite) {
      return TileLayer(
        urlTemplate: satelliteUrl,
        userAgentPackageName: userAgentPackage,
        tileProvider: NetworkTileProvider(
          silenceExceptions: true,
        ),
        maxZoom: 19.0,
        maxNativeZoom: 19,
        minZoom: 3.0,
        keepBuffer: 6,
        panBuffer: 2,
        evictErrorTileStrategy: EvictErrorTileStrategy.dispose,
        tileDisplay: const TileDisplay.fadeIn(duration: Duration(milliseconds: 60)),
        tileUpdateTransformer: TileUpdateTransformers.ignoreTapEvents,
      );
    }
    return TileLayer(
      urlTemplate: streetUrl,
      userAgentPackageName: userAgentPackage,
      tileProvider: NetworkTileProvider(
        silenceExceptions: true,
      ),
      maxZoom: 19.0,
      maxNativeZoom: 19,
      minZoom: 3.0,
      keepBuffer: 6,
      panBuffer: 2,
      evictErrorTileStrategy: EvictErrorTileStrategy.dispose,
      tileDisplay: const TileDisplay.fadeIn(duration: Duration(milliseconds: 60)),
      tileUpdateTransformer: TileUpdateTransformers.ignoreTapEvents,
    );
  }
}
