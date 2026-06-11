import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../challenges/screens/challenge_detail.dart';
import '../../creator/screens/creator_home_screen.dart';
import '../../explore/screens/creator_profile_screen.dart';
import '../../../shared/widgets/video_thumbnail_widget.dart';

class HomeFeedScreen extends StatefulWidget {
  const HomeFeedScreen({super.key});

  @override
  State<HomeFeedScreen> createState() => _HomeFeedScreenState();
}

class _HomeFeedScreenState extends State<HomeFeedScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;
  bool _isCreator = false;

  static const _accent = Color(0xFF7B2CBF);
  static const _bg = Color(0xFF080810);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _checkCreator();
  }

  Future<void> _checkCreator() async {
    if (_uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(_uid).get();
    final isCreator = (doc.data() ?? {})['isCreator'] == true;
    if (mounted && isCreator) setState(() => _isCreator = true);
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
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Image.asset('assets/images/Aura Arena Mono.png', height: 30),
        ),
        centerTitle: false,
        actions: _isCreator
            ? [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: IconButton(
                    tooltip: 'Creator Dashboard',
                    icon: const Icon(Icons.dashboard_rounded, color: Color(0xFF9B4DFF)),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CreatorHomeScreen()),
                    ),
                  ),
                ),
              ]
            : null,
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: _accent,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white38,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          tabs: const [
            Tab(text: 'For You'),
            Tab(text: 'Following'),
            Tab(text: 'Trending'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _PaginatedFeedTab(uid: _uid, orderBy: 'createdAt'),
          _FollowingFeedTab(uid: _uid),
          _PaginatedFeedTab(uid: _uid, orderBy: 'starsCount'),
        ],
      ),
    );
  }
}

// ── Paginated feed tab ────────────────────────────────────────────────────────

class _PaginatedFeedTab extends StatefulWidget {
  final String? uid;
  final String orderBy;

  const _PaginatedFeedTab({required this.uid, required this.orderBy});

  @override
  State<_PaginatedFeedTab> createState() => _PaginatedFeedTabState();
}

class _PaginatedFeedTabState extends State<_PaginatedFeedTab>
    with AutomaticKeepAliveClientMixin {
  static const _pageSize = 10;
  static const _accent = Color(0xFF7B2CBF);

  final _scrollCtrl = ScrollController();
  final List<QueryDocumentSnapshot> _docs = [];
  DocumentSnapshot? _lastDoc;
  bool _loading = false;
  bool _initialLoading = true;
  bool _hasMore = true;

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
        _scrollCtrl.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);

    try {
      var q = FirebaseFirestore.instance
          .collection('submissions')
          .where('isPublic', isEqualTo: true)
          .orderBy(widget.orderBy, descending: true)
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
      if (mounted) setState(() { _loading = false; _initialLoading = false; _hasMore = false; });
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _docs.clear();
      _lastDoc = null;
      _hasMore = true;
      _initialLoading = true;
    });
    await _loadMore();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_initialLoading) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }

    if (_docs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.people_outline_rounded,
                color: Colors.white24, size: 52),
            const SizedBox(height: 14),
            const Text('No posts yet',
                style: TextStyle(color: Colors.white38, fontSize: 16)),
            const SizedBox(height: 6),
            const Text('Be the first to share a challenge!',
                style: TextStyle(color: Colors.white24, fontSize: 13)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      color: _accent,
      child: ListView.builder(
        controller: _scrollCtrl,
        padding: const EdgeInsets.symmetric(vertical: 10),
        itemCount: _docs.length + (_loading || _hasMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (i >= _docs.length) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                  child: CircularProgressIndicator(
                      color: _accent, strokeWidth: 2)),
            );
          }
          final doc = _docs[i];
          return _FeedCard(
            submissionId: doc.id,
            data: doc.data() as Map<String, dynamic>,
            uid: widget.uid,
          );
        },
      ),
    );
  }
}

// ── Following feed tab ────────────────────────────────────────────────────────

class _FollowingFeedTab extends StatefulWidget {
  final String? uid;
  const _FollowingFeedTab({required this.uid});

  @override
  State<_FollowingFeedTab> createState() => _FollowingFeedTabState();
}

