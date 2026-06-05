import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../shared/widgets/video_thumbnail_widget.dart';
import '../../video/screens/video_feed_screen.dart';
import '../../explore/screens/participant_profile_screen.dart';
import 'camera_screen.dart';

class WatchOthersScreen extends StatefulWidget {
  final String challengeId;
  final String challengeTitle;
  final int auraPoints;
  final String referenceVideoUrl;

  const WatchOthersScreen({
    super.key,
    required this.challengeId,
    required this.challengeTitle,
    this.auraPoints = 0,
    this.referenceVideoUrl = '',
  });

  @override
  State<WatchOthersScreen> createState() => _WatchOthersScreenState();
}

class _WatchOthersScreenState extends State<WatchOthersScreen>
    with SingleTickerProviderStateMixin {
  static const _bg     = Color(0xFF0D0D1A);
  static const _card   = Color(0xFF12102A);
  static const _accent = Color(0xFF7B2CBF);

  static const _tabLabels = ['Top Scores', 'Friends', 'Recent', 'Near You'];

  late final TabController _tabCtrl;

  // results per tab index
  final Map<int, List<Map<String, dynamic>>> _results = {};
  final Map<int, bool> _loading = {};
  final Map<int, bool> _loaded  = {};

  String? _currentUid;
  String  _currentCity = '';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabLabels.length, vsync: this)
      ..addListener(_onTabChanged);
    _currentUid = FirebaseAuth.instance.currentUser?.uid;
    _loadTab(0);
  }

  @override
  void dispose() {
    _tabCtrl
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabCtrl.indexIsChanging) return;
    _loadTab(_tabCtrl.index);
  }

  // ── Data loading ──────────────────────────────────────────────────────────

  Future<void> _loadTab(int tab) async {
    if (_loaded[tab] == true) return;
    setState(() => _loading[tab] = true);

    switch (tab) {
      case 0: await _loadTopScores();
      case 1: await _loadFriends();
      case 2: await _loadRecent();
      case 3: await _loadNearYou();
    }

    if (mounted) setState(() { _loading[tab] = false; _loaded[tab] = true; });
  }

  Future<void> _loadTopScores() async {
    final snap = await FirebaseFirestore.instance
        .collection('submissions')
        .where('challengeId', isEqualTo: widget.challengeId)
        .where('status',      isEqualTo: 'approved')
        .where('isPublic',    isEqualTo: true)
        .orderBy('aiScore',   descending: true)
        .limit(30)
        .get();
    if (mounted) setState(() => _results[0] = _toDocs(snap));
  }

  Future<void> _loadFriends() async {
    if (_currentUid == null) { setState(() => _results[1] = []); return; }

    final follows = await FirebaseFirestore.instance
        .collection('follows')
        .where('followerUserId', isEqualTo: _currentUid)
        .limit(30)
        .get();

    final uids = follows.docs
        .map((d) => d.data()['followedUserId'] as String?)
        .whereType<String>()
        .toList();

    if (uids.isEmpty) { if (mounted) setState(() => _results[1] = []); return; }

    final snap = await FirebaseFirestore.instance
        .collection('submissions')
        .where('challengeId', isEqualTo: widget.challengeId)
        .where('status',      isEqualTo: 'approved')
        .where('isPublic',    isEqualTo: true)
        .where('userId',      whereIn: uids)
        .orderBy('aiScore',   descending: true)
        .limit(30)
        .get();

    if (mounted) setState(() => _results[1] = _toDocs(snap));
  }

  Future<void> _loadRecent() async {
    final snap = await FirebaseFirestore.instance
        .collection('submissions')
        .where('challengeId', isEqualTo: widget.challengeId)
        .where('status',      isEqualTo: 'approved')
        .where('isPublic',    isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(30)
        .get();
    if (mounted) setState(() => _results[2] = _toDocs(snap));
  }

  Future<void> _loadNearYou() async {
    if (_currentCity.isEmpty && _currentUid != null) {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUid)
          .get();
      _currentCity = userDoc.data()?['city'] as String? ?? '';
    }

    if (_currentCity.isEmpty) {
      if (mounted) setState(() => _results[3] = []);
      return;
    }

    final snap = await FirebaseFirestore.instance
        .collection('submissions')
        .where('challengeId', isEqualTo: widget.challengeId)
        .where('status',      isEqualTo: 'approved')
        .where('isPublic',    isEqualTo: true)
        .orderBy('aiScore',   descending: true)
        .limit(50)
        .get();

    // Client-side city filter via user docs
    final docs = _toDocs(snap);
    final uids = docs.map((d) => d['userId'] as String? ?? '').where((u) => u.isNotEmpty).toSet().toList();

    if (uids.isEmpty) {
      if (mounted) setState(() => _results[3] = []);
      return;
    }

    // Batch-fetch users (Firestore whereIn max 30)
    final userSnap = await FirebaseFirestore.instance
        .collection('users')
        .where(FieldPath.documentId, whereIn: uids.take(30).toList())
        .get();

    final cityMap = { for (final d in userSnap.docs) d.id: d.data()['city'] as String? ?? '' };

    final nearby = docs.where((d) {
      final city = cityMap[d['userId'] as String? ?? ''] ?? '';
      return city.isNotEmpty && city == _currentCity;
    }).toList();

    if (mounted) setState(() => _results[3] = nearby);
  }

  List<Map<String, dynamic>> _toDocs(QuerySnapshot snap) => snap.docs
      .map((d) => {'id': d.id, 'data': d.data() as Map<String, dynamic>})
      .toList();

  // ── Navigation ────────────────────────────────────────────────────────────

  void _openFeed(List<Map<String, dynamic>> docs, int startIndex) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => VideoFeedScreen(
        submissions: docs,
        initialIndex: startIndex,
      ),
    ));
  }

  void _openUserProfile(String userId) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => ParticipantProfileScreen(userId: userId),
    ));
  }

  void _takeChallenge() {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => CameraScreen(
        challengeTitle: widget.challengeTitle,
        challengeId: widget.challengeId,
        referenceVideoUrl: widget.referenceVideoUrl,
      ),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          _buildHeader(),
          _buildTabBar(),
          Expanded(
            child: Stack(
              children: [
                TabBarView(
                  controller: _tabCtrl,
                  children: List.generate(_tabLabels.length, (i) => _buildTabBody(i)),
                ),
                _buildStickyBottomCTA(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Sticky header ─────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 8, 16, 12),
      decoration: const BoxDecoration(
        color: _bg,
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.10),
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(8),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.challengeTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.diamond, color: _accent, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      '${widget.auraPoints} Aura',
                      style: const TextStyle(color: Color(0xFFD4A8FF), fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _takeChallenge,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF6B21E8), Color(0xFF7B2CBF)]),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: _accent.withValues(alpha: 0.40), blurRadius: 10, offset: const Offset(0, 3))],
              ),
              child: const Text('Take', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab bar ───────────────────────────────────────────────────────────────

  Widget _buildTabBar() {
    return Container(
      color: _bg,
      child: TabBar(
        controller: _tabCtrl,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        indicatorColor: _accent,
        indicatorSize: TabBarIndicatorSize.label,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white38,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        dividerColor: Colors.white10,
        tabs: _tabLabels.map((t) => Tab(text: t)).toList(),
      ),
    );
  }

  // ── Tab body ──────────────────────────────────────────────────────────────

  Widget _buildTabBody(int tab) {
    if (_loading[tab] == true) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }

    final docs = _results[tab];
    if (docs == null) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }

    if (docs.isEmpty) return _buildEmpty(tab);

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      itemCount: docs.length,
      itemBuilder: (_, i) => _buildVideoCard(docs, i, tab),
    );
  }

  // ── Video card ────────────────────────────────────────────────────────────

  Widget _buildVideoCard(List<Map<String, dynamic>> docs, int index, int tab) {
    final item = docs[index];
    final data = item['data'] as Map<String, dynamic>;
    final videoUrl  = data['videoUrl']  as String? ?? '';
    final username  = data['username']  as String? ?? 'User';
    final userId    = data['userId']    as String? ?? '';
    final aiScore   = (data['aiScore']  as num?)?.toInt() ?? 0;
    final isTopTab  = tab == 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isTopTab && index < 3
              ? _accent.withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.07),
        ),
      ),
      child: Row(
        children: [
          // Thumbnail
          GestureDetector(
            onTap: () => _openFeed(docs, index),
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                bottomLeft: Radius.circular(14),
              ),
              child: SizedBox(
                width: 90,
                height: 110,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    VideoThumbnailWidget(videoUrl: videoUrl, fit: BoxFit.cover),
                    // Dark overlay
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.55)],
                        ),
                      ),
                    ),
                    // Play icon
                    Center(
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: _accent.withValues(alpha: 0.85),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Info
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Rank + username row
                  Row(
                    children: [
                      if (isTopTab) ...[
                        Text(
                          _rankLabel(index),
                          style: TextStyle(
                            fontSize: 16,
                            color: index == 0 ? const Color(0xFFFFD700) : Colors.white54,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _openUserProfile(userId),
                          child: Text(
                            '@$username',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Score
                  if (aiScore > 0)
                    Row(
                      children: [
                        const Icon(Icons.bar_chart_rounded, color: Color(0xFFD4A8FF), size: 14),
                        const SizedBox(width: 4),
                        Text(
                          'Score  $aiScore',
                          style: const TextStyle(color: Color(0xFFD4A8FF), fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  if (isTopTab && index < 3) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: _accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Rank #${index + 1}',
                        style: const TextStyle(color: Color(0xFFD4A8FF), fontSize: 10, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // View button
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () => _openFeed(docs, index),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _accent.withValues(alpha: 0.40)),
                ),
                child: const Text('View', style: TextStyle(color: Color(0xFFD4A8FF), fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Sticky bottom CTA ─────────────────────────────────────────────────────

  Widget _buildStickyBottomCTA() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_bg.withValues(alpha: 0), _bg.withValues(alpha: 0.95), _bg],
          ),
        ),
        child: GestureDetector(
          onTap: _takeChallenge,
          child: Container(
            width: double.infinity,
            height: 54,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6B21E8), Color(0xFF7B2CBF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(30),
              boxShadow: [BoxShadow(color: _accent.withValues(alpha: 0.50), blurRadius: 18, offset: const Offset(0, 5))],
            ),
            child: Center(
              child: Text(
                'Take ${widget.challengeTitle} Challenge',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Empty states ──────────────────────────────────────────────────────────

  Widget _buildEmpty(int tab) {
    final messages = [
      ('No attempts yet', 'Be the first to take this challenge!'),
      ('No friends have tried this', 'Follow more people to see their attempts here.'),
      ('No recent submissions', 'Check back soon for new attempts.'),
      (_currentCity.isEmpty
          ? 'City not set'
          : 'No players from $_currentCity yet',
       _currentCity.isEmpty
          ? 'Add your city in your profile to see nearby players.'
          : 'Be the first from your city to attempt this!'),
    ];
    final (title, subtitle) = messages[tab];

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.videocam_off_outlined, color: Colors.white24, size: 52),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white30, fontSize: 13, height: 1.5)),
            const SizedBox(height: 28),
            GestureDetector(
              onTap: _takeChallenge,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF6B21E8), Color(0xFF7B2CBF)]),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Text('Be the first — Take it now', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _rankLabel(int i) {
    switch (i) {
      case 0: return '🥇';
      case 1: return '🥈';
      case 2: return '🥉';
      default: return '#${i + 1}';
    }
  }
}
