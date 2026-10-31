import 'package:flutter/material.dart';
import '../models/vehicle_type.dart';

class MapVehicleFilterBar extends StatelessWidget {
  final VehicleType selectedVehicle;
  final ValueChanged<VehicleType> onVehicleSelected;
  final bool showAllOption;
  final bool isAllSelected;
  final VoidCallback? onAllSelected;

  const MapVehicleFilterBar({
    super.key,
    required this.selectedVehicle,
    required this.onVehicleSelected,
    this.showAllOption = false,
    this.isAllSelected = false,
    this.onAllSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (showAllOption)
            _buildItem(
              label: 'All',
              icon: Icons.all_inclusive_rounded,
              color: const Color(0xFF1E293B),
              isSelected: isAllSelected,
              onTap: onAllSelected ?? () {},
            ),
          _buildItem(
            label: 'Car',
            icon: Icons.directions_car_rounded,
            color: VehicleType.car.color,
            isSelected: !isAllSelected && selectedVehicle == VehicleType.car,
            onTap: () => onVehicleSelected(VehicleType.car),
          ),
          _buildItem(
            label: 'Human',
            icon: Icons.directions_walk_rounded,
            color: VehicleType.human.color,
            isSelected: !isAllSelected && selectedVehicle == VehicleType.human,
            onTap: () => onVehicleSelected(VehicleType.human),
          ),
          _buildItem(
            label: 'Scooty',
            icon: Icons.moped_rounded,
            color: VehicleType.scooty.color,
            isSelected: !isAllSelected && selectedVehicle == VehicleType.scooty,
            onTap: () => onVehicleSelected(VehicleType.scooty),
          ),
          _buildItem(
            label: 'Bike',
            icon: Icons.two_wheeler_rounded,
            color: VehicleType.bike.color,
            isSelected: !isAllSelected && selectedVehicle == VehicleType.bike,
            onTap: () => onVehicleSelected(VehicleType.bike),
          ),
        ],
      ),
    );
  }

  Widget _buildItem({
    required String label,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.35),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected ? Colors.white : Colors.grey.shade700,
              ),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                    color: isSelected ? Colors.white : Colors.grey.shade700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
