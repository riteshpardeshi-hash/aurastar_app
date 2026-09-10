import 'package:flutter/material.dart';
import '../../core/services/auth_api_service.dart';
import '../../core/utils/nav_diag.dart';
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
    navDiag('AppBottomNav._switchTab: tap tab=$tab activeTab=${widget.activeTab} '
        'shellIndex=${tab.shellIndex}');
    if (widget.activeTab == tab) {
      navDiag('  -> early return (already on this tab)');
      return;
    }
    final nav = Navigator.of(context);
    var predicateCalls = 0;
    nav.popUntil((route) {
      predicateCalls++;
      return route.isFirst;
    });
    navDiag('  -> popUntil(isFirst): $predicateCalls predicate call(s), '
        '${predicateCalls - 1} pop(s); canPop now=${nav.canPop()}');
    MainShellController.instance.select(tab.shellIndex);
    navDiag('  -> MainShellController.select(${tab.shellIndex}) returned');
  }

  // Width reserved in the centre of the row for the floating action button.
  // The FAB's opaque hit box is [_fabSize] wide and sits inside this gap, so
  // keeping the gap wider than the FAB stops the FAB from stealing taps that
  // belong to the Search / Leaderboard slots on either side.
  static const _fabGap = 64.0;
  static const _fabSize = 56.0;
  static const _pillHeight = 62.0;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    navDiag('AppBottomNav.build: activeTab=${widget.activeTab} '
        'size=${mq.size} padding.bottom=${mq.padding.bottom} '
        'viewInsets.bottom=${mq.viewInsets.bottom} textScaler=${mq.textScaler}');
    // Clamp text scaling for the bar only. The labels are 9px and the row has
    // no room to grow: at the OS's larger font sizes the un-clamped row is
    // wider than the pill, Flutter clips the overflow, and — the actual bug —
    // pointer events are not delivered to the clipped-out region, so the last
    // items (Leaderboard, Profile) stop responding to taps on some devices.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: SafeArea(
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
                  height: _pillHeight,
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
                    // Equal-width Expanded slots (not spaceAround) so the row
                    // can never overflow the pill however narrow the device or
                    // large the font — each slot just gets tighter and its
                    // label ellipsises. Every slot is also full pill height, so
                    // the tap target is the whole slot, not the ~36px glyph +
                    // label stack it used to be (below the 48px min target).
                    child: Row(
                      children: [
                        Expanded(
                          child: _navItem(
                            icon: Icons.home_rounded,
                            label: 'Home',
                            active: widget.activeTab == AppNavTab.home,
                            onTap: () => _switchTab(context, AppNavTab.home),
                          ),
                        ),
                        Expanded(
                          child: _navItem(
                            icon: Icons.search_rounded,
                            label: 'Search',
                            active: widget.activeTab == AppNavTab.search,
                            onTap: () => _switchTab(context, AppNavTab.search),
                          ),
                        ),
                        const SizedBox(width: _fabGap),
                        Expanded(
                          child: _navItem(
                            icon: Icons.leaderboard_rounded,
                            label: 'Leaderboard',
                            active: widget.activeTab == AppNavTab.leaderboard,
                            onTap: () =>
                                _switchTab(context, AppNavTab.leaderboard),
                          ),
                        ),
                        Expanded(child: _profileNavItem(context)),
                      ],
                    ),
                  ),
                ),
                // Floating centre button — opens the full-screen vertical
                // challenge-video reel feed, for every role. Stretched full
                // width and centred so its opaque hit box stays a fixed
                // [_fabSize] square inside [_fabGap] and cannot overlap the
                // slots on either side.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        navDiag('AppBottomNav: centre FAB tapped -> push reels');
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ChallengeReelsScreen()),
                        );
                      },
                      child: Container(
                        width: _fabSize,
                        height: _fabSize,
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
                ),
              ],
            ),
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
      // Opaque + full pill height (see [_navItem]) so the whole slot is the
      // tap target, not just the painted avatar/label pixels.
      behavior: HitTestBehavior.opaque,
      onTap: () => _switchTab(context, AppNavTab.profile),
      child: SizedBox(
        height: _pillHeight,
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
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
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
      // Opaque + full pill height so the whole slot — not just the 22px glyph
      // and the tiny label — registers the tap. Small hit targets here were
      // making taps miss and forcing users to tap 2–3 times.
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: _pillHeight,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: active ? _accent : Colors.white54, size: 22),
            const SizedBox(height: 3),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
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
