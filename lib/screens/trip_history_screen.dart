import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/app_colors.dart';
import '../models/trip_model.dart';
import '../models/vehicle_type.dart';
import '../services/tracking_service.dart';
import '../widgets/map_calendar_bar.dart';
import '../widgets/map_vehicle_filter_bar.dart';
import '../widgets/trip_route_painter.dart';
import 'trip_details_screen.dart';

class TripHistoryScreen extends StatefulWidget {
  const TripHistoryScreen({super.key});

  @override
  State<TripHistoryScreen> createState() => _TripHistoryScreenState();
}

class _TripHistoryScreenState extends State<TripHistoryScreen> {
  String _selectedFilter = 'All';
  DateTime? _specificDate;
  VehicleType? _selectedVehicle;
  final List<String> _filters = ['All', 'Today', 'This Week', 'This Month'];

  @override
  void initState() {
    super.initState();
    trackingService.loadHistory();
  }

  List<TripModel> _filterTrips(List<TripModel> allTrips) {
    var list = allTrips;
    if (_selectedVehicle != null) {
      list = list.where((t) => t.vehicleTypeEnum == _selectedVehicle).toList();
    }
    if (_specificDate != null) {
      return list.where((t) =>
        t.startedAt.year == _specificDate!.year &&
        t.startedAt.month == _specificDate!.month &&
        t.startedAt.day == _specificDate!.day
      ).toList();
    }
    if (_selectedFilter == 'All') return list;
    final now = DateTime.now();
    return list.where((t) {
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

  void _openCalendarPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MapMonthlyCalendarSheet(
        initialDate: _specificDate ?? DateTime.now(),
        vehicleFilter: _selectedVehicle,
        onDateSelected: (date) {
          Navigator.pop(context);
          setState(() {
            _specificDate = date;
            _selectedFilter = DateFormat('dd MMM').format(date);
          });
        },
      ),
    );
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
                icon: const Icon(Icons.refresh_rounded, size: 22),
                tooltip: 'Refresh History',
                onPressed: () => trackingService.loadHistory(),
              ),
              IconButton(
                icon: const Icon(Icons.calendar_month_rounded, size: 22, color: AppColors.primary),
                tooltip: 'View Calendar with KM',
                onPressed: _openCalendarPicker,
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () => trackingService.loadHistory(),
            color: AppColors.primary,
            child: Column(
              children: [
                const SizedBox(height: 8),
                // Vehicle Mode Filter Bar
                MapVehicleFilterBar(
                  selectedVehicle: _selectedVehicle ?? VehicleType.car,
                  showAllOption: true,
                  isAllSelected: _selectedVehicle == null,
                  onAllSelected: () => setState(() => _selectedVehicle = null),
                  onVehicleSelected: (v) => setState(() => _selectedVehicle = v),
                ),
                const SizedBox(height: 10),
                // Time Range Filter Pills Row
                SizedBox(
                  height: 38,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    children: [
                      if (_specificDate != null) ...[
                        GestureDetector(
                          onTap: () => setState(() {
                            _specificDate = null;
                            _selectedFilter = 'All';
                          }),
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  DateFormat('dd MMM').format(_specificDate!),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.close, size: 14, color: Colors.white),
                              ],
                            ),
                          ),
                        ),
                      ],
                      ..._filters.map((filter) {
                        final isSelected = _specificDate == null && filter == _selectedFilter;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () => setState(() {
                              _specificDate = null;
                              _selectedFilter = filter;
                            }),
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
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                // Trips List
                Expanded(
                  child: trips.isEmpty
                      ? ListView(
                          children: [
                            SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                            Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.route_rounded, size: 64, color: Colors.grey.shade300),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'No trips recorded yet',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'Start live tracking to record trips automatically',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
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
          ),
        );
      },
    );
  }

  Widget _tripCard(TripModel trip) {
    return Dismissible(
      key: Key(trip.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.danger,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 26),
      ),
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
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
      },
      onDismissed: (_) {
        trackingService.deleteTrip(trip.id);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Trip deleted from history')),
        );
      },
      child: InkWell(
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
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: trip.vehicleTypeEnum.color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(trip.vehicleTypeEnum.icon, size: 12, color: trip.vehicleTypeEnum.color),
                              const SizedBox(width: 4),
                              Text(
                                trip.vehicleTypeEnum.displayName,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: trip.vehicleTypeEnum.color,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            trip.formattedDate,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
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
      ),
    );
  }
}
