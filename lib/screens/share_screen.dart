import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../services/share_service.dart';

class ShareScreen extends StatefulWidget {
  final String? tripId;

  const ShareScreen({super.key, this.tripId});

  @override
  State<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends State<ShareScreen> {
  final _recipientController = TextEditingController();
  int _selectedPermission = 0; // 0: Live only, 1: Live + History, 2: Set expiry
  bool _isSharing = false;

  final List<String> _sharedViewers = ['family_member@gmail.com'];

  @override
  void dispose() {
    _recipientController.dispose();
    super.dispose();
  }

  Future<void> _shareAccess() async {
    final recipient = _recipientController.text.trim();
    if (recipient.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an email or phone number')),
      );
      return;
    }

    setState(() => _isSharing = true);

    try {
      await shareService.shareLocationWith(recipient);

      setState(() {
        if (!_sharedViewers.contains(recipient)) {
          _sharedViewers.add(recipient);
        }
      });

      _recipientController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Live location shared with $recipient! They can track you on their Home screen.'),
                ),
              ],
            ),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Share error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  void _revokeAccess(String viewer) {
    setState(() {
      _sharedViewers.remove(viewer);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Removed access for $viewer')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Share Device'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              // Header Graphic: 2 Phones sharing location
              _buildShareIllustration(),
              const SizedBox(height: 24),
              // Title & Subtitle
              const Text(
                'Share Live Location',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navyDark,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Allow family or trusted people to view\nthis device\'s live location.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 28),
              // Input field: "Enter email or phone number"
              TextField(
                controller: _recipientController,
                decoration: const InputDecoration(
                  hintText: 'Enter email or phone number',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
              ),
              const SizedBox(height: 24),
              // Section: Viewer Permissions
              const Text(
                'Viewer Permissions',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.navyDark,
                ),
              ),
              const SizedBox(height: 12),
              _permissionRadioOption(
                index: 0,
                title: 'Live location only',
                subtitle: 'See current location',
              ),
              _permissionRadioOption(
                index: 1,
                title: 'Live location + History',
                subtitle: 'See current location and past routes',
              ),
              _permissionRadioOption(
                index: 2,
                title: 'Set expiry',
                subtitle: 'Allow access for limited time',
              ),
              const SizedBox(height: 28),
              // "Share" Button
              ElevatedButton(
                onPressed: _isSharing ? null : _shareAccess,
                child: _isSharing
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Text(
                        'Share',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
              const SizedBox(height: 32),
              // Approved Viewers Section
              if (_sharedViewers.isNotEmpty) ...[
                const Text(
                  'People with access',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navyDark,
                  ),
                ),
                const SizedBox(height: 10),
                ..._sharedViewers.map((viewer) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.tileBackground,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.account_circle_rounded, color: AppColors.primary, size: 28),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          viewer,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _revokeAccess(viewer),
                        child: const Text('Revoke', style: TextStyle(color: AppColors.danger, fontSize: 13)),
                      ),
                    ],
                  ),
                )),
              ],
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShareIllustration() {
    return Center(
      child: SizedBox(
        width: 180,
        height: 120,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Left Phone
            Positioned(
              left: 10,
              child: Container(
                width: 60,
                height: 96,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.primary, width: 2.2),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(Icons.location_on_rounded, color: AppColors.primary, size: 28),
                ),
              ),
            ),
            // Right Phone
            Positioned(
              right: 10,
              child: Container(
                width: 60,
                height: 96,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.primary, width: 2.2),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(Icons.location_on_rounded, color: AppColors.primary, size: 28),
                ),
              ),
            ),
            // Connecting curved dashed line with dot
            CustomPaint(
              size: const Size(100, 40),
              painter: _ConnectionLinePainter(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _permissionRadioOption({
    required int index,
    required String title,
    required String subtitle,
  }) {
    final isSelected = _selectedPermission == index;
    return InkWell(
      onTap: () => setState(() => _selectedPermission = index),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              height: 22,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.border,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(0, size.height * 0.8)
      ..cubicTo(size.width * 0.3, 0, size.width * 0.7, 0, size.width, size.height * 0.8);

    canvas.drawPath(path, paint);

    // Center pulsating dot
    canvas.drawCircle(Offset(size.width * 0.5, size.height * 0.15), 4, Paint()..color = AppColors.primary);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
