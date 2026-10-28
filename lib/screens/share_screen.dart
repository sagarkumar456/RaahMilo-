import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/app_colors.dart';
import '../models/shared_device_model.dart';
import '../services/share_service.dart';
import 'shared_device_map_screen.dart';
import 'shared_user_history_screen.dart';

class ShareScreen extends StatefulWidget {
  final String? tripId;

  const ShareScreen({super.key, this.tripId});

  @override
  State<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends State<ShareScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _recipientController = TextEditingController();

  // 0: 1 Hour, 1: 8 Hours, 2: 24 Hours, 3: Always
  int _selectedDurationIndex = 2; // Default: 24 Hours
  // 0: Live Only, 1: Live + Trip History
  int _selectedPermissionIndex = 0; // Default: Live Only
  bool _isSharing = false;
  bool _isRevokingAll = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _recipientController.dispose();
    super.dispose();
  }

  String get _myEmail {
    final user = FirebaseAuth.instance.currentUser;
    return user?.email?.trim().toLowerCase() ?? 'user@trackmyphone.app';
  }

  Duration? get _selectedDuration {
    switch (_selectedDurationIndex) {
      case 0:
        return const Duration(hours: 1);
      case 1:
        return const Duration(hours: 8);
      case 2:
        return const Duration(hours: 24);
      case 3:
      default:
        return null; // Always active
    }
  }

  String get _selectedPermission {
    return _selectedPermissionIndex == 1 ? 'live_history' : 'live_only';
  }

  Future<void> _shareAccess() async {
    final recipient = _recipientController.text.trim().toLowerCase();
    if (recipient.isEmpty) {
      _showFeedbackSnackBar('Please enter an email address', isError: true);
      return;
    }

    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(recipient)) {
      _showFeedbackSnackBar('Please enter a valid email address (e.g. name@gmail.com)', isError: true);
      return;
    }

    if (recipient == _myEmail) {
      _showFeedbackSnackBar('You cannot share location with your own email', isError: true);
      return;
    }

    setState(() => _isSharing = true);

    try {
      await shareService.shareLocationWith(
        recipient,
        permission: _selectedPermission,
        expiryDuration: _selectedDuration,
      );

      _recipientController.clear();
      FocusScope.of(context).unfocus();

      if (mounted) {
        final durationLabel = _selectedDurationIndex == 3 ? 'indefinitely' : 'for ${_durationLabel(_selectedDurationIndex)}';
        _showFeedbackSnackBar(
          'Live location shared with $recipient $durationLabel! They can track you on their Home screen.',
          isError: false,
        );
      }
    } catch (e) {
      if (mounted) {
        _showFeedbackSnackBar('Error sharing location: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  String _durationLabel(int index) {
    switch (index) {
      case 0:
        return '1 Hour';
      case 1:
        return '8 Hours';
      case 2:
        return '24 Hours';
      case 3:
      default:
        return 'Always';
    }
  }

  Future<void> _confirmRevoke(SharedDeviceModel share) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Revoke Location Access?'),
        content: Text(
          'Stop sharing your real-time location with ${share.sharedWithEmail}?',
          style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await shareService.revokeShare(share.id);
        if (mounted) {
          _showFeedbackSnackBar('Access revoked for ${share.sharedWithEmail}', isError: false);
        }
      } catch (e) {
        if (mounted) {
          _showFeedbackSnackBar('Failed to revoke access: $e', isError: true);
        }
      }
    }
  }

  Future<void> _confirmRevokeAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Stop All Location Sharing?'),
        content: const Text(
          'This will immediately revoke access for all active viewers. No one will be able to see your live location.',
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Stop All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isRevokingAll = true);
      try {
        await shareService.revokeAllMyShares();
        if (mounted) {
          _showFeedbackSnackBar('All active location shares have been stopped.', isError: false);
        }
      } catch (e) {
        if (mounted) {
          _showFeedbackSnackBar('Error stopping shares: $e', isError: true);
        }
      } finally {
        if (mounted) setState(() => _isRevokingAll = false);
      }
    }
  }

  void _copyInviteMessage() {
    final invite = 'Hi! Track my live GPS location on the RaahMilo app. Open RaahMilo and enter my email: $_myEmail to track me in real-time.';
    Clipboard.setData(ClipboardData(text: invite));
    _showFeedbackSnackBar('Invite message copied! Paste it into WhatsApp, SMS, or any chat app.', isError: false);
  }

  void _showFeedbackSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline_rounded : Icons.check_circle_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? AppColors.danger : AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: AppColors.navyDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Location Sharing Hub',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.navyDark,
          ),
        ),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          tabs: const [
            Tab(
              icon: Icon(Icons.cell_tower_rounded, size: 20),
              text: 'Share My Device',
            ),
            Tab(
              icon: Icon(Icons.people_alt_rounded, size: 20),
              text: 'Shared With Me',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildShareMyDeviceTab(),
          _buildSharedWithMeTab(),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 1: SHARE MY DEVICE (OUTGOING SHARES)
  // ==========================================
  Widget _buildShareMyDeviceTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Live Broadcast Status Header
          _buildBroadcastStatusCard(),

          const SizedBox(height: 16),

          // 2. Your Sharing Identity & Invite Card
          _buildSharingIdentityCard(),

          const SizedBox(height: 18),

          // 3. Add Recipient Form Card
          _buildShareFormCard(),

          const SizedBox(height: 24),

          // 4. Currently Active Viewers List
          _buildActiveViewersList(),

          const SizedBox(height: 24),

          // 5. Security & Privacy Notice
          _buildPrivacyNotice(),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildBroadcastStatusCard() {
    return StreamBuilder<List<SharedDeviceModel>>(
      stream: shareService.getMySharedWithOthersStream(),
      builder: (context, snapshot) {
        final shares = snapshot.data ?? [];
        final isBroadcasting = shares.isNotEmpty;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isBroadcasting
                ? const Color(0xFFE6F9F0)
                : AppColors.tileBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isBroadcasting
                  ? const Color(0xFF10B981).withValues(alpha: 0.5)
                  : AppColors.border,
              width: 1.2,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: isBroadcasting ? const Color(0xFF10B981) : Colors.grey.shade400,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isBroadcasting ? Icons.radar_rounded : Icons.cell_tower_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isBroadcasting
                          ? 'Live GPS Broadcast Active'
                          : 'Location Sharing Inactive',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: isBroadcasting ? const Color(0xFF047857) : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isBroadcasting
                          ? '${shares.length} ${shares.length == 1 ? "contact" : "contacts"} can view your real-time position'
                          : 'Nobody is currently tracking this device',
                      style: TextStyle(
                        fontSize: 12,
                        color: isBroadcasting ? const Color(0xFF065F46) : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (isBroadcasting)
                TextButton(
                  onPressed: _isRevokingAll ? null : _confirmRevokeAll,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  ),
                  child: _isRevokingAll
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.danger),
                        )
                      : const Text(
                          'Stop All',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                        ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSharingIdentityCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fingerprint_rounded, size: 18, color: AppColors.primary),
              const SizedBox(width: 6),
              const Text(
                'YOUR DEVICE SHARE ID',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.6,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Online',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _myEmail,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.navyDark,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Family or contacts can enter this email in their RaahMilo app to view your live movement.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.3),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _myEmail));
                    _showFeedbackSnackBar('Email copied to clipboard!', isError: false);
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('Copy Email', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(color: AppColors.primary.withValues(alpha: 0.4)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _copyInviteMessage,
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                  label: const Text('Invite / SMS', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildShareFormCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.person_add_alt_1_rounded, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Share With Contact',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.navyDark,
                      ),
                    ),
                    Text(
                      'Give access to family, friends, or trusted people',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Recipient Email Input
          TextField(
            controller: _recipientController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: 'Enter contact\'s email (e.g. family@gmail.com)',
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13.5),
              prefixIcon: const Icon(Icons.alternate_email_rounded, color: AppColors.primary, size: 20),
              suffixIcon: _recipientController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18, color: AppColors.textMuted),
                      onPressed: () {
                        _recipientController.clear();
                        setState(() {});
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              filled: true,
              fillColor: AppColors.tileBackground,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),

          const SizedBox(height: 20),

          // Duration Selector
          const Row(
            children: [
              Icon(Icons.timer_outlined, size: 16, color: AppColors.textSecondary),
              SizedBox(width: 6),
              Text(
                'Sharing Duration',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.navyDark),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildDurationChip(0, '1 Hour'),
              const SizedBox(width: 6),
              _buildDurationChip(1, '8 Hours'),
              const SizedBox(width: 6),
              _buildDurationChip(2, '24 Hours'),
              const SizedBox(width: 6),
              _buildDurationChip(3, 'Always'),
            ],
          ),

          const SizedBox(height: 20),

          // Permission Level Selector
          const Row(
            children: [
              Icon(Icons.shield_outlined, size: 16, color: AppColors.textSecondary),
              SizedBox(width: 6),
              Text(
                'Permission Level',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.navyDark),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildPermissionOptionCard(
                  index: 0,
                  icon: Icons.sensors_rounded,
                  title: 'Live Only',
                  subtitle: 'Real-time GPS pin & speed',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildPermissionOptionCard(
                  index: 1,
                  icon: Icons.alt_route_rounded,
                  title: 'Live + History',
                  subtitle: 'Live pin + past route trips',
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Submit Share Button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _isSharing ? null : _shareAccess,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: _isSharing
                  ? const SizedBox.shrink()
                  : const Icon(Icons.share_location_rounded, size: 20),
              label: _isSharing
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Text(
                      'Share Live Location',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDurationChip(int index, String label) {
    final isSelected = _selectedDurationIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedDurationIndex = index),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : AppColors.tileBackground,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionOptionCard({
    required int index,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final isSelected = _selectedPermissionIndex == index;
    return InkWell(
      onTap: () => setState(() => _selectedPermissionIndex = index),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryLight : AppColors.tileBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 1.8 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: isSelected ? AppColors.primary : AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: isSelected ? AppColors.navyDark : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveViewersList() {
    return StreamBuilder<List<SharedDeviceModel>>(
      stream: shareService.getMySharedWithOthersStream(),
      builder: (context, snapshot) {
        final shares = snapshot.data ?? [];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.visibility_rounded, size: 20, color: AppColors.navyDark),
                const SizedBox(width: 8),
                const Text(
                  'Active Viewers',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navyDark,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: shares.isNotEmpty ? AppColors.primary : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${shares.length}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: shares.isNotEmpty ? Colors.white : AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (shares.isEmpty)
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.tileBackground,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.person_off_rounded, color: AppColors.textMuted, size: 22),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'No active viewers right now',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.navyDark,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Share your location using the form above to let contacts track your live GPS.',
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.3),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: shares.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, idx) {
                  final share = shares[idx];
                  final initial = share.sharedWithEmail.isNotEmpty
                      ? share.sharedWithEmail[0].toUpperCase()
                      : '?';

                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                          child: Text(
                            initial,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                share.sharedWithEmail,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryLight,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      share.permission == 'live_history' ? 'Live + History' : 'Live Only',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFEF3C7),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      share.permissionLabel,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFFD97706),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        OutlinedButton(
                          onPressed: () => _confirmRevoke(share),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.danger,
                            side: const BorderSide(color: Color(0xFFFCA5A5)),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            minimumSize: const Size(60, 32),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text(
                            'Revoke',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }

  // ==========================================
  // TAB 2: SHARED WITH ME (INCOMING SHARES)
  // ==========================================
  Widget _buildSharedWithMeTab() {
    return StreamBuilder<List<SharedDeviceModel>>(
      stream: shareService.getSharedWithMeStream(),
      builder: (context, snapshot) {
        final devices = snapshot.data ?? [];

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Ask friends & family to share their live location with your email: $_myEmail',
                      style: const TextStyle(fontSize: 12, color: AppColors.navyDark, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            if (devices.isEmpty)
              Container(
                padding: const EdgeInsets.all(26),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.tileBackground,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.people_outline_rounded, color: AppColors.textMuted, size: 28),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'No Devices Shared With You',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.navyDark,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'When another user shares their live GPS with you, their device card with real-time map tracking will appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.35),
                    ),
                    const SizedBox(height: 18),
                    OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _myEmail));
                        _showFeedbackSnackBar('Your email copied to clipboard!', isError: false);
                      },
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Copy My Email To Send Them'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.4)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: devices.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, idx) {
                  final dev = devices[idx];
                  return _buildIncomingDeviceCard(dev);
                },
              ),
          ],
        );
      },
    );
  }

  Widget _buildIncomingDeviceCard(SharedDeviceModel dev) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.15),
                child: Text(
                  dev.ownerName.isNotEmpty ? dev.ownerName[0].toUpperCase() : 'U',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF10B981), fontSize: 16),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dev.ownerName,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.navyDark),
                    ),
                    Text(
                      dev.ownerEmail,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    const Text(
                      'LIVE',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.success),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.tileBackground,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_on_rounded, size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    dev.address,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${dev.speedKmh.toStringAsFixed(0)} km/h',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.navyDark),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SharedDeviceMapScreen(initialDevice: dev),
                      ),
                    );
                  },
                  icon: const Icon(Icons.map_rounded, size: 16),
                  label: const Text('Live Map', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SharedUserHistoryScreen(sharedDevice: dev),
                      ),
                    );
                  },
                  icon: const Icon(Icons.history_rounded, size: 16),
                  label: const Text('Trip History', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.navyDark,
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacyNotice() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.tileBackground,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline_rounded, size: 18, color: AppColors.textSecondary),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Location sharing is strictly consent-based and encrypted in transit. You can revoke access or stop broadcasting at any time.',
              style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