class _FollowingFeedTabState extends State<_FollowingFeedTab>
    with AutomaticKeepAliveClientMixin {
  static const _accent = Color(0xFF7B2CBF);
  static const _pageSize = 10;

  final _scrollCtrl = ScrollController();
  List<String> _followedIds = [];
  final List<QueryDocumentSnapshot> _docs = [];
  DocumentSnapshot? _lastDoc;
  bool _loading = false;
  bool _initialLoading = true;
  bool _hasMore = true;
  bool _followsLoaded = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadFollows();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >
        _scrollCtrl.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _loadFollows() async {
    if (widget.uid == null) {
      if (mounted) setState(() => _initialLoading = false);
      return;
    }
    final snap = await FirebaseFirestore.instance
        .collection('follows')
        .where('followerUserId', isEqualTo: widget.uid)
        .limit(30)
        .get();
    _followedIds = snap.docs
        .map((d) =>
            (d.data())['followedUserId'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
    _followsLoaded = true;
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (!_followsLoaded || _loading || !_hasMore) return;
    if (_followedIds.isEmpty) {
      if (mounted) setState(() => _initialLoading = false);
      return;
    }
    setState(() => _loading = true);

    try {
      var q = FirebaseFirestore.instance
          .collection('submissions')
          .where('userId', whereIn: _followedIds)
          .where('isPublic', isEqualTo: true)
          .orderBy('createdAt', descending: true)
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
      if (mounted) setState(() { _loading = false; _initialLoading = false; _hasMore = false; });
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _docs.clear();
      _lastDoc = null;
      _hasMore = true;
      _initialLoading = true;
      _followsLoaded = false;
    });
    await _loadFollows();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (widget.uid == null) {
      return const Center(
        child: Text('Log in to see your following feed',
            style: TextStyle(color: Colors.white38)),
      );
    }

    if (_initialLoading) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }

    if (!_followsLoaded || _followedIds.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.people_outline_rounded,
                  color: Colors.white24, size: 52),
              SizedBox(height: 14),
              Text("You're not following anyone yet",
                  style: TextStyle(color: Colors.white38, fontSize: 16),
                  textAlign: TextAlign.center),
              SizedBox(height: 6),
              Text('Follow players and creators to see their videos here',
                  style: TextStyle(color: Colors.white24, fontSize: 13),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    if (_docs.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.video_library_outlined, color: Colors.white24, size: 52),
            SizedBox(height: 14),
            Text('No videos yet from people you follow',
                style: TextStyle(color: Colors.white38, fontSize: 16)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      color: _accent,
      child: ListView.builder(
        controller: _scrollCtrl,
        padding: const EdgeInsets.symmetric(vertical: 10),
        itemCount: _docs.length + (_loading || _hasMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (i >= _docs.length) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                  child: CircularProgressIndicator(
                      color: _accent, strokeWidth: 2)),
            );
          }
          final doc = _docs[i];
          return _FeedCard(
            submissionId: doc.id,
            data: doc.data() as Map<String, dynamic>,
            uid: widget.uid,
          );
        },
      ),
    );
  }
}

// ── Feed card ─────────────────────────────────────────────────────────────────

class _FeedCard extends StatelessWidget {
  final String submissionId;
  final Map<String, dynamic> data;
  final String? uid;

  static const _accent = Color(0xFF7B2CBF);

  const _FeedCard({
    required this.submissionId,
    required this.data,
    required this.uid,
  });

