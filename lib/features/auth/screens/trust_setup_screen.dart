import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/app_text_styles.dart';
import 'setup_screen.dart';

class TrustSetupScreen extends StatefulWidget {
  const TrustSetupScreen({super.key});

  @override
  State<TrustSetupScreen> createState() => _TrustSetupScreenState();
}

class _TrustSetupScreenState extends State<TrustSetupScreen> {
  static const _bg     = Color(0xFF080810);
  static const _accent = Color(0xFF7B2CBF);

  static const _pledges = [
    (
      icon: Icons.videocam_outlined,
      title: 'I will only submit my own videos',
      body: 'No re-uploads, stolen clips, or content recorded by someone else.',
    ),
    (
      icon: Icons.shield_outlined,
      title: 'I will not use fake accounts or bots',
      body: 'Creating duplicate accounts or using automation is strictly prohibited.',
    ),
    (
      icon: Icons.people_outline_rounded,
      title: 'I will treat other members with respect',
      body: 'No harassment, hate speech, or harmful behaviour toward other users.',
    ),
    (
      icon: Icons.sports_score_outlined,
      title: 'I will compete with integrity',
      body: 'No cheating, score manipulation, or exploitation of platform loopholes.',
    ),
    (
      icon: Icons.warning_amber_rounded,
      title: 'I understand the consequences',
      body: 'Violations may result in score removal, account suspension, or a permanent ban.',
    ),
  ];

  bool _agreed = false;
  bool _saving = false;

  Future<void> _letsGo() async {
    if (!_agreed || _saving) return;
    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'trustPledgeAcceptedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (_) {
      // Non-blocking: proceed even if write fails
    }
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const SetupScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header icon ────────────────────────────────────────────────
              Center(
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: _accent.withValues(alpha: 0.40), width: 1.5),
                  ),
                  child: const Icon(Icons.handshake_outlined,
                      color: _accent, size: 30),
                ),
              ),
              const SizedBox(height: 20),
              const Text('Community Pledge', style: AppTextStyles.compactTitle),
              const SizedBox(height: 4),
              Text(
                'Please read and accept our community standards.',
                style: TextStyle(
                    color: AppColors.textMuted, fontSize: 14),
              ),
              const SizedBox(height: 24),

              // ── Pledge list (non-interactive) ──────────────────────────────
              Expanded(
                child: ListView.separated(
                  itemCount: _pledges.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final p = _pledges[i];
                    return _PledgeTile(
                      icon: p.icon,
                      title: p.title,
                      body: p.body,
                    );
                  },
                ),
              ),

              const SizedBox(height: 20),

              // ── I agree checkbox ───────────────────────────────────────────
              GestureDetector(
                onTap: () => setState(() => _agreed = !_agreed),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: _agreed ? _accent : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _agreed
                              ? _accent
                              : Colors.white.withValues(alpha: 0.35),
                          width: 1.5,
                        ),
                      ),
                      child: _agreed
                          ? const Icon(Icons.check_rounded,
                              color: Colors.white, size: 14)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'I agree to the community pledge',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.80),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── Let's Go button ────────────────────────────────────────────
              AnimatedOpacity(
                opacity: _agreed ? 1.0 : 0.4,
                duration: const Duration(milliseconds: 250),
                child: GestureDetector(
                  onTap: _letsGo,
                  child: Container(
                    width: double.infinity,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: _agreed
                          ? const LinearGradient(
                              colors: [Color(0xFF9B4DCA), Color(0xFF5A189A)],
                            )
                          : null,
                      color: _agreed
                          ? null
                          : Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: _agreed
                          ? [
                              BoxShadow(
                                color: _accent.withValues(alpha: 0.45),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ]
                          : null,
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
                              "Let's Go",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.3,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Static pledge tile ─────────────────────────────────────────────────────────

class _PledgeTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _PledgeTile({
    required this.icon,
    required this.title,
    required this.body,
  });

  static const _accent = Color(0xFF7B2CBF);
  static const _card   = Color(0xFF100A20);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: _accent, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.40),
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
