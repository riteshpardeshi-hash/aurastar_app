import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/models/aura_tier.dart';
import '../../shared/widgets/level_up_sheet.dart';
import '../../shared/widgets/level_rewards_screen.dart';
import '../../shared/widgets/wallet_screen.dart';
import '../challenges/screens/all_general_challenges_screen.dart';
import '../challenges/screens/challenge_detail.dart';
import '../explore/screens/explore_creators_screen.dart';
import '../home/screens/home_feed_screen.dart';
import '../leaderboard/leaderboard_screen.dart';
import '../account/screens/my_account_screen.dart';
import '../creator/admin/creator_admin_screen.dart';
import '../creator/screens/creator_home_screen.dart';
import '../creator/screens/create_creator_profile_screen.dart';
import '../admin/screens/admin_screen.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  int _selectedIndex = 0;
  int? _lastKnownLevel;

  static const _bg = Color(0xFF080810);
  static const _accent = Color(0xFF7B2CBF);

  static const int _xpPerLevel = 1300;
  int _level(int pts) => (pts ~/ _xpPerLevel) + 1;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return _buildScaffold(context, points: 32670, isAdmin: false, isBrand: false, userId: '');
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            backgroundColor: _bg,
            body: Center(child: CircularProgressIndicator(color: _accent)),
          );
        }

        final userData = snap.data!.data() as Map<String, dynamic>? ?? {};
        final isAdmin = userData['isAdmin'] ?? false;
        final isBrand = userData['isCreator'] ?? false;
        final points = (userData['totalRewards'] ?? 0) as int;
        final level = _level(points);

        if (_lastKnownLevel != null && level > _lastKnownLevel!) {
          final oldTier = auraTierForLevel(_lastKnownLevel!);
          final newTier = auraTierForLevel(level);
          if (newTier.minLevel > oldTier.minLevel) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _showLevelUpModal(context, level, newTier);
            });
          }
        }
        _lastKnownLevel = level;

        return _buildScaffold(context, points: points, isAdmin: isAdmin, isBrand: isBrand, userId: user.uid);
      },
    );
  }

  Widget _buildScaffold(BuildContext context, {
    required int points,
    required bool isAdmin,
    required bool isBrand,
    required String userId,
  }) {
    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          Expanded(
            child: SafeArea(
              bottom: false,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    _buildAuraLevelsCard(context, points),
                    _buildCommunityFeedCard(context),
                    _buildLiveChallenges(context),
                    _buildExploreBrandsCard(context),
                    _buildBecomeCreatorBanner(context),
                    if (isBrand || isAdmin) _buildBrandTools(context, userId, isBrand),
                    if (isAdmin) _buildAdminButton(context),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
          _buildBottomNav(context),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: Row(
        children: [
          const Spacer(),
          Image.asset(
            'assets/images/aura star logo.png',
            height: 36,
            fit: BoxFit.contain,
          ),
          const Spacer(),
          Builder(
            builder: (context) => GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WalletScreen()),
              ),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF7B2CBF).withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF7B2CBF).withValues(alpha: 0.35)),
                ),
                child: const Icon(Icons.account_balance_wallet_outlined,
                    color: Color(0xFFD4A8FF), size: 22),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuraLevelsCard(BuildContext context, int points) {
    final level = _level(points);
    final tier = auraTierForLevel(level);
    final next = nextAuraTier(level);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LevelRewardsScreen()),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: tier.color.withValues(alpha: 0.35)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.black.withValues(alpha: 0.7),
              tier.color.withValues(alpha: 0.12),
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, color: Color(0xFF7B2CBF), size: 16),
                const SizedBox(width: 8),
                const Text(
                  'Aura Rewards',
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                const Text('View all >', style: TextStyle(color: Colors.white60, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: tier.color.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: tier.color.withValues(alpha: 0.55)),
                  ),
                  child: Text(
                    tier.name,
                    style: TextStyle(
                      color: tier.color,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tier.unlock,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ],
            ),
            if (next != null) ...[
              const SizedBox(height: 10),
              Text(
                'Next: Level ${next.minLevel} — ${next.name} · ${next.unlock}',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ] else ...[
              const SizedBox(height: 10),
              const Text(
                'Max tier reached — you\'re Divine!',
                style: TextStyle(color: Color(0xFFFFD700), fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showLevelUpModal(BuildContext context, int level, AuraTier tier) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LevelUpSheet(level: level, tier: tier),
    );
  }

  Widget _buildLiveChallenges(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('challenges')
          .where('creatorId', isEqualTo: 'system')
          .limit(2)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Live Challenges',
                    style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AllGeneralChallengesScreen()),
                    ),
                    child: const Text('View all >', style: TextStyle(color: Colors.white60, fontSize: 13)),
                  ),
                ],
              ),
            ),
            if (docs.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Text('No live challenges right now.', style: TextStyle(color: Colors.white54)),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Row(
                  children: List.generate(docs.length, (i) {
                    final doc = docs[i];
                    final data = doc.data() as Map<String, dynamic>;
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(left: i == 0 ? 0 : 10),
                        child: _buildLiveChallengeCard(context, doc.id, data),
                      ),
                    );
                  }),
                ),
              ),
            const SizedBox(height: 6),
          ],
        );
      },
    );
  }

  Widget _buildLiveChallengeCard(
    BuildContext context,
    String challengeId,
    Map<String, dynamic> data,
  ) {
    final title = data['title'] ?? 'Challenge';
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChallengeDetail(
            title: title,
            instructions: data['instructions'] ?? 'No instructions',
            videoUrl: data['videoUrl'] ?? '',
            challengeId: challengeId,
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 230,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1A0533), Color(0xFF3A1C71)],
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.78)],
                    stops: const [0.35, 1.0],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Image.asset('assets/images/live.png', height: 26),
                    const Spacer(),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                        shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Tap to participate',
                      style: TextStyle(
                        color: Color(0xFFBB6BD9),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExploreBrandsCard(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExploreCreatorsScreen())),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF0E0E20),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 100,
              height: 44,
              child: Stack(
                children: [
                  Positioned(left: 0, child: _brandLogo('assets/images/pepsi.png')),
                  Positioned(left: 30, child: _brandLogo('assets/images/Nike.png')),
                  Positioned(left: 60, child: _brandLogo('assets/images/H&M.png')),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Explore Brands',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Join exclusive brand campaigns\nand earn Aura Points.',
                    style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
                  ),
                ],
              ),
            ),
            Image.asset(
              'assets/images/Explore brand(clickable button).png',
              width: 44,
              height: 44,
            ),
          ],
        ),
      ),
    );
  }

  Widget _brandLogo(String asset) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF0E0E20), width: 2),
      ),
      child: ClipOval(child: Image.asset(asset, fit: BoxFit.cover)),
    );
  }

  Widget _buildCommunityFeedCard(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const HomeFeedScreen()),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0E0E20),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF7B2CBF).withValues(alpha: 0.2),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF7B2CBF).withValues(alpha: 0.4)),
              ),
              child: const Icon(Icons.people_alt_outlined, color: Color(0xFFD4A8FF), size: 24),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Community Feed',
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'See what others are submitting & star your favourites.',
                    style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.35),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 14),
          ],
        ),
      ),
    );
  }

  Widget _buildBecomeCreatorBanner(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      height: 160,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/images/creator image.png',
              fit: BoxFit.cover,
              alignment: Alignment.centerRight,
            ),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Color(0xEE000000), Color(0x33000000)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Become an', style: TextStyle(color: Colors.white, fontSize: 14)),
                  const Text(
                    'AURA CREATOR',
                    style: TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Unlock exclusive rewards,\nbrand collabs and more.',
                    style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () {},
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white70),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'JOIN NOW',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrandTools(BuildContext context, String userId, bool isBrand) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Brand Tools', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _gradientButton(
                  label: isBrand ? 'Brand Home' : 'Start Brand Page',
                  gradient: const [Color(0xFFF59E0B), Color(0xFFEF4444)],
                  onTap: () async {
                    final doc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
                    final data = doc.data() ?? {};
                    final alreadyBrand = data['isCreator'] ?? false;
                    if (!context.mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => alreadyBrand
                            ? const CreatorHomeScreen()
                            : const CreateCreatorProfileScreen(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _gradientButton(
                  label: 'Brand Admin',
                  gradient: const [Color(0xFF5B2EFF), Color(0xFF9B4DFF)],
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreatorAdminScreen())),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAdminButton(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminScreen())),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        height: 50,
        decoration: BoxDecoration(
          color: const Color(0xFFB91C1C),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Center(
          child: Text('Admin Panel', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
        ),
      ),
    );
  }

  Widget _gradientButton({
    required String label,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradient),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
        ),
      ),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 82,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Image.asset(
                'assets/images/menu container.png',
                fit: BoxFit.fill,
                height: 70,
              ),
            ),
            Positioned(
              bottom: 6,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _navItem('assets/images/Home.png', 'Home', 0,
                      () => setState(() => _selectedIndex = 0)),
                  _navItem('assets/images/challenge.png', 'Challenges', 1,
                      () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AllGeneralChallengesScreen()))),
                  const SizedBox(width: 62),
                  _navItem('assets/images/Leaderboard.png', 'Leaderboard', 2,
                      () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LeaderboardScreen()))),
                  _navItem('assets/images/user.png', 'Profile', 3,
                      () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyAccountScreen()))),
                ],
              ),
            ),
            Positioned(
              top: 0,
              child: GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HomeFeedScreen()),
                ),
                child: Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF7C3AED), Color(0xFF4B6EF6)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF7B2CBF).withValues(alpha: 0.55),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(15),
                    child: Image.asset('assets/images/A.png'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navItem(String asset, String label, int index, VoidCallback onTap) {
    final selected = _selectedIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedIndex = index);
        onTap();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ColorFiltered(
            colorFilter: ColorFilter.mode(
              selected ? Colors.white : Colors.white38,
              BlendMode.srcIn,
            ),
            child: Image.asset(asset, width: 24, height: 24),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white38,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}
