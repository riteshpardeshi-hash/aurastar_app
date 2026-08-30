import 'package:flutter/material.dart';
import '../challenges/screens/challenge_detail.dart';
import 'screens/friends_management_screen.dart';
import '../../core/services/api_client.dart';
import '../../core/services/auth_api_service.dart';
import '../../core/services/challenges_service.dart';
import '../../core/services/friends_service.dart';
import '../../core/services/leaderboard_service.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/app_bottom_nav.dart';
import '../../shared/widgets/challenge_leaderboard_row.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen>
    with SingleTickerProviderStateMixin {
  static const _bg = Color(0xFF000000);
  static const _accent = Color(0xFF7B2CBF);

  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      bottomNavigationBar: const AppBottomNav(activeTab: AppNavTab.leaderboard),
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Leaderboard'),
        actions: const [_FriendsIconButton()],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: _accent,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: AppColors.textFaint,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            fontFamily: 'SpaceGrotesk',
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 13,
            fontFamily: 'SpaceGrotesk',
          ),
          tabs: const [
            Tab(text: 'Global'),
            Tab(text: 'Friends'),
            Tab(text: 'Challenge'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _ApiBoard(
            fetchPage:
                (page, limit) =>
                    LeaderboardService().fetchGlobal(page: page, limit: limit),
            scoreSuffix: 'Auras',
            emptyTitle: 'No players yet',
            emptySubtitle: 'Complete challenges to appear here',
          ),
          _ApiBoard(
            fetchPage:
                (page, limit) =>
                    LeaderboardService().fetchFriends(page: page, limit: limit),
            scoreSuffix: 'Auras',
            emptyTitle: 'No friends yet',
            emptySubtitle: 'Add friends to see how you stack up',
            emptyAction: Builder(
              builder: (context) => TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FriendsManagementScreen()),
                ),
                icon: const Icon(Icons.person_add_alt_1, color: _accent, size: 18),
                label: const Text(
                  'Add friends',
                  style: TextStyle(color: _accent, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
          const _ChallengeBoard(),
        ],
      ),
    );
  }
}

// ── API-backed Board (Global + Friends) ─────────────────────────────────────────

class _ApiBoard extends StatefulWidget {
  final Future<List<Map<String, dynamic>>> Function(int page, int limit)
  fetchPage;
  final String scoreSuffix;
  final String emptyTitle;
  final String emptySubtitle;
  final Widget? emptyAction;

  const _ApiBoard({
    required this.fetchPage,
    required this.scoreSuffix,
    required this.emptyTitle,
    required this.emptySubtitle,
    this.emptyAction,
  });

  @override
  State<_ApiBoard> createState() => _ApiBoardState();
}

class _ApiBoardState extends State<_ApiBoard>
    with AutomaticKeepAliveClientMixin {
  static const _accent = Color(0xFF7B2CBF);
  static const _pageSize = 20;

  final _scrollCtrl = ScrollController();
  final List<Map<String, dynamic>> _entries = [];
  int _page = 1;
  bool _loading = false;
  bool _initialLoading = true;
  bool _hasMore = true;
  String? _myId;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    ApiClient().userId.then((id) {
      if (mounted) setState(() => _myId = id);
    });
    _loadMore();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >
        _scrollCtrl.position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    final page = _page;
    final raw = await widget.fetchPage(page, _pageSize);
    if (!mounted) return;
    setState(() {
      _entries.addAll(raw.map(normaliseLeaderboardEntry));
      _hasMore = raw.length == _pageSize;
      _page = page + 1;
      _loading = false;
      _initialLoading = false;
    });
  }

  Future<void> _refresh() async {
    final raw = await widget.fetchPage(1, _pageSize);
    if (!mounted) return;
    setState(() {
      _entries
        ..clear()
        ..addAll(raw.map(normaliseLeaderboardEntry));
      _hasMore = raw.length == _pageSize;
      _page = 2;
      _initialLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_initialLoading) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }
    if (_entries.isEmpty) {
      return RefreshIndicator(
        color: _accent,
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              child: leaderboardEmptyState(
                widget.emptyTitle,
                widget.emptySubtitle,
                action: widget.emptyAction,
              ),
            ),
          ],
        ),
      );
    }
    final userInList = _myId != null && _entries.any((e) => e['id'] == _myId);
    return RefreshIndicator(
      color: _accent,
      onRefresh: _refresh,
      child: _EntryList(
        entries: _entries,
        currentId: _myId,
        scoreSuffix: widget.scoreSuffix,
        showCurrentUserFooter: !userInList && _myId != null,
        scrollController: _scrollCtrl,
        loadingMore: _loading,
      ),
    );
  }
}

