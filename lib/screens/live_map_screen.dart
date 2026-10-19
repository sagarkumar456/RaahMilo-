import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../core/app_colors.dart';
import '../models/trip_model.dart';
import '../models/vehicle_type.dart';
import '../services/geocoding_service.dart';
import '../services/tracking_service.dart';
import '../utils/path_arrows.dart';
import '../widgets/map_calendar_bar.dart';
import '../widgets/pulse_indicator.dart';
import '../widgets/vehicle_marker_widget.dart';
import 'location_disabled_screen.dart';
import 'tracking_details_sheet.dart';
import 'trip_details_screen.dart';

class LiveMapScreen extends StatefulWidget {
  const LiveMapScreen({super.key});

  @override
  State<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends State<LiveMapScreen> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  bool _isSatellite = false;
  bool _isLocationEnabled = true;
  bool _isSheetCollapsed = false;
  StreamSubscription<ServiceStatus>? _serviceStatusSub;

  DateTime _selectedDate = DateTime.now();
  bool _isViewingHistoryDate = false;

  static const ll.LatLng _defaultCoord = ll.LatLng(20.5937, 78.9629); // India center fallback until GPS is acquired

  ll.LatLng? _animatedMarkerCoord;
  ll.LatLng? _targetMarkerCoord;
  ll.LatLng? _prevMarkerCoord;
  AnimationController? _markerMoveController;
  Animation<double>? _markerMoveAnimation;

  @override
  void initState() {
    super.initState();
    _markerMoveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _markerMoveAnimation = CurvedAnimation(
      parent: _markerMoveController!,
      curve: Curves.easeInOutCubic,
    )..addListener(() {
      if (_prevMarkerCoord != null && _targetMarkerCoord != null && mounted) {
        final t = _markerMoveAnimation!.value;
        setState(() {
          _animatedMarkerCoord = ll.LatLng(
            _prevMarkerCoord!.latitude + (_targetMarkerCoord!.latitude - _prevMarkerCoord!.latitude) * t,
            _prevMarkerCoord!.longitude + (_targetMarkerCoord!.longitude - _prevMarkerCoord!.longitude) * t,
          );
        });
      }
    });

    trackingService.addListener(_onTrackingUpdate);
    _checkLocationServiceStatus();
    _initDeviceLocation();
  }

  void _onTrackingUpdate() {
    final pos = trackingService.current;
    if (pos != null) {
      final newCoord = ll.LatLng(pos.latitude, pos.longitude);
      if (_targetMarkerCoord == null) {
        _targetMarkerCoord = newCoord;
        _animatedMarkerCoord = newCoord;
      } else if (_targetMarkerCoord!.latitude != newCoord.latitude ||
                 _targetMarkerCoord!.longitude != newCoord.longitude) {
        _prevMarkerCoord = _animatedMarkerCoord ?? _targetMarkerCoord;
        _targetMarkerCoord = newCoord;
        _markerMoveController?.forward(from: 0.0);
      }
    }
  }

