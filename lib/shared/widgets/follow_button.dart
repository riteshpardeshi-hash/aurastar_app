import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FollowButton extends StatefulWidget {
  final String targetUserId;
  const FollowButton({super.key, required this.targetUserId});

  @override
  State<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<FollowButton> {
  static const _accent = Color(0xFF7B2CBF);

  final String _currentUid =
      FirebaseAuth.instance.currentUser?.uid ?? '';

  bool _following = false;
  bool _loading = true;
  bool _actioning = false;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    if (_currentUid.isEmpty || _currentUid == widget.targetUserId) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final snap = await FirebaseFirestore.instance
        .collection('follows')
        .where('followerUserId', isEqualTo: _currentUid)
        .where('followedUserId', isEqualTo: widget.targetUserId)
        .limit(1)
        .get();
    if (mounted) {
      setState(() {
        _following = snap.docs.isNotEmpty;
        _loading = false;
      });
    }
  }

  Future<void> _toggle() async {
    if (_actioning || _loading) return;
    setState(() => _actioning = true);

    try {
      if (_following) {
        final snap = await FirebaseFirestore.instance
            .collection('follows')
            .where('followerUserId', isEqualTo: _currentUid)
            .where('followedUserId', isEqualTo: widget.targetUserId)
            .limit(1)
            .get();
        for (final doc in snap.docs) {
          await doc.reference.delete();
        }
        await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.targetUserId)
            .update({'followerCount': FieldValue.increment(-1)});
        await FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUid)
            .update({'followingCount': FieldValue.increment(-1)});

        if (mounted) setState(() => _following = false);
      } else {
        await FirebaseFirestore.instance.collection('follows').add({
          'followerUserId': _currentUid,
          'followedUserId': widget.targetUserId,
          'createdAt': Timestamp.now(),
        });
        await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.targetUserId)
            .update({'followerCount': FieldValue.increment(1)});
        await FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUid)
            .update({'followingCount': FieldValue.increment(1)});

        // Notify the target user
        final myDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUid)
            .get();
        final myUsername =
            (myDoc.data() ?? {})['username'] as String? ?? 'Someone';
        await FirebaseFirestore.instance.collection('notifications').add({
          'userId': widget.targetUserId,
          'type': 'new_follower',
          'message': '@$myUsername started following you',
          'sourceUserId': _currentUid,
          'isRead': false,
          'createdAt': Timestamp.now(),
        });

        if (mounted) setState(() => _following = true);
      }
    } finally {
      if (mounted) setState(() => _actioning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUid == widget.targetUserId) return const SizedBox.shrink();

    if (_loading) {
      return const SizedBox(
        width: 90,
        height: 36,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: _toggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
            const EdgeInsets.symmetric(horizontal: 28, vertical: 9),
        decoration: BoxDecoration(
          color: _following ? Colors.transparent : _accent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _following
                ? Colors.white38
                : _accent,
          ),
        ),
        child: _actioning
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Text(
                _following ? 'Following' : 'Follow',
                style: TextStyle(
                  color: _following ? Colors.white54 : Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
      ),
    );
  }
}