// ── Challenge Board ────────────────────────────────────────────────────────────

class _ChallengeBoard extends StatefulWidget {
  const _ChallengeBoard();

  @override
  State<_ChallengeBoard> createState() => _ChallengeBoardState();
}

class _ChallengeBoardState extends State<_ChallengeBoard> {
  static const _accent = Color(0xFF7B2CBF);

  List<Map<String, dynamic>> _challenges = [];
  bool _loadingChallenges = true;

  String? _challengeId;
  String _challengeTitle = '';
  String _challengeVideoUrl = '';
  String _challengeInstructions = '';

  List<Map<String, dynamic>> _entries = [];
  bool _loadingBoard = false;
  String? _myId;
  // GET /challenges/{id}/submissions (used below) never joins a display
  // name for the submitter — see normaliseSubmissionEntry's doc comment —
  // so every row falls back to "Player N". For the viewer's own row we
  // don't need that guesswork: GET /profile already has their real name.
  String? _myUsername;

  @override
  void initState() {
    super.initState();
    ApiClient().userId.then((id) {
      if (mounted) setState(() => _myId = id);
    });
    AuthApiService().getProfile().then((profile) {
      if (!mounted || profile == null) return;
      final name = (profile['displayName'] as String?)?.trim();
      final username = (profile['username'] as String?)?.trim();
      final profileName = (profile['profileName'] as String?)?.trim();
      final resolved = (username?.isNotEmpty ?? false)
          ? username
          : (name?.isNotEmpty ?? false)
              ? name
              : profileName;
      if (resolved?.isNotEmpty ?? false) {
        setState(() => _myUsername = resolved);
      }
    });
    _loadChallenges();
  }

  Future<void> _loadChallenges() async {
    final list = await ChallengesService().fetchChallenges(limit: 20);
    if (!mounted) return;
    setState(() {
      _challenges = list;
      _loadingChallenges = false;
    });
    if (list.isNotEmpty) _selectChallenge(list.first);
  }

  void _selectChallenge(Map<String, dynamic> c) {
    setState(() {
      _challengeId = c['_id'] as String?;
      _challengeTitle = c['title'] as String? ?? '';
      _challengeVideoUrl = c['videoUrl'] as String? ?? '';
      _challengeInstructions =
          (c['instructions'] as String?)?.isNotEmpty == true
              ? c['instructions'] as String
              : c['description'] as String? ?? '';
    });
    _loadBoard();
  }

