import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../core/app_colors.dart';
import '../core/map_tiles.dart';
import '../models/stoppage_model.dart';
import '../models/trip_model.dart';
import '../models/vehicle_type.dart';
import '../services/geocoding_service.dart';
import '../services/tracking_service.dart';
import '../utils/path_arrows.dart';
import '../widgets/map_calendar_bar.dart';
import '../widgets/pulse_indicator.dart';
import '../widgets/stoppage_marker_widget.dart';
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
  bool _isAutoFollowEnabled = true;
  StreamSubscription<ServiceStatus>? _serviceStatusSub;

  DateTime _selectedDate = DateTime.now();
  bool _isViewingHistoryDate = false;
  VehicleType? _selectedVehicleFilter;
  bool _hasAutoFittedInitialRoute = false;

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
        final interp = ll.LatLng(
          _prevMarkerCoord!.latitude + (_targetMarkerCoord!.latitude - _prevMarkerCoord!.latitude) * t,
          _prevMarkerCoord!.longitude + (_targetMarkerCoord!.longitude - _prevMarkerCoord!.longitude) * t,
        );
        setState(() {
          _animatedMarkerCoord = interp;
        });

        // Auto-follow map camera during live tracking so the map glides smoothly with the car
        if (_isAutoFollowEnabled && trackingService.active && !_isViewingHistoryDate) {
          _mapController.move(interp, _mapController.camera.zoom);
        }
      }
    });

    trackingService.addListener(_onTrackingUpdate);
    _checkLocationServiceStatus();
    _initDeviceLocation();

    // If today already has completed trips and tracking is not currently active,
    // display today's path by default on initial map load!
    final today = DateTime.now();
    final todayTrips = trackingService.getTripsForDate(today, vehicleFilter: _selectedVehicleFilter);
    if (todayTrips.isNotEmpty && !trackingService.active) {
      _isViewingHistoryDate = true;
      _hasAutoFittedInitialRoute = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final pts = todayTrips
              .expand((t) => t.points)
              .map((p) => ll.LatLng(p.latitude, p.longitude))
              .toList();
          if (pts.isNotEmpty) {
            _fitRouteBounds(pts);
          }
        }
      });
    }
  }

  void _onTrackingUpdate() {
    final pos = trackingService.current;
    if (pos != null) {
      final newCoord = ll.LatLng(pos.latitude, pos.longitude);
      if (_targetMarkerCoord == null) {
        _targetMarkerCoord = newCoord;
        _animatedMarkerCoord = newCoord;
        if (_isAutoFollowEnabled && trackingService.active && !_isViewingHistoryDate) {
          _mapController.move(newCoord, _mapController.camera.zoom);
        }
      } else if (_targetMarkerCoord!.latitude != newCoord.latitude ||
                 _targetMarkerCoord!.longitude != newCoord.longitude) {
        _prevMarkerCoord = _animatedMarkerCoord ?? _targetMarkerCoord;
        _targetMarkerCoord = newCoord;
        _markerMoveController?.forward(from: 0.0);
      }
    }

    // Auto-fit today's trips once history trips finish loading from local storage
    if (!_hasAutoFittedInitialRoute && !trackingService.active) {
      final trips = trackingService.getTripsForDate(
        _selectedDate,
        vehicleFilter: _selectedVehicleFilter,
      );
      if (trips.isNotEmpty) {
        _hasAutoFittedInitialRoute = true;
        _isViewingHistoryDate = true;
        final pts = trips
            .expand((t) => t.points)
            .map((p) => ll.LatLng(p.latitude, p.longitude))
            .toList();
        if (pts.isNotEmpty && mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _fitRouteBounds(pts);
          });
        }
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
    final todayTrips = trackingService.getTripsForDate(
      _selectedDate,
      vehicleFilter: _selectedVehicleFilter,
    );
    final hasRouteToShow = todayTrips.isNotEmpty && !trackingService.active;

    if (pos != null) {
      geocodingService.updateFromPosition(pos.latitude, pos.longitude);
      if (!hasRouteToShow) {
        _mapController.move(ll.LatLng(pos.latitude, pos.longitude), 16.0);
      }
    } else {
      final p = await trackingService.initCurrentLocation();
      if (p != null && mounted) {
        geocodingService.updateFromPosition(p.latitude, p.longitude);
        if (!hasRouteToShow) {
          _mapController.move(ll.LatLng(p.latitude, p.longitude), 16.0);
        }
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
    setState(() => _isAutoFollowEnabled = true);
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
      vehicleFilter: _selectedVehicleFilter,
    );
    final pts = <ll.LatLng>[];
    for (final t in trips) {
      for (final p in t.points) {
        pts.add(ll.LatLng(p.latitude, p.longitude));
      }
    }
    if (pts.isNotEmpty) {
      _fitRouteBounds(pts);
    } else {
      _recenter();
    }
  }

  void _onLiveTapped() {
    setState(() {
      _isViewingHistoryDate = false;
      _isAutoFollowEnabled = true;
    });
    _recenter();
  }

  void _onVehicleSelected(VehicleType? type) {
    if (type != null) {
      trackingService.setVehicleType(type);
    }
    setState(() {
      _selectedVehicleFilter = type;
    });
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

  void _fitRouteBounds(List<ll.LatLng> points) {
    if (points.isEmpty) return;
    if (points.length == 1) {
      _mapController.move(points.first, 16.0);
      return;
    }
    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.only(
            left: 36,
            right: 36,
            top: 40,
            bottom: 210,
          ),
          maxZoom: 17.0,
        ),
      );
    } catch (_) {
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
      _mapController.move(center, 15.0);
    }
  }

  Future<void> _toggleTracking(bool isActive) async {
    try {
      if (isActive) {
        await trackingService.stop();
        if (mounted) {
          setState(() {
            _selectedDate = DateTime.now();
            _isViewingHistoryDate = true;
          });

          // Automatically fit the map to the completed trip and today's path
          final trips = trackingService.getTripsForDate(
            _selectedDate,
            vehicleFilter: _selectedVehicleFilter,
          );
          final pts = trips
              .expand((t) => t.points)
              .map((p) => ll.LatLng(p.latitude, p.longitude))
              .toList();

          if (pts.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _fitRouteBounds(pts);
              }
            });
          }

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('Trip completed & saved! Route is shown on map.'),
                  ),
                ],
              ),
              backgroundColor: AppColors.success,
              duration: Duration(seconds: 3),
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
        setState(() {
          _isViewingHistoryDate = false;
          _isAutoFollowEnabled = true;
        });
        await trackingService.start();
        _recenter();
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
              backgroundColor: AppColors.primary,
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


        // Prepare polylines and markers depending on mode
        final List<Polyline> polylines = [];
        final List<Marker> markers = [];
        final List<Marker> arrowMarkers = [];

        final dayTrips = trackingService.getTripsForDate(
          _selectedDate,
          vehicleFilter: _selectedVehicleFilter,
        );

        final isToday = _selectedDate.year == DateTime.now().year &&
            _selectedDate.month == DateTime.now().month &&
            _selectedDate.day == DateTime.now().day;

        // When not actively tracking and today has trips, display today's path by default!
        final shouldShowHistoryTrips = _isViewingHistoryDate || (!isActive && dayTrips.isNotEmpty);

        if (shouldShowHistoryTrips) {
          for (final trip in dayTrips) {
            final tPoints = trip.points.map((p) => ll.LatLng(p.latitude, p.longitude)).toList();
            if (tPoints.isNotEmpty) {
              if (tPoints.length >= 2) {
                // Outer casing / road edge
                polylines.add(
                  Polyline(
                    points: tPoints,
                    strokeWidth: 7.2,
                    color: const Color(0xFF10B981).withValues(alpha: 0.25),
                  ),
                );
                // Main route line (Green)
                polylines.add(
                  Polyline(
                    points: tPoints,
                    strokeWidth: 5.2,
                    color: const Color(0xFF10B981),
                  ),
                );
                arrowMarkers.addAll(buildDirectionalArrowMarkers(tPoints, routeColor: const Color(0xFF10B981)));
              }

              // 1. Start Origin Marker
              markers.add(
                Marker(
                  point: tPoints.first,
                  width: 52,
                  height: 52,
                  alignment: Alignment.topCenter,
                  child: StartOriginMarkerWidget(
                    startedAt: trip.startedAt,
                    onTap: () {
                      final startStop = StoppageModel(
                        stopNumber: 0,
                        latitude: tPoints.first.latitude,
                        longitude: tPoints.first.longitude,
                        arrivedAt: trip.startedAt,
                        departedAt: trip.startedAt,
                        duration: Duration.zero,
                        isStart: true,
                      );
                      showStoppageDetailsSheet(context, startStop);
                    },
                  ),
                ),
              );

              // 2. Intermediate Stoppages along the trip (where the phone halted)
              for (final stoppage in trip.stoppages.where((s) => !s.isEndStop && !s.isStart)) {
                markers.add(
                  Marker(
                    point: stoppage.latLng,
                    width: 54,
                    height: 56,
                    alignment: Alignment.topCenter,
                    child: StoppageMarkerWidget(
                      stoppage: stoppage,
                      onTap: () => showStoppageDetailsSheet(context, stoppage),
                    ),
                  ),
                );
              }

              // 3. End Stoppage Marker ("na end stopage banana hai")
              final endStop = trip.endStoppage ??
                  StoppageModel(
                    stopNumber: trip.stoppages.length + 1,
                    latitude: tPoints.last.latitude,
                    longitude: tPoints.last.longitude,
                    arrivedAt: trip.endedAt ?? trip.startedAt,
                    departedAt: trip.endedAt ?? trip.startedAt,
                    duration: Duration.zero,
                    isEndStop: true,
                  );

              markers.add(
                Marker(
                  point: endStop.latLng,
                  width: 68,
                  height: 60,
                  alignment: Alignment.topCenter,
                  child: StoppageMarkerWidget(
                    stoppage: endStop,
                    onTap: () => showStoppageDetailsSheet(context, endStop),
                  ),
                ),
              );

              // 4. Parked Vehicle Marker at final destination
              markers.add(
                Marker(
                  point: tPoints.last,
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  child: VehicleMarkerWidget(
                    vehicleType: trip.vehicleTypeEnum,
                    isLive: false,
                    isMoving: false,
                    size: 36.0,
                    showBadge: false,
                  ),
                ),
              );
            }
          }

          // Also show current device position marker when viewing completed trips
          if (pos != null) {
            final markerPoint = _animatedMarkerCoord ?? currentCoord;
            markers.add(
              Marker(
                point: markerPoint,
                width: 48,
                height: 48,
                alignment: Alignment.center,
                child: VehicleMarkerWidget(
                  vehicleType: currentVehicle,
                  speedText: null,
                  isLive: false,
                  isMoving: false,
                  size: 38.0,
                  showBadge: false,
                ),
              ),
            );
          }
        } else {
          // Live tracking mode
          // Also show completed trips of today with a subtle route line
          for (final prevTrip in dayTrips) {
            final prevPts = prevTrip.points.map((p) => ll.LatLng(p.latitude, p.longitude)).toList();
            if (prevPts.length >= 2) {
              polylines.add(
                Polyline(
                  points: prevPts,
                  strokeWidth: 3.5,
                  color: const Color(0xFF10B981).withValues(alpha: 0.45),
                ),
              );
            }
          }

          if (hasRoute) {
            // Outer casing / road edge
            polylines.add(
              Polyline(
                points: routePoints,
                strokeWidth: 7.2,
                color: const Color(0xFF10B981).withValues(alpha: 0.25),
              ),
            );
            // Main route line (Green)
            polylines.add(
              Polyline(
                points: routePoints,
                strokeWidth: 5.2,
                color: const Color(0xFF10B981),
              ),
            );
            arrowMarkers.addAll(buildDirectionalArrowMarkers(routePoints, routeColor: const Color(0xFF10B981)));
          }

          if (routePoints.isNotEmpty) {
            final liveTripPoints = trackingService.tripPoints;
            final tripStartTime = trackingService.began ??
                (liveTripPoints.isNotEmpty ? liveTripPoints.first.timestamp : DateTime.now());

            // Live Trip Start Origin Marker
            markers.add(
              Marker(
                point: routePoints.first,
                width: 52,
                height: 52,
                alignment: Alignment.topCenter,
                child: StartOriginMarkerWidget(
                  startedAt: tripStartTime,
                  onTap: () {
                    final startStop = StoppageModel(
                      stopNumber: 0,
                      latitude: routePoints.first.latitude,
                      longitude: routePoints.first.longitude,
                      arrivedAt: tripStartTime,
                      departedAt: tripStartTime,
                      duration: Duration.zero,
                      isStart: true,
                    );
                    showStoppageDetailsSheet(context, startStop);
                  },
                ),
              ),
            );

            // Live Intermediate Stoppages detected so far
            final liveStoppages = extractStoppages(liveTripPoints);
            for (final stoppage in liveStoppages.where((s) => !s.isEndStop && !s.isStart)) {
              markers.add(
                Marker(
                  point: stoppage.latLng,
                  width: 54,
                  height: 56,
                  alignment: Alignment.topCenter,
                  child: StoppageMarkerWidget(
                    stoppage: stoppage,
                    onTap: () => showStoppageDetailsSheet(context, stoppage),
                  ),
                ),
              );
            }
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
                  shouldShowHistoryTrips
                      ? (isToday ? 'Today\'s Route' : 'History')
                      : 'Live Map',
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
                  onPositionChanged: (camera, hasGesture) {
                    if (hasGesture && _isAutoFollowEnabled) {
                      setState(() => _isAutoFollowEnabled = false);
                    }
                  },
                ),
                children: [
                  AppMapTiles.buildTileLayer(isSatellite: _isSatellite),

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

              // 2. Right Side Action Controls: Calendar (Date & KM) + Auto-Follow + Zoom (+/-)
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
                    // Auto-follow / Recenter GPS button
                    _floatingCircleButton(
                      icon: (_isAutoFollowEnabled && trackingService.active && !_isViewingHistoryDate)
                          ? Icons.navigation_rounded
                          : Icons.my_location_rounded,
                      iconColor: (_isAutoFollowEnabled && trackingService.active && !_isViewingHistoryDate)
                          ? const Color(0xFF10B981)
                          : AppColors.navyDark,
                      tooltip: (_isAutoFollowEnabled && trackingService.active)
                          ? 'Auto-following active'
                          : 'Re-center & Follow',
                      onTap: _recenter,
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
                child: GestureDetector(
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
                    firstChild: (shouldShowHistoryTrips && !isActive)
                        ? _buildHistoryDaySummaryCard(dayTrips)
                        : _buildExpandedCard(
                            isActive: isActive,
                            speedKmh: speedKmh,
                            pos: pos,
                          ),
                    secondChild: (shouldShowHistoryTrips && !isActive)
                        ? _buildCollapsedHistoryCard(dayTrips)
                        : _buildCollapsedCard(
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
    final vehicle = _selectedVehicleFilter ?? (dayTrips.isNotEmpty ? dayTrips.first.vehicleTypeEnum : trackingService.currentVehicle);
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

    final allStoppages = <StoppageModel>[];
    for (final t in dayTrips) {
      allStoppages.addAll(t.stoppages);
    }
    final intermediateStops = allStoppages.where((s) => !s.isEndStop && !s.isStart).toList();

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
            child: GestureDetector(
              onTap: () => setState(() => _isSheetCollapsed = true),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 24),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: AppColors.textMuted),
                        SizedBox(width: 2),
                        Text(
                          'Slide down to minimize',
                          style: TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
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
                          ? 'No ${_selectedVehicleFilter?.displayName ?? "trips"} recorded on this day'
                          : '${dayTrips.length} ${dayTrips.length == 1 ? "Trip" : "Trips"} recorded${_selectedVehicleFilter != null ? " • ${vehicle.displayName}" : ""}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textSecondary, size: 26),
                tooltip: 'Minimize Sheet',
                onPressed: () => setState(() => _isSheetCollapsed = true),
              ),
              IconButton(
                icon: const Icon(Icons.my_location_rounded, color: AppColors.primary),
                tooltip: 'Recenter on My Location',
                onPressed: _onLiveTapped,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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
                _buildStatItem(
                  'Halts',
                  '${intermediateStops.length}',
                  Icons.pause_circle_filled_rounded,
                  const Color(0xFFF59E0B),
                ),
              ],
            ),
          ),
          if (allStoppages.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  'Stoppages (${intermediateStops.length} halts • Tap to focus)',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: allStoppages.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, idx) {
                  final st = allStoppages[idx];
                  final isEnd = st.isEndStop;
                  final chipColor = isEnd ? const Color(0xFFDC2626) : const Color(0xFFF59E0B);
                  return GestureDetector(
                    onTap: () {
                      _mapController.move(st.latLng, 17.0);
                      showStoppageDetailsSheet(context, st);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: chipColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: chipColor.withValues(alpha: 0.4), width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isEnd ? Icons.flag_rounded : Icons.pause_circle_rounded,
                            size: 14,
                            color: chipColor,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            isEnd
                                ? 'End Stoppage'
                                : 'Stop #${st.stopNumber} (${st.formattedDuration})',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: chipColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
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
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: const Text('Start Tracking'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => _toggleTracking(false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCollapsedHistoryCard(List<TripModel> dayTrips) {
    final vehicle = _selectedVehicleFilter ?? (dayTrips.isNotEmpty ? dayTrips.first.vehicleTypeEnum : trackingService.currentVehicle);
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
        ? '${totalMinutes ~/ 60}h ${totalMinutes % 60}m'
        : '$totalMinutes min';

    final isToday = _selectedDate.year == DateTime.now().year &&
        _selectedDate.month == DateTime.now().month &&
        _selectedDate.day == DateTime.now().day;
    final dateBadge = isToday ? 'Today' : DateFormat('dd MMM').format(_selectedDate);

    int haltsCount = 0;
    for (final t in dayTrips) {
      haltsCount += t.intermediateStoppagesCount;
    }

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
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: vehicle.color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(vehicle.icon, color: vehicle.color, size: 16),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
              decoration: BoxDecoration(
                color: AppColors.tileBackground,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                dateBadge,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.navyDark,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                haltsCount > 0
                    ? '$kmStr • $durationStr • $haltsCount ${haltsCount == 1 ? "Halt" : "Halts"}'
                    : '$kmStr • $durationStr',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up_rounded, color: AppColors.primary, size: 24),
              tooltip: 'Expand Route Details',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: () => setState(() => _isSheetCollapsed = false),
            ),
            const SizedBox(width: 6),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              onPressed: () => _toggleTracking(false),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.play_arrow_rounded, size: 16),
                  SizedBox(width: 2),
                  Text(
                    'Track',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
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
    final activeVehicle = _selectedVehicleFilter ?? currentVehicle;
    return PopupMenuButton<VehicleType?>(
      initialValue: _selectedVehicleFilter,
      tooltip: 'Filter Vehicle Mode',
      onSelected: _onVehicleSelected,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
      offset: const Offset(0, 36),
      itemBuilder: (context) => [
        PopupMenuItem<VehicleType?>(
          value: null,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.alt_route_rounded, color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                'All Modes',
                style: TextStyle(
                  fontWeight: _selectedVehicleFilter == null ? FontWeight.bold : FontWeight.w600,
                  color: _selectedVehicleFilter == null ? AppColors.primary : AppColors.textPrimary,
                ),
              ),
              if (_selectedVehicleFilter == null) ...[
                const Spacer(),
                const Icon(Icons.check_rounded, color: AppColors.primary, size: 18),
              ],
            ],
          ),
        ),
        ...[
          VehicleType.car,
          VehicleType.human,
          VehicleType.scooty,
          VehicleType.bike,
        ].map((v) {
          final isSelected = v == _selectedVehicleFilter;
          return PopupMenuItem<VehicleType?>(
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
        }),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: (_selectedVehicleFilter != null ? activeVehicle.color : AppColors.primary).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: (_selectedVehicleFilter != null ? activeVehicle.color : AppColors.primary).withValues(alpha: 0.35),
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _selectedVehicleFilter != null ? activeVehicle.icon : Icons.alt_route_rounded,
              color: _selectedVehicleFilter != null ? activeVehicle.color : AppColors.primary,
              size: 16,
            ),
            const SizedBox(width: 5),
            Text(
              _selectedVehicleFilter?.displayName ?? 'All Modes',
              style: TextStyle(
                color: _selectedVehicleFilter != null ? activeVehicle.color : AppColors.primary,
                fontWeight: FontWeight.bold,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down_rounded,
              color: _selectedVehicleFilter != null ? activeVehicle.color : AppColors.primary,
              size: 18,
            ),
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
        vehicleFilter: _selectedVehicleFilter,
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
