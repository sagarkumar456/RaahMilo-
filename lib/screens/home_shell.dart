import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../core/app_colors.dart';
import '../services/anti_theft_service.dart';
import '../services/notification_service.dart';
import 'anti_theft_screen.dart';
import 'dashboard_screen.dart';
import 'live_map_screen.dart';
import 'location_disabled_screen.dart';
import 'trip_history_screen.dart';
import 'profile_screen.dart';
import 'notifications_screen.dart';

class HomeShell extends StatefulWidget {
  final int initialTab;

  const HomeShell({super.key, this.initialTab = 0});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  late int _selectedTab;
  StreamSubscription<ServiceStatus>? _serviceStatusSub;
  bool _isLocationSheetShowing = false;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
    WidgetsBinding.instance.addObserver(this);
    _listenForLocationService();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLocationServiceStatus();
    });
  }

  @override
  void dispose() {
    _serviceStatusSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _listenForLocationService() {
    _serviceStatusSub = Geolocator.getServiceStatusStream().listen((status) {
      if (status == ServiceStatus.disabled) {
        _showLocationDisabledScreen();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkLocationServiceStatus();
    }
  }

  Future<void> _checkLocationServiceStatus() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled && mounted) {
      _showLocationDisabledScreen();
    }
  }

  void _showLocationDisabledScreen() {
    if (_isLocationSheetShowing || !mounted) return;
    _isLocationSheetShowing = true;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const LocationDisabledScreen(),
        fullscreenDialog: true,
      ),
    ).then((_) {
      _isLocationSheetShowing = false;
    });
  }

  void _switchTab(int index) {
    setState(() => _selectedTab = index);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([NotificationService(), antiTheftService]),
      builder: (context, _) {
        final unreadCount = NotificationService().unreadCount;
        final isAlarmActive = antiTheftService.isAlarmActive;

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            SystemNavigator.pop();
          },
          child: Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/images/logo_pin.png',
                    height: 26,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'RaahMilo',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.navyDark,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
              automaticallyImplyLeading: false,
              actions: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.notifications_none_rounded, size: 26),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                        );
                      },
                    ),
                    if (unreadCount > 0)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: AppColors.danger,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          child: Text(
                            '$unreadCount',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 8),
              ],
            ),
            body: Column(
              children: [
                if (isAlarmActive)
                  InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AntiTheftScreen()),
                      );
                    },
                    child: Container(
                      width: double.infinity,
                      color: AppColors.danger,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 22),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              '🚨 THEFT ALARM! Vehicle moved.',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: AppColors.danger,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              minimumSize: const Size(60, 28),
                            ),
                            onPressed: () => antiTheftService.silenceAlarm(),
                            child: const Text('Silence', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: IndexedStack(
                    index: _selectedTab,
                    children: [
                      DashboardScreen(onNavigateTab: _switchTab),
                      const LiveMapScreen(),
                      const TripHistoryScreen(),
                      const ProfileScreen(),
                    ],
                  ),
                ),
              ],
            ),
            bottomNavigationBar: Container(
              decoration: const BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Color(0x0F000000),
                    blurRadius: 10,
                    offset: Offset(0, -3),
                  ),
                ],
              ),
              child: NavigationBar(
                selectedIndex: _selectedTab,
                onDestinationSelected: _switchTab,
                backgroundColor: Colors.white,
                elevation: 0,
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home_rounded),
                    label: 'Home',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.map_outlined),
                    selectedIcon: Icon(Icons.map_rounded),
                    label: 'Map',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.history_rounded),
                    selectedIcon: Icon(Icons.history_rounded),
                    label: 'History',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.person_outline_rounded),
                    selectedIcon: Icon(Icons.person_rounded),
                    label: 'Profile',
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