  Future<void> _loadBoard() async {
    final id = _challengeId;
    if (id == null) return;
    setState(() => _loadingBoard = true);
    final raw = await ChallengesService().fetchSubmissions(id, limit: 50);
    if (!mounted || _challengeId != id) return;
    setState(() {
      _entries = raw.map(normaliseSubmissionEntry).toList();
      _loadingBoard = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Challenge chip picker ──────────────────────────────────────────────
        if (_loadingChallenges)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator(color: _accent)),
          )
        else if (_challenges.isNotEmpty)
          SizedBox(
            height: 46,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
              itemCount: _challenges.length,
              itemBuilder: (_, i) {
                final c = _challenges[i];
                final title = c['title'] as String? ?? '';
                final sel = _challengeId == c['_id'];

                return GestureDetector(
                  onTap: () => _selectChallenge(c),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: sel ? _accent : const Color(0xFF111111),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: sel ? _accent : Colors.white12),
                    ),
                    child: Text(
                      title,
                      style: TextStyle(
                        color: sel ? Colors.white : AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                        fontFamily: 'SpaceGrotesk',
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        const Divider(color: Colors.white10, height: 1),

        // ── Scores for selected challenge ──────────────────────────────────────
        if (_challengeId == null)
          Expanded(
            child: leaderboardEmptyState(
              'Select a challenge',
              'Tap a chip above to see the board',
            ),
          )
        else if (_loadingBoard)
          const Expanded(
            child: Center(child: CircularProgressIndicator(color: _accent)),
          )
        else if (_entries.isEmpty)
          Expanded(
            child: RefreshIndicator(
              color: _accent,
              onRefresh: _loadBoard,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.5,
                    child: leaderboardEmptyState(
                      'No scores yet',
                      'Be the first to attempt this challenge!',
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: RefreshIndicator(
                    color: _accent,
                    onRefresh: _loadBoard,
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      itemCount: _entries.length,
                      itemBuilder: (_, i) {
                        final e = _entries[i];
                        final isMe = e['id'] == _myId;
                        final rawUsername = e['username'] as String;
                        final rawName = e['name'] as String;
                        final username =
                            (isMe && (_myUsername?.isNotEmpty ?? false))
                                ? _myUsername!
                                : rawUsername.isNotEmpty
                                    ? rawUsername
                                    : rawName.isNotEmpty
                                        ? rawName
                                        : 'Player ${i + 1}';
                        return ChallengeLeaderboardRow(
                          rank: i + 1,
                          username: username,
                          score: e['score'] as int,
                          stars: e['stars'] as int,
                          isCurrentUser: isMe,
                          onTap: isMe
                              ? null
                              : () => showPrivateProfileNotice(context),
                        );
                      },
                    ),
                  ),
                ),
                // Try challenge CTA
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: GestureDetector(
                    onTap:
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder:
                                (_) => ChallengeDetail(
                                  title: _challengeTitle,
                                  instructions: _challengeInstructions,
                                  videoUrl: _challengeVideoUrl,
                                  challengeId: _challengeId!,
                                ),
                          ),
                        ),
                    child: Container(
                      width: double.infinity,
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF7B2CBF), Color(0xFF4B6EF6)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: Text(
                          'Try $_challengeTitle',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'SpaceGrotesk',
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ── Entry List (Global + Friends, API-backed) ───────────────────────────────────

class _EntryList extends StatelessWidget {
  final List<Map<String, dynamic>> entries;
  final String? currentId;
  final String scoreSuffix;
  final bool showCurrentUserFooter;
  final ScrollController? scrollController;
  final bool loadingMore;

  const _EntryList({
    required this.entries,
    required this.currentId,
    required this.scoreSuffix,
    this.showCurrentUserFooter = false,
    this.scrollController,
    this.loadingMore = false,
  });

  @override
  Widget build(BuildContext context) {
    final extra = showCurrentUserFooter ? 2 : 0;
    final total = entries.length + extra + (loadingMore ? 1 : 0);

    return ListView.builder(
      controller: scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: total,
      itemBuilder: (_, i) {
        // 1. Normal rows
        if (i < entries.length) {
          final e = entries[i];
          return _PlayerRow(
            rank: i + 1,
            name: e['name'] as String,
            username: e['username'] as String,
            score: e['score'] as int,
            scoreSuffix: scoreSuffix,
            isCurrentUser: e['id'] == currentId,
            onTap:
                e['id'] == currentId
                    ? null
                    : () => showPrivateProfileNotice(context),
          );
        }

        var offset = i - entries.length;

        // 2. Load-more spinner right after normal rows
        if (loadingMore) {
          if (offset == 0) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Color(0xFF7B2CBF),
                    strokeWidth: 2,
                  ),
                ),
              ),
            );
          }
          offset -= 1;
        }

        // 3. "Your position" separator
        if (showCurrentUserFooter && offset == 0) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Divider(color: Colors.white.withValues(alpha: 0.08)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'Your position',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                      fontSize: 11,
                      fontFamily: 'SpaceGrotesk',
                    ),
                  ),
                ),
                Expanded(
                  child: Divider(color: Colors.white.withValues(alpha: 0.08)),
                ),
              ],
            ),
          );
        }

        // 4. Current user's own row
        return FutureBuilder<Map<String, dynamic>?>(
          future: AuthApiService().getProfile(),
          builder: (_, snap) {
            if (!snap.hasData) return const SizedBox.shrink();
            final data = snap.data!;
            final name =
                (data['displayName'] as String?)?.trim().isNotEmpty == true
                    ? data['displayName'] as String
                    : data['name'] as String? ?? 'You';
            final username =
                data['username'] as String? ??
                data['profileName'] as String? ??
                '';
            final score =
                ((data['auraPoints'] ?? data['totalRewards']) as num?)
                    ?.toInt() ??
                0;
            return _PlayerRow(
              rank: entries.length + 1,
              name: name,
              username: username,
              score: score,
              scoreSuffix: scoreSuffix,
              isCurrentUser: true,
              rankLabel: '>${entries.length}',
              onTap: null,
            );
          },
        );
      },
    );
  }
}

