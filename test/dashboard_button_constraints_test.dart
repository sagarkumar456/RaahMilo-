import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackmyphone/core/app_colors.dart';
import 'package:trackmyphone/core/app_theme.dart';

void main() {
  testWidgets('OutlinedButton and ElevatedButton inside Row layout cleanly without infinite width constraints', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onPressed: () {},
                    icon: const Icon(Icons.map_rounded, size: 16),
                    label: const Text('View on Map'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.danger),
                    foregroundColor: AppColors.danger,
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  onPressed: () {},
                  icon: const Icon(Icons.notifications_active_rounded, size: 16),
                  label: const Text('Ring'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('View on Map'), findsOneWidget);
    expect(find.text('Ring'), findsOneWidget);
  });

  testWidgets('Device status row with long last seen and battery does not overflow 360px screen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SizedBox(
            width: 250, // Constrained container simulating device card
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    'Last seen Today at 10:45:20 PM',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Text(' • ', style: TextStyle(color: AppColors.textMuted)),
                const Icon(
                  Icons.battery_charging_full_rounded,
                  size: 13,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 2),
                const Text(
                  '85%',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('85%'), findsOneWidget);
  });
}
