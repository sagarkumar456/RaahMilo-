import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../core/app_colors.dart';
import '../core/map_tiles.dart';
import '../models/stoppage_model.dart';
import '../models/trip_model.dart';
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
  bool _isPlaying = false;
  double _sliderValue = 0.5;
  int _playbackSpeed = 1; // 1x, 2x, 4x
  Timer? _playbackTimer;

  late List<TripPoint> _points;
  List<StoppageModel> get _stoppages => extractStoppages(_points);

  @override
  void initState() {
    super.initState();
    _points = widget.trip.points.isNotEmpty
        ? widget.trip.points
        : [
            TripPoint(latitude: 28.6250, longitude: 77.2050, speed: 18.0, accuracy: 4.0, timestamp: widget.trip.startedAt),
            TripPoint(latitude: 28.6200, longitude: 77.2080, speed: 22.0, accuracy: 4.0, timestamp: widget.trip.startedAt.add(const Duration(minutes: 10))),
            TripPoint(latitude: 28.6139, longitude: 77.2090, speed: 25.0, accuracy: 4.0, timestamp: widget.trip.startedAt.add(const Duration(minutes: 20))),
            TripPoint(latitude: 28.6080, longitude: 77.2140, speed: 20.0, accuracy: 4.0, timestamp: widget.trip.startedAt.add(const Duration(minutes: 32))),
          ];
    _loadTripPointsFromFirestore();
  }

  Future<void> _loadTripPointsFromFirestore() async {
    if (widget.trip.points.isNotEmpty || widget.trip.id.startsWith('local_')) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('trips')
          .doc(widget.trip.id)
          .collection('points')
          .orderBy('at')
          .get();
      if (snap.docs.isNotEmpty && mounted) {
        final pts = snap.docs.map((d) => TripPoint.fromMap(d.data())).toList();
        setState(() {
          _points = pts;
        });
        if (pts.isNotEmpty) {
          _mapController.move(ll.LatLng(pts.first.latitude, pts.first.longitude), 15.0);
        }
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
          _sliderValue += 0.02;
          if (_sliderValue > 1.0) _sliderValue = 1.0;
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
    if (_points.isEmpty) return;
    final index = ((_points.length - 1) * _sliderValue).round().clamp(0, _points.length - 1);
    final pt = _points[index];
    _mapController.move(
      ll.LatLng(pt.latitude, pt.longitude),
      _mapController.camera.zoom,
    );
  }

  String get _currentTimestampText {
    if (_points.isEmpty) return '08:25 AM';
    final index = ((_points.length - 1) * _sliderValue).round().clamp(0, _points.length - 1);
    final time = _points[index].timestamp;
    final hour = time.hour > 12 ? time.hour - 12 : (time.hour == 0 ? 12 : time.hour);
    final minute = time.minute.toString().padLeft(2, '0');
    final ampm = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final latLngList = _points.map((p) => ll.LatLng(p.latitude, p.longitude)).toList();
    final playbackIndex = _points.isNotEmpty
        ? ((_points.length - 1) * _sliderValue).round().clamp(0, _points.length - 1)
        : 0;
    final currentPlaybackPt = _points.isNotEmpty
        ? _points[playbackIndex]
        : TripPoint(latitude: 28.6139, longitude: 77.2090, speed: 0, accuracy: 5, timestamp: DateTime.now());

    final currentPlaybackLL = ll.LatLng(currentPlaybackPt.latitude, currentPlaybackPt.longitude);

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
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: currentPlaybackLL,
              initialZoom: 14.8,
            ),
            children: [
              AppMapTiles.buildTileLayer(),
              PolylineLayer(
                polylines: [
                  // Outer casing / road edge
                  Polyline(
                    points: latLngList,
                    strokeWidth: 7.2,
                    color: const Color(0xFF10B981).withValues(alpha: 0.25),
                  ),
                  // Main route line (Green)
                  Polyline(
                    points: latLngList,
                    strokeWidth: 5.2,
                    color: const Color(0xFF10B981),
                  ),
                ],
              ),
              // Directional arrows embedded along route
              MarkerLayer(
                markers: buildDirectionalArrowMarkers(
                  latLngList,
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
                        startedAt: _points.first.timestamp,
                        onTap: () {
                          final startStop = StoppageModel(
                            stopNumber: 0,
                            latitude: _points.first.latitude,
                            longitude: _points.first.longitude,
                            arrivedAt: _points.first.timestamp,
                            departedAt: _points.first.timestamp,
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
                    width: 58,
                    height: 58,
                    alignment: Alignment.center,
                    child: VehicleMarkerWidget(
                      vehicleType: widget.trip.vehicleTypeEnum,
                      isLive: _isPlaying,
                      isMoving: _isPlaying,
                      heading: (playbackIndex > 0 && latLngList.length > 1)
                          ? calculateBearing(latLngList[playbackIndex - 1], latLngList[playbackIndex])
                          : 0.0,
                      size: 42.0,
                    ),
                  ),
                ],
              ),
            ],
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
                  Text(
                    widget.trip.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navyDark,
                    ),
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
                              _mapController.move(st.latLng, 16.5);
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
