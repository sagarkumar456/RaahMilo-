import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
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
import '../services/road_routing_service.dart';
import '../services/tracking_service.dart';
import '../utils/path_arrows.dart';
import '../utils/trip_direction_helper.dart';
import '../widgets/map_calendar_bar.dart';
import '../widgets/pulse_indicator.dart';
import '../widgets/stoppage_marker_widget.dart';
import '../widgets/vehicle_marker_widget.dart';
import 'location_disabled_screen.dart';
import 'tracking_details_sheet.dart';
import 'trip_details_screen.dart';

class LiveMapScreen extends StatefulWidget {
  final bool isActiveTab;

  const LiveMapScreen({super.key, this.isActiveTab = true});

  @override
  State<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends State<LiveMapScreen> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  bool _isMapReady = false;
  bool _isSatellite = false;
  bool _isLocationEnabled = true;
  bool _isSheetCollapsed = false;
  bool _isAutoFollowEnabled = true;
  StreamSubscription<ServiceStatus>? _serviceStatusSub;

  // Selected date defaults to today so today's path & location show automatically
  DateTime _selectedDate = DateTime.now();
  String? _selectedSegmentId; // null = Show all paths together
  VehicleType? _selectedVehicleFilter;
  StreamSubscription<Position>? _passivePositionSub;

  // Road snapped route cache
  final Map<String, List<ll.LatLng>> _snappedTripRoutes = {};
  final Set<String> _pendingSnapTripIds = {};

  static const ll.LatLng _defaultCoord = ll.LatLng(20.5937, 78.9629); // India fallback

  // Smooth Marker Animation
  ll.LatLng? _animatedMarkerCoord;
  ll.LatLng? _targetMarkerCoord;
  ll.LatLng? _prevMarkerCoord;
  double _lastValidHeading = 0.0;
  AnimationController? _markerMoveController;
  Animation<double>? _markerMoveAnimation;

  // Smooth Map Camera Movement Animation
  AnimationController? _mapAnimationController;

