import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/api_client.dart';
import '../../dashboard/dashboard.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  static const _purple = Color(0xFF7B2CBF);
  static const _bg = Color(0xFF080810);

  final _referralCodeCtrl = TextEditingController();
  bool _saving = false;

  static const _perms = [
    (
      icon: Icons.videocam_rounded,
      title: 'Camera',
      body: 'Record your challenge attempts. Required for scoring.',
      color: Color(0xFF54A0FF),
    ),
    (
      icon: Icons.mic_rounded,
      title: 'Microphone',
      body: 'Sound match is part of your AuraSense score.',
      color: Color(0xFFFF6B6B),
    ),
    (
      icon: Icons.notifications_rounded,
      title: 'Notifications',
      body: 'Get score results, rank alerts and streak reminders.',
      color: Color(0xFFFF9F43),
    ),
    (
      icon: Icons.photo_library_rounded,
      title: 'Photo Library',
      body: 'Save and share your Flex Card after a great score.',
      color: Color(0xFF5F27CD),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadPendingReferralCode();
  }

  Future<void> _loadPendingReferralCode() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('pending_referral_code') ?? '';
    if (code.isNotEmpty && mounted) {
      setState(() => _referralCodeCtrl.text = code);
    }
  }

  Future<void> _finish() async {
    final uid = await ApiClient().userId;
    if (uid == null || uid.isEmpty) {
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const Dashboard()),
        (_) => false,
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('pending_referral_code');
      // TODO: wire referral code to backend API when endpoint is available
    } catch (_) {} finally {
      if (mounted) setState(() => _saving = false);
    }

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const Dashboard()),
      (_) => false,
    );
  }

  @override
  void dispose() {
    _referralCodeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _bg,
        body: Stack(
          children: [
            // Purple glow top-right
            Positioned(
              top: -60,
              right: -60,
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _purple.withValues(alpha: 0.22),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Step indicator ───────────────────────────────────────
                    Row(
                      children: List.generate(4, (i) {
                        return Container(
                          margin: const EdgeInsets.only(right: 6),
                          width: i == 3 ? 24 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: i <= 3
                                ? _purple
                                : Colors.white.withValues(alpha: 0.20),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        );
                      }),
                    ),

                    SizedBox(height: size.height * 0.04),

                    // ── Title ────────────────────────────────────────────────
                    const Text(
                      'Allow access',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'These are needed for recording and scoring your challenges',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),

                    SizedBox(height: size.height * 0.038),

                    // ── Permission cards ─────────────────────────────────────
                    ..._perms.map((p) => _PermCard(
                          icon: p.icon,
                          title: p.title,
                          body: p.body,
                          color: p.color,
                        )),

                    SizedBox(height: size.height * 0.038),

                    // ── Referral code ────────────────────────────────────────
                    Row(
                      children: [
                        Icon(Icons.group_add_rounded,
                            color: _purple.withValues(alpha: 0.70), size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'Got a referral code? (Optional)',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12)),
                      ),
                      child: TextField(
                        controller: _referralCodeCtrl,
                        textCapitalization: TextCapitalization.characters,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          letterSpacing: 2,
                          fontFamily: 'SpaceGrotesk',
                        ),
                        cursorColor: _purple,
                        decoration: InputDecoration(
                          hintText: 'e.g. X7KP2M9Q',
                          hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.25),
                            fontSize: 13,
                            letterSpacing: 0,
                            fontFamily: 'SpaceGrotesk',
                          ),
                          prefixIcon: Icon(Icons.loyalty_rounded,
                              color: Colors.white.withValues(alpha: 0.35),
                              size: 20),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                        ),
                      ),
                    ),

                    SizedBox(height: size.height * 0.05),

                    // ── CTA ──────────────────────────────────────────────────
                    GestureDetector(
                      onTap: _saving ? null : _finish,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: double.infinity,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: _saving
                                ? [Colors.grey.shade800, Colors.grey.shade700]
                                : const [Color(0xFF9B4DCA), Color(0xFF5A189A)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: _saving
                              ? null
                              : [
                                  BoxShadow(
                                    color: _purple.withValues(alpha: 0.45),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                  )
                                ],
                        ),
                        child: Center(
                          child: _saving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2.5),
                                )
                              : const Text(
                                  'Enable & Start Playing',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Privacy note ─────────────────────────────────────────
                    Center(
                      child: Text(
                        'Permissions are requested when you first use each feature.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.25),
                          fontSize: 11,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Permission card ────────────────────────────────────────────────────────────

class _PermCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Color color;

  const _PermCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(body,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 12,
                        height: 1.4)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.check_circle_rounded,
              color: color.withValues(alpha: 0.65), size: 20),
        ],
      ),
    );
  }
}
