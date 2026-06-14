import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/models/aura_tier.dart';
import '../../challenges/screens/all_general_challenges_screen.dart';

class CreatorDashboardScreen extends StatelessWidget {
  const CreatorDashboardScreen({super.key});

  static const int _xpPerLevel = 1300;
  int _level(int pts) => (pts ~/ _xpPerLevel) + 1;
  int _xpInCurrentLevel(int pts) => pts % _xpPerLevel;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF080810),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF080810),
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
          builder: (context, userSnap) {
            if (!userSnap.hasData) {
              return const Center(
                  child: CircularProgressIndicator(color: Color(0xFF7B2CBF)));
            }
            final userData = userSnap.data!.data() as Map<String, dynamic>? ?? {};

            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('submissions')
                  .where('userId', isEqualTo: uid)
                  .orderBy('createdAt', descending: true)
                  .limit(20)
                  .snapshots(),
              builder: (context, subSnap) {
                final submissions = subSnap.data?.docs ?? [];
                return _buildBody(context, uid, userData, submissions);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    String uid,
    Map<String, dynamic> userData,
    List<QueryDocumentSnapshot> submissions,
  ) {
    final name = (userData['name'] as String?)?.trim().isNotEmpty == true
        ? userData['name'] as String
        : userData['username'] as String? ?? 'Creator';
    final username = userData['username'] as String? ?? '';
    final bio = userData['bio'] as String? ?? '';
    final totalRewards = (userData['totalRewards'] as num?)?.toInt() ?? 0;
    final followerCount = (userData['followerCount'] as num?)?.toInt() ?? 0;
    final followingCount = (userData['followingCount'] as num?)?.toInt() ?? 0;

    final level = _level(totalRewards);
    final xpInLevel = _xpInCurrentLevel(totalRewards);
    final tier = auraTierForLevel(level);
    final nextTier = nextAuraTier(level);
    final progressFraction = (xpInLevel / _xpPerLevel).clamp(0.0, 1.0);

    final totalSubs = submissions.length;
    final approvedSubs = submissions.where((d) =>
        (d.data() as Map<String, dynamic>)['status'] == 'approved').length;
    final approvalRate = totalSubs == 0 ? 0 : (approvedSubs / totalSubs * 100).round();

    final recentSubs = submissions.take(5).toList();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(left: 4, top: 4),
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
        SliverToBoxAdapter(
            child: _buildHeader(context, uid, name, username, bio,
                followerCount, followingCount)),
        SliverToBoxAdapter(
            child: _buildAuraProgress(
                level, tier, nextTier, xpInLevel, progressFraction, totalRewards)),
        SliverToBoxAdapter(
            child: _buildStats(
                totalRewards, totalSubs, approvedSubs, approvalRate)),
        SliverToBoxAdapter(child: _buildQuickActions(context)),
        SliverToBoxAdapter(
            child: _buildRecentSubmissions(context, recentSubs)),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  Widget _buildHeader(
    BuildContext context,
    String uid,
    String name,
    String username,
    String bio,
    int followerCount,
    int followingCount,
  ) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'C';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A0A2E), Color(0xFF2D1B4E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF7B2CBF).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7B2FF7), Color(0xFFF107A3)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                      color: const Color(0xFF9B4DFF).withValues(alpha: 0.6), width: 2),
                ),
                child: Center(
                  child: Text(initial,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'ClashDisplay')),
                    if (username.isNotEmpty)
                      Text('@$username',
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 13)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF7B2CBF).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color(0xFF7B2CBF).withValues(alpha: 0.5)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star_rounded, color: Color(0xFF9B4DFF), size: 14),
                    SizedBox(width: 4),
                    Text('Creator',
                        style: TextStyle(
                            color: Color(0xFF9B4DFF),
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          if (bio.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(bio,
                style: const TextStyle(color: Colors.white60, fontSize: 13)),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              _followStat('$followerCount', 'Followers'),
              const SizedBox(width: 24),
              _followStat('$followingCount', 'Following'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _followStat(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'SpaceGrotesk')),
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ],
    );
  }

  Widget _buildAuraProgress(
    int level,
    AuraTier tier,
    AuraTier? nextTier,
    int xpInLevel,
    double progressFraction,
    int totalRewards,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0820),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF7B2CBF).withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF7B2CBF), Color(0xFF9B4DFF)]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('Level $level',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'SpaceGrotesk')),
              ),
              const SizedBox(width: 10),
              Text(tier.name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'ClashDisplay')),
              const Spacer(),
              Text('$totalRewards Aura',
                  style: const TextStyle(
                      color: Color(0xFF9B4DFF),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'SpaceGrotesk')),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progressFraction,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Color(0xFF7B2CBF)),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$xpInLevel / $_xpPerLevel XP',
                  style: const TextStyle(color: Colors.white38, fontSize: 11)),
              if (nextTier != null)
                Text('Next: ${nextTier.name}',
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStats(
      int totalRewards, int totalSubs, int approvedSubs, int approvalRate) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('My Stats',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'ClashDisplay')),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: _statCard(
                      'Total Aura', '$totalRewards', Icons.auto_awesome,
                      const Color(0xFF7B2CBF))),
              const SizedBox(width: 10),
              Expanded(
                  child: _statCard('Submissions', '$totalSubs',
                      Icons.video_collection, Colors.blue)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                  child: _statCard('Approved', '$approvedSubs',
                      Icons.check_circle_outline, Colors.green)),
              const SizedBox(width: 10),
              Expanded(
                  child: _statCard('Approval Rate', '$approvalRate%',
                      Icons.trending_up_rounded, Colors.orange)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: color.withValues(alpha: 0.15),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 8),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'SpaceGrotesk')),
          const SizedBox(height: 2),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: _actionBtn(
              label: 'Browse Challenges',
              icon: Icons.flash_on_rounded,
              gradient: const [Color(0xFF7B2CBF), Color(0xFF9B4DFF)],
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AllGeneralChallengesScreen())),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn({
    required String label,
    required IconData icon,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradient),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    fontFamily: 'SpaceGrotesk')),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentSubmissions(
      BuildContext context, List<QueryDocumentSnapshot> recentSubs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Text('Recent Submissions',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'ClashDisplay')),
        ),
        if (recentSubs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: const Column(
                children: [
                  Icon(Icons.video_camera_back_outlined,
                      color: Colors.white24, size: 36),
                  SizedBox(height: 10),
                  Text('No submissions yet',
                      style: TextStyle(color: Colors.white54, fontSize: 14)),
                  SizedBox(height: 4),
                  Text('Take a challenge to earn Aura points',
                      style: TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
            ),
          )
        else
          ...recentSubs.map((sub) => _buildSubmissionRow(context, sub)),
      ],
    );
  }

  Widget _buildSubmissionRow(BuildContext context, QueryDocumentSnapshot sub) {
    final data = sub.data() as Map<String, dynamic>;
    final challengeId = data['challengeId']?.toString() ?? '';
    final status = data['status']?.toString() ?? 'pending';
    final aiScore = (data['aiScore'] as num?)?.toInt();
    final auraPoints = (data['auraPoints'] as num?)?.toInt() ?? 0;
    final createdAt = data['createdAt'] as Timestamp?;
    final timeStr = createdAt != null ? _timeAgo(createdAt.toDate()) : '';

    Color statusColor;
    IconData statusIcon;
    String statusLabel;
    switch (status) {
      case 'approved':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle_rounded;
        statusLabel = 'Approved';
        break;
      case 'rejected':
        statusColor = Colors.red;
        statusIcon = Icons.cancel_rounded;
        statusLabel = 'Rejected';
        break;
      default:
        statusColor = Colors.orange;
        statusIcon = Icons.hourglass_top_rounded;
        statusLabel = 'Pending';
    }

    return FutureBuilder<DocumentSnapshot>(
      future: challengeId.isEmpty
          ? null
          : FirebaseFirestore.instance
              .collection('challenges')
              .doc(challengeId)
              .get(),
      builder: (context, snap) {
        final cData = snap.data?.data() as Map<String, dynamic>? ?? {};
        final challengeTitle = cData['title'] as String? ?? 'Challenge';

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(statusIcon, color: statusColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(challengeTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(statusLabel,
                              style: TextStyle(
                                  color: statusColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600)),
                        ),
                        if (timeStr.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(timeStr,
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 10)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (aiScore != null)
                    Text('$aiScore%',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            fontFamily: 'SpaceGrotesk')),
                  if (status == 'approved' && auraPoints > 0)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.auto_awesome,
                            color: Color(0xFF9B4DFF), size: 12),
                        const SizedBox(width: 2),
                        Text('+$auraPoints',
                            style: const TextStyle(
                                color: Color(0xFF9B4DFF),
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'just now';
  }
}
