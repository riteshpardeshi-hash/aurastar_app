import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/models/aura_tier.dart';
import '../../../core/services/creators_service.dart';
import '../../../shared/widgets/follow_button.dart';
import '../../../shared/widgets/video_thumbnail_widget.dart';
import '../../video/widgets/video_player_widget.dart';

class CreatorProfileScreen extends StatefulWidget {
  final String creatorId;

  const CreatorProfileScreen({super.key, required this.creatorId});

  @override
  State<CreatorProfileScreen> createState() => _CreatorProfileScreenState();
}

class _CreatorProfileScreenState extends State<CreatorProfileScreen> {
  static const _bg     = Color(0xFF080810);
  static const _accent = Color(0xFF7B2CBF);

  final _service = CreatorsService();

  Map<String, dynamic>? _creator;
  List<Map<String, dynamic>> _videos = [];
  int _followerCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _service.fetchCreator(widget.creatorId),
      _service.fetchCreatorVideos(widget.creatorId, limit: 30),
      _service.fetchCreatorFollowerCount(widget.creatorId),
    ]);
    if (!mounted) return;
    setState(() {
      final raw = results[0] as Map<String, dynamic>?;
      _creator = raw != null ? normaliseCreator(raw) : null;
      _videos = (results[1] as List<Map<String, dynamic>>)
          .map(normaliseCreatorVideo)
          .toList();
      _followerCount = results[2] as int;
      _loading = false;
    });
  }

  void _share(String displayName) {
    Share.share('Check out @$displayName on Aura Arena!');
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
                    child: Text('Creator not found', style: TextStyle(color: Colors.white54)))
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
                const Spacer(),
                _circleIconButton(Icons.ios_share_rounded, () => _share(displayName)),
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
          sliver: _videos.isEmpty
              ? SliverToBoxAdapter(child: _emptyVideos())
              : SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                    childAspectRatio: 0.72,
                  ),
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
                            fit: BoxFit.cover,
                          ),
                        ),
                      );
                    },
                    childCount: _videos.length,
                  ),
                ),
        ),
      ],
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
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2D1B4E), Color(0xFF7B2CBF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: Colors.white24,
                backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
                child: avatar.isEmpty
                    ? Text(displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22))
                    : null,
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _statColumn('${_videos.length}', 'Challenges'),
                    _statColumn(_formatCount(_followerCount), 'Followers'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            displayName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'ClashDisplay'),
                          ),
                        ),
                        if (isVerified) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.verified_rounded, color: Color(0xFF7B9CFF), size: 18),
                        ],
                      ],
                    ),
                    if (username.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text('@$username',
                          style: const TextStyle(color: Colors.white60, fontSize: 14)),
                    ],
                    if (bio.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(bio,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.4)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _tierBadge(tier),
            ],
          ),
          const SizedBox(height: 18),
          FollowButton(targetUserId: widget.creatorId, initialIsFollowing: isFollowing),
        ],
      ),
    );
  }

  Widget _statColumn(String value, String label) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                fontFamily: 'SpaceGrotesk')),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
      ],
    );
  }

  Widget _tierBadge(AuraTier tier) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: tier.color.withValues(alpha: 0.15),
        border: Border.all(color: tier.color.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Icon(Icons.workspace_premium_rounded, color: tier.color, size: 28),
    );
  }

  Widget _emptyVideos() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.videocam_off_outlined, color: Colors.white24, size: 40),
            SizedBox(height: 10),
            Text('No videos yet', style: TextStyle(color: Colors.white38, fontSize: 13)),
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
