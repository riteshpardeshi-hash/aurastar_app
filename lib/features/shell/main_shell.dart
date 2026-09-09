import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/widgets/app_bottom_nav.dart';
import '../account/screens/my_account_screen.dart';
import '../challenges/screens/all_general_challenges_screen.dart';
import '../dashboard/dashboard.dart';
import '../leaderboard/leaderboard_screen.dart';
import 'main_shell_controller.dart';

/// The app's home surface once past auth/onboarding.
///
/// Hosts the four bottom-nav tabs — Home, Search, Leaderboard, Profile — in
/// an [IndexedStack] so all four are built once and kept alive. Switching
/// tabs is then just changing which one is shown: no route push, no
/// `initState` re-run, no re-fetch, and each tab keeps its scroll position.
/// Drill-down screens (challenge detail, video detail, the reels feed,
/// settings, …) still push on the root navigator on top of the shell.
///
/// The switch is unconditional and takes effect on the next frame. An
/// earlier version held on the current tab until the tapped one reported its
/// first payload "ready" (with a 5s timeout fallback) — that made the very
/// first visit to each tab feel frozen for several seconds and swallowed the
/// repeat taps users made in response. Every tab screen already renders its
/// own skeleton/empty/error state while loading, so revealing it straight
/// away is both simpler and better. See ADR 011.
class MainShell extends StatefulWidget {
  final int initialTab;

  const MainShell({super.key, this.initialTab = 0});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  static const _tabs = [
    AppNavTab.home,
    AppNavTab.search,
    AppNavTab.leaderboard,
    AppNavTab.profile,
  ];

  late int _tab = widget.initialTab;
  StreamSubscription<int>? _selectSub;

  static const _pages = <Widget>[
    Dashboard(embeddedInShell: true),
    AllGeneralChallengesScreen(embeddedInShell: true),
    LeaderboardScreen(embeddedInShell: true),
    MyAccountScreen(embeddedInShell: true),
  ];

  @override
  void initState() {
    super.initState();
    _selectSub = MainShellController.instance.onSelect.listen(_selectTab);
  }

  @override
  void dispose() {
    _selectSub?.cancel();
    super.dispose();
  }

  void _selectTab(int i) {
    if (i < 0 || i >= _pages.length || i == _tab) return;
    setState(() => _tab = i);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080810),
      // A plain IndexedStack, switched instantly: all four pages stay
      // mounted, so revealing one is a single frame with no rebuild and no
      // re-fetch. Wrapping this in an AnimatedSwitcher would mount two
      // IndexedStacks over the same page elements mid-transition and lose
      // their state — the point here is that state is never lost.
      body: IndexedStack(index: _tab, children: _pages),
      bottomNavigationBar: AppBottomNav(activeTab: _tabs[_tab]),
    );
  }
}
