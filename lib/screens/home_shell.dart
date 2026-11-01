import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../core/app_colors.dart';
import '../services/alert_sound_service.dart';
import '../services/geofence_service.dart';
import '../services/notification_service.dart';
import '../services/tracking_service.dart';
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
  StreamSubscription<GeofenceAlert>? _geofenceAlertSub;
  Timer? _healthTimer;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
    WidgetsBinding.instance.addObserver(this);
    _listenForLocationService();
    _listenForGeofenceAlerts();
    _healthTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) {
        trackingService.checkLocationHealth(autoStart: true);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      trackingService.checkLocationHealth(autoStart: true);
    });
  }

  @override
  void dispose() {
    _serviceStatusSub?.cancel();
    _geofenceAlertSub?.cancel();
    _healthTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _listenForGeofenceAlerts() {
    _geofenceAlertSub = GeofenceService().alertStream.listen((alert) {
      if (!mounted) return;
      AlertSoundService.playAlertSound();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                alert.isEntry ? Icons.login_rounded : Icons.logout_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      alert.title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    Text(
                      alert.message,
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          backgroundColor: alert.isEntry ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    });
  }

  void _listenForLocationService() {
    _serviceStatusSub = Geolocator.getServiceStatusStream().listen((status) {
      if (!mounted) return;
      trackingService.checkLocationHealth(autoStart: status == ServiceStatus.enabled);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      trackingService.checkLocationHealth(autoStart: true);
    }
  }

  void _switchTab(int index) {
    setState(() => _selectedTab = index);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: NotificationService(),
      builder: (context, _) {
        final unreadCount = NotificationService().unreadCount;

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            // Only exit app if HomeShell itself is currently the top/active route
            if (ModalRoute.of(context)?.isCurrent ?? true) {
              SystemNavigator.pop();
            }
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
                AnimatedBuilder(
                  animation: trackingService,
                  builder: (context, _) {
                    final isGpsOn = trackingService.isLocationServiceEnabled && trackingService.hasLocationPermission;
                    if (isGpsOn) return const SizedBox.shrink();

                    return Material(
                      color: AppColors.danger,
                      child: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LocationDisabledScreen(),
                              fullscreenDialog: true,
                            ),
                          ).then((res) {
                            if (res == true) {
                              trackingService.checkLocationHealth(autoStart: true);
                            }
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          child: Row(
                            children: [
                              const Icon(Icons.location_off_rounded, color: Colors.white, size: 18),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'Location is disabled. Tap to enable live tracking.',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'Enable',
                                  style: TextStyle(
                                    color: AppColors.danger,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                Expanded(
                  child: IndexedStack(
                    index: _selectedTab,
                    children: [
                      DashboardScreen(onNavigateTab: _switchTab),
                      LiveMapScreen(isActiveTab: _selectedTab == 1),
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
