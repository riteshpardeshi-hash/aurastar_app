import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/services/api_client.dart';
import '../../core/services/auth_api_service.dart';
import '../../core/services/leaderboard_service.dart';
import '../../core/services/safety_service.dart';
import '../../core/services/screen_cache.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../../shared/widgets/safety_sheets.dart';
import '../../shared/widgets/screen_skeleton.dart';
import 'screens/challenge_leaderboard_screen.dart';
import 'widgets/leaderboard_widgets.dart';

// Client, 26 Nov 2026: the Leaderboard gets search and sort like every other
// list. Global = option A (podium, All time / Month / Week, your rank pinned
// at the bottom); Challenge = option B (searchable, sortable challenge cards
// that open each challenge's board). Search and sort run on the server
// (backend ADR 154) because both lists are paginated.

class LeaderboardScreen extends StatefulWidget {
  /// True when hosted inside [MainShell]'s IndexedStack: the shell draws the
  /// one shared bottom nav.
  final bool embeddedInShell;

  /// Which Region board to open on: 'global', 'country' or 'city' (the
  /// profile's Ranks tab opens the one you tapped).
  final String initialScope;

  const LeaderboardScreen({
    super.key,
    this.embeddedInShell = false,
    this.initialScope = 'global',
  });

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen>
    with SingleTickerProviderStateMixin {
  static const _bg = Color(0xFF080810);

  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(() => setState(() {}));

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Widget _segment(String label, int index) {
    final on = _tabs.index == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => _tabs.animateTo(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: on ? const Color(0xFFF4F1FF) : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: on ? const Color(0xFF120C22) : AppColors.textMuted,
              fontWeight: on ? FontWeight.w700 : FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      bottomNavigationBar:
          widget.embeddedInShell
              ? null
              : const AppBottomNav(activeTab: AppNavTab.leaderboard),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 12, 18, 12),
              child: Text(
                'Aura Farmers',
                style: TextStyle(
                  fontFamily: 'ClashDisplay',
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  wordSpacing: 5.5,
                  color: Colors.white,
                ),
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: lbCard,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: lbLine),
              ),
              child: Row(
                children: [_segment('Region', 0), _segment('Challenges', 1)],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _GlobalBoard(initialScope: widget.initialScope),
                  const _ChallengeCards(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Global ───────────────────────────────────────────────────────────────────

const _periods = [
  ('all', 'All time', '👑', 'The legends, since day one'),
  ('month', 'This month', '📅', 'Last 30 days of farming'),
  ('week', 'This week', '⚡', 'Fresh W’s from the last 7 days'),
];

class _GlobalBoard extends StatefulWidget {
  final String initialScope;

  const _GlobalBoard({this.initialScope = 'global'});

  @override
  State<_GlobalBoard> createState() => _GlobalBoardState();
}

class _GlobalBoardState extends State<_GlobalBoard>
    with AutomaticKeepAliveClientMixin {
  static const _pageSize = 20;
  static const _cacheKey = 'leaderboard.global.v2';

  final _searchCtrl = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  StreamSubscription<void>? _safetySub;

  String _search = '';
  String _period = 'all';
  // No sorting (client, 26 Nov 2026): Aura Farmers is always ranked by Aura,
  // highest first; only filters change what's shown.
  // Region filter (client, 26 Nov 2026): Global, the viewer's country, the
  // viewer's city. Names come back with each page (backend ADR 155).
  late String _scope = widget.initialScope;
  String? _countryName;
  String? _cityName;

  final List<Map<String, dynamic>> _entries = [];
  Map<String, dynamic>? _me;
  int _page = 1;
  bool _hasMore = true;
  bool _loading = false;
  bool _initialLoading = true;
  int _request = 0;

  String? _myId;
  String _myName = 'You';
  String _myAvatar = '';

  bool get _isDefaultView =>
      _search.isEmpty && _period == 'all' && _scope == 'global';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    ApiClient().userId.then((id) {
      if (mounted) setState(() => _myId = id);
    });
    AuthApiService().getProfile().then((p) {
      if (!mounted || p == null) return;
      final name = (p['displayName'] as String?)?.trim() ?? '';
      setState(() {
        if (name.isNotEmpty) _myName = name;
        _myAvatar = p['avatar'] as String? ?? '';
      });
    });
    final cached = ScreenCache.read<GlobalBoardPage>(_cacheKey);
    if (cached != null) {
      _entries.addAll(cached.entries);
      _me = cached.me;
      _countryName = cached.country?['name'] as String?;
      _cityName = cached.city?['name'] as String?;
      _initialLoading = false;
    }
    _reload();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) {
        _loadMore();
      }
    });
    // Blocking / unblocking someone elsewhere reloads the board at once.
    _safetySub = SafetyService.changes.listen((_) => _reload());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _safetySub?.cancel();
    _searchCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final request = ++_request;
    setState(() => _loading = true);
    try {
      final page = await LeaderboardService().fetchGlobalBoard(
        page: 1,
        limit: _pageSize,
        search: _search,
        period: _period,
        sort: 'aura_desc',
        scope: _scope,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _entries
          ..clear()
          ..addAll(page.entries);
        _me = page.me;
        _countryName = page.country?['name'] as String? ?? _countryName;
        _cityName = page.city?['name'] as String? ?? _cityName;
        _page = 2;
        _hasMore = page.entries.length == _pageSize;
        _loading = false;
        _initialLoading = false;
      });
      if (_isDefaultView) ScreenCache.write(_cacheKey, page);
    } catch (_) {
      // Keep whatever is on screen if a reload fails.
      if (mounted && request == _request) {
        setState(() {
          _loading = false;
          _initialLoading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    final request = _request;
    setState(() => _loading = true);
    try {
      final page = await LeaderboardService().fetchGlobalBoard(
        page: _page,
        limit: _pageSize,
        search: _search,
        period: _period,
        sort: 'aura_desc',
        scope: _scope,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _entries.addAll(page.entries);
        _page += 1;
        _hasMore = page.entries.length == _pageSize;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (v.trim() == _search) return;
      _search = v.trim();
      _reload();
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchCtrl.clear();
    if (_search.isEmpty) return;
    _search = '';
    _reload();
  }

  void _openSafety(Map<String, dynamic> e) {
    final username = e['username'] as String? ?? '';
    showPlayerSafetyMenu(
      context,
      userId: e['id'] as String,
      name: username.isNotEmpty ? username : lbDisplayName(e),
      onBlocked: _reload,
    );
  }

  String get _periodWord => switch (_period) {
    'week' => 'this week',
    'month' => 'this month',
    _ => '',
  };

  Future<void> _pickRegion() async {
    final picked = await showLbOptionSheet<String>(
      context,
      title: 'Pick your arena 🌍',
      options: lbRegionOptions(_countryName, _cityName),
      current: _scope,
    );
    if (picked != null && picked != _scope) {
      setState(() => _scope = picked);
      _reload();
    }
  }

  Future<void> _pickTime() async {
    final picked = await showLbOptionSheet<String>(
      context,
      title: 'Pick your era ⏳',
      options: [for (final p in _periods) LbOption(p.$1, p.$3, p.$2, p.$4)],
      current: _period,
    );
    if (picked != null && picked != _period) {
      setState(() => _period = picked);
      _reload();
    }
  }

  Widget _controls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          LbSearchField(
            key: const Key('leaderboard-search'),
            controller: _searchCtrl,
            hint: 'Search players',
            onChanged: _onSearch,
            onClear: _clearSearch,
          ),
          const SizedBox(height: 10),
          // Client, 26 Nov 2026: pick the region and the time window — no
          // sorting; the board is always ranked by Aura, highest first.
          Row(
            children: [
              Expanded(
                flex: 6,
                child: LbSelectorPill(
                  key: const Key('leaderboard-region'),
                  emoji: lbRegionEmoji(_scope),
                  label: lbRegionLabel(_scope, _countryName, _cityName),
                  onTap: _pickRegion,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 5,
                child: LbSelectorPill(
                  key: const Key('leaderboard-time'),
                  emoji: '⏳',
                  label: _periods.firstWhere((p) => p.$1 == _period).$2,
                  onTap: _pickTime,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final showPodium = _search.isEmpty && _entries.isNotEmpty;
    final podium =
        showPodium ? _entries.take(3).toList() : <Map<String, dynamic>>[];
    final rows = showPodium ? _entries.skip(3).toList() : _entries;
    final me = _me;
    final bottomSpace = me != null ? 96.0 : 24.0;

    Widget body;
    if (_initialLoading) {
      body = const ScreenSkeleton(rows: 5);
    } else if (_entries.isEmpty) {
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: 320,
            child:
                _search.isNotEmpty
                    ? lbEmpty(
                      'No players match "$_search"',
                      'Try another name or @handle.',
                      icon: Icons.search_off_rounded,
                    )
                    : _scope == 'city' && _cityName == null
                    ? lbEmpty(
                      'Add your city to see who runs it',
                      'Set your city in your profile, then come back 📍',
                      icon: Icons.location_on_outlined,
                    )
                    : _scope == 'country' && _countryName == null
                    ? lbEmpty(
                      'Add your country to see your national board',
                      'Set it in your profile, then come back 🗺️',
                      icon: Icons.public_rounded,
                    )
                    : _period != 'all'
                    ? lbEmpty(
                      'No one farmed aura $_periodWord yet',
                      'Take a challenge and be the first W 🔥',
                    )
                    : lbEmpty(
                      'No farmers here yet',
                      'Take a challenge and claim #1 — no cap 🐐',
                    ),
          ),
        ],
      );
    } else {
      body = ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 4, 16, bottomSpace),
        itemCount:
            rows.length +
            (showPodium ? 1 : 0) +
            (_loading && !_initialLoading ? 1 : 0),
        itemBuilder: (_, i) {
          if (showPodium) {
            if (i == 0) {
              return LbPodium(top: podium, myId: _myId, onTap: _openSafety);
            }
            i -= 1;
          }
          if (i >= rows.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: lbAccent,
                    strokeWidth: 2,
                  ),
                ),
              ),
            );
          }
          final e = rows[i];
          final isMe = e['id'] == _myId;
          final rank = (e['rank'] as int?) ?? (_entries.indexOf(e) + 1);
          return LbPlayerRow(
            entry: e,
            rank: rank,
            isMe: isMe,
            onTap: isMe ? null : () => _openSafety(e),
          );
        },
      );
    }

    return Column(
      children: [
        _controls(),
        const SizedBox(height: 4),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: RefreshIndicator(
                  color: lbAccent,
                  onRefresh: _reload,
                  child: body,
                ),
              ),
              if (me != null)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: LbYouBar(
                    me: me,
                    name: _myName,
                    avatarUrl: _myAvatar,
                    periodLabel: _periodWord.isEmpty ? 'now' : _periodWord,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Challenge ────────────────────────────────────────────────────────────────

const _filters = [('all', 'All'), ('joined', 'Joined'), ('brand', 'Brand')];

class _ChallengeCards extends StatefulWidget {
  const _ChallengeCards();

  @override
  State<_ChallengeCards> createState() => _ChallengeCardsState();
}

class _ChallengeCardsState extends State<_ChallengeCards>
    with AutomaticKeepAliveClientMixin {
  static const _pageSize = 20;

  final _searchCtrl = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  String _search = '';
  String _filter = 'all';

  final List<Map<String, dynamic>> _cards = [];
  int _page = 1;
  bool _hasMore = true;
  bool _loading = false;
  bool _initialLoading = true;
  int _request = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _reload();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final request = ++_request;
    setState(() => _loading = true);
    try {
      final list = await LeaderboardService().fetchChallengeBoards(
        page: 1,
        limit: _pageSize,
        search: _search,
        filter: _filter,
        sort: 'participants_desc',
      );
      if (!mounted || request != _request) return;
      setState(() {
        _cards
          ..clear()
          ..addAll(list);
        _page = 2;
        _hasMore = list.length == _pageSize;
        _loading = false;
        _initialLoading = false;
      });
    } catch (_) {
      if (mounted && request == _request) {
        setState(() {
          _loading = false;
          _initialLoading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    final request = _request;
    setState(() => _loading = true);
    try {
      final list = await LeaderboardService().fetchChallengeBoards(
        page: _page,
        limit: _pageSize,
        search: _search,
        filter: _filter,
        sort: 'participants_desc',
      );
      if (!mounted || request != _request) return;
      setState(() {
        _cards.addAll(list);
        _page += 1;
        _hasMore = list.length == _pageSize;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (v.trim() == _search) return;
      _search = v.trim();
      _reload();
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchCtrl.clear();
    if (_search.isEmpty) return;
    _search = '';
    _reload();
  }

  Widget _empty() {
    if (_search.isNotEmpty) {
      return lbEmpty(
        'No challenges match "$_search"',
        'Try another challenge or brand name.',
        icon: Icons.search_off_rounded,
      );
    }
    if (_filter == 'joined') {
      return lbEmpty(
        "You haven't joined any yet 👀",
        'Take a challenge and your rank shows up here.',
      );
    }
    if (_filter == 'brand') {
      return lbEmpty(
        'No brand challenges yet',
        'New drops soon — stay tuned ✦',
      );
    }
    return lbEmpty('No challenges yet', 'New drops soon — stay tuned ✦');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    Widget body;
    if (_initialLoading) {
      body = const ScreenSkeleton(rows: 4);
    } else if (_cards.isEmpty) {
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [SizedBox(height: 320, child: _empty())],
      );
    } else {
      body = GridView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.74,
        ),
        itemCount: _cards.length,
        itemBuilder: (_, i) {
          final c = _cards[i];
          return LbChallengeCard(
            challenge: c,
            onTap:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) => ChallengeLeaderboardScreen(
                          challengeId: c['_id'] as String,
                          challengeTitle: c['title'] as String? ?? '',
                        ),
                  ),
                ),
          );
        },
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              LbSearchField(
                key: const Key('challenge-boards-search'),
                controller: _searchCtrl,
                hint: 'Search challenges or brands',
                onChanged: _onSearch,
                onClear: _clearSearch,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final (value, label) in _filters)
                    LbChip(
                      key: Key('challenge-boards-filter-$value'),
                      label: label,
                      selected: _filter == value,
                      onTap: () {
                        if (_filter == value) return;
                        setState(() => _filter = value);
                        _reload();
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: RefreshIndicator(
            color: lbAccent,
            onRefresh: _reload,
            child: body,
          ),
        ),
      ],
    );
  }
}
