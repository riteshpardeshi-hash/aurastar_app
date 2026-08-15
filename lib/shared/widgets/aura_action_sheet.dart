import 'package:flutter/material.dart';
import '../../features/challenges/screens/all_general_challenges_screen.dart';
import '../../features/challenges/screens/brand_challenges_screen.dart';
import '../../features/challenges/screens/trending_screen.dart';
import '../../features/account/screens/saved_challenges_screen.dart';
import '../theme/app_colors.dart';

/// Opens the guided center-button action sheet.
/// Call from any screen that hosts the bottom nav.
void showAuraActionSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _AuraActionSheet(parentContext: context),
  );
}

class _AuraActionSheet extends StatelessWidget {
  final BuildContext parentContext;
  const _AuraActionSheet({required this.parentContext});

  static const _bg     = Color(0xFF0D0D1A);
  static const _accent = Color(0xFF7B2CBF);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: _accent.withValues(alpha: 0.35), width: 1.5),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 18),

          // Header
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _accent.withValues(alpha: 0.15),
                  border: Border.all(color: _accent.withValues(alpha: 0.40)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Image.asset('assets/images/Aura Arena Mono.png', fit: BoxFit.contain),
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'What do you want to do?',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Options
          _option(
            context: context,
            icon: Icons.flag_rounded,
            color: _accent,
            label: 'Take a Challenge',
            subtitle: 'Browse all challenges and submit',
            onTap: () => _navigate(context, const AllGeneralChallengesScreen()),
          ),
          const SizedBox(height: 10),
          _option(
            context: context,
            icon: Icons.store_rounded,
            color: const Color(0xFF4B6EF6),
            label: 'Brand Challenges',
            subtitle: 'Sponsored & brand-owned challenges',
            onTap: () => _navigate(context, const BrandChallengesScreen()),
          ),
          const SizedBox(height: 10),
          _option(
            context: context,
            icon: Icons.local_fire_department_rounded,
            color: const Color(0xFFFF6B35),
            label: 'Trending Now',
            subtitle: "See what's hot right now",
            onTap: () => _navigate(context, const TrendingScreen()),
          ),
          const SizedBox(height: 10),
          _option(
            context: context,
            icon: Icons.bookmark_rounded,
            color: const Color(0xFFD4A8FF),
            label: 'Saved Challenges',
            subtitle: 'Your bookmarked challenges',
            onTap: () => _navigate(context, const SavedChallengesScreen()),
          ),
        ],
      ),
    );
  }

  void _navigate(BuildContext sheetContext, Widget screen) {
    Navigator.pop(sheetContext);
    Navigator.push(parentContext, MaterialPageRoute(builder: (_) => screen));
  }

  Widget _option({
    required BuildContext context,
    required IconData icon,
    required Color color,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(color: AppColors.textFaint, fontSize: 11)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 18),
          ],
        ),
      ),
    );
  }
}
