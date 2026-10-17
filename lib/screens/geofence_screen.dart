import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../core/app_colors.dart';
import '../services/geofence_service.dart';
import '../services/tracking_service.dart';

class GeofenceScreen extends StatefulWidget {
  const GeofenceScreen({super.key});

  @override
  State<GeofenceScreen> createState() => _GeofenceScreenState();
}

class _GeofenceScreenState extends State<GeofenceScreen> {
  GoogleMapController? _mapController;
  final _nameController = TextEditingController(text: 'Home');
  double _radius = 500.0;
  bool _notifyOnEntryExit = true;
  LatLng _center = const LatLng(28.6139, 77.2090);

  @override
  void initState() {
    super.initState();
    final existing = GeofenceService().currentGeofence;
    if (existing != null) {
      _nameController.text = existing.name;
      _radius = existing.radiusMeters;
      _notifyOnEntryExit = existing.notifyOnEntryExit;
      _center = existing.center;
    } else {
      final pos = trackingService.current;
      if (pos != null) {
        _center = LatLng(pos.latitude, pos.longitude);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _saveGeofence() {
    GeofenceService().saveGeofence(
      name: _nameController.text.trim(),
      latitude: _center.latitude,
      longitude: _center.longitude,
      radiusMeters: _radius,
      notifyOnEntryExit: _notifyOnEntryExit,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Geofence "${_nameController.text}" saved successfully!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([GeofenceService(), trackingService]),
      builder: (context, _) {
        final circles = <Circle>{
          Circle(
            circleId: const CircleId('geofence_circle'),
            center: _center,
            radius: _radius,
            fillColor: AppColors.primary.withValues(alpha: 0.15),
            strokeColor: AppColors.primary,
            strokeWidth: 2,
          ),
        };

        final markers = <Marker>{
          Marker(
            markerId: const MarkerId('geofence_center'),
            position: _center,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
            infoWindow: InfoWindow(title: _nameController.text),
          ),
        };

        final isInside = GeofenceService().isInside;
        final distance = GeofenceService().lastDistance;

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text('Geofence'),
            actions: [
              IconButton(
                icon: const Icon(Icons.my_location_rounded),
                onPressed: () {
                  final pos = trackingService.current;
                  if (pos != null) {
                    setState(() => _center = LatLng(pos.latitude, pos.longitude));
                    _mapController?.animateCamera(
                      CameraUpdate.newLatLng(_center),
                    );
                  }
                },
              ),
            ],
          ),
          body: Stack(
            children: [
              // 1. Google Map with Circle and Pin
              GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: _center,
                  zoom: 14.8,
                ),
                circles: circles,
                markers: markers,
                zoomControlsEnabled: false,
                myLocationButtonEnabled: false,
                onTap: (tappedLocation) {
                  setState(() => _center = tappedLocation);
                },
                onMapCreated: (ctrl) => _mapController = ctrl,
              ),

              // Status pill at top
              Positioned(
                top: 16,
                left: 20,
                right: 20,
                child: Container(
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
                      Text(
                        isInside ? 'Device is INSIDE the zone' : 'Device is OUTSIDE the zone',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isInside ? AppColors.success : AppColors.warning,
                        ),
                      ),
                      const Spacer(),
                      if (distance != null)
                        Text(
                          '${distance.toStringAsFixed(0)}m away',
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                    ],
                  ),
                ),
              ),

              // 2. Bottom Geofence Setup Card matching Screen 12
              Positioned(
                bottom: 20,
                left: 16,
                right: 16,
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
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Radius Row with Slider
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Radius: ${_radius.round()} meters',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppColors.navyDark,
                            ),
                          ),
                          Text(
                            '${_radius.round()} m',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: AppColors.primary,
                          inactiveTrackColor: AppColors.tileBackground,
                          thumbColor: AppColors.primary,
                          trackHeight: 4,
                        ),
                        child: Slider(
                          min: 100,
                          max: 2000,
                          divisions: 19,
                          value: _radius,
                          onChanged: (val) => setState(() => _radius = val),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Zone Name
                      const Text(
                        'Name',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          hintText: 'e.g. Home, Office, School',
                          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 14),
                      // Toggle: Get notifications when device enters or leaves
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Get notifications when device enters or leaves this area',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textPrimary,
                                height: 1.3,
                              ),
                            ),
                          ),
                          Switch(
                            value: _notifyOnEntryExit,
                            activeColor: AppColors.primary,
                            onChanged: (val) => setState(() => _notifyOnEntryExit = val),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // "Save Geofence" Button
                      ElevatedButton(
                        onPressed: _saveGeofence,
                        child: const Text(
                          'Save Geofence',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
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
