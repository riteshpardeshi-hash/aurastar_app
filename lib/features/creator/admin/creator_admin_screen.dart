import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../screens/creator_entries_screen.dart';
import '../../../shared/theme/app_colors.dart';

class CreatorAdminScreen extends StatelessWidget {
  const CreatorAdminScreen({super.key});

  static const _bg     = Color(0xFF080810);
  static const _accent = Color(0xFF7B2CBF);

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(
          backgroundColor: Color(0xFF080810),
          body: Center(child: Text('Not signed in.',
              style: TextStyle(color: AppColors.textMuted))));
    }

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Analytics',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800,
                fontFamily: 'ClashDisplay')),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('challenges')
            .where('creatorId', isEqualTo: uid)
            .where('status', isEqualTo: 'approved')
            .snapshots(),
        builder: (context, challengeSnap) {
          if (!challengeSnap.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: Color(0xFF7B2CBF)));
          }
          final challenges = challengeSnap.data!.docs;
          if (challenges.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bar_chart_rounded,
                      color: Colors.white24, size: 48),
                  const SizedBox(height: 12),
                  const Text('No live challenges yet',
                      style: TextStyle(color: AppColors.textFaint)),
                ],
              ),
            );
          }

          final challengeIds = challenges.map((d) => d.id).toList();

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('submissions')
                .where('challengeId',
                    whereIn: challengeIds.take(30).toList())
                .snapshots(),
            builder: (context, subSnap) {
              final allSubs = subSnap.data?.docs ?? [];

              // ── Aggregate stats ──
              final totalSubs = allSubs.length;
              final uniqueUsers = allSubs
                  .map((d) =>
                      (d.data() as Map<String, dynamic>)['userId']
                          ?.toString() ??
                      '')
                  .where((id) => id.isNotEmpty)
                  .toSet()
                  .length;
              final approvedSubs = allSubs
                  .where((d) =>
                      (d.data() as Map<String, dynamic>)['status'] ==
                      'approved')
                  .toList();
              final avgScore = approvedSubs.isEmpty
                  ? 0.0
                  : approvedSubs
                          .map((d) =>
                              ((d.data() as Map<String, dynamic>)['aiScore']
                                      as num?) ??
                              0)
                          .reduce((a, b) => a + b) /
                      approvedSubs.length;

              // Returning participants (> 1 unique challenge)
              final userToChallenges = <String, Set<String>>{};
              for (final s in allSubs) {
                final d    = s.data() as Map<String, dynamic>;
                final uId  = d['userId']?.toString() ?? '';
                final cId  = d['challengeId']?.toString() ?? '';
                if (uId.isNotEmpty && cId.isNotEmpty) {
                  userToChallenges.putIfAbsent(uId, () => {}).add(cId);
                }
              }
              final returning =
                  userToChallenges.values.where((s) => s.length > 1).length;

              return CustomScrollView(
                slivers: [
                  // ── Header stats ──
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Campaign Overview',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'ClashDisplay')),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              _StatCard('Challenges',
                                  '${challenges.length}',
                                  Icons.flash_on, Colors.amber),
                              const SizedBox(width: 10),
                              _StatCard('Submissions',
                                  '$totalSubs',
                                  Icons.video_collection, Colors.blue),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              _StatCard('Unique Players',
                                  '$uniqueUsers',
                                  Icons.people, Colors.green),
                              const SizedBox(width: 10),
                              _StatCard('Avg Score',
                                  avgScore.toStringAsFixed(1),
                                  Icons.star_rounded, _accent),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              _StatCard('Returning Players',
                                  '$returning',
                                  Icons.repeat_rounded,
                                  const Color(0xFF22C55E)),
                              const SizedBox(width: 10),
                              const Expanded(child: SizedBox()),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 24)),

                  // ── Per-challenge section header ──
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Text('Per Challenge',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'ClashDisplay')),
                    ),
                  ),

                  // ── Per-challenge cards ──
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final ch  = challenges[i];
                        final chData = ch.data() as Map<String, dynamic>;
                        final title  = chData['title'] as String? ?? 'Challenge';
                        final chId   = ch.id;

                        final chSubs = allSubs.where((s) =>
                            (s.data() as Map<String, dynamic>)['challengeId'] ==
                            chId).toList();
                        final chApproved = chSubs.where((s) =>
                            (s.data() as Map<String, dynamic>)['status'] ==
                            'approved').toList();
                        final chUsers = chSubs
                            .map((d) =>
                                (d.data() as Map<String, dynamic>)['userId']
                                    ?.toString() ??
                                '')
                            .where((id) => id.isNotEmpty)
                            .toSet();
                        final chReturning = chUsers
                            .where((uid) =>
                                (userToChallenges[uid]?.length ?? 0) > 1)
                            .length;

                        // Score distribution (0–25, 26–50, 51–75, 76–100)
                        final dist = [0, 0, 0, 0];
                        for (final s in chApproved) {
                          final sc =
                              ((s.data() as Map<String, dynamic>)['aiScore']
                                      as num?)
                                  ?.toInt() ??
                              0;
                          if (sc <= 25) {
                            dist[0]++;
                          } else if (sc <= 50) {
                            dist[1]++;
                          } else if (sc <= 75) {
                            dist[2]++;
                          } else {
                            dist[3]++;
                          }
                        }

                        return _ChallengeCard(
                          title:       title,
                          challengeId: chId,
                          totalSubs:   chSubs.length,
                          approved:    chApproved.length,
                          uniquePlayers: chUsers.length,
                          returning:   chReturning,
                          scoreDist:   dist,
                          onViewEntries: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CreatorEntriesScreen(
                                challengeId:    chId,
                                challengeTitle: title,
                              ),
                            ),
                          ),
                        );
                      },
                      childCount: challenges.length,
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 32)),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

