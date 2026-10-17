import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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
  GoogleMapController? _mapController;
  MapType _currentMapType = MapType.normal;
  static const LatLng _delhiCoord = LatLng(28.6139, 77.2090);

  // Sample realistic route points for Delhi
  final List<LatLng> _sampleDelhiRoute = const [
    LatLng(28.6250, 77.2050),
    LatLng(28.6210, 77.2070),
    LatLng(28.6170, 77.2085),
    LatLng(28.6139, 77.2090),
    LatLng(28.6100, 77.2120),
    LatLng(28.6050, 77.2150),
  ];

  void _zoomIn() {
    _mapController?.animateCamera(CameraUpdate.zoomIn());
  }

  void _zoomOut() {
    _mapController?.animateCamera(CameraUpdate.zoomOut());
  }

  void _recenter() {
    final pos = trackingService.current;
    final target = pos != null ? LatLng(pos.latitude, pos.longitude) : _delhiCoord;
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(target, 15.5));
  }

  void _toggleMapType() {
    setState(() {
      _currentMapType = _currentMapType == MapType.normal ? MapType.hybrid : MapType.normal;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: trackingService,
      builder: (context, _) {
        final pos = trackingService.current;
        final currentCoord = pos != null ? LatLng(pos.latitude, pos.longitude) : _delhiCoord;
        final isActive = trackingService.active;
        final routePoints = trackingService.points.isNotEmpty ? trackingService.points : _sampleDelhiRoute;

        final markers = <Marker>{
          Marker(
            markerId: const MarkerId('start'),
            position: routePoints.first,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
            infoWindow: const InfoWindow(title: 'Start Point'),
          ),
          Marker(
            markerId: const MarkerId('car_device'),
            position: currentCoord,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            infoWindow: const InfoWindow(title: 'Live Vehicle'),
          ),
        };

        final polylines = <Polyline>{
          Polyline(
            polylineId: const PolylineId('live_route'),
            points: routePoints,
            color: AppColors.primary,
            width: 5,
            jointType: JointType.round,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
          ),
        };

        final speedKmh = pos != null ? (pos.speed.clamp(0, 999) * 3.6).toStringAsFixed(0) : '52';

        return Scaffold(
          appBar: AppBar(
            title: const Text('Live Tracking'),
            actions: [
              IconButton(
                icon: const Icon(Icons.layers_outlined),
                onPressed: _toggleMapType,
              ),
              IconButton(
                icon: const Icon(Icons.my_location_rounded),
                onPressed: _recenter,
              ),
            ],
          ),
          body: Stack(
            children: [
              // 1. Google Map or Fallback simulated interactive map
              GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: currentCoord,
                  zoom: 15.0,
                ),
                mapType: _currentMapType,
                myLocationEnabled: false,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                markers: markers,
                polylines: polylines,
                onMapCreated: (ctrl) => _mapController = ctrl,
              ),

              // 2. Right Zoom Controls (+ / -)
              Positioned(
                right: 16,
                top: 100,
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
                bottom: 20,
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
                    padding: const EdgeInsets.all(20),
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
                        const SizedBox(height: 16),
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
                        const SizedBox(height: 18),
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
                            minimumSize: const Size.fromHeight(50),
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
