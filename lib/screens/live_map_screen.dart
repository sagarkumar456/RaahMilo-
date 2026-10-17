import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../core/app_colors.dart';
import '../services/tracking_service.dart';
import '../widgets/pulse_indicator.dart';
import 'tracking_details_sheet.dart';

class LiveMapScreen extends StatefulWidget {
  const LiveMapScreen({super.key});

  @override
  State<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends State<LiveMapScreen> {
  final MapController _mapController = MapController();
  bool _isSatellite = false;

  static const ll.LatLng _defaultCoord = ll.LatLng(28.6139, 77.2090);

  // Sample realistic route points for fallback preview
  final List<ll.LatLng> _sampleRoute = const [
    ll.LatLng(28.6250, 77.2050),
    ll.LatLng(28.6210, 77.2070),
    ll.LatLng(28.6170, 77.2085),
    ll.LatLng(28.6139, 77.2090),
    ll.LatLng(28.6100, 77.2120),
    ll.LatLng(28.6050, 77.2150),
  ];

  void _zoomIn() {
    final currentZoom = _mapController.camera.zoom;
    _mapController.move(_mapController.camera.center, currentZoom + 1);
  }

  void _zoomOut() {
    final currentZoom = _mapController.camera.zoom;
    _mapController.move(_mapController.camera.center, currentZoom - 1);
  }

  void _recenter() {
    final pos = trackingService.current;
    final target = pos != null ? ll.LatLng(pos.latitude, pos.longitude) : _defaultCoord;
    _mapController.move(target, 16.0);
  }

  void _toggleMapLayer() {
    setState(() => _isSatellite = !_isSatellite);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: trackingService,
      builder: (context, _) {
        final pos = trackingService.current;
        final currentCoord = pos != null ? ll.LatLng(pos.latitude, pos.longitude) : _defaultCoord;
        final isActive = trackingService.active;

        final routePoints = trackingService.points.isNotEmpty
            ? trackingService.points.map((p) => ll.LatLng(p.latitude, p.longitude)).toList()
            : _sampleRoute;

        final startPoint = routePoints.first;
        final speedKmh = pos != null ? (pos.speed.clamp(0, 999) * 3.6).toStringAsFixed(0) : '52';

        final tileUrl = _isSatellite
            ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
            : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

        return Scaffold(
          appBar: AppBar(
            title: const Text('Live Tracking'),
            actions: [
              IconButton(
                icon: Icon(_isSatellite ? Icons.map_outlined : Icons.layers_outlined),
                tooltip: _isSatellite ? 'Street Map' : 'Satellite Map',
                onPressed: _toggleMapLayer,
              ),
              IconButton(
                icon: const Icon(Icons.my_location_rounded),
                tooltip: 'Recenter on Vehicle',
                onPressed: _recenter,
              ),
            ],
          ),
          body: Stack(
            children: [
              // 1. OpenStreetMap Layer (100% Free, Zero API Key required, Real Streets & Buildings)
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: currentCoord,
                  initialZoom: 15.5,
                  minZoom: 3.0,
                  maxZoom: 19.0,
                ),
                children: [
                  TileLayer(
                    urlTemplate: tileUrl,
                    userAgentPackageName: 'com.trackmyphone.gps',
                  ),

                  // Route Polyline
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: routePoints,
                        strokeWidth: 5.0,
                        color: AppColors.primary,
                      ),
                    ],
                  ),

                  // Markers Layer: Start Point + Moving Vehicle
                  MarkerLayer(
                    markers: [
                      // Start Marker (Blue Pin)
                      Marker(
                        point: startPoint,
                        width: 40,
                        height: 40,
                        alignment: Alignment.topCenter,
                        child: const Icon(
                          Icons.location_on_rounded,
                          color: Color(0xFF0052CC),
                          size: 38,
                        ),
                      ),
                      // Vehicle / Current Position Marker (Red Car Badge)
                      Marker(
                        point: currentCoord,
                        width: 50,
                        height: 50,
                        alignment: Alignment.center,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.danger,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.danger.withValues(alpha: 0.4),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.directions_car_filled_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // 2. Right Zoom Controls (+ / -)
              Positioned(
                right: 16,
                top: 20,
                child: Column(
                  children: [
                    _floatingCircleButton(icon: Icons.add, onTap: _zoomIn),
                    const SizedBox(height: 8),
                    _floatingCircleButton(icon: Icons.remove, onTap: _zoomOut),
                  ],
                ),
              ),

              // 3. Floating Bottom Card matching Screen 7
              Positioned(
                bottom: 12,
                left: 16,
                right: 16,
                child: GestureDetector(
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                      ),
                      builder: (_) => TrackingDetailsSheet(position: pos),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Live Location row with speed pill
                        Row(
                          children: [
                            const PulseIndicator(size: 9, color: AppColors.success),
                            const SizedBox(width: 8),
                            const Text(
                              'Live Location',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.tileBackground,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$speedKmh km/h',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.navyDark,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Coordinates & Last Update
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Latitude',
                                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  pos != null ? pos.latitude.toStringAsFixed(4) : '28.6139',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Longitude',
                                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  pos != null ? pos.longitude.toStringAsFixed(4) : '77.2090',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'Last Update',
                                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Just now',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        // Big Red Stop Tracking Button
                        ElevatedButton(
                          onPressed: () async {
                            try {
                              if (isActive) {
                                await trackingService.stop();
                              } else {
                                await trackingService.start();
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('$e')),
                                );
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isActive ? AppColors.danger : AppColors.primary,
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                isActive ? Icons.stop_circle_rounded : Icons.play_arrow_rounded,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isActive ? 'Stop Tracking' : 'Start Tracking',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _floatingCircleButton({required IconData icon, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Icon(icon, color: AppColors.navyDark, size: 22),
      ),
    );
  }
}
