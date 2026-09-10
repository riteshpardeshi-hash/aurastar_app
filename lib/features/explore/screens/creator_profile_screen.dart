import 'package:flutter/material.dart';
import '../../../core/models/aura_tier.dart';
import '../../../core/services/challenges_service.dart';
import '../../../core/services/creators_service.dart';
import '../../../core/services/screen_cache.dart';
import '../../../core/services/video_prewarm_cache.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/follow_button.dart';
import '../../../shared/widgets/video_thumbnail_widget.dart';
import '../../challenges/screens/challenge_detail.dart';
import '../../video/widgets/video_player_widget.dart';

class CreatorProfileScreen extends StatefulWidget {
  final String creatorId;

  const CreatorProfileScreen({super.key, required this.creatorId});

  @override
  State<CreatorProfileScreen> createState() => _CreatorProfileScreenState();
}

class _CreatorProfileScreenState extends State<CreatorProfileScreen> {
  static const _bg          = Color(0xFF080810);
  static const _accent      = Color(0xFF7B2CBF);
  static const _accentLight  = Color(0xFFD4A8FF);

  final _service = CreatorsService();

  Map<String, dynamic>? _creator;
  // The creator's authored challenges — the profile's primary content.
  List<Map<String, dynamic>> _challenges = [];
  // Their own challenge-attempt submissions. Currently always empty from the
  // backend (docs/backend-issues/005); kept as a fallback grid for accounts
  // that authored no challenges, and for when that gap is fixed.
  List<Map<String, dynamic>> _videos = [];
  int _followerCount = 0;
  bool _loading = true;

  // Stale-while-revalidate — creator pages get re-opened constantly (from
  // every thumbnail grid), so the last-known page is cached per id and shown
  // instantly on re-entry while a fresh copy loads underneath. Follower
  // count / follow state converge on that background refresh.
  String get _cacheKey => 'creator.${widget.creatorId}';