  @override
  void dispose() {
    trackingService.removeListener(_onTrackingUpdate);
    _markerMoveController?.dispose();
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

  void _onDateSelected(DateTime date) {
    setState(() {
      _selectedDate = date;
      _isViewingHistoryDate = true;
    });
    final trips = trackingService.getTripsForDate(
      date,
      vehicleFilter: trackingService.currentVehicle,
    );
    final pts = <ll.LatLng>[];
    for (final t in trips) {
      for (final p in t.points) {
        pts.add(ll.LatLng(p.latitude, p.longitude));
      }
    }
    if (pts.isNotEmpty) {
      _fitRouteBounds(pts);
    }
  }

  void _onLiveTapped() {
    setState(() {
      _isViewingHistoryDate = false;
    });
    _recenter();
  }

  void _onVehicleSelected(VehicleType type) {
    trackingService.setVehicleType(type);
    if (_isViewingHistoryDate) {
      final trips = trackingService.getTripsForDate(
        _selectedDate,
        vehicleFilter: type,
      );
      final pts = <ll.LatLng>[];
      for (final t in trips) {
        for (final p in t.points) {
          pts.add(ll.LatLng(p.latitude, p.longitude));
        }
      }
      if (pts.isNotEmpty) {
        _fitRouteBounds(pts);
      }
    }
  }

  void _fitRouteBounds(List<ll.LatLng> points) {
    if (points.isEmpty) return;
    if (points.length == 1) {
      _mapController.move(points.first, 15.5);
      return;
    }
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    final center = ll.LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
    _mapController.move(center, 14.5);
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
        final currentVehicle = trackingService.currentVehicle;

        final hasRoute = trackingService.points.length >= 2;
        final routePoints = trackingService.points
            .map((p) => ll.LatLng(p.latitude, p.longitude))
            .toList();

        final rawSpeed = (pos != null && isActive)
            ? (pos.speed.clamp(0, 999) * 3.6)
            : 0.0;
        final speedKmh = rawSpeed.toStringAsFixed(0);
        final isMoving = isActive && rawSpeed >= 1.5;

        double heading = 0.0;
        if (pos != null && pos.heading > 0 && pos.heading <= 360) {
          heading = pos.heading * (pi / 180.0);
        } else if (routePoints.length >= 2) {
          heading = calculateBearing(routePoints[routePoints.length - 2], routePoints.last);
        }

        final tileUrl = _isSatellite
            ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
            : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

        // Prepare polylines and markers depending on mode
        final List<Polyline> polylines = [];
        final List<Marker> markers = [];
        final List<Marker> arrowMarkers = [];

        final dayTrips = trackingService.getTripsForDate(
          _selectedDate,
          vehicleFilter: currentVehicle,
        );

        if (_isViewingHistoryDate) {
          for (final trip in dayTrips) {
            final tPoints = trip.points.map((p) => ll.LatLng(p.latitude, p.longitude)).toList();
            if (tPoints.isNotEmpty) {
              if (tPoints.length >= 2) {
                polylines.add(
                  Polyline(
                    points: tPoints,
                    strokeWidth: 5.0,
                    color: trip.vehicleTypeEnum.color,
                  ),
                );
                arrowMarkers.addAll(buildDirectionalArrowMarkers(tPoints));
              }
              // Start Marker
              markers.add(
                Marker(
                  point: tPoints.first,
                  width: 36,
                  height: 36,
                  alignment: Alignment.topCenter,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                      ],
                    ),
                    child: const Icon(Icons.trip_origin_rounded, color: Colors.white, size: 20),
                  ),
                ),
              );
              // End Marker with 3D Vehicle
              markers.add(
                Marker(
                  point: tPoints.last,
                  width: 50,
                  height: 50,
                  alignment: Alignment.center,
                  child: VehicleMarkerWidget(
                    vehicleType: trip.vehicleTypeEnum,
                    isLive: false,
                    isMoving: false,
                    size: 38.0,
                    speedText: trip.avgSpeedKmh > 0 ? '${trip.avgSpeedKmh.toStringAsFixed(0)} km/h' : null,
                  ),
                ),
              );
            }
          }
        } else {
          // Live tracking mode
          if (hasRoute) {
            polylines.add(
              Polyline(
                points: routePoints,
                strokeWidth: 5.0,
                color: currentVehicle.color,
              ),
            );
            arrowMarkers.addAll(buildDirectionalArrowMarkers(routePoints));
          }
          if (trackingService.points.isNotEmpty) {
            markers.add(
              Marker(
                point: routePoints.first,
                width: 38,
                height: 38,
                alignment: Alignment.topCenter,
                child: const Icon(
                  Icons.location_on_rounded,
                  color: AppColors.primary,
                  size: 38,
                ),
              ),
            );
          }
          if (pos != null) {
            final markerPoint = _animatedMarkerCoord ?? currentCoord;
            markers.add(
              Marker(
                point: markerPoint,
                width: 58,
                height: 58,
                alignment: Alignment.center,
                child: VehicleMarkerWidget(
                  vehicleType: currentVehicle,
                  speedText: '$speedKmh km/h',
                  isLive: isActive,
                  isMoving: isMoving,
                  heading: heading,
                  size: 42.0,
                ),
              ),
            );
          }
        }

        return Scaffold(
          appBar: AppBar(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _isViewingHistoryDate ? 'History' : 'Live Map',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                ),
                const SizedBox(width: 8),
                _buildVehicleFilterDropdown(currentVehicle),
              ],
            ),
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

                  // Route Polyline
                  if (polylines.isNotEmpty)
                    PolylineLayer(
                      polylines: polylines,
                    ),

                  // Directional Arrow Badges along the path
                  if (arrowMarkers.isNotEmpty)
                    MarkerLayer(
                      markers: arrowMarkers,
                    ),

                  // Markers Layer: Start Point + Vehicle / Current Position
                  if (markers.isNotEmpty)
                    MarkerLayer(
                      markers: markers,
                    ),
                ],
              ),

              // 2. Right Side Action Controls: Calendar (Date & KM) + Zoom (+/-)
              Positioned(
                right: 16,
                top: 20,
                child: Column(
                  children: [
                    // Small Calendar Icon on right side of map
                    _floatingCircleButton(
                      icon: Icons.calendar_month_rounded,
                      iconColor: AppColors.primary,
                      tooltip: 'Calendar & KM History',
                      onTap: _openCalendarSheet,
                    ),
                    const SizedBox(height: 10),
                    _floatingCircleButton(
                      icon: Icons.add,
                      tooltip: 'Zoom In',
                      onTap: _zoomIn,
                    ),
                    const SizedBox(height: 8),
                    _floatingCircleButton(
                      icon: Icons.remove,
                      tooltip: 'Zoom Out',
                      onTap: _zoomOut,
                    ),
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

              // 5. Floating Bottom Card (History Day Summary or Live Tracking Card)
              Positioned(
                bottom: 12,
                left: 16,
                right: 16,
                child: _isViewingHistoryDate
                    ? _buildHistoryDaySummaryCard(dayTrips)
                    : GestureDetector(
                        onVerticalDragEnd: (details) {
                          if (details.primaryVelocity != null) {
                            if (details.primaryVelocity! > 60) {
                              setState(() => _isSheetCollapsed = true);
                            } else if (details.primaryVelocity! < -60) {
                              setState(() => _isSheetCollapsed = false);
                            }
                          }
                        },
                        onHorizontalDragEnd: (details) {
                          if (details.primaryVelocity != null && details.primaryVelocity!.abs() > 60) {
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

  Widget _buildHistoryDaySummaryCard(List<TripModel> dayTrips) {
    final vehicle = trackingService.currentVehicle;
    double totalMeters = 0.0;
    int totalMinutes = 0;
    for (final t in dayTrips) {
      totalMeters += t.distanceMeters;
      final end = t.endedAt ?? t.startedAt;
      totalMinutes += end.difference(t.startedAt).inMinutes;
    }
    final km = totalMeters / 1000.0;
    final kmStr = '${km.toStringAsFixed(1)} km';
    final durationStr = totalMinutes >= 60
        ? '${totalMinutes ~/ 60} hr ${totalMinutes % 60} min'
        : '$totalMinutes min';
    final dateStr = DateFormat('EEEE, dd MMM yyyy').format(_selectedDate);

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: vehicle.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(vehicle.icon, color: vehicle.color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dateStr,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      dayTrips.isEmpty
                          ? 'No ${vehicle.displayName} trips recorded on this day'
                          : '${dayTrips.length} ${dayTrips.length == 1 ? "Trip" : "Trips"} recorded • ${vehicle.displayName}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                tooltip: 'Return to Live Map',
                onPressed: _onLiveTapped,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.tileBackground,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('Distance', kmStr, Icons.straighten_rounded, vehicle.color),
                _buildStatItem('Duration', durationStr, Icons.access_time_rounded, AppColors.navyDark),
                _buildStatItem(
                  'Avg Speed',
                  dayTrips.isNotEmpty ? '${dayTrips.first.avgSpeedKmh.toStringAsFixed(0)} km/h' : '0 km/h',
                  Icons.speed_rounded,
                  AppColors.primary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (dayTrips.isNotEmpty)
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
                    label: const Text('View Trip'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary, width: 1.2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TripDetailsScreen(trip: dayTrips.first),
                        ),
                      );
                    },
                  ),
                ),
              if (dayTrips.isNotEmpty) const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.my_location_rounded, size: 18),
                  label: const Text('Live Map'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: _onLiveTapped,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
      ],
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

  Widget _buildVehicleFilterDropdown(VehicleType currentVehicle) {
    return PopupMenuButton<VehicleType>(
      initialValue: currentVehicle,
      tooltip: 'Filter Vehicle (Car, Human, Scooty, Bike)',
      onSelected: _onVehicleSelected,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
      offset: const Offset(0, 36),
      itemBuilder: (context) => [
        VehicleType.car,
        VehicleType.human,
        VehicleType.scooty,
        VehicleType.bike,
      ].map((v) {
        final isSelected = v == currentVehicle;
        return PopupMenuItem<VehicleType>(
          value: v,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: v.color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(v.icon, color: v.color, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                v.displayName,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: isSelected ? v.color : AppColors.textPrimary,
                ),
              ),
              if (isSelected) ...[
                const Spacer(),
                Icon(Icons.check_rounded, color: v.color, size: 18),
              ],
            ],
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: currentVehicle.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: currentVehicle.color.withValues(alpha: 0.35), width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(currentVehicle.icon, color: currentVehicle.color, size: 16),
            const SizedBox(width: 5),
            Text(
              currentVehicle.displayName,
              style: TextStyle(
                color: currentVehicle.color,
                fontWeight: FontWeight.bold,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down_rounded, color: currentVehicle.color, size: 18),
          ],
        ),
      ),
    );
  }

  void _openCalendarSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MapMonthlyCalendarSheet(
        initialDate: _selectedDate,
        vehicleFilter: trackingService.currentVehicle,
        onDateSelected: (date) {
          Navigator.pop(context);
          _onDateSelected(date);
        },
      ),
    );
  }

  Widget _floatingCircleButton({
    required IconData icon,
    Color? iconColor,
    String? tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
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
          child: Icon(icon, color: iconColor ?? AppColors.navyDark, size: 22),
        ),
      ),
    );
  }
}
