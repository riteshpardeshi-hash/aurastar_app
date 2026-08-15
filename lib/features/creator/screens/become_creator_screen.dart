import 'package:flutter/material.dart';
import '../../../core/services/creator_page_service.dart';
import '../../../shared/theme/app_colors.dart';
import 'create_creator_profile_screen.dart';

/// Standalone entry point for the "Become a Creator" dashboard button.
///
/// Always shows the Aura progress bar toward the Creator Program threshold
/// (sourced from `/creator/progress`, so it matches whatever the backend
/// actually requires rather than a hardcoded 500). Once the user qualifies,
/// a CTA hands off into [CreateCreatorProfileScreen], which re-checks
/// eligibility itself and goes straight to the setup form.
class BecomeCreatorScreen extends StatefulWidget {
  const BecomeCreatorScreen({super.key});

  @override
  State<BecomeCreatorScreen> createState() => _BecomeCreatorScreenState();
}

class _BecomeCreatorScreenState extends State<BecomeCreatorScreen> {
  static const _bg = Color(0xFF080810);
  static const _accent = Color(0xFF7B2CBF);

  final _service = CreatorPageService();
  Future<Map<String, dynamic>>? _progressFuture;

  @override
  void initState() {
    super.initState();
    _progressFuture = _service.fetchProgress();
  }

  void _reload() {
    setState(() => _progressFuture = _service.fetchProgress());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Become a Creator'),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _progressFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
                child: CircularProgressIndicator(color: _accent));
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_off_rounded,
                        color: Colors.white38, size: 40),
                    const SizedBox(height: 16),
                    const Text('Failed to load your progress.',
                        style: TextStyle(color: AppColors.textMuted)),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _reload,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _accent),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          final progress = snap.data ?? {};
          final currentAura = (progress['currentAura'] as num?)?.toInt() ?? 0;
          final requiredAura =
              (progress['requiredAura'] as num?)?.toInt() ?? 500;
          final pct = requiredAura > 0
              ? (currentAura / requiredAura).clamp(0.0, 1.0)
              : 0.0;
          final qualified = currentAura >= requiredAura;

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF2D0B5A), Color(0xFF0A1A40)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _accent.withValues(alpha: 0.30)),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        qualified
                            ? Icons.star_rounded
                            : Icons.hourglass_top_rounded,
                        color: const Color(0xFFD4A8FF),
                        size: 36,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '$currentAura / $requiredAura Aura',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'ClashDisplay',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: pct),
                        duration: const Duration(milliseconds: 900),
                        curve: Curves.easeOutCubic,
                        builder: (_, v, __) => ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: v,
                            minHeight: 10,
                            backgroundColor: Colors.white.withValues(alpha: 0.10),
                            valueColor:
                                const AlwaysStoppedAnimation(_accent),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        qualified
                            ? 'You\'ve unlocked the Creator Program!'
                            : 'Keep completing challenges to unlock the Creator Program.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 13, height: 1.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                if (qualified)
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const CreateCreatorProfileScreen()),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        textStyle: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      child: const Text('Create Your Creator Profile'),
                    ),
                  )
                else
                  Text(
                    '${(requiredAura - currentAura).clamp(0, requiredAura)} Aura to go — take on more challenges to close the gap.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textFaint, fontSize: 13),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
