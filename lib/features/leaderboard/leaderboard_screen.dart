import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../challenges/screens/challenge_detail.dart';

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
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Leaderboard',
          style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'ClashDisplay'),
        ),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: _accent,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white38,
          labelStyle: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: 13, fontFamily: 'SpaceGrotesk'),
          unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w500, fontSize: 13, fontFamily: 'SpaceGrotesk'),
          tabs: const [
            Tab(text: 'Global'),
            Tab(text: 'City'),
            Tab(text: 'Challenge'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _GlobalBoard(),
          _CityBoard(),
          _ChallengeBoard(),
        ],
      ),
    );
  }
}

// ── Global Board ───────────────────────────────────────────────────────────────

class _GlobalBoard extends StatefulWidget {
  const _GlobalBoard();

  @override
  State<_GlobalBoard> createState() => _GlobalBoardState();
}

class _GlobalBoardState extends State<_GlobalBoard>
    with AutomaticKeepAliveClientMixin {
  static const _accent = Color(0xFF7B2CBF);
  static const _pageSize = 20;

  final _scrollCtrl = ScrollController();
  final List<QueryDocumentSnapshot> _docs = [];
  DocumentSnapshot? _lastDoc;
  bool _loading = false;
  bool _initialLoading = true;
  bool _hasMore = true;
  final _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
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
    try {
      var q = FirebaseFirestore.instance
          .collection('users')
          .orderBy('totalRewards', descending: true)
          .limit(_pageSize);
      if (_lastDoc != null) q = q.startAfterDocument(_lastDoc!);
      final snap = await q.get();
      if (mounted) {
        setState(() {
          _docs.addAll(snap.docs);
          _lastDoc = snap.docs.isEmpty ? null : snap.docs.last;
          _hasMore = snap.docs.length == _pageSize;
          _loading = false;
          _initialLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _loading = false; _initialLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_initialLoading) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }
    if (_docs.isEmpty) {
      return _emptyState('No players yet', 'Complete challenges to appear here');
    }
    final userInList = _docs.any((d) => d.id == _uid);
    return _BoardList(
      docs: _docs,
      currentUid: _uid,
      scoreField: 'totalRewards',
      scoreSuffix: 'Auras',
      showCurrentUserFooter: !userInList && _uid.isNotEmpty,
      scrollController: _scrollCtrl,
      loadingMore: _loading,
    );
  }
}

// ── City Board ─────────────────────────────────────────────────────────────────

class _CityBoard extends StatelessWidget {
  const _CityBoard();

  static const _accent = Color(0xFF7B2CBF);

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return StreamBuilder<DocumentSnapshot>(
      stream: uid.isEmpty
          ? null
          : FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, userSnap) {
        if (uid.isEmpty || !userSnap.hasData) {
          return const Center(child: CircularProgressIndicator(color: _accent));
        }
        final userData = userSnap.data?.data() as Map<String, dynamic>? ?? {};
        final city = (userData['city'] as String?)?.trim() ?? '';

        if (city.isEmpty) {
          return _emptyState(
            'No city set',
            'Update your city in Settings to join the city board',
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Row(
                children: [
                  const Icon(Icons.location_on_rounded, color: _accent, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    city,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      fontFamily: 'SpaceGrotesk',
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .where('city', isEqualTo: city)
                    .limit(50)
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: _accent));
                  }
                  // Sort client-side to avoid needing a composite index
                  final docs = (snap.data?.docs ?? []).toList()
                    ..sort((a, b) {
                      final aS = ((a.data() as Map)['totalRewards'] as num?)?.toInt() ?? 0;
                      final bS = ((b.data() as Map)['totalRewards'] as num?)?.toInt() ?? 0;
                      return bS.compareTo(aS);
                    });

                  if (docs.isEmpty) {
                    return _emptyState(
                        'No players in $city yet', 'Be the first to compete!');
                  }
                  final userInList = docs.any((d) => d.id == uid);
                  return _BoardList(
                    docs: docs,
                    currentUid: uid,
                    scoreField: 'totalRewards',
                    scoreSuffix: 'Auras',
                    showCurrentUserFooter: !userInList,
                  );
                },
              ),
            ),
          ],
        );
      },
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

  String? _challengeId;
  String _challengeTitle = '';
  String _challengeVideoUrl = '';
  String _challengeInstructions = '';

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Column(
      children: [
        // ── Challenge chip picker ──────────────────────────────────────────────
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('challenges').limit(20).snapshots(),
          builder: (context, snap) {
            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) return const SizedBox.shrink();

            // Auto-select first challenge on first load
            if (_challengeId == null && docs.isNotEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                final d = docs.first.data() as Map<String, dynamic>;
                setState(() {
                  _challengeId = docs.first.id;
                  _challengeTitle = d['title'] as String? ?? '';
                  _challengeVideoUrl = d['videoUrl'] as String? ?? '';
                  _challengeInstructions = d['instructions'] as String? ?? '';
                });
              });
            }

            return SizedBox(
              height: 46,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final doc = docs[i];
                  final data = doc.data() as Map<String, dynamic>;
                  final title = data['title'] as String? ?? '';
                  final sel = _challengeId == doc.id;

                  return GestureDetector(
                    onTap: () => setState(() {
                      _challengeId = doc.id;
                      _challengeTitle = title;
                      _challengeVideoUrl = data['videoUrl'] as String? ?? '';
                      _challengeInstructions = data['instructions'] as String? ?? '';
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.only(right: 8),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                      decoration: BoxDecoration(
                        color: sel ? _accent : const Color(0xFF111111),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: sel ? _accent : Colors.white12),
                      ),
                      child: Text(
                        title,
                        style: TextStyle(
                          color: sel ? Colors.white : Colors.white54,
                          fontSize: 12,
                          fontWeight:
                              sel ? FontWeight.bold : FontWeight.normal,
                          fontFamily: 'SpaceGrotesk',
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
        const Divider(color: Colors.white10, height: 1),

        // ── Scores for selected challenge ──────────────────────────────────────
        if (_challengeId == null)
          Expanded(
            child: _emptyState(
                'Select a challenge', 'Tap a chip above to see the board'),
          )
        else
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('submissions')
                  .where('challengeId', isEqualTo: _challengeId)
                  .limit(200)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(color: _accent));
                }

                // Filter: not deleted, has aiScore
                final all = (snap.data?.docs ?? []).where((d) {
                  final data = d.data() as Map<String, dynamic>;
                  return !(data['isDeleted'] as bool? ?? false) &&
                      data['aiScore'] != null;
                }).toList();

                if (all.isEmpty) {
                  return _emptyState(
                    'No scores yet',
                    'Be the first to attempt this challenge!',
                  );
                }

                // Deduplicate — keep best aiScore per user
                final Map<String, QueryDocumentSnapshot> best = {};
                for (final doc in all) {
                  final data = doc.data() as Map<String, dynamic>;
                  final userId = data['userId'] as String? ?? doc.id;
                  final score = (data['aiScore'] as num?)?.toInt() ?? 0;
                  final prev = best[userId];
                  if (prev == null ||
                      score >
                          (((prev.data() as Map)['aiScore'] as num?)
                                  ?.toInt() ??
                              0)) {
                    best[userId] = doc;
                  }
                }

                final ranked = best.values.toList()
                  ..sort((a, b) {
                    final aS =
                        ((a.data() as Map)['aiScore'] as num?)?.toInt() ?? 0;
                    final bS =
                        ((b.data() as Map)['aiScore'] as num?)?.toInt() ?? 0;
                    return bS.compareTo(aS);
                  });

                return Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        itemCount: ranked.length,
                        itemBuilder: (_, i) {
                          final data = ranked[i].data() as Map<String, dynamic>;
                          final username = data['username'] as String? ?? 'User';
                          final aiScore =
                              (data['aiScore'] as num?)?.toInt() ?? 0;
                          final stars =
                              (data['starsCount'] as num?)?.toInt() ?? 0;
                          final userId = data['userId'] as String? ?? '';
                          return _SubmissionRow(
                            rank: i + 1,
                            username: username,
                            score: aiScore,
                            stars: stars,
                            isCurrentUser: userId == uid,
                          );
                        },
                      ),
                    ),
                    // Try challenge CTA
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      child: GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChallengeDetail(
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
                );
              },
            ),
          ),
      ],
    );
  }
}

