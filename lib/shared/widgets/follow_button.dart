import 'package:flutter/material.dart';
import '../../core/services/api_client.dart';
import '../../core/services/creators_service.dart';

class FollowButton extends StatefulWidget {
  final String targetUserId;

  /// Pass this when the caller already knows the follow state (e.g. from a
  /// `CreatorSummary`/`CreatorProfile` fetch that included `isFollowing`) to
  /// skip a redundant network round-trip. There's no standalone "am I
  /// following X" endpoint, so without this the button starts as "Follow"
  /// until toggled.
  final bool? initialIsFollowing;

  const FollowButton({
    super.key,
    required this.targetUserId,
    this.initialIsFollowing,
  });

  @override
  State<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<FollowButton> {
  static const _accent = Color(0xFF7B2CBF);
  final _service = CreatorsService();

  String? _myId;
  bool _following = false;
  bool _loading = true;
  bool _actioning = false;

  @override
  void initState() {
    super.initState();
    _following = widget.initialIsFollowing ?? false;
    ApiClient().userId.then((id) {
      if (mounted) {
        setState(() {
          _myId = id;
          _loading = false;
        });
      }
    });
  }

  Future<void> _toggle() async {
    if (_actioning || _loading || _myId == null) return;
    setState(() => _actioning = true);
    final wasFollowing = _following;
    final ok = wasFollowing
        ? await _service.unfollowCreator(widget.targetUserId)
        : await _service.followCreator(widget.targetUserId);
    if (mounted) {
      setState(() {
        if (ok) _following = !wasFollowing;
        _actioning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_myId == widget.targetUserId) return const SizedBox.shrink();

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
