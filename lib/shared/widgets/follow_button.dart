import 'package:flutter/material.dart';
import '../../core/services/api_client.dart';
import '../../core/services/creators_service.dart';
import '../../core/utils/error_message.dart';
import '../theme/app_colors.dart';

class FollowButton extends StatefulWidget {
  final String targetUserId;

  /// Pass this when the caller already knows the follow state (e.g. from a
  /// `CreatorSummary`/`CreatorProfile` fetch that included `isFollowing`) to
  /// skip a redundant network round-trip. There's no standalone "am I
  /// following X" endpoint, so without this the button starts as "Follow"
  /// until toggled.
  final bool? initialIsFollowing;

  /// Light/translucent pill (white bg, purple text) for placement on a
  /// solid-color card, e.g. the creator profile header. Default is the
  /// filled-purple pill used on video overlays.
  final bool light;

  /// Override the follow/unfollow calls — defaults to `CreatorsService`.
  /// Pass these to reuse this widget against a different `/{tag}/{id}/follow`
  /// pair (e.g. `BrandsService`) without duplicating the button.
  final Future<bool> Function(String id)? followFn;
  final Future<bool> Function(String id)? unfollowFn;

  const FollowButton({
    super.key,
    required this.targetUserId,
    this.initialIsFollowing,
    this.light = false,
    this.followFn,
    this.unfollowFn,
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
    final follow = widget.followFn ?? _service.followCreator;
    final unfollow = widget.unfollowFn ?? _service.unfollowCreator;
    try {
      await (wasFollowing
          ? unfollow(widget.targetUserId)
          : follow(widget.targetUserId));
      if (mounted) setState(() => _following = !wasFollowing);
    } catch (e) {
      // Previously this failure was swallowed entirely (the button just
      // silently stayed on "Follow"), so a failed follow was indistinguishable
      // from a successful one from the UI — surface the real reason instead.
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(humanizeError(e))));
      }
    } finally {
      if (mounted) setState(() => _actioning = false);
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

    final fillColor = widget.light ? Colors.white : _accent;
    final fillTextColor = widget.light ? _accent : Colors.white;

    return GestureDetector(
      onTap: _toggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: _following ? Colors.transparent : fillColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _following
                ? Colors.white38
                : fillColor,
          ),
        ),
        child: Center(
          widthFactor: 1,
          child: _actioning
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: fillTextColor),
                )
              : _following
                  ? const Text(
                      'Following',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    )
                  : widget.light
                      ? Image.asset(
                          'assets/images/creator public profile/Asset 16.png',
                          height: 16,
                          fit: BoxFit.contain,
                        )
                      : Text(
                          'Follow',
                          style: TextStyle(
                            color: fillTextColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
        ),
      ),
    );
  }
}