  Future<void> _toggleStar(BuildContext context) async {
    if (uid == null) return;
    final starredBy = (data['starredBy'] as List?) ?? [];
    final isStarred = starredBy.contains(uid);
    final ownerId = data['userId'] as String? ?? '';
    final delta = isStarred ? -1 : 1;

    final db = FirebaseFirestore.instance;
    final batch = db.batch();
    batch.update(db.collection('submissions').doc(submissionId), {
      'starredBy': isStarred
          ? FieldValue.arrayRemove([uid])
          : FieldValue.arrayUnion([uid]),
      'starsCount': FieldValue.increment(delta),
    });
    if (ownerId.isNotEmpty && ownerId != uid) {
      batch.update(db.collection('users').doc(ownerId),
          {'starsReceived': FieldValue.increment(delta)});
    }
    try {
      await batch.commit();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update star. Try again.')),
        );
      }
    }
  }

  void _showReportSheet(BuildContext context) {
    const reasons = [
      'Bullying / harassment',
      'Unsafe act',
      'Nudity / sexual content',
      'Spam / fake account',
      'Other',
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0D0D1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Report Video',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Why are you reporting this?',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 16),
            ...reasons.map((r) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(r,
                      style: const TextStyle(color: Colors.white, fontSize: 14)),
                  trailing: const Icon(Icons.chevron_right_rounded,
                      color: Colors.white24, size: 18),
                  onTap: () async {
                    Navigator.pop(context);
                    await FirebaseFirestore.instance
                        .collection('reports')
                        .add({
                      'submissionId': submissionId,
                      'reportedBy': uid,
                      'reason': r,
                      'createdAt': Timestamp.now(),
                    });
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Report submitted. Thank you.')),
                      );
                    }
                  },
                )),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final username = data['username'] as String? ?? 'User';
    final challengeTitle = data['challengeTitle'] as String? ?? 'Challenge';
    final challengeId = data['challengeId'] as String? ?? '';
    final videoUrl = data['videoUrl'] as String? ?? '';
    final thumbnailUrl = data['thumbnailUrl'] as String?;
    final aiScore = (data['aiScore'] as num?)?.toInt();
    final starsCount = (data['starsCount'] as num?)?.toInt() ?? 0;
    final starredBy = (data['starredBy'] as List?) ?? [];
    final isStarred = starredBy.contains(uid);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0xFF0D0D1F),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Card header ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: _accent.withValues(alpha: 0.3),
                  child: Text(
                    username.isNotEmpty ? username[0].toUpperCase() : 'U',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(username,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14)),
                      GestureDetector(
                        onTap: challengeId.isNotEmpty
                            ? () => Navigator.push(context,
                                  MaterialPageRoute(
                                    builder: (_) => ChallengeDetail(
                                      title: challengeTitle,
                                      instructions: '',
                                      videoUrl: videoUrl,
                                      challengeId: challengeId,
                                    ),
                                  ))
                            : null,
                        child: Text(
                          challengeTitle,
                          style: const TextStyle(
                              color: Color(0xFFBB6BD9), fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (challengeId.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        _SourceChip(challengeId: challengeId),
                      ],
                    ],
                  ),
                ),
                if (aiScore != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: _accent.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      '$aiScore',
                      style: const TextStyle(
                          color: Color(0xFFD4A8FF),
                          fontWeight: FontWeight.w900,
                          fontSize: 18),
                    ),
                  ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => _showReportSheet(context),
                  child: const Icon(Icons.more_vert_rounded,
                      color: Colors.white38, size: 20),
                ),
              ],
            ),
          ),

          ClipRRect(
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(0)),
            child: SizedBox(
              height: 210,
              width: double.infinity,
              child: VideoThumbnailWidget(
                videoUrl: videoUrl,
                thumbnailUrl: thumbnailUrl,
                fit: BoxFit.cover,
              ),
            ),
          ),

          // ── Actions ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => _toggleStar(context),
                  child: Row(
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          isStarred
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          key: ValueKey(isStarred),
                          color: isStarred
                              ? const Color(0xFFFFD700)
                              : Colors.white54,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text('$starsCount',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 14)),
                    ],
                  ),
                ),
                const Spacer(),
                if (challengeId.isNotEmpty)
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChallengeDetail(
                          title: challengeTitle,
                          instructions: '',
                          videoUrl: videoUrl,
                          challengeId: challengeId,
                        ),
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 9),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF7B2CBF), Color(0xFF4B6EF6)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Take Challenge',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold),
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

// ── Source attribution chip ────────────────────────────────────────────────────

class _SourceInfo {
  final String label;
  final String? creatorId;
  const _SourceInfo(this.label, this.creatorId);
}

class _SourceChip extends StatelessWidget {
  static final Map<String, Future<_SourceInfo>> _cache = {};

  final String challengeId;
  const _SourceChip({required this.challengeId});

  static Future<_SourceInfo> _resolve(String id) {
    if (_cache.length >= 200) _cache.remove(_cache.keys.first);
    return _cache.putIfAbsent(id, () async {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('challenges')
            .doc(id)
            .get();
        if (!doc.exists) return const _SourceInfo('AURA ARENA', null);

        final creatorId =
            (doc.data()!['creatorId'] as String? ?? '').trim();

        if (creatorId.isEmpty || creatorId == 'system') {
          return const _SourceInfo('AURA ARENA', null);
        }

        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(creatorId)
            .get();
        final username =
            ((userDoc.data() ?? {})['username'] as String? ?? '').trim();
        return _SourceInfo(
          username.isNotEmpty ? '@$username' : '@creator',
          creatorId,
        );
      } catch (_) {
        return const _SourceInfo('AURA ARENA', null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_SourceInfo>(
      future: _resolve(challengeId),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();

        final info = snap.data!;
        final isOfficial = info.creatorId == null;
        final chipColor =
            isOfficial ? const Color(0xFF7B2CBF) : const Color(0xFF4B6EF6);
        final textColor =
            isOfficial ? const Color(0xFFD4A8FF) : const Color(0xFF93B4FF);

        return GestureDetector(
          onTap: info.creatorId != null
              ? () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          CreatorProfileScreen(creatorId: info.creatorId!),
                    ),
                  )
              : null,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: chipColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: chipColor.withValues(alpha: 0.40)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isOfficial
                      ? Icons.auto_awesome_rounded
                      : Icons.person_rounded,
                  color: textColor,
                  size: 9,
                ),
                const SizedBox(width: 3),
                Text(
                  info.label,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
