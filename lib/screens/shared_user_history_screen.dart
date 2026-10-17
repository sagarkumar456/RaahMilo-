import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../core/app_colors.dart';
import '../models/shared_device_model.dart';
import '../models/trip_model.dart';
import '../services/share_service.dart';
import '../widgets/pulse_indicator.dart';
import '../widgets/trip_route_painter.dart';
import 'shared_device_map_screen.dart';
import 'trip_details_screen.dart';

class SharedUserHistoryScreen extends StatefulWidget {
  final SharedDeviceModel sharedDevice;

  const SharedUserHistoryScreen({
    super.key,
    required this.sharedDevice,
  });

  @override
  State<SharedUserHistoryScreen> createState() => _SharedUserHistoryScreenState();
}

class _SharedUserHistoryScreenState extends State<SharedUserHistoryScreen> {
  String _selectedFilter = 'All';
  final List<String> _filters = ['All', 'Today', 'This Week', 'This Month'];

  List<TripModel> _filterTrips(List<TripModel> allTrips) {
    if (_selectedFilter == 'All') return allTrips;
    final now = DateTime.now();
    return allTrips.where((t) {
      final diff = now.difference(t.startedAt);
      if (_selectedFilter == 'Today') {
        return diff.inHours < 24 && t.startedAt.day == now.day;
      } else if (_selectedFilter == 'This Week') {
        return diff.inDays <= 7;
      } else if (_selectedFilter == 'This Month') {
        return diff.inDays <= 30;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SharedDeviceModel?>(
      stream: shareService.streamSingleShare(widget.sharedDevice.id),
      initialData: widget.sharedDevice,
      builder: (context, devSnap) {
        final dev = devSnap.data ?? widget.sharedDevice;

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            title: Text(
              '${dev.ownerName}\'s Location',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            actions: [
              IconButton(
                tooltip: 'Live Map',
                icon: const Icon(Icons.map_rounded, color: AppColors.primary),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SharedDeviceMapScreen(initialDevice: dev),
                    ),
                  );
                },
              ),
            ],
          ),
          body: Column(
            children: [
              // 1. Current Live Status Header Card
              _buildLiveHeaderCard(dev),

              const SizedBox(height: 12),

              // 2. Filter Pills for Location History
              SizedBox(
                height: 38,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: _filters.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final filter = _filters[index];
                    final isSelected = filter == _selectedFilter;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedFilter = filter),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.primary : AppColors.tileBackground,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Center(
                          child: Text(
                            filter,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              color: isSelected ? Colors.white : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 12),

              // 3. Location History Stream
              Expanded(
                child: _buildTripsStream(dev),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLiveHeaderCard(SharedDeviceModel dev) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: dev.isActive ? AppColors.primary.withValues(alpha: 0.35) : AppColors.border,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.primaryLight,
                child: Text(
                  dev.ownerName.isNotEmpty ? dev.ownerName[0].toUpperCase() : 'U',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            dev.ownerName,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (dev.isActive) ...[
                          const PulseIndicator(size: 8, color: AppColors.success),
                          const SizedBox(width: 4),
                          const Text(
                            'Live Now',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.success,
                            ),
                          ),
                        ] else ...[
                          const Text(
                            'Offline',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dev.ownerEmail,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${dev.speedKmh.toStringAsFixed(0)} km/h',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Current Address Pill
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.tileBackground,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_on_rounded, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    dev.address,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Action Button: Open Live Map
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SharedDeviceMapScreen(initialDevice: dev),
                ),
              );
            },
            icon: const Icon(Icons.map_rounded, size: 18),
            label: Text('Track ${dev.ownerName} Live on Map'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTripsStream(SharedDeviceModel dev) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('trips')
          .where('ownerId', isEqualTo: dev.ownerId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];
        final allTrips = docs.map((doc) {
          return TripModel.fromFirestore(
            doc.id,
            doc.data() as Map<String, dynamic>,
          );
        }).toList();

        // Sort descending by startedAt
        allTrips.sort((a, b) => b.startedAt.compareTo(a.startedAt));

        final trips = _filterTrips(allTrips);

        if (trips.isEmpty) {
          return _buildEmptyState(dev);
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: trips.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final trip = trips[index];
            return _tripCard(trip);
          },
        );
      },
    );
  }

  Widget _buildEmptyState(SharedDeviceModel dev) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Mini map container showing current location pin
            Container(
              height: 160,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: ll.LatLng(dev.latitude, dev.longitude),
                  initialZoom: 14.5,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.none,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.trackmyphone.app',
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: ll.LatLng(dev.latitude, dev.longitude),
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.35),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.location_on_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No past trips saved yet',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${dev.ownerName}\'s real-time live location is sharing above. When they record and complete a trip, the complete route history will appear here.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SharedDeviceMapScreen(initialDevice: dev),
                  ),
                );
              },
              icon: const Icon(Icons.gps_fixed_rounded, size: 18),
              label: const Text('View Current Live Map'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tripCard(TripModel trip) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => TripDetailsScreen(trip: trip)),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border, width: 1.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            // Route preview thumbnail
            TripRouteThumbnail(points: trip.points, size: 54),
            const SizedBox(width: 14),
            // Trip metadata
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    trip.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    trip.formattedDate,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${trip.formattedDistance} • ${trip.formattedDuration}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textMuted,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}
