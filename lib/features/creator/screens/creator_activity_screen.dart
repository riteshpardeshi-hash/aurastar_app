import 'package:flutter/material.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import 'create_challenge.dart';
import 'creator_challenges_screen.dart';
import 'creator_insights_screen.dart';
import 'creator_settings_screen.dart';

/// Center-FAB destination for creators — mirrors the player-facing action
/// sheet's options but as a full screen of creator actions instead of a
/// bottom sheet, since a creator's next step is usually a dedicated screen
/// (create/manage/analyse) rather than a quick pick.
class CreatorActivityScreen extends StatelessWidget {
  const CreatorActivityScreen({super.key});

  static const _bg = Color(0xFF080810);

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
          const AppBottomNav(),
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
