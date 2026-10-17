import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../models/trip_model.dart';
import '../services/tracking_service.dart';
import '../widgets/trip_route_painter.dart';
import 'trip_details_screen.dart';

class TripHistoryScreen extends StatefulWidget {
  const TripHistoryScreen({super.key});

  @override
  State<TripHistoryScreen> createState() => _TripHistoryScreenState();
}

class _TripHistoryScreenState extends State<TripHistoryScreen> {
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
    return AnimatedBuilder(
      animation: trackingService,
      builder: (context, _) {
        final trips = _filterTrips(trackingService.historyTrips);

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            title: const Text('Trip History'),
            actions: [
              IconButton(
                icon: const Icon(Icons.calendar_today_outlined, size: 20),
                onPressed: () {
                  showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2024),
                    lastDate: DateTime.now(),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.filter_list_rounded, size: 22),
                onPressed: () {},
              ),
            ],
          ),
          body: Column(
            children: [
              const SizedBox(height: 8),
              // Filter pills row
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
              const SizedBox(height: 14),
              // Trips List
              Expanded(
                child: trips.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.route_rounded, size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            const Text(
                              'No trips in this period',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: trips.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final trip = trips[index];
                          return _tripCard(trip);
                        },
                      ),
              ),
            ],
          ),
        );
      },
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
