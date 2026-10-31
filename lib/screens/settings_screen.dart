import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_colors.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'geofence_screen.dart';
import 'support_chat_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _apiUrlController = TextEditingController();
  final TextEditingController _geminiKeyController = TextEditingController();
  String _speedUnit = 'km/h';
  String _gpsAccuracy = 'High Accuracy';
  bool _overspeedAlert = true;
  int _speedLimit = 80;
  bool _isPingingApi = false;
  bool _isSavingApi = false;
  bool _isSendingTestAlert = false;
  bool _showGeminiKey = false;

  bool _developerUnlocked = false;
  int _versionTapCount = 0;

  bool get _isAdmin {
    final email = authService.email.trim().toLowerCase();
    return email == 'sagar@onelap.in' || _developerUnlocked;
  }

  @override
  void initState() {
    super.initState();
    _apiUrlController.text = apiService.baseUrl;
    _geminiKeyController.text = apiService.geminiApiKey ?? '';
    _loadLocalPreferences();
  }

  Future<void> _loadLocalPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _speedUnit = prefs.getString('pref_speed_unit') ?? 'km/h';
      _gpsAccuracy = prefs.getString('pref_gps_accuracy') ?? 'High Accuracy';
      _overspeedAlert = prefs.getBool('pref_overspeed_alert') ?? true;
      _speedLimit = prefs.getInt('pref_speed_limit') ?? 80;
      _developerUnlocked = prefs.getBool('admin_developer_unlocked') ?? false;
    });
  }

  Future<void> _savePreference(String key, dynamic val) async {
    final prefs = await SharedPreferences.getInstance();
    if (val is String) await prefs.setString(key, val);
    if (val is bool) await prefs.setBool(key, val);
    if (val is int) await prefs.setInt(key, val);

    // Call API to sync settings to server
    apiService.syncSettings({
      'speedUnit': _speedUnit,
      'gpsAccuracy': _gpsAccuracy,
      'overspeedAlert': _overspeedAlert,
      'speedLimit': _speedLimit,
    });
  }

  Future<void> _pingServer() async {
    setState(() => _isPingingApi = true);
    final ok = await apiService.pingApi();
    if (mounted) {
      setState(() => _isPingingApi = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(ok ? Icons.check_circle_rounded : Icons.warning_rounded, color: Colors.white),
              const SizedBox(width: 8),
              Text(ok ? 'API Connection Healthy (200 OK)' : 'API Offline, using local sync mode'),
            ],
          ),
          backgroundColor: ok ? AppColors.success : AppColors.danger,
        ),
      );
    }
  }

  Future<void> _sendTestAlertToAdmin() async {
    if (_isSendingTestAlert) return;
    setState(() => _isSendingTestAlert = true);

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sending test message to Support Desk via API...')),
      );

      final res = await apiService.sendSupportIssueAlert(
        userEmail: authService.email.isNotEmpty ? authService.email : 'user@raahmilo.com',
        userUid: authService.uid.isNotEmpty ? authService.uid : 'device_test',
        issueDescription: 'TEST SYSTEM CHECK: Verified settings alert dispatched from RaahMilo mobile app.',
        priority: 'TEST_PING',
        forceSend: true,
      );

      if (mounted) {
        final isDelivered = res['mailDelivered'] == true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isDelivered
                  ? '✅ Email successfully delivered to Support Desk! [Ticket #${res['ticketId']}]'
                  : 'Alert dispatched! Ticket #${res['ticketId']} (Check API Inspector for logs)',
            ),
            backgroundColor: isDelivered ? AppColors.success : AppColors.primary,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingTestAlert = false);
    }
  }

  void _showAdminPinDialog() {
    final pinController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.admin_panel_settings_rounded, color: AppColors.primary),
            SizedBox(width: 8),
            Text('Admin Access PIN'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter Admin PIN to unlock Developer & API Settings (or sign in as sagar@onelap.in):',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              decoration: InputDecoration(
                hintText: 'Admin PIN (e.g. 1641)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              if (pinController.text.trim() == '1641' || pinController.text.trim() == '1234') {
                setState(() => _developerUnlocked = true);
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('admin_developer_unlocked', true);
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Admin API Settings unlocked!'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invalid Admin PIN')),
                );
              }
            },
            child: const Text('Unlock'),
          ),
        ],
      ),
    );
  }

  void _showApiLogsModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final logs = apiService.logs;

            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.history_edu_rounded, color: Color(0xFF2563EB), size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Live API Call Inspector',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.navyDark),
                            ),
                            Text(
                              'Authorized Admin Log: sagar@onelap.in',
                              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          apiService.clearLogs();
                          setModalState(() {});
                        },
                        child: const Text('Clear', style: TextStyle(color: AppColors.danger)),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  Expanded(
                    child: logs.isEmpty
                        ? const Center(
                            child: Text('No API calls logged yet.', style: TextStyle(color: AppColors.textMuted)),
                          )
                        : ListView.separated(
                            itemCount: logs.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final log = logs[i];
                              return ExpansionTile(
                                dense: true,
                                tilePadding: EdgeInsets.zero,
                                leading: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: log.method == 'POST' ? const Color(0xFF2563EB) : const Color(0xFF10B981),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    log.method,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  log.endpoint,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(
                                  'Status: ${log.statusCode} • ${log.latencyMs}ms • ${log.timestamp.hour}:${log.timestamp.minute.toString().padLeft(2, '0')}:${log.timestamp.second.toString().padLeft(2, '0')}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: log.isSuccess ? AppColors.success : AppColors.danger,
                                  ),
                                ),
                                children: [
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(10),
                                    color: const Color(0xFFF1F5F9),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (log.requestBody.isNotEmpty) ...[
                                          const Text('Request Body:',
                                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                          Text(log.requestBody,
                                              style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
                                          const SizedBox(height: 6),
                                        ],
                                        const Text('Response Body:',
                                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                        Text(log.responseBody,
                                            style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showBackgroundTrackingHelpDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.screen_lock_portrait_rounded, color: AppColors.primary),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Bag / Pocket Tracking Setup',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Agar aap phone ko bag ya pocket me rakh kar screen lock kar dete hain, to unbroken polyline route record karne ke liye ye 2 permissions zaroori hain:',
              style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.navyDark),
            ),
            const SizedBox(height: 14),
            _buildSetupStep(
              number: '1',
              title: 'Location: "Allow all the time"',
              subtitle: 'Phone settings me Location permission ko "Allow all the time" chunein taaki screen off hone par bhi updates milein.',
            ),
            const SizedBox(height: 10),
            _buildSetupStep(
              number: '2',
              title: 'Battery: "Unrestricted"',
              subtitle: 'Battery Optimization ko "Don\'t optimize" ya "Unrestricted" karein taaki Android Doze mode background GPS ko freeze na kare.',
            ),
            const SizedBox(height: 10),
            _buildSetupStep(
              number: '3',
              title: 'Notifications Allowed',
              subtitle: 'Foreground notification alert allow rakhein taaki OS background tracking service ko kill na kare.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              Geolocator.openAppSettings();
            },
            icon: const Icon(Icons.settings_rounded, size: 16),
            label: const Text('Open App Settings'),
          ),
        ],
      ),
    );
  }

  Widget _buildSetupStep({
    required String number,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
          ),
          child: Text(
            number,
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.navyDark)),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.3)),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: apiService,
      builder: (context, _) {
        final isAdmin = _isAdmin;

        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          appBar: AppBar(
            title: const Text('Settings'),
            actions: [
              // ONLY visible to sagar@onelap.in or unlocked admin
              if (isAdmin)
                IconButton(
                  tooltip: 'Live API Inspector (Admin)',
                  icon: const Icon(Icons.terminal_rounded, color: Color(0xFF2563EB)),
                  onPressed: _showApiLogsModal,
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            children: [
              // 1. Geofence Safe Zones
              _buildSectionHeader('Geofence Safe Zones'),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                ),
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Color(0xFFE6F9F0),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.radar_rounded, color: Color(0xFF10B981)),
                  ),
                  title: const Text('Geofence Safe Zones', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: const Text('Manage custom zones, perimeters & entry/exit alerts', style: TextStyle(fontSize: 12)),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const GeofenceScreen()),
                    );
                  },
                ),
              ),

              const SizedBox(height: 20),

              // 2. Help Support & AI Chat Section
              _buildSectionHeader('AI Support & Helpdesk'),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Color(0xFFEFF6FF),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.support_agent_rounded, color: Color(0xFF2563EB)),
                      ),
                      title: const Text('RaahMilo AI Chatbot', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: const Text('24x7 bilingual assistance & ticket routing', style: TextStyle(fontSize: 12)),
                      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const SupportChatScreen()),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(Icons.verified_user_outlined, color: AppColors.success, size: 20),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Support Desk Dispatch', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                Text('Active • Direct Email Escalation', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 84,
                            height: 32,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                side: const BorderSide(color: AppColors.primary),
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: _sendTestAlertToAdmin,
                              child: const Text('Test Alert', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 3. API & Server Configuration Section (ONLY for sagar@onelap.in or unlocked admin)
              if (isAdmin) ...[
                _buildSectionHeader('Admin & Developer API (sagar@onelap.in)'),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFF2563EB).withValues(alpha: 0.4), width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.admin_panel_settings_rounded, color: Color(0xFF2563EB), size: 18),
                              SizedBox(width: 6),
                              Text('Backend API Base URL', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.navyDark)),
                            ],
                          ),
                          InkWell(
                            onTap: _showApiLogsModal,
                            child: const Row(
                              children: [
                                Icon(Icons.receipt_long_rounded, size: 14, color: Color(0xFF2563EB)),
                                SizedBox(width: 4),
                                Text('View Logs', style: TextStyle(fontSize: 12, color: Color(0xFF2563EB), fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _apiUrlController,
                        style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          suffixIcon: _isSavingApi
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                )
                              : IconButton(
                                  icon: const Icon(Icons.save_rounded, size: 18),
                                  onPressed: () async {
                                    setState(() => _isSavingApi = true);
                                    await apiService.setBaseUrl(_apiUrlController.text);
                                    setState(() => _isSavingApi = false);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('API Base URL updated!')),
                                      );
                                    }
                                  },
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2563EB),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                              onPressed: _isPingingApi ? null : _pingServer,
                              icon: _isPingingApi
                                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.wifi_rounded, size: 16),
                              label: const Text('Ping API / Check Health', style: TextStyle(fontSize: 12)),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 28),
                      const Row(
                        children: [
                          Icon(Icons.smart_toy_rounded, color: Color(0xFF2563EB), size: 18),
                          SizedBox(width: 6),
                          Text('Google Gemini Free AI Key (Optional)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.navyDark)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '100% Free on aistudio.google.com. If left empty, the built-in Human Engine is active.',
                        style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _geminiKeyController,
                        obscureText: !_showGeminiKey,
                        style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                        decoration: InputDecoration(
                          hintText: 'AIzaSy... (Paste free key from aistudio.google.com)',
                          hintStyle: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          prefixIcon: IconButton(
                            icon: Icon(_showGeminiKey ? Icons.visibility_off : Icons.visibility, size: 16),
                            onPressed: () => setState(() => _showGeminiKey = !_showGeminiKey),
                          ),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.save_rounded, size: 18),
                            onPressed: () async {
                              await apiService.setGeminiApiKey(_geminiKeyController.text);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Gemini Free AI Key saved!'),
                                    backgroundColor: AppColors.success,
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // 4. Tracking & Display Preferences
              _buildSectionHeader('Tracking Preferences'),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Speed Unit', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          DropdownButton<String>(
                            value: _speedUnit,
                            underline: const SizedBox(),
                            items: const [
                              DropdownMenuItem(value: 'km/h', child: Text('km/h (Metric)')),
                              DropdownMenuItem(value: 'mph', child: Text('mph (Imperial)')),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _speedUnit = val);
                                _savePreference('pref_speed_unit', val);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('GPS Location Accuracy', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          DropdownButton<String>(
                            value: _gpsAccuracy,
                            underline: const SizedBox(),
                            items: const [
                              DropdownMenuItem(value: 'High Accuracy', child: Text('High (1-3m)')),
                              DropdownMenuItem(value: 'Balanced', child: Text('Balanced (5-10m)')),
                              DropdownMenuItem(value: 'Battery Saver', child: Text('Battery Saver')),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _gpsAccuracy = val);
                                _savePreference('pref_gps_accuracy', val);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text('Overspeed Alert', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text('Alert when vehicle speed exceeds $_speedLimit $_speedUnit', style: const TextStyle(fontSize: 11)),
                      value: _overspeedAlert,
                      activeColor: AppColors.primary,
                      onChanged: (val) {
                        setState(() => _overspeedAlert = val);
                        _savePreference('pref_overspeed_alert', val);
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 5. Bag & Background Tracking Mode Setup
              _buildSectionHeader('Bag & Background Tracking'),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                ),
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Color(0xFFEFF6FF),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.screen_lock_portrait_rounded, color: Color(0xFF2563EB)),
                  ),
                  title: const Text('Bag / Pocket Tracking Guide', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: const Text('Settings required to record complete polyline route with screen locked or in bag', style: TextStyle(fontSize: 12)),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                  onTap: _showBackgroundTrackingHelpDialog,
                ),
              ),

              const SizedBox(height: 20),

              // App Version & Hidden Developer Tap Unlock
              InkWell(
                onTap: () {
                  _versionTapCount++;
                  if (_versionTapCount >= 5 && !_developerUnlocked) {
                    _showAdminPinDialog();
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text(
                      'RaahMilo v1.0.0${isAdmin ? " • Admin Mode (sagar@onelap.in)" : ""}',
                      style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