  @override
  void initState() {
    super.initState();
    final cached = ScreenCache.read<Map<String, dynamic>>(_cacheKey);
    if (cached != null) {
      _creator = cached['creator'] as Map<String, dynamic>?;
      _challenges =
          (cached['challenges'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      _videos =
          (cached['videos'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      _followerCount = cached['followers'] as int? ?? 0;
      _loading = false;
    }
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _service.fetchCreator(widget.creatorId),
      _service.fetchCreatorVideos(widget.creatorId, limit: 30),
      _service.fetchCreatorFollowerCount(widget.creatorId),
      _service.fetchCreatorChallenges(widget.creatorId, limit: 30),
    ]);
    if (!mounted) return;
    final raw = results[0] as Map<String, dynamic>?;
    final creator = raw != null ? normaliseCreator(raw) : null;
    final videos = (results[1] as List<Map<String, dynamic>>)
        .map(normaliseCreatorVideo)
        .toList();
    final followers = results[2] as int;
    final challenges = (results[3] as List<Map<String, dynamic>>)
        .map(normaliseChallenge)
        .toList();
    // A failed fetch (creator == null) shouldn't wipe a good cached page.
    if (creator == null && _creator != null) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _creator = creator;
      _challenges = challenges;
      _videos = videos;
      _followerCount = followers;
      _loading = false;
    });
    if (creator != null) {
      ScreenCache.write(_cacheKey, {
        'creator': creator,
        'challenges': challenges,
        'videos': videos,
        'followers': followers,
      });
    }
    // Prewarm just the first few grid videos — the ones visible without
    // scrolling and most likely to be tapped first — not the whole list,
    // to keep VideoPrewarmCache's small cap from thrashing. mixWithOthers
    // defaults to false here to match VideoPlayerWidget's own default,
    // since that's what _VideoViewerScreen plays these through.
    for (final v in _videos.take(3)) {
      final videoUrl = v['videoUrl'] as String? ?? '';
      if (videoUrl.isNotEmpty) VideoPrewarmCache.prewarm(videoUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: _accent))
            : _creator == null
                ? const Center(
                    child: Text('Creator not found', style: TextStyle(color: AppColors.textMuted)))
                : _buildBody(context, _creator!),
      ),
    );
  }

  Widget _buildBody(BuildContext context, Map<String, dynamic> creator) {
    final displayName = creator['displayName'] as String;
    final username = creator['username'] as String;
    final bio = creator['bio'] as String;
    final avatar = creator['avatar'] as String;
    final isFollowing = creator['isFollowing'] as bool;
    final isVerified = creator['isVerified'] as bool;
    // Server-computed and authoritative — do not recompute locally.
    final tier = auraTierForName(creator['tier'] as String?);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Row(
              children: [
                _circleIconButton(Icons.arrow_back_ios_new_rounded, () => Navigator.pop(context)),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
            child: _buildCard(displayName, username, bio, avatar, isFollowing, isVerified, tier)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
          sliver: _buildContentSliver(context),
        ),
      ],
    );
  }

  // Authored challenges are the primary content. Fall back to the creator's
  // own attempt-submissions only when they've authored nothing (e.g. a
  // regular user promoted to creator), then to an empty state.
  Widget _buildContentSliver(BuildContext context) {
    if (_challenges.isNotEmpty) return _challengeGrid(context);
    if (_videos.isNotEmpty) return _videoGrid(context);
    return SliverToBoxAdapter(child: _emptyVideos());
  }

  static const _gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 3,
    crossAxisSpacing: 6,
    mainAxisSpacing: 6,
    childAspectRatio: 0.72,
  );

  Widget _challengeGrid(BuildContext context) {
    return SliverGrid(
      gridDelegate: _gridDelegate,
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final c = _challenges[index];
          return GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChallengeDetail(
                  challengeId: c['id'] as String,
                  title: c['title'] as String? ?? '',
                  // ChallengeDetail fills these in from its own fetch.
                  instructions: c['instructions'] as String? ?? '',
                  videoUrl: c['videoUrl'] as String? ?? '',
                ),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  VideoThumbnailWidget(
                    videoUrl: c['videoUrl'] as String? ?? '',
                    thumbnailUrl: (c['thumbnailUrl'] as String?)?.isNotEmpty == true
                        ? c['thumbnailUrl'] as String
                        : null,
                    fit: BoxFit.cover,
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(6, 12, 6, 6),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.7),
                          ],
                        ),
                      ),
                      child: Text(
                        c['title'] as String? ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        childCount: _challenges.length,
      ),
    );
  }

  Widget _videoGrid(BuildContext context) {
    return SliverGrid(
      gridDelegate: _gridDelegate,
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final v = _videos[index];
          return GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _VideoViewerScreen(
                  videoUrl: v['videoUrl'] as String,
                  aiScore: v['aiScore'] as int?,
                ),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: VideoThumbnailWidget(
                videoUrl: v['videoUrl'] as String,
                thumbnailUrl: v['thumbnailUrl'] as String?,
                fit: BoxFit.cover,
              ),
            ),
          );
        },
        childCount: _videos.length,
      ),
    );
  }

  Widget _circleIconButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _accent.withValues(alpha: 0.15),
          border: Border.all(color: _accent.withValues(alpha: 0.4)),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }

  Widget _buildCard(
    String displayName,
    String username,
    String bio,
    String avatar,
    bool isFollowing,
    bool isVerified,
    AuraTier tier,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: BoxDecoration(
        // A clean themed surface with a soft purple glow bleeding from the top
        // — replaces the old full-bleed raster gradient image that washed the
        // text out and looked off-theme.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _accent.withValues(alpha: 0.16),
            const Color(0xFF12111C),
          ],
          stops: const [0.0, 0.55],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          // Avatar with a tier-coloured ring.
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: tier.color.withValues(alpha: 0.9), width: 2),
            ),
            child: CircleAvatar(
              radius: 40,
              backgroundColor: Colors.white12,
              backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
              child: avatar.isEmpty
                  ? Text(
                      displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 28,
                          fontFamily: 'SpaceGrotesk'),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 14),
          // Name + verified tick.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  displayName,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'SpaceGrotesk'),
                ),
              ),
              if (isVerified) ...[
                const SizedBox(width: 6),
                const Icon(Icons.verified_rounded, color: _accentLight, size: 18),
              ],
            ],
          ),
          if (username.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text('@$username',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ],
          const SizedBox(height: 10),
          // Tier chip.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: tier.color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: tier.color.withValues(alpha: 0.45)),
            ),
            child: Text(
              tier.name.toUpperCase(),
              style: TextStyle(
                  color: tier.color,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  fontFamily: 'SpaceGrotesk'),
            ),
          ),
          if (bio.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              bio,
              maxLines: 3,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: AppColors.textMuted, fontSize: 12.5, height: 1.45),
            ),
          ],
          const SizedBox(height: 18),
          // Stats.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _stat('${_challenges.length}', 'Challenges'),
              Container(
                width: 1,
                height: 34,
                margin: const EdgeInsets.symmetric(horizontal: 28),
                color: Colors.white.withValues(alpha: 0.12),
              ),
              _stat(_formatCount(_followerCount), 'Followers'),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FollowButton(
              targetUserId: widget.creatorId,
              initialIsFollowing: isFollowing,
              // Follower count + isFollowing in the cached page are now stale —
              // drop it so the next visit re-fetches instead of showing the
              // pre-toggle numbers.
              onChanged: (_) => ScreenCache.invalidate(_cacheKey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                fontFamily: 'SpaceGrotesk')),
        const SizedBox(height: 3),
        Text(label.toUpperCase(),
            style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 10,
                letterSpacing: 0.8,
                fontFamily: 'SpaceGrotesk')),
      ],
    );
  }

  Widget _emptyVideos() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _accent.withValues(alpha: 0.12),
                border: Border.all(color: _accent.withValues(alpha: 0.25)),
              ),
              child: const Icon(Icons.videocam_off_rounded,
                  color: _accentLight, size: 28),
            ),
            const SizedBox(height: 14),
            const Text('No challenges yet',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'SpaceGrotesk')),
            const SizedBox(height: 4),
            const Text("This creator hasn't published a challenge.",
                style: TextStyle(color: AppColors.textFaint, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  String _formatCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }
}

class _VideoViewerScreen extends StatelessWidget {
  final String videoUrl;
  final int? aiScore;

  const _VideoViewerScreen({required this.videoUrl, this.aiScore});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (aiScore != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Row(
                  children: [
                    const Icon(Icons.star_rounded, color: Color(0xFFFFD700), size: 18),
                    const SizedBox(width: 4),
                    Text('$aiScore',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
        ],
      ),
      body: Center(child: VideoPlayerWidget(videoUrl)),
    );
  }
}
