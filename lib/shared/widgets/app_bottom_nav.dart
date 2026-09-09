import 'package:flutter/material.dart';
import '../../core/services/auth_api_service.dart';
import '../../features/challenges/screens/challenge_reels_screen.dart';
import '../../features/shell/main_shell_controller.dart';
import '../theme/app_colors.dart';
import 'avatar_widget.dart';

/// Which of [AppBottomNav]'s tabs (if any) corresponds to the screen it's
/// shown on — highlights that tab and makes tapping it a no-op instead of
/// switching to a copy of the screen the user is already on.
enum AppNavTab { home, search, leaderboard, profile }

extension AppNavTabIndex on AppNavTab {
  /// Position in [MainShell]'s `IndexedStack` — must match the order the
  /// shell builds its pages in.
  int get shellIndex => switch (this) {
        AppNavTab.home => 0,
        AppNavTab.search => 1,
        AppNavTab.leaderboard => 2,
        AppNavTab.profile => 3,
      };
}

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

  // The four tab screens are kept permanently alive inside [MainShell]'s
  // IndexedStack, so a tab switch is never a route push/rebuild — it's just
  // asking the shell to reveal an already-built screen (no reload, no
  // spinner). Any drill-down screen pushed on top of the shell renders its
  // own AppBottomNav too; from there we first pop back down to the shell so
  // it's on screen to receive the request. On the shell's own screens
  // `popUntil(isFirst)` is a no-op.
  void _switchTab(BuildContext context, AppNavTab tab) {
    if (widget.activeTab == tab) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    MainShellController.instance.select(tab.shellIndex);
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
                        onTap: () => _switchTab(context, AppNavTab.home),
                      ),
                      _navItem(
                        icon: Icons.search_rounded,
                        label: 'Search',
                        active: widget.activeTab == AppNavTab.search,
                        onTap: () => _switchTab(context, AppNavTab.search),
                      ),
                      const SizedBox(width: 58),
                      _navItem(
                        icon: Icons.leaderboard_rounded,
                        label: 'Leaderboard',
                        active: widget.activeTab == AppNavTab.leaderboard,
                        onTap: () => _switchTab(context, AppNavTab.leaderboard),
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
                  behavior: HitTestBehavior.opaque,
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
      // Without this the tap only lands on the painted avatar/label pixels;
      // the padding around them is dead. Opaque makes the whole item tappable.
      behavior: HitTestBehavior.opaque,
      onTap: () => _switchTab(context, AppNavTab.profile),
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
      // Opaque so the whole padded column — not just the 22px glyph and the
      // tiny label — registers the tap. Small hit targets here were making
      // taps miss and forcing users to tap 2–3 times.
      behavior: HitTestBehavior.opaque,
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
