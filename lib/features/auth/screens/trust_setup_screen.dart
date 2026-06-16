import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'setup_screen.dart';

class TrustSetupScreen extends StatefulWidget {
  const TrustSetupScreen({super.key});

  @override
  State<TrustSetupScreen> createState() => _TrustSetupScreenState();
}

class _TrustSetupScreenState extends State<TrustSetupScreen>
    with TickerProviderStateMixin {
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

  late final List<bool> _checked;
  late final List<AnimationController> _checkCtrls;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _checked = List.filled(_pledges.length, false);
    _checkCtrls = List.generate(
      _pledges.length,
      (_) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 250),
      ),
    );
  }

  @override
  void dispose() {
    for (final c in _checkCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _allChecked => _checked.every((v) => v);

  void _toggle(int i) {
    setState(() => _checked[i] = !_checked[i]);
    if (_checked[i]) {
      _checkCtrls[i].forward();
    } else {
      _checkCtrls[i].reverse();
    }
  }

  Future<void> _agree() async {
    if (!_allChecked || _saving) return;
    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'trustPledgeAcceptedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (_) {
      // Non-blocking: proceed to setup even if write fails
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
              // Header
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
              const Text(
                'Community Pledge',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Tap each item to confirm you understand.',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45), fontSize: 14),
              ),
              const SizedBox(height: 24),

              // Pledge items
              Expanded(
                child: ListView.separated(
                  itemCount: _pledges.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final p = _pledges[i];
                    return _PledgeItem(
                      icon: p.icon,
                      title: p.title,
                      body: p.body,
                      checked: _checked[i],
                      controller: _checkCtrls[i],
                      onTap: () => _toggle(i),
                    );
                  },
                ),
              ),

              const SizedBox(height: 20),

              // Progress indicator
              AnimatedOpacity(
                opacity: _allChecked ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 300),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_pledges.length, (i) {
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: _checked[i] ? 20 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _checked[i]
                              ? _accent
                              : Colors.white.withValues(alpha: 0.20),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                ),
              ),

              // Agree button
              AnimatedOpacity(
                opacity: _allChecked ? 1.0 : 0.4,
                duration: const Duration(milliseconds: 300),
                child: GestureDetector(
                  onTap: _agree,
                  child: Container(
                    width: double.infinity,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: _allChecked
                          ? const LinearGradient(
                              colors: [Color(0xFF9B4DCA), Color(0xFF5A189A)],
                            )
                          : null,
                      color: _allChecked
                          ? null
                          : Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: _allChecked
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
                              'I Agree — Let\'s Go',
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

// ── Pledge item ────────────────────────────────────────────────────────────────

class _PledgeItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final bool checked;
  final AnimationController controller;
  final VoidCallback onTap;

  const _PledgeItem({
    required this.icon,
    required this.title,
    required this.body,
    required this.checked,
    required this.controller,
    required this.onTap,
  });

  static const _accent = Color(0xFF7B2CBF);
  static const _card   = Color(0xFF100A20);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: checked
              ? _accent.withValues(alpha: 0.14)
              : _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: checked
                ? _accent.withValues(alpha: 0.60)
                : Colors.white.withValues(alpha: 0.08),
            width: checked ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon column
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: checked
                    ? _accent.withValues(alpha: 0.22)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon,
                  color: checked ? _accent : Colors.white38, size: 20),
            ),
            const SizedBox(width: 14),

            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: checked ? Colors.white : Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    body,
                    style: TextStyle(
                      color: Colors.white.withValues(
                          alpha: checked ? 0.55 : 0.35),
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // Check mark
            ScaleTransition(
              scale: CurvedAnimation(
                  parent: controller, curve: Curves.elasticOut),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: checked ? _accent : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: checked
                        ? _accent
                        : Colors.white.withValues(alpha: 0.25),
                    width: 1.5,
                  ),
                ),
                child: checked
                    ? const Icon(Icons.check_rounded,
                        color: Colors.white, size: 14)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
