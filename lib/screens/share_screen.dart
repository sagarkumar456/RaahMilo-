import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../core/app_colors.dart';
import '../models/shared_device_model.dart';
import '../services/share_service.dart';

class ShareScreen extends StatefulWidget {
  final String? tripId;

  const ShareScreen({super.key, this.tripId});

  @override
  State<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends State<ShareScreen> {
  final _recipientController = TextEditingController();
  int _selectedPermission = 0; // 0: Live only, 1: Live + History, 2: 24h Pass
  bool _isSharing = false;

  @override
  void dispose() {
    _recipientController.dispose();
    super.dispose();
  }

  String get _myEmail {
    final user = FirebaseAuth.instance.currentUser;
    return user?.email?.trim().toLowerCase() ?? 'user@trackmyphone.app';
  }

  Future<void> _shareAccess() async {
    final recipient = _recipientController.text.trim().toLowerCase();
    if (recipient.isEmpty) {
      _showFeedbackSnackBar('Please enter an email address', isError: true);
      return;
    }

    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(recipient)) {
      _showFeedbackSnackBar('Please enter a valid email address', isError: true);
      return;
    }

    if (recipient == _myEmail) {
      _showFeedbackSnackBar('You cannot share location with your own email', isError: true);
      return;
    }

    setState(() => _isSharing = true);

    try {
      String perm = 'live_only';
      Duration? expiry;

      if (_selectedPermission == 1) {
        perm = 'live_history';
      } else if (_selectedPermission == 2) {
        perm = 'temporary_24h';
        expiry = const Duration(hours: 24);
      }

      await shareService.shareLocationWith(
        recipient,
        permission: perm,
        expiryDuration: expiry,
      );

      _recipientController.clear();
      FocusScope.of(context).unfocus();

      if (mounted) {
        _showFeedbackSnackBar(
          'Location shared with $recipient! They can track your live movement on their Home screen.',
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

  Future<void> _confirmRevoke(SharedDeviceModel share) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Revoke Location Access?'),
        content: Text(
          'Are you sure you want to stop sharing your live location with ${share.sharedWithEmail}?',
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
            child: const Text('Revoke Access'),
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
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: AppColors.navyDark),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Live Location Sharing',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.navyDark,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. My Share ID & Email Banner
              _buildMyShareIdCard(),

              const SizedBox(height: 20),

              // 2. Share Input Section Card
              Container(
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
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
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
                                'Invite Contact or Family',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.navyDark,
                                ),
                              ),
                              Text(
                                'They will see your live GPS updates in real-time',
                                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),

                    // Email input field
                    TextField(
                      controller: _recipientController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        hintText: 'Enter recipient\'s email (e.g. family@gmail.com)',
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

                    // Permission Header
                    const Text(
                      'Select Sharing Permissions',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.navyDark,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // 3 Permission Selection Cards
                    _buildPermissionCard(
                      index: 0,
                      icon: Icons.sensors_rounded,
                      title: 'Live Location Only',
                      subtitle: 'Real-time GPS pin, current speed & map marker',
                      badge: 'Recommended',
                      badgeColor: AppColors.primary,
                    ),
                    const SizedBox(height: 10),
                    _buildPermissionCard(
                      index: 1,
                      icon: Icons.route_rounded,
                      title: 'Live + Trip History',
                      subtitle: 'Live pin plus past route lines, stops & playback',
                      badge: 'Full Access',
                      badgeColor: const Color(0xFF8B5CF6),
                    ),
                    const SizedBox(height: 10),
                    _buildPermissionCard(
                      index: 2,
                      icon: Icons.timer_outlined,
                      title: '24-Hour Temporary Pass',
                      subtitle: 'Access automatically revokes after 24 hours',
                      badge: 'Time-Limited',
                      badgeColor: const Color(0xFFF59E0B),
                    ),

                    const SizedBox(height: 22),

                    // Share Submit Button
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
              ),

              const SizedBox(height: 24),

              // 3. Real-Time Active Viewers List
              _buildActiveViewersSection(),

              const SizedBox(height: 24),

              // 4. Privacy & Encryption Note
              _buildPrivacyNotice(),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMyShareIdCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.satellite_alt_rounded, color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Text(
                      'Your Device ID',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.4,
                      ),
                    ),
                    SizedBox(width: 6),
                    Icon(Icons.verified_rounded, color: AppColors.success, size: 14),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _myEmail,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.navyDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: _myEmail));
              _showFeedbackSnackBar('Your sharing email copied to clipboard!', isError: false);
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.copy_rounded, size: 14, color: AppColors.primary),
                  SizedBox(width: 4),
                  Text(
                    'Copy',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionCard({
    required int index,
    required IconData icon,
    required String title,
    required String subtitle,
    required String badge,
    required Color badgeColor,
  }) {
    final isSelected = _selectedPermission == index;
    return InkWell(
      onTap: () => setState(() => _selectedPermission = index),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.05) : AppColors.tileBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.transparent,
            width: isSelected ? 1.8 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : Colors.grey.shade200,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isSelected ? Colors.white : AppColors.textSecondary,
                size: 19,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: isSelected ? AppColors.navyDark : AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          badge,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: badgeColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? AppColors.primary : Colors.transparent,
                border: Border.all(
                  color: isSelected ? AppColors.primary : Colors.grey.shade400,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check_rounded, color: Colors.white, size: 14)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveViewersSection() {
    return StreamBuilder<List<SharedDeviceModel>>(
      stream: shareService.getMySharedWithOthersStream(),
      builder: (context, snapshot) {
        final shares = snapshot.data ?? [];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.people_alt_rounded, size: 20, color: AppColors.navyDark),
                const SizedBox(width: 8),
                const Text(
                  'People With Active Access',
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
                padding: const EdgeInsets.all(20),
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
                            'No active shares',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.navyDark,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Share your location using the form above to let family or friends track this device.',
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
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryLight,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      share.permissionLabel,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Shared ${DateFormat('dd MMM, hh:mm a').format(share.updatedAt)}',
                                    style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
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
          Icon(Icons.shield_outlined, size: 20, color: AppColors.textSecondary),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Your GPS location is securely streamed to authorized contacts. You can revoke access at any time with one tap.',
              style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
