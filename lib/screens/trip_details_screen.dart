import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../core/app_colors.dart';
import '../core/map_tiles.dart';
import '../models/stoppage_model.dart';
import '../models/trip_model.dart';
import '../services/road_routing_service.dart';
import '../services/tracking_service.dart';
import '../utils/path_arrows.dart';
import '../widgets/stoppage_marker_widget.dart';
import '../widgets/vehicle_marker_widget.dart';
import 'share_screen.dart';

class TripDetailsScreen extends StatefulWidget {
  final TripModel trip;

  const TripDetailsScreen({super.key, required this.trip});

  @override
  State<TripDetailsScreen> createState() => _TripDetailsScreenState();
}

class _TripDetailsScreenState extends State<TripDetailsScreen> {
  final MapController _mapController = MapController();
  bool _isMapReady = false;
  bool _isPlaying = false;
  double _sliderValue = 0.5;
  int _playbackSpeed = 1; // 1x, 2x, 4x
  Timer? _playbackTimer;
  List<ll.LatLng>? _snappedRoute;

  late List<TripPoint> _points;

  List<StoppageModel> get _stoppages => extractStoppages(_points);

  void _safeMoveMap(ll.LatLng center, double zoom) {
    if (!_isMapReady) return;
    try {
      _mapController.move(center, zoom);
    } catch (_) {}
  }

  double get _safeZoom {
    if (!_isMapReady) return 14.8;
    try {
      return _mapController.camera.zoom;
    } catch (_) {
      return 14.8;
    }
  }

  @override
  void initState() {
    super.initState();
    _points = List<TripPoint>.from(widget.trip.points);
    _loadTripPointsFromFirestore();
    _snapTripRoute();
  }

  Future<void> _snapTripRoute() async {
    final rawPts = _points.map((p) => ll.LatLng(p.latitude, p.longitude)).toList();
    if (rawPts.length >= 2) {
      final snapped = await roadRoutingService.getRoadRoute(
        tripId: widget.trip.id,
        points: rawPts,
      );
      if (mounted && snapped.isNotEmpty && snapped != rawPts) {
        setState(() {
          _snappedRoute = snapped;
        });
        _fitTripBounds();
      }
    }
  }

