import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../core/app_colors.dart';
import '../core/map_tiles.dart';
import '../models/geofence_model.dart';
import '../services/alert_sound_service.dart';
import '../services/geofence_service.dart';
import '../services/tracking_service.dart';

class GeofenceScreen extends StatefulWidget {
  const GeofenceScreen({super.key});

  @override
  State<GeofenceScreen> createState() => _GeofenceScreenState();
}

class _GeofenceScreenState extends State<GeofenceScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final MapController _mapController = MapController();
  bool _isMapReady = false;

  final TextEditingController _nameController = TextEditingController(text: 'Home');
  double _radius = 500.0;
  bool _notifyOnEntryExit = true;
  ll.LatLng _center = const ll.LatLng(28.6139, 77.2090);
  StreamSubscription<GeofenceAlert>? _alertSub;

  final List<String> _quickNames = ['Home 🏠', 'Office 🏢', 'School 🏫', 'Gym 🏋️', 'Shop 🛍️'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    final pos = trackingService.current;
    if (pos != null) {
      _center = ll.LatLng(pos.latitude, pos.longitude);
    } else {
      final existing = GeofenceService().currentGeofence;
      if (existing != null) {
        _center = ll.LatLng(existing.latitude, existing.longitude);
      }
    }

    // Immediately fetch real GPS location so SafeZone centers where user actually is
    trackingService.initCurrentLocation(forceRefresh: true).then((p) {
      if (p != null && mounted) {
        setState(() {
          _center = ll.LatLng(p.latitude, p.longitude);
        });
        if (_isMapReady) {
          try {
            _mapController.move(_center, 15.5);
          } catch (_) {}
        }
        GeofenceService().checkLocation(p);
      }
    });

    // Listen for geofence entry/exit alerts to display instant prominent popups
    _alertSub = GeofenceService().alertStream.listen((alert) {
      if (!mounted) return;
      _showLiveAlertPopup(alert);
    });
  }

  void _showLiveAlertPopup(GeofenceAlert alert) {
    AlertSoundService.playAlertSound();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(22),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: alert.isEntry
                    ? AppColors.success.withValues(alpha: 0.15)
                    : const Color(0xFFF59E0B).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                alert.isEntry ? Icons.shield_rounded : Icons.logout_rounded,
                color: alert.isEntry ? AppColors.success : const Color(0xFFF59E0B),
                size: 38,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              alert.title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.navyDark),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              alert.message,
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.3),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: alert.isEntry ? AppColors.success : const Color(0xFFF59E0B),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                minimumSize: const Size.fromHeight(44),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK Got it', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _alertSub?.cancel();
    _tabController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _saveGeofence() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a name for the geofence'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    await GeofenceService().saveGeofence(
      name: name,
      latitude: _center.latitude,
      longitude: _center.longitude,
      radiusMeters: _radius,
      notifyOnEntryExit: _notifyOnEntryExit,
    );

    final currentPos = trackingService.current;
    if (currentPos != null) {
      GeofenceService().checkLocation(currentPos);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('Geofence "$name" saved! View it in "Saved Geofences".')),
            ],
          ),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
      // Switch to the Saved Geofences tab so user can immediately see their created geofence
      _tabController.animateTo(1);
    }
  }

  void _focusGeofenceOnMap(GeofenceModel geofence) {
    setState(() {
      _center = ll.LatLng(geofence.latitude, geofence.longitude);
      _radius = geofence.radiusMeters;
      _nameController.text = geofence.name;
      _notifyOnEntryExit = geofence.notifyOnEntryExit;
    });

    GeofenceService().selectGeofence(geofence);
    _tabController.animateTo(0);

    if (_isMapReady) {
      Future.delayed(const Duration(milliseconds: 150), () {
        try {
          _mapController.move(_center, 15.0);
        } catch (_) {}
      });
    }
  }

  void _testGeofenceAlert(GeofenceModel geofence) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          final isInside = GeofenceService().isInsideGeofence(geofence.id);
          final dist = GeofenceService().distanceToGeofence(geofence.id);
          final currentPos = trackingService.current;

          return Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
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
                    margin: const EdgeInsets.only(bottom: 14),
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
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.radar_rounded, color: AppColors.primary, size: 22),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Test Safe Zone • ${geofence.name}',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.navyDark),
                          ),
                          Text(
                            'Radius: ${geofence.radiusMeters.toInt()}m • Entry & Exit Alert Simulation',
                            style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Current live status card
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isInside
                        ? AppColors.success.withValues(alpha: 0.08)
                        : const Color(0xFFF59E0B).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isInside
                          ? AppColors.success.withValues(alpha: 0.3)
                          : const Color(0xFFF59E0B).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isInside ? Icons.shield_rounded : Icons.radar_rounded,
                        color: isInside ? AppColors.success : const Color(0xFFF59E0B),
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isInside ? 'STATUS: INSIDE SAFE ZONE' : 'STATUS: OUTSIDE SAFE ZONE',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: isInside ? AppColors.success : const Color(0xFFD97706),
                              ),
                            ),
                            if (dist != null)
                              Text(
                                '${dist.toInt()}m from safe zone center',
                                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Choose a test action to trigger alerts without physically walking outside:',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                // 1. Simulate Exit Button
                ElevatedButton.icon(
                  onPressed: () {
                    GeofenceService().simulateExit(geofence.id);
                    setSheetState(() {});
                    setState(() {});
                  },
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text('Simulate Exit (Bahar Jana) • Test Exit Alert'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 10),
                // 2. Simulate Entry Button
                ElevatedButton.icon(
                  onPressed: () {
                    GeofenceService().simulateEntry(geofence.id);
                    setSheetState(() {});
                    setState(() {});
                  },
                  icon: const Icon(Icons.login_rounded, size: 18),
                  label: const Text('Simulate Entry (Wapas Aana) • Test Entry Alert'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 10),
                // 3. Reset to Live GPS
                if (currentPos != null)
                  OutlinedButton.icon(
                    onPressed: () {
                      GeofenceService().resetToRealPosition(currentPos.latitude, currentPos.longitude);
                      setSheetState(() {});
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Reset to phone\'s actual GPS location.'),
                          duration: Duration(seconds: 2),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    icon: const Icon(Icons.my_location_rounded, size: 16),
                    label: const Text('Reset to Actual Phone GPS Location'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.navyDark,
                      side: const BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _confirmDeleteGeofence(GeofenceModel geofence) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Geofence?'),
        content: Text(
          'Are you sure you want to delete "${geofence.name}"? You will no longer receive arrival/exit alerts for this zone.',
          style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await GeofenceService().deleteGeofence(geofence.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Geofence "${geofence.name}" deleted.'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([GeofenceService(), trackingService]),
      builder: (context, _) {
        final geofences = GeofenceService().geofences;
        final selected = GeofenceService().currentGeofence;
        final currentPos = trackingService.current;
        final userCoord = currentPos != null ? ll.LatLng(currentPos.latitude, currentPos.longitude) : null;

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              'Geofence Safe Zones',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            centerTitle: true,
            bottom: TabBar(
              controller: _tabController,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
              indicatorColor: AppColors.primary,
              indicatorWeight: 3,
              tabs: [
                const Tab(
                  icon: Icon(Icons.map_rounded, size: 20),
                  text: 'Map & Create',
                ),
                Tab(
                  icon: const Icon(Icons.format_list_bulleted_rounded, size: 20),
                  text: 'Saved Zones (${geofences.length})',
                ),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildMapTab(geofences, selected, userCoord),
              _buildSavedListTab(geofences),
            ],
          ),
        );
      },
    );
  }

  // ==========================================
  // TAB 1: MAP & CREATE ZONE
  // ==========================================
  Widget _buildMapTab(
    List<GeofenceModel> allGeofences,
    GeofenceModel? selected,
    ll.LatLng? userCoord,
  ) {
    final circles = <CircleMarker>[];
    final markers = <Marker>[];

    // 1. Draw all saved geofences in soft blue/grey
    for (final g in allGeofences) {
      final isCurrentSelected = (selected?.id == g.id);
      circles.add(
        CircleMarker(
          point: g.llCenter,
          radius: g.radiusMeters,
          useRadiusInMeter: true,
          color: isCurrentSelected
              ? AppColors.primary.withValues(alpha: 0.22)
              : const Color(0xFF10B981).withValues(alpha: 0.12),
          borderColor: isCurrentSelected ? AppColors.primary : const Color(0xFF10B981),
          borderStrokeWidth: isCurrentSelected ? 2.5 : 1.5,
        ),
      );

      markers.add(
        Marker(
          point: g.llCenter,
          width: 70,
          height: 48,
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isCurrentSelected ? AppColors.primary : const Color(0xFF10B981),
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                ),
                child: Text(
                  g.name,
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.location_on_rounded, color: AppColors.primary, size: 22),
            ],
          ),
        ),
      );
    }

    // 2. Active editing circle if different from saved
    circles.add(
      CircleMarker(
        point: _center,
        radius: _radius,
        useRadiusInMeter: true,
        color: AppColors.primary.withValues(alpha: 0.18),
        borderColor: AppColors.primary,
        borderStrokeWidth: 2.5,
      ),
    );

    // 3. User current position marker
    if (userCoord != null) {
      markers.add(
        Marker(
          point: userCoord,
          width: 38,
          height: 38,
          alignment: Alignment.center,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Center(
              child: Icon(Icons.my_location_rounded, color: AppColors.primary, size: 22),
            ),
          ),
        ),
      );
    }

    return Stack(
      children: [
        // FlutterMap
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _center,
            initialZoom: 15.0,
            onMapReady: () {
              if (mounted) setState(() => _isMapReady = true);
            },
            onTap: (tapPosition, point) {
              setState(() => _center = point);
            },
          ),
          children: [
            AppMapTiles.buildTileLayer(),
            CircleLayer(circles: circles),
            MarkerLayer(markers: markers),
          ],
        ),

        // Top Status Pill
        Positioned(
          top: 14,
          left: 16,
          right: 16,
          child: _buildTopStatusPill(selected),
        ),

        // Recenter on my location button
        Positioned(
          right: 16,
          top: 74,
          child: FloatingActionButton.small(
            heroTag: 'geofence_my_loc',
            backgroundColor: Colors.white,
            foregroundColor: AppColors.primary,
            elevation: 3,
            tooltip: 'Center on My Location',
            onPressed: () async {
              var pos = trackingService.current;
              pos ??= await trackingService.initCurrentLocation(forceRefresh: true);
              if (pos != null && mounted) {
                setState(() => _center = ll.LatLng(pos!.latitude, pos.longitude));
                if (_isMapReady) {
                  try {
                    _mapController.move(_center, 15.5);
                  } catch (_) {}
                }
                GeofenceService().checkLocation(pos);
              }
            },
            child: const Icon(Icons.my_location_rounded, size: 20),
          ),
        ),

        // Bottom Geofence Setup Form Card
        Positioned(
          bottom: 14,
          left: 16,
          right: 16,
          child: _buildBottomCreateCard(),
        ),
      ],
    );
  }

  Widget _buildTopStatusPill(GeofenceModel? selected) {
    if (selected == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Row(
          children: [
            Icon(Icons.touch_app_rounded, size: 18, color: AppColors.primary),
            SizedBox(width: 8),
            Text(
              'Tap anywhere on the map to set zone center',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppColors.navyDark),
            ),
          ],
        ),
      );
    }

    final isInside = GeofenceService().isInsideGeofence(selected.id);
    final distance = GeofenceService().distanceToGeofence(selected.id);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: isInside ? AppColors.success : AppColors.warning,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isInside ? 'Device is INSIDE "${selected.name}"' : 'Device is OUTSIDE "${selected.name}"',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isInside ? AppColors.success : const Color(0xFFD97706),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (distance != null)
            Text(
              '${distance.toStringAsFixed(0)}m away',
              style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomCreateCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Quick Name Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _quickNames.map((q) {
                final clean = q.split(' ').first;
                final isSelected = _nameController.text.trim().toLowerCase() == clean.toLowerCase();
                return Padding(
                  padding: const EdgeInsets.only(right: 6.0),
                  child: ChoiceChip(
                    label: Text(q, style: const TextStyle(fontSize: 11.5)),
                    selected: isSelected,
                    selectedColor: AppColors.primaryLight,
                    onSelected: (_) {
                      setState(() => _nameController.text = clean);
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 10),

          // Name Input
          TextField(
            controller: _nameController,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              labelText: 'Zone Name',
              hintText: 'e.g. Home, Office, Gym',
              prefixIcon: const Icon(Icons.label_outline_rounded, color: AppColors.primary, size: 20),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),

          const SizedBox(height: 10),

          // Radius Slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Radius / Boundary:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${_radius.round()} meters',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: AppColors.tileBackground,
              thumbColor: AppColors.primary,
              trackHeight: 3.5,
            ),
            child: Slider(
              min: 50,
              max: 2000,
              divisions: 39,
              value: _radius,
              onChanged: (val) => setState(() => _radius = val),
            ),
          ),

          // Notification Toggle
          Row(
            children: [
              const Icon(Icons.notifications_active_outlined, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Notify when device enters or leaves',
                  style: TextStyle(fontSize: 12, color: AppColors.textPrimary),
                ),
              ),
              Switch(
                value: _notifyOnEntryExit,
                activeColor: AppColors.primary,
                onChanged: (val) => setState(() => _notifyOnEntryExit = val),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Save Button
          ElevatedButton.icon(
            onPressed: _saveGeofence,
            icon: const Icon(Icons.add_location_alt_rounded, size: 18),
            label: const Text('Save Safe Zone', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 2: SAVED GEOFENCES LIST
  // ==========================================
  Widget _buildSavedListTab(List<GeofenceModel> geofences) {
    if (geofences.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: Color(0xFFEFF6FF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.radar_rounded, color: AppColors.primary, size: 36),
              ),
              const SizedBox(height: 16),
              const Text(
                'No Geofences Created Yet',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.navyDark),
              ),
              const SizedBox(height: 8),
              const Text(
                'Create virtual safe perimeters around your home, office, or school to get instant entry & exit alerts.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => _tabController.animateTo(0),
                icon: const Icon(Icons.add_location_alt_rounded, size: 18),
                label: const Text('Create Safe Zone'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Top summary
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded, size: 20, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${geofences.where((g) => g.isActive).length} of ${geofences.length} geofences currently active & monitoring.',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppColors.navyDark),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // List of Geofence Cards
        ...geofences.map((g) => _buildGeofenceCard(g)),

        const SizedBox(height: 20),

        OutlinedButton.icon(
          onPressed: () => _tabController.animateTo(0),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add Another Safe Zone', style: TextStyle(fontWeight: FontWeight.bold)),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  Widget _buildGeofenceCard(GeofenceModel g) {
    final isInside = GeofenceService().isInsideGeofence(g.id);
    final distance = GeofenceService().distanceToGeofence(g.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: g.isActive ? AppColors.border : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: isInside
                      ? AppColors.success.withValues(alpha: 0.12)
                      : const Color(0xFFF59E0B).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isInside ? Icons.shield_rounded : Icons.radar_rounded,
                  color: isInside ? AppColors.success : const Color(0xFFF59E0B),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      g.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: g.isActive ? AppColors.navyDark : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Radius: ${g.radiusMeters.toInt()}m ${g.notifyOnEntryExit ? "• Alerts ON" : ""}',
                      style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Switch(
                value: g.isActive,
                activeColor: AppColors.primary,
                onChanged: (val) {
                  GeofenceService().toggleGeofenceActive(g.id, val);
                },
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Status & Distance Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isInside
                  ? AppColors.success.withValues(alpha: 0.08)
                  : const Color(0xFFF59E0B).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  isInside ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
                  size: 16,
                  color: isInside ? AppColors.success : const Color(0xFFD97706),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isInside ? 'Status: INSIDE SAFE ZONE' : 'Status: OUTSIDE ZONE',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: isInside ? AppColors.success : const Color(0xFFD97706),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (distance != null)
                  Text(
                    '${distance.toInt()}m from center',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: isInside ? AppColors.success : AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Actions Row: View on Map, Test Alert, Delete
          Row(
            children: [
              Expanded(
                flex: 3,
                child: OutlinedButton.icon(
                  onPressed: () => _focusGeofenceOnMap(g),
                  icon: const Icon(Icons.map_rounded, size: 14),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('View on Map', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(color: AppColors.primary.withValues(alpha: 0.3)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  onPressed: () => _testGeofenceAlert(g),
                  icon: const Icon(Icons.notifications_active_outlined, size: 14),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Test Alert', style: TextStyle(fontSize: 11.5)),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.navyDark,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger, size: 20),
                tooltip: 'Delete Geofence',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: () => _confirmDeleteGeofence(g),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
