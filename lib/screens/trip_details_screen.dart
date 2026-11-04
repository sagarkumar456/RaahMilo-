import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/app_colors.dart';
import '../core/map_tiles.dart';
import '../models/stoppage_model.dart';
import '../models/trip_model.dart';
import '../services/road_routing_service.dart';
import '../services/tracking_service.dart';
import '../utils/path_arrows.dart';
import '../widgets/animated_dashed_polyline_layer.dart';
import '../widgets/stoppage_marker_widget.dart';
import '../widgets/vehicle_marker_widget.dart';
import 'share_screen.dart';

class TripDetailsScreen extends StatefulWidget {
  final TripModel trip;

  const TripDetailsScreen({super.key, required this.trip});

  @override
  State<TripDetailsScreen> createState() => _TripDetailsScreenState();
}

class _TripDetailsScreenState extends State<TripDetailsScreen> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  final GlobalKey _mapRepaintBoundaryKey = GlobalKey();
  bool _isMapReady = false;
  bool _isPlaying = false;
  double _sliderValue = 0.5;
  double _playbackSpeed = 1.0; // 0.25x, 0.5x, 0.75x, 1x, 2x, 4x
  static const List<double> _speedOptions = [0.25, 0.5, 0.75, 1.0, 2.0, 4.0];
  Timer? _playbackTimer;
  List<ll.LatLng>? _snappedRoute;

  // Camera Snapshot Animation & State
  late AnimationController _shutterFlashController;
  late Animation<double> _shutterFlashAnimation;
  late AnimationController _thumbnailSlideController;
  late Animation<Offset> _thumbnailSlideAnimation;
  Uint8List? _lastSnapshotBytes;
  bool _showSnapshotThumbnail = false;
  Timer? _snapshotThumbnailTimer;

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

    // Initialize Shutter Flash Animation (320ms snappy burst)
    _shutterFlashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _shutterFlashAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 0.95).chain(CurveTween(curve: Curves.easeOut)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.95, end: 0.0).chain(CurveTween(curve: Curves.easeIn)),
        weight: 65,
      ),
    ]).animate(_shutterFlashController);

    // Initialize Floating Thumbnail Slide & Pop Animation
    _thumbnailSlideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _thumbnailSlideAnimation = Tween<Offset>(
      begin: const Offset(-1.3, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _thumbnailSlideController,
      curve: Curves.elasticOut,
    ));

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
    _snapshotThumbnailTimer?.cancel();
    _shutterFlashController.dispose();
    _thumbnailSlideController.dispose();
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

  String get _speedLabel {
    if (_playbackSpeed == _playbackSpeed.roundToDouble()) {
      return '${_playbackSpeed.toInt()}x';
    }
    return '${_playbackSpeed}x';
  }

  void _startPlayback() {
    _playbackTimer?.cancel();
    // 50ms tick interval for ultra-smooth 20 fps progress without jerky jumps
    _playbackTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!mounted) return;
      setState(() {
        if (_sliderValue >= 1.0) {
          _sliderValue = 0.0;
        } else {
          // At 1.0x, ~14.2s for complete trip; at 0.5x, ~28.5s in detailed slow-mo
          _sliderValue = (_sliderValue + 0.0035 * _playbackSpeed).clamp(0.0, 1.0);
        }
      });
      _updatePlaybackMarker();
    });
  }

  void _decreaseSpeed() {
    final idx = _speedOptions.indexOf(_playbackSpeed);
    if (idx > 0) {
      setState(() => _playbackSpeed = _speedOptions[idx - 1]);
      if (_isPlaying) _startPlayback();
    }
  }

  void _increaseSpeed() {
    final idx = _speedOptions.indexOf(_playbackSpeed);
    if (idx != -1 && idx < _speedOptions.length - 1) {
      setState(() => _playbackSpeed = _speedOptions[idx + 1]);
      if (_isPlaying) _startPlayback();
    }
  }

  void _showSpeedSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Playback Speed (प्लेबैक स्पीड)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.navyDark,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _speedOptions.map((speed) {
                final isSelected = _playbackSpeed == speed;
                final label = speed == speed.roundToDouble()
                    ? '${speed.toInt()}x'
                    : '${speed}x';
                final desc = speed < 1.0 ? 'Slow' : (speed == 1.0 ? 'Normal' : 'Fast');

                return ChoiceChip(
                  label: Text('$label ($desc)'),
                  selected: isSelected,
                  selectedColor: AppColors.primary,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : AppColors.navyDark,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  ),
                  onSelected: (_) {
                    setState(() => _playbackSpeed = speed);
                    if (_isPlaying) _startPlayback();
                    Navigator.pop(ctx);
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _captureTripSnapshot() async {
    // 1. Tactile haptic & shutter click sound
    try {
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.click);
    } catch (_) {}

    // 2. Fire camera shutter flash animation
    _shutterFlashController.forward(from: 0.0);

    // 3. Pause playback if playing so user can view snapshot comfortably
    if (_isPlaying) {
      _togglePlayPause();
    }

    // 4. Tiny frame delay for flash to peak and render boundary to be clean
    await Future.delayed(const Duration(milliseconds: 70));

    try {
      final boundary = _mapRepaintBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      final dpr = (MediaQuery.of(context).devicePixelRatio * 1.2).clamp(1.5, 3.0);
      final ui.Image image = await boundary.toImage(pixelRatio: dpr);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final Uint8List pngBytes = byteData.buffer.asUint8List();

      if (!mounted) return;

      setState(() {
        _lastSnapshotBytes = pngBytes;
        _showSnapshotThumbnail = true;
      });

      _thumbnailSlideController.forward(from: 0.0);

      // Auto-hide floating thumbnail after 4.5 seconds
      _snapshotThumbnailTimer?.cancel();
      _snapshotThumbnailTimer = Timer(const Duration(milliseconds: 4500), () {
        if (mounted && _showSnapshotThumbnail) {
          _thumbnailSlideController.reverse().then((_) {
            if (mounted) setState(() => _showSnapshotThumbnail = false);
          });
        }
      });

      // Show the beautiful snapshot modal
      _showSnapshotModal(pngBytes);
    } catch (e) {
      debugPrint('Snapshot capture error: $e');
    }
  }

  Future<String?> _saveSnapshotToFile(Uint8List bytes) async {
    try {
      final downloadDir = Directory('/storage/emulated/0/Download');
      if (await downloadDir.exists()) {
        final fileName = 'RaahMilo_Trip_${DateTime.now().millisecondsSinceEpoch}.png';
        final file = File('${downloadDir.path}/$fileName');
        await file.writeAsBytes(bytes);
        return file.path;
      }
    } catch (_) {}

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final fileName = 'RaahMilo_Trip_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${appDir.path}/$fileName');
      await file.writeAsBytes(bytes);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  void _showSnapshotModal(Uint8List pngBytes) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.88,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 42,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // Header Row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Trip Snapshot Captured',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: AppColors.navyDark,
                          ),
                        ),
                        Text(
                          '${widget.trip.title} • $_currentTimestampText',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: AppColors.navyDark),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Polaroid / Framed Photo Card
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                  border: Border.all(color: Colors.grey.shade200, width: 1.2),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(17),
                  child: Stack(
                    children: [
                      AspectRatio(
                        aspectRatio: 16 / 10,
                        child: Image.memory(
                          pngBytes,
                          fit: BoxFit.cover,
                        ),
                      ),
                      // Watermark / Stats Ribbon at bottom
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.75),
                              ],
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: AppColors.primary,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      widget.trip.vehicleTypeEnum.icon,
                                      size: 11,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'RaahMilo GPS • ${widget.trip.vehicleTypeEnum.displayName}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                decoration: BoxDecoration(
                                  color: Colors.black45,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _currentTimestampText,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              // Action Buttons: Share & Save
              Row(
                children: [
                  // Share Button
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.share_rounded, size: 18),
                      label: const Text(
                        'Share Snapshot',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      onPressed: () async {
                        try {
                          final tempDir = await getTemporaryDirectory();
                          final file = File('${tempDir.path}/RaahMilo_Trip_${DateTime.now().millisecondsSinceEpoch}.png');
                          await file.writeAsBytes(pngBytes);
                          await SharePlus.instance.share(
                            ShareParams(
                              files: [XFile(file.path, mimeType: 'image/png')],
                              text: '📍 RaahMilo Trip Snapshot: ${widget.trip.title} (${widget.trip.vehicleTypeEnum.displayName})',
                            ),
                          );
                        } catch (e) {
                          debugPrint('Share error: $e');
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Save to Device Button
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.navyDark,
                        side: const BorderSide(color: AppColors.border, width: 1.2),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text(
                        'Save Image',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      onPressed: () async {
                        final path = await _saveSnapshotToFile(pngBytes);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Row(
                                children: [
                                  const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      path != null ? 'Saved to Downloads folder!' : 'Saved to App Documents!',
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                              backgroundColor: AppColors.primary,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                          Navigator.pop(ctx);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _updatePlaybackMarker() {
    final activeList = _points.map((p) => ll.LatLng(p.latitude, p.longitude)).toList();
    if (activeList.isEmpty) return;
    final index = ((activeList.length - 1) * _sliderValue).round().clamp(0, activeList.length - 1);
    final pt = activeList[index];
    // Smooth camera panning
    if (_playbackSpeed <= 1.0 || index % 2 == 0) {
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
            key: _mapRepaintBoundaryKey,
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
                // Animated Dashed Road Polyline (exact match with reference design)
                if (displayRoute.length >= 2)
                  AnimatedDashedPolylineLayer(
                    routes: [
                      RoutePolylineStyle(
                        points: displayRoute,
                        routeColor: const Color(0xFF10B981),
                        casingColor: const Color(0xFF10B981).withValues(alpha: 0.22),
                        strokeWidth: 7.0,
                        casingWidth: 13.0,
                        dashWidth: 3.0,
                        dashLength: 12.0,
                        gapLength: 8.0,
                        isMoving: _isPlaying, // Flows towards car during playback, stops when paused
                      ),
                    ],
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
                      // Camera / snapshot icon with animated capture
                      IconButton(
                        icon: const Icon(Icons.camera_alt_rounded, color: AppColors.navyDark, size: 24),
                        tooltip: 'Capture Trip Snapshot',
                        onPressed: _captureTripSnapshot,
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
                      // Speed Stepper Control [-] 1x [+] with slow-motion highlight & long-press sheet
                      Container(
                        decoration: BoxDecoration(
                          color: _playbackSpeed < 1.0 ? AppColors.primary.withValues(alpha: 0.10) : AppColors.tileBackground,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _playbackSpeed < 1.0 ? AppColors.primary : AppColors.border,
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Decrement Speed Button [-]
                            InkWell(
                              onTap: _decreaseSpeed,
                              borderRadius: const BorderRadius.horizontal(left: Radius.circular(13)),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
                                child: Icon(
                                  Icons.remove_rounded,
                                  size: 17,
                                  color: _playbackSpeed > _speedOptions.first ? AppColors.navyDark : AppColors.textSecondary.withValues(alpha: 0.35),
                                ),
                              ),
                            ),
                            // Center Speed Pill (Tappable to show speed sheet)
                            InkWell(
                              onTap: _showSpeedSelector,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_playbackSpeed < 1.0) ...[
                                      const Icon(Icons.slow_motion_video_rounded, size: 13, color: AppColors.primary),
                                      const SizedBox(width: 3),
                                    ],
                                    Text(
                                      _speedLabel,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: _playbackSpeed < 1.0 ? AppColors.primary : AppColors.navyDark,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // Increment Speed Button [+]
                            InkWell(
                              onTap: _increaseSpeed,
                              borderRadius: const BorderRadius.horizontal(right: Radius.circular(13)),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
                                child: Icon(
                                  Icons.add_rounded,
                                  size: 17,
                                  color: _playbackSpeed < _speedOptions.last ? AppColors.navyDark : AppColors.textSecondary.withValues(alpha: 0.35),
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
            ),
          ),

          // 3. Floating Mini-Snapshot Thumbnail (Tap to open full preview)
          if (_showSnapshotThumbnail && _lastSnapshotBytes != null)
            Positioned(
              bottom: 235,
              left: 18,
              child: SlideTransition(
                position: _thumbnailSlideAnimation,
                child: GestureDetector(
                  onTap: () {
                    _snapshotThumbnailTimer?.cancel();
                    _showSnapshotModal(_lastSnapshotBytes!);
                  },
                  child: Container(
                    width: 74,
                    height: 98,
                    padding: const EdgeInsets.all(3.5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.30),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                      border: Border.all(color: AppColors.primary, width: 1.5),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(_lastSnapshotBytes!, fit: BoxFit.cover),
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              color: Colors.black.withValues(alpha: 0.70),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.touch_app_rounded, size: 8.5, color: Colors.white),
                                  SizedBox(width: 2.5),
                                  Text(
                                    'View',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // 4. Camera Shutter Flash & Glowing Shutter Overlay
          AnimatedBuilder(
            animation: _shutterFlashController,
            builder: (context, _) {
              final flash = _shutterFlashAnimation.value;
              if (flash <= 0.01) return const SizedBox.shrink();
              return Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: Colors.white.withValues(alpha: (flash * 0.95).clamp(0.0, 1.0)),
                    child: Center(
                      child: Opacity(
                        opacity: (flash * 1.3).clamp(0.0, 1.0),
                        child: Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.45),
                                blurRadius: 28,
                                spreadRadius: 8,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.camera_alt_rounded,
                            color: AppColors.primary,
                            size: 40,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
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