  void _fitTripBounds() {
    if (!_isMapReady) return;
    try {
      final activeList = (_snappedRoute != null && _snappedRoute!.isNotEmpty)
          ? _snappedRoute!
          : _points.map((p) => ll.LatLng(p.latitude, p.longitude)).toList();

      if (activeList.length >= 2) {
        final bounds = LatLngBounds.fromPoints(activeList);
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: bounds,
            padding: const EdgeInsets.only(top: 60, bottom: 220, left: 36, right: 36),
            maxZoom: 16.5,
            minZoom: 4.0,
          ),
        );
      } else if (activeList.isNotEmpty) {
        _mapController.move(activeList.first, 15.0);
      }
    } catch (_) {}
  }

  Future<void> _loadTripPointsFromFirestore() async {
    if (_points.isNotEmpty || widget.trip.id.startsWith('local_')) return;
    try {
      final pts = await trackingService.ensureTripPointsLoaded(widget.trip);
      if (pts.isNotEmpty && mounted) {
        setState(() {
          _points = pts;
        });
        _fitTripBounds();
        _snapTripRoute();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    super.dispose();
  }

  void _togglePlayPause() {
    setState(() => _isPlaying = !_isPlaying);
    if (_isPlaying) {
      _startPlayback();
    } else {
      _playbackTimer?.cancel();
    }
  }

  void _startPlayback() {
    _playbackTimer?.cancel();
    _playbackTimer = Timer.periodic(Duration(milliseconds: (200 / _playbackSpeed).round()), (timer) {
      if (!mounted) return;
      setState(() {
        if (_sliderValue >= 1.0) {
          _sliderValue = 0.0;
        } else {
          _sliderValue += 0.015;
        }
      });
      _updatePlaybackMarker();
    });
  }

  void _toggleSpeed() {
    setState(() {
      if (_playbackSpeed == 1) {
        _playbackSpeed = 2;
      } else if (_playbackSpeed == 2) {
        _playbackSpeed = 4;
      } else {
        _playbackSpeed = 1;
      }
    });
    if (_isPlaying) _startPlayback();
  }

  void _updatePlaybackMarker() {
    final activeList = _points.map((p) => ll.LatLng(p.latitude, p.longitude)).toList();
    if (activeList.isEmpty) return;
    final index = ((activeList.length - 1) * _sliderValue).round().clamp(0, activeList.length - 1);
    final pt = activeList[index];
    // Smooth camera panning: avoid moving map constantly during high speed playback to keep framerate ultra smooth
    if (_playbackSpeed == 1 || index % 2 == 0) {
      _safeMoveMap(pt, _safeZoom);
    }
  }

  String get _currentTimestampText {
    if (_points.isEmpty) return '08:25 AM';
    final startTime = _points.first.timestamp;
    final endTime = _points.last.timestamp;
    final totalSecs = endTime.difference(startTime).inSeconds;
    final time = totalSecs > 0
        ? startTime.add(Duration(seconds: (totalSecs * _sliderValue).round()))
        : startTime;
    final hour = time.hour > 12 ? time.hour - 12 : (time.hour == 0 ? 12 : time.hour);
    final minute = time.minute.toString().padLeft(2, '0');
    final ampm = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final latLngList = _points.map((p) => ll.LatLng(p.latitude, p.longitude)).toList();
    final displayRoute = (_snappedRoute != null && _snappedRoute!.isNotEmpty)
        ? _snappedRoute!
        : latLngList;

    final playbackIndex = displayRoute.isNotEmpty
        ? ((displayRoute.length - 1) * _sliderValue).round().clamp(0, displayRoute.length - 1)
        : 0;
    final currentPlaybackLL = displayRoute.isNotEmpty
        ? displayRoute[playbackIndex]
        : (trackingService.current != null
            ? ll.LatLng(trackingService.current!.latitude, trackingService.current!.longitude)
            : const ll.LatLng(20.5937, 78.9629));

    double heading = 0.0;
    if (displayRoute.length >= 2) {
      if (playbackIndex > 0) {
        final p1 = displayRoute[playbackIndex - 1];
        final p2 = displayRoute[playbackIndex];
        if (approximateDistanceMeters(p1, p2) > 0.5) {
          heading = calculateBearing(p1, p2);
        } else if (playbackIndex > 1) {
          heading = calculateBearing(displayRoute[playbackIndex - 2], p2);
        }
      } else {
        heading = calculateBearing(displayRoute[0], displayRoute[1]);
      }
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Trip Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share Trip',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ShareScreen(tripId: widget.trip.id)),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Delete Trip',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete Trip?'),
                  content: const Text('Are you sure you want to permanently delete this trip from history?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (confirm == true && mounted) {
                await trackingService.deleteTrip(widget.trip.id);
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Trip deleted from history')),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. OpenStreetMap showing route path & playback position
          RepaintBoundary(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: currentPlaybackLL,
                initialZoom: 15.0,
                minZoom: 3.0,
                maxZoom: 18.5,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  pinchZoomThreshold: 0.1,
                  pinchMoveThreshold: 8.0,
                  enableMultiFingerGestureRace: true,
                ),
                initialCameraFit: displayRoute.length >= 2
                    ? CameraFit.bounds(
                        bounds: LatLngBounds.fromPoints(displayRoute),
                        padding: const EdgeInsets.only(top: 60, bottom: 220, left: 36, right: 36),
                        maxZoom: 16.5,
                        minZoom: 4.0,
                      )
                    : null,
                onMapReady: () {
                  if (mounted) {
                    setState(() => _isMapReady = true);
                    // Ensure tiles load immediately after page transition without waiting for user touch
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      Future.delayed(const Duration(milliseconds: 100), () {
                        if (mounted) _fitTripBounds();
                      });
                    });
                  }
                },
              ),
              children: [
                AppMapTiles.buildTileLayer(),
                PolylineLayer(
                  cullingMargin: 20.0,
                  polylines: [
                    // Outer casing / road edge
                    Polyline(
                      points: displayRoute,
                      strokeWidth: 7.2,
                      color: const Color(0xFF10B981).withValues(alpha: 0.25),
                    ),
                    // Main route line (Green)
                    Polyline(
                      points: displayRoute,
                      strokeWidth: 5.2,
                      color: const Color(0xFF10B981),
                    ),
                  ],
                ),
              // Directional arrows embedded along route
              MarkerLayer(
                markers: buildDirectionalArrowMarkers(
                  displayRoute,
                  routeColor: const Color(0xFF10B981),
                ),
              ),
              MarkerLayer(
                markers: [
                  if (latLngList.isNotEmpty)
                    Marker(
                      point: latLngList.first,
                      width: 52,
                      height: 52,
                      alignment: Alignment.topCenter,
                      child: StartOriginMarkerWidget(
                        startedAt: _points.first.timestamp.toLocal(),
                        onTap: () {
                          final startStop = StoppageModel(
                            stopNumber: 0,
                            latitude: _points.first.latitude,
                            longitude: _points.first.longitude,
                            arrivedAt: _points.first.timestamp.toLocal(),
                            departedAt: _points.first.timestamp.toLocal(),
                            duration: Duration.zero,
                            isStart: true,
                          );
                          showStoppageDetailsSheet(context, startStop);
                        },
                      ),
                    ),
                  // Intermediate Stoppages
                  for (final stoppage in _stoppages.where((s) => !s.isEndStop && !s.isStart))
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
                  // End Stoppage Marker ("na end stopage banana hai")
                  if (_stoppages.any((s) => s.isEndStop))
                    Marker(
                      point: _stoppages.firstWhere((s) => s.isEndStop).latLng,
                      width: 68,
                      height: 60,
                      alignment: Alignment.topCenter,
                      child: StoppageMarkerWidget(
                        stoppage: _stoppages.firstWhere((s) => s.isEndStop),
                        onTap: () => showStoppageDetailsSheet(
                          context,
                          _stoppages.firstWhere((s) => s.isEndStop),
                        ),
                      ),
                    )
                  else if (latLngList.isNotEmpty)
                    Marker(
                      point: latLngList.last,
                      width: 68,
                      height: 60,
                      alignment: Alignment.topCenter,
                      child: StoppageMarkerWidget(
                        stoppage: StoppageModel(
                          stopNumber: _stoppages.length + 1,
                          latitude: latLngList.last.latitude,
                          longitude: latLngList.last.longitude,
                          arrivedAt: _points.last.timestamp,
                          departedAt: _points.last.timestamp,
                          duration: Duration.zero,
                          isEndStop: true,
                        ),
                        onTap: () {},
                      ),
                    ),
                  // Current Playback Vehicle
                  Marker(
                    point: currentPlaybackLL,
                    width: 72,
                    height: 72,
                    alignment: Alignment.center,
                    child: VehicleMarkerWidget(
                      vehicleType: widget.trip.vehicleTypeEnum,
                      isLive: _isPlaying,
                      isMoving: _isPlaying,
                      heading: heading,
                      size: 48.0,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

          // 2. Playback Bottom Card matching Screen 10
          Positioned(
            bottom: 14,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title & Date
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.trip.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.navyDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.trip.formattedTimeRange,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  // 4 Stats Columns
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _statColumn(
                        label: 'Distance',
                        value: widget.trip.formattedDistance,
                      ),
                      _statColumn(
                        label: 'Duration',
                        value: widget.trip.formattedDuration,
                      ),
                      _statColumn(
                        label: 'Avg Speed',
                        value: '${widget.trip.avgSpeedKmh.toStringAsFixed(0)} km/h',
                      ),
                      _statColumn(
                        label: 'Halts',
                        value: '${_stoppages.where((s) => !s.isEndStop && !s.isStart).length}',
                      ),
                    ],
                  ),
                  if (_stoppages.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 30,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _stoppages.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, idx) {
                          final st = _stoppages[idx];
                          final isEnd = st.isEndStop;
                          final chipColor = isEnd ? const Color(0xFFDC2626) : const Color(0xFFF59E0B);
                          return GestureDetector(
                            onTap: () {
                              final ptIndex = _points.indexWhere((p) =>
                                  (p.latitude - st.latitude).abs() < 0.0005 &&
                                  (p.longitude - st.longitude).abs() < 0.0005);
                              if (ptIndex != -1 && _points.length > 1) {
                                setState(() {
                                  _sliderValue = ptIndex / (_points.length - 1);
                                });
                                _updatePlaybackMarker();
                              }
                              _safeMoveMap(st.latLng, 16.5);
                              showStoppageDetailsSheet(context, st);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                                    size: 13,
                                    color: chipColor,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isEnd
                                        ? 'End Stoppage'
                                        : 'Stop #${st.stopNumber} (${st.formattedDuration})',
                                    style: TextStyle(
                                      fontSize: 11,
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
                  const SizedBox(height: 10),
                  // Timestamp above slider
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _currentTimestampText,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  // Playback scrub slider
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: AppColors.primary,
                      inactiveTrackColor: AppColors.tileBackground,
                      thumbColor: AppColors.primary,
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                    ),
                    child: Slider(
                      value: _sliderValue,
                      onChanged: (val) {
                        setState(() => _sliderValue = val);
                        _updatePlaybackMarker();
                      },
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Controls Bar: Camera, Play/Pause, Speed
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Camera / snapshot icon
                      IconButton(
                        icon: const Icon(Icons.camera_alt_outlined, color: AppColors.navyDark),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Trip snapshot captured!')),
                          );
                        },
                      ),
                      // Play / Pause round button
                      GestureDetector(
                        onTap: _togglePlayPause,
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.25),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Icon(
                            _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      ),
                      // Speed multiplier pill
                      InkWell(
                        onTap: _toggleSpeed,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.tileBackground,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Text(
                            '${_playbackSpeed}x',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppColors.navyDark,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statColumn({required String label, required String value}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.navyDark,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}
