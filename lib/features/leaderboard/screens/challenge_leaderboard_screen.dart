import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/services/api_client.dart';
import '../../../core/services/auth_api_service.dart';
import '../../../core/services/leaderboard_service.dart';
import '../../../shared/widgets/safety_sheets.dart';
import '../../../shared/widgets/screen_skeleton.dart';
import '../widgets/leaderboard_widgets.dart';

/// One challenge's Aura Farmers board (client, 26 Nov 2026): the top three on
/// the sticker podium, then everyone else, filterable to the viewer's country
/// or city and searchable, with the viewer's own rank pinned at the bottom.
/// Each player's best score counts (backend ADR 155).
class ChallengeLeaderboardScreen extends StatefulWidget {
  final String challengeId;
  final String challengeTitle;

  const ChallengeLeaderboardScreen({
    super.key,
    required this.challengeId,
    required this.challengeTitle,
  });

  @override
  State<ChallengeLeaderboardScreen> createState() =>
      _ChallengeLeaderboardScreenState();
}

class _ChallengeLeaderboardScreenState
    extends State<ChallengeLeaderboardScreen> {
  static const _bg = Color(0xFF080810);
  static const _pageSize = 20;

  final _searchCtrl = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  String _search = '';
  String _scope = 'global';
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

  Future<GlobalBoardPage> _fetch(int page) =>
      LeaderboardService().fetchChallengePlayers(
        widget.challengeId,
        page: page,
        limit: _pageSize,
        search: _search,
        scope: _scope,
      );

  Future<void> _reload() async {
    final request = ++_request;
    setState(() => _loading = true);
    try {
      final page = await _fetch(1);
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
      final page = await _fetch(_page);
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

  Widget _empty() {
    if (_search.isNotEmpty) {
      return lbEmpty(
        'No farmers match "$_search"',
        'Try another name or @handle.',
        icon: Icons.search_off_rounded,
      );
    }
    if (_scope == 'city' && _cityName == null) {
      return lbEmpty(
        'Add your city to see who runs it',
        'Set your city in your profile, then come back 📍',
        icon: Icons.location_on_outlined,
      );
    }
    if (_scope == 'country' && _countryName == null) {
      return lbEmpty(
        'Add your country to see your national board',
        'Set it in your profile, then come back 🗺️',
        icon: Icons.public_rounded,
      );
    }
    if (_scope != 'global') {
      return lbEmpty(
        'Nobody here has farmed this one yet',
        'Be the first W in your area 🔥',
      );
    }
    return lbEmpty('No scores yet', 'Be the first to farm aura here 🐐');
  }

  @override
  Widget build(BuildContext context) {
    final showPodium = _search.isEmpty && _entries.isNotEmpty;
    final podium =
        showPodium ? _entries.take(3).toList() : <Map<String, dynamic>>[];
    final rows = showPodium ? _entries.skip(3).toList() : _entries;
    final me = _me;
    final hasMyScore = me != null && me['rank'] != null;

    Widget body;
    if (_initialLoading) {
      body = const ScreenSkeleton(rows: 5);
    } else if (_entries.isEmpty) {
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [SizedBox(height: 320, child: _empty())],
      );
    } else {
      body = ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 4, 16, hasMyScore ? 96 : 24),
        itemCount: rows.length + (showPodium ? 1 : 0) + (_loading ? 1 : 0),
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
          return LbPlayerRow(
            entry: e,
            rank: (e['rank'] as int?) ?? (_entries.indexOf(e) + 1),
            isMe: isMe,
            scoreLabel: 'score',
            onTap: isMe ? null : () => _openSafety(e),
          );
        },
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.challengeTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'ClashDisplay',
                fontWeight: FontWeight.w600,
                fontSize: 18,
                wordSpacing: 4,
              ),
            ),
            const Text(
              'Aura Farmers',
              style: TextStyle(color: Color(0xFFC4A6FF), fontSize: 11.5),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                LbSearchField(
                  key: const Key('challenge-players-search'),
                  controller: _searchCtrl,
                  hint: 'Search farmers',
                  onChanged: _onSearch,
                  onClear: _clearSearch,
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 32,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final (value, label) in [
                        ('global', '🌍 Global'),
                        ('country', '🗺️ ${_countryName ?? 'Country'}'),
                        ('city', '📍 ${_cityName ?? 'City'}'),
                      ])
                        LbChip(
                          key: Key('challenge-players-scope-$value'),
                          label: label,
                          selected: _scope == value,
                          onTap: () {
                            if (_scope == value) return;
                            setState(() => _scope = value);
                            _reload();
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
                if (hasMyScore)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 16,
                    child: SafeArea(
                      top: false,
                      child: LbYouBar(
                        me: me,
                        name: _myName,
                        avatarUrl: _myAvatar,
                        periodLabel: 'here',
                        scoreLabel: 'score',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