  void _animatedMapMove(
    ll.LatLng destLocation,
    double destZoom, {
    int durationMs = 450,
    Curve curve = Curves.fastOutSlowIn,
  }) {
    if (!_isMapReady) return;
    _mapAnimationController?.stop();
    _mapAnimationController?.dispose();

    final startCenter = _mapController.camera.center;
    final startZoom = _mapController.camera.zoom;

    final latTween = Tween<double>(begin: startCenter.latitude, end: destLocation.latitude);
    final lngTween = Tween<double>(begin: startCenter.longitude, end: destLocation.longitude);
    final zoomTween = Tween<double>(begin: startZoom, end: destZoom);

    final controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: durationMs),
    );
    _mapAnimationController = controller;

    final animation = CurvedAnimation(parent: controller, curve: curve);

    controller.addListener(() {
      if (mounted) {
        try {
          _mapController.move(
            ll.LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)),
            zoomTween.evaluate(animation),
          );
        } catch (_) {}
      }
    });

    controller.forward();
  }

  void _safeMoveMap(ll.LatLng center, double zoom) {
    if (!_isMapReady) return;
    try {
      _mapController.move(center, zoom);
    } catch (_) {}
  }

  double get _safeZoom {
    if (!_isMapReady) return 16.0;
    try {
      return _mapController.camera.zoom;
    } catch (_) {
      return 16.0;
    }
  }

  @override
  void initState() {
    super.initState();
    // Marker interpolation animation (smooth 650ms transition)
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

        if (_isAutoFollowEnabled && trackingService.active) {
          _safeMoveMap(interp, _safeZoom);
        }
      }
    });

    trackingService.addListener(_onTrackingUpdate);
    _checkLocationServiceStatus();

    // Preload history
    trackingService.loadHistory();
  }

  @override
  void didUpdateWidget(LiveMapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActiveTab && !oldWidget.isActiveTab) {
      _refreshMapAndLocation();
    }
  }

  Future<void> _refreshMapAndLocation() async {
    await trackingService.loadHistory();
    _selectedDate = DateTime.now();
    _selectedSegmentId = null;
    _snapTripsForCurrentDate();

    final pos = await trackingService.initCurrentLocation(forceRefresh: true) ?? trackingService.current;

    if (_isMapReady && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (pos != null) {
          final coord = ll.LatLng(pos.latitude, pos.longitude);
          _targetMarkerCoord = coord;
          _animatedMarkerCoord = coord;
          _animatedMapMove(coord, 16.5, durationMs: 400);
        } else {
          final trips = trackingService.getTripsForDate(
            _selectedDate,
            vehicleFilter: _selectedVehicleFilter,
          );
          if (trips.isNotEmpty && !trackingService.active) {
            final allPoints = trips
                .expand((t) => _snappedTripRoutes[t.id] ?? t.points.map((p) => ll.LatLng(p.latitude, p.longitude)))
                .toList();
            if (allPoints.isNotEmpty) {
              _fitRouteBounds(allPoints, animate: true);
              return;
            }
          }
          try {
            _mapController.move(_mapController.camera.center, _mapController.camera.zoom);
          } catch (_) {}
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
        if (_isAutoFollowEnabled && trackingService.active) {
          _animatedMapMove(newCoord, _safeZoom, durationMs: 400);
        }
      } else if (_targetMarkerCoord!.latitude != newCoord.latitude ||
                 _targetMarkerCoord!.longitude != newCoord.longitude) {
        _prevMarkerCoord = _animatedMarkerCoord ?? _targetMarkerCoord;
        _targetMarkerCoord = newCoord;
        _markerMoveController?.forward(from: 0.0);
      }
    }

    if (trackingService.active) {
      _passivePositionSub?.cancel();
    } else if (_isLocationEnabled && _passivePositionSub == null) {
      _startPassiveLocationStream();
    }
  }

  @override
  void dispose() {
    trackingService.removeListener(_onTrackingUpdate);
    _passivePositionSub?.cancel();
    _markerMoveController?.dispose();
    _mapAnimationController?.dispose();
    _serviceStatusSub?.cancel();
    super.dispose();
  }

  void _checkLocationServiceStatus() {
    Geolocator.isLocationServiceEnabled().then((enabled) {
      if (mounted) {
        setState(() => _isLocationEnabled = enabled);
        if (enabled) {
          _initDeviceLocation();
          _startPassiveLocationStream();
        }
      }
    });
    _serviceStatusSub = Geolocator.getServiceStatusStream().listen((status) {
      if (mounted) {
        final isEnabled = status == ServiceStatus.enabled;
        setState(() => _isLocationEnabled = isEnabled);
        if (isEnabled) {
          _initDeviceLocation();
          _startPassiveLocationStream();
        } else {
          _passivePositionSub?.cancel();
        }
      }
    });
  }

  Future<void> _initDeviceLocation() async {
    final pos = await trackingService.initCurrentLocation(forceRefresh: true) ?? trackingService.current;
    if (pos != null && mounted) {
      final coord = ll.LatLng(pos.latitude, pos.longitude);
      _targetMarkerCoord = coord;
      _animatedMarkerCoord = coord;
      geocodingService.updateFromPosition(pos.latitude, pos.longitude);
      if (_isAutoFollowEnabled) {
        _animatedMapMove(coord, 16.5, durationMs: 500);
      }
    }
  }

  void _snapTripsForCurrentDate() {
    final trips = trackingService.getTripsForDate(
      _selectedDate,
      vehicleFilter: _selectedVehicleFilter,
    );
    for (final trip in trips) {
      if (trip.points.length >= 2 &&
          !_snappedTripRoutes.containsKey(trip.id) &&
          !_pendingSnapTripIds.contains(trip.id)) {
        _pendingSnapTripIds.add(trip.id);
        final rawPts = trip.points.map((p) => ll.LatLng(p.latitude, p.longitude)).toList();
        roadRoutingService.getRoadRoute(tripId: trip.id, points: rawPts).then((snapped) {
          _pendingSnapTripIds.remove(trip.id);
          if (mounted) {
            setState(() {
              _snappedTripRoutes[trip.id] = snapped;
            });
          }
        }).catchError((_) {
          _pendingSnapTripIds.remove(trip.id);
          if (mounted) {
            _snappedTripRoutes[trip.id] = rawPts;
          }
        });
      }
    }
  }

  void _startPassiveLocationStream() {
    _passivePositionSub?.cancel();
    if (trackingService.active) return;
    try {
      _passivePositionSub = Geolocator.getPositionStream(
        locationSettings: defaultTargetPlatform == TargetPlatform.android
            ? AndroidSettings(
                accuracy: LocationAccuracy.high,
                distanceFilter: 3,
                intervalDuration: const Duration(seconds: 3),
              )
            : const LocationSettings(
                accuracy: LocationAccuracy.high,
                distanceFilter: 3,
              ),
      ).listen((p) {
        if (!mounted || trackingService.active) return;
        if (p.accuracy > 70.0) return;

        trackingService.setCurrentPosition(p);
        final coord = ll.LatLng(p.latitude, p.longitude);
        _targetMarkerCoord = coord;
        if (_animatedMarkerCoord == null) {
          _animatedMarkerCoord = coord;
        }
        if (mounted) setState(() {});
      }, onError: (_) {});
    } catch (_) {}
  }

  void _zoomIn() {
    if (!_isMapReady) return;
    try {
      final currentZoom = _mapController.camera.zoom;
      _animatedMapMove(_mapController.camera.center, (currentZoom + 1.0).clamp(3.0, 19.0), durationMs: 300);
    } catch (_) {}
  }

  void _zoomOut() {
    if (!_isMapReady) return;
    try {
      final currentZoom = _mapController.camera.zoom;
      _animatedMapMove(_mapController.camera.center, (currentZoom - 1.0).clamp(3.0, 19.0), durationMs: 300);
    } catch (_) {}
  }

  Future<void> _recenter() async {
    setState(() {
      _isAutoFollowEnabled = true;
    });
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
    final pos = await trackingService.initCurrentLocation(forceRefresh: true) ?? trackingService.current;
    if (pos != null && mounted) {
      final coord = ll.LatLng(pos.latitude, pos.longitude);
      _targetMarkerCoord = coord;
      _animatedMarkerCoord = coord;
      geocodingService.updateFromPosition(pos.latitude, pos.longitude);
      _animatedMapMove(coord, 16.5, durationMs: 500);
    }
  }

  void _toggleMapLayer() {
    setState(() => _isSatellite = !_isSatellite);
  }

  void _onDateSelected(DateTime date) {
    setState(() {
      _selectedDate = date;
      _selectedSegmentId = null; // Reset to show all paths of the day
    });

    final dayTrips = trackingService.getTripsForDate(
      date,
      vehicleFilter: _selectedVehicleFilter,
    );

    final pts = <ll.LatLng>[];
    for (final t in dayTrips) {
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
      _selectedDate = DateTime.now();
      _selectedSegmentId = null;
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
      _selectedSegmentId = null;
    });

    final dayTrips = trackingService.getTripsForDate(
      _selectedDate,
      vehicleFilter: type,
    );
    final pts = <ll.LatLng>[];
    for (final t in dayTrips) {
      for (final p in t.points) {
        pts.add(ll.LatLng(p.latitude, p.longitude));
      }
    }
    if (pts.isNotEmpty) {
      _fitRouteBounds(pts);
    }
  }

  void _fitRouteBounds(List<ll.LatLng> points, {bool animate = true}) {
    if (!_isMapReady || points.isEmpty) return;
    if (points.length == 1) {
      if (animate) {
        _animatedMapMove(points.first, 16.0, durationMs: 400);
      } else {
        _safeMoveMap(points.first, 16.0);
      }
      return;
    }
    try {
      final cameraFit = CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.only(
          left: 36,
          right: 36,
          top: 110,
          bottom: 230,
        ),
        maxZoom: 17.0,
      );

      if (animate) {
        final fitted = cameraFit.fit(_mapController.camera);
        _animatedMapMove(fitted.center, fitted.zoom, durationMs: 500);
      } else {
        _mapController.fitCamera(cameraFit);
      }
    } catch (_) {
      try {
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
        if (animate) {
          _animatedMapMove(center, 15.0, durationMs: 500);
        } else {
          _safeMoveMap(center, 15.0);
        }
      } catch (_) {}
    }
  }

  Future<void> _toggleTracking(bool isActive) async {
    try {
      if (isActive) {
        await trackingService.stop();
        if (mounted) {
          final completedTrip = trackingService.historyTrips.isNotEmpty
              ? trackingService.historyTrips.first
              : null;
          final completedTripId = completedTrip?.id;

          setState(() {
            _selectedDate = DateTime.now();
            _selectedSegmentId = completedTripId;
          });

          final completedPts = (completedTrip != null && completedTrip.points.isNotEmpty)
              ? completedTrip.points.map((p) => ll.LatLng(p.latitude, p.longitude)).toList()
              : <ll.LatLng>[];

          if (completedPts.isNotEmpty) {
            _snapTripsForCurrentDate();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _fitRouteBounds(completedPts);
            });
          }

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('Trip completed & saved! Route is displayed on map.'),
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
          _selectedDate = DateTime.now();
          _isAutoFollowEnabled = true;
        });
        await trackingService.start();
        _recenter();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      trackingService.isBackgroundPermissionGranted
                          ? 'Live tracking started'
                          : 'Tracking started. For bag/pocket route recording, allow "All the time" location in Settings.',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
              action: trackingService.isBackgroundPermissionGranted
                  ? null
                  : SnackBarAction(
                      label: 'Settings',
                      textColor: Colors.amberAccent,
                      onPressed: () => Geolocator.openAppSettings(),
                    ),
              backgroundColor: AppColors.primary,
              duration: Duration(seconds: trackingService.isBackgroundPermissionGranted ? 2 : 4),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
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

        final List<ll.LatLng> liveRoutePoints = trackingService.points
            .map((p) => ll.LatLng(p.latitude, p.longitude))
            .toList();

        // Connect polyline right up to the live moving vehicle marker position only if in active motion
        if (isActive && liveRoutePoints.isNotEmpty && trackingService.isMoving) {
          final liveTip = _animatedMarkerCoord ?? currentCoord;
          final lastPt = liveRoutePoints.last;
          if (approximateDistanceMeters(lastPt, liveTip) >= 2.5) {
            liveRoutePoints.add(liveTip);
          }
        }
        final hasLiveRoute = liveRoutePoints.length >= 2;

        final rawSpeed = (pos != null && isActive)
            ? (pos.speed.clamp(0, 999) * 3.6)
            : 0.0;
        final speedKmh = rawSpeed.toStringAsFixed(0);
        final isMoving = isActive && rawSpeed >= 1.5;

        // Fetch day's trips
        final dayTrips = trackingService.getTripsForDate(
          _selectedDate,
          vehicleFilter: _selectedVehicleFilter,
        );

        double heading = _lastValidHeading;
        if (pos != null && pos.heading > 0 && pos.heading <= 360 && rawSpeed >= 1.0) {
          heading = pos.heading * (pi / 180.0);
          _lastValidHeading = heading;
        } else if (liveRoutePoints.length >= 2) {
          final p1 = liveRoutePoints[liveRoutePoints.length - 2];
          final p2 = liveRoutePoints.last;
          if (approximateDistanceMeters(p1, p2) >= 2.0) {
            heading = calculateBearing(p1, p2);
            _lastValidHeading = heading;
          }
        } else if (dayTrips.isNotEmpty && dayTrips.first.points.length >= 2) {
          final pts = dayTrips.first.points;
          final p1 = ll.LatLng(pts[pts.length - 2].latitude, pts[pts.length - 2].longitude);
          final p2 = ll.LatLng(pts.last.latitude, pts.last.longitude);
          heading = calculateBearing(p1, p2);
          _lastValidHeading = heading;
        }

        final now = DateTime.now();
        final isToday = _selectedDate.year == now.year &&
            _selectedDate.month == now.month &&
            _selectedDate.day == now.day;

        // Build distinct segments (Jaane Ka vs Aane Ka / Multiple trips)
        final segments = TripDirectionHelper.buildSegmentsForTrips(
          dayTrips,
          snappedRoutes: _snappedTripRoutes,
        );

        // Polylines & Markers for FlutterMap
        final List<Polyline> polylines = [];
        final List<Marker> markers = [];
        final List<Marker> arrowMarkers = [];

        // 1. Render Day Trips / Segments
        for (final seg in segments) {
          final isSelected = _selectedSegmentId == null || _selectedSegmentId == seg.id;
          if (!isSelected && _selectedSegmentId != null) {
            // If user selected a specific trip, dim the others
            continue;
          }

          final pts = seg.points;
          if (pts.length >= 2) {
            // Road casing
            polylines.add(
              Polyline(
                points: pts,
                strokeWidth: 7.2,
                color: seg.casingColor,
              ),
            );
            // Main route line in distinct color
            polylines.add(
              Polyline(
                points: pts,
                strokeWidth: 5.2,
                color: seg.primaryColor,
              ),
            );

            // Directional chevron arrows along this specific route
            arrowMarkers.addAll(
              buildDirectionalArrowMarkers(
                pts,
                routeColor: seg.primaryColor,
              ),
            );
          }

          if (pts.isNotEmpty) {
            // Start Origin Marker with direction label
            markers.add(
              Marker(
                point: pts.first,
                width: 78,
                height: 62,
                alignment: Alignment.topCenter,
                child: StartOriginMarkerWidget(
                  startedAt: seg.startedAt,
                  color: seg.primaryColor,
                  label: seg.isReturn ? 'RETURN START' : 'OUTWARD START',
                  onTap: () {
                    final startStop = StoppageModel(
                      stopNumber: 0,
                      latitude: pts.first.latitude,
                      longitude: pts.first.longitude,
                      arrivedAt: seg.startedAt,
                      departedAt: seg.startedAt,
                      duration: Duration.zero,
                      isStart: true,
                    );
                    showStoppageDetailsSheet(context, startStop);
                  },
                ),
              ),
            );

            // Turnaround Marker (for single continuous round trips)
            if (seg.turnaroundPoint != null && seg.isReturn) {
              markers.add(
                Marker(
                  point: seg.turnaroundPoint!,
                  width: 72,
                  height: 54,
                  alignment: Alignment.topCenter,
                  child: _TurnaroundMarkerWidget(
                    onTap: () {
                      _animatedMapMove(seg.turnaroundPoint!, 17.0);
                    },
                  ),
                ),
              );
            }

            // End Marker with destination badge
            final endStop = StoppageModel(
              stopNumber: 1,
              latitude: pts.last.latitude,
              longitude: pts.last.longitude,
              arrivedAt: seg.endedAt ?? seg.startedAt,
              departedAt: seg.endedAt ?? seg.startedAt,
              duration: Duration.zero,
              isEndStop: true,
            );

            markers.add(
              Marker(
                point: endStop.latLng,
                width: 78,
                height: 62,
                alignment: Alignment.topCenter,
                child: StoppageMarkerWidget(
                  stoppage: endStop,
                  customColor: seg.primaryColor,
                  customLabel: seg.isReturn ? 'RETURN DESTINATION' : 'DESTINATION',
                  customIcon: seg.isReturn ? Icons.home_rounded : Icons.flag_rounded,
                  onTap: () => showStoppageDetailsSheet(context, endStop),
                ),
              ),
            );
          }
        }

        // Add intermediate stoppages for the day's trips
        for (final trip in dayTrips) {
          if (_selectedSegmentId != null && !_selectedSegmentId!.startsWith(trip.id)) {
            continue;
          }
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
        }

        // 2. Render Active Live Tracking Route (if currently tracking on today's view)
        if (isActive && hasLiveRoute && isToday) {
          final liveColor = dayTrips.isNotEmpty ? TripDirectionHelper.colorReturn : TripDirectionHelper.colorOutward;
          polylines.add(
            Polyline(
              points: liveRoutePoints,
              strokeWidth: 7.2,
              color: liveColor.withValues(alpha: 0.25),
            ),
          );
          polylines.add(
            Polyline(
              points: liveRoutePoints,
              strokeWidth: 5.2,
              color: liveColor,
            ),
          );
          arrowMarkers.addAll(
            buildDirectionalArrowMarkers(liveRoutePoints, routeColor: liveColor),
          );

          // Live Start Marker
          final liveTripPoints = trackingService.tripPoints;
          final tripStartTime = trackingService.began ??
              (liveTripPoints.isNotEmpty ? liveTripPoints.first.timestamp : DateTime.now());

          markers.add(
            Marker(
              point: liveRoutePoints.first,
              width: 78,
              height: 62,
              alignment: Alignment.topCenter,
              child: StartOriginMarkerWidget(
                startedAt: tripStartTime,
                color: liveColor,
                label: dayTrips.isNotEmpty ? 'RETURN (LIVE)' : 'LIVE START',
                onTap: () {},
              ),
            ),
          );

          // Live intermediate halts
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



        // 3. User / Vehicle Position Marker
        if (pos != null) {
          final markerPoint = _animatedMarkerCoord ?? currentCoord;
          markers.add(
            Marker(
              point: markerPoint,
              width: 72,
              height: 72,
              alignment: Alignment.center,
              child: VehicleMarkerWidget(
                vehicleType: currentVehicle,
                speedText: '$speedKmh km/h',
                isLive: isActive,
                isMoving: isMoving,
                heading: heading,
                size: 48.0,
              ),
            ),
          );
        } else if (dayTrips.isNotEmpty) {
          final lastTripPts = dayTrips.first.points;
          if (lastTripPts.isNotEmpty) {
            final lastPt = ll.LatLng(lastTripPts.last.latitude, lastTripPts.last.longitude);
            markers.add(
              Marker(
                point: lastPt,
                width: 72,
                height: 72,
                alignment: Alignment.center,
                child: VehicleMarkerWidget(
                  vehicleType: dayTrips.first.vehicleTypeEnum,
                  speedText: null,
                  isLive: false,
                  isMoving: false,
                  heading: heading,
                  size: 48.0,
                  showBadge: false,
                ),
              ),
            );
          }
        }

        final titleText = isToday
            ? (isActive ? 'Live Tracking' : 'Today\'s Route')
            : DateFormat('dd MMM yyyy').format(_selectedDate);

        return Scaffold(
          appBar: AppBar(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  titleText,
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
              // 1. OpenStreetMap Layer with smooth gestures
              RepaintBoundary(
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: currentCoord,
                    initialZoom: pos != null ? 16.0 : 5.0,
                    minZoom: 3.0,
                    maxZoom: 19.0,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                      pinchZoomThreshold: 0.1,
                      pinchMoveThreshold: 8.0,
                      enableMultiFingerGestureRace: true,
                    ),
                    onMapReady: () {
                      if (mounted) {
                        setState(() => _isMapReady = true);
                        _initDeviceLocation();
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          Future.delayed(const Duration(milliseconds: 100), () {
                            if (mounted) _refreshMapAndLocation();
                          });
                        });
                      }
                    },
                    onPositionChanged: (camera, hasGesture) {
                      if (hasGesture && _isAutoFollowEnabled) {
                        setState(() => _isAutoFollowEnabled = false);
                      }
                    },
                  ),
                  children: [
                    AppMapTiles.buildTileLayer(isSatellite: _isSatellite),

                    // Polylines Layer
                    if (polylines.isNotEmpty)
                      PolylineLayer(
                        cullingMargin: 20.0,
                        polylines: polylines,
                      ),

                    // Directional Chevron Arrows
                    if (arrowMarkers.isNotEmpty)
                      MarkerLayer(
                        markers: arrowMarkers,
                      ),

                    // Markers (Starts, Halts, Ends, Vehicle)
                    if (markers.isNotEmpty)
                      MarkerLayer(
                        markers: markers,
                      ),
                  ],
                ),
              ),

              // 2. Top Floating Date & Trip Navigation Bar (Auto-loaded, 1-tap date and trip switching)
              Positioned(
                top: 12,
                left: 14,
                right: 68, // Leave room for right action buttons
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTopDateBar(isToday),
                    if (segments.length >= 2 || (segments.isNotEmpty && segments.first.turnaroundPoint != null)) ...[
                      const SizedBox(height: 6),
                      _buildTripFilterBar(segments),
                    ],
                  ],
                ),
              ),

              // 3. Right Side Action Controls: Calendar + Auto-Follow + Smooth Zoom (+/-)
              Positioned(
                right: 14,
                top: 12,
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
                      icon: (_isAutoFollowEnabled && trackingService.active)
                          ? Icons.navigation_rounded
                          : Icons.my_location_rounded,
                      iconColor: (_isAutoFollowEnabled && trackingService.active)
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

              // 4. Location Off Top Banner
              if (!_isLocationEnabled)
                Positioned(
                  top: 76,
                  left: 14,
                  right: 14,
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
                    firstChild: (!isActive && (dayTrips.isNotEmpty || !isToday))
                        ? _buildHistoryDaySummaryCard(dayTrips, segments)
                        : _buildExpandedCard(
                            isActive: isActive,
                            speedKmh: speedKmh,
                            pos: pos,
                          ),
                    secondChild: (!isActive && (dayTrips.isNotEmpty || !isToday))
                        ? _buildCollapsedHistoryCard(dayTrips, segments)
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

  /// Top floating date navigation bar with 1-tap date switching & distance badge
  Widget _buildTopDateBar(bool isToday) {
    final now = DateTime.now();
    final isYesterday = _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day - 1;

    String dateLabel = isToday
        ? 'Today'
        : (isYesterday ? 'Yesterday' : DateFormat('dd MMM').format(_selectedDate));

    final totalKm = trackingService.getDistanceForDate(
      _selectedDate,
      vehicleFilter: _selectedVehicleFilter,
    );
    final kmText = totalKm > 0 ? '${totalKm.toStringAsFixed(1)} km' : '0 km';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Previous day button
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              _onDateSelected(_selectedDate.subtract(const Duration(days: 1)));
            },
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.chevron_left_rounded, color: AppColors.navyDark, size: 20),
            ),
          ),

          // Date Chip + KM Badge (tap opens calendar)
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _openCalendarSheet,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isToday)
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.only(right: 5),
                      decoration: const BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                  Text(
                    dateLabel,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navyDark,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      kmText,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Next day button (disabled if already today)
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: isToday
                ? null
                : () {
                    _onDateSelected(_selectedDate.add(const Duration(days: 1)));
                  },
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.chevron_right_rounded,
                color: isToday ? Colors.grey.shade300 : AppColors.navyDark,
                size: 20,
              ),
            ),
          ),

          if (!isToday) ...[
            const SizedBox(width: 4),
            InkWell(
              onTap: _onLiveTapped,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.success,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Today',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Interactive Trip Selector chips: [ Sabhi Paths ] [ 🔵 Jaane Ka ] [ 🟠 Aane Ka ]
  Widget _buildTripFilterBar(List<TripRouteSegment> segments) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // "All Routes" chip
          _buildFilterChip(
            label: 'All Routes (${segments.length})',
            isSelected: _selectedSegmentId == null,
            color: AppColors.navyDark,
            icon: Icons.alt_route_rounded,
            onTap: () {
              setState(() => _selectedSegmentId = null);
              final allPts = segments.expand((s) => s.points).toList();
              if (allPts.isNotEmpty) _fitRouteBounds(allPts);
            },
          ),
          const SizedBox(width: 6),

          // Individual Segments (Jaane Ka, Aane Ka, etc.)
          ...segments.map((seg) {
            final isSelected = _selectedSegmentId == seg.id;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _buildFilterChip(
                label: '${seg.directionLabel} • ${seg.formattedDistance}',
                isSelected: isSelected,
                color: seg.primaryColor,
                icon: seg.isReturn ? Icons.keyboard_return_rounded : Icons.arrow_outward_rounded,
                onTap: () {
                  setState(() => _selectedSegmentId = seg.id);
                  if (seg.points.isNotEmpty) {
                    _fitRouteBounds(seg.points);
                  }
                },
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required Color color,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : color.withValues(alpha: 0.4),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? Colors.white : color,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isSelected ? Colors.white : color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryDaySummaryCard(List<TripModel> dayTrips, List<TripRouteSegment> segments) {
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
                          ? 'No recorded paths on this day'
                          : '${dayTrips.length} ${dayTrips.length == 1 ? "Trip" : "Trips"} recorded • Outward & Return separated',
                      style: const TextStyle(
                        fontSize: 11.5,
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
          const SizedBox(height: 10),
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
                      _animatedMapMove(st.latLng, 17.0);
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

  Widget _buildCollapsedHistoryCard(List<TripModel> dayTrips, List<TripRouteSegment> segments) {
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
                tooltip: 'Minimize to view map',
                onPressed: () => setState(() => _isSheetCollapsed = true),
              ),
            ],
          ),
          const SizedBox(height: 10),
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

/// Turnaround marker widget for round-trip return point
class _TurnaroundMarkerWidget extends StatelessWidget {
  final VoidCallback onTap;
  const _TurnaroundMarkerWidget({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            margin: const EdgeInsets.only(bottom: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED),
              borderRadius: BorderRadius.circular(6),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1)),
              ],
            ),
            child: const Text(
              'TURNAROUND',
              style: TextStyle(
                color: Colors.white,
                fontSize: 8.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.3,
              ),
            ),
          ),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
              ],
            ),
            child: const Icon(Icons.sync_rounded, color: Colors.white, size: 16),
          ),
        ],
      ),
    );
  }
}
