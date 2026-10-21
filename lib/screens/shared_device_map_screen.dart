import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../core/app_colors.dart';
import '../core/map_tiles.dart';
import '../models/shared_device_model.dart';
import '../services/share_service.dart';
import '../widgets/pulse_indicator.dart';
import 'shared_user_history_screen.dart';

class SharedDeviceMapScreen extends StatefulWidget {
  final SharedDeviceModel initialDevice;

  const SharedDeviceMapScreen({super.key, required this.initialDevice});

  @override
  State<SharedDeviceMapScreen> createState() => _SharedDeviceMapScreenState();
}

class _SharedDeviceMapScreenState extends State<SharedDeviceMapScreen> {
  final MapController _mapController = MapController();
  bool _isMapReady = false;
  bool _isSatellite = false;
  late SharedDeviceModel _currentDevice;

  @override
  void initState() {
    super.initState();
    _currentDevice = widget.initialDevice;
  }

  void _safeMoveMap(ll.LatLng center, double zoom) {
    if (!_isMapReady) return;
    try {
      _mapController.move(center, zoom);
    } catch (_) {}
  }

  void _zoomIn() {
    if (!_isMapReady) return;
    try {
      final currentZoom = _mapController.camera.zoom;
      _safeMoveMap(_mapController.camera.center, currentZoom + 1);
    } catch (_) {}
  }

  void _zoomOut() {
    if (!_isMapReady) return;
    try {
      final currentZoom = _mapController.camera.zoom;
      _safeMoveMap(_mapController.camera.center, currentZoom - 1);
    } catch (_) {}
  }

  void _recenter() {
    final target = ll.LatLng(_currentDevice.latitude, _currentDevice.longitude);
    _safeMoveMap(target, 16.5);
  }

  void _toggleMapLayer() {
    setState(() => _isSatellite = !_isSatellite);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SharedDeviceModel?>(
      stream: shareService.streamSingleShare(_currentDevice.id),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          _currentDevice = snapshot.data!;
        }

        final deviceCoord = ll.LatLng(_currentDevice.latitude, _currentDevice.longitude);
        final speed = _currentDevice.speedKmh.toStringAsFixed(0);

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text('${_currentDevice.ownerName}\'s Location'),
            actions: [
              IconButton(
                icon: const Icon(Icons.history_rounded),
                tooltip: 'Location History',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SharedUserHistoryScreen(sharedDevice: _currentDevice),
                    ),
                  );
                },
              ),
              IconButton(
                icon: Icon(_isSatellite ? Icons.map_outlined : Icons.layers_outlined),
                tooltip: _isSatellite ? 'Street Map' : 'Satellite Map',
                onPressed: _toggleMapLayer,
              ),
              IconButton(
                icon: const Icon(Icons.my_location_rounded),
                tooltip: 'Recenter on Person',
                onPressed: _recenter,
              ),
            ],
          ),
          body: Stack(
            children: [
              // OpenStreetMap
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: deviceCoord,
                  initialZoom: 16.5,
                  minZoom: 3.0,
                  maxZoom: 19.0,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                    pinchZoomThreshold: 0.1,
                    pinchMoveThreshold: 8.0,
                    enableMultiFingerGestureRace: true,
                  ),
                  onMapReady: () {
                    if (mounted) setState(() => _isMapReady = true);
                  },
                ),
                children: [
                  AppMapTiles.buildTileLayer(isSatellite: _isSatellite),

                  // Marker for the person
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: deviceCoord,
                        width: 54,
                        height: 54,
                        alignment: Alignment.center,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 3),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.4),
                                    blurRadius: 12,
                                    spreadRadius: 3,
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.person_pin_circle_rounded,
                                  color: Colors.white,
                                  size: 28,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // Zoom controls
              Positioned(
                right: 16,
                top: 20,
                child: Column(
                  children: [
                    FloatingActionButton.small(
                      heroTag: 'shared_zoom_in',
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.navyDark,
                      onPressed: _zoomIn,
                      child: const Icon(Icons.add, size: 20),
                    ),
                    const SizedBox(height: 8),
                    FloatingActionButton.small(
                      heroTag: 'shared_zoom_out',
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.navyDark,
                      onPressed: _zoomOut,
                      child: const Icon(Icons.remove, size: 20),
                    ),
                  ],
                ),
              ),

              // Bottom Live Info Card
              Positioned(
                left: 16,
                right: 16,
                bottom: 24,
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
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
                      // User Info Row
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                            child: Text(
                              _currentDevice.ownerName.isNotEmpty
                                  ? _currentDevice.ownerName[0].toUpperCase()
                                  : 'U',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      _currentDevice.ownerName,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const PulseIndicator(size: 8, color: AppColors.success),
                                    const SizedBox(width: 4),
                                    const Text(
                                      'Live Now',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.success,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _currentDevice.ownerEmail,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.tileBackground,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$speed km/h',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppColors.navyDark,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Complete Address
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.tileBackground,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border, width: 0.8),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.location_on_rounded,
                              color: AppColors.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'CURRENT LOCATION',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.6,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _currentDevice.address,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                      height: 1.35,
                                    ),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${deviceCoord.latitude.toStringAsFixed(4)}°, ${deviceCoord.longitude.toStringAsFixed(4)}°',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textMuted,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Recenter Button
                      ElevatedButton.icon(
                        icon: const Icon(Icons.my_location_rounded, size: 18),
                        label: const Text('Recenter on Person'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          minimumSize: const Size.fromHeight(44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _recenter,
                      ),
                      const SizedBox(height: 8),
                      // View Location History Button
                      OutlinedButton.icon(
                        icon: const Icon(Icons.history_rounded, size: 18, color: AppColors.primary),
                        label: Text('View ${_currentDevice.ownerName}\'s Trip History'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                          side: const BorderSide(color: AppColors.primary, width: 1.2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SharedUserHistoryScreen(sharedDevice: _currentDevice),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
