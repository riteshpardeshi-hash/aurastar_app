import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/services/brands_service.dart';
import '../../../core/services/challenges_service.dart';
import '../../../shared/widgets/follow_button.dart';
import '../../../shared/widgets/video_thumbnail_widget.dart';
import '../../challenges/screens/challenge_detail.dart';

class BrandProfileScreen extends StatefulWidget {
  final String brandId;

  const BrandProfileScreen({super.key, required this.brandId});

  @override
  State<BrandProfileScreen> createState() => _BrandProfileScreenState();
}

class _BrandProfileScreenState extends State<BrandProfileScreen> {
  static const _bg = Color(0xFF080810);
  static const _accent = Color(0xFF7B2CBF);

  final _service = BrandsService();

  Map<String, dynamic>? _brand;
  List<Map<String, dynamic>> _challenges = [];
  int _followerCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _service.fetchBrand(widget.brandId),
      _service.fetchBrandChallenges(widget.brandId, limit: 30),
      _service.fetchBrandFollowerCount(widget.brandId),
    ]);
    if (!mounted) return;
    setState(() {
      final raw = results[0] as Map<String, dynamic>?;
      _brand = raw != null ? normaliseBrand(raw) : null;
      _challenges = (results[1] as List<Map<String, dynamic>>)
          .map(normaliseChallenge)
          .toList();
      _followerCount = results[2] as int;
      _loading = false;
    });
  }

  void _share(String displayName) {
    Share.share('Check out $displayName on Aura Arena!');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: _accent))
            : _brand == null
                ? const Center(
                    child: Text('Brand not found',
                        style: TextStyle(color: Colors.white54)))
                : _buildBody(context, _brand!),
      ),
    );
  }

  Widget _buildBody(BuildContext context, Map<String, dynamic> brand) {
    final displayName = brand['displayName'] as String;
    final username = brand['username'] as String;
    final bio = brand['bio'] as String;
    final avatar = brand['avatar'] as String;
    final website = brand['website'] as String;
    final isFollowing = brand['isFollowing'] as bool;
    final isVerified = brand['isVerified'] as bool;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Row(
              children: [
                _circleIconButton(Icons.arrow_back_ios_new_rounded,
                    () => Navigator.pop(context)),
                const Spacer(),
                _circleIconButton(
                    Icons.ios_share_rounded, () => _share(displayName)),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: _buildCard(
              displayName, username, bio, avatar, website, isFollowing, isVerified),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text('Challenges',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'ClashDisplay')),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          sliver: _challenges.isEmpty
              ? SliverToBoxAdapter(child: _emptyChallenges())
              : SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 0.78,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final c = _challenges[index];
                      return _ChallengeCard(challenge: c);
                    },
                    childCount: _challenges.length,
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
    String website,
    bool isFollowing,
    bool isVerified,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E1A),
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
                backgroundImage:
                    avatar.isNotEmpty ? NetworkImage(avatar) : null,
                child: avatar.isEmpty
                    ? Text(
                        displayName.isNotEmpty
                            ? displayName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 22))
                    : null,
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _statColumn('${_challenges.length}', 'Challenges'),
                    _statDivider(),
                    _statColumn(_formatCount(_followerCount), 'Followers'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
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
                const Icon(Icons.verified_rounded,
                    color: _accent, size: 18),
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
                style: const TextStyle(
                    color: Colors.white70, fontSize: 12.5, height: 1.4)),
          ],
          if (website.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.link_rounded, color: _accent, size: 14),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(website,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: _accent, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          FollowButton(
            targetUserId: widget.brandId,
            initialIsFollowing: isFollowing,
            light: true,
            followFn: _service.followBrand,
            unfollowFn: _service.unfollowBrand,
          ),
        ],
      ),
    );
  }

  Widget _statDivider() => Container(
        width: 1,
        height: 28,
        color: Colors.white.withValues(alpha: 0.12),
      );

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

  Widget _emptyChallenges() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.flag_outlined, color: Colors.white24, size: 40),
            SizedBox(height: 10),
            Text('No challenges yet',
                style: TextStyle(color: Colors.white38, fontSize: 13)),
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

class _ChallengeCard extends StatelessWidget {
  final Map<String, dynamic> challenge;

  static const _accent = Color(0xFF7B2CBF);

  const _ChallengeCard({required this.challenge});

  @override
  Widget build(BuildContext context) {
    final id = challenge['id'] as String;
    final title = challenge['title'] as String;
    final videoUrl = challenge['videoUrl'] as String;
    final instructions = challenge['instructions'] as String;
    final stars = challenge['starsCount'] as int;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChallengeDetail(
            title: title,
            instructions: instructions,
            videoUrl: videoUrl,
            challengeId: id,
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            VideoThumbnailWidget(videoUrl: videoUrl, fit: BoxFit.cover),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.5, 1.0],
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.75),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.diamond, color: Colors.white, size: 10),
                    const SizedBox(width: 3),
                    Text('$stars',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