// ── Stat card ─────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String  label;
  final String  value;
  final IconData icon;
  final Color   color;

  const _StatCard(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF100A20),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
                Text(label,
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Per-challenge card ────────────────────────────────────────────────────────

class _ChallengeCard extends StatelessWidget {
  final String  title;
  final String  challengeId;
  final int     totalSubs;
  final int     approved;
  final int     uniquePlayers;
  final int     returning;
  final List<int> scoreDist;
  final VoidCallback onViewEntries;

  const _ChallengeCard({
    required this.title,
    required this.challengeId,
    required this.totalSubs,
    required this.approved,
    required this.uniquePlayers,
    required this.returning,
    required this.scoreDist,
    required this.onViewEntries,
  });

  static const _distColors = [
    Colors.redAccent,
    Color(0xFFF59E0B),
    Color(0xFF22C55E),
    Color(0xFF7B2CBF),
  ];
  static const _distLabels = ['0–25', '26–50', '51–75', '76–100'];

  @override
  Widget build(BuildContext context) {
    final totalDist = scoreDist.fold(0, (a, b) => a + b);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF100A20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),

          const SizedBox(height: 14),

          // Quick stats row
          Row(
            children: [
              _miniStat(Icons.people, '$uniquePlayers', 'Players'),
              const SizedBox(width: 16),
              _miniStat(Icons.check_circle_outline_rounded, '$approved',
                  'Approved'),
              const SizedBox(width: 16),
              _miniStat(Icons.repeat_rounded, '$returning', 'Returning'),
              const SizedBox(width: 16),
              _miniStat(Icons.video_collection_outlined, '$totalSubs',
                  'Total'),
            ],
          ),

          // Score distribution
          if (approved > 0) ...[
            const SizedBox(height: 16),
            const Text('Score Distribution',
                style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4)),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(4, (i) {
                final count = scoreDist[i];
                final ratio = totalDist == 0 ? 0.0 : count / totalDist;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i < 3 ? 4 : 0),
                    child: Column(
                      children: [
                        if (count > 0)
                          Text('$count',
                              style: TextStyle(
                                  color: _distColors[i],
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: ratio),
                          duration: const Duration(milliseconds: 700),
                          curve: Curves.easeOut,
                          builder: (_, v, __) => Container(
                            height: 36 * v + 4,
                            decoration: BoxDecoration(
                              color: _distColors[i].withValues(
                                  alpha: count > 0 ? 0.70 : 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(_distLabels[i],
                            style: const TextStyle(
                                color: AppColors.textFaint, fontSize: 9)),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ],

          const SizedBox(height: 14),

          // View Entries CTA
          GestureDetector(
            onTap: onViewEntries,
            child: Container(
              width: double.infinity,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFF7B2CBF).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFF7B2CBF).withValues(alpha: 0.40)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.play_circle_outline_rounded,
                      color: Color(0xFFD4A8FF), size: 16),
                  const SizedBox(width: 6),
                  Text(
                    approved > 0
                        ? 'View $approved Entr${approved == 1 ? 'y' : 'ies'}'
                        : 'No entries yet',
                    style: const TextStyle(
                        color: Color(0xFFD4A8FF),
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: Colors.white38, size: 14),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700)),
        Text(label,
            style: const TextStyle(color: AppColors.textFaint, fontSize: 10)),
      ],
    );
  }
}
