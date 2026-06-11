import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  static const _bg = Color(0xFF000000);
  static const _accent = Color(0xFF7B2CBF);
  static const _card = Color(0xFF0E0E1A);

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(
          child: Text('Not signed in', style: TextStyle(color: Colors.white54)),
        ),
      );
    }
    final uid = user.uid;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: () => _markAllRead(uid),
            child: const Text('Mark all read',
                style: TextStyle(color: Color(0xFFD4A8FF), fontSize: 13)),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('notifications')
            .where('userId', isEqualTo: uid)
            .orderBy('createdAt', descending: true)
            .limit(50)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: _accent));
          }

          final docs = snap.data?.docs ?? [];

          if (docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_none_rounded,
                      color: Colors.white24, size: 56),
                  SizedBox(height: 14),
                  Text('No notifications yet',
                      style:
                          TextStyle(color: Colors.white38, fontSize: 15)),
                  SizedBox(height: 6),
                  Text('We\'ll notify you about scores, stars and offers.',
                      style:
                          TextStyle(color: Colors.white24, fontSize: 12)),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final doc = docs[i];
              final data = doc.data() as Map<String, dynamic>;
              final isRead = data['isRead'] as bool? ?? false;
              final message = data['message'] as String? ?? '';
              final type = data['type'] as String? ?? 'general';
              final ts = data['createdAt'];
              final time = ts is Timestamp ? _timeAgo(ts.toDate()) : '';

              return GestureDetector(
                onTap: () {
                  if (!isRead) {
                    doc.reference.update({'isRead': true});
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isRead
                        ? _card
                        : _accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isRead
                          ? Colors.white10
                          : _accent.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _iconColor(type).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(_iconFor(type),
                            color: _iconColor(type), size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              message,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: isRead
                                    ? FontWeight.normal
                                    : FontWeight.w600,
                                height: 1.4,
                              ),
                            ),
                            if (time.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(time,
                                  style: const TextStyle(
                                      color: Colors.white38, fontSize: 11)),
                            ],
                          ],
                        ),
                      ),
                      if (!isRead)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(top: 4, left: 8),
                          decoration: const BoxDecoration(
                              color: _accent, shape: BoxShape.circle),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _markAllRead(String uid) async {
    final snap = await FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: uid)
        .where('isRead', isEqualTo: false)
        .get();
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'star':
        return Icons.star_rounded;
      case 'rank':
        return Icons.emoji_events_rounded;
      case 'offer':
        return Icons.local_offer_rounded;
      case 'referral':
        return Icons.group_add_rounded;
      case 'approved':
        return Icons.check_circle_rounded;
      case 'rejected':
        return Icons.cancel_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _iconColor(String type) {
    switch (type) {
      case 'star':
        return const Color(0xFFFFD700);
      case 'rank':
        return const Color(0xFFFF9800);
      case 'offer':
        return Colors.greenAccent;
      case 'referral':
        return Colors.tealAccent;
      case 'approved':
        return Colors.greenAccent;
      case 'rejected':
        return Colors.redAccent;
      default:
        return const Color(0xFF7B2CBF);
    }
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
