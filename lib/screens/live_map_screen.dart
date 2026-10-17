import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../core/app_colors.dart';
import '../services/geocoding_service.dart';
import '../services/tracking_service.dart';
import '../utils/path_arrows.dart';
import '../widgets/pulse_indicator.dart';
import 'location_disabled_screen.dart';
import 'tracking_details_sheet.dart';

class LiveMapScreen extends StatefulWidget {
  const LiveMapScreen({super.key});

  @override
  State<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends State<LiveMapScreen> {
  final MapController _mapController = MapController();
  bool _isSatellite = false;
  bool _isLocationEnabled = true;
  bool _isSheetCollapsed = false;
  StreamSubscription<ServiceStatus>? _serviceStatusSub;

  static const ll.LatLng _defaultCoord = ll.LatLng(20.5937, 78.9629); // India center fallback until GPS is acquired

  @override
  void initState() {
    super.initState();
    _checkLocationServiceStatus();
    _initDeviceLocation();
  }

  @override
  void dispose() {
    _serviceStatusSub?.cancel();
    super.dispose();
  }

  void _checkLocationServiceStatus() {
    Geolocator.isLocationServiceEnabled().then((enabled) {
      if (mounted) setState(() => _isLocationEnabled = enabled);
    });
    _serviceStatusSub = Geolocator.getServiceStatusStream().listen((status) {
      if (mounted) {
        setState(() => _isLocationEnabled = status == ServiceStatus.enabled);
        if (status == ServiceStatus.enabled) {
          _initDeviceLocation();
        }
      }
    });
  }

  Future<void> _initDeviceLocation() async {
    final pos = trackingService.current;
    if (pos != null) {
      geocodingService.updateFromPosition(pos.latitude, pos.longitude);
      _mapController.move(ll.LatLng(pos.latitude, pos.longitude), 16.0);
    } else {
      final p = await trackingService.initCurrentLocation();
      if (p != null && mounted) {
        geocodingService.updateFromPosition(p.latitude, p.longitude);
        _mapController.move(ll.LatLng(p.latitude, p.longitude), 16.0);
      }
    }
  }

  void _zoomIn() {
    final currentZoom = _mapController.camera.zoom;
    _mapController.move(_mapController.camera.center, currentZoom + 1);
  }

  void _zoomOut() {
    final currentZoom = _mapController.camera.zoom;
    _mapController.move(_mapController.camera.center, currentZoom - 1);
  }

  Future<void> _recenter() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const LocationDisabledScreen(),
            fullscreenDialog: true,
          ),
        );
      }
      return;
    }
    var pos = trackingService.current;
    if (pos == null) {
      pos = await trackingService.initCurrentLocation();
    }
    if (pos != null) {
      _mapController.move(ll.LatLng(pos.latitude, pos.longitude), 16.5);
    }
  }

  void _toggleMapLayer() {
    setState(() => _isSatellite = !_isSatellite);
  }

  Future<void> _toggleTracking(bool isActive) async {
    try {
      if (isActive) {
        await trackingService.stop();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.stop_circle_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('Live tracking stopped'),
                ],
              ),
              backgroundColor: AppColors.danger,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        final isEnabled = await Geolocator.isLocationServiceEnabled();
        if (!isEnabled) {
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const LocationDisabledScreen(),
                fullscreenDialog: true,
              ),
            );
          }
          return;
        }
        await trackingService.start();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('Live tracking started'),
                ],
              ),
              backgroundColor: AppColors.success,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        final isEnabled = await Geolocator.isLocationServiceEnabled();
        if (!isEnabled) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const LocationDisabledScreen(),
              fullscreenDialog: true,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([trackingService, geocodingService]),
      builder: (context, _) {
        final pos = trackingService.current;
        final currentCoord = pos != null ? ll.LatLng(pos.latitude, pos.longitude) : _defaultCoord;
        final isActive = trackingService.active;

        final hasRoute = trackingService.points.length >= 2;
        final routePoints = trackingService.points
            .map((p) => ll.LatLng(p.latitude, p.longitude))
            .toList();

        final speedKmh = (pos != null && isActive)
            ? (pos.speed.clamp(0, 999) * 3.6).toStringAsFixed(0)
            : '0';

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
                tooltip: 'Recenter on My Location',
                onPressed: _recenter,
              ),
            ],
          ),
          body: Stack(
            children: [
              // 1. OpenStreetMap Layer
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: currentCoord,
                  initialZoom: pos != null ? 16.0 : 5.0,
                  minZoom: 3.0,
                  maxZoom: 19.0,
                ),
                children: [
                  TileLayer(
                    urlTemplate: tileUrl,
                    userAgentPackageName: 'com.trackmyphone.gps',
                  ),

                  // Route Polyline (ONLY if user has actually moved/recorded points)
                  if (hasRoute)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: routePoints,
                          strokeWidth: 5.0,
                          color: AppColors.primary,
                        ),
                      ],
                    ),

                  // Directional Arrow Badges along the path
                  if (hasRoute)
                    MarkerLayer(
                      markers: buildDirectionalArrowMarkers(routePoints),
                    ),

                  // Markers Layer: Start Point + Moving Vehicle
                  MarkerLayer(
                    markers: [
                      // Start Marker (Green Pin) - only if points exist
                      if (trackingService.points.isNotEmpty)
                        Marker(
                          point: routePoints.first,
                          width: 40,
                          height: 40,
                          alignment: Alignment.topCenter,
                          child: const Icon(
                            Icons.location_on_rounded,
                            color: AppColors.primary,
                            size: 38,
                          ),
                        ),
                      // Vehicle / Current Position Marker
                      if (pos != null)
                        Marker(
                          point: currentCoord,
                          width: 50,
                          height: 50,
                          alignment: Alignment.center,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withValues(alpha: 0.4),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.my_location_rounded,
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

              // Location Off Top Banner
              if (!_isLocationEnabled)
                Positioned(
                  top: 14,
                  left: 16,
                  right: 70, // Leave room for zoom buttons on right
                  child: GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LocationDisabledScreen(),
                          fullscreenDialog: true,
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFE53935), Color(0xFFFF5252)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFE53935).withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.location_off_rounded, color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Location is turned off • Tap to Enable',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 12),
                        ],
                      ),
                    ),
                  ),
                ),

              // 3. Floating Bottom Card (Collapsible / Swipeable for full map visibility)
              Positioned(
                bottom: 12,
                left: 16,
                right: 16,
                child: GestureDetector(
                  onVerticalDragEnd: (details) {
                    if (details.primaryVelocity != null) {
                      if (details.primaryVelocity! > 60) {
                        // Swiped Down -> Minimize/Collapse
                        setState(() => _isSheetCollapsed = true);
                      } else if (details.primaryVelocity! < -60) {
                        // Swiped Up -> Expand
                        setState(() => _isSheetCollapsed = false);
                      }
                    }
                  },
                  onHorizontalDragEnd: (details) {
                    if (details.primaryVelocity != null && details.primaryVelocity!.abs() > 60) {
                      // Swiped Side (Left or Right) -> Toggle
                      setState(() => _isSheetCollapsed = !_isSheetCollapsed);
                    }
                  },
                  child: AnimatedCrossFade(
                    duration: const Duration(milliseconds: 250),
                    firstCurve: Curves.easeInOutCubic,
                    secondCurve: Curves.easeInOutCubic,
                    crossFadeState: _isSheetCollapsed
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    firstChild: _buildExpandedCard(
                      isActive: isActive,
                      speedKmh: speedKmh,
                      pos: pos,
                    ),
                    secondChild: _buildCollapsedCard(
                      isActive: isActive,
                      speedKmh: speedKmh,
                      pos: pos,
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

  Widget _buildCollapsedCard({
    required bool isActive,
    required String speedKmh,
    required Position? pos,
  }) {
    return GestureDetector(
      onTap: () => setState(() => _isSheetCollapsed = false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            PulseIndicator(size: 8, color: isActive ? AppColors.success : AppColors.textMuted),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.tileBackground,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$speedKmh km/h',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.navyDark,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                geocodingService.fullAddress.isNotEmpty
                    ? geocodingService.fullAddress
                    : (geocodingService.currentTitle != 'Locating address...'
                        ? geocodingService.currentTitle
                        : (isActive ? 'Tracking Active' : 'Live Location')),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            // Compact Start / Stop Tracking Pill
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _toggleTracking(isActive),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isActive ? AppColors.danger : AppColors.primary,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isActive ? Icons.stop_rounded : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isActive ? 'Stop' : 'Start',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up_rounded, color: AppColors.navyDark, size: 26),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: 'Expand Live Details',
              onPressed: () => setState(() => _isSheetCollapsed = false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedCard({
    required bool isActive,
    required String speedKmh,
    required Position? pos,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle pill at top
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Live Location row with speed pill + minimize button
          Row(
            children: [
              PulseIndicator(size: 9, color: isActive ? AppColors.success : AppColors.textMuted),
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
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textSecondary, size: 26),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: 'Minimize to view map (or swipe down/side)',
                onPressed: () => setState(() => _isSheetCollapsed = true),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Real-time Address Card (Tap opens full TrackingDetailsSheet)
          GestureDetector(
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.tileBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border, width: 0.8),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.location_on_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          geocodingService.fullAddress.isNotEmpty
                              ? geocodingService.fullAddress
                              : (geocodingService.currentTitle != 'Locating address...'
                                  ? '${geocodingService.currentTitle}, ${geocodingService.currentSubtitle}'
                                  : (pos != null ? 'Fetching address details...' : 'Detecting GPS location...')),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                            height: 1.35,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (pos != null) ...[
                              Text(
                                '${pos.latitude.toStringAsFixed(4)}°, ${pos.longitude.toStringAsFixed(4)}°',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textMuted,
                                  fontFamily: 'monospace',
                                ),
                              ),
                              const Text(
                                ' • ',
                                style: TextStyle(color: AppColors.textMuted),
                              ),
                            ],
                            Expanded(
                              child: Text(
                                isActive ? 'Tracking Active' : 'Stationary',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isActive ? AppColors.success : AppColors.textSecondary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Text(
                              'Details ›',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (geocodingService.isLoading)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Big Red / Green Stop / Start Tracking Button
          ElevatedButton(
            onPressed: () => _toggleTracking(isActive),
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
