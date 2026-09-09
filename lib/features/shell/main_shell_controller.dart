import 'dart:async';

/// App-wide bus for "switch to bottom-nav tab N".
///
/// [MainShell] hosts the four top-level tab screens in an `IndexedStack` and
/// listens here. Any [AppBottomNav] — whether it's the shell's own or one
/// rendered by a drill-down screen pushed on top of the shell — asks for a
/// tab by calling [select]; a drill-down first pops back to the shell
/// (`Navigator.popUntil(isFirst)`) so the shell is on screen to receive it.
///
/// A plain broadcast stream rather than a `ValueNotifier`: the shell only
/// cares about *transitions* (a tap), not about reading a current value, and
/// there is exactly one shell alive at a time.
class MainShellController {
  MainShellController._();

  static final MainShellController instance = MainShellController._();

  final StreamController<int> _select = StreamController<int>.broadcast();

  /// Fires the requested tab index each time [select] is called.
  /// 0 = Home, 1 = Search, 2 = Leaderboard, 3 = Profile.
  Stream<int> get onSelect => _select.stream;

  void select(int tabIndex) {
    if (tabIndex < 0 || tabIndex > 3) return;
    _select.add(tabIndex);
  }
}
