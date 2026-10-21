import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../core/app_colors.dart';

class LocationDisabledScreen extends StatefulWidget {
  final VoidCallback? onLocationEnabled;

  const LocationDisabledScreen({super.key, this.onLocationEnabled});

  @override
  State<LocationDisabledScreen> createState() => _LocationDisabledScreenState();
}

class _LocationDisabledScreenState extends State<LocationDisabledScreen>
    with WidgetsBindingObserver {
  StreamSubscription<ServiceStatus>? _serviceStatusSub;
  bool _isProcessing = false;
  bool _isDismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listenToServiceStatus();
  }

  @override
  void dispose() {
    _isDismissed = true;
    _serviceStatusSub?.cancel();
    _serviceStatusSub = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _listenToServiceStatus() {
    _serviceStatusSub = Geolocator.getServiceStatusStream().listen((status) async {
      if (status == ServiceStatus.enabled && mounted && !_isDismissed) {
        _handleLocationRestored();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isDismissed) {
      _checkLocationOnResume();
    }
  }

  Future<void> _checkLocationOnResume() async {
    if (_isDismissed || !mounted) return;
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (enabled && mounted && !_isDismissed) {
      _handleLocationRestored();
    }
  }

  void _handleLocationRestored() {
    if (_isDismissed || !mounted) return;
    _isDismissed = true;
    _serviceStatusSub?.cancel();
    _serviceStatusSub = null;

    widget.onLocationEnabled?.call();

    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop(true);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text('Location services enabled!'),
          ],
        ),
        backgroundColor: AppColors.success,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _safeClose() {
    if (_isDismissed || !mounted) return;
    _isDismissed = true;
    _serviceStatusSub?.cancel();
    _serviceStatusSub = null;
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop(false);
    }
  }

  Future<void> _enableLocation() async {
    if (_isProcessing || _isDismissed) return;
    setState(() => _isProcessing = true);

    try {
      final isServiceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!isServiceEnabled) {
        // Direct the user straight to device Location Settings page
        await Geolocator.openLocationSettings();
      }

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
      }

      final nowEnabled = await Geolocator.isLocationServiceEnabled();
      if (nowEnabled && mounted && !_isDismissed) {
        _handleLocationRestored();
      }
    } catch (e) {
      debugPrint('Error enabling location: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _openAppSettings() async {
    await Geolocator.openAppSettings();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isProcessing,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _safeClose();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppColors.navyDark),
            onPressed: _safeClose,
          ),
          centerTitle: true,
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
                fontSize: 20,
                color: AppColors.navyDark,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 10),

              // 1. Center 3D Isometric Map Illustration with Disabled Badge
              _buildLocationIllustration(),

              const SizedBox(height: 16),

              // 2. Heading
              const Text(
                'Location is turned off',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navyDark,
                  letterSpacing: -0.4,
                ),
              ),

              const SizedBox(height: 8),

              // Subtitle
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10.0),
                child: Text(
                  'RaahMilo needs location services enabled to provide live tracking, route history, and accurate location sharing.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: AppColors.textSecondary.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // 3. Feature Benefit Cards Container
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FBFF),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFE4EDFB), width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0066FF).withValues(alpha: 0.03),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _benefitTile(
                      icon: Icons.wifi_tethering_rounded,
                      iconBg: const Color(0xFFE8F1FF),
                      iconColor: const Color(0xFF2563EB),
                      title: 'Live Tracking',
                      subtitle: 'Share your real-time location with friends and family.',
                    ),
                    const Divider(height: 24, thickness: 1, color: Color(0xFFEDF2F9)),
                    _benefitTile(
                      icon: Icons.alt_route_rounded,
                      iconBg: const Color(0xFFE6F9F2),
                      iconColor: const Color(0xFF10B981),
                      title: 'Route History',
                      subtitle: 'View and save your past journeys automatically.',
                    ),
                    const Divider(height: 24, thickness: 1, color: Color(0xFFEDF2F9)),
                    _benefitTile(
                      icon: Icons.notifications_active_outlined,
                      iconBg: const Color(0xFFFFF0E6),
                      iconColor: const Color(0xFFF97316),
                      title: 'Accurate Alerts',
                      subtitle: 'Get timely alerts and notifications based on your location.',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 26),

              // 4. Primary Gradient Button: "Enable Location"
              Container(
                height: 52,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0066FF), Color(0xFF00D287)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0066FF).withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: _isProcessing ? null : _enableLocation,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                  ),
                  child: _isProcessing
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.location_on_rounded, color: Colors.white, size: 20),
                            SizedBox(width: 10),
                            Text(
                              'Enable Location',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.2,
                              ),
                            ),
                            SizedBox(width: 10),
                            Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
                          ],
                        ),
                ),
              ),

              const SizedBox(height: 12),

              // 5. Outlined Button: "Open Settings"
              SizedBox(
                height: 48,
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _openAppSettings,
                  icon: const Icon(Icons.settings_outlined, size: 19, color: Color(0xFF1E293B)),
                  label: const Text(
                    'Open Settings',
                    style: TextStyle(
                      color: Color(0xFF1E293B),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFCFE0FC), width: 1.2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                ),
              ),

              const SizedBox(height: 6),

              // 6. Text Button: "Maybe Later"
              TextButton(
                onPressed: _safeClose,
                child: const Text(
                  'Maybe Later',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // 7. Footer divider with disclaimer
              Row(
                children: [
                  const Expanded(child: Divider(color: Color(0xFFE2E8F0))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFF94A3B8)),
                        SizedBox(width: 5),
                        Text(
                          'You can enable it anytime from phone settings.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF94A3B8),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Expanded(child: Divider(color: Color(0xFFE2E8F0))),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    ),
  );
}

  Widget _buildLocationIllustration() {
    return SizedBox(
      height: 220,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Radial glow background
          Container(
            width: 250,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF007BFF).withValues(alpha: 0.14),
                  const Color(0xFF00D287).withValues(alpha: 0.08),
                  Colors.transparent,
                ],
                stops: const [0.2, 0.6, 1.0],
              ),
            ),
          ),

          // Isometric 3D Map Base
          Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.002)
              ..rotateX(0.72)
              ..rotateZ(-0.35),
            child: Container(
              width: 175,
              height: 140,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFD3E5FD), width: 3),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0066FF).withValues(alpha: 0.16),
                    blurRadius: 24,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(21),
                child: Stack(
                  children: [
                    // Green terrain patch
                    Positioned(
                      top: 10,
                      left: 10,
                      right: 15,
                      height: 50,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFE6F7F0),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    // Light blue terrain patch
                    Positioned(
                      bottom: 15,
                      left: 15,
                      right: 20,
                      height: 48,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFEBF3FF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    // White Roads
                    Positioned(
                      top: 0,
                      bottom: 0,
                      left: 65,
                      width: 14,
                      child: Container(color: Colors.white),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 55,
                      height: 14,
                      child: Container(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Big 3D Pin with Red Disabled Badge
          Positioned(
            top: 22,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // Pin ground shadow
                Positioned(
                  bottom: -6,
                  child: Container(
                    width: 34,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),

                // Teardrop Pin Shape
                SizedBox(
                  width: 84,
                  height: 102,
                  child: CustomPaint(
                    painter: _MapPinTeardropPainter(),
                  ),
                ),

                // Red/Pink Circular Badge with Location Off Icon
                Positioned(
                  bottom: 12,
                  right: -10,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF5252), Color(0xFFE53935)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3.2),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF5252).withValues(alpha: 0.45),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.location_off_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _benefitTile({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: Icon(icon, color: iconColor, size: 22),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Custom painter that paints the glossy 3D cyan/blue gradient map pin
class _MapPinTeardropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final path = Path();
    // Center point of the circle head
    final center = Offset(w / 2, w / 2);
    final radius = w / 2;

    // Start at bottom tip
    path.moveTo(w / 2, h);
    // Curve up to right side of circle
    path.cubicTo(w * 0.78, h * 0.65, w, h * 0.45, w, radius);
    // Arc across the top of circle
    path.arcToPoint(
      Offset(0, radius),
      radius: Radius.circular(radius),
      clockwise: false,
    );
    // Curve down left side to bottom tip
    path.cubicTo(0, h * 0.45, w * 0.22, h * 0.65, w / 2, h);
    path.close();

    // Fill with modern vibrant blue-to-cyan gradient
    final gradient = const LinearGradient(
      colors: [Color(0xFF00C6FF), Color(0xFF0072FF)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ).createShader(Rect.fromLTWH(0, 0, w, h));

    final paint = Paint()
      ..shader = gradient
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, paint);

    // Inner white circle (hole of the pin)
    final innerCirclePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius * 0.42, innerCirclePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
