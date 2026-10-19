import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/app_colors.dart';
import '../models/vehicle_type.dart';
import '../services/tracking_service.dart';

class MapCalendarBar extends StatelessWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;
  final VehicleType? vehicleFilter;
  final bool isLiveActive;
  final VoidCallback onLiveTapped;

  const MapCalendarBar({
    super.key,
    required this.selectedDate,
    required this.onDateSelected,
    this.vehicleFilter,
    required this.isLiveActive,
    required this.onLiveTapped,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    // Build list of last 14 days
    final days = List.generate(14, (i) {
      final d = now.subtract(Duration(days: i));
      return DateTime(d.year, d.month, d.day);
    });

    return Container(
      height: 78,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Live / Today quick button
          _buildLiveButton(context),

          const VerticalDivider(width: 1, indent: 12, endIndent: 12, color: AppColors.border),

          // Horizontal Date Ribbon with KM under each date
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              scrollDirection: Axis.horizontal,
              itemCount: days.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final date = days[index];
                final isSelected = !isLiveActive &&
                    selectedDate.year == date.year &&
                    selectedDate.month == date.month &&
                    selectedDate.day == date.day;

                final km = trackingService.getDistanceForDate(
                  date,
                  vehicleFilter: vehicleFilter,
                );

                final kmStr = km > 0
                    ? (km >= 10 ? '${km.toStringAsFixed(0)} km' : '${km.toStringAsFixed(1)} km')
                    : '0 km';

                final isToday = now.year == date.year &&
                    now.month == date.month &&
                    now.day == date.day;

                return GestureDetector(
                  onTap: () => onDateSelected(date),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 58,
                    padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary
                          : (km > 0
                              ? AppColors.primary.withValues(alpha: 0.08)
                              : AppColors.tileBackground),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary
                            : (km > 0
                                ? AppColors.primary.withValues(alpha: 0.3)
                                : Colors.transparent),
                        width: 1.2,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isToday ? 'Today' : DateFormat('EEE').format(date),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isSelected
                                ? Colors.white70
                                : (isToday ? AppColors.primary : AppColors.textSecondary),
                          ),
                        ),
                        Text(
                          '${date.day}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: isSelected ? Colors.white : AppColors.textPrimary,
                          ),
                        ),
                        // Distance KM directly under the date
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.white.withValues(alpha: 0.22)
                                : (km > 0 ? AppColors.primary.withValues(alpha: 0.15) : Colors.transparent),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            kmStr,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: km > 0 ? FontWeight.bold : FontWeight.w500,
                              color: isSelected
                                  ? Colors.white
                                  : (km > 0 ? AppColors.primary : AppColors.textMuted),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          const VerticalDivider(width: 1, indent: 12, endIndent: 12, color: AppColors.border),

          // Open Full Month Calendar Dialog Button
          IconButton(
            tooltip: 'Month Calendar with KM',
            icon: const Icon(Icons.calendar_month_rounded, color: AppColors.primary, size: 24),
            onPressed: () => _openMonthCalendarSheet(context),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveButton(BuildContext context) {
    return GestureDetector(
      onTap: onLiveTapped,
      child: Container(
        width: 58,
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: isLiveActive ? AppColors.success : AppColors.tileBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isLiveActive ? AppColors.success : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.my_location_rounded,
              size: 16,
              color: isLiveActive ? Colors.white : AppColors.textSecondary,
            ),
            const SizedBox(height: 2),
            Text(
              'LIVE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
                color: isLiveActive ? Colors.white : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              'Track',
              style: TextStyle(
                fontSize: 9,
                color: isLiveActive ? Colors.white70 : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openMonthCalendarSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MapMonthlyCalendarSheet(
        initialDate: selectedDate,
        vehicleFilter: vehicleFilter,
        onDateSelected: (date) {
          Navigator.pop(context);
          onDateSelected(date);
        },
      ),
    );
  }
}

class MapMonthlyCalendarSheet extends StatefulWidget {
  final DateTime initialDate;
  final VehicleType? vehicleFilter;
  final ValueChanged<DateTime> onDateSelected;

  const MapMonthlyCalendarSheet({
    super.key,
    required this.initialDate,
    this.vehicleFilter,
    required this.onDateSelected,
  });

  @override
  State<MapMonthlyCalendarSheet> createState() => _MapMonthlyCalendarSheetState();
}

class _MapMonthlyCalendarSheetState extends State<MapMonthlyCalendarSheet> {
  late DateTime _displayedMonth;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _displayedMonth = DateTime(widget.initialDate.year, widget.initialDate.month, 1);
    _selectedDate = widget.initialDate;
  }

  void _prevMonth() {
    setState(() {
      _displayedMonth = DateTime(_displayedMonth.year, _displayedMonth.month - 1, 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _displayedMonth = DateTime(_displayedMonth.year, _displayedMonth.month + 1, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final firstDayOfMonth = DateTime(_displayedMonth.year, _displayedMonth.month, 1);
    final daysInMonth = DateTime(_displayedMonth.year, _displayedMonth.month + 1, 0).day;
    // Monday = 1, Sunday = 7
    final weekdayOffset = (firstDayOfMonth.weekday - 1); // 0 for Monday

    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_rounded, color: AppColors.primary, size: 22),
                const SizedBox(width: 8),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Trip History Calendar',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Distance (KM) traveled shown under each date',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: AppColors.border),

          // Month navigation bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded, size: 28),
                  onPressed: _prevMonth,
                ),
                Text(
                  DateFormat('MMMM yyyy').format(_displayedMonth),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navyDark,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded, size: 28),
                  onPressed: _nextMonth,
                ),
              ],
            ),
          ),

          // Weekday columns header (Mon, Tue, Wed, Thu, Fri, Sat, Sun)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
                  .map(
                    (d) => Expanded(
                      child: Center(
                        child: Text(
                          d,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 6),

          // Calendar Grid
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 6,
                crossAxisSpacing: 4,
                childAspectRatio: 0.85,
              ),
              itemCount: weekdayOffset + daysInMonth,
              itemBuilder: (context, index) {
                if (index < weekdayOffset) {
                  return const SizedBox();
                }

                final dayNum = index - weekdayOffset + 1;
                final date = DateTime(_displayedMonth.year, _displayedMonth.month, dayNum);
                final isSelected = _selectedDate.year == date.year &&
                    _selectedDate.month == date.month &&
                    _selectedDate.day == date.day;

                final isToday = now.year == date.year &&
                    now.month == date.month &&
                    now.day == date.day;

                final isFuture = date.isAfter(DateTime(now.year, now.month, now.day));

                final km = isFuture
                    ? 0.0
                    : trackingService.getDistanceForDate(
                        date,
                        vehicleFilter: widget.vehicleFilter,
                      );

                final kmText = km > 0
                    ? (km >= 10 ? '${km.toStringAsFixed(0)}km' : '${km.toStringAsFixed(1)}km')
                    : '—';

                return GestureDetector(
                  onTap: isFuture
                      ? null
                      : () {
                          setState(() => _selectedDate = date);
                          widget.onDateSelected(date);
                        },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary
                          : (km > 0
                              ? AppColors.primary.withValues(alpha: 0.1)
                              : (isFuture ? Colors.grey.shade50 : AppColors.tileBackground)),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary
                            : (isToday
                                ? AppColors.primary
                                : (km > 0
                                    ? AppColors.primary.withValues(alpha: 0.3)
                                    : Colors.transparent)),
                        width: isToday || isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$dayNum',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isSelected
                                ? Colors.white
                                : (isFuture ? Colors.grey.shade300 : AppColors.textPrimary),
                          ),
                        ),
                        const SizedBox(height: 1),
                        // Distance written directly under the date
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.white.withValues(alpha: 0.25)
                                : (km > 0 ? AppColors.primary.withValues(alpha: 0.14) : Colors.transparent),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            kmText,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: km > 0 ? FontWeight.w800 : FontWeight.w500,
                              color: isSelected
                                  ? Colors.white
                                  : (km > 0 ? AppColors.primary : AppColors.textMuted),
                            ),
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
      ),
    );
  }
}
