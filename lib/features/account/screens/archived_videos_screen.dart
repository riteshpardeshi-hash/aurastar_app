import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/services/api_client.dart';

class ArchivedVideosScreen extends StatelessWidget {
  const ArchivedVideosScreen({super.key});

  static const _bg = Color(0xFF080810);
  static const _accent = Color(0xFF7B2CBF);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        title: const Text('Archived Videos'),
      ),
      body: FutureBuilder<String?>(
        future: ApiClient().userId,
        builder: (context, uidSnap) {
          if (!uidSnap.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: _accent));
          }
          final uid = uidSnap.data;
          if (uid == null || uid.isEmpty) {
            return const Center(
                child: Text('Please sign in to view archived videos.',
                    style: TextStyle(color: Colors.white54)));
          }
          return StreamBuilder<QuerySnapshot>(
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
                          style: TextStyle(
                              color: Colors.white38, fontSize: 15)),
                      SizedBox(height: 6),
                      Text('Videos you archive will appear here',
                          style: TextStyle(
                              color: Colors.white24, fontSize: 12)),
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
                  final countdownText = _countdownText(archiveDeleteAt);

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
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  String? _countdownText(Timestamp? archiveDeleteAt) {
    if (archiveDeleteAt == null) return null;
    final diff = archiveDeleteAt.toDate().difference(DateTime.now());
    if (diff.isNegative) return 'Deletes soon';
    final days = diff.inDays;
    if (days == 0) return 'Deletes today';
    if (days == 1) return 'Deletes tomorrow';
    return 'Deletes in $days days';
  }
}
