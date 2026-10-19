import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../models/app_notification.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';

class ChatMessage {
  final String id;
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final String? ticketId;
  final bool isIssueReported;

  ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.ticketId,
    this.isIssueReported = false,
  });
}

class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({super.key});

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isTyping = false;
  String _selectedLanguage = 'en'; // 'en' = English, 'hi' = Hindi

  List<String> get _quickSuggestions {
    if (_selectedLanguage == 'en') {
      return [
        'How does Anti-Theft work?',
        'Vehicle Alarm is ringing!',
        '🚨 Report Issue / Get Help',
        'Remote Engine Immobilizer',
        'GPS Accuracy troubleshooting',
      ];
    } else {
      return [
        'Anti-Theft kaise use karein?',
        'Gadi ka Alarm baj raha hai!',
        '🚨 Report Issue (Support Desk)',
        'Remote Engine Cut-off kya hai?',
        'GPS accuracy kaise improve karein?',
      ];
    }
  }

  @override
  void initState() {
    super.initState();
    _initWelcomeMessage();
  }

  void _initWelcomeMessage() {
    _messages.clear();
    if (_selectedLanguage == 'en') {
      _messages.add(
        ChatMessage(
          id: 'welcome_en',
          text: 'Hello! 👋 I am your RaahMilo AI Support Assistant.\n\n'
              'I can assist you with Anti-Theft security, Siren alarms, GPS live tracking, geofencing, and troubleshooting.\n\n'
              'If you encounter any issue or need help, let me know — our system will immediately forward an urgent ticket to our Support Desk.',
          isUser: false,
          timestamp: DateTime.now(),
        ),
      );
    } else {
      _messages.add(
        ChatMessage(
          id: 'welcome_hi',
          text: 'Namaste! 👋 Main RaahMilo AI Support Assistant hoon.\n\n'
              'Aap mujhse Anti-Theft Protection, Alarm Siren, GPS Live Tracking, ya kisi bhi takneeki sahayata ke baare mein pooch sakte hain.\n\n'
              'Agar aapko koi samasya (issue) ya complaint hai, toh batayein — hamara system turant Support Desk par alert bhej dega.',
          isUser: false,
          timestamp: DateTime.now(),
        ),
      );
    }
  }

  void _toggleLanguage(String lang) {
    if (_selectedLanguage == lang) return;
    setState(() {
      _selectedLanguage = lang;
      _initWelcomeMessage();
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  bool _isIssueKeywords(String text) {
    final lower = text.toLowerCase();
    final issueWords = [
      'issue',
      'problem',
      'complaint',
      'not working',
      'kam nahi',
      'kaam nahi',
      'kharab',
      'error',
      'bug',
      'crash',
      'stolen',
      'chori',
      'theft',
      'urgent',
      'help me',
      'madad',
      'failed',
      'loss',
      'kho gayi',
      'report',
      'broken',
      'cannot track',
    ];
    for (final word in issueWords) {
      if (lower.contains(word)) return true;
    }
    return false;
  }

  bool _isHindiInput(String text) {
    final lower = text.toLowerCase();
    final hindiKeywords = ['kya', 'hai', 'kaise', 'gadi', 'chori', 'nahi', 'karo', 'kripya', 'madad', 'mera', 'meri', 'batao'];
    for (final k in hindiKeywords) {
      if (lower.contains(k)) return true;
    }
    return false;
  }

  Future<void> _handleSendMessage([String? predefinedText]) async {
    final text = (predefinedText ?? _controller.text).trim();
    if (text.isEmpty) return;

    if (predefinedText == null) {
      _controller.clear();
    }

    final userMsg = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: text,
      isUser: true,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(userMsg);
      _isTyping = true;
    });
    _scrollToBottom();

    // Check if this is an issue requiring email escalation to admin
    final bool hasIssue = _isIssueKeywords(text);
    String? createdTicketId;

    if (hasIssue) {
      final userEmail = authService.email.isNotEmpty ? authService.email : 'user@raahmilo.com';
      final uid = authService.uid.isNotEmpty ? authService.uid : 'user_guest';

      try {
        final alertRes = await apiService.sendSupportIssueAlert(
          userEmail: userEmail,
          userUid: uid,
          issueDescription: text,
          priority: text.toLowerCase().contains('chori') || text.toLowerCase().contains('theft')
              ? 'CRITICAL_THEFT'
              : 'HIGH',
        );
        createdTicketId = alertRes['ticketId'] ?? 'RM-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';

        // Add to NotificationService
        NotificationService().addNotification(
          title: 'Ticket #$createdTicketId Created',
          subtitle: 'Issue escalated to Support Desk',
          type: NotificationType.supportTicket,
        );
      } catch (_) {
        createdTicketId = 'RM-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
      }
    }

    // Call API for AI message
    final history = _messages.take(10).map((m) => {
          'role': m.isUser ? 'user' : 'assistant',
          'content': m.text,
        }).toList();

    await apiService.sendAiChatMessage(
      message: text,
      chatHistory: history,
      userEmail: authService.email,
    );

    // Determine reply language: if user explicitly typed Hindi or language is 'hi', reply in Hindi; otherwise English
    final useHindi = _selectedLanguage == 'hi' || _isHindiInput(text);

    // Generate intelligent AI response
    await Future.delayed(const Duration(milliseconds: 550));
    final botResponse = _generateAiResponse(text, createdTicketId, useHindi);

    if (mounted) {
      setState(() {
        _isTyping = false;
        _messages.add(
          ChatMessage(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            text: botResponse,
            isUser: false,
            timestamp: DateTime.now(),
            ticketId: createdTicketId,
            isIssueReported: hasIssue,
          ),
        );
      });
      _scrollToBottom();
    }
  }

  String _generateAiResponse(String input, String? ticketId, bool useHindi) {
    final lower = input.toLowerCase();

    // If ticket was raised
    if (ticketId != null) {
      if (useHindi) {
        return 'Maine aapka issue note kar liya hai aur hamari support team ko alert bhej diya hai! ✅\n\n'
            '📌 Ticket ID: #$ticketId\n'
            'Status: Escalated to Support Desk\n\n'
            'Hamari technical team jald hi aapse sampark karegi. Agar vehicle security se judi koi emergency hai, toh kripya turant Police (112) ko bhi sampark karein.';
      } else {
        return 'Your issue has been recorded and an urgent ticket has been forwarded to our Support Team! ✅\n\n'
            '📌 Ticket ID: #$ticketId\n'
            'Status: Escalated to Support Desk\n\n'
            'Our technical team is reviewing this and will contact you shortly. If this is an active vehicle theft emergency, please also contact the emergency authorities (112).';
      }
    }

    // Anti-theft queries
    if (lower.contains('antitheft') || lower.contains('anti-theft') || lower.contains('arm')) {
      if (useHindi) {
        return '🛡️ Anti-Theft System RaahMilo ka high-security shield hai:\n\n'
            '1. "Arm Vehicle" button dabane par gadi ka location anchor lock ho jata hai.\n'
            '2. Agar gadi 8-15 meter se zyada hilti hai ya motion detect hota hai, toh loud siren bajega aur aapko alert aayega.\n'
            '3. Aap app se remotely Siren alarm trigger ya silence kar sakte hain.\n'
            '4. Emergency mein "Remote Engine Cut-off" switch se ignition immobilize kiya ja sakta hai.';
      } else {
        return '🛡️ RaahMilo Anti-Theft Security Guard:\n\n'
            '1. **Arm Vehicle**: Tap "Arm Vehicle" to lock your current parked GPS coordinate.\n'
            '2. **Movement Breach**: If the vehicle moves beyond the safety threshold (8–15m), the loud siren alarm triggers immediately.\n'
            '3. **Remote Siren**: You can sound or silence the alarm siren remotely from the Anti-Theft screen.\n'
            '4. **Engine Immobilizer**: Cut-off vehicle ignition remotely in case of theft.';
      }
    }

    // Alarm queries
    if (lower.contains('alarm') || lower.contains('siren') || lower.contains('baj raha') || lower.contains('ringing')) {
      if (useHindi) {
        return '🚨 Vehicle Alarm & Siren Alert:\n\n'
            '• Alarm band karne ke liye Anti-Theft screen par "Silence Alarm" button dabayein.\n'
            '• Gadi ko verify karein ki parked spot par surakshit hai ya nahi.\n'
            '• Settings screen se Siren Loudness aur Sensitivity customize kar sakte hain.';
      } else {
        return '🚨 Vehicle Alarm & Siren Controls:\n\n'
            '• To stop the alarm, tap **"Silence Siren"** on the Anti-Theft screen or top emergency banner.\n'
            '• Check the live map to verify your vehicle\'s current position.\n'
            '• You can customize siren loudness and motion sensitivity in the Settings screen.';
      }
    }

    // Engine cut-off queries
    if (lower.contains('engine') || lower.contains('immobilizer') || lower.contains('cut off') || lower.contains('cutoff')) {
      if (useHindi) {
        return '🔒 Remote Engine Immobilizer:\n\n'
            'Yeh feature theft attempt ke dauran vehicle ignition signal ko remotely disable karne ke liye use hota hai. Aap ise Anti-Theft Screen se 1-click mein On ya Off kar sakte hain.';
      } else {
        return '🔒 Remote Engine Immobilizer:\n\n'
            'This feature allows you to remotely cut-off the vehicle ignition/fuel signal in case of unauthorized movement. You can toggle this on or off with 1 tap from the Anti-Theft screen.';
      }
    }

    // GPS accuracy queries
    if (lower.contains('gps') || lower.contains('accuracy') || lower.contains('location') || lower.contains('track')) {
      if (useHindi) {
        return '📍 GPS Tracking Tips:\n\n'
            '• Phone Settings mein Location Permission ko "Allow all the time" par rakhein.\n'
            '• Battery optimization disable karein taaki background mein GPS drop na ho.\n'
            '• Settings mein jaakar GPS frequency High Accuracy mode par set karein.';
      } else {
        return '📍 GPS Tracking Optimization:\n\n'
            '• Ensure location permissions are set to **"Allow all the time"** in your phone settings.\n'
            '• Disable battery optimization for RaahMilo to keep GPS active in background.\n'
            '• Set GPS Accuracy to **"High Accuracy"** in the Settings screen for 1–3 meter precision.';
      }
    }

    // Default response
    if (useHindi) {
      return 'Main samajh gaya. RaahMilo aapke vehicle ki safety ke liye 24x7 tayar hai. Aap Anti-Theft, Alarm, Geofence, ya Live Map ke bare mein pooch sakte hain. Agar koi technical samasya hai, toh batayein aur main turant Support Desk ko alert bhej doonga!';
    } else {
      return 'Understood! RaahMilo is ready 24/7 to keep your vehicle secure. You can ask about Anti-Theft, Siren Alarms, Live Map Tracking, or Geofencing. If you are experiencing any technical issue, let me know and I will immediately escalate it to our Support Team.';
    }
  }

  void _showReportIssueModal() {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    String category = 'Anti-Theft & Alarm';
    bool isSubmitting = false;

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
            return Padding(
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.danger.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.report_problem_rounded, color: AppColors.danger, size: 24),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Report Issue to Support',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.navyDark),
                              ),
                              Text(
                                'Will be routed directly to Support Desk',
                                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    const Text('Issue Category', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: category,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Anti-Theft & Alarm', child: Text('Anti-Theft & Alarm')),
                        DropdownMenuItem(value: 'GPS Live Tracking', child: Text('GPS Live Tracking')),
                        DropdownMenuItem(value: 'Vehicle Geofence', child: Text('Vehicle Geofence')),
                        DropdownMenuItem(value: 'Account & Device Share', child: Text('Account & Device Share')),
                        DropdownMenuItem(value: 'Other Issue', child: Text('Other Issue')),
                      ],
                      onChanged: (val) {
                        if (val != null) setModalState(() => category = val);
                      },
                    ),
                    const SizedBox(height: 14),
                    const Text('Title / Subject', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: titleController,
                      decoration: InputDecoration(
                        hintText: 'e.g. Siren alert query / GPS signal drop',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text('Issue Description', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: descController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'Describe what happened in detail...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.all(14),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.danger,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                final desc = descController.text.trim();
                                if (desc.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Please enter an issue description')),
                                  );
                                  return;
                                }

                                setModalState(() => isSubmitting = true);
                                final userEmail =
                                    authService.email.isNotEmpty ? authService.email : 'user@raahmilo.com';
                                final uid = authService.uid.isNotEmpty ? authService.uid : 'user_guest';

                                final res = await apiService.sendSupportIssueAlert(
                                  userEmail: userEmail,
                                  userUid: uid,
                                  issueDescription:
                                      'Category: $category\nSubject: ${titleController.text.trim()}\nDetails: $desc',
                                  priority: 'HIGH',
                                );

                                final ticketId = res['ticketId'] ?? 'RM-8921';

                                NotificationService().addNotification(
                                  title: 'Support Issue Sent (#$ticketId)',
                                  subtitle: 'Dispatched to Support Desk',
                                  type: NotificationType.supportTicket,
                                );

                                if (context.mounted) {
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Row(
                                        children: [
                                          const Icon(Icons.check_circle_rounded, color: Colors.white),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text('Issue forwarded to Support Desk! Ticket #$ticketId'),
                                          ),
                                        ],
                                      ),
                                      backgroundColor: AppColors.success,
                                    ),
                                  );

                                  // Append in chat
                                  _handleSendMessage('🚨 Reported Issue: $category - ${titleController.text.trim()}');
                                }
                              },
                        icon: isSubmitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.send_rounded),
                        label: Text(isSubmitting ? 'Sending Ticket...' : 'Submit to Support Team'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: Color(0xFF2563EB),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(Icons.smart_toy_rounded, color: Colors.white, size: 20),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'RaahMilo AI Support',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.navyDark),
                  ),
                  Row(
                    children: [
                      const Icon(Icons.circle, size: 8, color: AppColors.success),
                      const SizedBox(width: 4),
                      Text(
                        _selectedLanguage == 'en' ? 'Online • English' : 'Online • हिंदी',
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // Language Switcher Toggle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            decoration: BoxDecoration(
              color: AppColors.tileBackground,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () => _toggleLanguage('en'),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _selectedLanguage == 'en' ? AppColors.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'EN',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _selectedLanguage == 'en' ? Colors.white : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => _toggleLanguage('hi'),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _selectedLanguage == 'hi' ? AppColors.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'HI',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _selectedLanguage == 'hi' ? Colors.white : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Report Issue to Support Team',
            icon: const Icon(Icons.report_problem_outlined, color: AppColors.danger),
            onPressed: _showReportIssueModal,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // Clean banner without exposing personal email
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFFEFF6FF),
            child: Row(
              children: [
                const Icon(Icons.shield_outlined, color: Color(0xFF2563EB), size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectedLanguage == 'en'
                        ? 'Reported issues are automatically forwarded to our Support Desk'
                        : 'Aapke issues turant hamare Support Desk ko forward ho jate hain',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF1E40AF)),
                  ),
                ),
                InkWell(
                  onTap: _showReportIssueModal,
                  child: Text(
                    _selectedLanguage == 'en' ? 'Report' : 'Shikayat',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF2563EB)),
                  ),
                ),
              ],
            ),
          ),

          // Message list
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                return _buildMessageBubble(msg);
              },
            ),
          ),

          if (_isTyping)
            Padding(
              padding: const EdgeInsets.only(left: 20, bottom: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _selectedLanguage == 'en' ? 'AI is typing...' : 'AI uttar de raha hai...',
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // Quick chips
          Container(
            height: 40,
            margin: const EdgeInsets.only(bottom: 6),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _quickSuggestions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final suggestion = _quickSuggestions[index];
                final isReport = suggestion.contains('Report Issue');
                return ActionChip(
                  label: Text(
                    suggestion,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isReport ? AppColors.danger : AppColors.textPrimary,
                    ),
                  ),
                  backgroundColor: isReport ? AppColors.dangerLight : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: isReport ? AppColors.danger.withValues(alpha: 0.4) : AppColors.border,
                    ),
                  ),
                  onPressed: () {
                    if (isReport) {
                      _showReportIssueModal();
                    } else {
                      _handleSendMessage(suggestion);
                    }
                  },
                );
              },
            ),
          ),

          // Input field
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.tileBackground,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _controller,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: _selectedLanguage == 'en'
                              ? 'Type your message or issue...'
                              : 'Apna message ya samasya likhein...',
                          hintStyle: const TextStyle(fontSize: 14, color: AppColors.textMuted),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        ),
                        onSubmitted: (_) => _handleSendMessage(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                      onPressed: () => _handleSendMessage(),
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

  Widget _buildMessageBubble(ChatMessage msg) {
    return Align(
      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: msg.isUser ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(msg.isUser ? 18 : 4),
            bottomRight: Radius.circular(msg.isUser ? 4 : 18),
          ),
          border: msg.isUser ? null : Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (msg.ticketId != null) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.dangerLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.mark_email_read_rounded, size: 14, color: AppColors.danger),
                    const SizedBox(width: 6),
                    Text(
                      'Ticket #${msg.ticketId} Dispatched to Support Desk',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.danger),
                    ),
                  ],
                ),
              ),
            ],
            Text(
              msg.text,
              style: TextStyle(
                fontSize: 14,
                color: msg.isUser ? Colors.white : AppColors.textPrimary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(
                '${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}',
                style: TextStyle(
                  fontSize: 10,
                  color: msg.isUser ? Colors.white70 : AppColors.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
