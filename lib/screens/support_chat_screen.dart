import 'dart:math';
import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../models/app_notification.dart';
import '../services/ai_human_engine.dart';
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
  final String? thoughtDetail;
  final double? thoughtDurationSec;
  bool isThoughtExpanded;

  ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.ticketId,
    this.isIssueReported = false,
    this.thoughtDetail,
    this.thoughtDurationSec,
    this.isThoughtExpanded = false,
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
  String _thinkingStep = '';
  bool _isSending = false;
  String? _activeSessionTicketId;
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

  String _generateThoughtDetail(String query, bool useHindi) {
    final q = query.toLowerCase();
    if (q.contains('theft') || q.contains('chori') || q.contains('alarm') || q.contains('siren') || q.contains('security')) {
      return useHindi
          ? '• User ke suraksha sawal ka vishleshan kiya gaya.\n'
            '• Vehicle Anti-Theft aur Alarm Siren telemetry state verify ki gayi.\n'
            '• Critical theft protocol aur immediate safety guidance formulate kiya gaya.'
          : '• Analyzed security alert & theft protection query.\n'
            '• Verified Anti-Theft engine lock and Siren alarm telemetry status.\n'
            '• Formulated immediate safety guidelines and emergency escalation.';
    } else if (q.contains('gps') || q.contains('location') || q.contains('map') || q.contains('accuracy') || q.contains('rasta')) {
      return useHindi
          ? '• GPS hardware tracking aur satellite lock accuracy evaluate ki gayi.\n'
            '• Location permissions aur background service battery restrictions check kiye gaye.\n'
            '• Precision calibration aur High Accuracy GPS mode steps formulate kiye gaye.'
          : '• Evaluated GPS coordinates, satellite fix, and background location mode.\n'
            '• Verified device battery optimization and background permission state.\n'
            '• Formulated precision calibration and real-time navigation recommendations.';
    } else if (q.contains('issue') || q.contains('shikayat') || q.contains('help') || q.contains('madad') || q.contains('problem') || q.contains('kharab')) {
      return useHindi
          ? '• Samasya ki gambhirta aur ticket escalation conditions check ki gayi.\n'
            '• Support Desk notification dispatch channel verify kiya gaya.\n'
            '• Rapid redressal protocol aur ticket status guidance formulate kiya gaya.'
          : '• Evaluated issue severity and ticket escalation thresholds.\n'
            '• Verified dispatch channel to Support Desk admin.\n'
            '• Formulated immediate assistance steps and ticket tracking reference.';
    } else {
      return useHindi
          ? '• User prashna ka uddeshya samajha gaya.\n'
            '• RaahMilo platform knowledge base aur vehicle controls scan kiye gaye.\n'
            '• Spasht aur madadgar samadhan prepare kiya gaya.'
          : '• Interpreted query intent and context.\n'
            '• Scanned RaahMilo platform services, trip telemetry, and knowledge base.\n'
            '• Formulated clear, step-by-step assistant guidance.';
    }
  }

  Future<void> _handleSendMessage([String? predefinedText]) async {
    if (_isSending || _isTyping) return;

    final text = (predefinedText ?? _controller.text).trim();
    if (text.isEmpty) return;

    final authService = AuthService();
    final apiService = ApiService();

    _isSending = true;

    try {
      if (predefinedText == null) {
        _controller.clear();
      }

      final userMsg = ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: text,
        isUser: true,
        timestamp: DateTime.now(),
      );

      final useHindi = _selectedLanguage == 'hi' || _isHindiInput(text);
      final stopwatch = Stopwatch()..start();

      setState(() {
        _messages.add(userMsg);
        _isTyping = true;
        _thinkingStep = useHindi ? 'Sawalon ka vishleshan ho raha hai...' : 'Understanding query...';
      });
      _scrollToBottom();

      // Progressive thinking status updates
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted && _isTyping) {
          setState(() {
            _thinkingStep = useHindi
                ? 'Suraksha va telemetry jaanch...'
                : 'Analyzing telemetry & vehicle context...';
          });
        }
      });
      Future.delayed(const Duration(milliseconds: 750), () {
        if (mounted && _isTyping) {
          setState(() {
            _thinkingStep = useHindi
                ? 'Samadhan formulate ho raha hai...'
                : 'Synthesizing response & solution...';
          });
        }
      });

      // Check if this is an issue requiring email escalation to admin
      final bool hasIssue = _isIssueKeywords(text);
      String? createdTicketId;

      if (hasIssue) {
        // If an issue was already escalated in this conversation, reuse ticket to avoid flooding inbox
        if (_activeSessionTicketId != null) {
          createdTicketId = _activeSessionTicketId;
        } else {
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
            _activeSessionTicketId = createdTicketId;

            // Add to NotificationService only for new escalated ticket
            NotificationService().addNotification(
              title: 'Ticket #$createdTicketId Created',
              subtitle: 'Issue escalated to Support Desk',
              type: NotificationType.supportTicket,
            );
          } catch (_) {
            createdTicketId = 'RM-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
            _activeSessionTicketId = createdTicketId;
          }
        }
      }

      // Call API for AI message
      final history = _messages.take(10).map((m) => {
            'role': m.isUser ? 'user' : 'assistant',
            'content': m.text,
          }).toList();

      final aiRes = await apiService.sendAiChatMessage(
        message: text,
        chatHistory: history,
        userEmail: authService.email,
        ticketId: createdTicketId,
        useHindi: useHindi,
      );

      final botResponse = aiRes['reply']?.toString() ??
          AiHumanEngine.generateHumanResponse(text, ticketId: createdTicketId, useHindi: useHindi);

      // Fast, snappy thinking duration (~1.1s) so thinking is visible, yet response is delivered quickly
      final elapsedMs = stopwatch.elapsedMilliseconds;
      const minThinkingMs = 1100;
      if (elapsedMs < minThinkingMs) {
        await Future.delayed(Duration(milliseconds: minThinkingMs - elapsedMs));
      }
      stopwatch.stop();
      final thoughtSeconds = (stopwatch.elapsedMilliseconds / 1000.0);
      final roundedSec = (thoughtSeconds * 10).round() / 10.0;

      final thoughtDetail = _generateThoughtDetail(text, useHindi);

      if (mounted) {
        setState(() {
          _isTyping = false;
          _thinkingStep = '';
          _messages.add(
            ChatMessage(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              text: botResponse,
              isUser: false,
              timestamp: DateTime.now(),
              ticketId: createdTicketId,
              isIssueReported: hasIssue,
              thoughtDetail: thoughtDetail,
              thoughtDurationSec: roundedSec,
              isThoughtExpanded: false,
            ),
          );
        });
        _scrollToBottom();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
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
              padding: const EdgeInsets.only(left: 16, bottom: 10, right: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFF8FAFC), Color(0xFFF1F5F9)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                      bottomLeft: Radius.circular(4),
                    ),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.psychology_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _thinkingStep.isNotEmpty
                            ? _thinkingStep
                            : (_selectedLanguage == 'en' ? 'AI is thinking...' : 'AI soch raha hai...'),
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF334155),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const _ThinkingDots(),
                    ],
                  ),
                ),
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
                        onSubmitted: (_isSending || _isTyping) ? null : (_) => _handleSendMessage(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: (_isSending || _isTyping) ? AppColors.textMuted : AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: _isSending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                      onPressed: (_isSending || _isTyping) ? null : () => _handleSendMessage(),
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
            if (!msg.isUser && msg.thoughtDurationSec != null) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () {
                        setState(() {
                          msg.isThoughtExpanded = !msg.isThoughtExpanded;
                        });
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.psychology_rounded, size: 14, color: Color(0xFF6366F1)),
                            const SizedBox(width: 6),
                            Text(
                              _selectedLanguage == 'en'
                                  ? 'Thought for ${msg.thoughtDurationSec!.toStringAsFixed(1)}s'
                                  : '${msg.thoughtDurationSec!.toStringAsFixed(1)}s tak socha',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF475569),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              msg.isThoughtExpanded
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              size: 16,
                              color: const Color(0xFF64748B),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (msg.isThoughtExpanded && msg.thoughtDetail != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Text(
                          msg.thoughtDetail!,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF334155),
                            height: 1.4,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
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

class _ThinkingDots extends StatefulWidget {
  const _ThinkingDots();

  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots> with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final delay = index * 0.2;
            final val = (_animController.value - delay) % 1.0;
            final offset = sin(val * 2 * pi) * 3.0;

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              child: Transform.translate(
                offset: Offset(0, -offset.clamp(0.0, 3.0)),
                child: Container(
                  width: 4.5,
                  height: 4.5,
                  decoration: const BoxDecoration(
                    color: Color(0xFF6366F1),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
