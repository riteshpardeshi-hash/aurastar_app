import 'package:flutter/material.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/aura_action_sheet.dart';
import '../../account/screens/my_account_screen.dart';
import '../../challenges/screens/all_general_challenges_screen.dart';
import '../../challenges/screens/brand_challenges_screen.dart';
import '../../leaderboard/leaderboard_screen.dart';
import 'create_challenge.dart';
import 'creator_challenges_screen.dart';
import 'creator_insights_screen.dart';
import 'creator_settings_screen.dart';

/// Center-FAB destination for creators — mirrors the player-facing
/// [showAuraActionSheet] options but as a full screen of creator actions
/// instead of a bottom sheet, since a creator's next step is usually a
/// dedicated screen (create/manage/analyse) rather than a quick pick.
class CreatorActivityScreen extends StatelessWidget {
  const CreatorActivityScreen({super.key});

  static const _bg = Color(0xFF080810);
  static const _accent = Color(0xFF7B2CBF);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          Expanded(
            child: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(context),
                  const SizedBox(height: 20),
                  _ActivityRow(
                    icon: Icons.add_rounded,
                    label: 'Create challenge',
                    onTap:
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CreateChallenge(),
                          ),
                        ),
                  ),
                  _ActivityRow(
                    icon: Icons.track_changes_rounded,
                    label: 'My Challenges',
                    onTap:
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CreatorChallengesScreen(),
                          ),
                        ),
                  ),
                  _ActivityRow(
                    icon: Icons.bar_chart_rounded,
                    label: 'Insights',
                    onTap:
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CreatorInsightsScreen(),
                          ),
                        ),
                  ),
                  _ActivityRow(
                    icon: Icons.settings_rounded,
                    label: 'Creator Settings',
                    onTap:
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CreatorSettingsScreen(),
                          ),
                        ),
                  ),
                ],
              ),
            ),
          ),
          _buildBottomNav(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          ),
          const SizedBox(width: 4),
          const Text(
            'Activity',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              fontFamily: 'ClashDisplay',
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom nav — same layout as the other creator-facing screens' nav so
  // navigating away from here doesn't feel like leaving a different app.
  Widget _buildBottomNav(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: SizedBox(
          height: 74,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: 62,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF111111),
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _navItem(
                              icon: Icons.emoji_events_rounded,
                              label: 'Challenges',
                              onTap:
                                  () => Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                      builder:
                                          (_) =>
                                              const AllGeneralChallengesScreen(),
                                    ),
                                  ),
                            ),
                            _navItem(
                              icon: Icons.storefront_rounded,
                              label: 'Brand Challenges',
                              onTap:
                                  () => Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                      builder:
                                          (_) => const BrandChallengesScreen(),
                                    ),
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 58),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _navItem(
                              icon: Icons.leaderboard_rounded,
                              label: 'Leaderboard',
                              onTap:
                                  () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const LeaderboardScreen(),
                                    ),
                                  ),
                            ),
                            _navItem(
                              icon: Icons.person_rounded,
                              label: 'Profile',
                              onTap:
                                  () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const MyAccountScreen(),
                                    ),
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 0,
                // Already here — re-tapping the FAB just re-opens this screen's
                // entry point instead of pushing a duplicate copy of itself.
                child: GestureDetector(
                  onTap: () => showAuraActionSheet(context),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF0D0020),
                      border: Border.all(
                        color: _accent.withValues(alpha: 0.7),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _accent.withValues(alpha: 0.5),
                          blurRadius: 18,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(13),
                      child: Image.asset(
                        'assets/images/Aura Arena Mono.png',
                        fit: BoxFit.contain,
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

  Widget _navItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white54, size: 22),
            const SizedBox(height: 3),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textFaint,
                fontSize: 9,
                fontFamily: 'SpaceGrotesk',
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActivityRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFF7B2FF7), Color(0xFF9B4DFF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'SpaceGrotesk',
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white38,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