// ── Board List (Global + City) ─────────────────────────────────────────────────

class _BoardList extends StatelessWidget {
  final List<QueryDocumentSnapshot> docs;
  final String currentUid;
  final String scoreField;
  final String scoreSuffix;
  final bool showCurrentUserFooter;
  final ScrollController? scrollController;
  final bool loadingMore;

  const _BoardList({
    required this.docs,
    required this.currentUid,
    required this.scoreField,
    required this.scoreSuffix,
    this.showCurrentUserFooter = false,
    this.scrollController,
    this.loadingMore = false,
  });

  @override
  Widget build(BuildContext context) {
    // +2 items when footer needed: separator + user row; +1 for load-more spinner
    final extra = showCurrentUserFooter ? 2 : 0;
    final total = docs.length + extra + (loadingMore ? 1 : 0);

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: total,
      itemBuilder: (_, i) {
        // 1. Normal rows
        if (i < docs.length) {
          final doc = docs[i];
          final data = doc.data() as Map<String, dynamic>;
          final name = (data['name'] as String?)?.trim().isNotEmpty == true
              ? data['name'] as String
              : data['username'] as String? ?? 'User';
          final username = data['username'] as String? ?? '';
          final score = (data[scoreField] as num?)?.toInt() ?? 0;
          return _PlayerRow(
            rank: i + 1,
            name: name,
            username: username,
            score: score,
            scoreSuffix: scoreSuffix,
            isCurrentUser: doc.id == currentUid,
          );
        }

        // Compute offset past the normal rows (accounts for optional spinner)
        var offset = i - docs.length;

        // 2. Load-more spinner right after normal rows
        if (loadingMore) {
          if (offset == 0) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(
                      color: Color(0xFF7B2CBF), strokeWidth: 2),
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
                Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.08))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'Your position',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
                        fontSize: 11,
                        fontFamily: 'SpaceGrotesk'),
                  ),
                ),
                Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.08))),
              ],
            ),
          );
        }

        // 4. Current user's own row (fetched live)
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(currentUid)
              .snapshots(),
          builder: (_, snap) {
            if (!snap.hasData) return const SizedBox.shrink();
            final data =
                snap.data!.data() as Map<String, dynamic>? ?? {};
            final name =
                (data['name'] as String?)?.trim().isNotEmpty == true
                    ? data['name'] as String
                    : data['username'] as String? ?? 'You';
            final username = data['username'] as String? ?? '';
            final score = (data[scoreField] as num?)?.toInt() ?? 0;
            return _PlayerRow(
              rank: docs.length + 1,
              name: name,
              username: username,
              score: score,
              scoreSuffix: scoreSuffix,
              isCurrentUser: true,
              rankLabel: '>${docs.length}',
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

  static const _accent = Color(0xFF7B2CBF);

  const _PlayerRow({
    required this.rank,
    required this.name,
    required this.username,
    required this.score,
    required this.scoreSuffix,
    required this.isCurrentUser,
    this.rankLabel,
  });

  @override
  Widget build(BuildContext context) {
    final medalColor = rank == 1
        ? const Color(0xFFFFD700)
        : rank == 2
            ? const Color(0xFFB8B8C8)
            : rank == 3
                ? const Color(0xFFCD7F32)
                : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isCurrentUser
            ? _accent.withValues(alpha: 0.13)
            : const Color(0xFF0E0E1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCurrentUser
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
            child: rank <= 3
                ? Icon(Icons.emoji_events_rounded, color: medalColor, size: 24)
                : Text(
                    rankLabel ?? '$rank',
                    style: TextStyle(
                      color: isCurrentUser ? Colors.white : Colors.white38,
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
                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
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
                        color: Colors.white38,
                        fontSize: 11,
                        fontFamily: 'SpaceGrotesk'),
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
                  color: medalColor ??
                      (isCurrentUser ? const Color(0xFFD4A8FF) : Colors.white),
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                  fontFamily: 'SpaceGrotesk',
                ),
              ),
              Text(
                scoreSuffix,
                style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                    fontFamily: 'SpaceGrotesk'),
              ),
            ],
          ),
          if (isCurrentUser) ...[
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
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
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

// ── Submission Row (Challenge board) ──────────────────────────────────────────

class _SubmissionRow extends StatelessWidget {
  final int rank;
  final String username;
  final int score;
  final int stars;
  final bool isCurrentUser;

  static const _accent = Color(0xFF7B2CBF);

  const _SubmissionRow({
    required this.rank,
    required this.username,
    required this.score,
    required this.stars,
    required this.isCurrentUser,
  });

  @override
  Widget build(BuildContext context) {
    final medalColor = rank == 1
        ? const Color(0xFFFFD700)
        : rank == 2
            ? const Color(0xFFB8B8C8)
            : rank == 3
                ? const Color(0xFFCD7F32)
                : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isCurrentUser
            ? _accent.withValues(alpha: 0.13)
            : const Color(0xFF0E0E1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCurrentUser
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
            child: rank <= 3
                ? Icon(Icons.emoji_events_rounded, color: medalColor, size: 24)
                : Text(
                    '$rank',
                    style: TextStyle(
                      color: isCurrentUser ? Colors.white : Colors.white38,
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
              username.isNotEmpty ? username[0].toUpperCase() : 'U',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          // Username
          Expanded(
            child: Text(
              '@$username',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
                fontFamily: 'SpaceGrotesk',
              ),
            ),
          ),
          // Stars
          Row(
            children: [
              const Icon(Icons.star_rounded, color: Colors.white38, size: 14),
              const SizedBox(width: 3),
              Text(
                _fmt(stars),
                style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                    fontFamily: 'SpaceGrotesk'),
              ),
            ],
          ),
          const SizedBox(width: 14),
          // AI Score
          Text(
            '$score',
            style: TextStyle(
              color: medalColor ??
                  (isCurrentUser ? const Color(0xFFD4A8FF) : Colors.white),
              fontWeight: FontWeight.w900,
              fontSize: 20,
              fontFamily: 'SpaceGrotesk',
            ),
          ),
          if (isCurrentUser) ...[
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
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
  }

  String _fmt(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

// ── Shared empty state ─────────────────────────────────────────────────────────

Widget _emptyState(String title, String subtitle) => Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.emoji_events_outlined,
              color: Colors.white24, size: 52),
          const SizedBox(height: 14),
          Text(title,
              style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 16,
                  fontFamily: 'SpaceGrotesk')),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white24,
                    fontSize: 12,
                    fontFamily: 'SpaceGrotesk'),
              ),
            ),
          ],
        ],
      ),
    );
