import 'package:flutter/material.dart';
import '../../core/services/auth_api_service.dart';
import '../../features/account/screens/my_account_screen.dart';
import '../../features/challenges/screens/all_general_challenges_screen.dart';
import '../../features/challenges/screens/challenge_reels_screen.dart';
import '../../features/leaderboard/leaderboard_screen.dart';
import '../theme/app_colors.dart';
import 'avatar_widget.dart';

/// Which of [AppBottomNav]'s tabs (if any) corresponds to the screen it's
/// shown on — highlights that tab and makes tapping it a no-op instead of
/// pushing a duplicate copy of the current screen. Dashboard is the "home"
/// screen every other tab returns to before pushing its destination.
enum AppNavTab { home, search, leaderboard, profile }

/// The single pill-shaped bottom nav + floating center action button used
/// on every top-level screen. Previously each screen (Dashboard, the
/// challenges list, the brand challenges list, creator activity) had its
/// own hand-copied version of this that had drifted apart — different
/// labels ("Brand" vs "Brand Challenges"), different icons (`person_rounded`
/// vs `person_outline_rounded`), different navigation methods (`push` vs
/// `pushReplacement` vs `popUntil`) even for the same tab, and one version
/// was a completely different flat-row design with no pill or FAB at all.
/// This widget is now the one source of truth — every screen instantiates
/// it instead of maintaining its own copy.
class AppBottomNav extends StatefulWidget {
  final AppNavTab? activeTab;

  const AppBottomNav({super.key, this.activeTab});

  @override
  State<AppBottomNav> createState() => _AppBottomNavState();
}

class _AppBottomNavState extends State<AppBottomNav> {
  static const _accent = Color(0xFF7B2CBF);

  String _displayName = '';
  String _photoUrl = '';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final profile = await AuthApiService().getProfile();
    if (!mounted || profile == null) return;
    setState(() {
      _displayName =
          (profile['displayName'] as String?)?.trim().isNotEmpty == true
              ? profile['displayName'] as String
              : (profile['profileName'] as String? ??
                  profile['username'] as String? ??
                  '');
      _photoUrl = (profile['avatar'] as String? ?? '').isNotEmpty
          ? profile['avatar'] as String
          : profile['profileImageUrl'] as String? ?? '';
    });
  }

  // Every tab (other than the one the current screen already is) returns to
  // Dashboard before pushing its destination, rather than pushing on top of
  // whatever screen the tap happened to originate from. Without this,
  // bouncing between tabs from a non-Dashboard screen stacks routes ever
  // deeper (Dashboard > Challenges > Leaderboard > Brand > ...) instead of
  // behaving like a normal tab bar — and this is the only way the resulting
  // stack shape actually matches "same as Dashboard" regardless of which
  // screen you tapped from.
  void _goTo(BuildContext context, AppNavTab tab, WidgetBuilder builder) {
    if (widget.activeTab == tab) return;
    Navigator.popUntil(context, (route) => route.isFirst);
    Navigator.push(context, MaterialPageRoute(builder: builder));
  }

  // Dashboard is always the app's root route (Splash reaches it via
  // pushReplacement, never a push), so "Home" just pops back to it instead
  // of pushing a new instance on top of itself.
  void _goHome(BuildContext context) {
    if (widget.activeTab == AppNavTab.home) return;
    Navigator.popUntil(context, (route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
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
              // Pill-shaped nav bar
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
                      width: 1,
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
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _navItem(
                        icon: Icons.home_rounded,
                        label: 'Home',
                        active: widget.activeTab == AppNavTab.home,
                        onTap: () => _goHome(context),
                      ),
                      _navItem(
                        icon: Icons.search_rounded,
                        label: 'Search',
                        active: widget.activeTab == AppNavTab.search,
                        onTap: () => _goTo(
                          context,
                          AppNavTab.search,
                          (_) => const AllGeneralChallengesScreen(),
                        ),
                      ),
                      const SizedBox(width: 58),
                      _navItem(
                        icon: Icons.leaderboard_rounded,
                        label: 'Leaderboard',
                        active: widget.activeTab == AppNavTab.leaderboard,
                        onTap: () => _goTo(
                          context,
                          AppNavTab.leaderboard,
                          (_) => const LeaderboardScreen(),
                        ),
                      ),
                      _profileNavItem(context),
                    ],
                  ),
                ),
              ),
              // Floating centre button — opens the full-screen vertical
              // challenge-video reel feed, for every role.
              Positioned(
                top: 0,
                child: GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ChallengeReelsScreen()),
                  ),
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

  Widget _profileNavItem(BuildContext context) {
    final active = widget.activeTab == AppNavTab.profile;
    final initial =
        _displayName.isNotEmpty ? _displayName[0].toUpperCase() : 'U';
    return GestureDetector(
      onTap: () => _goTo(
        context,
        AppNavTab.profile,
        (_) => const MyAccountScreen(),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            AvatarWidget(
              photoUrl: _photoUrl,
              fallbackText: initial,
              radius: 13,
              backgroundColor: active
                  ? _accent.withValues(alpha: 0.30)
                  : Colors.white24,
              textStyle: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'Profile',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: active ? _accent : AppColors.textFaint,
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

  Widget _navItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: active ? _accent : Colors.white54, size: 22),
            const SizedBox(height: 3),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: active ? _accent : AppColors.textFaint,
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
