import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'create_challenge.dart';
import '../../explore/screens/creator_profile_screen.dart';
import '../admin/creator_admin_screen.dart';
import '../admin/brand_participants_screen.dart';

class CreatorHomeScreen extends StatelessWidget {
  const CreatorHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
          builder: (context, userSnap) {
            final userData = userSnap.data?.data() as Map<String, dynamic>? ?? {};

            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('challenges')
                  .where('creatorId', isEqualTo: uid)
                  .where('status', isEqualTo: 'approved')
                  .snapshots(),
              builder: (context, challengeSnap) {
                final challenges = challengeSnap.data?.docs ?? [];
                final challengeIds = challenges.map((d) => d.id).toList();

                if (challengeIds.isEmpty) {
                  return _buildBody(context, uid, userData, challenges, []);
                }

                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('submissions')
                      .where('challengeId', whereIn: challengeIds.take(30).toList())
                      .snapshots(),
                  builder: (context, subSnap) {
                    final submissions = subSnap.data?.docs ?? [];
                    return _buildBody(context, uid, userData, challenges, submissions);
                  },
                );
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
    List<QueryDocumentSnapshot> challenges,
    List<QueryDocumentSnapshot> submissions,
  ) {
    final pageName = userData['pageName'] as String? ?? 'Your Brand';
    final username = userData['username'] as String? ?? '';
    final bio = userData['bio'] as String? ?? '';

    final totalChallenges = challenges.length;
    final totalSubmissions = submissions.length;
    final uniqueUserIds = submissions
        .map((d) => (d.data() as Map<String, dynamic>)['userId']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    final uniqueUsers = uniqueUserIds.length;
    final avgPerUser = uniqueUsers == 0 ? 0.0 : totalSubmissions / uniqueUsers;

    final pendingCount = submissions.where((d) {
      return (d.data() as Map<String, dynamic>)['status'] == 'pending';
    }).length;

    // Returning participants: users who submitted to 2+ distinct challenges
    final userChallengeMap = <String, Set<String>>{};
    for (final sub in submissions) {
      final d = sub.data() as Map<String, dynamic>;
      final uId = d['userId']?.toString() ?? '';
      final cId = d['challengeId']?.toString() ?? '';
      if (uId.isNotEmpty && cId.isNotEmpty) {
        userChallengeMap.putIfAbsent(uId, () => {}).add(cId);
      }
    }
    final returningParticipants =
        userChallengeMap.values.where((s) => s.length > 1).length;

    // Top challenge by submission count
    final subCountByChallengeId = <String, int>{};
    for (final sub in submissions) {
      final cId =
          (sub.data() as Map<String, dynamic>)['challengeId']?.toString() ?? '';
      if (cId.isNotEmpty) {
        subCountByChallengeId[cId] = (subCountByChallengeId[cId] ?? 0) + 1;
      }
    }

    // Week-over-week submissions
    final now = DateTime.now();
    final thisWeekStart = now.subtract(const Duration(days: 7));
    final lastWeekStart = now.subtract(const Duration(days: 14));
    int thisWeekSubs = 0;
    int lastWeekSubs = 0;
    for (final sub in submissions) {
      final ts =
          (sub.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
      if (ts == null) continue;
      final dt = ts.toDate();
      if (dt.isAfter(thisWeekStart)) {
        thisWeekSubs++;
      } else if (dt.isAfter(lastWeekStart)) {
        lastWeekSubs++;
      }
    }
    final weekDelta = thisWeekSubs - lastWeekSubs;

    final sortedSubs = [...submissions]..sort((a, b) {
        final aTime = (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
        final bTime = (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });
    final recentSubs = sortedSubs.take(10).toList();
    final challengeMap = {
      for (var d in challenges)
        d.id: (d.data() as Map<String, dynamic>)['title'] as String? ?? 'Challenge'
    };

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.only(left: 4, top: 4),
              child: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
            child: _buildHeader(context, uid, pageName, username, bio)),
        SliverToBoxAdapter(child: _buildQuickActions(context, uid)),
        SliverToBoxAdapter(
          child: _buildMetrics(
            context,
            totalChallenges,
            totalSubmissions,
            uniqueUsers,
            avgPerUser,
            uniqueUserIds,
            returningParticipants,
            thisWeekSubs,
            weekDelta,
            subCountByChallengeId,
            challengeMap,
          ),
        ),
        if (pendingCount > 0)
          SliverToBoxAdapter(
              child: _buildPendingSubmissionsBanner(
                  context, pendingCount, uniqueUserIds)),
        SliverToBoxAdapter(child: _buildPendingRequestsSection(uid)),
        SliverToBoxAdapter(
            child: _buildActiveChallenges(context, challenges, submissions)),
        SliverToBoxAdapter(
            child: _buildRecentActivity(context, recentSubs, challengeMap)),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context, String uid, String pageName,
      String username, String bio) {
    final initial = pageName.isNotEmpty ? pageName[0].toUpperCase() : 'B';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7B2FF7), Color(0xFFF107A3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                child: Text(initial,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pageName,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'ClashDisplay')),
                    if (username.isNotEmpty)
                      Text('@$username',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 14)),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => CreatorProfileScreen(creatorId: uid)),
                ),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('View Profile',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
          if (bio.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(bio,
                style:
                    const TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ],
      ),
    );
  }

  // ── Quick Actions ────────────────────────────────────────────────────────────

  Widget _buildQuickActions(BuildContext context, String uid) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: _actionBtn(
              label: 'Create Challenge',
              icon: Icons.add_circle_outline,
              gradient: const [Color(0xFF7B2CBF), Color(0xFF9B4DFF)],
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const CreateChallenge())),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _actionBtn(
              label: 'Analytics',
              icon: Icons.bar_chart_rounded,
              gradient: const [Color(0xFF1E3A5F), Color(0xFF2563EB)],
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const CreatorAdminScreen())),
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

  // ── Metrics ──────────────────────────────────────────────────────────────────

  Widget _buildMetrics(
    BuildContext context,
    int totalChallenges,
    int totalSubmissions,
    int uniqueUsers,
    double avgPerUser,
    List<String> uniqueUserIds,
    int returningParticipants,
    int thisWeekSubs,
    int weekDelta,
    Map<String, int> subCountById,
    Map<String, String> challengeMap,
  ) {
    // Resolve top challenge
    String topChallengeTitle = '';
    int topChallengeCount = 0;
    if (subCountById.isNotEmpty) {
      final top =
          subCountById.entries.reduce((a, b) => a.value > b.value ? a : b);
      topChallengeTitle = challengeMap[top.key] ?? 'Challenge';
      topChallengeCount = top.value;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Campaign Overview',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'ClashDisplay')),
          const SizedBox(height: 12),
          // Row 1: Challenges + Submissions
          Row(
            children: [
              Expanded(
                  child: _metricCard('Challenges', '$totalChallenges',
                      Icons.flash_on, Colors.amber)),
              const SizedBox(width: 10),
              Expanded(
                  child: _metricCard('Submissions', '$totalSubmissions',
                      Icons.video_collection, Colors.blue)),
            ],
          ),
          const SizedBox(height: 10),
          // Row 2: Participants + Avg videos/user
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: uniqueUserIds.isEmpty
                      ? null
                      : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => BrandParticipantsScreen(
                                  userIds: uniqueUserIds),
                            ),
                          ),
                  child: _metricCard('Participants', '$uniqueUsers',
                      Icons.people, Colors.green,
                      subtitle:
                          uniqueUserIds.isNotEmpty ? 'Tap to view' : null),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: _metricCard('Avg Videos/User',
                      avgPerUser.toStringAsFixed(1), Icons.analytics,
                      Colors.purple)),
            ],
          ),
          const SizedBox(height: 10),
          // Row 3: Returning participants + This week (with WoW delta)
          Row(
            children: [
              Expanded(
                child: _metricCard(
                  'Returning',
                  '$returningParticipants',
                  Icons.repeat,
                  Colors.teal,
                  subtitle: uniqueUsers > 0
                      ? '${((returningParticipants / uniqueUsers) * 100).round()}% of users'
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: _weekDeltaCard(thisWeekSubs, weekDelta)),
            ],
          ),
          // Top challenge card (full-width, only when data exists)
          if (topChallengeTitle.isNotEmpty) ...[
            const SizedBox(height: 10),
            _topChallengeCard(topChallengeTitle, topChallengeCount),
          ],
        ],
      ),
    );
  }

  Widget _weekDeltaCard(int thisWeekSubs, int weekDelta) {
    final isPositive = weekDelta > 0;
    final isFlat = weekDelta == 0;
    final deltaColor =
        isFlat ? Colors.white38 : (isPositive ? Colors.green : Colors.red);
    final deltaIcon =
        isFlat ? Icons.remove : (isPositive ? Icons.arrow_upward : Icons.arrow_downward);
    final deltaLabel = isFlat
        ? 'same as last week'
        : '${isPositive ? '+' : ''}$weekDelta vs last week';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.indigo.withValues(alpha: 0.15),
            child: const Icon(Icons.calendar_today,
                color: Colors.indigo, size: 18),
          ),
          const SizedBox(height: 8),
          Text('$thisWeekSubs',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          const Text('This Week',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(deltaIcon, color: deltaColor, size: 11),
              const SizedBox(width: 2),
              Flexible(
                child: Text(deltaLabel,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: deltaColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _topChallengeCard(String title, int count) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child:
                const Icon(Icons.emoji_events, color: Colors.amber, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Top Challenge',
                    style: TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$count',
                  style: const TextStyle(
                      color: Colors.amber,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              const Text('submissions',
                  style: TextStyle(color: Colors.white38, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricCard(String title, String value, IconData icon, Color color,
      {String? subtitle}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
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
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(title,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: Colors.white54, fontSize: 11)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle,
                style: const TextStyle(
                    color: Color(0xFF9B4DFF),
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }

  // ── Pending Submissions Banner ────────────────────────────────────────────────

  Widget _buildPendingSubmissionsBanner(
      BuildContext context, int count, List<String> uniqueUserIds) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                BrandParticipantsScreen(userIds: uniqueUserIds)),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF7B2CBF).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: const Color(0xFF7B2CBF).withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.pending_actions, color: Color(0xFF9B4DFF)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      '$count submission${count > 1 ? 's' : ''} awaiting review',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                  const Text('Tap to review participants',
                      style:
                          TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios,
                color: Colors.white54, size: 14),
          ],
        ),
      ),
    );
  }

  // ── Pending Admin Review Banner ───────────────────────────────────────────────

  Widget _buildPendingRequestsSection(String uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('creator_requests')
          .where('creatorId', isEqualTo: uid)
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snap) {
        final count = snap.data?.docs.length ?? 0;
        if (count == 0) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.hourglass_top,
                  color: Colors.amber, size: 20),
              const SizedBox(width: 12),
              Text(
                  '$count challenge request${count > 1 ? 's' : ''} pending admin approval',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 13)),
            ],
          ),
        );
      },
    );
  }

  // ── Active Challenges ─────────────────────────────────────────────────────────

  Widget _buildActiveChallenges(
    BuildContext context,
    List<QueryDocumentSnapshot> challenges,
    List<QueryDocumentSnapshot> submissions,
  ) {
    if (challenges.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Active Challenges',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'ClashDisplay')),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: const Column(
                children: [
                  Icon(Icons.flash_on, color: Colors.white24, size: 32),
                  SizedBox(height: 8),
                  Text('No approved challenges yet',
                      style: TextStyle(color: Colors.white54)),
                  SizedBox(height: 4),
                  Text('Create a challenge to get started',
                      style:
                          TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Text('Active Challenges',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'ClashDisplay')),
        ),
        SizedBox(
          height: 110,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: challenges.length,
            itemBuilder: (context, i) {
              final data =
                  challenges[i].data() as Map<String, dynamic>;
              final title =
                  data['title'] as String? ?? 'Challenge';
              final challengeId = challenges[i].id;

              final subCount = submissions.where((s) =>
                  (s.data() as Map<String, dynamic>)['challengeId'] ==
                  challengeId).length;
              final pendingCount = submissions.where((s) {
                final sd = s.data() as Map<String, dynamic>;
                return sd['challengeId'] == challengeId &&
                    sd['status'] == 'pending';
              }).length;

              return Container(
                width: 165,
                margin: EdgeInsets.only(
                    right: i < challenges.length - 1 ? 12 : 0),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                    const Spacer(),
                    Row(
                      children: [
                        const Icon(Icons.video_collection,
                            color: Colors.white54, size: 14),
                        const SizedBox(width: 4),
                        Text('$subCount',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12)),
                        if (pendingCount > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7B2CBF),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('$pendingCount pending',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Recent Activity ───────────────────────────────────────────────────────────

  Widget _buildRecentActivity(
    BuildContext context,
    List<QueryDocumentSnapshot> recentSubs,
    Map<String, String> challengeMap,
  ) {
    if (recentSubs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Text('Recent Activity',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'ClashDisplay')),
        ),
        ...recentSubs.map((sub) {
          final data = sub.data() as Map<String, dynamic>;
          final userId = data['userId']?.toString() ?? '';
          final challengeId = data['challengeId']?.toString() ?? '';
          final challengeTitle =
              challengeMap[challengeId] ?? 'Challenge';
          final createdAt = data['createdAt'] as Timestamp?;
          final timeStr =
              createdAt != null ? _timeAgo(createdAt.toDate()) : '';

          return FutureBuilder<DocumentSnapshot>(
            future: userId.isEmpty
                ? null
                : FirebaseFirestore.instance
                    .collection('users')
                    .doc(userId)
                    .get(),
            builder: (context, userSnap) {
              final uData = userSnap.data?.data()
                      as Map<String, dynamic>? ??
                  {};
              final name = uData.isNotEmpty
                  ? (uData['name'] as String? ??
                      uData['username'] as String? ??
                      'User')
                  : 'User';
              final initial =
                  name.isNotEmpty ? name[0].toUpperCase() : 'U';

              return Container(
                margin:
                    const EdgeInsets.fromLTRB(16, 0, 16, 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color:
                          Colors.white.withValues(alpha: 0.06)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: const Color(0xFF7B2CBF)
                          .withValues(alpha: 0.2),
                      child: Text(initial,
                          style: const TextStyle(
                              color: Color(0xFF9B4DFF),
                              fontWeight: FontWeight.bold,
                              fontSize: 14)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                          Text(
                              'submitted to $challengeTitle',
                              style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    if (timeStr.isNotEmpty)
                      Text(timeStr,
                          style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 11)),
                  ],
                ),
              );
            },
          );
        }),
      ],
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
