import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'review_screen.dart';

class ChallengeSubmissionsTab extends StatelessWidget {
  const ChallengeSubmissionsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Center(child: Text("Not signed in."));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('submissions')
          .limit(500)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text("Error: ${snapshot.error}"));
        }

        // Filter out deleted docs in Dart — older docs may not have the field
        final docs = (snapshot.data?.docs ?? []).where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return data['isDeleted'] != true;
        }).toList();

        if (docs.isEmpty) {
          return const Center(child: Text("No submissions yet."));
        }

        // Sort by createdAt descending in Dart (avoids composite index)
        docs.sort((a, b) {
          final aTs = (a.data() as Map)['createdAt'] as Timestamp?;
          final bTs = (b.data() as Map)['createdAt'] as Timestamp?;
          if (aTs == null && bTs == null) return 0;
          if (aTs == null) return 1;
          if (bTs == null) return -1;
          return bTs.compareTo(aTs);
        });

        // Group by challengeTitle
        final Map<String, List<QueryDocumentSnapshot>> grouped = {};
        for (final doc in docs) {
          final title = (doc['challengeTitle'] as String?) ?? 'Unknown Challenge';
          grouped.putIfAbsent(title, () => []).add(doc);
        }

        final challenges = grouped.keys.toList();

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: challenges.length,
          itemBuilder: (context, i) {
            final challengeTitle = challenges[i];
            final submissions = grouped[challengeTitle]!;
            final pendingCount = submissions.where((s) => s['status'] == 'pending').length;

            return _ChallengeSection(
              challengeTitle: challengeTitle,
              submissions: submissions,
              pendingCount: pendingCount,
            );
          },
        );
      },
    );
  }
}

class _ChallengeSection extends StatefulWidget {
  final String challengeTitle;
  final List<QueryDocumentSnapshot> submissions;
  final int pendingCount;

  const _ChallengeSection({
    required this.challengeTitle,
    required this.submissions,
    required this.pendingCount,
  });

  @override
  State<_ChallengeSection> createState() => _ChallengeSectionState();
}

class _ChallengeSectionState extends State<_ChallengeSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          InkWell(
            borderRadius: _expanded
                ? const BorderRadius.vertical(top: Radius.circular(12))
                : BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.challengeTitle,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              "${widget.submissions.length} submission${widget.submissions.length == 1 ? '' : 's'}",
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                            if (widget.pendingCount > 0) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: Colors.orange.withValues(alpha: 0.5)),
                                ),
                                child: Text(
                                  "${widget.pendingCount} pending",
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.orange,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            ...widget.submissions.map((s) => _SubmissionCard(submission: s)),
          ],
        ],
      ),
    );
  }
}

class _SubmissionCard extends StatelessWidget {
  final QueryDocumentSnapshot submission;

  const _SubmissionCard({required this.submission});

  @override
  Widget build(BuildContext context) {
    final data = submission.data() as Map<String, dynamic>;
    final username = data['username'] as String? ?? data['userId'] as String? ?? 'Unknown';
    final status = data['status'] as String? ?? 'pending';
    final auraPoints = (data['netAurasAwarded'] as num?)?.toInt()
        ?? (data['auraPoints'] as num?)?.toInt()
        ?? 0;
    final aiReason = data['aiReason'] as String? ?? '';
    final createdAt = data['createdAt'] as Timestamp?;

    return Column(
      children: [
        const Divider(height: 1, indent: 16, endIndent: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFF7B2CBF).withValues(alpha: 0.2),
                child: Text(
                  username.isNotEmpty ? username[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: Color(0xFF7B2CBF),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            username,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        _StatusChip(status: status),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Aura points row
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            color: Color(0xFFFFD700), size: 16),
                        const SizedBox(width: 4),
                        Text(
                          status == 'approved'
                              ? "$auraPoints Aura Points"
                              : status == 'pending'
                                  ? "Pending review"
                                  : "0 Aura Points",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: status == 'approved'
                                ? const Color(0xFFFFD700)
                                : Colors.grey[600],
                          ),
                        ),
                        if (createdAt != null) ...[
                          const Spacer(),
                          Text(
                            _formatDate(createdAt.toDate()),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[400],
                            ),
                          ),
                        ],
                      ],
                    ),
                    // AI comment/reason
                    if (aiReason.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: Colors.grey.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.smart_toy_outlined,
                                size: 14, color: Colors.grey[500]),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                aiReason,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[700],
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    // Watch / Review button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.play_circle_outline, size: 16),
                          label: Text(
                            status == 'pending' ? "Review" : "Watch",
                            style: const TextStyle(fontSize: 12),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    ReviewScreen(submission: submission),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) {
      if (diff.inHours == 0) return "${diff.inMinutes}m ago";
      return "${diff.inHours}h ago";
    }
    if (diff.inDays < 7) return "${diff.inDays}d ago";
    return "${dt.day}/${dt.month}/${dt.year}";
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (status) {
      case 'approved':
        color = Colors.green;
        label = 'Approved';
      case 'rejected':
        color = Colors.red;
        label = 'Rejected';
      case 'ai_error':
        color = Colors.orange;
        label = 'AI Error';
      default:
        color = Colors.blue;
        label = 'Pending';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