// ── Player Row ─────────────────────────────────────────────────────────────────

class _PlayerRow extends StatelessWidget {
  final int rank;
  final String name;
  final String username;
  final int score;
  final String scoreSuffix;
  final bool isCurrentUser;
  final String? rankLabel;
  final VoidCallback? onTap;

  static const _accent = Color(0xFF7B2CBF);

  const _PlayerRow({
    required this.rank,
    required this.name,
    required this.username,
    required this.score,
    required this.scoreSuffix,
    required this.isCurrentUser,
    this.rankLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final medalColor =
        rank == 1
            ? const Color(0xFFFFD700)
            : rank == 2
            ? const Color(0xFFB8B8C8)
            : rank == 3
            ? const Color(0xFFCD7F32)
            : null;

    final card = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color:
            isCurrentUser
                ? _accent.withValues(alpha: 0.13)
                : const Color(0xFF0E0E1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color:
              isCurrentUser
                  ? _accent.withValues(alpha: 0.50)
                  : Colors.white.withValues(alpha: 0.07),
          width: isCurrentUser ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          // Rank badge
          SizedBox(
            width: 38,
            child:
                rank <= 3
                    ? Icon(
                      Icons.emoji_events_rounded,
                      color: medalColor,
                      size: 24,
                    )
                    : Text(
                      rankLabel ?? '$rank',
                      style: TextStyle(
                        color: isCurrentUser ? Colors.white : AppColors.textFaint,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        fontFamily: 'SpaceGrotesk',
                      ),
                    ),
          ),
          // Avatar
          CircleAvatar(
            radius: 17,
            backgroundColor: _accent.withValues(alpha: 0.25),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : 'U',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Name + username
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    fontFamily: 'SpaceGrotesk',
                  ),
                ),
                if (username.isNotEmpty)
                  Text(
                    '@$username',
                    style: const TextStyle(
                      color: AppColors.textFaint,
                      fontSize: 11,
                      fontFamily: 'SpaceGrotesk',
                    ),
                  ),
              ],
            ),
          ),
          // Score
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _fmt(score),
                style: TextStyle(
                  color:
                      medalColor ??
                      (isCurrentUser ? const Color(0xFFD4A8FF) : Colors.white),
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                  fontFamily: 'SpaceGrotesk',
                ),
              ),
              Text(
                scoreSuffix,
                style: const TextStyle(
                  color: AppColors.textFaint,
                  fontSize: 10,
                  fontFamily: 'SpaceGrotesk',
                ),
              ),
            ],
          ),
          if (isCurrentUser) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'You',
                style: TextStyle(
                  color: Color(0xFFD4A8FF),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'SpaceGrotesk',
                ),
              ),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return card;
    return GestureDetector(onTap: onTap, child: card);
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

// ── Friends icon button (app bar) ────────────────────────────────────────────────

class _FriendsIconButton extends StatefulWidget {
  const _FriendsIconButton();

  @override
  State<_FriendsIconButton> createState() => _FriendsIconButtonState();
}

class _FriendsIconButtonState extends State<_FriendsIconButton> {
  final _service = FriendsService();
  int _pending = 0;

  @override
  void initState() {
    super.initState();
    _refreshCount();
  }

  Future<void> _refreshCount() async {
    final requests = await _service.fetchPendingRequests();
    if (mounted) setState(() => _pending = requests.length);
  }

  Future<void> _open() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FriendsManagementScreen()),
    );
    if (mounted) _refreshCount();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.people_alt_outlined, color: Colors.white70),
          if (_pending > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                constraints: const BoxConstraints(minWidth: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF7B2CBF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF080810), width: 1.5),
                ),
                child: Text(
                  _pending > 99 ? '99+' : '$_pending',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
      onPressed: _open,
    );
  }
}

