import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ArchivedVideosScreen extends StatelessWidget {
  const ArchivedVideosScreen({super.key});

  static const _bg = Color(0xFF080810);
  static const _accent = Color(0xFF7B2CBF);

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to view archived videos.')),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        title: const Text('Archived Videos'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('submissions')
            .where('userId', isEqualTo: uid)
            .where('isArchived', isEqualTo: true)
            .where('isDeleted', isEqualTo: false)
            .snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: _accent));
          }
          final docs = snap.data!.docs;

          if (docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.archive_outlined,
                      color: Colors.white24, size: 52),
                  SizedBox(height: 14),
                  Text('No archived videos',
                      style:
                          TextStyle(color: Colors.white38, fontSize: 15)),
                  SizedBox(height: 6),
                  Text('Videos you archive will appear here',
                      style:
                          TextStyle(color: Colors.white24, fontSize: 12)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final doc = docs[i];
              final data = doc.data() as Map<String, dynamic>;
              final title =
                  data['challengeTitle'] as String? ?? 'Challenge';
              final auraPoints =
                  (data['auraPoints'] as num?)?.toInt() ?? 0;
              final aiScore = (data['aiScore'] as num?)?.toInt();
              final status = data['status'] as String? ?? 'pending';
              final archiveDeleteAt =
                  data['archiveDeleteAt'] as Timestamp?;
              final countdownText =
                  _countdownText(archiveDeleteAt);

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0E0E20),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: _accent.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.archive_outlined,
                          color: _accent, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              if (aiScore != null &&
                                  status == 'approved') ...[
                                const Icon(Icons.star_rounded,
                                    size: 13, color: _accent),
                                const SizedBox(width: 3),
                                Text('$aiScore score',
                                    style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 12)),
                                const SizedBox(width: 10),
                                Text('+$auraPoints Auras',
                                    style: const TextStyle(
                                        color: Colors.white38,
                                        fontSize: 12)),
                              ] else
                                Text(
                                  status == 'pending'
                                      ? 'AI Reviewing…'
                                      : 'Not approved',
                                  style: const TextStyle(
                                      color: Colors.white38,
                                      fontSize: 12),
                                ),
                            ],
                          ),
                          if (countdownText != null) ...[
                            const SizedBox(height: 5),
                            Row(
                              children: [
                                const Icon(Icons.timer_outlined,
                                    size: 11,
                                    color: Colors.orangeAccent),
                                const SizedBox(width: 4),
                                Text(
                                  countdownText,
                                  style: const TextStyle(
                                    color: Colors.orangeAccent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () =>
                          _confirmShare(context, doc.id),
                      style: TextButton.styleFrom(
                        backgroundColor:
                            _accent.withValues(alpha: 0.15),
                        foregroundColor: const Color(0xFFD4A8FF),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                      ),
                      child: const Text('Share',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  String? _countdownText(Timestamp? archiveDeleteAt) {
    if (archiveDeleteAt == null) return null;
    final diff =
        archiveDeleteAt.toDate().difference(DateTime.now());
    if (diff.isNegative) return 'Deletes soon';
    final days = diff.inDays;
    if (days == 0) return 'Deletes today';
    if (days == 1) return 'Deletes tomorrow';
    return 'Deletes in $days days';
  }

  Future<void> _confirmShare(
      BuildContext context, String submissionId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF12102A),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18)),
        title: const Text('Share Publicly?',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
          'This will make your video visible in the community feed and eligible for leaderboards.',
          style: TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Share',
                style: TextStyle(
                    color: Color(0xFF7B2CBF),
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await FirebaseFirestore.instance
        .collection('submissions')
        .doc(submissionId)
        .update({'isPublic': true, 'isArchived': false});
  }
}
